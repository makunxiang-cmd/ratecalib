#' 一步式合格率权重校准
#'
#' 面向日常使用的一步式接口。用户只需提供数据、结果变量、初始权重、
#' 总体目标和各分组目标，函数会自动生成目标表、识别分组变量、执行数据检查，
#' 并调用 `calibrate_pass_rates()` 完成校准。
#'
#' @param data 数据框，每行代表一个样本。
#' @param outcome 二元结果变量列名，合格为1，不合格为0。
#' @param weight 初始权重列名。
#' @param overall 总体目标合格率，可为NULL。
#' @param groups 命名列表。每个元素名是分组变量名，元素内容是带名称的目标率向量。
#' @param priority 总体目标优先级，默认为5。
#' @param group_priority 分组目标优先级，可为单个数或按变量命名的向量。
#' @param lower,upper 权重调整倍数上下限。
#' @param mode `"soft"`为软约束，`"exact"`为精确约束。
#' @param lambda 软约束惩罚强度。
#' @param new_weight 新权重列名。
#' @param check 是否先执行数据检查。
#' @param verbose 是否显示OSQP求解信息。
#'
#' @return `pass_rate_calibration`对象。
#' @export
calibrate_rates <- function(
    data,
    outcome,
    weight,
    overall = NULL,
    groups = list(),
    priority = 5,
    group_priority = 1,
    lower = 0.25,
    upper = 4,
    mode = c("soft", "exact"),
    lambda = 1e4,
    new_weight = "weight_calibrated",
    check = TRUE,
    verbose = FALSE
) {
  mode <- match.arg(mode)
  if (!is.list(groups) || is.null(names(groups)) || any(names(groups) == "")) {
    stop("groups 必须是带名称的列表，例如 list(sex = c('男'=0.7, '女'=0.68))。",
         call. = FALSE)
  }
  group_vars <- names(groups)
  if (length(group_vars) < 1L) {
    stop("groups 至少需要包含一个分组变量。", call. = FALSE)
  }

  targets <- make_rate_targets(
    overall = overall,
    groups = groups,
    overall_priority = priority,
    group_priority = group_priority
  )

  if (isTRUE(check)) {
    report <- check_calibration_data(
      data = data,
      outcome = outcome,
      weight = weight,
      group_vars = group_vars,
      targets = targets
    )
    if (!isTRUE(report$ok)) {
      stop(paste(c("数据检查未通过：", paste0("- ", report$errors)), collapse = "\n"),
           call. = FALSE)
    }
    if (length(report$warnings) > 0L) {
      warning(paste(c("数据检查提示：", paste0("- ", report$warnings)), collapse = "\n"),
              call. = FALSE)
    }
  }

  calibrate_pass_rates(
    data = data,
    outcome = outcome,
    weight = weight,
    group_vars = group_vars,
    targets = targets,
    lower = lower,
    upper = upper,
    mode = mode,
    lambda = lambda,
    new_weight = new_weight,
    verbose = verbose
  )
}

