# Firebase backend

This document describes the Firebase backend configuration, collections, security rules, role management, App Check setup, and deployment workflow for CleanSpot, verified against the current code and `firestore.rules` on `main`.

## 1. Overview of the Firebase project

- **Project ID**: `clearspot-640fb` (defined in `firebase.json` and `lib/firebase_options.dart`, project number `502186374219`).
- **Configured app targets**: Android (`com.example.clean_spot`, config in `android/app/google-services.json`), iOS and macOS (`com.example.cleanSpot`), Web, and Windows (`lib/firebase_options.dart`).
- **Firebase services used**:
  1. **Firebase Authentication**: user sign-in and account registration.
  2. **Cloud Firestore**: primary NoSQL database for user profiles, breeding-site reports, Base64 report photos, reward coupons, and coupon redemptions.
  3. **Firebase App Check**: device and app attestation protecting AI calls.
  4. **Firebase AI Logic**: client-to-Gemini Developer API bridge (`FirebaseAI.googleAI()`, model `gemini-3.5-flash-lite`) without embedding a Gemini API key in the app binary.
- **Why only Spark plan features are used**: The project runs on the free Firebase Spark tier for university coursework, so it does not use paid Blaze-only features such as Cloud Functions or billed Cloud Storage buckets. All business logic (AI photo validation, geohash duplicate queries, batch writes, and coupon redemption transactions) runs in the Flutter client (`lib/services/firestore_service.dart` and `lib/services/report_write_plan.dart`) and is constrained by server-side rules in `firestore.rules`. Report images are compressed under 300 KB and stored as Base64 strings in a dedicated `reportPhotos` collection in Firestore rather than in Cloud Storage.

## 2. Authentication

### Enabled providers

CleanSpot uses two Firebase Authentication sign-in methods (`lib/features/auth/login_screen.dart` and `lib/features/auth/register_screen.dart`):

1. **Email and password**: `signInWithEmailAndPassword`, `createUserWithEmailAndPassword` (minimum 8-character password enforced in `RegisterScreen`), and `sendPasswordResetEmail` from the "Forgot password?" dialog on `LoginScreen`.
2. **Google sign-in**: `GoogleSignIn.instance.initialize()` and `authenticate()` (`google_sign_in: ^7.2.0`), passing the resulting ID token to `GoogleAuthProvider.credential(idToken: ...)` and `FirebaseAuth.instance.signInWithCredential(...)`.

### How the user document is created at first sign-in

Immediately after email/password sign-in, registration, or Google sign-in succeeds, both `LoginScreen` and `RegisterScreen` call `FirestoreService.createUserIfMissing(uid, displayName)` (`lib/services/firestore_service.dart`).

- `createUserIfMissing` reads `users/{uid}` first. If the document already exists, it returns without overwriting anything (preserving existing points, role, and block status).
- If `users/{uid}` does not exist, it creates the document with `displayName` (and alias `name`), `points: 0`, `pointsBalance: 0`, `createdAt`, `role: 'user'`, and `blocked: false`.
- Even if a brand-new user has not yet written `users/{uid}`, `callerRole()` and `isBlocked()` in `firestore.rules` treat a missing `users/{uid}` document as an unblocked `'user'`.

### How blocked users are signed out

Blocking is enforced both in the Flutter router (`lib/app/session.dart`) and in `firestore.rules`:

1. `SessionNotifier` listens to `FirebaseAuth.instance.authStateChanges()` and subscribes to `FirestoreService.watchUser(uid)` (`users/{uid}.snapshots()`).
2. While the user document is still loading (`ready == false`) or when `blocked == true`, `redirectFor()` redirects every route to `/splash`.
3. When `_onProfile` receives a `UserModel` with `blocked == true`, it sets `blockedNotice = true` and immediately calls `signOutEverywhere()` (`FirebaseAuth.instance.signOut()` followed by `GoogleSignIn.instance.signOut()`).
4. Once signed out with `blockedNotice == true`, `redirectFor()` redirects the router to `/login?blocked=1`, and `LoginScreen(blocked: true)` displays the error banner: `Your account has been blocked. Contact support.` (`kBlockedMessage`).
5. On the backend, the helper `isActive()` in `firestore.rules` requires `!isBlocked()`, so a blocked account cannot create reports, confirm sites, update their profile, or redeem coupons even before the client sign-out completes.

## 3. Firestore data model

