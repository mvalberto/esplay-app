import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../data/viewmodels/live_tv_guide_view_model.dart';

/// A channel tag as the user named it in Emby. A leading number such as
/// "02 LA LIGA" is split off so the screens can paint it apart.
class LiveTvTag {
  final String id;
  final String name;

  const LiveTvTag({required this.id, required this.name});

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

/// Reads tags and their channels from the server, keeping each answer for a
/// minute so moving between the screens doesn't ask again.
class LiveTvTagsRepository {
  LiveTvTagsRepository._();

  static final instance = LiveTvTagsRepository._();

  static const _maxAge = Duration(minutes: 1);

  String? _serverUrl;
  ({DateTime at, List<LiveTvTag> tags})? _tags;
  final _channels = <String, ({DateTime at, List<LiveTvTagChannel> list})>{};

  MediaServerClient get _client => GetIt.instance<MediaServerClient>();

  /// False on servers without channel tags (Jellyfin, Plex).
  bool get isSupported => _client.liveTvApi is LiveTvChannelTagsApi;

  void _resetIfServerChanged() {
    final url = _client.baseUrl;
    if (_serverUrl == url) return;
    _serverUrl = url;
    _tags = null;
    _channels.clear();
  }

  Future<List<LiveTvTag>> tags({bool refresh = false}) async {
    _resetIfServerChanged();
    final api = _client.liveTvApi;
    if (api is! LiveTvChannelTagsApi) return const [];
    final cached = _tags;
    if (!refresh && cached != null && _fresh(cached.at)) return cached.tags;
    final raw = await (api as LiveTvChannelTagsApi).getChannelTags(
      userId: _client.userId,
    );
    final tags = [
      for (final tag in raw)
        if ((tag['Id']?.toString() ?? '').isNotEmpty)
          LiveTvTag(
            id: tag['Id'].toString(),
            name: tag['Name']?.toString() ?? '',
          ),
    ];
    _tags = (at: DateTime.now(), tags: tags);
    return tags;
  }

  Future<List<LiveTvTagChannel>> channels(
    String tagId, {
    bool refresh = false,
  }) async {
    _resetIfServerChanged();
    final api = _client.liveTvApi;
    if (api is! LiveTvChannelTagsApi) return const [];
    final cached = _channels[tagId];
    if (!refresh && cached != null && _fresh(cached.at)) return cached.list;
    final raw = await (api as LiveTvChannelTagsApi).getChannelsWithTag(
      tagId,
      userId: _client.userId,
    );
    final list = raw.map(LiveTvTagChannel.fromRawItem).toList();
    _channels[tagId] = (at: DateTime.now(), list: list);
    return list;
  }

  bool _fresh(DateTime at) => DateTime.now().difference(at) < _maxAge;
}
