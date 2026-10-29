import 'package:material_ui/material_ui.dart';
import 'messaging_repository.dart';

/// Only shown after a VERIFIED external client-send operation is configured.
class FableMessageComposer extends StatefulWidget {
  const FableMessageComposer({super.key,required this.repository});
  final FableMessagingRepository repository;
  @override State<FableMessageComposer> createState()=>_FableMessageComposerState();
}
class _FableMessageComposerState extends State<FableMessageComposer>{
  final _recipient=TextEditingController(),_text=TextEditingController();
  bool _busy=false;int _epoch=0;String? _notice;
  @override void didUpdateWidget(covariant FableMessageComposer old){super.didUpdateWidget(old);
    if(!identical(old.repository,widget.repository)){_epoch++;_notice=null;_busy=false;
      _recipient.clear();_text.clear();}}
  @override void dispose(){_epoch++;_recipient.dispose();_text.dispose();super.dispose();}
  Future<void> _send() async {
    if(_busy)return;final epoch=++_epoch;setState((){_busy=true;_notice=null;});
    try{await widget.repository.send(recipient:_recipient.text,text:_text.text);
      if(mounted&&epoch==_epoch){_text.clear();setState(()=>_notice='Request submitted');}}
    catch(_){if(mounted&&epoch==_epoch)setState(()=>_notice='Sending failed. Check the destination.');}
    finally{if(mounted&&epoch==_epoch)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Column(mainAxisSize:MainAxisSize.min,children:[
    TextField(controller:_recipient,decoration:const InputDecoration(labelText:'Phone (+country code)')),
    TextField(controller:_text,maxLength:4096,maxLines:4,decoration:const InputDecoration(labelText:'Message')),
    FilledButton(onPressed:_busy?null:_send,child:Text(_busy?'Sending…':'Send')),
    if(_notice!=null)Text(_notice!)
  ]);
}
