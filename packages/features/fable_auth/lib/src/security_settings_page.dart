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
  List<FableAccountPasskey> accountPasskeys=const [];
  bool passkeysLoaded=false,passkeysLoading=false;
  int passkeyLoadEpoch=0;
  StreamSubscription<FableIdentityEvent>? identity;
  FableTwoFactorStatus? status;
  FableSecurityOtpPurpose? purpose;
  FableSecurityOtpChallenge? challenge;
  FableVerifiedSecurityOtp? verified;
  FableVerifiedSensitiveProof? recent;
  String? recentChallenge;
  bool busy=false,requiresRecent=false;
  String? message;

  // An old account must never publish an asynchronous OTP, contact,
  // 2FA or Passkey result into a different account's settings screen.
  int _securityEpoch=0;
  bool _live(int epoch,int revision)=>
    mounted && _securityEpoch==epoch &&
    widget.gateway.session.identityRevision==revision;

  void _bindIdentity(){
    identity=widget.gateway.session.identityEvents.listen((_){
      if(!mounted)return;
      _securityEpoch++;
      _clear();
      setState((){
        status=null;purpose=null;busy=false;
        message='Session changed. Sign in again.';
      });
    });
  }

  @override void initState(){
    super.initState();
    _bindIdentity();
    unawaited(_refresh());
    unawaited(_loadPasskeys());
  }

  @override void didUpdateWidget(covariant FableSecuritySettingsPage old){
    super.didUpdateWidget(old);
    if(!identical(old.gateway,widget.gateway)){
      _securityEpoch++;
      unawaited(identity?.cancel());
      _clear();
      status=null;purpose=null;busy=false;
      message='Security backend changed. Verify your account again.';
      _bindIdentity();
      unawaited(_refresh());
      unawaited(_loadPasskeys());
    }
  }
  void _clear(){
    code.clear();recentCode.clear();destination.clear();
    challenge=null;verified=null;recent=null;recentChallenge=null;
    passkeyRecent=null;passkeyChallenge=null;passkeyCode.clear();
    accountPasskeys=const [];passkeysLoaded=false;passkeysLoading=false;
    passkeyLoadEpoch++;
    requiresRecent=false;
  }
  @override void dispose(){
    _securityEpoch++;
    passkeyLoadEpoch++;
    unawaited(identity?.cancel());
    code.dispose();recentCode.dispose();passkeyCode.dispose();destination.dispose();
    super.dispose();
  }
  Future<void> _refresh()async{
    if(busy||!widget.gateway.canReadTwoFactorStatus)return;
    final epoch=_securityEpoch,revision=widget.gateway.session.identityRevision;
    setState(()=>busy=true);
    try{
      final state=await widget.gateway.loadTwoFactorStatus();
      if(_live(epoch,revision))setState(()=>status=state);
    }catch(_){
      if(_live(epoch,revision))setState(()=>message='Backend security status unavailable.');
    }finally{if(_live(epoch,revision))setState(()=>busy=false);}
  }
  void _choose(FableSecurityOtpPurpose value){
    if(busy)return;
    setState((){
      _clear();purpose=value;message=null;
    });
  }
  Future<void> _request()async{
    if(purpose==null||busy)return;
    final epoch=_securityEpoch,revision=widget.gateway.session.identityRevision;
    setState(()=>busy=true);
    try{
      final pending=await widget.gateway.requestSecurityOtp(
        purpose:purpose!,
        newDestination:purpose==FableSecurityOtpPurpose.twoFactor
          ?null:destination.text);
      if(_live(epoch,revision))setState((){
        challenge=pending;
        message='OTP challenge created. Provider delivery is not confirmed.';
      });
    }catch(_){
      if(_live(epoch,revision))setState(()=>message=
        'Backend did not confirm OTP request; check destination, limits and account.');
    }finally{if(_live(epoch,revision))setState(()=>busy=false);}
  }
  Future<void> _verify()async{
    if(challenge==null||busy)return;
    final epoch=_securityEpoch,revision=widget.gateway.session.identityRevision;
    setState(()=>busy=true);
    try{
      final proof=await widget.gateway.verifySecurityOtp(
        challenge!,code.text.trim());
      if(_live(epoch,revision))setState((){
        verified=proof;code.clear();message='OTP verified by Backend.';
      });
    }catch(_){
      if(_live(epoch,revision))setState(()=>message='OTP rejected, expired or identity changed.');
    }finally{if(_live(epoch,revision))setState(()=>busy=false);}
  }
  Future<void> _commit()async{
    if(verified==null||busy)return;
    if(purpose==FableSecurityOtpPurpose.twoFactor&&status==null)return;
    var shouldRefresh=false;
    final epoch=_securityEpoch,revision=widget.gateway.session.identityRevision;
    setState(()=>busy=true);
    try{
      final number=purpose==FableSecurityOtpPurpose.twoFactor
        ?(await widget.gateway.setTwoFactorEnabled(verified!,
          enabled:!status!.enabled)).revokedOtherSessions
        :(await widget.gateway.changeVerifiedContact(verified!,
          newDestination:destination.text,
          securityProof:recent)).revokedOtherSessions;
      if(!_live(epoch,revision))return;
      setState((){
        message='Backend confirmed change; other sessions revoked: $number.';
        _clear();purpose=null;status=null;
      });
      shouldRefresh=true;
    }on FableApiException catch(e){
      if(!_live(epoch,revision))return;
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
      if(_live(epoch,revision))setState(()=>
        message='Change unconfirmed. Verify server state before repeating.');
    }finally{
      if(_live(epoch,revision)){
        setState(()=>busy=false);
        if(shouldRefresh)unawaited(_refresh());
      }
    }
  }
  Future<void> _requestRecent()async{
    if(busy)return;
    final epoch=_securityEpoch,revision=widget.gateway.session.identityRevision;
    setState(()=>busy=true);
    try{
      final id=await widget.gateway.requestSensitiveActionOtp();
      if(_live(epoch,revision))setState((){
        recentChallenge=id;message='Recent-auth challenge created.';
      });
    }catch(_){
      if(_live(epoch,revision))setState(()=>message='Recent-auth challenge unavailable.');
    }finally{if(_live(epoch,revision))setState(()=>busy=false);}
  }
  Future<void> _verifyRecent()async{
    if(recentChallenge==null||busy)return;
    final epoch=_securityEpoch,revision=widget.gateway.session.identityRevision;
    setState(()=>busy=true);
    try{
      final proof=await widget.gateway.verifySensitiveActionOtp(
        recentChallenge!,recentCode.text.trim());
      if(_live(epoch,revision))setState((){
        recent=proof;recentCode.clear();
        message='Recent-auth proof verified. Confirm again.';
      });
    }catch(_){
      if(_live(epoch,revision))setState(()=>message='Additional verification failed.');
    }finally{if(_live(epoch,revision))setState(()=>busy=false);}
  }
  Future<void> _requestPasskeyProof()async{
    if(busy || !(widget.gateway.canRegisterNativePasskey ||
        widget.gateway.canManageAccountPasskeys))return;
    setState(()=>busy=true);
    final revision=widget.gateway.session.identityRevision,epoch=_securityEpoch;
    try{
      final challenge=await widget.gateway.requestSensitiveActionOtp();
      if(!_live(epoch,revision))return;
      setState((){
        passkeyChallenge=challenge;passkeyRecent=null;passkeyCode.clear();
        message='Recent-auth OTP requested; delivery is not yet confirmed.';
      });
    }catch(_){
      if(_live(epoch,revision))
        setState(()=>message='Could not request Passkey authorization.');
    }finally{if(_live(epoch,revision))setState(()=>busy=false);}
  }
  Future<void> _verifyPasskeyProof()async{
    final challenge=passkeyChallenge;
    if(busy||challenge==null)return;
    setState(()=>busy=true);
    final revision=widget.gateway.session.identityRevision,epoch=_securityEpoch;
    try{
      final proof=await widget.gateway.verifySensitiveActionOtp(
        challenge,passkeyCode.text.trim());
      if(!_live(epoch,revision))return;
      setState((){
        passkeyRecent=proof;passkeyCode.clear();
        message='Backend verified your recent authorization.';
      });
    }catch(_){
      if(_live(epoch,revision))
        setState(()=>message='Recent-auth challenge was rejected or expired.');
    }finally{if(_live(epoch,revision))setState(()=>busy=false);}
  }
  Future<void> _registerPasskey()async{
    final proof=passkeyRecent;
    if(busy||proof==null||!widget.gateway.canRegisterNativePasskey)return;
    setState(()=>busy=true);
    final revision=widget.gateway.session.identityRevision,epoch=_securityEpoch;
    try{
      final created=await widget.gateway.registerNativePasskey(
        proof:proof,createCredential:FableNativePasskeys().createCredential);
      if(!_live(epoch,revision))return;
      setState((){
        if(created){
          passkeyRecent=null;passkeyChallenge=null;
          message='Backend confirmed your new device Passkey.';
        }else{
          message='Native Passkey registration was cancelled.';
        }
      });
      if(created&&widget.gateway.canManageAccountPasskeys)
        unawaited(_loadPasskeys());
    }catch(_){
      if(_live(epoch,revision))
        setState(()=>message='Passkey registration failed. Check your authorization and app domain.');
    }finally{if(_live(epoch,revision))setState(()=>busy=false);}
  }

  Future<void> _loadPasskeys()async{
    if(passkeysLoading||!widget.gateway.canManageAccountPasskeys)return;
    final epoch=++passkeyLoadEpoch;
    final revision=widget.gateway.session.identityRevision;
    setState(()=>passkeysLoading=true);
    try{
      final rows=await widget.gateway.listAccountPasskeys();
      if(!mounted||passkeyLoadEpoch!=epoch||
          widget.gateway.session.identityRevision!=revision)return;
      setState((){
        accountPasskeys=rows;passkeysLoaded=true;
      });
    }catch(_){
      if(mounted&&passkeyLoadEpoch==epoch&&
          widget.gateway.session.identityRevision==revision)
        setState((){
          accountPasskeys=const [];passkeysLoaded=false;
          message='Passkey list could not be verified with Backend.';
        });
    }finally{
      if(mounted&&passkeyLoadEpoch==epoch)
        setState(()=>passkeysLoading=false);
    }
  }
  Future<void> _removePasskey(FableAccountPasskey passkey)async{
    final proof=passkeyRecent;
    if(busy||passkeysLoading||proof==null)return;
    final revision=widget.gateway.session.identityRevision,epoch=_securityEpoch;
    final confirmed=await showDialog<bool>(context:context,builder:(context)=>
      AlertDialog(
        title:const Text('Remove this Passkey?'),
        content:const Text('This may affect account recovery. Backend will block removing your last sign-in method.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context,false),
            child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(context,true),
            child:const Text('Remove')),
        ],
      ));
    if(confirmed!=true||!_live(epoch,revision) ||
        !identical(passkeyRecent,proof))return;
    setState(()=>busy=true);
    var removed=false;
    try{
      removed=await widget.gateway.removeAccountPasskey(
        passkey:passkey,proof:proof);
      if(!_live(epoch,revision))return;
      setState((){
        passkeyRecent=null;passkeyChallenge=null;passkeyCode.clear();
        message=removed?'Backend confirmed Passkey deletion.':
          'Credential no longer existed; refresh the list.';
      });
    }catch(_){
      if(_live(epoch,revision))
        setState((){
          passkeyRecent=null;passkeyChallenge=null;passkeyCode.clear();
          message='Passkey removal was not confirmed. Reauthorize and retry.';
        });
    }finally{if(_live(epoch,revision))setState(()=>busy=false);}
    if(removed&&_live(epoch,revision))
      unawaited(_loadPasskeys());
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
      if((widget.gateway.canRegisterNativePasskey ||
          widget.gateway.canManageAccountPasskeys) &&
          !kIsWeb && (defaultTargetPlatform==TargetPlatform.android ||
                     defaultTargetPlatform==TargetPlatform.iOS)) ...[
        const Divider(),
        const Text('Passkey security'),
        const Text('Create, review or remove device Passkeys with a fresh verified authorization code.'),
        if(widget.gateway.canManageAccountPasskeys)...[
          OutlinedButton.icon(
            onPressed:passkeysLoading?null:_loadPasskeys,
            icon:const Icon(Icons.refresh),
            label:const Text('Refresh linked Passkeys')),
          if(passkeysLoading)const LinearProgressIndicator(),
          if(passkeysLoaded&&accountPasskeys.isEmpty)
            const Text('No Passkeys linked to this account.'),
          for(final credential in accountPasskeys)
            ListTile(
              leading:const Icon(Icons.fingerprint),
              title:Text(credential.label?.isNotEmpty==true
                ?credential.label!:'Passkey'),
              subtitle:Text([
                if(credential.deviceType!=null)credential.deviceType!,
                credential.backedUp?'Backed up':'Device-bound',
                if(credential.lastUsedAt!=null)credential.lastUsedAt!,
              ].join(' · ')),
              trailing:IconButton(
                tooltip:'Remove with recent authorization',
                onPressed:busy||passkeysLoading||passkeyRecent==null
                  ?null:()=>unawaited(_removePasskey(credential)),
                icon:const Icon(Icons.delete_outline),
              ),
            ),
        ],
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
        if(passkeyRecent!=null&&widget.gateway.canRegisterNativePasskey)
          FilledButton.icon(onPressed:busy?null:_registerPasskey,
            icon:const Icon(Icons.fingerprint),
            label:const Text('Create Passkey on this device')),
      ],
      if(busy)const LinearProgressIndicator(),
      if(message!=null)Text(message!),
    ])),
  );
}