The database uses five top-level collections: `users`, `reports`, `reportPhotos`, `coupons`, and `redemptions`. For additional background on access patterns and lifecycle notes, see [DATA_MODEL.md](DATA_MODEL.md).

### `users/{uid}`

Defined in `lib/models/user_model.dart` (`UserModel`) and updated by `lib/services/report_write_plan.dart` and `lib/services/firestore_service.dart`. Document ID is the Firebase Auth `uid`.

| Field | Type | Meaning |
|---|---|---|
| `displayName` | `string` | User's display name shown in greetings, profile, and the Admin Dashboard. |
| `name` | `string` | Compatibility alias written equal to `displayName` by `UserModel.toMap()`. |
| `points` | `int` | Current point balance. `UserModel.fromMap` reads `points` first and falls back to `pointsBalance`. |
| `pointsBalance` | `int` | Current point balance, always incremented or updated to the same value as `points`. |
| `createdAt` | `timestamp` | Account creation timestamp. |
| `role` | `string` | `'user'` (default), `'authority'`, or `'admin'`. Missing or unknown values normalize to `'user'`. |
| `blocked` | `bool` | When `true`, signs the user out of the app and blocks all Firestore writes. Defaults to `false`. |

### `reports/{reportId}`

Defined in `lib/models/report_model.dart` (`ReportModel`) and `lib/services/report_write_plan.dart`. Document ID is an auto-generated Firestore ID (`FirestoreService.newReportId()`). Never stores photo bytes.

| Field | Type | Meaning |
|---|---|---|
| `uid` | `string` | UID of the user who submitted the report. |
| `reporterId` | `string` | Compatibility alias written equal to `uid` by `ReportModel.toMap()`. |
| `photoId` | `string` | Document ID in `reportPhotos/{photoId}` (equal to `reportId` for `'valid'` reports, or `''` for `'rejected'` reports). |
| `lat` | `double` | Latitude of the captured GPS fix. |
| `lng` | `double` | Longitude of the captured GPS fix. |
| `location` | `GeoPoint` | Firestore `GeoPoint(lat, lng)` of the breeding site. |
| `geohash` | `string` | Precision-9 geohash (`encode(lat, lng, 9)` from `lib/features/ai_validation/geohash.dart`) used by prefix range queries in the 50 m duplicate check. |
| `type` | `string` | Breeding site category wire value: `'stagnant_water'`, `'tire'`, `'blocked_drain'`, `'container'`, `'other'`, or `'none'`. |
| `description` | `string` | Optional user notes entered on the report form. |
| `status` | `string` | `'valid'` (AI approved), `'rejected'` (AI rejected), or `'cleared'` (marked cleared by an authority or admin). Legacy documents without a status read as `'pending'`. |
| `confirmationCount` | `int` | Number of "still present" confirmations added by subsequent passing photos within 50 m and 14 days. Starts at `0`. |
| `createdAt` | `timestamp` | Server timestamp (`FieldValue.serverTimestamp()`) set when the report is created. |
| `lastConfirmedAt` | `timestamp` | Server timestamp of the most recent "still present" confirmation (equal to `createdAt` initially). |
| `lastConfirmationId` | `string` (optional) | Unique ID of the last "still present" confirmation (`buildStillPresentUpdate`), used to make transaction retries idempotent. |
| `aiCategory` | `string` (optional) | Category wire value returned by Gemini (`SiteCategory.wireValue`). |
| `aiConfidence` | `double` (optional) | Gemini confidence score between `0.0` and `1.0`. |
| `aiReason` | `string` (optional) | Short explanation returned by Gemini. |
| `clearedBy` | `string` (optional) | UID of the authority or admin who marked the report as `'cleared'`. Present only on cleared reports. |
| `clearedAt` | `timestamp` (optional) | Server timestamp when the report was marked as `'cleared'`. Present only on cleared reports. |

### `reportPhotos/{reportId}`

Written by `buildReportWritePlan()` (`lib/services/report_write_plan.dart`) for `'valid'` reports only, and read on demand by `FirestoreService.getReportPhoto(reportId)`. Document ID matches `reports/{reportId}`.

| Field | Type | Meaning |
|---|---|---|
| `photoBase64` | `string` | Base64-encoded JPEG image (resized to max 800 px and compressed under 300 KB). |
| `reportId` | `string` | ID of the parent report in `reports/{reportId}`. |
| `createdAt` | `timestamp` | Server timestamp (`FieldValue.serverTimestamp()`) when the photo document was created. |

### `coupons/{couponId}`

