import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:tts_mod_vault/src/state/enums/download_error_type_enum.dart';

class DownloadErrorClassifier {
  static DownloadErrorTypeEnum classifyError(dynamic error) {
    if (error is DioException) {
      // Permanent errors
      if (error.response?.statusCode != null) {
        final statusCode = error.response!.statusCode!;

        // Client errors (4xx) are generally permanent
        if (statusCode == 403) {
          return DownloadErrorTypeEnum.permanent; // Forbidden
        }
        if (statusCode == 404) {
          return DownloadErrorTypeEnum.permanent; // Not Found
        }
        if (statusCode == 410) {
          return DownloadErrorTypeEnum.permanent; // Gone
        }
        if (statusCode >= 400 && statusCode < 500) {
          return DownloadErrorTypeEnum.permanent; // Other client errors
        }

        // Server errors (5xx) are generally temporary
        if (statusCode >= 500 && statusCode < 600) {
          return DownloadErrorTypeEnum.temporary;
        }
      }

      // Network-related errors are temporary
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return DownloadErrorTypeEnum.temporary;

        case DioExceptionType.badResponse:
          // Already handled above by status code
          return DownloadErrorTypeEnum.permanent;

        case DioExceptionType.cancel:
          // Cancellation shouldn't be stored as failure
          return DownloadErrorTypeEnum.unknown;

        default:
          return DownloadErrorTypeEnum.unknown;
      }
    }

    // Generic errors default to unknown
    return DownloadErrorTypeEnum.unknown;
  }

  static String getErrorMessage(dynamic error) {
    if (error is DioException) {
      if (error.response?.statusCode != null) {
        return 'HTTP ${error.response!.statusCode}: ${error.response!.statusMessage ?? "Unknown error"}';
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return 'Connection timeout';
        case DioExceptionType.sendTimeout:
          return 'Send timeout';
        case DioExceptionType.receiveTimeout:
          return 'Receive timeout';
        case DioExceptionType.connectionError:
          return 'Connection error';
        case DioExceptionType.cancel:
          return 'Download cancelled';
        default:
          return error.message ?? 'Unknown error';
      }
    }

    return error.toString();
  }
}
