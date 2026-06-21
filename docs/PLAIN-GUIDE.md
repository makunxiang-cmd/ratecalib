# ratecalib 中文使用说明

这份说明写给两类人：一类是会做调查、懂加权、但没碰过 R 的统计或业务人员；
另一类是要把这套方法接手下去的开发者。第一部分让你不写代码也能把活干完，
第二部分把每个函数、每一行代码讲透，第三部分讲清楚背后的数学。最后附一张问题速查表。

你完全不需要先去学 R。第二部分开头有一节专门解释你会看到的那几个符号，照着做就行。

---

# 重要声明：关于学术诚信与正当使用 / Important notice on integrity and proper use

在开始之前，请务必读完这一节。

本工具通过调整权重，使加权后的合格率、比例、均值或总量逼近或精确达到你设定的目标值。
正因为如此，它存在被滥用于学术造假的风险。请牢记：当目标值不是来自可靠的外部数据，
而是出于你的期望或主观设定时，所谓"达成"的数字，本质上是被你设出来的结果，而不是独立得到的发现。
把这种结果当成独立的研究发现去报告或发表，属于数据伪造或篡改，是学术不端，并可能触犯法律法规与期刊机构规定。

正当的用法是：目标值来自可靠的外部总体信息，并且在任何对外结论中如实、完整地披露所用的校准方法、
目标的来源与性质、权重的约束设定，以及校准对结果的影响。

This tool adjusts weights so that weighted rates, proportions, means, or totals approach or exactly meet
targets you specify. It can therefore be misused for academic fraud. When the targets are not derived from
reliable external data but reflect your own expectations or subjective choices, the resulting figures are a
product of the targets you set, not independent findings. Presenting such figures as independent research
findings constitutes data fabrication or falsification, is academic misconduct, and may violate laws and
institutional or journal rules. Legitimate use requires that targets come from reliable external information
and that any external conclusion fully and truthfully disclose the calibration method, the source and nature
of the targets, the weight constraints, and the effect of calibration on the results.

本软件按"现状"提供，不附带任何担保；使用者须对其合法、合规与合乎伦理的使用负全部责任。
下载、安装或使用本软件，即表示同意接受完整的免责声明与使用条款。
The software is provided "as is", without warranty; the user is solely responsible for its lawful, compliant,
and ethical use. By downloading, installing, or using it, you agree to the full disclaimer and terms.

完整的中英文免责声明与使用条款见项目根目录的 `DISCLAIMER.md`，安装后也可用
`system.file("DISCLAIMER.md", package = "ratecalib")` 找到。
The full bilingual disclaimer and terms are in `DISCLAIMER.md` at the project root, and after installation at
`system.file("DISCLAIMER.md", package = "ratecalib")`.

---

# 第一部分：快速上手

## 1. 它解决什么问题

做过抽样调查的人都熟悉一个困境：样本和真实人口对不上。真实人口男女各半，
你的样本却女多男少；真实城镇人口占六成，样本里城镇又偏少。这种结构偏差会让你直接算出来的
比例失真。

通行的补救办法是加权。给每个被访者一个权重，代表他在现实中"顶几个人"。男性在样本里偏少，
就让每个男性多顶几个人，把男性的话语权抬上来。`ratecalib` 做的就是这件事的精细版本：
它替你算出一套权重，让加权之后的合格率既贴合你掌握的总体目标，也贴合性别、城乡、学历、
年龄等各个分组的目标。

它特别适合这样的场景：你手上有一份名单，每行一个人，每人有一个是否合格的标记和一个初始权重；
你从官方统计或上级口径知道总体和各分组应该达到的合格率；你想通过调权重让样本结果对上这些口径，
而不是去改动任何人的答案。

手工凑权重的人都知道有多难受。性别、城乡、学历、年龄是相互交叉的，一个人同时落在好几个分组里，
你调他的权重会同时牵动好几个目标。先把男性凑好，城乡又歪了；回头修城乡，性别又跑了。
`ratecalib` 用数学方法一次性兼顾所有目标，避免这种按下葫芦浮起瓢的反复。

## 2. 工作原理：只调权重，不改答案

这套方法有三条原则，决定了它为什么可信。

第一，它只动权重，绝不碰原始答案。合格的人还是合格，不合格的还是不合格。变的只是每个人顶几个人，
也就是他在加总里的分量。

第二，它在达成目标的前提下，让权重尽量少偏离你给的初始值。它不会胡乱放大某些人来硬凑数字，
而是寻找改动最小的那套权重。

第三，它保持各群体的人口规模不变。比如男性原本合计代表一万人，调完还是一万人；
变的只是男性内部合格者与不合格者之间的权重此消彼长，从而改变男性的合格率。
这一条很关键：它防止算法为了凑合格率而偷偷把男女、城乡的人口盘子改大改小，
那样得到的合格率是假的。

## 3. 准备两张表

你要准备两张表，都可以在 Excel 里做，放进同一个工作簿的两个工作表。

### 数据表

每行一个人。它至少要有一个是否合格的列、一个初始权重列、以及你要校准的那些分组列。
下面是一张干净的数据表的样子：

| sex | residence | qualified | initial_weight |
|-----|-----------|-----------|----------------|
| M   | Urban     | 1         | 1.20           |
| F   | Rural     | 0         | 0.80           |
| M   | Rural     | 1         | 1.05           |

几条硬性要求，违反了程序会直接拒绝：是否合格列只能是 0 或 1；初始权重必须全是正数；
分组列不能留空，没填的要先归成一个明确的类别，比如"未知"。

关于列名，这是最容易踩坑的地方，我说清楚。数据表的列名你叫什么都行，
但你在程序里引用它时必须一字不差地对上。上表里我用的是英文 sex、qualified，
你在运行时就得写 `outcome = "qualified"`。中文列名在中文 Windows 上一般也能用，
但在一些区域设置是 GBK 的旧机器上会因为编码不一致而报错。我的建议是数据表的列名统一用英文，
省去这类排查。

### 目标表

这张表告诉程序每个分组要达到多少。每行一个目标：

| variable  | level | target_rate | priority |
|-----------|-------|-------------|----------|
| .overall  | .all  | 0.70        | 5        |
| sex       | M     | 0.72        | 2        |
| sex       | F     | 0.68        | 2        |
| residence | Urban | 0.71        | 2        |
| residence | Rural | 0.685       | 2        |

第一行那个 `.overall` 配 `.all` 是固定写法，代表总体目标。其余每行：variable 列填分组变量名，
level 列填这个变量的某个类别，target_rate 填目标合格率，写成 0 到 1 之间的小数，七成就是 0.70。

目标表有两点和数据表不同，对你有利。其一，这张表的表头程序既认英文也认中文，
你写 variable / level / target_rate / priority 可以，写变量 / 类别 / 目标率 / 优先级也可以，
程序会自动对应。其二，正因为如此，目标表用中文表头是安全的，不会误导。
但要注意：variable 列里填的分组名，必须和数据表的列名对得上；level 列里填的类别，
必须和数据里那一列的实际取值对得上。比如数据表里性别列叫 sex、取值是 M 和 F，
目标表里就得写 variable=sex、level=M。

### 关于 priority 这一列

priority 是优先级，意思是当几个目标互相冲突、没法同时精确满足时，谁更重要。
数值越大越被优先照顾。上表里我把总体目标设成 5，性别和城乡设成 2，
表示总体最重要，分组目标次之。

实务中各处来的目标率多少会有些口径或舍入上的不一致，很难分毫不差地同时满足，
这时优先级决定算法往哪边让步。它不是一个"必须达到"的开关，而是冲突时的权衡砝码。
如果你拿不准，可以先都填一样的数，跑出来看看哪些目标差得多，再回头给重要的目标加码。
priority 这一列可以省略，省略时所有目标按同等重要处理。

## 4. 用 Excel 跑完整流程

准备好工作簿之后，把下面这几行交给会开 R 的同事，或者你自己照着改文件名和列名。
我先把整段放出来，再逐行解释。

```r
library(ratecalib)

result <- calibrate_from_excel(
  "你的输入文件.xlsx",
  outcome       = "qualified",
  weight        = "initial_weight",
  data_sheet    = "data",
  targets_sheet = "targets",
  mode          = "soft"
)

export_calibration_xlsx(result, "校准结果.xlsx")
```

