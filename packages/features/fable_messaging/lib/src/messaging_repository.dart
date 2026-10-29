import 'package:fable_core/fable_core.dart';

/// Phone-message provider Webhooks in RC66 are INBOUND SERVER routes.
/// They must NEVER be reused by Flutter as a client send endpoint.
class FableMessageOperations {
  const FableMessageOperations._(this.sendId);
  final String sendId;
  factory FableMessageOperations.fromContract(OperationCatalog contract, String sendId) {
    final op = contract.require(sendId);
    if (op.method != 'POST' || !op.requiresAuth || op.credentialHeader != null ||
        op.path.contains('{') || op.path.contains(':') || op.path.contains('?') ||
        op.path.contains('/webhooks/') || op.id.contains('webhook')) {
      throw const FormatException('Messaging requires an authenticated client send operation');
    }
    return FableMessageOperations._(op.id);
  }
}

abstract interface class FableMessageRequestEncoder {
  /// Selected external contract owns field names and destination semantics.
  Map<String, dynamic> encode({required String recipient, required String text});
}

class FableMessagingRepository {
  const FableMessagingRepository({required this.gateway,required this.operations,required this.encoder});
  final BackendApiGateway gateway;
  final FableMessageOperations operations;
  final FableMessageRequestEncoder encoder;
  Future<void> send({required String recipient, required String text}) async {
    final number = recipient.trim(), body = text.trim();
    if (!RegExp(r'^\+[1-9][0-9]{5,14}$').hasMatch(number) ||
        body.isEmpty || body.runes.length > 4096 ||
        body.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'))) {
      throw ArgumentError('Invalid message destination or body');
    }
    final encoded = encoder.encode(recipient:number,text:body);
    FableImmutablePayload.object(encoded); // bound payload, reject arbitrary objects
    await gateway.execute(operations.sendId,body:encoded);
    // No automatic retry. A timed-out POST may already have sent the message.
  }
}
