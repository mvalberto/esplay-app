import 'dart:async';
import 'dart:convert';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/viewmodels/live_tv_guide_view_model.dart';

/// A channel tag as the user named it in Emby. A leading number such as
/// "02 LA LIGA" is split off so the screens can paint it apart.
class LiveTvTag {
  final String id;
  final String name;

  /// The tag's 16:9 picture in Emby, when it has one.
  final String? thumbTag;

  const LiveTvTag({required this.id, required this.name, this.thumbTag});

  static final _numbered = RegExp(r'^(\d+)\s+(.+)$');

  /// The leading number, or null when the name doesn't start with one.
  String? get number => _numbered.firstMatch(name)?.group(1);

  /// The name without its leading number.
  String get label => _numbered.firstMatch(name)?.group(2) ?? name;
}

/// A channel together with what it is airing now, when the guide knows.
class LiveTvTagChannel {
  final GuideChannel channel;
  final String? programName;
  final DateTime? start;
  final DateTime? end;

  const LiveTvTagChannel({
    required this.channel,
    this.programName,
    this.start,
    this.end,
  });

  factory LiveTvTagChannel.fromRawItem(Map<String, dynamic> raw) {
    final program = raw['CurrentProgram'];
    final current = program is Map ? program.cast<String, dynamic>() : null;
    return LiveTvTagChannel(
      channel: GuideChannel.fromRawItem(raw),
      programName: current?['Name'] as String?,
      start: DateTime.tryParse(current?['StartDate'] as String? ?? '')?.toLocal(),
      end: DateTime.tryParse(current?['EndDate'] as String? ?? '')?.toLocal(),
    );
  }

  bool get hasGuide => programName != null && start != null && end != null;

  /// How far the current program has run, 0 to 1.
  double progress(DateTime now) {
    if (!hasGuide) return 0;
    final total = end!.difference(start!).inSeconds;
    if (total <= 0) return 0;
    return (now.difference(start!).inSeconds / total).clamp(0.0, 1.0);
  }

  int minutesLeft(DateTime now) =>
      hasGuide ? end!.difference(now).inMinutes.clamp(0, 24 * 60) : 0;
}

/// Reads tags and their channels from the server. Screens asking at once share
/// one request. An answer under a minute old is used as it is; an older one
/// still shows at once while a fresh copy loads behind it for the next visit.
/// The tags, which rarely change, are also stored on the device so the page
/// has them as soon as it opens.
class LiveTvTagsRepository {
  LiveTvTagsRepository._();

  static final instance = LiveTvTagsRepository._();

  /// Channels a start page row shows before "See channels".
  static const rowSize = 20;

  static const _fresh = Duration(minutes: 1);
  static const _channelsUsable = Duration(minutes: 5);
  static const _tagsUsable = Duration(days: 7);
  static const _storedTagsKey = 'esplay_live_tv_tags';

  String? _owner;
  final _entries = <String, ({DateTime at, Future<Object> value})>{};
  final _refreshing = <String>{};

  MediaServerClient get _client => GetIt.instance<MediaServerClient>();

  /// False on servers without channel tags (Jellyfin, Plex).
  bool get isSupported => _client.liveTvApi is LiveTvChannelTagsApi;

  LiveTvChannelTagsApi? get _api {
    final api = _client.liveTvApi;
    return api is LiveTvChannelTagsApi ? api as LiveTvChannelTagsApi : null;
  }

  void _resetIfAccountChanged() {
    final owner = '${_client.baseUrl}|${_client.userId}';
    if (_owner == owner) return;
    _owner = owner;
    _entries.clear();
    _refreshing.clear();
  }

  Future<T> _load<T extends Object>(
    String key,
    Duration usable,
    Future<T> Function() fetch, {
    bool refresh = false,
  }) {
    final entry = _entries[key];
    if (entry != null && !refresh) {
      final age = DateTime.now().difference(entry.at);
      if (age < usable) {
        if (age >= _fresh) _refreshBehind(key, fetch);
        return entry.value.then((value) => value as T);
      }
    }
    final value = fetch();
    _entries[key] = (at: DateTime.now(), value: value);
    // A failed answer isn't kept, so the next visit asks again.
    value.then<void>((_) {}, onError: (Object _) {
      if (identical(_entries[key]?.value, value)) _entries.remove(key);
    });
    return value;
  }

