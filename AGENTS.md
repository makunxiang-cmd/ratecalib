# AGENTS.md — ratecalib 开发接手文档

> 本文件供后续 AI agent 或开发者快速接手本项目。阅读本文件后，应能理解项目目标、
> 代码结构、核心算法、开发流程与待办事项，无需重新通读全部源码。
> 配套深度文档：算法见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)，
> 已完成进度与工程清单见 [`docs/IMPROVEMENTS.md`](docs/IMPROVEMENTS.md)，
> 未实现的方法论扩展设计见 [`docs/METHODOLOGY-ROADMAP.md`](docs/METHODOLOGY-ROADMAP.md)。

---

## 0. 当前状态速览（务必先读）

- **仓库**：<https://github.com/makunxiang-cmd/ratecalib>，默认分支 `main`（本地与远端已同步）。
- **版本**：`DESCRIPTION` 为 `0.2.1`；`NEWS.md` 顶部有「开发中」段记录**尚未发版**的改动
  （含**破坏性**：删除中文函数别名）。正式发版时记得跳版本号并把「开发中」改成版本标题。
- **CRAN 体检**：`R CMD check --as-cran` = **0 ERROR / 0 WARNING / 1 NOTE**
  （NOTE 仅为 "New submission"，首次提交不可避免，非问题）。
- **测试**：**25 个 `test_that` 全通过**（`package/tests/testthat/` 下 5 个文件）。
- **最近一次接手做了什么**（2026-06）：
  1. 清理全部 CRAN 障碍，并把 **R 代码全面英文化**（删中文别名；报错/`print`/`summary`/`plot`
     输出/`example_rate_data()` 类别值改英文 `M/F`、`Urban/Rural`、`Edu1-5`、`Age1-5`）；
  2. 测试从 2 个扩到 25 个，过程中修复 `make_rate_targets()` 仅给 `overall`（无分组）时的两处误报；
  3. **转 roxygen**：`NAMESPACE`/`man/` 改由 `#'` 注释生成，`document()` 为唯一真源；
  4. 写 [`docs/METHODOLOGY-ROADMAP.md`](docs/METHODOLOGY-ROADMAP.md) 方法论扩展**设计方案**（仅设计，未实现）。
- **下一步在哪**：功能扩展均未实现，设计与优先级见 `METHODOLOGY-ROADMAP.md` §九。
  最稳起点＝可行性预检的「总体–分组一致性恒等式」；最实用＝Excel 输入输出。
- **接手注意**：本仓库有两条铁律——① **R 代码只用 ASCII 英文**（§7）；② **不手改 `NAMESPACE`/`man/`，
  改 roxygen 再 `document()`**（§7）。详见 §7。

---

## 1. 项目是什么

`ratecalib` 是一个**面向二元结果指标的多目标校准加权 R 包**（Title：多分组合格率目标的校准加权工具）。

**要解决的问题**：给定一份每行一个样本、带正初始权重的数据，一个二元结果列（合格=1 / 不合格=0），
以及总体和若干重叠分组（性别、城乡、学历、年龄等）的目标合格率，
**只调整权重、不改动原始结果变量**，使总体及各分组的加权合格率尽量接近（软约束）或精确达到（精确约束）目标，
同时尽量保留初始权重结构和各人口边际总量。

- **当前版本**：0.2.1（见 `DESCRIPTION` / `NEWS.md`）
- **语言**：**R 代码（函数名、报错信息、`print`/`summary`/`plot` 输出）已全部英文化**，
  以满足 CRAN 的 ASCII 可移植性要求；项目文档（README、本文件、`docs/`）仍以中文为主。
  旧版的中文函数别名（`校准合格率` 等）已删除，README 已同步改用英文函数名与英文演示数据类别值；
  原中文 PDF 手册已删除。
- **R 版本要求**：R (>= 4.1.0)
- **核心依赖**：`Matrix`、`methods`、`osqp`（求解器）；测试依赖 `testthat (>= 3.0.0)`
- **许可证**：MIT

---

## 2. 两层 API（最重要的概念）

