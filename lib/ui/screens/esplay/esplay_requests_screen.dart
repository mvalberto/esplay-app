import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../esplay/esplay_requests.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/top_toolbar.dart';
import '../livetv/live_tv_tag_widgets.dart';

const _red = Color(0xFFE71414);
const _muted = Color(0xFFA1A1AA);
const _card = Color(0xFF18181B);

/// The panel's error codes in the viewer's words.
String esplayRequestErrorText(AppLocalizations l10n, Object error) {
  final e = error is EsplayRequestException ? error : null;
  return switch (e?.code) {
    'limite_semanal' => l10n.esplayRequestsWeeklyLimit(
      '${e!.data['libera'] ?? ''}',
    ),
    'limite_diario' => l10n.esplayReportsDailyLimit(
      '${e!.data['libera'] ?? ''}',
    ),
    'ya_disponible' => l10n.esplayRequestsAlreadyOn,
    'no_autenticado' => l10n.esplayRequestsNoSession,
    'sin_conexion' => l10n.esplayPanelUnavailable,
    _ => l10n.esplayRequestsGenericError,
  };
}

String _interested(AppLocalizations l10n, Object? n) =>
    n == 1 ? l10n.esplayOneInterested : l10n.esplayInterested('$n');

/// EsPlay requests: look a title up, ask for it (or join someone else's
/// request), and follow your requests and reports.
class EsplayRequestsScreen extends StatefulWidget {
  const EsplayRequestsScreen({super.key, this.api});

  final EsplayRequestsApi? api;

  @override
  State<EsplayRequestsScreen> createState() => _EsplayRequestsScreenState();
}

class _EsplayRequestsScreenState extends State<EsplayRequestsScreen> {
  late final EsplayRequestsApi _api = widget.api ?? EsplayRequestsApi();
  final _query = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  bool _mineTab = false;
  bool _searching = false;
  List<Map<String, dynamic>>? _results;
  List<Map<String, dynamic>>? _mine;
  String? _error;
  int? _remaining;
  int _max = 2;

