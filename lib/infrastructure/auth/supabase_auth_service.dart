import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/app_error.dart';
import '../logging/sync_logger.dart';
import 'auth_token_provider.dart';

/// Supabase Auth + Google OAuth for web.
/// Uses `session.providerToken` to get a Google access token for Drive API.
///
/// Provider token lifecycle:
/// 1. Obtained on OAuth redirect (expires after ~1 hour)
/// 2. Cached in memory for reuse within the session
/// 3. On expiry, attempts refresh via Supabase GoTrue
/// 4. If refresh fails, triggers re-authentication
class SupabaseAuthService implements AuthTokenProvider {
  final SyncLogger _logger;

  /// In-memory cache of the Google provider token.
  String? _cachedProviderToken;
  DateTime? _cachedTokenTime;

  SupabaseAuthService({required SyncLogger logger}) : _logger = logger;

  SupabaseClient get _client => Supabase.instance.client;

  /// Cache the provider token when first obtained (e.g. from onAuthStateChange).
  void cacheProviderToken(String token) {
    _cachedProviderToken = token;
    _cachedTokenTime = DateTime.now();
    _logger.info('provider_token_cached');
  }

  /// Sign in with Google via Supabase Auth.
  /// This triggers a browser redirect for OAuth — the page will reload.
  Future<void> ensureAuthenticated() async {
    _logger.info('supabase_auth_check_started');

    final session = _client.auth.currentSession;
    if (session != null && !session.isExpired) {
      _logger.info('supabase_auth_session_valid');
      return;
    }

    // Try to refresh existing session
    try {
      await _client.auth.refreshSession();
      if (_client.auth.currentSession != null) {
        _logger.info('supabase_auth_session_refreshed');
        return;
      }
    } catch (e) {
      _logger.warn('supabase_auth_refresh_failed', {
        'error': e.toString(),
      });
      // Refresh failed, fall through to interactive sign-in
    }

    // Interactive sign-in with Google (triggers browser redirect)
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        scopes: 'https://www.googleapis.com/auth/drive.readonly',
        redirectTo: _getRedirectUrl(),
        queryParams: {
          'prompt': 'consent',
          'access_type': 'offline',
        },
      );
      // Note: execution may not reach here because the browser redirects.
    } catch (e) {
      _logger.error('supabase_auth_sign_in_failed', {'error': e.toString()});
      throw AppError(AppErrorCode.authRequired, 'Google sign-in failed', e);
    }

    _logger.info('supabase_auth_check_completed');
  }

  /// Get the Google provider token for Drive API calls.
  ///
  /// Attempts in order:
  /// 1. Current session's providerToken (set right after OAuth redirect)
  /// 2. Cached in-memory token (within ~55 min of caching)
  /// 3. Refresh session via Supabase GoTrue (may return new providerToken)
  /// 4. Throw tokenExpired → triggers re-authentication
  @override
  Future<String> getAccessToken() async {
    var session = _client.auth.currentSession;

    if (session == null) {
      throw const AppError(
        AppErrorCode.authRequired,
        'No active session. Please sign in.',
      );
    }

    // 1. Session's provider token (available right after OAuth)
    if (session.providerToken != null) {
      cacheProviderToken(session.providerToken!);
      return session.providerToken!;
    }

    // 2. Cached in-memory token (survives within the same page session)
    if (_cachedProviderToken != null && _cachedTokenTime != null) {
      final tokenAge = DateTime.now().difference(_cachedTokenTime!);
      if (tokenAge.inMinutes < 55) {
        _logger.info('using_cached_provider_token', {
          'ageMinutes': tokenAge.inMinutes,
        });
        return _cachedProviderToken!;
      }
      _logger.info('cached_provider_token_expired', {
        'ageMinutes': tokenAge.inMinutes,
      });
      _cachedProviderToken = null;
      _cachedTokenTime = null;
    }

    // 3. Try refreshing via Supabase GoTrue
    _logger.info('provider_token_missing_attempting_refresh');
    try {
      final response = await _client.auth.refreshSession();
      session = response.session;
      if (session?.providerToken != null) {
        _logger.info('provider_token_refreshed_via_gotrue');
        cacheProviderToken(session!.providerToken!);
        return session.providerToken!;
      }
    } catch (e) {
      _logger.warn('session_refresh_failed', {'error': e.toString()});
    }

    // 4. All attempts failed
    throw const AppError(
      AppErrorCode.tokenExpired,
      'Googleトークンの有効期限が切れました。再ログインしてください。',
    );
  }

  @override
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getAccessToken();
    return {'Authorization': 'Bearer $token'};
  }

  /// Sign out from Supabase.
  Future<void> signOut() async {
    _logger.info('supabase_auth_sign_out');
    await _client.auth.signOut();
  }

  /// Check if user is currently signed in.
  bool get isSignedIn => _client.auth.currentUser != null;

  /// Seed default data on first login.
  Future<void> seedIfNeeded() async {
    try {
      await _client.rpc('seed_user_data');
    } catch (e) {
      _logger.warn('seed_user_data_failed', {'error': e.toString()});
    }
  }

  String _getRedirectUrl() {
    // For GitHub Pages deployment, return the current page URL
    final uri = Uri.base;
    return '${uri.scheme}://${uri.host}'
        '${uri.hasPort ? ':${uri.port}' : ''}'
        '${uri.path}';
  }
}
