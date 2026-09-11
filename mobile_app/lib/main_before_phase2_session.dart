import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

// ============================================================
// BACKEND CONFIGURATION
// ============================================================

const String backendUrl = 'http://10.160.194.207:5000';

// ============================================================
// PROGRAM START
// ============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = [];

  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera initialization error: $e');
  }

  runApp(
    AntiProxyApp(cameras: cameras),
  );
}

// ============================================================
// APP
// ============================================================

class AntiProxyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const AntiProxyApp({
    super.key,
    required this.cameras,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AntiProxy Smart Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: AttendancePage(
        cameras: cameras,
      ),
    );
  }
}

// ============================================================
// ATTENDANCE PAGE
// ============================================================

class AttendancePage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AttendancePage({
    super.key,
    required this.cameras,
  });

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

// ============================================================
// STATE
// ============================================================

class _AttendancePageState extends State<AttendancePage> {
  final TextEditingController _usnController =
      TextEditingController();

  XFile? _capturedImage;

  CameraController? _cameraController;

  bool _cameraReady = false;
  bool _processing = false;

  String _statusMessage =
      'Enter your USN and capture your face.';

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _usnController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ==========================================================
  // CAMERA INITIALIZATION
  // ==========================================================

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      if (!mounted) return;

      setState(() {
        _statusMessage =
            'No camera was found on this device.';
      });

