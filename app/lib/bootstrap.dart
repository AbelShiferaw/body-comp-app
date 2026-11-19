import 'dart:async';
import 'dart:developer' as developer;

import 'package:app_auth/app_auth.dart';
import 'package:app_core/app_core.dart';
import 'package:body_comp/app/app.dart';
import 'package:body_comp/profile/data/supabase_profile_repository.dart';
import 'package:body_comp/profile/presentation/profile_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Starts the app: config, logging, error handlers, backend, then the widget
/// tree. Every `main_<flavor>.dart` calls this; nothing flavor-specific is
/// decided here except through [AppConfig]. [expected] guards against running
/// one flavor's entry point with another flavor's config file.
Future<void> bootstrap(Flavor expected) async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppConfig config;
  try {
    config = AppConfig.fromEnvironment();
    if (config.flavor != expected) {
      throw ConfigException(
        'Config file is for ${config.flavor.name}, '
        'but this is the ${expected.name} entry point',
      );
    }
  } on ConfigException catch (e) {
    // Fail loudly and visibly; a misconfigured build must never limp along.
    runApp(StartupErrorApp(message: e.message));
    return;
  }

  AppLogger.configure(level: config.logLevel, sink: _logSink);
  final log = AppLogger('bootstrap')..info('Starting $config');

  final CrashReporter crashReporter = LoggingCrashReporter();
  FlutterError.onError = (details) {
    unawaited(
      crashReporter.recordError(
        details.exception,
        details.stack,
        reason: details.context?.toDescription(),
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(crashReporter.recordError(error, stack, fatal: true));
    return true;
  };

  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabasePublishableKey,
    debug: false,
  );
  log.info('Supabase ready');
  final client = Supabase.instance.client;

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        crashReporterProvider.overrideWithValue(crashReporter),
        authRepositoryProvider.overrideWithValue(
          SupabaseAuthRepository(
            client,
            apple: const AppleIdTokenProvider(),
            google: GoogleIdTokenProvider(
              webClientId: config.googleWebClientId,
              iosClientId: config.googleIosClientId,
            ),
          ),
        ),
        profileRepositoryProvider.overrideWithValue(
          SupabaseProfileRepository(client),
        ),
      ],
      observers: [_ProviderErrorLogger(crashReporter)],
      child: const App(),
    ),
  );
}

void _logSink(LogRecord record) {
  // dart:developer shows in the IDE and device logs without print().
  developer.log(
    record.message,
    name: record.loggerName,
    level: record.level.value,
    error: record.error,
    stackTrace: record.stackTrace,
    time: record.time,
  );
}

/// Reports provider failures that are not AppExceptions we expect (those are
/// shown in the UI), so bugs inside providers are never silent.
final class _ProviderErrorLogger extends ProviderObserver {
  new(this._reporter);

  final CrashReporter _reporter;

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    if (error is AppException && error is! UnexpectedException) return;
    unawaited(
      _reporter.recordError(
        error,
        stackTrace,
        reason: 'Provider ${context.provider} failed',
      ),
    );
  }
}

/// Shown instead of the app when config is invalid.
class StartupErrorApp extends StatelessWidget {
  const new({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(kReleaseMode ? 'The app could not start.' : message),
        ),
      ),
    ),
  );
}
