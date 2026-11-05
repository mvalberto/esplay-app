import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:server_core/server_core.dart';

import '../../../auth/repositories/server_repository.dart';
import '../../../auth/repositories/session_repository.dart';
import '../../../auth/store/authentication_preferences.dart';
import '../../../auth/store/credential_store.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/pin_code_util.dart';
import '../../../preference/preference_constants.dart';
import '../../navigation/destinations.dart';
import '../../widgets/adaptive/adaptive_dialog.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/pin_entry_dialog.dart';
import '../../widgets/focus/request_initial_focus.dart';

class StartupScreen extends StatefulWidget {
  final bool bootstrapActiveSession;

  const StartupScreen({
    super.key,
    this.bootstrapActiveSession = false,
  });

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _barController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();
  late final Animation<double> _fadeAnimation;
  // EsPlay: the logo's Tunnel intro. Play outlines fly at the camera, the
  // word lands, the play shoots through it, splits it and stays out. The app
  // moves on only once it has finished and the whole logo has stayed on
  // screen for a moment.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _introLength,
  );
  final Completer<void> _introCompleter = Completer<void>();
  Future<void> get _introDone => _introCompleter.future;

  static const _introLength = Duration(milliseconds: 2500);
  static const _introHold = Duration(milliseconds: 600);
  static const _logoLayers = ['word', 'tri'];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _playIntro();
    _initialize();
  }

  /// Loads the logo layers before starting, so a slow cold start doesn't eat
  /// the beginning of the animation.
  Future<void> _playIntro() async {
    try {
      await Future.wait([
        for (final name in _logoLayers)
          SvgAssetLoader('assets/images/esplay_logo_$name.svg').loadBytes(null),
      ]).timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (mounted) await _intro.forward().orCancel.catchError((_) {});
    await Future.delayed(_introHold);
    _introCompleter.complete();
    if (mounted) _fadeController.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _fadeController.dispose();
    _barController.dispose();
    super.dispose();
  }

  Future<void> _go(String location) async {
    await _introDone;
    if (mounted) context.go(location);
  }

  /// On a cold boot the app can win the race against Wi-Fi association and
  /// see the device as offline for a few seconds. Waiting here keeps the
  /// splash up briefly instead of bouncing the user to the offline fallback.
  /// Once online, also settle server reachability (the boot-time check runs
  /// before a client exists) so home loads in the right online/offline mode.
  Future<void> _waitForNetworkSettle() async {
    final connectivity = GetIt.instance<ConnectivityService>();
    if (!connectivity.isOnline) {
      await connectivity.waitForOnline(const Duration(seconds: 5));
    }
    if (connectivity.isOnline &&
        GetIt.instance.isRegistered<MediaServerClient>()) {
      try {
        await connectivity.recheckNow();
      } catch (_) {}
    }
  }

  Future<void> _initialize() async {
    final session = GetIt.instance<SessionRepository>();
    final serverRepo = GetIt.instance<ServerRepository>();
    final credentialStore = GetIt.instance<CredentialStore>();
    final authPrefs = GetIt.instance<AuthenticationPreferences>();

    if (session.state != SessionState.ready) {
      // Never wait here forever. A session that cannot finish restoring would
      // otherwise hold the splash with nothing on screen to say why.
      await session.stateStream
          .firstWhere((s) => s == SessionState.ready)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => SessionState.ready,
          );
    }

    await serverRepo.loadStoredServers();

    if (widget.bootstrapActiveSession && session.activeUserId != null) {
      await _waitForNetworkSettle();
      await _go(Destinations.home);
      return;
    }

    final behavior = authPrefs.loginBehavior;
    String? targetUserId;

    if (behavior == UserSelectBehavior.lastUser) {
      targetUserId = authPrefs.savedLastUserId;
    } else if (behavior == UserSelectBehavior.currentUser) {
      targetUserId = authPrefs.savedAutoLoginUserId;
    }

    bool pinEnabledForAutoLoginUser = false;
    if (targetUserId != null && targetUserId.isNotEmpty) {
      final store = GetIt.instance<PreferenceStore>();
      final pinUtil = PinCodeUtil(store, targetUserId);
      pinEnabledForAutoLoginUser = pinUtil.isPinEnabled;
    }

    final restored = (authPrefs.shouldAlwaysAuthenticate || pinEnabledForAutoLoginUser)
        ? false
        : await session.restoreSession();

    if (!mounted) return;
    // Dialogs wait for the logo too, so they never cover it half built.
    await _introDone;
    if (!mounted) return;

    // Read the flag either way so a one-off failure doesn't carry over to the
    // next launch, but only warn when it cost the user something. A session
    // that came back has the token it needs and the warning is just noise.
    final storageFailed = credentialStore.consumeSecureStorageUnavailable();
    if (storageFailed && !(restored && session.activeUserId != null)) {
      await _showSecureStorageWarning();
      if (!mounted) return;
    }

    if (restored && session.activeUserId != null) {
      final store = GetIt.instance<PreferenceStore>();
      final pinUtil = PinCodeUtil(store, session.activeUserId!);

      if (pinUtil.isPinEnabled) {
        final verified = await PinEntryDialog.show(
          context,
          mode: PinEntryMode.verify,
          onVerify: pinUtil.verifyPin,
          onForgotPin: () {
            if (mounted) context.go(Destinations.esplayLogin);
          },
        );

        if (!verified) {
          if (mounted) context.go(Destinations.esplayLogin);
          return;
        }
      }

      await _waitForNetworkSettle();
      await _go(Destinations.home);
    } else {
      // EsPlay: username and password only, whatever server was used before.
      await _go(Destinations.esplayLogin);
    }
  }

  Future<void> _showSecureStorageWarning() async {
    final l10n = AppLocalizations.of(context);
    await showFocusRestoringDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog.adaptive(
        title: Text(l10n.secureStorageUnavailable),
        content: Text(
          l10n.secureStorageUnavailableMessage,
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      RequestInitialFocus(child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    // EsPlay: the same black as the Android launch splash, which shows nothing
    // else, so the logo animation starts from an empty screen. Below the logo
    // a red bar runs along its track if starting takes longer.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(child: _buildLogoIntro()),
          Center(
            child: Padding(
              // Below the logo, which is as tall as a 3.57th of its width.
              padding: EdgeInsets.only(
                top:
                    math.min(MediaQuery.sizeOf(context).width * 0.62, 620.0) /
                        3.57 +
                    48,
              ),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    width: 100,
                    height: 3,
                    color: const Color(0xFF1C1C20),
                    child: AnimatedBuilder(
                      animation: _barController,
                      builder: (context, _) => Stack(
                        children: [
                          Positioned(
                            left: -40 + 140 * _barController.value,
                            top: 0,
                            bottom: 0,
                            width: 40,
                            child: ColoredBox(color: AppColorScheme.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The intro's timings in seconds, from the mockup (C:\esplay\brand).
  Animation<double> _phase(double from, double to, Curve curve) =>
      CurvedAnimation(
        parent: _intro,
        curve: Interval(from / 2.5, to / 2.5, curve: curve),
      );

  Widget _buildLogoIntro() {
    // The logo's artwork is 4640 x 1300 units, starting at (150, -110).
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(screen.width * 0.62, 620.0);
    final unit = width / 4640;
    final height = 1300 * unit;
    // In the mockup the logo is drawn at 0.3, so a screen pixel there is
    // this many here.
    final px = unit / 0.3;
    Widget layer(String name) => SvgPicture.asset(
          'assets/images/esplay_logo_$name.svg',
          width: width,
          height: height,
        );
    final word = _phase(1, 1.45, const Cubic(0.2, 1.3, 0.4, 1));
    final trail = _phase(1.55, 2.25, Curves.easeOut);
    final shot = _phase(1.55, 1.91, const Cubic(0.5, 0, 0.3, 1));
    final split = _phase(1.8, 2.22, const Cubic(0.2, 1.5, 0.4, 1));
    final pop = _phase(1.9, 2.4, Curves.easeOut);
    final shake = _phase(1.82, 2.14, Curves.linear);
    return SizedBox(
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: _intro,
        builder: (context, _) {
          final seconds = _intro.value * 2.5;
          final grow = word.value;
          final topShift = 1 - split.value;
          // Centered on the word and play, not on the artwork's box.
          return Transform.translate(
            offset: Offset(-155 * unit, 9 * unit) + _shake(shake.value) * px,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TunnelPainter(
                      seconds: seconds,
                      px: px,
                      center: Offset(2475 - 150, 531 + 110) * unit,
                    ),
                  ),
                ),
                if (seconds >= 1)
                  Opacity(
                    opacity: grow.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.2 + 0.8 * grow,
                      alignment: const FractionalOffset(0.4466, 0.5046),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipPath(
                            clipper: _Cut(unit, top: false),
                            child: layer('word'),
                          ),
                          Transform.translate(
                            offset: Offset(
                              60 - 60 * topShift,
                              -30 + 30 * topShift,
                            ) * unit,
                            child: ClipPath(
                              clipper: _Cut(unit, top: true),
                              child: layer('word'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TrailPainter(
                      progress: seconds >= 1.55 ? trail.value : -1,
                      pop: seconds >= 1.9 ? pop.value : -1,
                      unit: unit,
                    ),
                  ),
                ),
                if (seconds >= 1.55)
                  Transform.translate(
                    offset: Offset(-4300, 205) * unit * (1 - shot.value),
                    child: layer('tri'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The mockup's shake, in its screen pixels, at [t] of the way through.
  static Offset _shake(double t) {
    if (t <= 0 || t >= 1) return Offset.zero;
    const keys = [
      (0.0, Offset.zero),
      (0.15, Offset(-16, 10)),
      (0.3, Offset(14, -12)),
      (0.45, Offset(-10, -6)),
      (0.6, Offset(8, 8)),
      (0.8, Offset(-4, 3)),
      (1.0, Offset.zero),
    ];
    for (var i = 1; i < keys.length; i++) {
      if (t <= keys[i].$1) {
        final a = keys[i - 1];
        final b = keys[i];
        return Offset.lerp(a.$2, b.$2, (t - a.$1) / (b.$1 - a.$1))!;
      }
    }
    return Offset.zero;
  }
}

/// One half of the word: above or below the slash that cuts it.
class _Cut extends CustomClipper<Path> {
  final double unit;
  final bool top;

  const _Cut(this.unit, {required this.top});

  Offset _p(double x, double y) => Offset((x - 150) * unit, (y + 110) * unit);

  @override
  Path getClip(Size size) {
    final points = top
        ? [_p(-100, -300), _p(5000, -300), _p(5000, 417), _p(-100, 660)]
        : [_p(-100, 660), _p(5000, 417), _p(5000, 1400), _p(-100, 1400)];
    return Path()..addPolygon(points, true);
  }

  @override
  bool shouldReclip(_Cut oldClipper) =>
      oldClipper.unit != unit || oldClipper.top != top;
}

/// Play outlines flying at the camera, red and faint white in turn.
class _TunnelPainter extends CustomPainter {
  final double seconds;
  final double px;
  final Offset center;

  const _TunnelPainter({
    required this.seconds,
    required this.px,
    required this.center,
  });

  static const _curve = Cubic(0.6, 0, 0.9, 0.5);

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..moveTo(-36, -44)
      ..lineTo(-36, 44)
      ..lineTo(46, 0)
      ..close();
    for (var i = 0; i < 8; i++) {
      final t = seconds - i * 0.1;
      if (t <= 0 || t >= 1) continue;
      final opacity = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85;
      final scale = 0.05 + (16 - 0.05) * _curve.transform(t);
      final white = i.isOdd;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(scale * px);
      canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = white ? 3 : 7
          ..color = (white ? Colors.white : const Color(0xFFE71414))
              .withValues(alpha: opacity * (white ? 0.35 : 1)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TunnelPainter oldDelegate) =>
      oldDelegate.seconds != seconds || oldDelegate.px != px;
}

/// The white trail the play leaves through the word, and the ring where it
/// stops. A negative value means not started yet.
class _TrailPainter extends CustomPainter {
  final double progress;
  final double pop;
  final double unit;

  const _TrailPainter({
    required this.progress,
    required this.pop,
    required this.unit,
  });

  Offset _p(double x, double y) => Offset((x - 150) * unit, (y + 110) * unit);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 0 && progress < 1) {
      final reach = (progress / 0.45).clamp(0.0, 1.0);
      final fade = progress < 0.45 ? 1.0 : 1 - (progress - 0.45) / 0.55;
      final from = _p(120, 652);
      final to = Offset.lerp(from, _p(4380, 449), reach)!;
      canvas.drawLine(
        from,
        to,
        Paint()
          ..strokeWidth = 16 * unit
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: fade),
      );
    }
    if (pop >= 0 && pop < 1) {
      final scale = 0.2 + 2.8 * pop;
      canvas.drawCircle(
        _p(4600, 440),
        70 * unit * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14 * unit * scale
          ..color = Colors.white.withValues(alpha: 1 - pop),
      );
    }
  }

  @override
  bool shouldRepaint(_TrailPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.pop != pop ||
      oldDelegate.unit != unit;
}
