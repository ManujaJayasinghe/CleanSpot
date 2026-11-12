# CleanSpot Data Model

This document outlines the Cloud Firestore database collections, document structures, and field definitions for the CleanSpot platform.

---

## Collections Overview

| Collection | Description |
|---|---|
| `users` | User profile information and accumulated points balance. |
| `reports` | Mosquito-breeding site reports (metadata, location, category, confirmation status). Keeps reads lightweight. |
| `reportPhotos` | High-resolution compressed image Base64 payloads stored in isolation to prevent reading photo bytes in bulk queries. |
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
| `pointsBalance` | `int` | Current balance of points accumulated by the user (also aliased as `points`). |
| `createdAt` | `timestamp` | Timestamp when the user account was registered. |

---

## 2. `reports` Collection

Stores reports of potential mosquito-breeding sites submitted by community members.

> **Performance Rule:** List queries, radius/geohash searches, map pins, and duplicate-checking queries must only query this collection. Never fetch `reportPhotos` in list views.

- **Document ID**: Auto-generated unique ID (`reportId`)

### Fields

| Field | Type | Description |
|---|---|---|
| `uid` | `string` | UID of the user who submitted the report (alias `reporterId`). |
| `photoId` | `string` | Document ID pointing to `reportPhotos/{photoId}` (defaults to same ID as `reportId`). |
| `type` | `string` | Hazard category (e.g. `'Stagnant Water'`, `'Tyres'`, `'Blocked Drain'`, `'Containers'`, `'Other'`). |
| `description` | `string` | Optional details or notes from the submitter. |
| `location` | `GeoPoint` | Geographic coordinates (`latitude`, `longitude`) of the breeding site. |
| `lat` | `double` | Latitude coordinate. |
| `lng` | `double` | Longitude coordinate. |
| `geohash` | `string` | Geohash string computed from location for proximity queries. |
| `status` | `string` | Status of the report: `'pending'`, `'valid'`, or `'rejected'`. |
| `aiReason` | `string?` | Optional explanation or reason from AI validation. |
| `confirmationCount` | `int` | Number of community/admin confirmations for duplicate reporting. |
| `createdAt` | `timestamp` | Timestamp when the report was submitted. |
| `lastConfirmedAt` | `timestamp` | Timestamp when the report was last confirmed/verified. |
| `aiCategory` | `string` (optional) | Site type found by the AI photo check: `'stagnant_water'`, `'tire'`, `'blocked_drain'`, `'container'` or `'other'`. Absent on older reports. |
| `aiConfidence` | `number` (optional) | AI confidence that the photo shows a breeding site, from 0 to 1. Absent on older reports. |
| `aiReason` | `string` (optional) | Short user-friendly explanation from the AI check. Absent on older reports. |

---

## 3. `reportPhotos` Collection

Stores photo payloads separately from `reports` to ensure minimal egress and instant map/list querying without downloading image bytes.

- **Document ID**: Same ID as the associated report (`reportId`)

### Fields

| Field | Type | Description |
|---|---|---|
| `photoBase64` | `string` | JPEG image compressed to max 800px, 70% quality, and capped under 300 KB, encoded in Base64 format. |
| `reportId` | `string` | References the parent report in `reports/{reportId}`. |
| `createdAt` | `timestamp` | Timestamp when the photo was uploaded. |

> **Client Access Pattern:** A document from this collection is loaded only when the user opens the single detailed view for that specific report.

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
