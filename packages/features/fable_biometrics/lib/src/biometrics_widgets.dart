import 'package:material_ui/material_ui.dart';
import 'biometrics_repository.dart';
import 'passkey_registration.dart';

/// Explicit user gesture only. Result may require further Auth/2FA steps.
class FablePasskeySignInButton extends StatefulWidget {
  const FablePasskeySignInButton({super.key,required this.repository,this.onResult});
  final FablePasskeyRepository repository;
  final ValueChanged<Object>? onResult;
  @override State<FablePasskeySignInButton> createState()=>_FablePasskeySignInButtonState();
}
class _FablePasskeySignInButtonState extends State<FablePasskeySignInButton> {
  bool _busy=false; int _epoch=0; String? _error;
  @override void didUpdateWidget(covariant FablePasskeySignInButton old){super.didUpdateWidget(old);
    if(!identical(old.repository,widget.repository)){_epoch++;_busy=false;_error=null;}}
  @override void dispose(){_epoch++;super.dispose();}
  Future<void> _run() async{
    if(_busy)return;
    final epoch=++_epoch;setState((){_busy=true;_error=null;});
    try{final result=await widget.repository.authenticate();
      if(mounted&&epoch==_epoch&&result!=null)widget.onResult?.call(result);
    }catch(_){if(mounted&&epoch==_epoch)setState(()=>_error='Passkey authentication unavailable.');}
    finally{if(mounted&&epoch==_epoch)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Column(mainAxisSize:MainAxisSize.min,children:[
    OutlinedButton.icon(onPressed:_busy?null:_run,icon:const Icon(Icons.fingerprint),
      label:Text(_busy?'Authenticating…':'Use a passkey')),
    if(_error!=null)Text(_error!,style:Theme.of(context).textTheme.bodySmall)
  ]);
}

 
/// Only show after the host has verified its Fable registration contract,
/// mounted a native Credential Manager/AuthenticationServices creator and,
/// where required, completed a fresh server-side step-up challenge.
class FablePasskeyRegisterButton extends StatefulWidget {
  const FablePasskeyRegisterButton({super.key,required this.repository,
    this.label,this.securityChallengeId,this.onRegistered});
  final FablePasskeyRegistrationRepository repository;
  final String? label,securityChallengeId;
  final VoidCallback? onRegistered;
  @override State<FablePasskeyRegisterButton> createState()=>
    _FablePasskeyRegisterButtonState();
}
class _FablePasskeyRegisterButtonState extends State<FablePasskeyRegisterButton>{
  bool _busy=false;
  int _epoch=0;
  String? _error;
  @override void didUpdateWidget(covariant FablePasskeyRegisterButton old){
    super.didUpdateWidget(old);
    if(!identical(old.repository,widget.repository)||
        old.securityChallengeId!=widget.securityChallengeId){
      _epoch++;_busy=false;_error=null;
    }
  }
  @override void dispose(){_epoch++;super.dispose();}
  Future<void> _register()async{
    if(_busy)return;
    final epoch=++_epoch;
    setState((){_busy=true;_error=null;});
    try{
      final registered=await widget.repository.register(
        label:widget.label,securityChallengeId:widget.securityChallengeId);
      if(mounted&&epoch==_epoch&&registered)widget.onRegistered?.call();
    }catch(_){
      if(mounted&&epoch==_epoch){
        setState(()=>_error='Passkey registration requires a verified session and recent authorization.');
      }
    }finally{if(mounted&&epoch==_epoch)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Column(
    mainAxisSize:MainAxisSize.min,children:[
      OutlinedButton.icon(onPressed:_busy?null:_register,
        icon:const Icon(Icons.fingerprint),
        label:Text(_busy?'Registering…':'Add a passkey')),
      if(_error!=null)Text(_error!,style:Theme.of(context).textTheme.bodySmall),
    ]);
}
