import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';
import '../services/firestore_service.dart';

/// Shown on the login screen after a blocked user has been signed out.
const String kBlockedMessage =
    'Your account has been blocked. Contact support.';

/// Where each role lands after login.
/// Authorities land on their dashboard; admins and regular users land on /home
/// (admins can access /admin from their profile or drawer).
String homeRouteFor(String role) => switch (role) {
      kRoleAuthority => '/authority',
      _ => '/home',
    };

/// The route guard, as a pure function so it can be tested without Firebase.
/// Returns where to send the user, or null to stay on [location].
///
/// - signed out: only /login and /register (after a block: /login?blocked=1)
/// - signed in but the role is not loaded yet, or the user is blocked: /splash
/// - signed in: login, register and splash lead to the role's home; /admin is
///   for admins only; /authority is for authorities and admins
String? redirectFor({
  required String location,
  required bool signedIn,
  required bool ready,
  required String role,
  required bool blocked,
  required bool blockedNotice,
}) {
  final atAuth = location == '/login' || location == '/register';

  if (!signedIn) {
    if (atAuth) return null;
    return blockedNotice ? '/login?blocked=1' : '/login';
  }
  if (!ready || blocked) return location == '/splash' ? null : '/splash';

  final home = homeRouteFor(role);
  if (location == '/splash' || atAuth) return home;
  if (location.startsWith('/admin') && role != kRoleAdmin) return home;
  if (location.startsWith('/authority') &&
      role != kRoleAuthority &&
      role != kRoleAdmin) {
    return home;
  }
  return null;
}

/// Signs out of Firebase and, if used, Google.
Future<void> signOutEverywhere() async {
  await FirebaseAuth.instance.signOut();
  try {
    await GoogleSignIn.instance.signOut();
  } catch (_) {
    // Not signed in with Google; nothing to clear.
  }
}

/// Who is signed in and what their role is, read live from `users/{uid}`.
///
/// The router refreshes whenever this changes, so a role change or a block
/// takes effect while the app is open. A blocked user is signed out at once and
/// [blockedNotice] stays true until someone who is not blocked signs in.
class SessionNotifier extends ChangeNotifier {
  SessionNotifier({
    Stream<User?>? authChanges,
    Stream<UserModel?> Function(String uid)? watchProfile,
    Future<void> Function()? signOut,
  })  : _watchProfile = watchProfile ?? FirestoreService().watchUser,
        _signOut = signOut ?? signOutEverywhere {
    _user = null;
    _authSub = (authChanges ?? FirebaseAuth.instance.authStateChanges())
        .listen(_onAuth);
  }

  final Stream<UserModel?> Function(String uid) _watchProfile;
  final Future<void> Function() _signOut;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<UserModel?>? _profileSub;

  User? _user;
  UserModel? _profile;
  bool _ready = false;
  bool _blockedNotice = false;

  bool get signedIn => _user != null;

  /// True once the profile has been read (or reading it failed).
  bool get ready => _ready;

  /// 'user' when the profile is missing, unreadable or has no role.
  String get role => _profile?.role ?? kRoleUser;

  bool get blocked => _profile?.blocked ?? false;
  bool get blockedNotice => _blockedNotice;

  String? redirect(String location) => redirectFor(
        location: location,
        signedIn: signedIn,
        ready: ready,
        role: role,
        blocked: blocked,
        blockedNotice: blockedNotice,
      );

  void _onAuth(User? user) {
    _profileSub?.cancel();
    _profileSub = null;
    _user = user;
    _profile = null;
    _ready = false;
    if (user != null) {
      _profileSub = _watchProfile(user.uid).listen(
        _onProfile,
        // Unreadable profile: least privilege (a normal user). The rules still
        // decide what the account can actually do.
        onError: (Object _) {
          _profile = null;
          _ready = true;
          notifyListeners();
        },
      );
    }
    notifyListeners();
  }

  void _onProfile(UserModel? profile) {
    _profile = profile;
    _ready = true;
    if (profile != null && profile.blocked) {
      _blockedNotice = true;
      unawaited(_signOut());
    } else if (profile != null) {
      _blockedNotice = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
