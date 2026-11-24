# Dengue Analysis: data and risk index

This document covers where the numbers on the Analysis screen come from, how
to refresh them, how the seasonal risk index is worked out, and what the data
cannot tell you.

## Files

| File | What it is |
|---|---|
| `assets/data/dengue_stats.csv` | Weekly dengue cases per RDHS: `district,year,week,cases`. Made by `tool/extract_dengue.py`. |
| `tool/dengue_sources.csv` | `year,week,pdf_url`: the report each week came from. |
| `tool/wer_manifest.csv` | Every listed report: original URL, where the file was actually fetched from, and the result. |
| `tool/validation_report.txt` | Output of the last extractor run (checks, missing weeks, spot checks). |
| `assets/data/waste_periods.csv` | Sourced high-waste periods: `label,start_date,end_date,districts,source_url`. |
| `assets/data/dengue_stats_sample_fallback.csv` | Synthetic data, **not real**. Used only if `dengue_stats.csv` is missing; the screen then shows a "Sample data only" warning. Made by `tool/gen_sample_dengue.ps1`. |
| `tool/wer_pdfs/` | The downloaded report PDFs. Git-ignored; re-create them with `tool/download_wer.py`. |

## Data source

Weekly Epidemiological Report (WER), Epidemiology Unit, Ministry of Health,
Sri Lanka. Listing page:
<https://www.epid.gov.lk/epid/public/index.php/weekly-epidemiological-report/weekly-epidemiological-report>

From each report we use **Table 1** (notifiable diseases reported by Medical
Officers of Health), the **Dengue Fever, column A** (cases reported in that
week). Column B is the cumulative total for the year and is not used.

### How the PDFs were fetched on 2026-11-24

`www.epid.gov.lk` answered **HTTP 509 "Bandwidth Limit Exceeded"** for every
page and every PDF on 2026-11-24 (the site's own quota; retries over more than
an hour did not change it). So:

- The report **listing** was read from the Internet Archive snapshot of that
  page taken on 2026-07-15 (`20260715141555`). It lists 129 English reports for
  2024 to 2026, up to week 25 of 2026.
- **102 PDFs were fetched through Internet Archive copies** of the original
  epid.gov.lk URLs. `tool/wer_manifest.csv` records, for each report, the
  original URL (`url`) and the archive URL it was downloaded from
  (`fetched_from`).
- **27 reports could not be fetched** (not archived): all 24 reports of
  volume 53 numbers 2 to 25 (2026), and volume 52 numbers 19, 39 and 52 (which
  appear to be 2025 table weeks 18, 38 and 51).
- `tool/dengue_sources.csv` always holds the **original epid.gov.lk link**, so
  anyone can check a number against the Epidemiology Unit's own file.

## How extraction works

`tool/extract_dengue.py` reads every PDF in `tool/wer_pdfs/`:

1. Finds the "Table 1" title and reads the **year and week from the title**
   (for example `20th – 26th Dec 2025 (52nd Week)`), never from the file name
   or volume number. (Volume 53 number 1 is week 52 of 2025.)
2. The table is printed sideways, so the characters are rotated back using
   their position on the page. The first column heading must be Dengue.
3. Takes the first two numbers of each RDHS row: column A is the week, B the
   cumulative year; B must be at least A or the PDF is skipped.
4. Reads the 26 RDHS rows. Kalmunai is its own RDHS and stays separate from
   Ampara. The reports print "Monaragala"; the CSV uses "Moneragala". The first
   2024 reports print "Anuradhapur" and "Kalmune"; those two exact labels are
   mapped.
5. Reads the SRI LANKA total row **for checking only**.
6. If a table cannot be read with every check passing, the PDF is skipped and
   the reason is printed. A week found in two PDFs with different numbers is
   left out. Only 2024 to 2026 are written (`--years` changes this).

Nothing is estimated or filled in: a week that is missing stays missing.

## How to refresh the data (PowerShell)

Run from the project root.

