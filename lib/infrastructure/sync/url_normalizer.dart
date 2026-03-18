/// Normalizes URLs for stable source_key generation.
class UrlNormalizer {
  /// Tracking query parameters that should be removed.
  static const _trackingParams = {
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_term',
    'utm_content',
    'fbclid',
    'gclid',
    'ref',
    'share',
  };

  /// Normalize a URL for consistent hashing.
  static String normalize(String url) {
    var normalized = url.trim();

    // Decode percent-encoded characters that are safe to decode
    normalized = _safeDecode(normalized);

    // Parse the URL
    final uri = Uri.tryParse(normalized);
    if (uri == null) return normalized;

    // Upgrade http to https
    var scheme = uri.scheme;
    if (scheme == 'http') {
      scheme = 'https';
    }

    // Lowercase host
    final host = uri.host.toLowerCase();

    // Remove trailing slash from path
    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    // Remove tracking query parameters, keep place-relevant ones
    final filteredParams = <String, String>{};
    uri.queryParameters.forEach((key, value) {
      if (!_trackingParams.contains(key.toLowerCase())) {
        filteredParams[key] = value;
      }
    });

    // Rebuild URL
    final newUri = Uri(
      scheme: scheme,
      host: host,
      port: uri.hasPort && uri.port != 443 && uri.port != 80 ? uri.port : null,
      path: path,
      queryParameters: filteredParams.isNotEmpty ? filteredParams : null,
      fragment: null, // Remove fragment
    );

    return newUri.toString();
  }

  static String _safeDecode(String url) {
    try {
      return Uri.decodeFull(url);
    } catch (_) {
      return url;
    }
  }
}
