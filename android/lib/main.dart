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

// Existing faculty test account
const int facultyUserId = 2;

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
      home: HomePage(
        cameras: cameras,
      ),
    );
  }
}

// ============================================================
// HOME PAGE
// ============================================================

class HomePage extends StatelessWidget {
  final List<CameraDescription> cameras;

  const HomePage({
    super.key,
    required this.cameras,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AntiProxy'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 30),

              const Icon(
                Icons.security,
                size: 80,
              ),

              const SizedBox(height: 20),

              const Text(
                'AntiProxy Smart Attendance',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Face + GPS + Session Based Attendance',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 40),

              // ------------------------------------------------
              // FACULTY DASHBOARD
              // ------------------------------------------------

              SizedBox(
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FacultyDashboard(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.dashboard),
                  label: const Text(
                    'FACULTY DASHBOARD',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------
              // STUDENT ATTENDANCE
              // ------------------------------------------------

              SizedBox(
                height: 60,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendancePage(
                          cameras: cameras,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.face),
                  label: const Text(
                    'STUDENT ATTENDANCE',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              const Text(
                'AntiProxy Attendance System',
                textAlign: TextAlign.center,
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

// ============================================================
// FACULTY DASHBOARD
// ============================================================

class FacultyDashboard extends StatefulWidget {
  const FacultyDashboard({
    super.key,
  });

  @override
  State<FacultyDashboard> createState() =>
      _FacultyDashboardState();
}

// ============================================================
// FACULTY DASHBOARD STATE
// ============================================================

class _FacultyDashboardState
    extends State<FacultyDashboard> {
  final TextEditingController _classController =
      TextEditingController(
    text: 'CSE 5A',
  );

  final TextEditingController _subjectController =
      TextEditingController(
    text: 'DBMS',
  );

  final TextEditingController _latitudeController =
      TextEditingController(
    text: '12.9716',
  );

  final TextEditingController _longitudeController =
      TextEditingController(
    text: '77.5946',
  );

  final TextEditingController _radiusController =
      TextEditingController(
    text: '100',
  );

  TimeOfDay _startTime = const TimeOfDay(
    hour: 15,
    minute: 0,
  );

  TimeOfDay _endTime = const TimeOfDay(
    hour: 16,
    minute: 0,
  );

  bool _processing = false;

  Map<String, dynamic>? _activeSession;

  String _statusMessage =
      'No active attendance session.';

  @override
  void dispose() {
    _classController.dispose();
    _subjectController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  // ==========================================================
  // FORMAT TIME
  // ==========================================================

  String _formatTime(TimeOfDay time) {
    final hour =
        time.hour.toString().padLeft(2, '0');

    final minute =
        time.minute.toString().padLeft(2, '0');

    return '$hour:$minute:00';
  }

  // ==========================================================
  // PICK START TIME
  // ==========================================================

  Future<void> _pickStartTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );

    if (selected != null) {
      setState(() {
        _startTime = selected;
      });
    }
  }

  // ==========================================================
  // PICK END TIME
  // ==========================================================

  Future<void> _pickEndTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );

    if (selected != null) {
      setState(() {
        _endTime = selected;
      });
    }
  }

  // ==========================================================
  // START SESSION
  // ==========================================================

  Future<void> _startSession() async {
    final className =
        _classController.text.trim();

    final subjectName =
        _subjectController.text.trim();

    if (className.isEmpty) {
      _showMessage('Please enter class name.');
      return;
    }

    if (subjectName.isEmpty) {
      _showMessage('Please enter subject name.');
      return;
    }

    final latitude =
        double.tryParse(
      _latitudeController.text.trim(),
    );

    final longitude =
        double.tryParse(
      _longitudeController.text.trim(),
    );

    final radius =
        int.tryParse(
      _radiusController.text.trim(),
    );

    if (latitude == null ||
        longitude == null ||
        radius == null) {
      _showMessage(
        'Please enter valid GPS values.',
      );
      return;
    }

    if (latitude < -90 || latitude > 90) {
      _showMessage('Invalid latitude.');
      return;
    }

    if (longitude < -180 || longitude > 180) {
      _showMessage('Invalid longitude.');
      return;
    }

    if (radius <= 0) {
      _showMessage(
        'Radius must be greater than 0.',
      );
      return;
    }

    setState(() {
      _processing = true;
      _statusMessage =
          'Starting attendance session...';
    });

    try {
      final now = DateTime.now();

      final date =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final uri = Uri.parse(
        '$backendUrl/sessions/start',
      );

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'faculty_user_id': facultyUserId,
          'class_name': className,
          'subject_name': subjectName,
          'attendance_date': date,
          'start_time': _formatTime(_startTime),
          'end_time': _formatTime(_endTime),
          'allowed_latitude': latitude,
          'allowed_longitude': longitude,
          'allowed_radius': radius,
        }),
      );

      debugPrint(
        'START SESSION STATUS: ${response.statusCode}',
      );

      debugPrint(
        'START SESSION RESPONSE: ${response.body}',
      );

      Map<String, dynamic> data = {};

      try {
        final decoded =
            jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      if (!mounted) return;

      if (response.statusCode == 201 &&
          data['success'] == true) {
        final session =
            data['session'] is Map
                ? Map<String, dynamic>.from(
                    data['session'],
                  )
                : null;

        setState(() {
          _activeSession = session;
          _processing = false;
          _statusMessage =
              'Attendance session is ACTIVE.';
        });

        _showSessionStarted();
      } else {
        final message =
            data['message']?.toString() ??
                'Could not start session.';

        setState(() {
          _processing = false;
          _statusMessage = message;
        });

        _showMessage(message);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _processing = false;
        _statusMessage =
            'Could not connect to backend:\n$e';
      });

      _showMessage(
        'Could not connect to AntiProxy backend.\n\n$e',
      );
    }
  }

  // ==========================================================
  // SESSION STARTED DIALOG
  // ==========================================================

  Future<void> _showSessionStarted() async {
    final session = _activeSession;

    if (session == null) return;

    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Attendance Session Started',
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Class: ${session['class_name']}',
                ),
                Text(
                  'Subject: ${session['subject_name']}',
                ),
                Text(
                  'Session ID: ${session['id']}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'QR Token:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  session['qr_token']?.toString() ??
                      '-',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // CLOSE SESSION
  // ==========================================================

  Future<void> _closeSession() async {
    if (_activeSession == null) {
      _showMessage(
        'There is no active session.',
      );
      return;
    }

    final sessionId =
        _activeSession!['id'];

    if (sessionId == null) {
      _showMessage(
        'Invalid session ID.',
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Close Attendance Session?',
          ),
          content: const Text(
            'Students will no longer be able '
            'to use this active session.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _processing = true;
      _statusMessage =
          'Closing attendance session...';
    });

    try {
      final uri = Uri.parse(
        '$backendUrl/sessions/$sessionId/close',
      );

      final response =
          await http.post(uri);

      debugPrint(
        'CLOSE SESSION STATUS: '
        '${response.statusCode}',
      );

      debugPrint(
        'CLOSE SESSION RESPONSE: '
        '${response.body}',
      );

      Map<String, dynamic> data = {};

      try {
        final decoded =
            jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      if (!mounted) return;

      if (response.statusCode == 200 &&
          data['success'] == true) {
        setState(() {
          _activeSession = null;
          _processing = false;
          _statusMessage =
              'Attendance session CLOSED.';
        });

        _showMessage(
          'Attendance session closed successfully.',
        );
      } else {
        final message =
            data['message']?.toString() ??
                'Could not close session.';

        setState(() {
          _processing = false;
          _statusMessage = message;
        });

        _showMessage(message);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _processing = false;
        _statusMessage =
            'Could not connect to backend:\n$e';
      });

      _showMessage(
        'Could not connect to backend.\n\n$e',
      );
    }
  }

  // ==========================================================
  // MESSAGE
  // ==========================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  // ==========================================================
  // BUILD DASHBOARD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final active =
        _activeSession != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Faculty Dashboard',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              // ------------------------------------------------
              // HEADER
              // ------------------------------------------------

              const Text(
                'Welcome, Test Faculty',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 4),

              const Text(
                'Faculty Attendance Control Panel',
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------
              // ACTIVE SESSION CARD
              // ------------------------------------------------

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            active
                                ? Icons.circle
                                : Icons.circle_outlined,
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            active
                                ? 'SESSION ACTIVE'
                                : 'NO ACTIVE SESSION',
                            style: const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Text(
                        _statusMessage,
                      ),

                      if (active) ...[
                        const SizedBox(height: 16),

                        Text(
                          'Class: '
                          '${_activeSession!['class_name']}',
                        ),

                        Text(
                          'Subject: '
                          '${_activeSession!['subject_name']}',
                        ),

                        Text(
                          'Session ID: '
                          '${_activeSession!['id']}',
                        ),

                        Text(
                          'Time: '
                          '${_activeSession!['start_time']}'
                          ' - '
                          '${_activeSession!['end_time']}',
                        ),

                        const SizedBox(height: 12),

                        const Text(
                          'QR TOKEN',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Container(
                          padding:
                              const EdgeInsets.all(10),
                          decoration:
                              BoxDecoration(
                            border: Border.all(
                              color: Theme.of(
                                context,
                              )
                                  .dividerColor,
                            ),
                            borderRadius:
                                BorderRadius.circular(
                              8,
                            ),
                          ),
                          child: SelectableText(
                            _activeSession![
                                      'qr_token']
                                    ?.toString() ??
                                '-',
                          ),
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed:
                                _processing
                                    ? null
                                    : _closeSession,
                            icon: const Icon(
                              Icons.stop_circle,
                            ),
                            label: const Text(
                              'CLOSE ATTENDANCE SESSION',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------
              // SESSION FORM
              // ------------------------------------------------

              if (!active) ...[
                const Text(
                  'Start New Attendance Session',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 14),

                TextField(
                  controller: _classController,
                  enabled: !_processing,
                  decoration:
                      const InputDecoration(
                    labelText: 'Class',
                    hintText: 'CSE 5A',
                    border:
                        OutlineInputBorder(),
                    prefixIcon:
                        Icon(Icons.class_),
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: _subjectController,
                  enabled: !_processing,
                  decoration:
                      const InputDecoration(
                    labelText: 'Subject',
                    hintText: 'DBMS',
                    border:
                        OutlineInputBorder(),
                    prefixIcon:
                        Icon(Icons.book),
                  ),
                ),

                const SizedBox(height: 16),

                // ------------------------------------------------
                // TIME
                // ------------------------------------------------

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _processing
                                ? null
                                : _pickStartTime,
                        icon: const Icon(
                          Icons.access_time,
                        ),
                        label: Text(
                          'Start\n'
                          '${_startTime.format(context)}',
                          textAlign:
                              TextAlign.center,
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _processing
                                ? null
                                : _pickEndTime,
                        icon: const Icon(
                          Icons.access_time_filled,
                        ),
                        label: Text(
                          'End\n'
                          '${_endTime.format(context)}',
                          textAlign:
                              TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                const Text(
                  'Campus Geofence',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller:
                      _latitudeController,
                  enabled: !_processing,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration:
                      const InputDecoration(
                    labelText: 'Allowed Latitude',
                    border:
                        OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller:
                      _longitudeController,
                  enabled: !_processing,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration:
                      const InputDecoration(
                    labelText: 'Allowed Longitude',
                    border:
                        OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller:
                      _radiusController,
                  enabled: !_processing,
                  keyboardType:
                      TextInputType.number,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Allowed Radius (meters)',
                    border:
                        OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed:
                        _processing
                            ? null
                            : _startSession,
                    icon: _processing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.play_circle,
                          ),
                    label: Text(
                      _processing
                          ? 'STARTING...'
                          : 'START ATTENDANCE SESSION',
                      style: const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ------------------------------------------------
              // STUDENT SCREEN
              // ------------------------------------------------

              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const StudentAttendancePlaceholder(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.face,
                ),
                label: const Text(
                  'OPEN STUDENT ATTENDANCE',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// STUDENT ATTENDANCE PLACEHOLDER
//
// The actual AttendancePage is defined below.
// This page simply makes it clear which screen is being opened.
// ============================================================

class StudentAttendancePlaceholder
    extends StatelessWidget {
  const StudentAttendancePlaceholder({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Student Attendance',
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.face,
                size: 70,
              ),
              const SizedBox(height: 20),
              const Text(
                'Student Attendance',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AttendancePage(
                        cameras:
                            _globalCameras,
                      ),
                    ),
                  );
                },
                child: const Text(
                  'CONTINUE TO ATTENDANCE',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// GLOBAL CAMERA LIST
// ============================================================

List<CameraDescription> _globalCameras = [];

// ============================================================
// ORIGINAL STUDENT ATTENDANCE PAGE
// ============================================================

class AttendancePage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AttendancePage({
    super.key,
    required this.cameras,
  });

  @override
  State<AttendancePage> createState() =>
      _AttendancePageState();
}

// ============================================================
// STUDENT ATTENDANCE STATE
// ============================================================

class _AttendancePageState
    extends State<AttendancePage> {
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

    _globalCameras = widget.cameras;

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
          'Student Attendance',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const Icon(
              Icons.home,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
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