import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';

/// Name, email and photo of whoever is signed in right now.
class CurrentUser {
  const CurrentUser({required this.name, required this.email, this.photoUrl});

  final String name;
  final String email;
  final String? photoUrl;

  factory CurrentUser.fromAuth() {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final displayName = user?.displayName?.trim() ?? '';
    final name = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email.split('@').first : 'there');
    return CurrentUser(name: name, email: email, photoUrl: user?.photoURL);
  }

  String get firstName => name.split(RegExp(r'\s+')).first;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }
}

/// Builds with the signed-in user's live points balance from Firestore
/// (users/{uid}.pointsBalance). Shows 0 until it loads.
class UserPoints extends StatefulWidget {
  const UserPoints({super.key, required this.builder, this.stream});

  final Widget Function(BuildContext context, int points) builder;

  /// Profile stream override, for tests. Defaults to the signed-in user.
  final Stream<UserModel?>? stream;

  @override
  State<UserPoints> createState() => _UserPointsState();
}

class _UserPointsState extends State<UserPoints> {
  Stream<UserModel?>? _stream;

  @override
  void initState() {
    super.initState();
    if (widget.stream != null) {
      _stream = widget.stream;
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _stream = FirestoreService().watchUser(uid);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserModel?>(
      stream: _stream,
      builder: (context, snapshot) =>
          widget.builder(context, snapshot.data?.pointsBalance ?? 0),
    );
  }
}
