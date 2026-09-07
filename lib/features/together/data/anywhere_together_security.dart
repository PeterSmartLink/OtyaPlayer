final RegExp _anywhereTogetherTokenPattern = RegExp(r'^[a-f0-9]{48}$');

/// Accepts only the random-token loopback URL produced by
/// [AnywhereTogetherMediaGuest]. The guest player must never be redirected to
/// an arbitrary local or internet HTTP endpoint by room data.
bool isAllowedAnywhereTogetherMediaUri(Uri uri) {
  if (uri.scheme != 'http' ||
      uri.host != '127.0.0.1' ||
      uri.path != '/anywhere-together-media' ||
      uri.userInfo.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      uri.port <= 0 ||
      uri.port > 65535) {
    return false;
  }

  final tokens = uri.queryParametersAll['t'];
  if (tokens == null || tokens.length != 1) return false;
  return _anywhereTogetherTokenPattern.hasMatch(tokens.single);
}
