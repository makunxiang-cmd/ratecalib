\name{make_rate_targets}
\alias{make_rate_targets}
\alias{生成目标表}
\title{生成合格率目标表}
\usage{
make_rate_targets(overall = NULL, groups = list(), overall_priority = 5, group_priority = 1)
生成目标表(...)
}
\arguments{
\item{overall}{可选总体目标合格率。}
\item{groups}{命名列表，每个元素是一个带类别名称的目标率向量。}
\item{overall_priority}{总体目标优先级。}
\item{group_priority}{分组目标优先级，可为单个数或按变量命名的向量。}
\item{...}{传递给make_rate_targets的参数。}
}
\value{可直接传给calibrate_pass_rates的目标数据框。}
\description{把易读的命名列表转换为标准目标表，并检查目标率和优先级。}