Defined in `lib/models/coupon_model.dart` (`CouponModel`) and managed by `FirestoreService.addCoupon`, `removeCoupon`, and `redeemCoupon`.

| Field | Type | Meaning |
|---|---|---|
| `title` | `string` | Title of the reward or sponsor offer. |
| `description` | `string` | Reward details or discount value. |
| `value` | `string` | Compatibility alias written equal to `description` by `CouponModel.toMap()`. |
| `cost` | `int` | Points required to redeem the coupon. |
| `pointsCost` | `int` | Compatibility alias written equal to `cost` by `CouponModel.toMap()`. |
| `code` | `string` | Primary promo code (or first code in `codes`). |
| `codes` | `array<string>` | Pool of one-time promo codes for multi-quantity coupons. |
| `stock` | `int` | Remaining redemptions available. |
| `available` | `bool` | `true` when the coupon can be redeemed (`available && stock > 0`), `false` once redeemed out. |
| `status` | `string` | `'available'` when `available && stock > 0`, otherwise `'redeemed'`. |

### `redemptions/{redemptionId}`

Defined in `lib/models/redemption_model.dart` (`RedemptionModel`) and created inside the `FirestoreService.redeemCoupon` transaction.

| Field | Type | Meaning |
|---|---|---|
| `uid` | `string` | UID of the user who redeemed the coupon. |
| `couponId` | `string` | ID of the redeemed coupon document in `coupons/{couponId}`. |
| `code` | `string` | Promo code issued to the user from the coupon. |
| `title` | `string` | Snapshot of the coupon's `title` at redemption time. |
| `description` | `string` | Snapshot of the coupon's `description` at redemption time. |
| `cost` | `int` | Points deducted from the user for this redemption. |
| `redeemedAt` | `timestamp` | Timestamp when the coupon was redeemed. |

## 4. Security rules

All rules live in `firestore.rules` using `rules_version = '2'`.

### Role and status helpers

At the top of `firestore.rules`, helper functions inspect the caller's own `users/$(request.auth.uid)` document:

- `isSignedIn()`: `request.auth != null`.
- `isOwner(uid)`: `isSignedIn() && request.auth.uid == uid`.
- `callerPath()` and `callerExists()`: points to `/databases/$(database)/documents/users/$(request.auth.uid)` and checks whether it exists.
- `callerRole()`: if `callerExists()` is true, reads `get(callerPath()).data.get('role', 'user')`; otherwise returns `'user'` so a newly signed-in user works before `users/{uid}` is created.
- `isBlocked()`: `callerExists() && get(callerPath()).data.get('blocked', false) == true`.
- `isActive()`: `isSignedIn() && !isBlocked()`.
- `isAdmin()`: `isActive() && callerRole() == 'admin'`.
- `isStaff()`: `isActive() && (callerRole() == 'authority' || callerRole() == 'admin')`.

### Collection rules and points protection

| Collection | Read | Create | Update | Delete |
|---|---|---|---|---|
| `users/{uid}` | `isOwner(uid) \|\| isAdmin()` (normal users and authorities cannot read or list other users) | `isOwner(uid)` only, and must have `role == 'user'`, `blocked == false`, `points == 0`, and `pointsBalance == 0` | `(isOwner(uid) && ownerMayUpdate()) \|\| (isAdmin() && adminMayUpdate())` | `false` (never allowed) |
| `reports/{reportId}` | `isSignedIn()` | `isActive()`, `uid == request.auth.uid`, and `status in ['valid', 'rejected']` | `(isStaff() && isClearing()) \|\| (isActive() && isStillPresent())` | `false` (never allowed) |
| `reportPhotos/{reportId}` | `allow get: if isSignedIn();` and `allow list: if false;` | `isActive()` and `getAfter(.../reports/$(reportId)).data.uid == request.auth.uid` | `false` (never allowed) | `isStaff()` |
| `coupons/{couponId}` | `isSignedIn()` | `isAdmin()` | `isAdmin() \|\| (isActive() && isRedeeming())` | `isAdmin()` |
| `redemptions/{redemptionId}` | `isSignedIn() && (resource == null \|\| resource.data.uid == request.auth.uid)` | `isActive() && request.resource.data.uid == request.auth.uid` | Not allowed | Not allowed |

Key enforcement details in `firestore.rules`:

