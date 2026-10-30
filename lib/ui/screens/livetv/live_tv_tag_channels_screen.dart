import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../esplay/live_tv_tags.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/focus/request_initial_focus.dart';
import 'live_tv_tag_widgets.dart';

/// The channels of one tag, as a list with what each one airs or as a grid.
class LiveTvTagChannelsScreen extends StatefulWidget {
  final String tagId;
  final String tagName;

  const LiveTvTagChannelsScreen({
    super.key,
    required this.tagId,
    required this.tagName,
  });

  @override
  State<LiveTvTagChannelsScreen> createState() =>
      _LiveTvTagChannelsScreenState();
}

class _LiveTvTagChannelsScreenState extends State<LiveTvTagChannelsScreen> {
  late Future<List<LiveTvTagChannel>> _channels;
  bool _grid = PlatformDetection.isTV;

  LiveTvTag get _tag => LiveTvTag(id: widget.tagId, name: widget.tagName);

  @override
  void initState() {
    super.initState();
    _channels = LiveTvTagsRepository.instance.channels(widget.tagId);
  }

  void _reload() {
    setState(() {
      _channels = LiveTvTagsRepository.instance.channels(
        widget.tagId,
        refresh: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTV = PlatformDetection.isTV;
    return RequestInitialFocus(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isTV ? 48 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: isTV ? 28 : 8),
                Row(
                  children: [
                    if (!isTV)
                      IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                    Expanded(
                      child: LiveTvTagName(
                        tag: _tag,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTV ? 30 : 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isTV ? 0 : 8),
                  child: Row(
                    children: [
                      LiveTvChip(
                        label: Text(l10n.esplayLiveTvList),
                        selected: !_grid,
                        height: 36,
                        onTap: () => setState(() => _grid = false),
                      ),
                      const SizedBox(width: 8),
                      LiveTvChip(
                        label: Text(l10n.esplayLiveTvGrid),
                        selected: _grid,
                        height: 36,
                        onTap: () => setState(() => _grid = true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<LiveTvTagChannel>>(
                    future: _channels,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return _Message(
                          text: l10n.esplayLiveTvLoadError,
                          onRetry: _reload,
                        );
                      }
                      final items = snapshot.data ?? const [];
                      if (items.isEmpty) {
                        return _Message(text: l10n.esplayLiveTvNoChannels);
                      }
                      return _grid
                          ? LiveTvChannelGrid(
                              items: items,
                              columns: isTV ? 4 : 2,
                            )
                          : _ChannelList(items: items);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Channels in a grid; select plays one with the rest of the tag to zap.
class LiveTvChannelGrid extends StatelessWidget {
  final List<LiveTvTagChannel> items;
  final int columns;
  final bool autofocusFirst;

  const LiveTvChannelGrid({
    super.key,
    required this.items,
    required this.columns,
    this.autofocusFirst = true,
  });

  @override
  Widget build(BuildContext context) {
    final large = PlatformDetection.isTV;
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: large ? 1.25 : 1.35,
      ),
      itemBuilder: (context, index) => LiveTvChannelCard(
        item: items[index],
        large: large,
        autofocus: autofocusFirst && index == 0,
        onTap: () => openLiveTvChannel(context, items[index].channel.id),
      ),
    );
  }
}

class _ChannelList extends StatelessWidget {
  final List<LiveTvTagChannel> items;

  const _ChannelList({required this.items});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final channels = [for (final item in items) item.channel];
    final now = DateTime.now();
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = items[index];
        return LiveTvFocusable(
          autofocus: index == 0,
          onTap: () => openLiveTvChannel(context, item.channel.id),
          builder: (focused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: focused ? liveTvChipColor : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 48,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: liveTvCardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: liveTvCardBorder),
                  ),
                  child: LiveTvChannelLogo(
                    channelId: item.channel.id,
                    imageTag: item.channel.imageTag,
                    name: item.channel.name,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.programName ?? l10n.esplayLiveTvNoGuide,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD4D4D8),
                          fontSize: 13,
                        ),
                      ),
                      if (item.hasGuide) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Expanded(
                              child: LiveTvProgressBar(value: item.progress(now)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.esplayLiveTvMinutesLeft(
                                item.minutesLeft(now),
                              ),
                              style: const TextStyle(
                                color: liveTvMutedText,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // Play straight away from the list; the row itself opens the
                // channel's page.
                IconButton(
                  tooltip: l10n.play,
                  icon: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  onPressed: () => playLiveTvChannel(context, channels, index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Message({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: liveTvMutedText, fontSize: 15),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            LiveTvChip(
              label: Text(l10n.retry),
              autofocus: true,
              onTap: onRetry!,
            ),
          ],
        ],
      ),
    );
  }
}
