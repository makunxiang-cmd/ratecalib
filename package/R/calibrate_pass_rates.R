#' Calibrate weights to multiple pass-rate targets
#'
#' Adjust initial positive weights so that an overall binary outcome rate and
#' subgroup outcome rates approach or exactly match specified targets. The
#' optimization is performed on demographic-cell-by-outcome aggregates.
#'
#' @param data A data frame containing one row per sampled unit.
#' @param outcome Name of a binary 0/1 outcome column.
#' @param weight Name of the initial positive weight column.
#' @param group_vars Character vector naming grouping variables.
#' @param targets A data frame with columns `variable`, `level`, and
#'   `target_rate`; optional column `priority` controls soft-mode importance.
#' @param lower,upper Scalar lower and upper bounds on the multiplier applied
#'   to each initial cell weight.
#' @param mode Either `"soft"` or `"exact"`.
#' @param distance Distance function of the calibration family. `"chi2"` (the
#'   default) is the linear/quadratic distance solved as a bounded QP via OSQP
#'   and reproduces earlier behaviour. `"raking"` is the entropy distance
#'   `g log g - g + 1`, whose solution `g = exp(eta)` is strictly positive by
#'   construction; it is solved by a dual Newton iteration and currently
#'   supports `mode = "exact"` only. Raking is unbounded above, so `lower` and
#'   `upper` are not enforced for it but multipliers outside that range are
#'   reported in the diagnostics. `"logit"` is the bounded logit distance whose
#'   multipliers stay strictly inside `(lower, upper)` by construction (requires
#'   `lower < 1 < upper`); it is also dual-Newton solved and `mode = "exact"`
#'   only. Use `"logit"` when capping extreme weights is a hard requirement.
#' @param lambda Positive soft-constraint penalty. Larger values emphasize
#'   target matching more strongly.
#' @param new_weight Name of the calibrated weight column added to `data`.
#' @param verbose Logical; passed to OSQP.
#'
#' @return An object of class `pass_rate_calibration`.
#' @export
calibrate_pass_rates <- function(
    data,
    outcome,
    weight,
    group_vars,
    targets,
    lower = 0.25,
    upper = 4,
    mode = c("soft", "exact"),
    distance = c("chi2", "raking", "logit"),
    lambda = 1e4,
    new_weight = "weight_calibrated",
    verbose = FALSE
) {
  mode <- match.arg(mode)
  distance <- match.arg(distance)
  if (distance != "chi2" && mode != "exact") {
    stop("distance='", distance, "' currently supports mode='exact' only.",
         call. = FALSE)
  }

  if (!requireNamespace("osqp", quietly = TRUE)) {
    stop("Package 'osqp' is required. Run install.packages('osqp').", call. = FALSE)
  }
  if (!requireNamespace("Matrix", quietly = TRUE)) {
    stop("Package 'Matrix' is required. Run install.packages('Matrix').", call. = FALSE)
  }

  if (!is.data.frame(data)) stop("data must be a data frame.", call. = FALSE)
  if (!is.character(outcome) || length(outcome) != 1L) {
    stop("outcome must be one column name.", call. = FALSE)
  }
  if (!is.character(weight) || length(weight) != 1L) {
    stop("weight must be one column name.", call. = FALSE)
  }
  if (!is.character(group_vars) || length(group_vars) < 1L) {
    stop("group_vars must contain at least one column name.", call. = FALSE)
  }
  if (anyDuplicated(group_vars)) {
    stop("group_vars must not contain duplicates.", call. = FALSE)
  }

  required_cols <- unique(c(outcome, weight, group_vars))
  missing_cols <- setdiff(required_cols, names(data))
  if (length(missing_cols) > 0L) {
    stop("Missing columns in data: ", paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  target_cols <- c("variable", "level", "target_rate")
  missing_target_cols <- setdiff(target_cols, names(targets))
  if (length(missing_target_cols) > 0L) {
    stop("targets is missing columns: ",
         paste(missing_target_cols, collapse = ", "), call. = FALSE)
  }

  if (!is.numeric(lower) || length(lower) != 1L ||
      !is.numeric(upper) || length(upper) != 1L ||
      !is.finite(lower) || !is.finite(upper) ||
      lower < 0 || upper <= lower || lower > 1 || upper < 1) {
    stop("Use scalar bounds satisfying 0 <= lower <= 1 <= upper and lower < upper.",
         call. = FALSE)
  }
  if (!is.numeric(lambda) || length(lambda) != 1L ||
      !is.finite(lambda) || lambda <= 0) {
    stop("lambda must be one finite positive number.", call. = FALSE)
  }

  d <- as.numeric(data[[weight]])
  y_raw <- data[[outcome]]
  if (is.logical(y_raw)) y_raw <- as.integer(y_raw)
  y <- suppressWarnings(as.numeric(as.character(y_raw)))

  if (any(!is.finite(d)) || any(d <= 0)) {
    stop("Initial weights must all be finite and strictly positive.", call. = FALSE)
  }
  if (anyNA(y) || any(!y %in% c(0, 1))) {
    stop("The outcome column must contain only 0 and 1.", call. = FALSE)
  }
  if (anyNA(data[group_vars])) {
    stop("Grouping variables contain missing values. Recode missing values as a category first.",
         call. = FALSE)
  }

  targets <- as.data.frame(targets, stringsAsFactors = FALSE)
  targets$variable <- as.character(targets$variable)
  targets$level <- as.character(targets$level)
  targets$target_rate <- as.numeric(targets$target_rate)

  if (nrow(targets) < 1L) stop("targets must contain at least one row.", call. = FALSE)
  if (any(!is.finite(targets$target_rate)) ||
      any(targets$target_rate < 0 | targets$target_rate > 1)) {
    stop("All target_rate values must be between 0 and 1.", call. = FALSE)
  }

  if (!"priority" %in% names(targets)) targets$priority <- 1
  targets$priority <- as.numeric(targets$priority)
  if (any(!is.finite(targets$priority)) || any(targets$priority <= 0)) {
    stop("priority must contain finite positive numbers.", call. = FALSE)
  }

  target_key <- paste(targets$variable, targets$level, sep = "\u001F")
  if (anyDuplicated(target_key)) {
    stop("targets contains duplicate variable-level rows.", call. = FALSE)
  }

  # Aggregate to demographic cell x outcome.
  key_data <- data[group_vars]
  key_data[] <- lapply(key_data, as.character)
  key_parts <- c(key_data, list(.outcome = as.character(y)))
  aggregate_key <- do.call(paste, c(key_parts, list(sep = "\u001F")))

  D_matrix <- rowsum(d, group = aggregate_key, reorder = FALSE)
  D <- as.numeric(D_matrix[, 1L])
  aggregate_names <- rownames(D_matrix)
  first_index <- match(aggregate_names, aggregate_key)

  cells <- data[first_index, group_vars, drop = FALSE]
  cells[] <- lapply(cells, as.character)
  cells$.outcome <- y[first_index]
  cells$.initial_total <- D
  cells$.cell_id <- seq_len(nrow(cells))

  m <- nrow(cells)
  grand_total <- sum(D)

  # Preserve the current population margins as hard constraints.
  margin_rows <- list(overall = rep(1, m))
  margin_rhs_named <- c(overall = grand_total)

  for (v in group_vars) {
    observed_levels <- unique(cells[[v]])
    if (length(observed_levels) > 1L) {
      included_levels <- observed_levels[-length(observed_levels)]
      for (lev in included_levels) {
        row_name <- paste(v, lev, sep = "=")
        z <- as.numeric(cells[[v]] == lev)
        margin_rows[[row_name]] <- z
        margin_rhs_named[row_name] <- sum(D * z)
      }
    }
  }

  M <- Matrix::Matrix(do.call(rbind, margin_rows), sparse = TRUE)
  margin_rhs <- as.numeric(margin_rhs_named)

  # Construct linearized pass-rate target rows.
  rate_rows <- vector("list", nrow(targets))
  target_sizes <- numeric(nrow(targets))
  initial_rates <- numeric(nrow(targets))
  target_names <- character(nrow(targets))

  for (j in seq_len(nrow(targets))) {
    v <- targets$variable[j]
    lev <- targets$level[j]
    r <- targets$target_rate[j]

    is_overall <- v %in% c(".overall", "overall", "TOTAL")

    if (is_overall) {
      mask <- rep(TRUE, m)
      v <- ".overall"
      lev <- ".all"
      targets$variable[j] <- v
      targets$level[j] <- lev
    } else {
      if (!v %in% group_vars) {
        stop("Target variable '", v,
             "' is not in group_vars. Use '.overall' for the total target.",
             call. = FALSE)
      }
      mask <- cells[[v]] == lev
    }

    if (!any(mask)) {
      stop("No observed sample cell for target: ", v, " = ", lev, call. = FALSE)
    }

    target_sizes[j] <- sum(D[mask])
    initial_rates[j] <- sum(D[mask] * cells$.outcome[mask]) / target_sizes[j]

    # sum x_i * I(group) * (y_i - target_rate) = 0
    rate_rows[[j]] <- as.numeric(mask) * (cells$.outcome - r)
    target_names[j] <- paste(v, lev, sep = "=")
  }

  R <- Matrix::Matrix(do.call(rbind, rate_rows), sparse = TRUE)
  rownames(R) <- make.unique(target_names)

  if (distance == "chi2") {
    # Minimize sum_c (x_c - D_c)^2 / D_c.
    # OSQP form: 0.5*x'P*x + q'x.
    P <- Matrix::Diagonal(m, x = 2 / D)
    q <- rep(-2, m)

    if (mode == "soft") {
      penalty <- lambda * grand_total * targets$priority / (target_sizes^2)
      W <- Matrix::Diagonal(nrow(R), x = penalty)
      P <- P + 2 * crossprod(R, W %*% R)
    }

    I_m <- Matrix::Diagonal(m)

    if (mode == "exact") {
      A <- rbind(M, R, I_m)
      l <- c(margin_rhs, rep(0, nrow(R)), lower * D)
      u <- c(margin_rhs, rep(0, nrow(R)), upper * D)
    } else {
      A <- rbind(M, I_m)
      l <- c(margin_rhs, lower * D)
      u <- c(margin_rhs, upper * D)
    }

    P <- methods::as(
      methods::as(Matrix::forceSymmetric(P, uplo = "U"), "generalMatrix"),
      "CsparseMatrix"
    )
    A <- methods::as(methods::as(A, "generalMatrix"), "CsparseMatrix")

    settings <- osqp::osqpSettings(
      verbose = verbose,
      max_iter = 100000L,
      eps_abs = 1e-8,
      eps_rel = 1e-8,
      polishing = TRUE,
      scaled_termination = TRUE
    )

    solution <- osqp::solve_osqp(P = P, q = q, A = A, l = l, u = u,
                                 pars = settings)
    status <- as.character(solution$info$status)

    if (!grepl("solved", status, ignore.case = TRUE)) {
      stop(
        "Optimization did not solve successfully. OSQP status: ", status,
        if (mode == "exact") {
          paste0(". The targets may be mutually inconsistent or the bounds ",
                 "may be too narrow. Try mode='soft', or widen lower/upper.")
        } else {
          ". Try widening lower/upper or reducing numerical strictness."
        },
        call. = FALSE
      )
    }

    x <- as.numeric(solution$x)
  } else {
    # Deville-Sarndal distance family, exact calibration via dual Newton.
    # Constraints A_eq x = t_eq: population margins plus linearized rate rows.
    if (distance == "raking") {
      # Entropy distance: g(eta) = exp(eta), strictly positive, unbounded above.
      gfun <- function(eta) exp(eta)
      gpfun <- function(eta) exp(eta)
    } else {
      # Logit distance: g maps eta into the open interval (lower, upper).
      if (lower >= 1 || upper <= 1) {
        stop("distance='logit' requires lower < 1 < upper.", call. = FALSE)
      }
      Lb <- lower; Ub <- upper
      Acoef <- (Ub - Lb) / ((1 - Lb) * (Ub - 1))
      gfun <- function(eta) {
        z <- exp(Acoef * eta)
        (Lb * (Ub - 1) + Ub * (1 - Lb) * z) / ((Ub - 1) + (1 - Lb) * z)
      }
      gpfun <- function(eta) {
        z <- exp(Acoef * eta)
        den <- (Ub - 1) + (1 - Lb) * z
        (Ub - Lb)^2 * z / den^2
      }
    }
    A_eq <- rbind(M, R)
    t_eq <- c(margin_rhs, rep(0, nrow(R)))
    solution <- .calibrate_dual(D, A_eq, t_eq, gfun, gpfun, verbose = verbose)
    status <- if (isTRUE(solution$converged)) "solved" else "not converged"
    if (!isTRUE(solution$converged)) {
      stop(
        "The ", distance, " dual iteration did not converge (max residual ",
        signif(solution$max_resid, 3), " after ", solution$iterations,
        " iterations). The exact targets may be infeasible or unreachable",
        if (distance == "logit")
          " within (lower, upper); try widening the bounds, or note an "
        else
          ", for example an ",
        "all-pass or all-fail group. Otherwise try mode='soft' with distance='chi2'.",
        call. = FALSE
      )
    }
    x <- solution$x
  }

  g <- x / D

  cells$.adjusted_total <- x
  cells$.multiplier <- g
  cells$.at_lower_bound <- g <= lower + 1e-6
  cells$.at_upper_bound <- g >= upper - 1e-6

  multiplier_map <- stats::setNames(g, aggregate_names)
  output_data <- data
  output_data[[new_weight]] <- d * unname(multiplier_map[aggregate_key])

  achieved_rates <- numeric(nrow(targets))
  for (j in seq_len(nrow(targets))) {
    v <- targets$variable[j]
    lev <- targets$level[j]
    mask <- if (v == ".overall") rep(TRUE, m) else cells[[v]] == lev
    achieved_rates[j] <- sum(x[mask] * cells$.outcome[mask]) / sum(x[mask])
  }

  target_check <- data.frame(
    variable = targets$variable,
    level = targets$level,
    target_rate = targets$target_rate,
    initial_rate = initial_rates,
    achieved_rate = achieved_rates,
    error = achieved_rates - targets$target_rate,
    abs_error = abs(achieved_rates - targets$target_rate),
    priority = targets$priority,
    stringsAsFactors = FALSE
  )

  margin_check <- data.frame(
    variable = ".overall",
    level = ".all",
    initial_total = grand_total,
    adjusted_total = sum(x),
    relative_change = sum(x) / grand_total - 1,
    stringsAsFactors = FALSE
  )

  for (v in group_vars) {
    for (lev in unique(cells[[v]])) {
      mask <- cells[[v]] == lev
      level_initial_total <- sum(D[mask])
      level_adjusted_total <- sum(x[mask])
      margin_check <- rbind(
        margin_check,
        data.frame(
          variable = v,
          level = lev,
          initial_total = level_initial_total,
          adjusted_total = level_adjusted_total,
          relative_change = level_adjusted_total / level_initial_total - 1,
          stringsAsFactors = FALSE
        )
      )
    }
  }

  old_w <- d
  new_w <- output_data[[new_weight]]
  ess <- function(w) sum(w)^2 / sum(w^2)
  deff <- function(w) {
    if (length(w) < 2L || mean(w) == 0) return(NA_real_)
    1 + (stats::sd(w) / mean(w))^2
  }

  diagnostics <- data.frame(
    metric = c(
      "sample_size",
      "observed_optimization_cells",
      "initial_ESS",
      "calibrated_ESS",
      "initial_weight_DEFF",
      "calibrated_weight_DEFF",
      "minimum_multiplier",
      "median_multiplier",
      "maximum_multiplier",
      "cells_at_lower_bound",
      "cells_at_upper_bound",
      "maximum_absolute_target_error"
    ),
    value = c(
      nrow(data),
      m,
      ess(old_w),
      ess(new_w),
      deff(old_w),
      deff(new_w),
      min(g),
      stats::median(g),
      max(g),
      sum(cells$.at_lower_bound),
      sum(cells$.at_upper_bound),
      max(target_check$abs_error)
    ),
    stringsAsFactors = FALSE
  )

  structure(
    list(
      data = output_data,
      cell_weights = cells,
      target_check = target_check,
      margin_check = margin_check,
      diagnostics = diagnostics,
      solver_status = status,
      solver = solution,
      settings = list(
        outcome = outcome,
        weight = weight,
        group_vars = group_vars,
        lower = lower,
        upper = upper,
        mode = mode,
        distance = distance,
        lambda = lambda,
        new_weight = new_weight
      ),
      call = match.call()
    ),
    class = "pass_rate_calibration"
  )
}

# Dual Newton solver for exact calibration in the Deville-Sarndal distance
# family. Solves A x = t with x_c = D_c * g(eta_c), eta = A^T lambda, for the
# dual variable lambda, where g is the distance's weight-ratio function and
# gprime its derivative. Newton step uses J = A diag(D*g'(eta)) A^T with a
# backtracking line search on the infinity-norm residual for robustness.
# Returns a list with the primal solution x and convergence information.
.calibrate_dual <- function(D, A, t, gfun, gpfun, max_iter = 200L,
                            tol = 1e-10, verbose = FALSE) {
  A <- methods::as(A, "CsparseMatrix")
  k <- nrow(A)
  m <- ncol(A)
  lambda <- rep(0, k)
  eta <- as.numeric(Matrix::crossprod(A, lambda))  # A^T lambda, length m

  resid_of <- function(eta) {
    x <- D * gfun(eta)
    list(x = x, F = as.numeric(A %*% x) - t)
  }

  cur <- resid_of(eta)
  resid <- max(abs(cur$F))

  for (it in seq_len(max_iter)) {
    if (is.finite(resid) && resid < tol) {
      return(list(x = cur$x, iterations = it - 1L, converged = TRUE,
                  max_resid = resid))
    }
    Dg <- D * gpfun(eta)
    J <- as.matrix(A %*% Matrix::Diagonal(m, x = Dg) %*% Matrix::t(A))
    step <- tryCatch(solve(J, cur$F),
                     error = function(e) solve(J + diag(1e-10, k), cur$F))

    # Backtracking line search: accept the step only if it reduces the residual.
    alpha <- 1
    accepted <- FALSE
    repeat {
      eta_try <- as.numeric(Matrix::crossprod(A, lambda - alpha * step))
      try_res <- resid_of(eta_try)
      new_resid <- max(abs(try_res$F))
      if (isTRUE(new_resid < resid)) {
        accepted <- TRUE
        break
      }
      alpha <- alpha / 2
      if (alpha < 1e-8) break
    }
    if (!accepted) break  # cannot make progress: likely infeasible

    lambda <- lambda - alpha * step
    eta <- eta_try
    cur <- try_res
    resid <- new_resid
    if (isTRUE(verbose)) {
      message(sprintf("raking iter %d: max residual %.3e", it, resid))
    }
  }

  list(x = cur$x, iterations = max_iter,
       converged = is.finite(resid) && resid < tol, max_resid = resid)
}
