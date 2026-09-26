# Data-quality report: date and price errors in the EGX30 file

| | |
|---|---|
| File | `data/raw/egx30_2000_2025.csv` (SHA-256 `e35bebbe…b48b0c`, identical to the upload) |
| Contents | 6,283 data rows plus a header; `Date` as `dd-Mon-yy`, `Close` with thousands separators; CRLF line endings |
| Span | 2 Jan 2000 – 30 Oct 2025 |
| Reader | `R/data.R`: `read_egx30()` parses the file, then `clean_egx30()` removes rows the EGX could not have traded on |
| Evidence | `scripts/scan_egx30_raw.R` (independent scan) and `scripts/stale_row_impact.R` (with/without comparison) |
| External sources | EGX Annual Report 2005 and CBE Annual Report 2002/2003, both in the project's Google Drive `EGX30_Report` folder (§8) |

## 1. Summary

1. **One corrupted row, confirmed.**
   - **Where:** file line 1,349, data row 1,348: `18-Jun-05,"4,617.95"`.
   - **What:** it is dated **Saturday 18 June 2005**, and its close repeats the
     previous row (Thursday 16 June) to the cent. It is a stale carry-forward
     stamped with a non-trading day.
   - **Status:** the pipeline removes it, and the raw file is left unmodified.
   - **External confirmation:** the EGX's official session count for 2005 is
     249, one fewer than the file's 250 rows (§8.1).
2. **The row's impact is negligible.** It inserts one spurious zero return and
   shifts every later observation by one position. No estimate moves by more
   than 0.5%, no test crosses a significance threshold, and no conclusion of
   the replication changes.
3. **The reader had a more serious latent fault, now fixed.** Under a
   non-English locale (verified with French and Arabic/Egypt), the original
   `read_egx30()` parsed **no** dates and **silently returned zero rows**. It
   gave no warning. The reader is now locale-independent and fails loudly
   (§7.2).
4. **10 Sep 2002 was investigated and is retained.** It was a genuine trading
   day, and its flat close is consistent with chance (§8.3). One anomaly
   remains unconfirmed and is kept: a ±5–6% three-day oscillation on
   28–30 Apr 2024.
5. **One 2000 session appears to be missing.** The official count is 248, and
   the file has 247 rows (§8.2). It can't be identified without a daily source.
6. **All values before 2 Feb 2003 are backfilled.** CASE 30 was launched on
   that date and calculated backwards to 1998. The backfilled segment differs
   in variance and tails, but no conclusion of the replication depends on it
   (§8.4).

## 2. Detection method

### 2.1 Rule in the pipeline

`clean_egx30()` drops a row when both of these hold:

- the date falls on a Friday or Saturday, the EGX weekend throughout 2000–2025;
- the close equals the previous row's close.

`audit_egx30()` records the dropped rows, and the report prints them.

### 2.2 Independent scan (`scripts/scan_egx30_raw.R`)

The raw file was re-read without the project's reader. The scan runs ten
checks, covering both the date field and the price field:

| # | Check | What it catches | Result |
|---|---|---|---|
| 1 | Weekday of every date | Rows on non-trading days | **1 row: 2005-06-18 (Saturday)** |
| 2 | Close equal to the previous close | Stale or carried-forward prices | 2 rows: **2005-06-18**, 2002-09-10 |
| 3 | Spike followed by a reversal of ≥ 80% of its size (> 5%) | Keying errors that revert next day | 5 dates, all inside real sell-offs (§6) |
| 4 | Price ratio to the neighbouring row > 1.5 or < 0.67 | Decimal shifts, rebasing | none |
| 5 | Returns > 8 MAD from the median | Gross price errors | 6 dates, all known market events (2003 float, Oct 2008, Jan 2011, Nov 2012, Mar 2020) |
| 6 | Gaps between consecutive dates | Missing days, closures | longest gap 55 days (2011 closure); 14 gaps of 6–10 days (holidays) |
| 7 | Rows per ISO week > 5 | Extra or duplicated sessions | **1 week: 2005-W24 (6 rows)** |
| 8 | Date parse failures, ordering, duplicates | Malformed or unsorted dates | 0 failures; strictly increasing; no duplicates |
| 9 | Two-digit year pivot | `yy` read into the wrong century | all years in 2000–2025 |
| 10 | Price string format | Malformed numbers | 80 strings with trimmed trailing zeros (`"930"`, `"991.6"`); all parse correctly and are harmless |

