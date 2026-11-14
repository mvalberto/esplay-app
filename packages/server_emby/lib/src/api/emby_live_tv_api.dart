import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class EmbyLiveTvApi implements LiveTvApi, LiveTvChannelTagsApi {
  final Dio _dio;
  static const _postChannelIdsThreshold = 1800;

  EmbyLiveTvApi(this._dio);

  @override
  Future<Map<String, dynamic>> getChannels({
    int? startIndex,
    int? limit,
    String? sortBy,
    String? sortOrder,
    String? fields,
    bool? enableTotalRecordCount,
    String? userId,
  }) async {
    final response = await _dio.get('/LiveTv/Channels', queryParameters: {
      'StartIndex': ?startIndex,
      'Limit': ?limit,
      'SortBy': ?sortBy,
      'SortOrder': ?sortOrder,
      'Fields': ?fields,
      'EnableTotalRecordCount': ?enableTotalRecordCount,
      'UserId': ?userId,
    });
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<List<Map<String, dynamic>>> getChannelTags({String? userId}) async {
    final response = await _dio.get(
      '/LiveTv/ChannelTags',
      queryParameters: {'UserId': ?userId},
    );
    final data = response.data;
    final items = data is Map ? data['Items'] : data;
    return ((items as List?) ?? const [])
        .whereType<Map>()
        .map((tag) => tag.cast<String, dynamic>())
        .toList();
  }

  @override
  Future<Map<String, dynamic>> getAiringPrograms({
    int? limit,
    String? userId,
  }) async {
    // In channel order, like Emby's own apps. /LiveTv/Programs/Recommended
    // ranks by what each user watches most instead.
    final response = await _dio.get('/LiveTv/Channels', queryParameters: {
      'AddCurrentProgram': true,
      'EnableImageTypes': 'Primary',
      'ImageTypeLimit': 1,
      'EnableTotalRecordCount': false,
      // Some channels have no guide, so ask for more than will be shown.
      'Limit': ?(limit == null ? null : limit * 4),
      'UserId': ?userId,
    });
    final channels = (response.data as Map<String, dynamic>)['Items'] as List?;
    final programs = <Map<String, dynamic>>[];
    for (final channel in (channels ?? const []).whereType<Map>()) {
      final program = channel['CurrentProgram'];
      if (program is! Map) continue;
      programs.add({
        ...program.cast<String, dynamic>(),
        'ChannelId': program['ChannelId'] ?? channel['Id'],
        'ChannelName': program['ChannelName'] ?? channel['Name'],
        'ChannelNumber': ?(program['ChannelNumber'] ?? channel['ChannelNumber']),
        'ChannelPrimaryImageTag':
            ?(program['ChannelPrimaryImageTag'] ??
                (channel['ImageTags'] as Map?)?['Primary']),
      });
      if (limit != null && programs.length >= limit) break;
    }
    if (limit != null && programs.length < limit) {
      await _addAiringPrograms(programs, limit, userId);
    }
    return {'Items': programs, 'TotalRecordCount': programs.length};
  }

  /// A user whose first channels have no guide (on ep02 the list can open
  /// with hundreds of them) still gets what airs, straight from the guide,
  /// with each channel's logo looked up after.
  Future<void> _addAiringPrograms(
    List<Map<String, dynamic>> programs,
    int limit,
    String? userId,
  ) async {
    try {
      final response = await _dio.get('/LiveTv/Programs', queryParameters: {
        'IsAiring': true,
        'Fields': 'ChannelInfo,Overview',
        'EnableTotalRecordCount': false,
        'Limit': limit * 2,
        'UserId': ?userId,
      });
      final seen = {for (final p in programs) p['ChannelId']?.toString()};
      final extra = <Map<String, dynamic>>[];
      final items = (response.data as Map<String, dynamic>)['Items'] as List?;
      for (final program in (items ?? const []).whereType<Map>()) {
        final channelId = program['ChannelId']?.toString();
        if (channelId == null || !seen.add(channelId)) continue;
        extra.add(program.cast<String, dynamic>());
        if (programs.length + extra.length >= limit) break;
      }
      if (extra.isEmpty) return;
      final channels = await _dio.get('/LiveTv/Channels', queryParameters: {
        'Ids': extra.map((p) => p['ChannelId']).join(','),
        'EnableImageTypes': 'Primary',
        'ImageTypeLimit': 1,
        'EnableTotalRecordCount': false,
        'UserId': ?userId,
      });
      final logos = <String, String>{
        for (final c in ((channels.data as Map<String, dynamic>)['Items']
                    as List? ??
                const [])
            .whereType<Map>())
          if ((c['ImageTags'] as Map?)?['Primary'] is String)
            c['Id'].toString(): (c['ImageTags'] as Map)['Primary'] as String,
      };
      for (final program in extra) {
        programs.add({
          ...program,
          'ChannelPrimaryImageTag': ?logos[program['ChannelId'].toString()],
        });
      }
    } catch (_) {
      // On now just shows what the channel list found.
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getChannelsWithTag(
    String tagId, {
    String? userId,
    int? limit,
  }) async {
    final response = await _dio.get('/LiveTv/Channels', queryParameters: {
      'TagIds': tagId,
      'AddCurrentProgram': true,
      'EnableUserData': true,
      'Fields': 'ImageTags,UserData',
      'EnableImageTypes': 'Primary',
      'ImageTypeLimit': 1,
      'EnableTotalRecordCount': false,
      'Limit': ?limit,
      'UserId': ?userId,
    });
    final items = (response.data as Map<String, dynamic>)['Items'] as List?;
    return (items ?? const [])
        .whereType<Map>()
        .map((channel) => channel.cast<String, dynamic>())
        .toList();
  }

  @override
  Future<Map<String, dynamic>> getGuide({
    DateTime? startDate,
    DateTime? endDate,
    List<String>? channelIds,
    bool? isMovie,
    bool? isSeries,
    bool? isSports,
    bool? isNews,
    bool? isKids,
    String? fields,
    bool? enableTotalRecordCount,
    bool? enableImages,
    bool? enableUserData,
    String? userId,
  }) async {
    final ids =
        (channelIds != null && channelIds.isNotEmpty) ? channelIds : null;
    final joined = ids?.join(',');
    final usePost = joined != null && joined.length > _postChannelIdsThreshold;

    // EnableImages/EnableUserData are off for the guide to keep the per-program
    // payload small (issue #666). Channel logos come from /LiveTv/Channels, not
    // this response, so they are unaffected.
    final common = <String, dynamic>{
      if (startDate != null) 'MinEndDate': startDate.toUtc().toIso8601String(),
      if (endDate != null) 'MaxStartDate': endDate.toUtc().toIso8601String(),
      'IsMovie': ?isMovie,
      'IsSeries': ?isSeries,
      'IsSports': ?isSports,
      'IsNews': ?isNews,
      'IsKids': ?isKids,
      'Fields': ?fields,
      'EnableTotalRecordCount': ?enableTotalRecordCount,
      'EnableImages': ?enableImages,
      'EnableUserData': ?enableUserData,
      'UserId': ?userId,
    };

    // POST needs ChannelIds as a JSON array (Jellyfin GetProgramsDto and remux
    // GetProgramsBody both type it as a GUID list); a comma string is rejected
    // by strict servers. GET uses the conventional comma form.
    final Response response;
    if (usePost) {
      response = await _dio.post('/LiveTv/Programs', data: {
        ...common,
        'ChannelIds': ids,
      });
    } else {
      response = await _dio.get('/LiveTv/Programs', queryParameters: {
        ...common,
        'ChannelIds': ?joined,
      });
    }
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> getRecommendedPrograms({
    int? limit,
    bool? isAiring,
  }) async {
    final response = await _dio.get(
      '/LiveTv/Programs/Recommended',
      queryParameters: {'Limit': ?limit, 'IsAiring': ?isAiring},
    );
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> getProgram(
    String programId, {
    String? userId,
  }) async {
    final response = await _dio.get(
      '/LiveTv/Programs/${Uri.encodeComponent(programId)}',
      queryParameters: {'UserId': ?userId},
    );
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> getRecordings({
    int? limit,
    String? fields,
    bool? enableImages,
    bool? isSeries,
    bool? isMovie,
    bool? isSports,
    bool? isKids,
  }) async {
    final response = await _dio.get('/LiveTv/Recordings', queryParameters: {
      'Limit': ?limit,
      'Fields': ?fields,
      'EnableImages': ?enableImages,
      'IsSeries': ?isSeries,
      'IsMovie': ?isMovie,
      'IsSports': ?isSports,
      'IsKids': ?isKids,
    });
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> getTimers() async {
    final response = await _dio.get('/LiveTv/Timers');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> getSeriesTimers() async {
    final response = await _dio.get('/LiveTv/SeriesTimers');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> createTimer(String programId) async {
    await _dio.post('/LiveTv/Timers', data: await _timerDefaults(programId));
  }

  @override
  Future<void> createSeriesTimer(
    String programId, {
    Map<String, dynamic>? settings,
  }) async {
    await _dio.post(
      '/LiveTv/SeriesTimers',
      data: {...await _timerDefaults(programId), ...?settings},
    );
  }

  @override
  Future<Map<String, dynamic>> getSeriesTimer(String seriesTimerId) async {
    final response = await _dio.get('/LiveTv/SeriesTimers/$seriesTimerId');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> updateSeriesTimer(
    String seriesTimerId,
    Map<String, dynamic> seriesTimer,
  ) async {
    await _dio.post('/LiveTv/SeriesTimers/$seriesTimerId', data: seriesTimer);
  }

  /// The server's own defaults for a program, which both kinds of timer post
  /// straight back. A server that wont hand them over still takes a bare
  /// program id.
  Future<Map<String, dynamic>> _timerDefaults(String programId) async {
    try {
      final defaults = await _dio.get(
        '/LiveTv/Timers/Defaults',
        queryParameters: {'ProgramId': programId},
      );
      final payload = Map<String, dynamic>.from(
        (defaults.data as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      );
      return payload..putIfAbsent('ProgramId', () => programId);
    } catch (_) {
      return {'ProgramId': programId};
    }
  }

  @override
  Future<void> cancelTimer(String timerId) async {
    await _dio.delete('/LiveTv/Timers/$timerId');
  }

  @override
  Future<void> cancelSeriesTimer(String seriesTimerId) async {
    await _dio.delete('/LiveTv/SeriesTimers/$seriesTimerId');
  }
}
