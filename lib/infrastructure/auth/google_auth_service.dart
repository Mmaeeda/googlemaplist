import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/models/app_error.dart';
import '../logging/sync_logger.dart';
import 'auth_token_provider.dart';

/// Manages Google OAuth 2.0 authentication for Drive API access.
class GoogleAuthService implements AuthTokenProvider {
  static const _scopes = [
    'https://www.googleapis.com/auth/drive.readonly',
  ];

  static const _tokenKey = 'google_access_token';
  static const _refreshTokenKey = 'google_refresh_token';
  static const _expiryKey = 'google_token_expiry';

  final GoogleSignIn _googleSignIn;
  final FlutterSecureStorage _secureStorage;
  final SyncLogger _logger;

  GoogleSignInAccount? _currentUser;

  GoogleAuthService({
    GoogleSignIn? googleSignIn,
    FlutterSecureStorage? secureStorage,
    required SyncLogger logger,
  })  : _googleSignIn = googleSignIn ??
            GoogleSignIn(scopes: _scopes),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _logger = logger;

  /// Ensure the user is authenticated and tokens are valid.
  /// Throws [AppError] with AUTH_REQUIRED if sign-in fails.
  Future<void> ensureAuthenticated() async {
    _logger.info('auth_check_started');

    // Try silent sign-in first
    _currentUser = await _googleSignIn.signInSilently();

    if (_currentUser == null) {
      // Interactive sign-in required
      try {
        _currentUser = await _googleSignIn.signIn();
      } catch (e) {
        _logger.error('auth_sign_in_failed', {'error': e.toString()});
        throw AppError(
          AppErrorCode.authRequired,
          'Google sign-in failed',
          e,
        );
      }
    }

    if (_currentUser == null) {
      throw const AppError(
        AppErrorCode.authRequired,
        'User cancelled sign-in',
      );
    }

    // Get and store auth tokens
    await _refreshAndStoreTokens();
    _logger.info('auth_check_completed');
  }

  /// Get a valid authentication header for API calls.
  @override
  Future<Map<String, String>> getAuthHeaders() async {
    if (_currentUser == null) {
      await ensureAuthenticated();
    }

    final auth = await _currentUser!.authentication;
    final accessToken = auth.accessToken;

    if (accessToken == null) {
      throw const AppError(
        AppErrorCode.tokenExpired,
        'Access token is null',
      );
    }

    return {'Authorization': 'Bearer $accessToken'};
  }

  /// Get the current access token string.
  @override
  Future<String> getAccessToken() async {
    if (_currentUser == null) {
      await ensureAuthenticated();
    }

    final auth = await _currentUser!.authentication;
    final accessToken = auth.accessToken;

    if (accessToken == null) {
      // Try to refresh
      await _refreshAndStoreTokens();
      final refreshedAuth = await _currentUser!.authentication;
      final refreshedToken = refreshedAuth.accessToken;
      if (refreshedToken == null) {
        throw const AppError(
          AppErrorCode.tokenExpired,
          'Cannot obtain access token after refresh',
        );
      }
      return refreshedToken;
    }

    return accessToken;
  }

  /// Sign out and clear stored tokens.
  Future<void> signOut() async {
    _logger.info('auth_sign_out');
    await _googleSignIn.signOut();
    _currentUser = null;
    await _clearStoredTokens();
  }

  /// Check if user is currently signed in (without triggering sign-in flow).
  Future<bool> isSignedIn() async {
    return _googleSignIn.isSignedIn();
  }

  Future<void> _refreshAndStoreTokens() async {
    try {
      final auth = await _currentUser!.authentication;
      if (auth.accessToken != null) {
        await _secureStorage.write(key: _tokenKey, value: auth.accessToken);
      }
      // Store expiry estimate (1 hour from now as Google tokens are typically 1h)
      final expiry =
          DateTime.now().add(const Duration(hours: 1)).toIso8601String();
      await _secureStorage.write(key: _expiryKey, value: expiry);
    } catch (e) {
      _logger.warn('token_store_failed', {'error': e.toString()});
    }
  }

  Future<void> _clearStoredTokens() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _expiryKey);
  }
}
