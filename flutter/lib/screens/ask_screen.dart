import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/format.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../state/expense_store.dart';
import '../theme/app_theme.dart';
import '../widgets/calm.dart';

class _Msg {
  _Msg(this.role, this.text, {this.actions = const [], this.error = false});
  final String role; // 'user' | 'assistant'
  final String text;
  final List<Map<String, dynamic>> actions;
  final bool error;
}

class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
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
    final t = CalmTokens.of(context);
    final currency = context.select<ExpenseStore, String>((s) => s.currency);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(children: [
          Orb(size: 30, mode: _sending ? OrbMode.thinking : OrbMode.idle),
          const SizedBox(width: 10),
          const Text('Ask'),
        ]),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: GlassCard(
              blur: true,
              fill: t.sheetFill,
              radius: 28,
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
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
                    decoration: const InputDecoration(
                      hintText: 'Chai 30 aur samosa 40…',
                      counterText: '',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                _SendButton(enabled: !_sending, onTap: _send),
              ]),
            ),
          ),
        ),
      ]),
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
    final t = CalmTokens.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 24), children: [
      const SizedBox(height: 12),
      const Center(child: Orb(size: 148)),
      const SizedBox(height: 20),
      Text('Talk to log', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        'Say what you spent in plain words, or ask about your money.',
        style: theme.textTheme.bodyLarge?.copyWith(color: t.muted),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 28),
      Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
        for (final s in suggestions)
          GlassCard(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            onTap: () => onPick(s),
            child: Text(s, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface)),
          ),
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
    final t = CalmTokens.of(context);
    final mine = msg.role == 'user';
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
                  color: msg.error ? theme.colorScheme.errorContainer : (mine ? null : t.glassFill),
                  gradient: mine && !msg.error ? t.accent : null,
                  border: mine ? null : Border.all(color: t.glassBorder),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(mine ? 20 : 6),
                    bottomRight: Radius.circular(mine ? 6 : 20),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          action['type'] == 'deleted' ? Icons.delete_outline_rounded : Icons.check_circle_rounded,
          size: 16,
          color: info.colorFor(theme.brightness),
        ),
        const SizedBox(width: 6),
        Text('$verb ${formatMoney(e.amount, currency: currency)} · ${info.label}', style: theme.textTheme.labelMedium),
      ]),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Orb(size: 36, mode: OrbMode.thinking),
            const SizedBox(width: 8),
            Text('Thinking…', style: theme.textTheme.bodyMedium),
          ]),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = CalmTokens.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send',
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.4,
        duration: Motion.of(context, Motion.short),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: t.accent,
              boxShadow: [BoxShadow(color: t.glow, blurRadius: 14)],
            ),
            child: Icon(Icons.arrow_upward_rounded, color: Theme.of(context).colorScheme.onPrimary),
          ),
        ),
      ),
    );
  }
}
