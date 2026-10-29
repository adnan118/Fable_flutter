import 'package:flutter/widgets.dart';
import 'package:fable_design_system/fable_design_system.dart';
import 'access_policy.dart';

/// Ready-to-use action that derives VISIBILITY from the verified operationId.
/// No per-screen role/permission `if` statements and no Fable-only semantics.
/// The app still supplies the actual action callback; the server authorizes it.
enum FableUnauthorizedBehavior { hide, disable }

class FableAuthorizedAsyncButton extends StatelessWidget {
  const FableAuthorizedAsyncButton({super.key,
    required this.operationId, required this.label, required this.onExecute,
    this.confirmTitle, this.confirmMessage, this.requireConfirmation = false,
    this.isDestructive = false, this.enabled = true, this.onSucceeded,
    this.fallback = const SizedBox.shrink(),
    this.unauthorizedBehavior = FableUnauthorizedBehavior.hide});

  final String operationId, label;
  final Future<void> Function() onExecute;
  final String? confirmTitle, confirmMessage;
  final bool requireConfirmation, isDestructive, enabled;
  final VoidCallback? onSucceeded;
  final Widget fallback;
  final FableUnauthorizedBehavior unauthorizedBehavior;

  @override
  Widget build(BuildContext context) {
    final allowed = FableAccessScope.maybeOf(context)?.allows(operationId) ?? false;
    if (!allowed && unauthorizedBehavior == FableUnauthorizedBehavior.hide) return fallback;
    return FableAsyncActionButton(
      label: label, onExecute: onExecute,
      confirmTitle: confirmTitle, confirmMessage: confirmMessage,
      requireConfirmation: requireConfirmation,
      isDestructive: isDestructive, enabled: enabled && allowed,
      onSucceeded: onSucceeded,
    );
  }
}

/// Screen-level protection, including deep-linked or manually navigated pages.
/// It is a PRESENTATION gate, not an authorization boundary.
class FableAuthorizedScreen extends StatelessWidget {
  const FableAuthorizedScreen({super.key,required this.operationId,
    required this.child,this.fallback = const SizedBox.shrink()});
  final String operationId;
  final Widget child, fallback;

  @override
  Widget build(BuildContext context) => FableOperationVisibility(
    operationId: operationId, child: child, fallback: fallback);
}
