import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';

/// RC94 Username settings for Fable Backend only.
/// Availability is advisory; the PATCH response is authoritative.
class FableUsernameSettingsPage extends StatefulWidget {
  const FableUsernameSettingsPage({super.key, required this.gateway});
  final FableAuthGateway gateway;
  @override State<FableUsernameSettingsPage> createState() => _UsernameState();
}

class _UsernameState extends State<FableUsernameSettingsPage> {
  final TextEditingController _value = TextEditingController();
  final TextEditingController _otp = TextEditingController();
  StreamSubscription<FableIdentityEvent>? _identity;
  String? _challengeId, _status;
  bool _busy = false;
  int _revision = 0;

  @override void initState() {
    super.initState();
    _revision = widget.gateway.session.identityRevision;
    _identity = widget.gateway.session.identityEvents.listen((_) {
      if (!mounted) return;
      _otp.clear();
      _challengeId = null;
      _revision = widget.gateway.session.identityRevision;
      setState(() => _status = 'Account changed. Please verify the current user.');
    });
  }

  @override void dispose() {
    unawaited(_identity?.cancel());
    _value.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _availability() async {
    if (_busy || !widget.gateway.canCheckUsernameAvailability) return;
    setState(() => _busy = true);
    try {
      final result = await widget.gateway.checkUsernameAvailability(_value.text);
      if (!mounted || _revision != widget.gateway.session.identityRevision) return;
      setState(() => _status = result.available
        ? 'Available according to Backend; not reserved yet.'
        : 'Username is unavailable.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Availability not confirmed by Backend.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update({FableVerifiedSensitiveProof? proof}) async {
    if (_busy || !widget.gateway.canUpdateUsername) return;
    setState(() => _busy = true);
    try {
      final result = proof == null
        ? await widget.gateway.updateUsername(_value.text)
        : await widget.gateway.updateUsernameWithProof(_value.text, proof);
      if (!mounted || _revision != widget.gateway.session.identityRevision) return;
      setState(() {
        _status = result.changed ? 'Backend confirmed username update.'
          : 'Backend confirmed username unchanged.';
        _challengeId = null;
        _otp.clear();
      });
    } on FableApiException catch (e) {
      if (!mounted || _revision != widget.gateway.session.identityRevision) return;
      setState(() => _status = e.code == 'AUTH_RECENT_AUTH_REQUIRED'
        ? 'A recent authentication proof is required.'
        : e.status == 409
          ? 'Username unavailable or changed in another request.'
          : 'Backend did not confirm username update.');
    } catch (_) {
      if (mounted) setState(() => _status =
        'Update unconfirmed. Re-read account state before retrying.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestProof() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await widget.gateway.requestSensitiveActionOtp();
      if (!mounted || _revision != widget.gateway.session.identityRevision) return;
      setState(() { _challengeId = id; _status = 'Verification challenge created.'; });
    } catch (_) {
      if (mounted) setState(() => _status = 'Verification unavailable.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _verifyAndUpdate() async {
    if (_busy || _challengeId == null) return;
    setState(() => _busy = true);
    FableVerifiedSensitiveProof? proof;
    try {
      final verified = await widget.gateway.verifySensitiveActionOtp(
        _challengeId!, _otp.text.trim());
      // A verified proof is bound to the gateway and current identity.
      proof = verified;
    } catch (_) {
      if (mounted) setState(() => _status = 'Verification rejected or expired.');
    } finally { if (mounted) setState(() => _busy = false); }
    if (proof != null && mounted) await _update(proof:proof);
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Username')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Public username. Backend determines uniqueness and final result.'),
      TextField(controller: _value, maxLength: 30,
        decoration: const InputDecoration(labelText:'Username')),
      if (widget.gateway.canCheckUsernameAvailability)
        OutlinedButton(onPressed:_busy?null:()=>unawaited(_availability()),
          child: const Text('Check availability')),
      if (widget.gateway.canUpdateUsername)
        FilledButton(onPressed:_busy?null:()=>unawaited(_update()),
          child: const Text('Save username')),
      if (widget.gateway.canUpdateUsername && _status == 'A recent authentication proof is required.')
        OutlinedButton(onPressed:_busy?null:()=>unawaited(_requestProof()),
          child: const Text('Verify recent authentication')),
      if (_challengeId != null) ...[
        TextField(controller:_otp, obscureText:true,
          keyboardType:TextInputType.number, maxLength:10,
          decoration: const InputDecoration(labelText:'Security OTP')),
        FilledButton(onPressed:_busy?null:()=>unawaited(_verifyAndUpdate()),
          child:const Text('Verify and save')),
      ],
      if (_busy) const LinearProgressIndicator(),
      if (_status != null) Text(_status!),
    ]),
  );
}
