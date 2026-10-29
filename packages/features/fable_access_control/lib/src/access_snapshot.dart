/// Response-preserving access snapshot for any backend provider.
/// Authorization MUST still be enforced by the server.
class FableAccessSnapshot {
  final String userId;
  final List<String> keys;
  final List<String> roles;
  final Map<String, dynamic> raw;
  final Map<String, dynamic> additionalFields;
  const FableAccessSnapshot({required this.userId, required this.keys,
    required this.roles, required this.raw, required this.additionalFields});

  factory FableAccessSnapshot.fromJson(Map<String, dynamic> json, {
    String userIdField = 'userId', String permissionsField = 'keys',
    String rolesField = 'roles',
  }) {
    dynamic readField(String path) {
      dynamic current = json;
      for (final segment in path.split('.')) {
        if (current is! Map || !current.containsKey(segment)) return null;
        current = current[segment];
      }
      return current;
    }
    List<String> readStrings(String key) {
      final value = readField(key);
      if (value == null) return <String>[];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('Invalid access field: $key');
      }
      return List<String>.unmodifiable(value.cast<String>());
    }
    final id = readField(userIdField);
    if (id is! String || id.trim().isEmpty) throw FormatException('Missing user ID');
    final raw = Map<String, dynamic>.unmodifiable(json);
    final extra = Map<String, dynamic>.of(json)
      ..remove(userIdField)..remove(permissionsField)..remove(rolesField);
    return FableAccessSnapshot(userId: id, keys: readStrings(permissionsField),
      roles: readStrings(rolesField), raw: raw,
      additionalFields: Map<String, dynamic>.unmodifiable(extra));
  }

  bool can(String permission) => keys.contains(permission);
  bool canAll(Iterable<String> permissions) => permissions.every(can);
  bool hasRole(String roleKey) => roles.contains(roleKey);
  Map<String,dynamic> toJson() => Map<String,dynamic>.of(raw);
}
