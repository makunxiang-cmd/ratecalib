# ratecalib 通俗使用说明（不懂编程也能看懂）

这份说明用大白话讲清楚：这个工具是干什么的、能帮你解决什么问题、你要准备什么、
结果怎么看。**全程不需要你懂 R 语言或写代码**——真正运行时，只要把准备好的 Excel
交给会跑一两行命令的同事（或按最后一节照抄即可）。

---

## 一、一句话：它在做什么

> **在不改动任何人答案的前提下，调整每个样本"代表多少人"，让加权后的各项比例对上你已知的目标。**

打个比方。你做了一次调查，收回 5000 份问卷。但样本往往和真实人口对不上——
比如真实人口男女各半，你的样本却男少女多。这时我们不会去伪造问卷，而是给每个人一个
**权重**，意思是"这个人代表现实中的多少人"。男性偏少，就让每个男性多代表几个人。

`ratecalib` 干的就是**精细地调这些权重**：让加权之后算出来的"合格率"既符合总体目标，
也符合各个分组（性别、城乡、学历、年龄……）的目标——而且**绝不改动每个人是否合格这个事实**。

---

## 二、它专门解决的问题

设想这样一个场景：

- 你有一份名单，每人一行；
- 每个人有个**是否合格**的标记（合格=1，不合格=0）；
- 每个人有个**初始权重**（代表多少人）；
- 你从外部（官方统计、上级要求等）知道一些**目标合格率**，例如：
  - 总体合格率应为 **70%**；
  - 男性 **72%**、女性 **68%**；
  - 城镇 **71%**、农村 **68.5%**；
  - 各学历段、各年龄段也各有目标。

直接的难题是：**性别、城乡、学历、年龄是相互交叉重叠的**。一个人同时是"男性 + 城镇 +
本科 + 30 岁段"。你调他的权重，会同时牵动好几个目标。手动一个一个组去凑，往往按下葫芦
浮起瓢——刚调好男性，城乡又歪了。

`ratecalib` 用数学方法**同时兼顾所有目标**，一次性算出每个人最合适的权重。

---

## 三、它的三条核心原则（很重要，决定了它"靠谱"在哪）

1. **不改原始答案，只调权重。**
   合格的人还是合格，不合格的还是不合格。变的只是每个人的"话语权/代表人数"。

2. **尽量少动原来的权重结构。**
   它不会乱来，而是在"达到目标"的前提下，让权重相对初始值改动**最小**。

3. **保持各群体的总规模不变。**
   比如男性原本代表 10000 人，调完还是 10000 人；只是男性内部"合格的人"和"不合格的人"
   之间的权重此消彼长，从而改变男性的合格率。这样可以防止为了凑合格率而把男女、城乡的
   人口盘子改大改小。

---

## 四、你需要准备什么

只要两样东西，都可以用 **Excel** 准备：

### 1）样本数据表（一个工作表）

每行一个人，至少包含这些列（列名你可以自定，运行时告诉程序即可）：

| 性别 sex | 城乡 residence | 是否合格 qualified | 初始权重 initial_weight |
|---|---|---|---|
| M | Urban | 1 | 1.2 |
| F | Rural | 0 | 0.8 |
| … | … | … | … |

- "是否合格"列**只能填 0 或 1**；
- "初始权重"列必须都是**正数**；
- 分组列（性别、城乡等）**不能有空白**——没填的要先归成一个明确类别（如"未知"）。

### 2）目标表（另一个工作表）

告诉程序每个分组的目标合格率长什么样：

| variable（变量） | level（类别） | target_rate（目标率） |
|---|---|---|
| .overall | .all | 0.70 |
| sex | M | 0.72 |
| sex | F | 0.68 |
| residence | Urban | 0.71 |
| residence | Rural | 0.685 |

- `.overall` / `.all` 这一行代表**总体**目标；
- 目标率是 0 到 1 之间的小数（70% 写成 0.70）；
- 表头支持中文（如"变量/类别/目标率"），程序能自动识别。

把这两个工作表放进同一个 Excel 文件即可。

---

## 五、怎么真正跑起来（最省事的 Excel 方式）

非编程用户最方便的方式是"从 Excel 进、从 Excel 出"。请会用 R 的同事（或你自己照抄）
运行下面这几行——**只需改文件名和列名**：

