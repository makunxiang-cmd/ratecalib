\name{check_calibration_data}
\alias{check_calibration_data}
\alias{检查校准数据}
\alias{print.ratecalib_check}
\title{校准前数据与目标可行性检查}
\usage{
check_calibration_data(data, outcome, weight, group_vars, targets = NULL)
检查校准数据(...)
\method{print}{ratecalib_check}(x, ...)
}
\arguments{
\item{data}{数据框。}
\item{outcome}{0/1结果变量列名。}
\item{weight}{初始权重列名。}
\item{group_vars}{分组变量列名。}
\item{targets}{可选目标表。}
\item{x}{检查结果对象。}
\item{...}{其他参数。}
}
\value{包含检查状态、错误、提示、数据概况、分组摘要和目标支持表的列表。}
\description{检查缺失变量、非正权重、非0/1结果、分组缺失、空类别以及全0或全1类别。}
