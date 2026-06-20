\name{calibration_diagnostics}
\alias{calibration_diagnostics}
\title{提取校准诊断结果}
\usage{calibration_diagnostics(x, sort_targets = TRUE)}
\arguments{
\item{x}{pass_rate_calibration对象。}
\item{sort_targets}{是否按目标绝对误差从大到小排序。}
}
\value{包含targets、margins和weights三个诊断表的列表。}
\description{集中提取目标误差、人口边际和权重质量诊断。}
