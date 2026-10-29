import 'dart:async';
import 'package:flutter/widgets.dart';

/// Register a destination once in the project router, not in every button/widget.
/// The backend and the destination remain responsible for authentication and access.
class FableDeepLinkDispatcher {
  FableDeepLinkDispatcher._();
  static final instance = FableDeepLinkDispatcher._();
  final navigatorKey = GlobalKey<NavigatorState>();
  final Map<String, Future<bool> Function(Uri)> _destinations = {};
  Future<bool> Function(Uri)? authorization;
  Uri? _pending;
  int _generation = 0; // Invalidate older asynchronous authorization decisions.

  void register(String prefix, Future<bool> Function(Uri) navigate) {
    if (!prefix.startsWith('/') || prefix.contains('..') || prefix.contains('?')) {
      throw ArgumentError.value(prefix, 'prefix', 'Use absolute safe path prefix');
    }
    _destinations[prefix] = navigate;
  }

  void unregister(String prefix) => _destinations.remove(prefix);

  Future<bool> dispatch(Uri link) async {
    final generation = ++_generation;
    _pending = null; // A newly requested destination supersedes any prior deferral.
    final keys = _destinations.keys.where((prefix) =>
      prefix == '/' || link.path == prefix || link.path.startsWith('$prefix/')).toList()
      ..sort((a,b)=>b.length.compareTo(a.length));
    if (keys.isEmpty) return false; // Unknown route: never open arbitrary pages.
    // Never allow a result for an older link to navigate or overwrite a newer
    // deferred link (for example when switching accounts during an Auth prompt).
    final allowed = authorization == null || await authorization!(link);
    if (generation != _generation) return false;
    if (!allowed) {
      _pending = link; // Re-check authorization before any post-login navigation.
      return false;
    }
    _pending = null;
    return _destinations[keys.first]!(link);
  }

  Future<bool> resumeAfterLogin() async {
    final saved = _pending;
    if (saved == null) return false;
    return dispatch(saved);
  }
  void clearPending() { _generation++; _pending = null; }
}
