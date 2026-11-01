import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';

/// واجهة تغيير كلمة المرور تخص Auth في Fable ولا تُستخدم مع Backend خارجي.
/// نجاح الخادم يلغي جميع جلسات المستخدم، لذلك تعود الصفحة إلى Login.
/// تفاصيل الاستجابة والخطر: docs/integrations/FABLE-BACKEND-WIDE-DECISIONS-RC81.ar.md
class FableChangePasswordPage extends StatefulWidget {
  const FableChangePasswordPage({
    super.key,required this.gateway,required this.contract,
  });
  final FableAuthGateway gateway;
  final FableContract contract;

  @override State<FableChangePasswordPage> createState()=>
      _FableChangePasswordPageState();
}

class _FableChangePasswordPageState extends State<FableChangePasswordPage> {
  final _form=GlobalKey<FormState>();
  final _current=TextEditingController();
  final _newPassword=TextEditingController();
  final _confirmPassword=TextEditingController();
  bool _busy=false;
  String? _error;

  // لا نطبع قيمة الخطأ الخام ولا كلمات المرور؛ أكواد الخادم الموثقة فقط
  // تترجم إلى نص آمن. سياسة التعقيد يفرضها Backend وقد تختلف بين المشاريع.
  String _displayError(FableApiException failure) {
    switch(failure.code){
      case 'AUTH_CURRENT_PASSWORD_INVALID':
        return 'Current password was not accepted.';
      case 'AUTH_PASSWORD_TOO_SHORT':
      case 'AUTH_PASSWORD_TOO_LONG':
      case 'AUTH_PASSWORD_NEEDS_UPPERCASE':
      case 'AUTH_PASSWORD_NEEDS_LOWERCASE':
      case 'AUTH_PASSWORD_NEEDS_NUMBER':
      case 'AUTH_PASSWORD_NEEDS_SYMBOL':
      case 'AUTH_PASSWORD_TOO_SIMPLE':
      case 'AUTH_PASSWORD_TOO_COMMON':
      case 'AUTH_PASSWORD_TOO_REPETITIVE':
      case 'AUTH_PASSWORD_TOO_SEQUENTIAL':
      case 'AUTH_PASSWORD_CONTAINS_IDENTITY':
      case 'AUTH_PASSWORD_RECENT_REUSE':
        return 'New password does not meet the current Backend password policy.';
      case 'AUTH_PASSWORD_STATE_CHANGED':
        return 'Your password was changed in another request. Sign in again.';
    }
    if(failure.status==429)return 'Too many attempts. Try again later.';
    if(failure.status==401||failure.status==403)
      return 'Session is no longer authorized. Sign in again.';
    if(failure.status==409)return 'Account changed. Sign in again before trying.';
    // قد يكون الخادم نفّذ الطلب بالفعل وانقطع الرد؛ لا نكرر الطلب تلقائياً.
    return 'Password change could not be confirmed. Verify your session before retrying.';
  }

  Future<void> _submit()async{
    if(_busy||!(_form.currentState?.validate()??false))return;
    final revision=widget.gateway.session.identityRevision;
    setState((){_busy=true;_error=null;});
    try{
      await widget.gateway.changePassword(
        currentPassword:_current.text,newPassword:_newPassword.text);
      if(!mounted||widget.gateway.session.identityRevision==revision)return;
      // يحفظ مدير كلمات المرور تغيير الاعتماد فقط بعد تأكيد الخادم.
      TextInput.finishAutofillContext(shouldSave:true);
      Navigator.of(context).pop(true);
    }on FableApiException catch(e){
      if(mounted&&revision==widget.gateway.session.identityRevision)
        setState(()=>_error=_displayError(e));
    }catch(_){
      if(mounted&&revision==widget.gateway.session.identityRevision)
        setState(()=>_error=
          'Password change could not be confirmed. Verify your session before retrying.');
    }finally{
      // لا نستخدم Controller بعد dispose حتى لو عاد رد شبكي متأخر.
      if(mounted&&revision==widget.gateway.session.identityRevision)
        setState(()=>_busy=false);
    }
  }

  @override void dispose(){
    _current.clear();_newPassword.clear();_confirmPassword.clear();
    _current.dispose();_newPassword.dispose();_confirmPassword.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext context){
    final eligible=widget.contract.supports('auth.change-password');
    return Scaffold(
      appBar:AppBar(title:const Text('Change password')),
      body:SafeArea(child:Center(child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:470),
        child:ListView(padding:const EdgeInsets.all(24),children:[
          if(!eligible)const Text('Password change is not provided by this Backend contract.'),
          if(eligible)...[
            const Text('All signed-in devices will be signed out after this change.'),
            const SizedBox(height:12),
            AutofillGroup(child:Form(key:_form,child:Column(children:[
              TextFormField(controller:_current,obscureText:true,
                enableSuggestions:false,autocorrect:false,maxLength:1024,
                autofillHints:const [AutofillHints.password],
                decoration:const InputDecoration(labelText:'Current password'),
                validator:(value)=>value==null||value.isEmpty?'Required':null),
              const SizedBox(height:12),
              TextFormField(controller:_newPassword,obscureText:true,
                enableSuggestions:false,autocorrect:false,maxLength:1024,
                autofillHints:const [AutofillHints.newPassword],
                decoration:const InputDecoration(labelText:'New password'),
                validator:(value)=>value==null||value.isEmpty?'Required':
                  value==_current.text?'Choose a different password':null),
              const SizedBox(height:12),
              TextFormField(controller:_confirmPassword,obscureText:true,
                enableSuggestions:false,autocorrect:false,maxLength:1024,
                decoration:const InputDecoration(labelText:'Confirm new password'),
                validator:(value)=>value!=_newPassword.text?'Passwords do not match':null),
              const SizedBox(height:18),
              FilledButton(
                onPressed:_busy?null:_submit,
                child:Text(_busy?'Updating…':'Change password and sign out')),
            ]))),
          ],
          if(_error!=null)Padding(padding:const EdgeInsets.only(top:14),
            child:Text(_error!)),
        ]),
      ))),
    );
  }
}
