import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _tabs = [
  (path: '/home', label: 'Map', icon: Icons.map_outlined),
  (path: '/report', label: 'Report', icon: Icons.add_circle_outline),
  (path: '/rewards', label: 'Rewards', icon: Icons.card_giftcard_outlined),
  (path: '/profile', label: 'Profile', icon: Icons.person_outline),
];

const _extras = [
  (path: '/analysis', label: 'Analysis', icon: Icons.bar_chart),
  (path: '/symptoms', label: 'Symptoms', icon: Icons.health_and_safety_outlined),
];

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    int index = _tabs.indexWhere((t) => location.startsWith(t.path));
    if (location == '/map') index = 0;
    final onTab = index != -1;

    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              for (final t in _tabs)
                ListTile(
                  leading: Icon(t.icon),
                  title: Text(t.label),
                  selected: location.startsWith(t.path),
                  onTap: () {
                    Navigator.pop(context);
                    context.go(t.path);
                  },
                ),
              const Divider(),
              for (final t in _extras)
                ListTile(
                  leading: Icon(t.icon),
                  title: Text(t.label),
                  selected: location.startsWith(t.path),
                  onTap: () {
                    Navigator.pop(context);
                    context.go(t.path);
                  },
                ),
            ],
          ),
        ),
      ),
      body: child,
      bottomNavigationBar: onTab
          ? Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE8EDE8), width: 1),
                ),
              ),
              child: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => context.go(_tabs[i].path),
                destinations: [
                  for (final t in _tabs)
                    NavigationDestination(icon: Icon(t.icon), label: t.label),
                ],
              ),
            )
          : null,
    );
  }
}