      return;
    }

    CameraDescription selectedCamera =
        widget.cameras.first;

    for (final camera in widget.cameras) {
      if (camera.lensDirection ==
          CameraLensDirection.front) {
        selectedCamera = camera;
        break;
      }
    }

    final controller = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraReady = true;
        _statusMessage =
            'Camera ready. Capture your face.';
      });
    } catch (e) {
      await controller.dispose();

      if (!mounted) return;

      setState(() {
        _cameraReady = false;
        _statusMessage =
            'Could not initialize camera:\n$e';
      });
    }
  }

  // ==========================================================
  // CAPTURE FACE
  // ==========================================================

  Future<void> _captureFace() async {
    if (_cameraController == null ||
        !_cameraReady ||
        !_cameraController!.value.isInitialized) {
      setState(() {
        _statusMessage =
            'Camera is not ready.';
      });

      return;
    }

    if (_processing) {
      return;
    }

    try {
      final image =
          await _cameraController!.takePicture();

      if (!mounted) return;

      setState(() {
        _capturedImage = image;
        _statusMessage =
            'Face captured successfully. '
            'Press Mark Attendance.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _statusMessage =
            'Could not capture face:\n$e';
      });
    }
  }

  // ==========================================================
  // GET GPS LOCATION
  // ==========================================================

  Future<Position?> _getLocation() async {
    try {
      bool serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return null;

        setState(() {
          _statusMessage =
              'Location services are disabled. '
              'Please enable GPS.';
        });

        return null;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission ==
              LocationPermission.denied ||
          permission ==
              LocationPermission.deniedForever) {
        if (!mounted) return null;

        setState(() {
          _statusMessage =
              'Location permission is required.';
        });

        return null;
      }

      final position =
          await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      return position;
    } catch (e) {
      if (!mounted) return null;

      setState(() {
        _statusMessage =
            'Could not get GPS location:\n$e';
      });

      return null;
    }
  }

  // ==========================================================
  // MARK ATTENDANCE
  // ==========================================================

  Future<void> _markAttendance() async {
    if (_capturedImage == null) {
      setState(() {
        _statusMessage =
            'Please capture your face first.';
      });
      return;
    }

    final usn =
        _usnController.text.trim();

    if (usn.isEmpty) {
      setState(() {
        _statusMessage =
            'Please enter your USN.';
      });
      return;
    }

    setState(() {
      _processing = true;
      _statusMessage =
          'Verifying face and location...';
    });

    try {
      // ========================================================
      // GET GPS
      // ========================================================

      final position =
          await _getLocation();

      if (position == null) {
        if (mounted) {
          setState(() {
            _processing = false;
          });
        }

        return;
      }

      debugPrint(
        '======================================',
      );
      debugPrint(
        'ANTIPROXY ATTENDANCE REQUEST',
      );
      debugPrint(
        'USN: $usn',
      );
      debugPrint(
        'Latitude: ${position.latitude}',
      );
      debugPrint(
        'Longitude: ${position.longitude}',
      );
      debugPrint(
        'Accuracy: ${position.accuracy}',
      );
      debugPrint(
        '======================================',
      );

      // ========================================================
      // CREATE REQUEST
      // ========================================================

      final uri = Uri.parse(
        '$backendUrl/attendance/mark',
      );

      final request =
          http.MultipartRequest(
        'POST',
        uri,
      );

      request.fields['usn'] =
          usn;

      request.fields['latitude'] =
          position.latitude.toString();

      request.fields['longitude'] =
          position.longitude.toString();

      request.fields['accuracy'] =
          position.accuracy.toString();

      // ========================================================
      // ADD FACE IMAGE
      // ========================================================

      request.files.add(
        await http.MultipartFile.fromPath(
          'face',
          _capturedImage!.path,
        ),
      );

      if (!mounted) return;

      setState(() {
        _statusMessage =
            'Sending data to AntiProxy server...';
      });

      debugPrint(
        'Sending request to: $uri',
      );

      // ========================================================
      // SEND REQUEST
      // ========================================================

      final streamedResponse =
          await request.send();

      final response =
          await http.Response.fromStream(
        streamedResponse,
      );

      debugPrint(
        '======================================',
      );
      debugPrint(
        'SERVER RESPONSE',
      );
      debugPrint(
        'Status Code: ${response.statusCode}',
      );
      debugPrint(
        'Response Body: ${response.body}',
      );
      debugPrint(
        '======================================',
      );

      // ========================================================
      // PARSE RESPONSE
      // ========================================================

      Map<String, dynamic> data = {};

      if (response.body.isNotEmpty) {
        try {
          final decoded =
              jsonDecode(response.body);

          if (decoded
              is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (e) {
          debugPrint(
            'JSON parsing error: $e',
          );
        }
      }

      if (!mounted) return;

      // ========================================================
      // SUCCESS
      // ========================================================

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        final student =
            data['student'] is Map
                ? Map<String, dynamic>.from(
                    data['student'],
                  )
                : null;

        final face =
            data['face'] is Map
                ? Map<String, dynamic>.from(
                    data['face'],
                  )
                : null;

        final location =
            data['location'] is Map
                ? Map<String, dynamic>.from(
                    data['location'],
                  )
                : null;

        final name =
            student?['name']?.toString() ??
            usn;

        final similarity =
            face?['similarity']?.toString() ??
            '-';

        final distance =
            location?['distance']?.toString() ??
            '-';

        setState(() {
          _processing = false;
          _statusMessage =
              'ATTENDANCE MARKED SUCCESSFULLY';
        });

        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text(
              'Attendance Successful',
            ),
            content: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Name: $name',
                ),
                Text(
                  'USN: $usn',
                ),
                const SizedBox(
                  height: 10,
                ),
                const Text(
                  'Face verified: YES',
                ),
                Text(
                  'Face similarity: $similarity',
                ),
                Text(
                  'Campus distance: $distance m',
                ),
                const SizedBox(
                  height: 10,
                ),
                const Text(
                  'Status: PRESENT',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                  );
                },
                child:
                    const Text('OK'),
              ),
            ],
          ),
        );

        return;
      }

      // ========================================================
      // SERVER REJECTED
      // ========================================================

      String message = '';

      if (data['message'] != null) {
        message =
            data['message'].toString();
      } else if (data['error'] != null) {
        message =
            data['error'].toString();
      } else if (data['reason'] != null) {
        message =
            data['reason'].toString();
      } else if (response.body.isNotEmpty) {
        message =
            response.body;
      }

      if (message.isEmpty) {
        message =
            'Server rejected the request.\n'
            'HTTP Status: ${response.statusCode}';
      }

      setState(() {
        _processing = false;
        _statusMessage = message;
      });

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(
            'Attendance Rejected',
          ),
          content:
              SingleChildScrollView(
            child: Text(
              'Reason:\n\n$message\n\n'
              'HTTP Status: '
              '${response.statusCode}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                );
              },
              child:
                  const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      debugPrint(
        '======================================',
      );
      debugPrint(
        'ANTIPROXY CONNECTION ERROR',
      );
      debugPrint(
        e.toString(),
      );
      debugPrint(
        '======================================',
      );

      setState(() {
        _processing = false;
        _statusMessage =
            'Could not connect to backend:\n$e';
      });

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(
            'Connection Error',
          ),
          content:
              SingleChildScrollView(
            child: Text(
              'Could not connect to the '
              'AntiProxy server.\n\n'
              'Backend:\n'
              '$backendUrl\n\n'
              'Make sure Flask is running '
              'and the phone is connected '
              'to the same Wi-Fi network.\n\n'
              'Error:\n$e',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                );
              },
              child:
                  const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AntiProxy Attendance',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              // ------------------------------------------------
              // TITLE
              // ------------------------------------------------

              const Text(
                'Smart Attendance',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 6,
              ),

              const Text(
                'Face + GPS Verification',
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(
                height: 20,
              ),

              // ------------------------------------------------
              // USN
              // ------------------------------------------------

              TextField(
                controller:
                    _usnController,
                enabled: !_processing,
                textCapitalization:
                    TextCapitalization.characters,
                decoration:
                    const InputDecoration(
                  labelText: 'USN',
                  hintText:
                      'Enter student USN',
                  border:
                      OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.badge),
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              // ------------------------------------------------
              // CAMERA
              // ------------------------------------------------

              Container(
                height: 320,
                decoration:
                    BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                  color: Colors.black,
                ),
                clipBehavior:
                    Clip.antiAlias,
                child: _capturedImage !=
                        null
                    ? Image.file(
                        File(
                          _capturedImage!
                              .path,
                        ),
                        fit: BoxFit.cover,
                      )
                    : _cameraReady &&
                            _cameraController !=
                                null
                        ? CameraPreview(
                            _cameraController!,
                          )
                        : const Center(
                            child:
                                CircularProgressIndicator(),
                          ),
              ),

              const SizedBox(
                height: 12,
              ),

              // ------------------------------------------------
              // CAPTURE BUTTON
              // ------------------------------------------------

              ElevatedButton.icon(
                onPressed:
                    _processing
                        ? null
                        : _captureFace,
                icon: const Icon(
                  Icons.camera_alt,
                ),
                label: Text(
                  _capturedImage ==
                          null
                      ? 'Capture Face'
                      : 'Capture Again',
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              // ------------------------------------------------
              // STATUS
              // ------------------------------------------------

              Container(
                padding:
                    const EdgeInsets.all(
                  12,
                ),
                decoration:
                    BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(
                    8,
                  ),
                  color: Colors.grey
                      .withValues(
                    alpha: 0.12,
                  ),
                ),
                child: Text(
                  _statusMessage,
                  textAlign:
                      TextAlign.center,
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              // ------------------------------------------------
              // MARK ATTENDANCE
              // ------------------------------------------------

              SizedBox(
                height: 52,
                child:
                    ElevatedButton(
                  onPressed:
                      _processing
                          ? null
                          : _markAttendance,
                  child: _processing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'MARK ATTENDANCE',
                          style:
                              TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              const Text(
                'Attendance requires a registered face '
                'and valid campus GPS location.',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
