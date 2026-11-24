# Generates assets/data/dengue_stats_sample_fallback.csv: SYNTHETIC placeholder data
# (NOT real statistics) so the Analysis screen runs before Anushka's real CSV
# arrives. Re-run from the project root: powershell -File tool/gen_sample_dengue.ps1
$rand = New-Object System.Random 42
$districts = [ordered]@{
  'Colombo' = 30; 'Gampaha' = 18; 'Kalutara' = 10; 'Kandy' = 9; 'Matale' = 3
  'Nuwara Eliya' = 1; 'Galle' = 6; 'Matara' = 5; 'Hambantota' = 3; 'Jaffna' = 5
  'Kilinochchi' = 1; 'Mannar' = 1; 'Vavuniya' = 1; 'Mullaitivu' = 1; 'Batticaloa' = 4
  'Ampara' = 2; 'Trincomalee' = 3; 'Kurunegala' = 8; 'Puttalam' = 3; 'Anuradhapura' = 3
  'Polonnaruwa' = 2; 'Badulla' = 2; 'Monaragala' = 1; 'Ratnapura' = 5; 'Kegalle' = 4
}
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('district,year,week,cases')
foreach ($name in $districts.Keys) {
  foreach ($year in 2024, 2025, 2026) {
    $lastWeek = 52
    if ($year -eq 2026) { $lastWeek = 45 }
    for ($week = 1; $week -le $lastWeek; $week++) {
      # Two seasonal humps (mid-year and year-end), plus noise.
      $season = 1 + 1.2 * [math]::Exp(-[math]::Pow(($week - 27) / 5.0, 2)) + 0.8 * [math]::Exp(-[math]::Pow(($week - 49) / 4.0, 2))
      $noise = 0.75 + 0.5 * $rand.NextDouble()
      $cases = [int][math]::Round($districts[$name] * $season * $noise)
      $lines.Add("$name,$year,$week,$cases")
    }
  }
}
$out = Join-Path (Get-Location) 'assets\data\dengue_stats_sample_fallback.csv'
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
[IO.File]::WriteAllLines($out, $lines)
Write-Output "Wrote $($lines.Count - 1) rows to $out"
