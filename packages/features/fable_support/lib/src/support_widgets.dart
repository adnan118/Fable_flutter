import 'package:material_ui/material_ui.dart';
import 'support_repository.dart';

/// Neutral support list. It never displays unknown raw ticket fields.
class FableSupportTicketList extends StatefulWidget {
  const FableSupportTicketList({super.key,required this.repository});
  final FableSupportRepository repository;
  @override State<FableSupportTicketList> createState()=>_FableSupportTicketListState();
}
class _FableSupportTicketListState extends State<FableSupportTicketList> {
  Future<List<FableSupportTicket>>? _load;
  @override void initState(){super.initState();_load=widget.repository.list();}
  @override void didUpdateWidget(covariant FableSupportTicketList old){
    super.didUpdateWidget(old);
    if(!identical(old.repository,widget.repository)) _load=widget.repository.list();
  }
  @override Widget build(BuildContext context)=>FutureBuilder<List<FableSupportTicket>>(
    future:_load,builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError)return const Text('Support unavailable. Please retry later.');
      return Column(mainAxisSize:MainAxisSize.min,children:[
        for(final ticket in (snapshot.data??const <FableSupportTicket>[]).take(50))
          ListTile(title:Text(ticket.subject),subtitle:Text(ticket.status)),
      ]);
    });
}
