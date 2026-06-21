# ratecalib (开发中)

- **新增 Excel 输入/输出（方法论路线图 §四）**：`read_calibration_data()`、`read_targets_xlsx()`
  （表头容错，支持英文别名与中文表头）、`calibrate_from_excel()`（一步读数据+目标并求解，自动从
  目标表推断分组变量）、`export_calibration_xlsx()`（导出 data/target_check/margin_check/
  diagnostics/settings 多工作表）。依赖 `openxlsx` 走 `Suggests`，运行时 `requireNamespace()`
  守卫，缺失即报安装提示；不引入任何核心依赖。中文表头别名在源码中以 Unicode 码点构造，保持 R 代码纯 ASCII。
- **新增 `calibration_feasibility()`：求解前目标可行性预检**（方法论路线图 §三，收窄版）。
  做两件确定性、闭式的检查：(1) **总体–分组一致性恒等式**——某分组变量的每个水平都被目标覆盖时，
  总体率被唯一确定（`Σ W_ℓ·r_ℓ / W`），据此抓出与显式总体目标或另一完整变量互相矛盾的目标；
  (2) **单目标边际可达区间**——组总量固定 + 倍数箱界下，组内加权率的闭式可达区间（两段 water-filling），
  目标落区间外即必不可行。配套 `print.ratecalib_feasibility()`。返回值含明确边界声明：
  单目标筛查是**必要非充分**条件，联合可行仍以求解器为准。
- **`check_calibration_data()` 接入一致性预检**：求解前若分组目标隐含的总体率与显式总体目标
  实质性不一致，会发出告警（`calibrate_rates(check=TRUE)` 默认路径也会触发）。新增参数
  `consistency_tol`（默认 0.01）——仅在不一致超过该容差时告警，避免约数目标无法整除连续权重边际
  导致的亚个百分点噪音；需要精确（exact 模式）分析请直接调用 `calibration_feasibility()`。
- **R 代码全面英文化以满足 CRAN ASCII 可移植性要求**：报错信息、`print`/`summary`/`plot`
  输出、`example_rate_data()` 的类别值（现为 M/F、Urban/Rural、Edu1-5、Age1-5）均改为英文。
- **移除中文函数别名**（`校准合格率`、`生成目标表`、`检查校准数据`、`生成演示数据`）；所有函数仅保留英文名。
- CRAN 准备：删除 `DESCRIPTION` 的 `LazyData`、补 `methods` 到 Imports、改写英文 Description、
  修正 `URL`/`BugReports` 为真实仓库、`as()` 改用新版 Matrix 推荐写法、中文 PDF 手册移至
  `inst/manual/` 并改 ASCII 文件名。`R CMD check --as-cran` 现为 0 ERROR / 0 WARNING（仅余首次提交的 New submission NOTE）。
- **修复**：`make_rate_targets()` 仅给 `overall`（不给任何分组）时会误报 “groups must be a named list”
  与 “group_priority must be a scalar or a named vector”——现已支持仅总体目标的用法。
- 大幅扩充测试：新增 exact 模式达标与边际保持、soft 模式 achieved≈target、触界、错误路径、
  `check_calibration_data()` 各分支、以及 `print`/`summary`/`plot`/`calibration_diagnostics` 等 S3 方法的覆盖。

# ratecalib 0.2.1

- 全面改写中文README，加入理论、算法、参数、诊断、案例和常见问题。
- 新增一步式函数 `calibrate_rates()`。
- 新增中文别名：`校准合格率()`、`生成目标表()`、`检查校准数据()`、`生成演示数据()`。
- 新增 `check_calibration_data()`，在求解前检查权重、0/1结果、分组缺失、空类别及全0/全1类别。
- 新增 `example_rate_data()` 演示数据生成器。
- 中文化打印、摘要和绘图标题。
- 保留 `calibrate_pass_rates()` 作为完整专业接口。

# ratecalib 0.1.0

- 初始版本。
