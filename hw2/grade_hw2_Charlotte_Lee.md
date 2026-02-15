*Charlotte Lee*

### Overall Grade: 109/200

### Quality of report: 8/10

-   Is the homework submitted (git tag time) before deadline?  
    - 3 min late (-2)
-   Is the final report in a human readable format (html, pdf)?  
-   Is the report prepared as a dynamic document (Quarto) for better reproducibility?  
-   Is the report clear (whole sentences, typos, grammar)? Do readers have a clear idea what's going on and how results are produced by just reading the report?

### Completeness, correctness and efficiency of solution: 63/150

- Q1 (13/20)
    - Q1.1 (10/10): All three methods benchmarked with `system.time` and `lobstr::obj_size`. Identifies `fread` as fastest (0.302s). Discusses parsed type differences (data.frame, tibble, data.table). Memory: 200.10, 70.02, 63.47 MB.
    - Q1.2 (3/10): Uses `col_double()` for subject_id, hadm_id, and hospital_expire_flag instead of `col_integer()`. Uses `col_character()` for all categorical columns instead of `col_factor()`. Reports **70.02 MB** no improvement over default `read_csv`, and well above the <50 MB target stated in the hint. (-5 for no `col_factor()`, -2 for `col_double()` instead of `col_integer()`)

- Q2 (50/80)
    - Q2.1 (10/10): Reports R terminated after 3+ minutes. Adequate explanation.
    - Q2.2 (10/10): Uses `col_select` with 4 columns. Reports "Timing stopped at: 113.2 157 338.9". Correctly notes it doesn't fully solve the issue.
    - Q2.3 (15/15): Excellent awk with dynamic `keep[]` associative array for item IDs. Filters on `$5`. Prints `$2","$5","$7","$10`. Hardcoded header output. 33,712,352 rows reported. First 10 rows displayed with `arrange()`. `read_csv` timing (6.471s).
    - Q2.4 (15/15): Correct decompression via `gunzip -k`. Opens decompressed CSV with `arrow::open_dataset()`. Reports 41.777s, 33,712,352 rows. First 10 rows displayed with `arrange()`. Arrow explanation provided.
    - Q2.5 (0/15): **Empty code chunk — no Parquet conversion attempted.** No file size, no timing, no row count, no explanation. (-15)
    - Q2.6 (0/15): **Empty code chunk — no DuckDB work attempted.** No timing, no row count, no explanation. (-15)

- Q3 (0/30): **No code or answer provided.** Only the question prompt is present. (-30)

- Q4 (0/20): **No answer provided.** No AI assistant description, no 5 instances of incorrect output. (-20)

### Usage of Git: 10/10

-   Are branches (`main` and `develop`) correctly set up? Is the hw submission put into the `main` branch?  
-   Are there enough commits (>=5) in develop branch? Are commit messages clear?  
-   Is the hw2 submission tagged?  
-   Are the folders (`hw1`, `hw2`, ...) created correctly?  
-   Do not put auxiliary and big data files into version control.

### Reproducibility: 10/10

-   Are the materials (files and instructions) submitted to the `main` branch sufficient for reproducing all the results?  
-   If necessary, are there clear instructions how to reproduce the results?

### R code style: 18/20

-   [Rule 2.2.4](https://style.tidyverse.org/syntax.html#infix-operators) Place spaces around all infix operators.
    - **Violation (lines 92, 105, 148, 228, 243):** `file <-"/Users/..."` — missing space after `<-` operator. Also line 367: `format= "csv"` — missing space before `=`. (-2)

-   [Rule 2.6](https://style.tidyverse.org/syntax.html#long-function-calls) The maximum line length is 80 characters. No violations found in R code.
-   [Rule 2.5.1](https://style.tidyverse.org/syntax.html#indenting) When indenting your code, use two spaces. No violations found.
-   [Rule 2.2.1](https://style.tidyverse.org/syntax.html#commas) Do not place a space before a comma, but always place one after a comma. No violations found.
-   [Rule 2.2.2](https://style.tidyverse.org/syntax.html#parentheses) Do not place spaces around code in parentheses or square brackets. No violations found.

**Note:** This submission is significantly incomplete — Q2.5, Q2.6, Q3, and Q4 are entirely missing, accounting for 80 points of deductions.
