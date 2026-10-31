import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_design_system/fable_design_system.dart';

/// Backend-agnostic sign-in screen: no guessed HTTP paths or JSON properties.
/// A login mapping must be approved in the CLI before this can connect.
class ExternalLoginPage extends StatefulWidget {
  const ExternalLoginPage({super.key, required this.catalog});
  final ExternalOperationCatalog catalog;
  @override State<ExternalLoginPage> createState() => _ExternalLoginPageState();
}

class _ExternalLoginPageState extends State<ExternalLoginPage> {
  late final Future<ExternalAuthBinding?> _config = ExternalAuthBinding.loadOptional(rootBundle, widget.catalog);
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  FableRememberedIdentifier? _remembered;
  bool _rememberIdentifier=false;
  FableRememberedIdentifier get _credentialHints =>
    _remembered ??= FableRememberedIdentifier(
      backendScope:widget.catalog.baseUri.origin);
  Future<void> _restoreIdentifier() async {
    try {
      final previous=await _credentialHints.load();
      if(!mounted||previous==null)return;
      setState((){_identifier.text=previous;_rememberIdentifier=true;});
    }catch(_){/* No native key store available. */}
  }
  Future<void> _saveIdentifier() async {
    try{
      await _credentialHints.save(
        identifier:_identifier.text,remember:_rememberIdentifier);
    }catch(_){/* UX failure never changes the authenticated session. */}
  }
  bool _busy = false;
  bool _authenticated = false;
  bool _savedSessionAvailable = false;
  String? _message;
  ExternalAuthGateway? _gateway;

  @override
  void initState() {
    super.initState();
    _restoreIdentifier();
    _readSavedSession();
  }

  Future<void> _readSavedSession() async {
    try {
      final binding = await _config;
      if (!mounted || binding == null) return;
      final client = _auth(binding);
      final revision = client.session.identityRevision;
      final token = await client.session.accessToken;
      if (!mounted || client.session.identityRevision != revision || _busy || _authenticated) return;
      if (token != null && token.isNotEmpty) {
        setState(() {
          _savedSessionAvailable = true;
          _message = 'Saved credentials found. This backend has not verified the session yet.';
        });
      }
    } catch (_) {
      // Never interpret an unavailable mapping/storage as authentication.
    }
  }

  ExternalAuthGateway _auth(ExternalAuthBinding config) => _gateway ??=
      ExternalAuthGateway(catalog: widget.catalog, mapping: config);

  Future<void> _login(ExternalAuthBinding config) async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() { _busy = true; _message = null; });
    try {
      await _auth(config).login(identifier: _identifier.text, password: _password.text);
      await _saveIdentifier();
      TextInput.finishAutofillContext(shouldSave:true);
      _password.clear();
      if (mounted) setState(() { _authenticated = true; _savedSessionAvailable = false; _message = 'Signed in securely.'; });
    } on FableApiException catch (e) {
      if (mounted) setState(() => _message = e.status == 401 || e.status == 403
        ? 'Credentials were not accepted.' : 'Unable to reach the sign-in service.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Sign-in failed. Verify the imported contract and field mapping.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _logout(ExternalAuthBinding config) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      final remoteRevoked = await _auth(config).logout();
      if (mounted) setState(() {
        _authenticated = false;
        _savedSessionAvailable = false;
        _message = remoteRevoked
            ? 'Signed out successfully.'
            : 'Signed out locally. Server session revocation could not be confirmed.';
      });
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override void dispose() {
    _gateway?.dispose(); _identifier.dispose(); _password.dispose(); super.dispose();
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account access')),
    body: SafeArea(child: FutureBuilder<ExternalAuthBinding?>(future: _config, builder: (context, result) {
      if (result.connectionState != ConnectionState.done) {
        return const FableStateView(state: FableContentState.loading);
      }
      if (result.hasError || result.data == null) {
        return const FableStateView(state: FableContentState.error,
          message: 'External authentication is not configured. Use Backend Auth Wizard to map login, refresh and logout operations.');
      }
      final config = result.data!;
      return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Icon(Icons.lock_outline, size: 48), const SizedBox(height: 20),
          if (_savedSessionAvailable && !_authenticated) ...[
            const Text('Saved session is unverified. Sign in again to confirm access.',
              textAlign: TextAlign.center),
            TextButton(onPressed: _busy ? null : () => _logout(config),
              child: const Text('Discard saved session')),
          ],
          if (_authenticated) FilledButton.tonal(
            onPressed: _busy ? null : () => _logout(config), child: const Text('Sign out')),
          if (!_authenticated) AutofillGroup(child:Form(key: _form, child: Column(children: [
            TextFormField(controller: _identifier, maxLength: 191,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(labelText: 'Username or email'),
              validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null),
            TextFormField(controller: _password, obscureText: true, maxLength: 256,
              autocorrect: false, enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (value) => value == null || value.isEmpty ? 'Required' : null),
            CheckboxListTile(
              contentPadding:EdgeInsets.zero,
              value:_rememberIdentifier,
              onChanged:_busy?null:(value)=>setState(()=>_rememberIdentifier=value??false),
              title:const Text('Remember my login identifier on this device'),
              subtitle:const Text('Passwords are managed by the operating system.'),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : () => _login(config),
                child: Text(_busy ? 'Connecting…' : 'Sign in')),
          ]))),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 20),
            child: Text(_message!, textAlign: TextAlign.center)),
        ])));
    })),
  );
}
