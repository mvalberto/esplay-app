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
  // EsPlay: the logo builds itself, the play rolls in and the button grows
  // from it. The app moves on only once it has finished.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _introLength,
  );
  final Future<void> _introDone = Future.delayed(_introLength);

  static const _introLength = Duration(milliseconds: 2100);
  static const _logoWidth = 180.0;
  // From the logo artwork (C:\esplay\brand\gen.js): its shape and where its
  // parts sit, as fractions of its width and height.
  static const _logoAspect = 4.0366;
  static const _pillLeft = 0.2364;
  static const _pillRight = 1.0;
  static const _triCenter = FractionalOffset(0.8355, 0.5);
  static const _logoUnit = 0.003539;

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
    _intro.forward().whenCompleteOrCancel(() {
      if (mounted) _fadeController.forward();
    });
    _initialize();
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
              padding: const EdgeInsets.only(top: 90),
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

  Widget _buildLogoIntro() {
    const height = _logoWidth / _logoAspect;
    const unit = _logoUnit * _logoWidth;
    Widget layer(String name) => SvgPicture.asset(
          'assets/images/esplay_logo_$name.svg',
          width: _logoWidth,
          height: height,
        );
    // The same timings as the mockup, as parts of the 2.1 s run.
    final roll = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.43, curve: Cubic(0.2, 0.8, 0.2, 1)),
    );
    final grow = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.405, 0.69, curve: Cubic(0.65, 0, 0.35, 1)),
    );
    final playIn = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.62, 0.76, curve: Curves.easeOut),
    );
    final esIn = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.74, 0.98, curve: Cubic(0.2, 0.8, 0.2, 1)),
    );
    return SizedBox(
      width: _logoWidth,
      height: height,
      child: AnimatedBuilder(
        animation: _intro,
        builder: (context, _) {
          final hidden = (1 - grow.value) * 0.7 * (_pillRight - _pillLeft);
          return Stack(
            children: [
              ClipRect(
                clipper: _FromLeft((_pillLeft + hidden) * _logoWidth),
                child: layer('pill'),
              ),
              Opacity(opacity: playIn.value, child: layer('play')),
              Opacity(
                opacity: (_intro.value / 0.086).clamp(0.0, 1.0),
                child: Transform(
                  alignment: _triCenter,
                  transform: Matrix4.translationValues(
                    -260 * unit * (1 - roll.value),
                    0,
                    0,
                  )..rotateZ(-2 * math.pi * (1 - roll.value)),
                  child: layer('tri'),
                ),
              ),
              Opacity(
                opacity: esIn.value,
                child: Transform.translate(
                  offset: Offset(-30 * unit * (1 - esIn.value), 0),
                  child: layer('es'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shows everything right of [left].
class _FromLeft extends CustomClipper<Rect> {
  final double left;

  const _FromLeft(this.left);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(left, 0, size.width, size.height);

  @override
  bool shouldReclip(_FromLeft oldClipper) => oldClipper.left != left;
}
