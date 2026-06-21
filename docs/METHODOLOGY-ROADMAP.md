# ratecalib 方法论扩展设计方案

本文件是 **Phase 4 的产出**：对 `ratecalib` 方法论扩展的设计方案（**只设计、不实现**）。
每项扩展给出动机、数学形式、提议 API、实现路径、工作量与风险、优先级。
实现前应据此再细化为带验收测试的实施计划。

> 本版已纳入一轮实际使用反馈（2026-06）：默认距离改熵方法、合格率泛化要区分「比例 vs 均值」、
> 增加 Excel 输入输出、进度反馈，以及对「可行性预检到底能给出什么」的批判性澄清。

相关文档：现状与算法见 [`ARCHITECTURE.md`](ARCHITECTURE.md)，已完成的工程改进见
[`IMPROVEMENTS.md`](IMPROVEMENTS.md)，接手概览见 [`../AGENTS.md`](../AGENTS.md)。

---

## 0. 现状回顾（设计的出发点）

当前求解的是一个**有界凸二次规划**（见 ARCHITECTURE.md §3）：

```
minimize  Σ_c (x_c − D_c)² / D_c          # 卡方距离（线性校准）
s.t.      边际等式 M x = margin_rhs        # 总量 + 各分组各水平总量（硬约束）
          [exact] 目标行 R x = 0           # 组内加权合格率 = 目标率
          L·D_c ≤ x_c ≤ U·D_c              # 单元倍数箱式边界
（soft 模式：把目标行 R 以 λ 惩罚并入目标函数，不作硬约束）
```

关键结构：先把个人记录聚合到「分组交叉单元 × 结果状态」，决策变量 `x_c` 是单元调整后总权重。
**下面所有扩展都应尽量复用这套「聚合 + 约束装配 + 求解 + 诊断」骨架。**

把现有约束统一记为「校准方程」`A x = t`：`A` 的每一行是一个约束（边际行或目标行），
`t` 是其目标总量。这一视角是多数扩展的共同抽象。

---

## 一、距离函数族（Deville–Särndal 校准族）— 旗舰扩展 · P1 · 🟡 **部分实现** · ⛔ **默认不改 raking（已决定）**

> **项目决策（2026-06-21）**：**默认距离永久保持 `"chi2"`**，不做"默认改 raking"的破坏性变更。
> raking 与 logit 作为 **opt-in** 长期保留即可。下文一切关于"默认改为熵/raking"的论述仅作历史背景，
> **不再执行**；本节剩余待办因此只剩 soft 版 raking/logit 与 `A x = t` 统一层。

> **实现状态（2026-06）**：新增 `distance = c("chi2", "raking")` 参数（`calibrate_pass_rates()` 与
> `calibrate_rates()` 透传），`package/R/calibrate_pass_rates.R` 内新增 `.calibrate_raking()` 对偶
> Newton 求解器（纯 R + Matrix，回溯线搜索），`test-distance.R` 覆盖（exact 达标、边际保持、恒正、
> 与 chi2 在欠定系统下结果不同、settings 记录、soft 拒绝、不可达不收敛报错）。
> **采取了非破坏性策略**（与下文"默认改 raking"的最终目标不同）：
> - **默认仍 `"chi2"`**，旧行为逐字节保留；raking/logit 为 opt-in，**未跳版本号**。
> - **`"raking"` 与 `"logit"` 均已实现**（exact，对偶 Newton 共用 `.calibrate_dual()`）：
>   raking 上方无界（`lower`/`upper` 不强制，越界倍数在诊断中报告）；logit 倍数解析地恒在
>   `(lower, upper)` 内（要求 `lower < 1 < upper`），即下文"需硬性封顶时首选 logit"。
> - **尚未实现**：soft 版 raking/logit（惩罚校准）、以及把 chi2/raking/logit 统一到 `A x = t` 抽象层
>   （现 chi2 仍走独立 OSQP 分支）。
> - **已决定不做**：把默认改成 raking（破坏性变更，2026-06-21 决定放弃；默认永久 chi2）。