- **How points are protected (`pointsChangeAllowed` and `ownerMayUpdate`)**: An owner can only update their own `users/{uid}` document if they are not currently blocked (`resource.data.get('blocked', false) == false`) and the update does not touch `role` or `blocked`. Their `points` and `pointsBalance` fields may only change in three ways:
  1. Both fields stay unchanged (`dPoints == 0 && dBalance == 0`), such as when updating `displayName`.
  2. Both fields increase by exactly `+10` (`dPoints == 10 && dBalance == 10`), matching `kPointsPerValidReport` in the valid-report write batch.
  3. Both fields are set to the same non-negative integer strictly lower than the previous balance (`after.get('points', 0) == after.get('pointsBalance', 0) && after.get('points', 0) >= 0 && after.get('points', 0) < current`), matching a coupon redemption.
- **Admin updates on users (`adminMayUpdate`)**: An active admin can update only `['role', 'blocked']` on a `users/{uid}` document, where `role` must be in `['user', 'admin', 'authority']` and `blocked` must be a boolean. Even an admin cannot edit a user's points or display name through the client SDK.
- **Report create and clear rules (`isClearing` and `isStillPresent`)**:
  - A new report can only be created with `status` equal to `'valid'` or `'rejected'` (never `'cleared'`, `'pending'`, or `'approved'`).
  - `isClearing()` requires the existing report to have `status == 'valid'`, the new status to be `'cleared'`, the modified keys to be only `['status', 'clearedBy', 'clearedAt']`, `clearedBy == request.auth.uid`, and `clearedAt == request.time`. Only `isStaff()` (an active `'authority'` or `'admin'`) may perform this update.
  - `isStillPresent()` requires the existing report to have `status == 'valid'`, the modified keys to be only `['confirmationCount', 'lastConfirmedAt', 'lastConfirmationId']`, `confirmationCount` to increase by exactly `+1`, and `lastConfirmedAt == request.time`. Any active user (`isActive()`) may perform this update.
- **`reportPhotos` get-only and batch creation**: `reportPhotos/{reportId}` allows `get` for any signed-in user so `ReportPhotoView` can fetch a single report's photo by ID, but explicitly sets `allow list: if false` so clients cannot query or dump the collection. On creation, `getAfter(/databases/$(database)/documents/reports/$(reportId)).data.uid == request.auth.uid` checks the parent report state after the batch commits, allowing `FirestoreService.submitReport` to create `reports/{id}` and `reportPhotos/{id}` in the same atomic batch while preventing orphan photos or photos attached to another user's report. When an authority or admin calls `FirestoreService.markReportCleared(reportId)`, the batch updates `reports/{id}` to `'cleared'` and deletes `reportPhotos/{id}` (permitted by `allow delete: if isStaff()`).
- **Coupon redemption rule (`isRedeeming`) and redemption record**: Any active user can update a coupon document only when `before.get('available', true) == true`, `after.available == false`, and the diff affects only `['available', 'status']`. In the same transaction, the user creates a document in `redemptions/{redemptionId}` with `request.resource.data.uid == request.auth.uid`, and can only read their own redemption documents (`resource == null || resource.data.uid == request.auth.uid`).

## 5. Roles

A user's role is stored in `users/{uid}.role` as `'user'`, `'authority'`, or `'admin'`. Self-registration always sets `role: 'user'`, and `firestore.rules` blocks users from changing their own `role`.

### Promoting an account to `admin` or `authority` in the Firebase console

The Firebase console bypasses client security rules, so the first admin or authority is assigned directly in the console:

