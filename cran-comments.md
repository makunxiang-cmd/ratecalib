## Submission

This is a new submission of ratecalib 0.3.0.

ratecalib performs calibration weighting for binary-outcome pass rates against
multiple overlapping subgroup targets, with extensions for raking and logit
distances, mean/total and proportion targets, interaction targets, a feasibility
precheck, Excel input/output, and replicate-weight variance estimation.

## R CMD check results

Local check with `R CMD check --as-cran` gives:

0 errors | 0 warnings | 1 note

* The note is the standard "New submission" note.

## Test environments

* local: macOS, R 4.6.0
* (please also run win-builder and R-hub before submitting; see notes below)

## Downstream dependencies

There are no downstream dependencies (new package).

## Notes for the maintainer before submitting

* Run `devtools::check_win_devel()` and an R-hub check to cover other platforms.
* The full disclaimer ships in `inst/DISCLAIMER.md`; non-ASCII content is in
  documentation and inst only, while all R code is ASCII.
* Suggested package 'openxlsx' is used only behind `requireNamespace()` guards;
  examples that need it are wrapped accordingly.