### 动机
当前目标函数是卡方距离（线性校准），靠箱式约束近似实现「有界」。卡方距离的解析解
`g = 1 + η` **可能为负或被边界硬裁剪**，稳健性靠数值约束兜底。经典校准估计量
（Deville & Särndal, 1992）是一**族**距离函数；不同距离给出不同的权重比 `g_c = x_c / D_c` 形态：

| 距离 | `G(g)` | 解的形态 `g(η)` | 取值范围 | 评价 |
|------|--------|----------------|----------|------|
| **raking / 熵（建议默认）** | `g log g − g + 1` | `exp(η)` | `(0, +∞)` | **天然为正**、乘性、平滑；调查校准的稳健常用项 |
| logit（有界） | 见 D–S 1992 | `[L(U−1)+U(1−L)e^{Aη}] / [(U−1)+(1−L)e^{Aη}]` | **`(L, U)`** | 上下界都解析保证，需硬性封顶时首选 |
| 线性 / 卡方（现状，保留兼容） | `(g−1)²/2` | `1 + η` | `(−∞, +∞)` | 可能为负/极端，靠箱约束兜底；OSQP-QP 路径 |

其中 `η_c = (Aᵀλ)_c` 是单元 c 的对偶线性预测子，`λ` 为各校准约束的拉格朗日乘子，
`A = (U−L)/[(1−L)(U−1)]`。

### 默认改为 raking（熵）的理由与**安全边界**
- **理由**：熵距离乘性调整、`g=exp(η)>0` **恒正**，不会出现卡方那种「负权重再裁剪」的隐患，
  是把「正性」做成解析保证而非数值兜底。这是更安全、更符合校准理论的默认。
- ⚠️ **诚实的代价**：raking **上方无界**——目标很激进时个别单元可能被放大到很大的倍数。
  因此默认下仍保留 `upper` 作**安全阀**：超过即告警，并建议改用 `logit`（上下界都封死）。
  换言之：**默认 raking（正性安全）；当「防极端大权重」是硬需求时用 `logit`。**
- ⚠️ **这是破坏性默认变更**：现版本（0.2.1）默认是卡方，结果会变。需在 `NEWS.md` 明确标注，
  并保留 `distance = "chi2"` 复现旧结果。建议随一次 minor 版本号跳变发布。

### 数学与求解
exact 校准等价于求对偶 `λ` 使**校准方程**成立：

```
Σ_c D_c · g(η_c) · a_c = t ,   η_c = a_cᵀ λ        （a_c 是 A 的第 c 列）
```

用 Newton–Raphson 迭代 `λ`：

```
F(λ)   = Σ_c D_c g(η_c) a_c − t
J(λ)   = Σ_c D_c g'(η_c) a_c a_cᵀ
λ ← λ − J⁻¹ F
```

- raking：`g=exp(η)`，`g'=g`，即经典 IPF/raking 的牛顿形式（**默认**）。
- logit：`g,g'` 按上表，迭代中天然不越界。
- 卡方：`g=1+η`，一步线性求解（与现有 QP exact 等价，作 `distance="chi2"` 兼容分支）。

### 提议 API
```r
calibrate_pass_rates(..., distance = c("raking", "logit", "chi2"))   # 默认 raking
# calibrate_rates() 透传同名参数
```
- `distance="raking"`（默认）：忽略 `lower`（恒正）；`upper` 作安全阀（越界告警/建议 logit）。
- `distance="logit"`：用 `lower/upper` 作为 `L/U`，箱约束改由 `g()` 解析保证。
- `distance="chi2"`：保持现有 OSQP 路径，**向后兼容旧结果**。

### 实现路径
1. 抽出「约束装配」：把 `M`、`R` 统一成 `A`（行=约束）与 `t`（右端），现有 QP 路径作为 `distance="chi2"` 分支。
2. 新增对偶 Newton 求解器（纯 R + `Matrix`，无需 OSQP）；`J` 为稀疏对称，可用 `Matrix::solve`，
   配阻尼/线搜索保证收敛。
