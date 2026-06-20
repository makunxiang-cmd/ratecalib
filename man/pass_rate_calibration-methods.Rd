\name{pass_rate_calibration-methods}
\alias{print.pass_rate_calibration}
\alias{summary.pass_rate_calibration}
\alias{print.summary_pass_rate_calibration}
\alias{plot.pass_rate_calibration}
\title{校准结果的打印、摘要和绘图方法}
\usage{
\method{print}{pass_rate_calibration}(x, digits = 4, ...)
\method{summary}{pass_rate_calibration}(object, top = 10L, ...)
\method{print}{summary_pass_rate_calibration}(x, digits = 4, ...)
\method{plot}{pass_rate_calibration}(x, type = c("target_error", "multipliers"), top = 20L, ...)
}
\arguments{
\item{x, object}{校准结果或摘要对象。}
\item{digits}{显示的小数位数。}
\item{top}{显示误差最大的目标数量。}
\item{type}{target_error为目标误差图，multipliers为权重倍数直方图。}
\item{...}{其他绘图或打印参数。}
}
\value{print和plot不可见地返回输入对象；summary返回摘要对象。}
\description{用中文展示求解状态、目标误差、有效样本量、设计效应和权重调整倍数。}