Checks 1, 2 and 7 each flag the same row independently.

## 3. Evidence for the error

The raw lines around the row:

```
line 1346  14-Jun-05,"4,461.32"   Tuesday
line 1347  15-Jun-05,"4,513.73"   Wednesday
line 1348  16-Jun-05,"4,617.95"   Thursday
line 1349  18-Jun-05,"4,617.95"   Saturday   <- corrupted
line 1350  19-Jun-05,"4,782.16"   Sunday
line 1351  20-Jun-05,"4,927.59"   Monday
```

Four independent pieces of evidence point to a carry-forward:

1. **The date is a non-trading day.** The file has 6,283 rows over 26 years.
   It contains zero Fridays and exactly one Saturday, this row. The EGX week
   runs Sunday to Thursday.
2. **The price is an exact repeat.** The Saturday close matches Thursday's close
   to the cent. Only one other exact repeat occurs in 6,282 transitions. An
   unchanged index is rare in isolation, and it is far less likely in this week,
   when the index rose 2.3%, 3.5% and 3.0% on the neighbouring sessions.
3. **The row breaks the week's structure.** ISO week 2005-W24 is the only week
   in the file with six rows; every neighbouring week has at most five, Sunday
   to Thursday.
4. **The data contain no Friday row.** A genuine extra session would not
   explain why the Saturday row simply repeats Thursday's close. A fill-forward
   over the weekend, stamped with the wrong day, explains it.

**Classification:** a date and price error of the stale-duplicate type. The
Saturday row is not a real session, and its price is Thursday's.

## 4. Location

| Field | Value |
|---|---|
| File line (header = line 1) | 1,349 |
| Data row | 1,348 of 6,283 |
| Raw text | `18-Jun-05,"4,617.95"` |
| Parsed date | 2005-06-18 (Saturday) |
| Parsed close | 4,617.95 (equals 2005-06-16) |
| Return it creates | r = 0 on 2005-06-18 |
| Samples affected | paper window (2000–2015), full sample (2000–2025), every pre-float subsample |

## 5. Downstream impact

### 5.1 Local effect

The row adds one return and changes no price level. The genuine move from
Thursday to Sunday (+3.49%) is unchanged either way.

| Date | Return with the row | Cleaned return | Days since the previous row (with / cleaned) |
|---|---|---|---|
| 2005-06-16 | +2.28% | +2.28% | 1 / 1 |
| **2005-06-18** | **0.00%** | removed | 2 / – |
| 2005-06-19 | +3.49% | +3.49% | 1 / 3 |

Mechanically, the row does three things:

- It adds one fake zero return in a high-momentum week, which slightly damps
  measured autocorrelation.
- It shifts every later observation by one index. That realigns the R/S
  sub-period blocks and bootstrap block boundaries.
- It understates the calendar gap before the Sunday return.

### 5.2 Effect on the replication's statistics (`scripts/stale_row_impact.R`)

| Statistic | 2000–2015, with row | 2000–2015, cleaned | 2000–2025, with row | 2000–2025, cleaned |
|---|---|---|---|---|
| N returns | 3,895 | 3,894 | 6,282 | 6,281 |
| Zero returns | 2 | 1 | 2 | 1 |
| Mean (×10⁻⁴) | 4.560 | 4.561 | 5.530 | 5.531 |
| SD (%) | 1.7569 | 1.7572 | 1.6157 | 1.6158 |
| Kurtosis | 11.537 | 11.534 | 11.499 | 11.497 |
| Lag-1 autocorrelation | 0.1796 | 0.1803 | 0.1732 | 0.1737 |
| VR(2), robust z₂ | 5.438 | 5.457 | 6.660 | 6.678 |
| BDS max W, raw returns | 28.87 | 28.96 | 37.26 | 37.33 |
| BDS max \|W\|, GJR residuals | 1.737 | 1.819 | 2.388 | 2.407 |
| BDS min p, GJR residuals | 0.082 | 0.069 | 0.0170 | 0.0161 |
| Ljung–Box(20) p, AR(2) residuals | 0.0017 | 0.0020 | 5.0e-5 | 6.9e-5 |
| Hurst H (Anis–Lloyd corrected) | 0.5374 | 0.5371 | 0.5416 | 0.5419 |
| Lo's V (Andrews q) | 2.032 | 2.031 | 1.647 | 1.647 |
| Local-Whittle d | 0.0714 | 0.0714 | 0.0882 | 0.0879 |

What the numbers show:

