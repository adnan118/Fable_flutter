import 'package:flutter/widgets.dart';
import 'access_snapshot.dart';

/// Visual convenience only. Backend remains the sole authority.
class FablePermissionGate extends StatelessWidget {
  final FableAccessSnapshot? snapshot;
  final List<String> permissions;
  final Widget child;
  final Widget fallback;
  const FablePermissionGate({super.key, required this.snapshot,
    required this.permissions, required this.child,
    this.fallback = const SizedBox.shrink()});
  @override
  Widget build(BuildContext context) =>
    snapshot != null && snapshot!.canAll(permissions) ? child : fallback;
}
