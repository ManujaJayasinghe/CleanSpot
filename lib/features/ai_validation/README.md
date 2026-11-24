# AI photo validation

Checks whether a report photo shows a possible dengue mosquito breeding site,
using Gemini through Firebase AI Logic (Gemini Developer API).

The feature is complete: live camera photo and GPS, the AI check, the
"still present" check, the decision, and the Report screen, which saves the
result and awards points (see "Saving the result").

Settings live in `ai_config.dart`: model `kAiModelName`, request timeout
`kAiRequestTimeout` (30 s) and minimum confidence `kMinConfidence` (0.7). The
GPS limit is `CaptureResult.maxAccuracyMeters` (50 m).

## What is here

| File | Purpose |
|---|---|
| `ai_config.dart` | The Gemini model name (one constant), request timeout, minimum confidence (0.7). |
| `ai_prompts.dart` | System instruction and prompt for the photo check. |
| `ai_validation_service.dart` | `AiValidationService.validatePhoto(Uint8List jpegBytes)`. |
| `validation_result.dart` | `ValidationResult` and `SiteCategory`. |
| `capture_service.dart` | `captureReportPhoto()`: live camera photo plus a GPS fix. |
| `capture_result.dart` | `CaptureResult` (photo + GPS, or why it failed). |
| `duplicate_check.dart` | `findStillPresentReport(lat, lng)`: the id of a valid report within 50 m active in the last 14 days, or null. See "Still present rule". |
| `geohash.dart` | `encode(lat, lng, precision)`, `bounds(hash)`, `neighbours(hash)` (the 8 surrounding cells). No package. |
| `haversine.dart` | `haversineMeters(lat1, lng1, lat2, lng2)`. |
| `report_decision.dart` | `decide(ai, capture, existingReportId)`: approved, still present or rejected. |
| `report_check_controller.dart` | Runs validatePhoto, then the still-present check, then `decide()`. |
| `report_outcome.dart` | `ReportOutcome` and the `onDecision` callback type. |
| `dev_live_test.dart` | Debug-only live test (see Testing). |

## How the Report screen uses it

The whole flow lives in `lib/features/report/report_screen.dart` (form, checking,
approved, still present, rejected). Submit is enabled only after a live camera photo with a
valid GPS fix (within 50 m). Then:

1. **Checking:** `ReportCheckController.check()` runs. The screen shows real
   progress. If the check itself fails (network, quota, App Check, the
   still-present lookup) the user gets **Try again / Retake photo**; nothing is
   approved on an error.
2. `decide()` gives one of three results. A photo **passes** only if the AI
   says it is a breeding site with confidence of at least 0.7, the photo does
   not look fake, and GPS is within 50 m.
   - **Approved:** it passes and no valid report covers this spot. A new report
     is saved and earns points.
   - **Still present:** it passes, but a valid report already covers this spot
     (see "Still present rule"). That report is updated; the user sees "Thanks,
     this site is already reported. We've marked it as still present."
   - **Rejected:** it does not pass. This is checked first, so a failing photo
     never marks a site as still present.

## Saving the result (reports, photo and points)

After the check, `ReportScreen` saves the result itself with
`FirestoreService.submitReport` (`lib/services/firestore_service.dart`). What is
written is decided by `buildReportWritePlan` (`lib/services/report_write_plan.dart`)
and is written in **one write batch**, so it all happens or none of it does:

| Result | `reports/{id}` | `reportPhotos/{id}` | `users/{uid}` points |
|---|---|---|---|
| **Approved** (`status: 'valid'`) | yes | yes (the only place the photo is stored) | `+10` (`kPointsPerValidReport`) on `pointsBalance` and `points` |
| **Rejected** (`status: 'rejected'`) | yes (AI fields and geohash included) | **no** | **no** |
| **Still present** | **no new report**; the existing one gets `confirmationCount + 1`, `lastConfirmedAt` (server time) and `lastConfirmationId` | **no** | **no** |

- The `reports` document never contains the photo (no `imageUrl` / `photoUrl`).
  Anything that shows a photo loads it for that one report with
  `FirestoreService.getReportPhoto(reportId)` (cached; placeholder while loading
  or if missing). Lists, the map and the still-present check read `reports` only; a
  test (`test/services/report_photos_access_test.dart`) fails if that changes.
- `type` and `aiCategory` are saved as wire values (`stagnant_water`, `tire`,
  `blocked_drain`, `container`, `other`, `none`). Older documents with enum names
  (`blockedDrain`) are converted when read.
- `createdAt` is the server's time; `geohash` is `encode(lat, lng, 9)` from
  `geohash.dart`, so the still-present check can find the report.
