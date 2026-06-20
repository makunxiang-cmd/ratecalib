# release/ — 最终上传用的 R 包

存放构建好、可分发/上传的源码包 `ratecalib_<version>.tar.gz`。

## 如何生成

在项目根目录执行（包本体在 `package/` 子目录）：

```bash
R CMD build package
# 生成 ratecalib_0.2.1.tar.gz 到当前目录，移动到 release/
mv ratecalib_*.tar.gz release/
```

或在 R 中：

```r
devtools::build("package", path = "release")
```

## 发布前自检

```bash
R CMD check release/ratecalib_0.2.1.tar.gz --as-cran
```

确保无 ERROR / WARNING 后再上传到 CRAN、GitHub Release 或内部仓库。

> 注：`.tar.gz` 已被 `.gitignore` 忽略，不进版本库；本文件夹靠本 README 占位保留。
