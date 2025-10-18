import 'dart:async';
import 'package:flutter/foundation.dart';

class FeedBus {
  static final StreamController<void> _ctrl =
      StreamController<void>.broadcast();

  static Stream<void> get stream => _ctrl.stream;

  /// เรียกเมื่อโพสต์สำเร็จ เพื่อให้ Home รีโหลดฟีด
  static void notify() {
    debugPrint('[FeedBus] notify()');
    _ctrl.add(null);
  }

  /// (ไม่ต้องเรียกก็ได้) ปิดตอนปิดแอปจริงๆ
  static void dispose() {
    debugPrint('[FeedBus] dispose()');
    _ctrl.close();
  }
}
