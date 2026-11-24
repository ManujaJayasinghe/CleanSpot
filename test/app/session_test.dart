import 'dart:async';

import 'package:clean_spot/app/session.dart';
import 'package:clean_spot/models/user_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

/// Only `uid` is ever read from the signed-in user.
class _FakeUser implements User {
  _FakeUser(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String? guard(
  String location, {
  bool signedIn = true,
  bool ready = true,
  String role = 'user',
  bool blocked = false,
  bool blockedNotice = false,
}) =>
    redirectFor(
      location: location,
      signedIn: signedIn,
      ready: ready,
      role: role,
      blocked: blocked,
      blockedNotice: blockedNotice,
    );

void main() {
  group('homeRouteFor', () {
    test('each role has its own home', () {
      expect(homeRouteFor('admin'), '/home');
      expect(homeRouteFor('authority'), '/authority');
      expect(homeRouteFor('user'), '/home');
      expect(homeRouteFor('anything else'), '/home');
    });
  });

  group('redirectFor: signed out', () {
    test('everything goes to login except login and register', () {
      expect(guard('/home', signedIn: false), '/login');
      expect(guard('/admin', signedIn: false), '/login');
      expect(guard('/authority', signedIn: false), '/login');
      expect(guard('/report', signedIn: false), '/login');
      expect(guard('/login', signedIn: false), isNull);
      expect(guard('/register', signedIn: false), isNull);
    });

    test('after a block the login page carries the blocked notice', () {
      expect(guard('/home', signedIn: false, blockedNotice: true), '/login?blocked=1');
      expect(guard('/splash', signedIn: false, blockedNotice: true), '/login?blocked=1');
      expect(guard('/login', signedIn: false, blockedNotice: true), isNull);
    });
  });

  group('redirectFor: signed in, role not known yet or blocked', () {
    test('waits on the splash page while the role loads', () {
      expect(guard('/login', ready: false), '/splash');
      expect(guard('/home', ready: false), '/splash');
      expect(guard('/admin', ready: false), '/splash');
      expect(guard('/splash', ready: false), isNull);
    });

    test('a blocked user is held on the splash page until signed out', () {
      expect(guard('/home', blocked: true), '/splash');
      expect(guard('/admin', role: 'admin', blocked: true), '/splash');
      expect(guard('/splash', blocked: true), isNull);
    });
  });

  group('redirectFor: after login', () {
    test('each role lands on its home', () {
      expect(guard('/splash', role: 'admin'), '/home');
      expect(guard('/splash', role: 'authority'), '/authority');
      expect(guard('/splash', role: 'user'), '/home');
      expect(guard('/login', role: 'admin'), '/home');
      expect(guard('/register', role: 'authority'), '/authority');
      expect(guard('/login', role: 'user'), '/home');
    });
  });

  group('redirectFor: guarded routes', () {
    test('a normal user cannot open /admin or /authority', () {
      expect(guard('/admin'), '/home');
      expect(guard('/authority'), '/home');
      expect(guard('/admin/users'), '/home');
    });

    test('an authority cannot open /admin', () {
      expect(guard('/admin', role: 'authority'), '/authority');
      expect(guard('/authority', role: 'authority'), isNull);
    });

    test('an admin can open /admin and /authority', () {
      expect(guard('/admin', role: 'admin'), isNull);
      expect(guard('/authority', role: 'admin'), isNull);
    });

    test('normal routes are open to a signed-in user', () {
      for (final r in ['/home', '/map', '/report', '/rewards', '/profile', '/analysis']) {
        expect(guard(r), isNull, reason: r);
      }
    });
  });

  group('SessionNotifier', () {
    late StreamController<User?> auth;
    late Map<String, StreamController<UserModel?>> profiles;
    late int signOuts;

    SessionNotifier make() => SessionNotifier(
          authChanges: auth.stream,
          watchProfile: (uid) =>
              (profiles[uid] ??= StreamController<UserModel?>.broadcast()).stream,
          signOut: () async {
            signOuts++;
            auth.add(null);
          },
        );

    setUp(() {
      auth = StreamController<User?>.broadcast();
      profiles = {};
      signOuts = 0;
    });

    tearDown(() async {
      await auth.close();
      for (final c in profiles.values) {
        await c.close();
      }
    });

    UserModel user(String uid, {String role = 'user', bool blocked = false}) =>
        UserModel(
          uid: uid,
          displayName: uid,
          pointsBalance: 0,
          createdAt: DateTime(2026),
          role: role,
          blocked: blocked,
        );

    Future<void> pump() => Future<void>.delayed(Duration.zero);

    test('starts signed out', () {
      final s = make();
      expect(s.signedIn, isFalse);
      expect(s.ready, isFalse);
      expect(s.redirect('/home'), '/login');
      s.dispose();
    });

    test('signing in is not ready until the profile arrives', () async {
      final s = make();
      auth.add(_FakeUser('a'));
      await pump();
      expect(s.signedIn, isTrue);
      expect(s.ready, isFalse);
      expect(s.redirect('/login'), '/splash');

      profiles['a']!.add(user('a', role: 'admin'));
      await pump();
      expect(s.ready, isTrue);
      expect(s.role, 'admin');
      expect(s.redirect('/splash'), '/admin');
      s.dispose();
    });

    test('a normal user goes to the normal home', () async {
      final s = make();
      auth.add(_FakeUser('u'));
      await pump();
      profiles['u']!.add(user('u'));
      await pump();
      expect(s.role, 'user');
      expect(s.redirect('/splash'), '/home');
      expect(s.redirect('/admin'), '/home');
      s.dispose();
    });

    test('a missing profile document is a normal user', () async {
      final s = make();
      auth.add(_FakeUser('new'));
      await pump();
      profiles['new']!.add(null);
      await pump();
      expect(s.ready, isTrue);
      expect(s.role, 'user');
      expect(s.blocked, isFalse);
      s.dispose();
    });

    test('an unreadable profile is treated as a normal user, not an admin', () async {
      final s = make();
      auth.add(_FakeUser('x'));
      await pump();
      profiles['x']!.addError(Exception('permission-denied'));
      await pump();
      expect(s.ready, isTrue);
      expect(s.role, 'user');
      s.dispose();
    });

    test('a blocked user is signed out and gets the blocked notice', () async {
      final s = make();
      auth.add(_FakeUser('b'));
      await pump();
      profiles['b']!.add(user('b', blocked: true));
      await pump();
      expect(signOuts, 1);
      expect(s.signedIn, isFalse, reason: 'signing out cleared the user');
      expect(s.blockedNotice, isTrue);
      expect(s.redirect('/home'), '/login?blocked=1');
      expect(s.redirect('/login'), isNull);
      s.dispose();
    });

    test('a blocked admin is signed out too', () async {
      final s = make();
      auth.add(_FakeUser('ba'));
      await pump();
      profiles['ba']!.add(user('ba', role: 'admin', blocked: true));
      await pump();
      expect(signOuts, 1);
      expect(s.redirect('/admin'), '/login?blocked=1');
      s.dispose();
    });

    test('blocking a signed-in user while the app is open signs them out', () async {
      final s = make();
      auth.add(_FakeUser('live'));
      await pump();
      profiles['live']!.add(user('live'));
      await pump();
      expect(s.redirect('/home'), isNull);

      profiles['live']!.add(user('live', blocked: true));
      await pump();
      expect(signOuts, 1);
      expect(s.redirect('/home'), '/login?blocked=1');
      s.dispose();
    });

    test('the blocked notice clears when an unblocked user signs in', () async {
      final s = make();
      auth.add(_FakeUser('b'));
      await pump();
      profiles['b']!.add(user('b', blocked: true));
      await pump();
      expect(s.blockedNotice, isTrue);

      auth.add(_FakeUser('ok'));
      await pump();
      profiles['ok']!.add(user('ok'));
      await pump();
      expect(s.blockedNotice, isFalse);
      expect(s.redirect('/login'), '/home');
      s.dispose();
    });

    test('a role change while the app is open moves the user', () async {
      final s = make();
      auth.add(_FakeUser('r'));
      await pump();
      profiles['r']!.add(user('r', role: 'authority'));
      await pump();
      expect(s.redirect('/authority'), isNull);

      profiles['r']!.add(user('r')); // demoted
      await pump();
      expect(s.redirect('/authority'), '/home');
      s.dispose();
    });

    test('signing out resets everything', () async {
      final s = make();
      auth.add(_FakeUser('r'));
      await pump();
      profiles['r']!.add(user('r', role: 'admin'));
      await pump();
      auth.add(null);
      await pump();
      expect(s.signedIn, isFalse);
      expect(s.ready, isFalse);
      expect(s.role, 'user');
      expect(s.redirect('/admin'), '/login');
      s.dispose();
    });
  });
}
