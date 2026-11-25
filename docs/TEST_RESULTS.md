# CleanSpot Test Results

**Project:** CleanSpot  
**Date:** 25 November 2026

---

## 1. Automated Test Results

### 1.1 Flutter Tests

The following commands were executed on 25 November 2026 with Flutter 3.47.0, on the latest `main` plus the removal of the Maps API key check:

```bash
flutter analyze
flutter test
```

#### Static Analysis

| Command | Result |
|---|---|
| `flutter analyze` | No issues found. |

#### Test Summary

| Metric | Result |
|---|---:|
| Total test files | 26 |
| Total tests | 271 |
| Passed tests | 271 |
| Failed tests | 0 |
| Skipped tests | 0 |

**Result:** All 271 tests passed, with no failures and none skipped.

The earlier failure in `test/app/session_test.dart` (`SessionNotifier signing in is not ready until the profile arrives`) was fixed when the Home screen changes were merged; the test now expects the `/home` landing route and passes.

### 1.2 Automated Test Coverage

The following table describes the automated test coverage based on the existing test files.

| Test Area | Test File | What the Tests Cover |
|---|---|---|
| AI Validation | `capture_result_test.dart` | JPEG validation, GPS accuracy and capture results. |
| AI Validation | `validation_result_test.dart` | AI response parsing, JSON validation and invalid responses or categories. |
| AI Validation | `report_decision_test.dart` | Report approval and rejection decisions, confidence thresholds and still-present decisions. |
| AI Validation | `report_check_controller_test.dart` | AI validation workflow, duplicate checking and retryable failures. |
| Geohash / Haversine | `geohash_test.dart` | Geohash encoding, decoding, neighbouring cells and location coverage. |
| Geohash / Haversine | `haversine_test.dart` | Geographical distance calculations. |
| Duplicate and Still-Present Rule | `duplicate_check_test.dart` | Duplicate detection using a 50-metre radius, 14-day window and recent confirmations. |
| Duplicate and Still-Present Rule | `report_decision_test.dart` | Still-present decisions and report rejection conditions. |
| Duplicate and Still-Present Rule | `report_check_controller_test.dart` | Detection of existing reports during report submission. |
| Report Saving | `report_write_plan_test.dart` | Valid and rejected report saving, photo storage, points allocation and still-present updates. |
| Report Saving | `report_photos_access_test.dart` | Access restrictions for the separate report photos collection. |
| Report Saving | `report_model_test.dart` | Report serialization, AI fields, photo fields and cleared-report information. |
| Risk Index | `risk_index_test.dart` | Seasonal calculations, risk scores, risk levels, live reports and waste-period adjustments. |
| Risk Index | `analysis_screen_test.dart` | Risk index presentation, charts, historical data and live report information. |

### 1.3 Firestore Security Rules Tests

The following environment requirements were checked:

| Requirement | Installed Version / Status |
|---|---|
| Node.js | v26.13.1 |
| npm | 11.20.0 |
| Java | OpenJDK 21.0.13 |
| Firebase CLI | 15.31.0 |

The commands used to execute the Firestore Rules tests were:

```bash
cd firestore-rules-test
npm install
npm test
```

They ran against the Firestore emulator using the `firestore.rules` and `rules.test.mjs` committed on `main`.

| Metric | Result |
|---|---:|
| Test suites | 7 |
| Total tests | 58 |
| Passed tests | 58 |
| Failed tests | 0 |
| Skipped tests | 0 |

**Test Result:** All 58 Firestore Security Rules tests passed.

The emulator log contains `PERMISSION_DENIED` lines. These are expected: they are the requests that the negative test cases (for example a blocked user trying to redeem a coupon) deliberately send to confirm the rules reject them.

---

## 2. Manual Testing

The following manual test cases are prepared for execution on a real mobile device.

The Actual Result, Pass/Fail and Tester columns are intentionally left blank. These columns should be completed after performing the tests.

| ID | Feature | Steps | Expected Result | Actual Result | Pass/Fail | Tester |
|---|---|---|---|---|---|---|
| MT-01 | User Registration and Login | 1. Open the application. 2. Navigate to the registration screen. 3. Enter valid user details. 4. Register the account. 5. Log out and log in using the registered credentials. | The account should be created successfully, and the user should be able to log in and access the home screen. | | | |
| MT-02 | Google Sign-In | 1. Open the login screen. 2. Select Google Sign-In. 3. Choose a valid Google account. 4. Complete authentication. | The user should be authenticated successfully and redirected to the appropriate screen. | | | |
| MT-03 | Report Approval | 1. Log in as a normal user. 2. Open the report submission feature. 3. Capture a clear photo of a valid dengue breeding location. 4. Submit the report. | The report should pass validation and be saved successfully. The user should receive the appropriate points. | | | |
| MT-04 | Report Rejection | 1. Log in as a normal user. 2. Open the report submission feature. 3. Capture a clean photo that does not show a dengue breeding location. 4. Submit the report. | The report should be rejected by the validation process and should not be saved as an approved report. | | | |
| MT-05 | Still-Present Report Update | 1. Find an existing reported location. 2. Submit a new report for the same location within the applicable period. 3. Confirm that the issue is still present. | The system should recognise the existing report and apply the still-present update rule instead of treating it as an unrelated new report. | | | |
| MT-06 | Camera-Only Photo Capture |