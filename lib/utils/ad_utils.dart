import 'package:video_player/video_player.dart';

class AdUtils {
  static String cleanVideoUrl(String url) {
    if (url.contains('https://cloud.softacular.nethttps://')) {
      return url.replaceFirst('https://cloud.softacular.nethttps://', 'https://');
    }
    if (url.contains('http://cloud.softacular.nethttps://')) {
      return url.replaceFirst('http://cloud.softacular.nethttps://', 'https://');
    }
    return url;
  }

  static bool isPortraitAspectRatio(double aspectRatio) {
    return aspectRatio < 1.0;
  }

  static Duration getVideoDuration(VideoPlayerController? controller, int fallbackSeconds) {
    if (controller?.value.isInitialized == true) {
      final duration = controller!.value.duration;
      if (duration.inSeconds > 0) {
        return duration;
      }
    }
    return Duration(seconds: fallbackSeconds);
  }

  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
