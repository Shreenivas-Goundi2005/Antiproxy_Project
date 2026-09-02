import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cameras = await availableCameras();

  runApp(AntiProxyApp(cameras: cameras));
}

class AntiProxyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const AntiProxyApp({
    super.key,
    required this.cameras,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AntiProxy Smart Attendance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F669D),
        ),
        useMaterial3: true,
      ),
      home: RegisterStudentPage(cameras: cameras),
    );
  }
}

// -----------------------------------------------------------------------------
// REGISTER STUDENT
// -----------------------------------------------------------------------------

class RegisterStudentPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const RegisterStudentPage({
    super.key,
    required this.cameras,
  });

  @override
  State<RegisterStudentPage> createState() => _RegisterStudentPageState();
}

class _RegisterStudentPageState extends State<RegisterStudentPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();

  String department = 'CSE — Computer Science and Engineering';
  String semester = 'Semester 7';

  @override
  void dispose() {
    _nameController.dispose();
    _studentIdController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _createAccount() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceRegistrationPage(
          cameras: widget.cameras,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Student'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create your student account',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'You will register your face after creating the account.',
                style: TextStyle(fontSize: 16),
              ),

              const SizedBox(height: 30),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter your full name';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              TextFormField(
                controller: _studentIdController,
                decoration: const InputDecoration(
                  labelText: 'USN / Student ID',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter your student ID';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Password must contain at least 6 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || !value.contains('@')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              DropdownButtonFormField<String>(
                initialValue: department,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'CSE — Computer Science and Engineering',
                    child: Text(
                      'CSE — Computer Science and Engineering',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'ISE — Information Science and Engineering',
                    child: Text(
                      'ISE — Information Science and Engineering',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'ECE — Electronics and Communication Engineering',
                    child: Text(
                      'ECE — Electronics and Communication Engineering',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'EEE — Electrical and Electronics Engineering',
                    child: Text(
                      'EEE — Electrical and Electronics Engineering',
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      department = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 18),

              DropdownButtonFormField<String>(
                initialValue: semester,
                decoration: const InputDecoration(
                  labelText: 'Semester',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  8,
                  (index) => DropdownMenuItem(
                    value: 'Semester ${index + 1}',
                    child: Text('Semester ${index + 1}'),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      semester = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _createAccount,
                  child: const Text(
                    'Create Student Account',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// FACE REGISTRATION INTRO
// -----------------------------------------------------------------------------

class FaceRegistrationPage extends StatelessWidget {
  final List<CameraDescription> cameras;

  const FaceRegistrationPage({
    super.key,
    required this.cameras,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Registration'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.face,
                size: 100,
              ),

              const SizedBox(height: 24),

              const Text(
                'Register Your Face',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Position your face inside the camera frame '
                'and capture your face for attendance registration.',
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: cameras.isEmpty
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FaceCapturePage(
                                cameras: cameras,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text(
                    'Start Face Registration',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),

              if (cameras.isEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'No camera was detected on this device.',
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// REAL CAMERA FACE CAPTURE
// -----------------------------------------------------------------------------

class FaceCapturePage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceCapturePage({
    super.key,
    required this.cameras,
  });

  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage> {
  CameraController? _controller;

  bool _isInitializing = true;
  bool _isCapturing = false;

  XFile? _capturedImage;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      CameraDescription selectedCamera;

      // Prefer the front camera for face registration.
      final frontCameras = widget.cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );

      if (frontCameras.isNotEmpty) {
        selectedCamera = frontCameras.first;
      } else {
        selectedCamera = widget.cameras.first;
      }

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _controller = controller;

      await controller.initialize();

      if (!mounted) {
        return;
      }

      setState(() {
        _isInitializing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isInitializing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to start camera: $error',
          ),
        ),
      );
    }
  }

  Future<void> _captureFace() async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final image = await controller.takePicture();

      if (!mounted) {
        return;
      }

      setState(() {
        _capturedImage = image;
        _isCapturing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isCapturing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to capture face: $error',
          ),
        ),
      );
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedImage = null;
    });
  }

  void _confirmPhoto() {
    if (_capturedImage == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Face photo captured and ready for registration.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Face'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              'Starting camera...',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_capturedImage != null) {
      return _buildCapturedImage();
    }

    if (_controller == null ||
        !_controller!.value.isInitialized) {
      return _buildCameraError();
    }

    return _buildCameraPreview();
  }

  Widget _buildCameraPreview() {
    final controller = _controller!;

    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Position your face inside the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Look directly at the camera and keep your face visible.',
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(controller),

                    // Face guide.
                    Center(
                      child: Container(
                        width: 250,
                        height: 320,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white,
                            width: 4,
                          ),
                          borderRadius: BorderRadius.circular(140),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton.icon(
                onPressed: _isCapturing ? null : _captureFace,
                icon: _isCapturing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(
                  _isCapturing
                      ? 'Capturing...'
                      : 'Capture Face',
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapturedImage() {
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 70,
                ),
                SizedBox(height: 10),
                Text(
                  'Face Photo Captured',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Review the photo before confirming.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.file(
                  File(_capturedImage!.path),
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _retakePhoto,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retake'),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _confirmPhoto,
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.no_photography,
              size: 80,
            ),

            const SizedBox(height: 20),

            const Text(
              'Camera unavailable',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'AntiProxy could not start the phone camera.',
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isInitializing = true;
                });

                _initializeCamera();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}