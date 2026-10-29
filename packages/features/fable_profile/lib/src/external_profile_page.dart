import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_design_system/fable_design_system.dart';
import 'external_profile_repository.dart';

/// Optional, contract-bound profile for Other Backend.
/// Identity and contract changes are trust boundaries: never display another
/// account's profile and never let a late response repopulate a retired view.
class ExternalProfilePage extends StatefulWidget {
  const ExternalProfilePage({super.key, required this.catalog, required this.bindings});
  final ExternalOperationCatalog catalog;
  final ExternalFeatureBindings bindings;
  @override State<ExternalProfilePage> createState() => _ExternalProfilePageState();
}

class _ExternalProfilePageState extends State<ExternalProfilePage> {
  late Future<ExternalProfileFields> _fields;
  ExternalProfile? _profile;
  String? _error;
  bool _busy = false;
  int _generation = 0;
  ExternalApiGateway? _gateway;
  ExternalAuthGateway? _authGateway;
  FableSecureSession? _session;
  StreamSubscription<FableIdentityEvent>? _identityChanges;

  @override void initState() {
    super.initState();
    _configureBackend();
  }

  void _configureBackend() {
    _fields = ExternalProfileFields.fromAssets(rootBundle, widget.catalog, widget.bindings);
    // Shares the selected Other Backend's secure-storage namespace with Auth;
    // never reuse a Fable session or a session from a different backend origin.
    _session = ExternalAuthGateway.secureSessionFor(widget.catalog);
    _identityChanges = _session!.identityEvents.listen((_) {
      if (!mounted) return;
      // A login, logout or account replacement invalidates both the visible
      // profile and all in-flight requests, before any new profile can load.
      _generation++;
      setState(() { _profile = null; _error = null; _busy = false; });
    });
  }

  bool _current(int generation, int identity, FableSecureSession session) =>
      mounted && generation == _generation && identical(session, _session) &&
      session.identityRevision == identity;

  @override void didUpdateWidget(covariant ExternalProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.catalog, widget.catalog) ||
        !identical(oldWidget.bindings, widget.bindings)) {
      _generation++;
      unawaited(_identityChanges?.cancel());
      _identityChanges = null;
      _gateway?.dispose();
      _authGateway?.dispose();
      _gateway = null;
      _authGateway = null;
      _session = null;
      _profile = null;
      _error = null;
      _busy = false;
      _configureBackend();
    }
  }

  @override void dispose() {
    _generation++;
    unawaited(_identityChanges?.cancel());
    _gateway?.dispose();
    _authGateway?.dispose();
    super.dispose();
  }

  Future<void> _load(ExternalProfileFields fields) async {
    if (_busy) return;
    final generation = _generation;
    final session = _session!;
    final identity = session.identityRevision;
    setState(() { _busy = true; _error = null; });
    try {
      if (_gateway == null) {
        final mapping = await ExternalAuthBinding.loadOptional(rootBundle, widget.catalog);
        if (!_current(generation, identity, session)) return;
        _authGateway = mapping == null ? null : ExternalAuthGateway(
          catalog: widget.catalog, mapping: mapping, secureSession: session);
        _gateway = ExternalApiGateway(catalog: widget.catalog, session: session,
          refreshSession: _authGateway?.refresh);
      }
      final profile = await ExternalProfileRepository(
        gateway: _gateway!, bindings: widget.bindings, fields: fields).read();
      if (_current(generation, identity, session)) {
        setState(() => _profile = profile);
      }
    } on FableApiException catch (error) {
      if (_current(generation, identity, session)) {
        setState(() { _profile = null; _error = error.status == 401
            ? 'Please sign in using your backend authentication adapter first.'
            : 'Unable to load your profile. Check the connection or access permissions.'; });
      }
    } catch (_) {
      if (_current(generation, identity, session)) {
        setState(() { _profile = null; _error =
          'Unable to load the mapped profile safely. Verify API fields and configuration.'; });
      }
    } finally {
      if (_current(generation, identity, session)) setState(() => _busy = false);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: SafeArea(child: FutureBuilder<ExternalProfileFields>(future: _fields, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const FableStateView(state: FableContentState.loading);
      }
      if (snapshot.hasError) {
        return const FableStateView(state: FableContentState.error,
          message: 'Profile field mapping is missing or outdated. Configure it from Fable Mobile Wizard.');
      }
      return ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.account_circle_outlined, size: 62),
        const SizedBox(height: 16),
        if (_profile != null) ...[
          SelectableText(_profile!.displayName, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          if (_profile!.email != null) SelectableText(_profile!.email!, textAlign: TextAlign.center),
        ] else const Text('Your profile has not been loaded yet.', textAlign: TextAlign.center),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 16),
          child: Text(_error!, textAlign: TextAlign.center)),
        const SizedBox(height: 18),
        FilledButton(onPressed: _busy ? null : () => _load(snapshot.data!),
            child: Text(_busy ? 'Loading…' : 'Load profile')),
      ]);
    })),
  );
}
