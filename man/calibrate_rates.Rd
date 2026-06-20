\name{calibrate_rates}
\alias{calibrate_rates}
\alias{校准合格率}
\title{一步式多分组合格率权重校准}
\usage{
calibrate_rates(
  data, outcome, weight, overall = NULL, groups = list(), priority = 5,
  group_priority = 1, lower = 0.25, upper = 4,
  mode = c("soft", "exact"), lambda = 1e+04,
  new_weight = "weight_calibrated", check = TRUE, verbose = FALSE
)

校准合格率(...)
}
\arguments{
\item{data}{数据框，每行代表一个样本。}
\item{outcome}{0/1结果变量列名。}
\item{weight}{初始正权重列名。}
\item{overall}{总体目标合格率，可为NULL。}
\item{groups}{命名列表；元素名为分组变量，元素为带类别名称的目标率向量。}
\item{priority}{总体目标优先级。}
\item{group_priority}{分组目标优先级，可为单个数或命名向量。}
\item{lower, upper}{最终权重相对初始权重的倍数下限与上限。}
\item{mode}{软约束soft或精确约束exact。}
\item{lambda}{软约束目标误差的惩罚强度。}
\item{new_weight}{新增的校准权重列名。}
\item{check}{是否在求解前自动检查数据。}
\item{verbose}{是否显示底层求解器信息。}
\item{...}{传递给calibrate_rates的参数。}
}
\value{一个pass_rate_calibration对象，包含带新权重的数据、目标检查、边际检查和权重诊断。}
\description{自动生成目标表、识别分组变量、检查数据并执行校准，是推荐给多数用户的简化接口。}
