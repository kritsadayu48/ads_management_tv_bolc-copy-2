import 'package:ads_management_tv/models/advertisement.dart';

abstract class AdEvent {}

class InitializeAd extends AdEvent {
  final String deviceId;
  InitializeAd(this.deviceId);
  
  @override
  String toString() => 'InitializeAd(deviceId: $deviceId)';
}

class FetchAdvertisements extends AdEvent {
  @override
  String toString() => 'FetchAdvertisements()';
}

class PlayNextAd extends AdEvent {
  @override
  String toString() => 'PlayNextAd()';
}

class PreloadVideos extends AdEvent {
  final List<Advertisement> advertisements;
  PreloadVideos(this.advertisements);
  
  @override
  String toString() => 'PreloadVideos(${advertisements.length} ads)';
}

class VideoInitialized extends AdEvent {
  final Advertisement ad;
  VideoInitialized(this.ad);
  
  @override
  String toString() => 'VideoInitialized(${ad.id})';
}

class VideoCompleted extends AdEvent {
  @override
  String toString() => 'VideoCompleted()';
}

class SkipToNext extends AdEvent {
  @override
  String toString() => 'SkipToNext()';
}

class HandleError extends AdEvent {
  final String error;
  HandleError(this.error);
  
  @override
  String toString() => 'HandleError($error)';
}
