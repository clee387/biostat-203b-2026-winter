*Charlotte Lee*

### Overall Grade: 250/270

### Late penalty

- Is the homework submitted (git tag time) before deadline? Take 10 pts off per day for late submission.  

### Quality of report: 10/10

-   Is the final report in a human readable format html? 

-   Is the report prepared as a dynamic document (Quarto) for better reproducibility?

-   Is the report clear (whole sentences, typos, grammar)? Do readers have a clear idea what's going on and how results are produced by just reading the report? Take some points off if the solutions are too succinct to grasp, or there are too many typos/grammar. 

### Completeness, correctness and efficiency of solution: 205/220

- Q1 (90/100)

If `collect` before end of Q1.7, take 20 points off.

If ever put the BigQuery token in Git, take 50 points off.

Cohort in Q1.7 should match that in HW3.

Q1.8 summaries should roughly match those given.

  - Q1.5 & Q1.6 (-5 total): Missing `arrange` at the end of both the labevents and chartevents pipe chains. Output order will not match the ground truth. Single 5-point deduction applied.
  - Q1.5 (-5): Lab events pipeline does not include `stay_id` in the `left_join` select or in the `group_by`.
  - Q1.7: Uses `tbl(con_bq, "admissions")` and `tbl(con_bq, "patients")` directly instead of the lazy table references `admissions_tble` and `patients_tble` created earlier. This works but re-creates the connections and ignores the arranged references from Q1.3/Q1.4. `collect()` correctly placed near end (line 182). `arrange` present after `collect()`.
  - Q1.8: `fct_lump_n` with varying n values applied to all five variables. `fct_collapse` used for race with `other_level = "Other"`. `los_long = los >= 2` correct.


- Q2 (95/100)

  - **Folder structure**: Separate `app.R` in `mimiciv_shiny/`. No penalty.
  - **Tab 1 (Cohort Summary)**: Includes all three variable categories (Demographics, Vitals, Labs) via `radioButtons` with separate `conditionalPanel` for each — *bonus: +5 for grouped variable categories*. Summary tables via `tbl_summary()`, distribution plots via Plotly, stratified boxplots and vitals trends.
  - **Tab 2 (Patient Explorer)**:
  - (-5): Bug in patient_base(). The query asks for race from mimiciv_3_1.patients, but that column is not in the patients table. As a result, the BigQuery job fails and the ADT plot cannot render.
  - (-5): Diagnoses query uses `LIMIT 3` without `ORDER BY seq_num`. Not sorted by clinical priority.
  - **Error handling**: Excellent — `tryCatch` around every BigQuery call, `req()`, `showNotification` on errors, safe empty fallbacks for labs/procedures/diagnoses. Very polished UI with CSS styling and info badges.

- Q3 (20/20)

  - Lists AI tool (Claude) and discusses use.
  - Provides 5 instances of AI errors with screenshots: scale_linewidth_manual string keys, bq_auth placement crashing app, triplicate output definitions, subplot approach, .env file confusion. Full credit.

### Usage of Git: 10/10

-   Are branches (`main` and `develop`) correctly set up? Is the hw submission put into the `main` branch?

-   Are there enough commits (>=5) in develop branch? Are commit messages clear? The commits should span out not clustered the day before deadline. 
          
-   Is the hw submission tagged? 

-   Are the folders (`hw1`, `hw2`, ...) created correctly? 
  
-   Do not put a lot auxiliary files into version control. 

-   If those gz data files are in Git, take 5 points off.

### Reproducibility: 5/10

-   Are the materials (files and instructions) submitted to the `main` branch sufficient for reproducing all the results? Just click the `Render` button will produce the final `html`? 

-   If necessary, are there clear instructions, either in report or in a separate file, how to reproduce the results?

-   **Note**: (-5) Hardcoded absolute path in Q1.1 (line 58) would prevent rendering on other machines.

### R code style: 20/20

For bash commands, only enforce the 80-character rule. Take 2 pts off for each violation. 

-   [Rule 2.6](https://style.tidyverse.org/syntax.html#long-function-calls) The maximum line length is 80 characters. Long URLs and strings are exceptions.  

-   [Rule 2.5.1](https://style.tidyverse.org/syntax.html#indenting) When indenting your code, use two spaces.  
    - No violations found.

-   [Rule 2.2.4](https://style.tidyverse.org/syntax.html#infix-operators) Place spaces around all infix operators (=, +, -, <-, etc.).  
    - No violations found.

-   [Rule 2.2.1.](https://style.tidyverse.org/syntax.html#commas) Do not place a space before a comma, but always place one after a comma.  
    - No violations found.

-   [Rule 2.2.2](https://style.tidyverse.org/syntax.html#parentheses) Do not place spaces around code in parentheses or square brackets. Place a space before left parenthesis, except in a function call.
    - No violations found.
