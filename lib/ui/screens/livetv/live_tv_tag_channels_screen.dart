import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../esplay/live_tv_tags.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';
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

class _LiveTvTagChannelsScreenState extends State<LiveTvTagChannelsScreen>
    with LiveTvChannelsLayout {
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
                      const SizedBox(width: 16),
                      ...sortAndSizeChips(l10n, showSize: _grid),
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
                      final items = sortChannels(snapshot.data ?? const []);
                      if (items.isEmpty) {
                        return _Message(text: l10n.esplayLiveTvNoChannels);
                      }
                      return _grid
                          ? LiveTvChannelGrid(
                              items: items,
                              columns: isTV ? 4 : 2,
                              maxTileWidth: maxTileWidth,
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

  /// When set, the grid fits as many columns as tiles of at most this width
  /// allow, instead of [columns].
  final double? maxTileWidth;

  const LiveTvChannelGrid({
    super.key,
    required this.items,
    required this.columns,
    this.autofocusFirst = true,
    this.maxTileWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (maxTileWidth != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 16.0;
          final cols =
              ((constraints.maxWidth + spacing) / (maxTileWidth! + spacing))
                  .ceil()
                  .clamp(1, 16);
          final tileWidth =
              (constraints.maxWidth - spacing * (cols - 1)) / cols;
          // Big tiles also show what's on; small ones only the program name.
          final large = tileWidth >= 260;
          final textHeight = large ? 54.0 : 28.0;
          return GridView.builder(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              mainAxisExtent: tileWidth * 9 / 16 + textHeight,
            ),
            itemBuilder: (context, index) => LiveTvChannelCard(
              item: items[index],
              large: large,
              autofocus: autofocusFirst && index == 0,
              onTap: () => openLiveTvChannel(context, items[index].channel.id),
            ),
          );
        },
      );
    }
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
                              child: LiveTvProgressBar(
                                value: item.progress(now),
                              ),
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

/// The order and grid size of a tag's channels, shared by the tag's own
/// screen and the TV Tags tab. Both choices are remembered.
mixin LiveTvChannelsLayout<T extends StatefulWidget> on State<T> {
  final _prefs = GetIt.instance<UserPreferences>();
  late String _sort = _prefs.get(UserPreferences.esplayTagChannelsSort);
  late int _size = _prefs
      .get(UserPreferences.esplayTagChannelsGridSize)
      .clamp(0, _tileWidths.length - 1);

  /// Widest a grid tile may be at each size step; the grid fits as many
  /// columns as that allows.
  static List<double> get _tileWidths => PlatformDetection.isTV
      ? const [200, 260, 340, 440]
      : const [150, 210, 290, 400];

  static const _sorts = ['server', 'number', 'name', 'endsSoon', 'favorites'];

  double get maxTileWidth => _tileWidths[_size];

  String sortLabel(AppLocalizations l10n, String sort) => switch (sort) {
    'number' => l10n.esplayLiveTvSortNumber,
    'name' => l10n.esplayLiveTvSortName,
    'endsSoon' => l10n.esplayLiveTvSortEndsSoon,
    'favorites' => l10n.esplayLiveTvSortFavorites,
    _ => l10n.esplayLiveTvSortServer,
  };

  void _setSort(String sort) {
    setState(() => _sort = sort);
    _prefs.set(UserPreferences.esplayTagChannelsSort, sort);
  }

  void _setSize(int size) {
    setState(() => _size = size);
    _prefs.set(UserPreferences.esplayTagChannelsGridSize, size);
  }

  Future<void> pickSort(BuildContext chipContext) async {
    final l10n = AppLocalizations.of(context);
    final box = chipContext.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(chipContext).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(
      Offset(0, box.size.height + 4),
      ancestor: overlay,
    );
    final picked = await showMenu<String>(
      context: context,
      color: liveTvChipColor,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlay.size.width - topLeft.dx,
        0,
      ),
      items: [
        for (final sort in _sorts)
          CheckedPopupMenuItem<String>(
            value: sort,
            checked: sort == _sort,
            child: Text(
              sortLabel(l10n, sort),
              style: const TextStyle(color: Colors.white),
            ),
          ),
      ],
    );
    if (picked != null && picked != _sort) _setSort(picked);
  }

  /// The channels in the chosen order; ties keep the server's order.
  List<LiveTvTagChannel> sortChannels(List<LiveTvTagChannel> items) {
    if (_sort == 'server') return items;
    final now = DateTime.now();
    final order = {for (var i = 0; i < items.length; i++) items[i]: i};
    int compare(LiveTvTagChannel a, LiveTvTagChannel b) {
      switch (_sort) {
        case 'number':
          return _channelNumber(a).compareTo(_channelNumber(b));
        case 'name':
          return _sortName(a).compareTo(_sortName(b));
        case 'endsSoon':
          if (a.hasGuide != b.hasGuide) return a.hasGuide ? -1 : 1;
          return a.minutesLeft(now).compareTo(b.minutesLeft(now));
        case 'favorites':
          if (a.channel.isFavorite == b.channel.isFavorite) return 0;
          return a.channel.isFavorite ? -1 : 1;
      }
      return 0;
    }

    return [...items]..sort((a, b) {
      final c = compare(a, b);
      return c != 0 ? c : order[a]!.compareTo(order[b]!);
    });
  }

  /// Channels without a number go last.
  static double _channelNumber(LiveTvTagChannel item) =>
      double.tryParse(item.channel.number?.trim() ?? '') ?? double.infinity;

  /// The name without its country prefix (`|ES|`, `ES-AV|`, `[ES-P]`...), so
  /// AMC sorts under A whatever feed it comes from.
  static String _sortName(LiveTvTagChannel item) => item.channel.name
      .replaceFirst(RegExp(r'^\s*[\[|]?[A-Za-z]{2}(-[A-Za-z]+)?[\]|]\s*'), '')
      .trim()
      .toLowerCase();

  /// The sort chip and, when [showSize], the smaller and bigger chips.
  List<Widget> sortAndSizeChips(
    AppLocalizations l10n, {
    bool showSize = true,
  }) => [
    Builder(
      builder: (chipContext) => LiveTvChip(
        height: 36,
        onTap: () => pickSort(chipContext),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              '${l10n.esplayLiveTvSort}: '
              '${sortLabel(l10n, _sort)}',
            ),
          ],
        ),
      ),
    ),
    if (showSize) ...[
      const SizedBox(width: 16),
      Semantics(
        label: l10n.esplayLiveTvSmaller,
        child: LiveTvChip(
          height: 36,
          onTap: () {
            if (_size > 0) _setSize(_size - 1);
          },
          label: Icon(
            Icons.zoom_out_rounded,
            size: 20,
            color: _size > 0 ? Colors.white : liveTvMutedText,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Semantics(
        label: l10n.esplayLiveTvBigger,
        child: LiveTvChip(
          height: 36,
          onTap: () {
            if (_size < _tileWidths.length - 1) {
              _setSize(_size + 1);
            }
          },
          label: Icon(
            Icons.zoom_in_rounded,
            size: 20,
            color: _size < _tileWidths.length - 1
                ? Colors.white
                : liveTvMutedText,
          ),
        ),
      ),
    ],
  ];
}
