import 'package:ads_management_tv/models/advertisement.dart';
import 'package:video_player/video_player.dart';

abstract class AdState {}

class AdInitial extends AdState {
  @override
  String toString() => 'AdInitial()';
}

class AdLoading extends AdState {
  @override
  String toString() => 'AdLoading()';
}

class AdPreloading extends AdState {
  final double progress;
  final String status;
  
  AdPreloading({required this.progress, required this.status});
  
  @override
  String toString() => 'AdPreloading(progress: $progress, status: $status)';
}

class AdPlaying extends AdState {
  final Advertisement currentAd;
  // final bool isVideoReady;
  // final VideoPlayerController? videoController;
  // final int? textureId;
  
  AdPlaying({
    required this.currentAd,
    // this.isVideoReady = false,
    // this.videoController,
    // this.textureId,
  });
  
  // @override
  // String toString() => 'AdPlaying(ad: ${currentAd.id}, videoReady: $isVideoReady)';
}

class AdNoContent extends AdState {
  @override
  String toString() => 'AdNoContent()';
}

class AdError extends AdState {
  final String message;
  final bool isDeviceRevoked;
  
  AdError({required this.message, this.isDeviceRevoked = false});
  
  @override
  String toString() => 'AdError(message: $message, deviceRevoked: $isDeviceRevoked)';
}