3. 诊断照旧（ESS/DEFF/触界——logit 改报「接近边界」，raking 额外报「最大倍数 + 是否触安全阀」）。
4. **soft 模式**：raking/logit 的软化＝惩罚校准（ridge / penalized calibration，Guggemos & Tillé 2010）。
   建议**分两步**：先做 raking/logit 的 **exact** 模式；soft 版本另立子任务。

### 工作量 / 风险
中—高。风险：logit/raking 目标贴近边界或不可行时 Newton 收敛慢/发散（需阻尼 + 迭代上限 + 清晰双语报错）；
默认变更影响既有用户（靠 `NEWS.md` 与版本号管理）。

---

## 二、目标统计量泛化：**比例 / 均值 / 总量**（务必区分，处理非 0/1 数据）· P1 · ✅ **已实现**

> **实现状态（2026-06）**：**均值 / 总量已落地**。目标表新增可选列 `statistic`（proportion/mean/total，
> 缺省 proportion，向后兼容）与 `value_var`；mean/total 用单元级充分统计量 `w̄_c = Σ(d·W)/D_c` 在
> **现有单元**上加线性目标行（chi2/raking/logit 均支持，仅 `mode="exact"`）。`make_rate_targets()` 加
> `means`/`totals` 参数；`target_check` 加 `statistic`/`value_var` 列。`test-statistic.R` 覆盖（mean/total
> 达标并从原始权重直验、1/2 编码是均值非比例、raking 非零 rhs 路径、向后兼容回归、soft 拒绝、校验放宽）。
>
> **更新（2026-06-21）：占比泛化已实现**。proportion 目标分离「分组」（variable/level）与「被测量」
> （`value_var`/`value`）；被测量的非 outcome 分类变量加入聚合键 `extra_split_vars` **拆纯单元**，组内占比
> 因此可完全控制。遗留合格率 = `value_var=outcome,value=1` 特例，无额外占比目标时不拆分、逐字节兼容。
> `target_check` 增 `value` 列；重复行判定改为 variable/level/statistic/value_var/value 全键。
> `test-proportion.R` 覆盖（任意分类占比 overall/分组达标并从原始权重直验、1/2 编码是占比非均值、
> 显式 outcome/1 等于遗留路径、非法 value_var 报错、同变量两取值共存）。
>
> **⚠️ 对下文「聚合改造」草图的关键修正（已据此实现）**：下文建议按分组单元聚合、每单元存内部比例 `ā_c`
> 且**不按取值拆单元**——这对 proportion **不成立**：0/1 合格率正是靠**按 outcome 拆纯单元**才能完全控制；
> 若存 `ā_c` 不拆，组率只能在各单元 `ā_c` 凸包内移动，控制力被削弱、破坏兼容。故实现为：
> **连续量（mean/total）用充分统计量（本就无法拆纯单元，凸包控制是标准做法）；分类占比按指示变量拆纯单元**。
>
> **尚余**：mean/total 的 soft 模式；`make_rate_targets()` 的 `proportions=` 便捷接口（现可直接构造目标
> data.frame，含 value_var/value 列）。

### 动机与**关键修正**
当前 `outcome` 锁死 0/1，目标是「合格率」。真实数据常见两类需求，**二者不能混为一谈**：

1. **比例（proportion）**：结果变量并非 0/1，而是任意编码或多分类——例如 **1/2 编码求「等于 1 的占比」**、
   或 `{A,B,C}` 求「类别 A 的占比」。**此时「均值」无法替代「比例」**：`{1,2}` 数据的均值是 1.x，
   而「1 的占比」需要先做**指示变换** `I(z == 取值)` 再校准其加权均值。
2. **连续变量的均值 / 总量**：如收入、年龄的组内均值或总量。

> 现有「合格率」是「比例」在 0/1 + 取值=1 时的特例，必须作为子情形兼容，**不能**退化成「对原始值取均值」。

