class AdError extends Error {
  final String message;
  final String? code;
  
  AdError(this.message, {this.code});
  
  @override
  String toString() => 'AdError: $message${code != null ? ' (Code: $code)' : ''}';
}

class VideoInitializationError extends AdError {
  VideoInitializationError(String message) : super(message, code: 'VIDEO_INIT_ERROR');
}

class NetworkError extends AdError {
  NetworkError(String message) : super(message, code: 'NETWORK_ERROR');
}

class DeviceRevokedError extends AdError {
  DeviceRevokedError() : super('Device has been revoked', code: 'DEVICE_REVOKED');
}

class CacheError extends AdError {
  CacheError(String message) : super(message, code: 'CACHE_ERROR');
}