import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/app_error.dart';
import '../logging/sync_logger.dart';
import 'auth_token_provider.dart';

/// Supabase Auth + Google OAuth for web.
/// Uses `session.providerToken` to get a Google access token for Drive API.
///
/// Note: `signInWithOAuth` triggers a browser redirect.
/// After the redirect, Supabase restores the session automatically.
/// The `providerToken` (Google access token) is available only after
/// the redirect callback and expires after ~1 hour.
class SupabaseAuthService implements AuthTokenProvider {
  final SyncLogger _logger;

  SupabaseAuthService({required SyncLogger logger}) : _logger = logger;

  SupabaseClient get _client => Supabase.instance.client;

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

  /// Get the Google provider token from the Supabase session.
  /// This is the Google access token needed for Drive API calls.
  ///
  /// The provider token is only available immediately after OAuth sign-in
  /// and expires after ~1 hour. If expired, re-authentication is required.
  @override
  Future<String> getAccessToken() async {
    final session = _client.auth.currentSession;

    if (session == null) {
      throw const AppError(
        AppErrorCode.authRequired,
        'No active session. Please sign in.',
      );
    }

    // If the Supabase session itself is expired, try refreshing
    if (session.isExpired) {
      _logger.info('supabase_session_expired_refreshing');
      try {
        await _client.auth.refreshSession();
      } catch (e) {
        _logger.error('supabase_session_refresh_failed', {
          'error': e.toString(),
        });
        throw AppError(
          AppErrorCode.tokenExpired,
          'Session expired and refresh failed. Please sign in again.',
          e,
        );
      }
    }

    final refreshedSession = _client.auth.currentSession;
    if (refreshedSession == null) {
      throw const AppError(
        AppErrorCode.authRequired,
        'Session lost after refresh.',
      );
    }

    final providerToken = refreshedSession.providerToken;
    if (providerToken == null) {
      // Provider token is only set at initial OAuth sign-in.
      // It is NOT refreshed by Supabase session refresh.
      throw const AppError(
        AppErrorCode.tokenExpired,
        'Google provider token not available. '
            'Re-authentication required (provider tokens expire after ~1 hour).',
      );
    }

    return providerToken;
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
