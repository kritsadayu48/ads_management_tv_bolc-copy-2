import 'package:video_player/video_player.dart';

class Advertisement {
  final String id;
  final String type; // 'image' or 'video'
  final String content; // URL to the content
  final int durationSeconds;
  final String? title;
  final DateTime? startTime; // Start time if scheduled
  final DateTime? endTime; // End time if scheduled
  final String orientation; // 'horizontal' or 'vertical'
  
  Advertisement({
    required this.id,
    required this.type,
    required this.content,
    required this.durationSeconds,
    this.title,
    this.startTime,
    this.endTime,
    this.orientation = 'horizontal', // Default to horizontal
  });
  
  // Create from JSON
  factory Advertisement.fromJson(Map<String, dynamic> json) {
    // Parse the start and end dates if present
    DateTime? startTime;
    DateTime? endTime;
    
    if (json['start_date'] != null || json['start_time'] != null) {
      try {
        String? dateString = json['start_date']?.toString() ?? json['start_time']?.toString();
        if (dateString != null && dateString.isNotEmpty) {
          startTime = DateTime.parse(dateString);
        }
      } catch (e) {
        print('📺 TV - Error parsing start date: ${json['start_date'] ?? json['start_time']}');
      }
    }
    
    if (json['end_date'] != null || json['end_time'] != null) {
      try {
        String? dateString = json['end_date']?.toString() ?? json['end_time']?.toString();
        if (dateString != null && dateString.isNotEmpty) {
          endTime = DateTime.parse(dateString);
        }
      } catch (e) {
        print('📺 TV - Error parsing end date: ${json['end_date'] ?? json['end_time']}');
      }
    }
    
    // Determine if the content is image or video
    String type = json['type'] ?? 'image';
    
    if (type.isEmpty && json['url'] != null) {
      // If no type specified, try to determine from URL extension
      final url = json['url'].toString().toLowerCase();
      if (url.endsWith('.mp4') || url.endsWith('.mov') || 
          url.endsWith('.avi') || url.endsWith('.webm')) {
        type = 'video';  
      } else {
        type = 'image';
      }
    }
    
    // Parse duration, default to 10 seconds for images, 30 for videos
    int duration = 0;
    if (json['duration'] != null) {
      try {
        duration = int.parse(json['duration'].toString());
      } catch (e) {
        // Use default
      }
    }
    
    if (duration <= 0) {
      duration = type == 'video' ? 30 : 10;
    }
    
    // สร้าง ID กรณีที่ไม่มี ID ส่งมา
    String id = json['id']?.toString() ?? '';
    if (id.isEmpty) {
      // ใช้ URL ในการสร้าง ID
      final url = json['url']?.toString() ?? '';
      if (url.isNotEmpty) {
        // ตัดเฉพาะส่วนท้ายของ URL หลังเครื่องหมาย / ตัวสุดท้าย
        id = url.split('/').last;
        print('📺 TV - สร้าง ID จาก URL: $id');
      } else {
        // ถ้าไม่มี URL ให้ใช้เวลาปัจจุบัน
        id = DateTime.now().millisecondsSinceEpoch.toString();
        print('📺 TV - สร้าง ID จากเวลา: $id');
      }
    }
    
    // ตรวจสอบค่า orientation ทั้ง orientation และ play_orientation
    String orientation = 'horizontal';
    if (json['orientation'] != null && json['orientation'].toString().isNotEmpty) {
      orientation = json['orientation'].toString().toLowerCase();
    } else if (json['play_orientation'] != null && json['play_orientation'].toString().isNotEmpty) {
      orientation = json['play_orientation'].toString().toLowerCase();
    }
    
    return Advertisement(
      id: id,
      type: type,
      content: json['url']?.toString() ?? '',
      durationSeconds: duration,
      title: json['title']?.toString(),
      startTime: startTime,
      endTime: endTime,
      orientation: orientation,
    );
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Advertisement &&
        other.id == id &&
        other.content == content &&
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(id, content, type);
  
  @override
  String toString() {
    String timeRange = '';
    if (startTime != null || endTime != null) {
      timeRange = 'Schedule: ${startTime?.toString() ?? 'Any'} to ${endTime?.toString() ?? 'Any'}';
    }
    
    return 'Ad($id, $type, Orientation: $orientation, Duration: ${durationSeconds}s, $timeRange)';
  }
}
