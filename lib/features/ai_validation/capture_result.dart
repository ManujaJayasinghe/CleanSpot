import 'dart:typed_data';

/// Why a capture did not produce a usable photo and location.
enum CaptureFailure {
  /// The user closed the camera without taking a photo.
  cancelled,
  cameraFailed,
  notJpeg,
  locationServicesOff,
  locationPermissionDenied,
  locationPermissionDeniedForever,
  locationTimeout,
  locationUnavailable,
  lowAccuracy,
}

/// A live camera photo together with the GPS fix taken when it was captured,
/// or the reason the capture failed.
///
/// A successful result always has a JPEG photo and a GPS fix that is accurate
/// to within [maxAccuracyMeters]; callers do not need to re-check the GPS.
class CaptureResult {
  const CaptureResult.success({
    required Uint8List this.jpegBytes,
    required double this.latitude,
    required double this.longitude,
    required double this.accuracyMeters,
  })  : failure = null,
        message = null;

  /// [message] is short, user-friendly text that can be shown as-is.
  const CaptureResult.failure(CaptureFailure this.failure, String this.message)
      : jpegBytes = null,
        latitude = null,
        longitude = null,
        accuracyMeters = null;

  /// The GPS fix must be at least this accurate (smaller is better).
  static const double maxAccuracyMeters = 50;

  final Uint8List? jpegBytes;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final CaptureFailure? failure;
  final String? message;

  bool get isOk => failure == null;

  /// True when the user simply closed the camera (not an error to show).
  bool get wasCancelled => failure == CaptureFailure.cancelled;
}

/// Whether a GPS accuracy reading (metres) is good enough to accept.
bool isAccuracyAcceptable(double accuracyMeters) =>
    accuracyMeters >= 0 && accuracyMeters <= CaptureResult.maxAccuracyMeters;

/// Whether [bytes] start with the JPEG signature (FF D8 FF).
bool looksLikeJpeg(Uint8List bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xFF &&
    bytes[1] == 0xD8 &&
    bytes[2] == 0xFF;