第一行 `library(ratecalib)` 把这个工具加载进来，每次开新会话都要先跑这一行。

中间一大段是核心。`calibrate_from_excel` 是专为不写代码的人准备的入口，它一次把数据和目标都从
Excel 读进来并完成求解。等号左边的 `result` 是给计算结果起的名字，你可以叫别的，
但记住后面要用它。引号里的文件名换成你自己的工作簿。`outcome` 填是否合格那一列的列名，
`weight` 填初始权重那一列的列名，这两个名字必须和数据表里的列名完全一致。
`data_sheet` 和 `targets_sheet` 填这两张表所在工作表的名字。`mode = "soft"` 选软约束模式，
这是我建议大多数情况用的，后面第 6 节细说。

你可能注意到这里没有单独写分组变量。不用写，程序会从目标表的 variable 列自动认出来：
你在目标表里给 sex 和 residence 设了目标，它就知道要按 sex 和 residence 来校准。

优先级也不在这段代码里设，而是在目标表的 priority 列里设，就像第 3 节那张表那样。
这是 Excel 路径设优先级的正确位置。如果你的目标表没有 priority 列，所有目标按同等重要处理。

最后一行 `export_calibration_xlsx` 把算完的结果写成一个新的 Excel 文件。打开它你会看到好几个
工作表，下一节讲怎么看。

第一次使用前，请让同事先装好这几个包，只需装一次：

```r
install.packages(c("Matrix", "osqp", "openxlsx"))
```

## 5. 看懂结果

打开导出的 `校准结果.xlsx`，重点看三张工作表。

`data` 这张表是你的原始数据再加一列校准后的新权重，列名默认是 weight_calibrated。
以后做任何加权统计，用这一列，不要再用旧权重。

`target_check` 是最该先看的一张，它逐行告诉你每个目标达成得怎么样。target_rate 是你设的目标，
initial_rate 是校准前的加权合格率，achieved_rate 是校准后的，error 和 abs_error 是校准后与目标的差距。
abs_error 越接近零，说明这个目标贴合得越好。

`diagnostics` 是权重质量的体检表，我最看重其中两项。一项是 calibrated_ESS，叫有效样本量，
你可以理解成调完权重之后，这份样本相当于多少个分量均等的人。它比原始样本量低是正常的，
但如果掉得太狠，说明为了凑目标把权重拉得太极端，结论的可靠性会打折扣。另一项是
maximum_multiplier 和 minimum_multiplier，也就是权重被放大和缩小的最大倍数。
要是有人被放大到很离谱的倍数，得警惕，往往意味着目标太激进或者某个组的数据撑不起这个目标。

## 6. 三个最常调的旋钮

绝大多数实际工作，你只会反复调三样东西：模式、优先级、上下限。

模式有软和精确两种。精确模式要求所有目标分毫不差地同时达到，只要目标之间稍有矛盾，
它就会失败、什么都算不出来。软模式允许目标之间有一点小矛盾，会尽量靠近所有目标，
冲突时按优先级权衡。真实数据里各处口径很难完全自洽，所以我几乎总是从软模式开始，
只有在确信目标完全相容、且确实需要分毫不差时才用精确模式。

优先级前面讲过，是冲突时的权衡砝码，在目标表的 priority 列里设，数值越大越优先。

上下限限制每个人的权重最多被放大或缩小到几倍，默认是缩到 0.25 倍、放大到 4 倍。
卡得越窄，权重越稳健，但可能离目标更远；放得越宽，目标更容易达到，但容易出现极端权重，
有效样本量也会掉得更多。一般分析用默认的 0.25 到 4 就够了；目标和现状差得很远时，
可以放宽到 0.1 到 10，但要回头盯住有效样本量别掉太多。

## 7. 常见疑问

**精确模式为什么算不出来。** 多半是你给的目标本身做不到。最常见的是总体目标和分组目标对不上，
其次是某个组里的人全都合格或全都不合格，这种组光靠调权重永远改变不了它的合格率，
再就是上下限卡得太死。先换软模式，通常就能出结果。

**软模式误差还是偏大怎么办。** 可以把惩罚强度调大，让算法更使劲贴目标，
也可以适当放宽上下限给它更大的腾挪空间，同时盯住有效样本量。

**目标率能不能我自己定。** 技术上可以，但解释时要诚实。如果目标来自可靠的外部总体数据，
校准后的结果可以说成是在外部信息约束下的估计；如果目标只是你的期望值，
那校准后的合格率本质上是你设出来的，不能再当成独立得出的发现去汇报。这一点上我见过不少人栽跟头。

**分组变量是数字编码行不行。** 行。后面第二部分会专门讲。

---

# 第二部分：完整使用说明

这一部分把每个函数讲透，每段代码逐行解释，目标是让没碰过 R 的人也能完整操作。

## 8. 先认识几个符号

R 的代码里反复出现的就那么几个符号，先认全它们，后面就不费劲了。

`<-` 是赋值，把右边算出来的东西存进左边的名字，`x <- 5` 就是让 x 等于 5。
`函数名(参数)` 是调用一个函数，比如 `library(ratecalib)`。
引号 `"文本"` 把文字括起来，列名、文件名这类都要加引号。
`c(...)` 把几个值拼成一串，叫向量，`c(0.72, 0.68)` 是两个数。
`c(M = 0.72, F = 0.68)` 是带名字的一串，M 和 F 是名字，后面是对应的值。
`list(...)` 是列表，能把不同东西装在一起，分组目标就是用它装的。
`$` 从一个结果对象里取出某一部分，`fit$target_check` 取出 fit 里的达成表。
`#` 后面到行尾是注释，写给人看的，程序会忽略。

记住这八个，第二部分的代码你都读得懂。

## 9. 安装

```r
install.packages(c("Matrix", "osqp"))
install.packages("openxlsx")
install.packages("ratecalib_0.2.1.tar.gz", repos = NULL, type = "source")
library(ratecalib)
```

第一行装两个必需的底层包，Matrix 管矩阵运算，osqp 是求解器。第二行装 openxlsx，
只有用到 Excel 读写时才需要，平时可省。第三行从本地源码包安装 ratecalib 本身，
引号里换成你拿到的安装包文件名。最后一行加载，每次新开 R 都要跑。

这里要分清装和加载是两回事。装是用 install.packages 把包放到硬盘上，每个包装一次就够。
加载是用 library 把包请进当前这次会话，每次新开 R 都要重来。容易让人犯嘀咕的是：
Matrix、osqp、openxlsx 这几个依赖只需要装，不需要你去 library。
真正干活时你只写 library(ratecalib) 这一行就行。ratecalib 会自己在背后调用 Matrix 和 osqp，
用到 Excel 时再自己请出 openxlsx，都不需要你手动加载它们。
你唯一要保证的是它们已经装上，比如 openxlsx 没装，一调 Excel 函数就会提示你去装它。

macOS 上如果装 osqp 时报编译错误，先在终端跑一次 `xcode-select --install` 装上命令行工具再试。

## 10. 两层接口该选哪个

这个工具有两个主入口。`calibrate_rates` 是一步式的，你给它数据和各分组目标率，
它自动建目标表、认出分组、做数据检查、再求解，适合绝大多数人。
`calibrate_pass_rates` 是底层专业接口，要你自己准备好目标表，但换来对全部参数的完全掌控。
其实前者内部就是先替你把目标表建好，再调用后者。不写代码的人则用第一部分的
`calibrate_from_excel`，它从 Excel 进、从 Excel 出。

## 11. 一步式 calibrate_rates 逐参数详解

先看完整的一段，再逐个参数讲。

```r
fit <- calibrate_rates(
  data    = dat,
  outcome = "qualified",
  weight  = "initial_weight",
  overall = 0.70,
  groups  = list(
    sex       = c(M = 0.72, F = 0.68),
    residence = c(Urban = 0.71, Rural = 0.685)
  ),
  priority       = 5,
  group_priority = c(sex = 2, residence = 2),
  lower = 0.25,
  upper = 4,
  mode  = "soft",
  lambda = 1e4,
  new_weight = "weight_calibrated"
)
```

`data` 是你的数据框，也就是读进 R 的那张数据表。`outcome` 是是否合格那一列的列名，
`weight` 是初始权重那一列的列名，两个都要加引号，都要和数据里的列名一致。

