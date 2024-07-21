import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_vision/google_ml_vision.dart';
import 'voice_agent.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:external_path/external_path.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:audioplayers/audioplayers.dart';

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
  Timer? awayTimer;
  Timer? longAwayTimer;
  List<List<Offset>> previousPositions = [];
  bool wasFacesEmpty = true;
  bool isFrontCamera = false;
  late VoiceService _voiceService;
  List<File> imagesList = [];
  bool isListening = false;
  late AudioPlayer audioPlayer;
  bool isPersonInFrame = true;

  @override
  void initState() {
    super.initState();
    audioPlayer = AudioPlayer();
    _requestPermissions();
    _playStartupSound();
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
        takePicture();
      }
    };
  }

  void _handleListeningStatusChanged(bool isListening) {
    setState(() {
      this.isListening = isListening;
    });
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
      cameraController.dispose();
      startCamera();
    });
  }

  Future<File> saveImage(XFile image) async {
    final downloadPath = await ExternalPath.getExternalStoragePublicDirectory(
        ExternalPath.DIRECTORY_DOWNLOADS);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('$downloadPath/$fileName');

    try {
      await file.writeAsBytes(await image.readAsBytes());
    } catch (e) {
      print('Error saving image: $e');
    }

    return file;
  }

  void takePicture() async {
    XFile? image;
    if (cameraController.value.isTakingPicture ||
        !cameraController.value.isInitialized) {
      return;
    }
    try {
      image = await cameraController.takePicture();
    } catch (e) {
      print('Error taking picture: $e');
      return;
    }

    final file = await saveImage(image);
    setState(() {
      imagesList.add(file);
    });
    MediaScanner.loadMedia(path: file.path);
    _playCaptureSound();
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

        if (!wasFacesEmpty && faces.isEmpty) {
          isPersonInFrame = false;
          detectDirection(previousPositions);
          _startAwayTimers();
        } else if (wasFacesEmpty && faces.isNotEmpty) {
          _cancelAwayTimers();
          _playFoundSound();
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
    List<Offset> lastPositions = [];
    for (int i = previousPositions.length - 1; i >= 0; i--) {
      if (previousPositions[i].isNotEmpty) {
        lastPositions = previousPositions[i];
        break;
      }
    }

    double previewWidth = cameraController.value.previewSize!.width;
    double previewHeight = cameraController.value.previewSize!.height;
    Offset previewCenter = Offset(previewWidth / 2, previewHeight / 2);

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

    String directionVertical;
    if (minDistanceTop <= minDistanceBottom) {
      directionVertical = "up";
    } else {
      directionVertical = "down";
    }

    String directionHorizontal;
    if (minDistanceLeft <= minDistanceRight) {
      directionHorizontal = "right";
      _playAwayRecording();
    } else {
      directionHorizontal = "left";
      _playAwayRecording();
    }
    String direction = "$directionVertical-$directionHorizontal";

    int facesCount = lastPositions.length;
    String message = "Detected ${facesCount} faces. User moved ${direction}.";
    print(message);
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _playStartupSound() {
    audioPlayer.play(AssetSource('Sounds/Startup/startup.mp3'));
  }

  void _playCaptureSound() {
    var randomNumber = Random().nextInt(8) + 1;
    audioPlayer.play(AssetSource('Sounds/Photo/$randomNumber-Photo.mp3'));
  }

  void _playAwayRecording() {
    var randomNumber = Random().nextInt(8) + 1;
    audioPlayer.play(AssetSource('Sounds/Away/Away-$randomNumber.mp3'));
  }

  void _playFoundSound() {
    var randomNumber = Random().nextInt(4) + 1;
    audioPlayer.play(AssetSource("Sounds/Found/Found-$randomNumber.mp3"));
  }

  void _playLongAwaySound() {
    var randomNumber = Random().nextInt(2) + 1;
    audioPlayer.play(AssetSource("Sounds/Story/Story-$randomNumber.wav"));
  }

  void _cancelAwayTimers() {
    awayTimer?.cancel();
    longAwayTimer?.cancel();
  }

  void _startAwayTimers() {
    awayTimer?.cancel();
    longAwayTimer?.cancel();

    awayTimer = Timer(Duration(seconds: 30), () {
      _playAwayRecording();
    });

    longAwayTimer = Timer(Duration(minutes: 2), () {
      _playLongAwaySound();
    });
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
                return CameraPreview(cameraController);
              } else if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}'),
                );
              } else {
                return Center(
                  child: CircularProgressIndicator(),
                );
              }
            },
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 7, bottom: 75),
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: imagesList.length,
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (BuildContext context, int index) {
                          return Padding(
                            padding: const EdgeInsets.all(2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image(
                                height: 100,
                                width: 100,
                                opacity: const AlwaysStoppedAnimation(1.0),
                                image: FileImage(
                                  File(imagesList[index].path),
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        margin: EdgeInsets.only(bottom: 30, right: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              onPressed: switchCamera,
              backgroundColor: Colors.blue,
              child: Icon(
                isFrontCamera ? Icons.camera_rear : Icons.camera_front,
                size: 32.0,
              ),
            ),
            SizedBox(width: 40.0), // Spacing between buttons

            FloatingActionButton(
              onPressed: () {},
              backgroundColor: isListening ? Colors.green : Colors.red,
              child: Icon(
                Icons.mic,
                size: 32.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