```r
library(ratecalib)

result <- calibrate_from_excel(
  "你的输入文件.xlsx",      # 准备好的 Excel
  outcome = "qualified",    # "是否合格"那一列的列名
  weight  = "initial_weight", # "初始权重"那一列的列名
  data_sheet    = "data",     # 样本数据所在工作表名
  targets_sheet = "targets"   # 目标表所在工作表名
)

# 把结果（含校准后新权重 + 各种核对表）导出成一个新的 Excel
export_calibration_xlsx(result, "校准结果.xlsx")
```

> 说明：上面的 `result` 只是给结果起的名字，可随意改成别的英文名。
> 注意本工具的**函数名和参数名都是英文**（如 `calibrate_from_excel`、`outcome`），
> 这些不能改成中文；你自己起的变量名虽然在中文系统里也能用中文，但为了在各种电脑上都不出错，
> 建议统一用英文。

跑完你会得到一个 **`校准结果.xlsx`**，里面有好几个工作表（下一节解释怎么看）。

> 安装：第一次使用前，请同事运行 `install.packages(c("Matrix","osqp","openxlsx"))`。

---

## 六、结果怎么看（重点看这三张表）

打开导出的 `校准结果.xlsx`：

### 1）`data`：带新权重的明细
和你的原始数据一样，但**多了一列校准后权重**（默认列名 `weight_calibrated`）。
以后做任何加权统计，用这一列即可。

### 2）`target_check`：目标达成情况（最该看的一张）

| 字段 | 含义 |
|---|---|
| `target_rate` | 你设定的目标 |
| `initial_rate` | 校准**前**的加权合格率 |
| `achieved_rate` | 校准**后**的加权合格率 |
| `error` / `abs_error` | 校准后与目标的差距（越接近 0 越好） |

一眼就能看出每个目标"达到没有、差多少"。

### 3）`diagnostics`：权重质量体检

最该关心两个：

- **`calibrated_ESS`（有效样本量）**：可以理解为"调权重之后，你的样本相当于多少个'等分量'的人"。
  这个数比原始样本量低是正常的；如果**降得太多**，说明为了凑目标，权重被拉得很极端，
  统计结论会变"虚"。
- **`maximum_multiplier` / `minimum_multiplier`（最大/最小放大倍数）**：每个人权重最多被放大/缩小
  到几倍。如果有人被放大到很离谱的倍数，要警惕。

---

## 七、几个常见疑问（大白话版）

**Q：为什么有时候"精确达到目标"会失败？**
因为你给的目标可能**自相矛盾**或**根本做不到**。常见原因：
- 总体目标和分组目标对不上（比如各组目标按人数加权根本算不出你写的总体数）；
- 某个组里的人**全合格或全不合格**——光调权重永远改变不了这个组的合格率；
- 权重上下限卡得太死。

遇到这种情况，换成"软模式"（见下）通常就能出结果。程序还附带一个**事前体检**功能，
能在开算前就提示"你这几个目标互相打架"。

**Q：什么是"软模式"和"精确模式"？**
- **精确模式**：要求所有目标**分毫不差**地达到。目标稍有矛盾就会失败。
- **软模式（推荐，默认）**：允许目标之间有一点小矛盾，程序会**尽量靠近**所有目标，
  在冲突时按你设的"优先级"权衡。真实数据建议用软模式，因为各处来的目标率本就常有
  舍入或口径差异。

**Q：什么是"优先级"？**
当目标互相冲突、不能全满足时，优先级高的目标会被**优先照顾**。它不是"必须达到"的开关，
而是"谁更重要"的相对权重。

**Q：权重上下限是干嘛的？**
限制每个人权重最多被放大/缩小几倍（默认在 0.25 到 4 倍之间）。
- 卡得越窄：权重越稳健，但目标可能差得多；
- 放得越宽：目标更容易达到，但可能出现极端权重、样本"变虚"。

**Q：目标率可以是我自己拍脑袋定的吗？**
技术上可以，但**解释时要诚实**。如果目标来自可靠的外部总体数据，校准后的结果可以说是
"在已知总体信息约束下的估计"；如果目标只是你的期望值，那校准后的合格率**主要是被你设出来的**，
不能再当成"独立发现的结论"去汇报。

---

## 八、它还能做的进阶事情（按需了解）

除了上面的"合格率"，这个工具还支持：