- **Point estimates** move by less than 0.5%.
- **Tail probabilities** move the most, as expected for p-values:
  - The BDS minimum p on GJR residuals (2000–2015) goes from 0.082 to 0.069.
  - The Ljung–Box p-values rise by 20–37% in relative terms.
- **No decision changes.** No test crosses 5% or 1% in either direction.
  - GARCH-filtered BDS stays non-significant for 2000–2015.
  - Ljung–Box stays significant.
  - Lo's V stays inside the 99% region.
- **Conclusions are unaffected.** They are the same with or without the row,
  including the chaos diagnostics, which run on GJR residuals.

The effect is small because one zero among about 4,000–6,000 returns barely
changes any moment. It could matter more in short subsamples or rolling
windows. It would also matter if the same error pattern occurred many times
in another vendor's file, which is why the rule stays in the pipeline.

## 6. Other findings

### 6.1 The reader returns nothing under non-English locales (high severity)

`parse_dates()` uses `%b`, which R matches against month names in the current
`LC_TIME` locale. The results by locale:

| Locale | Rows read |
|---|---|
| C.UTF-8 | 6,283 |
| fr_FR.UTF-8 | **0** |
| ar_EG.UTF-8 | **0** |

`read_egx30()` then drops rows with `NA` dates without reporting a count. On an
Arabic-locale machine, the likely setup for EGX users, the pipeline would start
from an empty series. It would then fail downstream with an unrelated error,
far from the real cause. This session never hit the fault because it ran under
the C locale.

### 6.2 Silent filtering in the reader (medium severity)

`read_egx30()` removes these rows without reporting how many:

- unparseable dates;
- non-finite or non-positive prices;
- duplicate dates.

In this file the count is zero, but a corrupted file would be cleaned silently.

### 6.3 The cleaning rule is narrower than the error class (low severity)

`clean_egx30()` drops a Friday or Saturday row only if its close repeats the
previous row. A weekend row with a different price would pass through. So would
a stale repeat dated on a weekday holiday.

### 6.4 Candidates checked for staleness (kept)

| Date | Observation | Assessment |
|---|---|---|
| 2002-09-10 (Tue) | Close 474.09, identical to Monday | **Resolved: retained.** A genuine trading day, and the flat close is consistent with chance (§8.3). |
| 2024-04-28 to 04-30 | −5.1%, +5.4%, −6.2% | Inside a sustained sell-off from 28,144 to 24,449. The 25 Apr holiday (Thursday) is correctly absent. Consistent with genuine volatility. |

## 7. Recommended correction

### 7.1 The corrupted row: remove it, done

- **Keep** the removal of 2005-06-18 in `clean_egx30()`, as applied.
- **Do not edit the raw file.** The correction lives in code and is recorded by
  `audit_egx30()` and in the report's Data section, so the provenance stays
  intact.
- **Do not replace it with an interpolated value.** No session occurred, so
  there is nothing to impute. Removing the row gives the Sunday return its
  correct three-day span.

### 7.2 Harden the reader

**Status: applied** to both `R/data.R` and the Colab script. The four
recommendations below are implemented as follows:

1. Month names are mapped to numbers before parsing, so `%b` is never used.
2. The reader stops when more than 1% of rows fail to parse. It always
   reports how many rows it read, and how many bad dates, bad prices and
   duplicate dates it removed.
3. Weekend rows that repeat the previous close are dropped. Weekend rows with
   a new price are kept, and the reader raises a warning so they can be
   reviewed.
4. Four new tests in `tests/testthat/test-data.R` cover the behaviour:
   - the file parses identically under French and Arabic locales;
   - all seven supported date formats parse to the same dates;
   - unparseable rows stop the reader instead of being dropped silently;
   - a weekend row with a new price is kept and reported.

The fix changes no result on the supplied file: every pipeline target was
rebuilt and compared with the previous values (§9).

The original recommendations:


1. **Parse months independently of locale.** Map `Jan`–`Dec` to `01`–`12`
   explicitly, or wrap parsing in `withr::with_locale(c(LC_TIME = "C"), ...)`.
   Add a test that runs `read_egx30()` under `fr_FR` or `ar_EG`.
2. **Fail loudly.** `stop()` when more than a few rows fail to parse, and always
   `message()` the counts of dropped and deduplicated rows.
3. **Treat every Friday or Saturday row as an error.** Report it, and drop it
   only when its close repeats the previous one. Weekend rows with a different
   price should stop the pipeline for manual review.
