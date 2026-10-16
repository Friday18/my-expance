import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  bool _showEmail = false;
  bool _register = false;
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitEmail() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    await _run(() => _register
        ? auth.registerWithEmail(_email.text, _password.text)
        : auth.signInWithEmail(_email.text, _password.text));
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your email first.')));
      return;
    }
    final auth = context.read<AuthService>();
    await _run(() async {
      await auth.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset link sent to $email')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.read<AuthService>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset('assets/icon/icon.png', width: 88, height: 88,
                      errorBuilder: (_, __, ___) => const SizedBox(height: 88)),
                ),
                const SizedBox(height: 20),
                Text('My Expance', style: theme.textTheme.displaySmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Say "spent 450 on lunch" and it\'s logged.',
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                if (auth.devMode) ...[
                  FilledButton.icon(
                    onPressed: auth.devSignIn,
                    icon: const Icon(Icons.developer_mode_rounded),
                    label: const Text('Continue as developer'),
                  ),
                  const SizedBox(height: 8),
                  Text('DEV_AUTH is on. Firebase is skipped.',
                      style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                ] else ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(() async => auth.signInWithGoogle()),
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                    label: const Text('Continue with Google'),
                  ),
                  if (Platform.isIOS) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                        foregroundColor: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
                      ),
                      onPressed: _busy ? null : () => _run(auth.signInWithApple),
                      icon: const Icon(Icons.apple_rounded),
                      label: const Text('Continue with Apple'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => setState(() => _showEmail = !_showEmail),
                    icon: const Icon(Icons.mail_outline_rounded),
                    label: const Text('Continue with email'),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    child: !_showEmail ? const SizedBox(width: double.infinity) : _emailForm(theme),
                  ),
                ],
                if (_busy) const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailForm(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (v) => (v ?? '').length >= 6 ? null : 'At least 6 characters',
              onFieldSubmitted: (_) => _submitEmail(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submitEmail,
              child: Text(_register ? 'Create account' : 'Sign in'),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              TextButton(
                onPressed: () => setState(() => _register = !_register),
                child: Text(_register ? 'I have an account' : 'Create an account'),
              ),
              if (!_register) TextButton(onPressed: _resetPassword, child: const Text('Forgot password?')),
            ]),
          ]),
        ),
      ),
    );
  }
}