- **校准任意比例**：不止 0/1 合格率，也能校准"某个类别占多少比例"（比如"评级为 A 的占 40%"）。
- **校准平均数或总量**：比如让"加权平均收入"达到某个数，或"某地区总收入"达到某个数。
- **交叉分组目标**：比如专门校准"城镇男性"这一交叉群体的合格率。
- **不确定性评估**：配合"重复权重"估计结果的标准误（衡量结论有多稳）。
- **求解前体检**：开算前检查目标有没有自相矛盾、哪些大概率达不到。

这些都属于专业功能，需要时让懂 R 的同事查阅项目根目录的 `README.md` 第十四节即可。

---

## 九、一句话总结

把"每行一个人、带是否合格和初始权重"的数据，连同"各分组目标合格率"一起交给它，
它会**只动权重、不动答案**地算出一套新权重，让加权结果尽量贴合所有目标，
并给你一张"达成情况表"和"权重质量体检表"让你判断结果可不可信。

---
---

# 第二部分：全量使用说明（由浅入深）

上面是"够用就好"的入门。下面是完整说明：先把**所有用法**讲清楚，再用**带数字的实例**走一遍，
然后解释背后的**数学原理**，最后给一张**问题速查表**。看不懂数学那节可以跳过，不影响使用。

---

## 十、完整使用方法

### 10.1 安装

```r
install.packages(c("Matrix", "osqp"))   # 必装：矩阵运算 + 求解器
install.packages("openxlsx")            # 选装：Excel 读写
# 然后安装本包（本地源码包）：
install.packages("ratecalib_0.2.1.tar.gz", repos = NULL, type = "source")
library(ratecalib)
```

### 10.2 两层接口：先选对入口

| 接口 | 适合谁 | 特点 |
|---|---|---|
| `calibrate_rates()` | 大多数人 | **一步式**：给数据、目标率，自动建目标表、识别分组、做检查、求解 |
| `calibrate_pass_rates()` | 需要完全掌控的人 | **专业底层**：自己准备目标表，控制全部求解参数 |
| `calibrate_from_excel()` | 不写代码的人 | 从 Excel 读数据+目标，一步出结果（见第五节） |

`calibrate_rates()` 内部其实就是"自动建好目标表后调用 `calibrate_pass_rates()`"。

### 10.3 一步式 `calibrate_rates()` 的全部参数

```r
fit <- calibrate_rates(
  data    = dat,               # 数据框，每行一个人
  outcome = "qualified",       # 0/1 结果列名
  weight  = "initial_weight",  # 正的初始权重列名
  overall = 0.70,              # 总体目标率（可省略 = 不设总体目标）
  groups  = list(              # 各分组目标：列表，名字是分组变量
    sex       = c(M = 0.72, F = 0.68),
    residence = c(Urban = 0.71, Rural = 0.685)
  ),
  priority       = 5,                       # 总体目标的优先级
  group_priority = c(sex = 2, residence = 2), # 各分组目标优先级（也可写一个数）
  lower = 0.25, upper = 4,     # 权重最多缩到 0.25 倍、放大到 4 倍
  mode  = "soft",              # "soft"（默认，推荐）或 "exact"
  distance = "chi2",           # 校准距离，见 11.1（默认 chi2）
  lambda = 1e4,                # 软模式惩罚强度，越大越逼近目标
  new_weight = "weight_calibrated", # 新权重列叫什么名
  check = TRUE                 # 求解前是否自动检查数据（默认是）
)
```

每个参数的通俗含义见第六、七节与 11.1。

### 10.4 自己构造目标表 `make_rate_targets()`

专业接口要先有"目标表"。用 `make_rate_targets()` 拼出来最省事：

```r
targets <- make_rate_targets(
  overall = 0.70,
  groups  = list(sex = c(M = 0.72, F = 0.68)),
  # 进阶（按需）：
  interactions = list("sex:residence" = c("M:Urban" = 0.75)),   # 交互目标，见 11.2
  means        = data.frame(variable=".overall", level=".all",
                            value_var="income", target=52000),   # 均值目标，见 11.3
  totals       = data.frame(variable="residence", level="Urban",
                            value_var="income", target=1.2e8),    # 总量目标
  proportions  = data.frame(variable=".overall", level=".all",
                            value_var="grade", value="A", target=0.40) # 占比，见 11.4
)
```