### 数学（统一为线性目标行，复用 `A x = t`）
设组 G 的掩码为 `mask`，单元 c 的初始权重和 `D_c`、调整后 `x_c`（`x_c = g_c D_c`）。

| 统计量 | 单元级充分统计量 | 目标行（对 x 线性） | 右端 |
|--------|-----------------|---------------------|------|
| **比例**：变量 Z 取值 v 的占比 = p | `ā_c = Σ_{i∈c} d_i·I(Z_i=v) / D_c` | `Σ_c x_c·mask_c·(ā_c − p) = 0` | 0 |
| **均值**：数值 W 的组内均值 = m | `w̄_c = Σ_{i∈c} d_i·W_i / D_c` | `Σ_c x_c·mask_c·(w̄_c − m) = 0` | 0 |
| **总量**：数值 W 的组内总量 = T | `w̄_c` 同上 | `Σ_c x_c·mask_c·w̄_c = T` | T |

线性性成立的关键：`Σ_{i∈c} x_i f(·)_i = g_c Σ_{i∈c} d_i f(·)_i = x_c·(单元级充分统计量)`，
回写无歧义。**比例与均值的差别就在于充分统计量用的是 `I(Z=v)` 还是原始 `W`。**

### 聚合改造（核心，最易出错处）
现聚合键含 `outcome`，使指示值在单元内恒为 0/1。泛化后**不必**把键拆到每个目标变量的每个取值，
而是按「分组交叉单元」聚合，每个单元存所需的**充分统计量向量**：`D_c`（边际用）、
每个比例目标的 `Σ(d·I(Z=v))`、每个数值目标的 `Σ(d·W)`。单元内 `ā_c`、`w̄_c` 可为小数，数学照样成立。

### 提议 API
```r
targets <- data.frame(
  variable  = c("city",       ".overall", "region"),
  level     = c("A",          ".all",     "north"),
  statistic = c("proportion", "mean",     "total"),
  value_var = c("grade",      "income",   "income"),  # proportion: 看 value_var 里等于 value 的占比
  value     = c("1",          NA,         NA),         # proportion 的目标取值（如 1/2 数据里的 "1"）
  target    = c(0.62,         50000,      1.2e9)
)
# 便捷接口：make_rate_targets() 增 proportions=/means=/totals= 参数；
# 旧的 target_rate / overall / groups 作为 proportion(value=1) 的语法糖保留。
```

### 工作量 / 风险
中。风险：聚合层重构触及核心回写逻辑，**必须**新增不变量测试（比例/均值/总量各自达成 + 边际保持 +
0/1 旧路径回归全绿）；务必加一条「1/2 编码求占比 ≠ 均值」的回归测试，防止退化。

---

## 三、目标可行性预检：**能给什么、不能给什么**（批判性澄清）· P1（范围收窄）· ✅ **已实现**

> **实现状态（2026-06）**：已落地为导出函数 `calibration_feasibility()`（`package/R/feasibility.R`），
> 配 `print.ratecalib_feasibility()`，并有 `test-feasibility.R` 覆盖（一致性命中/冲突/部分覆盖不误报、
> 可达区间数值、区间外否决、联合可行声明）。两项检查均按下文设计实现。
> **一处对设计的修正**：下文说「单目标可达区间不是朴素闭式、是小型 LP」——对**当前单维目标结构**而言其实**是闭式**。
> 因为箱界 `[L,U]` 对组内所有单元一致，组总量固定时把单元按通过/不通过分成两块即可解析求解
> （`max_pass = min(U·P, W − L·F)`，`min_pass = max(L·P, W − U·F)`，两段 water-filling）。
> 真正退化成「小型 LP / 需 phase-1」的是**交互/多维目标耦合**（§六），届时再升级。

### 上一版的过度承诺与修正
初版宣称能给每个目标算「闭式可达区间」并据此判定可行。**这有两处不成立**，必须诚实界定：

1. **单目标可达区间不是朴素闭式**：组总量被边际约束固定，各单元权重又互相耦合，
   「上调合格单元、下调不合格单元」与「保持组总量」不能同时取极端——这是一个小型 LP（或 water-filling）。
   可解，但不是「全调到上/下界」那么简单。
