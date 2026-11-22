import 'package:flutter/material.dart';

import '../../../esplay/esplay_requests.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../livetv/live_tv_tag_widgets.dart';
import 'esplay_requests_screen.dart';

const _red = Color(0xFFE71414);
const _muted = Color(0xFFA1A1AA);

/// Report a problem with a movie, series or episode to the EsPlay panel.
class EsplayReportDialog extends StatefulWidget {
  const EsplayReportDialog({super.key, required this.itemId, required this.title, this.api});

  final String itemId;
  final String title;
  final EsplayRequestsApi? api;

  static Future<void> show(BuildContext context, {required String itemId, required String title}) {
    return showDialog<void>(
      context: context,
      builder: (_) => EsplayReportDialog(itemId: itemId, title: title),
    );
  }

  @override
  State<EsplayReportDialog> createState() => _EsplayReportDialogState();
}

class _EsplayReportDialogState extends State<EsplayReportDialog> {
  late final EsplayRequestsApi _api = widget.api ?? EsplayRequestsApi();
  final _note = TextEditingController();
  String? _category;
  bool _sending = false;
  bool _done = false;
  String? _message;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_category == null || _sending) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await _api.report(widget.itemId, _category!, _note.text.trim());
      if (!mounted) return;
      setState(() {
        _done = true;
        _message = l10n.esplayReportThanks;
      });
    } catch (e) {
      if (mounted) setState(() => _message = esplayRequestErrorText(l10n, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  (String, String) _text(AppLocalizations l10n, String id) => switch (id) {
    'audio' => (l10n.audio, l10n.esplayReportAudioHint),
    'imagen' => (l10n.esplayReportPicture, l10n.esplayReportPictureHint),
    'subtitulos' => (l10n.subtitles, l10n.esplayReportSubtitlesHint),
    _ => (l10n.esplayReportQuality, l10n.esplayReportQualityHint),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTV = PlatformDetection.isTV;
    return Dialog(
      backgroundColor: const Color(0xFF141416),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.esplayReportProblem,
                style: TextStyle(color: Colors.white, fontSize: isTV ? 26 : 21, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(widget.title, style: const TextStyle(color: _muted, fontSize: 14)),
              if (!_done) ...[
                const SizedBox(height: 18),
                Text(l10n.esplayReportWhatsWrong, style: const TextStyle(color: Color(0xFFD4D4D8))),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (i, id) in esplayReportCategories.indexed)
                      _CategoryButton(
                        label: _text(l10n, id).$1,
                        hint: _text(l10n, id).$2,
                        selected: _category == id,
                        autofocus: i == 0,
                        onTap: () => setState(() => _category = id),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _note,
                  maxLength: 300,
                  maxLines: isTV ? 1 : 3,
                  minLines: 1,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: l10n.esplayReportDetailsHint,
                    hintStyle: const TextStyle(color: _muted),
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFF0C0C0E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF3F3F46)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _red, width: 2),
                    ),
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 14),
                Text(
                  _message!,
                  style: TextStyle(color: _done ? const Color(0xFFBBF7D0) : const Color(0xFFFCA5A5)),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _done ? '' : l10n.esplayReportDailyHint,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                  _DialogButton(
                    label: _done ? l10n.close : l10n.cancel,
                    autofocus: _done,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  if (!_done) ...[
                    const SizedBox(width: 10),
                    _DialogButton(
                      label: _sending ? l10n.esplaySending : l10n.esplaySend,
                      primary: true,
                      enabled: _category != null && !_sending,
                      onTap: _send,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final String hint;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      child: LiveTvFocusable(
        onTap: onTap,
        autofocus: autofocus,
        radius: BorderRadius.circular(12),
        builder: (focused) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? _red : const Color(0xFF1C1C20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused ? Colors.white : (selected ? _red : const Color(0xFF2E2E34)),
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(hint, style: const TextStyle(color: Color(0xFFD4D4D8), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.enabled = true,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: LiveTvFocusable(
        onTap: enabled ? onTap : () {},
        autofocus: autofocus,
        radius: BorderRadius.circular(22),
        builder: (focused) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: primary ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: focused ? _red : (primary ? Colors.white : const Color(0xFF3F3F46)),
              width: 2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: primary ? Colors.black : Colors.white,
              fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