它返回一张普通的数据表（每行一个目标），你也可以直接在 Excel/R 里手工拼这张表。
列的含义：`variable`（分组变量，总体用 `.overall`）、`level`（类别，总体用 `.all`）、
`target_rate`（目标值）、`priority`（优先级，可省）、以及进阶列 `statistic`/`value_var`/`value`。

### 10.5 求解前：数据检查 + 可行性预检

```r
# 数据质量检查：列是否齐、权重是否为正、结果是否 0/1、分组有无缺失、目标是否可支持
check_calibration_data(dat, "qualified", "initial_weight",
                       group_vars = c("sex","residence"), targets = targets)

# 可行性预检：求解前判断目标有没有"自相矛盾"，以及每个目标能不能够得着
calibration_feasibility(dat, "qualified", "initial_weight",
                        group_vars = "sex", targets = targets)
```

可行性预检会告诉你：分组目标隐含的总体率是否和你写的总体目标一致（不一致＝精确模式必失败），
以及每个目标在权重上下限内的"可达区间"。

### 10.6 专业接口 `calibrate_pass_rates()`

```r
fit <- calibrate_pass_rates(
  data = dat, outcome = "qualified", weight = "initial_weight",
  group_vars = c("sex","residence","education5","age5"),  # 要保持边际的所有分组变量
  targets = targets,
  lower = 0.25, upper = 4, mode = "soft", distance = "chi2", lambda = 1e4
)
```

注意 `group_vars` 要列出**所有需要保持人口边际的分组变量**，哪怕它没有目标率——
列进来就会保证它的各类别人口规模不变。

### 10.7 读懂返回结果

`fit` 是一个结果对象，重要部分：

| 取法 | 内容 |
|---|---|
| `fit$data` 或 `as.data.frame(fit)` | 原数据 + 新权重列 |
| `weights(fit)` | 直接取校准后权重向量 |
| `fit$target_check` | 每个目标的目标值/校准前后值/误差（最常看） |
| `fit$margin_check` | 人口边际是否保持（`relative_change` 应≈0） |
| `fit$diagnostics` | 权重质量体检（ESS、放大倍数、触限单元数…） |
| `summary(fit)` / `print(fit)` | 摘要打印 |
| `plot(fit, "target_error")` / `plot(fit, "multipliers")` | 误差图 / 倍数分布图 |

---

## 十一、进阶目标类型

### 11.1 校准距离：chi2 / raking / logit

`distance` 参数控制"用什么尺子衡量权重改动"，三选一：

| `distance` | 通俗理解 | 什么时候用 |
|---|---|---|
| `"chi2"`（默认） | 加减式微调，靠上下限防极端 | 一般默认；软/精确都行 |
| `"raking"` | 乘法式微调，权重**天生不会变负**，但上方没封顶 | 想要稳健的正权重 |
| `"logit"` | 权重严格卡在 `(lower, upper)` 之间出不去 | 必须**硬性封顶**极端权重时（要求 lower<1<upper） |

```r
calibrate_pass_rates(..., distance = "raking")   # 或 "logit"
```

> 默认永远是 `chi2`，结果和旧版一致；另外两种是可选项。

### 11.2 交互（交叉分组）目标

校准"城镇 × 男性"这种交叉群体，用冒号连接：

```r
make_rate_targets(interactions = list("sex:residence" = c("M:Urban" = 0.75, "F:Rural" = 0.62)))
```

### 11.3 均值 / 总量目标（连续变量）

不只 0/1，还能让某个**数值变量**的加权均值或总量达到目标（如收入）：

```r
make_rate_targets(
  means  = data.frame(variable=".overall", level=".all", value_var="income", target=52000),
  totals = data.frame(variable="residence", level="Urban", value_var="income", target=1.2e8)
)
```

### 11.4 任意分类取值的占比

合格率是"`outcome` 等于 1 的占比"的特例。要校准**别的变量某取值的占比**（含 1/2 这种非 0/1 编码）：

```r
# 让"评级=A"的加权占比达到 40%
data.frame(variable=".overall", level=".all", target_rate=0.40,
           statistic="proportion", value_var="grade", value="A")
```

> 注意"占比"≠"均值"：`{1,2}` 数据求"等于 1 的占比"要用占比（结果在 0–1），不是对原值取平均（那会得到 1.x）。

### 11.5 Excel 进出（见第五节）

`read_calibration_data()` / `read_targets_xlsx()` / `calibrate_from_excel()` / `export_calibration_xlsx()`。