1. Open the [Firebase console](https://console.firebase.google.com/) and select project **`clearspot-640fb`**.
2. Go to **Build > Authentication > Users** and copy the **User UID** for the target account.
3. Go to **Build > Firestore Database > Data**, open the **`users`** collection, and select the document whose ID matches that UID. (Sign in to the app once first if the document has not been created yet.)
4. Click **Add field** (or edit the existing `role` field), set the field name to `role`, type to `string`, and value to `admin` or `authority`, then click **Update**.

Once an account has `role = "admin"`, that admin can also change other users' roles from the in-app **Admin Dashboard** (`/admin` > **Users & Roles** tab > three-dot menu > **Change Role**), which calls `FirestoreService.setUserRole(uid, role)`.

### Removing an `admin` or `authority` role

- **In the Firebase console**: Open **Firestore Database > Data > `users` > `{uid}`** and change the `role` field back to `user` (or delete the `role` field, since missing values default to `'user'`).
- **In the app**: Another admin can open `/admin` > **Users & Roles** and set the user's role back to **USER** (the UI prevents an admin from removing the `admin` role from their own currently signed-in account).

Because `SessionNotifier` listens to `users/{uid}` in real time, role promotions, demotions, and account blocks take effect immediately without requiring an app restart.

## 6. App Check and AI Logic

`lib/main.dart` activates Firebase App Check at startup before running the app:

- **Debug builds (`kDebugMode == true`)**: activates `AndroidDebugProvider()` on Android and `AppleDebugProvider()` on iOS/macOS.
- **Release and profile builds (`kDebugMode == false`)**: activates `AndroidPlayIntegrityProvider()` on Android and `AppleAppAttestWithDeviceCheckFallbackProvider()` on iOS/macOS.

### Registering a debug token in the Firebase console

1. Run a debug build of the app on your device or emulator (`flutter run -d <deviceId>`).
2. On first run, the App Check debug provider logs a line formatted as `Firebase App Check debug token: <uuid>`. Retrieve it in PowerShell:
   ```powershell
   adb logcat -d | Select-String "App Check debug token"
   ```
   On macOS or Linux, run `adb logcat -d | grep "App Check debug token"`. On iOS, find `App Check debug token` in the Xcode console.
3. In the Firebase console for `clearspot-640fb`, navigate to **Build > App Check > Apps**.
4. Open the menu on **`clean_spot (android)`** (or the iOS app), click **Manage debug tokens**, click **Add debug token**, give it a name, paste only the UUID string, and save.

### Enforcement for Firebase AI Logic

Firebase AI Logic (`FirebaseAI.googleAI()`, used in `lib/features/ai_validation/ai_validation_service.dart`) enforces App Check on requests to `gemini-3.5-flash-lite`. No Gemini API key is stored in the repository or compiled into the app. If a debug install's token is not registered (or Play Integrity is not configured for a release signing key), Firebase AI Logic rejects the request with `403 App attestation failed`. `AiValidationService.validatePhoto()` catches all errors and returns `ValidationResult.error(...)`, which causes `ReportCheckController` to show **Try again** so an unverified photo is never approved.

## 7. Indexes

There is no `firestore.indexes.json` file in the repository (`firebase.json` configures only `"rules": "firestore.rules"`).

All Firestore queries in the codebase rely solely on Firestore's automatic single-field indexes:

- `reports.where('status', isEqualTo: 'valid')` in `FirestoreService.watchValidReports()`
- `reports.where('uid', isEqualTo: uid)` in `FirestoreService.watchUserReports()` (sorted by `createdAt` in Dart so no composite `(uid, createdAt)` index is required)
- `reports.orderBy('geohash').startAt([prefix]).endAt(['$prefix\uf8ff'])` in `findStillPresentReport()` (`lib/features/ai_validation/duplicate_check.dart`, which filters `status == 'valid'` and the 14-day activity window in Dart so only the single-field index on `geohash` is used)
- `redemptions.where('uid', isEqualTo: uid)` in `FirestoreService.watchUserRedemptions()` (sorted by `redeemedAt` in Dart)

## 8. Deployment

You need the Firebase CLI (`npm install -g firebase-tools`) and access to the `clearspot-640fb` Firebase project.

### 1. Sign in and select the project

```powershell
firebase login
firebase use clearspot-640fb
```

### 2. Back up the live rules before deploying

Before publishing changes to `firestore.rules`, back up the currently active ruleset from the project:

1. Open **Firebase console > Firestore Database > Rules**.
2. Copy the currently published rules text into a local backup file (for example `firestore.rules.backup`), or note the top timestamped entry in the left-hand version history list so you can restore it with one click if needed.

### 3. Deploy Firestore security rules

From the repository root:

```powershell
firebase deploy --only firestore:rules
```

### 4. Deploying indexes (if added later)

No custom composite indexes exist right now. If you add a `firestore.indexes.json` file in the future, reference `"indexes": "firestore.indexes.json"` under the `"firestore"` key in `firebase.json` and deploy with:

```powershell
firebase deploy --only firestore:indexes
```

## 9. Testing the rules locally

The `firestore-rules-test/` folder contains an offline test suite (`firestore-rules-test/rules.test.mjs`) that tests `../firestore.rules` against the local Firestore emulator using `@firebase/rules-unit-testing` (`^6.0.0`) and the Node test runner.

### Running the emulator tests

Requires Node.js, Java 11 or newer, and the Firebase CLI on PATH. In PowerShell:

```powershell
cd firestore-rules-test
npm install
npm test
```

`npm test` runs the script configured in `firestore-rules-test/package.json`:

```text
firebase emulators:exec --config ../firebase.json --only firestore --project clearspot-rules-test "node --test rules.test.mjs"
```

This boots the local Firestore emulator on port `8080` (with the Emulator UI disabled, as configured in `firebase.json`), executes `rules.test.mjs`, and shuts the emulator down automatically.

### What `firestore-rules-test/rules.test.mjs` covers

The test suite mirrors the exact batch and transaction writes performed by `lib/services/firestore_service.dart` across seven `describe` blocks:

- **`signed out`**: verifies unauthenticated clients cannot read or write `users`, `reports`, `reportPhotos`, or `coupons`.
- **`users`**: tests owner read access, prohibition of reading or listing other users by normal users and authorities, admin read and list access, safe self-creation with `0` points and `role: 'user'`, rejection of self-assigned roles or initial points, protection against arbitrary point edits, allowance of the exact `+10` increment on both `points` and `pointsBalance` and equal non-negative point deductions on coupon redemption, admin updates limited strictly to `role` and `blocked`, loss of permissions when a user or admin is blocked, and prohibition of user document deletion.
- **`reports`**: tests signed-in read access, creation of `'valid'` and `'rejected'` reports for the caller's own UID, rejection of reports created as `'cleared'`, `'pending'`, or `'approved'`, clearing of `'valid'` reports by authorities and admins with `clearedBy == request.auth.uid` and server timestamp `clearedAt`, rejection of clearing by normal or blocked users, "still present" updates (`confirmationCount` incremented by `+1` with server timestamp `lastConfirmedAt` and `lastConfirmationId`), and prohibition of report deletion.
- **`saving a report (the real batch from FirestoreService.submitReport)`**: verifies the atomic 3-write batch for a `'valid'` report (`reports/{id}` + `reportPhotos/{id}` + `users/{uid}` `+10` points), the single-document batch for a `'rejected'` report, rejection of photos attached to another user's report or without a report, and rejection of batches from blocked users.
- **`reportPhotos`**: verifies signed-in `get` by ID, denial of collection `list` queries, denial of photo overwrites, and deletion restricted to authority and admin users (including the atomic status-clear + photo-delete batch from `FirestoreService.markReportCleared`).
- **`coupons`**: verifies signed-in read access, admin-only create, edit, and delete permissions, and active user redemption updates (`available: false`, `status: 'redeemed'`).
- **`redemptions`**: tests the multi-document redemption transaction from `FirestoreService.redeemCoupon` and verifies that users can only create and query their own redemption documents.

## 10. Limits and future work

- **Firebase Spark plan limits**:
  - **No Cloud Storage**: photos cannot be uploaded to a storage bucket on the free setup used by this project, so each valid report photo is compressed under 300 KB and stored as a Base64 string in `reportPhotos/{reportId}` (well below Firestore's 1 MiB document size limit).
  - **No Cloud Functions**: there is no trusted server runtime to execute Gemini checks, geohash queries, point awards, or coupon code pops behind an API endpoint.
- **Client-side trust limitation**:
  - Because validation and batch construction happen in the Flutter app, `firestore.rules` can enforce structural invariants (the caller owns the report, `status` is `'valid'` or `'rejected'`, points only change by `+10` or decrease on redemption, and `reportPhotos` cannot be listed), but `firestore.rules` cannot verify that a client actually ran the camera, got a real GPS fix, or received a passing Gemini verdict before sending a `+10` points batch.
  - Because `coupons` must be readable by signed-in clients for the reward shop and client-side redemption transaction, any signed-in user who inspects raw Firestore documents can read the `code` and `codes` fields on `coupons`.
  - In `firestore.rules`, `isRedeeming()` restricts non-admin coupon updates to `['available', 'status']` (setting `available: false`), while multi-code pool coupons in `FirestoreService.redeemCoupon` also update `stock` and `codes`.
- **What upgrading to the Blaze plan would allow**:
  - **Cloud Functions for Firebase**: move `AiValidationService.validatePhoto()`, `findStillPresentReport()`, report creation, and the `+10` points increment into a callable Cloud Function or Firestore trigger so clients can only submit a pending report request and can never write `status: 'valid'` or increment their own points directly. Move coupon redemption into a callable function and store secret promo code pools in a private admin-only collection so users only see the single code they redeemed.
  - **Cloud Storage for Firebase**: store report JPEG files in a Cloud Storage bucket governed by Storage security rules and keep only a storage path or download URL on the report document.
