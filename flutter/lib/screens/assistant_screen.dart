import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/format.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../state/expense_store.dart';
import '../theme/app_theme.dart';

class _Msg {
  _Msg(this.role, this.text, {this.actions = const [], this.error = false});
  final String role; // 'user' | 'assistant'
  final String text;
  final List<Map<String, dynamic>> actions;
  final bool error;
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _sending = false;

  static const _suggestions = [
    'Spent 450 on lunch',
    'Uber 220 yesterday',
    'How much on food this month?',
    'Am I within budget?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    final store = context.read<ExpenseStore>();
    setState(() {
      _messages.add(_Msg('user', text));
      _sending = true;
      _input.clear();
    });
    _scrollToEnd();

    // Send the last 20 good turns as context.
    final history = _messages
        .where((m) => !m.error)
        .map((m) => {'role': m.role, 'content': m.text})
        .toList();
    final recent = history.length > 20 ? history.sublist(history.length - 20) : history;

    try {
      final result = await store.api.chat(recent);
      if (!mounted) return;
      setState(() => _messages.add(_Msg('assistant', result.reply, actions: result.actions)));
      if (result.actions.isNotEmpty) await store.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_Msg('assistant', e.toString(), error: true)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (Motion.reduced(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: Motion.medium, curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = context.select<ExpenseStore, String>((s) => s.currency);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'New conversation',
              onPressed: _sending ? null : () => setState(_messages.clear),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _messages.isEmpty
              ? _Welcome(onPick: _send, suggestions: _suggestions)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _messages.length) return const _Typing();
                    return _Bubble(msg: _messages[i], currency: currency);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Spent 450 on lunch…', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.arrow_upward_rounded),
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
            ]),
          ),
        ),
      ]),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onPick, required this.suggestions});
  final ValueChanged<String> onPick;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 24),
      Icon(Icons.auto_awesome_rounded, size: 44, color: theme.colorScheme.primary),
      const SizedBox(height: 16),
      Text('Talk to log', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        'Tell me what you spent in plain words, or ask about your spending.',
        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        for (final s in suggestions) ActionChip(label: Text(s), onPressed: () => onPick(s)),
      ]),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.currency});
  final _Msg msg;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = msg.role == 'user';
    final bg = msg.error
        ? theme.colorScheme.errorContainer
        : mine
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHigh;
    final fg = msg.error
        ? theme.colorScheme.onErrorContainer
        : mine
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 18),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: SelectableText(msg.text, style: theme.textTheme.bodyLarge?.copyWith(color: fg)),
                ),
              ),
              if (msg.actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final a in msg.actions) _ActionChip(action: a, currency: currency),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.action, required this.currency});
  final Map<String, dynamic> action;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = Expense.fromJson(action['expense'] as Map<String, dynamic>);
    final info = categoryInfo(e.category);
    final verb = switch (action['type']) { 'added' => 'Added', 'updated' => 'Updated', 'deleted' => 'Deleted', _ => '' };
    return Chip(
      avatar: Icon(
        action['type'] == 'deleted' ? Icons.delete_outline_rounded : Icons.check_circle_rounded,
        size: 18,
        color: info.colorFor(theme.brightness),
      ),
      label: Text('$verb ${formatMoney(e.amount, currency: currency)} · ${info.label}'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'Assistant is thinking',
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const SizedBox(width: 28, height: 12, child: LinearProgressIndicator()),
        ),
      ),
    );
  }
}
