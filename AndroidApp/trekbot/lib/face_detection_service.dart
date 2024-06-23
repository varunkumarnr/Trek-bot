import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class FaceDetectionService {
  static const MethodChannel _channel = MethodChannel('face_detection_plugin');

  static Future<bool> detectFaces(Uint8List imageBytes) async {
    try {
      final bool facesDetected =
          await _channel.invokeMethod('detectFaces', imageBytes);
      return facesDetected;
    } on PlatformException catch (e) {
      print("Error detecting faces: ${e.message}");
      return false;
    }
  }
}
