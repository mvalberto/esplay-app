import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

/// EsPlay's transparent sign-in: the panel finds which Emby server a username
/// and password belong to, and the app then signs in against that server
/// itself. The panel never hands out a token.
const esplayPanelLoginUrl = 'https://panel.esplay.es/api/app/login';

/// The panel may hand back a server's internal address. Clients always go
/// through the public HTTPS name.
const _publicAddressByIp = {
  '194.164.172.201': 'https://ep01.esplay.es:8920',
  '5.250.191.4': 'https://ep02.esplay.es:8920',
};

String esplayPublicAddress(String address) {
  final host = Uri.tryParse(address)?.host;
  return _publicAddressByIp[host] ?? address;
}

/// Preference key holding the server that last signed [username] in, tried
/// first so a regular user gets in even while the panel is down.
String esplayServerCacheKey(String username) =>
    'esplay_server_${username.trim().toLowerCase()}';

sealed class EsPlayPanelResult {
  const EsPlayPanelResult();
}

class EsPlayPanelServer extends EsPlayPanelResult {
  final String address;
  const EsPlayPanelServer(this.address);
}

class EsPlayPanelInvalidCredentials extends EsPlayPanelResult {
  const EsPlayPanelInvalidCredentials();
}

class EsPlayPanelTooManyAttempts extends EsPlayPanelResult {
  const EsPlayPanelTooManyAttempts();
}

class EsPlayPanelOutdatedApp extends EsPlayPanelResult {
  final String message;
  const EsPlayPanelOutdatedApp(this.message);
}

/// The panel could not be reached or answered something unexpected.
class EsPlayPanelUnavailable extends EsPlayPanelResult {
  const EsPlayPanelUnavailable();
}

Future<EsPlayPanelResult> esplayPanelLogin(
  String username,
  String password,
) async {
  final device = GetIt.instance<DeviceInfo>();
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
      validateStatus: (_) => true,
    ),
  );
  try {
    final response = await dio.post<dynamic>(
      esplayPanelLoginUrl,
      data: {
        'username': username,
        'password': password,
        'appName': device.appName,
        'appVersion': device.appVersion,
      },
    );
    final data = response.data is Map ? response.data as Map : const {};
    switch (response.statusCode) {
      case 200:
        final address = data['address'];
        if (address is String && address.isNotEmpty) {
          return EsPlayPanelServer(esplayPublicAddress(address));
        }
        return const EsPlayPanelUnavailable();
      case 400:
      case 401:
        return const EsPlayPanelInvalidCredentials();
      case 426:
        return EsPlayPanelOutdatedApp(data['message'] as String? ?? '');
      case 429:
        return const EsPlayPanelTooManyAttempts();
      default:
        return const EsPlayPanelUnavailable();
    }
  } catch (_) {
    return const EsPlayPanelUnavailable();
  } finally {
    dio.close();
  }
}
