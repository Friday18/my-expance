import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/format.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../state/expense_store.dart';

/// Bottom sheet to add a new expense or edit [existing].
Future<void> showExpenseEditor(BuildContext context, {Expense? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<ExpenseStore>(),
      child: _ExpenseEditor(existing: existing),
    ),
  );
}

class _ExpenseEditor extends StatefulWidget {
  const _ExpenseEditor({this.existing});
  final Expense? existing;

  @override
  State<_ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<_ExpenseEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _category;
  late DateTime _day;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(text: e == null ? '' : _plain(e.amount));
    _note = TextEditingController(text: e?.note ?? '');
    _category = e?.category ?? 'food';
    _day = e?.spentOn ?? dayOnly(DateTime.now());
  }

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _day = dayOnly(picked));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final store = context.read<ExpenseStore>();
    final amount = double.parse(_amount.text.replaceAll(',', '').trim());
    setState(() => _saving = true);
    try {
      if (_editing) {
        await store.update(widget.existing!.copyWith(
          amount: amount,
          category: _category,
          note: _note.text.trim(),
          spentOn: _day,
        ));
      } else {
        await store.add(amount: amount, category: _category, note: _note.text.trim(), spentOn: _day);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _delete() async {
    final store = context.read<ExpenseStore>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.delete(widget.existing!);
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = context.read<ExpenseStore>().currency;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_editing ? 'Edit expense' : 'Add expense', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: !_editing,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: theme.textTheme.headlineSmall,
                decoration: InputDecoration(labelText: 'Amount', prefixText: currencySymbol(currency)),
                validator: (v) {
                  final n = double.tryParse((v ?? '').replaceAll(',', '').trim());
                  if (n == null || n <= 0) return 'Enter an amount';
                  if (n > 10000000) return 'That amount is too large';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text('Category', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in kCategories)
                  ChoiceChip(
                    selected: _category == c.key,
                    onSelected: (_) => setState(() => _category = c.key),
                    avatar: Icon(c.icon, size: 18, color: c.colorFor(theme.brightness)),
                    label: Text(c.label),
                    showCheckmark: false,
                  ),
              ]),
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)', counterText: ''),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDay,
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                label: Text(DateFormat('EEE, d MMM yyyy').format(_day)),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(_editing ? 'Save changes' : 'Add expense'),
              ),
              if (_editing) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error, minimumSize: const Size(64, 48)),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
