import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'passkey_management.dart';

/// The host's callback MUST complete an independent server-verified recent
/// authentication step and return its opaque challenge UUID. The widget never
/// handles OTP secrets, raw WebAuthn keys or client-issued authorization.
typedef FableRecentPasskeyProof = Future<String?> Function();

/// Fable-only credential management, gated by the imported project contract.
/// Device/biometric registration remains a separate native user-gesture flow.
class FablePasskeyManagementPage extends StatefulWidget {
  const FablePasskeyManagementPage({super.key,required this.repository,
    required this.obtainRecentProof,this.onListChanged});
  final FablePasskeyManagementRepository repository;
  final FableRecentPasskeyProof obtainRecentProof;
  final VoidCallback? onListChanged;

  @override State<FablePasskeyManagementPage> createState()=>_PasskeysPageState();
}

class _PasskeysPageState extends State<FablePasskeyManagementPage>{
  StreamSubscription<FableIdentityEvent>? _identity;
  List<FablePasskeyCredentialInfo> _items=const [];
  bool _busy=false;
  String? _message;
  int _epoch=0;

  bool get _ar=>Localizations.localeOf(context).languageCode=='ar';
  String _t(String ar,String en)=>_ar?ar:en;

  void _watchSession(){
    _identity=widget.repository.client.session.identityEvents.listen((_){
      if(!mounted)return;
      _epoch++;
      setState((){
        _items=const [];
        _busy=false;
        _message=_t('تغيّرت جلسة الحساب. أعد التحميل.',
          'Account session changed. Reload to continue.');
      });
    });
  }

  @override void initState(){
    super.initState();
    _watchSession();
    unawaited(_refresh());
  }

  @override void didUpdateWidget(covariant FablePasskeyManagementPage old){
    super.didUpdateWidget(old);
    if(!identical(old.repository,widget.repository)){
      _epoch++;
      unawaited(_identity?.cancel());
      _watchSession();
      _items=const [];
      _busy=false;
      _message=null;
      unawaited(_refresh());
    }
  }

  @override void dispose(){
    _epoch++;
    unawaited(_identity?.cancel());
    super.dispose();
  }

  Future<void> _refresh()async{
    if(_busy)return;
    final epoch=++_epoch;
    final session=widget.repository.client.session;
    final identity=session.identityRevision;
    setState((){_busy=true;_message=null;});
    try{
      final fetched=await widget.repository.list();
      if(!mounted||_epoch!=epoch||session.identityRevision!=identity)return;
      setState(()=>_items=fetched);
    }catch(_){
      if(mounted&&_epoch==epoch&&session.identityRevision==identity){
        setState((){
          _items=const [];
          _message=_t('تعذّر جلب مفاتيح الدخول من الخادم.',
            'Passkeys could not be loaded from the server.');
        });
      }
    }finally{
      if(mounted&&_epoch==epoch)setState(()=>_busy=false);
    }
  }

  Future<void> _remove(FablePasskeyCredentialInfo credential)async{
    if(_busy)return;
    final session=widget.repository.client.session;
    final identity=session.identityRevision;
    final epoch=++_epoch;
    setState((){_busy=true;_message=null;});
    var removed=false;
    try{
      final confirmed=await showDialog<bool>(
        context:context,
        builder:(context)=>AlertDialog(
          title:Text(_t('حذف مفتاح الدخول؟','Remove this passkey?')),
          content:Text(_t(
            'قد تفقد الوصول إلى حسابك إذا كان هذا آخر وسيلة لتسجيل الدخول. سيتحقق الخادم من وسائل الاسترداد.',
            'Removing your last sign-in method could lock you out. The server will verify recovery methods.')),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(context,false),
              child:Text(_t('إلغاء','Cancel'))),
            FilledButton(onPressed:()=>Navigator.pop(context,true),
              child:Text(_t('متابعة الحذف','Continue'))),
          ],
        ),
      );
      if(confirmed!=true||!mounted||_epoch!=epoch||
         session.identityRevision!=identity)return;
      final proof=await widget.obtainRecentProof();
      if(proof==null||!mounted||_epoch!=epoch||
         session.identityRevision!=identity)return;
      removed=await widget.repository.remove(
        credentialId:credential.id,securityChallengeId:proof);
      if(!mounted||_epoch!=epoch||session.identityRevision!=identity)return;
      if(!removed){
        setState(()=>_message=_t('لم يؤكد الخادم حذف المفتاح.',
          'The server did not confirm passkey removal.'));
      }
    }catch(_){
      if(mounted&&_epoch==epoch&&session.identityRevision==identity){
        setState(()=>_message=_t(
          'تعذّر حذف المفتاح. تحقق من صلاحية التفويض وطريقة تسجيل الدخول البديلة.',
          'Removal failed. Check recent authorization and alternative sign-in methods.'));
      }
    }finally{
      if(mounted&&_epoch==epoch)setState(()=>_busy=false);
    }
    if(removed&&mounted&&_epoch==epoch&&session.identityRevision==identity){
      widget.onListChanged?.call();
      await _refresh();
    }
  }

  @override Widget build(BuildContext context){
    final canList=widget.repository.operations.listId!=null;
    return Scaffold(
      appBar:AppBar(
        title:Text(_t('مفاتيح الدخول','Passkeys')),
        actions:[
          IconButton(
            tooltip:_t('تحديث','Refresh'),
            onPressed:_busy||!canList?null:()=>unawaited(_refresh()),
            icon:const Icon(Icons.refresh),
          ),
        ],
      ),
      body:SafeArea(child:ListView(
        padding:const EdgeInsets.all(16),
        children:[
          Text(_t('إدارة مفاتيح المرور المرتبطة بحسابك. لا تُرسل البيانات الحيوية إلى الخادم.',
            'Manage passkeys linked to your account. Your biometric data never leaves your device.')),
          const SizedBox(height:16),
          if(!canList)Text(_t(
            'هذا المشروع لا يوفّر عملية عرض مفاتيح الدخول في عقده المعتمد.',
            'This project does not export a verified passkey-list operation.')),
          if(_busy)const LinearProgressIndicator(),
          if(_message!=null)Padding(
            padding:const EdgeInsets.symmetric(vertical:12),
            child:Text(_message!),
          ),
          if(canList&&!_busy&&_items.isEmpty&&_message==null)
            Padding(padding:const EdgeInsets.symmetric(vertical:16),
              child:Text(_t('لا توجد مفاتيح دخول مسجلة.','No passkeys registered.'))),
          for(final credential in _items)
            Card(child:ListTile(
              leading:const Icon(Icons.fingerprint),
              title:Text(credential.label?.trim().isNotEmpty==true
                ?credential.label!
                :_t('مفتاح دخول','Passkey')),
              subtitle:Text([
                if(credential.deviceType!=null)credential.deviceType!,
                credential.backedUp
                  ?_t('قابل للمزامنة','Backed up')
                  :_t('مرتبط بجهاز','Device-bound'),
                if(credential.lastUsedAt!=null)
                  _t('آخر استخدام: ','Last used: ')+credential.lastUsedAt!,
              ].join(' · ')),
              trailing:IconButton(
                tooltip:_t('حذف','Remove'),
                onPressed:_busy?null:()=>unawaited(_remove(credential)),
                icon:const Icon(Icons.delete_outline),
              ),
            )),
        ],
      )),
    );
  }
}