`overall` 是总体目标合格率，这里要七成。如果你不想设总体目标，把这一行删掉即可。

`groups` 是各分组的目标，用 list 装。list 里每一项的名字是分组变量名，
值是一串带名字的目标率。`sex = c(M = 0.72, F = 0.68)` 的意思是：性别这个变量，
男性目标七成二、女性目标六成八。这里的 M 和 F 必须和数据里性别列的实际取值对得上。

`priority` 是总体目标的优先级，`group_priority` 是各分组目标的优先级。
`group_priority = c(sex = 2, residence = 2)` 给性别和城乡都设成 2。
你也可以只写一个数 `group_priority = 1`，那就所有分组目标一视同仁。
优先级只在软模式下、目标冲突时起作用，数值越大越优先。

`lower` 和 `upper` 是权重倍数的下限和上限，0.25 和 4 表示每个人的权重最少缩到原来的四分之一、
最多放大到四倍。

`mode` 选软约束还是精确约束，填 "soft" 或 "exact"，我建议从 "soft" 开始。

`lambda` 是软模式下的惩罚强度，默认一万。它越大，算法越使劲把合格率往目标上拉，
误差越小，但权重改动也越大。目标差得远又想贴得更紧时，可以加到十万、百万。

`new_weight` 是给新权重列起的名字，算完会以这个名字加到数据里。

算完得到的 `fit` 是一个结果对象，第 15 节讲怎么从里面取东西。

## 12. 自己建目标表 make_rate_targets

用专业接口前，得先有目标表。手拼容易出错，`make_rate_targets` 替你拼。

```r
targets <- make_rate_targets(
  overall = 0.70,
  groups  = list(sex = c(M = 0.72, F = 0.68)),
  overall_priority = 5,
  group_priority   = c(sex = 2)
)
```

参数和 `calibrate_rates` 里同名的那些含义完全一样。`overall_priority` 对应总体目标的优先级，
`group_priority` 对应分组目标的优先级。算出来的 `targets` 就是第一部分见过的那张目标表，
是一个普通的数据框，每行一个目标，你可以打印出来核对，也可以直接拿去喂给专业接口。

如果要校准更复杂的东西，`make_rate_targets` 还有三个进阶参数，分别建交互目标、均值或总量目标、
任意取值的占比目标，留到第 16 节细讲。

## 13. 求解前的检查与可行性预检

动手求解前，我习惯先跑两道检查，能省掉很多事后排查。

第一道是数据质量检查：

```r
report <- check_calibration_data(
  data       = dat,
  outcome    = "qualified",
  weight     = "initial_weight",
  group_vars = c("sex", "residence"),
  targets    = targets
)
report
```

`group_vars` 用 `c(...)` 列出你要校准的所有分组变量名。把 `report` 打印出来，
它会告诉你列齐没齐、权重是不是都为正、结果是不是只有 0 和 1、分组列有没有缺失、
每个目标在数据里支不支持，还会列出当前各组的加权合格率。
报告里 `report$group_summary` 是分组明细，`report$target_support` 是各目标的可支持情况。

第二道是可行性预检，专门看目标之间会不会自相矛盾：

```r
fz <- calibration_feasibility(
  data       = dat,
  outcome    = "qualified",
  weight     = "initial_weight",
  group_vars = "sex",
  targets    = make_rate_targets(overall = 0.62,
                                 groups = list(sex = c(M = 0.66, F = 0.60)))
)
fz
```

打印出来的 `fz` 会做两件事。一是一致性检查：如果某个分组变量的每个类别你都设了目标，
那么总体合格率其实已经被这些分组目标和各组人数唯一确定了。你要是再单独给一个对不上的总体目标，
精确模式就必然无解，这道检查能在求解前就把它指出来。二是逐个目标的可达区间：
在权重上下限之内，每个组的合格率最高能到多少、最低能到多少，目标若落在区间外就一定做不到。
`fz$consistency$consistent` 是一致性结论，真表示自洽，假表示有冲突。

## 14. 专业接口 calibrate_pass_rates

掌控全部参数时用它。

```r
fit <- calibrate_pass_rates(
  data       = dat,
  outcome    = "qualified",
  weight     = "initial_weight",
  group_vars = c("sex", "residence", "education5", "age5"),
  targets    = targets,
  lower = 0.25,
  upper = 4,
  mode  = "soft",
  distance = "chi2",
  lambda = 1e4,
  new_weight = "weight_calibrated"
)
```

它和一步式最大的区别是：分组要你自己用 `group_vars` 列全，目标要你自己用 `targets` 传进去。
`group_vars` 这里要列出所有需要保持人口规模不变的分组变量，哪怕某个变量你没给它设合格率目标。
比如上面 education5 和 age5 即使没有目标，列进来也会保证学历和年龄各段的人口规模在校准后不变。
这一点是专业接口的价值所在，你可以精确控制哪些边际被锁住。

`distance` 是校准距离，控制用什么尺子衡量权重的改动，默认 chi2，第 16 节会讲另外两种。
其余参数和一步式同名的完全一样。

## 15. 读懂结果对象

不管走哪个接口，算出来的 `fit` 都是同一种结果对象。下面是从里面取东西的常用方式。

```r
fit$data                 # 原数据加上新权重列
weights(fit)             # 直接取出校准后的权重向量
fit$target_check         # 每个目标的目标值、校准前后值、误差
fit$margin_check         # 人口边际保持情况
fit$diagnostics          # 权重质量体检
summary(fit)             # 打印摘要
plot(fit, "target_error")   # 画各目标误差
plot(fit, "multipliers")    # 画权重倍数分布
```

`fit$data` 取出带新权重的完整数据，`weights(fit)` 是只要权重向量时的快捷方式。
`fit$target_check` 是那张达成表。`fit$margin_check` 里有一列 relative_change，
它应该非常接近零，因为人口边际是被锁住的；要是不接近零，说明哪里出了问题。
`fit$diagnostics` 是体检表，前面讲过重点看有效样本量和最大最小倍数。
`summary(fit)` 给一份摘要打印，`plot` 的两种图分别看目标误差和权重倍数的分布。

## 16. 进阶目标类型

### 校准距离 chi2 / raking / logit

`distance` 参数三选一，控制权重改动的衡量方式。

```r
calibrate_pass_rates(..., distance = "raking")
```

默认的 chi2 是加减式的微调，靠上下限来防止权重变得离谱。
raking 是乘法式的微调，它算出来的权重天生不会变成负数或零，
代价是上方没有封顶，个别权重可能被放得很大。
logit 则把每个权重严格卡在下限和上限之间，一步都出不去，
适合那种必须硬性封顶极端权重的场合，用它时要保证下限小于 1、上限大于 1。
三种距离都支持软和精确两种模式。默认永远是 chi2，结果和过去一致，另外两种是按需选用。

### 交互目标

要校准城镇男性这种交叉群体，用冒号把变量和类别连起来。

```r
make_rate_targets(
  interactions = list("sex:residence" = c("M:Urban" = 0.75, "F:Rural" = 0.62))
)
```

`"sex:residence"` 表示按性别和城乡的交叉来定目标，`"M:Urban" = 0.75` 表示城镇男性这一格目标七成五。
要注意交互目标只新增这一条约束，不会自动锁住交叉格的人口规模，类别值本身也不能含冒号。

### 均值或总量目标

不只 0 和 1，还能让某个数值变量的加权均值或总量达到目标，比如收入。

```r
make_rate_targets(
  means  = data.frame(variable = ".overall", level = ".all",
                      value_var = "income", target = 52000),
  totals = data.frame(variable = "residence", level = "Urban",
                      value_var = "income", target = 1.2e8)
)
```

`means` 和 `totals` 各是一张小表，variable 和 level 指定在哪个组上校准，
value_var 指定要校准哪个数值列，target 是目标的均值或总量。
上面第一行让总体的加权平均收入达到五万二，第二行让城镇的收入总量达到一点二亿。

### 任意取值的占比

合格率本质上是"是否合格这一列等于 1 的占比"。要校准别的变量某个取值的占比，
包括那种用 1 和 2 而不是 0 和 1 编码的数据，用下面这种目标行。

```r
data.frame(variable = ".overall", level = ".all", target_rate = 0.40,
           statistic = "proportion", value_var = "grade", value = "A")
```

