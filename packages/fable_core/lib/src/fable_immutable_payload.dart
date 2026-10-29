/// Read-only snapshot of a verified JSON response. Unknown fields remain
/// available to contract adapters without being rendered, logged, or persisted.
/// A response that exceeds the safety bounds is rejected, never truncated.
class FableImmutablePayload {
  const FableImmutablePayload._();

  static Map<String, dynamic> object(Object? value) {
    final count = _NodeBudget();
    final frozen = _freeze(value, 0, count);
    if (frozen is! Map<String, dynamic>) {
      throw const FormatException('Backend response must be a JSON object');
    }
    return frozen;
  }

  static Object? _freeze(Object? value, int depth, _NodeBudget budget) {
    budget.nodes++;
    if (depth > 24 || budget.nodes > 20000) {
      throw const FormatException('Backend response exceeds safe JSON bounds');
    }
    if (value is double && !value.isFinite) {
      throw const FormatException('Invalid non-finite JSON number');
    }
    if (value == null || value is bool || value is num) return value;
    if (value is String) {
      if (value.length > 250000) throw const FormatException('Oversized JSON text');
      return value;
    }
    if (value is List) {
      if (value.length > 10000) throw const FormatException('Oversized JSON array');
      return List<Object?>.unmodifiable(
        value.map((entry) => _freeze(entry, depth + 1, budget)));
    }
    if (value is Map) {
      if (value.length > 2000) throw const FormatException('Oversized JSON object');
      final frozen = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String || key.length > 500) {
          throw const FormatException('Invalid JSON object key');
        }
        frozen[key] = _freeze(entry.value, depth + 1, budget);
      }
      return Map<String, dynamic>.unmodifiable(frozen);
    }
    throw const FormatException('Unsupported JSON payload value');
  }
}

class _NodeBudget { int nodes = 0; }
