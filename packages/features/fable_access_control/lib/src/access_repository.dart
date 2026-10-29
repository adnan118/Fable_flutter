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
  });
  final BackendApiGateway gateway;
  final String operationId;
  final String userIdField, permissionsField, rolesField;

  /// Reads only the verified operationId; provider-specific paths belong in
  /// BackendApiGateway, not in access widgets.
  factory FableAccessRepository.fromPolicy(BackendApiGateway gateway,
      Map<String, dynamic> policy) {
    if (policy['kind'] != 'fable.mobile-access-policy' || policy['snapshot'] is! Map) {
      throw const FormatException('Access snapshot operation not configured');
    }
    final mapped = policy['snapshot'] as Map;
    final id = mapped['operationId'];
    if (id is! String || id.isEmpty) throw const FormatException('Invalid access operation');
    return FableAccessRepository(gateway, operationId: id,
      userIdField: mapped['userIdField'] as String? ?? 'userId',
      permissionsField: mapped['permissionsField'] as String? ?? 'keys',
      rolesField: mapped['rolesField'] as String? ?? 'roles');
  }

  Future<FableAccessSnapshot> current() async {
    if (operationId.isEmpty) throw StateError('Access operation is not bound');
    final response = await gateway.execute(operationId);
    final data = response.data;
    if (data is! Map) throw const FormatException('Access snapshot response must be an object');
    return FableAccessSnapshot.fromJson(Map<String,dynamic>.from(data),
      userIdField:userIdField, permissionsField:permissionsField,
      rolesField:rolesField);
  }
}
