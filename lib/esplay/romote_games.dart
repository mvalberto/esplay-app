import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../ui/navigation/destinations.dart';

/// The game page for an Emby Game item, or null when its ROM isn't in a
/// Moonbase game library. Moonbase names a game by its ROM's path in base64url
/// without padding, and the ROMote item points at that same file.
Future<String?> moonbaseGameRoute(String itemId) async {
  final client = GetIt.instance<MediaServerClient>();
  final games = client.gamesApi;
  if (games == null) return null;
  final List<GameLibrary> libraries;
  final String gameId;
  try {
    final item = await client.itemsApi.getItem(itemId, fields: 'Path');
    final path = item['Path']?.toString() ?? '';
    if (path.isEmpty) return null;
    gameId = base64Url.encode(utf8.encode(path)).replaceAll('=', '');
    libraries = await games.getLibraries();
  } catch (_) {
    return null;
  }
  for (final library in libraries) {
    try {
      // A ROM outside this library answers 404.
      if (await games.getGame(library.id, gameId) != null) {
        return Destinations.gameDetailOf(library.id, gameId);
      }
    } catch (_) {}
  }
  return null;
}

/// A game as Emby holds it, with the metadata and box art the ROMote plugin
/// scraped for it.
class RomoteGame {
  final String id;
  final String name;
  final String? imageTag;
  final String? overview;
  final int? year;
  final List<String> genres;

  const RomoteGame({
    required this.id,
    required this.name,
    this.imageTag,
    this.overview,
    this.year,
    this.genres = const [],
  });

  String? imageUrl({int? maxWidth}) => imageTag == null
      ? null
      : GetIt.instance<MediaServerClient>().imageApi.getPrimaryImageUrl(
          id,
          maxWidth: maxWidth,
          tag: imageTag,
        );
}

/// Moonbase reads ROMs straight from disk and looks their art up in libretro,
/// which misses names like "Ace of Aces (NA)". ROMote has already scraped
/// those same files into Emby's own Game items, so EsPlay takes the box art
/// and details from there, matching by file name and then by title.
class RomoteGames {
  RomoteGames._();

  static final instance = RomoteGames._();

  Future<_Index>? _index;
  _Index? _loaded;
  String? _serverUrl;

  /// The match for a game once the index has loaded, else null. Screens call
  /// [match] first and rebuild when it answers.
  RomoteGame? cachedMatch({required String fileName, required String title}) {
    final index = _loaded;
    if (index == null) return null;
    return index.byFile[_baseName(fileName)] ?? index.byTitle[_title(title)];
  }

  Future<RomoteGame?> match({
    required String fileName,
    required String title,
  }) async {
    final index = await _load();
    return index.byFile[_baseName(fileName)] ?? index.byTitle[_title(title)];
  }

  /// Every match for [games], keyed by the game's file name.
  Future<Map<String, RomoteGame>> matchAll(
    Iterable<({String fileName, String title})> games,
  ) async {
    final index = await _load();
    final result = <String, RomoteGame>{};
    for (final game in games) {
      final found =
          index.byFile[_baseName(game.fileName)] ?? index.byTitle[_title(game.title)];
      if (found != null) result[game.fileName] = found;
    }
    return result;
  }

  Future<_Index> _load() {
    final client = GetIt.instance<MediaServerClient>();
    if (_serverUrl != client.baseUrl) {
      _serverUrl = client.baseUrl;
      _index = null;
      _loaded = null;
    }
    final pending = _index ??= _fetch(client);
    // A failed load is asked for again next time instead of being kept.
    pending.catchError((_) {
      if (identical(_index, pending)) _index = null;
      return _Index.empty;
    });
    return pending;
  }

  Future<_Index> _fetch(MediaServerClient client) async {
    final byFile = <String, RomoteGame>{};
    final byTitle = <String, RomoteGame>{};
    var start = 0;
    const page = 1000;
    while (true) {
      final response = await client.itemsApi.getItems(
        includeItemTypes: const ['Game'],
        recursive: true,
        startIndex: start,
        limit: page,
        fields: 'Path,Overview,Genres,ProductionYear',
      );
      final items = ((response['Items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      for (final item in items) {
        final game = RomoteGame(
          id: item['Id']?.toString() ?? '',
          name: item['Name']?.toString() ?? '',
          imageTag: (item['ImageTags'] as Map?)?['Primary'] as String?,
          overview: item['Overview'] as String?,
          year: item['ProductionYear'] as int?,
          genres: ((item['Genres'] as List?) ?? const [])
              .map((g) => g.toString())
              .toList(),
        );
        final path = item['Path']?.toString();
        if (path != null && path.isNotEmpty) {
          byFile.putIfAbsent(_baseName(path), () => game);
        }
        byTitle.putIfAbsent(_title(game.name), () => game);
      }
      if (items.length < page) break;
      start += items.length;
    }
    return _loaded = _Index(byFile, byTitle);
  }

  static String _baseName(String path) =>
      path.split(RegExp(r'[\\/]')).last.toLowerCase();

  /// "Ace of Aces (NA)" and "Ace of Aces" are the same game for matching.
  static String _title(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

class _Index {
  final Map<String, RomoteGame> byFile;
  final Map<String, RomoteGame> byTitle;

  const _Index(this.byFile, this.byTitle);

  static const empty = _Index({}, {});
}
