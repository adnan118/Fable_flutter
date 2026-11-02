import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'social_auth_repository.dart';

/// Fable-specific account linking. Other Backend must provide its own contract
/// and UI; this screen never infers OAuth routes or membership permissions.
class FableSocialAccountSettingsPage extends StatefulWidget {
  const FableSocialAccountSettingsPage({super.key,required this.gateway,
    required this.repository});
  final FableAuthGateway gateway;
  final FableSocialRepository repository;
  @override State<FableSocialAccountSettingsPage> createState() =>
      _SocialAccountSettingsState();
}

class _SocialAccountSettingsState extends State<FableSocialAccountSettingsPage> {
  final _otp=TextEditingController();
  StreamSubscription<FableIdentityEvent>? _identity;
  String? _challengeId,_message;
  FableVerifiedSensitiveProof? _verified;
  FableSocialProvider? _provider;
  bool _link=true,_busy=false;
  int _identityRevision=0;

  bool get _bound => identical(widget.repository.gateway,widget.gateway) &&
    identical(widget.repository.session,widget.gateway.session) &&
    widget.repository.adapter is FableSocialBackendAdapter;

  @override void initState() {
    super.initState();
    _identityRevision=widget.gateway.session.identityRevision;
    _identity=widget.gateway.session.identityEvents.listen((_) {
      if(!mounted)return;
      _otp.clear();
      setState((){
        _verified=null;_challengeId=null;_provider=null;
        _identityRevision=widget.gateway.session.identityRevision;
        _message='Account changed; the pending operation was cancelled.';
      });
    });
  }

  @override void dispose() {
    unawaited(_identity?.cancel());
    _otp.dispose();
    super.dispose();
  }

  bool get _current => _bound &&
    _identityRevision==widget.gateway.session.identityRevision;

  Future<void> _start(FableSocialProvider provider,{required bool link}) async {
    if(_busy||!_current)return;
    if(link && !widget.repository.operations.supports(
        '${provider.wireName}Link'))return;
    if(!link && !widget.gateway.canUnlinkSocialIdentity)return;
    if(!link){
      final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Unlink sign-in method?'),
        content:const Text('Backend may reject removal of the final sign-in method.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:const Text('Confirm')),
        ]));
      if(yes!=true||!mounted||!_current)return;
    }
    setState((){
      _provider=provider;_link=link;
      _challengeId=null;_verified=null;_message=null;
      _otp.clear();_busy=true;
    });
    try {
      final id=await widget.gateway.requestSensitiveActionOtp();
      if(!mounted||!_current)return;
      setState((){
        _challengeId=id;
        _message='A security OTP was requested; delivery is not yet confirmed.';
      });
    }catch(_){
      if(mounted&&_current)setState(()=>_message=
        'Backend did not accept a security challenge. Check your session and 2FA.');
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _verify() async {
    final id=_challengeId;
    if(_busy||!_current||id==null)return;
    setState(()=>_busy=true);
    try {
      final proof=await widget.gateway.verifySensitiveActionOtp(id,_otp.text.trim());
      if(!mounted||!_current)return;
      _otp.clear();
      setState((){
        _verified=proof;_message='Backend verified recent authentication.';
      });
    }catch(_){
      if(mounted&&_current)setState(()=>_message=
        'Security code was rejected, expired or belongs to another account.');
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _perform() async {
    final provider=_provider,proof=_verified;
    if(_busy||!_current||provider==null||proof==null)return;
    setState(()=>_busy=true);
    try {
      String result;
      if(_link){
        final verifiedId=widget.gateway.verifiedSocialActionChallengeId(proof);
        final linked=await widget.repository.link(provider,
          securityChallengeId:verifiedId);
        result=linked==true ? 'Backend confirmed social account link.'
          : 'Provider sign-in was cancelled; no link was confirmed.';
      }else{
        final unlinked=await widget.gateway.unlinkSocialIdentityWithProof(
          provider.wireName,proof);
        result=unlinked.unlinked
          ?'Backend confirmed social account unlink.'
          :'Backend did not remove this sign-in method.';
      }
      if(!mounted||!_current)return;
      setState((){
        _message=result;
        _provider=null;_challengeId=null;_verified=null;_otp.clear();
      });
    }on FableApiException catch(e){
      if(mounted&&_current)setState(()=>_message=e.status==409
        ?'Backend rejected this account change; refresh sign-in methods.'
        :'Backend rejected the requested account action.');
    }catch(_){
      if(mounted&&_current)setState(()=>_message=
        'Account change unconfirmed. Re-read the server state before retrying.');
    }finally{
      if(mounted){
        setState((){
          _busy=false;_verified=null;_challengeId=null;_otp.clear();
        });
      }
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Linked sign-in methods')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Google/Apple credentials come only from the host app native SDK. '
        'Backend confirms account ownership and prevents deleting the last sign-in method.'),
      if(!_bound)const Text(
        'Unavailable: social identity must share the exact Fable Auth gateway and session.'),
      if(_bound)...[
        for(final provider in FableSocialProvider.values)...[
          if(widget.repository.operations.supports('${provider.wireName}Link'))
            OutlinedButton(onPressed:_busy?null:()=>_start(provider,link:true),
              child:Text('Link ${provider.name}')),
          if(widget.gateway.canUnlinkSocialIdentity)
            TextButton(onPressed:_busy?null:()=>_start(provider,link:false),
              child:Text('Unlink ${provider.name}')),
        ],
      ],
      if(_challengeId!=null && _verified==null)...[
        TextField(controller:_otp,keyboardType:TextInputType.number,
          obscureText:true,maxLength:10,
          decoration:const InputDecoration(labelText:'Recent-auth OTP')),
        FilledButton(onPressed:_busy?null:_verify,
          child:const Text('Verify security code')),
      ],
      if(_verified!=null)
        FilledButton(onPressed:_busy?null:_perform,
          child:Text(_link?'Confirm account link':'Confirm unlink')),
      if(_provider!=null)
        TextButton(onPressed:_busy?null:()=>setState((){
          _provider=null;_verified=null;_challengeId=null;_otp.clear();
        }),child:const Text('Cancel pending account action')),
      if(_busy)const LinearProgressIndicator(),
      if(_message!=null)Text(_message!),
    ]),
  );
}
