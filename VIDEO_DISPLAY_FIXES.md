# การแก้ไขปัญหาสีและการแสดงผลเต็มจอของวิดีโอ

## ปัญหาที่พบ
1. **สีของวิดีโอไม่ตรง** - วิดีโอแสดงผลสีที่ผิดเพี้ยนหรือไม่ตรงกับต้นฉบับ
2. **ภาพไม่เต็มจอ** - วิดีโอไม่แสดงผลเต็มจอหรือมีขอบดำรอบๆ

## การแก้ไขที่ทำ

### 1. ปรับปรุง AndroidManifest.xml
- เพิ่ม `android:hardwareAccelerated="true"` ใน application level
- เพิ่ม `android:screenOrientation="landscape"` เพื่อบังคับแนวนอน
- ลบ `android:colorMode="wideColorGamut"` ที่อาจทำให้สีผิดเพี้ยน

### 2. ปรับปรุง styles.xml
- เปลี่ยนจาก `Theme.Light.NoTitleBar` เป็น `Theme.Black.NoTitleBar.Fullscreen`
- เพิ่มการตั้งค่าเต็มจอ:
  - `android:windowFullscreen="true"`
  - `android:windowNoTitle="true"`
  - `android:windowActionBar="false"`
  - `android:windowContentOverlay="@null"`
- ตั้งพื้นหลังเป็นสีดำ `@android:color/black`

### 3. ปรับปรุงการแสดงผลวิดีโอใน home_screen.dart
- เปลี่ยนจาก `AspectRatio` เป็น `FittedBox` พร้อม `BoxFit.cover`
- ใช้ `SizedBox` กับขนาดจริงของวิดีโอ
- เพิ่มการตั้งค่า SystemChrome สำหรับเต็มจอ:
  - `SystemUiMode.immersiveSticky`
  - บังคับแนวนอน `DeviceOrientation.landscape`

### 4. ปรับปรุง VideoPlayerController ใน ad_controller.dart
- เปลี่ยนจาก `VideoPlayerController.network` เป็น `VideoPlayerController.networkUrl`
- เพิ่ม HTTP headers ที่เหมาะสม:
  - `User-Agent: Flutter/TV Player`
  - `Accept: video/mp4,video/*;q=0.9,*/*;q=0.8`
- ปรับปรุง VideoPlayerOptions สำหรับ TV

### 5. เพิ่มการตั้งค่าเต็มจอใน Flutter
```dart
// ตั้งค่าเต็มจอและซ่อน system UI
SystemChrome.setEnabledSystemUIMode(
  SystemUiMode.immersiveSticky,
  overlays: [],
);

// บังคับให้แสดงผลแนวนอน
SystemChrome.setPreferredOrientations([
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
]);
```

### 6. ปรับปรุงการแสดงผลวิดีโอ
```dart
// ใช้ FittedBox เพื่อให้วิดีโอเต็มจอและรักษาอัตราส่วนที่ถูกต้อง
return Container(
  color: Colors.black,
  width: double.infinity,
  height: double.infinity,
  child: FittedBox(
    fit: BoxFit.cover, // ใช้ cover เพื่อให้เต็มจอ
    child: SizedBox(
      width: _adController.videoController!.value.size.width,
      height: _adController.videoController!.value.size.height,
      child: VideoPlayer(_adController.videoController!),
    ),
  ),
);
```

## ผลลัพธ์ที่คาดหวัง
1. **สีที่ถูกต้อง** - วิดีโอจะแสดงสีที่ตรงกับต้นฉบับ
2. **เต็มจอ** - วิดีโอจะแสดงผลเต็มจอโดยไม่มีขอบดำ
3. **อัตราส่วนที่ถูกต้อง** - วิดีโอจะรักษาอัตราส่วนที่ถูกต้องแต่ครอบคลุมพื้นที่ทั้งหมด
4. **ประสิทธิภาพที่ดีขึ้น** - การใช้ hardware acceleration จะทำให้การเล่นวิดีโอลื่นขึ้น

## การทดสอบ
1. รันแอปบนอุปกรณ์ Android TV
2. ตรวจสอบการแสดงผลวิดีโอที่มีสีต่างๆ
3. ตรวจสอบการแสดงผลเต็มจอ
4. ทดสอบกับวิดีโอที่มีอัตราส่วนต่างๆ (16:9, 4:3, ฯลฯ)

## หมายเหตุ
- การเปลี่ยนแปลงเหล่านี้เฉพาะสำหรับแอป TV เท่านั้น
- ไม่ส่งผลกระทบต่อแอปมือถือ
- หากยังมีปัญหาสี อาจต้องตรวจสอบการตั้งค่าของอุปกรณ์ TV เพิ่มเติม 