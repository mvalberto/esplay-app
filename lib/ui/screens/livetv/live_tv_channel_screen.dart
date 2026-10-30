import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:server_core/server_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/focus/request_initial_focus.dart';
import 'live_tv_tag_widgets.dart';

/// A channel's own page, like Emby's: its logo, Play, Record and Favorite,
/// then what it airs from now on.
class LiveTvChannelScreen extends StatefulWidget {
  final String channelId;

  const LiveTvChannelScreen({super.key, required this.channelId});

  @override
  State<LiveTvChannelScreen> createState() => _LiveTvChannelScreenState();
}

class _LiveTvChannelScreenState extends State<LiveTvChannelScreen> {
  MediaServerClient get _client => GetIt.instance<MediaServerClient>();

  Map<String, dynamic>? _channel;
  List<Map<String, dynamic>>? _programs;
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _client.userLibraryApi.getItem(widget.channelId),
        _client.liveTvApi.getGuide(
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(hours: 24)),
          channelIds: [widget.channelId],
          fields: 'Overview,Genres,ProductionYear,OfficialRating,'
              'CommunityRating,EpisodeTitle',
          enableImages: true,
          userId: _client.userId,
        ),
      ]);
      final programs =
          (((results[1])['Items'] as List?) ?? const [])
              .whereType<Map>()
              .map((p) => p.cast<String, dynamic>())
              .toList()
            ..sort(
              (a, b) => (a['StartDate'] as String? ?? '').compareTo(
                b['StartDate'] as String? ?? '',
              ),
            );
      if (!mounted) return;
      setState(() {
        _channel = results[0];
        _programs = programs;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  bool get _isFavorite =>
      (_channel?['UserData'] as Map?)?['IsFavorite'] == true;

  Map<String, dynamic>? get _current {
    final now = DateTime.now();
    for (final program in _programs ?? const <Map<String, dynamic>>[]) {
      final start = _date(program['StartDate']);
      final end = _date(program['EndDate']);
      if (start != null && end != null && !now.isBefore(start) && now.isBefore(end)) {
        return program;
      }
    }
    return null;
  }

  static DateTime? _date(Object? raw) =>
      DateTime.tryParse(raw as String? ?? '')?.toLocal();

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleFavorite() async {
    final channel = _channel;
    if (channel == null || _busy) return;
    final favorite = !_isFavorite;
    setState(() => _busy = true);
    try {
      if (favorite) {
        await _client.userLibraryApi.markFavorite(widget.channelId);
      } else {
        await _client.userLibraryApi.unmarkFavorite(widget.channelId);
      }
      if (!mounted) return;
      setState(() {
        final userData = Map<String, dynamic>.from(
          (channel['UserData'] as Map?) ?? const {},
        )..['IsFavorite'] = favorite;
        _channel = {...channel, 'UserData': userData};
      });
    } catch (_) {
      if (mounted) _snack(AppLocalizations.of(context).esplayLiveTvActionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Records [program], or cancels its recording when one is set.
  Future<void> _toggleRecording(Map<String, dynamic> program) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final timerId = program['TimerId']?.toString();
    setState(() => _busy = true);
    try {
      if (timerId != null && timerId.isNotEmpty) {
        await _client.liveTvApi.cancelTimer(timerId);
        if (mounted) _snack(l10n.recordingCancelled);
      } else {
        await _client.liveTvApi.createTimer(program['Id'].toString());
        if (mounted) _snack(l10n.esplayLiveTvRecordingScheduled);
      }
      await _load();
    } catch (_) {
      if (mounted) _snack(l10n.esplayLiveTvActionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _play() => context.push(Destinations.liveTvChannel(widget.channelId));

  /// A later program: its whole description and a button to record it.
  Future<void> _showProgram(Map<String, dynamic> program) {
    final l10n = AppLocalizations.of(context);
    final recording = (program['TimerId']?.toString() ?? '').isNotEmpty;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: liveTvCardColor,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                program['Name']?.toString() ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    program['Overview']?.toString() ?? '',
                    style: const TextStyle(
                      color: Color(0xFFD4D4D8),
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _PillButton(
                label: recording
                    ? l10n.esplayLiveTvCancelRecording
                    : l10n.esplayLiveTvCreateRecording,
                icon: Icons.fiber_manual_record_rounded,
                iconColor: recording ? liveTvRed : Colors.white,
                autofocus: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _toggleRecording(program);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTV = PlatformDetection.isTV;
    final channel = _channel;
    final programs = _programs;
    Widget body;
    if (_failed) {
      body = Center(
        child: Text(
          l10n.esplayLiveTvLoadError,
          textAlign: TextAlign.center,
          style: const TextStyle(color: liveTvMutedText, fontSize: 15),
        ),
      );
    } else if (channel == null || programs == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final current = _current;
      final recording = (current?['TimerId']?.toString() ?? '').isNotEmpty;
      final logoTag = (channel['ImageTags'] as Map?)?['Primary'] as String?;
      final side = isTV ? 48.0 : 20.0;
      body = ListView(
        padding: EdgeInsets.fromLTRB(side, 8, side, 120),
        children: [
          SizedBox(
            height: isTV ? 150 : 130,
            child: LiveTvChannelLogo(
              channelId: widget.channelId,
              imageTag: logoTag,
              name: channel['Name']?.toString() ?? '',
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            channel['Name']?.toString() ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: isTV ? 30 : 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          _PillButton(
            label: l10n.play,
            icon: Icons.play_arrow_rounded,
            primary: true,
            autofocus: true,
            onTap: _play,
          ),
          if (current != null) ...[
            const SizedBox(height: 10),
            _PillButton(
              label: recording
                  ? l10n.esplayLiveTvCancelRecording
                  : l10n.esplayLiveTvCreateRecording,
              icon: Icons.fiber_manual_record_rounded,
              iconColor: recording ? liveTvRed : Colors.white,
              onTap: () => _toggleRecording(current),
            ),
          ],
          const SizedBox(height: 14),
          Center(
            child: LiveTvFocusable(
              onTap: _toggleFavorite,
              radius: BorderRadius.circular(12),
              builder: (focused) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: _isFavorite ? liveTvRed : Colors.white,
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.favorite,
                      style: const TextStyle(
                        color: liveTvMutedText,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (programs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.esplayLiveTvNoPrograms,
                textAlign: TextAlign.center,
                style: const TextStyle(color: liveTvMutedText, fontSize: 15),
              ),
            )
          else
            for (final program in programs) ...[
              _ProgramTile(
                program: program,
                channelId: widget.channelId,
                channelLogoTag: logoTag,
                channelName: channel['Name']?.toString() ?? '',
                onTap: identical(program, current)
                    ? _play
                    : () => _showProgram(program),
              ),
              const Divider(color: liveTvCardBorder, height: 1),
            ],
        ],
      );
    }

    return RequestInitialFocus(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: isTV
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
        body: SafeArea(top: isTV, child: body),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final bool autofocus;
  final Color? iconColor;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return LiveTvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      radius: BorderRadius.circular(28),
      builder: (focused) => Container(
        height: 54,
        decoration: BoxDecoration(
          color: primary ? Colors.white : liveTvChipColor,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: iconColor ?? (primary ? Colors.black : Colors.white),
              size: primary ? 30 : 22,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: primary ? Colors.black : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One program in the schedule: its picture, title, when it airs and what it
/// is about. The one on now shows how far it has run.
class _ProgramTile extends StatelessWidget {
  final Map<String, dynamic> program;
  final String channelId;
  final String? channelLogoTag;
  final String channelName;
  final VoidCallback onTap;

  const _ProgramTile({
    required this.program,
    required this.channelId,
    required this.channelLogoTag,
    required this.channelName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final start = DateTime.tryParse(program['StartDate'] as String? ?? '')
        ?.toLocal();
    final end = DateTime.tryParse(program['EndDate'] as String? ?? '')
        ?.toLocal();
    final now = DateTime.now();
    final onNow = start != null &&
        end != null &&
        !now.isBefore(start) &&
        now.isBefore(end);
    final recording = (program['TimerId']?.toString() ?? '').isNotEmpty;

    final title = [
      program['Name']?.toString() ?? '',
      if ((program['EpisodeTitle']?.toString() ?? '').isNotEmpty)
        program['EpisodeTitle'].toString(),
    ].join(' · ');
    final year = program['ProductionYear'];
    final rating = program['OfficialRating']?.toString();
    final community = (program['CommunityRating'] as num?)?.toDouble();
    final facts = [
      if (year != null) '$year',
      if (rating != null && rating.isNotEmpty) rating,
      if (community != null) '★${community.toStringAsFixed(1)}/10',
    ].join(' | ');
    String? when;
    if (start != null && end != null) {
      String day;
      try {
        day = DateFormat('EEEE, d MMM', locale).format(start);
      } catch (_) {
        day = DateFormat('EEEE, d MMM').format(start);
      }
      when = '$day, ${liveTvTimeRange(start, end)}';
    }
    final genres = ((program['Genres'] as List?) ?? const [])
        .map((g) => g.toString())
        .join(', ');
    final overview = program['Overview']?.toString() ?? '';

    final imageTag = (program['ImageTags'] as Map?)?['Primary'] as String?;
    final imageApi = GetIt.instance<MediaServerClient>().imageApi;
    final picture = imageTag != null
        ? BoundedNetworkImage(
            imageUrl: imageApi.getPrimaryImageUrl(
              program['Id'].toString(),
              maxWidth: 400,
              tag: imageTag,
            ),
            fit: BoxFit.cover,
            maxWidth: 400,
            errorBuilder: (context, url, error) => LiveTvChannelLogo(
              channelId: channelId,
              imageTag: channelLogoTag,
              name: channelName,
            ),
          )
        : LiveTvChannelLogo(
            channelId: channelId,
            imageTag: channelLogoTag,
            name: channelName,
          );

    return LiveTvFocusable(
      onTap: onTap,
      radius: BorderRadius.circular(10),
      builder: (focused) => Container(
        color: focused ? liveTvChipColor : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 120,
              height: 150,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: liveTvCardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: picture),
                  if (onNow)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LiveTvProgressBar(
                        value: now.difference(start).inSeconds /
                            end.difference(start).inSeconds,
                        height: 4,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (recording)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.fiber_manual_record_rounded,
                            color: liveTvRed,
                            size: 14,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      facts,
                      style: const TextStyle(color: liveTvMutedText, fontSize: 14),
                    ),
                  ],
                  if (when != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      when,
                      style: TextStyle(
                        color: onNow ? liveTvRed : liveTvMutedText,
                        fontSize: 14,
                        fontWeight: onNow ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (genres.isNotEmpty) '($genres)',
                      if (overview.isNotEmpty) overview,
                    ].join(' '),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD4D4D8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
