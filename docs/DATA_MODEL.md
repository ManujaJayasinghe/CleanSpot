# CleanSpot Data Model

This document outlines the Cloud Firestore database collections, document structures, and field definitions for the CleanSpot platform.

---

## Collections Overview

| Collection | Description |
|---|---|
| `users` | User profile information and accumulated points balance. |
| `reports` | Mosquito-breeding site reports (metadata, location, category, AI result, status). Never contains the photo, so reads stay lightweight. |
| `reportPhotos` | The only place a report photo is stored (compressed Base64), one document per `'valid'` report. Rejected reports have no photo. |
| `coupons` | Rewards available for redemption using points. |
| `redemptions` | Records of coupons redeemed by users. |

---

## 1. `users` Collection

Stores user profile and gamification balance data.

- **Document ID**: User UID (matches Firebase Authentication UID)

### Fields

| Field | Type | Description |
|---|---|---|
| `displayName` | `string` | Display name of the user. |
| `pointsBalance` | `int` | Current balance of points accumulated by the user. Also written as `points` (the app reads `points` first, so both are always updated together). |
| `points` | `int` | Same value as `pointsBalance`. |
| `createdAt` | `timestamp` | Timestamp when the user account was registered. |
| `role` | `string` (optional) | `'user'` (default), `'admin'` or `'authority'`. A missing or unknown value is read as `'user'`. Decides where the user lands after login (`/home`, `/admin`, `/authority`). Only an admin can change it, in the Firebase console or with `FirestoreService.setUserRole`. |
| `blocked` | `bool` (optional) | `true` blocks the account: the app signs the user out ("Your account has been blocked. Contact support.") and the security rules refuse everything they try to save. A missing value means not blocked. Only an admin can change it (`FirestoreService.setUserBlocked`). |

**Roles.** `'user'` is a normal account. `'authority'` can mark valid reports as cleared. `'admin'` can do that too, and can also manage users (role, blocked) and coupons. The role is read from this document after login; `firestore.rules` is what actually enforces it, so it cannot be changed from the app by the user themselves.

**How points change:** saving a report with status `'valid'` adds 10 points (`FieldValue.increment(10)` on both `pointsBalance` and `points`, defined once as `kPointsPerValidReport` in `lib/services/report_write_plan.dart`) in the **same write batch** as the report and its photo. Redeeming a coupon subtracts the coupon cost. Rejected reports add nothing.

---

## 2. `reports` Collection

Stores reports of potential mosquito-breeding sites submitted by community members.

> **Performance Rule:** List queries, radius/geohash searches, map pins, and duplicate-checking queries must only query this collection. Never fetch `reportPhotos` in list views.

> **No photo here.** A `reports` document never holds the image (no `imageUrl` / `photoUrl` Base64). The photo is only in `reportPhotos/{photoId}` and is loaded on demand with `FirestoreService.getReportPhoto`. Old documents that still contain `imageUrl` / `photoUrl` are still read, but that data is never written back.

> **What is saved.** After the AI check, every result is saved in ONE write batch:
> - **`'valid'`** (approved): `reports/{id}` + `reportPhotos/{id}` + `users/{uid}` points `+10`.
> - **`'rejected'`**: only `reports/{id}` (with the AI fields and geohash). No `reportPhotos` document and no points.
>
> A failed save is reported to the user (nothing is saved and no points are added), and Retry reuses the same `reportId`, so a retry cannot create a second report or award points twice.
>
> **Clearing.** `FirestoreService.markReportCleared(reportId)` (authority or admin only) sets `status: 'cleared'`, `clearedBy` and `clearedAt` and **deletes `reportPhotos/{id}`** in one batch. The report document stays.

- **Document ID**: Auto-generated unique ID (`reportId`)

### Fields

| Field | Type | Description |
|---|---|---|
| `uid` | `string` | UID of the user who submitted the report (alias `reporterId`). |
| `photoId` | `string` | Document ID of `reportPhotos/{photoId}` (same as `reportId`) for `'valid'` reports; empty (`''`) for `'rejected'` reports, which have no photo. |
| `type` | `string` | Site type as a wire value: `'stagnant_water'`, `'tire'`, `'blocked_drain'`, `'container'`, `'other'` or `'none'`. Older documents may hold the enum name (`blockedDrain`) or a label (`Tyres`); they are converted when read. |
| `description` | `string` | Optional details or notes from the submitter. |
| `location` | `GeoPoint` | Geographic coordinates (`latitude`, `longitude`) of the breeding site. |
| `lat` | `double` | Latitude coordinate. |
| `lng` | `double` | Longitude coordinate. |
| `geohash` | `string` | Geohash string computed from location for proximity queries. |
| `status` | `string` | `'valid'` (AI approved, automatic), `'rejected'` (AI did not approve) or `'cleared'` (an authority or admin marked the site as dealt with). `'pending'` is not used by the AI flow. **Only `'valid'` reports count for the map and the still-present check**, so a cleared report leaves the map and a new photo at that spot creates a new report. Only a `'valid'` report can become `'cleared'`. |
| `clearedBy` | `string` (optional) | UID of the authority or admin who cleared the report. Only on `'cleared'` reports. |
| `clearedAt` | `timestamp` (optional) | Server time when the report was cleared. Only on `'cleared'` reports. |
| `confirmationCount` | `int` | Number of "still present" confirmations: a passing photo from any user within 50 m and 14 days of this report adds one instead of creating a new report. |
| `createdAt` | `timestamp` | Timestamp when the report was submitted. |
| `lastConfirmedAt` | `timestamp` | Server time of the last "still present" confirmation (the creation time until then). |
| `lastConfirmationId` | `string` (optional) | Id of the last "still present" confirmation, so a retried confirmation is not counted twice. Absent until the first confirmation. |
| `aiCategory` | `string` (optional) | Site type found by the AI photo check, as a wire value: `'stagnant_water'`, `'tire'`, `'blocked_drain'`, `'container'`, `'other'` or `'none'`. Absent on older reports. |
| `aiConfidence` | `number` (optional) | AI confidence that the photo shows a breeding site, from 0 to 1. Absent on older reports. |
| `aiReason` | `string` (optional) | Short user-friendly explanation from the AI check. Absent on older reports. |