  static bool get _showNavbar => !PlatformDetection.isTV;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() => _searching = true);
    try {
      final data = await _api.search(q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = [
          for (final r in (data['results'] as List? ?? const []))
            if (r is Map) r.cast<String, dynamic>(),
        ];
        _remaining = data['remaining'] as int?;
        _max = data['max'] as int? ?? 2;
        _error = null;
      });
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() => _error = esplayRequestErrorText(AppLocalizations.of(context), e));
      }
    } finally {
      if (mounted && seq == _seq) setState(() => _searching = false);
    }
  }

  Future<void> _loadMine() async {
    setState(() => _mine = null);
    try {
      final data = await _api.mine();
      if (!mounted) return;
      setState(() {
        _mine = [
          for (final r in (data['items'] as List? ?? const []))
            if (r is Map) r.cast<String, dynamic>(),
        ];
        _remaining = data['remaining'] as int?;
        _max = data['max'] as int? ?? 2;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _mine = const [];
          _error = esplayRequestErrorText(AppLocalizations.of(context), e);
        });
      }
    }
  }

  Future<void> _openTitle(Map<String, dynamic> item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EsplayRequestTitleScreen(api: _api, item: item),
      ),
    );
    final q = _query.text.trim();
    if (!_mineTab && q.length >= 2) _search(q);
    if (_mineTab) _loadMine();
  }

  void _setTab(bool mine) {
    setState(() {
      _mineTab = mine;
      _error = null;
    });
    if (mine) _loadMine();
  }

  @override
  Widget build(BuildContext context) {
    final page = _buildContent(context);
    return RequestInitialFocus(
      child: _showNavbar
          ? Scaffold(
              backgroundColor: Colors.black,
              body: NavigationLayout(showBackButton: true, child: page),
            )
          : Scaffold(backgroundColor: Colors.black, body: page),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTV = PlatformDetection.isTV;
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
    final side = isTV ? 48.0 : 16.0;
    final width = MediaQuery.sizeOf(context).width - leftInset - side * 2;
    final columns = isTV ? 6 : (width / 130).floor().clamp(2, 8);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(side + leftInset, topInset + 16, side, 0),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                runSpacing: 8,
                spacing: 16,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.esplayRequests,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTV ? 32 : 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Pill(
                            label: l10n.esplayRequestATitle,
                            selected: !_mineTab,
                            autofocus: true,
                            onTap: () => _setTab(false),
                          ),
                          const SizedBox(width: 10),
                          _Pill(
                            label: l10n.esplayMyRequests,
                            selected: _mineTab,
                            onTap: () => _setTab(true),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_remaining != null)
                    Text(
                      l10n.esplayRequestsLeft('$_remaining', '$_max'),
                      style: const TextStyle(color: _muted, fontSize: 14),
                    ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            if (!_mineTab) ...[
              SliverToBoxAdapter(
                child: TextField(
                  controller: _query,
                  onChanged: _onQuery,
                  onSubmitted: (v) {
                    if (v.trim().length >= 2) _search(v.trim());
                  },
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: InputDecoration(
                    hintText: l10n.esplaySearchTitleHint,
                    hintStyle: const TextStyle(color: _muted),
                    prefixIcon: const Icon(Icons.search, color: _muted),
                    filled: true,
                    fillColor: const Color(0xFF1C1C20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _red, width: 2),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(child: _status(l10n)),
              if (_results != null)
                SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.48,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _ResultCard(
                      item: _results![i],
                      onTap: () => _openTitle(_results![i]),
                    ),
                    childCount: _results!.length,
                  ),
                ),
            ] else ...[
              SliverToBoxAdapter(child: _status(l10n)),
              if (_mine != null)
                SliverList.builder(
                  itemCount: _mine!.length,
                  itemBuilder: (context, i) => _MineRow(
                    row: _mine![i],
                    onTap: () {
                      final row = _mine![i];
                      if (row['kind'] == 'reporte' || (row['tmdb_id'] ?? 0) == 0) {
                        return;
                      }
                      _openTitle({
                        'id': row['tmdb_id'],
                        'media_type': row['media_type'],
                        'title': row['title'],
                        'year': row['year'],
                        'poster': row['poster'],
                      });
                    },
                  ),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }

  Widget _status(AppLocalizations l10n) {
    String? text;
    var color = _muted;
    if (_error != null) {
      text = _error;
      color = const Color(0xFFFCA5A5);
    } else if (_mineTab) {
      if (_mine == null) text = l10n.esplayLoading;
      if (_mine != null && _mine!.isEmpty) text = l10n.esplayNoRequestsYet;
    } else if (_searching && _results == null) {
      text = l10n.esplaySearching;
    } else if (_results == null) {
      text = l10n.esplaySearchIntro;
    } else if (_results!.isEmpty) {
      text = l10n.noResults;
    }
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(text, style: TextStyle(color: color, fontSize: 16)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LiveTvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      radius: BorderRadius.circular(24),
      builder: (focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFF1C1C20),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: focused
                ? _red
                : selected
                ? Colors.white
                : const Color(0xFF2E2E34),
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url, required this.title});

  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: _card,
        child: url == null || url!.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.background, this.foreground);

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _kind(AppLocalizations l10n, Object? mediaType) =>
    mediaType == 'tv' ? l10n.series : l10n.movie;

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final request = item['request'];
    final inLibrary = '${item['library_item_id'] ?? ''}'.isNotEmpty;
    final year = '${item['year'] ?? ''}';
    return LiveTvFocusable(
      onTap: onTap,
      radius: BorderRadius.circular(12),
      builder: (focused) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
              child: _Poster(
                url: item['poster'] as String?,
                title: '${item['title'] ?? ''}',
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${item['title'] ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          Text(
            year.isEmpty
                ? _kind(l10n, item['media_type'])
                : '${_kind(l10n, item['media_type'])} · $year',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          if (inLibrary)
            _Badge(
              l10n.esplayOnEsplay,
              const Color(0xFF14532D),
              const Color(0xFFBBF7D0),
            )
          else if (request is Map)
            _Badge(
              '${l10n.esplayAskedFor} · ${_interested(l10n, request['followers'])}',
              _red,
              Colors.white,
            )
          else
            const SizedBox(height: 18),
        ],
      ),
    );
  }
}

(String, Color, Color) _statusBadge(AppLocalizations l10n, Map row) {
  final report = row['kind'] == 'reporte';
  return switch (row['status']) {
    'en_curso' => (
      l10n.esplayStatusInProgress,
      const Color(0xFF1E3A8A),
      const Color(0xFFDBEAFE),
    ),
    'hecha' => (
      report ? l10n.esplayStatusSolved : l10n.esplayStatusDone,
      const Color(0xFF14532D),
      const Color(0xFFBBF7D0),
    ),
    'rechazada' => (
      l10n.esplayStatusRejected,
      const Color(0xFF450A0A),
      const Color(0xFFFECACA),
    ),
    _ => (l10n.esplayStatusPending, const Color(0xFF3F3F46), Colors.white),
  };
}

class _MineRow extends StatelessWidget {
  const _MineRow({required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final report = row['kind'] == 'reporte';
    final (label, bg, fg) = _statusBadge(l10n, row);
    final year = '${row['year'] ?? ''}';
    final followers = row['followers'] as int? ?? 0;
    final sub = [
      if (report)
        '${row['note'] ?? ''}'
      else
        year.isEmpty ? _kind(l10n, row['media_type']) : '${_kind(l10n, row['media_type'])} · $year',
      row['mine'] == true
          ? l10n.esplayRequestedOn('${row['created'] ?? ''}')
          : l10n.esplayYouJoined,
      if (!report && followers > 1) _interested(l10n, followers),
    ].where((s) => s.isNotEmpty).join(' · ');
    final note = '${row['admin_note'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LiveTvFocusable(
        onTap: onTap,
        radius: BorderRadius.circular(14),
        builder: (focused) => Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 78,
                child: report
                    ? Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF27272A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.report_problem_outlined, color: _muted),
                      )
                    : _Poster(
                        url: row['poster'] as String?,
                        title: '${row['title'] ?? ''}',
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report
                          ? '${l10n.esplayReport} · ${row['title'] ?? ''}'
                          : '${row['title'] ?? ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(sub, style: const TextStyle(color: _muted, fontSize: 13)),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${l10n.esplayReply}: «$note»',
                        style: const TextStyle(color: Color(0xFFE4E4E7), fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _Badge(label, bg, fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// A title from TMDB: request it, join the open request, or open it when it
/// is already on EsPlay.
class EsplayRequestTitleScreen extends StatefulWidget {
  const EsplayRequestTitleScreen({
    super.key,
    required this.api,
    required this.item,
  });

  final EsplayRequestsApi api;
  final Map<String, dynamic> item;

  @override
  State<EsplayRequestTitleScreen> createState() =>
      _EsplayRequestTitleScreenState();
}

class _EsplayRequestTitleScreenState extends State<EsplayRequestTitleScreen> {
  Map<String, dynamic>? _data;
  late Map<String, dynamic> _item = widget.item;
  String? _message;
  bool _ok = false;
  bool _sending = false;
  bool _needsRisk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _tmdbId => (_item['id'] as num).toInt();
  String get _mediaType => '${_item['media_type']}';

  Future<void> _load() async {
    try {
      final data = await widget.api.title(_mediaType, _tmdbId);
      if (!mounted) return;
      setState(() {
        _data = data;
        if (data['item'] is Map) {
          _item = (data['item'] as Map).cast<String, dynamic>();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _message = esplayRequestErrorText(AppLocalizations.of(context), e));
      }
    }
  }

  Future<void> _request({bool acceptRisk = false}) async {
    if (_sending) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      final res = await widget.api.request(_mediaType, _tmdbId, acceptRisk: acceptRisk);
      await _load();
      if (!mounted) return;
      setState(() {
        _ok = true;
        _needsRisk = false;
        _message = res['result'] == 'followed'
            ? l10n.esplayFollowedMessage
            : l10n.esplayRequestedMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _needsRisk = e is EsplayRequestException && e.code == 'requiere_aceptar_riesgo';
        _message = _needsRisk ? null : esplayRequestErrorText(l10n, e);
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _watch() {
    final id = '${(_data?['library'] as Map?)?['item_id'] ?? ''}';
    if (id.isEmpty) return;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(Destinations.item(id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTV = PlatformDetection.isTV;
    final data = _data;
    final lib = data?['library'] as Map?;
    final found = lib?['found'] == true;
    final request = data?['request'] as Map?;
    final following = data?['following'] == true;
    final es = data?['es'] as List?;
    final year = '${_item['year'] ?? ''}';
    final overview = '${_item['overview'] ?? ''}';

    Widget? primary;
    if (found) {
      primary = _ActionButton(label: l10n.esplayWatchOnEsplay, primary: true, autofocus: true, onTap: _watch);
    } else if (following) {
      primary = _ActionButton(label: l10n.esplayYouFollowIt, autofocus: true, onTap: () {});
    } else if (_needsRisk) {
      primary = _ActionButton(
        label: l10n.esplayRequestAnyway,
        primary: true,
        autofocus: true,
        onTap: () => _request(acceptRisk: true),
      );
    } else if (data != null) {
      primary = _ActionButton(
        label: request != null ? l10n.esplayImInterested : l10n.esplayRequest,
        primary: true,
        autofocus: true,
        onTap: _sending ? () {} : _request,
      );
    }

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (year.isEmpty ? _kind(l10n, _mediaType) : '${_kind(l10n, _mediaType)} · $year').toUpperCase(),
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w700, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        Text(
          '${_item['title'] ?? ''}',
          style: TextStyle(color: Colors.white, fontSize: isTV ? 40 : 28, fontWeight: FontWeight.w800, height: 1.1),
        ),
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            overview,
            maxLines: isTV ? 5 : 8,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFD4D4D8), fontSize: 15, height: 1.45),
          ),
        ],
        if (data == null && _message == null) ...[
          const SizedBox(height: 12),
          Text(l10n.esplayLoading, style: const TextStyle(color: _muted)),
        ],
        if (es != null && es.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(l10n.esplayInSpainOn(es.join(', ')), style: const TextStyle(color: _muted)),
        ],
        if (es != null && es.isEmpty && !found) ...[
          const SizedBox(height: 10),
          Text(l10n.esplayNotInSpain, style: const TextStyle(color: Color(0xFFFBBF24))),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ?primary,
            _ActionButton(label: l10n.back, onTap: () => Navigator.of(context).maybePop()),
          ],
        ),
        if (request != null && !found) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
            child: Text(
              [
                l10n.esplayAlreadyRequested,
                _statusBadge(l10n, {'status': request['status']}).$1,
                _interested(l10n, request['followers']),
              ].join(' · ') +
                  (following ? '' : '\n${l10n.esplayInterestedFree}'),
              style: const TextStyle(color: Colors.white, height: 1.5),
            ),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 14),
          Text(
            _message!,
            style: TextStyle(color: _ok ? const Color(0xFFBBF7D0) : const Color(0xFFFCA5A5), fontSize: 15),
          ),
        ],
        if (data != null && request == null && !found && data['remaining'] != null) ...[
          const SizedBox(height: 12),
          Text(
            l10n.esplayRequestsLeft('${data['remaining']}', '${data['max'] ?? 2}'),
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ],
      ],
    );

    final poster = _Poster(url: _item['poster'] as String?, title: '${_item['title'] ?? ''}');
    final wide = MediaQuery.sizeOf(context).width > 700;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isTV ? 48 : 18),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: isTV ? 260 : 200, height: isTV ? 390 : 300, child: poster),
                    const SizedBox(width: 36),
                    Expanded(child: info),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    Center(child: SizedBox(width: 180, height: 270, child: poster)),
                    const SizedBox(height: 18),
                    info,
                  ],
                ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return LiveTvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      radius: BorderRadius.circular(28),
      builder: (focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
        decoration: BoxDecoration(
          color: primary ? _red : _card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: focused ? Colors.white : (primary ? _red : const Color(0xFF3F3F46)),
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
