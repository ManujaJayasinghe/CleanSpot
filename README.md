# CleanSpot

CleanSpot is a community dengue risk monitoring mobile application built with Flutter and Firebase. Residents report potential mosquito breeding sites by taking a live camera photo with a GPS fix, earn points when the AI photo check approves a new site, and redeem points for sponsor coupons. Users can explore active breeding sites on a live risk map and heatmap, review district dengue trends and a seasonal risk index calculated from Sri Lanka Epidemiology Unit weekly reports, and use a symptom self-check guide. Public health authorities and administrators have dedicated dashboards to inspect and clear reported sites and manage users and reward coupons.

This project was developed for the Mobile Application Development coursework module (`SE303.3-MAD`) at NSBM Green University.

## Features

- **Reporting with live photo and GPS**: `captureReportPhoto()` (`lib/features/ai_validation/capture_service.dart`) checks location services and permission before opening the device camera (`ImageSource.camera`, max width 1280 px, JPEG quality 80). Gallery uploads are not supported, and the captured bytes must start with the JPEG header `FF D8 FF`. Immediately after capture, the app requests a GPS fix (`LocationAccuracy.best`, 15 s timeout) and rejects fixes with accuracy worse than 50 m. The report form previews the captured coordinates and accuracy radius on a read-only OpenStreetMap card (`LocationPreviewMap`).
- **AI photo validation**: `AiValidationService.validatePhoto()` sends the JPEG to Gemini (`gemini-3.5-flash-lite`) through Firebase AI Logic with temperature `0`, a 30 s timeout, and a fixed JSON response schema (`isBreedingSite`, `category`, `confidence`, `looksFake`, `reason`). A photo passes only when `looksFake` is `false`, `isBreedingSite` is `true`, and `confidence` is at least `0.7`. Any network, timeout, quota, or App Check failure asks the user to retry and never approves a report.
- **Duplicate and "still present" rule**: After a photo passes the AI check, `findStillPresentReport()` queries the precision-6 geohash cell of the report and its 8 neighbouring cells on the Firestore server. If a `'valid'` report from any user exists within 50 m (by Haversine distance) and has activity (`createdAt` or `lastConfirmedAt`) within the last 14 days, the app marks that existing report as still present (`confirmationCount + 1` and a new server-time `lastConfirmedAt`) instead of creating a duplicate report or awarding points.
- **Points and rewards shop**: Each approved new report awards 10 points (`kPointsPerValidReport = 10` in `lib/services/report_write_plan.dart`) in a single atomic write batch alongside the report metadata and compressed photo. In the Rewards tab (`/rewards`), users spend points to redeem available coupons in a Firestore transaction (`FirestoreService.redeemCoupon`) that supports single codes and multi-code stock pools, and view claimed promo codes under My Coupons (`/profile/coupons`).
- **Live risk map and heatmap**: `RiskMapView` (`lib/features/map/risk_map_view.dart`) renders OpenStreetMap street tiles on a Web Mercator viewport with a toggle between radial risk heatmap blobs and water-drop pins for `'valid'` reports, time-range chips (Last 7 days, Last 30 days, All time), and a detail bottom sheet that loads the site photo on demand. A non-interactive preview (`RiskMapPreview`) also sits on the Home dashboard.
- **Seasonal dengue risk analysis from Epidemiology Unit data**: The Analysis screen (`/analysis`) loads weekly notified dengue cases across 26 RDHS areas from `assets/data/dengue_stats.csv` (built from Sri Lanka Ministry of Health Weekly Epidemiological Report PDFs by `tool/extract_dengue.py`) and sourced waste collection disruptions from `assets/data/waste_periods.csv`. It computes a district seasonal risk index (Low, Medium, High) for today's ISO week, adjusted for active waste periods and districts with more than 2 live valid reports in the last 14 days, and displays weekly charts (`fl_chart`) with sourced public health notes.
- **Symptom checker**: The Symptom Checker (`/symptoms`) walks the user through 7 yes/no questions (`symptomQuestions`) followed by 4 warning signs (`warningSigns`). It classifies the result into High risk (any warning sign ticked), Medium risk (fever for two or more days plus at least two other symptoms), or Low risk, and displays next-step advice with a medical disclaimer.
- **Admin dashboard**: The Admin Dashboard (`/admin`) displays live platform counters (total users and total, valid, rejected, and cleared reports) and provides two management tabs: Users & Roles (search users, change roles between `user`, `authority`, and `admin`, and block or unblock accounts) and Coupons & Stock (create coupons with single codes or comma-separated code pools, and delete coupons).
- **Authority dashboard**: The Authority Dashboard (`/authority`) gives health officers a live risk heatmap and marker view, active and cleared site counters, area filter chips grouping valid reports by nearest RDHS district centre (`nearestDistrict`) and sorting them by area name and highest "still present" confirmation count, a full report detail sheet with the site photo, and a "Mark as cleared" action that updates the report status to `'cleared'` and deletes its `reportPhotos` document in one batch.

