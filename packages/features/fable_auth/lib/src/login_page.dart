import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'sessions_page.dart';
import 'change_password_page.dart';
import 'password_reset_page.dart';
import 'otp_login_page.dart';

/// شاشة الدخول الخاصة بـFable تعتمد عقد مصادقة الموبايل ومعرّف الجهاز.
/// نجاح هذه الشاشة لا يعني نقل تغيير البريد/الهاتف/كلمة المرور وOTP كلها.
/// لفهم انتقال الحالات: docs/integrations/FLUTTER-BLOC-LEARNING.ar.md
class FableLoginPage extends StatefulWidget {
  const FableLoginPage({super.key,required this.contract,this.gateway,
    this.deviceName,this.appVersion});
  final FableContract contract;
  /// اسم الجهاز اختياري ويُمرره التطبيق فقط بعد موافقة/سياسة خصوصية واضحة.
  /// لا نخترع موديل جهاز أو مدينة من المنطقة الزمنية.
  final String? deviceName;
  /// يُمرر إصدار الحزمة الفعلي من Bootstrap أو --dart-define، لا من Backend.
  final String? appVersion;
  /// حقن Gateway يسهّل Widget tests من دون افتراض URL أو Backend حي.
  /// ملكية هذا المورد تبقى للمستدعي، لذا لا تتخلص منه الشاشة عند الخروج.
  final FableAuthGateway? gateway;
  @override State<FableLoginPage> createState()=>_FableLoginPageState();
}
class _FableLoginPageState extends State<FableLoginPage> {
  final _key=GlobalKey<FormState>();
  final _user=TextEditingController(),_password=TextEditingController(),_otp=TextEditingController();
  FableSecondFactorChallenge? _challenge;
  String? _challengeId;
  DateTime? _otpExpiresAt;
  String? _otpMethod, _otpDestination;
  String? _preferredChannel;
  bool _rememberIdentifier=false;
  FableRememberedIdentifier? _remembered;
  FableRememberedIdentifier get _credentialHints =>
    _remembered ??= FableRememberedIdentifier(backendScope: _url);
  Future<void> _restoreIdentifier() async {
    if(_url.isEmpty)return;
    try{
      final previous=await _credentialHints.load();
      if(!mounted||previous==null)return;
      setState((){_user.text=previous;_rememberIdentifier=true;});
    }catch(_){/* Native secure storage may be unavailable. */}
  }
  Future<void> _saveLoginHint() async {
    // This is optional UX state, never an authentication requirement.
    try {
      await _credentialHints.save(identifier:_user.text,remember:_rememberIdentifier);
    }catch(_){/* A storage failure must not invalidate a valid server session. */}
  }
  bool _busy=false;
  bool _signedIn=false;
  bool _passwordChangeRequired=false;
  bool _savedSessionAvailable=false;
  String? _message;
  static const _url=String.fromEnvironment('FABLE_API_BASE_URL');
  FableAuthGateway? _gateway;

