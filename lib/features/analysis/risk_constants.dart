/// Every threshold of the seasonal dengue risk index, in one place.
///
/// The formula and the reasons for these numbers are written up in
/// docs/ANALYSIS_DATA.md. Change a value here and the screen, the reason lines
/// and the tests that use the constants all follow.
library;

/// Seasonal score below this is Low. The score is the district's usual level
/// for this time of year divided by the district's normal weekly level.
const double seasonalLowBelow = 0.8;

/// Seasonal score above this is High. From [seasonalLowBelow] up to and
/// including this value is Medium.
const double seasonalHighAbove = 1.3;

/// "This time of year" means today's ISO week plus or minus this many weeks.
const int seasonalWeekWindow = 1;

/// The dengue reports number weeks 1 to 52 (a 53rd week is counted as week 52
/// when comparing). Week distance wraps around this year length, so week 52
/// and week 1 are neighbours.
const int seasonalWeeksPerYear = 52;

/// A score within this distance of 1.0 is described as "about the normal
/// level" in the reason line instead of "1.0x higher".
const double nearNormalBand = 0.05;

/// Valid CleanSpot reports are counted over this many days back from today.
const int liveReportWindowDays = 14;

/// The district goes up one level when it has MORE than this many valid
/// reports in the window (so 3 or more).
const int liveReportsBumpAbove = 2;

/// Levels added when today falls in a sourced high-waste period.
const int wastePeriodBump = 1;

/// Levels added when the live-report count is above [liveReportsBumpAbove].
const int liveReportBump = 1;
