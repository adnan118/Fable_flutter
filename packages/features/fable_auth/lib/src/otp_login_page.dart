import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';

/// RC95 Fable-only bearer login via verified public OTP purpose LOGIN.
/// This is not password-reset or a workaround for enabled 2FA.
class FableOtpLoginPage extends StatefulWidget {
  const FableOtpLoginPage({super.key,required this.gateway,
    this.deviceName,this.appVersion});
  final FableAuthGateway gateway;
  final String? deviceName,appVersion;
  @override State<FableOtpLoginPage> createState()=>_OtpLoginState();
}

enum _OtpLoginStage { identifier, code, confirmed }
class _OtpLoginState extends State<FableOtpLoginPage> {
  final _identifier=TextEditingController(),_code=TextEditingController();
  FableOtpLoginChallenge? _challenge;
  FableVerifiedLoginOtp? _verified;
  _OtpLoginStage _stage=_OtpLoginStage.identifier;
  bool _busy=false;
  String? _message;
  String? _channel;

  @override void dispose(){
    _identifier.dispose();_code.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if(_busy||!widget.gateway.canLoginWithPublicOtp)return;
    setState((){_busy=true;_message=null;_verified=null;});
    try {
      final c=await widget.gateway.requestLoginOtp(
        identifier:_identifier.text,preferredChannel:_channel);
      if(!mounted)return;
      setState((){
        _challenge=c;_stage=_OtpLoginStage.code;
        _message='Backend queued the OTP request; actual delivery is not confirmed.';
      });
    } on FableApiException catch(e) {
      if(mounted)setState(()=>_message=e.status==429
        ?'Too many attempts. Follow server cooldown.'
        :'Backend rejected OTP request.');
    } catch (_) {
      if(mounted)setState(()=>_message='OTP request was not confirmed.');
    } finally {if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _verify() async {
    final c=_challenge;
    if(_busy||c==null)return;
    setState((){_busy=true;_message=null;});
    try {
      final p=await widget.gateway.verifyLoginOtp(c,_code.text.trim());
      if(!mounted)return;
      _code.clear();
      setState((){
        _verified=p;_stage=_OtpLoginStage.confirmed;
        _message='LOGIN OTP verified; session has not been created yet.';
      });
    } catch (_) {
      if(mounted)setState(()=>_message='OTP invalid, expired or wrong purpose.');
    } finally {if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _complete() async {
    final p=_verified;
    if(_busy||p==null)return;
    setState((){_busy=true;_message=null;});
    try {
      final result=await widget.gateway.completeLoginWithOtp(p,
        platform:defaultTargetPlatform==TargetPlatform.iOS?'ios':'android',
        deviceName:widget.deviceName,appVersion:widget.appVersion);
      if(mounted)Navigator.of(context).pop(result);
    } on FableApiException catch(e) {
      if(mounted)setState(()=>_message=e.code=='AUTH_OTP_LOGIN_REQUIRES_PRIMARY'
        ?'This account requires a different first factor and separate 2FA.'
        :e.code=='AUTH_OTP_LOGIN_DISABLED'
          ?'Backend has disabled OTP login.'
          :'Backend did not confirm sign-in. Start with a new OTP challenge.');
    } catch (_) {
      if(mounted)setState(()=>_message=
        'Login was not confirmed. Re-check account state before starting again.');
    } finally {if(mounted)setState(()=>_busy=false);}
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Sign in with OTP')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Backend controls OTP availability, account existence and 2FA policy.'),
      if(_stage==_OtpLoginStage.identifier)...[
        TextField(controller:_identifier,maxLength:191,
          decoration:const InputDecoration(labelText:'Email, username or phone')),
        DropdownButtonFormField<String>(
          value:_channel,
          decoration:const InputDecoration(labelText:'Preferred channel (optional)'),
          items:const [
            DropdownMenuItem(value:'EMAIL',child:Text('Email')),
            DropdownMenuItem(value:'PHONE',child:Text('Phone')),
          ],
          onChanged:_busy?null:(v)=>setState(()=>_channel=v)),
        FilledButton(onPressed:_busy?null:()=>_request(),
          child:const Text('Request login OTP')),
      ],
      if(_stage==_OtpLoginStage.code)...[
        TextField(controller:_code,maxLength:10,
          keyboardType:TextInputType.number,
          decoration:const InputDecoration(labelText:'6–10 digit OTP')),
        FilledButton(onPressed:_busy?null:()=>_verify(),
          child:const Text('Verify LOGIN OTP')),
      ],
      if(_stage==_OtpLoginStage.confirmed)
        FilledButton(onPressed:_busy?null:()=>_complete(),
          child:const Text('Complete sign-in')),
      if(_stage!=_OtpLoginStage.identifier)
        TextButton(onPressed:_busy?null:()=>setState((){
          _stage=_OtpLoginStage.identifier;_challenge=null;_verified=null;
          _code.clear();_message=null;
        }),child:const Text('Start a new OTP challenge')),
      if(_busy)const LinearProgressIndicator(),
      if(_message!=null)Text(_message!),
    ]),
  );
}
