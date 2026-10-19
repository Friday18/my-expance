import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/expense_store.dart';
import '../state/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/calm.dart';
import 'ask_screen.dart';
import 'assistant_screen.dart';
import 'insights_screen.dart';
import 'now_screen.dart';
import 'overview_screen.dart';
import 'settings_screen.dart';

/// Loads data once, then shows the shell for the chosen app style (Settings → Appearance).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ExpenseStore>().load());
  }

  @override
  Widget build(BuildContext context) {
    final futuristic = context.select<SettingsStore, bool>((s) => s.futuristic);
    return futuristic ? const _FuturisticShell() : const _ClassicShell();
  }
}

/// Classic: the original Material navigation bar with Overview, Assistant and Settings.
class _ClassicShell extends StatefulWidget {
  const _ClassicShell();

  @override
  State<_ClassicShell> createState() => _ClassicShellState();
}

class _ClassicShellState extends State<_ClassicShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps the assistant conversation when switching tabs.
      body: IndexedStack(
        index: _index,
        children: const [OverviewScreen(), AssistantScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline_rounded),
            selectedIcon: Icon(Icons.pie_chart_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Assistant',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Futuristic: three tabs only, Now, Ask (the orb) and Insights. Settings lives behind the avatar on Now.
class _FuturisticShell extends StatefulWidget {
  const _FuturisticShell();

  @override
  State<_FuturisticShell> createState() => _FuturisticShellState();
}

class _FuturisticShellState extends State<_FuturisticShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return CalmBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        // IndexedStack keeps the assistant conversation when switching tabs.
        body: IndexedStack(
          index: _index,
          children: const [NowScreen(), AskScreen(), InsightsScreen()],
        ),
        bottomNavigationBar: keyboardOpen
            ? null
            : _GlassNavBar(index: _index, onSelect: (i) => setState(() => _index = i)),
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = CalmTokens.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 4),
        child: GlassCard(
          blur: true,
          fill: t.sheetFill,
          radius: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            _NavItem(
              label: 'Now',
              icon: Icons.radio_button_checked_rounded,
              selected: index == 0,
              onTap: () => onSelect(0),
            ),
            _NavItem(
              label: 'Ask',
              selected: index == 1,
              onTap: () => onSelect(1),
              custom: const Orb(size: 40),
            ),
            _NavItem(
              label: 'Insights',
              icon: Icons.insights_rounded,
              selected: index == 2,
              onTap: () => onSelect(2),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.selected, required this.onTap, this.icon, this.custom});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? custom;

  @override
  Widget build(BuildContext context) {
    final t = CalmTokens.of(context);
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.onSurface : t.muted;
    Widget glyph = custom ?? Icon(icon, color: color, size: 24);
    if (custom == null && selected) glyph = AccentGradient(child: glyph);

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: SizedBox(
            height: 60,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(height: 40, child: Center(child: glyph)),
              AnimatedContainer(
                duration: Motion.of(context, Motion.short),
                width: selected ? 16 : 0,
                height: 3,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(gradient: t.accent, borderRadius: BorderRadius.circular(2)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
