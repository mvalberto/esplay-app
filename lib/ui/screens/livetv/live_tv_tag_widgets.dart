import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/viewmodels/live_tv_guide_view_model.dart';
import '../../../esplay/live_tv_tags.dart';
import '../../../l10n/app_localizations.dart';
import '../../../playback/external_player_policy.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/key_event_utils.dart';
import '../../navigation/destinations.dart';
import '../../widgets/bounded_network_image.dart';
import 'live_tv_channel_player_loader.dart';

// EsPlay's live TV look: near-black cards, the brand red for numbers and
// progress, the theme's focus border for the remote.
const liveTvCardColor = Color(0xFF18181B);
const liveTvCardBorder = Color(0xFF26262B);
const liveTvChipColor = Color(0xFF1C1C20);
const liveTvChipBorder = Color(0xFF2E2E34);
const liveTvMutedText = Color(0xFFA1A1AA);

Color get liveTvRed => AppColorScheme.accent;
Color get liveTvFocus => ThemeRegistry.active.borders.focusBorder.color;

/// Plays [channels] from [index] in the live TV player, so the remote's
/// channel up and down zap through the same tag.
Future<void> playLiveTvChannel(
  BuildContext context,
  List<GuideChannel> channels,
  int index,
) async {
  if (index < 0 || index >= channels.length) return;
  unawaited(
    GetIt.instance<UserPreferences>().set(
      UserPreferences.liveTvLastChannelId,
      channels[index].id,
    ),
  );
  final external =
      ExternalPlayerPolicy.isEnabled &&
      await queueChannelForExternalPlayer(channels[index]);
  if (!context.mounted) return;
  await context.push(
    external ? Destinations.externalPlayer : Destinations.liveTvPlayer,
    extra: external ? null : {'channels': channels, 'startIndex': index},
  );
}

/// Opens the channel's own page, with what it airs next and Play and Record,
/// the way Emby does, instead of tuning in straight away.
void openLiveTvChannel(BuildContext context, String channelId) {
  context.push(Destinations.liveTvChannelInfo(channelId));
}

String liveTvTimeRange(DateTime start, DateTime end) {
  String hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return '${hm(start)} – ${hm(end)}';
}

/// Anything the remote can land on: a focus border, select to open.
class LiveTvFocusable extends StatefulWidget {
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final BorderRadius radius;
  final Widget Function(bool focused) builder;

  const LiveTvFocusable({
    super.key,
    required this.onTap,
    required this.builder,
    this.onFocusChange,
    this.autofocus = false,
    this.radius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<LiveTvFocusable> createState() => _LiveTvFocusableState();
}

class _LiveTvFocusableState extends State<LiveTvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) => handleOneShotSelect(event, widget.onTap),
      onFocusChange: (focused) {
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 150),
          );
        }
        setState(() => _focused = focused);
        widget.onFocusChange?.call(focused);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          foregroundDecoration: BoxDecoration(
            borderRadius: widget.radius,
            border: _focused
                ? Border.all(color: liveTvFocus, width: 2.5)
                : null,
          ),
          child: widget.builder(_focused),
        ),
      ),
    );
  }
}

/// "02 LA LIGA" with the number in red; a name without one stays whole.
class LiveTvTagName extends StatelessWidget {
  final LiveTvTag tag;
  final TextStyle style;
  final Color? numberColor;

  const LiveTvTagName({
    super.key,
    required this.tag,
    required this.style,
    this.numberColor,
  });

  @override
  Widget build(BuildContext context) {
    final number = tag.number;
    return Text.rich(
      TextSpan(
        children: [
          if (number != null)
            TextSpan(
              text: '$number ',
              style: style.copyWith(
                color: numberColor ?? liveTvRed,
                fontWeight: FontWeight.w900,
              ),
            ),
          TextSpan(text: tag.label, style: style),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class LiveTvChannelLogo extends StatelessWidget {
  final String channelId;
  final String? imageTag;
  final String name;
  final double fontSize;

  const LiveTvChannelLogo({
    super.key,
    required this.channelId,
    required this.imageTag,
    required this.name,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
    if (imageTag == null) return fallback;
    final url = GetIt.instance<MediaServerClient>().imageApi.getPrimaryImageUrl(
      channelId,
      maxHeight: 160,
      tag: imageTag,
    );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: BoundedNetworkImage(
        imageUrl: url,
        cacheManager: liveTvLogoCache,
        fit: BoxFit.contain,
        fadeInDuration: Duration.zero,
        maxWidth: 320,
        errorBuilder: (context, url, error) => fallback,
      ),
    );
  }
}

class LiveTvProgressBar extends StatelessWidget {
  final double value;
  final double height;

  const LiveTvProgressBar({super.key, required this.value, this.height = 3});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: liveTvChipBorder)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: liveTvRed),
            ),
          ],
        ),
      ),
    );
  }
}

/// A channel as a 16:9 tile with its logo and progress, and what it is airing
/// underneath.
class LiveTvChannelCard extends StatelessWidget {
  final LiveTvTagChannel item;
  final VoidCallback onTap;
  final bool large;
  final bool autofocus;

