import 'package:fable_core/fable_core.dart';

/// Support APIs are NOT part of RC66. Bind a real authenticated client API from
/// an imported contract; a support keyword in the catalog is not an API.
class FableSupportOperations {
  const FableSupportOperations._(this.listId, this.createId);
  final String listId, createId;
  factory FableSupportOperations.fromContract(OperationCatalog catalog,
      {required String listOperationId, required String createOperationId}) {
    final list = catalog.require(listOperationId);
    final create = catalog.require(createOperationId);
    for (final op in [list, create]) {
      if (!op.requiresAuth || op.credentialHeader != null ||
          op.path.contains('{') || op.path.contains(':') || op.path.contains('?')) {
        throw const FormatException('Support requires authenticated fixed-path operations');
      }
    }
    if (list.method != 'GET' || create.method != 'POST' || list.id == create.id) {
      throw const FormatException('Invalid support client operations');
    }
    return FableSupportOperations._(list.id, create.id);
  }
}

class FableSupportTicket {
  const FableSupportTicket._(this.id, this.subject, this.status, this.raw);
  final String id, subject, status;
  final Map<String, dynamic> raw;
  factory FableSupportTicket.fromJson(Object? value) {
    final data = FableImmutablePayload.object(value);
    final id = data['id'], subject = data['subject'], status = data['status'];
    if (id is! String || id.isEmpty || id.length > 128 ||
        subject is! String || subject.isEmpty || subject.length > 500 ||
        status is! String || status.isEmpty || status.length > 80) {
      throw const FormatException('Invalid support ticket');
    }
    return FableSupportTicket._(id, subject, status, data);
  }
}

typedef FableSupportListDecoder = List<FableSupportTicket> Function(Object? result);

abstract interface class FableSupportRequestEncoder {
  Map<String, dynamic> encode({required String subject, required String description});
}

class FableSupportRepository {
  const FableSupportRepository({required this.gateway, required this.operations,
      required this.decodeList, required this.encoder});
  final BackendApiGateway gateway;
  final FableSupportOperations operations;
  /// External backend must supply an explicit schema decoder; unknown envelopes
  /// cannot be treated as tickets.
  final FableSupportListDecoder decodeList;
  final FableSupportRequestEncoder encoder;
  Future<List<FableSupportTicket>> list() async {
    final response = await gateway.execute(operations.listId);
    return List<FableSupportTicket>.unmodifiable(decodeList(response.data));
  }
  Future<void> create({required String subject, required String description}) async {
    final s = subject.trim(), d = description.trim();
    if (s.length < 2 || s.length > 200 || d.length < 2 || d.length > 5000 ||
        s.contains(RegExp(r'[\x00-\x1f]')) || d.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'))) {
      throw ArgumentError('Invalid support ticket content');
    }
    final payload=encoder.encode(subject:s,description:d);
    FableImmutablePayload.object(payload);
    await gateway.execute(operations.createId,body:payload);
  }
}
