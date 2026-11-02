import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';

/// Fable-specific public PASSWORD_RESET flow; never presumes Other Backend.
class FablePasswordResetPage extends StatefulWidget {
  const FablePasswordResetPage({super.key,required this.gateway});
  final FableAuthGateway gateway;
  @override State<FablePasswordResetPage> createState()=>_FablePasswordResetPageState();
}
enum _ResetStep { identifier, otp, password, complete }

class _FablePasswordResetPageState extends State<FablePasswordResetPage> {
  final _identifier=TextEditingController();
  final _otp=TextEditingController();
  final _newPassword=TextEditingController();
  final _confirm=TextEditingController();
  _ResetStep _step=_ResetStep.identifier;
  FablePasswordResetChallenge? _challenge;
  FablePasswordResetProof? _proof;
  bool _busy=false;
  String? _status;
  String? _preferredChannel;
  FablePasswordResetResult? _result;
  @override void dispose(){
    _identifier.dispose();_otp.dispose();_newPassword.dispose();_confirm.dispose();
    super.dispose();
  }

  Future<void> _request()async{
    if(_busy||!widget.gateway.canResetPasswordWithPublicOtp)return;
    final id=_identifier.text.trim();
    if(id.isEmpty||id.length>191){
      setState(()=>_status='Enter a valid account identifier (up to 191 characters).');
      return;
    }
    setState((){_busy=true;_status=null;_challenge=null;_proof=null;});
    try{
      final challenge=await widget.gateway.requestPasswordResetOtp(
        identifier:id,preferredChannel:_preferredChannel);
      if(!mounted)return;
      setState((){
        _challenge=challenge;_step=_ResetStep.otp;
        _status='OTP request queued by the server. Delivery is not yet confirmed.';
      });
    }on FableApiException catch(error){
      if(!mounted)return;
      setState(()=>_status=error.status==429
        ?'Too many attempts. Retry after the server cooldown.'
        :error.status==503
          ?'Password-reset OTP is temporarily unavailable.'
          :'The request was not accepted. Check the details or contact support.');
    }catch(_){
      if(mounted)setState(()=>_status='Could not start password reset. Retry safely.');
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _verify()async{
    final challenge=_challenge;
    if(_busy||challenge==null)return;
    final code=_otp.text.trim();
    if(!RegExp(r'^[0-9]{6,10}$').hasMatch(code)){
      setState(()=>_status='Enter the 6–10 digit verification code.');
      return;
    }
    setState((){_busy=true;_status=null;});
    try{
      final proof=await widget.gateway.verifyPasswordResetOtp(challenge,code);
      if(!mounted)return;
      _otp.clear();
      setState((){
        _proof=proof;_step=_ResetStep.password;
        _status='Code verified. Choose a new password.';
      });
    }on FableApiException catch(error){
      if(!mounted)return;
      setState(()=>_status=error.status==429
        ?'Too many verification attempts. Request a new challenge later.'
        :'Verification failed or the code expired. Request a new code if needed.');
    }catch(_){
      if(mounted)setState(()=>_status='Verification not completed. Retry or request a new code.');
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _finish()async{
    final proof=_proof;
    if(_busy||proof==null)return;
    if(_newPassword.text.isEmpty||_newPassword.text.length>1024||
      _newPassword.text!=_confirm.text){
      setState(()=>_status='Enter a matching password. Backend enforces the password policy.');
      return;
    }
    setState((){_busy=true;_status=null;});
    try{
      final result=await widget.gateway.completePasswordReset(
        proof,newPassword:_newPassword.text);
      if(!mounted)return;
      _newPassword.clear();_confirm.clear();_otp.clear();
      setState((){
        _result=result;_proof=null;_challenge=null;_step=_ResetStep.complete;
        _status='Password changed and existing sessions revoked. Sign in again.';
      });
    }on FableApiException catch(error){
      if(!mounted)return;
      setState(()=>_status=error.status==409
        ?'Account state changed during reset. Restart verification.'
        :error.status==400
          ?'Password rejected by backend policy or reset proof expired.'
          :'Password change not confirmed. Check account state before retrying.');
    }catch(_){
      if(mounted)setState(()=>_status='No confirmed server response. Check the account state before retrying.');
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  void _restart(){
    if(_busy)return;
    _otp.clear();_newPassword.clear();_confirm.clear();
    setState((){
      _step=_ResetStep.identifier;_challenge=null;_proof=null;_result=null;
      _status=null;
    });
  }

  @override Widget build(BuildContext context){
    final enabled=widget.gateway.canResetPasswordWithPublicOtp;
    return Scaffold(
      appBar:AppBar(title:const Text('Reset Fable password')),
      body:SafeArea(child:Center(child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:480),
        child:ListView(padding:const EdgeInsets.all(24),children:[
          const Icon(Icons.lock_reset,size:48),
          const SizedBox(height:12),
          Text('Password recovery',style:Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height:12),
          if(!enabled)const Text(
            'This project has no verified public OTP/reset operations in its Fable contract.'),
          if(enabled&&_step==_ResetStep.identifier)...[
            TextField(controller:_identifier,enabled:!_busy,maxLength:191,
              decoration:const InputDecoration(labelText:'Account identifier'),
              autofillHints:const [AutofillHints.username]),
            DropdownButtonFormField<String>(
              value:_preferredChannel,
              decoration:const InputDecoration(labelText:'Preferred channel (optional)'),
              items:const [
                DropdownMenuItem(value:'EMAIL',child:Text('Email')),
                DropdownMenuItem(value:'PHONE',child:Text('Phone')),
              ],
              onChanged:_busy?null:(v)=>setState(()=>_preferredChannel=v)),
            const SizedBox(height:12),
            FilledButton(onPressed:_busy?null:_request,child:const Text('Request reset code')),
          ],
          if(enabled&&_step==_ResetStep.otp)...[
            Text('Challenge expires: '+_challenge!.expiresAt.toLocal().toString()),
            const SizedBox(height:12),
            TextField(controller:_otp,enabled:!_busy,maxLength:10,
              keyboardType:TextInputType.number,
              autofillHints:const [AutofillHints.oneTimeCode],
              decoration:const InputDecoration(labelText:'Verification code')),
            FilledButton(onPressed:_busy?null:_verify,child:const Text('Verify reset code')),
            TextButton(onPressed:_busy?null:_restart,child:const Text('Request a new code')),
          ],
          if(enabled&&_step==_ResetStep.password)...[
            const Text('Backend enforces password policy and history.'),
            const SizedBox(height:12),
            TextField(controller:_newPassword,enabled:!_busy,obscureText:true,
              autocorrect:false,enableSuggestions:false,
              autofillHints:const [AutofillHints.newPassword],
              decoration:const InputDecoration(labelText:'New password')),
            const SizedBox(height:12),
            TextField(controller:_confirm,enabled:!_busy,obscureText:true,
              autocorrect:false,enableSuggestions:false,
              decoration:const InputDecoration(labelText:'Confirm password')),
            FilledButton(onPressed:_busy?null:_finish,child:const Text('Reset password')),
            TextButton(onPressed:_busy?null:_restart,child:const Text('Start over')),
          ],
          if(_step==_ResetStep.complete)...[
            Text('Sessions revoked: '+_result!.sessionsRevoked.toString()),
            if(_result!.twoFactorPreserved)const Text('Two-factor protection preserved.'),
            FilledButton(onPressed:()=>Navigator.of(context).pop(true),
              child:const Text('Return to sign in')),
          ],
          if(_busy)const Padding(padding:EdgeInsets.all(12),
            child:Center(child:CircularProgressIndicator())),
          if(_status!=null)Padding(padding:const EdgeInsets.only(top:16),
            child:Text(_status!,textAlign:TextAlign.center)),
        ])))));
  }
}
