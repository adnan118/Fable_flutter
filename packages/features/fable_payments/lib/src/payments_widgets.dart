import 'package:material_ui/material_ui.dart';
import 'payments_repository.dart';

/// Read-only payment state. No checkout, capture or refund action is inferred.
class FablePaymentStatusCard extends StatefulWidget {
  const FablePaymentStatusCard({super.key,required this.repository,required this.paymentId});
  final FablePaymentReadRepository repository; final String paymentId;
  @override State<FablePaymentStatusCard> createState()=>_FablePaymentStatusCardState();
}
class _FablePaymentStatusCardState extends State<FablePaymentStatusCard>{
  Future<FablePaymentSnapshot>? _load;
  @override void initState(){super.initState();_load=widget.repository.read(widget.paymentId);}
  @override void didUpdateWidget(covariant FablePaymentStatusCard old){super.didUpdateWidget(old);
    if(!identical(old.repository,widget.repository)||old.paymentId!=widget.paymentId){
      _load=widget.repository.read(widget.paymentId);}}
  @override Widget build(BuildContext context)=>FutureBuilder<FablePaymentSnapshot>(
    future:_load,builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
      if(snapshot.hasError)return const Text('Payment status unavailable.');
      return ListTile(title:const Text('Payment status'),subtitle:Text(snapshot.data?.status??'Unknown'));
    });
}
