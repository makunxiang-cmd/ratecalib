# ratecalib：多分组合格率目标的校准加权工具

> 说明：本包的 **R 函数名、报错信息与打印输出均为英文**（满足 CRAN 的 ASCII 可移植性要求）；
> 本文档为中文。旧版的中文函数别名（如 `校准合格率`）已移除，请使用英文函数名。
> 演示数据 `example_rate_data()` 的类别值也已英文化：`M`/`F`、`Urban`/`Rural`、`Edu1`–`Edu5`、`Age1`–`Age5`。

`ratecalib` 用于调整人口样本或调查样本的初始权重，使一个二元指标（合格=1、不合格=0）的总体加权合格率，以及性别、城乡、学历、年龄等多个重叠分组的加权合格率，尽量接近或精确达到给定目标。

这个包特别适合以下数据结构：

- 每行代表一个样本；
- 每个样本有一个正的初始权重；
- 结果变量只有0和1；
- 样本按多个分类变量交叉形成若干人口单元；
- 并非每个理论交叉单元都有样本；
- 已知总体及各边际分组的目标合格率；
- 希望通过调整权重，而不是修改原始结果变量，使加权结果靠近目标。

包提供两层接口：

1. **一步式接口**：`calibrate_rates()`，自动建目标表、识别分组、数据检查后求解；
2. **底层专业接口**：`calibrate_pass_rates()`，适合需要完全控制目标表和求解参数的使用者。

