import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'analytics_repository.dart';

/// RC315 — optional, source-only privacy control for a *host-supplied* tracker.
///
/// No implicit Analytics provider, URL, SDK, persistence or HTTP request.
/// The host owns its reviewed sink and supplies a trusted identity revision
/// and eligibility predicate. Every newly mounted identity must opt in anew.
class FableAnalyticsConsentPanel extends StatefulWidget {
  const FableAnalyticsConsentPanel({
    super.key,
    required this.tracker,
    required this.identityRevision,
    required this.identityInvalidations,
    required this.mayCollect,
  });
  final FableAnalyticsTracker tracker;
  final int Function() identityRevision;
  final Stream<void> identityInvalidations;
  final bool Function() mayCollect;

  @override
  State<FableAnalyticsConsentPanel> createState() =>
      _FableAnalyticsConsentPanelState();
}

class _FableAnalyticsConsentPanelState
    extends State<FableAnalyticsConsentPanel> {
  StreamSubscription<void>? _identitySubscription;
  int? _boundIdentityRevision;

  @override
  void initState() {
    super.initState();
    // A reused tracker must never carry consent into a newly displayed host.
    widget.tracker.setConsent(false);
    _bindIdentity();
  }

  int? _safeRevision() {
    try {
      return widget.identityRevision();
    } catch (_) {
      // Identity providers are host-supplied; a failure stays ineligible.
      return null;
    }
  }

  void _bindIdentity() {
    _boundIdentityRevision = _safeRevision();
    _identitySubscription = widget.identityInvalidations.listen((_) {
      // Revoke immediately, before the scheduled UI rebuild.
      widget.tracker.setConsent(false);
      if (!mounted) return;
      setState(() {
        _boundIdentityRevision = _safeRevision();
      });
    });
  }

  @override
  void didUpdateWidget(covariant FableAnalyticsConsentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tracker, widget.tracker) ||
        !identical(oldWidget.identityInvalidations,
            widget.identityInvalidations)) {
      oldWidget.tracker.setConsent(false);
      unawaited(_identitySubscription?.cancel());
      _identitySubscription = null;
      widget.tracker.setConsent(false);
      _bindIdentity();
    }
  }

  bool _isEligible() {
    try {
      final revision = _safeRevision();
      return revision != null && _boundIdentityRevision != null &&
          widget.mayCollect() && revision == _boundIdentityRevision;
    } catch (_) {
      // Unknown identity or eligibility must never grant collection.
      return false;
    }
  }

  void _toggle(bool value) {
    // Re-read identity at the moment of user interaction.
    if (!_isEligible()) {
      widget.tracker.setConsent(false);
      if (mounted) setState(() {});
      return;
    }
    widget.tracker.setConsent(value);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Consent is scoped to the lifetime of this particular host panel.
    widget.tracker.setConsent(false);
    unawaited(_identitySubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eligible = _isEligible();
    if (!eligible && widget.tracker.hasConsent) {
      // Fail closed even if a host identity revision changed before its
      // asynchronous invalidation notification reaches this widget.
      widget.tracker.setConsent(false);
    }
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final optedIn = eligible && widget.tracker.hasConsent;
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: Text(ar ? 'الموافقة على إحصاءات الاستخدام'
                : 'Share optional usage analytics'),
            subtitle: Text(ar
                ? 'اختياري تمامًا. لا تُجمع أحداث دون موافقتك، وتُلغى الموافقة عند تغيير الحساب.'
                : 'Optional. No events are queued without your consent. Changing accounts revokes it.'),
            value: optedIn,
            onChanged: eligible ? _toggle : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              !eligible
                  ? (ar ? 'لا يمكن تفعيل الجمع قبل التحقق من الجلسة.'
                      : 'Analytics is unavailable until the host verifies the session.')
                  : optedIn
                      ? (ar ? 'الأحداث قيد الانتظار: ${widget.tracker.pendingCount}'
                          : 'Queued events: ${widget.tracker.pendingCount}')
                      : (ar ? 'جمع الأحداث متوقف. لا يتم إرسال أي شيء من هذه الواجهة.'
                          : 'Collection is off. This panel never sends data by itself.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
