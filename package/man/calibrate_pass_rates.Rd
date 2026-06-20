\name{calibrate_pass_rates}
\alias{calibrate_pass_rates}
\title{使用有界二次规划校准多个合格率目标}
\usage{
calibrate_pass_rates(
  data, outcome, weight, group_vars, targets,
  lower = 0.25, upper = 4, mode = c("soft", "exact"),
  lambda = 1e+04, new_weight = "weight_calibrated", verbose = FALSE
)
}
\arguments{
\item{data}{每行一个样本的数据框。}
\item{outcome}{只含0和1的结果变量列名。}
\item{weight}{全部为正的初始权重列名。}
\item{group_vars}{分组变量列名向量。}
\item{targets}{至少含variable、level、target_rate三列的目标表；priority列可选。}
\item{lower, upper}{校准权重相对初始权重的倍数上下限。}
\item{mode}{soft为软约束；exact为精确约束。}
\item{lambda}{软约束模式的目标误差惩罚强度。}
\item{new_weight}{写入返回数据的新权重列名。}
\item{verbose}{是否显示OSQP求解过程。}
}
\value{pass_rate_calibration对象。}
\description{先将个人数据聚合到“交叉人口单元×结果状态”，保持初始人口边际权重总量，再通过有界凸二次规划调整单元权重。}
\details{
对目标率r，函数使用线性化条件sum(w*I*(y-r))=0。软约束模式在权重变化成本和目标误差之间进行权衡；精确模式要求所有目标在给定边界内同时成立。
}
