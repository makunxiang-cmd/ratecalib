# dev/dev.R — ratecalib 常用开发工作流
# 在包根目录（ratecalib 2/）启动 R 后逐段运行。本文件不参与包构建。

# ---- 一次性：安装开发依赖 ----
# install.packages(c("devtools", "roxygen2", "testthat", "Matrix", "osqp"))

library(devtools)

# ---- 日常开发循环 ----
load_all()        # 加载包（不安装），改完代码重跑即可
test()            # 运行 tests/testthat/ 全部测试

# ---- 文档 ----
# 注意：NAMESPACE 与 man/ 当前为手写维护。
# 仅在确认 roxygen 注释完整后再运行 document()，否则可能覆盖手写内容。
# document()

# ---- 提交前检查 ----
check()           # R CMD check，提交前必跑，确保无 ERROR/WARNING

# ---- 构建源码包 ----
# build()         # 生成 ../ratecalib_<version>.tar.gz

# ---- 快速冒烟测试 ----
smoke_test <- function() {
  load_all()
  d <- example_rate_data(n = 3000L)
  fit <- calibrate_rates(
    data = d,
    outcome = "qualified",
    weight = "initial_weight",
    overall = 0.70,
    groups = list(
      sex = c("男" = 0.71, "女" = 0.69),
      residence = c("城镇" = 0.71, "农村" = 0.68)
    ),
    mode = "soft"
  )
  print(fit)
  summary(fit)
  invisible(fit)
}
# fit <- smoke_test()
