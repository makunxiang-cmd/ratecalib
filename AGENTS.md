# AGENTS.md — ratecalib 开发接手文档

> 本文件供后续 AI agent 或开发者快速接手本项目。阅读本文件后，应能理解项目目标、
> 代码结构、核心算法、开发流程与待办事项，无需重新通读全部源码。
> 配套深度文档见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

---

## 1. 项目是什么

`ratecalib` 是一个**面向二元结果指标的多目标校准加权 R 包**（Title：多分组合格率目标的校准加权工具）。

**要解决的问题**：给定一份每行一个样本、带正初始权重的数据，一个二元结果列（合格=1 / 不合格=0），
以及总体和若干重叠分组（性别、城乡、学历、年龄等）的目标合格率，
**只调整权重、不改动原始结果变量**，使总体及各分组的加权合格率尽量接近（软约束）或精确达到（精确约束）目标，
同时尽量保留初始权重结构和各人口边际总量。

- **当前版本**：0.2.1（见 `DESCRIPTION` / `NEWS.md`）
- **语言**：界面与文档以中文为主，底层 R 函数提供中英文双套接口
- **R 版本要求**：R (>= 4.1.0)
- **核心依赖**：`Matrix`、`osqp`（求解器）；测试依赖 `testthat (>= 3.0.0)`
- **许可证**：MIT

---

## 2. 两层 API（最重要的概念）

| 层级 | 函数 | 中文别名 | 适用场景 |
|------|------|----------|----------|
| 一步式 | `calibrate_rates()` | `校准合格率()` | 日常使用，自动建目标表、识别分组、数据检查后求解 |
| 专业底层 | `calibrate_pass_rates()` | — | 需要完全控制目标表与求解参数 |
| 辅助 | `make_rate_targets()` | `生成目标表()` | 由 `overall` + `groups` 命名列表构造目标 data.frame |
| 辅助 | `check_calibration_data()` | `检查校准数据()` | 求解前检查权重/0-1结果/分组缺失/目标可支持性 |
| 辅助 | `example_rate_data()` | `生成演示数据()` | 生成含性别/城乡/学历/年龄的模拟数据 |
| 诊断 | `calibration_diagnostics()` | — | 从结果对象提取目标/边际/权重诊断 |

调用链：`calibrate_rates()` → `make_rate_targets()` + `check_calibration_data()` → `calibrate_pass_rates()`（真正的求解器）。

中文别名在 `R/zzz_aliases.R` 中以 `` `校准合格率` <- calibrate_rates `` 形式定义，并在 `NAMESPACE` 中导出。

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

6. **求解失败处理**：若 OSQP status 非 "solved"，抛出中文/英文提示，建议改 soft 或放宽边界。

求解后产出：调整后权重列、单元级倍数、`target_check`（目标达成情况）、`margin_check`（边际保持情况）、
`diagnostics`（样本量、ESS 有效样本量、DEFF 设计效应、倍数范围、触界单元数、最大目标误差）。

返回对象 class 为 `pass_rate_calibration`，配套 S3 方法 `print` / `summary` / `plot`。

---

## 4. 文件地图

```
ratecalib 2/                        # R 包根目录（注意目录名含空格）
├── DESCRIPTION                     # 包元数据、依赖、版本
├── NAMESPACE                       # 导出函数与 S3 方法（手写，未用 roxygen 自动生成）
├── NEWS.md                         # 版本变更记录
├── LICENSE                         # MIT，占位作者信息待替换
├── README.md                       # 中文完整使用手册（理论/算法/参数/诊断/FAQ）
├── README.txt                      # README 的纯文本副本
├── .Rbuildignore                   # 构建时忽略的文件
├── AGENTS.md                       # ← 本文件
├── CONTRIBUTING.md                 # 开发与贡献指南
├── .gitignore                      # Git 忽略规则
├── R/
│   ├── calibrate_pass_rates.R      # ★ 核心求解器（QP 构造 + OSQP + 诊断）
│   ├── easy.R                      # 一步式 calibrate_rates() + check_calibration_data() + example_rate_data()
│   ├── targets.R                   # make_rate_targets() 目标表构造
│   ├── methods.R                   # S3: print/summary/plot + calibration_diagnostics()
│   └── zzz_aliases.R               # 中文函数别名
├── man/                            # .Rd 帮助文档（7 个，与导出函数对应）
├── tests/
│   ├── testthat.R                  # 测试入口
│   └── testthat/test-calibration.R # 软校准与目标构造的单元测试
├── inst/
│   ├── examples/basic_example.R    # 端到端示例脚本
│   └── doc/ratecalib_中文使用手册.pdf
├── dev/                            # 开发辅助脚本（非构建产物）
│   └── dev.R                       # 常用 devtools 工作流
├── docs/
│   └── ARCHITECTURE.md             # 架构与算法详解（图解数据流）
└── .github/
    └── workflows/R-CMD-check.yaml  # CI：多平台 R CMD check
```

