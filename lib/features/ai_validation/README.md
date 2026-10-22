# AI photo validation

Checks whether a report photo shows a possible dengue mosquito breeding site,
using Gemini through Firebase AI Logic (Gemini Developer API).

Work in progress. This first part contains the Gemini plumbing; camera, GPS,
duplicate check and the final decision are added in later steps.

## What is here

| File | Purpose |
|---|---|
| `ai_config.dart` | The Gemini model name (one constant) and the request timeout. |
| `ai_prompts.dart` | System instruction and prompt for the photo check. |
| `ai_validation_service.dart` | `AiValidationService.validatePhoto(Uint8List jpegBytes)`. |
| `validation_result.dart` | `ValidationResult` and `SiteCategory`. |
| `dev_live_test.dart` | Debug-only live test (see Testing). |

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
