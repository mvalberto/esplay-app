import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../ui/screens/setup/setup_wizard_gate.dart';

/// EsPlay's own requests and reports, kept by the panel. The panel knows who
/// is asking from the app's Emby session: its token, this device's id and the
/// server it belongs to.
const _base = 'https://panel.esplay.es/api/app/solicitudes';

const esplayReportCategories = ['audio', 'imagen', 'subtitulos', 'calidad'];

class EsplayRequestException implements Exception {
  EsplayRequestException(this.code, [this.data = const {}]);

  /// The panel's error code, or `sin_conexion` when it could not be reached.
  final String code;
  final Map<String, dynamic> data;

  @override
  String toString() => 'EsplayRequestException($code)';
}

class EsplayRequestsApi {
  EsplayRequestsApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final Dio _dio;

  Map<String, String> _headers() {
    final client = SetupWizardGate.activeClient();
    final device = GetIt.instance.isRegistered<DeviceInfo>()
        ? GetIt.instance<DeviceInfo>().id
        : '';
    return {
      'X-Emby-Token': client?.accessToken ?? '',
      'X-Emby-Device-Id': device,
      'X-Emby-Server': client?.baseUrl ?? '',
    };
  }

  Future<Map<String, dynamic>> _call(String path, [Object? body]) async {
    try {
      final response = body == null
          ? await _dio.get<Object>(
              '$_base$path',
              options: Options(headers: _headers()),
            )
          : await _dio.post<Object>(
              '$_base$path',
              data: body,
              options: Options(headers: _headers()),
            );
      final data = response.data;
      return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] is String) {
        throw EsplayRequestException(
          data['error'] as String,
          data.cast<String, dynamic>(),
        );
      }
      throw EsplayRequestException(
        e.response == null ? 'sin_conexion' : 'http_${e.response!.statusCode}',
      );
    }
  }

  Future<Map<String, dynamic>> search(String query) =>
      _call('/buscar?q=${Uri.encodeQueryComponent(query)}');

  Future<Map<String, dynamic>> title(String mediaType, int tmdbId) =>
      _call('/detalle/$mediaType/$tmdbId');

  Future<Map<String, dynamic>> request(
    String mediaType,
    int tmdbId, {
    bool acceptRisk = false,
  }) => _call('/solicitar', {
    'media_type': mediaType,
    'tmdb_id': tmdbId,
    'acepta_riesgo': acceptRisk,
  });

  Future<Map<String, dynamic>> report(
    String embyItemId,
    String category,
    String note,
  ) => _call('/reportar', {
    'emby_item_id': embyItemId,
    'category': category,
    'note': note,
  });

  Future<Map<String, dynamic>> mine() => _call('/mis');
}
