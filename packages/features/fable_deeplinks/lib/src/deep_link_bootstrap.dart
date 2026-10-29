import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'deep_link_policy.dart';
import 'deep_link_dispatcher.dart';

/// Cold start + foreground links. A malformed/unverified URL is ignored.
/// The native iOS/Android association must separately validate the domain.
class FableDeepLinksBootstrap extends StatefulWidget {
  const FableDeepLinksBootstrap({super.key, required this.child});
  final Widget child;
  @override
  State<FableDeepLinksBootstrap> createState() => _FableDeepLinksBootstrapState();
}
class _FableDeepLinksBootstrapState extends State<FableDeepLinksBootstrap> {
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _subscription;
  FableDeepLinkPolicy? _policy;
  String? _last;
  DateTime? _lastAt;
  bool _closed = false;
  @override
  void initState() { super.initState(); unawaited(_init()); }

  Future<void> _init() async {
    try {
      final raw = await rootBundle.loadString('assets/config/deep-links.json');
      final policy = FableDeepLinkPolicy.fromJson(raw);
      if (!mounted || _closed) return;
      _policy = policy;
      final links = AppLinks();
      _appLinks = links;
      // Subscribe first to avoid dropping links received while loading initial intent.
      _subscription = links.uriLinkStream.listen((link) => unawaited(_route(link)),
        onError:(Object err, StackTrace trace) => debugPrint('Deep link delivery failed: $err'));
      final initial = await links.getInitialLink();
      if (initial != null) await _route(initial);
    } catch (error) {
      debugPrint('Deep links disabled due to invalid configuration: $error');
    }
  }
  Future<void> _route(Uri link) async {
    if (_closed || !mounted || !(_policy?.accepts(link) ?? false)) return;
    final now = DateTime.now();
    if (_last == link.toString() && _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds:2)) return;
    _last = link.toString(); _lastAt = now;
    try { await FableDeepLinkDispatcher.instance.dispatch(link); }
    catch (err) {debugPrint('Deep link route unavailable: $err');}
  }
  @override
  void dispose() { _closed = true; unawaited(_subscription?.cancel()); super.dispose(); }
  @override
  Widget build(BuildContext context) => widget.child;
}
