import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../logic/format.dart';
import '../services/auth_service.dart';
import '../state/expense_store.dart';
import '../state/settings_store.dart';

const _currencies = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'AUD', 'CAD', 'JPY'];

Future<void> showBudgetDialog(BuildContext context) async {
  final store = context.read<ExpenseStore>();
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _BudgetDialog(initial: store.monthlyBudget, currency: store.currency),
  );
  if (result == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final value = double.tryParse(result.trim());
    await store.setBudget(value == null || value <= 0 ? null : value);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

/// Owns its text controller, so it is disposed only after the dialog's closing animation finishes.
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.initial, required this.currency});
  final double? initial;
  final String currency;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial == null ? '' : widget.initial!.toStringAsFixed(0));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Monthly budget'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(prefixText: currencySymbol(widget.currency), hintText: '20000'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Remove')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Save')),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t open $uri')));
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final store = context.read<ExpenseStore>();
    await context.read<AuthService>().signOut();
    store.clear();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and every expense. This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final store = context.read<ExpenseStore>();
    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.deleteAccount();
      await auth.deleteFirebaseAccount();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Couldn\'t delete account: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final settings = context.watch<SettingsStore>();
    final auth = context.watch<AuthService>();
    final theme = Theme.of(context);

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(child: Text(auth.displayName.isEmpty ? '?' : auth.displayName[0].toUpperCase())),
          title: Text(auth.displayName),
          subtitle: Text(auth.email),
        ),
        header('Money'),
        ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: const Text('Monthly budget'),
          subtitle: Text(store.monthlyBudget == null
              ? 'Not set'
              : formatMoney(store.monthlyBudget!, currency: store.currency, decimals: false)),
          onTap: () => showBudgetDialog(context),
        ),
        ListTile(
          leading: const Icon(Icons.currency_exchange_rounded),
          title: const Text('Currency'),
          trailing: DropdownButton<String>(
            value: _currencies.contains(store.currency) ? store.currency : 'INR',
            underline: const SizedBox.shrink(),
            items: [for (final c in _currencies) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (c) async {
              if (c == null) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await store.setCurrency(c);
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
          ),
        ),
        header('Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_rounded)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => settings.setThemeMode(s.first),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.insert_chart_outlined_rounded),
          title: const Text('Overview chart'),
          trailing: DropdownButton<ChartStyle>(
            value: settings.chartStyle,
            underline: const SizedBox.shrink(),
            items: [for (final s in ChartStyle.values) DropdownMenuItem(value: s, child: Text(s.label))],
            onChanged: (s) {
              if (s != null) settings.setChartStyle(s);
            },
          ),
        ),
        header('About'),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy policy'),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => _open(context, Uri.parse(AppConfig.privacyUrl)),
        ),
        ListTile(
          leading: const Icon(Icons.mail_outline_rounded),
          title: const Text('Contact support'),
          subtitle: const Text(AppConfig.supportEmail),
          onTap: () => _open(context, Uri(scheme: 'mailto', path: AppConfig.supportEmail, query: 'subject=My Expance')),
        ),
        header('Account'),
        ListTile(
          leading: const Icon(Icons.logout_rounded),
          title: const Text('Sign out'),
          onTap: () => _signOut(context),
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_rounded, color: theme.colorScheme.error),
          title: Text('Delete account', style: TextStyle(color: theme.colorScheme.error)),
          subtitle: const Text('Permanently delete your account and all data'),
          onTap: () => _deleteAccount(context),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }
}