- `confirmationCount` counts "still present" confirmations
  (`FirestoreService.markReportStillPresent`). It runs in a transaction that
  reads the report from the server; if the report already has this
  confirmation's `lastConfirmationId` (an earlier attempt whose reply was lost),
  it writes nothing, so Retry never counts twice.

**Failures.** `submitReport` never swallows an error. If saving fails the
Approved view shows "Couldn't save your report" with **Retry** (re-runs only the
save, not the AI check) and **Retake photo**, and never claims points were added.
"+10 points added" appears only after the save succeeded. Each outcome gets one
report id; Retry reuses it, and `submitReport` writes nothing (and awards no
points) if that report already exists on the server, so a retry cannot save the
report or the points twice. The "already saved?" check reads from the server
only, so being offline fails the save instead of queueing a write.

## Hook for other code (`onDecision`)

`ReportScreen` also has an optional callback, if something else needs to react
to a result:

```dart
ReportScreen(onDecision: (ReportOutcome outcome) { ... });
```

It is called **once per completed check** with a final approved or rejected
decision, when that decision is made (before the save finishes). It is **not**
called when the check itself failed (the user retries instead). `ReportOutcome`
contains:

- `capture.jpegBytes`, `capture.latitude`, `capture.longitude`,
  `capture.accuracyMeters`: the live photo and GPS fix
- `validation.category`, `validation.confidence`, `validation.reason`,
  `validation.looksFake`: the AI result
- `existingReportId` (set when the site was already reported),
  `decision.kind`, `decision.eligible`, `decision.isStillPresent`,
  `decision.reason`, `checkedAt`

Do not save the report again from this callback: the screen already does.

## Still present rule

From the proposal: a site reported again within about 50 m and 14 days is a
"still present" update, not a new report. This applies to **any user**, so a
site always has one report, and a second account cannot earn points for it.

`findStillPresentReport(lat, lng)` in `duplicate_check.dart`:

1. Takes the precision-6 geohash of the point (a cell about 1.2 km x 0.6 km)
   and its 8 neighbours. Together they always cover the 50 m radius.
2. Runs one range query per cell on `reports`, in parallel:
   `orderBy('geohash').startAt([prefix]).endAt([prefix + '\uf8ff'])`. Reads
   come from the **server only**. Offline, the queries fail; they do not
   silently use the cache.
3. Filters the results on the phone (`matchDistance`): `status == 'valid'`,
   last activity (the later of `createdAt` and `lastConfirmedAt`) within the
   last 14 days, and Haversine distance ≤ 50 m from `location`. Documents
   missing timestamps or `location` are ignored. Because confirmations count as
   activity, a site that keeps being confirmed stays one report.
4. Returns the id of the **nearest** match, or null for a new site. If any query
   fails it **throws**, and the check controller shows the retryable error. A
   failed lookup is never treated as "new site".

The radius and window are `stillPresentRadiusMeters` and `stillPresentWindow`.
Only `'valid'` reports match, so a report whose status is changed later (for
example cleared by an authority) no longer matches, and a new photo there
becomes a new report.

Only a single-field index on `geohash` is needed, which Firestore creates
automatically. Status and date are filtered on the phone, so no composite index
is needed. Each check reads every report in 9 cells (about 3.3 km x 1.8 km).
That is fine at coursework scale.

## Demo controls

The old "UI FLOW" stage bar and the Simulate Approved/Rejected buttons are hidden
by default. Show them for demos with:

```bash
flutter run --dart-define=DEMO_CONTROLS=true
```

## Failures, limits and security

- `validatePhoto` never throws. Any failure (network, timeout, quota, App Check
  rejection, malformed reply) returns `ValidationResult.error(...)`, which is
  never a breeding site and so can never lead to a verified report.
- In debug builds, a failed check is logged as `Report check failed: <detail>`
  and a failed save as `Saving the report failed: <error>`
  (`adb logcat -d | grep -E "Report check failed|Saving the report failed"`).
  Nothing else is logged.
- **The still-present rule is location-based only.** Photos are never
  compared. Any passing photo within 50 m of a valid report active in the last
  14 days marks that report as still present, from any user and any angle.
  Two different sites less than 50 m apart count as one. GPS may be off by up
  to 50 m, so two reports of the same site can occasionally both be approved.
- The checks run on the phone, so a determined user could bypass them. That is
  acceptable for this coursework project; real enforcement would need Firestore
  rules or a server function.

## Firebase console setup

