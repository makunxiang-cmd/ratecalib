#' 提取校准诊断结果
#'
#' @param x `pass_rate_calibration`对象。
#' @param sort_targets 是否按目标绝对误差从大到小排序。
#' @return 包含目标、边际和权重诊断的列表。
#' @export
calibration_diagnostics <- function(x, sort_targets = TRUE) {
  if (!inherits(x, "pass_rate_calibration")) {
    stop("x 必须是 pass_rate_calibration 对象。", call. = FALSE)
  }
  target_check <- x$target_check
  if (isTRUE(sort_targets)) {
    target_check <- target_check[order(-target_check$abs_error), , drop = FALSE]
    rownames(target_check) <- NULL
  }
  list(targets = target_check, margins = x$margin_check, weights = x$diagnostics)
}

#' @export
print.pass_rate_calibration <- function(x, digits = 4, ...) {
  d <- stats::setNames(x$diagnostics$value, x$diagnostics$metric)
  cat("合格率权重校准结果\n")
  cat("  校准模式：        ", if (x$settings$mode == "soft") "软约束" else "精确约束", "\n", sep = "")
  cat("  求解状态：        ", x$solver_status, "\n", sep = "")
  cat("  原始样本量：      ", format(d[["sample_size"]], scientific = FALSE), "\n", sep = "")
  cat("  优化单元数：      ", format(d[["observed_optimization_cells"]], scientific = FALSE), "\n", sep = "")
  cat("  最大目标误差：    ", format(round(d[["maximum_absolute_target_error"]], digits), nsmall = digits), "\n", sep = "")
  cat("  权重倍数范围：    ", format(round(d[["minimum_multiplier"]], digits), nsmall = digits),
      " 至 ", format(round(d[["maximum_multiplier"]], digits), nsmall = digits), "\n", sep = "")
  cat("  校准后有效样本量：", format(round(d[["calibrated_ESS"]], 1), scientific = FALSE), "\n", sep = "")
  invisible(x)
}

#' @export
summary.pass_rate_calibration <- function(object, top = 10L, ...) {
  top <- max(1L, as.integer(top))
  target_check <- object$target_check[order(-object$target_check$abs_error), , drop = FALSE]
  structure(list(call = object$call, settings = object$settings,
                 solver_status = object$solver_status,
                 diagnostics = object$diagnostics,
                 largest_target_errors = utils::head(target_check, top)),
            class = "summary_pass_rate_calibration")
}

#' @export
print.summary_pass_rate_calibration <- function(x, digits = 4, ...) {
  labels <- c(
    sample_size = "样本量", observed_optimization_cells = "优化单元数",
    initial_ESS = "初始有效样本量", calibrated_ESS = "校准后有效样本量",
    initial_weight_DEFF = "初始权重设计效应", calibrated_weight_DEFF = "校准后权重设计效应",
    minimum_multiplier = "最小权重倍数", median_multiplier = "权重倍数中位数",
    maximum_multiplier = "最大权重倍数", cells_at_lower_bound = "触及下限的单元数",
    cells_at_upper_bound = "触及上限的单元数", maximum_absolute_target_error = "最大目标绝对误差"
  )
  cat("合格率权重校准摘要\n\n调用：\n")
  print(x$call)
  cat("\n求解状态：", x$solver_status, "\n", sep = "")
  cat("校准模式：", if (x$settings$mode == "soft") "软约束" else "精确约束", "\n\n", sep = "")
  d <- x$diagnostics
  d$metric_cn <- unname(labels[d$metric])
  d$value <- round(d$value, digits)
  cat("权重诊断：\n")
  print(d[c("metric_cn", "value")], row.names = FALSE)
  cat("\n误差最大的目标：\n")
  shown <- x$largest_target_errors
  names(shown)[names(shown) == "variable"] <- "变量"
  names(shown)[names(shown) == "level"] <- "类别"
  names(shown)[names(shown) == "target_rate"] <- "目标率"
  names(shown)[names(shown) == "initial_rate"] <- "初始率"
  names(shown)[names(shown) == "achieved_rate"] <- "校准后率"
  names(shown)[names(shown) == "error"] <- "误差"
  names(shown)[names(shown) == "abs_error"] <- "绝对误差"
  numeric_cols <- vapply(shown, is.numeric, logical(1))
  shown[numeric_cols] <- lapply(shown[numeric_cols], round, digits = digits)
  print(shown, row.names = FALSE)
  invisible(x)
}

#' 绘制校准诊断图
#' @param x 校准结果对象。
#' @param type `"target_error"`或`"multipliers"`。
#' @param top 展示误差最大的目标数量。
#' @param ... 传给基础绘图函数的参数。
#' @return 不可见地返回x。
#' @export
plot.pass_rate_calibration <- function(x, type = c("target_error", "multipliers"), top = 20L, ...) {
  type <- match.arg(type)
  if (type == "target_error") {
    d <- x$target_check
    d$label <- paste(d$variable, d$level, sep = "：")
    d <- utils::head(d[order(d$abs_error, decreasing = TRUE), , drop = FALSE], max(1L, as.integer(top)))
    graphics::barplot(rev(d$error), names.arg = rev(d$label), horiz = TRUE, las = 1,
                      xlab = "校准后合格率 − 目标合格率", main = "目标合格率误差", ...)
    graphics::abline(v = 0, lty = 2)
  } else {
    graphics::hist(x$cell_weights$.multiplier, xlab = "校准权重 ÷ 初始权重",
                   main = "权重调整倍数分布", ...)
  }
  invisible(x)
}
