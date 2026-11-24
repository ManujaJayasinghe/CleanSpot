// Tests for ../firestore.rules, run against the local Firestore emulator:
//
//   cd firestore-rules-test
//   npm install              (once)
//   npm test                 (starts the emulator, runs these tests, stops it)
//
// The writes below copy what the app really does (lib/services/*.dart), so a
// rule that breaks saving a report, redeeming a coupon or marking a site as
// still present fails here before it reaches the app.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'clearspot-rules-test',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await env.cleanup();
});

const report = (uid, status = 'valid', extra = {}) => ({
  uid,
  status,
  type: 'blocked_drain',
  lat: 7.29,
  lng: 80.63,
  geohash: 'tc336z5wv',
  confirmationCount: 0,
  photoId: '',
  createdAt: new Date('2026-11-20'),
  lastConfirmedAt: new Date('2026-11-20'),
  ...extra,
});

// Seed with the rules switched off.
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), { displayName: 'Alice', points: 50, pointsBalance: 50 });
    await setDoc(doc(db, 'users/bob'), { displayName: 'Bob', points: 0, pointsBalance: 0, role: 'user', blocked: false });
    await setDoc(doc(db, 'users/boss'), { displayName: 'Boss', points: 0, pointsBalance: 0, role: 'admin' });
    await setDoc(doc(db, 'users/officer'), { displayName: 'Officer', points: 0, pointsBalance: 0, role: 'authority' });
    await setDoc(doc(db, 'users/banned'), { displayName: 'Banned', points: 20, pointsBalance: 20, blocked: true });
    await setDoc(doc(db, 'users/banned-officer'), { displayName: 'BO', role: 'authority', blocked: true });
    await setDoc(doc(db, 'reports/r1'), report('alice', 'valid', { photoId: 'r1' }));
    await setDoc(doc(db, 'reports/r2'), report('alice', 'rejected'));
    await setDoc(doc(db, 'reportPhotos/r1'), { photoBase64: 'QUJD', reportId: 'r1' });
    await setDoc(doc(db, 'coupons/c1'), { title: 'Eco', description: 'x', cost: 20, code: 'ECO20', available: true });
    await setDoc(doc(db, 'redemptions/red1'), { uid: 'alice', couponId: 'c0', cost: 5 });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

// ---------------------------------------------------------------------------
describe('signed out', () => {
  test('cannot read anything', async () => {
    for (const path of ['users/alice', 'reports/r1', 'reportPhotos/r1', 'coupons/c1']) {
      await assertFails(getDoc(doc(anon(), path)));
    }
  });
  test('cannot write anything', async () => {
    await assertFails(setDoc(doc(anon(), 'reports/x'), report('alice')));
  });
});

