import 'package:flutter/material.dart';

import '../features/models/presentation/models_screen.dart';
import '../features/monitor/presentation/monitor_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';
import 'app_controller.dart';

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release camera immediately when backgrounded or folded away
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      widget.controller.handleLifecyclePaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final screens = [
          MonitorScreen(controller: widget.controller),
          ModelsScreen(controller: widget.controller),
          StatisticsScreen(controller: widget.controller),
          SettingsScreen(controller: widget.controller),
        ];

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'SafeZone AI — مراقبة السلامة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            centerTitle: true,
            backgroundColor: const Color(0xFF0F172A),
          ),
          body: SafeArea(
            child: IndexedStack(
              index: _selectedIndex,
              children: screens,
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (idx) {
              setState(() => _selectedIndex = idx);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.videocam_outlined),
                selectedIcon: Icon(Icons.videocam),
                label: 'المراقبة',
              ),
              NavigationDestination(
                icon: Icon(Icons.hub_outlined),
                selectedIcon: Icon(Icons.hub),
                label: 'النماذج',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: 'الإحصائيات',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'الإعدادات',
              ),
            ],
          ),
        );
      },
    );
  }
}
