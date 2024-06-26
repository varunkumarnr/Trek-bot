import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_vision/google_ml_vision.dart';
import 'voice_agent.dart';

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
  List<Face> faces = [];
  Timer? processingTimer;
  Timer? noFaceTimer;
  List<List<Offset>> previousPositions = [];
  bool wasFacesEmpty = true;
  bool isFrontCamera = false;
  late VoiceService _voiceService;

  @override
  void initState() {
    super.initState();
    startCamera();
    _voiceService = VoiceService();
    _voiceService.onCommand = (command) {
      if (command == 'capture photo') {
        print("captured");
      }
    };
  }

  void startCamera() async {
    CameraDescription selectedCamera = widget.cameras[isFrontCamera ? 1 : 0];
    cameraController = CameraController(
      selectedCamera,
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
          processingTimer?.cancel();
          processingTimer =
              Timer(Duration(seconds: 1), () => processCameraImage(image));
        }
      });
    });
  }

  void switchCamera() {
    setState(() {
      isFrontCamera = !isFrontCamera;
      cameraController.dispose(); // Dispose of current controller
      startCamera(); // Restart camera with new selected camera
    });
  }

  void processCameraImage(CameraImage image) async {
    try {
      final CameraDescription description =
          widget.cameras[isFrontCamera ? 1 : 0];
      int sensorOrientation = description.sensorOrientation;

      // Determine the rotation dynamically based on sensor orientation
      // ImageRotation rotation = _rotationIntToImageRotation(sensorOrientation);
      final GoogleVisionImage visionImage = GoogleVisionImage.fromBytes(
        image.planes[0].bytes,
        GoogleVisionImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: ImageRotation.rotation0,
          rawFormat: image.format.raw,
          planeData: image.planes.map(
            (Plane plane) {
              return GoogleVisionImagePlaneMetadata(
                bytesPerRow: plane.bytesPerRow,
                height: plane.height,
                width: plane.width,
              );
            },
          ).toList(),
        ),
      );

      final FaceDetector faceDetector = GoogleVision.instance.faceDetector();
      final List<Face> detectedFaces =
          await faceDetector.processImage(visionImage);

      setState(() {
        faces = detectedFaces;
        print("Detected ${faces.length} faces");

        List<Offset> currentFacePositions =
            faces.map((face) => face.boundingBox.center).toList();
        previousPositions.add(currentFacePositions);

        // Check for transition from detecting faces to not detecting any faces
        if (!wasFacesEmpty && faces.isEmpty) {
          detectDirection(previousPositions);
        }

        // Update wasFacesEmpty for the next frame
        wasFacesEmpty = faces.isEmpty;
      });
    } catch (e) {
      print("Error processing camera image: $e");
    } finally {
      isDetecting = false;
    }
  }

  void detectDirection(List<List<Offset>> previousPositions) {
    // Find the last non-empty list of offsets in previousPositions
    List<Offset> lastPositions = [];
    for (int i = previousPositions.length - 1; i >= 0; i--) {
      if (previousPositions[i].isNotEmpty) {
        lastPositions = previousPositions[i];
        break;
      }
    }

    // Your existing logic to calculate direction based on lastPositions
    double previewWidth = cameraController.value.previewSize!.width;
    double previewHeight = cameraController.value.previewSize!.height;
    Offset previewCenter = Offset(previewWidth / 2, previewHeight / 2);

    // Calculate distances from each face position to the edges of the preview area
    double minDistanceTop = double.infinity;
    double minDistanceBottom = double.infinity;
    double minDistanceLeft = double.infinity;
    double minDistanceRight = double.infinity;

    for (Offset pos in lastPositions) {
      double distanceTop = pos.dy;
      double distanceBottom = previewHeight - pos.dy;
      double distanceLeft = pos.dx;
      double distanceRight = previewWidth - pos.dx;

      if (distanceTop < minDistanceTop) {
        minDistanceTop = distanceTop;
      }
      if (distanceBottom < minDistanceBottom) {
        minDistanceBottom = distanceBottom;
      }
      if (distanceLeft < minDistanceLeft) {
        minDistanceLeft = distanceLeft;
      }
      if (distanceRight < minDistanceRight) {
        minDistanceRight = distanceRight;
      }
    }

    // Determine the closest edges for both vertical and horizontal movements
    String directionVertical;
    if (minDistanceTop <= minDistanceBottom) {
      directionVertical = "up";
    } else {
      directionVertical = "down";
    }

    String directionHorizontal;
    if (minDistanceLeft <= minDistanceRight) {
      directionHorizontal = "right";
    } else {
      directionHorizontal = "left";
    }

    // Combine vertical and horizontal directions
    String direction = "$directionVertical-$directionHorizontal";

    int facesCount =
        lastPositions.length; // Number of faces detected in the last frame
    String message = "Detected ${facesCount} faces. User moved ${direction}.";
    print(message);
  }

  // ImageRotation _rotationIntToImageRotation(int rotation) {
  //   switch (rotation) {
  //     case 0:
  //       return ImageRotation.rotation0;
  //     case 90:
  //       return ImageRotation.rotation90;
  //     case 180:
  //       return ImageRotation.rotation180;
  //     case 270:
  //       return ImageRotation.rotation270;
  //     default:
  //       throw Exception("Unknown rotation $rotation");
  //   }
  // }

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
        ],
      ),
      floatingActionButton: Container(
        width: 70.0, // Set the width of the button
        height: 70.0, // Set the height of the button
        margin: EdgeInsets.only(bottom: 30, right: 20),
        child: FittedBox(
          child: FloatingActionButton(
            onPressed: switchCamera,
            backgroundColor: Colors.blue,
            child: Icon(
              isFrontCamera ? Icons.camera_rear : Icons.camera_front,
              size: 24.0, // Adjust the icon size if needed
            ),
          ),
        ),
      ),
    );
  }
}