| 层级 | 函数 | 适用场景 |
|------|------|----------|
| 一步式 | `calibrate_rates()` | 日常使用，自动建目标表、识别分组、数据检查后求解 |
| 专业底层 | `calibrate_pass_rates()` | 需要完全控制目标表与求解参数 |
| 辅助 | `make_rate_targets()` | 由 `overall` + `groups` 命名列表构造目标 data.frame |
| 辅助 | `check_calibration_data()` | 求解前检查权重/0-1结果/分组缺失/目标可支持性 |
| 辅助 | `example_rate_data()` | 生成含性别/城乡/学历/年龄的模拟数据（类别值现为英文：M/F、Urban/Rural、Edu1-5、Age1-5） |
| 诊断 | `calibration_diagnostics()` | 从结果对象提取目标/边际/权重诊断 |

调用链：`calibrate_rates()` → `make_rate_targets()` + `check_calibration_data()` → `calibrate_pass_rates()`（真正的求解器）。

> 注：旧版的中文函数别名（`校准合格率` / `生成目标表` / `检查校准数据` / `生成演示数据`，原在 `R/zzz_aliases.R`）
> 已为满足 CRAN ASCII 要求而删除，`zzz_aliases.R` 文件已不存在。所有函数仅保留英文名。

---

## 3. 核心算法（求解器内部，`R/calibrate_pass_rates.R`）

求解一个**有界凸二次规划（QP）**，用 OSQP 求解。关键设计：

1. **聚合降维**：先把个人记录按「分组变量交叉单元 × 结果状态(0/1)」聚合，
   每个聚合单元只保留初始权重之和 `D`。优化变量 `x` 是各单元的调整后权重总和，
   维度 `m` = 观测到的单元数，远小于样本量 n，因此大样本下高效。
   分隔符用 ``（单元分隔符），避免与数据中的字符冲突。

2. **目标函数**：最小化 `sum_c (x_c - D_c)^2 / D_c`，即在保持权重结构前提下偏离初始最小。
   OSQP 形式 `0.5 x'P x + q'x`，其中 `P = diag(2/D)`、`q = -2`。

3. **硬约束（始终保留人口边际）**：
   - 总量约束：`sum(x) = grand_total`；
   - 每个分组变量的各水平（去掉最后一个水平避免共线）：`sum(x · I(level)) = 初始该水平总量`。
   这些约束保证校准后各边际总量不变（`margin_check$relative_change ≈ 0`）。

4. **目标行（线性化合格率约束）**：对每个目标
   `sum_i x_i · I(group) · (y_i − target_rate) = 0` 等价于该组加权合格率 = 目标率。
   - **soft 模式**：把目标行作为惩罚项加入 `P`，权重为 `lambda * grand_total * priority / size^2`，
     允许误差但越大越受罚（默认模式，更稳健）。
   - **exact 模式**：把目标行作为等式硬约束，可能因目标相互矛盾或边界过窄而无解。

5. **边界**：每个单元的调整倍数 `x_c / D_c ∈ [lower, upper]`，默认 `[0.25, 4]`。

6. **求解失败处理**：若 OSQP status 非 "solved"，抛出英文报错（exact 模式提示目标可能矛盾），建议改 soft 或放宽边界。

求解后产出：调整后权重列、单元级倍数、`target_check`（目标达成情况）、`margin_check`（边际保持情况）、
`diagnostics`（样本量、ESS 有效样本量、DEFF 设计效应、倍数范围、触界单元数、最大目标误差）。

返回对象 class 为 `pass_rate_calibration`，配套 S3 方法 `print` / `summary` / `plot`。

---

## 4. 文件地图

项目采用「工程目录 + 子目录里的 R 包」布局：项目根只保留 `AGENTS.md`、`README.md`
两个可见文件，R 包本体（含 `DESCRIPTION`/`NAMESPACE` 等必须位于包根的文件）整体放在
`package/` 子目录，便于构建工具识别。

