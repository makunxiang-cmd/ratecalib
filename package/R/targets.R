#' Build a pass-rate target table
#'
#' @param overall Optional scalar overall target rate.
#' @param groups Named list. Each element is a named numeric vector containing
#'   target rates for one grouping variable.
#' @param interactions Named list of cross-classification (interaction) targets.
#'   Each element name is a colon-joined set of grouping variables
#'   (e.g. `"sex:residence"`) and each element is a named numeric vector whose
#'   names are the matching colon-joined level combinations
#'   (e.g. `c("M:Urban" = 0.7)`).
#' @param overall_priority Positive priority for the overall target.
#' @param group_priority Either one positive scalar or a named positive vector
#'   indexed by group-variable name.
#' @param interaction_priority Either one positive scalar or a named positive
#'   vector indexed by interaction key.
#'
#' @return A data frame suitable for `calibrate_pass_rates()`.
#' @export
make_rate_targets <- function(
    overall = NULL,
    groups = list(),
    interactions = list(),
    overall_priority = 5,
    group_priority = 1,
    interaction_priority = 1
) {
  if (!is.list(groups) ||
      (length(groups) > 0L && (is.null(names(groups)) || any(names(groups) == "")))) {
    stop("groups must be a named list.", call. = FALSE)
  }

  out <- data.frame(
    variable = character(),
    level = character(),
    target_rate = numeric(),
    priority = numeric(),
    stringsAsFactors = FALSE
  )

  if (!is.null(overall)) {
    if (!is.numeric(overall) || length(overall) != 1L ||
        !is.finite(overall) || overall < 0 || overall > 1) {
      stop("overall must be NULL or one number between 0 and 1.", call. = FALSE)
    }
    if (!is.numeric(overall_priority) || length(overall_priority) != 1L ||
        !is.finite(overall_priority) || overall_priority <= 0) {
      stop("overall_priority must be one finite positive number.", call. = FALSE)
    }
    out <- rbind(out, data.frame(
      variable = ".overall",
      level = ".all",
      target_rate = overall,
      priority = overall_priority,
      stringsAsFactors = FALSE
    ))
  }

  if (length(groups) > 0L) {
    if (length(group_priority) == 1L) {
      group_priority <- stats::setNames(rep(group_priority, length(groups)), names(groups))
    }
    if (is.null(names(group_priority))) {
      stop("group_priority must be a scalar or a named vector.", call. = FALSE)
    }
  }

  for (v in names(groups)) {
    rates <- groups[[v]]
    if (!is.numeric(rates) || is.null(names(rates)) || any(names(rates) == "")) {
      stop("Each groups element must be a named numeric vector: ", v,
           call. = FALSE)
    }
    if (any(!is.finite(rates)) || any(rates < 0 | rates > 1)) {
      stop("All rates in groups[['", v, "']] must be between 0 and 1.",
           call. = FALSE)
    }
    priority <- unname(group_priority[v])
    if (length(priority) != 1L || is.na(priority) || priority <= 0) {
      stop("Missing or invalid group_priority for variable: ", v, call. = FALSE)
    }
    out <- rbind(out, data.frame(
      variable = v,
      level = names(rates),
      target_rate = unname(rates),
      priority = priority,
      stringsAsFactors = FALSE
    ))
  }

  if (!is.list(interactions) ||
      (length(interactions) > 0L &&
       (is.null(names(interactions)) || any(names(interactions) == "")))) {
    stop("interactions must be a named list.", call. = FALSE)
  }
  if (length(interactions) > 0L) {
    if (length(interaction_priority) == 1L) {
      interaction_priority <- stats::setNames(
        rep(interaction_priority, length(interactions)), names(interactions))
    }
    if (is.null(names(interaction_priority))) {
      stop("interaction_priority must be a scalar or a named vector.",
           call. = FALSE)
    }
  }

  for (v in names(interactions)) {
    rates <- interactions[[v]]
    if (!is.numeric(rates) || is.null(names(rates)) || any(names(rates) == "")) {
      stop("Each interactions element must be a named numeric vector: ", v,
           call. = FALSE)
    }
    if (any(!is.finite(rates)) || any(rates < 0 | rates > 1)) {
      stop("All rates in interactions[['", v, "']] must be between 0 and 1.",
           call. = FALSE)
    }
    priority <- unname(interaction_priority[v])
    if (length(priority) != 1L || is.na(priority) || priority <= 0) {
      stop("Missing or invalid interaction_priority for: ", v, call. = FALSE)
    }
    out <- rbind(out, data.frame(
      variable = v,
      level = names(rates),
      target_rate = unname(rates),
      priority = priority,
      stringsAsFactors = FALSE
    ))
  }

  rownames(out) <- NULL
  out
}
