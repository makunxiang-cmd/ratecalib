# ratecalib 改进与扩展路线

本文件记录对 `ratecalib` 的改进与扩展评估，供后续开发排期。
按性价比从高到低排列：能直接修的硬问题 → 方法论扩展 → 接口/工程 → 测试与文档。
评估基于通读源码（未运行 `R CMD check`，部分结论待实跑验证）。

相关文档：架构与算法见 [`ARCHITECTURE.md`](ARCHITECTURE.md)，接手概览见 [`../AGENTS.md`](../AGENTS.md)。

优先级标记：**P0**=尽快、**P1**=重要、**P2**=可选增强。

---

## 一、可直接修的具体问题

### P0 — 删除 `DESCRIPTION` 的 `LazyData: true`
该字段只在包内有 `data/` 目录（保存 `.rda` 数据集）时才该写。本包的"演示数据"由函数
`example_rate_data()` 生成，没有 `data/` 目录，因此这行会触发 R CMD check NOTE：
"LazyData is specified with no data directory"。直接删掉该行即可。

### P1 — `inst/doc/` 放预编译 PDF 不规范
R 包约定 `inst/doc` 由 vignette 构建自动生成，手动放 PDF 在 `--as-cran` 下可能告警。
建议二选一：
- 把中文手册改写成 `vignettes/` 下的 `.Rmd`，让它参与构建（推荐，见下文）；
- 或把 PDF 移到 `inst/manual/` 这类中性目录。

### P1 — roxygen 与手写 NAMESPACE / man 的漂移风险
源码里有 `#'` 注释，但 `NAMESPACE` 和 `man/*.Rd` 是手写的，且 `DESCRIPTION` 没有
`RoxygenNote` 字段。任何人一跑 `devtools::document()` 就可能覆盖手写内容。建议彻底转 roxygen：
补全各导出函数的 roxygen 块，加 `Roxygen: list(markdown = TRUE)`，让 `document()` 成为
唯一真源。长期省事。若暂不转，则在 `CONTRIBUTING.md` 明确禁用 `document()`。

### P2 — `README.txt` 与 `README.md` 重复
两者内容重复，易漂移。已在重组中把旧 `README.txt` 移到 `docs/old-readme.txt` 留档；
确认无用后可删除，统一以根目录 `README.md` 为准。

---

## 二、方法论上的扩展（最有价值）

### P1 — 支持多种距离函数（Deville–Särndal 校准族）
当前目标函数 `Σ(x−D)²/D` 是卡方距离（线性校准）。经典校准估计量是一个距离函数族——
线性、raking/熵距离、logit（有界）。现在用"卡方 + 箱式约束"近似有界校准，但熵 / logit
距离能**自然保证权重为正**且乘性调整更平滑。

建议加参数 `distance = c("chi2", "raking", "logit")`。这会让本包从"一个解法"升级为"一类方法"，
是最能拉开差距的扩展。实现上 raking/logit 是非二次目标，需改用迭代（牛顿/IPF）或对偶法，
工作量中等但收益大。

### P1 — 泛化到连续变量的均值 / 总量校准
真正的校准加权通常同时校准"人口边际总量"和"某连续变量的总量/均值"。现在 `outcome` 锁死 0/1。
把目标行从 `Σ x_i·I(组)·(y_i − r) = 0` 泛化为 `Σ x_i·(z_i − target) = 0`（z 为任意数值变量），
即可覆盖连续指标，核心代码改动不大。

### P2 — 支持交互目标（cross-classification）
目标现在是单维 `variable = level`。现实里常要校准"城镇×男性"的合格率。允许复合 key
（如 `variable = "sex:residence"` 或一组列）的交互目标会很实用。

### P1 — 目标一致性预检
固定各组边际总量后，总体合格率其实是各组率的加权平均——用户若同时给总体和分组目标，
exact 模式可能内在矛盾，目前只能等 OSQP 报 `primal infeasible`。建议求解前计算"理论可达区间"，
提前指出哪几个目标互相冲突，比单纯报 solver 失败友好得多。

### P2 — 方差 / 不确定性估计
校准后估计量的方差不同于原始抽样。可加 design-based 线性化方差，或支持 replicate weights
（BRR / jackknife）校准，向 `survey` 包看齐。

---

## 三、接口与工程

### P1 — 补齐标准 S3 提取方法
建议加 `weights.pass_rate_calibration()`（取校准权重）、`coef()` / `as.data.frame()`、
`predict()`。用户现在得 `fit$data$weight_calibrated` 手挖，不够地道。