  @override
  void initState() {
    super.initState();
    _restoreIdentifier();
    // Do not infer a valid server session just because a token is on disk.
    // First surface its presence, then allow explicit verification.
    if ((_url.isNotEmpty || widget.gateway!=null) && widget.contract.supports('auth.login')) {
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
    final client=_client();
    final revision=client.session.identityRevision;
    setState(() { _busy=true; _message=null; });
    try {
      await client.sessions(); // قراءة موثّقة من الخادم، لا من ذاكرة الجهاز.
      if(!mounted || client.session.identityRevision!=revision)return;
      setState(() {
        _signedIn=true;_passwordChangeRequired=false;_savedSessionAvailable=false;
        _message='Your saved session was verified by the server.';
      });
    } on FableApiException catch(error) {
      // 403 لهذا الكود لا تعني انتهاء التوكن؛ الخادم يسمح بتغيير
      // كلمة المرور أو Logout فقط. لا نحذف الاعتماد ولا نعرض Sessions.
      if(error.status==403 && error.code=='AUTH_PASSWORD_CHANGE_REQUIRED'){
        final stillStored=await client.session.accessToken;
        if(!mounted || client.session.identityRevision!=revision)return;
        if(stillStored!=null && stillStored.isNotEmpty){
          setState((){
            _signedIn=true;_passwordChangeRequired=true;_savedSessionAvailable=false;
            _message='You must change your password before using this account.';
          });
          return;
        }
      }
      final stillStored=await client.session.accessToken;
      if(!mounted || client.session.identityRevision!=revision)return;
      setState(() {
        _savedSessionAvailable=stillStored!=null;
        _message=error.status==401
          ? 'Your session has expired. Please sign in again.'
          : 'Unable to verify the saved session. You may retry when connected.';
      });
    } catch (_) {
      if(mounted && client.session.identityRevision==revision)
        setState(()=>_message=
          'Session verification is unavailable. Your saved credentials were not deleted.');
    } finally {
      // A different session may become active while verification is in flight.
      // Reset the local busy flag even when its obsolete result is discarded.
      if(mounted)setState(()=>_busy=false);
    }
  }
  @override void dispose(){_user.dispose();_password.dispose();_otp.dispose();_gateway?.dispose();super.dispose();}
  FableAuthGateway _client() => widget.gateway ?? (_gateway ??= FableAuthGateway(
    baseUri: Uri.parse(_url),
    contract: widget.contract,
    allowHttpForLocalDevelopment: kDebugMode,
  ));

  Future<void> _login() async {
    if (_busy || !_key.currentState!.validate()) return;
    if (!widget.contract.supports('auth.login')) {
      setState(() => _message = 'Login operation missing from imported backend contract.');
      return;
    }
    if (_url.isEmpty && widget.gateway==null) {
      setState(() => _message = 'Set FABLE_API_BASE_URL at build/run time.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      final result = await _client().login(
        identifier: _user.text,
        password: _password.text,
        platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        deviceName:widget.deviceName,
        appVersion:widget.appVersion ??
          (const String.fromEnvironment('FABLE_APP_VERSION').isEmpty
            ? null:const String.fromEnvironment('FABLE_APP_VERSION')),
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
          _challenge=pending;_challengeId=null;_otpExpiresAt=null;
          _otpMethod=null;_otpDestination=null;_preferredChannel=channel;
          _message=widget.contract.supports('auth.2fa.login.request') &&
              widget.contract.supports('auth.2fa.login.complete')
            ? 'Choose your verification channel and request a one-time code.'
            : 'Login requires 2FA; import a verified Fable contract containing both 2FA operations.';
        });
        return;
      }
      if (result.authenticated) {
        final signedRevision=_client().session.identityRevision;
        await _saveLoginHint();
        // قد يتغير الحساب أثناء حفظ اسم الدخول الاختياري؛ لا نعرض
        // نتيجة الجلسة القديمة لحساب آخر ولا نحفظ كلمة المرور هنا.
        if(!mounted || _client().session.identityRevision!=signedRevision)return;
        TextInput.finishAutofillContext(shouldSave:true);
        _password.clear();
        setState(() {
          _signedIn=true;_passwordChangeRequired=result.mustChangePassword;
          _savedSessionAvailable=false;
          _message=result.mustChangePassword
            ? 'Password change is required before using the account.'
            : 'Session saved securely.';
        });
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
      final details=await _client().requestSecondFactorDetails(
        pending,preferredChannel:_preferredChannel);
      if(!mounted || !identical(pending,_challenge))return;
      setState(() {
        _challengeId=details.challengeId;
        _otpExpiresAt=details.expiresAt;
        _otpMethod=details.method;
        _otpDestination=details.maskedDestination;
        _message='A one-time code was requested. Enter it to finish sign-in.';
      });
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
      final outcome=await _client().completeSecondFactor(
        pending,challengeId:id,code:_otp.text.trim());
      final signedRevision=_client().session.identityRevision;
      await _saveLoginHint();
      if(!mounted || _client().session.identityRevision!=signedRevision)return;
      // Do not save after the first factor: only a confirmed full login.
      TextInput.finishAutofillContext(shouldSave:true);
      setState(() {
        _otp.clear();_challenge=null;_challengeId=null;
        _otpExpiresAt=null;_otpMethod=null;_otpDestination=null;
        _signedIn=true;
        _passwordChangeRequired=outcome.mustChangePassword;_savedSessionAvailable=false;
        _message=outcome.mustChangePassword
          ? 'Second factor verified. Change your password before continuing.'
          : 'Two-factor sign-in completed. Session saved securely.';
      });
    }on FableApiException catch(error){
      if(mounted)setState(()=>_message='Verification rejected: ${error.code}');
    }catch(_){
      if(mounted)setState(()=>_message='Unable to complete verification. Please check your code and connection.');
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  void _cancelChallenge(){
    _otp.clear();_password.clear();
    setState((){
      _challenge=null;_challengeId=null;_preferredChannel=null;_message=null;
      _otpExpiresAt=null;_otpMethod=null;_otpDestination=null;
    });
  }

  Future<void> _logout() async {
    if (_busy) return;
    final client=_client();
    setState(() { _busy = true; _message = null; });
    try {
      final confirmed = await client.logout();
      // An in-flight old logout may finish after another account signs in.
      // Do not claim its new credentials were removed or its server session
      // revoked. Offer an explicit server verification of the current token.
      final activeToken=await client.session.accessToken;
      if (!mounted)return;
      if(activeToken!=null && activeToken.isNotEmpty){
        setState((){
          _signedIn=false;_passwordChangeRequired=false;
          _savedSessionAvailable=true;
          _message='Session changed during sign-out. Verify the current session.';
        });
        return;
      }
      setState(() {
        _signedIn = false;
        _passwordChangeRequired=false;
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
        if(_signedIn && _passwordChangeRequired)
          const Padding(padding:EdgeInsets.only(top:12),
            child:Text('Password change required. Other account operations are locked until the password is updated.',textAlign:TextAlign.center)),
        if(_signedIn && _passwordChangeRequired &&
           !widget.contract.supports('auth.change-password'))
          const Padding(padding:EdgeInsets.only(top:8),
            child:Text('This contract has no verified password-change operation. Sign out and contact support.',textAlign:TextAlign.center)),
        if (_signedIn) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
          child: FilledButton.tonal(onPressed:_busy?null:_logout,child:const Text('Sign out'))),
        if(_signedIn && widget.contract.supports('auth.change-password'))
          Padding(padding:const EdgeInsets.only(bottom:12),
            child:OutlinedButton.icon(
              onPressed:_busy?null:()async{
                final changed=await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(builder:(_)=>FableChangePasswordPage(
                    gateway:_client(),contract:widget.contract)));
                if(changed==true&&mounted){
                  // عند تغيير كلمة المرور ألغى الباك كل الجلسات، لا نُظهر Login صالحاً.
                  setState((){
                    _signedIn=false;_passwordChangeRequired=false;
                    _savedSessionAvailable=false;_challenge=null;
                    _message='Password updated. Sign in again on every device.';
                  });
                }
              },
              icon:const Icon(Icons.password),
              label:Text(_passwordChangeRequired?'Change password to continue':'Change password'),
            )),
        if(_signedIn && !_passwordChangeRequired &&
           widget.contract.supports('auth.sessions'))
          Padding(padding:const EdgeInsets.only(bottom:12),
            child:OutlinedButton.icon(
              onPressed:_busy?null:()=>Navigator.of(context).push(
                MaterialPageRoute<void>(builder:(_)=>FableSessionsPage(
                  gateway:_client(),contract:widget.contract))),
              icon:const Icon(Icons.devices_other),
              label:const Text('My active devices & sessions'),
            )),
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
            onChanged:_busy?null:(value)=>setState((){
              _preferredChannel=value;_challengeId=null;_otpExpiresAt=null;
              _otpMethod=null;_otpDestination=null;_otp.clear();
            }),
          ),
          const SizedBox(height:12),
          FilledButton.tonal(onPressed:!_busy&&widget.contract.supports('auth.2fa.login.request')&&
            widget.contract.supports('auth.2fa.login.complete')?_requestCode:null,
            child:const Text('Request verification code')),
          if(_challengeId!=null) ...[
            const SizedBox(height:12),
            if(_otpMethod!=null)Text(_otpMethod=='EMAIL_OTP'
              ?'Verification code sent by email.'
              :'Verification code sent by phone.'),
            if(_otpDestination!=null)Text('Recipient: $_otpDestination'),
            if(_otpExpiresAt!=null)Text(
              'Code expires: ${_otpExpiresAt!.toLocal()}'),
            TextField(controller:_otp,keyboardType:TextInputType.number,
              autofillHints:const [AutofillHints.oneTimeCode],maxLength:10,
              decoration:const InputDecoration(labelText:'One-time code')),
            FilledButton(onPressed:_busy?null:_completeCode,child:const Text('Verify and sign in')),
          ],
          TextButton(onPressed:_busy?null:_cancelChallenge,child:const Text('Cancel sign-in')),
        ]),
        if (!_signedIn && _challenge==null) AutofillGroup(child:Form(key:_key,child:Column(children:[
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
          CheckboxListTile(
            contentPadding:EdgeInsets.zero,
            value:_rememberIdentifier,
            onChanged:_busy?null:(value) async {
              setState(()=>_rememberIdentifier=value??false);
              if(!_rememberIdentifier) {
                try{await _credentialHints.clear();}catch(_){}
              }
            },
            title:const Text('Remember my login identifier on this device'),
            subtitle:const Text('Passwords stay with your device password manager.'),
          ),
          const SizedBox(height:22),FilledButton(onPressed:enabled&&!_busy?_login:null,
            child:_busy?const SizedBox(height:18,width:18,child:CircularProgressIndicator(strokeWidth:2)):
              const Text('Sign in')),
        ]))),
        if(!_signedIn&&_challenge==null&&
            (_url.isNotEmpty||widget.gateway!=null)&&
            _client().canLoginWithPublicOtp)
          TextButton(onPressed:_busy?null:()async{
            final outcome=await Navigator.of(context).push<FableLoginOutcome>(
              MaterialPageRoute<FableLoginOutcome>(builder:(_)=>FableOtpLoginPage(
                gateway:_client(),deviceName:widget.deviceName,
                appVersion:widget.appVersion)));
            if(!mounted||outcome==null||!outcome.authenticated)return;
            _password.clear();
            setState((){
              _signedIn=true;
              _passwordChangeRequired=outcome.mustChangePassword;
              _savedSessionAvailable=false;
              _message=outcome.mustChangePassword
                ?'Backend requires changing the password before continuing.'
                :'OTP login completed and session confirmed by Backend.';
            });
          },child:const Text('Sign in using a one-time code')),
        if(!_signedIn&&_challenge==null&&
            (_url.isNotEmpty||widget.gateway!=null)&&
            _client().canResetPasswordWithPublicOtp)
          Padding(padding:const EdgeInsets.only(top:8),
            child:TextButton(
              onPressed:_busy?null:()async{
                final reset=await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(builder:(_)=>FablePasswordResetPage(
                    gateway:_client())));
                if(reset==true&&mounted){
                  setState((){
                    _password.clear();
                    _savedSessionAvailable=false;
                    _message='Password reset confirmed by Backend. Sign in again.';
                  });
                }
              },
              child:const Text('Forgot password? Verify by OTP'))),
        if(_message!=null)Padding(padding:const EdgeInsets.only(top:20),child:Text(_message!,textAlign:TextAlign.center)),
        if(_url.isEmpty && widget.gateway==null)const Padding(padding:EdgeInsets.only(top:14),child:Text(
          'Configure with --dart-define=FABLE_API_BASE_URL=https://your-api.example',textAlign:TextAlign.center)),
      ])))));
  }
}