## User roles

Roles are stored in `users/{uid}.role` in Cloud Firestore (`lib/models/user_model.dart`) and enforced by `lib/app/session.dart` in the router and by `firestore.rules` on the server:

| Role | Default landing route | What the role can do |
|---|---|---|
| `user` | `/home` | Submit breeding-site reports, confirm existing sites as still present, earn points, redeem coupons, view the risk map, dengue analysis, symptom checker, and personal report and coupon history. Cannot open `/admin` or `/authority`. |
| `authority` | `/authority` | View all valid breeding-site reports grouped by district area on the Authority Dashboard, inspect report photos and confirmation counts, and mark valid reports as `'cleared'` (which also deletes the stored photo from `reportPhotos`). Cannot open `/admin`, edit user roles, or manage coupons. |
| `admin` | `/home` (with access to `/admin` from Profile and `/authority`) | Full user app access plus the Admin Dashboard (`/admin`): read and list all user documents, change any user's `role` (`user`, `authority`, `admin`) or `blocked` status, add or delete coupons in `coupons`, view all reports across all statuses, and mark valid reports as `'cleared'`. |

## Tech stack

- **Framework and language**: Flutter with Dart SDK `^3.13.0` (`pubspec.yaml`).
- **Routing and state**: `go_router` (`^18.0.2`) with a live `SessionNotifier` (`ChangeNotifier`) route guard, and `provider` (`^6.1.5+1`).
- **Firebase services**:
  - `firebase_core` (`^5.1.0`)
  - `firebase_auth` (`^7.0.1`) and `google_sign_in` (`^7.2.0`) for Email/Password and Google authentication
  - `cloud_firestore` (`^7.1.0`) for all application data and Base64 report photos
  - `firebase_app_check` (`^0.5.1`) using the debug provider in debug builds and Play Integrity / App Attest in release builds
  - `firebase_ai` (`^5.1.0`) for Firebase AI Logic, calling Gemini model `gemini-3.5-flash-lite` (`kAiModelName` in `lib/features/ai_validation/ai_config.dart`) via `FirebaseAI.googleAI()`