2. **更要命：通过所有单目标筛查 ≠ 联合可行**。各目标通过重叠样本互相牵连（一个单元同属多个分组 + 边际），
   单目标边际区间只是**必要条件**，不是充分条件。真正的充分判定＝做一次 phase-1 LP 可行性，
   其代价≈直接求解。

### 因此，预检真正**有价值**的是这两件确定性的事
1. **总体–分组一致性恒等式（确定性，强烈推荐）**：若某个分组变量的**每个水平**都同时有
   「固定边际总量」和「exact 比例目标」，则**总体比例被唯一确定** = `Σ_ℓ 边际总量_ℓ·目标_ℓ / 总量`。
   用户若再给一个对不上的总体目标，或给了两个各自确定却互相矛盾的变量目标——这能在求解前**精确**抓出。
   这是最常见的用户错误，且判定是闭式、零成本。
2. **单目标边际必要筛查（一票否决）**：对每个目标解上述小 LP，得 `[min, max]` 可达区间；
   目标落在区间外 → **必定**不可行，明确报出（必要条件，能否决、不能保证）。

### 对 soft 模式的定位
soft 永远有解，预检在此**纯信息性**：预告「哪些目标大概率达不到、差多少、为什么」（如某组全 0/全 1、
边际必要区间太窄），帮助用户解读结果，而非判定成败。

### 提议 API
```r
calibration_feasibility(data, outcome/targets..., lower, upper)
# 返回：
#   $consistency  —— 总体与各「完整目标变量」的隐含比例是否一致（确定性，闭式）
#   $marginal     —— 每个目标的 [min_achievable, max_achievable] 与是否落区间外（必要筛查）
#   $note         —— 明确声明：通过 ≠ 联合可行；exact 的最终判定仍以求解为准
```
可在 `check_calibration_data()` 内顺带调用。

### 工作量 / 风险
低—中。价值集中在「一致性恒等式」（高频错误、确定性、便宜）。务必在文档与返回值里**写明边界**，
不可让用户误以为「预检通过＝一定能解」。

---

## 四、Excel 数据输入 / 输出兼容 · P1（实用价值高、独立、低风险）· ✅ **已实现**

> **实现状态（2026-06）**：已落地 `read_calibration_data()`、`read_targets_xlsx()`、
> `calibrate_from_excel()`、`export_calibration_xlsx()`（`package/R/excel.R`），`openxlsx` 走
> `Suggests` + `requireNamespace()` 守卫，`test-excel.R` 以真实 `.xlsx` 往返覆盖。
> 表头容错支持英文别名与中文表头；为遵守「R 代码纯 ASCII」铁律，中文别名在源码中用
> `intToUtf8()` 码点构造（源码零非 ASCII 字节）。目标表 schema 对齐当前实现
> （`variable/level/target_rate[/priority]`）；§二 的扩展列（statistic/value/value_var）待 §二 落地后再加。
> CSV 零依赖兜底尚未做（按需补）。

### 动机
真实用户的数据与目标率清单**载体往往是 Excel**（`.xlsx`），而非 R 里的 data.frame。
目标率常由业务方在电子表格里维护，结果也需回写成可分发的工作簿。降低「进/出 R」的摩擦，实用收益大。

### 设计
- **读入**：
  - `read_calibration_data(path, sheet)` —— 读样本数据为 data.frame。
  - `read_targets_xlsx(path, sheet)` —— 把含 `variable/level/statistic/value/target/priority` 列的
    工作表直接读成目标表（列名容错、中英表头映射）。
  - 便捷封装 `calibrate_from_excel(path, data_sheet, targets_sheet, ...)`：一步读数据+目标并求解。
- **导出**：
  - `export_calibration_xlsx(fit, path)` —— 写**多工作表**工作簿：`data`（含校准权重）、
    `target_check`、`margin_check`、`diagnostics`、`settings`，可加简单条件格式（如误差超阈值标红）。
