import 'package:material_ui/material_ui.dart';

/// A universal action primitive for optional capabilities and either Backend.
/// The caller provides a contract-verified operation; this widget never
/// constructs a URL, retries a write, or assumes transaction success.
class FableAsyncActionButton extends StatefulWidget {
  const FableAsyncActionButton({super.key, required this.label,
    required this.onExecute, this.confirmTitle, this.confirmMessage,
    this.requireConfirmation = false, this.isDestructive = false,
    this.enabled = true, this.onSucceeded});
  final String label;
  final Future<void> Function() onExecute;
  final String? confirmTitle, confirmMessage;
  final bool requireConfirmation, isDestructive, enabled;
  final VoidCallback? onSucceeded;
  @override State<FableAsyncActionButton> createState() => _FableAsyncActionButtonState();
}

class _FableAsyncActionButtonState extends State<FableAsyncActionButton> {
  bool _busy = false;
  bool _confirming = false;
  String? _error;
  bool get _ar => Localizations.maybeLocaleOf(context)?.languageCode == 'ar';

  Future<void> _execute() async {
    if (_busy || !widget.enabled) return;
    // Reserve the action immediately to prevent double taps during the dialog.
    setState(() {
      _busy = true;
      _confirming = widget.requireConfirmation || widget.isDestructive;
      _error = null;
    });
    try {
      if (widget.requireConfirmation || widget.isDestructive) {
        final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: Text(widget.confirmTitle ?? (_ar ? 'تأكيد الإجراء' : 'Confirm action')),
          content: Text(widget.confirmMessage ?? (_ar ? 'هل تريد تنفيذ هذا الإجراء؟' : 'Do you want to proceed?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_ar ? 'رجوع' : 'Back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_ar ? 'تأكيد' : 'Confirm')),
          ],
        ));
        if (confirmed != true || !mounted) return;
        setState(() => _confirming = false);
      }
      await widget.onExecute();
      if (mounted) widget.onSucceeded?.call();
    } catch (_) {
      // Do not expose backend exception contents, credentials or private payload.
      if (mounted) setState(() => _error = _ar
        ? 'تعذّر تنفيذ الإجراء. تحقّق من النتيجة قبل إعادة المحاولة.'
        : 'Action could not be confirmed. Verify the outcome before trying again.');
    } finally {
      if (mounted) setState(() { _busy = false; _confirming = false; });
    }
  }

  @override Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FilledButton(
        onPressed: widget.enabled && !_busy ? _execute : null,
        child: _busy && !_confirming ? const SizedBox(width:20, height:20,
          child: CircularProgressIndicator(strokeWidth:2)) : Text(widget.label),
      ),
      if (_error != null) Padding(
        padding: const EdgeInsets.only(top:8),
        child: Semantics(liveRegion:true, child:Text(_error!,
          style:TextStyle(color:Theme.of(context).colorScheme.error))),
      ),
    ],
  );
}
