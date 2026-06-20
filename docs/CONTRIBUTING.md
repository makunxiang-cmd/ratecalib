# 贡献指南 — ratecalib

感谢参与 `ratecalib` 的开发。本文件说明本地开发、测试与提交规范。
项目整体结构与算法见 [`../AGENTS.md`](../AGENTS.md)、[`ARCHITECTURE.md`](ARCHITECTURE.md)
与改进路线 [`IMPROVEMENTS.md`](IMPROVEMENTS.md)。

> 布局提示：R 包本体在项目根的 `package/` 子目录，开发命令都针对它。

## 开发环境

需要 R (>= 4.1.0)。安装开发依赖：

```r
install.packages(c("devtools", "roxygen2", "testthat", "Matrix", "osqp"))
```

## 常用流程

在**项目根目录**启动 R（包在 `package/` 子目录）：

```r
devtools::load_all("package")    # 加载包
devtools::document("package")    # 由 roxygen 注释重新生成 NAMESPACE 与 man/
devtools::test("package")        # 运行测试
devtools::check("package")       # 提交前必跑 R CMD check
```

辅助脚本见 [`../dev/dev.R`](../dev/dev.R)。

## 代码约定

- **只调权重，不改 outcome**：本包的核心哲学，任何修改原始结果变量的逻辑都不接受。
- **roxygen 是 `NAMESPACE` 与 `man/` 的唯一真源**：只编辑 `package/R/*.R` 里的 `#'` 注释，
  再跑 `devtools::document("package")` 生成；**切勿手改 `NAMESPACE` 或 `man/*.Rd`**（会被覆盖）。
- **R 代码全英文（CRAN ASCII 硬约束）**：报错信息、`print`/`summary`/`plot` 输出、演示数据类别值
  都用 ASCII 英文，新增导出函数只用英文名（不再提供中文别名）。
- **soft 为默认模式**，文档与示例优先演示 soft。
- 参数校验要给出清晰、可操作的报错信息。
- 缩进 2 空格，遵循 tidyverse 风格。

## 测试要求

- 新功能须配套 `package/tests/testthat/` 下的测试。
- 保持核心不变量：校准后权重有限且 > 0；`max(abs(margin_check$relative_change)) < 1e-5`。
- 涉及求解器的测试用 `skip_if_not_installed("osqp")` 保护。

## 提交规范

- 提交信息简洁说明「做了什么、为什么」。
- 修改面向用户的行为时，更新 `package/NEWS.md` 与 `README.md`。
- 提 PR 前确保 `devtools::check("package")` 无 ERROR/WARNING。