除基础的合格率校准外，本包还支持一组**进阶功能**（详见[第十四节](#十四进阶功能本版新增)）：
多种校准距离（卡方 / 熵-raking / 有界-logit）、交互（交叉分组）目标、对连续变量的均值/总量校准与对任意
分类取值的占比校准、求解前的目标可行性预检、Excel 数据进出、以及基于重复权重的方差估计。

---

## 重要声明 / Disclaimer

本工具通过调整权重使加权结果逼近或精确达到使用者设定的目标值，因此存在被滥用于学术造假的风险。
当目标值并非来自可靠的外部数据，而是出于期望或主观设定时，所谓"达成"的数字本质上是被设定出来的结果，
而非独立发现；将其作为独立研究发现报告或发表，构成数据伪造或篡改，属于学术不端，并可能违反法律法规与
期刊机构规定。正当使用要求目标来自可靠外部信息，并在任何对外结论中如实、完整披露校准方法、目标来源、
权重约束及校准对结果的影响。本软件按"现状"提供、不附带任何担保；使用者须对其合法、合规与合乎伦理的
使用负全部责任。

This tool adjusts weights to meet user-specified targets and can therefore be misused for academic fraud. When
targets are not from reliable external data but reflect expectations or subjective choices, the resulting
figures are a product of the chosen targets, not independent findings; presenting them as independent findings
is data fabrication or falsification and academic misconduct. The software is provided "as is", without
warranty, and the user is solely responsible for its lawful and ethical use.

完整的中英文免责声明与使用条款见 [`DISCLAIMER.md`](DISCLAIMER.md)。下载、安装或使用本软件即表示同意接受。
Full bilingual terms are in [`DISCLAIMER.md`](DISCLAIMER.md); using the software constitutes acceptance.

---

## 一、安装

先安装底层依赖：

```r
install.packages(c("Matrix", "osqp"))
```

若要使用 Excel 读写功能（[第十四节](#5-excel-数据输入--输出)），再装可选依赖 `openxlsx`：

```r
install.packages("openxlsx")
```

再安装本地源码包：

```r
install.packages(
  "ratecalib_0.2.1.tar.gz",
  repos = NULL,
  type = "source"
)
```

加载包：

```r
library(ratecalib)
```

macOS 若在编译 `osqp` 时失败，可先安装命令行开发工具：

```bash
xcode-select --install
```

---

## 二、最简单的使用方式

### 1. 准备数据

数据至少应包含：

- 一个0/1结果变量；
- 一个正的初始权重变量；
- 若干分组变量。

包内可生成一份演示数据：

```r
dat <- example_rate_data(n = 5000)
head(dat)
```

演示数据包含：

```text
sex             性别            取值 M / F
residence       城乡            取值 Urban / Rural
education5      五段学历        取值 Edu1 … Edu5
age5            五段年龄        取值 Age1 … Age5
qualified       合格指标，1=合格，0=不合格
initial_weight  初始权重
```

### 2. 一步完成校准

```r
fit <- calibrate_rates(
  data = dat,
  outcome = "qualified",
  weight = "initial_weight",

  overall = 0.70,

  groups = list(
    sex = c(M = 0.72, F = 0.68),
    residence = c(Urban = 0.71, Rural = 0.685),
    education5 = c(
      Edu1 = 0.62,
      Edu2 = 0.66,
      Edu3 = 0.70,
      Edu4 = 0.74,
      Edu5 = 0.78
    ),
    age5 = c(
      Age1 = 0.76,
      Age2 = 0.73,
      Age3 = 0.70,
      Age4 = 0.67,
      Age5 = 0.64
    )
  ),

  priority = 5,
  group_priority = c(
    sex = 2,
    residence = 2,
    education5 = 1,
    age5 = 1
  ),

  lower = 0.25,
  upper = 4,
  mode = "soft",
  new_weight = "final_weight"
)
```

查看结果：

```r
fit
summary(fit)
```

获取带新权重的数据：

```r
result_data <- fit$data
head(result_data[c("initial_weight", "final_weight")])
```

---

## 三、理论原理

### 3.1 加权合格率

设第 \(i\) 个样本的结果为 \(y_i\)，其中合格为1、不合格为0；初始权重为 \(d_i\)，校准后权重为 \(w_i\)。

某个分组 \(j\) 的加权合格率为：

\[
\hat r_j = \frac{\sum_i w_i I_{ij}y_i}{\sum_i w_i I_{ij}}
\]

其中 \(I_{ij}=1\) 表示样本 \(i\) 属于分组 \(j\)，否则为0。

若目标合格率为 \(r_j^*\)，则目标条件可以改写为：

\[
\sum_i w_i I_{ij}(y_i-r_j^*)=0
\]

这样，原本的比例约束就转化成了线性约束。

### 3.2 为什么不能直接把所有合格样本乘同一个倍数

因为性别、城乡、学历和年龄是重叠分组。一个样本同时属于某个性别、某个城乡类别、某个学历段和某个年龄段。改变一个样本的权重，会同时影响多个目标。

因此需要同时考虑所有目标，而不能逐组独立调整。逐组循环乘权重虽然直观，但容易出现：

- 后调整的目标破坏先前已达到的目标；
- 在多个目标之间反复震荡；
- 产生极端权重；
- 无法判断目标是否数学上相容。

### 3.3 优化目标

本包默认最小化：

\[
\sum_c \frac{(W_c-D_c)^2}{D_c}
\]

其中：

- \(D_c\) 是某个“人口交叉单元×合格状态”的初始权重总和；
- \(W_c\) 是该单元校准后的权重总和。

这意味着：在满足目标的同时，尽量少改变原始权重结构。

### 3.4 为什么先聚合再优化

若有：

- 2类性别；
- 2类城乡；
- 5段学历；
- 5段年龄；
- 2种结果状态；

理论上最多只有：

\[
2\times2\times5\times5\times2=200
\]

个优化单元。

即使个人样本有几十万条，优化问题通常仍只有不超过200个核心变量。求解后，再把每个单元的调整倍数映射回个人样本。这既提高效率，也保证同一单元中的样本按相同比例调整。

### 3.5 人口边际保持

本包默认把原有的总体权重总量，以及各分组变量的边际权重总量作为硬约束保持不变。

例如，男性的初始权重总量为10000，校准后仍保持10000；但男性内部合格与不合格样本之间的权重结构可以变化，从而改变男性合格率。

这样可以防止算法为了达到合格率目标而任意改变男性、女性、城镇、农村等群体在总体中的规模。

---

## 四、软约束与精确约束

### 4.1 软约束：推荐默认使用

```r
mode = "soft"
```

软约束允许目标之间存在轻微矛盾。算法会综合考虑：

- 目标误差；
- 目标优先级；
- 权重变化幅度；
- 权重上下限；
- 人口边际保持。

这通常最适合真实业务数据，因为不同来源的目标率可能存在舍入误差、测量误差或内部不一致。

### 4.2 精确约束

```r
mode = "exact"
```

精确模式要求所有目标同时精确满足。只有在以下条件都成立时才适合：

- 目标之间完全相容；
- 数据结构支持所有目标；
- 每个需要调整的组中同时存在0和1；
- 权重上下限足够宽；
- 缺失交叉单元没有造成结构性冲突。

精确模式失败并不一定意味着程序错误，更常见的原因是目标不可行。

---

## 五、目标优先级

在软约束模式下，`priority` 越大，算法越重视该目标。

```r
priority = 5
```

表示总体目标优先级为5。

```r
group_priority = c(
  sex = 2,
  residence = 2,
  education5 = 1,
  age5 = 1
)
```

表示：

- 总体目标最重要；
- 性别和城乡次之；
- 学历和年龄再次之。

优先级不是“必须达到”的开关，而是目标发生冲突时的相对权衡系数。

---

## 六、权重上下限

```r
lower = 0.25
upper = 4
```

表示：

\[
0.25d_i \le w_i \le 4d_i
\]

即最终权重最多降到初始权重的25%，最多升到4倍。

常见选择：

| 使用场景 | 建议范围 |
|---|---|
| 非常保守 | 0.5–2 |
| 一般分析 | 0.25–4 |
| 目标差距较大 | 0.1–10 |

范围越窄，权重越稳定，但目标误差可能越大；范围越宽，目标更容易达到，但有效样本量可能明显下降。

---

## 七、校准前自动检查

一步式函数默认执行检查，也可以单独运行：

```r
targets <- make_rate_targets(
  overall = 0.70,
  groups = list(
    sex = c(M = 0.72, F = 0.68)
  )
)

check <- check_calibration_data(
  data = dat,
  outcome = "qualified",
  weight = "initial_weight",
  group_vars = "sex",
  targets = targets
)

check
```

检查内容包括：

- 必要变量是否存在；
- 初始权重是否为正；
- 结果变量是否只含0和1；
- 分组变量是否有缺失；
- 目标类别是否在数据中存在；
- 某组是否全部为0或全部为1；
- 当前各组加权合格率；
- 数据是否支持给定目标。

详细分组检查表：

```r
check$group_summary
```

目标支持情况：

```r
check$target_support
```

---

## 八、专业接口

需要完全控制目标表时，可先生成目标表：

```r
targets <- make_rate_targets(
  overall = 0.70,
  groups = list(
    sex = c(M = 0.72, F = 0.68),
    residence = c(Urban = 0.71, Rural = 0.685)
  ),
  overall_priority = 5,
  group_priority = c(sex = 2, residence = 2)
)
```

目标表结构：

```text
variable     level   target_rate   priority
.overall     .all       0.700          5
sex          M          0.720          2
sex          F          0.680          2
```

然后调用底层函数：

```r
fit <- calibrate_pass_rates(
  data = dat,
  outcome = "qualified",
  weight = "initial_weight",
  group_vars = c("sex", "residence", "education5", "age5"),
  targets = targets,
  lower = 0.25,
  upper = 4,
  mode = "soft",
  lambda = 1e4,
  new_weight = "final_weight"
)
```

---

## 九、如何解释输出

### 9.1 目标检查

```r
fit$target_check
```

重要字段：

- `target_rate`：目标合格率；
- `initial_rate`：校准前加权合格率；
- `achieved_rate`：校准后加权合格率；
- `error`：校准后率减目标率；
- `abs_error`：绝对误差；
- `priority`：目标优先级。

误差最大的目标：

```r
fit$target_check[order(-fit$target_check$abs_error), ]
```

### 9.2 人口边际检查

```r
fit$margin_check
```

`relative_change` 应非常接近0，因为本包默认保持各边际权重总量。

### 9.3 权重诊断

```r
fit$diagnostics
```

重点指标：

- `initial_ESS`：初始有效样本量；
- `calibrated_ESS`：校准后有效样本量；
- `calibrated_weight_DEFF`：校准后权重设计效应；
- `minimum_multiplier`：最小调整倍数；
- `maximum_multiplier`：最大调整倍数；
- `cells_at_lower_bound`：触及下限的单元数；
- `cells_at_upper_bound`：触及上限的单元数；
- `maximum_absolute_target_error`：最大目标绝对误差。

### 9.4 有效样本量

有效样本量定义为：

\[
ESS=\frac{(\sum_iw_i)^2}{\sum_iw_i^2}
\]

权重越不均匀，ESS通常越低。若校准后ESS大幅下降，说明为了达到目标付出了较高的统计效率成本。

### 9.5 权重设计效应

近似权重设计效应为：

\[
DEFF_w\approx1+CV(w)^2
\]

该值越大，表示权重不均衡对估计方差的放大越明显。

---

## 十、图形诊断

目标误差图：

```r
plot(fit, type = "target_error")
```

权重调整倍数分布：

```r
plot(fit, type = "multipliers")
```

---

## 十一、完整案例

```r
library(ratecalib)

# 1. 生成演示数据
dat <- example_rate_data(10000)

# 2. 设定目标并一步校准
fit <- calibrate_rates(
  data = dat,
  outcome = "qualified",
  weight = "initial_weight",
  overall = 0.70,
  groups = list(
    sex = c(M = 0.72, F = 0.68),
    residence = c(Urban = 0.71, Rural = 0.685),
    education5 = c(
      Edu1 = 0.62,
      Edu2 = 0.66,
      Edu3 = 0.70,
      Edu4 = 0.74,
      Edu5 = 0.78
    ),
    age5 = c(
      Age1 = 0.76,
      Age2 = 0.73,
      Age3 = 0.70,
      Age4 = 0.67,
      Age5 = 0.64
    )
  ),
  priority = 5,
  group_priority = c(
    sex = 2,
    residence = 2,
    education5 = 1,
    age5 = 1
  ),
  lower = 0.25,
  upper = 4,
  mode = "soft",
  lambda = 1e4,
  new_weight = "final_weight"
)

# 3. 查看摘要
summary(fit)

# 4. 查看目标误差
fit$target_check

# 5. 查看权重质量
fit$diagnostics

# 6. 绘图
plot(fit, "target_error")
plot(fit, "multipliers")

# 7. 导出结果
result <- fit$data
write.csv(result, "校准后样本.csv", row.names = FALSE, fileEncoding = "UTF-8")
```

---

## 十二、常见问题

### 1. 为什么精确模式无解？

常见原因包括：

- 总体目标与分组目标不一致；
- 某组全是0或全是1；
- 某些交叉单元没有样本；
- 权重上下限过窄；
- 多组目标通过重叠样本产生结构性冲突。

处理顺序建议：

1. 先运行 `check_calibration_data()`；
2. 改用 `mode="soft"`；
3. 适度放宽 `lower` 和 `upper`；
4. 调整优先级；
5. 检查目标来源及内部一致性。

### 2. 软约束误差仍然较大怎么办？

可尝试：

```r
lambda = 1e5
```

或放宽权重范围：

```r
lower = 0.1
upper = 10
```

但应同步检查ESS和权重设计效应。

### 3. 所有目标都应该设成最高优先级吗？

不建议。若目标之间略有冲突，全部设置同样的极高优先级并不能消除冲突，只会迫使权重产生更剧烈的变化。应根据目标来源的可靠性和业务重要性设置层级。

### 4. 没有样本的交叉人群怎么办？

算法不能凭空创造样本。缺失单元本身不一定导致失败，但若目标要求依赖这些缺失单元才能实现，就会出现不可行或较大误差。

### 5. 目标合格率是否可以来自主观设定？

技术上可以，但解释上必须谨慎。若目标来自外部总体数据，校准后结果可理解为外部信息约束下的加权估计；若目标是人为期望值，校准后的合格率主要是被设定出来的结果，不应再被表述为独立发现。

---

## 十三、推荐工作流

实际项目中建议按照以下顺序：

1. 清理0/1结果变量和分组变量；
2. 确认初始权重全部为正；
3. 明确目标率来源及优先级；
4. 运行校准前检查；
5. 首先使用软约束和0.25–4倍范围；
6. 查看目标误差、ESS、DEFF和边界命中情况；
7. 必要时调整优先级、lambda或权重范围；
8. 保存最终权重和全部诊断结果；
9. 在报告中披露校准方法、目标来源和权重限制。

---

## 十四、进阶功能（本版新增）

以下功能均向后兼容：不使用时，函数行为与基础用法完全一致。

### 1. 校准距离函数族

`calibrate_pass_rates()` 与 `calibrate_rates()` 新增参数 `distance`，可选三种校准距离：

| `distance` | 距离 | 倍数性质 | 适用 |
|---|---|---|---|
| `"chi2"`（默认） | 线性 / 卡方 | 靠 `lower`/`upper` 箱式约束兜底 | 一般默认；soft/exact 均可 |
| `"raking"` | 熵（raking） | `g=exp(η)` **天然恒正**，上方无界 | 要正性保证；越界倍数仅在诊断中报告 |
| `"logit"` | 有界 logit | 倍数**解析地恒在 `(lower, upper)` 内** | 需硬性封顶极端权重（要求 `lower<1<upper`） |

`"chi2"` 走 OSQP，行为与旧版完全一致；`"raking"`/`"logit"` 用对偶 Newton 求解（纯 R + Matrix），
exact 与 soft 模式均支持。例：

```r
fit <- calibrate_pass_rates(
  dat, "qualified", "initial_weight",
  group_vars = c("sex", "residence"),
  targets = make_rate_targets(groups = list(sex = c(M = 0.72, F = 0.68))),
  mode = "exact", distance = "raking"
)
```

> 注：默认距离永久保持 `"chi2"`，不会改为 raking；raking/logit 始终是可选项。

### 2. 交互（交叉分组）目标

校准「城镇 × 男性」这类交叉分组的合格率，用冒号连接的复合 key：

```r
targets <- make_rate_targets(
  groups = list(sex = c(M = 0.72, F = 0.68)),
  interactions = list("sex:residence" = c("M:Urban" = 0.75, "F:Rural" = 0.62))
)
fit <- calibrate_pass_rates(dat, "qualified", "initial_weight",
                            group_vars = c("sex", "residence"), targets = targets)
```

交互目标只新增目标行、**不**自动固定交互边际；各分量变量须在 `group_vars` 中；水平值本身不可含冒号。

### 3. 均值 / 总量目标（连续变量）

除合格率外，可校准任意数值变量的**组内均值或总量**。在目标表加 `statistic`（`"mean"`/`"total"`）与
`value_var` 列，或用 `make_rate_targets()` 的 `means` / `totals` 参数（均**仅支持 `mode="exact"`**）：

```r
# dat$income 为数值列
targets <- make_rate_targets(
  overall = 0.70,
  means  = data.frame(variable = ".overall", level = ".all",
                      value_var = "income", target = 52000),
  totals = data.frame(variable = "residence", level = "Urban",
                      value_var = "income", target = 1.2e8)
)
fit <- calibrate_pass_rates(dat, "qualified", "initial_weight",
                            group_vars = "residence", targets = targets,
                            mode = "exact")
```

### 4. 任意分类取值的占比

合格率是「`outcome==1` 的占比」的特例。要校准**其他变量某取值的占比**（含 1/2 编码这类非 0/1 数据），
用 `value_var` + `value` 列指定被测量。注意「占比」≠「均值」——`{1,2}` 数据求「等于 1 的占比」需用占比，
而非对原值取均值：

```r
# 校准总体中 grade == "A" 的加权占比为 0.40
targets <- data.frame(
  variable = ".overall", level = ".all", target_rate = 0.40,
  statistic = "proportion", value_var = "grade", value = "A",
  stringsAsFactors = FALSE
)
fit <- calibrate_pass_rates(dat, "qualified", "initial_weight",
                            group_vars = "sex", targets = targets, mode = "exact")
```

### 5. Excel 数据输入 / 输出

需先 `install.packages("openxlsx")`。

```r
# 读样本数据与目标表
dat     <- read_calibration_data("input.xlsx", sheet = "data")
targets <- read_targets_xlsx("input.xlsx", sheet = "targets")  # 表头支持中英别名

# 一步：从工作簿读数据+目标并求解（未给 group_vars 时自动从目标表推断）
fit <- calibrate_from_excel("input.xlsx", outcome = "qualified",
                            weight = "initial_weight",
                            data_sheet = "data", targets_sheet = "targets")

# 导出多工作表结果（data / target_check / margin_check / diagnostics / settings）
export_calibration_xlsx(fit, "result.xlsx")
```

### 6. 求解前目标可行性预检

`calibration_feasibility()` 在求解前做两项确定性检查：(1) **总体–分组一致性**——某分组变量每个水平都有
目标时，总体率被唯一确定，据此抓出与显式总体目标互相矛盾的设定；(2) **单目标可达区间**——目标落在
区间外则必不可行（必要非充分）。

```r
fz <- calibration_feasibility(dat, "qualified", "initial_weight",
                              group_vars = "sex",
                              targets = make_rate_targets(overall = 0.62,
                                groups = list(sex = c(M = 0.66, F = 0.60))))
fz                      # 打印一致性与可达区间
fz$consistency$consistent
```

> 一步式 `calibrate_rates(check = TRUE)` 默认路径也会在目标实质性不一致时发出告警。

### 7. 重复权重方差估计

校准后估计量的方差不同于原始抽样。提供基于**重复权重**（bootstrap / jackknife / BRR，外部生成）的
方差估计，与 `survey` 包的 `svrepdesign` 对齐：

```r
# repw: 每行一个样本、每列一套重复权重的矩阵
rc <- calibrate_replicate_weights(fit, repweights = repw,
                                  scale = 1, rscales = NULL, progress = TRUE)

# 估计某数值变量加权总量/均值的方差与标准误
v <- replicate_variance(rc, x = dat$income, statistic = "total")
v$estimate; v$se
```

`scale` / `rscales` 为重复方差常数，按你的重复方案设定（如 JK1：`scale=(R-1)/R`、`rscales=1`；
bootstrap：`scale=1/R`）。方差公式为 `Var = scale · Σ rscales_r · (θ̂_r − θ̂_0)²`。

### 8. 标准提取方法

```r
weights(fit)        # 校准后权重向量（等价于 fit$data[[new_weight]]）
as.data.frame(fit)  # 含校准权重列的数据框
```