- **依赖策略（保持核心轻量）**：Excel 能力一律走 **`Suggests`**，运行时 `requireNamespace()` 守卫，
  缺失则报「请 install.packages(...)」。推荐 **`openxlsx`**（无 Java、读写双向、可设样式，单一依赖）；
  CSV 路径作零依赖兜底（注意 UTF-8/BOM，中文表头建议 `fileEncoding="UTF-8"`）。

### 工作量 / 风险
低—中。纯 I/O 包装，不碰核心算法，可独立交付。风险：Excel 表头/类型不规范（空格、合并单元格、
数字存成文本）——读入需做清洗与明确报错。

---

## 五、进度反馈（进度条）· P2（是否需要 + 能否实现的判断）

### 结论先行：**分情况，且收益主要在「循环/迭代」场景**
- **单次 OSQP 求解（现状主路径）**：求解在一次 C 调用内完成，**无法给真正的百分比进度条**；
  只能透传 `verbose`（OSQP 迭代日志）或显示一个「solving…」spinner。而且因为先聚合、变量数 m 通常很小，
  这一步往往很快，进度条收益有限。
- **对偶 Newton（raking/logit，§一）**：是 R 里的显式迭代循环，**可**按迭代数/残差下降显示进度
  （虽通常几步就收敛，意义一般）。
- **真正值得做进度条的：外层循环**——
  - **重复权重方差（§七）**：对 N 套 replicate weights 各跑一次完整校准 → 天然的 N 步进度条。
  - **批量处理多张 Excel / 多套目标场景（§四）** → 同理。

### 设计
- 加 `progress = TRUE` 选项；用 `cli::cli_progress_bar()`（现代、自动节流）或基础 `utils::txtProgressBar`，
  `cli` 放 `Suggests`。
- 仅在**外层循环**（replicate / batch）真正驱动进度条；单次求解只提供 spinner + `verbose`。

### 工作量 / 风险
低。属打磨项，建议**搭着 §七 重复权重或 §四 批量处理一起做**，单独为单次求解做进度条性价比低。

---

## 六、交互目标（cross-classification）· P2 · ✅ **已实现**

> **实现状态（2026-06）**：`calibrate_pass_rates()` 内新增 `build_mask()` 辅助，识别冒号复合 key
> 并对各分量取交集；`make_rate_targets()` 新增 `interactions` / `interaction_priority` 参数；
> `test-interaction.R` 覆盖（make 构造、exact 达标并从原始权重直验语义、soft 可用、非分组变量报错、
> 分量数不匹配报错）。**API 修正**：设计稿写的 `list(c("sex","residence") = ...)` 不是合法 R（列表名须为
> 字符串），实现改用冒号连接的字符串名 `list("sex:residence" = c("M:Urban" = 0.7))`，与内部 key 一致。
> **边界**：水平值本身不可含冒号；交互目标尚未接入 `check_calibration_data()` / `calibration_feasibility()`
> （那两者按单维变量处理，遇交互 key 会误判，故交互目标目前走 `calibrate_pass_rates()` 直连路径）。

### 动机
现实常要校准「城镇 × 男性」的比例，当前目标只支持单维 `variable = level`。

### 设计
- 复合 key：`variable = "sex:residence"`、`level = "M:Urban"`，内部按 `:` 拆分、对各分量取交集 mask。
- `make_rate_targets()` 增 `interactions = list("sex:residence" = c("M:Urban"=0.7, ...))`（已实现）。
- 注意：交互目标只新增「目标行」，**不**自动新增边际等式（是否同时固定交互边际由用户显式选择）。
- 与 §二 正交：交互目标同样可是 proportion / mean / total（待 §二 落地后）。

### 工作量 / 风险
低—中。风险：mask 构造与命名解析的边界情形（分隔符冲突——复用现有 `` 思路或改整数编码）。

---

## 七、方差 / 不确定性估计 · P2

### 动机
校准后估计量的方差不同于原始抽样设计。当前只给点估计与 ESS/DEFF，缺正式方差。

