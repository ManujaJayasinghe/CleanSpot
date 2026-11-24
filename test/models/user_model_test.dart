import 'package:clean_spot/models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserModel role and blocked', () {
    test('an old document without role or blocked is a normal, unblocked user', () {
      final u = UserModel.fromMap('u1', {
        'displayName': 'Alice',
        'points': 5,
        'pointsBalance': 5,
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
      });
      expect(u.role, 'user');
      expect(u.blocked, isFalse);
      expect(u.isAdmin, isFalse);
      expect(u.isAuthority, isFalse);
    });

    test('role and blocked are read from the document', () {
      final admin = UserModel.fromMap('a', {'role': 'admin'});
      expect(admin.role, 'admin');
      expect(admin.isAdmin, isTrue);

      final officer = UserModel.fromMap('o', {'role': 'authority', 'blocked': true});
      expect(officer.role, 'authority');
      expect(officer.isAuthority, isTrue);
      expect(officer.blocked, isTrue);
    });

    test('an unknown or mistyped role falls back to user', () {
      for (final bad in ['superuser', 'Admin', '', 42, null, true]) {
        expect(UserModel.fromMap('u', {'role': bad}).role, 'user', reason: '$bad');
      }
    });

    test('blocked is true only for a real true', () {
      for (final notBlocked in [false, null, 'true', 1, 'yes']) {
        expect(UserModel.fromMap('u', {'blocked': notBlocked}).blocked, isFalse,
            reason: '$notBlocked');
      }
      expect(UserModel.fromMap('u', {'blocked': true}).blocked, isTrue);
    });

    test('toMap writes the defaults for a new user', () {
      final map = UserModel(
        uid: 'u',
        displayName: 'N',
        pointsBalance: 0,
        createdAt: DateTime(2026, 11, 1),
      ).toMap();
      expect(map['role'], 'user');
      expect(map['blocked'], false);
      expect(map['points'], 0);
      expect(map['pointsBalance'], 0);
    });

    test('role and blocked round trip', () {
      final original = UserModel(
        uid: 'u',
        displayName: 'N',
        pointsBalance: 3,
        createdAt: DateTime(2026, 11, 1),
        role: 'authority',
        blocked: true,
      );
      final copy = UserModel.fromMap('u', original.toMap());
      expect(copy.role, 'authority');
      expect(copy.blocked, isTrue);
    });

    test('normalizeRole and the role list', () {
      expect(kUserRoles, ['user', 'admin', 'authority']);
      expect(normalizeRole('admin'), 'admin');
      expect(normalizeRole('nope'), 'user');
      expect(normalizeRole(null), 'user');
    });
  });
}
