import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:server_core/server_core.dart';

import '../../../esplay/live_tv_tags.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/bottom_nav/bottom_navbar.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/top_toolbar.dart';
import 'live_tv_tag_channels_screen.dart';
import 'live_tv_tag_widgets.dart';

enum _Section { home, tags }

/// EsPlay's live TV start page: the channel tags from Emby, what is on now and
/// a row per tag, with the guide and recordings one tab away.
class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  _Section _section = _Section.home;

  static bool get _showNavbar => !PlatformDetection.isTV;

  @override
  Widget build(BuildContext context) {
    final page = _buildContent(context);
    return RequestInitialFocus(
      child: _showNavbar
          ? Scaffold(
              backgroundColor: Colors.black,
              body: NavigationLayout(showBackButton: true, child: page),
            )
          : page,
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTV = PlatformDetection.isTV;
    // The navbar draws over the page, and a left or bottom one puts the back
    // button in the corner the title uses.
    final position =
        NavigationLayout.positionNotifier.value ?? NavbarPosition.top;
    final topInset = !_showNavbar
        ? 0.0
        : position == NavbarPosition.top
        ? TopToolbar.heightFor(context)
        : 56.0;
    final leftInset = _showNavbar && position == NavbarPosition.left
        ? 72.0
        : 0.0;
    final side = isTV ? 48.0 : 20.0;
    final hasTags = LiveTvTagsRepository.instance.isSupported;

    final tabs = <({String label, bool selected, VoidCallback onTap})>[
      (
        label: l10n.esplayLiveTvHome,
        selected: _section == _Section.home,
        onTap: () => setState(() => _section = _Section.home),
      ),
      if (hasTags)
        (
          label: l10n.esplayLiveTvTags,
          selected: _section == _Section.tags,
          onTap: () => setState(() => _section = _Section.tags),
        ),
      (
        label: l10n.guide,
        selected: false,
        onTap: () => context.push(Destinations.liveTvGuide),
      ),
      (
        label: l10n.recordings,
        selected: false,
        onTap: () => context.push(Destinations.liveTvRecordings),
      ),
      (
        label: l10n.schedule,
        selected: false,
        onTap: () => context.push(Destinations.liveTvSchedule),
      ),
      (
        label: l10n.seriesRecordings,
        selected: false,
        onTap: () => context.push(Destinations.liveTvSeriesRecordings),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: leftInset,
            top: topInset + (isTV ? 32 : 12),
            bottom: bottomNavContentPadding(context, 0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: side),
                child: Text(
                  l10n.liveTv,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isTV ? 30 : 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: side),
                  itemCount: tabs.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = tabs[index];
                    return Center(
                      child: LiveTvChip(
                        label: Text(tab.label),
                        selected: tab.selected,
                        autofocus: index == 0,
                        onTap: tab.onTap,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: switch (_section) {
                  _Section.home => _HomeView(
                    side: side,
                    onSeeAllTags: () =>
                        setState(() => _section = _Section.tags),
                  ),
                  _Section.tags =>
                    isTV ? _TvTagsView(side: side) : _TagsGrid(side: side),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _openTag(BuildContext context, LiveTvTag tag) {
  context.push(Destinations.liveTvTagChannels(tag.id, tag.name));
}

class _SectionTitle extends StatelessWidget {
  final Widget title;
  final String? action;
  final VoidCallback? onAction;
  final double side;

  const _SectionTitle({
    required this.title,
    required this.side,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 8, side, 10),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: Colors.white,
                fontSize: PlatformDetection.isTV ? 22 : 18,
                fontWeight: FontWeight.w700,
              ),
              child: title,
            ),
          ),
          if (action != null && onAction != null)
            LiveTvFocusable(
              onTap: onAction!,
              radius: BorderRadius.circular(8),
              builder: (focused) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  action!,
                  style: TextStyle(
                    color: liveTvRed,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeView extends StatefulWidget {
  final double side;
  final VoidCallback onSeeAllTags;

  const _HomeView({required this.side, required this.onSeeAllTags});

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  late final Future<List<LiveTvTag>> _tags =
      LiveTvTagsRepository.instance.tags().catchError((_) => <LiveTvTag>[]);
  late final Future<List<Map<String, dynamic>>> _onNow = _loadOnNow();

  Future<List<Map<String, dynamic>>> _loadOnNow() async {
    try {
      final client = GetIt.instance<MediaServerClient>();
      final api = client.liveTvApi;
      // Emby's call also brings each program's channel name and logo.
      final response = api is LiveTvChannelTagsApi
          ? await (api as LiveTvChannelTagsApi).getAiringPrograms(
              limit: 12,
              userId: client.userId,
            )
          : await api.getRecommendedPrograms(limit: 12, isAiring: true);
      return ((response['Items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .where((item) => item['ChannelId'] != null)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final side = widget.side;
    final isTV = PlatformDetection.isTV;
    return FutureBuilder<List<LiveTvTag>>(
      future: _tags,
      builder: (context, tagSnapshot) {
        final tags = tagSnapshot.data ?? const <LiveTvTag>[];
        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            if (tags.isNotEmpty) ...[
              _SectionTitle(
                side: side,
                title: Text(l10n.esplayLiveTvTags),
                action: l10n.esplayLiveTvSeeAllTags,
                onAction: widget.onSeeAllTags,
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: side),
                  itemCount: tags.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => Center(
                    child: LiveTvChip(
                      label: LiveTvTagName(
                        tag: tags[index],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () => _openTag(context, tags[index]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _onNow,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const [];
                if (items.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(side: side, title: Text(l10n.esplayLiveTvOnNow)),
                    SizedBox(
                      height: isTV ? 360 : 290,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: side),
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, index) => SizedBox(
                          width: isTV ? 200 : 160,
                          child: _OnNowCard(program: items[index]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
            for (final tag in tags) _TagRow(tag: tag, side: side),
          ],
        );
      },
    );
  }
}

/// A program airing now as a poster. Select opens its channel's page.
class _OnNowCard extends StatelessWidget {
  final Map<String, dynamic> program;

  const _OnNowCard({required this.program});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => LiveTvFocusable(
        onTap: () => openLiveTvChannel(
          context,
          program['ChannelId'].toString(),
        ),
        builder: (focused) => LiveTvOnNowPoster(
          program: program,
          width: constraints.maxWidth,
        ),
      ),
    );
  }
}

/// One tag's channels in a row on the start page. It loads when it scrolls
/// into view and stays out of the way when the tag is empty.
class _TagRow extends StatefulWidget {
  final LiveTvTag tag;
  final double side;

  const _TagRow({required this.tag, required this.side});

  @override
  State<_TagRow> createState() => _TagRowState();
}

class _TagRowState extends State<_TagRow> {
  late final Future<List<LiveTvTagChannel>> _channels = LiveTvTagsRepository
      .instance
      .channels(widget.tag.id)
      .catchError((_) => <LiveTvTagChannel>[]);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTV = PlatformDetection.isTV;
    return FutureBuilder<List<LiveTvTagChannel>>(
      future: _channels,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(height: isTV ? 230 : 170);
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              side: widget.side,
              title: LiveTvTagName(
                tag: widget.tag,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isTV ? 22 : 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              action: l10n.esplayLiveTvSeeChannels,
              onAction: () => _openTag(context, widget.tag),
            ),
            SizedBox(
              height: isTV ? 180 : 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: widget.side),
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) => SizedBox(
                  width: isTV ? 240 : 150,
                  child: LiveTvChannelCard(
                    item: items[index],
                    onTap: () => openLiveTvChannel(context, items[index].channel.id),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

/// Phone and tablet: every tag as a card with a few of its channels.
class _TagsGrid extends StatefulWidget {
  final double side;

  const _TagsGrid({required this.side});

  @override
  State<_TagsGrid> createState() => _TagsGridState();
}

class _TagsGridState extends State<_TagsGrid> {
  late Future<List<LiveTvTag>> _tags = LiveTvTagsRepository.instance.tags();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<LiveTvTag>>(
      future: _tags,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CenteredMessage(
            text: l10n.esplayLiveTvLoadError,
            onRetry: () => setState(() {
              _tags = LiveTvTagsRepository.instance.tags(refresh: true);
            }),
          );
        }
        final tags = snapshot.data ?? const [];
        if (tags.isEmpty) return _CenteredMessage(text: l10n.esplayLiveTvNoTags);
        final width = MediaQuery.sizeOf(context).width;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(widget.side, 0, widget.side, 120),
          itemCount: tags.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: width >= 900 ? 4 : width >= 600 ? 3 : 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 96,
          ),
          itemBuilder: (context, index) => _TagCard(tag: tags[index]),
        );
      },
    );
  }
}

class _TagCard extends StatefulWidget {
  final LiveTvTag tag;

  const _TagCard({required this.tag});

  @override
  State<_TagCard> createState() => _TagCardState();
}

class _TagCardState extends State<_TagCard> {
  late final Future<List<LiveTvTagChannel>> _channels = LiveTvTagsRepository
      .instance
      .channels(widget.tag.id)
      .catchError((_) => <LiveTvTagChannel>[]);

  @override
  Widget build(BuildContext context) {
    final tag = widget.tag;
    return LiveTvFocusable(
      onTap: () => _openTag(context, tag),
      radius: BorderRadius.circular(14),
      builder: (focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: liveTvCardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: liveTvCardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (tag.number != null)
              Text(
                tag.number!,
                style: TextStyle(
                  color: liveTvRed,
                  fontSize: 26,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            Text(
              tag.label,
              maxLines: tag.number == null ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            FutureBuilder<List<LiveTvTagChannel>>(
              future: _channels,
              builder: (context, snapshot) => Text(
                (snapshot.data ?? const [])
                    .take(3)
                    .map((item) => item.channel.name)
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: liveTvMutedText, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Android TV: the tags down the left, the focused tag's channels on the right.
class _TvTagsView extends StatefulWidget {
  final double side;

  const _TvTagsView({required this.side});

  @override
  State<_TvTagsView> createState() => _TvTagsViewState();
}

class _TvTagsViewState extends State<_TvTagsView> {
  late final Future<List<LiveTvTag>> _tags = LiveTvTagsRepository.instance
      .tags();
  LiveTvTag? _selected;
  Future<List<LiveTvTagChannel>>? _channels;

  void _select(LiveTvTag tag) {
    if (_selected?.id == tag.id) return;
    setState(() {
      _selected = tag;
      _channels = LiveTvTagsRepository.instance.channels(tag.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<LiveTvTag>>(
      future: _tags,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final tags = snapshot.data ?? const [];
        if (tags.isEmpty) {
          return _CenteredMessage(
            text: snapshot.hasError
                ? l10n.esplayLiveTvLoadError
                : l10n.esplayLiveTvNoTags,
          );
        }
        if (_selected == null) {
          _selected = tags.first;
          _channels = LiveTvTagsRepository.instance.channels(tags.first.id);
        }
        final selected = _selected!;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.side),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 300,
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: tags.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final tag = tags[index];
                    final isSelected = tag.id == selected.id;
                    return LiveTvFocusable(
                      autofocus: index == 0,
                      radius: BorderRadius.circular(10),
                      onFocusChange: (focused) {
                        if (focused) _select(tag);
                      },
                      onTap: () => _openTag(context, tag),
                      builder: (focused) => Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: LiveTvTagName(
                          tag: tag,
                          numberColor: isSelected
                              ? const Color(0xFFB80F0F)
                              : null,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.black
                                : const Color(0xFFD4D4D8),
                            fontSize: 17,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LiveTvTagName(
                      tag: selected,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: FutureBuilder<List<LiveTvTagChannel>>(
                        key: ValueKey(selected.id),
                        future: _channels,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final items = snapshot.data ?? const [];
                          if (items.isEmpty) {
                            return _CenteredMessage(
                              text: snapshot.hasError
                                  ? l10n.esplayLiveTvLoadError
                                  : l10n.esplayLiveTvNoChannels,
                            );
                          }
                          return LiveTvChannelGrid(
                            items: items,
                            columns: 4,
                            autofocusFirst: false,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _CenteredMessage({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
              LiveTvChip(label: Text(l10n.retry), onTap: onRetry!),
            ],
          ],
        ),
      ),
    );
  }
}
