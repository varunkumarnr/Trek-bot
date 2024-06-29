import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:trekbot/face_detection_service.dart';
import 'package:image/image.dart' as img;

class MainPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MainPage({Key? key, required this.cameras}) : super(key: key);

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late CameraController cameraController;
  bool _isDetecting = false;
  List<Map<String, int>> faces = [];

  @override
  void initState() {
    super.initState();

    // Initialize the camera controller with the first camera
    cameraController = CameraController(
      widget.cameras[0], // Assuming using the first camera
      ResolutionPreset.medium,
      enableAudio: false,
    );

    // Initialize the camera controller asynchronously
    cameraController.initialize().then((_) {
      if (!mounted) {
        return;
      }

      // Once initialized, update the state to rebuild the widget
      setState(() {});

      // Start streaming images from the camera
      cameraController.startImageStream((CameraImage availableImage) {
        _processCameraImage(availableImage);
      });
    }).catchError((error) {
      print('Error initializing camera: $error');
    });
  }

  @override
  void dispose() {
    // Dispose of the camera controller when no longer needed
    cameraController.stopImageStream();
    cameraController.dispose();
    super.dispose();
  }

  void _processCameraImage(CameraImage availableImage) async {
    if (_isDetecting) return;
    _isDetecting = true;

    // Convert the CameraImage to a JPEG byte array
    final jpegBytes = await _convertYUV420ToImage(availableImage);

    // Call face detection service
    final detectedFaces = await FaceDetectionService.detectFaces(jpegBytes);

    setState(() {
      faces = detectedFaces;
      print("Detected ${faces.length} faces");
    });

    _isDetecting = false;
  }

  Future<Uint8List> _convertYUV420ToImage(CameraImage image) async {
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    // Create an empty buffer for RGB image
    img.Image rgbImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex =
            uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
        final int index = y * width + x;

        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];

        // Apply YUV to RGB conversion
        int r = (yp + (vp - 128) * 1.402).round();
        int g = (yp - (up - 128) * 0.34414 - (vp - 128) * 0.71414).round();
        int b = (yp + (up - 128) * 1.772).round();

        // Clamp values to the 0-255 range
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        rgbImage.setPixel(x, y, rgbImage.getColor(r, g, b));
      }
    }

    // Encode RGB image to JPEG
    Uint8List jpegBytes = Uint8List.fromList(img.encodeJpg(rgbImage));
    return jpegBytes;
  }

  @override
  Widget build(BuildContext context) {
    if (!cameraController.value.isInitialized) {
      return Container();
    }
    return Scaffold(
      body: Stack(
        children: <Widget>[
          CameraPreview(cameraController),
          CustomPaint(
            painter: FacePainter(faces),
          ),
        ],
      ),
    );
  }
}

class FacePainter extends CustomPainter {
  final List<Map<String, int>> faces;
  FacePainter(this.faces);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var face in faces) {
      final rect = Rect.fromLTWH(
        face['x']!.toDouble(),
        face['y']!.toDouble(),
        face['width']!.toDouble(),
        face['height']!.toDouble(),
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
