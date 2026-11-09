import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'support_repository.dart';

/// A real support workflow ONLY after a developer binds a verified project
/// or Other Backend client operation, DTO encoder and list decoder.
/// The UI never infers a support endpoint from a feature keyword.
class FableSupportWorkflowPage extends StatefulWidget {
  const FableSupportWorkflowPage({
    super.key,
    required this.repository,
    required this.identityRevision,
    required this.isAuthenticated,
    required this.identityInvalidations,
  });

  final FableSupportWorkflowPort repository;
  final int Function() identityRevision;
  final bool Function() isAuthenticated;
  final Stream<void> identityInvalidations;

  @override
  State<FableSupportWorkflowPage> createState() =>
      _FableSupportWorkflowPageState();
}

class _FableSupportWorkflowPageState extends State<FableSupportWorkflowPage> {
  final _subject = TextEditingController();
  final _description = TextEditingController();
  StreamSubscription<void>? _identitySub;
  int _generation = 0;
  List<FableSupportTicket>? _tickets;
  int? _ticketsIdentity;
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _identitySub = widget.identityInvalidations.listen((_) {
      if (!mounted) return;
      _clearPrivateState();
    });
  }

  void _clearPrivateState() {
    _generation++;
    _subject.clear();
    _description.clear();
    setState(() {
      _tickets = null;
      _ticketsIdentity = null;
      _busy = false;
      _message = null;
      _error = null;
    });
  }

  @override
  void didUpdateWidget(covariant FableSupportWorkflowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.identityInvalidations, widget.identityInvalidations) ||
        oldWidget.identityRevision != widget.identityRevision ||
        oldWidget.isAuthenticated != widget.isAuthenticated) {
      unawaited(_identitySub?.cancel());
      _clearPrivateState();
      _listen();
    }
  }

  bool _current(int generation, int identity) =>
      mounted && generation == _generation &&
      widget.identityRevision() == identity &&
      widget.isAuthenticated();

  Future<void> _load() async {
    if (_busy || !widget.isAuthenticated()) return;
    final generation = ++_generation;
    final identity = widget.identityRevision();
    setState(() { _busy = true; _error = null; _message = null; });
    try {
      final result = await widget.repository.list();
      if (_current(generation, identity)) {
        setState(() {
          _tickets = List<FableSupportTicket>.unmodifiable(result);
          _ticketsIdentity = identity;
        });
      }
    } catch (_) {
      if (_current(generation, identity)) {
        setState(() => _error = 'Could not load tickets. Check your session and connection.');
      }
    } finally {
      if (_current(generation, identity)) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy || !widget.isAuthenticated()) return;
    final subject = _subject.text.trim();
    final description = _description.text.trim();
    if (subject.length < 2 || subject.length > 200 ||
        description.length < 2 || description.length > 5000 ||
        subject.contains(RegExp(r'[\x00-\x1f]')) ||
        description.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'))) {
      setState(() => _error = 'Enter a valid subject and description.');
      return;
    }
    final generation = ++_generation;
    final identity = widget.identityRevision();
    setState(() { _busy = true; _error = null; _message = null; });
    try {
      // No automatic retry: timeout might mean the Backend created the ticket.
      await widget.repository.create(subject: subject, description: description);
      if (_current(generation, identity)) {
        _subject.clear();
        _description.clear();
        setState(() {
          _tickets = null; // Force authoritative reload instead of stale list.
          _ticketsIdentity = null;
          _message = 'Ticket request accepted. Reload your tickets to verify.';
        });
      }
    } catch (_) {
      if (_current(generation, identity)) {
        setState(() => _error =
          'Submission is unconfirmed. Review tickets before trying again.');
      }
    } finally {
      if (_current(generation, identity)) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_identitySub?.cancel());
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.isAuthenticated();
    // A provider may revoke auth without emitting a widget event. A rebuild
    // must NEVER render tickets from a different identity revision or logout.
    final visibleTickets = enabled && _ticketsIdentity == widget.identityRevision()
        ? _tickets : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Support tickets')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        if (!enabled) const Text('Sign in with the selected Backend before using support.'),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, key: const Key('support-error')),
        if (_message != null) Text(_message!, key: const Key('support-message')),
        TextField(
          key: const Key('support-subject'),
          controller: _subject, enabled: enabled && !_busy,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Subject'),
        ),
        TextField(
          key: const Key('support-description'),
          controller: _description, enabled: enabled && !_busy,
          minLines: 2, maxLines: 5, maxLength: 5000,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        FilledButton(
          key: const Key('support-create'),
          onPressed: enabled && !_busy ? _create : null,
          child: const Text('Create ticket'),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          key: const Key('support-load'),
          onPressed: enabled && !_busy ? _load : null,
          child: const Text('Load tickets'),
        ),
        if (visibleTickets != null && visibleTickets.isEmpty) const Text('No tickets.'),
        for (final ticket in visibleTickets ?? const <FableSupportTicket>[])
          ListTile(title: Text(ticket.subject), subtitle: Text(ticket.status)),
      ])),
    );
  }
}
