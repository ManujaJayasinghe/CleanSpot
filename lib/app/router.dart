import 'package:go_router/go_router.dart';

import '../features/admin/admin_home_screen.dart';
import '../features/analysis/analysis_screen.dart';
import '../features/authority/authority_home_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/home/home_screen.dart';
import '../features/map/map_screen.dart';
import '../features/profile/my_coupons_screen.dart';
import '../features/profile/my_reports_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/report/report_screen.dart';
import '../features/rewards/rewards_screen.dart';
import '../features/symptoms/symptoms_screen.dart';
import 'home_shell.dart';
import 'session.dart';
import 'splash_screen.dart';

/// Who is signed in and their role (read live from Firestore). The router
/// re-runs its redirect whenever this changes.
final SessionNotifier session = SessionNotifier();

final router = GoRouter(
  initialLocation: '/home',
  refreshListenable: session,
  // See redirectFor() in session.dart: login sends each role to its home, and
  // /admin and /authority are closed to everyone else.
  redirect: (context, state) => session.redirect(state.matchedLocation),
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, state) =>
          LoginScreen(blocked: state.uri.queryParameters['blocked'] == '1'),
    ),
    GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
    GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/admin', builder: (_, _) => const AdminHomeScreen()),
    GoRoute(
      path: '/authority',
      builder: (_, _) => const AuthorityHomeScreen(),
    ),
    ShellRoute(
      builder: (_, _, child) => HomeShell(child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/map', builder: (_, _) => const MapScreen()),
        GoRoute(path: '/report', builder: (_, _) => const ReportScreen()),
        GoRoute(path: '/rewards', builder: (_, _) => const RewardsScreen()),
        GoRoute(path: '/analysis', builder: (_, _) => const AnalysisScreen()),
        GoRoute(path: '/symptoms', builder: (_, _) => const SymptomsScreen()),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(
          path: '/profile/reports',
          builder: (_, _) => const MyReportsScreen(),
        ),
        GoRoute(
          path: '/profile/coupons',
          builder: (_, _) => const MyCouponsScreen(),
        ),
      ],
    ),
  ],
);
