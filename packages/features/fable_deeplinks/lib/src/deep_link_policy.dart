import 'dart:convert';

/// An allowlist only: never treat a verified link as an authorization grant.
class FableDeepLinkPolicy {
  const FableDeepLinkPolicy({required this.host, required this.paths});
  final String host;
  final List<String> paths;

  factory FableDeepLinkPolicy.fromJson(String value) {
    final data = jsonDecode(value);
    if (data is! Map<String,dynamic>) throw const FormatException('Invalid link settings');
    final host = data['domain'];
    final hostPattern = RegExp(r'^(?=.{4,253}$)[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$');
    final pathPattern = RegExp(r'^/(?:[a-zA-Z0-9_.~-]+(?:/[a-zA-Z0-9_.~-]+)*)?$');
    final raw = data['paths'];
    if (host is! String || raw is! List || raw.isEmpty ||
        raw.any((x) => x is! String || !pathPattern.hasMatch(x) ||
          x.split('/').contains('..') || x.split('/').contains('.')) ||
        !hostPattern.hasMatch(host)) {
      throw const FormatException('Invalid deep link allowlist');
    }
    return FableDeepLinkPolicy(host: host, paths: raw.cast<String>());
  }

  bool accepts(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasPort ||
        uri.host.toLowerCase() != host.toLowerCase() ||
        uri.pathSegments.any((x) => x == '..' || x == '.')) return false;
    final segments = uri.pathSegments;
    if (uri.toString().length > 2048 || uri.path.contains('//') ||
        RegExp(r'%(?:2e|2f|5c)', caseSensitive: false).hasMatch(uri.toString()) ||
        uri.path.contains('\\')) return false;
    for (final prefix in paths) {
      if (prefix == '/') return true;
      final parts = Uri.parse(prefix).pathSegments;
      if (segments.length >= parts.length &&
          List.generate(parts.length, (i) => segments[i] == parts[i]).every((ok) => ok)) return true;
    }
    return false;
  }
}
