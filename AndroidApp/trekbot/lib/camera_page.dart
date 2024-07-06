import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_vision/google_ml_vision.dart';
import 'voice_agent.dart';
import 'package:permission_handler/permission_handler.dart';

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
    _requestPermissions();
  }

  void _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.camera,
    ].request();

    if (statuses[Permission.microphone] != PermissionStatus.granted ||
        statuses[Permission.camera] != PermissionStatus.granted) {
      print("Permission denied");
      _showPermissionDialog();
      return;
    }
    startCamera();
    _initVoiceService();
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Permissions Required"),
          content: Text(
              "This app needs camera, microphone, and storage permissions to function properly. Please grant them in your device settings."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: Text("Open Settings"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  void _initVoiceService() {
    _voiceService =
        VoiceService(onListeningStatusChanged: _handleListeningStatusChanged);
    _voiceService.onCommand = (command) {
      if (command == 'capture') {
        print("Capture photo command received");
      }
    };
  }

  void _handleListeningStatusChanged(bool isListening) {
    print("Listening status changed: $isListening");
  }

  void startCamera() async {
    CameraDescription selectedCamera = widget.cameras[isFrontCamera ? 1 : 0];
    cameraController = CameraController(
      selectedCamera,
      ResolutionPreset.high,
    );
    try {
      cameraValue = cameraController.initialize();
      await cameraValue;
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
    } catch (e) {
      print("Error initializing camera: $e");
    }
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

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (cameraController == null || !cameraController.value.isInitialized) {
      return Container();
    }
    return Scaffold(
      body: Stack(
        children: [
          FutureBuilder<void>(
            future: cameraValue,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                // If camera initialization is complete, show CameraPreview
                return CameraPreview(cameraController);
              } else if (snapshot.hasError) {
                // If there's an error during initialization, handle it
                return Center(
                  child: Text('Error: ${snapshot.error}'),
                );
              } else {
                // While waiting for initialization, show a progress indicator
                return Center(
                  child: CircularProgressIndicator(),
                );
              }
            },
          ),
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
