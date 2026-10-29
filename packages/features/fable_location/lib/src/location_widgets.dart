import 'package:material_ui/material_ui.dart';
import 'location_repository.dart';

/// Provider-neutral list. No map-renderer or OS-location dependency.
/// Attribution is mandatory whenever provider results are shown.
class FableLocationResultsView extends StatelessWidget {
  const FableLocationResultsView({super.key, required this.response});
  final FableLocationResponse response;
  static String _short(String value) => value.length <= 200 ? value : value.substring(0, 200);
  @override Widget build(BuildContext context) {
    final items = response.data is List ? response.data as List : const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final item in items.take(20))
        if (item is Map && (item['name'] is String || item['formattedAddress'] is String))
          ListTile(title: Text(_short((item['name'] ?? item['formattedAddress']) as String)),
            subtitle: item['name'] is String && item['formattedAddress'] is String
              ? Text(_short(item['formattedAddress'] as String)) : null),
      for (final warning in response.warnings) Text(warning,
        style: Theme.of(context).textTheme.bodySmall),
      Text(response.attribution, style: Theme.of(context).textTheme.labelSmall),
    ]);
  }
}

/// Generic optional search UI. It never silently requests device GPS.
class FableLocationSearchCard extends StatefulWidget {
  const FableLocationSearchCard({super.key, required this.repository});
  final FableLocationRepository repository;
  @override State<FableLocationSearchCard> createState() => _FableLocationSearchCardState();
}
class _FableLocationSearchCardState extends State<FableLocationSearchCard> {
  final _input = TextEditingController();
  FableLocationResponse? _response;
  bool _loading = false;
  int _epoch = 0;
  String? _error;
  @override void didUpdateWidget(covariant FableLocationSearchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _epoch++; _response = null; _error = null; _loading = false;
    }
  }
  @override void dispose() { _epoch++; _input.dispose(); super.dispose(); }
  Future<void> _search() async {
    if (_loading) return;
    final epoch = ++_epoch;
    setState(() { _loading = true; _response = null; _error = null; });
    try {
      final response = await widget.repository.geocode(_input.text);
      if (mounted && epoch == _epoch) setState(() => _response = response);
    } catch (_) {
      if (mounted && epoch == _epoch) setState(() =>
        _error = 'Location search unavailable. Check access or connection.');
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }
  @override Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(12),
    child: Column(children: [
      TextField(controller: _input, maxLength: 500,
        decoration: const InputDecoration(labelText: 'Location or address'),
        onSubmitted: (_) => _search()),
      FilledButton(onPressed: _loading ? null : _search, child: const Text('Search')),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (_response != null) FableLocationResultsView(response: _response!),
    ]),
  ));
}