它的意思是：让总体里评级等于 A 的加权占比达到四成。`statistic` 写 proportion 表示这是占比目标，
`value_var` 是要看的那一列，`value` 是要算占比的那个取值。
这里要分清占比和均值是两回事。比如一列用 1 和 2 编码，你要的是"等于 1 的占比"，
就得用占比，算出来在 0 到 1 之间；要是错当成对原值取平均，会得到一点几那样的数，不是占比。

## 17. 重复权重方差估计

校准后的估计量是有抽样误差的，光给一个点估计不够。如果你按自己的抽样设计在外部生成了
若干套重复权重，比如自助法、刀切法或平衡半样本，就能用它们估出标准误。

```r
rc <- calibrate_replicate_weights(fit, repweights = repw, scale = 1, progress = TRUE)
v  <- replicate_variance(rc, x = dat$income, statistic = "total")
v$estimate
v$se
```

`calibrate_replicate_weights` 拿你已经算好的 `fit` 当模板，对每一套重复权重按同样的目标和设置
重新校准一遍。`repw` 是一个矩阵，每行一个人，每列一套重复权重。`progress = TRUE` 会显示进度条，
重复套数多时有用。`replicate_variance` 再用这些重算结果估方差，`x` 是你要估计的那个数值变量，
`statistic` 选 total 估总量、选 mean 估均值，返回里 estimate 是点估计，se 是标准误。
scale 这个常数要按你的重复方案来定，刀切法和自助法的取值不同。

## 18. 应用实例

下面的数字都来自 `example_rate_data(5000, seed = 2026)` 这份模拟数据，你照着跑能复现。

### 实例一：基础合格率校准

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

这份数据初始的总体合格率只有 0.6297，离七成的目标差了不少。校准之后达成表是这样：

| variable  | level | 目标  | 校准前 | 校准后 | 绝对误差 |
|-----------|-------|-------|--------|--------|----------|
| .overall  | .all  | 0.700 | 0.6297 | 0.7003 | 0.0003   |
| sex       | M     | 0.720 | 0.6326 | 0.7207 | 0.0007   |
| sex       | F     | 0.680 | 0.6268 | 0.6807 | 0.0007   |
| residence | Urban | 0.710 | 0.6415 | 0.7086 | 0.0014   |
| residence | Rural | 0.685 | 0.6070 | 0.6843 | 0.0007   |

五个目标全被拉到了非常接近的程度，最大误差才千分之一点四。再看体检，
样本量五千，有效样本量从 4614 只降到 4518，掉了大约百分之二，代价很小；
权重倍数落在 0.75 到 1.15 之间，相当温和。这说明这组目标和数据很相容，校准很轻松。

### 实例二：精确模式遇到矛盾目标，先预检

假设你想用精确模式，同时给总体定六成二、性别定男六成六女六成。求解前先预检：

```r
calibration_feasibility(
  dat, "qualified", "initial_weight", "sex",
  make_rate_targets(overall = 0.62, groups = list(sex = c(M = 0.66, F = 0.60)))
)
```

预检会告诉你，性别目标按各自人数加权后隐含的总体合格率是 0.6293，
而你写的总体目标是 0.62，两者对不上，一致性结论为假。这意味着精确模式必然算不出来。
解决办法有三个：把总体目标改成隐含的 0.6293，或者干脆不设总体目标，或者改用软模式让它尽量靠拢。
先预检再求解，就不会一头撞上无解的报错还摸不着头脑。

### 实例三：连续变量的均值校准

```r
dat$income <- round(rlnorm(nrow(dat), log(40000) + 0.5 * dat$qualified, 0.3))
tg <- make_rate_targets(
  means = data.frame(variable = ".overall", level = ".all",
                     value_var = "income", target = 52000)
)
fit <- calibrate_pass_rates(
  dat, "qualified", "initial_weight",
  group_vars = "residence", targets = tg, mode = "exact", lower = 0.1, upper = 10
)
w <- weights(fit)
sum(w * dat$income) / sum(w)
```

这里先给数据造了一列收入，让它和是否合格相关。目标是让加权平均收入达到五万二。
最后一行手工算校准后的加权平均收入，结果正好是 52000，目标精确达成。

### 实例四：交互目标

```r
tg <- make_rate_targets(interactions = list("sex:residence" = c("M:Urban" = 0.75)))
fit <- calibrate_pass_rates(
  dat, "qualified", "initial_weight",
  group_vars = c("sex", "residence"), targets = tg, mode = "exact"
)
w   <- weights(fit)
sub <- dat$sex == "M" & dat$residence == "Urban"
sum(w[sub] * dat$qualified[sub]) / sum(w[sub])
```

目标是把城镇男性这一交叉群体的合格率校到七成五。最后两行单独挑出城镇男性，
算他们的加权合格率，结果正好 0.75。

### 实例五：重复权重方差

```r
rc <- calibrate_replicate_weights(fit, repw, scale = 1)
replicate_variance(rc, dat$income, "mean")$se
```

假设 repw 是按你的抽样设计在外部生成的重复权重矩阵，这两行就给出校准后加权平均收入的标准误，
用来衡量这个估计有多稳。

### 分组变量用数字编码

分组列既可以是文字像 Urban 和 F，也可以是数字编码像学历段 1、2、3、4，还可以是因子。
程序内部一律把分组列当成类别处理，所以数字照样能用。下面这段能完整跑通：

```r
dat2 <- data.frame(grp = sample(1:4, 2000, TRUE),
                   qualified = rbinom(2000, 1, 0.6),
                   w = runif(2000, 0.5, 2))
fit2 <- calibrate_rates(
  dat2, "qualified", "w",
  groups = list(grp = c("1" = 0.72, "2" = 0.68, "3" = 0.64, "4" = 0.60)),
  mode = "soft"
)
```

唯一要留意的是，目标里写类别时按文字对应。数据里的数字 1，在目标里写成名字 "1"，
也就是 `c("1" = 0.72, ...)` 这种写法，程序会自动把数据里的 1 和目标里的 "1" 对上。
另外分组应当是离散的类别，不要拿连续的小数当分组，那种需求应该用前面的均值或总量目标来表达。
这条只针对分组列，是否合格那一列仍然必须是 0 和 1。

---

# 第三部分：数学原理

这一部分讲清楚方法背后的数学。不影响使用，看不懂可以跳过。公式用到的记号尽量随用随解释。

## 19. 加权合格率与线性化

设第 $i$ 个人的结果是 $y_i$，合格为 1、不合格为 0，校准后权重是 $w_i$。
某个分组 $j$ 的加权合格率是这个组里合格者的权重之和除以全组权重之和：

$$\hat r_j=\frac{\sum_i w_i I_{ij} y_i}{\sum_i w_i I_{ij}}$$

这里 $I_{ij}$ 在第 $i$ 人属于组 $j$ 时取 1，否则取 0。要让这个比例等于目标 $r_j^{*}$，
把分母乘到右边再移项：

$$\hat r_j=r_j^{*}\ \Longleftrightarrow\ \sum_i w_i I_{ij} y_i=r_j^{*}\sum_i w_i I_{ij}
\ \Longleftrightarrow\ \sum_i w_i I_{ij}\,(y_i-r_j^{*})=0$$

要特别说明的是，这个变换是**严格等价**，不是近似。只要全组权重之和 $\sum_i w_i I_{ij}$ 不为零，
"比例等于目标"和"上面这个等式成立"就是一回事。原本"比例等于某值"是一个带分母的非线性约束，
不好直接优化；化成上面这种对权重 $w$ 完全线性的等式之后，整个问题就落进了线性约束的框架，
可以交给成熟的二次规划或对偶迭代求解。

再点一个实务含义。这个约束控制的是合格者的加权人数 $\sum_i w_i I_{ij} y_i$。
由于后面会把全组权重之和 $\sum_i w_i I_{ij}$ 用边际约束钉死，控制了合格者的加权人数，
也就等于控制了合格率本身。换句话说，调合格率的自由度，全在"把权重在组内的合格者与不合格者
之间挪动"这件事上。

## 20. 先聚合再优化

很多人的分组和结果完全相同。把分组交叉和结果状态都相同的人合并成一个单元，
每个单元只记初始权重之和 $D_c=\sum_{i\in c} d_i$，求解的未知数变成各单元校准后的总权重 $x_c$。

