import 'package:app_auth/src/domain/auth_repository.dart';
import 'package:app_auth/src/presentation/auth_providers.dart';
import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// The first screen: the 3D body, the promise, and one-tap Apple and Google
/// sign-in, with email behind "Continue with email". Laid out like the
/// Onboarding board on the design canvas.
///
/// The app passes [hero] (the 3D body preview) and [wordmark], so this module
/// needs no other module.
///
// TODO(auth): move strings to localization once modules share l10n.
class SignInPage extends ConsumerStatefulWidget {
  const new({this.hero, this.wordmark, super.key});

  /// Shown behind the wordmark at the top, until the email form opens.
  final Widget? hero;
  final String? wordmark;

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _createAccount = true;
  bool _showEmail = false;

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

  void _openEmail({required bool createAccount}) => setState(() {
    _showEmail = true;
    _createAccount = createAccount;
  });

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signInControllerProvider);
    final methods =
        ref.watch(signInMethodsProvider).value ?? const {SignInMethod.email};
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final busy = state.isLoading;
    final error = state.error;
    final notice = state.value;

    final String headline;
    final String subline;
    if (!_showEmail) {
      headline = 'See where you lose fat and build muscle.';
      subline = 'Your body in 3D, built from your own scans, region by region.';
    } else if (_createAccount) {
      headline = 'Create your account';
      subline = 'Use at least 8 characters for your password.';
    } else {
      headline = 'Welcome back';
      subline = 'Sign in to see your body and your scans.';
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _showEmail
                    ? _EmailTopBar(
                        wordmark: widget.wordmark,
                        onBack: busy
                            ? null
                            : () => setState(() => _showEmail = false),
                      )
                    : _Hero(hero: widget.hero, wordmark: widget.wordmark),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.xs,
                  AppSpacing.gutter,
                  AppSpacing.lg,
                ),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(headline, style: text.headlineLarge),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        subline,
                        style: text.bodyLarge?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_showEmail)
                        ..._emailForm(busy)
                      else
                        ..._methodButtons(methods, busy),
                      if (error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _messageFor(error),
                          key: const Key('signIn_error'),
                          style: text.bodyMedium?.copyWith(
                            color: tokens.danger,
                          ),
                        ),
                      ],
                      if (notice == SignInNotice.checkYourEmail) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Check your email to confirm your account, '
                          'then sign in.',
                          key: const Key('signIn_notice'),
                          style: text.bodyMedium,
                        ),
                      ],
                      const Spacer(),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Your health data stays private. '
                        'You choose what we store.',
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                          color: tokens.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _methodButtons(Set<SignInMethod> methods, bool busy) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      if (methods.contains(SignInMethod.apple)) ...[
        SizedBox(
          height: 54,
          child: SignInWithAppleButton(
            key: const Key('signIn_apple'),
            onPressed: busy ? () {} : _controller.signInWithApple,
            text: 'Continue with Apple',
            height: 54,
            borderRadius: BorderRadius.circular(AppRadius.md),
            // Apple's guidelines: white on dark, black on light.
            style: dark
                ? SignInWithAppleButtonStyle.white
                : SignInWithAppleButtonStyle.black,
          ),
        ),
        const SizedBox(height: AppSpacing.smd),
      ],
      if (methods.contains(SignInMethod.google)) ...[
        _SecondaryAction(
          key: const Key('signIn_google'),
          label: 'Continue with Google',
          leading: const _GoogleMark(),
          onPressed: busy ? null : _controller.signInWithGoogle,
        ),
        const SizedBox(height: AppSpacing.smd),
      ],
      _SecondaryAction(
        key: const Key('signIn_emailOption'),
        label: 'Continue with email',
        leading: const Icon(Icons.mail_outline, size: 20),
        onPressed: busy ? null : () => _openEmail(createAccount: true),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextButton(
        key: const Key('signIn_haveAccount'),
        onPressed: busy ? null : () => _openEmail(createAccount: false),
        child: const Text('I already have an account'),
      ),
    ];
  }

  List<Widget> _emailForm(bool busy) => [
    TextField(
      key: const Key('signIn_email'),
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(labelText: 'Email'),
    ),
    const SizedBox(height: AppSpacing.smd),
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
      decoration: const InputDecoration(labelText: 'Password'),
      onSubmitted: (_) => _submit(),
    ),
    const SizedBox(height: AppSpacing.lg),
    AppButton(
      key: const Key('signIn_submit'),
      label: _createAccount ? 'Create account' : 'Sign in',
      loading: busy,
      onPressed: _submit,
    ),
    const SizedBox(height: AppSpacing.sm),
    TextButton(
      key: const Key('signIn_toggle'),
      onPressed: busy
          ? null
          : () => setState(() => _createAccount = !_createAccount),
      child: Text(
        _createAccount ? 'I already have an account' : 'Create an account',
      ),
    ),
  ];

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
    ValidationException(code: 'email_address_invalid') =>
      'Enter a valid email address.',
    ValidationException(code: 'over_request_rate_limit') ||
    ValidationException(
      code: 'over_email_send_rate_limit',
    ) => 'Too many attempts. Wait a minute and try again.',
    ValidationException() => 'Check your email and password and try again.',
    _ => 'Something went wrong. Please try again.',
  };
}

/// The wordmark above the 3D body, as on the design canvas.
class _Hero extends StatelessWidget {
  const new({required this.hero, required this.wordmark});

  final Widget? hero;
  final String? wordmark;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 380,
    child: Column(
      children: [
        if (wordmark case final w?)
          SizedBox(
            height: 64,
            child: Center(child: Text(w, style: AppTheme.wordmark)),
          ),
        Expanded(child: hero ?? const SizedBox.shrink()),
      ],
    ),
  );
}

/// Replaces the hero once the email form opens, so the form and keyboard fit.
class _EmailTopBar extends StatelessWidget {
  const new({required this.wordmark, required this.onBack});

  final String? wordmark;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: IconButton(
              key: const Key('signIn_back'),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
          ),
        ),
        if (wordmark case final w?) Text(w, style: AppTheme.wordmark),
      ],
    ),
  );
}

/// The canvas's secondary button with a leading mark.
class _SecondaryAction extends StatelessWidget {
  const new({
    required this.label,
    required this.leading,
    required this.onPressed,
    super.key,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: AppSpacing.smd,
        children: [
          leading,
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    ),
  );
}

/// Google's four-color "G", drawn so no image asset is needed. Its colors are
/// Google's brand colors, required on a Google sign-in button, so they are
/// not app tokens.
class _GoogleMark extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 20,
    child: CustomPaint(painter: _GooglePainter()),
  );
}

class _GooglePainter extends CustomPainter {
  const new();

  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromCircle(
      center: Offset(s / 2, s / 2),
      radius: (s - stroke) / 2,
    );
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = 3.14159265 / 180;
    canvas
      ..drawArc(rect, -40 * deg, -60 * deg, false, arc(_red))
      ..drawArc(rect, -100 * deg, -80 * deg, false, arc(_red))
      ..drawArc(rect, 180 * deg, -50 * deg, false, arc(_yellow))
      ..drawArc(rect, 130 * deg, -90 * deg, false, arc(_green))
      ..drawArc(rect, 40 * deg, -40 * deg, false, arc(_blue))
      ..drawRect(
        Rect.fromLTWH(s / 2, s / 2 - stroke / 2, s / 2 - stroke / 4, stroke),
        Paint()..color = _blue,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