// ---------------------------------------------------------------------------
describe('users', () => {
  test('an owner reads their own document; a stranger cannot', async () => {
    await assertSucceeds(getDoc(doc(as('alice'), 'users/alice')));
    await assertFails(getDoc(doc(as('bob'), 'users/alice')));
  });

  test('an authority cannot read other users', async () => {
    await assertFails(getDoc(doc(as('officer'), 'users/alice')));
  });

  test('an admin reads every user and can list them', async () => {
    await assertSucceeds(getDoc(doc(as('boss'), 'users/alice')));
    await assertSucceeds(getDocs(collection(as('boss'), 'users')));
  });

  test('a normal user cannot list users', async () => {
    await assertFails(getDocs(collection(as('alice'), 'users')));
  });

  test('anyone can create their own document as a normal user with 0 points', async () => {
    await assertSucceeds(
      setDoc(doc(as('newbie'), 'users/newbie'), {
        displayName: 'N', name: 'N', points: 0, pointsBalance: 0,
        createdAt: new Date(), role: 'user', blocked: false,
      }),
    );
  });

  test('a document cannot be created as admin, blocked, or with points', async () => {
    const base = { displayName: 'N', points: 0, pointsBalance: 0 };
    await assertFails(setDoc(doc(as('n1'), 'users/n1'), { ...base, role: 'admin' }));
    await assertFails(setDoc(doc(as('n2'), 'users/n2'), { ...base, role: 'authority' }));
    await assertFails(setDoc(doc(as('n3'), 'users/n3'), { ...base, blocked: true }));
    await assertFails(setDoc(doc(as('n4'), 'users/n4'), { ...base, points: 100, pointsBalance: 100 }));
    await assertFails(setDoc(doc(as('n5'), 'users/n6'), base)); // someone else's id
  });

  test('an owner cannot change their own role or blocked flag', async () => {
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { role: 'admin' }));
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { role: 'authority' }));
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { blocked: true }));
    await assertFails(updateDoc(doc(as('bob'), 'users/bob'), { role: 'admin' }));
    // even through a merge set
    await assertFails(setDoc(doc(as('alice'), 'users/alice'), { role: 'admin' }, { merge: true }));
  });

  test('an owner can edit harmless fields', async () => {
    await assertSucceeds(updateDoc(doc(as('alice'), 'users/alice'), { displayName: 'Alice B' }));
  });

  test('points cannot be raised by hand', async () => {
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { points: 9999, pointsBalance: 9999 }));
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { points: 51, pointsBalance: 51 }));
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { pointsBalance: 60 }));
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { points: increment(25), pointsBalance: increment(25) }));
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { points: increment(10), pointsBalance: increment(20) }));
  });

  test('the +10 increment on both fields works (saving a valid report)', async () => {
    await assertSucceeds(
      setDoc(doc(as('alice'), 'users/alice'), { points: increment(10), pointsBalance: increment(10) }, { merge: true }),
    );
  });

  test('redeeming lowers both fields to the same value', async () => {
    await assertSucceeds(updateDoc(doc(as('alice'), 'users/alice'), { points: 30, pointsBalance: 30 }));
  });

  test('redeeming cannot go negative or leave the fields different', async () => {
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { points: -5, pointsBalance: -5 }));
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { points: 30, pointsBalance: 40 }));
  });

  test('an admin can set role and blocked on another user', async () => {
    await assertSucceeds(updateDoc(doc(as('boss'), 'users/alice'), { role: 'authority' }));
    await assertSucceeds(updateDoc(doc(as('boss'), 'users/alice'), { role: 'user', blocked: true }));
    await assertSucceeds(updateDoc(doc(as('boss'), 'users/banned'), { blocked: false }));
  });

  test('an admin cannot set an invalid role or edit anything else', async () => {
    await assertFails(updateDoc(doc(as('boss'), 'users/alice'), { role: 'superuser' }));
    await assertFails(updateDoc(doc(as('boss'), 'users/alice'), { points: 9999, pointsBalance: 9999 }));
    await assertFails(updateDoc(doc(as('boss'), 'users/alice'), { displayName: 'Hacked' }));
  });

  test('an authority cannot change roles or block anyone', async () => {
    await assertFails(updateDoc(doc(as('officer'), 'users/alice'), { blocked: true }));
    await assertFails(updateDoc(doc(as('officer'), 'users/alice'), { role: 'admin' }));
  });

  test('a blocked user cannot change their own document', async () => {
    await assertFails(updateDoc(doc(as('banned'), 'users/banned'), { blocked: false }));
    await assertFails(updateDoc(doc(as('banned'), 'users/banned'), { displayName: 'x' }));
    await assertFails(
      setDoc(doc(as('banned'), 'users/banned'), { points: increment(10), pointsBalance: increment(10) }, { merge: true }),
    );
  });

  test('nobody can delete a user document', async () => {
    await assertFails(deleteDoc(doc(as('alice'), 'users/alice')));
    await assertFails(deleteDoc(doc(as('boss'), 'users/alice')));
  });

  test('a blocked admin loses admin powers', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/boss'), { role: 'admin', blocked: true });
    });
    await assertFails(getDoc(doc(as('boss'), 'users/alice')));
    await assertFails(updateDoc(doc(as('boss'), 'users/alice'), { role: 'authority' }));
  });
});

