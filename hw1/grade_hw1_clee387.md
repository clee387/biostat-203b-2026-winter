*LEE, CHARLOTTE (clee387)*

### Overall Grade: 86/140

---

### Quality of report: 10/10

- Is the homework submitted (git tag time) before deadline? **Yes (but no tag)**

- Is the final report in a human readable format html? **Yes**

- Is the report clear (whole sentences, typos, grammar)? **Yes**

---

### Completeness, correctness and efficiency of solution: 59/90

**Q1 (10/10)**

- Repository name correctly set up.

**Q2 (0/20)**

- **-15 points**: CITI training completion link not provided. No links or screenshots found in Q2 section.

- **-5 points**: PhysioNet credential link not provided.

**Q3 (10/20)**

- Q3.1: OK - Used `~/mimic/` path correctly.

- Q3.2: OK - Displayed contents of both hosp and icu folders. However, no explanation provided for why files are distributed as `.csv.gz` instead of `.csv`. **-4 points**

- Q3.3: OK - Explanations provided for all four commands (zcat, zless, zmore, zgrep). Direction is correct though zcat description could be more precise.

- Q3.4: OK - Loop output correctly shown. Line count loop implemented correctly.

- Q3.5: **-5 points** - Used decompressed `.csv` file directly (`~/mimic/hosp/admissions.csv`) instead of using `zcat` on `.csv.gz` file. This violates the instruction not to decompress gz files. Also used `gunzip -c` with a different path (`~/Downloads/mimic-iv-3.1/hosp/patients.csv.gz`) which is inconsistent.

- Q3.6: OK - Used `gunzip -c` which is acceptable (streams without creating file). All four variables shown with counts.

- Q3.7: OK - Correctly counted ICU stays and unique patients.

- Q3.8: OK - Compared file sizes and run times with discussion.

**Q4 (15/10)**

- Q4.1: OK - Explained `wget -nc` correctly. Loop uses `grep -o -i` which counts words. **Bonus +5 points** for counting words instead of just lines.

- Q4.2: OK - Correctly explained difference between `>` and `>>`.

- Q4.3: OK - Correctly explained the output (lines 16-20) and meaning of `$1`, `$2`, `$3`. Shebang explanation provided. middle.sh was submitted.

**Q5 (8/10)**

- **-2 points**: `date` command is missing from the bash chunk. All other commands are present with interpretations.

**Q6 (10/10)**

- Screenshot of Section 4.1.5 included (`section4.1.5.png`).

- Used relative path, not local absolute path.

- Screenshot shows correct section "4.1.5 Spaces in directory and file names".

**Q7 (6/10)**

- Which AI assistant: GitHub Copilot, GPT-5 (1/1)

- Which AI model: GPT-5 (1/1)

- How do you use them: Error debugging in bash commands (1/1)

- Do you think they help improve productivity: Not explicitly answered (0/2)

- 3 instances of AI errors provided (3/5).

---

### Usage of Git: 0/10

- **-10 points**: hw1 submission was not tagged.

---

### Reproducibility: 5/10

- **-5 points**: The qmd file uses decompressed `.csv` files in Q3.5 (`~/mimic/hosp/admissions.csv`) which would not exist on other machines. Also uses inconsistent paths (`~/Downloads/mimic-iv-3.1/` vs `~/mimic/`). Rendering would fail without the decompressed file.

---

### R code style: 12/20

80-character rule violations (bash commands in chunks):

1. Line 144: `echo "$datafile: $(zcat < "$datafile" | wc -l) lines"` (within 80 - OK)

2. Line 184: `gunzip -c ~/Downloads/mimic-iv-3.1/hosp/admissions.csv.gz | tail -n +2 | awk -F, '{print $6}' | sort | uniq -c | sort -nr` (117 chars) **VIOLATION**

3. Line 187: `gunzip -c ~/Downloads/mimic-iv-3.1/hosp/admissions.csv.gz | tail -n +2 | awk -F, '{print $8}' | sort | uniq -c | sort -nr` (117 chars) **VIOLATION**

4. Line 190: `gunzip -c ~/Downloads/mimic-iv-3.1/hosp/admissions.csv.gz | tail -n +2 | awk -F, '{print $10}' | sort | uniq -c | sort -nr` (118 chars) **VIOLATION**

5. Line 193: `gunzip -c ~/Downloads/mimic-iv-3.1/hosp/admissions.csv.gz | tail -n +2 | awk -F, '{print $13}' | sort | uniq -c | sort -nr` (118 chars) **VIOLATION**

**4 violations × 2 points = -8 points**

---

### Additional Notes

- The AI error screenshots provided show ChatGPT giving incorrect path suggestions and command recommendations.
