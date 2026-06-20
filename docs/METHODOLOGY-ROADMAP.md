# ratecalib 方法论扩展设计方案

本文件是 **Phase 4 的产出**：对 `ratecalib` 方法论扩展的设计方案（**只设计、不实现**）。
每项扩展给出动机、数学形式、提议 API、实现路径、工作量与风险、优先级。
实现前应据此再细化为带验收测试的实施计划。

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

## 一、距离函数族（Deville–Särndal 校准族）— 旗舰扩展 · P1

### 动机
当前目标函数是卡方距离（线性校准），靠箱式约束近似实现「有界」。经典校准估计量
（Deville & Särndal, 1992）是一**族**距离函数；不同距离给出不同的权重比 `g_c = x_c / D_c` 形态：

| 距离 | `G(g)` | 解的形态 `g(η)` | 特点 |
|------|--------|----------------|------|
| 线性 / 卡方（现有） | `(g−1)²/2` | `1 + η` | 可能为负，需箱式约束兜底 |
| raking / 熵 | `g log g − g + 1` | `exp(η)` | **天然为正**、乘性调整、更平滑 |
| logit（有界） | 见 D–S 1992 | `[L(U−1)+U(1−L)e^{Aη}] / [(U−1)+(1−L)e^{Aη}]` | **天然落在 (L,U)**，无需箱约束 |

其中 `η_c = (Aᵀλ)_c` 是单元 c 的对偶线性预测子，`λ` 为各校准约束的拉格朗日乘子，
`A = (U−L)/[(1−L)(U−1)]`。raking/logit 比「卡方+箱约束」更符合校准理论，且权重正性/有界性
是解析保证而非数值裁剪。这是最能把本包从「一个解法」提升为「一类方法」的扩展。

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

- 卡方：`g(η)=1+η`，一步线性求解（与现有 QP exact 等价）。
- raking：`g(η)=exp(η)`，`g'=g`，即经典 IPF/raking 的牛顿形式。
- logit：`g,g'` 按上表，迭代中天然不越界。

### 提议 API
```r
calibrate_pass_rates(..., distance = c("chi2", "raking", "logit"))
# calibrate_rates() 透传同名参数
```
- `distance="chi2"`（默认）：保持现有 OSQP 路径，**完全向后兼容**。
- `distance="raking"`：忽略 `lower`（恒正）；可保留 `upper` 作安全阀（越界则告警/回退）。
- `distance="logit"`：用 `lower/upper` 作为 `L/U`，箱约束改由 `g()` 解析保证。

### 实现路径
1. 抽出「约束装配」：把 `M`、`R` 统一成 `A`（行=约束）与 `t`（右端），现有 QP 路径作为 `distance="chi2"` 分支。
2. 新增对偶 Newton 求解器（纯 R + `Matrix`，无需 OSQP）；`J` 为稀疏对称，可用 `Matrix::solve`。
3. 诊断照旧（ESS/DEFF/触界——logit 改报「接近边界」）。
4. **soft 模式**：raking/logit 的软化＝惩罚校准（ridge / penalized calibration，Guggemos & Tillé 2010）。
   建议**分两步**：先只支持 `distance∈{raking,logit}` 的 **exact** 模式；soft 版本另立子任务。

### 工作量 / 风险
中—高。风险：logit 在目标贴近边界时 Newton 收敛慢/震荡（需阻尼/线搜索）；目标不可行时
对偶发散（需迭代上限 + 清晰报错，复用 exact 的双语提示）。

---

## 二、连续变量的均值 / 总量校准 — P1

### 动机
真实校准常同时校准「人口边际总量」与「某连续变量的总量/均值」（如收入、年龄均值）。
当前 `outcome` 锁死 0/1，只能做合格率。把目标行从

```
Σ x_i · I(组) · (y_i − r) = 0          # 合格率
```
泛化为
```
Σ x_i · I(组) · (z_i − m) = 0          # z 的组内均值 = m
Σ x_i · I(组) · z_i      = T          # z 的组内总量 = T
```
即可覆盖连续指标，核心改动不大。

### 设计要点
- **目标表扩列**：`statistic = c("rate","mean","total")`、`value_var`（被校准的列名；
  `rate`/`mean`/`total` 默认 `value_var=outcome`）。`rate` 是 `mean` 在 0/1 上的特例，保持兼容。
- **聚合改造**（关键）：现聚合键含 `outcome`，使 y 在单元内恒定。改为按**分组交叉单元**聚合，
  每个单元存「充分统计量」：`Σd`（边际用）与每个被校准变量的 `Σ(d·z)`。
  单元级 `zbar_c = Σ(d z) / Σ d`，则组内总量 `= Σ_c x_c·mask·zbar_c`，因 `x_c = g_c·Σd_c` 而
  `g_c·Σ(d z)_c = x_c·zbar_c` 成立，回写无歧义。
- 连续目标与距离族正交：二者都只是「校准方程 `A x = t`」里多/改几行，能与第一节共用对偶求解。

### 提议 API
```r
targets <- data.frame(
  variable = c(".overall", "city"),
  level    = c(".all",     "A"),
  statistic= c("mean",     "total"),
  value_var= c("income",   "income"),
  target   = c(50000,      1.2e9)
)
# 或在 make_rate_targets() 增加 means=/totals= 便捷参数
```
保留 `target_rate` 作为 `statistic="rate"` 的别名列以兼容旧代码。

