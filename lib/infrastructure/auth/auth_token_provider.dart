/// Abstract interface for obtaining auth tokens.
/// Both GoogleAuthService (native) and SupabaseAuthService (web) implement this.
abstract class AuthTokenProvider {
  Future<Map<String, String>> getAuthHeaders();
  Future<String> getAccessToken();
}
