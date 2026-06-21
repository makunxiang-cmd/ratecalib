# release/ — 最终上传用的 R 包与 CRAN 提交指南

存放构建好、可分发/上传的源码包 `ratecalib_<version>.tar.gz`，并记录提交 CRAN 的完整步骤。

## 一、生成 tarball

在项目根目录执行，包本体在 `package/` 子目录：

```bash
R CMD build package          # 生成 ratecalib_0.3.0.tar.gz 到当前目录
mv ratecalib_*.tar.gz release/
```

或在 R 中：`devtools::build("package", path = "release")`。

## 二、本地自检

```bash
R CMD check release/ratecalib_0.3.0.tar.gz --as-cran
```

目标是 0 ERROR / 0 WARNING；首次提交会有一个 "New submission" NOTE，属正常。
本机若无 LaTeX(pdflatex)，PDF 手册检查会报错，可加 `--no-manual` 跳过——该项由
win-builder/CRAN 代为构建（见下）。`--as-cran` 会联网查 CRAN，网络不通时会中止，重试即可。

## 三、提交 CRAN 的完整步骤（须由维护者本人完成）

CRAN 要求由 DESCRIPTION 里的维护者本人提交并通过邮件确认，无法代办。

1. **确认包名可用**：浏览器打开 <https://CRAN.R-project.org/package=ratecalib>，
   若显示 404 即名字未被占用。

2. **确认维护者邮箱可收信**：DESCRIPTION 中为 mkx07080412@gmail.com，
   CRAN 的确认邮件会发到这里，注意查收（含垃圾箱）。

3. **跨平台预检（强烈建议，能提前发现 Windows 与 PDF 手册问题）**：
   在 R 中安装 devtools 后运行，结果会发到维护者邮箱，约半小时：

   ```r
   install.packages("devtools")
   devtools::check_win_devel("package")     # Windows R-devel
   devtools::check_win_release("package")    # Windows R-release
   ```

   可选再跑多平台的 R-hub（需 GitHub Actions，本仓库已在 GitHub）：

   ```r
   install.packages("rhub")
   rhub::rhub_setup()      # 按提示在仓库启用一次
   rhub::rhub_check()
   ```

   只有当这些检查也基本干净（仅 New submission 等可解释的 NOTE）时再提交。

4. **阅读 CRAN 政策**：<https://cran.r-project.org/web/packages/policies.html>。

5. **网页提交**：打开 <https://cran.r-project.org/submit.html>，
   - 上传 `release/ratecalib_0.3.0.tar.gz`；
   - 维护者姓名/邮箱填得与 DESCRIPTION 一致；
   - 把项目根 `cran-comments.md` 的内容粘进说明框。

6. **邮件确认**：提交后 CRAN 向维护者邮箱发确认链接，点击确认，自动检查随即开始。

7. **响应审稿**：首次提交通常有人工复核，可能就措辞、示例、引用等提小修改意见。
   按意见改完后，提升版本号（如 0.3.0 -> 0.3.1），更新 `cran-comments.md`
   说明本次改了什么，重新走第一、二步并重新提交。

8. **通过后**：包进入 CRAN，全球镜像同步后即可用 `install.packages("ratecalib")` 安装，
   镜像同步通常需要一到两天。

> 注：`.tar.gz` 已被 `.gitignore` 忽略，不进版本库；本文件夹靠本 README 占位保留。
