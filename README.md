# QR Code ลงทะเบียนอุปกรณ์

แอปพลิเคชันสำหรับสร้าง QR Code เพื่อลงทะเบียนอุปกรณ์สำหรับระบบ Ads Management

## คุณสมบัติ

- สร้าง Client ID ที่ไม่ซ้ำกันสำหรับแต่ละอุปกรณ์
- สร้าง QR Code จากข้อมูลอุปกรณ์ผ่าน API
- จดจำรหัสอุปกรณ์ไว้ในอุปกรณ์
- รองรับทั้ง Android และ iOS

## วิธีการติดตั้ง

1. โคลนโปรเจค
```
git clone https://github.com/yourusername/ads_management_mobile.git
```

2. ติดตั้ง dependencies
```
flutter pub get
```

3. รันแอปพลิเคชัน
```
flutter run
```

## วิธีการใช้งาน

1. เปิดแอปพลิเคชัน
2. ระบบจะสร้าง Client ID ที่ไม่ซ้ำกันโดยอัตโนมัติ
3. QR Code จะถูกสร้างขึ้นจาก API
4. สแกน QR Code ด้วยแอปพลิเคชันหลักเพื่อลงทะเบียนอุปกรณ์

## การทำงานของระบบ

แอปพลิเคชันจะสร้าง Client ID ที่ไม่ซ้ำกันจากข้อมูลเฉพาะของอุปกรณ์แต่ละเครื่อง เช่น:
- หมายเลขเครื่อง (Device ID)
- รุ่นอุปกรณ์
- ข้อมูลฮาร์ดแวร์
- เวลาที่ลงทะเบียน

Client ID จะถูกเข้ารหัสและจัดรูปแบบให้เป็นรหัสที่ใช้งานได้ง่าย เช่น `TV_ABCDEF123456_7890` และจะถูกส่งไปยัง API เพื่อสร้าง QR Code สำหรับการลงทะเบียน

## API Endpoint

```
POST https://advert.softacular.net/api/devices/generate-registration-qr
```

Body:
```json
{
  "client_id": "TV_ABCDEF123456_7890"
}
```

## การลงทะเบียนอุปกรณ์ทีวี

ระบบลงทะเบียนอุปกรณ์ทีวีใช้ QR Code ในการจับคู่ระหว่างอุปกรณ์ทีวีและอุปกรณ์มือถือ โดยมีขั้นตอนดังนี้:

1. อุปกรณ์ทีวีจะสร้าง client_id ที่เป็นเอกลักษณ์ของเครื่อง เช่น `TV_250513_GZI8MKAH`
2. ทีวีจะแสดง QR Code ที่มีข้อมูลเป็น client_id โดยตรง (ไม่มีการเข้ารหัสหรือแปลงรูปแบบ)
3. ผู้ใช้สแกน QR Code ผ่านแอปพลิเคชันมือถือเพื่อจับคู่กับอุปกรณ์ทีวี

### รูปแบบ Client ID

Client ID มีรูปแบบดังนี้:
```
TV_YYMMDD_XXXXXXXX
```

โดย:
- `TV_` คือ prefix ที่บ่งบอกว่าเป็น client_id ของอุปกรณ์ทีวี
- `YYMMDD` คือวันที่สร้าง client_id (ปี เดือน วัน)
- `XXXXXXXX` คือรหัสสุ่มที่สร้างขึ้นเพื่อความเป็นเอกลักษณ์

### การประกาศอุปกรณ์ (Device Announcement)

หลังจากสร้าง client_id แล้ว ทีวีจะส่งข้อมูลไปยัง API เพื่อประกาศตัวเองและรอการจับคู่:

```
POST https://advert.softacular.net/api/pairing/announce
```

Body:
```json
{
  "client_id": "TV_250513_GZI8MKAH"
}
```

### การตรวจสอบสถานะการจับคู่

ทีวีจะตรวจสอบสถานะการจับคู่เป็นระยะผ่าน API:

```
GET https://advert.softacular.net/api/pairing/status/{client_id}
```

### หมายเหตุการปรับปรุง

> **การเปลี่ยนแปลงล่าสุด**: ระบบได้รับการปรับปรุงให้ใช้ client_id โดยตรงเป็นข้อมูล QR Code แทนการใช้ API `/devices/generate-registration-qr` ซึ่งทำให้กระบวนการมีความเรียบง่ายและมีประสิทธิภาพมากขึ้น โดยไม่ต้องพึ่งพาการสร้าง QR Code จาก server
