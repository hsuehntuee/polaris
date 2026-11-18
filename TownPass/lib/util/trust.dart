import 'package:flutter/foundation.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';

/// 開發工具（WebView 遠端除錯、/sdcard 覆蓋資料夾、外部模型檔）：debug 版或 --dart-define=DEV_TOOLS=true 才開。
/// 給市民的 release 版一律關閉：網頁與模型只來自 APK 本身，別的程式看不到 WebView 內容。
const bool kDevTools = kDebugMode || bool.fromEnvironment('DEV_TOOLS', defaultValue: false);

/// 可以使用原生功能（語音、定位、使用者資料…）與定位權限的網頁：APK 內建的 http://townpass.local，
/// 或開發時用 DEV_SERVICE_URL 指定的那一台。其他網站（服務頁裡的外部連結、iframe）一律不行。
bool isTrustedOrigin(String? origin) {
  if (origin == null || origin.isEmpty) return false;
  final Uri? u = Uri.tryParse(origin);
  if (u == null || u.host.isEmpty) return false;
  if (u.scheme == 'http' && u.host == 'townpass.local') return true;
  bool same(String base) {
    final Uri? b = Uri.tryParse(base);
    return b != null && b.host.isNotEmpty && u.scheme == b.scheme && u.host == b.host && u.port == b.port;
  }
  // 開發時：服務頁那台（DEV_SERVICE_URL），以及另外指定的小幫手那台（ASSISTANT_URL）
  return same(kDevServiceUrl) || (kAssistantUrlOverride.isNotEmpty && same(kAssistantUrlOverride));
}

/// 跟 AssistantService 的 kAssistantUrl 同一個編譯參數（這裡另外讀，避免互相 import）
const String kAssistantUrlOverride = String.fromEnvironment('ASSISTANT_URL', defaultValue: '');