```powershell
# one time
py -m pip install pdfplumber requests beautifulsoup4

# 1. Fetch new reports (when epid.gov.lk is reachable again).
#    Reads the live listing, skips files already in tool\wer_pdfs\, waits
#    between downloads, rewrites tool\wer_manifest.csv. If the live site is
#    down it falls back to the Internet Archive copy of the page and files.
py tool\download_wer.py

# 2. Rebuild the CSV files and print the validation report.
py tool\extract_dengue.py | Tee-Object tool\validation_report.txt

# 3. Check the app side.
flutter test test\features\analysis
```

To add reports by hand: save the English WER PDFs into `tool\wer_pdfs\`, run
step 1 (it records their original URLs from the listing) and then step 2. If
step 2 is run without step 1, weeks from PDFs that are not in the manifest get
an empty `pdf_url` and the report lists them. Running the extractor again
always rebuilds both CSV files from everything in `tool\wer_pdfs\`.

**The app picks up new weeks automatically.** `dengue_stats.csv` is a bundled
asset, so after the next build the data note, the charts and the risk index
use the newest weeks. The note under the title is worked out from the CSV, and
the "reports not yet available" sentence disappears once the data reaches the
current year.

## Validation (run of 2026-11-24)

| | |
|---|---|
| Reports listed (English, 2024 to 2026) | 129 |
| Downloaded | 102 |
| Not available | 27 |
| Parsed | 102 (101 in range; one is week 52 of 2023 and is left out) |
| Skipped as unreadable | 0 |
| Weeks in the CSV | 101 (2,626 rows = 101 weeks x 26 RDHS) |

| Year | Weeks in CSV | Missing weeks |
|---|---|---|
| 2024 | 52 (1 to 52) | none |
| 2025 | 49 | 18, 38, 51 |
| 2026 | 0 | all (reports not available) |

**The latest week in the data is week 52 of 2025.**

### Sum check against the SRI LANKA total

For every week, the sum of the 26 RDHS values is compared with the SRI LANKA
total printed in the same table. **92 of 101 weeks match exactly.**

**9 weeks are flagged and are kept in the data:** 2025 weeks 1, 2, 3, 4, 5, 19,
20, 23 and 52. In all nine the printed total is the start of our district sum
with its last digit missing (for example week 52: sum 1443, printed total
"144"). I rendered the week 52 page and the PDF itself prints "144" in that
cell, so the typo is in the Epidemiology Unit's table, not in the extraction.
The district values in those weeks are used as read.

Five random values were also checked by eye against their PDFs; see the end of
`tool/validation_report.txt`.

## Seasonal risk index

Worked out for **today's ISO week** (from the device clock, not from the last
week in the data), per RDHS. All thresholds are named constants in
`lib/features/analysis/risk_constants.dart`; the functions are pure and live
in `risk_index.dart` (tests: `test/features/analysis/risk_index_test.dart`).

1. **Seasonal level** = average cases of the district in weeks within +/- 1 of
   today's week, over all years in the data.
2. **District normal** = average weekly cases of the district over every week
   in the data.
3. **Seasonal score** = seasonal level / district normal (a normal of 0 gives a
   score of 0, not a division by zero).
4. **Base level**: score below 0.8 is **Low**, 0.8 up to and including 1.3 is
   **Medium**, above 1.3 is **High**.
5. **+1 level** if today is inside a sourced high-waste period for that
   district (`waste_periods.csv`).
6. **+1 level** if the district has **more than 2** valid CleanSpot reports in
   the last **14 days** (so 3 or more). Levels never go above High.

| Constant | Value |
|---|---|
| `seasonalLowBelow` | 0.8 |
| `seasonalHighAbove` | 1.3 |
| `seasonalWeekWindow` | 1 week |
| `liveReportWindowDays` | 14 days |
| `liveReportsBumpAbove` | 2 (bump at 3 or more) |
| `wastePeriodBump`, `liveReportBump` | 1 level each |

Week distance wraps around the year (week 52 and week 1 are neighbours); week
53 is counted as week 52.

The reason line looks like `Usually 1.6× higher this time of year · 3 live
reports`. If live reports cannot be loaded (no network, Firestore error) they
are left out of the index and the screen says so.

**Live reports** come from `FirestoreService.watchValidReports()`. A report is
put into the district whose centre is nearest in a straight line
(`district_centres.dart`). This is an **approximation**, not a boundary lookup.
The centres are the coordinates of each RDHS's main town (Wikipedia/Wikidata
coordinates, rounded to four decimals).

## Waste periods

`assets/data/waste_periods.csv` has only periods with a source I read:

| Period | Districts | Source |
|---|---|---|
| 2024-12-28 to 2024-12-31: Colombo Municipal Council expects festive-season garbage to rise from about 450 to 500 tonnes a day | Colombo | <https://adaderana.lk/news/104535/colombos-garbage-surges-during-festive-season> |
| 2019-08-05 to 2019-08-08: Colombo city garbage collection halted after the Kerawalapitiya dump stopped accepting it | Colombo | <https://www.newsfirst.lk/2019/08/08/collection-of-garbage-in-colombo-halted-solution-not-yet-provided/> |
| 2026-06-29: Kaduwela Municipal Council collection vehicles reported to have missed some areas for nearly three weeks | Colombo | <https://adaderana.lk/news/cmqzd34is0006356pbmnd8jx1> |

Dates are the dates the source gives. The Kaduwela report says "nearly three
weeks" without a start date, so only the reporting date is used.

**Looked for but not included** (no source I could open with the dates, or no
dated disruption): Sinhala and Tamil New Year and Vesak collection, the 2017
Meethotamulla dump collapse (the article I read gives no calendar date), and
waste after Cyclone Ditwah in late 2025 (reported by UNDP and the Daily
Mirror, but I could not read the article text to confirm dates and districts).
Add a row only with a link to a page that states the dates.

Because these periods are in the past, **the waste-period bump does not apply
to today's date (24 Nov 2026)**. It starts working when a period that covers
the current date is added.

## Insight note sources

The two written notes on the screen say only what their sources say:

- Tissera et al., "Severe Dengue Epidemic, Sri Lanka, 2017", Emerging
  Infectious Diseases 26(4), April 2020 (authors from the National Dengue
  Control Unit and Central Epidemiology Unit):
  <https://wwwnc.cdc.gov/eid/article/26/4/19-0435>. Used for: seasonal epidemics
  mostly in areas with annual rainfall above 2,500 mm; one quarter of the
  year's cases reported 5 weeks after the southwest monsoon started (2017); in
  the Western Province more than half of Aedes aegypti breeding was in
  discarded items such as containers and tyres.
- WHO, Dengue fact sheet (21 August 2025):
  <https://www.who.int/news-room/fact-sheets/detail/dengue-and-severe-dengue>.
  Used for: "dispose of solid waste properly and remove artificial habitats
  that can hold water".

## Limitations

- **Reported cases only.** The counts are notified cases, not all infections.
  Reporting habits and testing change from week to week.
- **Recent weeks can be revised.** A report is a snapshot; later reports may
  correct earlier weeks, and this data was not re-checked against them.
- **RDHS is not the same as district.** The areas follow health regions.
  Kalmunai is its own RDHS and is shown as "Kalmunai (Ampara)" next to
  Ampara; the other names match the administrative districts but the borders
  may differ.
- **Only two years.** The seasonal level averages 2024 and 2025 (about 2 values
  per week), so it is noisy and one big outbreak year can dominate it. Three
  weeks of 2025 are missing (18, 38, 51).
- **The latest data is week 52 of 2025.** 2026 reports were not available. The
  index shows what is usual for this time of year, not what is happening now.
- **The sum check has 9 flagged weeks** because of typos in the printed totals
  (see above).
- **Live reports are mapped to the nearest district centre**, which is an
  approximation and can misplace reports near borders. The count is the number
  of valid reports, not adjusted for how many people use the app in each
  district.
- **Few waste periods, all in the past**, and each covers only the area its
  source names.
- **The index is not a forecast** and is not medical advice.
