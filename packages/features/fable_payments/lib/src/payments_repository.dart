import 'package:fable_core/fable_core.dart';

/// Financial capability exposes VERIFIED READ ONLY status. Checkout, capture,
/// refund and settlement require payment-specific idempotency and verified
/// server quotes; the generic BackendApiGateway does not expose those contracts.
class FablePaymentOperations {
  const FablePaymentOperations._(this.readId);
  final String readId;
  factory FablePaymentOperations.fromContract(OperationCatalog catalog,String readId) {
    final op = catalog.require(readId);
    if (op.method != 'GET' || !op.requiresAuth || op.credentialHeader != null ||
        !op.path.contains('{id}') ||
        op.path.contains('/admin/') || op.path.contains('?')) {
      throw const FormatException('Payments require authenticated individual read operation');
    }
    return FablePaymentOperations._(op.id);
  }
  factory FablePaymentOperations.fable(OperationCatalog catalog) =>
    FablePaymentOperations.fromContract(catalog,'financial.payment.read');
}

class FablePaymentSnapshot {
  const FablePaymentSnapshot._(this.id,this.status,this.raw);
  final String id,status;
  final Map<String,dynamic> raw;
  factory FablePaymentSnapshot.fromJson(Object? value) {
    final data = FableImmutablePayload.object(value);
    final id = data['id'], status = data['status'];
    if (id is! String || id.isEmpty || id.length > 128 || status is! String ||
        !RegExp(r'^[A-Z_]{2,64}$').hasMatch(status)) {
      throw const FormatException('Invalid payment state');
    }
    return FablePaymentSnapshot._(id,status,data);
  }
}

typedef FablePaymentDecoder = FablePaymentSnapshot Function(Object? response);
class FablePaymentReadRepository {
  const FablePaymentReadRepository({required this.gateway,required this.operations,required this.decode});
  final BackendApiGateway gateway;
  final FablePaymentOperations operations;
  final FablePaymentDecoder decode;
  Future<FablePaymentSnapshot> read(String id) async {
    if (!RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',caseSensitive:false).hasMatch(id)) {
      throw ArgumentError('Invalid payment ID');
    }
    final response = await gateway.execute(operations.readId,path:{'id':id});
    return decode(response.data);
  }
}