### 设计（两条路，可分期）
1. **design-based 线性化方差**：校准估计量近似等于「以校准残差替代原变量」的 HT 估计量方差
   （Deville & Särndal 1992 的残差技术）。需要抽样设计信息（至少一阶包含概率/分层）。
2. **重复权重（replicate weights）**：对每套 BRR/jackknife 重复权重各跑一次校准，由重复估计求方差。
   工程上最稳妥，与 `survey` 包对齐；**这正是 §五 进度条的天然落点**。

### 提议 API
```r
calibrate_replicate_weights(fit, repweights, progress = TRUE)  # 对已校准对象按重复权重重算
vcov(fit)                                                       # 或 S3 方法返回方差
```

### 工作量 / 风险
高。需引入设计信息抽象；建议作为独立里程碑，最后做。

---

## 八、配套接口 / 工程增强（与方法论并行，低成本）

来自 IMPROVEMENTS.md「三、接口与工程」，实现方法论时顺带做收益高：

- `weights()` / `coef()` / `as.data.frame()` / `predict()` 等标准 S3 提取方法（P1，避免用户手挖 `fit$data`）。
- `keep_solver = FALSE` 选项给返回对象瘦身（P2）。
- 核心求解器内置「不可达组」提示，与 `check_calibration_data()` 对齐（P2）。
- 聚合 key 改 `match()` + 整数编码，免分隔符碰撞且更快（P2）。
- `plot()` 增加 `ggplot2` 选项（放 Suggests，P2）。

---

## 九、建议的实施顺序（按反馈调整后）

按「价值 ÷ 风险」与依赖关系排序：

1. ~~**目标可行性预检（§三，收窄版）**~~ ✅ **已实现**（`calibration_feasibility()`）——确定性「一致性恒等式」+ 单目标可达区间，提升 exact 体验。
2. 🟡 **约束装配抽象 + 距离族，默认 raking（§一）** — **部分实现**：raking 熵距离与 logit 有界距离
   （exact，对偶 Newton）已作为 opt-in 落地（默认仍 chi2，非破坏性）；**剩余**：soft 版 raking/logit、
   以及把 chi2/raking/logit 统一到 `A x = t` 抽象层。（默认改 raking 已决定放弃，见 §一 顶部。）
3. ✅ **目标统计量泛化：比例/均值/总量（§二）** — **已实现**：均值/总量（充分统计量）+ 任意分类变量占比
   （按指示变量拆纯单元）+ `make_rate_targets(means=/totals=)`；**仅余** mean/total 的 soft 模式与
   `proportions=` 便捷接口。
4. ~~**Excel 输入输出（§四）**~~ ✅ **已实现**（`read/export` + `calibrate_from_excel()`，openxlsx 走 Suggests）。
5. ~~**交互目标（§六）**~~ ✅ **已实现**（冒号复合 key + `make_rate_targets(interactions=)`；仅目标行，不加边际）。
6. **方差估计 + 重复权重（§七）**，**搭配进度条（§五）** — 较重，独立里程碑收尾。

> 每一步落地前：先写带**验收断言**的测试（达成度、边际保持、向后兼容、错误路径、
> 「比例≠均值」回归），再实现——延续 Phase 2 已建立的测试基线。
> 凡涉及默认/接口变更（如 §二 目标表扩列），同步更新 `NEWS.md` 与版本号。
> （注：§一"默认改 raking"已于 2026-06-21 决定放弃，默认永久 chi2。）

---

## 参考

- Deville, J.-C., & Särndal, C.-E. (1992). *Calibration Estimators in Survey Sampling.* JASA, 87(418), 376–382.
- Deville, Särndal, & Sautory (1993). *Generalized Raking Procedures in Survey Sampling.* JASA.
- Guggemos, F., & Tillé, Y. (2010). *Penalized calibration in survey sampling.* J. Statist. Plann. Inference.
- R 包 `survey`（Lumley）、`sampling`（Tillé & Matei）作为接口与功能对标；`openxlsx` 作为 Excel I/O 对标。