  const LiveTvChannelCard({
    super.key,
    required this.item,
    required this.onTap,
    this.large = false,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LiveTvFocusable(
          onTap: onTap,
          autofocus: autofocus,
          builder: (focused) => AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: liveTvCardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: liveTvCardBorder),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: LiveTvChannelLogo(
                      channelId: item.channel.id,
                      imageTag: item.channel.imageTag,
                      name: item.channel.name,
                      fontSize: large ? 18 : 14,
                    ),
                  ),
                  if (item.hasGuide)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LiveTvProgressBar(
                        value: item.progress(now),
                        height: large ? 4 : 3,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          large ? item.channel.name : (item.programName ?? item.channel.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: large ? 16 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (large)
          Text(
            item.programName ?? l10n.esplayLiveTvNoGuide,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: liveTvMutedText, fontSize: 14),
          ),
      ],
    );
  }
}

/// A rounded chip, white when selected; also used for the section tabs.
class LiveTvChip extends StatelessWidget {
  final Widget label;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;
  final double height;

  const LiveTvChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.autofocus = false,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    return LiveTvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      radius: BorderRadius.circular(height / 2),
      builder: (focused) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : liveTvChipColor,
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: selected ? Colors.white : liveTvChipBorder,
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          child: label,
        ),
      ),
    );
  }
}

/// A program airing now as a poster: the program's own picture (the channel's
/// logo when it has none), a live badge and its progress, then the program and
/// its channel underneath. The poster is [width] wide and half as tall again.
class LiveTvOnNowPoster extends StatelessWidget {
  final Map<String, dynamic> program;
  final double width;
  final bool focused;