// ---------------------------------------------------------------------------
describe('reports', () => {
  test('any signed-in user can read reports', async () => {
    await assertSucceeds(getDoc(doc(as('bob'), 'reports/r1')));
    await assertSucceeds(getDocs(query(collection(as('bob'), 'reports'), where('status', '==', 'valid'))));
  });

  test('a user can create their own valid or rejected report', async () => {
    await assertSucceeds(setDoc(doc(as('bob'), 'reports/n1'), report('bob', 'valid')));
    await assertSucceeds(setDoc(doc(as('bob'), 'reports/n2'), report('bob', 'rejected')));
  });

  test('a user cannot create a report for someone else', async () => {
    await assertFails(setDoc(doc(as('bob'), 'reports/n3'), report('alice', 'valid')));
  });

  test('a report cannot be created already cleared, pending or approved', async () => {
    for (const status of ['cleared', 'pending', 'approved']) {
      await assertFails(setDoc(doc(as('bob'), `reports/s-${status}`), report('bob', status)));
    }
  });

  test('a blocked user cannot create a report', async () => {
    await assertFails(setDoc(doc(as('banned'), 'reports/n4'), report('banned', 'valid')));
  });

  test('a brand-new user with no users document can still create a report', async () => {
    await assertSucceeds(setDoc(doc(as('fresh'), 'reports/n5'), report('fresh', 'valid')));
  });

  test('an authority can clear a valid report', async () => {
    await assertSucceeds(
      updateDoc(doc(as('officer'), 'reports/r1'), {
        status: 'cleared', clearedBy: 'officer', clearedAt: serverTimestamp(),
      }),
    );
  });

  test('an admin can clear a valid report', async () => {
    await assertSucceeds(
      updateDoc(doc(as('boss'), 'reports/r1'), {
        status: 'cleared', clearedBy: 'boss', clearedAt: serverTimestamp(),
      }),
    );
  });

  test('a normal user cannot clear a report, even their own', async () => {
    const clear = (uid) => ({ status: 'cleared', clearedBy: uid, clearedAt: serverTimestamp() });
    await assertFails(updateDoc(doc(as('alice'), 'reports/r1'), clear('alice')));
    await assertFails(updateDoc(doc(as('bob'), 'reports/r1'), clear('bob')));
  });

  test('clearing must name the person clearing and use server time', async () => {
    await assertFails(
      updateDoc(doc(as('officer'), 'reports/r1'), { status: 'cleared', clearedBy: 'boss', clearedAt: serverTimestamp() }),
    );
    await assertFails(
      updateDoc(doc(as('officer'), 'reports/r1'), { status: 'cleared', clearedBy: 'officer', clearedAt: new Date('2020-01-01') }),
    );
    await assertFails(updateDoc(doc(as('officer'), 'reports/r1'), { status: 'cleared' }));
  });

  test('only a valid report can be cleared', async () => {
    await assertFails(
      updateDoc(doc(as('officer'), 'reports/r2'), { status: 'cleared', clearedBy: 'officer', clearedAt: serverTimestamp() }),
    );
  });

  test('staff cannot change anything else about a report', async () => {
    await assertFails(updateDoc(doc(as('officer'), 'reports/r1'), { status: 'rejected' }));
    await assertFails(updateDoc(doc(as('officer'), 'reports/r1'), { aiReason: 'edited' }));
    await assertFails(
      updateDoc(doc(as('officer'), 'reports/r1'), {
        status: 'cleared', clearedBy: 'officer', clearedAt: serverTimestamp(), uid: 'officer',
      }),
    );
  });

  test('a blocked authority cannot clear', async () => {
    await assertFails(
      updateDoc(doc(as('banned-officer'), 'reports/r1'), {
        status: 'cleared', clearedBy: 'banned-officer', clearedAt: serverTimestamp(),
      }),
    );
  });

  test('anyone active can add a still-present confirmation', async () => {
    await assertSucceeds(
      updateDoc(doc(as('bob'), 'reports/r1'), {
        confirmationCount: increment(1), lastConfirmedAt: serverTimestamp(), lastConfirmationId: 'conf-1',
      }),
    );
  });

  test('a still-present update cannot do more than +1 or touch other fields', async () => {
    await assertFails(
      updateDoc(doc(as('bob'), 'reports/r1'), {
        confirmationCount: increment(5), lastConfirmedAt: serverTimestamp(), lastConfirmationId: 'c',
      }),
    );
    await assertFails(
      updateDoc(doc(as('bob'), 'reports/r1'), {
        confirmationCount: increment(1), lastConfirmedAt: serverTimestamp(), lastConfirmationId: 'c', status: 'cleared',
      }),
    );
    await assertFails(
      updateDoc(doc(as('bob'), 'reports/r1'), {
        confirmationCount: increment(1), lastConfirmedAt: new Date('2020-01-01'), lastConfirmationId: 'c',
      }),
    );
    await assertFails(updateDoc(doc(as('bob'), 'reports/r1'), { aiReason: 'edited' }));
  });

  test('a still-present update only works on a valid report and for an active user', async () => {
    const up = { confirmationCount: increment(1), lastConfirmedAt: serverTimestamp(), lastConfirmationId: 'c' };
    await assertFails(updateDoc(doc(as('bob'), 'reports/r2'), up));
    await assertFails(updateDoc(doc(as('banned'), 'reports/r1'), up));
  });

  test('nobody can delete a report', async () => {
    await assertFails(deleteDoc(doc(as('alice'), 'reports/r1')));
    await assertFails(deleteDoc(doc(as('boss'), 'reports/r1')));
  });
});

