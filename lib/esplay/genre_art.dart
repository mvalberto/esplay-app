import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The picture a genre card showed, kept on the device.
typedef GenreArtEntry = ({String? imageUrl, String? backdropUrl, String? itemId});

/// Genre cards without art of their own take a random title's. A new random
/// pick on every visit meant a new address, so the picture stored on the
/// device was never used again. Each genre keeps the one it got the first time.
class GenreArt {
  GenreArt._();

  static final instance = GenreArt._();

  static const _storedKey = 'esplay_genre_art';

  Future<Map<String, GenreArtEntry>>? _entries;
  Timer? _save;

  Future<Map<String, GenreArtEntry>> _load() => _entries ??= () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storedKey);
      if (raw == null) return <String, GenreArtEntry>{};
      return {
        for (final entry in (jsonDecode(raw) as Map<String, dynamic>).entries)
          entry.key: (
            imageUrl: entry.value['i'] as String?,
            backdropUrl: entry.value['b'] as String?,
            itemId: entry.value['id'] as String?,
          ),
      };
    } catch (_) {
      return <String, GenreArtEntry>{};
    }
  }();

  Future<GenreArtEntry?> recall(String key) async => (await _load())[key];

  Future<void> remember(String key, GenreArtEntry entry) async {
    (await _load())[key] = entry;
    _saveSoon();
  }

  /// For a picture the server no longer has, because its title was deleted.
  Future<void> forget(String key) async {
    (await _load()).remove(key);
    _saveSoon();
  }

  void _saveSoon() {
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), _store);
  }

  Future<void> _store() async {
    try {
      final entries = await _load();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storedKey,
        jsonEncode({
          for (final entry in entries.entries)
            entry.key: {
              'i': entry.value.imageUrl,
              'b': entry.value.backdropUrl,
              'id': entry.value.itemId,
            },
        }),
      );
    } catch (_) {
      // The pictures just get picked again next time.
    }
  }
}
