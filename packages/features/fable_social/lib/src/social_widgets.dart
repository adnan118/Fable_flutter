import 'package:material_ui/material_ui.dart';
import 'social_auth_repository.dart';

/// Ready-to-use button; OAuth secrets stay in the injected, native SDK adapter.
/// The widget never stores challenge state or renders backend tokens.
class FableSocialSignInButton extends StatefulWidget {
  const FableSocialSignInButton({super.key, required this.repository,
    required this.provider, this.onResult});
  final FableSocialRepository repository;
  final FableSocialProvider provider;
  final ValueChanged<FableSocialAuthResult>? onResult;
  @override State<FableSocialSignInButton> createState() => _FableSocialSignInButtonState();
}
class _FableSocialSignInButtonState extends State<FableSocialSignInButton> {
  bool _loading = false;
  int _revision = 0;
  String? _error;
  @override void didUpdateWidget(covariant FableSocialSignInButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) || oldWidget.provider != widget.provider) {
      _revision++; _loading=false; _error=null;
    }
  }
  @override void dispose() { _revision++; super.dispose(); }
  Future<void> _signIn() async {
    if (_loading) return;
    final revision = ++_revision;
    setState(() { _loading=true; _error=null; });
    try {
      final result = await widget.repository.signIn(widget.provider);
      if (mounted && revision == _revision && result != null) widget.onResult?.call(result);
    } catch (_) {
      if (mounted && revision == _revision) setState(() =>
        _error='Social sign-in unavailable. Verify your account provider and connection.');
    } finally {
      if (mounted && revision == _revision) setState(() => _loading=false);
    }
  }
  @override Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min,
    children: [OutlinedButton.icon(onPressed:_loading?null:_signIn,
      icon: Icon(widget.provider==FableSocialProvider.apple?Icons.apple:Icons.login),
      label:Text(_loading?'Connecting…':'Continue with ${widget.provider==FableSocialProvider.apple?'Apple':'Google'}')),
      if (_error!=null) Text(_error!, style:Theme.of(context).textTheme.bodySmall)],
  );
}
