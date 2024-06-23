import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:trekbot/face_detection_service.dart';

class MainPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MainPage({Key? key, required this.cameras}) : super(key: key);

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late CameraController cameraController;
  late Future<void> cameraValue;
  bool isDetecting = false;

  void startCamera() async {
    cameraController = CameraController(
      widget.cameras[0], // Assuming using the first camera
      ResolutionPreset.high,
    );
    cameraValue = cameraController.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});

      cameraController.startImageStream((CameraImage image) {
        if (!isDetecting) {
          isDetecting = true;
          processCameraImage(image);
        }
      });
    });
  }

  void processCameraImage(CameraImage image) async {
    try {
      final Uint8List imageBytes = _concatenatePlanes(image.planes);
      final bool facesDetected =
          await FaceDetectionService.detectFaces(imageBytes);

      if (facesDetected) {
        // Handle the case where faces are detected
        print("Faces detected!");
        // Implement further logic as needed, e.g., drawing boxes around faces
      } else {
        // Handle the case where no faces are detected
        print("No faces detected.");
      }
    } catch (e) {
      print("Error processing camera image: $e");
    } finally {
      isDetecting = false;
    }
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final List<Uint8List> planesList = planes.map((Plane plane) {
      return plane.bytes;
    }).toList();

    final Uint8List concatenatedImage =
        Uint8List(planes.fold(0, (prev, el) => prev + el.bytes.length));

    int offset = 0;
    for (Uint8List plane in planesList) {
      concatenatedImage.setRange(offset, offset + plane.lengthInBytes, plane);
      offset += plane.lengthInBytes;
    }

    return concatenatedImage;
  }

  @override
  void initState() {
    super.initState();
    startCamera();
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
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
          // Add UI components like buttons or overlays here
        ],
      ),
    );
  }
}