// ---------------------------------------------------------------------------
describe('saving a report (the real batch from FirestoreService.submitReport)', () => {
  const pointsMerge = { points: increment(10), pointsBalance: increment(10) };

  test('valid: report + photo + points in one batch', async () => {
    const db = as('alice');
    const batch = writeBatch(db);
    batch.set(doc(db, 'reports/new1'), report('alice', 'valid', { photoId: 'new1' }));
    batch.set(doc(db, 'reportPhotos/new1'), { photoBase64: 'QUJD', reportId: 'new1', createdAt: serverTimestamp() });
    batch.set(doc(db, 'users/alice'), pointsMerge, { merge: true });
    await assertSucceeds(batch.commit());
  });

  test('rejected: only the report', async () => {
    const db = as('alice');
    const batch = writeBatch(db);
    batch.set(doc(db, 'reports/new2'), report('alice', 'rejected'));
    await assertSucceeds(batch.commit());
  });

  test('a photo for someone else\'s report is refused', async () => {
    const db = as('bob');
    const batch = writeBatch(db);
    batch.set(doc(db, 'reports/new3'), report('bob', 'valid'));
    // bob tries to store a photo under alice's existing report id
    batch.set(doc(db, 'reportPhotos/r2'), { photoBase64: 'QUJD', reportId: 'r2' });
    await assertFails(batch.commit());
  });

  test('a photo without any report is refused', async () => {
    await assertFails(setDoc(doc(as('alice'), 'reportPhotos/orphan'), { photoBase64: 'QUJD', reportId: 'orphan' }));
  });

  test('a blocked user cannot save a photo or report', async () => {
    const db = as('banned');
    const batch = writeBatch(db);
    batch.set(doc(db, 'reports/new4'), report('banned', 'valid'));
    batch.set(doc(db, 'reportPhotos/new4'), { photoBase64: 'QUJD', reportId: 'new4' });
    await assertFails(batch.commit());
  });
});

// ---------------------------------------------------------------------------
describe('reportPhotos', () => {
  test('a signed-in user can read one photo by id but never list', async () => {
    await assertSucceeds(getDoc(doc(as('bob'), 'reportPhotos/r1')));
    await assertFails(getDocs(collection(as('bob'), 'reportPhotos')));
  });

  test('only authority or admin can delete a photo', async () => {
    await assertFails(deleteDoc(doc(as('alice'), 'reportPhotos/r1')));
    await assertFails(deleteDoc(doc(as('bob'), 'reportPhotos/r1')));
    await assertSucceeds(deleteDoc(doc(as('officer'), 'reportPhotos/r1')));
  });

  test('a photo cannot be overwritten', async () => {
    await assertFails(updateDoc(doc(as('alice'), 'reportPhotos/r1'), { photoBase64: 'ZZZ' }));
  });

  test('markReportCleared: status change and photo delete in one batch', async () => {
    const db = as('officer');
    const batch = writeBatch(db);
    batch.update(doc(db, 'reports/r1'), { status: 'cleared', clearedBy: 'officer', clearedAt: serverTimestamp() });
    batch.delete(doc(db, 'reportPhotos/r1'));
    await assertSucceeds(batch.commit());
  });

  test('the same batch is refused for a normal user', async () => {
    const db = as('alice');
    const batch = writeBatch(db);
    batch.update(doc(db, 'reports/r1'), { status: 'cleared', clearedBy: 'alice', clearedAt: serverTimestamp() });
    batch.delete(doc(db, 'reportPhotos/r1'));
    await assertFails(batch.commit());
  });
});

