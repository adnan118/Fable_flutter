import 'package:material_ui/material_ui.dart';

/// UI states are deliberately independent from a specific networking package,
/// architecture style or backend. A feature decides which state is appropriate.
enum FableContentState { loading, ready, empty, error, offline }

/// Text can be supplied by a runtime localization provider. Bundled fallbacks
/// make critical error states usable before remote translations are available.
@immutable
class FableStateCopy {
  const FableStateCopy({required this.loading, required this.empty,
    required this.error, required this.offline, required this.retry});

  final String loading, empty, error, offline, retry;

  static const english = FableStateCopy(
    loading: 'Loading', empty: 'Nothing to show yet',
    error: 'Could not load this content',
    offline: 'This content is unavailable without a connection',
    retry: 'Try again');
  static const arabic = FableStateCopy(
    loading: 'جارٍ التحميل', empty: 'لا يوجد محتوى لعرضه بعد',
    error: 'تعذّر تحميل المحتوى',
    offline: 'هذا المحتوى غير متاح دون اتصال بالإنترنت',
    retry: 'إعادة المحاولة');

  static FableStateCopy forLocale(Locale locale) =>
      locale.languageCode == 'ar' ? arabic : english;
}

/// Accessible, theme-aware states shared by every feature and backend adapter.
/// A retry action appears *only* if the caller supplies a real callback.
/// Do not infer offline state from an arbitrary exception: choose it only
/// when a feature has positively identified that condition.
class FableStateView extends StatelessWidget {
  const FableStateView({super.key, required this.state, this.child,
    this.onRetry, this.copy, this.message, this.maxWidth = 420});

  final FableContentState state;
  final Widget? child;
  final VoidCallback? onRetry;
  final FableStateCopy? copy;
  final String? message;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (state == FableContentState.ready) {
      if (child == null) throw StateError('Ready content requires a child');
      return child!;
    }
    final words = copy ?? FableStateCopy.forLocale(
      Localizations.maybeLocaleOf(context) ?? const Locale('en'));
    if (state == FableContentState.loading) {
      return Center(child: Semantics(
        liveRegion: true, label: words.loading,
        child: ExcludeSemantics(child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: const SizedBox(height: 104, child: Center(child: CircularProgressIndicator()))))));
    }
    final title = switch (state) {
      FableContentState.empty => words.empty,
      FableContentState.error => words.error,
      FableContentState.offline => words.offline,
      _ => words.error,
    };
    final icon = switch (state) {
      FableContentState.empty => Icons.inbox_outlined,
      FableContentState.offline => Icons.wifi_off_rounded,
      _ => Icons.error_outline,
    };
    return Center(child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: const EdgeInsets.all(24),
        child: Semantics(liveRegion: true, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
            if (message != null && message!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(message!, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry,
                icon: const Icon(Icons.refresh), label: Text(words.retry)),
            ],
          ],
        )),
      ),
    ));
  }
}