### 11.6 重复权重方差估计

校准后的估计量有抽样误差。若你有外部生成的**重复权重**（bootstrap / jackknife / BRR），可估方差：

```r
rc <- calibrate_replicate_weights(fit, repweights = 重复权重矩阵, progress = TRUE)
replicate_variance(rc, x = dat$income, statistic = "total")   # 返回 估计值/方差/标准误
```

---

## 十二、应用实例（带真实数字走一遍）

下面的数字来自 `example_rate_data(5000, seed = 2026)`，可复现。

### 例 1：基础合格率校准（一步式，软模式）

```r
dat <- example_rate_data(5000, seed = 2026)
fit <- calibrate_rates(
  dat, "qualified", "initial_weight",
  overall = 0.70,
  groups  = list(sex = c(M = 0.72, F = 0.68), residence = c(Urban = 0.71, Rural = 0.685)),
  priority = 5, group_priority = c(sex = 2, residence = 2), mode = "soft"
)
fit$target_check
```

初始总体合格率只有 **0.6297**，目标 0.70。校准后：

| variable | level | 目标 | 校准前 | 校准后 | 绝对误差 |
|---|---|---|---|---|---|
| .overall | .all | 0.700 | 0.6297 | **0.7003** | 0.0003 |
| sex | M | 0.720 | 0.6326 | 0.7207 | 0.0007 |
| sex | F | 0.680 | 0.6268 | 0.6807 | 0.0007 |
| residence | Urban | 0.710 | 0.6415 | 0.7086 | 0.0014 |
| residence | Rural | 0.685 | 0.6070 | 0.6843 | 0.0007 |

所有目标都被拉到了非常接近的程度。再看体检：

- 样本量 5000，初始有效样本量 **4614** → 校准后 **4518**（只降了约 2%，代价很小，说明权重没被拉得很极端）；
- 权重倍数范围 **0.75 – 1.15**（都在 0.25–4 的限内，很温和）；
- 最大目标绝对误差 **0.0014**（千分之一量级，软模式下已很贴合）。

### 例 2：精确模式 + 可行性预检（处理"算不出来"）

如果改用 `mode = "exact"` 且同时给了总体 0.62 和性别目标 M=0.66/F=0.60，先做预检：

```r
calibration_feasibility(dat, "qualified", "initial_weight", "sex",
  make_rate_targets(overall = 0.62, groups = list(sex = c(M = 0.66, F = 0.60))))
```

预检结果（真实输出）：性别目标隐含的总体率是 **0.6293**，而你写的总体目标是 **0.6200**——
**对不上**（`consistent: FALSE`）。这说明精确模式必然失败。解决：要么把总体目标改成 0.6293，
要么去掉总体目标，要么改用软模式。**先预检、再求解，能避免直接撞上"无解"报错。**

### 例 3：连续变量的均值校准（精确或软）

```r
dat$income <- round(rlnorm(nrow(dat), log(40000) + 0.5 * dat$qualified, 0.3))
tg <- make_rate_targets(means = data.frame(
  variable = ".overall", level = ".all", value_var = "income", target = 52000))
fit <- calibrate_pass_rates(dat, "qualified", "initial_weight",
  group_vars = "residence", targets = tg, mode = "exact", lower = 0.1, upper = 10)
# 验证：校准后加权平均收入
w <- weights(fit); sum(w * dat$income) / sum(w)   # ≈ 52000
```

### 例 4：交互目标

```r
tg <- make_rate_targets(interactions = list("sex:residence" = c("M:Urban" = 0.75)))
fit <- calibrate_pass_rates(dat, "qualified", "initial_weight",
  group_vars = c("sex","residence"), targets = tg, mode = "exact")
# 验证：城镇男性子群的加权合格率
w <- weights(fit); sub <- dat$sex=="M" & dat$residence=="Urban"
sum(w[sub]*dat$qualified[sub]) / sum(w[sub])       # ≈ 0.75
```

### 例 5：重复权重方差

```r
# 假设 repw 是 5000 行 × R 列的重复权重矩阵（外部按你的抽样设计生成）
rc <- calibrate_replicate_weights(fit, repw, scale = 1)
replicate_variance(rc, dat$income, "mean")$se      # 加权平均收入的标准误
```

---

## 十三、数学原理（讲清楚，但尽量好懂）

### 13.1 加权合格率与"线性化"

