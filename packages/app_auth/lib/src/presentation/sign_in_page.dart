import 'package:app_auth/src/domain/auth_repository.dart';
import 'package:app_auth/src/presentation/auth_providers.dart';
import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Sign in or create an account: Apple and Google first (one tap, where
/// available), then email and password.
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

  SignInController get _controller =>
      ref.read(signInControllerProvider.notifier);

  Future<void> _submit() => _controller.submitEmail(
    email: _email.text.trim(),
    password: _password.text,
    createAccount: _createAccount,
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signInControllerProvider);
    final methods =
        ref.watch(signInMethodsProvider).value ?? const {SignInMethod.email};
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final busy = state.isLoading;
    final error = state.error;
    final notice = state.value;
    final hasSocial =
        methods.contains(SignInMethod.apple) ||
        methods.contains(SignInMethod.google);

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
                    style: textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Track your body composition in 3D, scan by scan.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (methods.contains(SignInMethod.apple)) ...[
                    SizedBox(
                      height: 52,
                      child: SignInWithAppleButton(
                        key: const Key('signIn_apple'),
                        onPressed: busy ? () {} : _controller.signInWithApple,
                        text: 'Continue with Apple',
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        // Apple's guidelines: white on dark, black on light.
                        style: Theme.of(context).brightness == Brightness.dark
                            ? SignInWithAppleButtonStyle.white
                            : SignInWithAppleButtonStyle.black,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (methods.contains(SignInMethod.google)) ...[
                    _OutlinedAction(
                      key: const Key('signIn_google'),
                      label: 'Continue with Google',
                      icon: Icons.g_mobiledata,
                      onPressed: busy ? null : _controller.signInWithGoogle,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (hasSocial) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: Divider(color: tokens.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          child: Text(
                            'or use email',
                            style: TextStyle(color: tokens.textSecondary),
                          ),
                        ),
                        Expanded(child: Divider(color: tokens.border)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  TextField(
                    key: const Key('signIn_email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const Key('signIn_password'),
                    controller: _password,
                    obscureText: true,
                    autofillHints: [
                      if (_createAccount)
                        AutofillHints.newPassword
                      else
                        AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: _createAccount
                          ? 'At least 8 characters'
                          : null,
                    ),
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
                  if (notice == SignInNotice.checkYourEmail) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Check your email to confirm your account, then sign in.',
                      key: const Key('signIn_notice'),
                      style: TextStyle(color: tokens.textPrimary),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const Key('signIn_submit'),
                    label: _createAccount ? 'Create account' : 'Sign in',
                    loading: busy,
                    onPressed: _submit,
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () =>
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
    UnauthorizedException(code: 'invalid_credentials') =>
      'That email and password did not match.',
    UnauthorizedException() => 'Sign-in did not work. Please try again.',
    ValidationException(code: 'weak_password') =>
      'Choose a longer password, at least 8 characters.',
    ValidationException(code: 'user_already_exists' || 'email_exists') =>
      'There is already an account with that email. Try signing in.',
    ValidationException(code: 'email_not_confirmed') =>
      'Confirm your email first. Check your inbox for the link.',
    ValidationException(code: 'validation_failed' || 'email_address_invalid') =>
      'Enter a valid email address.',
    ValidationException(code: 'over_request_rate_limit') ||
    ValidationException(
      code: 'over_email_send_rate_limit',
    ) => 'Too many attempts. Wait a minute and try again.',
    ValidationException() => 'Check your email and password and try again.',
    _ => 'Something went wrong. Please try again.',
  };
}

class _OutlinedAction extends StatelessWidget {
  const new({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 28),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          side: BorderSide(color: tokens.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}
