/// Auth module. Depends only on app_core and app_ui; the app supplies the
/// Supabase client by overriding `authRepositoryProvider`.
library;

export 'src/data/apple_id_token_provider.dart';
export 'src/data/google_id_token_provider.dart';
export 'src/data/supabase_auth_repository.dart';
export 'src/domain/auth_repository.dart';
export 'src/domain/auth_user.dart';
export 'src/domain/id_token_provider.dart';
export 'src/presentation/auth_providers.dart';
export 'src/presentation/sign_in_page.dart';