// ---------------------------------------------------------------------------
describe('coupons', () => {
  test('a signed-in user can read coupons', async () => {
    await assertSucceeds(getDoc(doc(as('bob'), 'coupons/c1')));
    await assertSucceeds(getDocs(query(collection(as('bob'), 'coupons'), where('available', '==', true))));
  });

  test('only an admin can create or delete a coupon', async () => {
    const coupon = { title: 'New', description: 'd', cost: 10, code: 'NEW10', available: true };
    await assertSucceeds(setDoc(doc(as('boss'), 'coupons/c2'), coupon));
    await assertFails(setDoc(doc(as('alice'), 'coupons/c3'), coupon));
    await assertFails(setDoc(doc(as('officer'), 'coupons/c4'), coupon));
    await assertSucceeds(deleteDoc(doc(as('boss'), 'coupons/c1')));
    await assertFails(deleteDoc(doc(as('alice'), 'coupons/c1')));
  });

  test('redeeming: an available coupon becomes unavailable', async () => {
    await assertSucceeds(updateDoc(doc(as('alice'), 'coupons/c1'), { available: false, status: 'redeemed' }));
  });

  test('a user cannot change a coupon any other way', async () => {
    await assertFails(updateDoc(doc(as('alice'), 'coupons/c1'), { cost: 0 }));
    await assertFails(updateDoc(doc(as('alice'), 'coupons/c1'), { available: false, cost: 0 }));
    await assertFails(updateDoc(doc(as('alice'), 'coupons/c1'), { code: 'FREE' }));
  });

  test('a redeemed coupon cannot be made available again by a user', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'coupons/c1'), { available: false, status: 'redeemed' });
    });
    await assertFails(updateDoc(doc(as('alice'), 'coupons/c1'), { available: true, status: 'available' }));
  });

  test('an admin can edit a coupon', async () => {
    await assertSucceeds(updateDoc(doc(as('boss'), 'coupons/c1'), { cost: 99, available: true }));
  });

  test('a blocked user cannot redeem', async () => {
    await assertFails(updateDoc(doc(as('banned'), 'coupons/c1'), { available: false, status: 'redeemed' }));
  });
});

// ---------------------------------------------------------------------------
describe('redemptions', () => {
  test('the real redeemCoupon transaction works', async () => {
    const db = as('alice');
    await assertSucceeds(
      runTransaction(db, async (tx) => {
        const userRef = doc(db, 'users/alice');
        const couponRef = doc(db, 'coupons/c1');
        const user = await tx.get(userRef);
        await tx.get(couponRef);
        const left = user.data().points - 20;
        tx.update(userRef, { points: left, pointsBalance: left });
        tx.update(couponRef, { available: false, status: 'redeemed' });
        tx.set(doc(collection(db, 'redemptions')), { uid: 'alice', couponId: 'c1', code: 'ECO20', cost: 20 });
      }),
    );
  });

  test('a user cannot add points while redeeming', async () => {
    const db = as('alice');
    await assertFails(
      runTransaction(db, async (tx) => {
        const userRef = doc(db, 'users/alice');
        await tx.get(userRef);
        tx.update(userRef, { points: 500, pointsBalance: 500 });
        tx.set(doc(collection(db, 'redemptions')), { uid: 'alice', couponId: 'c1', cost: 20 });
      }),
    );
  });

  test('a user can only create and read their own redemptions', async () => {
    await assertSucceeds(setDoc(doc(as('bob'), 'redemptions/b1'), { uid: 'bob', couponId: 'c1', cost: 5 }));
    await assertFails(setDoc(doc(as('bob'), 'redemptions/b2'), { uid: 'alice', couponId: 'c1', cost: 5 }));
    await assertSucceeds(getDocs(query(collection(as('alice'), 'redemptions'), where('uid', '==', 'alice'))));
    await assertFails(getDocs(query(collection(as('bob'), 'redemptions'), where('uid', '==', 'alice'))));
  });

  test('a blocked user cannot create a redemption', async () => {
    await assertFails(setDoc(doc(as('banned'), 'redemptions/b3'), { uid: 'banned', couponId: 'c1', cost: 5 }));
  });
});
