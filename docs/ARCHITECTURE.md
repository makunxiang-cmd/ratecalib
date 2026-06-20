# ratecalib 架构与算法说明

本文件详解数据如何流经各函数，以及核心二次规划（QP）问题如何构造。
速览见 [`AGENTS.md`](../AGENTS.md)。

---

## 1. 模块依赖关系

```
                 用户输入
                    │
       ┌────────────┴─────────────┐
       │  calibrate_rates()  (easy.R, 一步式中文接口)
       │  ├── make_rate_targets()        (targets.R)   生成目标表
       │  ├── check_calibration_data()   (easy.R)      求解前体检
       │  └── calibrate_pass_rates()     ★核心求解器
       └────────────┬─────────────┘
                    │
       calibrate_pass_rates()  (calibrate_pass_rates.R)
                    │
        ┌───────────┼────────────┐
   聚合降维      QP 构造        OSQP 求解
                    │
       返回 pass_rate_calibration 对象
                    │
       ┌────────────┼─────────────┐
   print()      summary()       plot()        (methods.R)
   calibration_diagnostics()                  (methods.R)

   中文别名：校准合格率 / 生成目标表 / 检查校准数据 / 生成演示数据  (zzz_aliases.R)
```

★ `calibrate_pass_rates()` 是唯一真正做数学的地方；其余都是包装、校验、展示。

---

## 2. 端到端数据流

```
个人记录 data (n 行)
   │  outcome(0/1) · weight(>0) · group_vars(无缺失)
   ▼
[1] 校验      列存在性、权重正性、0/1 结果、分组无缺失、目标率∈[0,1]
   ▼
[2] 聚合      key = 分组交叉  结果状态(0/1)，按 key 对 weight 求和
   │          得到 m 个「单元」，每个单元一个初始权重总和 D_c
   ▼
[3] 建约束    M：边际总量等式（总量 + 各分组各水平）
   │          R：目标合格率线性化行
   ▼
[4] 建目标    P = diag(2/D)，q = -2  （soft 模式额外把 R 罚入 P）
   ▼
[5] 求解      OSQP 解有界 QP，得每个单元的调整后总权重 x_c
   ▼
[6] 回写      倍数 g_c = x_c / D_c，按 key 映射回每条个人记录
   │          new_weight = old_weight × g_c
   ▼
[7] 诊断      target_check / margin_check / diagnostics
   ▼
pass_rate_calibration 对象
```

**为什么聚合**：优化变量数从 n（样本量，可达数十万）降到 m（观测到的单元数，通常几百），
QP 规模与求解时间随之大幅下降。同一单元内所有个体共享同一倍数，因此回写无歧义。

---

## 3. QP 问题的精确形式

记 `m` 为单元数，`D_c` 为单元 c 的初始权重总和，决策变量 `x_c` 为调整后权重总和。

### 目标函数

最小化对初始权重的卡方型偏离：

```
minimize  Σ_c (x_c − D_c)² / D_c
```

OSQP 标准形式 `0.5 xᵀP x + qᵀx`：

```
P = diag(2 / D_c)        q = (−2, −2, …, −2)ᵀ
```

（展开 `(x−D)²/D = x²/D − 2x + D`，常数 D 不影响最优解。）

### 硬约束 M —— 始终保持人口边际

```
总量：     Σ_c x_c = Σ_c D_c                       (grand_total)
分组水平： Σ_c x_c·I(单元c属于 变量v=水平ℓ) = 该水平初始总量
```

对每个分组变量，**去掉最后一个观测水平**以避免与总量约束线性相关（共线）。
这组等式保证校准只在边际内部重新分配，不改变任何边际总量
（验证：`margin_check$relative_change ≈ 0`）。

### 目标行 R —— 合格率约束

「组内加权合格率 = 目标率 r」可线性化为：

```
Σ_i x_i · I(i∈组) · (y_i − r) = 0
```

在单元层级即 `Σ_c x_c · mask_c · (outcome_c − r) = 0`。

- **soft 模式（默认）**：不作硬约束，而是把 R 以惩罚加入目标：
  `P ← P + 2·Rᵀ W R`，其中 `W = diag(λ · grand_total · priority_j / size_j²)`。
  越偏离目标罚越大，`priority` 调相对重要性，`size_j²` 归一化使不同规模的组可比。
  优点：永远有解，对相互矛盾的目标做加权折中。

- **exact 模式**：把 R 作为等式硬约束（`l = u = 0`）。
  目标精确达成，但若目标互相矛盾或边界过窄会无解（OSQP 返回非 solved，函数报错并建议改 soft / 放宽边界）。

### 边界约束

每个单元的调整倍数受限：

```
lower ≤ x_c / D_c ≤ upper        默认 [0.25, 4]
```

即 `lower·D_c ≤ x_c ≤ upper·D_c`，用单位矩阵行实现。

### 约束矩阵装配

```
soft：   A = [ M ; I ]           l = [margin ; lower·D]    u = [margin ; upper·D]
exact：  A = [ M ; R ; I ]       l = [margin ; 0 ; lower·D] u = [margin ; 0 ; upper·D]
```

P 经 `forceSymmetric` 转上三角对称的 `dgCMatrix`，OSQP 设置高精度
（eps 1e-8、polishing、max_iter 1e5）。

---

## 4. 输出对象字段

| 字段 | 内容 |
|------|------|
| `data` | 原始 data 加上校准后权重列（`new_weight`） |
| `cell_weights` | 单元级：分组键、结果、初始/调整总量、倍数、是否触界 |
| `target_check` | 每个目标的 目标率/初始率/校准后率/误差/绝对误差/优先级 |
| `margin_check` | 总体与各分组各水平的 初始总量/调整总量/相对变化 |
| `diagnostics` | 样本量、单元数、ESS、DEFF、倍数 min/中位/max、触界数、最大目标误差 |
| `solver_status` | OSQP 状态字符串 |
| `solver` | OSQP 原始返回 |
| `settings` | 本次调用的参数 |
| `call` | `match.call()` |

**ESS（有效样本量）** `= (Σw)² / Σw²`，**DEFF（设计效应）** `= 1 + (sd(w)/mean(w))²`，
用于量化校准对权重离散度（即统计效率）的影响。

---

## 5. 关键实现注意点

- **分隔符**：聚合键用控制字符 ``（``）拼接，避免与数据中普通字符冲突。
- **总体目标识别**：`variable` 为 `.overall`/`overall`/`总体`/`总计`/`TOTAL` 之一即视为总体，内部统一成 `.overall` + `.all`。
- **soft 惩罚的量纲**：`λ·grand_total·priority/size²` 让惩罚与目标函数量纲匹配，默认 `λ=1e4`。
- **回写映射**：用单元键 → 倍数的命名向量，按每条记录的键查表得到个体倍数。
- **错误信息双语**：底层校验偏英文，一步式接口与展示偏中文。