### P2 — `plot()` 提供 ggplot2 选项
当前只有 base graphics。可选 `ggplot2` 输出（放 `Suggests`），诊断图更美观、可拼装。

### P2 — 返回对象瘦身选项
返回对象里塞了整个 `solver`，大问题时占内存。可加 `keep_solver = FALSE` 选项。

### P2 — 核心求解器内补充不可达组提示
`check_calibration_data()` 会警告全 0 / 全 1 组，但 `calibrate_pass_rates()` 本身不预检——
这类组目标根本不可达，soft 模式会静默偏离。建议核心函数也给出同样提示。

### P2 — 聚合分隔符的碰撞风险
聚合 key 用控制字符 `` 拼接，理论上若数据含该字符会碰撞。可改用 `match()` + 整数编码
构造 key，既免碰撞又更快。

---

## 四、测试与文档

### P0 — 扩充测试（上 CRAN 前的硬门槛）
目前只有 2 个测试（soft + 目标构造）。建议补：

- exact 模式可达 + 边际保持；
- soft 模式 `achieved ≈ target`（带 tolerance 的断言）；
- `check_calibration_data()` 各分支；
- 错误路径：权重含 0、outcome 非 0/1、目标变量不存在、exact 不可行；
- 边界触界（`.at_lower_bound` / `.at_upper_bound`）；
- S3 方法（print / summary / plot / diagnostics）输出。

### P1 — 增加 vignette
中文 PDF 手册已删除、内容并入中文 README。建议写一个 `.Rmd` vignette（端到端案例 +
soft/exact 对比 + 诊断解读），既参与构建又能生成 pkgdown 站点。

### P2 — pkgdown 站点与发布材料
如打算发布，可加 `_pkgdown.yml`（文档站点）与 `cran-comments.md`（CRAN 提交说明）。

---

## 五、建议的起步顺序

性价比最高的三件，**均已完成**（2026-06）：

1. ~~**删 `LazyData`**~~ ✅ 连同其余 CRAN 障碍一并清理（见下「进度」）。
2. ~~**转 roxygen**~~ ✅ `NAMESPACE`/`man/` 现由 `#'` 注释生成，`document()` 是唯一真源。
3. ~~**补一组测试**~~ ✅ 已覆盖 exact 达标、soft `achieved≈target`、触界、错误路径、`check_calibration_data` 各分支与 S3 方法。

方法论扩展（距离函数族 / 连续变量校准）建议单独立项，先出设计方案再实现（见 [`METHODOLOGY-ROADMAP.md`](METHODOLOGY-ROADMAP.md)，Phase 4 产出）。

---

## 进度（2026-06 接手）

- **CRAN 障碍清理（Phase 1）**：删 `LazyData`、补 `methods` 到 Imports、英文 Description、
  修正 `URL`/`BugReports`、`as()` 改新版 Matrix 写法、PDF 移至 `inst/manual/` 且 ASCII 文件名、
  **R 代码全面英文化**（删除中文别名，报错/输出/演示数据类别值改英文）。
  `R CMD check --as-cran` 由 3 WARNING/4 NOTE 降到 **0 ERROR / 0 WARNING / 1 NOTE**（仅 New submission）。
- **测试扩充（Phase 2）**：测试从 2 个增至 25 个 `test_that`；过程中修复 `make_rate_targets()`
  仅给 `overall`（无分组）时的两处误报。
- **转 roxygen（Phase 3）**：`DESCRIPTION` 加 `RoxygenNote`/`Roxygen: list(markdown=TRUE)`，
  `roxygenise()` 幂等无告警。
- **收尾**：中文 PDF 手册已删除；README 已改用英文函数名与英文演示数据类别值（`M/F`、`Urban/Rural`、`Edu1-5`、`Age1-5`），示例经端到端实跑验证。

---

## 附：已确认的正确性（通读核对，无需改动）

- soft 模式 `P += 2·RᵀWR` 与目标 `0.5 xᵀP x` 的系数一致（惩罚项 `xᵀRᵀWR x` 正确）。
- 卡方目标到 OSQP 形式的展开 `P = diag(2/D)`、`q = −2` 正确。
- 边际约束去掉每个分组变量的最后一个水平以避免与总量约束共线，处理得当。
- 目标行线性化 `Σ x_c·mask·(outcome − r) = 0` 等价于该组加权合格率 = 目标率，成立。