- **App Check:** Firebase AI Logic is enforced by App Check.
  - Debug builds use the debug provider. Every developer install needs its
    token registered (see "Live test" below).
  - Release builds use **Play Integrity** on Android (App Attest on iOS). Before
    a release or demo build, register Play Integrity for the Android app under
    App Check > Apps, with the app's SHA-256 signing fingerprint. Without it,
    every AI check in a release build fails.
- **Firestore rules:** signed-in users must be able to read `reports` (for the
  still-present check), update other users' reports (for still-present
  confirmations; the current rules allow this) and write `reports`, `reportPhotos` and their own points.
  If reads are denied, every check ends on **Try again**.
- **Indexes:** none to add (see "Still present rule").

## Testing

### Unit tests

```bash
flutter test test/features/ai_validation
```

### Live test with real photos (needs your own App Check debug token)

Firebase AI Logic requires App Check. Debug builds use the App Check *debug
provider*, which generates a token per app install. Gemini calls from your phone
are rejected until that token is registered in the Firebase console.

1. Run the app once on your phone or emulator:
   ```bash
   flutter run -d <deviceId>
   ```
2. Find your debug token. On Android it is in the log as
   `Firebase App Check debug token: <uuid>`:
   ```bash
   adb logcat -d | grep "App Check debug token"           # macOS / Git Bash
   adb logcat -d | Select-String "App Check debug token"  # PowerShell
   ```
   If nothing prints, close and reopen the app, then try again. On iOS, search
   the Xcode console for `App Check debug token`.
3. Register it under Firebase console > App Check > Apps > **clean_spot
   (android)** > ⋮ > Manage debug tokens > Add debug token. Paste **only the
   UUID** into Value (anything else gives "must be a version 4 UUID"). Do not
   click "Generate token". If you do not have console access, send the token
   privately to Manuja. Do not commit it, paste it into code, or post it in a
   public place.
4. Wait a minute or two, then fully close and reopen the app.
   - Until the token is registered, checks fail with
     `403 App attestation failed`.
   - Retrying quickly then gives `Too many attempts`; wait a few minutes before
     trying again.
   - The token changes if you uninstall the app or clear its data. Repeat these
     steps if checks start failing with App Check errors.
5. Put your own `.jpg` or `.jpeg` photos in `assets/dev_samples/`. The folder
   is tracked only through `.gitkeep`; the photos are git-ignored and stay on
   your machine. Good test set: a tyre or pot holding water, a clean room, a
   photo of a screen showing a puddle, and a selfie.
6. Run the live test:
   ```bash
   flutter run -d <deviceId> --dart-define=AI_LIVE_TEST=true
   ```
   The test only runs in debug builds and only with that flag. Each photo's full
   `ValidationResult` is printed with the prefix `AI LIVE TEST`:
   ```bash
   adb logcat -d | grep "AI LIVE TEST"
   ```
   `isError: true` means the call or the reply failed; the error text says why.

### Testing the Report screen without a real camera (emulator)

The emulator camera only shows a virtual scene, which the AI correctly rejects as
fake. To test the whole Report flow with a real photo, use the debug capture
override:

```bash
flutter run -d <deviceId> --dart-define=DEBUG_CAPTURE_ASSET=assets/dev_samples/drain.jpg
```

This works on a real phone too, if you want to test with a fixed photo. With this set, tapping **Camera** skips the camera and uses that bundled asset as
the photo. Location services, location permission and the GPS fix (within 50 m)
are still checked for real, so set a location on the emulator first. It only
works in debug builds (`kDebugMode`) and is ignored in profile and release
builds. Leave the flag out for the normal camera. The photo must be a `.jpg`
inside `assets/dev_samples/` (git-ignored, so use your own).

Sample photos must be **real JPEG data**. A web download saved as `.jpg` is often
really WebP; the app rejects those ("The photo could not be read"). Check with
`file assets/dev_samples/*.jpg` and convert if needed (on macOS:
`sips -s format jpeg in.png --out assets/dev_samples/photo.jpg`).

### Manual test checklist

1. Report a real breeding site (e.g. a container holding water). Expect
   **Approved** and +10 points. In Firestore, the new `reports` document has a
   9-character `geohash`, `status: "valid"` and a server `createdAt`, and
   `reportPhotos/{id}` exists.
2. Report again within 50 m (same or another account). Expect **Site Already
   Reported** with "Thanks, this site is already reported. We've marked it as
   still present.", no new `reports` document, no points, and the existing
   report's `confirmationCount` up by 1 with a new `lastConfirmedAt`.
3. Photograph something unrelated (a clean desk, a selfie). Expect **Rejected**
   as not a breeding site.
4. Turn on airplane mode and submit. Expect **Try again**; nothing is saved.