```
ratecalib/                          # 项目根（只放 AGENTS.md、README.md 两个可见文件）
├── AGENTS.md                       # ← 本文件，agent 接手入口
├── README.md                       # 中文完整使用手册（理论/算法/参数/诊断/FAQ）
├── .gitignore                      # Git 忽略规则（dotfile）
├── package/                        # ★ R 包本体（R CMD build/check 的目标目录）
│   ├── DESCRIPTION                 # 包元数据、依赖、版本
│   ├── NAMESPACE                   # 由 roxygen 自动生成（勿手改），导出函数与 S3 方法
│   ├── NEWS.md                     # 版本变更记录
│   ├── LICENSE                     # MIT
│   ├── .Rbuildignore               # 构建时忽略的文件
│   ├── R/
│   │   ├── calibrate_pass_rates.R  # ★ 核心求解器（QP 构造 + OSQP + 诊断）
│   │   ├── easy.R                  # 一步式 calibrate_rates() + check_calibration_data() + example_rate_data()
│   │   ├── targets.R               # make_rate_targets() 目标表构造
│   │   └── methods.R               # S3: print/summary/plot + calibration_diagnostics()
│   ├── man/                        # .Rd 帮助文档（roxygen 自动生成，勿手改）
│   ├── tests/
│   │   ├── testthat.R              # 测试入口
│   │   └── testthat/             # test-calibration / -exact-and-bounds / -checks / -errors / -methods
│   └── inst/
│       └── examples/basic_example.R    # 端到端示例脚本
├── docs/                           # 开发文档
│   ├── ARCHITECTURE.md             # 架构与算法详解（图解数据流）
│   ├── IMPROVEMENTS.md             # 改进与扩展路线（含已完成进度）
│   ├── METHODOLOGY-ROADMAP.md      # 方法论扩展设计方案（距离族/连续变量/一致性预检等）
│   ├── CONTRIBUTING.md             # 开发与贡献指南
│   └── old-readme.txt              # 旧版 README 纯文本副本（历史留存）
├── dev/                            # 开发辅助脚本（非构建产物）
│   └── dev.R                       # 常用 devtools 工作流
├── feedback/                       # 用户反馈（每条一文件，见其 README）
│   └── README.md
├── release/                        # 最终上传用的 R 包（ratecalib_*.tar.gz）
│   └── README.md
└── .github/
    └── workflows/R-CMD-check.yaml  # CI：多平台 R CMD check（working-directory: package）
```

★ = 改动风险最高、最该先读：`package/` 是构建目标，`package/R/calibrate_pass_rates.R` 是核心。

---

## 5. 数据契约（修改时务必遵守）

**输入 `data`**：data.frame，每行一个样本。
- `outcome` 列：仅含 0/1（或可强转为 0/1 的 logical/factor）；
- `weight` 列：全部有限且严格 > 0；
- `group_vars` 各列：无缺失值（缺失须先编码为显式类别）。

**`targets` data.frame**：列 `variable`、`level`、`target_rate`（0–1），可选 `priority`（正数，soft 模式权重）。
总体目标的 `variable` 用 `.overall`/`overall`/`TOTAL` 任一（中文关键字已随英文化移除），内部统一为 `.overall` + level `.all`。

**返回对象 `pass_rate_calibration`** 关键字段：`data`（含新权重列）、`cell_weights`、`target_check`、
`margin_check`、`diagnostics`、`solver_status`、`solver`、`settings`、`call`。

不变量（测试覆盖）：新权重全部有限且 > 0；`max(abs(margin_check$relative_change)) < 1e-5`。

---

## 6. 开发命令

R 包在 `package/` 子目录，所有命令都针对它，在**项目根目录**操作。

**首选 devtools 流程**（若未装：`install.packages(c("devtools","roxygen2","testthat","Matrix","osqp"))`）：

```r
devtools::load_all("package")            # 加载包（不安装）
devtools::document("package")            # 改了 #' 注释后必跑：重生成 NAMESPACE 与 man/
devtools::test("package")                # 运行 testthat
devtools::check("package")               # R CMD check（提交前必跑）
devtools::build("package", path = "release")  # 构建 .tar.gz 到 release/
```

**无 devtools 时的等价做法**（本环境最近就是这样跑通的——只需 `Matrix`/`osqp`/`testthat`/`roxygen2`，
可 `install.packages(..., type="binary")` 装二进制更快）：

