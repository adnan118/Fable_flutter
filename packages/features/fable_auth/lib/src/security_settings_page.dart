import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:flutter/foundation.dart';
import 'package:fable_biometrics/fable_biometrics.dart';

/// Fable-only security settings; server remains authoritative.
class FableSecuritySettingsPage extends StatefulWidget {
  const FableSecuritySettingsPage({super.key,required this.gateway});
  final FableAuthGateway gateway;
  @override State<FableSecuritySettingsPage> createState()=>_SecurityState();
}
class _SecurityState extends State<FableSecuritySettingsPage> {
  final destination=TextEditingController();
  final code=TextEditingController();
  final recentCode=TextEditingController();
  final passkeyCode=TextEditingController();
  FableVerifiedSensitiveProof? passkeyRecent;
  String? passkeyChallenge;
  StreamSubscription<FableIdentityEvent>? identity;
  FableTwoFactorStatus? status;
  FableSecurityOtpPurpose? purpose;
  FableSecurityOtpChallenge? challenge;
  FableVerifiedSecurityOtp? verified;
  FableVerifiedSensitiveProof? recent;
  String? recentChallenge;
  bool busy=false,requiresRecent=false;
  String? message;

  @override void initState(){
    super.initState();
    identity=widget.gateway.session.identityEvents.listen((_){
      if(!mounted)return;
      _clear();
      setState((){
        status=null;purpose=null;message='Session changed. Sign in again.';
      });
    });
    unawaited(_refresh());
  }
  void _clear(){
    code.clear();recentCode.clear();destination.clear();
    challenge=null;verified=null;recent=null;recentChallenge=null;
    passkeyRecent=null;passkeyChallenge=null;passkeyCode.clear();
    requiresRecent=false;
  }
  @override void dispose(){
    unawaited(identity?.cancel());
    code.dispose();recentCode.dispose();passkeyCode.dispose();destination.dispose();
    super.dispose();
  }
  Future<void> _refresh()async{
    if(busy||!widget.gateway.canReadTwoFactorStatus)return;
    setState(()=>busy=true);
    try{
      final state=await widget.gateway.loadTwoFactorStatus();
      if(mounted)setState(()=>status=state);
    }catch(_){
      if(mounted)setState(()=>message='Backend security status unavailable.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  void _choose(FableSecurityOtpPurpose value){
    if(busy)return;
    setState((){
      _clear();purpose=value;message=null;
    });
  }
  Future<void> _request()async{
    if(purpose==null||busy)return;
    setState(()=>busy=true);
    try{
      final pending=await widget.gateway.requestSecurityOtp(
        purpose:purpose!,
        newDestination:purpose==FableSecurityOtpPurpose.twoFactor
          ?null:destination.text);
      if(mounted)setState((){
        challenge=pending;
        message='OTP challenge created. Provider delivery is not confirmed.';
      });
    }catch(_){
      if(mounted)setState(()=>message=
        'Backend did not confirm OTP request; check destination, limits and account.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _verify()async{
    if(challenge==null||busy)return;
    setState(()=>busy=true);
    try{
      final proof=await widget.gateway.verifySecurityOtp(
        challenge!,code.text.trim());
      if(mounted)setState((){
        verified=proof;code.clear();message='OTP verified by Backend.';
      });
    }catch(_){
      if(mounted)setState(()=>message='OTP rejected, expired or identity changed.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _commit()async{
    if(verified==null||busy)return;
    if(purpose==FableSecurityOtpPurpose.twoFactor&&status==null)return;
    var shouldRefresh=false;
    setState(()=>busy=true);
    try{
      final number=purpose==FableSecurityOtpPurpose.twoFactor
        ?(await widget.gateway.setTwoFactorEnabled(verified!,
          enabled:!status!.enabled)).revokedOtherSessions
        :(await widget.gateway.changeVerifiedContact(verified!,
          newDestination:destination.text,
          securityProof:recent)).revokedOtherSessions;
      if(!mounted)return;
      setState((){
        message='Backend confirmed change; other sessions revoked: $number.';
        _clear();purpose=null;status=null;
      });
      shouldRefresh=true;
    }on FableApiException catch(e){
      if(!mounted)return;
      setState((){
        if(e.code=='AUTH_RECENT_AUTH_REQUIRED'){
          requiresRecent=true;
          message='A separate recent-auth proof is required.';
        }else if(e.code=='AUTH_INDEPENDENT_FACTOR_REQUIRED'){
          message='Backend requires an independent factor. This session cannot meet it.';
        }else{
          message='Backend did not confirm change: '+(e.status==409
            ?'destination conflict.':'check permissions or account state.');
        }
      });
    }catch(_){
      if(mounted)setState(()=>
        message='Change unconfirmed. Verify server state before repeating.');
    }finally{
      if(mounted){
        setState(()=>busy=false);
        if(shouldRefresh)unawaited(_refresh());
      }
    }
  }
  Future<void> _requestRecent()async{
    if(busy)return;
    setState(()=>busy=true);
    try{
      final id=await widget.gateway.requestSensitiveActionOtp();
      if(mounted)setState((){
        recentChallenge=id;message='Recent-auth challenge created.';
      });
    }catch(_){
      if(mounted)setState(()=>message='Recent-auth challenge unavailable.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _verifyRecent()async{
    if(recentChallenge==null||busy)return;
    setState(()=>busy=true);
    try{
      final proof=await widget.gateway.verifySensitiveActionOtp(
        recentChallenge!,recentCode.text.trim());
      if(mounted)setState((){
        recent=proof;recentCode.clear();
        message='Recent-auth proof verified. Confirm again.';
      });
    }catch(_){
      if(mounted)setState(()=>message='Additional verification failed.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _requestPasskeyProof()async{
    if(busy||!widget.gateway.canRegisterNativePasskey)return;
    setState(()=>busy=true);
    final revision=widget.gateway.session.identityRevision;
    try{
      final challenge=await widget.gateway.requestSensitiveActionOtp();
      if(!mounted||widget.gateway.session.identityRevision!=revision)return;
      setState((){
        passkeyChallenge=challenge;passkeyRecent=null;passkeyCode.clear();
        message='Recent-auth OTP requested; delivery is not yet confirmed.';
      });
    }catch(_){
      if(mounted&&widget.gateway.session.identityRevision==revision)
        setState(()=>message='Could not request Passkey authorization.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _verifyPasskeyProof()async{
    final challenge=passkeyChallenge;
    if(busy||challenge==null)return;
    setState(()=>busy=true);
    final revision=widget.gateway.session.identityRevision;
    try{
      final proof=await widget.gateway.verifySensitiveActionOtp(
        challenge,passkeyCode.text.trim());
      if(!mounted||widget.gateway.session.identityRevision!=revision)return;
      setState((){
        passkeyRecent=proof;passkeyCode.clear();
        message='Backend verified your recent authorization.';
      });
    }catch(_){
      if(mounted&&widget.gateway.session.identityRevision==revision)
        setState(()=>message='Recent-auth challenge was rejected or expired.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _registerPasskey()async{
    final proof=passkeyRecent;
    if(busy||proof==null||!widget.gateway.canRegisterNativePasskey)return;
    setState(()=>busy=true);
    final revision=widget.gateway.session.identityRevision;
    try{
      final created=await widget.gateway.registerNativePasskey(
        proof:proof,createCredential:FableNativePasskeys().createCredential);
      if(!mounted||widget.gateway.session.identityRevision!=revision)return;
      setState((){
        if(created){
          passkeyRecent=null;passkeyChallenge=null;
          message='Backend confirmed your new device Passkey.';
        }else{
          message='Native Passkey registration was cancelled.';
        }
      });
    }catch(_){
      if(mounted&&widget.gateway.session.identityRevision==revision)
        setState(()=>message='Passkey registration failed. Check your authorization and app domain.');
    }finally{if(mounted)setState(()=>busy=false);}
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Account security')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      Text(status==null?'2FA status not verified':
        status!.enabled?'2FA enabled':'2FA disabled'),
      if(status!=null)Text('Methods: '+status!.methods.join(', ')),
      TextButton(onPressed:busy?null:_refresh,
        child:const Text('Refresh security status')),
      if(widget.gateway.canManageTwoFactor&&status!=null)
        FilledButton.tonal(onPressed:busy?null:()=>
          _choose(FableSecurityOtpPurpose.twoFactor),
          child:Text(status!.enabled?'Disable 2FA':'Enable 2FA')),
      if(widget.gateway.canChangeEmailWithOtp)
        OutlinedButton(onPressed:busy?null:()=>
          _choose(FableSecurityOtpPurpose.changeEmail),
          child:const Text('Change email')),
      if(widget.gateway.canChangePhoneWithOtp)
        OutlinedButton(onPressed:busy?null:()=>
          _choose(FableSecurityOtpPurpose.changePhone),
          child:const Text('Change phone')),
      if(purpose!=null)...[
        const Divider(),
        Text('Selected: '+purpose!.backendPurpose),
        if(purpose!=FableSecurityOtpPurpose.twoFactor)
          TextField(controller:destination,enabled:challenge==null&&!busy,
            decoration:const InputDecoration(labelText:'New email or +phone')),
        if(challenge==null)
          FilledButton(onPressed:busy?null:_request,
            child:const Text('Request OTP')),
        if(challenge!=null&&verified==null)...[
          TextField(controller:code,maxLength:10,enabled:!busy,
            keyboardType:TextInputType.number,
            decoration:const InputDecoration(labelText:'OTP (6–10 digits)')),
          FilledButton(onPressed:busy?null:_verify,
            child:const Text('Verify OTP')),
        ],
        if(verified!=null)...[
          if(requiresRecent&&recent==null)...[
            if(widget.gateway.canRequestSensitiveProof)
              OutlinedButton(onPressed:busy?null:_requestRecent,
                child:const Text('Request recent-auth OTP')),
            if(recentChallenge!=null)...[
              TextField(controller:recentCode,enabled:!busy,maxLength:10,
                keyboardType:TextInputType.number,
                decoration:const InputDecoration(labelText:'Recent-auth code')),
              FilledButton(onPressed:busy?null:_verifyRecent,
                child:const Text('Verify recent-auth code')),
            ],
          ],
          if(!requiresRecent||recent!=null)
            FilledButton(onPressed:busy?null:_commit,
              child:const Text('Confirm security change')),
        ],
        TextButton(onPressed:busy?null:()=>setState((){
          _clear();purpose=null;
        }),child:const Text('Cancel and clear codes')),
      ],
      if(widget.gateway.canRegisterNativePasskey &&
          !kIsWeb && (defaultTargetPlatform==TargetPlatform.android ||
                     defaultTargetPlatform==TargetPlatform.iOS)) ...[
        const Divider(),
        const Text('Passkey registration'),
        const Text('Device passkeys are created by the operating system. Backend requires a verified recent-auth code.'),
        if(passkeyChallenge==null)
          OutlinedButton.icon(
            onPressed:busy?null:_requestPasskeyProof,
            icon:const Icon(Icons.security),
            label:const Text('Request Passkey authorization code')),
        if(passkeyChallenge!=null&&passkeyRecent==null)...[
          TextField(controller:passkeyCode,enabled:!busy,
            maxLength:10,keyboardType:TextInputType.number,
            decoration:const InputDecoration(labelText:'Recent-auth OTP')),
          OutlinedButton(
            onPressed:busy?null:_verifyPasskeyProof,
            child:const Text('Verify authorization')),
        ],
        if(passkeyRecent!=null)
          FilledButton.icon(onPressed:busy?null:_registerPasskey,
            icon:const Icon(Icons.fingerprint),
            label:const Text('Create Passkey on this device')),
      ],
      if(busy)const LinearProgressIndicator(),
      if(message!=null)Text(message!),
    ])),
  );
}