★ = 改动风险最高、最该先读的文件。

---

## 5. 数据契约（修改时务必遵守）

**输入 `data`**：data.frame，每行一个样本。
- `outcome` 列：仅含 0/1（或可强转为 0/1 的 logical/factor）；
- `weight` 列：全部有限且严格 > 0；
- `group_vars` 各列：无缺失值（缺失须先编码为显式类别）。

**`targets` data.frame**：列 `variable`、`level`、`target_rate`（0–1），可选 `priority`（正数，soft 模式权重）。
总体目标的 `variable` 用 `.overall`/`overall`/`总体`/`总计`/`TOTAL` 任一，内部统一为 `.overall` + level `.all`。

**返回对象 `pass_rate_calibration`** 关键字段：`data`（含新权重列）、`cell_weights`、`target_check`、
`margin_check`、`diagnostics`、`solver_status`、`solver`、`settings`、`call`。

不变量（测试覆盖）：新权重全部有限且 > 0；`max(abs(margin_check$relative_change)) < 1e-5`。

---

## 6. 开发命令

在包根目录（`ratecalib 2/`）启动 R：

```r
# 一次性安装开发依赖
install.packages(c("devtools", "roxygen2", "testthat", "Matrix", "osqp"))

devtools::load_all()    # 加载包（不安装）
devtools::test()        # 运行 testthat 测试
devtools::check()       # R CMD check（提交前必跑）
devtools::document()    # 若改用 roxygen 自动生成 man/ 与 NAMESPACE
devtools::build()       # 生成 .tar.gz 源码包
```

命令行：

```bash
R CMD build "ratecalib 2"
R CMD check ratecalib_0.2.1.tar.gz --as-cran
```

详见 `dev/dev.R`。

---

## 7. 项目约定（重要）

- **NAMESPACE 当前为手写维护**。`man/*.Rd` 也已存在。源码中虽有 roxygen 风格注释（`#'`），
  但若运行 `devtools::document()` 需先确认 roxygen 注释完整，否则可能覆盖手写的 NAMESPACE/Rd。
  **新增导出函数时，记得同步更新 `NAMESPACE` 和 `man/`。**
- **中英双接口**：底层注释与参数校验信息多为英文，面向用户的一步式接口与打印输出为中文。
  新增面向用户的函数应提供中文别名并在 `zzz_aliases.R` 注册、`NAMESPACE` 导出。
- **soft 是默认模式**，比 exact 更稳健；文档与示例应优先演示 soft。
- **不要改动原始 outcome**：本包哲学是只调权重。任何修改 y 的逻辑都违背设计。
- **目录名含空格**（`ratecalib 2`）：脚本中引用路径需加引号。

---

## 8. 已知占位/待办（TODO）

- [ ] `DESCRIPTION` 的 `Authors@R` 仍是占位（"Your Name" / you@example.com）与 `LICENSE` 的作者占位，需替换为真实信息。
- [ ] `DESCRIPTION` 已补 `URL` / `BugReports` 占位的 GitHub 地址，需改为真实仓库。
- [ ] 测试覆盖较薄：目前仅 soft 模式 + 目标构造。建议补 exact 模式、`check_calibration_data()`、
      边界触界、求解失败路径、S3 方法的测试。
- [ ] `man/` 与源码 roxygen 注释的同步机制需明确（手写 vs 自动生成），避免二者漂移。
- [ ] 可考虑加 vignette（`vignettes/`）替代或补充 `inst/doc` 中的 PDF 手册。
- [ ] `README.txt` 与 `README.md` 是重复内容，需确认是否继续维护两份。
- [ ] 父目录存在 `ratecalib/ratecalib 2/` 的嵌套结构，确认 git 仓库根与包根的关系。

---

## 9. 接手第一步建议

1. 读本文件 → `docs/ARCHITECTURE.md` → `R/calibrate_pass_rates.R`。
2. `devtools::load_all()` 后跑 `inst/examples/basic_example.R` 感受端到端流程。
3. `devtools::test()` 确认基线通过。
4. 再动手改代码。