这样做为什么不损失任何东西，值得说清楚。前面所有的约束和目标函数，都只通过"单元内的权重之和"
这一个量来依赖数据：边际约束是若干单元权重之和，合格率约束也是若干单元权重之和，
目标函数 $\sum_c(x_c-D_c)^2/D_c$ 同样只看单元总量。也就是说，同一单元里的两个人对任何约束、
任何代价都是无差别的。既然无差别，最优解自然会给他们相同的调整倍数。于是我们可以放心地
只对单元总量 $x_c$ 求解，事后令单元内每个人的倍数都等于 $g_c=x_c/D_c$，把这个倍数乘回个人初始权重。

降维的效果很可观。设决策变量个数 $m$ 等于实际观测到的单元数，它至多是各分组变量类别数与结果状态数的
乘积。举例来说，两种性别、两种城乡、五段学历、五段年龄、两种结果状态，理论上最多
$2\times2\times5\times5\times2=200$ 个单元。哪怕原始数据有几十万人，核心优化问题也就两百来个未知数，
$m$ 与样本量 $n$ 无关。这就是它在大样本上依然很快的原因。

实现上，单元的标识键用一个控制字符把各分组取值和结果状态拼起来，这样能避开数据里普通字符造成的拼接歧义。

## 21. 目标函数与边际硬约束

默认的 chi2 距离下，要最小化的是权重改动的代价：

$$\min_x\ \sum_c \frac{(x_c-D_c)^2}{D_c}$$

它是校准前后权重之间的卡方距离，度量校准后权重相对初始值偏离了多少。
分母上的 $D_c$ 起到标准化作用：同样大小的绝对偏移，发生在初始权重小的单元上罚得更重，
所以它倾向于按比例温和地调整，而不是猛拉某几个单元。

这个目标可以化成标准二次规划的形式 $\tfrac12 x^{\top}Px+q^{\top}x$，便于交给求解器。把式子展开：

$$\sum_c\frac{(x_c-D_c)^2}{D_c}=\sum_c\frac{x_c^2}{D_c}-2\sum_c x_c+\sum_c D_c$$

末项 $\sum_c D_c$ 是常数，与 $x$ 无关，求最小时可以丢掉。剩下两项对照标准形式，
就得到对角矩阵 $P=\operatorname{diag}(2/D_c)$ 和常向量 $q=-2\cdot\mathbf 1$。

与此同时有两类必须满足的硬约束。一类是总量不变，所有单元权重之和等于初始总权重 $\sum_c x_c=\sum_c D_c$。
另一类是每个分组变量的各个类别总量不变，比如男性的总权重、城镇的总权重都保持原值。
这两类约束就是前面说的保持人口规模，它防止算法靠改变群体大小来凑合格率。

这里有个技术细节。每个分组变量的各类别总量之和，本就等于总量，所以最后一个类别的约束是多余的，
它可以由总量约束减去其余类别推出。把它一并写进去会让约束矩阵出现线性相关、秩亏，给求解添麻烦。
因此实现时对每个分组变量都去掉最后一个类别的约束。去掉一条冗余的等式不改变可行域，结果完全一样。

## 22. 软约束与精确约束的数学差别

精确模式把合格率目标也当成硬约束，就是第 19 节那个等于零的线性等式，和边际约束并列。
只要目标之间稍有矛盾，可行域就空了，求解器报无解。

软模式不把目标当硬约束，而是改成惩罚项加进目标函数。达不到目标允许，但偏得越多罚得越狠：

$$\min_x\ \sum_c \frac{(x_c-D_c)^2}{D_c}\;+\;\sum_j \lambda_j\Big(\sum_c x_c I_{cj}(y_c-r_j^{*})\Big)^2$$

它在"少动权重"和"贴近目标"之间找平衡。注意边际约束仍然是硬的，软化的只是合格率目标。
每个目标的惩罚权重取成

$$\lambda_j=\frac{\lambda\cdot N\cdot \text{priority}_j}{\text{size}_j^{2}}$$

其中 $N$ 是总权重，$\text{size}_j$ 是该组的初始权重之和。这个 $\text{size}_j^2$ 放在分母上不是随手写的，
它让惩罚变得与组的大小无关。看一下惩罚项里那个括号：

$$\sum_c x_c I_{cj}(y_c-r_j^{*})=\big(\hat r_j-r_j^{*}\big)\cdot\text{size}_j$$

也就是"组的合格率误差"乘以"组的大小"。代回惩罚项，$\text{size}_j^2$ 正好和括号平方里的
$\text{size}_j^2$ 抵消，剩下

$$\lambda_j\Big(\sum_c x_c I_{cj}(y_c-r_j^{*})\Big)^2=\lambda\cdot N\cdot\text{priority}_j\cdot\big(\hat r_j-r_j^{*}\big)^2$$

于是惩罚实际罚的是合格率误差的平方，大组小组一视同仁，不会因为某个组人多就被过度偏袒。
参数 $\lambda$ 越大、某目标的 priority 越高，它就被拉得越紧。这就是优先级在数学上起作用的地方。

总量这类目标的右端不是零，惩罚的是 $\big(\sum_c x_c I_{cj}\bar W_c-T\big)^2$，展开后除了二次项还会多一个
一次项，并到 $q$ 里即可。均值和总量因为量纲和合格率不同，惩罚还会再按目标的量级归一化，
使不同量纲的目标罚得可比。

## 23. 距离函数族与对偶

卡方只是一类更广的方法里的一个特例。把校准写成一个通用形式：在保持各约束
$A x=t$ 成立的前提下，最小化总的距离 $\sum_c D_c\,G(g_c)$，其中 $g_c=x_c/D_c$ 是调整倍数，
$G$ 是一个衡量"倍数偏离 1 多远"的距离函数。这个 $G$ 满足 $G(1)=0$、$G'(1)=0$、$G''(1)=1$，
意思是不调整时代价为零，且在 1 附近表现得像二次函数。这一族就是 Deville 和 Särndal 1992 年提出的校准估计量。

用拉格朗日乘子 $\lambda$ 处理约束 $A x=t$，对 $x$ 求驻点，会得到一个很漂亮的结构：
最优倍数只通过一个标量线性预测子 $\eta_c$ 决定，

$$g_c=g(\eta_c),\qquad \eta_c=(A^{\top}\lambda)_c$$

这里 $A$ 是把所有约束按行摞起来的矩阵，$\eta_c$ 是第 $c$ 个单元在这些约束上的"对偶打分"。
不同的距离 $G$ 给出不同的 $g$：

$$
\begin{aligned}
\text{卡方 } &G(g)=\tfrac12(g-1)^2 &&\Rightarrow\ g(\eta)=1+\eta &&\text{可正可负，靠上下限裁剪}\\
\text{熵 raking } &G(g)=g\log g-g+1 &&\Rightarrow\ g(\eta)=e^{\eta} &&\text{恒正，上方无界}\\
\text{logit } &\text{见 D-S 1992} &&\Rightarrow\ g(\eta)\in(L,U) &&\text{解析地卡在上下限之间}
\end{aligned}
$$

其中 logit 的 $g(\eta)$ 是一条把 $\eta$ 压进区间 $(L,U)$ 的 S 形曲线，$L$ 和 $U$ 就是你设的下限和上限，
$\eta=0$ 时 $g=1$，三种距离在 $\eta=0$ 附近的一阶行为都一样。

卡方因为 $g$ 是线性的，整体是个二次规划，可以直接用 OSQP 解。熵和 logit 的 $g$ 是非线性的，
没有现成的二次规划解法，于是改用对偶牛顿法去求那个让约束成立的 $\lambda$。
把单元权重写成 $x(\lambda)=D\,g(A^{\top}\lambda)$，要解的方程是