```bash
R CMD build package                            # 生成 ratecalib_<ver>.tar.gz（项目根）
R CMD check ratecalib_<ver>.tar.gz --as-cran   # 全量体检（会顺带跑测试）
Rscript -e 'roxygen2::roxygenise("package")'   # 重生成 NAMESPACE / man/
```

只想快速跑测试（不打包）：把 `package/R/*.R` 用 `sys.source()` 载入环境后
`testthat::test_dir("package/tests/testthat")`。

> `*.tar.gz` 与 `*.Rcheck/` 已在 `.gitignore`，不会误提交。更多见 `dev/dev.R`。

---

## 7. 项目约定（重要）

- **roxygen 是 `NAMESPACE` 与 `man/` 的唯一真源**（`DESCRIPTION` 含 `RoxygenNote` 与
  `Roxygen: list(markdown = TRUE)`）。只改 `R/*.R` 里的 `#'` 注释，再跑 `devtools::document("package")`
  （或 `roxygen2::roxygenise("package")`）重新生成；**切勿手改 `NAMESPACE` 或 `man/*.Rd`**。
  S3 方法用 `@rdname` 归并到共享帮助主题（如 `pass_rate_calibration-methods`）。
- **R 代码全英文（CRAN 可移植性硬约束）**：所有报错信息、`print`/`summary`/`plot` 输出、`example_rate_data()`
  生成的类别值都必须是 ASCII 英文，不得引入非 ASCII 字符（注释里允许中文，但避免为宜）。
  新增导出函数只用英文名，不再提供中文别名。面向中文用户的说明放在文档（README），不进 R 代码。
- **soft 是默认模式**，比 exact 更稳健；文档与示例应优先演示 soft。
- **不要改动原始 outcome**：本包哲学是只调权重。任何修改 y 的逻辑都违背设计。
- **包在 `package/` 子目录**：所有 devtools/R CMD 命令都针对 `package/`，不要在项目根直接当包构建。
- **项目根保持整洁**：根目录只放 `AGENTS.md`、`README.md`（及 `.gitignore`、`.github` 等 dotfile/基础设施），
  其余一律归入文件夹。新增文档进 `docs/`，脚本进 `dev/`。

---

## 8. 改进与扩展路线

完整的改进与扩展清单（含可直接修的问题、方法论扩展、接口/工程、测试文档）见
[`docs/IMPROVEMENTS.md`](docs/IMPROVEMENTS.md)。下面只列最紧的待办：

- [x] `DESCRIPTION` 的 `URL`/`BugReports` 与 git remote 已指向 `makunxiang-cmd/ratecalib`。
- [x] 删 `DESCRIPTION` 的 `LazyData: true`（无 `data/` 目录会触发 R CMD check NOTE）。
- [x] 已转 roxygen：`NAMESPACE`/`man/` 全部由 `#'` 注释生成，`document()` 是唯一真源。
- [x] 测试已扩充：exact 模式、`check_calibration_data()` 各分支、错误路径、S3 方法、`achieved≈target` 断言均已覆盖。
- [x] 中文 PDF 手册已删除（内容并入中文 README）；后续如需可改写为 `vignettes/` 下的 `.Rmd`。

---

## 9. 接手第一步建议

1. 读 §0 状态速览 → 本文件其余 → `docs/ARCHITECTURE.md` → `package/R/calibrate_pass_rates.R`（核心）。
2. 确认基线：跑一次 `R CMD check ... --as-cran`（或 `devtools::check("package")`），应是 0/0/1；
   再跑测试确认全绿（§6）。**先确认基线通过，再动手。**
3. 跑 `package/inst/examples/basic_example.R` 感受端到端流程（英文类别值）。
4. 要做新功能：先读 `docs/METHODOLOGY-ROADMAP.md`，按 §九 优先级选一项，**先出带验收断言的测试再实现**。
5. 任何改动牢记两条铁律（§7）：R 代码只用 ASCII 英文；不手改 `NAMESPACE`/`man/`，改 roxygen 后 `document()`。
