\name{example_rate_data}
\alias{example_rate_data}
\alias{生成演示数据}
\title{生成合格率校准演示数据}
\usage{
example_rate_data(n = 5000L, seed = 2026L)
生成演示数据(...)
}
\arguments{
\item{n}{样本量。}
\item{seed}{随机种子。}
\item{...}{传递给example_rate_data的参数。}
}
\value{包含性别、城乡、五段学历、五段年龄、0/1合格指标和初始权重的数据框。}
\description{用于学习、测试和复现README案例的模拟数据生成器。}
