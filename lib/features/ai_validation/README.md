# AI photo validation

Checks whether a report photo shows a possible dengue mosquito breeding site,
using Gemini through Firebase AI Logic (Gemini Developer API).

Work in progress. Camera, GPS, the AI check, the decision and the Report screen
flow are done. The duplicate check is still a stub (see below).

## What is here

| File | Purpose |
|---|---|
| `ai_config.dart` | The Gemini model name (one constant), request timeout, minimum confidence (0.7). |
| `ai_prompts.dart` | System instruction and prompt for the photo check. |
| `ai_validation_service.dart` | `AiValidationService.validatePhoto(Uint8List jpegBytes)`. |
| `validation_result.dart` | `ValidationResult` and `SiteCategory`. |
| `capture_service.dart` | `captureReportPhoto()`: live camera photo plus a GPS fix. |
| `capture_result.dart` | `CaptureResult` (photo + GPS, or why it failed). |
| `duplicate_check.dart` | `isDuplicate(lat, lng)`. **Stub: always false** until Step 8. |
| `report_decision.dart` | `decide(ai, capture, isDuplicate)`: the eligibility rule. |
| `report_check_controller.dart` | Runs validatePhoto, then the duplicate check, then `decide()`. |
| `report_outcome.dart` | `ReportOutcome` and the `onDecision` callback type. |
| `dev_live_test.dart` | Debug-only live test (see Testing). |

## How the Report screen uses it

The whole flow lives in `lib/features/report/report_screen.dart` (form, checking,
approved, rejected). Submit is enabled only after a live camera photo with a
valid GPS fix (within 50 m). Then:

1. **Checking:** `ReportCheckController.check()` runs. The screen shows real
   progress. If the check itself fails (network, quota, App Check, duplicate
   lookup error) the user gets **Try again / Retake photo**; nothing is
   approved on an error.
2. **Approved** or **Rejected** is decided by `decide()`. A report is eligible
   only if the AI says it is a breeding site with confidence of at least 0.7,
   the photo does not look fake, it is not a duplicate, and GPS is within 50 m.

## Hook for report submission and points

`ReportScreen` has an optional callback:

```dart
ReportScreen(onDecision: (ReportOutcome outcome) { ... });
```

It is called **once per completed check** with a final approved or rejected
decision. It is **not** called when the check failed (the user retries instead).
This screen does not save anything and does not award points. `ReportOutcome`
contains:

- `capture.jpegBytes`, `capture.latitude`, `capture.longitude`,
  `capture.accuracyMeters`: the live photo and GPS fix
- `validation.category`, `validation.confidence`, `validation.reason`,
  `validation.looksFake`: the AI result
- `isDuplicate`, `decision.eligible`, `decision.reason`, `checkedAt`

What the submission owner should do:

- Only save reports with `outcome.eligible == true`. A rejected photo is not
  saved; the user retakes it.
- Save an eligible report with `status: 'approved'` (automatic, no manual
  review) and fill `aiCategory` (`validation.category.wireValue`),
  `aiConfidence` and `aiReason` from `outcome.validation`. These optional fields
  are on `ReportModel` and documented in `docs/DATA_MODEL.md`.
- `confirmationCount` is for community "still there" confirmations, not a gate.
- Write `geohash` with the encoder from `geohash.dart` (precision 9) once it is
  added in Step 8, so the duplicate check can find the report.
- The Approved screen says "Eligible for 10 points"; actually awarding the
  points is up to the submission/points owner.

## Demo controls

The old "UI FLOW" stage bar and the Simulate Approved/Rejected buttons are hidden
by default. Show them for demos with:

```bash
flutter run --dart-define=DEMO_CONTROLS=true
```

`validatePhoto` never throws. Any failure (network, timeout, quota, App Check
rejection, malformed reply) returns `ValidationResult.error(...)`, which is
never a breeding site and so can never lead to a verified report.

The checks run on the phone, so a determined user could bypass them. That is
acceptable for this coursework project; real enforcement would need Firestore
rules or a server function.

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
2. Find your debug token. Look in the `flutter run` output for a line like
   ```
   Enter this debug secret into the allow list in the Firebase Console for your project: <uuid>
   ```
   If it is not in the `flutter run` output, read it from the Android log:
   ```bash
   adb logcat -c            # clear the log, then restart the app
   adb logcat -d | grep -i "debug secret"        # Git Bash
   adb logcat -d | Select-String "debug secret"  # PowerShell
   ```
   On iOS, search the Xcode console for `App Check debug token`.
3. **Send the token privately to the branch owner (Manuja) so they can register
   it** under Firebase console > App Check > Apps > Manage debug tokens. Do not
   commit it, paste it into code, or post it in a public place.
4. The token changes if you uninstall the app or clear its data. Repeat the
   steps above if the AI calls start failing with App Check errors.
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

With this set, tapping **Camera** skips the camera and uses that bundled asset as
the photo. Location services, location permission and the GPS fix (within 50 m)
are still checked for real, so set a location on the emulator first. It only
works in debug builds (`kDebugMode`) and is ignored in profile and release
builds. Leave the flag out for the normal camera. The photo must be a `.jpg`
inside `assets/dev_samples/` (git-ignored, so use your own).

In debug builds the check also prints timings and the AI result, prefixed
`AI TIMING` and `AI RESULT`:

```bash
adb logcat -d | grep -E "AI TIMING|AI RESULT"
```

Sample photos must be **real JPEG data**. A web download saved as `.jpg` is often
really WebP; the app rejects those ("The photo could not be read"). Check with
`file assets/dev_samples/*.jpg` and convert if needed.