  void _refreshBehind<T extends Object>(
    String key,
    Future<T> Function() fetch,
  ) {
    if (!_refreshing.add(key)) return;
    final owner = _owner;
    fetch().then<void>((value) {
      if (_owner == owner) {
        _entries[key] = (at: DateTime.now(), value: Future.value(value));
      }
    }, onError: (Object _) {}).whenComplete(() => _refreshing.remove(key));
  }

  Future<List<LiveTvTag>> tags({bool refresh = false}) async {
    _resetIfAccountChanged();
    final api = _api;
    if (api == null) return const [];
    if (!refresh && !_entries.containsKey('tags')) await _restoreTags();
    return _load('tags', _tagsUsable, () async {
      final raw = await api.getChannelTags(userId: _client.userId);
      final tags = [
        for (final tag in raw)
          if ((tag['Id']?.toString() ?? '').isNotEmpty)
            LiveTvTag(
              id: tag['Id'].toString(),
              name: tag['Name']?.toString() ?? '',
              thumbTag: (tag['ImageTags'] as Map?)?['Thumb']?.toString(),
            ),
      ];
      // By their number: Emby doesn't return them in that order. Ones without
      // a number go last, by name.
      int numberOf(LiveTvTag tag) =>
          int.tryParse(tag.number ?? '') ?? 1 << 30;
      tags.sort((a, b) {
        final byNumber = numberOf(a).compareTo(numberOf(b));
        return byNumber != 0 ? byNumber : a.name.compareTo(b.name);
      });
      unawaited(_storeTags(tags));
      return tags;
    }, refresh: refresh);
  }

  /// Every channel of a tag.
  Future<List<LiveTvTagChannel>> channels(
    String tagId, {
    bool refresh = false,
  }) {
    _resetIfAccountChanged();
    final api = _api;
    if (api == null) return Future.value(const []);
    return _load(
      'tag:$tagId',
      _channelsUsable,
      () => _fetchChannels(api, tagId),
      refresh: refresh,
    );
  }

  /// A tag's first [rowSize] channels, for a row or a card that shows a few.
  Future<List<LiveTvTagChannel>> rowChannels(String tagId) {
    _resetIfAccountChanged();
    final api = _api;
    if (api == null) return Future.value(const []);
    final whole = _entries['tag:$tagId'];
    if (whole != null &&
        DateTime.now().difference(whole.at) < _channelsUsable) {
      return whole.value.then(
        (list) => (list as List<LiveTvTagChannel>).take(rowSize).toList(),
      );
    }
    return _load(
      'row:$tagId',
      _channelsUsable,
      () => _fetchChannels(api, tagId, limit: rowSize),
    );
  }

  Future<List<LiveTvTagChannel>> _fetchChannels(
    LiveTvChannelTagsApi api,
    String tagId, {
    int? limit,
  }) async {
    final raw = await api.getChannelsWithTag(
      tagId,
      userId: _client.userId,
      limit: limit,
    );
    return raw.map(LiveTvTagChannel.fromRawItem).toList();
  }

  Future<void> _restoreTags() async {
    final owner = _owner;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storedTagsKey);
      if (raw == null || _owner != owner || _entries.containsKey('tags')) {
        return;
      }
      final stored = jsonDecode(raw) as Map<String, dynamic>;
      if (stored['owner'] != owner) return;
      final at = DateTime.fromMillisecondsSinceEpoch(stored['at'] as int);
      final tags = [
        for (final tag in (stored['tags'] as List).cast<Map>())
          LiveTvTag(
            id: tag['id'] as String,
            name: tag['name'] as String,
            thumbTag: tag['thumb'] as String?,
          ),
      ];
      _entries['tags'] = (at: at, value: Future.value(tags));
    } catch (_) {
      // Nothing usable stored: the server answers instead.
    }
  }

  Future<void> _storeTags(List<LiveTvTag> tags) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storedTagsKey,
        jsonEncode({
          'owner': _owner,
          'at': DateTime.now().millisecondsSinceEpoch,
          'tags': [
            for (final tag in tags)
              {'id': tag.id, 'name': tag.name, 'thumb': tag.thumbTag},
          ],
        }),
      );
    } catch (_) {
      // The tags just aren't kept for the next start.
    }
  }
}

/// Channel logos rarely change and there are well over a thousand, more than
/// the shared image cache keeps, so they get a store of their own on the device.
final liveTvLogoCache = CacheManager(
  Config(
    'esplayLiveTvLogos',
    stalePeriod: const Duration(days: 60),
    maxNrOfCacheObjects: 3000,
  ),
);
