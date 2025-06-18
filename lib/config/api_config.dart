class ApiConfig {
  static const String baseUrl = 'https://advert.softacular.net/api';
  
  // Timeout configurations
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  
  // Retry configurations
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  
  // Cache configurations
  static const Duration cacheTimeout = Duration(minutes: 15);
}