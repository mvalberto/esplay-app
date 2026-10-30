import 'dart:async';

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
  context.push(Destinations.item(channelId));
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
