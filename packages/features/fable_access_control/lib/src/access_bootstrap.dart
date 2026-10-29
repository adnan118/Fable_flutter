import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fable_core/fable_core.dart';
import 'access_policy.dart';
import 'access_repository.dart';
import 'access_session.dart';

/// Optional app-level wiring: Fable and Other backends share the same UI gate.
/// Only verified, contract-bound snapshots ever grant visibility.
/// This widget is generated ONLY when `access_control` is selected.
class FableAccessBootstrap extends StatefulWidget {
  const FableAccessBootstrap({super.key, this.fableContract,
    this.externalCatalog, required this.child});
  final FableContract? fableContract;
  final ExternalOperationCatalog? externalCatalog;
  final Widget child;

  @override
  State<FableAccessBootstrap> createState() => _FableAccessBootstrapState();
}

class _AccessRuntime {
  _AccessRuntime(this.policy, this.session, this.gateway);
  final FableAccessPolicy policy;
  final FableAccessSession session;
  final BackendApiGateway gateway;
  void dispose() { session.dispose(); gateway.dispose(); }
}

class _FableAccessBootstrapState extends State<FableAccessBootstrap>
    with WidgetsBindingObserver {
  _AccessRuntime? _active;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void didUpdateWidget(covariant FableAccessBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.fableContract, oldWidget.fableContract) ||
        !identical(widget.externalCatalog, oldWidget.externalCatalog)) {
      _setup();
    }
  }

  /// Compare against the verified catalog, not an untrusted policy fingerprint.
  /// Any missing or stale manifest results in NO private grants.
  Future<String> _fingerprint() async {
    final fable = widget.fableContract;
    if (fable != null) {
      var coreHash = '';
      try {
        final json = jsonDecode(await rootBundle.loadString(
          'assets/contracts/mobile-core-operations.json'));
        if (json is! Map || json['backendContractHash'] != fable.contractHash ||
            json['operationsHash'] is! String) {
          throw const FormatException('Invalid mobile core hash');
        }
        coreHash = json['operationsHash'] as String;
      } on FlutterError { /* optional Fable core operations export */ }
      return '${fable.contractHash}:$coreHash';
    }
    final external = widget.externalCatalog!;
    final payload = <String, dynamic>{
      'adapter': external.adapter, 'sourceHash': external.sourceHash,
      'operationsHash': external.operationsHash,
      'baseUrl': external.baseUri.toString(),
    };
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  Future<void> _setup() async {
    final generation = ++_revision;
    final previous = _active;
    _active = null;
    previous?.dispose();
    if (mounted) setState(() {});
    BackendApiGateway? gateway;
    _AccessRuntime? pendingRuntime;
    try {
      if ((widget.fableContract == null) == (widget.externalCatalog == null)) return;
      final manifestRaw = jsonDecode(await rootBundle.loadString(
          'assets/contracts/access-policy.json'));
      if (manifestRaw is! Map<String, dynamic>) throw const FormatException('Invalid policy');
      final policy = FableAccessPolicy.fromManifest(manifestRaw,
          expectedFingerprint: await _fingerprint());
      final catalog = widget.fableContract ?? widget.externalCatalog!;
      if (policy.provider != (widget.fableContract != null ? 'fable' : 'other')) {
        throw const FormatException('Policy provider does not match backend');
      }
      for (final entry in policy.operationModes.entries) {
        if (!catalog.supports(entry.key) ||
            (entry.value == 'public' && catalog.require(entry.key).requiresAuth) ||
            (entry.value != 'public' && !catalog.require(entry.key).requiresAuth)) {
          throw const FormatException('Policy operation differs from catalog');
        }
      }
      FableSecureSession credentials;
      if (widget.fableContract != null) {
        const base = String.fromEnvironment('FABLE_API_BASE_URL');
        if (base.isEmpty) return; // Never invent an API host.
        final auth = FableAuthGateway(baseUri: Uri.parse(base),
          contract: widget.fableContract!,
          allowHttpForLocalDevelopment: kDebugMode);
        credentials = auth.session;
        gateway = auth;
      } else {
        final external = widget.externalCatalog!;
        final mapped = await ExternalAuthBinding.loadOptional(rootBundle, external);
        if (mapped != null) {
          final auth = ExternalAuthGateway(catalog: external, mapping: mapped,
              allowHttpForLocalDevelopment: kDebugMode);
          credentials = auth.session;
          gateway = auth;
        } else {
          credentials = ExternalAuthGateway.secureSessionFor(external);
          gateway = ExternalApiGateway(catalog: external, session: credentials,
              allowHttpForLocalDevelopment: kDebugMode);
        }
      }
      if (manifestRaw['snapshot'] is Map) {
        final access = FableAccessSession(FableAccessRepository.fromPolicy(gateway, manifestRaw));
        pendingRuntime = _AccessRuntime(policy, access, gateway);
        if (!mounted || generation != _revision) { pendingRuntime.dispose(); return; }
        _active = pendingRuntime;
        setState(() {});
        // Waiting for verified `/permissions/me` does not show stale grants.
        await access.bindToCredentials(credentials);
      } else {
        // Public operations may be rendered; private grants are never guessed.
        final missingSnapshot = FableAccessSession(
            FableAccessRepository(gateway, operationId: ''));
        pendingRuntime = _AccessRuntime(policy, missingSnapshot, gateway);
        if (!mounted || generation != _revision) { pendingRuntime.dispose(); return; }
        _active = pendingRuntime;
        setState(() {});
      }
    } catch (_) {
      // Any provider/contract/storage failure is fail-closed. Dispose even if
      // credential binding threw AFTER publishing the pending runtime.
      if (identical(_active, pendingRuntime)) _active = null;
      if (pendingRuntime != null) { pendingRuntime.dispose(); }
      else { gateway?.dispose(); }
      if (mounted && generation == _revision) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active?.session.onForeground().catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    if (active == null) return widget.child;
    return FableAccessScope(policy: active.policy,
        snapshot: active.session, child: widget.child);
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    _active?.dispose();
    super.dispose();
  }
}
