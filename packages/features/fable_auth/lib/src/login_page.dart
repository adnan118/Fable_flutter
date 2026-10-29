import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';

/// Concrete R2 mobile auth contract consumer, including installation binding.
/// Requires a real reachable generated Fable backend at FABLE_API_BASE_URL.
class FableLoginPage extends StatefulWidget {
  const FableLoginPage({super.key,required this.contract});
  final FableContract contract;
  @override State<FableLoginPage> createState()=>_FableLoginPageState();
}
class _FableLoginPageState extends State<FableLoginPage> {
  final _key=GlobalKey<FormState>();
  final _user=TextEditingController(),_password=TextEditingController(),_otp=TextEditingController();
  FableSecondFactorChallenge? _challenge;
  String? _challengeId;
  String? _preferredChannel;
  bool _busy=false;
  bool _signedIn=false;
  bool _savedSessionAvailable=false;
  String? _message;
  static const _url=String.fromEnvironment('FABLE_API_BASE_URL');
  FableAuthGateway? _gateway;

  @override
  void initState() {
    super.initState();
    // Do not infer a valid server session just because a token is on disk.
    // First surface its presence, then allow explicit verification.
    if (_url.isNotEmpty && widget.contract.supports('auth.login')) {
      _restoreLocalSession();
    }
  }

  Future<void> _restoreLocalSession() async {
    try {
      final client = _client();
      final revision = client.session.identityRevision;
      final token = await client.session.accessToken;
      if (!mounted || client.session.identityRevision != revision || _busy || _signedIn) return;
      if (token != null && token.isNotEmpty) {
        setState(() {
          _savedSessionAvailable = true;
          _message = 'Saved credentials found. Verify the session with the server before continuing.';
        });
      }
    } catch (_) {
      // An inaccessible native storage is not evidence of authentication.
    }
  }