4. **Keep the scan as a regression check.** Run `scripts/scan_egx30_raw.R`
   whenever the data file is replaced, for example when 1998–1999 are added
   or the series is extended.

### 7.3 Remaining checks

1. **28–30 Apr 2024.** Check against a daily source, such as EGX bulletins or
   Refinitiv/Bloomberg. Change the values only if that source disagrees.
2. **The missing 2000 session.** Identify it from a daily source for April and
   October 2000 (§8.2). Add it only with a verified close. Until then, the
   returns either side of it span two sessions, which has a negligible effect.
3. **Backfill disclosure.** State in any write-up that CASE 30 values before
   2 Feb 2003 are reconstructions, and report the split-sample results (§8.4).

## 8. External-source verification

### 8.1 18 June 2005: confirmed as an artifact (EGX Annual Report 2005)

Source: `DiscDoc_ID715_31-Dec-2005_ENG.pdf` (20 pages). I read the PDF
directly.

"Main Market Indicators for the Period 2000–2005" (printed p. 11) gives the
**Number of Trading Days**:

| Year | Official sessions | Rows in the file | Difference |
|---|---:|---:|---:|
| 2000 | 248 | 247 | −1 (§8.2) |
| 2001 | 246 | 246 | 0 |
| 2002 | 249 | 249 | 0 |
| 2003 | 244 | 244 | 0 |
| 2004 | 249 | 249 | 0 |
| **2005** | **249** | **250** | **+1** |

What the counts show:

- **Why the comparison is valid.** Four years match exactly, so the EGX counts
  sessions the same way the file does.
- **The extra row is 18 June.** The only surplus is in 2005. June 2005 has 22
  Sunday–Thursday days and 23 rows, and the surplus row is Saturday 18 June.
  Without it, no June weekday is missing or extra.

The report's index figures also match the file, so the surrounding data are
correct:

| Report statement | Page | File |
|---|---|---|
| End-2005 level: 6,325 | 3 | 6,324.70 |
| 2005 growth: 146% | 3 | 146.3% |
| 2003 growth: 135% | 3 | 134.5% |
| 2004 growth: 122% | 3 | 122.2% |
| Growth over 2003–2005: 1,183% | 3 | 1,183.3% |
| End-H1 2005 level: 4,829, +88% | 4 | 4,828.66, +88.0% |

### 8.2 2000: one session missing from the file

The official count is 248 and the file has 247 rows. The file lacks 14
Sunday–Thursday dates in 2000. Most match public holidays; the holiday dates
below come from general knowledge of the Egyptian calendar and are approximate:

- Eid al-Fitr: 9–10 Jan and 27–28 Dec
- Eid al-Adha: 15–16 Mar
- Islamic New Year: 6 Apr
- Sinai Day: 25 Apr
- Sham el-Nessim and Labour Day: 1 May
- Prophet's Birthday: 15 Jun
- Revolution Day: 23 Jul
- Armed Forces Day, observed: 5 Oct

That leaves three candidates for the missing session:

| Candidate | Why it is a candidate |
|---|---|
| **26 Apr 2000 (Wed)** | No known holiday |
| **30 Apr 2000 (Sun)** | Coptic Easter, not usually an exchange holiday |
| **5 Oct 2000 (Thu)** | A candidate only if Armed Forces Day (Fri 6 Oct) was not bridged |

The effect is negligible: one return spans two sessions instead of one.

### 8.3 10 September 2002: a genuine session, retained (CBE Annual Report 2002/2003)

Source: `CBE/Annual Report 2002-2003.pdf` (130 pages). Drive's text layer
stops before the Stock Exchange chapter, so I extracted the PDF itself.
Section 4/5, "The Stock Exchange", is on printed pp. 84–88.

What the report establishes:

- **The official levels match the file.** The listings table (p. 85) gives
  CASE 30 at 472.1 at end-June 2002 and 775.9 at end-June 2003, up 64.4%
  (p. 87). The file has 472.07 and 775.88, which is also +64.4%.
- **The index was backfilled.** CASE 30 "was retroactively calculated for five
  years as of 1/1/1998 … to replace the former share price index (CASE 50) as
  of February 2, 2003" (p. 87). The September 2002 value was reconstructed
  later from constituent closes, so a live data feed going stale that day can't
  explain the repeat.