- **Device sensors, media, and charts**: `image_picker` (`^1.2.4`), `geolocator` (`^14.1.2`), `image` (`^4.3.0`), `fl_chart` (`^1.3.1`), and `cupertino_icons` (`^2.0.0`).
- **Maps**: OpenStreetMap street tiles (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`) projected with a custom Web Mercator implementation (`lib/features/map/map_projection.dart`) and rendered in `RiskMapView`, `LocationPreviewMap`, and `AuthorityHomeScreen`. The `google_maps_flutter` (`^2.19.0`) package is included for coordinate/heatmap data types (`LatLng`, `WeightedLatLng` in `lib/features/map/map_filters.dart`) and native platform key configuration.
- **Firebase Spark plan design**: The backend runs on the free Firebase Spark plan, which does not include Cloud Functions or free Cloud Storage buckets (note: `firebase_storage: ^14.0.1` is listed in `pubspec.yaml`, but the app does not use Cloud Storage). Instead, approved report photos are resized in `lib/features/report/report_screen.dart` to at most 800 px, encoded as JPEG at quality 70 (and stepped down if needed to stay under 300 KB), and stored as Base64 in `reportPhotos/{reportId}` separate from `reports/{reportId}` so list, map, and geohash queries never transfer image bytes.

## Project structure

```text
CleanSpot/
├── lib/
│   ├── main.dart                     # App entry point, Firebase init, App Check, AI_LIVE_TEST hook
│   ├── firebase_options.dart         # Generated FlutterFire configuration for clearspot-640fb
│   ├── app/                          # GoRouter config, SessionNotifier role guard, splash, themes
│   ├── models/                       # UserModel, ReportModel, CouponModel, RedemptionModel
│   ├── services/                     # FirestoreService and ReportWritePlan batch builders
│   └── features/
│       ├── admin/                    # Admin dashboard: platform stats, user roles/blocking, coupon stock
│       ├── ai_validation/            # Camera+GPS capture, Gemini validation, geohash duplicate check, decision
│       ├── analysis/                 # Epidemiology Unit CSV parser, seasonal risk index, charts, notes
│       ├── auth/                     # Email/password and Google login and registration screens
│       ├── authority/                # Authority dashboard: area-sorted valid reports, heatmap, mark cleared
│       ├── home/                     # Home dashboard: points card, live map preview, latest report card
│       ├── map/                      # Web Mercator OSM tile renderer, risk heatmap/markers, report location preview
│       ├── profile/                  # User profile, My Reports, My Coupons, shared profile widgets
│       ├── report/                   # Breeding-site report workflow, photo compression, on-demand photo view
│       ├── rewards/                  # Rewards shop screen, coupon cards, redemption dialog
│       └── symptoms/                 # 7-question dengue symptom checker, warning signs, result guidance
├── assets/
│   ├── data/                         # dengue_stats.csv, waste_periods.csv, dengue_stats_sample_fallback.csv
│   ├── dev_samples/                  # Git-ignored local folder for debug AI test photos (.gitkeep tracked)
│   └── images/                       # CleanSpot logo asset
├── docs/                             # AI_VALIDATION.md, ANALYSIS_DATA.md, DATA_MODEL.md, FIREBASE_BACKEND.md, TEST_RESULTS.md
├── firestore-rules-test/             # Local Firestore emulator unit tests for firestore.rules
├── tool/                             # Python WER PDF downloader/extractor scripts, manifests, logo generator
├── firestore.rules                   # Cloud Firestore security rules
└── firebase.json                     # Firebase CLI and Firestore emulator configuration
```

## Getting started

### Prerequisites

- Flutter SDK supporting Dart `^3.13.0` (`flutter --version`)
- Android Studio (with Android SDK and an emulator or physical Android device) or Xcode for iOS
- For running the local Firestore security rules tests: Node.js, Java 11 or newer, and the Firebase CLI (`npm install -g firebase-tools`)

### Clone and install dependencies

```powershell
git clone https://github.com/ManujaJayasinghe/CleanSpot.git
cd CleanSpot
flutter pub get
```

### Firebase configuration and Google sign-in

The Firebase configuration files (`android/app/google-services.json` and `lib/firebase_options.dart`) for project `clearspot-640fb` are already committed to the repository. Email/password authentication and Firestore work right away after cloning.

For **Google sign-in on Android**, Firebase requires the SHA-1 certificate fingerprint of each developer machine's debug keystore:

1. Print your debug keystore SHA-1 in PowerShell:
   ```powershell
   keytool -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore"
   ```
   On macOS or Linux, replace `"$env:USERPROFILE\.android\debug.keystore"` with `"$HOME/.android/debug.keystore"`. When prompted for the keystore password, press Enter or enter the standard Android debug keystore password.
2. In the Firebase console, open **Project settings > Your apps > clean_spot (android)** and click **Add fingerprint** to register your SHA-1.
3. Download the updated `google-services.json` into `android/app/google-services.json`.

### App Check debug token

Firebase AI Logic requires a valid App Check attestation. Debug builds use `AndroidDebugProvider` on Android and `AppleDebugProvider` on iOS (`lib/main.dart`). Until your install's debug token is registered in the Firebase console, AI photo validation fails with HTTP 403 and the Report screen shows **Try again**.

1. Run the app once on your connected device or emulator:
   ```powershell
   flutter run -d <deviceId>
   ```
2. Search the device log for the line containing `debug token` (`Firebase App Check debug token: <uuid>`):
   ```powershell
   adb logcat -d | Select-String "App Check debug token"
   ```
   On macOS or Linux, run `adb logcat -d | grep "App Check debug token"`. On iOS, search the Xcode console output for `App Check debug token`.
3. Open **Firebase console > App Check > Apps > clean_spot (android) > Manage debug tokens > Add debug token** and paste only the UUID value.
4. Wait one to two minutes, then restart the app. The debug token changes if you uninstall the app or clear app storage.

### Maps key configuration

`MapScreen` (`lib/features/map/map_screen.dart`) and `AuthorityHomeScreen` (`lib/features/authority/authority_home_screen.dart`) check whether `MAPS_API_KEY` is configured via `checkMapsApiKeyConfigured()` (`lib/features/map/map_filters.dart`). If no key is set, both screens show a **Map key not set** message instead of crashing, while the Home preview (`RiskMapPreview`) and Report form preview (`LocationPreviewMap`) render OpenStreetMap tiles directly.

To enable the map on `MapScreen` and `AuthorityHomeScreen`, set `MAPS_API_KEY` in one of these git-ignored files (or pass `--dart-define=MAPS_API_KEY=<your-key>` at run time):

- **Android** (`android/local.properties`, read by `android/app/build.gradle.kts` and exposed by `MainActivity.kt`):
  ```properties
  MAPS_API_KEY=your_maps_api_key_here
  ```
- **iOS** (`ios/Flutter/Secrets.xcconfig`, read via `Info.plist` by `ios/Runner/AppDelegate.swift`):
  ```xcconfig
  MAPS_API_KEY=your_maps_api_key_here
  ```

### Running the app and `--dart-define` flags

Run a standard build on your device or emulator:

```powershell
flutter run -d <deviceId>
```

The codebase supports four `--dart-define` flags:

| Flag | Defined in | What it does |
|---|---|---|
| `DEMO_CONTROLS=true` | `lib/features/report/report_screen.dart` | Shows the "UI FLOW" stage switcher bar and the Simulate Approved / Simulate Rejected buttons on the Report screen for classroom demonstrations. Off by default. |
| `AI_LIVE_TEST=true` | `lib/main.dart`, `lib/features/ai_validation/dev_live_test.dart` | Debug builds only (`kDebugMode`). At startup, runs `AiValidationService.validatePhoto()` on every `.jpg` or `.jpeg` in `assets/dev_samples/` and logs each `ValidationResult` with prefix `AI LIVE TEST`. |
| `DEBUG_CAPTURE_ASSET=assets/dev_samples/<file>.jpg` | `lib/features/ai_validation/capture_service.dart` | Debug builds only (`kDebugMode`). Skips opening the camera when tapping Camera on the Report screen and loads the specified bundled JPEG asset instead, while still running real location permission and GPS accuracy checks (useful on an emulator where the virtual camera scene is rejected as fake). |
| `MAPS_API_KEY=<key>` | `lib/features/map/map_filters.dart` | Satisfies `checkMapsApiKeyConfigured()` from the command line without editing `android/local.properties` or `ios/Flutter/Secrets.xcconfig`. |

Example running with the debug capture asset on an emulator:

```powershell
flutter run -d <deviceId> --dart-define=DEBUG_CAPTURE_ASSET=assets/dev_samples/sample.jpg
```

## Running the tests

Run static analysis and the Flutter unit and widget test suite from the repository root:

```powershell
flutter analyze
flutter test
```

To run the Cloud Firestore security rules tests against the local Firestore emulator (configured on port `8080` in `firebase.json`), you need Node.js, Java 11+, and the Firebase CLI (`firebase --version`):

```powershell
cd firestore-rules-test
npm install
npm test
```

## How the AI check works

1. `captureReportPhoto()` verifies location services and permission, captures a live camera JPEG (or loads `DEBUG_CAPTURE_ASSET` in debug mode), and records a GPS fix that must be accurate to within 50 m.
2. `AiValidationService.validatePhoto()` sends the JPEG to `gemini-3.5-flash-lite` via Firebase AI Logic with temperature `0` and parses a strict JSON verdict (`isBreedingSite`, `category`, `confidence`, `looksFake`, `reason`).
3. If the AI check succeeds, `findStillPresentReport()` queries the report's precision-6 geohash cell and its 8 neighbours on the Firestore server for any `'valid'` report within 50 m active in the last 14 days.
4. `decide()` rejects the report if the AI call errored, GPS accuracy exceeded 50 m, `looksFake` is true, `isBreedingSite` is false, or `confidence < 0.7`; otherwise it returns **still present** when an existing report matched or **approved** for a new site.
5. `ReportScreen` writes the outcome to Firestore: an approved report saves `reports/{id}`, `reportPhotos/{id}`, and `+10` user points in one batch; a rejected report saves only `reports/{id}`; a still-present result increments `confirmationCount` and updates `lastConfirmedAt` in a transaction.

For full implementation details, data schemas, and backend rules, see:

- [AI photo validation guide](docs/AI_VALIDATION.md)
- [Firestore data model](docs/DATA_MODEL.md)
- [Dengue analysis data and seasonal risk index](docs/ANALYSIS_DATA.md)
- [Firebase backend and security rules reference](docs/FIREBASE_BACKEND.md)
- [Automated and manual test results](docs/TEST_RESULTS.md)

## Team workflow

- Create a dedicated branch from `main` for every feature, fix, or documentation task (for example `feature/<name>`, `fix/<name>`, or `docs/<name>`).
- Run `flutter analyze` and `flutter test` locally before opening a pull request.
- Merge changes into `main` through pull requests only. Never push directly to `main`.

## Known limitations

- **Checks run on the phone**: Because the Firebase project uses the free Spark plan without Cloud Functions, the AI check, the 50 m / 14-day duplicate lookup, and the `decide()` function execute in the Flutter client. Although `firestore.rules` restricts document fields and limits point increases to `+10`, a determined user with a modified client could bypass the camera and AI check and write a `'valid'` report batch directly.
- **Coupon codes are readable by any signed-in user**: `firestore.rules` allows any signed-in user to read documents in `coupons`, which include the `code` and `codes` fields so the client transaction in `FirestoreService.redeemCoupon` can assign a promo code.
- **Dengue data ends at 2025 week 52**: `assets/data/dengue_stats.csv` contains 101 weeks of Epidemiology Unit data from 2024 week 1 through 2025 week 52 (with 2025 weeks 18, 38, and 51 missing and 2026 PDFs unavailable when fetched; see [docs/ANALYSIS_DATA.md](docs/ANALYSIS_DATA.md)). The seasonal risk index reflects historical averages for the current ISO week rather than live 2026 case notifications.
- **Only the sourced waste periods exist**: `assets/data/waste_periods.csv` includes only three dated news-sourced waste disruptions in Colombo (from 2019, 2024, and June 2026). Because all three are in the past, the waste-period bump does not affect the current date unless a new sourced row covering today is added.
- **The AI check requires a registered App Check debug token on debug builds**: Each developer device or emulator install generates its own App Check debug token that must be added in the Firebase console before Gemini requests succeed.
- **Confirmations of an existing report do not award points and can be repeated**: Marking a site as "still present" increments `confirmationCount` and awards 0 points. Neither the client nor `firestore.rules` stores a list of UIDs that have already confirmed a report, so one user can confirm the same site multiple times.

## Team

Contributors from the repository commit history (`git shortlog -sn --all`):

- Manuja Jayasinghe (`ManujaJayasinghe`)
- IvanShirosh
- kethmiwarnasooriya
- Maduranga14
- Yohan52
- chathuranga00
- madushan24
