import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

/// A collection that holds a title, with the fields a details page reads.
typedef CollectionEntry = ({String id, String name, Map<String, dynamic> rawData});

/// Which collections hold each title. Emby can't answer that for one title, so
/// every collection is asked what it holds. Doing that on every details page
/// sent a request per collection each time, so the answer is built once and
/// kept for a while, and dropped when the app adds to or takes from a
/// collection.
class CollectionIndex {
  CollectionIndex._();

  static final instance = CollectionIndex._();

  static const _keep = Duration(minutes: 30);
  static const _pageSize = 200;
  static const _lookupsAtOnce = 12;

  String? _owner;
  DateTime? _builtAt;
  Future<Map<String, List<CollectionEntry>>>? _index;

  MediaServerClient get _client => GetIt.instance<MediaServerClient>();

  /// The collections holding [itemId], keyed by collection id.
  Future<Map<String, ({String name, Map<String, dynamic> rawData})>> collectionsOf(
    String itemId,
  ) async {
    final owner = '${_client.baseUrl}|${_client.userId}';
    final builtAt = _builtAt;
    if (_index == null ||
        _owner != owner ||
        builtAt == null ||
        DateTime.now().difference(builtAt) > _keep) {
      _owner = owner;
      _builtAt = DateTime.now();
      final index = _build();
      _index = index;
      // A failed scan isn't kept, so the next page asks again.
      index.then<void>((_) {}, onError: (Object _) {
        if (identical(_index, index)) forget();
      });
    }
    try {
      final index = await _index!;
      return {
        for (final entry in index[itemId] ?? const <CollectionEntry>[])
          entry.id: (name: entry.name, rawData: entry.rawData),
      };
    } catch (_) {
      return const {};
    }
  }

  void forget() {
    _index = null;
    _builtAt = null;
  }

  Future<Map<String, List<CollectionEntry>>> _build() async {
    final index = <String, List<CollectionEntry>>{};
    var startIndex = 0;
    while (true) {
      final data = await _client.itemsApi.getItems(
        includeItemTypes: ['BoxSet'],
        recursive: true,
        sortBy: 'SortName',
        fields: 'BasicSyncInfo,PrimaryImageAspectRatio,ImageTags,ProviderIds',
        startIndex: startIndex,
        limit: _pageSize,
        enableTotalRecordCount: true,
      );
      final boxSets = ((data['Items'] as List?) ?? const [])
          .whereType<Map>()
          .map((raw) => raw.cast<String, dynamic>())
          .toList();
      final candidates = <CollectionEntry>[
        for (final boxSet in boxSets)
          if ((boxSet['Id']?.toString() ?? '').isNotEmpty &&
              boxSet['Name'] != null)
            (
              id: boxSet['Id'].toString(),
              name: boxSet['Name'].toString(),
              rawData: boxSet,
            ),
      ];
      for (var i = 0; i < candidates.length; i += _lookupsAtOnce) {
        await Future.wait(
          candidates.skip(i).take(_lookupsAtOnce).map((candidate) async {
            // Direct children only, as the details page always asked.
            final membership = await _client.itemsApi.getItems(
              parentId: candidate.id,
              fields: 'BasicSyncInfo',
            );
            for (final member
                in ((membership['Items'] as List?) ?? const []).whereType<Map>()) {
              final id = member['Id']?.toString();
              if (id != null && id.isNotEmpty) {
                (index[id] ??= []).add(candidate);
              }
            }
          }),
        );
      }
      if (boxSets.length < _pageSize) break;
      startIndex += boxSets.length;
    }
    return index;
  }
}
