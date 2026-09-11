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

      // PHASE 1:
      // Application now starts with Login Page
      home: LoginPage(
        cameras: cameras,
      ),
    );
  }
}

// ============================================================
// LOGIN PAGE
// ============================================================

class LoginPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const LoginPage({
    super.key,
    required this.cameras,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

// ============================================================
// LOGIN STATE
// ============================================================

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  String _message = '';

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ==========================================================
  // LOGIN
  // ==========================================================

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _message = 'Please enter username and password.';
      });

      return;
    }

    setState(() {
      _loading = true;
      _message = 'Logging in...';
    });

    try {
      final uri = Uri.parse(
        '$backendUrl/login',
      );

      debugPrint(
        'Sending login request to: $uri',
      );

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      debugPrint(
        'Login status code: ${response.statusCode}',
      );

      debugPrint(
        'Login response: ${response.body}',
      );

      Map<String, dynamic> data = {};

      if (response.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);

          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (e) {
          debugPrint(
            'Login JSON parsing error: $e',
          );
        }
      }

      if (!mounted) return;

      // ========================================================
      // LOGIN SUCCESS
      // ========================================================

      if (response.statusCode == 200 &&
          data['success'] == true) {
        final user = data['user'] is Map
            ? Map<String, dynamic>.from(
                data['user'],
              )
            : <String, dynamic>{};

        final role = user['role']?.toString().toLowerCase();
        final userId = user['id'];
        final loggedUsername =
            user['username']?.toString() ?? username;

        setState(() {
          _loading = false;
          _message = 'Login successful.';
        });

        // ======================================================
        // STUDENT
        // ======================================================

        if (role == 'student') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AttendancePage(
                cameras: widget.cameras,
                username: loggedUsername,
              ),
            ),
          );

          return;
        }

        // ======================================================
        // FACULTY
        // ======================================================

        if (role == 'faculty') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => FacultyDashboard(
                cameras: widget.cameras,
                userId: userId,
                username: loggedUsername,
              ),
            ),
          );

          return;
        }

        // ======================================================
        // ADMIN
        // ======================================================

        if (role == 'admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AdminDashboard(
                cameras: widget.cameras,
                userId: userId,
                username: loggedUsername,
              ),
            ),
          );

          return;
        }

        // ======================================================
        // UNKNOWN ROLE
        // ======================================================

        setState(() {
          _message = 'Unknown user role: $role';
        });

        return;
      }

      // ========================================================
      // LOGIN FAILED
      // ========================================================

      String message = '';

      if (data['message'] != null) {
        message = data['message'].toString();
      } else if (data['error'] != null) {
        message = data['error'].toString();
      }

      if (message.isEmpty) {
        message =
            'Login failed. HTTP Status: ${response.statusCode}';
      }

      setState(() {
        _loading = false;
        _message = message;
      });
    } catch (e) {
      if (!mounted) return;

      debugPrint(
        'LOGIN CONNECTION ERROR',
      );

      debugPrint(
        e.toString(),
      );

      setState(() {
        _loading = false;
        _message =
            'Could not connect to backend.\n\n'
            'Make sure Flask is running and '
            'the phone is connected to the same Wi-Fi network.';
      });
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
          'AntiProxy Login',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                // ------------------------------------------------
                // APP TITLE
                // ------------------------------------------------

                const Icon(
                  Icons.security,
                  size: 80,
                ),

                const SizedBox(
                  height: 16,
                ),

                const Text(
                  'AntiProxy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                const Text(
                  'Smart Attendance System',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                  ),
                ),

                const SizedBox(
                  height: 40,
                ),

                // ------------------------------------------------
                // USERNAME
                // ------------------------------------------------

                TextField(
                  controller: _usernameController,
                  enabled: !_loading,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'Enter username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(
                      Icons.person,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),

                // ------------------------------------------------
                // PASSWORD
                // ------------------------------------------------

                TextField(
                  controller: _passwordController,
                  enabled: !_loading,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(
                      Icons.lock,
                    ),
                    suffixIcon: IconButton(
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _obscurePassword =
                                    !_obscurePassword;
                              });
                            },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 20,
                ),

                // ------------------------------------------------
                // MESSAGE
                // ------------------------------------------------

                if (_message.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(
                      bottom: 16,
                    ),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(8),
                      color: Colors.grey.withValues(
                        alpha: 0.12,
                      ),
                    ),
                    child: Text(
                      _message,
                      textAlign: TextAlign.center,
                    ),
                  ),

                // ------------------------------------------------
                // LOGIN BUTTON
                // ------------------------------------------------

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'LOGIN',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(
                  height: 24,
                ),

                const Text(
                  'Login access is controlled by user role.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FACULTY DASHBOARD
// ============================================================

class FacultyDashboard extends StatelessWidget {
  final List<CameraDescription> cameras;
  final dynamic userId;
  final String username;

  const FacultyDashboard({
    super.key,
    required this.cameras,
    required this.userId,
    required this.username,
  });

  // ==========================================================
  // LOGOUT
  // ==========================================================

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LoginPage(
          cameras: cameras,
        ),
      ),
      (route) => false,
    );
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Faculty Dashboard',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              _logout(context);
            },
            icon: const Icon(
              Icons.logout,
            ),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.school,
                size: 80,
              ),

              const SizedBox(
                height: 20,
              ),

              const Text(
                'Welcome Faculty',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 10,
              ),

              Text(
                'Username: $username',
                textAlign: TextAlign.center,
              ),

              const SizedBox(
                height: 40,
              ),

              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_available,
                        size: 50,
                      ),
                      SizedBox(
                        height: 12,
                      ),
                      Text(
                        'Faculty Module',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      SizedBox(
                        height: 8,
                      ),
                      Text(
                        'Session creation, QR attendance '
                        'and attendance monitoring will '
                        'be connected in the next phase.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              ElevatedButton.icon(
                onPressed: () {
                  _logout(context);
                },
                icon: const Icon(
                  Icons.logout,
                ),
                label: const Text(
                  'LOGOUT',
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
// ADMIN DASHBOARD
// ============================================================

class AdminDashboard extends StatelessWidget {
  final List<CameraDescription> cameras;
  final dynamic userId;
  final String username;

  const AdminDashboard({
    super.key,
    required this.cameras,
    required this.userId,
    required this.username,
  });

  // ==========================================================
  // LOGOUT
  // ==========================================================

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LoginPage(
          cameras: cameras,
        ),
      ),
      (route) => false,
    );
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              _logout(context);
            },
            icon: const Icon(
              Icons.logout,
            ),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.admin_panel_settings,
                size: 80,
              ),

              const SizedBox(
                height: 20,
              ),

              const Text(
                'Welcome Admin',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 10,
              ),

              Text(
                'Username: $username',
                textAlign: TextAlign.center,
              ),

              const SizedBox(
                height: 40,
              ),

              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.dashboard,
                        size: 50,
                      ),
                      SizedBox(
                        height: 12,
                      ),
                      Text(
                        'Admin Module',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      SizedBox(
                        height: 8,
                      ),
                      Text(
                        'User management, student management, '
                        'reports and system administration '
                        'will be connected in the next phase.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              ElevatedButton.icon(
                onPressed: () {
                  _logout(context);
                },
                icon: const Icon(
                  Icons.logout,
                ),
                label: const Text(
                  'LOGOUT',
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
// ATTENDANCE PAGE
// ============================================================

class AttendancePage extends StatefulWidget {
  final List<CameraDescription> cameras;

  // Logged-in username
  final String username;

  const AttendancePage({
    super.key,
    required this.cameras,
    this.username = '',
  });

  @override
  State<AttendancePage> createState() =>
      _AttendancePageState();
}

// ============================================================
// STATE
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
        actions: [
          IconButton(
            onPressed: _processing
                ? null
                : () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LoginPage(
                          cameras: widget.cameras,
                        ),
                      ),
                      (route) => false,
                    );
                  },
            icon: const Icon(
              Icons.logout,
            ),
            tooltip: 'Logout',
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
              // ------------------------------------------------
              // LOGGED-IN USER
              // ------------------------------------------------

              if (widget.username.isNotEmpty)
                Text(
                  'Logged in as: ${widget.username}',
                  textAlign:
                      TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                  ),
                ),

              const SizedBox(
                height: 8,
              ),

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