第 $i$ 个人的结果 $y_i\in\{0,1\}$、校准后权重 $w_i$。某分组 $j$ 的加权合格率：

$$\hat r_j=\frac{\sum_i w_i I_{ij} y_i}{\sum_i w_i I_{ij}}$$

其中 $I_{ij}=1$ 表示第 $i$ 人属于组 $j$。要让它等于目标 $r_j^\*$，等价于：

$$\sum_i w_i I_{ij}\,(y_i-r_j^\*)=0$$

这一步把"比例约束"变成了对权重 $w$ 的**线性约束**——线性约束才好高效求解。

### 13.2 先聚合再优化（为什么快）

很多人结果/分组完全相同。把"分组交叉 × 结果状态"相同的人**合并成一个单元**，
每个单元只记初始权重之和 $D_c$，求解的未知数是各单元调整后的总权重 $x_c$。
例如 2 性别 ×2 城乡 ×5 学历 ×5 年龄 ×2 结果 = 最多 200 个单元——
哪怕原始有几十万人，核心问题也就 ~200 个变量。算完再把每个单元的"调整倍数" $g_c=x_c/D_c$
回贴到每个人。

### 13.3 目标函数与边际硬约束

默认（chi2 距离）最小化"权重改动的代价"：

$$\min_x\ \sum_c \frac{(x_c-D_c)^2}{D_c}$$

含义：在达到目标的前提下，让权重尽量**少偏离**初始值。同时有两类**硬约束**（必须满足）：

- 总量不变：$\sum_c x_c=$ 初始总权重；
- 每个分组变量的各类别总量不变（如男性总权重、城镇总权重保持原值）。

这保证不会为了凑合格率而改变各群体的人口盘子。

### 13.4 软约束 vs 精确约束

- **精确（exact）**：把"合格率目标"也作为硬约束（上式的线性约束 $=0$）。目标稍有矛盾就**无解**。
- **软（soft，默认）**：把目标作为**惩罚项**加进目标函数——允许有误差，但误差越大罚得越狠：

$$\min_x\ \sum_c \frac{(x_c-D_c)^2}{D_c}\;+\;\sum_j \lambda_j\Big(\textstyle\sum_c x_c I_{cj}(y_c-r_j^\*)\Big)^2,
\qquad \lambda_j=\frac{\lambda\cdot\text{总量}\cdot \text{priority}_j}{\text{size}_j^2}$$

`lambda` 越大、`priority` 越高，越逼近该目标。冲突时按 `priority` 权衡。

### 13.5 距离函数族与对偶（chi2 / raking / logit）

更一般地，可用不同"距离"衡量倍数 $g_c=x_c/D_c$ 的改动。它们的最优解都长成
$g_c=g(\eta_c)$，其中 $\eta=A^\top\lambda$（$A$ 是所有约束拼成的矩阵，$\lambda$ 是对偶变量）：

| 距离 | $g(\eta)$ | 取值范围 |
|---|---|---|
| chi2（卡方） | $1+\eta$ | 可能为负（靠上下限裁剪） |
| raking（熵） | $e^{\eta}$ | $(0,\infty)$，天然为正 |
| logit | $\dfrac{L(U-1)+U(1-L)e^{A\eta}}{(U-1)+(1-L)e^{A\eta}}$ | 严格落在 $(L,U)$ 内 |

raking/logit 用**对偶牛顿迭代**求 $\lambda$ 使约束成立（$L,U$ 即 `lower,upper`）。
软模式则在对偶方程里对目标行加一个"岭"正则，等价于上面的惩罚校准。

### 13.6 统计量泛化（占比 / 均值 / 总量）

把目标行写成统一形式 $\sum_c x_c\,I_{cj}\,a_c=t_j$：

| 统计量 | 单元上的量 $a_c$ | 右端 $t_j$ |
|---|---|---|
| 占比（某值 $v$） | 单元内 $I(Z=v)$（按取值拆纯单元后为 0/1） | 0（配 $-r^\*$ 项） |
| 均值（变量 $W$） | $\bar W_c=\sum_{i\in c} d_i W_i/D_c$（配 $-m^\*$） | 0 |
| 总量（变量 $W$） | $\bar W_c$ | 目标总量 $T$ |

