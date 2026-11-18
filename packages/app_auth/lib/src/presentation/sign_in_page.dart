import 'package:app_auth/src/presentation/auth_providers.dart';
import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Email and password sign-in. A placeholder flow for development and tests;
/// Sign in with Apple and Google land in the auth feature thread.
///
// TODO(auth): move strings to localization once modules share l10n.
class SignInPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _createAccount = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() => ref
      .read(signInControllerProvider.notifier)
      .submit(
        email: _email.text.trim(),
        password: _password.text,
        createAccount: _createAccount,
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signInControllerProvider);
    final tokens = context.tokens;
    final error = state.error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _createAccount ? 'Create your account' : 'Welcome back',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    key: const Key('signIn_email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const Key('signIn_password'),
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _messageFor(error),
                      key: const Key('signIn_error'),
                      style: TextStyle(color: tokens.danger),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: _createAccount ? 'Create account' : 'Sign in',
                    loading: state.isLoading,
                    onPressed: _submit,
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _createAccount = !_createAccount),
                    child: Text(
                      _createAccount
                          ? 'I already have an account'
                          : 'Create an account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _messageFor(Object error) => switch (error) {
    NetworkException() => 'No connection. Check your internet and try again.',
    ValidationException(:final message) => message,
    UnauthorizedException() => 'That email and password did not match.',
    _ => 'Something went wrong. Please try again.',
  };
}
