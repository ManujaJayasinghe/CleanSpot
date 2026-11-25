## Dengue Data and Seasonal Risk Analysis

### 1. Introduction

This report explains the dengue data collection, processing, validation, and seasonal risk calculation implemented in the application. The analysis uses weekly dengue case data published by the Epidemiology Unit of the Ministry of Health, Sri Lanka, together with selected waste-management reports. The purpose is to provide district-level seasonal risk information using historical dengue patterns and additional environmental indicators.

The dengue data is obtained from the Epidemiology Unit's *Weekly Epidemiological Report* (WER), which publishes weekly information about notifiable diseases reported by Medical Officers of Health (MOH) areas [1]. The application uses the reported dengue figures to support its Regional Director of Health Services (RDHS)-level analysis.

### 2. Dengue Data Source and Extraction

The primary data source is Table 1, which presents notifiable diseases reported by Medical Officers of Health in the *Weekly Epidemiological Reports*. The analysis uses the weekly dengue fever case count from Column A. Column B, which contains cumulative totals, is not used because the application requires individual weekly case counts.

The reporting week and year are identified using the date range and week number printed in each report's title. For example, a report titled `"20th–26th Dec 2025 (52nd Week)"` is recorded as week 52 of 2025. This approach ensures that the extracted data is associated with the correct reporting period [1].

A Python extraction script processes the downloaded PDF reports. It handles sideways table characters where necessary and identifies the dengue fever row before extracting the 26 RDHS-level values. The printed Sri Lanka total is used only for validation and is not treated as an additional district record.

The data is stored in `assets/data/waste_periods.csv` for waste-related periods and the relevant dengue dataset described in the project documentation. The extracted dengue records are organised by year, epidemiological week, RDHS region, and weekly case count. Kalmunai is retained as a separate RDHS region, while the spelling `"Monaragala"` is standardised to `"Moneragala"` to maintain consistency.

### 3. Data Availability and Coverage

The live Epidemiology Unit website returned HTTP 509 during the data collection process on 24 November 2026. Therefore, an Internet Archive snapshot dated 15 July 2026 was used as an alternative source for retrieving the available reports. The archive listing contained 129 English reports. Of these, 102 archived PDFs were successfully retrieved, while 27 were unavailable.

A total of 101 PDF reports were successfully parsed for the requested years. One report, corresponding to week 52 of 2023, was excluded. The resulting dataset contains 101 epidemiological weeks and 2,626 RDHS-level records, calculated as 101 weeks multiplied by 26 RDHS regions.

The extracted national totals were compared with the totals printed in the reports. Out of 101 reports, 92 national totals matched exactly. Nine reports were flagged because their printed national totals appeared to be missing the final digit. These records were retained with validation warnings rather than silently changing the extracted district values. In addition, five randomly selected district-week values were manually checked against the original reports.

The available weekly coverage is summarised below:

| Year | Available Weeks | Missing Weeks |
| :--- | :---: | :--- |
| 2024 | 52 | None |
| 2025 | 49 | 18, 38, 51 |
| 2026 | 0 | All weeks |

The three missing weeks in 2025 correspond to reports 19, 39, and 52 in Volume 52, which were listed but unavailable for retrieval. The 24 reports in Volume 53, covering reports 2–25 in 2026, were also unavailable. Therefore, the absence of 2026 data is a retrieval limitation and should not be interpreted as an intentional exclusion by the application.

### 4. Seasonal Risk Calculation

The application calculates dengue risk separately for each RDHS region using the current ISO epidemiological week obtained from the device's date and time.

First, the seasonal level is calculated as the average dengue case count for the selected RDHS region across the current epidemiological week and the weeks immediately before and after it, using all available years in the dataset. This provides a historical seasonal reference for the current period.

Next, the district normal is calculated as the average weekly dengue case count for that RDHS region across all available weeks in the dataset. The seasonal score is then calculated by dividing the seasonal level by the district normal. If the district normal is zero, the seasonal score is set to zero to avoid division by zero.

The resulting score is classified using the following thresholds:

* **Low risk:** Seasonal score below `0.8`.
* **Medium risk:** Seasonal score from `0.8` to `1.3`, including both values.
* **High risk:** Seasonal score above `1.3`.