### 工作量 / 风险
中。风险：聚合层重构触及核心回写逻辑，需新增不变量测试（连续目标达成 + 边际保持）；
`rate` 兼容路径必须回归测试全绿。

---

## 三、目标一致性预检 — P1（高性价比、低风险）

### 动机
固定各组边际总量后，总体合格率＝各组率按组总量的加权平均。用户若同时给总体与分组目标，
**exact 模式可能内在矛盾**，目前只能等 OSQP 报 `primal infeasible`，对用户不友好。

### 设计
求解前计算两类信息（纯线性代数 + 小型 LP，复用聚合结果）：
1. **逐目标可达区间**：组总量固定、单元倍数 ∈[L,U] 时，组内加权率（或均值）的
   最小/最大可达值——上调 y=1 单元至 `U·D`、下调 y=0 单元至 `L·D`（反之取 min）即得闭式区间。
   目标落在区间外 → 标记不可行并给出区间。
2. **总体–分组一致性**：检查 `overall_target ≈ Σ_g 组总量·组目标率 / 总量`；偏离超容差则提示冲突。

### 提议 API
```r
calibration_feasibility(data, outcome, weight, group_vars, targets,
                        lower = 0.25, upper = 4)
# 返回：每个目标的 [min_achievable, max_achievable]、是否可行、
#       以及 overall 与 groups 的一致性诊断
```
可在 `check_calibration_data()` 中顺带调用，或 `calibrate_rates(check=TRUE)` 时自动预警。

### 工作量 / 风险
低—中。风险低，纯诊断，不改求解。收益：把「solver failed」变成「哪几个目标互相冲突、差多少」。

---

## 四、交互目标（cross-classification）— P2

### 动机
现实常要校准「城镇 × 男性」的合格率，当前目标只支持单维 `variable = level`。

### 设计
- 复合 key：`variable = "sex:residence"`、`level = "M:Urban"`，内部按 `:` 拆分、对各分量取交集 mask。
- `make_rate_targets()` 增 `interactions = list(c("sex","residence") = c("M:Urban"=0.7, ...))`。
- 注意：交互目标只新增「目标行」，**不**自动新增边际等式（是否同时固定交互边际由用户显式选择）。

### 工作量 / 风险
低—中。风险：mask 构造与命名解析的边界情形（分隔符冲突——复用现有 `` 思路或改整数编码）。

---

## 五、方差 / 不确定性估计 — P2

### 动机
校准后估计量的方差不同于原始抽样设计。当前只给点估计与 ESS/DEFF，缺正式方差。

### 设计（两条路，可分期）
1. **design-based 线性化方差**：校准估计量近似等于「以校准残差替代原变量」的 HT 估计量方差
   （Deville & Särndal 1992 的残差技术）。需要抽样设计信息（至少一阶包含概率/分层）。
2. **重复权重（replicate weights）**：对每套 BRR/jackknife 重复权重各跑一次校准，由重复估计求方差。
   工程上最稳妥，与 `survey` 包对齐。

### 提议 API
```r
calibrate_replicate_weights(fit, repweights)   # 对已校准对象按重复权重重算
vcov(fit)                                       # 或 S3 方法返回方差
```

### 工作量 / 风险
高。需引入设计信息抽象；建议作为独立里程碑，最后做。

---

## 六、配套接口/工程增强（与方法论并行，低成本）

来自 IMPROVEMENTS.md「三、接口与工程」，实现方法论时顺带做收益高：

- `weights()` / `coef()` / `as.data.frame()` / `predict()` 等标准 S3 提取方法（P1，避免用户手挖 `fit$data`）。
- `keep_solver = FALSE` 选项给返回对象瘦身（P2）。
- 核心求解器内置「不可达组」提示，与 `check_calibration_data()` 对齐（P2）。
- 聚合 key 改 `match()` + 整数编码，免分隔符碰撞且更快（P2）。
- `plot()` 增加 `ggplot2` 选项（放 Suggests，P2）。

---

## 七、建议的实施顺序

按「价值 ÷ 风险」与依赖关系排序：

1. **目标一致性预检（§三）** — 低风险、纯诊断、立即提升 exact 模式体验。先做。
2. **约束装配抽象 + 距离族 exact（§一）** — 旗舰能力；先抽出 `A x = t` 统一层，再加 raking/logit。
3. **连续变量校准（§二）** — 复用 §一的统一层与对偶求解；同步重构聚合为充分统计量。
4. **交互目标（§四）** — 在统一目标行机制上增量。
5. **距离族 soft 版 / 方差估计（§一 soft、§五）** — 较重，独立里程碑。

> 每一步落地前：先写带**验收断言**的测试（达成度、边际保持、向后兼容、错误路径），
> 再实现——延续 Phase 2 已建立的测试基线（exact 达标 / `achieved≈target` / 触界 / 错误路径）。

---

## 参考

- Deville, J.-C., & Särndal, C.-E. (1992). *Calibration Estimators in Survey Sampling.* JASA, 87(418), 376–382.
- Deville, Särndal, & Sautory (1993). *Generalized Raking Procedures in Survey Sampling.* JASA.
- Guggemos, F., & Tillé, Y. (2010). *Penalized calibration in survey sampling.* J. Statist. Plann. Inference.
- R 包 `survey`（Lumley）、`sampling`（Tillé & Matei）作为接口与功能对标。