#' 校准前数据检查
#'
#' 检查变量、权重、二元结果、分组覆盖情况和目标可支持性，并给出当前加权合格率。
#'
#' @param data 数据框。
#' @param outcome 二元结果变量列名。
#' @param weight 初始权重列名。
#' @param group_vars 分组变量列名向量。
#' @param targets 可选目标表。
#'
#' @return 一个列表，包含 `ok`、`errors`、`warnings`、`overview`、
#'   `group_summary` 和 `target_support`。
#' @export
check_calibration_data <- function(data, outcome, weight, group_vars, targets = NULL) {
  errors <- character()
  warnings <- character()

  if (!is.data.frame(data)) {
    return(list(ok = FALSE, errors = "data 必须是数据框。", warnings = character()))
  }
  required <- unique(c(outcome, weight, group_vars))
  missing <- setdiff(required, names(data))
  if (length(missing)) errors <- c(errors, paste0("缺少变量：", paste(missing, collapse = "、")))
  if (length(errors)) return(list(ok = FALSE, errors = errors, warnings = warnings))

  w <- suppressWarnings(as.numeric(data[[weight]]))
  y_raw <- data[[outcome]]
  if (is.logical(y_raw)) y_raw <- as.integer(y_raw)
  y <- suppressWarnings(as.numeric(as.character(y_raw)))

  if (anyNA(w) || any(!is.finite(w))) errors <- c(errors, "初始权重含缺失值或非有限值。")
  if (any(w <= 0, na.rm = TRUE)) errors <- c(errors, "初始权重必须全部大于0。")
  if (anyNA(y) || any(!y %in% c(0, 1))) errors <- c(errors, "结果变量必须只包含0和1。")
  if (anyNA(data[group_vars])) errors <- c(errors, "分组变量含缺失值；请先将缺失值编码为明确类别。")
  if (length(errors)) return(list(ok = FALSE, errors = errors, warnings = warnings))

  weighted_rate <- function(mask) sum(w[mask] * y[mask]) / sum(w[mask])
  overview <- data.frame(
    指标 = c("样本量", "初始权重总和", "初始加权合格率", "初始权重最小值", "初始权重中位数", "初始权重最大值"),
    数值 = c(nrow(data), sum(w), weighted_rate(rep(TRUE, nrow(data))), min(w), stats::median(w), max(w)),
    check.names = FALSE
  )

  group_summary <- data.frame()
  for (v in group_vars) {
    levs <- unique(as.character(data[[v]]))
    for (lev in levs) {
      mask <- as.character(data[[v]]) == lev
      yy <- y[mask]
      row <- data.frame(
        variable = v,
        level = lev,
        n = sum(mask),
        initial_weight_total = sum(w[mask]),
        initial_weighted_rate = weighted_rate(mask),
        has_0 = any(yy == 0),
        has_1 = any(yy == 1),
        stringsAsFactors = FALSE
      )
      group_summary <- rbind(group_summary, row)
      if (!row$has_0 || !row$has_1) {
        warnings <- c(warnings, paste0(v, " = ", lev, " 仅包含", if (row$has_1) "合格样本" else "不合格样本", "，该组的目标率无法通过组内权重调整改变。"))
      }
    }
  }

  target_support <- NULL
  if (!is.null(targets)) {
    targets <- as.data.frame(targets, stringsAsFactors = FALSE)
    needed <- c("variable", "level", "target_rate")
    if (!all(needed %in% names(targets))) {
      errors <- c(errors, "targets 必须包含 variable、level、target_rate 三列。")
    } else {
      target_support <- targets
      target_support$supported <- TRUE
      target_support$reason <- ""
      for (i in seq_len(nrow(targets))) {
        v <- as.character(targets$variable[i])
        lev <- as.character(targets$level[i])
        r <- as.numeric(targets$target_rate[i])
        if (v %in% c(".overall", "overall", "总体", "总计", "TOTAL")) {
          mask <- rep(TRUE, nrow(data))
        } else if (!v %in% group_vars) {
          target_support$supported[i] <- FALSE
          target_support$reason[i] <- "目标变量不在group_vars中"
          next
        } else {
          mask <- as.character(data[[v]]) == lev
        }
        if (!any(mask)) {
          target_support$supported[i] <- FALSE
          target_support$reason[i] <- "该类别没有样本"
        } else if (all(y[mask] == 0) && r > 0) {
          target_support$supported[i] <- FALSE
          target_support$reason[i] <- "该组全部为0，无法达到大于0的目标"
        } else if (all(y[mask] == 1) && r < 1) {
          target_support$supported[i] <- FALSE
          target_support$reason[i] <- "该组全部为1，无法达到小于1的目标"
        }
      }
      bad <- which(!target_support$supported)
      if (length(bad)) {
        errors <- c(errors, paste0("存在", length(bad), "个数据不支持的目标；请查看 target_support。"))
      }
    }
  }

  structure(list(
    ok = length(errors) == 0L,
    errors = unique(errors),
    warnings = unique(warnings),
    overview = overview,
    group_summary = group_summary,
    target_support = target_support
  ), class = "ratecalib_check")
}

#' @export
print.ratecalib_check <- function(x, ...) {
  cat("ratecalib 校准前检查\n")
  cat("状态：", if (isTRUE(x$ok)) "通过" else "未通过", "\n", sep = "")
  if (length(x$errors)) {
    cat("\n错误：\n", paste0("- ", x$errors, collapse = "\n"), "\n", sep = "")
  }
  if (length(x$warnings)) {
    cat("\n提示：\n", paste0("- ", x$warnings, collapse = "\n"), "\n", sep = "")
  }
  if (!is.null(x$overview)) {
    cat("\n数据概况：\n")
    print(x$overview, row.names = FALSE)
  }
  invisible(x)
}

#' 生成演示数据
#'
#' 创建一份包含性别、城乡、五段学历、五段年龄、合格指标和初始权重的模拟数据。
#'
#' @param n 样本量。
#' @param seed 随机种子。
#' @return 数据框。
#' @export
example_rate_data <- function(n = 5000L, seed = 2026L) {
  set.seed(seed)
  sex <- sample(c("男", "女"), n, TRUE, c(0.49, 0.51))
  residence <- sample(c("城镇", "农村"), n, TRUE, c(0.65, 0.35))
  education5 <- sample(paste0("学历", 1:5), n, TRUE, c(0.14, 0.23, 0.25, 0.27, 0.11))
  age5 <- sample(paste0("年龄", 1:5), n, TRUE, c(0.20, 0.24, 0.23, 0.19, 0.14))
  eta <- 0.45 + 0.10 * (sex == "男") + 0.08 * (residence == "城镇") +
    0.09 * (as.integer(sub("学历", "", education5)) - 3) -
    0.06 * (as.integer(sub("年龄", "", age5)) - 3)
  p <- stats::plogis(eta)
  qualified <- stats::rbinom(n, 1, p)
  initial_weight <- exp(stats::rnorm(n, 0, 0.28))
  data.frame(sex, residence, education5, age5, qualified, initial_weight,
             stringsAsFactors = FALSE)
}