---

## 3. `reportPhotos` Collection

The only place a report photo is stored, kept separate from `reports` to ensure minimal egress and instant map/list querying without downloading image bytes. Only `'valid'` reports have a document here, and it is deleted when the report is cleared.

- **Document ID**: Same ID as the associated report (`reportId`)

### Fields

| Field | Type | Description |
|---|---|---|
| `photoBase64` | `string` | JPEG image compressed to max 800px, 70% quality, and capped under 300 KB, encoded in Base64 format. |
| `reportId` | `string` | References the parent report in `reports/{reportId}`. |
| `createdAt` | `timestamp` | Timestamp when the photo was uploaded. |

> **Client Access Pattern:** A document from this collection is loaded only for a single report that is on screen, with `FirestoreService.getReportPhoto(reportId)` (cached in memory after the first load; a placeholder is shown while loading or if the photo is missing). Lists, the map and the duplicate check never read this collection.

---

## 4. `coupons` Collection

Stores reward vouchers and coupons available for redemption.

- **Document ID**: Auto-generated unique ID

### Fields

| Field | Type | Description |
|---|---|---|
| `title` | `string` | Title of the reward / merchant offer. |
| `description` | `string` | Reward value or details (e.g., "$5 Off", "15% Discount"). |
| `cost` | `int` | Point cost required to redeem this coupon (alias `pointsCost`). |
| `code` | `string` | Unique coupon redemption code. |
| `available` | `bool` | Availability status: `true` if available, `false` once redeemed. |

---

## 5. `redemptions` Collection

Stores atomic records of redeemed coupons.

- **Document ID**: Auto-generated unique ID

### Fields

| Field | Type | Description |
|---|---|---|
| `uid` | `string` | UID of the user who redeemed the coupon (references `users`). |
| `couponId` | `string` | ID of the coupon that was redeemed (references `coupons`). |
| `code` | `string` | One-time code issued to the user. |
| `title` | `string` | Snapshot of coupon title. |
| `description` | `string` | Snapshot of coupon description. |
| `cost` | `int` | Points deducted for the redemption. |
| `redeemedAt` | `timestamp` | Timestamp when the redemption occurred. |

---

## Security rules (`firestore.rules`)

The rules look up the caller's `users/{uid}` document for `role` and `blocked`. A blocked user counts as signed in but can do nothing but read. Summary:

| Collection | Who can do what |
|---|---|
| `users` | An owner reads and edits their own document, **except** `role`, `blocked` and points. Points can only change by the +10 save-a-valid-report increment (both fields) or by lowering both to the same smaller value when redeeming a coupon. A new user can only create their own document as a normal, unblocked user with 0 points. An admin can read every user and change only `role` and `blocked`. Nobody can delete a user. |
| `reports` | Any signed-in user reads. An active (not blocked) user creates their own report with status `'valid'` or `'rejected'`. Only an authority or admin can update a report, and only to change a `'valid'` report to `'cleared'` (with `clearedBy` and `clearedAt`). Any active user can add a "still present" confirmation (`confirmationCount` +1, `lastConfirmedAt`, `lastConfirmationId`) to a valid report. Nobody can delete. |
| `reportPhotos` | A signed-in user reads one photo by id (never lists). Only the owner of the report creates it. Only an authority or admin deletes it. No updates. |
| `coupons` | A signed-in user reads. Only an admin creates, deletes or edits freely. Any active user can redeem (set `available` to false and `status` to `'redeemed'`, nothing else). |
| `redemptions` | A user reads and creates their own only. |

**Making an account admin:** Firebase console → Firestore Database → `users` → open the document whose ID is the account's UID (Authentication → Users shows it) → Add field `role` (string) = `admin`. The console is not limited by the rules. The app picks the change up live.

The rules are tested in `firestore-rules-test/` (see its README).
