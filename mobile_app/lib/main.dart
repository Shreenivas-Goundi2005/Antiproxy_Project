import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

// ============================================================
// BACKEND CONFIGURATION
// ============================================================

const String backendUrl = 'http://10.160.194.207:5000';

// ============================================================
// MAIN
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

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  String? _selectedRole;
  String _message = '';

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

    if (_selectedRole == null) {
      setState(() {
        _message = 'Please select user type.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = 'Logging in...';
    });

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      Map<String, dynamic> data = {};

      if (response.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);

          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (_) {}
      }

      if (!mounted) return;

      if (response.statusCode == 200 &&
          data['success'] == true) {
        final user = data['user'] is Map
            ? Map<String, dynamic>.from(data['user'])
            : <String, dynamic>{};

        final role =
            user['role']?.toString().toLowerCase();

        final userId = user['id'];

        final loggedUsername =
            user['username']?.toString() ?? username;

        // ------------------------------------------------------
        // ROLE VALIDATION
        // ------------------------------------------------------

        if (_selectedRole == 'student' &&
            role != 'student') {
          setState(() {
            _loading = false;
            _message =
                'This account is not a student account.';
          });
          return;
        }

        if (_selectedRole == 'faculty' &&
            role != 'faculty') {
          setState(() {
            _loading = false;
            _message =
                'This account is not a teacher account.';
          });
          return;
        }

        setState(() {
          _loading = false;
          _message = '';
        });

        // ------------------------------------------------------
        // STUDENT
        // ------------------------------------------------------

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

        // ------------------------------------------------------
        // FACULTY
        // ------------------------------------------------------

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

        // ------------------------------------------------------
        // ADMIN
        // ------------------------------------------------------

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

        setState(() {
          _message = 'Unknown user role: $role';
        });

        return;
      }

      setState(() {
        _loading = false;
        _message =
            data['message']?.toString() ??
                'Login failed.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _message =
            'Could not connect to backend.\n\n'
            'Make sure Flask is running and '
            'the phone is connected to the same Wi-Fi network.';
      });

      debugPrint('LOGIN CONNECTION ERROR: $e');
    }
  }

  // ==========================================================
  // CHANGE ROLE
  // ==========================================================

  void _changeRole() {
    setState(() {
      _selectedRole = null;
      _message = '';
      _usernameController.clear();
      _passwordController.clear();
    });
  }

  // ==========================================================
  // REGISTRATION
  // ==========================================================

  void _openStudentRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RegisterPage(),
      ),
    );
  }

  void _openTeacherRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FacultyRegisterPage(),
      ),
    );
  }

  // ==========================================================
  // ROLE SELECTION
  // ==========================================================

  Widget _roleSelection() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Select User Type',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 25),

        SizedBox(
          height: 58,
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _selectedRole = 'faculty';
                _message = '';
              });
            },
            icon: const Icon(Icons.school),
            label: const Text(
              'TEACHER',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        SizedBox(
          height: 58,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _selectedRole = 'student';
                _message = '';
              });
            },
            icon: const Icon(Icons.person),
            label: const Text(
              'STUDENT',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // LOGIN FORM
  // ==========================================================

  Widget _loginForm() {
    final isFaculty = _selectedRole == 'faculty';

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        Text(
          isFaculty
              ? 'Teacher Login'
              : 'Student Login',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 25),

        TextField(
          controller: _usernameController,
          enabled: !_loading,
          textCapitalization:
              TextCapitalization.characters,
          decoration: InputDecoration(
            labelText:
                isFaculty ? 'Employee ID' : 'USN',
            hintText: isFaculty
                ? 'Enter employee ID'
                : 'Enter student USN',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(
              isFaculty
                  ? Icons.badge
                  : Icons.person,
            ),
          ),
        ),

        const SizedBox(height: 16),

        TextField(
          controller: _passwordController,
          enabled: !_loading,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'Enter password',
            border: const OutlineInputBorder(),
            prefixIcon:
                const Icon(Icons.lock),
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

        const SizedBox(height: 18),

        if (_message.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.all(12),
            margin:
                const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(8),
              color:
                  Colors.grey.withValues(alpha: 0.12),
            ),
            child: Text(
              _message,
              textAlign:
                  TextAlign.center,
            ),
          ),

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

        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: _loading
              ? null
              : isFaculty
                  ? _openTeacherRegistration
                  : _openStudentRegistration,
          icon: const Icon(
            Icons.person_add,
          ),
          label: Text(
            isFaculty
                ? 'NEW TEACHER? REGISTER'
                : 'NEW STUDENT? REGISTER',
          ),
        ),

        const SizedBox(height: 8),

        TextButton(
          onPressed:
              _loading ? null : _changeRole,
          child: const Text(
            '← CHANGE USER TYPE',
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('AntiProxy Login'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.security,
                  size: 80,
                ),

                const SizedBox(height: 16),

                const Text(
                  'AntiProxy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Smart Attendance System',
                  textAlign:
                      TextAlign.center,
                ),

                const SizedBox(height: 40),

                _selectedRole == null
                    ? _roleSelection()
                    : _loginForm(),

                const SizedBox(height: 25),

                const Text(
                  'Secure role-based attendance system',
                  textAlign:
                      TextAlign.center,
                  style:
                      TextStyle(fontSize: 12),
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
// STUDENT REGISTRATION
// ============================================================

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() =>
      _RegisterPageState();
}

class _RegisterPageState
    extends State<RegisterPage> {
  final TextEditingController _nameController =
      TextEditingController();

  final TextEditingController _usnController =
      TextEditingController();

  final TextEditingController _semesterController =
      TextEditingController();

  final TextEditingController _divisionController =
      TextEditingController();

  final TextEditingController _departmentController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  final TextEditingController
      _confirmPasswordController =
      TextEditingController();

  final ImagePicker _imagePicker =
      ImagePicker();

  List<XFile> _photos = [];

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String _message = '';

  @override
  void dispose() {
    _nameController.dispose();
    _usnController.dispose();
    _semesterController.dispose();
    _divisionController.dispose();
    _departmentController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ==========================================================
  // PICK PHOTOS
  // ==========================================================

  Future<void> _pickPhotos() async {
    if (_loading) return;

    try {
      final selected =
          await _imagePicker.pickMultiImage(
        imageQuality: 85,
      );

      if (selected.isEmpty) return;

      if (selected.length < 3 ||
          selected.length > 4) {
        setState(() {
          _message =
              'Please select exactly 3 or 4 photos.';
        });
        return;
      }

      setState(() {
        _photos = selected;
        _message =
            '${selected.length} photos selected.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _message =
            'Could not select photos:\n$e';
      });
    }
  }

  void _removePhoto(int index) {
    if (_loading) return;

    setState(() {
      _photos.removeAt(index);

      if (_photos.isEmpty) {
        _message = '';
      } else {
        _message =
            '${_photos.length} photo(s) selected.';
      }
    });
  }

  // ==========================================================
  // VALIDATE
  // ==========================================================

  String? _validateForm() {
    final name =
        _nameController.text.trim();

    final usn =
        _usnController.text.trim();

    final semester =
        _semesterController.text.trim();

    final division =
        _divisionController.text.trim();

    final department =
        _departmentController.text.trim();

    final password =
        _passwordController.text;

    final confirmPassword =
        _confirmPasswordController.text;

    if (name.isEmpty) {
      return 'Please enter your name.';
    }

    if (usn.isEmpty) {
      return 'Please enter your USN.';
    }

    if (semester.isEmpty) {
      return 'Please enter your semester.';
    }

    if (int.tryParse(semester) == null) {
      return 'Semester must be a number.';
    }

    if (division.isEmpty) {
      return 'Please enter your division.';
    }

    if (department.isEmpty) {
      return 'Please enter your department.';
    }

    if (password.length < 6) {
      return
          'Password must contain at least 6 characters.';
    }

    if (password != confirmPassword) {
      return 'Passwords do not match.';
    }

    if (_photos.length < 3 ||
        _photos.length > 4) {
      return
          'Please select exactly 3 or 4 photos.';
    }

    return null;
  }

  // ==========================================================
  // REGISTER
  // ==========================================================

  Future<void> _registerStudent() async {
    final validation =
        _validateForm();

    if (validation != null) {
      setState(() {
        _message = validation;
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = 'Registering student...';
    });

    try {
      final request =
          http.MultipartRequest(
        'POST',
        Uri.parse('$backendUrl/register'),
      );

      request.fields['name'] =
          _nameController.text.trim();

      request.fields['usn'] =
          _usnController.text
              .trim()
              .toUpperCase();

      request.fields['semester'] =
          _semesterController.text.trim();

      request.fields['division'] =
          _divisionController.text
              .trim()
              .toUpperCase();

      request.fields['department'] =
          _departmentController.text.trim();

      request.fields['password'] =
          _passwordController.text;

      for (final photo in _photos) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'photos',
            photo.path,
          ),
        );
      }

      final streamedResponse =
          await request.send();

      final response =
          await http.Response.fromStream(
        streamedResponse,
      );

      Map<String, dynamic> data = {};

      try {
        final decoded =
            jsonDecode(response.body);

        if (decoded
            is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        setState(() {
          _loading = false;
          _message =
              'Student registration successful.';
        });

        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text(
              'Registration Successful',
            ),
            content: const Text(
              'Student account and face '
              'registration completed successfully.',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (!mounted) return;

        Navigator.pop(context);
        return;
      }

      setState(() {
        _loading = false;
        _message =
            data['message']?.toString() ??
                'Registration failed.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _message =
            'Could not connect to backend.\n\n'
            'Make sure Flask is running.';
      });

      debugPrint(
        'STUDENT REGISTRATION ERROR: $e',
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
        title:
            const Text('Student Registration'),
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
              const Icon(
                Icons.person_add,
                size: 70,
              ),

              const SizedBox(height: 12),

              const Text(
                'Create Student Account',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 25),

              TextField(
                controller:
                    _nameController,
                enabled: !_loading,
                textCapitalization:
                    TextCapitalization.words,
                decoration:
                    const InputDecoration(
                  labelText: 'Full Name',
                  border:
                      OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.person),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller:
                    _usnController,
                enabled: !_loading,
                textCapitalization:
                    TextCapitalization.characters,
                decoration:
                    const InputDecoration(
                  labelText: 'USN',
                  hintText:
                      'Example: 2BA23CS085',
                  border:
                      OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.badge),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller:
                    _semesterController,
                enabled: !_loading,
                keyboardType:
                    TextInputType.number,
                decoration:
                    const InputDecoration(
                  labelText: 'Semester',
                  border:
                      OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.school),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller:
                    _divisionController,
                enabled: !_loading,
                decoration:
                    const InputDecoration(
                  labelText: 'Division',
                  border:
                      OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.groups),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller:
                    _departmentController,
                enabled: !_loading,
                decoration:
                    const InputDecoration(
                  labelText: 'Department',
                  border:
                      OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.account_balance),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller:
                    _passwordController,
                enabled: !_loading,
                obscureText:
                    _obscurePassword,
                decoration:
                    InputDecoration(
                  labelText: 'Password',
                  border:
                      const OutlineInputBorder(),
                  prefixIcon:
                      const Icon(Icons.lock),
                  suffixIcon:
                      IconButton(
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

              const SizedBox(height: 14),

              TextField(
                controller:
                    _confirmPasswordController,
                enabled: !_loading,
                obscureText:
                    _obscureConfirmPassword,
                decoration:
                    InputDecoration(
                  labelText:
                      'Confirm Password',
                  border:
                      const OutlineInputBorder(),
                  prefixIcon:
                      const Icon(
                    Icons.lock_outline,
                  ),
                  suffixIcon:
                      IconButton(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      const Text(
                        'Face Registration Photos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Select exactly 3 or 4 clear '
                        'photos of the same person.',
                        textAlign:
                            TextAlign.center,
                      ),

                      const SizedBox(height: 12),

                      ElevatedButton.icon(
                        onPressed: _loading
                            ? null
                            : _pickPhotos,
                        icon: const Icon(
                          Icons.photo_library,
                        ),
                        label: const Text(
                          'SELECT PHOTOS',
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (_photos.isNotEmpty)
                        SizedBox(
                          height: 120,
                          child:
                              ListView.separated(
                            scrollDirection:
                                Axis.horizontal,
                            itemCount:
                                _photos.length,
                            separatorBuilder:
                                (_, index) =>
                                    const SizedBox(
                              width: 8,
                            ),
                            itemBuilder:
                                (context, index) {
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                      10,
                                    ),
                                    child:
                                        Image.file(
                                      File(
                                        _photos[
                                                index]
                                            .path,
                                      ),
                                      width: 100,
                                      height: 110,
                                      fit: BoxFit
                                          .cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child:
                                        GestureDetector(
                                      onTap: () =>
                                          _removePhoto(
                                        index,
                                      ),
                                      child:
                                          Container(
                                        padding:
                                            const EdgeInsets
                                                .all(
                                          4,
                                        ),
                                        decoration:
                                            const BoxDecoration(
                                          color:
                                              Colors.black54,
                                          shape:
                                              BoxShape.circle,
                                        ),
                                        child:
                                            const Icon(
                                          Icons.close,
                                          color:
                                              Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        )
                      else
                        Container(
                          height: 110,
                          decoration:
                              BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(
                              10,
                            ),
                            border: Border.all(
                              color:
                                  Colors.grey,
                            ),
                          ),
                          child:
                              const Center(
                            child: Text(
                              'No photos selected',
                            ),
                          ),
                        ),

                      const SizedBox(height: 10),

                      Text(
                        'Selected: ${_photos.length}/4',
                        textAlign:
                            TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (_message.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.all(12),
                  margin:
                      const EdgeInsets.only(
                    bottom: 16,
                  ),
                  decoration:
                      BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(8),
                    color:
                        Colors.grey.withValues(
                      alpha: 0.12,
                    ),
                  ),
                  child: Text(
                    _message,
                    textAlign:
                        TextAlign.center,
                  ),
                ),

              SizedBox(
                height: 54,
                child:
                    ElevatedButton.icon(
                  onPressed: _loading
                      ? null
                      : _registerStudent,
                  icon: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.person_add,
                        ),
                  label: Text(
                    _loading
                        ? 'REGISTERING...'
                        : 'REGISTER STUDENT',
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

// ============================================================
// FACULTY REGISTRATION
// ============================================================

class FacultyRegisterPage
    extends StatefulWidget {
  const FacultyRegisterPage({
    super.key,
  });

  @override
  State<FacultyRegisterPage>
      createState() =>
          _FacultyRegisterPageState();
}

class _FacultyRegisterPageState
    extends State<FacultyRegisterPage> {
  final TextEditingController
      _nameController =
      TextEditingController();

  final TextEditingController
      _employeeIdController =
      TextEditingController();

  final TextEditingController
      _passwordController =
      TextEditingController();

  final TextEditingController
      _confirmPasswordController =
      TextEditingController();

  String? _department;

  bool _loading = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String _message = '';

  final List<String> _departments = [
    'Computer Science and Engineering',
    'Information Science and Engineering',
    'Electronics and Communication Engineering',
    'Electrical and Electronics Engineering',
    'Mechanical Engineering',
    'Civil Engineering',
    'Artificial Intelligence and Machine Learning',
    'Master of Computer Applications',
    'Other',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _employeeIdController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ==========================================================
  // REGISTER FACULTY
  // ==========================================================

  Future<void> _registerFaculty() async {
    final name =
        _nameController.text.trim();

    final employeeId =
        _employeeIdController.text
            .trim()
            .toUpperCase();

    final password =
        _passwordController.text;

    final confirmPassword =
        _confirmPasswordController.text;

    if (name.isEmpty) {
      setState(() {
        _message =
            'Please enter your full name.';
      });
      return;
    }

    if (employeeId.isEmpty) {
      setState(() {
        _message =
            'Please enter your Employee ID.';
      });
      return;
    }

    if (_department == null) {
      setState(() {
        _message =
            'Please select your department.';
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _message =
            'Password must contain at least 6 characters.';
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _message =
            'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message =
          'Creating teacher account...';
    });

    try {
      final response = await http.post(
        Uri.parse(
          '$backendUrl/faculty/register',
        ),
        headers: {
          'Content-Type':
              'application/json',
        },
        body: jsonEncode({
          'name': name,
          'faculty_id': employeeId,
          'department': _department,
          'password': password,
        }),
      );

      Map<String, dynamic> data = {};

      try {
        final decoded =
            jsonDecode(response.body);

        if (decoded
            is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        setState(() {
          _loading = false;
          _message =
              'Teacher registration successful.';
        });

        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text(
              'Teacher Registration Successful',
            ),
            content: Text(
              'Teacher account created successfully.\n\n'
              'Employee ID: $employeeId\n'
              'Department: $_department\n\n'
              'You can now login using your Employee ID.',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (!mounted) return;

        Navigator.pop(context);
        return;
      }

      setState(() {
        _loading = false;
        _message =
            data['message']?.toString() ??
                'Teacher registration failed.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _message =
            'Could not connect to backend.';
      });

      debugPrint(
        'FACULTY REGISTRATION ERROR: $e',
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
        title:
            const Text('Teacher Registration'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.school,
                size: 75,
              ),

              const SizedBox(height: 12),

              const Text(
                'Create Teacher Account',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 28),

              TextField(
                controller:
                    _nameController,
                enabled: !_loading,
                decoration:
                    const InputDecoration(
                  labelText: 'Full Name',
                  border:
                      OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.person),
                ),
              ),

              const SizedBox(height: 16),

              TextField(
                controller:
                    _employeeIdController,
                enabled: !_loading,
                textCapitalization:
                    TextCapitalization.characters,
                decoration:
                    const InputDecoration(
                  labelText: 'Employee ID',
                  border:
                      OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.badge),
                ),
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _department,
                decoration:
                    const InputDecoration(
                  labelText: 'Department',
                  border:
                      OutlineInputBorder(),
                  prefixIcon: Icon(
                    Icons.account_balance,
                  ),
                ),
                items:
                    _departments.map(
                  (department) {
                    return DropdownMenuItem<
                        String>(
                      value: department,
                      child: Text(
                        department,
                        overflow:
                            TextOverflow.ellipsis,
                      ),
                    );
                  },
                ).toList(),
                onChanged: _loading
                    ? null
                    : (value) {
                        setState(() {
                          _department =
                              value;
                        });
                      },
              ),

              const SizedBox(height: 16),

              TextField(
                controller:
                    _passwordController,
                enabled: !_loading,
                obscureText:
                    _obscurePassword,
                decoration:
                    InputDecoration(
                  labelText: 'Password',
                  border:
                      const OutlineInputBorder(),
                  prefixIcon:
                      const Icon(Icons.lock),
                  suffixIcon:
                      IconButton(
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

              const SizedBox(height: 16),

              TextField(
                controller:
                    _confirmPasswordController,
                enabled: !_loading,
                obscureText:
                    _obscureConfirmPassword,
                decoration:
                    InputDecoration(
                  labelText:
                      'Confirm Password',
                  border:
                      const OutlineInputBorder(),
                  prefixIcon:
                      const Icon(
                    Icons.lock_outline,
                  ),
                  suffixIcon:
                      IconButton(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              if (_message.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.all(12),
                  margin:
                      const EdgeInsets.only(
                    bottom: 16,
                  ),
                  decoration:
                      BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(8),
                    color:
                        Colors.grey.withValues(
                      alpha: 0.12,
                    ),
                  ),
                  child: Text(
                    _message,
                    textAlign:
                        TextAlign.center,
                  ),
                ),

              SizedBox(
                height: 54,
                child:
                    ElevatedButton.icon(
                  onPressed: _loading
                      ? null
                      : _registerFaculty,
                  icon: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.person_add,
                        ),
                  label: Text(
                    _loading
                        ? 'REGISTERING...'
                        : 'REGISTER TEACHER',
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

// ============================================================
// FACULTY DASHBOARD
// ============================================================

class FacultyDashboard extends StatefulWidget {
  final List<CameraDescription> cameras;
  final dynamic userId;
  final String username;

  const FacultyDashboard({
    super.key,
    required this.cameras,
    required this.userId,
    required this.username,
  });

  @override
  State<FacultyDashboard> createState() =>
      _FacultyDashboardState();
}

class _FacultyDashboardState
    extends State<FacultyDashboard> {
  bool _loading = false;
  bool _sessionActive = false;

  int? _sessionId;

  String? _qrData;

  String _subjectName = '';
  String _subjectCode = '';
  String _semester = '';
  String _division = '';

  double _radius = 100;

  Position? _teacherPosition;

  DateTime? _sessionEndTime;

  Duration _remainingTime =
      Duration.zero;

  Timer? _countdownTimer;

  String _statusMessage =
      'No attendance session is active.';

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ==========================================================
  // LOCATION
  // ==========================================================

  Future<Position?> _getCurrentLocation() async {
    final serviceEnabled =
        await Geolocator
            .isLocationServiceEnabled();

    if (!serviceEnabled) {
      _showMessage(
        'Please enable location services.',
      );
      return null;
    }

    var permission =
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
      _showMessage(
        'Location permission is required.',
      );
      return null;
    }

    try {
      return await Geolocator
          .getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.high,
      );
    } catch (e) {
      _showMessage(
        'Could not get location:\n$e',
      );
      return null;
    }
  }



  // ==========================================================
  // CREATE SESSION DIALOG
  // ==========================================================

  Future<void> _openCreateSessionDialog() async {
    if (_loading || _sessionActive) {
      return;
    }

    final subjectNameController =
        TextEditingController();

    final subjectCodeController =
        TextEditingController();

    final semesterController =
        TextEditingController();

    final divisionController =
        TextEditingController();

    final durationController =
        TextEditingController(
      text: '10',
    );

    final radiusController =
        TextEditingController(
      text: '100',
    );

    bool gettingLocation = true;

    Position? location;

    String error = '';
    
    // Automatically capture teacher's current GPS location
location = await _getCurrentLocation();
gettingLocation = false;

if (location == null) {
  _showMessage(
    'Unable to get teacher location. Please enable GPS and try again.',
  );
  return;
}
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder:
                (dialogBuildContext,
                    setDialogState) {
              Future<void> captureLocation() async {
                if (gettingLocation) return;

                setDialogState(() {
                  gettingLocation = true;
                  error = '';
                });

                final capturedLocation =
                    await _getCurrentLocation();

                if (!dialogBuildContext
                    .mounted) {
                  return;
                }

                location =
                    capturedLocation;

                setDialogState(() {
                  gettingLocation = false;
                });
              }

              return AlertDialog(
                title: const Text(
                  'Create Attendance Session',
                ),
                content:
                    SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      TextField(
                        controller:
                            subjectNameController,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Subject Name',
                          hintText:
                              'Data Structures',
                          border:
                              OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.book),
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      TextField(
                        controller:
                            subjectCodeController,
                        textCapitalization:
                            TextCapitalization
                                .characters,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Subject Code',
                          hintText:
                              '21CS42',
                          border:
                              OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.code),
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      TextField(
                        controller:
                            semesterController,
                        keyboardType:
                            TextInputType.number,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Semester',
                          hintText: '5',
                          border:
                              OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.school),
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      TextField(
                        controller:
                            divisionController,
                        textCapitalization:
                            TextCapitalization
                                .characters,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Division',
                          hintText: 'A',
                          border:
                              OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.groups),
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      TextField(
                        controller:
                            durationController,
                        keyboardType:
                            TextInputType.number,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Attendance Duration (minutes)',
                          hintText: '10',
                          border:
                              OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.timer),
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      TextField(
                        controller:
                            radiusController,
                        keyboardType:
                            const TextInputType
                                .numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Geofence Radius (metres)',
                          hintText: '100',
                          border:
                              OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.radar),
                        ),
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      SizedBox(
                        width:
                            double.infinity,
                        child:
                            OutlinedButton.icon(
                          onPressed:
                              gettingLocation
                                  ? null
                                  : captureLocation,
                          icon: gettingLocation
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.my_location,
                                ),
                          label: Text(
                            gettingLocation
                                ? 'GETTING LOCATION...'
                                : location == null
                                    ? 'CAPTURE TEACHER LOCATION'
                                    : 'LOCATION CAPTURED ✓',
                          ),
                        ),
                      ),

                      if (location != null)
                        Padding(
                          padding:
                              const EdgeInsets.only(
                            top: 8,
                          ),
                          child: Text(
                            'Lat: ${location!.latitude.toStringAsFixed(6)}\n'
                            'Lng: ${location!.longitude.toStringAsFixed(6)}\n'
                            'Accuracy: ${location!.accuracy.toStringAsFixed(1)} m',
                            textAlign:
                                TextAlign.center,
                            style:
                                const TextStyle(
                              fontSize: 12,
                            ),
                          ),
                        ),

                      if (error.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.only(
                            top: 10,
                          ),
                          child: Text(
                            error,
                            style:
                                const TextStyle(
                              color: Colors.red,
                            ),
                            textAlign:
                                TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        gettingLocation
                            ? null
                            : () {
                                Navigator.pop(
                                  dialogContext,
                                );
                              },
                    child:
                        const Text('CANCEL'),
                  ),

                  ElevatedButton.icon(
                    onPressed:
                        gettingLocation
                            ? null
                            : () async {
                                final subject =
                                    subjectNameController
                                        .text
                                        .trim();

                                final code =
                                    subjectCodeController
                                        .text
                                        .trim()
                                        .toUpperCase();

                                final semester =
                                    semesterController
                                        .text
                                        .trim();

                                final division =
                                    divisionController
                                        .text
                                        .trim()
                                        .toUpperCase();

                                final duration =
                                    int.tryParse(
                                  durationController
                                      .text
                                      .trim(),
                                );

                                final radius =
                                    double.tryParse(
                                  radiusController
                                      .text
                                      .trim(),
                                );

                                if (subject.isEmpty) {
                                  setDialogState(() {
                                    error =
                                        'Enter subject name.';
                                  });
                                  return;
                                }

                                if (code.isEmpty) {
                                  setDialogState(() {
                                    error =
                                        'Enter subject code.';
                                  });
                                  return;
                                }

                                if (semester.isEmpty) {
                                  setDialogState(() {
                                    error =
                                        'Enter semester.';
                                  });
                                  return;
                                }

                                if (int.tryParse(
                                      semester,
                                    ) ==
                                    null) {
                                  setDialogState(() {
                                    error =
                                        'Semester must be a number.';
                                  });
                                  return;
                                }

                                if (division.isEmpty) {
                                  setDialogState(() {
                                    error =
                                        'Enter division.';
                                  });
                                  return;
                                }

                                if (duration == null ||
                                    duration <= 0) {
                                  setDialogState(() {
                                    error =
                                        'Enter a valid duration.';
                                  });
                                  return;
                                }

                                if (radius == null ||
                                    radius <= 0) {
                                  setDialogState(() {
                                    error =
                                        'Enter a valid radius.';
                                  });
                                  return;
                                }

                                if (location == null) {
                                  setDialogState(() {
                                    error =
                                        'Capture teacher location first.';
                                  });
                                  return;
                                }

                               // Get the teacher's FRESH GPS location immediately
// before creating the attendance session.
setDialogState(() {
  gettingLocation = true;
  error = '';
});

final freshLocation = await _getCurrentLocation();

if (!dialogBuildContext.mounted) {
  return;
}

if (freshLocation == null) {
  setDialogState(() {
    gettingLocation = false;
    error =
        'Could not get teacher GPS location. Please enable GPS and try again.';
  });
  return;
}

location = freshLocation;

setDialogState(() {
  gettingLocation = false;
});

final selectedLocation = freshLocation;

Navigator.pop(
  dialogContext,
);

await _startSession(
                                  subjectName:
                                      subject,
                                  subjectCode:
                                      code,
                                  semester:
                                      semester,
                                  division:
                                      division,
                                  durationMinutes:
                                      duration,
                                  radius:
                                      radius,
                                  location:
                                      selectedLocation,
                                );
                              },
                    icon: const Icon(
                      Icons.play_arrow,
                    ),
                    label:
                        const Text('START'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      WidgetsBinding.instance
          .addPostFrameCallback((_) {
        subjectNameController.dispose();
        subjectCodeController.dispose();
        semesterController.dispose();
        divisionController.dispose();
        durationController.dispose();
        radiusController.dispose();
      });
    }
  }

  // ==========================================================
  // START SESSION
  // ==========================================================

  Future<void> _startSession({
    required String subjectName,
    required String subjectCode,
    required String semester,
    required String division,
    required int durationMinutes,
    required double radius,
    required Position location,
  }) async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _statusMessage =
          'Creating attendance session...';
    });

    try {
      // ------------------------------------------------------
      // IMPORTANT:
      // These field names EXACTLY match backend/routes/session.py
      // ------------------------------------------------------

      final now = DateTime.now();

      final endTime = now.add(
        Duration(minutes: durationMinutes),
      );

      final response = await http.post(
        Uri.parse(
          '$backendUrl/sessions/start',
        ),
        headers: {
          'Content-Type':
              'application/json',
        },
        body: jsonEncode({
          'faculty_user_id':
              widget.userId,

          // Backend requires BOTH fields.
          // We use subject name as class name.
          'class_name':
              subjectName,

          'subject_name':
              subjectName,

          'attendance_date':
              _formatDate(now),

          'start_time':
              _formatTime(now),

          'end_time':
              _formatTime(endTime),

          'allowed_latitude':
              location.latitude,

          'allowed_longitude':
              location.longitude,

          'allowed_radius':
              radius,
        }),
      );

      Map<String, dynamic> data = {};

      try {
        final decoded =
            jsonDecode(response.body);

        if (decoded
            is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      if (!mounted) return;

      // ------------------------------------------------------
      // SUCCESS
      // ------------------------------------------------------

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        final session =
            data['session'] is Map
                ? Map<String, dynamic>.from(
                    data['session'],
                  )
                : <String, dynamic>{};

        final rawSessionId =
            data['session_id'] ??
                session['id'] ??
                session['session_id'];

        final sessionId =
            int.tryParse(
          rawSessionId?.toString() ?? '',
        );

        final token =
            data['qr_token'] ??
                data['token'] ??
                data['session_token'] ??
                session['qr_token'] ??
                session['token'];

        if (sessionId == null) {
          setState(() {
            _loading = false;
            _statusMessage =
                'Session created, but session ID was not returned by server.';
          });

          _showMessage(
            _statusMessage,
          );
          return;
        }

        if (token == null ||
            token.toString().isEmpty) {
          setState(() {
            _loading = false;
            _statusMessage =
                'Session created, but QR token was not returned by server.';
          });

          _showMessage(
            _statusMessage,
          );
          return;
        }

        final qrValue =
            token.toString();

        setState(() {
          _loading = false;
          _sessionActive = true;

          _sessionId = sessionId;
          _qrData = qrValue;

          _subjectName =
              subjectName;
          _subjectCode =
              subjectCode;
          _semester =
              semester;
          _division =
              division;

          _radius =
              radius;

          _teacherPosition =
              location;

          _sessionEndTime =
              endTime;

          _remainingTime =
              Duration(
            minutes:
                durationMinutes,
          );

          _statusMessage =
              'Attendance session is active.';
        });

        _startCountdown();

        return;
      }

      // ------------------------------------------------------
      // SERVER ERROR
      // ------------------------------------------------------

      final message =
          data['message']?.toString() ??
              data['error']?.toString() ??
              'Could not create attendance session.';

      setState(() {
        _loading = false;
        _statusMessage =
            message;
      });

      _showMessage(message);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _statusMessage =
            'Could not connect to backend.';
      });

      _showMessage(
        'Session creation failed.\n$e',
      );

      debugPrint(
        'SESSION START ERROR: $e',
      );
    }
  }

  // ==========================================================
  // DATE / TIME HELPERS
  // ==========================================================

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  // ==========================================================
  // COUNTDOWN
  // ==========================================================

  void _startCountdown() {
    _countdownTimer?.cancel();

    _countdownTimer =
        Timer.periodic(
      const Duration(seconds: 1),
      (_) async {
        if (!mounted ||
            _sessionEndTime == null) {
          return;
        }

        final remaining =
            _sessionEndTime!
                .difference(
          DateTime.now(),
        );

        if (remaining <=
            Duration.zero) {
          _countdownTimer?.cancel();

          if (_sessionActive) {
            await _closeSession(
              automatic: true,
            );
          }

          return;
        }

        if (!mounted) return;

        setState(() {
          _remainingTime =
              remaining;
        });
      },
    );
  }

  // ==========================================================
  // CLOSE SESSION
  // ==========================================================

  Future<void> _closeSession({
    bool automatic = false,
  }) async {
    if (!_sessionActive) {
      return;
    }

    _countdownTimer?.cancel();

    if (_sessionId == null) {
      if (!mounted) return;

      setState(() {
        _sessionActive = false;
        _qrData = null;
        _statusMessage =
            'Attendance session closed.';
      });

      return;
    }

    try {
      final response =
          await http.post(
        Uri.parse(
          '$backendUrl/sessions/'
          '${_sessionId!}/close',
        ),
        headers: {
          'Content-Type':
              'application/json',
        },
        body: jsonEncode({
          'faculty_user_id':
              widget.userId,
        }),
      );

      debugPrint(
        'SESSION CLOSE STATUS: '
        '${response.statusCode}',
      );

      debugPrint(
        'SESSION CLOSE RESPONSE: '
        '${response.body}',
      );
    } catch (e) {
      debugPrint(
        'SESSION CLOSE ERROR: $e',
      );
    }

    if (!mounted) return;

    setState(() {
      _sessionActive = false;
      _qrData = null;
      _remainingTime =
          Duration.zero;
      _sessionId = null;
      _sessionEndTime = null;

      _statusMessage = automatic
          ? 'Attendance session expired.'
          : 'Attendance session closed.';
    });

    if (!automatic) {
      _showMessage(
        'Attendance session closed.',
      );
    }
  }

  // ==========================================================
  // SHARE QR
  // ==========================================================

  Future<void> _shareQr() async {
    if (!_sessionActive ||
        _qrData == null) {
      return;
    }

    try {
      final painter = QrPainter(
        data: _qrData!,
        version:
            QrVersions.auto,
        gapless: true,
      );

      final ByteData? byteData =
          await painter.toImageData(
        900,
        format:
            ImageByteFormat.png,
      );

      if (byteData == null) {
        _showMessage(
          'Could not generate QR image.',
        );
        return;
      }

      final bytes =
          byteData.buffer
              .asUint8List();

      final directory =
          await getTemporaryDirectory();

      final file = File(
        '${directory.path}/'
        'antiproxy_attendance_qr.png',
      );

      await file.writeAsBytes(
        bytes,
      );

      await SharePlus.instance.share(
        ShareParams(
          text:
              'AntiProxy Attendance Session\n'
              'Subject: $_subjectName\n'
              'Code: $_subjectCode\n'
              'Semester: $_semester\n'
              'Division: $_division\n'
              'Radius: ${_radius.toStringAsFixed(0)} metres\n\n'
              'Scan this QR to mark attendance.',
          files: [
            XFile(
              file.path,
              mimeType:
                  'image/png',
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessage(
        'Could not share QR code.\n$e',
      );

      debugPrint(
        'QR SHARE ERROR: $e',
      );
    }
  }

  // ==========================================================
  // MESSAGE
  // ==========================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ==========================================================
  // LOGOUT
  // ==========================================================

  void _logout() {
    if (_sessionActive) {
      _showMessage(
        'Close the active attendance session before logout.',
      );
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LoginPage(
          cameras: widget.cameras,
        ),
      ),
      (route) => false,
    );
  }

  // ==========================================================
  // INFO ROW
  // ==========================================================

  Widget _infoRow(
    IconData icon,
    String title,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ACTIVE SESSION CARD
  // ==========================================================

  Widget _activeSessionCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.qr_code_2,
                  size: 30,
                ),

                const SizedBox(width: 10),

                const Expanded(
                  child: Text(
                    'LIVE ATTENDANCE SESSION',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration:
                      BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                    color: Colors.green,
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      color:
                          Colors.white,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            if (_qrData != null)
              Container(
                padding:
                    const EdgeInsets.all(12),
                decoration:
                    BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                  color: Colors.white,
                  border: Border.all(
                    color: Colors.grey,
                  ),
                ),
                child: QrImageView(
                  data: _qrData!,
                  version:
                      QrVersions.auto,
                  size: 240,
                  backgroundColor:
                      Colors.white,
                ),
              ),

            const SizedBox(height: 16),

            Text(
              _formatDuration(
                _remainingTime,
              ),
              style: const TextStyle(
                fontSize: 38,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const Text(
              'TIME REMAINING',
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 18),

            _infoRow(
              Icons.book,
              'Subject',
              _subjectName,
            ),

            _infoRow(
              Icons.code,
              'Subject Code',
              _subjectCode,
            ),

            _infoRow(
              Icons.school,
              'Semester',
              _semester,
            ),

            _infoRow(
              Icons.groups,
              'Division',
              _division,
            ),

            _infoRow(
              Icons.radar,
              'Radius',
              '${_radius.toStringAsFixed(0)} metres',
            ),

            if (_teacherPosition != null)
              _infoRow(
                Icons.location_on,
                'Teacher GPS',
                '${_teacherPosition!.latitude.toStringAsFixed(5)}, '
                '${_teacherPosition!.longitude.toStringAsFixed(5)}',
              ),

            const SizedBox(height: 18),

            SizedBox(
              width:
                  double.infinity,
              height: 50,
              child:
                  ElevatedButton.icon(
                onPressed:
                    _shareQr,
                icon:
                    const Icon(
                  Icons.share,
                ),
                label:
                    const Text(
                  'SHARE QR / WHATSAPP',
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width:
                  double.infinity,
              height: 50,
              child:
                  OutlinedButton.icon(
                onPressed: () async {
                  final confirmed =
                      await showDialog<bool>(
                    context: context,
                    builder:
                        (dialogContext) =>
                            AlertDialog(
                      title:
                          const Text(
                        'Close Session?',
                      ),
                      content:
                          const Text(
                        'Students will no longer be able '
                        'to mark attendance using this session.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(
                            dialogContext,
                            false,
                          ),
                          child:
                              const Text(
                            'CANCEL',
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () =>
                              Navigator.pop(
                            dialogContext,
                            true,
                          ),
                          child:
                              const Text(
                            'CLOSE',
                          ),
                        ),
                      ],
                    ),
                  );

                  if (!mounted) return;

                  if (confirmed == true) {
                    await _closeSession();
                  }
                },
                icon:
                    const Icon(
                  Icons.stop_circle,
                ),
                label:
                    const Text(
                  'CLOSE SESSION',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // DASHBOARD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'Faculty Dashboard',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed:
                _loading ? null : _logout,
            icon:
                const Icon(Icons.logout),
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.school,
                size: 70,
              ),

              const SizedBox(height: 10),

              const Text(
                'Welcome Faculty',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Employee ID: ${widget.username}',
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(height: 20),

              if (!_sessionActive)
                Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      20,
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.event_available,
                          size: 55,
                        ),

                        const SizedBox(
                            height: 12),

                        const Text(
                          'Attendance Session',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(
                            height: 8),

                        const Text(
                          'Create a session, set the '
                          'teacher location and geofence, '
                          'then generate a dynamic QR code.',
                          textAlign:
                              TextAlign.center,
                        ),

                        const SizedBox(
                            height: 18),

                        SizedBox(
                          width:
                              double.infinity,
                          height: 52,
                          child:
                              ElevatedButton.icon(
                            onPressed:
                                _loading
                                    ? null
                                    : _openCreateSessionDialog,
                            icon: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.add,
                                  ),
                            label: Text(
                              _loading
                                  ? 'CREATING SESSION...'
                                  : 'CREATE ATTENDANCE SESSION',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_sessionActive)
                _activeSessionCard(),

              const SizedBox(height: 16),

              Card(
                child: ListTile(
                  leading:
                      const Icon(
                    Icons.assessment,
                  ),
                  title:
                      const Text(
                    'Attendance Reports',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  subtitle:
                      const Text(
                    'View attendance records and reports',
                  ),
                  trailing:
                      const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                  ),
                  onTap: () {
                    _showMessage(
                      'Reports module will be connected next.',
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              Container(
                padding:
                    const EdgeInsets.all(12),
                decoration:
                    BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(8),
                  color:
                      Colors.grey.withValues(
                    alpha: 0.12,
                  ),
                ),
                child: Text(
                  _statusMessage,
                  textAlign:
                      TextAlign.center,
                ),
              ),

              const SizedBox(height: 25),

              if (!_sessionActive)
                ElevatedButton.icon(
                  onPressed: _logout,
                  icon:
                      const Icon(
                    Icons.logout,
                  ),
                  label:
                      const Text(
                    'LOGOUT',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(
      Duration duration) {
    final hours =
        duration.inHours;

    final minutes =
        duration.inMinutes
            .remainder(60);

    final seconds =
        duration.inSeconds
            .remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

// ============================================================
// ADMIN DASHBOARD
// ============================================================

class AdminDashboard
    extends StatelessWidget {
  final List<CameraDescription> cameras;
  final dynamic userId;
  final String username;

  const AdminDashboard({
    super.key,
    required this.cameras,
    required this.userId,
    required this.username,
  });

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Admin Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () =>
                _logout(context),
            icon:
                const Icon(Icons.logout),
          ),
        ],
      ),

      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.admin_panel_settings,
                size: 80,
              ),

              const SizedBox(height: 20),

              const Text(
                'Welcome Admin',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                'Username: $username',
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(height: 40),

              const Card(
                child: Padding(
                  padding:
                      EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.dashboard,
                        size: 50,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Admin Module',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'User management, student management, '
                        'reports and system administration.',
                        textAlign:
                            TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              ElevatedButton.icon(
                onPressed: () =>
                    _logout(context),
                icon:
                    const Icon(
                  Icons.logout,
                ),
                label:
                    const Text(
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
// STUDENT ATTENDANCE PAGE
// ============================================================

class AttendancePage
    extends StatefulWidget {
  final List<CameraDescription> cameras;
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
 
 class AttendanceQrScannerPage extends StatefulWidget {
  const AttendanceQrScannerPage({super.key});

  @override
  State<AttendanceQrScannerPage> createState() =>
      _AttendanceQrScannerPageState();
}

class _AttendanceQrScannerPageState
    extends State<AttendanceQrScannerPage> {
  final MobileScannerController _scannerController =
      MobileScannerController();

  bool _qrHandled = false;

  void _handleBarcode(BarcodeCapture capture) {
    if (_qrHandled) return;

    if (capture.barcodes.isEmpty) return;

    final Barcode barcode = capture.barcodes.first;

    final String? value = barcode.rawValue;

    if (value == null || value.trim().isEmpty) {
      return;
    }

    _qrHandled = true;

    Navigator.pop(
      context,
      value.trim(),
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        title: const Text('Scan Attendance QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),

      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _scannerController,
              onDetect: _handleBarcode,
            ),
          ),

          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            left: 20,
            right: 20,
            bottom: 60,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.70),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Point the camera at the QR code shown by your faculty.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendancePageState
    extends State<AttendancePage> {
  final TextEditingController
      _usnController =
      TextEditingController();

  XFile? _capturedImage;

  CameraController?
      _cameraController;

  bool _cameraReady = false;
  bool _processing = false;

  String _statusMessage =
      'Enter your USN and capture your face.';

  String? _qrToken;
  bool _scanningQr = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _usnController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ==========================================================
  // CAMERA
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

    for (final camera
        in widget.cameras) {
      if (camera.lensDirection ==
          CameraLensDirection.front) {
        selectedCamera = camera;
        break;
      }
    }

    final controller =
        CameraController(
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
        _cameraController =
            controller;
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
    if (_cameraController ==
            null ||
        !_cameraReady ||
        !_cameraController!
            .value
            .isInitialized) {
      setState(() {
        _statusMessage =
            'Camera is not ready.';
      });
      return;
    }

    if (_processing) return;

    try {
      final image =
          await _cameraController!
              .takePicture();

      if (!mounted) return;

      setState(() {
        _capturedImage = image;
        _statusMessage =
            'Face captured successfully.';
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
  // LOCATION
  // ==========================================================

  Future<Position?> _getCurrentLocation() async {
    final serviceEnabled =
        await Geolocator
            .isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (!mounted) return null;

      setState(() {
        _statusMessage =
            'Please enable location services.';
      });
      return null;
    }

    var permission =
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

    try {
      return await Geolocator
          .getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.high,
      );
    } catch (e) {
      if (!mounted) return null;

      setState(() {
        _statusMessage =
            'Could not get location:\n$e';
      });
      return null;
    }
  }

  // ==========================================================
  // SCAN ATTENDANCE
  // ==========================================================

  Future<void> _scanAttendanceQr() async {
  if (_scanningQr) return;

  setState(() {
    _scanningQr = true;
    _statusMessage = 'Opening QR scanner...';
  });

  try {
    // Release the face camera temporarily because
    // MobileScanner also needs camera access.
    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;

      if (mounted) {
        setState(() {
          _cameraReady = false;
        });
      }
    }

    if (!mounted) return;

    final String? scannedValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const AttendanceQrScannerPage(),
      ),
    );

    if (!mounted) return;

    if (scannedValue != null && scannedValue.trim().isNotEmpty) {
      setState(() {
        _qrToken = scannedValue.trim();
        _statusMessage = 'QR code scanned successfully.';
      });
    } else {
      setState(() {
        _statusMessage = 'QR scanning cancelled.';
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _statusMessage = 'QR scanner error: $e';
      });
    }
  } finally {
    if (mounted) {
      setState(() {
        _scanningQr = false;
      });
    }

    // Restart your front camera after returning from QR scanner.
    try {
      await _initializeCamera();
    } catch (_) {}
  }
}

Future<Position?> _getStableStudentLocation() async {
  const int requiredReadings = 5;

  final List<Position> readings = [];

  if (!mounted) {
    return null;
  }

  setState(() {
    _statusMessage =
        'Getting GPS location...\n'
        'Please keep the phone still.';
  });

  // ------------------------------------------------------------
  // GET 5 GPS READINGS
  // ------------------------------------------------------------

  for (int i = 0; i < requiredReadings; i++) {
    try {
      if (!mounted) {
        return null;
      }

      setState(() {
        _statusMessage =
            'Getting GPS reading ${i + 1}/$requiredReadings...\n'
            'Please keep the phone still.';
      });

      final Position position =
          await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      print(
        'GPS READING ${i + 1}: '
        'lat=${position.latitude}, '
        'lon=${position.longitude}, '
        'accuracy=${position.accuracy}, '
        'mocked=${position.isMocked}',
      );

      // ----------------------------------------------------------
      // MOCK LOCATION CHECK
      // ----------------------------------------------------------

      if (position.isMocked) {
        print(
          'GPS READING ${i + 1}: '
          'REJECTED - MOCK LOCATION',
        );

        if (!mounted) {
          return null;
        }

        setState(() {
          _statusMessage =
              'Mock location detected.\n'
              'Attendance rejected.';
        });

        return null;
      }

      // ----------------------------------------------------------
      // VALID GPS CHECK
      // ----------------------------------------------------------

      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          !position.accuracy.isFinite) {
        print(
          'GPS READING ${i + 1}: '
          'REJECTED - INVALID GPS DATA',
        );
      } else {
        readings.add(position);

        print(
          'GPS READING ${i + 1}: '
          'ACCEPTED '
          '(accuracy '
          '${position.accuracy.toStringAsFixed(2)} m)',
        );
      }

      // Wait before next reading.
      if (i < requiredReadings - 1) {
        await Future.delayed(
          const Duration(milliseconds: 1200),
        );
      }
    } catch (e) {
      print(
        'GPS READING ${i + 1} ERROR: $e',
      );
    }
  }

  // ------------------------------------------------------------
  // MAKE SURE WE HAVE READINGS
  // ------------------------------------------------------------

  if (readings.isEmpty) {
    print(
      'GPS FAILED: No valid GPS readings obtained.',
    );

    if (!mounted) {
      return null;
    }

    setState(() {
      _statusMessage =
          'Unable to get your current location.\n'
          'Please try again.';
    });

    return null;
  }

  // ------------------------------------------------------------
  // FIND THE READING WITH MINIMUM ACCURACY
  // ------------------------------------------------------------

  Position bestReading = readings.first;

  for (final Position reading in readings) {
    if (reading.accuracy <
        bestReading.accuracy) {
      bestReading = reading;
    }
  }

  // ------------------------------------------------------------
  // PRINT ALL READINGS
  // ------------------------------------------------------------

  print(
    '======================================',
  );
  print(
    'GPS READINGS SUMMARY',
  );
  print(
    '======================================',
  );

  for (int i = 0;
      i < readings.length;
      i++) {
    print(
      'Reading ${i + 1}: '
      'lat=${readings[i].latitude}, '
      'lon=${readings[i].longitude}, '
      'accuracy='
      '${readings[i].accuracy.toStringAsFixed(2)} m',
    );
  }

  // ------------------------------------------------------------
  // BEST GPS READING
  // ------------------------------------------------------------

  print(
    '======================================',
  );
  print(
    'BEST GPS READING',
  );
  print(
    '======================================',
  );
  print(
    'Latitude: ${bestReading.latitude}',
  );
  print(
    'Longitude: ${bestReading.longitude}',
  );
  print(
    'Accuracy: '
    '${bestReading.accuracy.toStringAsFixed(2)} m',
  );
  print(
    'Mocked: ${bestReading.isMocked}',
  );
  print(
    '======================================',
  );

  if (!mounted) {
    return null;
  }

  setState(() {
    _statusMessage =
        'Best GPS location obtained.';
  });

  // ------------------------------------------------------------
  // RETURN THE COMPLETE BEST READING
  // ------------------------------------------------------------

  return bestReading;
}

// ==========================================================
  // MARK ATTENDANCE
  // ==========================================================
  
     Future<void> _markAttendance() async {
  // ==========================================================
  // 1. GET USN
  // ==========================================================

  final usn = _usnController.text.trim().toUpperCase();

  if (usn.isEmpty) {
    if (!mounted) return;

    setState(() {
      _statusMessage = 'Please enter your USN.';
    });

    return;
  }

  // ==========================================================
  // 2. QR VALIDATION
  // ==========================================================

  if (_qrToken == null || _qrToken!.trim().isEmpty) {
    if (!mounted) return;

    setState(() {
      _statusMessage =
          'Please scan the attendance QR code first.';
    });

    return;
  }

  // ==========================================================
  // 3. FACE VALIDATION
  // ==========================================================

  if (_capturedImage == null) {
    if (!mounted) return;

    setState(() {
      _statusMessage = 'Please capture your face first.';
    });

    return;
  }

  // ==========================================================
  // 4. PREVENT DOUBLE CLICK
  // ==========================================================

  if (_processing) return;

  setState(() {
    _processing = true;
    _statusMessage = 'Getting your location...';
  });

  try {
    // ========================================================
    // 5. GET CURRENT GPS LOCATION
    // ========================================================

    final position = await _getStableStudentLocation();

    if (position == null) {
      if (!mounted) return;

      setState(() {
        _processing = false;
        _statusMessage =
            'Unable to get your current location.';
      });

      return;
    }

    if (!mounted) return;

    // ========================================================
    // 6. CHECK MOCK LOCATION
    // ========================================================

    if (position.isMocked) {
      setState(() {
        _processing = false;
        _statusMessage =
            'Mock location detected. Attendance rejected.';
      });

      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(
            'Attendance Rejected',
          ),
          content: const Text(
            'Mock/fake location detected.\n\n'
            'Please disable mock location and try again.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

      return;
    }

    // ========================================================
    // 7. VERIFY FACE + GPS + QR ON BACKEND
    // ========================================================

    setState(() {
      _statusMessage =
          'Verifying QR, face and location...';
    });

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '$backendUrl/attendance/mark-session',
      ),
    );

    // --------------------------------------------------------
    // REQUIRED FIELDS
    // --------------------------------------------------------

    request.fields['usn'] = usn;
    request.fields['qr_token'] = _qrToken!.trim();
    request.fields['latitude'] =
        position.latitude.toString();
    request.fields['longitude'] =
        position.longitude.toString();
    request.fields['accuracy'] =
        position.accuracy.toString();
    request.fields['is_mocked'] =
        position.isMocked.toString();

    // --------------------------------------------------------
    // FACE IMAGE
    // --------------------------------------------------------

    request.files.add(
      await http.MultipartFile.fromPath(
        'face',
        _capturedImage!.path,
      ),
    );

    // ========================================================
    // 8. SEND REQUEST
    // ========================================================

    final streamedResponse =
        await request.send();

    final response =
        await http.Response.fromStream(
      streamedResponse,
    );

    // ========================================================
    // 9. DECODE SERVER RESPONSE
    // ========================================================

    Map<String, dynamic> data = {};

    try {
      final decoded =
          jsonDecode(response.body);

      if (decoded is Map) {
        data = Map<String, dynamic>.from(
          decoded,
        );
      }
    } catch (e) {
      print(
        'JSON DECODE ERROR: $e',
      );
    }

    print(
      'ATTENDANCE STATUS: '
      '${response.statusCode}',
    );

    print(
      'ATTENDANCE RESPONSE: '
      '${response.body}',
    );

    // ========================================================
    // 10. SUCCESS
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

      final session =
          data['session'] is Map
              ? Map<String, dynamic>.from(
                  data['session'],
                )
              : null;

      final name =
          student?['name']?.toString() ??
              student?['full_name']?.toString() ??
              usn;

      final similarity =
          face?['similarity']?.toString() ??
              '-';

      final distance =
          location?['distance']?.toString() ??
              '-';

      final subject =
          session?['subject_name']?.toString() ??
              session?['class_name']?.toString() ??
              '-';

      if (!mounted) return;

      setState(() {
        _processing = false;
        _statusMessage =
            'ATTENDANCE MARKED SUCCESSFULLY';
      });

      // ======================================================
      // SUCCESS DIALOG
      // ======================================================

      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(
            'Attendance Successful',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Name: $name',
                ),
                Text(
                  'USN: $usn',
                ),
                Text(
                  'Subject: $subject',
                ),
                const SizedBox(
                  height: 10,
                ),
                const Text(
                  'Face verified: YES',
                ),
                Text(
                  'Face similarity: '
                  '$similarity',
                ),
                Text(
                  'Distance from teacher: '
                  '$distance m',
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
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text(
                'OK',
              ),
            ),
          ],
        ),
      );

      return;
    }

    // ========================================================
    // 11. SERVER REJECTED ATTENDANCE
    // ========================================================

    final message =
        data['message']?.toString() ??
            data['error']?.toString() ??
            data['reason']?.toString() ??
            'Server rejected the request.';

    if (!mounted) return;

    setState(() {
      _processing = false;
      _statusMessage = message;
    });

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Attendance Rejected',
        ),
        content: SingleChildScrollView(
          child: Text(
            'Reason:\n\n'
            '$message\n\n'
            'HTTP Status: '
            '${response.statusCode}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
              );
            },
            child: const Text(
              'OK',
            ),
          ),
        ],
      ),
    );
  } catch (e) {
    // ========================================================
    // 12. CONNECTION ERROR
    // ========================================================

    print(
      'ATTENDANCE CONNECTION ERROR: $e',
    );

    if (!mounted) return;

    setState(() {
      _processing = false;
      _statusMessage =
          'Could not connect to backend.';
    });

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Connection Error',
        ),
        content: SingleChildScrollView(
          child: Text(
            'Could not connect to the '
            'AntiProxy server.\n\n'
            'Backend:\n'
            '$backendUrl\n\n'
            'Error:\n$e',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
              );
            },
            child: const Text(
              'OK',
            ),
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
        title:
            const Text(
          'AntiProxy Attendance',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _processing
                ? null
                : () {
                    Navigator
                        .pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            LoginPage(
                          cameras:
                              widget.cameras,
                        ),
                      ),
                      (route) => false,
                    );
                  },
            icon:
                const Icon(
              Icons.logout,
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
              if (widget.username
                  .isNotEmpty)
                Text(
                  'Logged in as: '
                  '${widget.username}',
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    fontSize: 13,
                  ),
                ),

              const SizedBox(height: 8),

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

              const SizedBox(height: 6),

              const Text(
                'Face + GPS Verification',
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(height: 20),

              TextField(
                controller:
                    _usnController,
                enabled: !_processing,
                textCapitalization:
                    TextCapitalization
                        .characters,
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
              
              const SizedBox(height: 16),

SizedBox(
  width: double.infinity,
  child: ElevatedButton.icon(
    onPressed: _processing || _scanningQr
        ? null
        : _scanAttendanceQr,
    icon: Icon(
      _qrToken == null
          ? Icons.qr_code_scanner
          : Icons.check_circle,
    ),
    label: Text(
      _qrToken == null
          ? 'SCAN ATTENDANCE QR'
          : 'QR SCANNED ✓',
    ),
  ),
),

if (_qrToken != null) ...[
  const SizedBox(height: 10),

  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.green.withOpacity(0.10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: Colors.green,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.verified,
              color: Colors.green,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'Attendance QR scanned',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        Text(
          'Token: ${_qrToken!.length > 18 ? '${_qrToken!.substring(0, 18)}...' : _qrToken!}',
          style: const TextStyle(
            fontSize: 12,
          ),
        ),

        const SizedBox(height: 8),

        TextButton.icon(
          onPressed: _scanAttendanceQr,
          icon: const Icon(Icons.refresh),
          label: const Text('SCAN AGAIN'),
        ),
      ],
    ),
  ),
],

              const SizedBox(height: 16),

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
                child:
                    _capturedImage != null
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

              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: _processing
                    ? null
                    : _captureFace,
                icon: const Icon(
                  Icons.camera_alt,
                ),
                label: Text(
                  _capturedImage == null
                      ? 'CAPTURE FACE'
                      : 'CAPTURE AGAIN',
                ),
              ),

              const SizedBox(height: 12),

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
                  color:
                      Colors.grey.withValues(
                    alpha: 0.12,
                  ),
                ),
                child: Text(
                  _statusMessage,
                  textAlign:
                      TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),

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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Attendance requires a registered face '
                'and valid campus GPS location.',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}