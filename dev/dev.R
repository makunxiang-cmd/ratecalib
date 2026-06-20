# dev/dev.R — ratecalib 常用开发工作流
# 在【项目根目录】启动 R 后逐段运行。R 包本体在 package/ 子目录，故命令都带 "package" 路径。
# 本文件不参与包构建。

# ---- 一次性：安装开发依赖 ----
# install.packages(c("devtools", "roxygen2", "testthat", "Matrix", "osqp"))

library(devtools)

PKG <- "package"  # R 包所在子目录

# ---- 日常开发循环 ----
load_all(PKG)     # 加载包（不安装），改完代码重跑即可
test(PKG)         # 运行 package/tests/testthat/ 全部测试

# ---- 文档 ----
# 注意：NAMESPACE 与 man/ 当前为手写维护。
# 仅在确认 roxygen 注释完整后再运行 document()，否则可能覆盖手写内容。
# document(PKG)

# ---- 提交前检查 ----
check(PKG)        # R CMD check，提交前必跑，确保无 ERROR/WARNING

# ---- 构建源码包到 release/ ----
# build(PKG, path = "release")   # 生成 release/ratecalib_<version>.tar.gz

# ---- 快速冒烟测试 ----
smoke_test <- function() {
  load_all(PKG)
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
