# Firestore rules tests

Tests for `../firestore.rules` (roles, blocked users, clearing reports, points,
coupons). They run against the **local Firestore emulator**, so they never touch
the real database.

## Run

You need Node, Java 11+ and the Firebase CLI (`firebase --version`).

```bash
cd firestore-rules-test
npm install      # once
npm test         # starts the emulator, runs the tests, stops the emulator
```

The first run downloads the Firestore emulator (about 60 MB).

## What is covered

Signed-out access; users (create, role/blocked/points protection, admin changes,
blocked users); reports (create, clear by authority/admin only, still-present
update, no deletes); the real report-save batch, the clear batch and the coupon
redemption transaction; reportPhotos (owner create, staff delete, no list);
coupons (admin create/delete, user redeem); redemptions.

The writes copy what the app really does (`lib/services/firestore_service.dart`),
so a rule that would break saving a report or redeeming a coupon fails here.

## If you change the rules

Edit `../firestore.rules`, run `npm test`, then deploy with
`firebase deploy --only firestore:rules` (or paste the file into the Firebase
console > Firestore Database > Rules > Publish).