  Future<void> _verifySavedSession() async {
    if (_busy || !_savedSessionAvailable || !widget.contract.supports('auth.sessions')) return;
    setState(() { _busy = true; _message = null; });
    try {
      final client = _client();
      final revision = client.session.identityRevision;
      await client.sessions(); // A protected, contract-declared read.
      if (!mounted || client.session.identityRevision != revision) return;
      setState(() {
        _signedIn = true;
        _savedSessionAvailable = false;
        _message = 'Your saved session was verified by the server.';
      });
    } on FableApiException catch (error) {
      if (!mounted) return;
      final stillStored = await _client().session.accessToken != null;
      if (!mounted) return;
      setState(() {
        _savedSessionAvailable = stillStored;
        _message = error.status == 401
          ? 'Your session has expired. Please sign in again.'
          : 'Unable to verify the saved session. You may retry when connected.';
      });
    } catch (_) {
      if (mounted) setState(() => _message =
          'Session verification is unavailable. Your saved credentials were not deleted.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override void dispose(){_user.dispose();_password.dispose();_otp.dispose();_gateway?.dispose();super.dispose();}
  FableAuthGateway _client() => _gateway ??= FableAuthGateway(
    baseUri: Uri.parse(_url),
    contract: widget.contract,
    allowHttpForLocalDevelopment: kDebugMode,
  );

  Future<void> _login() async {
    if (_busy || !_key.currentState!.validate()) return;
    if (!widget.contract.supports('auth.login')) {
      setState(() => _message = 'Login operation missing from imported backend contract.');
      return;
    }
    if (_url.isEmpty) {
      setState(() => _message = 'Set FABLE_API_BASE_URL at build/run time.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      final result = await _client().login(
        identifier: _user.text,
        password: _password.text,
        platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      );
      if (!mounted) return;
      if (result.requiresTwoFactor) {
        final pending=result.secondFactor;
        if(pending==null)throw StateError('Missing pending 2FA challenge');
        final methods=pending.methods;
        final channel=methods.contains('EMAIL_OTP')?'EMAIL':
          methods.contains('PHONE_OTP')?'PHONE':null;
        _password.clear();
        setState(() {
          _challenge=pending;_challengeId=null;_preferredChannel=channel;
          _message=widget.contract.supports('auth.2fa.login.request') &&
              widget.contract.supports('auth.2fa.login.complete')
            ? 'Choose your verification channel and request a one-time code.'
            : 'Login requires 2FA; import a verified Fable contract containing both 2FA operations.';
        });
        return;
      }
      if (result.authenticated) {
        _password.clear();
        setState(() { _signedIn = true; _savedSessionAvailable = false; _message = 'Session saved securely.'; });
      }
    } on FableApiException catch (error) {
      if (mounted) setState(() => _message = 'Server rejected login: ${error.code}');
    } catch (_) {
      if (mounted) setState(() => _message = 'Sign-in failed. Check contract and backend connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestCode() async {
    final pending=_challenge;
    if(_busy||pending==null)return;
    setState(() {_busy=true;_message=null;});
    try {
      final id=await _client().requestSecondFactor(pending,preferredChannel:_preferredChannel);
      if(mounted)setState(() {_challengeId=id;_message='A one-time code was requested. Enter it to finish sign-in.';});
    }on FableApiException catch(error){
      if(mounted)setState(()=>_message='Verification request rejected: ${error.code}');
    }catch(_){
      if(mounted)setState(()=>_message='Verification could not start. Check the backend contract or network.');
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _completeCode() async {
    final pending=_challenge,id=_challengeId;
    if(_busy||pending==null||id==null||!RegExp(r'^\d{4,10}$').hasMatch(_otp.text.trim()))return;
    setState(() {_busy=true;_message=null;});
    try {
      await _client().completeSecondFactor(pending,challengeId:id,code:_otp.text.trim());
      if(mounted)setState(() {
        _otp.clear();_challenge=null;_challengeId=null;_signedIn=true;_savedSessionAvailable=false;
        _message='Two-factor sign-in completed. Session saved securely.';
      });
    }on FableApiException catch(error){
      if(mounted)setState(()=>_message='Verification rejected: ${error.code}');
    }catch(_){
      if(mounted)setState(()=>_message='Unable to complete verification. Please check your code and connection.');
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  void _cancelChallenge(){
    _otp.clear();_password.clear();
    setState((){_challenge=null;_challengeId=null;_preferredChannel=null;_message=null;});
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      final confirmed = await _client().logout();
      if (mounted) setState(() {
        _signedIn = false;
        _savedSessionAvailable = false;
        _message = confirmed
            ? 'Signed out of this session.'
            : 'Local credentials removed. Server revocation could not be confirmed.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override Widget build(BuildContext context){
    final enabled=widget.contract.supports('auth.login');
    return Scaffold(appBar:AppBar(title:const Text('Sign in')),body:SafeArea(child:Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:470),child:ListView(padding:const EdgeInsets.all(24),children:[
        const Icon(Icons.lock_outline,size:48),const SizedBox(height:24),
        Text(enabled?'Fable account':'Login contract missing',style:Theme.of(context).textTheme.headlineSmall),
        if (_signedIn) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
          child: FilledButton.tonal(onPressed:_busy?null:_logout,child:const Text('Sign out'))),
        if (_savedSessionAvailable && !_signedIn) ...[
          const SizedBox(height: 12),
          const Text('A stored session has not yet been verified.', textAlign: TextAlign.center),
          if (widget.contract.supports('auth.sessions'))
            OutlinedButton(onPressed: _busy ? null : _verifySavedSession,
              child: const Text('Verify saved session')),
          TextButton(onPressed: _busy ? null : _logout, child: const Text('Discard saved session')),
        ],
        if (!_signedIn) const SizedBox(height:18),
        if (!_signedIn && _challenge!=null) Column(children:[
          const Text('Second-factor verification'),const SizedBox(height:12),
          if (_challenge!.methods.length>1) DropdownButtonFormField<String>(
            value:_preferredChannel,
            decoration:const InputDecoration(labelText:'Verification channel'),
            items:[
              if(_challenge!.methods.contains('EMAIL_OTP'))const DropdownMenuItem(value:'EMAIL',child:Text('Email')),
              if(_challenge!.methods.contains('PHONE_OTP'))const DropdownMenuItem(value:'PHONE',child:Text('Phone')),
            ],
            onChanged:_busy?null:(value)=>setState((){_preferredChannel=value;_challengeId=null;}),
          ),
          const SizedBox(height:12),
          FilledButton.tonal(onPressed:!_busy&&widget.contract.supports('auth.2fa.login.request')&&
            widget.contract.supports('auth.2fa.login.complete')?_requestCode:null,
            child:const Text('Request verification code')),
          if(_challengeId!=null) ...[
            const SizedBox(height:12),
            TextField(controller:_otp,keyboardType:TextInputType.number,
              autofillHints:const [AutofillHints.oneTimeCode],maxLength:10,
              decoration:const InputDecoration(labelText:'One-time code')),
            FilledButton(onPressed:_busy?null:_completeCode,child:const Text('Verify and sign in')),
          ],
          TextButton(onPressed:_busy?null:_cancelChallenge,child:const Text('Cancel sign-in')),
        ]),
        if (!_signedIn && _challenge==null) Form(key:_key,child:Column(children:[
          TextFormField(controller:_user,autovalidateMode:AutovalidateMode.onUserInteraction,
            autofillHints:const [AutofillHints.username],maxLength:191,
            decoration:const InputDecoration(labelText:'Email / username / phone'),
            validator:(value)=>FableValidation.message(FableValidation.requiredText(value,max:191),
              languageCode:Localizations.localeOf(context).languageCode)),
          const SizedBox(height:12),TextFormField(controller:_password,obscureText:true,
            enableSuggestions:false,autocorrect:false,maxLength:128,
            autofillHints:const [AutofillHints.password],
            decoration:const InputDecoration(labelText:'Password'),
            validator:(value)=>FableValidation.message(FableValidation.requiredText(value,max:128),
              languageCode:Localizations.localeOf(context).languageCode)),
          const SizedBox(height:22),FilledButton(onPressed:enabled&&!_busy?_login:null,
            child:_busy?const SizedBox(height:18,width:18,child:CircularProgressIndicator(strokeWidth:2)):
              const Text('Sign in')),
        ])),
        if(_message!=null)Padding(padding:const EdgeInsets.only(top:20),child:Text(_message!,textAlign:TextAlign.center)),
        if(_url.isEmpty)const Padding(padding:EdgeInsets.only(top:14),child:Text(
          'Configure with --dart-define=FABLE_API_BASE_URL=https://your-api.example',textAlign:TextAlign.center)),
      ])))));
  }
}