$$F(\lambda)=A\,x(\lambda)-t=0,\qquad J=A\,\operatorname{diag}\!\big(D\,g'(\eta)\big)A^{\top}$$

每步牛顿更新 $\lambda\leftarrow\lambda-J^{-1}F$，并配一个回溯线搜索，确保残差逐步下降、迭代稳健。
目标确实不可达时它不会乱收敛，而是报告未收敛。

软模式怎么进来。把硬约束 $A x=t$ 里的合格率那几行换成"带二次惩罚的软约束"，
再走一遍对偶推导，会发现结构几乎不变，只是对偶方程多出一个岭式正则项：

$$F(\lambda)=A\,x(\lambda)-t+\operatorname{reg}\odot\lambda,\qquad J=A\,\operatorname{diag}\!\big(D\,g'(\eta)\big)A^{\top}+\operatorname{diag}(\operatorname{reg})$$

边际那几行的 $\operatorname{reg}$ 取零，保持硬约束；合格率那几行取一个正的 $\operatorname{reg}=1/(2\lambda_j)$，
就是第 22 节那个惩罚的强度。$\operatorname{reg}$ 越小越接近精确，趋于零就还原成硬约束。
加这一项还让雅可比变正定，迭代更稳。这正是第 22 节惩罚校准在距离族里的统一写法。

## 24. 统计量泛化

合格率不是唯一能校准的统计量。先看一个关键的代数事实。任何对个人的线性汇总，
按单元拆开后都能写成"单元总权重乘以单元级常数"。设某个对个人的取值是 $f_i$，那么单元 $c$ 内的加权汇总

$$\sum_{i\in c} x_i f_i=g_c\sum_{i\in c} d_i f_i=x_c\cdot\frac{\sum_{i\in c} d_i f_i}{D_c}=x_c\cdot\bar f_c$$

其中 $\bar f_c=\sum_{i\in c} d_i f_i/D_c$ 是单元内 $f$ 的初始加权均值，一个固定的数。
关键就在第一个等号：单元内每个人共用同一个倍数 $g_c$，所以可以提到求和号外面。
于是任何线性目标都能统一写成 $\sum_c x_c\,I_{cj}\,a_c=t_j$，对决策变量 $x$ 是线性的，
$a_c$ 是某个单元级充分统计量，$t_j$ 是右端：

| 统计量 | 单元级 $a_c$ | 右端 $t_j$ |
|--------|-------------|-----------|
| 占比，变量 $Z$ 取值 $v$ | 单元内 $I(Z=v)$ 的加权比例 | 0，行内配 $-\,p^{*}$ 项 |
| 均值，数值变量 $W$ | $\bar W_c=\sum_{i\in c} d_i W_i/D_c$ | 0，行内配 $-\,m^{*}$ 项 |
| 总量，数值变量 $W$ | $\bar W_c$ | 目标总量 $T$ |

合格率就是"占比"在 $Z$ 取是否合格、$v$ 取 1 时的特例。

这里有个实务上很要紧的区别，关系到"能不能精确达成"。占比目标如果按那个分类变量把单元拆纯，
$a_c$ 就只取 0 或 1，组内占比可以在 0 到 1 之间被完全控制，所以能精确达成，这正是 0/1 合格率精确可达的原因。
连续变量没法这样拆纯，$\bar W_c$ 是个落在区间内的小数，此时组的均值只能在各单元均值的凸包内移动，
这是均值校准固有的、也是标准的处理方式。一句话：分类占比靠拆单元拿到完全控制，连续量靠充分统计量做凸组合。

## 25. 目标可行性的两条确定性判断

预检不试图判定"一定能解"，那等于把问题求解一遍。它只做两件确定、便宜、可靠的判断。

第一件是一致性恒等式。各分组的人口总量被边际约束锁死之后，如果某个分组变量的每个类别 $\ell$
都设了精确目标 $r_\ell$，那么总体合格率根本不是自由的，它被唯一确定了。
推导很直接：该变量各类别恰好不重不漏地划分全体，校准后合格者总权重等于各类别合格者权重之和
$\sum_\ell W_\ell r_\ell$，全体总权重等于 $\sum_\ell W_\ell=N$，两者相除：

$$\hat r_{\text{总体}}=\frac{\sum_\ell W_\ell\,r_\ell}{\sum_\ell W_\ell}$$

这里 $W_\ell$ 是类别 $\ell$ 被锁死的初始权重总量。你若再单独给一个对不上这个值的总体目标，
或者再有第二个分组变量也各类别齐全却推出不同的总体率，精确模式就必然无解。
这个判断是闭式的、零成本的，所以预检能在求解前精确抓出这类最常见的设定错误。

第二件是单目标可达区间。某组总量 $W$ 固定，组内合格者初始权重和为 $P$、不合格者为 $F$，$W=P+F$，
每个单元倍数限在 $[L,U]$ 之内。问这个组的合格率最高能到多少。合格率等于合格者权重除以 $W$，
而 $W$ 固定，所以等价于问合格者权重 $P'$ 最大能到多少。要把 $P'$ 顶高，
就把不合格那边压到最低、合格那边抬到最高。因为上下限对组内所有单元一致，
不合格权重最低是 $L F$，于是合格权重至多是"总量减去不合格的最低"，即 $W-LF$；
同时合格那边自己也封顶在 $U P$。两者取小：

$$P'_{\max}=\min(U P,\ W-L F),\qquad P'_{\min}=\max(L P,\ W-U F)$$

除以 $W$ 就得到合格率的可达区间。这是一个两段式的注水问题，正好有闭式解，不需要迭代。
目标落在这个区间之外就一定做不到。

要诚实地提醒一句：这只是必要条件，不是充分条件。每个目标单看都落在自己的区间内，
并不保证它们摆在一起还联合可行，因为一个单元同时属于多个分组，重叠的样本把多个目标牵连在一起。
真要判定联合可行，代价基本等于直接求解。所以预检的定位是"便宜地排除明显不可行"，而非"保证可行"。

## 26. 方差估计

校准后的估计量有抽样误差，光给点估计不够。直接套用普通的方差公式是错的，
因为校准把外部信息加了进来，权重不再是独立同分布。正确的做法是把"校准"这一整套操作
当成估计量的一部分，连同它一起重复评估。这正是重复权重法的思路。

具体地，你按自己的抽样设计在外部生成若干套重复权重，每套相当于对原样本的一次扰动。
对每一套重复权重，用和正式估计完全相同的目标和设置**重新校准一遍**，得到该套下的估计 $\hat\theta_r$。
再与全样本估计 $\hat\theta_0$ 比较。方差估计是各套估计相对全样本估计的离差平方的加权和：

$$\widehat{\operatorname{Var}}(\hat\theta)=\text{scale}\cdot\sum_r \text{rscales}_r\,(\hat\theta_r-\hat\theta_0)^2$$

之所以"对每套都重新校准"，是因为校准本身会改变方差，跳过它会低估或扭曲不确定性。
常数 $\text{scale}$ 和 $\text{rscales}_r$ 由你的重复方案决定：刀切法、平衡半样本、自助法各有取法，
和 `survey` 包里 `svrepdesign` 的参数一致。这里把离差中心取在全样本估计 $\hat\theta_0$ 上，
是校准场合常用的约定。一个有用的自检：如果某个量恰好被目标精确钉死，它在每套重复下都一样，
方差自然算出来近似为零，这与直觉相符。

## 27. 有效样本量与设计效应

不等的权重会损失统计效率。有效样本量衡量加权后这份样本相当于多少个分量均等的观测，
用的是 Kish 的定义：

$$\text{ESS}=\frac{\big(\sum_i w_i\big)^2}{\sum_i w_i^2}$$

当所有权重相等时，$\text{ESS}$ 正好等于真实样本量 $n$；权重越参差，分母相对分子越大，$\text{ESS}$ 越小。
它的含义是：一个等权的简单随机样本要达到当前加权估计同样的精度，大约需要这么多个观测。

与之配套的是权重带来的设计效应，近似等于一加上权重变异系数的平方：

$$\text{DEFF}_w\approx 1+\text{CV}(w)^2,\qquad \text{CV}(w)=\frac{\operatorname{sd}(w)}{\operatorname{mean}(w)}$$

它衡量不等权重把估计方差放大了多少倍。$\text{ESS}$ 与 $n$、$\text{DEFF}_w$ 之间近似有 $\text{ESS}\approx n/\text{DEFF}_w$。
权重越不均匀，有效样本量越低、设计效应越大，意味着为了达成目标在统计效率上付出的代价越高。
我的经验是把校准前后的 $\text{ESS}$ 摆在一起看：掉得多，就说明目标相对数据太激进，该回头斟酌目标或放宽限制。
这两个数是判断校准结果可不可信的关键。

## 28. 推荐参考文献

想深入这套方法的理论，下面按主题给出权威来源。**校准估计量的奠基与综述**首推
Deville 与 Särndal 1992 年那篇，它正是本工具距离函数族的源头；要系统读，
Särndal、Swensson 与 Wretman 的教材是标准参考。

校准方法核心

- Deville, J.-C., & Särndal, C.-E. (1992). Calibration Estimators in Survey Sampling. *Journal of the American Statistical Association*, 87(418), 376–382.
- Deville, J.-C., Särndal, C.-E., & Sautory, O. (1993). Generalized Raking Procedures in Survey Sampling. *Journal of the American Statistical Association*, 88(423), 1013–1020.
- Särndal, C.-E. (2007). The Calibration Approach in Survey Theory and Practice. *Survey Methodology*, 33(2), 99–119.
- Devaud, D., & Tillé, Y. (2019). Deville and Särndal's Calibration: Revisiting a 25-Year-Old Successful Optimization Problem. *TEST*, 28(4), 1033–1065.

惩罚校准，对应本工具的软模式

- Guggemos, F., & Tillé, Y. (2010). Penalized Calibration in Survey Sampling: Design-Based Estimation Assisted by Mixed Models. *Journal of Statistical Planning and Inference*, 140(11), 3199–3212.

抽样理论与方差估计教材

- Särndal, C.-E., Swensson, B., & Wretman, J. (1992). *Model Assisted Survey Sampling*. Springer.
- Wolter, K. M. (2007). *Introduction to Variance Estimation* (2nd ed.). Springer. 重复权重、刀切、平衡半样本、自助法。
- Lumley, T. (2010). *Complex Surveys: A Guide to Analysis Using R*. Wiley. R 中 survey 包与重复权重设计的对标。

有效样本量与设计效应

- Kish, L. (1965). *Survey Sampling*. Wiley.
- Kish, L. (1992). Weighting for Unequal Pi. *Journal of Official Statistics*, 8(2), 183–200.

优化与求解器背景

- Boyd, S., & Vandenberghe, L. (2004). *Convex Optimization*. Cambridge University Press. 二次规划、对偶与牛顿法的背景。
- Stellato, B., Banjac, G., Goulart, P., Bemporad, A., & Boyd, S. (2020). OSQP: An Operator Splitting Solver for Quadratic Programs. *Mathematical Programming Computation*, 12(4), 637–672. 本工具卡方距离所用的求解器。

---

# 问题速查

分两部分。先按现象快速定位，再按函数给出全套报错原文和应对。报错信息都是英文，
下表照原文列出，方便你直接对照屏幕。带省略号的地方表示程序会填进具体的列名、数值或类别。

## 按现象快速定位

| 现象 | 多半的原因 | 怎么办 |
|------|-----------|--------|
| 精确模式报无解或不可行 | 目标自相矛盾，或某组全合格全不合格，或上下限太窄 | 先跑 calibration_feasibility 预检；改软模式；放宽 lower 和 upper |
| 预检显示一致性为假 | 总体目标和分组目标隐含的总体率对不上 | 把总体目标改成隐含值，或删掉总体目标，或改软模式 |
| 软模式误差偏大 | 惩罚太弱，或目标本就难达 | 把 lambda 调到十万或百万；给重要目标加 priority；适当放宽上下限 |
| 校准后有效样本量大降 | 权重被拉得太极端 | 收紧上下限；放缓过激的目标；核对目标是否现实 |
| 出现很大的权重倍数 | chi2 距离遇上激进目标 | 改用 logit 距离硬封顶，或收紧 upper |
| 某组目标怎么都达不到 | 该组样本全合格或全不合格 | 光调权重改不了，需要补样本或放弃该组目标 |
| 报错说结果列不是 0 和 1 | 结果列编码不对 | 先把它编码成 0 和 1；若要算某取值占比用 value_var 和 value |
| 报错权重含零或负或缺失 | 初始权重不合法 | 确保初始权重全为正、无缺失 |
| 报错分组变量有缺失 | 分组列有空白 | 把缺失先归成一个明确类别，比如未知 |
| Excel 函数报缺少 openxlsx | 没装可选依赖 | 运行 install.packages("openxlsx") |
| 中文变量名在旧 Windows 报编码错 | 区域设置不是 UTF-8 | 变量名改用英文，函数名和参数名本就是英文 |
| 想要权重恒正或硬性封顶 | 距离选择问题 | 要恒正用 distance 设 raking，要封顶用 logit |
| 想知道估计有多稳 | 需要标准误 | 用 calibrate_replicate_weights 配 replicate_variance |
| 分组变量是数字编码 | 不确定支不支持 | 支持，目标类别按文字写如 c("1" = 0.72)；分组须离散，连续值改用均值或总量目标 |

## 全套报错对照手册

下面按报出错误的函数分组。报错原文一字不差，旁边给出触发条件和应对。

### 求解器 calibrate_pass_rates 和一步式 calibrate_rates 的输入校验

| 报错原文 | 触发条件 | 应对 |
|---------|---------|------|
| `Package 'osqp' is required. Run install.packages('osqp').` | 没装求解器 osqp | 运行 install.packages("osqp") |
| `Package 'Matrix' is required. Run install.packages('Matrix').` | 没装 Matrix | 运行 install.packages("Matrix") |
| `data must be a data frame.` | data 传的不是数据框 | 把数据读成 data.frame 再传 |
| `outcome must be one column name.` | outcome 不是单个列名字符串 | 写成一个列名，如 outcome = "qualified" |
| `weight must be one column name.` | weight 不是单个列名字符串 | 写成一个列名，如 weight = "initial_weight" |
| `group_vars must contain at least one column name.` | 没给分组变量 | 至少给一个分组变量名 |
| `group_vars must not contain duplicates.` | 分组变量名有重复 | 去掉重复项 |
| `Missing columns in data: ...` | outcome/weight/分组列在数据里找不到 | 核对列名拼写，与数据完全一致 |
| `targets is missing columns: ...` | 目标表缺 variable/level/target_rate | 补齐这三列，用 make_rate_targets 最稳 |
| `Use scalar bounds satisfying 0 <= lower <= 1 <= upper and lower < upper.` | 上下限不合法 | 让 lower 不超过 1、upper 不小于 1、且 lower 小于 upper |
| `lambda must be one finite positive number.` | lambda 非正或非有限 | 给一个正数，默认 1e4 |
| `Initial weights must all be finite and strictly positive.` | 初始权重含 0、负数、缺失或无穷 | 清洗权重列，确保全为正且有限 |
| `The outcome column must contain only 0 and 1.` | 结果列不是纯 0/1 | 先编码成 0/1；若要算某取值占比改用 value_var 和 value |
| `Grouping variables contain missing values. Recode missing values as a category first.` | 分组列有缺失 | 把缺失归成一个明确类别，如 "未知" |
| `targets must contain at least one row.` | 目标表是空的 | 至少给一个目标 |
| `All target_rate values must be finite.` | 目标值含缺失或无穷 | 检查目标列 |
| `proportion target_rate values must be between 0 and 1.` | 占比类目标不在 0 到 1 之间 | 占比写成小数；若这是均值或总量目标，要标对 statistic |
| `priority must contain finite positive numbers.` | 优先级非正或非有限 | 优先级填正数 |
| `statistic must be one of: proportion, mean, total` | statistic 列写了别的词 | 只能填这三个之一 |
| `Targets with statistic 'mean' or 'total' require a value_var.` | 均值或总量目标没指定数值列 | 补 value_var，指向要校准的数值列 |
| `targets contains duplicate target rows.` | 有两行目标完全重复 | 去重；同变量不同取值的占比目标算不同行，不冲突 |

### 目标行构造阶段的报错

| 报错原文 | 触发条件 | 应对 |
|---------|---------|------|
| `Proportion value_var(s) not found in data: ...` | 占比目标的 value_var 不是数据里的列 | 核对列名 |
| `value_var '...' is not a column in data.` | 均值或总量目标的 value_var 找不到 | 核对列名 |
| `value_var '...' must be numeric and free of missing values.` | 均值或总量的数值列含非数字或缺失 | 清洗该数值列 |
| `Interaction target '...' = '...' has a mismatched number of component variables and levels.` | 交互目标冒号两边数量对不上，如变量两段、类别一段 | 让 variable 和 level 的冒号段数一致 |
| `Interaction target variable(s) not in group_vars: ...` | 交互目标里的某个变量没列进 group_vars | 把它加进 group_vars |
| `Target variable '...' is not in group_vars. Use '.overall' for the total target.` | 目标里的变量既不是分组变量也不是总体 | 把变量加进 group_vars，或总体目标用 .overall |
| `No observed sample cell for target: ... = ...` | 目标指向的类别在数据里没有样本 | 核对类别名，或去掉这个没样本的目标 |
| `distance='logit' requires lower < 1 < upper.` | 用 logit 距离但上下限没把 1 夹在中间 | 让 lower 小于 1、upper 大于 1 |

### 求解失败的报错

| 报错原文 | 触发条件 | 应对 |
|---------|---------|------|
| `Optimization did not solve successfully. OSQP status: ...` 后接精确模式提示 `The targets may be mutually inconsistent or the bounds may be too narrow. Try mode='soft', or widen lower/upper.` | chi2 精确模式无解 | 先跑可行性预检；改软模式；放宽上下限 |
| 同上但软模式提示 `Try widening lower/upper or reducing numerical strictness.` | chi2 软模式数值上没解出 | 放宽上下限，或检查数据是否异常 |
| `The raking dual iteration did not converge ... The exact targets may be infeasible or unreachable, for example an all-pass or all-fail group; try mode='soft'.` | raking 精确模式不收敛，目标多半不可达 | 改软模式；核对是否有全合格全不合格的组 |
| `The logit dual iteration did not converge ... within (lower, upper); try widening the bounds or ... mode='soft'.` | logit 精确模式在上下限内做不到 | 放宽上下限或改软模式 |
| `The raking/logit dual iteration did not converge ... Try a smaller lambda or distance='chi2'.` | raking 或 logit 软模式没收敛 | 调小 lambda，或改用 chi2 |

### 目标表构造 make_rate_targets 的报错

| 报错原文 | 触发条件 | 应对 |
|---------|---------|------|
| `groups must be a named list.` | groups 不是带名字的列表 | 写成 list(sex = c(M = 0.7, F = 0.68)) 这种形式 |
| `overall must be NULL or one number between 0 and 1.` | 总体目标不在 0 到 1 | 填 0 到 1 之间的小数，或不设则留空 |
| `overall_priority must be one finite positive number.` | 总体优先级非正 | 填一个正数 |
| `group_priority must be a scalar or a named vector.` | 分组优先级格式不对 | 填一个数，或按变量命名的向量 |
| `Each groups element must be a named numeric vector: ...` | 某分组的目标没给类别名 | 写成 c(M = 0.7, F = 0.68)，类别要带名字 |
| `All rates in groups[['...']] must be between 0 and 1.` | 某分组目标率越界 | 改成 0 到 1 之间 |
| `Missing or invalid group_priority for variable: ...` | 缺某变量的优先级或为非正 | 给该变量一个正的优先级 |
| `interactions must be a named list.` | 交互目标格式不对 | 写成 list("sex:residence" = c("M:Urban" = 0.7)) |
| `Each interactions element must be a named numeric vector: ...` | 交互目标没给类别组合名 | 类别组合要带名字，如 "M:Urban" = 0.7 |
| `All rates in interactions[['...']] must be between 0 and 1.` | 交互目标率越界 | 改成 0 到 1 之间 |
| `interaction_priority must be a scalar or a named vector.` | 交互优先级格式不对 | 填一个数或按交互键命名的向量 |
| `Missing or invalid interaction_priority for: ...` | 缺某交互的优先级或为非正 | 给该交互一个正的优先级 |
| `mean/total/proportion must have columns: ...` | means、totals 或 proportions 的小表缺列 | 按要求补 variable、level、value_var、target 等列 |
| `All mean/total/proportion target values must be finite.` | 这些目标的 target 值含缺失或无穷 | 检查 target 列 |

### 数据检查 check_calibration_data 报告里的条目

这个函数不直接中断，而是把问题装进报告的 errors、warnings 和 target_support 里返回；
一步式 `calibrate_rates` 在 check 为真时，遇到 errors 会中断、遇到 warnings 会提醒。

| 报告里的文字 | 含义 | 应对 |
|------------|------|------|
| `Missing columns: ...` | 必要的列缺失 | 补齐列 |
| `Initial weights contain missing or non-finite values.` | 权重有缺失或无穷 | 清洗权重 |
| `All initial weights must be greater than 0.` | 权重有非正值 | 改成正数 |
| `The outcome column must contain only 0 and 1.` | 结果列不是 0/1 | 编码成 0/1 |
| `Grouping variables contain missing values; recode missing values as an explicit category first.` | 分组列有缺失 | 缺失归成明确类别 |
| `targets must contain the columns variable, level and target_rate.` | 目标表缺列 | 补齐 |
| `There are N target(s) not supported by the data; see target_support.` | 有目标数据撑不起 | 看 target_support 逐条排查 |
| 警告 `... = ... contains only passing/failing units; its target rate cannot be changed by reweighting within the group.` | 某组全合格或全不合格 | 该组合格率调不动，删掉它的目标或补样本 |
| 警告 `Targets imply conflicting overall rates ...` | 分组目标隐含的总体率与显式总体目标实质性不一致 | 对齐总体目标，或改软模式；细看用 calibration_feasibility |
| target_support 里 `target variable is not in group_vars` | 目标变量没列进分组 | 加进 group_vars |
| target_support 里 `no sample in this category` | 该类别没样本 | 核对类别名或去掉该目标 |
| target_support 里 `group is all 0; a target above 0 is unreachable` | 该组全不合格 | 调不动，删目标或补样本 |
| target_support 里 `group is all 1; a target below 1 is unreachable` | 该组全合格 | 同上 |
| target_support 里 `not checked (interaction or non-outcome statistic target)` | 该目标是交互或非合格率统计量，检查会跳过它 | 属正常，不是错误 |

### 可行性预检 calibration_feasibility 的报错

| 报错原文 | 触发条件 | 应对 |
|---------|---------|------|
| `data must be a data frame.` | data 不是数据框 | 传 data.frame |
| `Missing columns: ...` | 引用的列不存在 | 核对列名 |
| `targets must contain the columns variable, level and target_rate.` | 目标表缺列 | 补齐 |

### Excel 读写函数的报错

| 报错原文 | 触发条件 | 应对 |
|---------|---------|------|
| `Reading or writing Excel files requires the 'openxlsx' package. Install it with install.packages("openxlsx").` | 没装 openxlsx | 运行 install.packages("openxlsx") |
| `File not found: ...` | 路径里的文件不存在 | 核对文件名和工作目录 |
| `The target sheet is missing required column(s): ...` | 目标工作表缺必要列 | 补齐 variable、level、target_rate，表头中英文均可 |
| `fit must be a pass_rate_calibration object.` | 导出时传的不是校准结果 | 传 calibrate_pass_rates 或 calibrate_rates 的返回值 |

### 重复权重方差 calibrate_replicate_weights 和 replicate_variance 的报错

| 报错原文 | 触发条件 | 应对 |
|---------|---------|------|
| `fit must be a pass_rate_calibration object.` | 第一个参数不是校准结果 | 传校准返回的 fit |
| `repweights must have one row per observation in fit.` | 重复权重矩阵行数和样本数不符 | 让矩阵每行对应一个样本 |
| `repweights must have at least one column.` | 没有任何一套重复权重 | 至少给一列 |
| `Replicate weights must all be finite and positive.` | 重复权重含非正或非有限值 | 清洗重复权重 |
| `rscales must have one value per replicate.` | rscales 长度和重复套数不符 | 让 rscales 每套一个值 |
| `Calibration failed for replicate r: ... Consider mode='soft' for robust replicate calibration.` | 某套重复权重在精确模式下重校准失败 | 改用软模式跑重复校准更稳 |
| `object must be a replicate_calibration object.` | replicate_variance 第一个参数不对 | 传 calibrate_replicate_weights 的返回值 |
| `x must have one value per observation.` | 估计变量长度和样本数不符 | 让 x 每个样本一个值 |

### 提取诊断 calibration_diagnostics 的报错

| 报错原文 | 触发条件 | 应对 |
|---------|---------|------|
| `x must be a pass_rate_calibration object.` | 传的不是校准结果 | 传校准返回的 fit |

---

想查某个函数的完整参数，在 R 里输入问号加函数名，比如 `?calibrate_rates`。
更技术性的架构与算法细节见 `docs/ARCHITECTURE.md`。
