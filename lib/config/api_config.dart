import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  // Android emulator loopback.
  static const String emulatorBaseUrl = 'http://10.0.2.2:5001';

  // Laptop Wi-Fi IPv4 from ipconfig for real phone testing on the same network.
  static const String phoneBaseUrl = 'http://10.6.192.57:5001';

  // نفس الجهاز (اختبار الويب على نفس اللابتوب اللي شغّال عليه السيرفر).
  static const String webBaseUrl = 'http://127.0.0.1:5001';

  // على الويب نستخدم localhost تلقائياً (المتصفح وين ما كان مو على نفس
  // شبكة واي فاي الجوال بالضرورة)، وعلى الجوال/الديسكتوب نستخدم IP
  // اللابتوب. غيّري لـ emulatorBaseUrl وقت اختبار محاكي أندرويد.
  static const String baseUrl = kIsWeb ? webBaseUrl : phoneBaseUrl;
}