关键：**连续量**（均值/总量）无法把单元拆"纯"，用单元内充分统计量 $\bar W_c$ 即可；
**分类占比**必须按该分类变量拆单元，才能完全控制组内占比（这也是 0/1 合格率能精确达成的原因）。

### 13.7 目标可行性（预检在算什么）

- **一致性恒等式**：因为各分组的人口总量被固定，如果某分组变量**每个类别都设了目标**，
  总体率就被唯一确定为 $\sum_\ell W_\ell r_\ell/\sum_\ell W_\ell$。你若再给一个对不上的总体目标，
  精确模式必然无解——这能在求解前**精确**抓出。
- **单目标可达区间**：某组总量固定、倍数限在 $[L,U]$，则该组合格率的可达范围是
  $\big[\max(L\!\cdot\!P,\,W\!-\!U\!\cdot\!F),\ \min(U\!\cdot\!P,\,W\!-\!L\!\cdot\!F)\big]/W$，
  其中 $P,F$ 是组内合格/不合格的初始权重和、$W=P+F$。目标落区间外 → 必不可行。
  （这是**必要**条件：通过不代表多目标联合一定可行。）

### 13.8 方差估计（重复权重）

对每套重复权重各重算一次校准，得各重复估计 $\hat\theta_r$ 与全样本估计 $\hat\theta_0$，方差为：

$$\widehat{\operatorname{Var}}(\hat\theta)=\text{scale}\cdot\sum_r \text{rscales}_r\,(\hat\theta_r-\hat\theta_0)^2$$

`scale`/`rscales` 由你的重复方案决定（JK1：scale=(R-1)/R；bootstrap：scale=1/R）。

### 13.9 有效样本量 ESS 与设计效应 DEFF

$$\text{ESS}=\frac{(\sum_i w_i)^2}{\sum_i w_i^2},\qquad \text{DEFF}_w\approx 1+\text{CV}(w)^2$$

权重越不均匀，ESS 越低、DEFF 越大，意味着为达目标付出的统计效率代价越高。

---

## 十四、问题速查

| 症状 / 现象 | 可能原因 | 怎么办 |
|---|---|---|
| 精确模式报 "did not solve / infeasible" | 目标自相矛盾，或某组全 0/全 1，或上下限太窄 | 先跑 `calibration_feasibility()`；改 `mode="soft"`；放宽 `lower/upper` |
| 预检显示 `consistent: FALSE` | 总体目标与分组目标隐含的总体率对不上 | 改总体目标为隐含值、或删总体目标、或用软模式 |
| 软模式误差仍偏大 | 惩罚太弱，或目标本就难达 | 调大 `lambda`（如 1e5/1e6）；提该目标 `priority`；放宽上下限 |
| 校准后 ESS 大幅下降 | 权重被拉得很极端 | 收紧 `lower/upper`；降低过激的目标；检查目标是否现实 |
| 出现很大的放大倍数 | chi2 + 激进目标 | 用 `distance="logit"` 硬封顶，或收紧 `upper` |
| 某组目标怎么都达不到 | 该组样本全合格或全不合格 | 光调权重改不了，需补样本或放弃该组目标 |
| 报错 "must contain only 0 and 1" | 结果列不是 0/1 | 先把结果列编码成 0/1；若要"某取值占比"用 `value_var/value` |
| 报错权重含 0 或负 / 缺失 | 初始权重不合法 | 确保初始权重全为正、无缺失 |
| 报错分组变量有缺失 | 分组列有空白 | 把缺失先归成一个明确类别（如 "未知"） |
| 交互/均值目标被 `check` 当成 "not in group_vars" | 旧版行为 | 已修复：这两个检查现会自动跳过进阶目标，不再误判 |
| Excel 函数报 "requires the 'openxlsx' package" | 没装可选依赖 | `install.packages("openxlsx")` |
| 中文变量名报编码错（旧版 Windows） | 非 UTF-8 区域设置 | 变量名改用英文（函数/参数本就是英文） |
| 想要正权重保证 / 硬性封顶 | 距离选择 | 正性用 `distance="raking"`；封顶用 `"logit"` |
| 想知道结果有多稳（标准误） | 需要方差 | 用 `calibrate_replicate_weights()` + `replicate_variance()` |

---

> 想了解每个函数的完整参数，在 R 里输入 `?calibrate_rates`、`?calibrate_pass_rates` 等查看帮助；
> 更技术性的架构与算法细节见 `docs/ARCHITECTURE.md`。
