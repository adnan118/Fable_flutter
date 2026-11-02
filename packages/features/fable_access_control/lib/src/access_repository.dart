import 'package:fable_core/fable_core.dart';
import 'access_snapshot.dart';

/// Operation-based access snapshot. No Fable route is hardcoded.
/// For Other Backend, supply a verified operation ID and field mappings.
class FableAccessRepository {
  const FableAccessRepository(this.gateway, {
    required this.operationId,
    this.userIdField = 'userId',
    this.permissionsField = 'keys',
    this.rolesField = 'roles',
    this.requiresFableSuccessEnvelope = false,
  });
  final BackendApiGateway gateway;
  final String operationId;
  final String userIdField, permissionsField, rolesField;
  /// Fable RC66 always wraps GET /permissions/me in {success:true,data:{...}}.
  /// Other Backend uses its explicitly mapped response shape instead.
  final bool requiresFableSuccessEnvelope;

  /// Reads only the verified operationId; provider-specific paths belong in
  /// BackendApiGateway, not in access widgets.
  factory FableAccessRepository.fromPolicy(BackendApiGateway gateway,
      Map<String, dynamic> policy) {
    if (policy['kind'] != 'fable.mobile-access-policy' || policy['snapshot'] is! Map) {
      throw const FormatException('Access snapshot operation not configured');
    }
    if (!const {'fable','other'}.contains(policy['provider'])) {
      throw const FormatException('Access policy provider not configured');
    }
    final mapped = policy['snapshot'] as Map;
    final id = mapped['operationId'];
    if (id is! String || id.isEmpty) throw const FormatException('Invalid access operation');
    return FableAccessRepository(gateway, operationId: id,
      userIdField: mapped['userIdField'] as String? ?? 'userId',
      permissionsField: mapped['permissionsField'] as String? ?? 'keys',
      rolesField: mapped['rolesField'] as String? ?? 'roles',
      requiresFableSuccessEnvelope:policy['provider']=='fable');
  }

  Future<FableAccessSnapshot> current() async {
    if (operationId.isEmpty) throw StateError('Access operation is not bound');
    final response = await gateway.execute(operationId);
    final responseData = response.data;
    Object? data = responseData;
    if (requiresFableSuccessEnvelope) {
      if (responseData is! Map || responseData['success'] != true ||
          responseData['data'] is! Map) {
        throw const FormatException('Fable did not confirm the access snapshot');
      }
      data = responseData['data'];
    }
    if (data is! Map) {
      throw const FormatException('Access snapshot response must be an object');
    }
    // Snapshot mapping and authorization keys always come from this response,
    // never from local role guesses or a stale cached token.
    return FableAccessSnapshot.fromJson(Map<String,dynamic>.from(data),
      userIdField:userIdField, permissionsField:permissionsField,
      rolesField:rolesField);
  }
}