- **The market was thin.** Trading was "calm" for most of FY 2002/03
  (pp. 84–85). A new closing-price rule used a volume-weighted average only
  when at least 100 securities traded (p. 84), and the report doesn't date it.
  In a thin market this rule leaves many constituent prices unchanged from one
  day to the next.
- **What the report lacks:** daily values, trading-day counts and anything on
  September 2002. The statistical annex it lists (Table 9/2, p. 151) is not in
  the PDF.

Evidence from the calendar and the data:

| Check | Result |
|---|---|
| Calendar | A Tuesday with no public holiday. Every Sunday–Thursday in Sep 2002 has a row. |
| Session count | 249 rows match the official 249 for 2002 (§8.1). All 12 missing Sunday–Thursday dates in 2002 fall on holidays. |
| Chance of an exact flat close | About 0.27% that day, at the local volatility of about 1.5 index points a day. Across the whole file about 0.8 exact repeats are expected by chance, and 1 is observed on a weekday. |
| Neighbouring days | Normal small moves: −0.24% on 9 Sep, then +0.16%, +0.54% and +0.60%. |

**Decision:** keep the row. If it were stale after all, it would only turn one
small return into a zero, the same negligible impact as in §5.

### 8.4 Backfilled index values: split-sample check

The CBE report (p. 87) shows that every CASE 30 value before 2 Feb 2003 is a
reconstruction from the 30 most liquid stocks of 2003. The pipeline's
`backfill` target (`R/backfill.R`) repeats the main diagnostics on each
segment. Values are rounded; the report's "Backfilled index values" section
has the full table.

| | Backfilled, 2000 – Jan 2003 | Live, Feb 2003 – 2015 | Live, Feb 2003 – 2025 |
|---|---:|---:|---:|
| N | 761 | 3,133 | 5,520 |
| Mean return, annualised | −23.3% | +19.6% | +18.6% |
| Volatility, annualised | 25.3% | 28.0% | 25.3% |
| Kurtosis | 4.7 | 12.7 | 12.5 |
| Days with \|r\| < 0.01% | 1.18% | 0.64% | 0.78% |
| Lag-1 autocorrelation | 0.197 | 0.159 | 0.158 |
| Ljung–Box(20) p, AR(2) residuals | 0.33 | 0.001 | < 0.001 |
| BDS on GJR residuals: min p (asymptotic) | 0.008 | 0.039 | 0.010 |
| Local-Whittle d (se) | −0.007 (0.058) | 0.067 (0.037) | 0.070 (0.030) |
| Lo's V (95% bound 1.862) | 1.34 | 1.88 | 2.09 |
| DChaos λ̂ (p for H₀: chaos) | −10.3 (< 0.001) | −2.8 (< 0.001) | −3.2 (< 0.001) |

Tests for a change at the launch date:

| Test | Statistic | p |
|---|---:|---:|
| Chow test, AR(1) coefficients (paper window) | 2.39 | 0.092 |
| Equal lag-1 autocorrelation (Fisher z) | 0.97 | 0.33 |
| Equal variance (F test) | 0.82 | 0.0007 |

**Reading.**

- **How the backfilled segment differs.** It has lower variance, much thinner
  tails and nearly twice as many flat days, which fits an index reconstructed
  from thinly traded prices. Its negative mean reflects the 2000–2002 bear
  market, not the backfill itself.
- **The linear dynamics don't change** at the launch: the autocorrelation
  difference is not significant, and the Chow test p is 0.09.
- **Chaos is rejected in every segment.** λ̂'s magnitude is unstable in the
  short backfilled sample, but its sign is not.
- **Long memory comes from the live period.** The weak evidence of it, from
  Lo's V and local-Whittle d, is absent in the backfilled segment.
- **Conclusion:** no finding of the replication depends on the backfilled
  years. The paper window's descriptive moments, especially kurtosis, do mix
  two segments with different distributions, and a write-up should say so.

## 9. Reproduction

```sh
Rscript scripts/scan_egx30_raw.R     # §2.2 checks and §3 evidence
Rscript scripts/stale_row_impact.R   # §5 impact tables
LC_ALL=fr_FR.UTF-8 Rscript -e 'source("R/data.R"); nrow(read_egx30("data/raw/egx30_2000_2025.csv"))'   # §6.1, needs the locale installed
Rscript -e 'targets::tar_make(backfill); print(targets::tar_read(backfill))'   # §8.4
Rscript -e 'testthat::test_dir("tests/testthat")'   # reader tests for §7.2 (locale tests skip if fr_FR/ar_EG are not installed)
```
