library(ratecalib)

set.seed(2026)
n <- 5000
sample_data <- data.frame(
  qualified = rbinom(n, 1, 0.70),
  initial_weight = runif(n, 0.5, 2),
  sex = sample(c("男", "女"), n, TRUE),
  residence = sample(c("城镇", "农村"), n, TRUE),
  education5 = sample(paste0("学历", 1:5), n, TRUE),
  age5 = sample(paste0("年龄", 1:5), n, TRUE)
)

targets <- make_rate_targets(
  overall = 0.705,
  groups = list(
    sex = c("男" = 0.71, "女" = 0.70),
    residence = c("城镇" = 0.71, "农村" = 0.70)
  )
)

fit <- calibrate_pass_rates(
  data = sample_data,
  outcome = "qualified",
  weight = "initial_weight",
  group_vars = c("sex", "residence", "education5", "age5"),
  targets = targets,
  mode = "soft"
)

print(fit)
summary(fit)