The application also applies additional risk adjustments. One risk level is added when the current date falls within a high-waste period recorded for the relevant district. Another risk level is added when more than two valid CleanSpot reports have been recorded during the previous 14 days. Therefore, three or more valid reports are required to trigger this adjustment. The final risk level is capped at **High**.

The seasonal calculation also handles the transition between the end and beginning of the year. Weeks 52 and 1 are treated as neighbouring weeks, and week 53 is treated as week 52. These rules allow the seasonal calculation to operate consistently around the year boundary.

### 5. Waste-Management Data and Environmental Indicators

The application includes selected waste-management periods as an additional environmental indicator. These periods are recorded in `assets/data/waste_periods.csv` and are based on reported waste-collection issues in Colombo.

The recorded examples include an increase in Colombo's garbage during the festive season in December 2024 [2], a temporary halt in garbage collection reported in August 2019 [3], and reported missed collection areas involving Kaduwela Municipal Council in June 2026 [4].

These records are used to identify periods when waste-related conditions may contribute to environmental risk. However, all three recorded periods are historical relative to 24 November 2026. Consequently, none of these entries should automatically be interpreted as evidence of a current waste-management problem.

The waste indicator is an additional adjustment rather than a direct measurement of dengue cases. It should therefore be interpreted alongside the historical dengue data and not as independent proof of an increase in dengue transmission.

### 6. CleanSpot Reports and Geographic Assignment

CleanSpot reports provide another supplementary indicator in the risk calculation. Valid reports from the previous 14 days are considered. Each report is assigned to the nearest RDHS centre using straight-line geographic distance.

This method provides an approximate regional assignment. It does not perform an exact administrative boundary check, meaning that a report close to an RDHS boundary could be assigned to a neighbouring region. If live CleanSpot reports cannot be loaded, those reports are excluded from the calculation, and the application indicates the loading issue.

### 7. Limitations

Several limitations should be considered when interpreting the results:

* **Underreporting and Revisions:** Reported dengue cases represent notified cases and may not include every infection. The figures may also be revised in later reports.
* **Limited Historical Coverage:** The available historical dataset covers approximately two years and contains three missing weeks in 2025. No 2026 weekly dengue records were available during the extraction process.
* **Validation Warnings and Spatial Approximation:** Nine reports contained national-total validation warnings, and the geographic assignment of CleanSpot reports is based on approximate distance rather than official administrative boundaries.
* **Historical Waste Records:** The waste-management records are limited in number and refer to historical events, so they cannot establish current waste conditions.
* **Rule-Based Heuristic:** The risk index is a rule-based indicator based on historical averages and additional adjustments. It is not a clinical assessment, a confirmed dengue outbreak warning, or a predictive model of future infections. The results should be interpreted as an indication of relative seasonal risk rather than a guarantee of actual dengue activity.

### 8. Conclusion

The implemented analysis combines historical weekly dengue case data, seasonal averages, selected waste-management periods, and recent CleanSpot reports to calculate an RDHS-level dengue risk category. The extraction and validation process provides a structured dataset while identifying unavailable reports and inconsistencies. However, missing data, limited historical coverage, and approximate geographic assignment should be considered when interpreting the results. Improving data availability and incorporating more comprehensive environmental information could strengthen the reliability of future risk assessments.

### References

[1] Epidemiology Unit, Ministry of Health, Sri Lanka, "Weekly Epidemiological Report." [Online]. Available: https://www.epid.gov.lk/epid/public/index.php/weekly-epidemiological-report/weekly-epidemiological-report  
[2] Ada Derana, "Colombo's garbage surges during festive season," Dec. 28, 2024. [Online]. Available: https://adaderana.lk/news/104535/colombos-garbage-surges-during-festive-season  
[3] News First, "Collection of garbage in Colombo halted, solution not yet provided," Aug. 8, 2019. [Online]. Available: https://www.newsfirst.lk/2019/08/08/collection-of-garbage-in-colombo-halted-solution-not-yet-provided/  
[4] Ada Derana, "Report on Kaduwela Municipal Council collection vehicles missing areas," Jun. 29, 2026. [Online]. Available: https://adaderana.lk/news/cmqzd34is0006356pbmnd8jx1