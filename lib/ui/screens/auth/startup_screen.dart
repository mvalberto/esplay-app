import 'package:flutter/material.dart';
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
    _fadeController.forward();
    _initialize();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _barController.dispose();
    super.dispose();
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
      if (mounted) context.go(Destinations.home);
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
      if (mounted) context.go(Destinations.home);
    } else {
      // EsPlay: username and password only, whatever server was used before.
      if (mounted) context.go(Destinations.esplayLogin);
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
    // EsPlay: the same black and wordmark, at the same size and spot, as the
    // Android launch splash, so the hand-over can't be seen. Below the logo a red
    // bar runs along its track, as on the TV app.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Image.asset(
              'assets/images/esplay_splash_wordmark.png',
              width: 180,
            ),
          ),
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
}
