// RC29: live server authority for monetary quotes. Never persist quotes or amounts.
import 'package:dio/dio.dart';
import 'fable_api.dart';

class FableCurrentQuote {
  const FableCurrentQuote({required this.data,required this.revision});
  final dynamic data;
  final String revision;
}

/// Contract IDs must come from the selected backend; never invent URL paths.
/// The customer must confirm the exact CURRENT price before submitting.
/// The server MUST revalidate If-Match against the authoritative transaction
/// state. An HTTP refresh alone does not prevent races between read and write.
class FableFinancialFreshness {
  const FableFinancialFreshness(this.gateway);
  final BackendApiGateway gateway;
  static final _revision=RegExp(r'^[0-9a-f]{64}$');

  Future<FableCurrentQuote> currentQuote(String readOperation,
      {Map<String,dynamic>? path,CancelToken? cancelToken}) async {
    final response=await gateway.execute(readOperation,path:path,cancelToken:cancelToken);
    final raw=response.headers.value('etag');
    final etag=raw==null?null:raw.replaceAll('"','');
    if(etag==null || !_revision.hasMatch(etag)) {
      throw StateError('The backend did not provide a verified price revision; payment must be blocked');
    }
    // No persistent snapshot, no retrying a write, no offline fallback.
    return FableCurrentQuote(data:response.data,revision:etag);
  }

  Future<Response<dynamic>> submitConfirmedQuote(String writeOperation,
      {required FableCurrentQuote confirmed,Map<String,dynamic>? path,
       Object? body,CancelToken? cancelToken}) async {
    if(!_revision.hasMatch(confirmed.revision))throw StateError('Invalid confirmed quote');
    // 409 from backend => refresh price and ask user to confirm again.
    return gateway.execute(writeOperation,path:path,body:body,
      cancelToken:cancelToken,ifMatch:confirmed.revision);
  }
}