  const LiveTvOnNowPoster({
    super.key,
    required this.program,
    required this.width,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final channelId = program['ChannelId']?.toString() ?? '';
    final channelName = program['ChannelName']?.toString() ?? '';
    final start = DateTime.tryParse(program['StartDate'] as String? ?? '')
        ?.toLocal();
    final end = DateTime.tryParse(program['EndDate'] as String? ?? '')
        ?.toLocal();
    var progress = 0.0;
    if (start != null && end != null && end.isAfter(start)) {
      progress = DateTime.now().difference(start).inSeconds /
          end.difference(start).inSeconds;
    }
    final logo = LiveTvChannelLogo(
      channelId: channelId,
      imageTag: program['ChannelPrimaryImageTag'] as String?,
      name: channelName,
      fontSize: 14,
    );
    final imageTag = (program['ImageTags'] as Map?)?['Primary'] as String?;
    final picture = imageTag == null
        ? logo
        : BoundedNetworkImage(
            imageUrl: GetIt.instance<MediaServerClient>().imageApi
                .getPrimaryImageUrl(
                  program['Id'].toString(),
                  maxWidth: 400,
                  tag: imageTag,
                ),
            fit: BoxFit.cover,
            maxWidth: 400,
            errorBuilder: (context, url, error) => logo,
          );
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: width,
            height: width * 1.5,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: liveTvCardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused ? liveTvFocus : liveTvCardBorder,
                width: focused ? 2.5 : 1,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: picture),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: liveTvRed,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      l10n.esplayLiveTvLive,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LiveTvProgressBar(value: progress, height: 4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            program['Name']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            [
              if (channelName.isNotEmpty) channelName,
              if (start != null && end != null) liveTvTimeRange(start, end),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: liveTvMutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// What a program airing now has to show: its time and how far along it is.
class _Airing {
  final DateTime start;
  final DateTime end;

  _Airing(this.start, this.end);

  static _Airing? of(Map<String, dynamic> program) {
    final start = DateTime.tryParse(program['StartDate'] as String? ?? '')
        ?.toLocal();
    final end = DateTime.tryParse(program['EndDate'] as String? ?? '')
        ?.toLocal();
    if (start == null || end == null || !end.isAfter(start)) return null;
    return _Airing(start, end);
  }

  double get progress =>
      DateTime.now().difference(start).inSeconds /
      end.difference(start).inSeconds;

  int get minutesLeft =>
      math.max(0, (end.difference(DateTime.now()).inSeconds / 60).round());
}

/// A program's own picture, wide where the guide has one, else its poster
/// cropped to fit; null when it has neither.
String? _programPictureUrl(Map<String, dynamic> program, int maxWidth) {
  final tags = program['ImageTags'] as Map?;
  final id = program['Id']?.toString();
  final thumb = tags?['Thumb'] as String?;
  final primary = tags?['Primary'] as String?;
  if (id == null || (thumb == null && primary == null)) return null;
  final images = GetIt.instance<MediaServerClient>().imageApi;
  return thumb != null
      ? images.getThumbImageUrl(id, maxWidth: maxWidth, tag: thumb)
      : images.getPrimaryImageUrl(id, maxWidth: maxWidth, tag: primary);
}

/// The program at the top of On Now on a TV, as on Samsung: the one under the
/// remote, its picture on the right fading into the background towards the
/// text and the row below. Without a picture its channel's logo stands there.
/// [unit] is a 1920-wide screen's pixel, [textInset] where Home's row titles
/// start.
class LiveTvOnNowHero extends StatelessWidget {
  final Map<String, dynamic> program;
  final double unit;
  final double textInset;

  const LiveTvOnNowHero({
    super.key,
    required this.program,
    required this.unit,
    required this.textInset,
  });

  static double heightFor(double unit) => 370 * unit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final u = unit;
    final width = MediaQuery.sizeOf(context).width;
    final channelId = program['ChannelId']?.toString() ?? '';
    final channelName = program['ChannelName']?.toString() ?? '';
    final overview = program['Overview']?.toString().trim() ?? '';
    final airing = _Airing.of(program);
    final logo = Align(
      alignment: const Alignment(0.75, 0),
      child: FractionallySizedBox(
        widthFactor: 0.4,
        heightFactor: 0.56,
        child: LiveTvChannelLogo(
          channelId: channelId,
          imageTag: program['ChannelPrimaryImageTag'] as String?,
          name: channelName,
          fontSize: 40 * u,
        ),
      ),
    );
    final url = _programPictureUrl(program, 1280);
    // Fades [child] to nothing from the [from] edge, solid from the last stop on.
    Widget fade(Widget child, Alignment from, List<double> stops) => ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: from,
            end: -from,
            colors: const [
              Color(0x00000000),
              Color(0x00000000),
              Color(0x80000000),
              Color(0xFF000000),
            ],
            stops: stops,
          ).createShader(rect),
          child: child,
        );
    Widget badge(String text, Color color) => Container(
          padding: EdgeInsets.symmetric(horizontal: 14 * u, vertical: 7 * u),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8 * u),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20 * u,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
    return SizedBox(
      height: heightFor(u),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: width * 0.66,
            child: url == null
                ? logo
                : fade(
                    fade(
                      BoundedNetworkImage(
                        key: ValueKey(url),
                        imageUrl: url,
                        fit: BoxFit.cover,
                        maxWidth: 1280,
                        errorBuilder: (context, url, error) => logo,
                      ),
                      Alignment.bottomCenter,
                      const [0.0, 0.06, 0.30, 0.55],
                    ),
                    Alignment.centerLeft,
                    const [0.0, 0.10, 0.34, 0.62],
                  ),
          ),
          Positioned(
            left: textInset,
            bottom: 26 * u,
            width: width * 0.46,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (channelName.isNotEmpty) ...[
                      Flexible(
                        child: badge(channelName, const Color(0xFF26262B)),
                      ),
                      SizedBox(width: 12 * u),
                    ],
                    badge(l10n.esplayLiveTvLive, liveTvRed),
                  ],
                ),
                SizedBox(height: 16 * u),
                Text(
                  program['Name']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 56 * u,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (airing != null) ...[
                  SizedBox(height: 14 * u),
                  Text(
                    '${liveTvTimeRange(airing.start, airing.end)} · '
                    '${l10n.esplayLiveTvMinutesLeft(airing.minutesLeft)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFC4C4CA),
                      fontSize: 24 * u,
                    ),
                  ),
                  SizedBox(height: 14 * u),
                  SizedBox(
                    width: 520 * u,
                    child: LiveTvProgressBar(
                      value: airing.progress,
                      height: 8 * u,
                    ),
                  ),
                ],
                if (overview.isNotEmpty) ...[
                  SizedBox(height: 14 * u),
                  Text(
                    overview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFA8A8B0),
                      fontSize: 22 * u,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A program airing now as a small 16:9 card under the hero: its picture (its
/// channel's logo, then its name, when it has none) with its progress, and the
/// channel underneath. [unit] is a 1920-wide screen's pixel.
class LiveTvOnNowCard extends StatelessWidget {
  final Map<String, dynamic> program;
  final double unit;
  final bool focused;

  const LiveTvOnNowCard({
    super.key,
    required this.program,
    required this.unit,
    this.focused = false,
  });

  static double widthFor(double unit) => 320 * unit;
  static double heightFor(double unit) => 180 * unit + 8 * unit + 40 * unit;

  @override
  Widget build(BuildContext context) {
    final u = unit;
    final channelName = program['ChannelName']?.toString() ?? '';
    final airing = _Airing.of(program);
    final logo = LiveTvChannelLogo(
      channelId: program['ChannelId']?.toString() ?? '',
      imageTag: program['ChannelPrimaryImageTag'] as String?,
      name: channelName,
      fontSize: (26 * u).clamp(11.0, 20.0),
    );
    final url = _programPictureUrl(program, 480);
    return SizedBox(
      width: widthFor(u),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: widthFor(u),
            height: 180 * u,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C20),
              borderRadius: BorderRadius.circular(14 * u),
              border: Border.all(
                color: focused ? liveTvFocus : Colors.transparent,
                width: 4 * u,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: url == null
                      ? logo
                      : BoundedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          maxWidth: 480,
                          errorBuilder: (context, url, error) => logo,
                        ),
                ),
                if (airing != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LiveTvProgressBar(
                      value: airing.progress,
                      height: 5 * u,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 8 * u),
          Text(
            channelName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: (22 * u).clamp(11.0, 18.0),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
