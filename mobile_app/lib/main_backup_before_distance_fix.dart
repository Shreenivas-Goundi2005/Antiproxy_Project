import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:math';

import 'student_subject_registration_page.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

// ============================================================
// BACKEND CONFIGURATION
// ============================================================

const String backendUrl = 'http://10.249.162.207:5000';

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

  runApp(AntiProxyApp(cameras: cameras));
}

// ============================================================
// APP
// ============================================================

class AntiProxyApp extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AntiProxyApp({super.key, required this.cameras});

  @override
  State<AntiProxyApp> createState() => _AntiProxyAppState();
}

class _AntiProxyAppState extends State<AntiProxyApp> {
  bool _checkingLogin = true;
  String? _savedToken;
  String? _savedRole;
  String? _savedUsername;
  dynamic _savedUserId;

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
  }

  Future<void> _checkExistingLogin() async {
    final prefs = await SharedPreferences.getInstance();

    final token = prefs.getString('auth_token');

    // No saved token -> show login page.
    if (token == null || token.isEmpty) {
      if (!mounted) return;

      setState(() {
        _checkingLogin = false;
        _savedToken = null;
      });

      return;
    }

    // Read previously saved login information.
    final role = prefs.getString('user_role');
    final username = prefs.getString('username');
    final userId = prefs.get('user_id');

    if (!mounted) return;

    setState(() {
      _savedToken = token;
      _savedRole = role;
      _savedUsername = username;
      _savedUserId = userId;
      _checkingLogin = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AntiProxy Smart Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: _buildStartPage(),
    );
  }

  Widget _buildStartPage() {
    // ----------------------------------------------------------
    // CHECKING SAVED LOGIN
    // ----------------------------------------------------------
    if (_checkingLogin) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // ----------------------------------------------------------
    // NO SAVED TOKEN
    // ----------------------------------------------------------
    // User is not logged in.
    if (_savedToken == null || _savedToken!.isEmpty) {
      return LoginPage(cameras: widget.cameras);
    }

    // ----------------------------------------------------------
    // STUDENT
    // ----------------------------------------------------------
    if (_savedRole == 'student') {
      return StudentDashboardPage(
        cameras: widget.cameras,
        userId: _savedUserId,
        username: _savedUsername ?? '',
      );
    }

    // ----------------------------------------------------------
    // FACULTY
    // ----------------------------------------------------------
    // Restore the faculty session from SharedPreferences after
    // the app is reopened or Android recreates the app process.
    // The faculty dashboard itself does not need a new login as
    // long as the locally saved authentication token is present.
    if (_savedRole == 'faculty') {
      return FacultyDashboard(
        cameras: widget.cameras,
        userId: _savedUserId,
        username: _savedUsername ?? '',
      );
    }

    if (_savedRole == 'admin') {
      return AdminDashboard(
        cameras: widget.cameras,
        userId: _savedUserId,
        username: _savedUsername ?? 'admin',
      );
    }

    // ----------------------------------------------------------
    // UNKNOWN ROLE
    // ----------------------------------------------------------
    // If the saved role is missing or invalid, return to login.
    return LoginPage(cameras: widget.cameras);
  }
}

// ============================================================
// LOGIN PAGE
// ============================================================

class LoginPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const LoginPage({super.key, required this.cameras});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
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

      if (!mounted) {
        return;
      }

      // ========================================================
      // LOGIN SUCCESS
      // ========================================================

      if (response.statusCode == 200 && data['success'] == true) {
        final user = data['user'] is Map
            ? Map<String, dynamic>.from(data['user'])
            : <String, dynamic>{};

        final role = user['role']?.toString().toLowerCase();

        final userId = user['id'];

        final loggedUsername = user['username']?.toString() ?? username;

        // ------------------------------------------------------
        // ROLE VALIDATION
        // ------------------------------------------------------

        if (_selectedRole == 'student' && role != 'student') {
          setState(() {
            _loading = false;
            _message = 'This account is not a student account.';
          });
          return;
        }

        if (_selectedRole == 'faculty' && role != 'faculty') {
          setState(() {
            _loading = false;
            _message = 'This account is not a teacher account.';
          });
          return;
        }

        if (_selectedRole == 'admin' && role != 'admin') {
          setState(() {
            _loading = false;
            _message = 'This account is not an admin account.';
          });
          return;
        }

        // ------------------------------------------------------
        // GET AUTHENTICATION TOKEN
        // ------------------------------------------------------

        final token = data['token']?.toString();

        if (token == null || token.isEmpty) {
          setState(() {
            _loading = false;
            _message = 'Login failed: authentication token was not received.';
          });
          return;
        }

        // ------------------------------------------------------
        // SAVE LOGIN SESSION
        // ------------------------------------------------------

        final prefs = await SharedPreferences.getInstance();

        // Save authentication token.
        await prefs.setString('auth_token', token);

        // Save user role.
        if (role != null && role.isNotEmpty) {
          await prefs.setString('user_role', role);
        }

        // Save username.
        await prefs.setString('username', loggedUsername);

        // Save user ID.
        if (userId is int) {
          await prefs.setInt('user_id', userId);
        } else if (userId != null) {
          final parsedUserId = int.tryParse(userId.toString());

          if (parsedUserId != null) {
            await prefs.setInt('user_id', parsedUserId);
          }
        }

        debugPrint('Authentication token saved successfully');

        debugPrint('User role saved: $role');

        debugPrint('Username saved: $loggedUsername');

        debugPrint('User ID saved: $userId');

        if (!mounted) {
          return;
        }

        setState(() {
          _loading = false;
          _message = '';
        });

        // ======================================================
        // STUDENT
        // ======================================================

        if (role == 'student') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => StudentDashboardPage(
                cameras: widget.cameras,
                userId: userId,
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
          _loading = false;
          _message = 'Unknown user role: $role';
        });

        return;
      }

      // ========================================================
      // LOGIN FAILURE
      // ========================================================

      setState(() {
        _loading = false;
        _message = data['message']?.toString() ?? 'Login failed.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

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
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
  }

  void _openTeacherRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FacultyRegisterPage()),
    );
  }

  // ==========================================================
  // ROLE SELECTION
  // ==========================================================

  Widget _roleSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Select User Type',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 25),

        // ------------------------------------------------------
        // TEACHER
        // ------------------------------------------------------
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
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ------------------------------------------------------
        // STUDENT
        // ------------------------------------------------------
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
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ------------------------------------------------------
        // ADMIN
        // ------------------------------------------------------
        SizedBox(
          height: 58,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _selectedRole = 'admin';
                _message = '';
              });
            },
            icon: const Icon(Icons.admin_panel_settings),
            label: const Text(
              'ADMINISTRATOR',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
    final isAdmin = _selectedRole == 'admin';

    String title;

    if (isAdmin) {
      title = 'Administrator Login';
    } else if (isFaculty) {
      title = 'Teacher Login';
    } else {
      title = 'Student Login';
    }

    String usernameLabel;

    String usernameHint;

    IconData usernameIcon;

    if (isAdmin) {
      usernameLabel = 'Admin Username';
      usernameHint = 'Enter admin username';
      usernameIcon = Icons.admin_panel_settings;
    } else if (isFaculty) {
      usernameLabel = 'Employee ID';
      usernameHint = 'Enter employee ID';
      usernameIcon = Icons.badge;
    } else {
      usernameLabel = 'USN';
      usernameHint = 'Enter student USN';
      usernameIcon = Icons.person;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 25),

        // ------------------------------------------------------
        // USERNAME
        // ------------------------------------------------------
        TextField(
          controller: _usernameController,
          enabled: !_loading,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: usernameLabel,
            hintText: usernameHint,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(usernameIcon),
          ),
        ),

        const SizedBox(height: 16),

        // ------------------------------------------------------
        // PASSWORD
        // ------------------------------------------------------
        TextField(
          controller: _passwordController,
          enabled: !_loading,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'Enter password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              onPressed: _loading
                  ? null
                  : () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
              ),
            ),
          ),
        ),

        const SizedBox(height: 18),

        // ------------------------------------------------------
        // MESSAGE
        // ------------------------------------------------------
        if (_message.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.withValues(alpha: 0.12),
            ),
            child: Text(_message, textAlign: TextAlign.center),
          ),

        // ------------------------------------------------------
        // LOGIN BUTTON
        // ------------------------------------------------------
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _login,
            child: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'LOGIN',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),

        const SizedBox(height: 12),

        // ------------------------------------------------------
        // REGISTRATION
        // ------------------------------------------------------
        if (!isAdmin)
          OutlinedButton.icon(
            onPressed: _loading
                ? null
                : isFaculty
                ? _openTeacherRegistration
                : _openStudentRegistration,
            icon: const Icon(Icons.person_add),
            label: Text(
              isFaculty ? 'NEW TEACHER? REGISTER' : 'NEW STUDENT? REGISTER',
            ),
          ),

        const SizedBox(height: 8),

        // ------------------------------------------------------
        // CHANGE USER TYPE
        // ------------------------------------------------------
        TextButton(
          onPressed: _loading ? null : _changeRole,
          child: const Text('← CHANGE USER TYPE'),
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
      appBar: AppBar(title: const Text('AntiProxy Login'), centerTitle: true),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.security, size: 80),

                const SizedBox(height: 16),

                const Text(
                  'AntiProxy',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Smart Attendance System',
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                _selectedRole == null ? _roleSelection() : _loginForm(),

                const SizedBox(height: 25),

                const Text(
                  'Secure role-based attendance system',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
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
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _usnController = TextEditingController();

  final TextEditingController _semesterController = TextEditingController();

  final TextEditingController _divisionController = TextEditingController();

  final TextEditingController _departmentController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

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
      final selected = await _imagePicker.pickMultiImage(imageQuality: 85);

      if (selected.isEmpty) return;

      if (selected.length < 3 || selected.length > 4) {
        setState(() {
          _message = 'Please select exactly 3 or 4 photos.';
        });
        return;
      }

      setState(() {
        _photos = selected;
        _message = '${selected.length} photos selected.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _message = 'Could not select photos:\n$e';
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
        _message = '${_photos.length} photo(s) selected.';
      }
    });
  }

  // ==========================================================
  // VALIDATE
  // ==========================================================

  String? _validateForm() {
    final name = _nameController.text.trim();

    final usn = _usnController.text.trim();

    final semester = _semesterController.text.trim();

    final division = _divisionController.text.trim();

    final department = _departmentController.text.trim();

    final password = _passwordController.text;

    final confirmPassword = _confirmPasswordController.text;

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
      return 'Password must contain at least 6 characters.';
    }

    if (password != confirmPassword) {
      return 'Passwords do not match.';
    }

    if (_photos.length < 3 || _photos.length > 4) {
      return 'Please select exactly 3 or 4 photos.';
    }

    return null;
  }

  // ==========================================================
  // REGISTER
  // ==========================================================

  Future<void> _registerStudent() async {
    final validation = _validateForm();

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
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$backendUrl/register'),
      );

      request.fields['name'] = _nameController.text.trim();

      request.fields['usn'] = _usnController.text.trim().toUpperCase();

      request.fields['semester'] = _semesterController.text.trim();

      request.fields['division'] = _divisionController.text
          .trim()
          .toUpperCase();

      request.fields['department'] = _departmentController.text.trim();

      request.fields['password'] = _passwordController.text;

      for (final photo in _photos) {
        request.files.add(
          await http.MultipartFile.fromPath('photos', photo.path),
        );
      }

      final streamedResponse = await request.send();

      final response = await http.Response.fromStream(streamedResponse);

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        setState(() {
          _loading = false;
          _message = 'Student registration successful.';
        });

        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Registration Successful'),
            content: const Text(
              'Student account and face '
              'registration completed successfully.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
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
        _message = data['message']?.toString() ?? 'Registration failed.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _message =
            'Could not connect to backend.\n\n'
            'Make sure Flask is running.';
      });

      debugPrint('STUDENT REGISTRATION ERROR: $e');
    }
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Registration'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.person_add, size: 70),

              const SizedBox(height: 12),

              const Text(
                'Create Student Account',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 25),

              TextField(
                controller: _nameController,
                enabled: !_loading,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _usnController,
                enabled: !_loading,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'USN',
                  hintText: 'Example: 2BA23CS085',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _semesterController,
                enabled: !_loading,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Semester',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.school),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _divisionController,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Division',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.groups),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _departmentController,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.account_balance),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _passwordController,
                enabled: !_loading,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
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
                controller: _confirmPasswordController,
                enabled: !_loading,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
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
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      const Text(
                        'Face Registration Photos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Select exactly 3 or 4 clear '
                        'photos of the same person.',
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 12),

                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickPhotos,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('SELECT PHOTOS'),
                      ),

                      const SizedBox(height: 12),

                      if (_photos.isNotEmpty)
                        SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _photos.length,
                            separatorBuilder: (_, index) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      File(_photos[index].path),
                                      width: 100,
                                      height: 110,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () => _removePhoto(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
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
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey),
                          ),
                          child: const Center(
                            child: Text('No photos selected'),
                          ),
                        ),

                      const SizedBox(height: 10),

                      Text(
                        'Selected: ${_photos.length}/4',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (_message.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.withValues(alpha: 0.12),
                  ),
                  child: Text(_message, textAlign: TextAlign.center),
                ),

              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _registerStudent,
                  icon: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add),
                  label: Text(_loading ? 'REGISTERING...' : 'REGISTER STUDENT'),
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

class FacultyRegisterPage extends StatefulWidget {
  const FacultyRegisterPage({super.key});

  @override
  State<FacultyRegisterPage> createState() => _FacultyRegisterPageState();
}

class _FacultyRegisterPageState extends State<FacultyRegisterPage> {
  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _employeeIdController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _confirmPasswordController =
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
    final name = _nameController.text.trim();

    final employeeId = _employeeIdController.text.trim().toUpperCase();

    final password = _passwordController.text;

    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty) {
      setState(() {
        _message = 'Please enter your full name.';
      });
      return;
    }

    if (employeeId.isEmpty) {
      setState(() {
        _message = 'Please enter your Employee ID.';
      });
      return;
    }

    if (_department == null) {
      setState(() {
        _message = 'Please select your department.';
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _message = 'Password must contain at least 6 characters.';
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _message = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = 'Creating teacher account...';
    });

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/faculty/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'faculty_id': employeeId,
          'department': _department,
          'password': password,
        }),
      );

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        setState(() {
          _loading = false;
          _message = 'Teacher registration successful.';
        });

        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Teacher Registration Successful'),
            content: Text(
              'Teacher account created successfully.\n\n'
              'Employee ID: $employeeId\n'
              'Department: $_department\n\n'
              'You can now login using your Employee ID.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
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
            data['message']?.toString() ?? 'Teacher registration failed.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _message = 'Could not connect to backend.';
      });

      debugPrint('FACULTY REGISTRATION ERROR: $e');
    }
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Registration'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.school, size: 75),

              const SizedBox(height: 12),

              const Text(
                'Create Teacher Account',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 28),

              TextField(
                controller: _nameController,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),

              const SizedBox(height: 16),

              TextField(
                controller: _employeeIdController,
                enabled: !_loading,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Employee ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _department,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.account_balance),
                ),
                items: _departments.map((department) {
                  return DropdownMenuItem<String>(
                    value: department,
                    child: Text(department, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: _loading
                    ? null
                    : (value) {
                        setState(() {
                          _department = value;
                        });
                      },
              ),

              const SizedBox(height: 16),

              TextField(
                controller: _passwordController,
                enabled: !_loading,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
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
                controller: _confirmPasswordController,
                enabled: !_loading,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
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
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.withValues(alpha: 0.12),
                  ),
                  child: Text(_message, textAlign: TextAlign.center),
                ),

              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _registerFaculty,
                  icon: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add),
                  label: Text(_loading ? 'REGISTERING...' : 'REGISTER TEACHER'),
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

class ClassroomGeofencePreview extends StatelessWidget {
  final double length;
  final double width;
  final double? accuracy;
  final bool verified;
  final bool compact;

  const ClassroomGeofencePreview({
    super.key,
    required this.length,
    required this.width,
    this.accuracy,
    this.verified = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final area = length > 0 && width > 0 ? length * width : 0.0;

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: .65)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.crop_free_rounded, color: primary),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Classroom geofence',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Rectangular attendance boundary',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: verified
                      ? Colors.green.withValues(alpha: .10)
                      : primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: verified
                        ? Colors.green.withValues(alpha: .22)
                        : primary.withValues(alpha: .18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      verified
                          ? Icons.verified_rounded
                          : Icons.visibility_rounded,
                      size: 14,
                      color: verified ? Colors.green.shade700 : primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      verified ? 'VERIFIED' : 'PREVIEW',
                      style: TextStyle(
                        color: verified ? Colors.green.shade700 : primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: .055),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'The faculty position is the classroom centre. Students must stay inside the rectangle.',
                    style: TextStyle(fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: compact ? 224 : 270,
            width: double.infinity,
            child: CustomPaint(
              painter: ClassroomGeofencePainter(
                length: length,
                width: width,
                primary: primary,
                verified: verified,
                accuracy: accuracy,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  context,
                  Icons.straighten_rounded,
                  'LENGTH',
                  '${length.toStringAsFixed(1)} m',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCard(
                  context,
                  Icons.width_normal_rounded,
                  'WIDTH',
                  '${width.toStringAsFixed(1)} m',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCard(
                  context,
                  Icons.square_foot_rounded,
                  'AREA',
                  '${area.toStringAsFixed(1)} m²',
                ),
              ),
            ],
          ),
          if (accuracy != null) ...[
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: verified
                    ? Colors.green.withValues(alpha: .075)
                    : primary.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.gps_fixed_rounded,
                    size: 17,
                    color: verified ? Colors.green.shade700 : primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Centre accuracy',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  Text(
                    '${accuracy!.toStringAsFixed(1)} m',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: verified ? Colors.green.shade700 : primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricCard(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: primary),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class ClassroomGeofencePainter extends CustomPainter {
  final double length;
  final double width;
  final Color primary;
  final bool verified;
  final double? accuracy;

  ClassroomGeofencePainter({
    required this.length,
    required this.width,
    required this.primary,
    required this.verified,
    required this.accuracy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final safeLength = length > 0 ? length : 1.0;
    final safeWidth = width > 0 ? width : 1.0;
    final ratio = safeLength / safeWidth;

    // Deliberately reserve space around every side. This prevents N/S/E/W
    // and measurement labels from touching the classroom rectangle.
    const leftSpace = 74.0;
    const rightSpace = 52.0;
    const topSpace = 42.0;
    const bottomSpace = 54.0;

    final availableWidth = max(80.0, size.width - leftSpace - rightSpace);
    final availableHeight = max(70.0, size.height - topSpace - bottomSpace);

    double rectWidth = availableWidth;
    double rectHeight = rectWidth / ratio;

    if (rectHeight > availableHeight) {
      rectHeight = availableHeight;
      rectWidth = rectHeight * ratio;
    }

    rectWidth = max(80.0, rectWidth);
    rectHeight = max(54.0, rectHeight);

    final rect = Rect.fromCenter(
      center: Offset(
        leftSpace + (availableWidth / 2),
        topSpace + (availableHeight / 2),
      ),
      width: rectWidth,
      height: rectHeight,
    );

    final boundaryColor = verified ? Colors.green.shade600 : primary;

    final fillPaint = Paint()
      ..color = boundaryColor.withValues(alpha: .075)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      fillPaint,
    );

    final borderPaint = Paint()
      ..color = boundaryColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      borderPaint,
    );

    final center = rect.center;
    final centerPaint = Paint()
      ..color = boundaryColor
      ..style = PaintingStyle.fill;

    if (accuracy != null && accuracy! > 0) {
      final accuracyRadius = max(
        12.0,
        min(rect.shortestSide * .20, accuracy! * 2.0),
      );
      final ringPaint = Paint()
        ..color = boundaryColor.withValues(alpha: .12)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, accuracyRadius, ringPaint);
    }

    canvas.drawCircle(center, 7, centerPaint);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );

    void drawText(
      String text,
      Offset centerPoint, {
      double fontSize = 10,
      FontWeight weight = FontWeight.w700,
      Color? color,
    }) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: color ?? primary,
          fontSize: fontSize,
          fontWeight: weight,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          centerPoint.dx - textPainter.width / 2,
          centerPoint.dy - textPainter.height / 2,
        ),
      );
    }

    void drawPill(String text, Offset centerPoint) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: boundaryColor,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      );
      textPainter.layout();
      final pill = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: centerPoint,
          width: textPainter.width + 16,
          height: 22,
        ),
        const Radius.circular(11),
      );
      final paint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawRRect(pill, paint);
      final border = Paint()
        ..color = boundaryColor.withValues(alpha: .25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(pill, border);
      textPainter.paint(
        canvas,
        Offset(
          centerPoint.dx - textPainter.width / 2,
          centerPoint.dy - textPainter.height / 2,
        ),
      );
    }

    // Direction markers are deliberately outside the classroom boundary.
    drawPill('N', Offset(center.dx, rect.top - 28));
    drawPill('S', Offset(center.dx, rect.bottom + 28));
    drawPill('W', Offset(rect.left - 36, center.dy));
    drawPill('E', Offset(rect.right + 26, center.dy));

    // Length measurement: below the classroom, independent from S marker.
    final dimensionPaint = Paint()
      ..color = boundaryColor.withValues(alpha: .55)
      ..strokeWidth = 1.2;
    final lengthY = min(size.height - 13, rect.bottom + 39);

    canvas.drawLine(
      Offset(rect.left, lengthY),
      Offset(rect.right, lengthY),
      dimensionPaint,
    );
    canvas.drawLine(
      Offset(rect.left, lengthY - 4),
      Offset(rect.left, lengthY + 4),
      dimensionPaint,
    );
    canvas.drawLine(
      Offset(rect.right, lengthY - 4),
      Offset(rect.right, lengthY + 4),
      dimensionPaint,
    );
    drawText(
      'Length  ${safeLength.toStringAsFixed(1)} m',
      Offset(center.dx, lengthY + 10),
      fontSize: 9,
      weight: FontWeight.w800,
    );

    // Width measurement: left of the classroom, independent from W marker.
    final widthX = max(30.0, rect.left - 55);
    canvas.drawLine(
      Offset(widthX, rect.top),
      Offset(widthX, rect.bottom),
      dimensionPaint,
    );
    canvas.drawLine(
      Offset(widthX - 4, rect.top),
      Offset(widthX + 4, rect.top),
      dimensionPaint,
    );
    canvas.drawLine(
      Offset(widthX - 4, rect.bottom),
      Offset(widthX + 4, rect.bottom),
      dimensionPaint,
    );

    canvas.save();
    canvas.translate(widthX - 13, center.dy);
    canvas.rotate(-pi / 2);
    drawText(
      'Width  ${safeWidth.toStringAsFixed(1)} m',
      Offset.zero,
      fontSize: 9,
      weight: FontWeight.w800,
    );
    canvas.restore();

    // Centre marker label sits inside the rectangle with a dedicated pill.
    drawPill('CLASSROOM CENTRE', Offset(center.dx, center.dy + 32));
  }

  @override
  bool shouldRepaint(covariant ClassroomGeofencePainter oldDelegate) {
    return oldDelegate.length != length ||
        oldDelegate.width != width ||
        oldDelegate.primary != primary ||
        oldDelegate.verified != verified ||
        oldDelegate.accuracy != accuracy;
  }
}

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
  State<FacultyDashboard> createState() => _FacultyDashboardState();
}

class _FacultyDashboardState extends State<FacultyDashboard> {
  bool _loading = false;
  bool _sessionActive = false;

  int? _sessionId;

  String? _qrData;

  String _subjectName = '';
  String _subjectCode = '';
  String _semester = '';
  String _division = '';

  // Kept only for backward compatibility with older session data.
  double _radius = 0;

  double _classroomLength = 0;
  double _classroomWidth = 0;

  int _selectedTab = 0;

  Position? _teacherPosition;

  DateTime? _sessionEndTime;

  Duration _remainingTime = Duration.zero;

  Timer? _countdownTimer;
  Timer? _attendanceRefreshTimer;

  int _livePresentCount = 0;
  int _liveLateCount = 0;
  int _liveRejectedCount = 0;
  int _liveTotalStudents = 0;
  bool _attendanceRefreshing = false;
  DateTime? _lastAttendanceRefresh;
  List<Map<String, dynamic>> _liveRecentActivity = [];

  String _statusMessage = 'No attendance session is active.';

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _attendanceRefreshTimer?.cancel();
    super.dispose();
  }

  // ==========================================================
  // LOCATION
  // ==========================================================

  Future<Position?> _getCurrentLocation() async {
    const int requiredReadings = 5;

    // Maximum acceptable reported GPS accuracy.
    // Readings worse than this are ignored.
    const double maxAccuracyMeters = 15.0;

    final List<Position> readings = [];

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (mounted) {
        _showMessage('Please enable location services.');
      }
      return null;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        _showMessage('Location permission is required.');
      }
      return null;
    }

    if (mounted) {
      _showMessage(
        'Getting accurate teacher location...\n'
        'Please keep the phone still.',
      );
    }

    // ----------------------------------------------------------
    // COLLECT 5 GPS READINGS
    // ----------------------------------------------------------

    for (int i = 0; i < requiredReadings; i++) {
      try {
        if (mounted) {
          _showMessage(
            'Getting teacher GPS reading ${i + 1}/$requiredReadings...\n'
            'Please keep the phone still.',
          );
        }

        final Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
        );

        print(
          'FACULTY GPS READING ${i + 1}: '
          'lat=${position.latitude}, '
          'lon=${position.longitude}, '
          'accuracy=${position.accuracy}, '
          'mocked=${position.isMocked}',
        );

        // --------------------------------------------------------
        // MOCK LOCATION CHECK
        // --------------------------------------------------------

        if (position.isMocked) {
          print(
            'FACULTY GPS READING ${i + 1}: '
            'REJECTED - MOCK LOCATION',
          );

          if (mounted) {
            _showMessage(
              'Mock location detected.\n'
              'Teacher location rejected.',
            );
          }

          return null;
        }

        // --------------------------------------------------------
        // BASIC VALIDITY CHECK
        // --------------------------------------------------------

        if (!position.latitude.isFinite ||
            !position.longitude.isFinite ||
            !position.accuracy.isFinite) {
          print(
            'FACULTY GPS READING ${i + 1}: '
            'REJECTED - INVALID DATA',
          );
          continue;
        }

        // --------------------------------------------------------
        // ACCURACY CHECK
        // --------------------------------------------------------

        if (position.accuracy <= 0 || position.accuracy > maxAccuracyMeters) {
          print(
            'FACULTY GPS READING ${i + 1}: '
            'REJECTED - ACCURACY ${position.accuracy}m',
          );
          continue;
        }

        readings.add(position);

        if (mounted) {
          _showMessage(
            'Teacher GPS reading ${i + 1}/$requiredReadings captured.\n'
            'Accuracy: ${position.accuracy.toStringAsFixed(1)} m',
          );
        }

        // Small delay allows the GPS subsystem to obtain
        // a fresh measurement instead of repeatedly using
        // the same cached position.
        if (i < requiredReadings - 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      } catch (e) {
        print('FACULTY GPS READING ${i + 1}: ERROR $e');

        continue;
      }
    }

    // ----------------------------------------------------------
    // REQUIRE ENOUGH VALID READINGS
    // ----------------------------------------------------------

    if (readings.length < 3) {
      if (mounted) {
        _showMessage(
          'Unable to obtain enough accurate GPS readings.\n'
          'Please move to an area with better GPS reception '
          'and try again.',
        );
      }

      return null;
    }

    // ----------------------------------------------------------
    // CALCULATE WEIGHTED STABLE LOCATION
    // ----------------------------------------------------------
    //
    // More accurate readings get more weight.
    //
    // weight = 1 / accuracy²
    //
    // Therefore a 5m reading contributes more than a 10m
    // reading.
    // ----------------------------------------------------------

    double weightedLatitude = 0.0;
    double weightedLongitude = 0.0;
    double totalWeight = 0.0;

    for (final Position position in readings) {
      final double accuracy = position.accuracy.clamp(1.0, 100.0);

      final double weight = 1.0 / (accuracy * accuracy);

      weightedLatitude += position.latitude * weight;
      weightedLongitude += position.longitude * weight;

      totalWeight += weight;
    }

    if (totalWeight <= 0) {
      if (mounted) {
        _showMessage('Could not calculate a stable teacher location.');
      }

      return null;
    }

    final double stableLatitude = weightedLatitude / totalWeight;

    final double stableLongitude = weightedLongitude / totalWeight;

    // ----------------------------------------------------------
    // CALCULATE AVERAGE GPS ACCURACY
    // ----------------------------------------------------------

    double totalAccuracy = 0.0;

    for (final Position position in readings) {
      totalAccuracy += position.accuracy;
    }

    final double averageAccuracy = totalAccuracy / readings.length;

    print(
      'FACULTY STABLE LOCATION: '
      'lat=$stableLatitude, '
      'lon=$stableLongitude, '
      'validReadings=${readings.length}, '
      'averageAccuracy=${averageAccuracy.toStringAsFixed(2)}m',
    );

    if (mounted) {
      _showMessage(
        'Teacher location confirmed.\n'
        '${readings.length} accurate readings used.\n'
        'Average accuracy: '
        '${averageAccuracy.toStringAsFixed(1)} m',
      );
    }

    // Return the calculated stable coordinate.
    //
    // We use the best available reading as the Position object
    // template and replace its latitude/longitude with the
    // calculated stable coordinates.
    final Position reference = readings.reduce(
      (a, b) => a.accuracy <= b.accuracy ? a : b,
    );

    return Position(
      longitude: stableLongitude,
      latitude: stableLatitude,
      timestamp: DateTime.now(),
      accuracy: averageAccuracy,
      altitude: reference.altitude,
      altitudeAccuracy: reference.altitudeAccuracy,
      heading: reference.heading,
      headingAccuracy: reference.headingAccuracy,
      speed: reference.speed,
      speedAccuracy: reference.speedAccuracy,
    );
  }

  // ==========================================================
  // CREATE SESSION DIALOG
  // ==========================================================

  Future<void> _openCreateSessionDialog() async {
    if (_loading || _sessionActive) {
      return;
    }

    final subjectNameController = TextEditingController();
    final subjectCodeController = TextEditingController();
    final semesterController = TextEditingController();
    final divisionController = TextEditingController();
    final durationController = TextEditingController(text: '10');
    final lengthController = TextEditingController();
    final widthController = TextEditingController();

    bool gettingLocation = false;
    Position? stableLocation;
    String error = '';
    int currentStep = 0;

    Future<Position?> captureStableTeacherLocation(
      void Function(int completed, int total) onProgress,
    ) async {
      const int requiredReadings = 5;
      const double maximumAcceptedAccuracy = 20.0;

      try {
        final readings = <Position>[];

        // --------------------------------------------------------
        // COLLECT 5 READINGS IN PARALLEL
        // --------------------------------------------------------
        //
        // This avoids unnecessarily waiting for five complete
        // sequential GPS acquisition cycles.
        //
        final futures = List.generate(requiredReadings, (_) async {
          try {
            final position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.bestForNavigation,
            );

            return position;
          } catch (e) {
            debugPrint('TEACHER GPS READING ERROR: $e');
            return null;
          }
        });

        final results = await Future.wait(futures);

        // --------------------------------------------------------
        // VALIDATE READINGS
        // --------------------------------------------------------

        for (final position in results) {
          onProgress(readings.length + 1, requiredReadings);

          if (position == null) {
            continue;
          }

          debugPrint(
            'TEACHER GPS READING: '
            'lat=${position.latitude}, '
            'lon=${position.longitude}, '
            'accuracy=${position.accuracy}, '
            'mocked=${position.isMocked}',
          );

          // Mock/fake GPS protection.
          if (position.isMocked) {
            debugPrint('MOCK GPS DETECTED - TEACHER LOCATION REJECTED');

            return null;
          }

          // Coordinate validation.
          if (!position.latitude.isFinite ||
              !position.longitude.isFinite ||
              !position.accuracy.isFinite) {
            continue;
          }

          if (position.latitude < -90 ||
              position.latitude > 90 ||
              position.longitude < -180 ||
              position.longitude > 180) {
            continue;
          }

          // Accuracy validation.
          if (position.accuracy <= 0 ||
              position.accuracy > maximumAcceptedAccuracy) {
            continue;
          }

          readings.add(position);
        }

        // We require all five readings to be valid.
        if (readings.length < requiredReadings) {
          debugPrint(
            'TEACHER GPS FAILED: '
            '${readings.length}/$requiredReadings valid readings',
          );

          return null;
        }

        // --------------------------------------------------------
        // CHECK FOR EXCESSIVE GPS INSTABILITY
        // --------------------------------------------------------
        //
        // Calculate the approximate spread of the readings.
        // A very large spread indicates unstable GPS.
        //

        double minLatitude = readings.first.latitude;
        double maxLatitude = readings.first.latitude;
        double minLongitude = readings.first.longitude;
        double maxLongitude = readings.first.longitude;

        for (final position in readings) {
          if (position.latitude < minLatitude) {
            minLatitude = position.latitude;
          }

          if (position.latitude > maxLatitude) {
            maxLatitude = position.latitude;
          }

          if (position.longitude < minLongitude) {
            minLongitude = position.longitude;
          }

          if (position.longitude > maxLongitude) {
            maxLongitude = position.longitude;
          }
        }

        // Approximate metres per degree.
        const double metersPerLatitudeDegree = 111320.0;

        final latitudeSpreadMeters =
            (maxLatitude - minLatitude).abs() * metersPerLatitudeDegree;

        final averageLatitude =
            readings
                .map((position) => position.latitude)
                .reduce((a, b) => a + b) /
            readings.length;

        final longitudeMetersPerDegree =
            metersPerLatitudeDegree * cos(averageLatitude * pi / 180.0);

        final longitudeSpreadMeters =
            (maxLongitude - minLongitude).abs() * longitudeMetersPerDegree;

        final maximumSpread = max(latitudeSpreadMeters, longitudeSpreadMeters);

        debugPrint(
          'TEACHER GPS SPREAD: '
          '${maximumSpread.toStringAsFixed(2)} m',
        );

        // If readings are extremely far apart, GPS is unstable.
        if (maximumSpread > 40.0) {
          debugPrint('TEACHER GPS FAILED: unstable location');

          return null;
        }

        // --------------------------------------------------------
        // ACCURACY-WEIGHTED CENTER
        // --------------------------------------------------------
        //
        // Weight = 1 / accuracy²
        //
        // Example:
        // 5m accuracy gets significantly more influence than
        // 15m accuracy.
        //

        double weightedLatitude = 0;
        double weightedLongitude = 0;
        double totalWeight = 0;

        for (final position in readings) {
          final accuracy = max(position.accuracy, 1.0);

          final weight = 1.0 / (accuracy * accuracy);

          weightedLatitude += position.latitude * weight;

          weightedLongitude += position.longitude * weight;

          totalWeight += weight;
        }

        if (totalWeight <= 0) {
          return null;
        }

        final finalLatitude = weightedLatitude / totalWeight;

        final finalLongitude = weightedLongitude / totalWeight;

        // Use the most accurate reading as the template for
        // the resulting Position object.
        final bestReading = readings.reduce(
          (a, b) => a.accuracy <= b.accuracy ? a : b,
        );

        final stablePosition = Position(
          latitude: finalLatitude,
          longitude: finalLongitude,
          timestamp: bestReading.timestamp,
          accuracy: bestReading.accuracy,
          altitude: bestReading.altitude,
          altitudeAccuracy: bestReading.altitudeAccuracy,
          heading: bestReading.heading,
          headingAccuracy: bestReading.headingAccuracy,
          speed: bestReading.speed,
          speedAccuracy: bestReading.speedAccuracy,
          floor: bestReading.floor,
          isMocked: bestReading.isMocked,
        );

        debugPrint(
          'STABLE TEACHER LOCATION: '
          'lat=${stablePosition.latitude}, '
          'lon=${stablePosition.longitude}, '
          'accuracy=${stablePosition.accuracy}',
        );

        return stablePosition;
      } catch (e) {
        debugPrint('STABLE TEACHER LOCATION ERROR: $e');

        return null;
      }
    }

    bool validateClassStep(void Function(void Function()) setDialogState) {
      final subject = subjectNameController.text.trim();
      final code = subjectCodeController.text.trim();
      final semester = semesterController.text.trim();
      final division = divisionController.text.trim();
      final duration = int.tryParse(durationController.text.trim());

      if (subject.isEmpty) {
        setDialogState(() => error = 'Enter the subject name.');
        return false;
      }
      if (code.isEmpty) {
        setDialogState(() => error = 'Enter the subject code.');
        return false;
      }
      if (semester.isEmpty || int.tryParse(semester) == null) {
        setDialogState(() => error = 'Enter a valid semester number.');
        return false;
      }
      if (division.isEmpty) {
        setDialogState(() => error = 'Enter the division.');
        return false;
      }
      if (duration == null || duration < 1 || duration > 240) {
        setDialogState(
          () => error = 'Duration must be between 1 and 240 minutes.',
        );
        return false;
      }
      setDialogState(() => error = '');
      return true;
    }

    bool validateClassroomStep(void Function(void Function()) setDialogState) {
      final length = double.tryParse(lengthController.text.trim());
      final width = double.tryParse(widthController.text.trim());

      if (length == null || length <= 0 || length > 500) {
        setDialogState(
          () => error = 'Classroom length must be between 0 and 500 metres.',
        );
        return false;
      }
      if (width == null || width <= 0 || width > 500) {
        setDialogState(
          () => error = 'Classroom width must be between 0 and 500 metres.',
        );
        return false;
      }
      setDialogState(() => error = '');
      return true;
    }

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogBuildContext, setDialogState) {
              Future<void> captureLocation() async {
                if (gettingLocation) return;

                setDialogState(() {
                  gettingLocation = true;
                  error = '';
                  stableLocation = null;
                });

                final capturedLocation = await captureStableTeacherLocation((
                  completed,
                  total,
                ) {
                  if (!dialogBuildContext.mounted) return;
                  setDialogState(() {
                    error =
                        'Verifying classroom centre...\nGPS reading $completed of $total';
                  });
                });

                if (!dialogBuildContext.mounted) return;

                if (capturedLocation == null) {
                  setDialogState(() {
                    gettingLocation = false;
                    stableLocation = null;
                    error =
                        'Location verification failed.\nMove to the classroom centre, enable GPS, and ensure mock location is disabled.';
                  });
                  return;
                }

                stableLocation = capturedLocation;
                setDialogState(() {
                  gettingLocation = false;
                  error = '';
                });
              }

              final double? classroomLength = double.tryParse(
                lengthController.text.trim(),
              );
              final double? classroomWidth = double.tryParse(
                widthController.text.trim(),
              );
              final double area =
                  (classroomLength ?? 0) * (classroomWidth ?? 0);

              Widget stepIndicator() {
                const labels = ['Class', 'Classroom', 'Security'];
                return Row(
                  children: List.generate(labels.length, (index) {
                    final active = index == currentStep;
                    final completed =
                        index < currentStep ||
                        (index == 2 && stableLocation != null);
                    return Expanded(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              if (index > 0)
                                Expanded(
                                  child: Container(
                                    height: 2,
                                    color: index <= currentStep
                                        ? Theme.of(
                                            dialogBuildContext,
                                          ).colorScheme.primary
                                        : Theme.of(
                                            dialogBuildContext,
                                          ).dividerColor,
                                  ),
                                ),
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: active || completed
                                      ? Theme.of(
                                          dialogBuildContext,
                                        ).colorScheme.primary
                                      : Theme.of(
                                          dialogBuildContext,
                                        ).colorScheme.surfaceContainerHighest,
                                ),
                                child: Icon(
                                  completed && !active
                                      ? Icons.check
                                      : Icons.circle,
                                  size: completed && !active ? 18 : 10,
                                  color: active || completed
                                      ? Theme.of(
                                          dialogBuildContext,
                                        ).colorScheme.onPrimary
                                      : Theme.of(
                                          dialogBuildContext,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (index < labels.length - 1)
                                Expanded(
                                  child: Container(
                                    height: 2,
                                    color: index < currentStep
                                        ? Theme.of(
                                            dialogBuildContext,
                                          ).colorScheme.primary
                                        : Theme.of(
                                            dialogBuildContext,
                                          ).dividerColor,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            labels[index],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: active
                                  ? Theme.of(
                                      dialogBuildContext,
                                    ).colorScheme.primary
                                  : Theme.of(
                                      dialogBuildContext,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                );
              }

              Widget sectionHeader(
                IconData icon,
                String title,
                String subtitle,
              ) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(
                      dialogBuildContext,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        icon,
                        color: Theme.of(dialogBuildContext).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Theme.of(
                                  dialogBuildContext,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              Widget classStep() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeader(
                      Icons.menu_book_rounded,
                      'Class details',
                      'Tell AntiProxy which class is being recorded.',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: subjectNameController,
                      decoration: const InputDecoration(
                        labelText: 'Subject name',
                        hintText: 'Data Structures',
                        prefixIcon: Icon(Icons.book_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subjectCodeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Subject code',
                        hintText: '22UCS113C',
                        prefixIcon: Icon(Icons.code_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: semesterController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Semester',
                              hintText: '7',
                              prefixIcon: Icon(Icons.school_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: divisionController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Division',
                              hintText: 'B',
                              prefixIcon: Icon(Icons.groups_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: durationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Session duration (minutes)',
                        hintText: '10',
                        prefixIcon: Icon(Icons.timer_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                );
              }

              Widget classroomStep() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeader(
                      Icons.crop_square_rounded,
                      'Classroom setup',
                      'The faculty GPS position becomes the centre of this rectangular classroom.',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: lengthController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Length (m)',
                              hintText: '8',
                              prefixIcon: Icon(Icons.straighten_rounded),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: widthController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Width (m)',
                              hintText: '6',
                              prefixIcon: Icon(Icons.width_normal_rounded),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ClassroomGeofencePreview(
                      length: classroomLength ?? 0,
                      width: classroomWidth ?? 0,
                      verified: false,
                    ),
                  ],
                );
              }

              Widget securityStep() {
                final verified = stableLocation != null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeader(
                      Icons.verified_user_rounded,
                      'Security verification',
                      'AntiProxy verifies the classroom centre before generating the attendance QR.',
                    ),
                    const SizedBox(height: 14),
                    ...[
                      (
                        '5-point GPS verification',
                        'Five accurate readings establish a stable centre.',
                        Icons.location_searching_rounded,
                      ),
                      (
                        'Mock-location protection',
                        'Simulated/fake GPS readings are rejected.',
                        Icons.gps_off_rounded,
                      ),
                      (
                        'Rectangular geofence',
                        'Students must be inside the configured classroom boundary.',
                        Icons.crop_square_rounded,
                      ),
                      (
                        'Dynamic QR session',
                        'The QR is generated only after verification succeeds.',
                        Icons.qr_code_2_rounded,
                      ),
                    ].map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: Theme.of(
                              dialogBuildContext,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                item.$3,
                                color: Theme.of(
                                  dialogBuildContext,
                                ).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.$1,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      item.$2,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(
                                          dialogBuildContext,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.check_circle_rounded, size: 20),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: verified
                            ? Theme.of(
                                dialogBuildContext,
                              ).colorScheme.primaryContainer
                            : Theme.of(
                                dialogBuildContext,
                              ).colorScheme.surfaceContainerHighest,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            verified
                                ? Icons.location_on_rounded
                                : Icons.my_location_rounded,
                            size: 34,
                            color: Theme.of(
                              dialogBuildContext,
                            ).colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            verified
                                ? 'Classroom centre verified'
                                : 'Ready to verify classroom centre',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 5),
                          if (verified)
                            Text(
                              'Accuracy ${stableLocation!.accuracy.toStringAsFixed(1)} m\n'
                              '${stableLocation!.latitude.toStringAsFixed(6)}, ${stableLocation!.longitude.toStringAsFixed(6)}',
                              textAlign: TextAlign.center,
                            )
                          else
                            const Text(
                              'Stand at the centre of the classroom and verify your location before starting.',
                              textAlign: TextAlign.center,
                            ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: gettingLocation
                                  ? null
                                  : captureLocation,
                              icon: gettingLocation
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      verified
                                          ? Icons.refresh_rounded
                                          : Icons.my_location_rounded,
                                    ),
                              label: Text(
                                gettingLocation
                                    ? 'VERIFYING LOCATION...'
                                    : verified
                                    ? 'VERIFY AGAIN'
                                    : 'VERIFY CLASSROOM CENTRE',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (gettingLocation) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                );
              }

              final titles = [
                'Class details',
                'Classroom setup',
                'Security verification',
              ];

              return AlertDialog(
                titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Start Attendance',
                            style: Theme.of(dialogBuildContext)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: gettingLocation
                              ? null
                              : () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(
                      'Step ${currentStep + 1} of 3 • ${titles[currentStep]}',
                      style: TextStyle(
                        color: Theme.of(
                          dialogBuildContext,
                        ).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    stepIndicator(),
                  ],
                ),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        if (currentStep == 0) classStep(),
                        if (currentStep == 1) classroomStep(),
                        if (currentStep == 2) securityStep(),
                        if (error.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: gettingLocation
                                  ? Theme.of(
                                      dialogBuildContext,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      dialogBuildContext,
                                    ).colorScheme.errorContainer,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  gettingLocation
                                      ? Icons.sync_rounded
                                      : Icons.info_outline_rounded,
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(error)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  if (currentStep > 0)
                    TextButton(
                      onPressed: gettingLocation
                          ? null
                          : () => setDialogState(() {
                              currentStep--;
                              error = '';
                            }),
                      child: const Text('BACK'),
                    )
                  else
                    TextButton(
                      onPressed: gettingLocation
                          ? null
                          : () => Navigator.pop(dialogContext),
                      child: const Text('CANCEL'),
                    ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: gettingLocation
                        ? null
                        : () async {
                            if (currentStep == 0) {
                              if (validateClassStep(setDialogState)) {
                                setDialogState(() {
                                  currentStep = 1;
                                  error = '';
                                });
                              }
                              return;
                            }

                            if (currentStep == 1) {
                              if (validateClassroomStep(setDialogState)) {
                                setDialogState(() {
                                  currentStep = 2;
                                  error = '';
                                });
                              }
                              return;
                            }

                            if (stableLocation == null) {
                              setDialogState(() {
                                error =
                                    'Verify the classroom centre before starting attendance.';
                              });
                              return;
                            }

                            final subject = subjectNameController.text.trim();
                            final code = subjectCodeController.text
                                .trim()
                                .toUpperCase();
                            final semester = semesterController.text.trim();
                            final division = divisionController.text
                                .trim()
                                .toUpperCase();
                            final duration = int.parse(
                              durationController.text.trim(),
                            );
                            final finalLength = double.parse(
                              lengthController.text.trim(),
                            );
                            final finalWidth = double.parse(
                              widthController.text.trim(),
                            );
                            final capturedLocation = stableLocation!;

                            Navigator.pop(dialogContext);

                            await _startSession(
                              subjectName: subject,
                              subjectCode: code,
                              semester: semester,
                              division: division,
                              durationMinutes: duration,
                              classroomLength: finalLength,
                              classroomWidth: finalWidth,
                              location: capturedLocation,
                            );
                          },
                    icon: Icon(
                      currentStep == 2
                          ? Icons.play_arrow_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                    label: Text(
                      currentStep == 2 ? 'START ATTENDANCE' : 'CONTINUE',
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        subjectNameController.dispose();
        subjectCodeController.dispose();
        semesterController.dispose();
        divisionController.dispose();
        durationController.dispose();
        lengthController.dispose();
        widthController.dispose();
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
    required double classroomLength,
    required double classroomWidth,
    required Position location,
  }) async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _statusMessage = 'Creating attendance session...';
    });

    try {
      final now = DateTime.now();

      final endTime = now.add(Duration(minutes: durationMinutes));

      final response = await http.post(
        Uri.parse('$backendUrl/sessions/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'faculty_user_id': widget.userId,

          // Backend requires both fields.
          // Subject name is used as class name.
          'class_name': subjectName,

          'subject_name': subjectName,

          'subject_code': subjectCode,

          'semester': semester,

          'division': division,

          'attendance_date': _formatDate(now),

          'start_time': _formatTime(now),

          'end_time': _formatTime(endTime),

          // Stable teacher coordinate becomes
          // the classroom center.
          'allowed_latitude': location.latitude,

          'allowed_longitude': location.longitude,

          // NEW RECTANGULAR CLASSROOM GEO-FENCE
          'classroom_length': classroomLength,
          'classroom_width': classroomWidth,

          // Kept only for compatibility with older
          // backend/database records.
          'allowed_radius': 0,
        }),
      );

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
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
        final session = data['session'] is Map
            ? Map<String, dynamic>.from(data['session'])
            : <String, dynamic>{};

        final rawSessionId =
            data['session_id'] ?? session['id'] ?? session['session_id'];

        final sessionId = int.tryParse(rawSessionId?.toString() ?? '');

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

          _showMessage(_statusMessage);
          return;
        }

        if (token == null || token.toString().isEmpty) {
          setState(() {
            _loading = false;
            _statusMessage =
                'Session created, but QR token was not returned by server.';
          });

          _showMessage(_statusMessage);
          return;
        }

        final qrValue = token.toString();

        setState(() {
          _loading = false;

          _sessionActive = true;

          _sessionId = sessionId;

          _qrData = qrValue;

          _subjectName = subjectName;

          _subjectCode = subjectCode;

          _semester = semester;

          _division = division;

          // Radius is retained only for backward compatibility.
          _radius = 0;

          _classroomLength = classroomLength;
          _classroomWidth = classroomWidth;

          // Stable teacher position = classroom center.
          _teacherPosition = location;

          _sessionEndTime = endTime;

          _remainingTime = Duration(minutes: durationMinutes);

          _statusMessage = 'Attendance session is active.';

          // Reset live monitoring for the newly created session.
          _livePresentCount = 0;
          _liveLateCount = 0;
          _liveRejectedCount = 0;
          _liveTotalStudents = 0;
          _liveRecentActivity = [];
          _lastAttendanceRefresh = null;
        });

        _startCountdown();
        _startLiveAttendanceRefresh();

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
        _statusMessage = message;
      });

      _showMessage(message);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _statusMessage = 'Could not connect to backend.';
      });

      _showMessage('Session creation failed.\n$e');

      debugPrint('SESSION START ERROR: $e');
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

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || _sessionEndTime == null) {
        return;
      }

      final remaining = _sessionEndTime!.difference(DateTime.now());

      if (remaining <= Duration.zero) {
        _countdownTimer?.cancel();

        if (_sessionActive) {
          await _closeSession(automatic: true);
        }

        return;
      }

      if (!mounted) return;

      setState(() {
        _remainingTime = remaining;
      });
    });
  }

  // ==========================================================
  // CLOSE SESSION
  // ==========================================================

  Future<void> _closeSession({bool automatic = false}) async {
    if (!_sessionActive) {
      return;
    }

    _countdownTimer?.cancel();
    _attendanceRefreshTimer?.cancel();
    _attendanceRefreshTimer = null;

    if (_sessionId == null) {
      if (!mounted) return;

      setState(() {
        _sessionActive = false;
        _qrData = null;
        _statusMessage = 'Attendance session closed.';
      });

      return;
    }

    try {
      final response = await http.post(
        Uri.parse(
          '$backendUrl/sessions/'
          '${_sessionId!}/close',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'faculty_user_id': widget.userId}),
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
      debugPrint('SESSION CLOSE ERROR: $e');
    }

    if (!mounted) return;

    setState(() {
      _sessionActive = false;
      _qrData = null;
      _remainingTime = Duration.zero;
      _sessionId = null;
      _sessionEndTime = null;

      _statusMessage = automatic
          ? 'Attendance session expired.'
          : 'Attendance session closed.';
    });

    if (!automatic) {
      _showMessage('Attendance session closed.');
    }
  }

  // ==========================================================
  // SHARE QR
  // ==========================================================

  Future<void> _shareQr() async {
    if (!_sessionActive || _qrData == null) {
      return;
    }

    try {
      final painter = QrPainter(
        data: _qrData!,
        version: QrVersions.auto,
        gapless: true,
        color: Colors.black,
        emptyColor: Colors.white,
      );

      final ByteData? byteData = await painter.toImageData(
        900,
        format: ImageByteFormat.png,
      );

      if (byteData == null) {
        _showMessage('Could not generate QR image.');
        return;
      }

      final bytes = byteData.buffer.asUint8List();

      final directory = await getTemporaryDirectory();

      final file = File(
        '${directory.path}/'
        'antiproxy_attendance_qr.png',
      );

      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          text:
              'AntiProxy Attendance Session\n'
              'Subject: $_subjectName\n'
              'Code: $_subjectCode\n'
              'Semester: $_semester\n'
              'Division: $_division\n'
              'Classroom: ${_classroomLength.toStringAsFixed(1)} m × ${_classroomWidth.toStringAsFixed(1)} m\n\n'
              'Scan this QR to mark attendance.',
          files: [XFile(file.path, mimeType: 'image/png')],
        ),
      );
    } catch (e) {
      _showMessage('Could not share QR code.\n$e');

      debugPrint('QR SHARE ERROR: $e');
    }
  }

  // ==========================================================
  // LIVE ATTENDANCE MONITORING
  // ==========================================================

  void _startLiveAttendanceRefresh() {
    _attendanceRefreshTimer?.cancel();

    // Fetch immediately, then refresh every 5 seconds while the
    // session is active. The existing faculty report endpoint is
    // used so no new backend API is required for this UI phase.
    _refreshLiveAttendance();
    _attendanceRefreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshLiveAttendance(),
    );
  }

  Future<void> _refreshLiveAttendance({bool manual = false}) async {
    if (!_sessionActive || _sessionId == null || _attendanceRefreshing) {
      return;
    }

    if (manual) {
      setState(() => _attendanceRefreshing = true);
    } else {
      _attendanceRefreshing = true;
    }

    try {
      final response = await http.get(
        Uri.parse('$backendUrl/faculty/attendance-report/${widget.userId}'),
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final session = _findLiveSession(decoded, _sessionId!);

      if (session == null) {
        _attendanceRefreshing = false;
        if (manual && mounted) setState(() {});
        return;
      }

      final summaryValue = session['summary'];
      final summary = summaryValue is Map
          ? Map<String, dynamic>.from(summaryValue)
          : <String, dynamic>{};

      final studentsValue = session['students'];
      final students = studentsValue is List
          ? List<dynamic>.from(studentsValue)
          : <dynamic>[];

      int total = _liveTotalStudents;
      int present = _toIntValue(
        summary['present'] ?? session['present'] ?? session['present_count'],
      );
      int late = _toIntValue(
        summary['late'] ?? session['late'] ?? session['late_count'],
      );
      int rejected = _toIntValue(
        summary['rejected'] ?? session['rejected'] ?? session['rejected_count'],
      );

      if (students.isNotEmpty) {
        total = students.length;
        present = 0;
        late = 0;

        for (final item in students) {
          if (item is! Map) continue;
          final status = _toStringValue(item['status']).toLowerCase().trim();
          if (status == 'present') {
            present++;
          } else if (status == 'late') {
            late++;
          }
        }
      }

      if (total < present + late + rejected) {
        total = present + late + rejected;
      }

      final recent = <Map<String, dynamic>>[];
      for (final item in students) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final status = _toStringValue(map['status']).toLowerCase().trim();
        if (status == 'present' || status == 'late' || status == 'rejected') {
          recent.add(map);
        }
      }

      recent.sort((a, b) {
        final aTime = _toStringValue(
          a['marked_at'] ?? a['created_at'] ?? a['attendance_time'],
        );
        final bTime = _toStringValue(
          b['marked_at'] ?? b['created_at'] ?? b['attendance_time'],
        );
        return bTime.compareTo(aTime);
      });

      if (!mounted) return;

      setState(() {
        _liveTotalStudents = total;
        _livePresentCount = present;
        _liveLateCount = late;
        _liveRejectedCount = rejected;
        _liveRecentActivity = recent.take(5).toList();
        _lastAttendanceRefresh = DateTime.now();
        _attendanceRefreshing = false;
      });
    } catch (e) {
      _attendanceRefreshing = false;
      debugPrint('LIVE ATTENDANCE REFRESH ERROR: $e');
      if (manual && mounted) setState(() {});
    }
  }

  Map<String, dynamic>? _findLiveSession(dynamic value, int sessionId) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final candidates = [
        map['id'],
        map['session_id'],
        map['attendance_session_id'],
      ];
      if (candidates.any((v) => v?.toString() == sessionId.toString())) {
        return map;
      }

      for (final entry in map.values) {
        final found = _findLiveSession(entry, sessionId);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final item in value) {
        final found = _findLiveSession(item, sessionId);
        if (found != null) return found;
      }
    }
    return null;
  }

  int _toIntValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _toStringValue(dynamic value) {
    if (value == null || value.toString() == 'null') return '';
    return value.toString();
  }

  // ==========================================================
  // MESSAGE
  // ==========================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ==========================================================
  // LOGOUT
  // ==========================================================

  void _logout() {
    if (_sessionActive) {
      _showMessage('Close the active attendance session before logout.');
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage(cameras: widget.cameras)),
      (route) => false,
    );
  }

  // ==========================================================
  // INFO ROW
  // ==========================================================

  Widget _infoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // ==========================================================
  // ACTIVE SESSION CARD
  // ==========================================================

  Widget _activeSessionCard() {
    final theme = Theme.of(context);
    final remainingSeconds = _remainingTime.inSeconds;
    final totalSeconds = _sessionEndTime == null
        ? 1
        : _sessionEndTime!.difference(DateTime.now()).inSeconds.clamp(1, 86400);
    final progress = (remainingSeconds / totalSeconds).clamp(0.0, 1.0);
    final markedCount = _livePresentCount + _liveLateCount;
    final notMarked = (_liveTotalStudents - markedCount - _liveRejectedCount)
        .clamp(0, 999999);
    final attendanceRate = _liveTotalStudents > 0
        ? (markedCount / _liveTotalStudents) * 100
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.wifi_tethering,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live attendance',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text('Students can scan the active QR now'),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(value: progress, minHeight: 7),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Time remaining', style: TextStyle(fontSize: 12)),
                  Text(
                    _formatDuration(_remainingTime),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_qrData != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: QrImageView(
                      data: _qrData!,
                      version: QrVersions.auto,
                      size: 230,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  _subjectName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_subjectCode • Semester $_semester • Division $_division',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),

                // ------------------------------------------------
                // LIVE ATTENDANCE COUNTERS
                // ------------------------------------------------
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Attendance monitor',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh attendance',
                        onPressed: _attendanceRefreshing
                            ? null
                            : () => _refreshLiveAttendance(manual: true),
                        icon: _attendanceRefreshing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _liveCountCard(
                        icon: Icons.check_circle_rounded,
                        label: 'Present',
                        value: _livePresentCount,
                        iconColor: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _liveCountCard(
                        icon: Icons.hourglass_top_rounded,
                        label: 'Not marked',
                        value: notMarked,
                        iconColor: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _liveCountCard(
                        icon: Icons.block_rounded,
                        label: 'Rejected',
                        value: _liveRejectedCount,
                        iconColor: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Attendance rate',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              '${attendanceRate.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$_livePresentCount${_liveLateCount > 0 ? ' + $_liveLateCount late' : ''} / $_liveTotalStudents',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ------------------------------------------------
                // RECENT ACTIVITY
                // ------------------------------------------------
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recent activity',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_liveRecentActivity.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.hourglass_empty_rounded),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Waiting for students to mark attendance...',
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._liveRecentActivity.map(_liveActivityTile),

                const SizedBox(height: 18),
                ClassroomGeofencePreview(
                  length: _classroomLength,
                  width: _classroomWidth,
                  accuracy: _teacherPosition?.accuracy,
                  verified: true,
                  compact: true,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _sessionStat(
                        Icons.straighten,
                        'Classroom',
                        '${_classroomLength.toStringAsFixed(1)} × ${_classroomWidth.toStringAsFixed(1)} m',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _sessionStat(
                        Icons.location_on_outlined,
                        'Center',
                        _teacherPosition == null
                            ? 'Verified'
                            : '${_teacherPosition!.latitude.toStringAsFixed(4)}, ${_teacherPosition!.longitude.toStringAsFixed(4)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _lastAttendanceRefresh == null
                        ? 'Live monitor starting...'
                        : 'Updated ${_formatTime(_lastAttendanceRefresh!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _shareQr,
                    icon: const Icon(Icons.share),
                    label: const Text('SHARE QR'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Close attendance session?'),
                          content: const Text(
                            'Students will no longer be able to mark attendance using this QR.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('CANCEL'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('CLOSE SESSION'),
                            ),
                          ],
                        ),
                      );
                      if (mounted && confirmed == true) await _closeSession();
                    },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('CLOSE SESSION'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _liveCountCard({
    required IconData icon,
    required String label,
    required int value,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 5),
          Text(
            '$value',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _liveActivityTile(Map<String, dynamic> student) {
    final status = _toStringValue(student['status']).toLowerCase().trim();
    final name = _toStringValue(
      student['full_name'] ??
          student['name'] ??
          student['student_name'] ??
          student['student_id'],
    );
    final usn = _toStringValue(
      student['student_id'] ?? student['usn'] ?? student['username'],
    );
    final time = _toStringValue(
      student['marked_at'] ??
          student['created_at'] ??
          student['attendance_time'],
    );

    final isLate = status == 'late';
    final isRejected = status == 'rejected';
    final iconColor = isRejected
        ? Colors.red
        : (isLate ? Colors.orange : Colors.green);
    final icon = isRejected
        ? Icons.block_rounded
        : (isLate ? Icons.schedule_rounded : Icons.check_circle_rounded);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Student' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  isRejected
                      ? 'Attendance rejected'
                      : (isLate
                            ? 'Attendance marked late'
                            : 'Attendance verified'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (usn.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                usn,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (time.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                time.length > 16 ? time.substring(time.length - 8) : time,
                style: const TextStyle(fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sessionStat(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11)),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // DASHBOARD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final pages = <Widget>[
      _buildFacultyHome(theme),
      _buildFacultyProfile(theme),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Command Center'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: _openFacultyNotifications,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => setState(() => _selectedTab = 1),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: _selectedTab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    FacultyAttendanceReportPage(userId: widget.userId),
              ),
            );
            return;
          }
          setState(() => _selectedTab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Reports',
          ),
        ],
      ),
    );
  }

  void _openFacultySecurity() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacultySecurityCenterPage(
          username: widget.username,
          sessionActive: _sessionActive,
          presentCount: _livePresentCount,
          rejectedCount: _liveRejectedCount,
        ),
      ),
    );
  }

  void _openFacultyAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacultyAnalyticsPage(userId: widget.userId),
      ),
    );
  }

  void _openFacultyHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacultySessionHistoryPage(userId: widget.userId),
      ),
    );
  }

  void _openFacultyNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacultyNotificationsPage(
          sessionActive: _sessionActive,
          presentCount: _livePresentCount,
          rejectedCount: _liveRejectedCount,
        ),
      ),
    );
  }

  Widget _buildFacultyHome(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(
                    widget.username.isEmpty
                        ? 'F'
                        : widget.username.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome back',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _sessionActive
                            ? 'Attendance session is live'
                            : 'Ready to take attendance',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_sessionActive)
            _activeSessionCard()
          else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.qr_code_2,
                        size: 34,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Start a new attendance session',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Set the subject, classroom dimensions and duration. AntiProxy will verify the teacher location before creating the QR.',
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _openCreateSessionDialog,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: Text(
                        _loading
                            ? 'VERIFYING & CREATING...'
                            : 'START ATTENDANCE',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _featureCard(
                    Icons.location_on_outlined,
                    'Verified GPS',
                    '5-point teacher location check',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _featureCard(
                    Icons.crop_square,
                    'Classroom',
                    'Length × width geofence',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Faculty tools',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _openFacultySecurity,
                          icon: const Icon(Icons.security_rounded),
                          label: const Text('Security Center'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openFacultyAnalytics,
                          icon: const Icon(Icons.insights_rounded),
                          label: const Text('Analytics'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openFacultyHistory,
                          icon: const Icon(Icons.history_rounded),
                          label: const Text('Session History'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_statusMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_statusMessage)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _featureCard(IconData icon, String title, String subtitle) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildFacultyProfile(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 42,
                    child: Text(
                      widget.username.isEmpty
                          ? 'F'
                          : widget.username.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.username,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Faculty account'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Employee ID'),
                  subtitle: Text(widget.username),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Security'),
                  subtitle: const Text(
                    'QR, GPS, mock-location and face verification enabled',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.crop_square),
                  title: const Text('Geofencing'),
                  subtitle: const Text(
                    'Rectangular classroom perimeter using length and width',
                  ),
                ),
              ],
            ),
          ),
          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_none_rounded),
                  title: const Text('Notifications'),
                  subtitle: const Text('Session and attendance alerts'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openFacultyNotifications,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.security_rounded),
                  title: const Text('Security Center'),
                  subtitle: const Text(
                    'Verification layers and security events',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openFacultySecurity,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('Session History'),
                  subtitle: const Text('Review completed attendance sessions'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openFacultyHistory,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _sessionActive ? null : _logout,
            icon: const Icon(Icons.logout),
            label: const Text('LOG OUT'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;

    final minutes = duration.inMinutes.remainder(60);

    final seconds = duration.inSeconds.remainder(60);

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
// FACULTY SECURITY CENTER
// ============================================================
class FacultySecurityCenterPage extends StatelessWidget {
  final String username;
  final bool sessionActive;
  final int presentCount;
  final int rejectedCount;

  const FacultySecurityCenterPage({
    super.key,
    required this.username,
    required this.sessionActive,
    required this.presentCount,
    required this.rejectedCount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layers = [
      (
        'Dynamic QR',
        'Unique session token protects the attendance session.',
        Icons.qr_code_2_rounded,
      ),
      (
        '5-point GPS',
        'Multiple readings establish a stable verification point.',
        Icons.gps_fixed_rounded,
      ),
      (
        'Mock GPS detection',
        'Simulated location signals are rejected by the existing flow.',
        Icons.location_disabled_rounded,
      ),
      (
        'Rectangular geofence',
        'Students must be inside the configured classroom boundary.',
        Icons.crop_square_rounded,
      ),
      (
        'Face verification',
        'Student identity verification remains part of attendance.',
        Icons.face_retouching_natural_rounded,
      ),
      (
        'Duplicate prevention',
        'Repeated attendance for the same session is blocked.',
        Icons.block_rounded,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Faculty Security Center')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  child: Text(
                    username.isEmpty
                        ? 'F'
                        : username.substring(0, 1).toUpperCase(),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AntiProxy Security',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sessionActive
                            ? 'Live session protected'
                            : 'Protection layers ready',
                      ),
                    ],
                  ),
                ),
                Icon(Icons.verified_rounded, color: scheme.primary, size: 32),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _metric(
                  context,
                  'Present',
                  presentCount.toString(),
                  Icons.how_to_reg_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metric(
                  context,
                  'Rejected',
                  rejectedCount.toString(),
                  Icons.gpp_bad_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Verification layers',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...layers.map(
            (item) => Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Icon(item.$3, size: 21)),
                title: Text(
                  item.$1,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(item.$2),
                trailing: const Icon(Icons.check_circle_rounded),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Security activity',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  const SizedBox(height: 10),
                  _event(
                    Icons.qr_code_2_rounded,
                    'QR session protection',
                    'Dynamic QR is used for the active session.',
                  ),
                  _event(
                    Icons.location_on_rounded,
                    'Location protection',
                    'Teacher and student location validation remain enabled.',
                  ),
                  _event(
                    Icons.face_rounded,
                    'Identity protection',
                    'Face verification remains part of attendance marking.',
                  ),
                  _event(
                    Icons.crop_square_rounded,
                    'Boundary protection',
                    'Rectangular classroom geofence is enforced server-side.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _event(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(subtitle, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FACULTY ANALYTICS
// ============================================================
class FacultyAnalyticsPage extends StatefulWidget {
  final dynamic userId;
  const FacultyAnalyticsPage({super.key, required this.userId});
  @override
  State<FacultyAnalyticsPage> createState() => _FacultyAnalyticsPageState();
}

class _FacultyAnalyticsPageState extends State<FacultyAnalyticsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('$backendUrl/faculty/attendance-report/${widget.userId}'),
      );
      if (response.statusCode != 200)
        throw Exception('Server returned ${response.statusCode}.');
      final decoded = jsonDecode(response.body);
      final raw = decoded is List
          ? decoded
          : (decoded is Map && decoded['reports'] is List
                ? decoded['reports']
                : decoded is Map && decoded['data'] is List
                ? decoded['data']
                : <dynamic>[]);
      _reports = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.toString();
        });
    }
  }

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
  int _int(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final sessions = _reports.length;
    int present = 0, total = 0;
    for (final r in _reports) {
      present += _int(r['present'] ?? r['present_count']);
      total += _int(r['total'] ?? r['total_students']);
    }
    final rate = total == 0 ? 0.0 : present * 100 / total;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Analytics'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _stat(
                          context,
                          'Sessions',
                          sessions.toString(),
                          Icons.calendar_month_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _stat(
                          context,
                          'Present',
                          present.toString(),
                          Icons.how_to_reg_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _stat(
                    context,
                    'Average attendance',
                    '${rate.toStringAsFixed(1)}%',
                    Icons.insights_rounded,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Attendance overview',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${rate.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (rate / 100).clamp(0, 1),
                            minHeight: 10,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$present verified attendance records across the available report data.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Sessions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ..._reports.asMap().entries.map(
                    (entry) => _reportCard(context, entry.value, entry.key + 1),
                  ),
                  if (_reports.isEmpty)
                    const Card(
                      elevation: 0,
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No report data is available yet.'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _stat(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(title),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _reportCard(BuildContext context, Map<String, dynamic> r, int n) {
    final subject =
        (r['subject_name'] ?? r['subject'] ?? r['subject_code'] ?? 'Session')
            .toString();
    final date = (r['attendance_date'] ?? r['date'] ?? '').toString();
    final p = _int(r['present'] ?? r['present_count']);
    final t = _int(r['total'] ?? r['total_students']);
    final pct = t == 0 ? 0.0 : p * 100 / t;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Text('$n')),
        title: Text(
          subject,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          date.isEmpty ? '$p / $t present' : '$date • $p / $t present',
        ),
        trailing: Text(
          '${pct.toStringAsFixed(0)}%',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

// ============================================================
// FACULTY SESSION HISTORY + STUDENT DETAILS
// ============================================================
class FacultySessionHistoryPage extends StatefulWidget {
  final dynamic userId;

  const FacultySessionHistoryPage({super.key, required this.userId});

  @override
  State<FacultySessionHistoryPage> createState() =>
      _FacultySessionHistoryPageState();
}

class _FacultySessionHistoryPageState extends State<FacultySessionHistoryPage> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final response = await http.get(
        Uri.parse('$backendUrl/faculty/attendance-report/${widget.userId}'),
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}.');
      }

      final decoded = jsonDecode(response.body);

      final dynamic raw = decoded is List
          ? decoded
          : decoded is Map && decoded['reports'] is List
          ? decoded['reports']
          : decoded is Map && decoded['data'] is List
          ? decoded['data']
          : <dynamic>[];

      _reports = raw is List
          ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  // Safely converts the JSON "students" array into
  // List<Map<String, dynamic>>.
  List<Map<String, dynamic>> _studentList(dynamic value) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Completed attendance sessions',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),

                  ..._reports.asMap().entries.map((entry) {
                    final r = entry.value;

                    final subject =
                        (r['subject_name'] ??
                                r['subject'] ??
                                r['subject_code'] ??
                                'Session')
                            .toString();

                    final date = (r['attendance_date'] ?? r['date'] ?? '')
                        .toString();

                    // IMPORTANT:
                    // Convert List<dynamic> from JSON into
                    // List<Map<String, dynamic>> before passing
                    // it to the student details page.
                    final studentList = _studentList(r['students']);

                    final count = studentList.length;

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.event_note_rounded),
                        ),
                        title: Text(
                          subject,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          date.isEmpty ? 'Session ${entry.key + 1}' : date,
                        ),
                        trailing: Text(
                          '$count\nstudents',
                          textAlign: TextAlign.center,
                        ),
                        onTap: studentList.isNotEmpty
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        FacultySessionStudentDetailsPage(
                                          subject: subject,
                                          date: date,
                                          students: studentList,
                                        ),
                                  ),
                                );
                              }
                            : null,
                      ),
                    );
                  }),

                  if (_reports.isEmpty)
                    const Card(
                      elevation: 0,
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No session history is available yet.'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// FACULTY SESSION STUDENT DETAILS
// ============================================================
class FacultySessionStudentDetailsPage extends StatelessWidget {
  final String subject;
  final String date;
  final List<dynamic> students;
  const FacultySessionStudentDetailsPage({
    super.key,
    required this.subject,
    required this.date,
    required this.students,
  });
  @override
  Widget build(BuildContext context) {
    int present = 0, absent = 0, late = 0;
    for (final item in students) {
      if (item is! Map) continue;
      final status = (item['status'] ?? '').toString().toLowerCase();
      if (status == 'present')
        present++;
      else if (status == 'late')
        late++;
      else
        absent++;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Student Attendance Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (date.isNotEmpty) Text(date),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Present $present')),
                      Chip(label: Text('Late $late')),
                      Chip(label: Text('Absent $absent')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...students.whereType<Map>().map((raw) {
            final m = Map<String, dynamic>.from(raw);
            final name =
                (m['full_name'] ??
                        m['name'] ??
                        m['student_name'] ??
                        m['student_id'] ??
                        'Student')
                    .toString();
            final usn = (m['student_id'] ?? m['usn'] ?? '').toString();
            final status = (m['status'] ?? '').toString();
            final ok =
                status.toLowerCase() == 'present' ||
                status.toLowerCase() == 'late';
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    ok ? Icons.verified_rounded : Icons.person_outline_rounded,
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(usn.isEmpty ? status : '$usn • $status'),
                trailing: Icon(
                  ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ============================================================
// FACULTY NOTIFICATIONS
// ============================================================
class FacultyNotificationsPage extends StatelessWidget {
  final bool sessionActive;
  final int presentCount;
  final int rejectedCount;
  const FacultyNotificationsPage({
    super.key,
    required this.sessionActive,
    required this.presentCount,
    required this.rejectedCount,
  });
  @override
  Widget build(BuildContext context) {
    final items = <Map<String, dynamic>>[
      if (sessionActive)
        {
          'icon': Icons.play_circle_fill_rounded,
          'title': 'Attendance session is live',
          'subtitle': '$presentCount students currently marked.',
        },
      if (rejectedCount > 0)
        {
          'icon': Icons.warning_amber_rounded,
          'title': 'Attendance attempts rejected',
          'subtitle':
              '$rejectedCount rejection(s) reported by the current live session.',
        },
      {
        'icon': Icons.security_rounded,
        'title': 'Security protection active',
        'subtitle':
            'QR, GPS, mock-location, geofence and face verification remain enabled.',
      },
      {
        'icon': Icons.info_outline_rounded,
        'title': 'AntiProxy system',
        'subtitle':
            'Attendance actions are validated through the configured backend.',
      },
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (items.isEmpty)
            const Card(
              elevation: 0,
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No notifications.'),
              ),
            ),
          ...items.map(
            (item) => Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Icon(item['icon'] as IconData)),
                title: Text(
                  item['title'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(item['subtitle'] as String),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ADMIN DASHBOARD
// ============================================================

class AdminDashboard extends StatefulWidget {
  final List<CameraDescription> cameras;
  final dynamic userId;
  final String username;

  const AdminDashboard({
    super.key,
    required this.cameras,
    required this.userId,
    required this.username,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  Map<String, dynamic>? _adminData;

  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('auth_token');
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final token = await _getToken();

      if (token == null || token.isEmpty) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _errorMessage = 'Authentication token not found.';
        });

        return;
      }

      final response = await http.get(
        Uri.parse('$backendUrl/admin/dashboard'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _errorMessage =
              'Unable to load dashboard '
              '(${response.statusCode}).';
        });

        return;
      }

      final decoded = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _adminData = Map<String, dynamic>.from(decoded);

        _loading = false;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('Admin dashboard error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = 'Unable to connect to the backend server.';
      });
    }
  }

  int _overviewValue(String key) {
    final overview = _adminData?['overview'];

    if (overview is Map) {
      return int.tryParse(overview[key]?.toString() ?? '0') ?? 0;
    }

    return 0;
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('LOGOUT'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('auth_token');
    await prefs.remove('user_role');
    await prefs.remove('username');
    await prefs.remove('user_id');

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginPage(cameras: widget.cameras)),
      (route) => false,
    );
  }

  void _openDepartments() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminDepartmentsPage(cameras: widget.cameras),
      ),
    );
  }

  void _openStudents() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminStudentsPage(cameras: widget.cameras),
      ),
    );
  }

  void _openFaculty() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminFacultyPage(cameras: widget.cameras),
      ),
    );
  }

  void _openSubjects() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminSubjectsPage(cameras: widget.cameras),
      ),
    );
  }

  void _openSessions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminAttendanceSessionsPage(cameras: widget.cameras),
      ),
    );
  }

  void _openAttendanceRecords() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminAttendanceRecordsPage(cameras: widget.cameras),
      ),
    );
  }

  void _openUserManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminUserManagementPage(cameras: widget.cameras),
      ),
    );
  }

  void _openReports() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminReportsAnalyticsPage(cameras: widget.cameras),
      ),
    );
  }

  void _openSecurity() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminSecurityCenterPage(cameras: widget.cameras),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,

      appBar: AppBar(
        elevation: 0,
        titleSpacing: 20,
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _AdminErrorView(message: _errorMessage!, onRetry: _loadDashboard)
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _buildWelcomeCard(context),

                  const SizedBox(height: 26),

                  _buildSectionTitle(
                    context,
                    'Institution Overview',
                    'Monitor the institution at a glance',
                  ),

                  const SizedBox(height: 12),

                  _buildOverviewGrid(context),

                  const SizedBox(height: 28),

                  _buildSectionTitle(
                    context,
                    'Administration',
                    'Manage users, analytics and system security',
                  ),

                  const SizedBox(height: 12),

                  _AdminActionCard(
                    icon: Icons.people_alt_rounded,
                    title: 'User Management',
                    subtitle:
                        'Manage students, faculty and administrative users.',
                    onTap: _openUserManagement,
                  ),

                  _AdminActionCard(
                    icon: Icons.analytics_rounded,
                    title: 'Reports & Analytics',
                    subtitle: 'Review institutional attendance and activity.',
                    onTap: _openReports,
                  ),

                  _AdminActionCard(
                    icon: Icons.security_rounded,
                    title: 'Security Center',
                    subtitle:
                        'Review available AntiProxy security information.',
                    onTap: _openSecurity,
                  ),

                  const SizedBox(height: 20),

                  OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('LOGOUT'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildWelcomeCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.primaryContainer],
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 16,
            offset: const Offset(0, 7),
            color: Colors.black.withValues(alpha: 0.10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome, Administrator',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  widget.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  'Institution Administration Portal',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 1000 ? 3 : 2;

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,

          // IMPORTANT:
          // This replaces the old 1.25 ratio
          // which caused the 23px overflow.
          childAspectRatio: width < 400 ? 0.88 : 1.05,

          children: [
            _AdminOverviewCard(
              title: 'Departments',
              value: _overviewValue('total_departments'),
              icon: Icons.account_balance_rounded,
              onTap: _openDepartments,
            ),

            _AdminOverviewCard(
              title: 'Students',
              value: _overviewValue('total_students'),
              icon: Icons.school_rounded,
              onTap: _openStudents,
            ),

            _AdminOverviewCard(
              title: 'Faculty',
              value: _overviewValue('total_faculty'),
              icon: Icons.people_rounded,
              onTap: _openFaculty,
            ),

            _AdminOverviewCard(
              title: 'Subjects',
              value: _overviewValue('total_subjects'),
              icon: Icons.menu_book_rounded,
              onTap: _openSubjects,
            ),

            _AdminOverviewCard(
              title: 'Attendance Sessions',
              value: _overviewValue('total_sessions'),
              icon: Icons.event_available_rounded,
              onTap: _openSessions,
            ),

            _AdminOverviewCard(
              title: 'Attendance Records',
              value: _overviewValue('total_attendance_records'),
              icon: Icons.fact_check_rounded,
              onTap: _openAttendanceRecords,
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// ADMIN OVERVIEW CARD
// ============================================================

class _AdminOverviewCard extends StatelessWidget {
  final String title;
  final int value;
  final IconData icon;
  final VoidCallback onTap;

  const _AdminOverviewCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 24, color: colorScheme.primary),
                  ),

                  const Spacer(),

                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Text(
                value.toString(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),

              const SizedBox(height: 7),

              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),

              const SizedBox(height: 7),

              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'View  →',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
// ADMIN ACTION CARD
// ============================================================

class _AdminActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 27),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ADMIN ERROR VIEW
// ============================================================

class _AdminErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AdminErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 54,
                  color: Theme.of(context).colorScheme.primary,
                ),

                const SizedBox(height: 14),

                const Text(
                  'Unable to load dashboard',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),

                const SizedBox(height: 8),

                Text(message, textAlign: TextAlign.center),

                const SizedBox(height: 18),

                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('RETRY'),
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
// USER MANAGEMENT
// ============================================================

class AdminUserManagementPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminUserManagementPage({super.key, required this.cameras});

  @override
  State<AdminUserManagementPage> createState() =>
      _AdminUserManagementPageState();
}

class _AdminUserManagementPageState extends State<AdminUserManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = true;
  String? _error;

  List<dynamic> _students = [];
  List<dynamic> _faculty = [];
  List<dynamic> _administrators = [];

  String _studentSearch = '';
  String _facultySearch = '';

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);

    _loadUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token');

      if (token == null || token.isEmpty) {
        throw Exception('Authentication token not found.');
      }

      final response = await http.get(
        Uri.parse('$backendUrl/admin/users'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        throw Exception('Invalid response from server.');
      }

      if (decoded['success'] != true) {
        throw Exception(
          decoded['message']?.toString() ?? 'Unable to load users.',
        );
      }

      if (!mounted) return;

      setState(() {
        _students = List<dynamic>.from(decoded['students'] ?? []);

        _faculty = List<dynamic>.from(decoded['faculty'] ?? []);

        _administrators = List<dynamic>.from(decoded['administrators'] ?? []);

        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Admin users error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load user management data.';
      });
    }
  }

  List<dynamic> get _filteredStudents {
    final query = _studentSearch.trim().toLowerCase();

    if (query.isEmpty) {
      return _students;
    }

    return _students.where((student) {
      final values = [
        student['student_id'],
        student['full_name'],
        student['department'],
        student['semester'],
        student['division'],
        student['email'],
      ];

      return values.any(
        (value) => value?.toString().toLowerCase().contains(query) ?? false,
      );
    }).toList();
  }

  List<dynamic> get _filteredFaculty {
    final query = _facultySearch.trim().toLowerCase();

    if (query.isEmpty) {
      return _faculty;
    }

    return _faculty.where((faculty) {
      final values = [
        faculty['faculty_id'],
        faculty['full_name'],
        faculty['department'],
        faculty['email'],
      ];

      return values.any(
        (value) => value?.toString().toLowerCase().contains(query) ?? false,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,

      appBar: AppBar(
        title: const Text(
          'User Management',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadUsers,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(
              icon: const Icon(Icons.school_rounded),
              text: 'Students (${_students.length})',
            ),
            Tab(
              icon: const Icon(Icons.people_rounded),
              text: 'Faculty (${_faculty.length})',
            ),
            Tab(
              icon: const Icon(Icons.admin_panel_settings_rounded),
              text: 'Admins (${_administrators.length})',
            ),
          ],
        ),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _AdminErrorView(message: _error!, onRetry: _loadUsers)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStudentsTab(),
                _buildFacultyTab(),
                _buildAdminTab(),
              ],
            ),
    );
  }

  Widget _buildStudentsTab() {
    final students = _filteredStudents;

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _buildUserSummaryCard(
            icon: Icons.school_rounded,
            title: 'Student Directory',
            subtitle: 'View registered students across the institution.',
            count: _students.length,
          ),

          const SizedBox(height: 14),

          _buildSearchField(
            hintText: 'Search by USN, name, department, semester...',
            onChanged: (value) {
              setState(() {
                _studentSearch = value;
              });
            },
          ),

          const SizedBox(height: 14),

          if (students.isEmpty)
            const _AdminEmptyView(message: 'No students match your search.')
          else
            _buildStudentTable(students),
        ],
      ),
    );
  }

  Widget _buildFacultyTab() {
    final faculty = _filteredFaculty;

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _buildUserSummaryCard(
            icon: Icons.people_rounded,
            title: 'Faculty Directory',
            subtitle: 'View faculty members and department assignments.',
            count: _faculty.length,
          ),

          const SizedBox(height: 14),

          _buildSearchField(
            hintText: 'Search by faculty ID, name, department...',
            onChanged: (value) {
              setState(() {
                _facultySearch = value;
              });
            },
          ),

          const SizedBox(height: 14),

          if (faculty.isEmpty)
            const _AdminEmptyView(
              message: 'No faculty members match your search.',
            )
          else
            _buildFacultyTable(faculty),
        ],
      ),
    );
  }

  Widget _buildAdminTab() {
    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _buildUserSummaryCard(
            icon: Icons.admin_panel_settings_rounded,
            title: 'Administrators',
            subtitle: 'Administrative accounts currently registered.',
            count: _administrators.length,
          ),

          const SizedBox(height: 14),

          if (_administrators.isEmpty)
            const _AdminEmptyView(message: 'No administrators found.')
          else
            _buildAdminCards(),
        ],
      ),
    );
  }

  Widget _buildUserSummaryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: colorScheme.primary, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField({
    required String hintText,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
      ),
    );
  }

  Widget _buildStudentTable(List<dynamic> students) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 56,
          dataRowMinHeight: 58,
          dataRowMaxHeight: 76,
          horizontalMargin: 18,
          columnSpacing: 28,
          columns: const [
            DataColumn(label: Text('Sl. No.')),
            DataColumn(label: Text('USN')),
            DataColumn(label: Text('Student Name')),
            DataColumn(label: Text('Department')),
            DataColumn(label: Text('Sem')),
            DataColumn(label: Text('Div')),
            DataColumn(label: Text('Face')),
            DataColumn(label: Text('Details')),
          ],
          rows: students.asMap().entries.map((entry) {
            final index = entry.key;
            final student = Map<String, dynamic>.from(entry.value);

            final faceRegistered =
                student['face_registered'] == 1 ||
                student['face_registered'] == true;

            return DataRow(
              cells: [
                DataCell(Text('${index + 1}')),
                DataCell(
                  Text(
                    student['student_id']?.toString() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataCell(Text(student['full_name']?.toString() ?? '-')),
                DataCell(
                  SizedBox(
                    width: 190,
                    child: Text(
                      student['department']?.toString() ?? '-',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(student['semester']?.toString() ?? '-')),
                DataCell(Text(student['division']?.toString() ?? '-')),
                DataCell(
                  _statusChip(
                    faceRegistered ? 'Registered' : 'Not Registered',
                    faceRegistered,
                  ),
                ),
                DataCell(
                  IconButton(
                    tooltip: 'View details',
                    onPressed: () {
                      _showStudentDetails(student);
                    },
                    icon: const Icon(Icons.visibility_rounded),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFacultyTable(List<dynamic> faculty) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 56,
          dataRowMinHeight: 58,
          dataRowMaxHeight: 76,
          horizontalMargin: 18,
          columnSpacing: 28,
          columns: const [
            DataColumn(label: Text('Sl. No.')),
            DataColumn(label: Text('Faculty ID')),
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Department')),
            DataColumn(label: Text('Email')),
            DataColumn(label: Text('Details')),
          ],
          rows: faculty.asMap().entries.map((entry) {
            final index = entry.key;
            final member = Map<String, dynamic>.from(entry.value);

            return DataRow(
              cells: [
                DataCell(Text('${index + 1}')),
                DataCell(
                  Text(
                    member['faculty_id']?.toString() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataCell(Text(member['full_name']?.toString() ?? '-')),
                DataCell(
                  SizedBox(
                    width: 200,
                    child: Text(
                      member['department']?.toString() ?? '-',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(member['email']?.toString() ?? '-')),
                DataCell(
                  IconButton(
                    tooltip: 'View details',
                    onPressed: () {
                      _showFacultyDetails(member);
                    },
                    icon: const Icon(Icons.visibility_rounded),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAdminCards() {
    return Column(
      children: _administrators.map<Widget>((item) {
        final admin = Map<String, dynamic>.from(item);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            leading: CircleAvatar(
              child: const Icon(Icons.admin_panel_settings_rounded),
            ),
            title: Text(
              admin['username']?.toString() ?? '-',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'Role: ${admin['role'] ?? '-'}\n'
                'Created: ${admin['created_at'] ?? '-'}',
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _statusChip(String label, bool positive) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: positive
            ? colorScheme.primary.withValues(alpha: 0.10)
            : colorScheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: positive ? colorScheme.primary : colorScheme.error,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  void _showStudentDetails(Map<String, dynamic> student) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _AdminDetailsSheet(
          title: 'Student Details',
          icon: Icons.school_rounded,
          items: [
            _AdminDetailItem('USN', student['student_id']),
            _AdminDetailItem('Name', student['full_name']),
            _AdminDetailItem('Username', student['username']),
            _AdminDetailItem('Department', student['department']),
            _AdminDetailItem('Semester', student['semester']),
            _AdminDetailItem('Division', student['division']),
            _AdminDetailItem('Email', student['email']),
            _AdminDetailItem(
              'Face Registered',
              student['face_registered'] == 1 ? 'Yes' : 'No',
            ),
            _AdminDetailItem('Created', student['created_at']),
          ],
        );
      },
    );
  }

  void _showFacultyDetails(Map<String, dynamic> faculty) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _AdminDetailsSheet(
          title: 'Faculty Details',
          icon: Icons.people_rounded,
          items: [
            _AdminDetailItem('Faculty ID', faculty['faculty_id']),
            _AdminDetailItem('Name', faculty['full_name']),
            _AdminDetailItem('Username', faculty['username']),
            _AdminDetailItem('Department', faculty['department']),
            _AdminDetailItem('Email', faculty['email']),
            _AdminDetailItem('Created', faculty['created_at']),
          ],
        );
      },
    );
  }
}

// ============================================================
// REPORTS & ANALYTICS
// ============================================================

class AdminReportsAnalyticsPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminReportsAnalyticsPage({super.key, required this.cameras});

  @override
  State<AdminReportsAnalyticsPage> createState() =>
      _AdminReportsAnalyticsPageState();
}

class _AdminReportsAnalyticsPageState extends State<AdminReportsAnalyticsPage> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token');

      if (token == null || token.isEmpty) {
        throw Exception('Authentication token not found.');
      }

      final response = await http.get(
        Uri.parse('$backendUrl/admin/dashboard'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        throw Exception('Invalid analytics response.');
      }

      if (!mounted) return;

      setState(() {
        _data = Map<String, dynamic>.from(decoded);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Admin reports error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load reports and analytics.';
      });
    }
  }

  int _number(String key) {
    final overview = _data['overview'];

    if (overview is Map) {
      return int.tryParse(overview[key]?.toString() ?? '0') ?? 0;
    }

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reports & Analytics',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadReports,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _AdminErrorView(message: _error!, onRetry: _loadReports)
          : RefreshIndicator(
              onRefresh: _loadReports,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _buildHeader(),

                  const SizedBox(height: 18),

                  _buildStatsGrid(),

                  const SizedBox(height: 28),

                  _buildSectionHeader(
                    'Department Summary',
                    'Current academic structure and population.',
                  ),

                  const SizedBox(height: 12),

                  _buildDepartments(),

                  const SizedBox(height: 28),

                  _buildSectionHeader(
                    'Recent Attendance Sessions',
                    'Latest sessions recorded by the system.',
                  ),

                  const SizedBox(height: 12),

                  _buildRecentSessions(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.analytics_rounded,
                color: colorScheme.primary,
                size: 29,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Institutional Analytics',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'A consolidated view of departments, users, subjects and attendance activity.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 850
            ? 3
            : constraints.maxWidth >= 520
            ? 2
            : 1;

        final stats = [
          (
            'Departments',
            _number('total_departments'),
            Icons.account_balance_rounded,
          ),
          ('Students', _number('total_students'), Icons.school_rounded),
          ('Faculty', _number('total_faculty'), Icons.people_rounded),
          ('Subjects', _number('total_subjects'), Icons.menu_book_rounded),
          (
            'Sessions',
            _number('total_sessions'),
            Icons.event_available_rounded,
          ),
          (
            'Attendance Records',
            _number('total_attendance_records'),
            Icons.fact_check_rounded,
          ),
        ];

        return GridView.builder(
          itemCount: stats.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 128,
          ),
          itemBuilder: (context, index) {
            final item = stats[index];

            return _AnalyticsStatCard(
              title: item.$1,
              value: item.$2,
              icon: item.$3,
            );
          },
        );
      },
    );
  }

  Widget _buildDepartments() {
    // Backend now provides department_overview.
    // The legacy "departments" field is retained as fallback.
    final raw = _data['department_overview'] ?? _data['departments'];

    if (raw is! List || raw.isEmpty) {
      return const _AdminEmptyView(
        message: 'No department analytics available.',
      );
    }

    return Column(
      children: raw.map<Widget>((item) {
        final department = Map<String, dynamic>.from(item);

        final students =
            int.tryParse(
              (department['total_students'] ?? department['student_count'] ?? 0)
                  .toString(),
            ) ??
            0;

        final faculty =
            int.tryParse(
              (department['total_faculty'] ??
                      department['total_teachers'] ??
                      department['faculty_count'] ??
                      0)
                  .toString(),
            ) ??
            0;

        final subjects =
            int.tryParse(
              (department['total_subjects'] ?? department['subject_count'] ?? 0)
                  .toString(),
            ) ??
            0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      child: const Icon(Icons.account_balance_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            department['department_name']?.toString() ?? '-',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Code: ${department['department_code'] ?? '-'}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 500 ? 3 : 1;

                    if (columns == 1) {
                      return Column(
                        children: [
                          _buildDepartmentMetric(
                            Icons.school_rounded,
                            'Students',
                            students,
                          ),
                          const SizedBox(height: 8),
                          _buildDepartmentMetric(
                            Icons.people_rounded,
                            'Faculty',
                            faculty,
                          ),
                          const SizedBox(height: 8),
                          _buildDepartmentMetric(
                            Icons.menu_book_rounded,
                            'Subjects',
                            subjects,
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          child: _buildDepartmentMetric(
                            Icons.school_rounded,
                            'Students',
                            students,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildDepartmentMetric(
                            Icons.people_rounded,
                            'Faculty',
                            faculty,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildDepartmentMetric(
                            Icons.menu_book_rounded,
                            'Subjects',
                            subjects,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDepartmentMetric(IconData icon, String label, int value) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 21, color: colorScheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSessions() {
    final raw = _data['recent_sessions'];

    if (raw is! List || raw.isEmpty) {
      return const _AdminEmptyView(message: 'No recent sessions available.');
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 54,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 72,
          columnSpacing: 26,
          horizontalMargin: 16,
          columns: const [
            DataColumn(label: Text('Session')),
            DataColumn(label: Text('Subject')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Faculty')),
            DataColumn(label: Text('Division')),
            DataColumn(label: Text('Status')),
          ],
          rows: raw.map<DataRow>((item) {
            final session = Map<String, dynamic>.from(item);

            final status = session['status']?.toString() ?? '-';

            final isActive = status.toLowerCase() == 'active';

            return DataRow(
              cells: [
                DataCell(
                  Text(
                    '#${session['id'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataCell(Text(session['subject_code']?.toString() ?? '-')),
                DataCell(Text(session['attendance_date']?.toString() ?? '-')),
                DataCell(Text(session['faculty_name']?.toString() ?? '-')),
                DataCell(
                  Text(
                    '${session['semester'] ?? '-'} / ${session['division'] ?? '-'}',
                  ),
                ),
                DataCell(_sessionStatusChip(status, isActive)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _sessionStatusChip(String status, bool active) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? colorScheme.primary.withValues(alpha: 0.10)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ============================================================
// SECURITY CENTER
// ============================================================

class AdminSecurityCenterPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminSecurityCenterPage({super.key, required this.cameras});

  @override
  State<AdminSecurityCenterPage> createState() =>
      _AdminSecurityCenterPageState();
}

class _AdminSecurityCenterPageState extends State<AdminSecurityCenterPage> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic> _securityData = {};

  @override
  void initState() {
    super.initState();
    _loadSecurity();
  }

  Future<void> _loadSecurity() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token');

      if (token == null || token.isEmpty) {
        throw Exception('Authentication token not found.');
      }

      final response = await http.get(
        Uri.parse('$backendUrl/admin/security'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Security endpoint returned '
          '${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        throw Exception('Invalid security response.');
      }

      if (!mounted) return;

      setState(() {
        _securityData = Map<String, dynamic>.from(decoded);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Admin security error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load security information.';
      });
    }
  }

  int _securityNumber(String key) {
    dynamic value = _securityData[key];

    // Also support a nested security object if the backend
    // returns one in a future version.
    if (value == null && _securityData['security'] is Map) {
      value = _securityData['security'][key];
    }

    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Security Center',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadSecurity,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _AdminErrorView(message: _error!, onRetry: _loadSecurity)
          : RefreshIndicator(
              onRefresh: _loadSecurity,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _buildSecurityHeader(),

                  const SizedBox(height: 18),

                  _buildSecurityStats(),

                  const SizedBox(height: 24),

                  _buildSecurityOverview(),

                  const SizedBox(height: 20),

                  _buildSecurityNote(),
                ],
              ),
            ),
    );
  }

  Widget _buildSecurityHeader() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                Icons.verified_user_rounded,
                size: 30,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AntiProxy Security',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Security and attendance-verification information reported by the AntiProxy system.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityStats() {
    final total = _securityNumber('total_records');

    final present = _securityNumber('present_records');

    final faceVerified = _securityNumber('face_verified_records');

    final late = _securityNumber('late_records');

    final verificationRate = total > 0 ? (faceVerified / total * 100) : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 850
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;

        final cards = [
          _SecurityMetric(
            title: 'Total Records',
            value: total,
            icon: Icons.fact_check_rounded,
          ),
          _SecurityMetric(
            title: 'Face Verified',
            value: faceVerified,
            icon: Icons.face_retouching_natural_rounded,
          ),
          _SecurityMetric(
            title: 'Present',
            value: present,
            icon: Icons.check_circle_rounded,
          ),
          _SecurityMetric(
            title: 'Late',
            value: late,
            icon: Icons.schedule_rounded,
          ),
        ];

        return GridView.builder(
          itemCount: cards.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 126,
          ),
          itemBuilder: (context, index) {
            final metric = cards[index];

            return _SecurityMetricCard(metric: metric);
          },
        );
      },
    );
  }

  Widget _buildSecurityOverview() {
    final total = _securityNumber('total_records');

    final faceVerified = _securityNumber('face_verified_records');

    final present = _securityNumber('present_records');

    final late = _securityNumber('late_records');

    final verificationRate = total > 0 ? faceVerified / total : 0.0;

    final attendanceRate = total > 0 ? present / total : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Security Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 18),

            _buildProgressRow(
              title: 'Face Verification',
              value: verificationRate,
              label: '${(verificationRate * 100).toStringAsFixed(1)}%',
              icon: Icons.face_retouching_natural_rounded,
            ),

            const SizedBox(height: 18),

            _buildProgressRow(
              title: 'Present Attendance',
              value: attendanceRate,
              label: '${(attendanceRate * 100).toStringAsFixed(1)}%',
              icon: Icons.check_circle_outline_rounded,
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 21,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Late Attendance Records',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  late.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRow({
    required String title,
    required double value,
    required String label,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 21, color: colorScheme.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 9),

        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 9,
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityNote() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'These statistics are generated from attendance records currently available to the AntiProxy administration system.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ADMIN UI SUPPORT WIDGETS
// ============================================================

class _AdminDetailItem {
  final String label;
  final dynamic value;

  const _AdminDetailItem(this.label, this.value);
}

class _AdminDetailsSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_AdminDetailItem> items;

  const _AdminDetailsSheet({
    required this.title,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 25, child: Icon(icon)),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              ...items.map((item) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.value?.toString() ?? '-',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsStatCard extends StatelessWidget {
  final String title;
  final int value;
  final IconData icon;

  const _AnalyticsStatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colorScheme.primary, size: 22),
            ),
            const Spacer(),
            Text(
              value.toString(),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityMetric {
  final String title;
  final int value;
  final IconData icon;

  const _SecurityMetric({
    required this.title,
    required this.value,
    required this.icon,
  });
}

class _SecurityMetricCard extends StatelessWidget {
  final _SecurityMetric metric;

  const _SecurityMetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(metric.icon, color: colorScheme.primary, size: 22),
            ),
            const Spacer(),
            Text(
              metric.value.toString(),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            Text(
              metric.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// EMPTY STATE
// ============================================================

class _AdminEmptyView extends StatelessWidget {
  final String message;

  const _AdminEmptyView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ADMIN DEPARTMENTS PAGE
// ============================================================

class AdminDepartmentsPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminDepartmentsPage({super.key, required this.cameras});

  @override
  State<AdminDepartmentsPage> createState() => _AdminDepartmentsPageState();
}

class _AdminDepartmentsPageState extends State<AdminDepartmentsPage> {
  bool _loading = true;
  String? _error;
  List<dynamic> _departments = [];

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token');

      final response = await http.get(
        Uri.parse('$backendUrl/admin/departments/details'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _departments = data['departments'] ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Failed to load departments.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Departments')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _loadDepartments)
          : _departments.isEmpty
          ? const _EmptyView(message: 'No departments found.')
          : RefreshIndicator(
              onRefresh: _loadDepartments,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Department Information',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Sl. No.')),
                        DataColumn(label: Text('Department ID')),
                        DataColumn(label: Text('Department Name')),
                        DataColumn(label: Text('Teachers')),
                        DataColumn(label: Text('Students')),
                      ],
                      rows: List.generate(_departments.length, (index) {
                        final department = _departments[index];

                        return DataRow(
                          cells: [
                            DataCell(Text('${index + 1}')),
                            DataCell(
                              Text(
                                department['department_id']?.toString() ?? '-',
                              ),
                            ),
                            DataCell(
                              Text(
                                department['department_name']?.toString() ??
                                    '-',
                              ),
                            ),
                            DataCell(
                              Text(
                                department['total_teachers']?.toString() ?? '0',
                              ),
                            ),
                            DataCell(
                              Text(
                                department['total_students']?.toString() ?? '0',
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// ADMIN STUDENTS PAGE
// ============================================================

class AdminStudentsPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminStudentsPage({super.key, required this.cameras});

  @override
  State<AdminStudentsPage> createState() => _AdminStudentsPageState();
}

class _AdminStudentsPageState extends State<AdminStudentsPage> {
  bool _loadingDepartments = true;

  List<dynamic> _departments = [];

  String? _selectedDepartment;
  int? _selectedSemester;
  String? _selectedDivision;

  List<dynamic> _groups = [];
  List<dynamic> _students = [];

  bool _loadingGroups = false;
  bool _loadingStudents = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('auth_token');
  }

  Future<void> _loadDepartments() async {
    try {
      final token = await _token();

      final response = await http.get(
        Uri.parse('$backendUrl/admin/students/departments'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _departments = data['departments'] ?? [];
        _loadingDepartments = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingDepartments = false;
        _error = 'Failed to load departments.';
      });
    }
  }

  Future<void> _loadGroups(String department) async {
    setState(() {
      _selectedDepartment = department;
      _selectedSemester = null;
      _selectedDivision = null;
      _groups = [];
      _students = [];
      _loadingGroups = true;
      _error = null;
    });

    try {
      final token = await _token();

      final uri = Uri.parse(
        '$backendUrl/admin/students/groups',
      ).replace(queryParameters: {'department': department});

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _groups = data['groups'] ?? [];
        _loadingGroups = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingGroups = false;
        _error = 'Failed to load semester/division.';
      });
    }
  }

  Future<void> _loadStudents() async {
    if (_selectedDepartment == null ||
        _selectedSemester == null ||
        _selectedDivision == null) {
      return;
    }

    setState(() {
      _loadingStudents = true;
      _students = [];
      _error = null;
    });

    try {
      final token = await _token();

      final uri = Uri.parse('$backendUrl/admin/students/list').replace(
        queryParameters: {
          'department': _selectedDepartment!,
          'semester': _selectedSemester!.toString(),
          'division': _selectedDivision!,
        },
      );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _students = data['students'] ?? [];
        _loadingStudents = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingStudents = false;
        _error = 'Failed to load students.';
      });
    }
  }

  Future<void> _showStudentDetails(int studentId) async {
    try {
      final token = await _token();

      final response = await http.get(
        Uri.parse('$backendUrl/admin/students/$studentId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      final student = Map<String, dynamic>.from(data['student'] ?? {});

      await showDialog(
        context: context,
        builder: (_) {
          return _AdminDetailsDialog(title: 'Student Details', data: student);
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load student details.')),
      );
    }
  }

  String _semesterRoman(dynamic value) {
    final semester = int.tryParse(value.toString());

    const roman = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII'];

    if (semester != null && semester > 0 && semester < roman.length) {
      return roman[semester];
    }

    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Management')),
      body: _loadingDepartments
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _departments.isEmpty
          ? _ErrorView(message: _error!, onRetry: _loadDepartments)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Select Department',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  initialValue: _selectedDepartment,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Department',
                  ),
                  items: _departments.map<DropdownMenuItem<String>>((
                    department,
                  ) {
                    final name = department['department']?.toString() ?? '';

                    return DropdownMenuItem(value: name, child: Text(name));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _loadGroups(value);
                    }
                  },
                ),

                const SizedBox(height: 24),

                if (_loadingGroups)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingGroups && _groups.isNotEmpty) ...[
                  const Text(
                    'Semester - Division',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _groups.map<Widget>((group) {
                      final semester =
                          int.tryParse(group['semester'].toString()) ?? 0;

                      final division = group['division']?.toString() ?? '';

                      final selected =
                          _selectedSemester == semester &&
                          _selectedDivision == division;

                      return ChoiceChip(
                        selected: selected,
                        label: Text(
                          'Sem : '
                          '${_semesterRoman(semester)}  '
                          'Division : $division',
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selectedSemester = semester;
                            _selectedDivision = division;
                          });

                          _loadStudents();
                        },
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 24),

                if (_loadingStudents)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingStudents && _selectedDivision != null)
                  _buildStudentTable(),
              ],
            ),
    );
  }

  Widget _buildStudentTable() {
    if (_students.isEmpty) {
      return const _EmptyView(
        message: 'No students found for the selected group.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Students',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Sl. No.')),
              DataColumn(label: Text('USN')),
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Details')),
            ],
            rows: List.generate(_students.length, (index) {
              final student = _students[index];

              final id = int.tryParse(student['id'].toString());

              return DataRow(
                cells: [
                  DataCell(Text('${index + 1}')),
                  DataCell(Text(student['student_id']?.toString() ?? '-')),
                  DataCell(Text(student['full_name']?.toString() ?? '-')),
                  DataCell(
                    InkWell(
                      onTap: id == null ? null : () => _showStudentDetails(id),
                      child: const Text(
                        'Details',
                        style: TextStyle(
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ADMIN FACULTY PAGE
// ============================================================

class AdminFacultyPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminFacultyPage({super.key, required this.cameras});

  @override
  State<AdminFacultyPage> createState() => _AdminFacultyPageState();
}

class _AdminFacultyPageState extends State<AdminFacultyPage> {
  bool _loading = true;
  bool _loadingFaculty = false;

  List<dynamic> _departments = [];
  List<dynamic> _faculty = [];

  String? _selectedDepartment;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('auth_token');
  }

  Future<void> _loadDepartments() async {
    try {
      final token = await _token();

      final response = await http.get(
        Uri.parse('$backendUrl/admin/faculty/departments'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _departments = data['departments'] ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Failed to load departments.';
      });
    }
  }

  Future<void> _loadFaculty(String department) async {
    setState(() {
      _selectedDepartment = department;
      _loadingFaculty = true;
      _faculty = [];
    });

    try {
      final token = await _token();

      final uri = Uri.parse(
        '$backendUrl/admin/faculty/list',
      ).replace(queryParameters: {'department': department});

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _faculty = data['faculty'] ?? [];
        _loadingFaculty = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingFaculty = false;
        _error = 'Failed to load faculty.';
      });
    }
  }

  Future<void> _showFacultyDetails(int facultyId) async {
    try {
      final token = await _token();

      final response = await http.get(
        Uri.parse('$backendUrl/admin/faculty/$facultyId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      final faculty = Map<String, dynamic>.from(data['faculty'] ?? {});

      await showDialog(
        context: context,
        builder: (_) {
          return _AdminDetailsDialog(title: 'Faculty Details', data: faculty);
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load faculty details.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Faculty Management')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _departments.isEmpty
          ? _ErrorView(message: _error!, onRetry: _loadDepartments)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Select Department',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  initialValue: _selectedDepartment,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Department',
                  ),
                  items: _departments.map<DropdownMenuItem<String>>((
                    department,
                  ) {
                    final name = department['department']?.toString() ?? '';

                    return DropdownMenuItem(value: name, child: Text(name));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _loadFaculty(value);
                    }
                  },
                ),

                const SizedBox(height: 24),

                if (_loadingFaculty)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingFaculty && _selectedDepartment != null)
                  _buildFacultyTable(),
              ],
            ),
    );
  }

  Widget _buildFacultyTable() {
    if (_faculty.isEmpty) {
      return const _EmptyView(message: 'No faculty members found.');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Sl. No.')),
          DataColumn(label: Text('Faculty ID')),
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Email')),
          DataColumn(label: Text('Details')),
        ],
        rows: List.generate(_faculty.length, (index) {
          final faculty = _faculty[index];

          final id = int.tryParse(faculty['id'].toString());

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(faculty['faculty_id']?.toString() ?? '-')),
              DataCell(Text(faculty['full_name']?.toString() ?? '-')),
              DataCell(Text(faculty['email']?.toString() ?? '-')),
              DataCell(
                InkWell(
                  onTap: id == null ? null : () => _showFacultyDetails(id),
                  child: const Text(
                    'Details',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ============================================================
// ADMIN SUBJECTS PAGE
// ============================================================

class AdminSubjectsPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminSubjectsPage({super.key, required this.cameras});

  @override
  State<AdminSubjectsPage> createState() => _AdminSubjectsPageState();
}

class _AdminSubjectsPageState extends State<AdminSubjectsPage> {
  bool _loadingDepartments = true;
  bool _loadingGroups = false;
  bool _loadingSubjects = false;

  List<dynamic> _departments = [];
  List<dynamic> _groups = [];
  List<dynamic> _subjects = [];

  int? _selectedDepartmentId;
  int? _selectedSemester;
  String? _selectedDivision;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('auth_token');
  }

  Future<void> _loadDepartments() async {
    try {
      final token = await _token();

      final response = await http.get(
        Uri.parse('$backendUrl/admin/subjects/departments'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _departments = data['departments'] ?? [];
        _loadingDepartments = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingDepartments = false;
        _error = 'Failed to load departments.';
      });
    }
  }

  Future<void> _loadGroups(int departmentId) async {
    setState(() {
      _selectedDepartmentId = departmentId;
      _selectedSemester = null;
      _selectedDivision = null;
      _groups = [];
      _subjects = [];
      _loadingGroups = true;
    });

    try {
      final token = await _token();

      final uri = Uri.parse(
        '$backendUrl/admin/subjects/groups',
      ).replace(queryParameters: {'department_id': departmentId.toString()});

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _groups = data['groups'] ?? [];
        _loadingGroups = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingGroups = false;
        _error = 'Failed to load groups.';
      });
    }
  }

  Future<void> _loadSubjects() async {
    if (_selectedDepartmentId == null ||
        _selectedSemester == null ||
        _selectedDivision == null) {
      return;
    }

    setState(() {
      _loadingSubjects = true;
      _subjects = [];
    });

    try {
      final token = await _token();

      final uri = Uri.parse('$backendUrl/admin/subjects/list').replace(
        queryParameters: {
          'department_id': _selectedDepartmentId!.toString(),
          'semester': _selectedSemester!.toString(),
          'division': _selectedDivision!,
        },
      );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _subjects = data['subjects'] ?? [];
        _loadingSubjects = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingSubjects = false;
        _error = 'Failed to load subjects.';
      });
    }
  }

  String _semesterRoman(dynamic value) {
    final semester = int.tryParse(value.toString());

    const roman = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII'];

    if (semester != null && semester > 0 && semester < roman.length) {
      return roman[semester];
    }

    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subject Management')),
      body: _loadingDepartments
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Select Department',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<int>(
                  initialValue: _selectedDepartmentId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Department',
                  ),
                  items: _departments.map<DropdownMenuItem<int>>((department) {
                    final id = int.tryParse(
                      department['department_id'].toString(),
                    );

                    return DropdownMenuItem(
                      value: id,
                      child: Text(
                        department['department_name']?.toString() ?? '-',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _loadGroups(value);
                    }
                  },
                ),

                const SizedBox(height: 24),

                if (_loadingGroups)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingGroups && _groups.isNotEmpty) ...[
                  const Text(
                    'Semester - Division',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _groups.map<Widget>((group) {
                      final semester =
                          int.tryParse(group['semester'].toString()) ?? 0;

                      final division = group['division']?.toString() ?? '';

                      return ChoiceChip(
                        selected:
                            _selectedSemester == semester &&
                            _selectedDivision == division,
                        label: Text(
                          'Sem : '
                          '${_semesterRoman(semester)}  '
                          'Division : $division',
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selectedSemester = semester;
                            _selectedDivision = division;
                          });

                          _loadSubjects();
                        },
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 24),

                if (_loadingSubjects)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingSubjects && _selectedDivision != null)
                  _buildSubjectTable(),
              ],
            ),
    );
  }

  Widget _buildSubjectTable() {
    if (_subjects.isEmpty) {
      return const _EmptyView(
        message: 'No subjects found for the selected group.',
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Sl. No.')),
          DataColumn(label: Text('Subject Code')),
          DataColumn(label: Text('Subject Name')),
          DataColumn(label: Text('Faculty Handling')),
        ],
        rows: List.generate(_subjects.length, (index) {
          final subject = _subjects[index];

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(subject['subject_code']?.toString() ?? '-')),
              DataCell(Text(subject['subject_name']?.toString() ?? '-')),
              DataCell(
                Text(subject['faculty_handling']?.toString() ?? 'Not assigned'),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ============================================================
// ADMIN ATTENDANCE SESSIONS PAGE
// ============================================================

class AdminAttendanceSessionsPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminAttendanceSessionsPage({super.key, required this.cameras});

  @override
  State<AdminAttendanceSessionsPage> createState() =>
      _AdminAttendanceSessionsPageState();
}

class _AdminAttendanceSessionsPageState
    extends State<AdminAttendanceSessionsPage> {
  bool _loadingDepartments = true;
  bool _loadingGroups = false;
  bool _loadingSubjects = false;
  bool _loadingSessions = false;

  List<dynamic> _departments = [];
  List<dynamic> _groups = [];
  List<dynamic> _subjects = [];
  List<dynamic> _sessions = [];

  int? _departmentId;
  int? _semester;
  String? _division;
  String? _subjectCode;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('auth_token');
  }

  Future<void> _loadDepartments() async {
    try {
      final token = await _token();

      final response = await http.get(
        Uri.parse('$backendUrl/admin/attendance-sessions/departments'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _departments = data['departments'] ?? [];
        _loadingDepartments = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingDepartments = false;
        _error = 'Failed to load departments.';
      });
    }
  }

  Future<void> _loadGroups(int departmentId) async {
    setState(() {
      _departmentId = departmentId;
      _semester = null;
      _division = null;
      _subjectCode = null;

      _groups = [];
      _subjects = [];
      _sessions = [];

      _loadingGroups = true;
    });

    try {
      final token = await _token();

      final uri = Uri.parse(
        '$backendUrl/admin/attendance-sessions/groups',
      ).replace(queryParameters: {'department_id': departmentId.toString()});

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _groups = data['groups'] ?? [];
        _loadingGroups = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingGroups = false;
        _error = 'Failed to load groups.';
      });
    }
  }

  Future<void> _loadSubjects() async {
    if (_departmentId == null || _semester == null || _division == null) {
      return;
    }

    setState(() {
      _loadingSubjects = true;
      _subjects = [];
      _subjectCode = null;
      _sessions = [];
    });

    try {
      final token = await _token();

      final uri = Uri.parse('$backendUrl/admin/attendance-sessions/subjects')
          .replace(
            queryParameters: {
              'department_id': _departmentId!.toString(),
              'semester': _semester!.toString(),
              'division': _division!,
            },
          );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _subjects = data['subjects'] ?? [];
        _loadingSubjects = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingSubjects = false;
        _error = 'Failed to load subjects.';
      });
    }
  }

  Future<void> _loadSessions(String subjectCode) async {
    if (_departmentId == null || _semester == null || _division == null) {
      return;
    }

    setState(() {
      _subjectCode = subjectCode;
      _loadingSessions = true;
      _sessions = [];
    });

    try {
      final token = await _token();

      final uri = Uri.parse('$backendUrl/admin/attendance-sessions/list')
          .replace(
            queryParameters: {
              'department_id': _departmentId!.toString(),
              'semester': _semester!.toString(),
              'division': _division!,
              'subject_code': subjectCode,
            },
          );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _sessions = data['sessions'] ?? [];
        _loadingSessions = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingSessions = false;
        _error = 'Failed to load sessions.';
      });
    }
  }

  String _semesterRoman(dynamic value) {
    final semester = int.tryParse(value.toString());

    const roman = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII'];

    if (semester != null && semester > 0 && semester < roman.length) {
      return roman[semester];
    }

    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Sessions')),
      body: _loadingDepartments
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Department',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<int>(
                  initialValue: _departmentId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Select Department',
                  ),
                  items: _departments.map<DropdownMenuItem<int>>((department) {
                    final id = int.tryParse(
                      department['department_id'].toString(),
                    );

                    return DropdownMenuItem(
                      value: id,
                      child: Text(
                        department['department_name']?.toString() ?? '-',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _loadGroups(value);
                    }
                  },
                ),

                const SizedBox(height: 22),

                if (_loadingGroups)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingGroups && _groups.isNotEmpty) ...[
                  const Text(
                    'Semester - Division',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _groups.map<Widget>((group) {
                      final semester =
                          int.tryParse(group['semester'].toString()) ?? 0;

                      final division = group['division']?.toString() ?? '';

                      return ChoiceChip(
                        selected:
                            _semester == semester && _division == division,
                        label: Text(
                          'Sem : '
                          '${_semesterRoman(semester)}  '
                          'Division : $division',
                        ),
                        onSelected: (_) {
                          setState(() {
                            _semester = semester;
                            _division = division;
                          });

                          _loadSubjects();
                        },
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 22),

                if (_loadingSubjects)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingSubjects && _subjects.isNotEmpty) ...[
                  const Text(
                    'Subject',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  DropdownButtonFormField<String>(
                    initialValue: _subjectCode,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Select Subject',
                    ),
                    items: _subjects.map<DropdownMenuItem<String>>((subject) {
                      final code = subject['subject_code']?.toString() ?? '';

                      final name = subject['subject_name']?.toString() ?? '';

                      return DropdownMenuItem(
                        value: code,
                        child: Text('$code - $name'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _loadSessions(value);
                      }
                    },
                  ),
                ],

                const SizedBox(height: 24),

                if (_loadingSessions)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingSessions && _subjectCode != null)
                  _buildSessionsTable(),
              ],
            ),
    );
  }

  Widget _buildSessionsTable() {
    if (_sessions.isEmpty) {
      return const _EmptyView(message: 'No attendance sessions found.');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Sl. No.')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Subject')),
          DataColumn(label: Text('Session ID')),
          DataColumn(label: Text('Faculty')),
          DataColumn(label: Text('Start')),
          DataColumn(label: Text('End')),
          DataColumn(label: Text('Status')),
        ],
        rows: List.generate(_sessions.length, (index) {
          final session = _sessions[index];

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(session['attendance_date']?.toString() ?? '-')),
              DataCell(Text(session['subject_code']?.toString() ?? '-')),
              DataCell(Text(session['id']?.toString() ?? '-')),
              DataCell(Text(session['faculty_name']?.toString() ?? '-')),
              DataCell(Text(session['start_time']?.toString() ?? '-')),
              DataCell(Text(session['end_time']?.toString() ?? '-')),
              DataCell(Text(session['status']?.toString() ?? '-')),
            ],
          );
        }),
      ),
    );
  }
}

// ============================================================
// ADMIN ATTENDANCE RECORDS PAGE
// ============================================================

class AdminAttendanceRecordsPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminAttendanceRecordsPage({super.key, required this.cameras});

  @override
  State<AdminAttendanceRecordsPage> createState() =>
      _AdminAttendanceRecordsPageState();
}

class _AdminAttendanceRecordsPageState
    extends State<AdminAttendanceRecordsPage> {
  bool _loadingDepartments = true;
  bool _loadingGroups = false;
  bool _loadingSubjects = false;
  bool _loadingRecords = false;

  List<dynamic> _departments = [];
  List<dynamic> _groups = [];
  List<dynamic> _subjects = [];
  List<dynamic> _records = [];

  int? _departmentId;
  int? _semester;
  String? _division;
  String? _subjectCode;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('auth_token');
  }

  Future<void> _loadDepartments() async {
    try {
      final token = await _token();

      final response = await http.get(
        Uri.parse('$backendUrl/admin/attendance-records/departments'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _departments = data['departments'] ?? [];
        _loadingDepartments = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingDepartments = false;
        _error = 'Failed to load departments.';
      });
    }
  }

  Future<void> _loadGroups(int departmentId) async {
    setState(() {
      _departmentId = departmentId;
      _semester = null;
      _division = null;
      _subjectCode = null;

      _groups = [];
      _subjects = [];
      _records = [];

      _loadingGroups = true;
    });

    try {
      final token = await _token();

      final uri = Uri.parse(
        '$backendUrl/admin/attendance-records/groups',
      ).replace(queryParameters: {'department_id': departmentId.toString()});

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _groups = data['groups'] ?? [];
        _loadingGroups = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingGroups = false;
        _error = 'Failed to load groups.';
      });
    }
  }

  Future<void> _loadSubjects() async {
    if (_departmentId == null || _semester == null || _division == null) {
      return;
    }

    setState(() {
      _loadingSubjects = true;
      _subjects = [];
      _subjectCode = null;
      _records = [];
    });

    try {
      final token = await _token();

      final uri = Uri.parse('$backendUrl/admin/attendance-records/subjects')
          .replace(
            queryParameters: {
              'department_id': _departmentId!.toString(),
              'semester': _semester!.toString(),
              'division': _division!,
            },
          );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _subjects = data['subjects'] ?? [];
        _loadingSubjects = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingSubjects = false;
        _error = 'Failed to load subjects.';
      });
    }
  }

  Future<void> _loadRecords(String subjectCode) async {
    if (_departmentId == null || _semester == null || _division == null) {
      return;
    }

    setState(() {
      _subjectCode = subjectCode;
      _loadingRecords = true;
      _records = [];
    });

    try {
      final token = await _token();

      final uri = Uri.parse('$backendUrl/admin/attendance-records/list')
          .replace(
            queryParameters: {
              'department_id': _departmentId!.toString(),
              'semester': _semester!.toString(),
              'division': _division!,
              'subject_code': subjectCode,
            },
          );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        _records = data['records'] ?? [];
        _loadingRecords = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingRecords = false;
        _error = 'Failed to load attendance records.';
      });
    }
  }

  String _semesterRoman(dynamic value) {
    final semester = int.tryParse(value.toString());

    const roman = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII'];

    if (semester != null && semester > 0 && semester < roman.length) {
      return roman[semester];
    }

    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Records')),
      body: _loadingDepartments
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Department',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<int>(
                  initialValue: _departmentId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Select Department',
                  ),
                  items: _departments.map<DropdownMenuItem<int>>((department) {
                    final id = int.tryParse(
                      department['department_id'].toString(),
                    );

                    return DropdownMenuItem(
                      value: id,
                      child: Text(
                        department['department_name']?.toString() ?? '-',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _loadGroups(value);
                    }
                  },
                ),

                const SizedBox(height: 22),

                if (_loadingGroups)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingGroups && _groups.isNotEmpty) ...[
                  const Text(
                    'Semester - Division',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _groups.map<Widget>((group) {
                      final semester =
                          int.tryParse(group['semester'].toString()) ?? 0;

                      final division = group['division']?.toString() ?? '';

                      return ChoiceChip(
                        selected:
                            _semester == semester && _division == division,
                        label: Text(
                          'Sem : '
                          '${_semesterRoman(semester)}  '
                          'Division : $division',
                        ),
                        onSelected: (_) {
                          setState(() {
                            _semester = semester;
                            _division = division;
                          });

                          _loadSubjects();
                        },
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 22),

                if (_loadingSubjects)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingSubjects && _subjects.isNotEmpty) ...[
                  const Text(
                    'Subject',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  DropdownButtonFormField<String>(
                    initialValue: _subjectCode,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Select Subject',
                    ),
                    items: _subjects.map<DropdownMenuItem<String>>((subject) {
                      final code = subject['subject_code']?.toString() ?? '';

                      final name = subject['subject_name']?.toString() ?? '';

                      return DropdownMenuItem(
                        value: code,
                        child: Text('$code - $name'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _loadRecords(value);
                      }
                    },
                  ),
                ],

                const SizedBox(height: 24),

                if (_loadingRecords)
                  const Center(child: CircularProgressIndicator()),

                if (!_loadingRecords && _subjectCode != null)
                  _buildRecordsTable(),
              ],
            ),
    );
  }

  Widget _buildRecordsTable() {
    if (_records.isEmpty) {
      return const _EmptyView(message: 'No attendance records found.');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Sl. No.')),
          DataColumn(label: Text('USN')),
          DataColumn(label: Text('Student Name')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Session')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Face Verified')),
        ],
        rows: List.generate(_records.length, (index) {
          final record = _records[index];

          final status = record['status']?.toString() ?? '-';

          final faceVerified = record['face_verified']?.toString() == '1'
              ? 'Yes'
              : 'No';

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(record['student_id']?.toString() ?? '-')),
              DataCell(Text(record['full_name']?.toString() ?? '-')),
              DataCell(
                Text(
                  record['attendance_date']?.toString() ??
                      record['record_date']?.toString() ??
                      '-',
                ),
              ),
              DataCell(
                Text(
                  'Session '
                  '${record['session_id'] ?? '-'}',
                ),
              ),
              DataCell(Text(status)),
              DataCell(Text(faceVerified)),
            ],
          );
        }),
      ),
    );
  }
}

// ============================================================
// ADMIN DETAILS DIALOG
// ============================================================

class _AdminDetailsDialog extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;

  const _AdminDetailsDialog({required this.title, required this.data});

  String _formatKey(String key) {
    final result = key.replaceAll('_', ' ');

    if (result.isEmpty) {
      return result;
    }

    return result
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}'
                    '${word.substring(1)}',
        )
        .join(' ');
  }

  String _formatValue(dynamic value) {
    if (value == null) {
      return 'Not available';
    }

    if (value is bool) {
      return value ? 'Yes' : 'No';
    }

    if (value.toString() == '1') {
      return 'Yes';
    }

    if (value.toString() == '0') {
      return 'No';
    }

    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: data.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatKey(entry.key),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text(_formatValue(entry.value)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}

// ============================================================
// ADMIN EMPTY VIEW
// ============================================================

class _EmptyView extends StatelessWidget {
  final String message;

  const _EmptyView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.inbox_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ADMIN ERROR VIEW
// ============================================================

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 55),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// STUDENT ATTENDANCE PAGE
// ============================================================

// ============================================================
// ATTENDANCE PAGE
// ============================================================

class AttendancePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String username;

  const AttendancePage({super.key, required this.cameras, this.username = ''});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

// ============================================================
// ATTENDANCE QR SCANNER PAGE
// ============================================================

class AttendanceQrScannerPage extends StatefulWidget {
  const AttendanceQrScannerPage({super.key});

  @override
  State<AttendanceQrScannerPage> createState() =>
      _AttendanceQrScannerPageState();
}

class _AttendanceQrScannerPageState extends State<AttendanceQrScannerPage> {
  final MobileScannerController _scannerController = MobileScannerController();

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

    Navigator.pop(context, value.trim());
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
                    border: Border.all(color: Colors.white, width: 3),
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
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ATTENDANCE PAGE STATE
// ============================================================

class _AttendancePageState extends State<AttendancePage> {
  final TextEditingController _usnController = TextEditingController();

  XFile? _capturedImage;

  CameraController? _cameraController;

  bool _cameraReady = false;
  bool _processing = false;

  String _statusMessage = 'Enter your USN and capture your face.';

  String? _qrToken;
  bool _scanningQr = false;

  // ==========================================================
  // INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();

    // Pre-fill the USN when the page was opened
    // from the logged-in student dashboard.
    if (widget.username.trim().isNotEmpty) {
      _usnController.text = widget.username.trim().toUpperCase();
    }

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
        _statusMessage = 'No camera was found on this device.';
      });

      return;
    }

    CameraDescription selectedCamera = widget.cameras.first;

    for (final camera in widget.cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
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
        _statusMessage = 'Camera ready. Capture your face.';
      });
    } catch (e) {
      await controller.dispose();

      if (!mounted) return;

      setState(() {
        _cameraReady = false;
        _statusMessage = 'Could not initialize camera:\n$e';
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
      if (!mounted) return;

      setState(() {
        _statusMessage = 'Camera is not ready.';
      });

      return;
    }

    if (_processing) return;

    try {
      final image = await _cameraController!.takePicture();

      if (!mounted) return;

      setState(() {
        _capturedImage = image;
        _statusMessage = 'Face captured successfully.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _statusMessage = 'Could not capture face:\n$e';
      });
    }
  }

  // ==========================================================
  // LOCATION
  // ==========================================================

  Future<Position?> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (!mounted) return null;

      setState(() {
        _statusMessage = 'Please enable location services.';
      });

      return null;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return null;

      setState(() {
        _statusMessage = 'Location permission is required.';
      });

      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      if (!mounted) return null;

      setState(() {
        _statusMessage = 'Could not get location:\n$e';
      });

      return null;
    }
  }

  // ==========================================================
  // SCAN ATTENDANCE QR
  // ==========================================================

  Future<void> _scanAttendanceQr() async {
    if (_scanningQr) return;

    setState(() {
      _scanningQr = true;
      _statusMessage = 'Opening QR scanner...';
    });

    try {
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
        MaterialPageRoute(builder: (_) => const AttendanceQrScannerPage()),
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

      try {
        await _initializeCamera();
      } catch (_) {}
    }
  }

  // ==========================================================
  // STABLE STUDENT GPS
  // ==========================================================

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

        final Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        print(
          'GPS READING ${i + 1}: '
          'lat=${position.latitude}, '
          'lon=${position.longitude}, '
          'accuracy=${position.accuracy}, '
          'mocked=${position.isMocked}',
        );

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

        if (i < requiredReadings - 1) {
          await Future.delayed(const Duration(milliseconds: 1200));
        }
      } catch (e) {
        print('GPS READING ${i + 1} ERROR: $e');
      }
    }

    if (readings.isEmpty) {
      print('GPS FAILED: No valid GPS readings obtained.');

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

    Position bestReading = readings.first;

    for (final Position reading in readings) {
      if (reading.accuracy < bestReading.accuracy) {
        bestReading = reading;
      }
    }

    print('======================================');

    print('GPS READINGS SUMMARY');

    print('======================================');

    for (int i = 0; i < readings.length; i++) {
      print(
        'Reading ${i + 1}: '
        'lat=${readings[i].latitude}, '
        'lon=${readings[i].longitude}, '
        'accuracy='
        '${readings[i].accuracy.toStringAsFixed(2)} m',
      );
    }

    print('======================================');

    print('BEST GPS READING');

    print('======================================');

    print('Latitude: ${bestReading.latitude}');

    print('Longitude: ${bestReading.longitude}');

    print(
      'Accuracy: '
      '${bestReading.accuracy.toStringAsFixed(2)} m',
    );

    print('Mocked: ${bestReading.isMocked}');

    print('======================================');

    if (!mounted) {
      return null;
    }

    setState(() {
      _statusMessage = 'Best GPS location obtained.';
    });

    return bestReading;
  }

  // ==========================================================
  // MARK ATTENDANCE
  // ==========================================================

  Future<void> _markAttendance() async {
    final usn = _usnController.text.trim().toUpperCase();

    if (usn.isEmpty) {
      if (!mounted) return;

      setState(() {
        _statusMessage = 'Please enter your USN.';
      });

      return;
    }

    if (_qrToken == null || _qrToken!.trim().isEmpty) {
      if (!mounted) return;

      setState(() {
        _statusMessage = 'Please scan the attendance QR code first.';
      });

      return;
    }

    if (_capturedImage == null) {
      if (!mounted) return;

      setState(() {
        _statusMessage = 'Please capture your face first.';
      });

      return;
    }

    if (_processing) return;

    setState(() {
      _processing = true;
      _statusMessage = 'Getting your location...';
    });

    try {
      // ======================================================
      // GET SAVED AUTHENTICATION TOKEN
      // ======================================================

      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token');

      if (token == null || token.isEmpty) {
        if (!mounted) return;

        setState(() {
          _processing = false;
          _statusMessage =
              'Authentication session not found. Please login again.';
        });

        return;
      }

      // ======================================================
      // GET STABLE STUDENT LOCATION
      // ======================================================

      final position = await _getStableStudentLocation();

      if (position == null) {
        if (!mounted) return;

        setState(() {
          _processing = false;
          _statusMessage = 'Unable to get your current location.';
        });

        return;
      }

      if (!mounted) return;

      // ======================================================
      // MOCK LOCATION CHECK
      // ======================================================

      if (position.isMocked) {
        setState(() {
          _processing = false;
          _statusMessage = 'Mock location detected. Attendance rejected.';
        });

        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Attendance Rejected'),
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

      setState(() {
        _statusMessage = 'Verifying QR, face and location...';
      });

      // ======================================================
      // CREATE MULTIPART ATTENDANCE REQUEST
      // ======================================================

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$backendUrl/attendance/mark-session'),
      );

      // ======================================================
      // AUTHENTICATION HEADER
      // ======================================================

      request.headers['Authorization'] = 'Bearer $token';

      // ======================================================
      // FORM DATA
      // ======================================================

      request.fields['usn'] = usn;

      request.fields['qr_token'] = _qrToken!.trim();

      request.fields['latitude'] = position.latitude.toString();

      request.fields['longitude'] = position.longitude.toString();

      request.fields['accuracy'] = position.accuracy.toString();

      request.fields['is_mocked'] = position.isMocked.toString();

      // ======================================================
      // FACE IMAGE
      // ======================================================

      request.files.add(
        await http.MultipartFile.fromPath('face', _capturedImage!.path),
      );

      // ======================================================
      // SEND REQUEST
      // ======================================================

      final streamedResponse = await request.send();

      final response = await http.Response.fromStream(streamedResponse);

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        print('JSON DECODE ERROR: $e');
      }

      print(
        'ATTENDANCE STATUS: '
        '${response.statusCode}',
      );

      print(
        'ATTENDANCE RESPONSE: '
        '${response.body}',
      );

      // ======================================================
      // AUTHENTICATION FAILURE
      // ======================================================

      if (response.statusCode == 401) {
        if (!mounted) return;

        setState(() {
          _processing = false;
          _statusMessage = 'Session expired. Please login again.';
        });

        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Authentication Required'),
            content: const Text(
              'Your login session has expired.\n\n'
              'Please login again before marking attendance.',
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

      // ======================================================
      // ATTENDANCE SUCCESS
      // ======================================================

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        final student = data['student'] is Map
            ? Map<String, dynamic>.from(data['student'])
            : null;

        final face = data['face'] is Map
            ? Map<String, dynamic>.from(data['face'])
            : null;

        final location = data['location'] is Map
            ? Map<String, dynamic>.from(data['location'])
            : null;

        final session = data['session'] is Map
            ? Map<String, dynamic>.from(data['session'])
            : null;

        final name =
            student?['name']?.toString() ??
            student?['full_name']?.toString() ??
            usn;

        final similarity = face?['similarity']?.toString() ?? '-';

        final distance = location?['distance']?.toString() ?? '-';

        final subject =
            session?['subject_name']?.toString() ??
            session?['class_name']?.toString() ??
            '-';

        if (!mounted) return;

        setState(() {
          _processing = false;
          _statusMessage = 'ATTENDANCE MARKED SUCCESSFULLY';
        });

        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Attendance Successful'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Name: $name'),

                  Text('USN: $usn'),

                  Text('Subject: $subject'),

                  const SizedBox(height: 10),

                  const Text('Face verified: YES'),

                  Text(
                    'Face similarity: '
                    '$similarity',
                  ),

                  Text(
                    'Distance from teacher: '
                    '$distance m',
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'Status: PRESENT',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
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

      // ======================================================
      // ATTENDANCE REJECTED
      // ======================================================

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
          title: const Text('Attendance Rejected'),
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
                Navigator.pop(dialogContext);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('ATTENDANCE CONNECTION ERROR: $e');

      if (!mounted) return;

      setState(() {
        _processing = false;

        _statusMessage = 'Could not connect to backend.';
      });

      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Connection Error'),
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
                Navigator.pop(dialogContext);
              },
              child: const Text('OK'),
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
        title: const Text('AntiProxy Attendance'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _processing
                ? null
                : () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LoginPage(cameras: widget.cameras),
                      ),
                      (route) => false,
                    );
                  },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // =================================================
              // LOGGED-IN STUDENT
              // =================================================
              if (widget.username.isNotEmpty)
                Text(
                  'Logged in as: '
                  '${widget.username}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                ),

              const SizedBox(height: 8),

              // =================================================
              // TITLE
              // =================================================
              const Text(
                'Smart Attendance',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 6),

              const Text(
                'Face + GPS Verification',
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              // =================================================
              // USN
              // =================================================
              TextField(
                controller: _usnController,
                readOnly: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'USN',
                  hintText: 'Student USN',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                  suffixIcon: Icon(Icons.lock_outline),
                ),
              ),

              const SizedBox(height: 16),

              // =================================================
              // QR SCANNER
              // =================================================
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
                    _qrToken == null ? 'SCAN ATTENDANCE QR' : 'QR SCANNED ✓',
                  ),
                ),
              ),

              // =================================================
              // QR STATUS
              // =================================================
              if (_qrToken != null) ...[
                const SizedBox(height: 10),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.verified, color: Colors.green, size: 20),
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
                        'Token: '
                        '${_qrToken!.length > 18 ? '${_qrToken!.substring(0, 18)}...' : _qrToken!}',
                        style: const TextStyle(fontSize: 12),
                      ),

                      const SizedBox(height: 8),

                      TextButton.icon(
                        onPressed: _processing ? null : _scanAttendanceQr,
                        icon: const Icon(Icons.refresh),
                        label: const Text('SCAN AGAIN'),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // =================================================
              // CAMERA / CAPTURED FACE
              // =================================================
              Container(
                height: 320,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black,
                ),
                clipBehavior: Clip.antiAlias,
                child: _capturedImage != null
                    ? Image.file(File(_capturedImage!.path), fit: BoxFit.cover)
                    : _cameraReady && _cameraController != null
                    ? CameraPreview(_cameraController!)
                    : const Center(child: CircularProgressIndicator()),
              ),

              const SizedBox(height: 12),

              // =================================================
              // CAPTURE FACE
              // =================================================
              ElevatedButton.icon(
                onPressed: _processing ? null : _captureFace,
                icon: const Icon(Icons.camera_alt),
                label: Text(
                  _capturedImage == null ? 'CAPTURE FACE' : 'CAPTURE AGAIN',
                ),
              ),

              const SizedBox(height: 12),

              // =================================================
              // STATUS
              // =================================================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.withValues(alpha: 0.12),
                ),
                child: Text(_statusMessage, textAlign: TextAlign.center),
              ),

              const SizedBox(height: 16),

              // =================================================
              // MARK ATTENDANCE
              // =================================================
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _processing ? null : _markAttendance,
                  child: _processing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'MARK ATTENDANCE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // =================================================
              // INFORMATION
              // =================================================
              const Text(
                'Attendance requires a registered face '
                'and valid campus GPS location.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FACULTY ATTENDANCE REPORT PAGE
// ============================================================
class FacultyAttendanceReportPage extends StatefulWidget {
  final dynamic userId;

  const FacultyAttendanceReportPage({super.key, required this.userId});

  @override
  State<FacultyAttendanceReportPage> createState() =>
      _FacultyAttendanceReportPageState();
}

// Student Dashboard
// ============================================================
// EDIT STUDENT PROFILE PAGE
// ============================================================

class EditStudentProfilePage extends StatefulWidget {
  final dynamic userId;
  final Map<String, dynamic> student;

  const EditStudentProfilePage({
    super.key,
    required this.userId,
    required this.student,
  });

  @override
  State<EditStudentProfilePage> createState() => _EditStudentProfilePageState();
}

class _EditStudentProfilePageState extends State<EditStudentProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _departmentController;
  late final TextEditingController _semesterController;
  late final TextEditingController _divisionController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.student['full_name']?.toString() ?? '',
    );

    _emailController = TextEditingController(
      text: widget.student['email']?.toString() ?? '',
    );

    _departmentController = TextEditingController(
      text: widget.student['department']?.toString() ?? '',
    );

    _semesterController = TextEditingController(
      text: widget.student['semester']?.toString() ?? '',
    );

    _divisionController = TextEditingController(
      text: widget.student['division']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _departmentController.dispose();
    _semesterController.dispose();
    _divisionController.dispose();

    super.dispose();
  }

  // ==========================================================
  // SAVE PROFILE
  // ==========================================================

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final department = _departmentController.text.trim();
    final semester = _semesterController.text.trim();
    final division = _divisionController.text.trim();

    // --------------------------------------------------------
    // Validation
    // --------------------------------------------------------

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Full name is required.')));
      return;
    }

    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email is required.')));
      return;
    }

    if (department.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Department is required.')));
      return;
    }

    if (semester.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Semester is required.')));
      return;
    }

    if (division.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Division is required.')));
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final response = await http.put(
        Uri.parse('$backendUrl/student/profile/user/${widget.userId}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'full_name': name,
          'email': email,
          'department': department,
          'semester': semester,
          'division': division,
        }),
      );

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully.')),
        );

        // ----------------------------------------------------
        // Return updated student data to Dashboard.
        // ----------------------------------------------------

        Navigator.pop(context, data['student']);

        return;
      }

      final message =
          data['message']?.toString() ?? 'Could not update profile.';

      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not connect to backend.\n$error')),
      );
    }
  }

  // ==========================================================
  // TEXT FIELD
  // ==========================================================

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        enabled: enabled && !_saving,
        keyboardType: keyboardType,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final studentId = widget.student['student_id']?.toString() ?? '-';

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Student Profile')),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // =================================================
              // HEADER
              // =================================================
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.08),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        Icons.person_outline,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Update your profile',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            'USN: $studentId',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // =================================================
              // PROTECTED USN
              // =================================================
              const Text(
                'Student ID / USN',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              TextField(
                enabled: false,
                controller: TextEditingController(text: studentId),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                  helperText: 'Student ID cannot be changed.',
                ),
              ),

              const SizedBox(height: 16),

              // =================================================
              // FULL NAME
              // =================================================
              _field(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person,
              ),

              // =================================================
              // EMAIL
              // =================================================
              _field(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email,
                keyboardType: TextInputType.emailAddress,
              ),

              // =================================================
              // DEPARTMENT
              // =================================================
              _field(
                controller: _departmentController,
                label: 'Department',
                icon: Icons.account_balance,
              ),

              // =================================================
              // SEMESTER
              // =================================================
              _field(
                controller: _semesterController,
                label: 'Semester',
                icon: Icons.school,
                keyboardType: TextInputType.number,
              ),

              // =================================================
              // DIVISION
              // =================================================
              _field(
                controller: _divisionController,
                label: 'Division',
                icon: Icons.groups,
              ),

              const SizedBox(height: 8),

              // =================================================
              // SAVE
              // =================================================
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveProfile,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _saving ? 'SAVING...' : 'SAVE CHANGES',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // =================================================
              // NOTE
              // =================================================
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.withValues(alpha: 0.08),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20),

                    SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'Your Student ID / USN and face registration status are protected and cannot be changed from this page.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudentDashboardPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final dynamic userId;
  final String username;

  const StudentDashboardPage({
    super.key,
    required this.cameras,
    required this.userId,
    required this.username,
  });

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  bool _loading = true;
  String _errorMessage = '';

  Map<String, dynamic>? _student;
  List<dynamic> _subjects = [];

  int _selectedNavigationIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  // ============================================================
  // LOAD COMPLETE STUDENT DASHBOARD
  // ============================================================

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = '';
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token');

      if (token == null || token.isEmpty) {
        throw Exception('Authentication token not found. Please login again.');
      }

      final response = await http.get(
        Uri.parse('$backendUrl/student/dashboard'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      }

      if (response.statusCode == 403) {
        throw Exception(
          'You are not authorized to access the student dashboard.',
        );
      }

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        throw Exception(
          data['message']?.toString() ?? 'Could not load dashboard',
        );
      }

      final studentData = data['student'];

      final subjectData = data['subjects'];

      if (!mounted) return;

      setState(() {
        _student = studentData is Map
            ? Map<String, dynamic>.from(studentData)
            : {};

        _subjects = subjectData is List ? List<dynamic>.from(subjectData) : [];

        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ============================================================
  // STUDENT VALUE
  // ============================================================

  String _studentValue(String key, {String fallback = '-'}) {
    final value = _student?[key];

    if (value == null || value.toString().trim().isEmpty) {
      return fallback;
    }

    return value.toString();
  }

  // ============================================================
  // GREETING
  // ============================================================

  String _getGreeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Good Morning';
    }

    if (hour < 17) {
      return 'Good Afternoon';
    }

    if (hour < 21) {
      return 'Good Evening';
    }

    return 'Good Night';
  }

  // ============================================================
  // OPEN ATTENDANCE
  // ============================================================

  void _openAttendance() {
    final usn = _studentValue('student_id', fallback: widget.username);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendancePage(cameras: widget.cameras, username: usn),
      ),
    );
  }

  // ============================================================
  // OPEN REPORT
  // ============================================================

  void _openReport({String? subjectCode}) {
    final usn = _student?['student_id']?.toString() ?? '';

    if (usn.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student information is not available.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StudentAttendanceReportPage(usn: usn, subjectCode: subjectCode),
      ),
    );
  }

  // ============================================================
  // OPEN SUBJECT REGISTRATION
  // ============================================================

  void _openSubjects() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StudentSubjectRegistrationPage(username: widget.username),
      ),
    );
  }

  // ============================================================
  // EDIT PROFILE
  // ============================================================

  Future<void> _editProfile() async {
    if (_student == null) {
      return;
    }

    final updatedStudent = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditStudentProfilePage(
          userId: widget.userId,
          student: Map<String, dynamic>.from(_student!),
        ),
      ),
    );

    if (!mounted) return;

    if (updatedStudent is Map) {
      await _loadDashboard();
    } else {
      await _loadDashboard();
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('LOGOUT'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // Remove the login token ONLY when the user explicitly logs out.
    await prefs.remove('auth_token');

    if (!mounted) return;

    // Completely remove the dashboard and every previous page
    // from the navigation stack and return directly to LoginPage.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginPage(cameras: widget.cameras)),
      (route) => false,
    );
  }
  // ============================================================
  // PROFILE AVATAR
  // ============================================================

  Widget _profileAvatar() {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primary.withValues(alpha: 0.10),
        border: Border.all(color: primary.withValues(alpha: 0.15), width: 2),
      ),
      child: Icon(Icons.person_rounded, size: 42, color: primary),
    );
  }

  // ============================================================
  // PROFILE CARD
  // ============================================================

  Widget _buildProfileCard() {
    final name = _studentValue('full_name', fallback: widget.username);

    final usn = _studentValue('student_id', fallback: widget.username);

    final department = _studentValue('department');

    final semester = _studentValue('semester');

    final division = _studentValue('division');

    final email = _studentValue('email');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _profileAvatar(),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  usn,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  department,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),

                const SizedBox(height: 8),

                Wrap(
                  spacing: 10,
                  runSpacing: 5,
                  children: [
                    _profileBadge(Icons.school_outlined, 'Semester $semester'),
                    _profileBadge(Icons.groups_outlined, 'Division $division'),
                  ],
                ),

                const SizedBox(height: 7),

                Row(
                  children: [
                    Icon(
                      Icons.email_outlined,
                      size: 15,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          IconButton(
            tooltip: 'Edit Profile',
            onPressed: _editProfile,
            icon: Icon(
              Icons.edit_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PROFILE BADGE
  // ============================================================

  Widget _profileBadge(IconData icon, String text) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: primary.withValues(alpha: 0.07),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ATTENDANCE HERO
  // ============================================================

  Widget _buildAttendanceHero() {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, primary.withValues(alpha: 0.78)],
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.20),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: Colors.white.withValues(alpha: 0.13),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 32,
                  color: Colors.white,
                ),
              ),

              const SizedBox(width: 13),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mark Attendance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Secure classroom attendance',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          const Text(
            'QR + Face + GPS + Time verification',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 13),

          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _openAttendance,
              icon: const Icon(Icons.camera_alt_outlined, size: 19),
              label: const Text(
                'MARK ATTENDANCE',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _sectionTitle(
    String title, {
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        if (actionText != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionText, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 3),
                const Icon(Icons.arrow_forward, size: 15),
              ],
            ),
          ),
      ],
    );
  }

  // ============================================================
  // SUBJECT CARD
  // ============================================================

  Widget _subjectCard(Map<String, dynamic> subject, int index) {
    final name = subject['subject_name']?.toString() ?? '-';

    final code = subject['subject_code']?.toString() ?? '-';

    final presentValue = subject['present'];

    final totalValue = subject['total'];

    final percentageValue = subject['percentage'];

    final status = subject['status']?.toString() ?? 'Not started';

    double percentage = 0;

    bool hasClasses = false;

    if (percentageValue != null) {
      percentage = double.tryParse(percentageValue.toString()) ?? 0;
    }

    final total = int.tryParse(totalValue?.toString() ?? '') ?? 0;

    final present = int.tryParse(presentValue?.toString() ?? '') ?? 0;

    hasClasses = total > 0;

    percentage = percentage.clamp(0, 100);

    // ----------------------------------------------------------
    // Status styling
    // ----------------------------------------------------------

    Color statusColor;
    Color statusBackground;
    IconData statusIcon;

    if (!hasClasses || status.toLowerCase() == 'not started') {
      statusColor = Colors.grey.shade700;

      statusBackground = Colors.grey.withValues(alpha: 0.10);

      statusIcon = Icons.schedule_outlined;
    } else if (status == 'Safe') {
      statusColor = Colors.green.shade700;

      statusBackground = Colors.green.withValues(alpha: 0.10);

      statusIcon = Icons.check_circle_outline;
    } else {
      statusColor = Colors.orange.shade800;

      statusBackground = Colors.orange.withValues(alpha: 0.12);

      statusIcon = Icons.warning_amber_rounded;
    }

    // ----------------------------------------------------------
    // Subject icon
    // ----------------------------------------------------------

    final primary = Theme.of(context).colorScheme.primary;

    final subjectColors = [
      primary,
      Colors.deepPurple,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
      Colors.orange,
    ];

    final subjectColor = subjectColors[index % subjectColors.length];

    // ----------------------------------------------------------
    // Percentage text
    // ----------------------------------------------------------

    final percentageText = hasClasses ? '${percentage.round()}%' : 'No classes';

    // ----------------------------------------------------------
    // Card
    // ----------------------------------------------------------

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --------------------------------------------------
            // SUBJECT HEADER
            // --------------------------------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: subjectColor.withValues(alpha: 0.10),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: subjectColor,
                    size: 23,
                  ),
                ),

                const SizedBox(width: 9),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 5),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: statusBackground,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),

                      const SizedBox(width: 3),

                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            // --------------------------------------------------
            // ATTENDANCE DATA
            // --------------------------------------------------
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Present',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        hasClasses ? '$present / $total' : '0 / 0',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attendance',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        percentageText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: hasClasses
                              ? statusColor
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 9),

            // --------------------------------------------------
            // PROGRESS BAR
            // --------------------------------------------------
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: hasClasses ? percentage / 100 : 0,
                minHeight: 7,
                backgroundColor: Colors.grey.withValues(alpha: 0.13),
                valueColor: AlwaysStoppedAnimation<Color>(
                  hasClasses ? statusColor : Colors.grey.shade400,
                ),
              ),
            ),

            const SizedBox(height: 4),

            // --------------------------------------------------
            // VIEW REPORT
            // --------------------------------------------------
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  final subjectCode = subject['subject_code']
                      ?.toString()
                      .trim();

                  if (subjectCode == null || subjectCode.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Subject code is not available.'),
                      ),
                    );

                    return;
                  }

                  _openReport(subjectCode: subjectCode);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 3,
                  ),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'View Report',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(width: 4),

                    Icon(Icons.arrow_forward, size: 14, color: primary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MY SUBJECTS
  // ============================================================

  Widget _buildSubjects() {
    if (_subjects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 45,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 10),
            const Text(
              'No subjects registered yet.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Register your subjects to view attendance here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _openSubjects,
              icon: const Icon(Icons.add),
              label: const Text('REGISTER SUBJECT'),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _subjects.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (context, index) {
        final subject = Map<String, dynamic>.from(_subjects[index]);

        return _subjectCard(subject, index);
      },
    );
  }

  // ============================================================
  // QUICK ACTION CARD
  // ============================================================

  Widget _quickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 112,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),

                const Spacer(),

                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 3),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 11, color: color),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // QUICK ACTIONS
  // ============================================================

  Widget _buildQuickActions() {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Row(
          children: [
            _quickActionCard(
              icon: Icons.bar_chart_rounded,
              title: 'Attendance Report',
              subtitle: 'Detailed report',
              onPressed: _openReport,
              color: primary,
            ),
            const SizedBox(width: 12),
            _quickActionCard(
              icon: Icons.menu_book_rounded,
              title: 'My Subjects',
              subtitle: 'Subjects & records',
              onPressed: _openSubjects,
              color: Colors.deepPurple,
            ),
          ],
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          height: 72,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: _openSubjects,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.deepPurple.withValues(alpha: 0.10),
                      ),
                      child: const Icon(
                        Icons.library_add_outlined,
                        color: Colors.deepPurple,
                      ),
                    ),

                    const SizedBox(width: 12),

                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Subject Registration',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Manage your registered subjects',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),

                    const Icon(Icons.arrow_forward_ios, size: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SECURITY CARD
  // ============================================================

  Widget _buildSecurityCard() {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: primary.withValues(alpha: 0.06),
        border: Border.all(color: primary.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.10),
            ),
            child: Icon(Icons.security_rounded, color: primary, size: 21),
          ),

          const SizedBox(width: 11),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Attendance',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 3),
                Text(
                  'QR, face and GPS verification protect attendance marking.',
                  style: TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MORE MENU
  // ============================================================

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'More',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 12),

                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('My Profile'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _editProfile();
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Subject Registration'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openSubjects();
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.assessment_outlined),
                  title: const Text('Attendance Report'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openReport();
                  },
                ),

                const Divider(),

                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Logout'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _logout();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // BOTTOM NAVIGATION
  // ============================================================

  void _onNavigationSelected(int index) {
    setState(() {
      _selectedNavigationIndex = index;
    });

    switch (index) {
      case 0:
        break;

      case 1:
        _openSubjects();
        break;

      case 2:
        _openReport();
        break;

      case 3:
        _showMoreMenu();
        break;
    }
  }

  // ============================================================
  // LOADING SCREEN
  // ============================================================

  Widget _buildLoadingScreen() {
    final primary = Theme.of(context).colorScheme.primary;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: primary, strokeWidth: 3),
          const SizedBox(height: 18),
          const Text(
            'Loading your dashboard...',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            'Please wait',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ERROR SCREEN
  // ============================================================

  Widget _buildErrorScreen() {
    final primary = Theme.of(context).colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha: 0.08),
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: Colors.red,
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'Unable to load dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: _loadDashboard,
              icon: const Icon(Icons.refresh),
              label: const Text('TRY AGAIN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MAIN DASHBOARD
  // ============================================================

  Widget _buildDashboard() {
    final name = _studentValue('full_name', fallback: widget.username);

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
        children: [
          // ----------------------------------------------------
          // PROFILE
          // ----------------------------------------------------
          _buildProfileCard(),

          const SizedBox(height: 22),

          // ----------------------------------------------------
          // GREETING
          // ----------------------------------------------------
          Text(
            '${_getGreeting()}, $name 👋',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 5),

          Text(
            'Here\'s your attendance and academic overview',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),

          const SizedBox(height: 16),

          // ----------------------------------------------------
          // ATTENDANCE
          // ----------------------------------------------------
          _buildAttendanceHero(),

          const SizedBox(height: 24),

          // ----------------------------------------------------
          // MY SUBJECTS
          // ----------------------------------------------------
          _sectionTitle(
            'My Subjects',
            actionText: 'View All',
            onAction: _openSubjects,
          ),

          const SizedBox(height: 5),

          _buildSubjects(),

          const SizedBox(height: 24),

          // ----------------------------------------------------
          // QUICK ACTIONS
          // ----------------------------------------------------
          _sectionTitle('Quick Actions'),

          const SizedBox(height: 10),

          _buildQuickActions(),

          const SizedBox(height: 22),

          // ----------------------------------------------------
          // SECURITY
          // ----------------------------------------------------
          _buildSecurityCard(),

          const SizedBox(height: 20),

          // ----------------------------------------------------
          // LOGOUT
          // ----------------------------------------------------
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text(
                'LOGOUT',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),

      // --------------------------------------------------------
      // APP BAR
      // --------------------------------------------------------
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,

        titleSpacing: 8,

        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Colors.white,
                size: 25,
              ),
            ),

            const SizedBox(width: 10),

            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AntiProxy',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Student Portal',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'Refresh Dashboard',
            onPressed: _loading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: _showMoreMenu,
            icon: const Icon(Icons.menu_rounded),
          ),
        ],
      ),

      // --------------------------------------------------------
      // BODY
      // --------------------------------------------------------
      body: _loading
          ? _buildLoadingScreen()
          : _errorMessage.isNotEmpty
          ? _buildErrorScreen()
          : _buildDashboard(),

      // --------------------------------------------------------
      // BOTTOM NAVIGATION
      // --------------------------------------------------------
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavigationIndex,
        onDestinationSelected: _onNavigationSelected,
        height: 68,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Subjects',
          ),
          NavigationDestination(
            icon: Icon(Icons.assessment_outlined),
            selectedIcon: Icon(Icons.assessment_rounded),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            selectedIcon: Icon(Icons.more_horiz_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class StudentAttendanceReportPage extends StatefulWidget {
  final String usn;
  final String? subjectCode;

  const StudentAttendanceReportPage({
    super.key,
    required this.usn,
    this.subjectCode,
  });

  @override
  State<StudentAttendanceReportPage> createState() =>
      _StudentAttendanceReportPageState();
}

class _StudentAttendanceReportPageState
    extends State<StudentAttendanceReportPage> {
  bool _loading = true;
  String _errorMessage = '';

  String _studentName = '';
  String _studentUsn = '';

  int _totalClasses = 0;
  int _presentClasses = 0;
  int _absentClasses = 0;
  double _overallPercentage = 0;

  List<dynamic> _subjects = [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = '';
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token');

      if (token == null || token.isEmpty) {
        throw Exception('Authentication token not found. Please login again.');
      }

      final usn = widget.usn.trim().toUpperCase();

      final response = await http.get(
        Uri.parse('$backendUrl/attendance/student-report/$usn'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      }

      if (response.statusCode == 403) {
        throw Exception(
          'You are not authorized to access this attendance report.',
        );
      }

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        throw Exception(
          data['message']?.toString() ?? 'Could not load attendance report',
        );
      }

      final student = data['student'] ?? {};
      final summary = data['summary'] ?? {};

      List<dynamic> loadedSubjects = data['subjects'] is List
          ? List<dynamic>.from(data['subjects'])
          : [];

      // ------------------------------------------------------------
      // SUBJECT FILTER
      // ------------------------------------------------------------
      //
      // If this page was opened from a specific subject card,
      // only that subject is displayed.
      //
      if (widget.subjectCode != null && widget.subjectCode!.trim().isNotEmpty) {
        final requestedCode = widget.subjectCode!.trim().toUpperCase();

        loadedSubjects = loadedSubjects.where((subject) {
          final map = Map<String, dynamic>.from(subject);

          final code =
              map['subject_code']?.toString().trim().toUpperCase() ?? '';

          return code == requestedCode;
        }).toList();
      }

      if (!mounted) return;

      // ------------------------------------------------------------
      // Calculate displayed summary
      // ------------------------------------------------------------
      int displayedTotal = 0;
      int displayedPresent = 0;
      int displayedAbsent = 0;
      double displayedPercentage = 0;

      if (widget.subjectCode != null &&
          widget.subjectCode!.trim().isNotEmpty &&
          loadedSubjects.isNotEmpty) {
        final subject = Map<String, dynamic>.from(loadedSubjects.first);

        displayedTotal =
            int.tryParse(subject['total_classes']?.toString() ?? '0') ?? 0;

        displayedPresent =
            int.tryParse(subject['present_classes']?.toString() ?? '0') ?? 0;

        displayedAbsent =
            int.tryParse(subject['absent_classes']?.toString() ?? '0') ?? 0;

        displayedPercentage =
            double.tryParse(
              subject['attendance_percentage']?.toString() ?? '0',
            ) ??
            0;
      } else {
        displayedTotal =
            int.tryParse(summary['total_classes']?.toString() ?? '0') ?? 0;

        displayedPresent =
            int.tryParse(summary['present_classes']?.toString() ?? '0') ?? 0;

        displayedAbsent =
            int.tryParse(summary['absent_classes']?.toString() ?? '0') ?? 0;

        displayedPercentage =
            double.tryParse(
              summary['attendance_percentage']?.toString() ?? '0',
            ) ??
            0;
      }

      setState(() {
        _studentName = student['name']?.toString() ?? '';

        _studentUsn = student['usn']?.toString() ?? usn;

        _totalClasses = displayedTotal;
        _presentClasses = displayedPresent;
        _absentClasses = displayedAbsent;
        _overallPercentage = displayedPercentage;

        _subjects = loadedSubjects;

        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = error.toString();
      });
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) {
      return '-';
    }

    final text = value.toString();

    if (text.length >= 10) {
      final parts = text.substring(0, 10).split('-');

      if (parts.length == 3) {
        return '${parts[2]}-${parts[1]}-${parts[0]}';
      }
    }

    return text;
  }

  String _formatTime(dynamic value) {
    if (value == null) {
      return '-';
    }

    final text = value.toString();

    if (text.length >= 5) {
      return text.substring(0, 5);
    }

    return text;
  }

  String _formatPercentage(dynamic value) {
    if (value == null) {
      return 'N/A';
    }

    final number = double.tryParse(value.toString());

    if (number == null) {
      return 'N/A';
    }

    return '${number.toStringAsFixed(1)}%';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
      case 'late':
        return Colors.green;

      case 'absent':
        return Colors.red;

      default:
        return Colors.grey;
    }
  }

  Future<void> _downloadSubjectPdf(Map<String, dynamic> subject) async {
    try {
      final pdf = pw.Document();

      final subjectName = subject['subject_name']?.toString() ?? '';

      final subjectCode = subject['subject_code']?.toString() ?? '';

      final total =
          int.tryParse(subject['total_classes']?.toString() ?? '0') ?? 0;

      final present =
          int.tryParse(subject['present_classes']?.toString() ?? '0') ?? 0;

      final absent =
          int.tryParse(subject['absent_classes']?.toString() ?? '0') ?? 0;

      final percentage =
          double.tryParse(
            subject['attendance_percentage']?.toString() ?? '0',
          ) ??
          0;

      final records = subject['records'] is List
          ? List<dynamic>.from(subject['records'])
          : <dynamic>[];

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return [
              pw.Text(
                'AntiProxy Student Attendance Report',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 12),

              pw.Text('Student: $_studentName'),

              pw.Text('USN: $_studentUsn'),

              pw.SizedBox(height: 12),

              pw.Text(
                'Subject: $subjectName',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.Text('Subject Code: $subjectCode'),

              pw.SizedBox(height: 12),

              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    children: [
                      _pdfCell('Total Classes', bold: true),
                      _pdfCell('Present', bold: true),
                      _pdfCell('Absent', bold: true),
                      _pdfCell('Attendance', bold: true),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _pdfCell(total.toString()),
                      _pdfCell(present.toString()),
                      _pdfCell(absent.toString()),
                      _pdfCell('${percentage.toStringAsFixed(1)}%'),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 18),

              pw.Text(
                'Attendance Dates',
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 8),

              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(1.2),
                  2: const pw.FlexColumnWidth(1.2),
                  3: const pw.FlexColumnWidth(1.2),
                },
                children: [
                  pw.TableRow(
                    children: [
                      _pdfCell('Date', bold: true),
                      _pdfCell('Start', bold: true),
                      _pdfCell('End', bold: true),
                      _pdfCell('Status', bold: true),
                    ],
                  ),
                  ...records.map((record) {
                    final item = Map<String, dynamic>.from(record);

                    return pw.TableRow(
                      children: [
                        _pdfCell(_formatDate(item['attendance_date'])),
                        _pdfCell(_formatTime(item['start_time'])),
                        _pdfCell(_formatTime(item['end_time'])),
                        _pdfCell(
                          (item['status'] ?? 'absent').toString().toUpperCase(),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ];
          },
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            '${subjectCode.isEmpty ? 'Subject' : subjectCode}_Attendance.pdf',
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create PDF: $error')));
    }
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final bool isSubjectReport =
        widget.subjectCode != null && widget.subjectCode!.trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _studentName.isEmpty ? 'Student Attendance' : _studentName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 4),

            Text(_studentUsn, style: const TextStyle(fontSize: 14)),

            if (isSubjectReport) ...[
              const SizedBox(height: 8),
              Text(
                'Subject: ${widget.subjectCode}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _summaryItem(
                    'Total',
                    _totalClasses.toString(),
                    Icons.calendar_month,
                  ),
                ),
                Expanded(
                  child: _summaryItem(
                    'Present',
                    _presentClasses.toString(),
                    Icons.check_circle,
                  ),
                ),
                Expanded(
                  child: _summaryItem(
                    'Absent',
                    _absentClasses.toString(),
                    Icons.cancel,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Center(
              child: Column(
                children: [
                  Text(
                    isSubjectReport
                        ? 'Subject Attendance'
                        : 'Overall Attendance',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    _formatPercentage(_overallPercentage),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 22),

        const SizedBox(height: 4),

        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),

        Text(title, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildSubjectCard(Map<String, dynamic> subject) {
    final subjectName = subject['subject_name']?.toString() ?? '';

    final subjectCode = subject['subject_code']?.toString() ?? '';

    final total =
        int.tryParse(subject['total_classes']?.toString() ?? '0') ?? 0;

    final present =
        int.tryParse(subject['present_classes']?.toString() ?? '0') ?? 0;

    final absent =
        int.tryParse(subject['absent_classes']?.toString() ?? '0') ?? 0;

    final percentageValue = subject['attendance_percentage'];

    final percentage = double.tryParse(percentageValue?.toString() ?? '0') ?? 0;

    final records = subject['records'] is List
        ? List<dynamic>.from(subject['records'])
        : <dynamic>[];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subjectName,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(subjectCode, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),

                IconButton(
                  tooltip: 'Download PDF',
                  onPressed: () => _downloadSubjectPdf(subject),
                  icon: const Icon(Icons.download),
                ),
              ],
            ),

            const Divider(),

            Row(
              children: [
                Expanded(child: _subjectStat('Present', present.toString())),
                Expanded(child: _subjectStat('Absent', absent.toString())),
                Expanded(child: _subjectStat('Total', total.toString())),
              ],
            ),

            const SizedBox(height: 12),

            Center(
              child: Text(
                percentageValue == null
                    ? 'N/A'
                    : _formatPercentage(percentageValue),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Attendance Dates',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            if (records.isEmpty)
              const Text('No classes recorded.')
            else
              ...records.map((record) {
                final item = Map<String, dynamic>.from(record);

                final status = item['status']?.toString() ?? 'absent';

                final statusColor = _statusColor(status);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDate(item['attendance_date']),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 3),

                            Text(
                              '${_formatTime(item['start_time'])} - ${_formatTime(item['end_time'])}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),

                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _downloadSubjectPdf(subject),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('DOWNLOAD PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subjectStat(String title, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 2),

        Text(title, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isSubjectReport =
        widget.subjectCode != null && widget.subjectCode!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isSubjectReport
              ? '${widget.subjectCode} Report'
              : 'My Attendance Report',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadReport,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48),

                    const SizedBox(height: 12),

                    Text(_errorMessage, textAlign: TextAlign.center),

                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: _loadReport,
                      child: const Text('TRY AGAIN'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadReport,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryCard(),

                  if (_subjects.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: Text(
                            'No attendance classes found for this subject.',
                          ),
                        ),
                      ),
                    ),

                  ..._subjects.map(
                    (subject) =>
                        _buildSubjectCard(Map<String, dynamic>.from(subject)),
                  ),
                ],
              ),
            ),
    );
  }
}
// ============================================================
// FACULTY ATTENDANCE REPORT PAGE STATE
// ============================================================

class _FacultyAttendanceReportPageState
    extends State<FacultyAttendanceReportPage> {
  bool _loading = true;

  String? _errorMessage;

  List<dynamic> _reports = [];

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  // ============================================================
  // SAFE INT CONVERSION
  // ============================================================

  int _toInt(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  // ============================================================
  // SAFE DOUBLE CONVERSION
  // ============================================================

  double _toDouble(dynamic value) {
    if (value == null) {
      return 0.0;
    }

    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0.0;
  }

  // ============================================================
  // SAFE STRING CONVERSION
  // ============================================================

  String _toStringValue(dynamic value) {
    if (value == null) {
      return '';
    }

    if (value.toString() == 'null') {
      return '';
    }

    return value.toString();
  }

  // ============================================================
  // LOAD REPORTS
  // ============================================================

  Future<void> _loadReports() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('================================================');

      debugPrint('LOADING FACULTY ATTENDANCE REPORTS');

      debugPrint('Faculty ID: ${widget.userId}');

      final String url =
          '$backendUrl/faculty/attendance-report/${widget.userId}';

      debugPrint('REPORT URL: $url');

      final response = await http.get(Uri.parse(url));

      debugPrint('REPORT STATUS: ${response.statusCode}');

      debugPrint('REPORT BODY: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Server returned status ${response.statusCode}');
      }

      final dynamic decoded = jsonDecode(response.body);

      if (decoded is List) {
        _reports = List<dynamic>.from(decoded);
      } else if (decoded is Map) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(decoded);

        if (data['reports'] is List) {
          _reports = List<dynamic>.from(data['reports']);
        } else if (data['data'] is List) {
          _reports = List<dynamic>.from(data['data']);
        } else {
          _reports = [data];
        }
      } else {
        _reports = [];
      }

      debugPrint('TOTAL REPORT GROUPS: ${_reports.length}');

      for (int i = 0; i < _reports.length; i++) {
        debugPrint('REPORT ${i + 1}: ${_reports[i]}');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      debugPrint('REPORT ERROR: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // ============================================================
  // DOWNLOAD BUTTON
  // ============================================================

  Widget _buildDownloadButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 21),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DOWNLOAD SESSION PDF
  // ============================================================

  Future<void> _downloadSessionPdf({
    required Map<String, dynamic> session,
    required int sessionNumber,
    required String subjectName,
    required String subjectCode,
  }) async {
    try {
      final pdf = pw.Document();

      // ----------------------------------------------------------
      // SESSION DETAILS
      // ----------------------------------------------------------

      final String semester = _toStringValue(session['semester']);

      final String division = _toStringValue(session['division']);

      final String date = _toStringValue(session['attendance_date']);

      final String startTime = _toStringValue(session['start_time']);

      final String endTime = _toStringValue(session['end_time']);

      final String status = _toStringValue(session['status']);

      // ----------------------------------------------------------
      // TEACHER LOCATION
      // ----------------------------------------------------------

      final String latitude = _toStringValue(
        session['teacher_latitude'] ?? session['allowed_latitude'],
      );

      final String longitude = _toStringValue(
        session['teacher_longitude'] ?? session['allowed_longitude'],
      );

      // ----------------------------------------------------------
      // CLASSROOM DIMENSIONS
      // ----------------------------------------------------------

      final double classroomLength = _toDouble(session['classroom_length']);

      final double classroomWidth = _toDouble(session['classroom_width']);

      // ----------------------------------------------------------
      // STUDENT DATA
      // ----------------------------------------------------------

      final dynamic studentsValue = session['students'];

      final List<dynamic> students = studentsValue is List
          ? List<dynamic>.from(studentsValue)
          : <dynamic>[];

      int present = 0;
      int absent = 0;
      int late = 0;

      for (final student in students) {
        if (student is! Map) {
          continue;
        }

        final String studentStatus = _toStringValue(
          student['status'],
        ).toLowerCase();

        if (studentStatus == 'present') {
          present++;
        } else if (studentStatus == 'late') {
          late++;
        } else {
          absent++;
        }
      }

      final int total = students.length;

      final double percentage = total > 0
          ? ((present + late) / total) * 100
          : 0.0;

      // ==========================================================
      // PDF PAGE
      // ==========================================================

      pdf.addPage(
        pw.MultiPage(
          build: (context) {
            return [
              // --------------------------------------------------
              // TITLE
              // --------------------------------------------------
              pw.Center(
                child: pw.Text(
                  'ATTENDANCE REPORT',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 15),

              // --------------------------------------------------
              // SUBJECT DETAILS
              // --------------------------------------------------
              pw.Text(
                'Subject: $subjectName',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.Text('Subject Code: $subjectCode'),

              pw.Text('Semester: $semester'),

              pw.Text('Division: $division'),

              pw.SizedBox(height: 10),

              // --------------------------------------------------
              // SESSION DETAILS
              // --------------------------------------------------
              pw.Text(
                'Session: $sessionNumber',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),

              pw.Text('Date: $date'),

              pw.Text('Time: $startTime - $endTime'),

              pw.Text('Status: ${status.toUpperCase()}'),

              pw.SizedBox(height: 8),

              // --------------------------------------------------
              // TEACHER LOCATION
              // --------------------------------------------------
              pw.Text('Teacher Latitude: $latitude'),

              pw.Text('Teacher Longitude: $longitude'),

              // --------------------------------------------------
              // CLASSROOM DIMENSIONS
              // --------------------------------------------------
              pw.Text(
                'Classroom Size: '
                '${classroomLength.toStringAsFixed(1)} m × '
                '${classroomWidth.toStringAsFixed(1)} m',
              ),

              pw.SizedBox(height: 18),

              // --------------------------------------------------
              // ATTENDANCE SUMMARY
              // --------------------------------------------------
              pw.Text(
                'Attendance Summary',
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 8),

              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    children: [
                      _pdfCell('Present', bold: true),
                      _pdfCell('Absent', bold: true),
                      _pdfCell('Late', bold: true),
                      _pdfCell('Total', bold: true),
                      _pdfCell('Attendance %', bold: true),
                    ],
                  ),

                  pw.TableRow(
                    children: [
                      _pdfCell(present.toString()),
                      _pdfCell(absent.toString()),
                      _pdfCell(late.toString()),
                      _pdfCell(total.toString()),
                      _pdfCell('${percentage.toStringAsFixed(2)}%'),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 20),

              // --------------------------------------------------
              // STUDENT ATTENDANCE
              // --------------------------------------------------
              pw.Text(
                'Student Attendance',
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 8),

              pw.Table.fromTextArray(
                headers: ['USN', 'Name', 'Status', 'Face', 'GPS'],
                data: students.map((student) {
                  if (student is! Map) {
                    return ['-', '-', '-', '-', '-'];
                  }

                  final Map<String, dynamic> map = Map<String, dynamic>.from(
                    student,
                  );

                  return [
                    _toStringValue(map['usn']),
                    _toStringValue(map['student_name']),
                    _toStringValue(map['status']),
                    map['face_verified'] == true ? 'Verified' : 'No',
                    map['gps_verified'] == true ? 'Verified' : 'No',
                  ];
                }).toList(),

                cellStyle: const pw.TextStyle(fontSize: 8),

                headerStyle: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),

                cellPadding: const pw.EdgeInsets.all(5),
              ),
            ];
          },
        ),
      );

      // ==========================================================
      // SAVE PDF
      // ==========================================================

      final Uint8List bytes = await pdf.save();

      final String filename = '${subjectCode}_Session_$sessionNumber.pdf';

      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      debugPrint('SESSION PDF ERROR: $e');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to generate session PDF: $e')),
      );
    }
  }

  // ============================================================
  // PDF TABLE CELL
  // ============================================================

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // ============================================================
  // DOWNLOAD SUBJECT SUMMARY PDF
  // ============================================================

  Future<void> _downloadSubjectSummaryPdf({
    required Map<String, dynamic> report,
    required List<dynamic> sessions,
    required String subjectName,
    required String subjectCode,
    required String semester,
    required String division,
  }) async {
    try {
      final pdf = pw.Document();

      // ========================================================
      // STUDENT AGGREGATION
      // ========================================================

      final Map<String, Map<String, dynamic>> studentSummary = {};

      for (final sessionValue in sessions) {
        if (sessionValue is! Map) {
          continue;
        }

        final Map<String, dynamic> session = Map<String, dynamic>.from(
          sessionValue,
        );

        final dynamic studentsValue = session['students'];

        if (studentsValue is! List) {
          continue;
        }

        final List<dynamic> sessionStudents = List<dynamic>.from(studentsValue);

        for (final studentValue in sessionStudents) {
          if (studentValue is! Map) {
            continue;
          }

          final Map<String, dynamic> student = Map<String, dynamic>.from(
            studentValue,
          );

          final String usn = _toStringValue(student['usn']);

          final String name = _toStringValue(student['student_name']);

          // ----------------------------------------------------
          // IDENTIFY STUDENT
          // ----------------------------------------------------

          final String key = usn.isNotEmpty
              ? usn
              : '${student['student_id'] ?? name}';

          if (!studentSummary.containsKey(key)) {
            studentSummary[key] = {
              'usn': usn,
              'name': name,
              'attended': 0,
              'absent': 0,
            };
          }

          final String studentStatus = _toStringValue(
            student['status'],
          ).trim().toLowerCase();

          // ----------------------------------------------------
          // ATTENDANCE COUNT
          // ----------------------------------------------------

          if (studentStatus == 'present' || studentStatus == 'late') {
            studentSummary[key]!['attended'] =
                _toInt(studentSummary[key]!['attended']) + 1;
          } else {
            studentSummary[key]!['absent'] =
                _toInt(studentSummary[key]!['absent']) + 1;
          }
        }
      }

      // ========================================================
      // TOTAL CLASSES
      // ========================================================

      final int totalClasses = sessions.length;

      // ========================================================
      // PDF
      // ========================================================

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return [
              pw.Center(
                child: pw.Text(
                  'SESSION SUMMARY',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 18),

              pw.Text(
                'Subject: $subjectName',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.Text('Subject Code: $subjectCode'),

              pw.Text('Semester: $semester'),

              pw.Text('Division: $division'),

              pw.Text('Total Classes: $totalClasses'),

              pw.SizedBox(height: 20),

              // =================================================
              // SUMMARY TABLE
              // =================================================
              pw.TableHelper.fromTextArray(
                headers: [
                  'USN',
                  'Name',
                  'Classes Attended',
                  'Classes Absent',
                  'Total Classes',
                  'Attendance %',
                ],
                data: studentSummary.values.map((student) {
                  final int attended = _toInt(student['attended']);

                  final int absent = _toInt(student['absent']);

                  final double percentage = totalClasses > 0
                      ? (attended / totalClasses) * 100
                      : 0.0;

                  return [
                    _toStringValue(student['usn']),
                    _toStringValue(student['name']),
                    attended.toString(),
                    absent.toString(),
                    totalClasses.toString(),
                    '${percentage.toStringAsFixed(2)}%',
                  ];
                }).toList(),
                border: pw.TableBorder.all(),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerStyle: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellPadding: const pw.EdgeInsets.all(5),
                headerDecoration: const pw.BoxDecoration(),
              ),

              pw.SizedBox(height: 25),

              pw.Text(
                'Generated by AntiProxy Smart Attendance',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ];
          },
        ),
      );

      final bytes = await pdf.save();

      final String filename = '${subjectCode}_Session_Summary.pdf';

      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      debugPrint('SUBJECT SUMMARY PDF ERROR: $e');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to generate subject summary: $e')),
      );
    }
  }

  // ============================================================
  // SESSION REPORT
  // ============================================================

  Widget _buildSessionReport(dynamic report) {
    if (report is! Map) {
      return const SizedBox.shrink();
    }

    final Map<String, dynamic> reportMap = Map<String, dynamic>.from(report);

    // ----------------------------------------------------------
    // SUBJECT INFORMATION
    // ----------------------------------------------------------

    final dynamic sessionValue = reportMap['session'];

    final Map<String, dynamic> latestSession = sessionValue is Map
        ? Map<String, dynamic>.from(sessionValue)
        : <String, dynamic>{};

    final String subjectName = _toStringValue(
      latestSession['subject_name'] ?? reportMap['subject_name'],
    );

    final String subjectCode = _toStringValue(
      latestSession['subject_code'] ?? reportMap['subject_code'],
    );

    final String semester = _toStringValue(
      latestSession['semester'] ?? reportMap['semester'],
    );

    final String division = _toStringValue(
      latestSession['division'] ?? reportMap['division'],
    );

    // ----------------------------------------------------------
    // READ ALL SESSIONS
    // ----------------------------------------------------------

    final dynamic sessionsValue = reportMap['sessions'];

    final List<dynamic> sessions =
        sessionsValue is List && sessionsValue.isNotEmpty
        ? List<dynamic>.from(sessionsValue)
        : <dynamic>[latestSession];

    debugPrint(
      'UI SUBJECT REPORT: '
      '$subjectCode | '
      'Sessions=${sessions.length}',
    );

    // ----------------------------------------------------------
    // SUBJECT CARD
    // ----------------------------------------------------------

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==================================================
            // SUBJECT HEADER
            // ==================================================
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.book,
                    color: Colors.indigo.shade700,
                    size: 30,
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subjectName.isEmpty ? 'Subject' : subjectName,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        subjectCode,
                        style: TextStyle(
                          fontSize: 17,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        'Semester $semester • Division $division',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // ==================================================
            // TOTAL SESSIONS
            // ==================================================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.library_books,
                    color: Colors.indigo.shade700,
                    size: 28,
                  ),

                  const SizedBox(width: 12),

                  const Expanded(
                    child: Text(
                      'Total sessions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Text(
                    sessions.length.toString(),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ==================================================
            // SUBJECT SUMMARY DOWNLOAD
            // ==================================================
            _buildDownloadButton(
              label: 'Download Subject Summary',
              icon: Icons.summarize,
              onPressed: () {
                _downloadSubjectSummaryPdf(
                  report: reportMap,
                  sessions: sessions,
                  subjectName: subjectName,
                  subjectCode: subjectCode,
                  semester: semester,
                  division: division,
                );
              },
            ),

            const SizedBox(height: 24),

            // ==================================================
            // EACH SESSION
            // ==================================================
            ...List.generate(sessions.length, (index) {
              final dynamic sessionValue = sessions[index];

              if (sessionValue is! Map) {
                return const SizedBox.shrink();
              }

              final Map<String, dynamic> session = Map<String, dynamic>.from(
                sessionValue,
              );

              return _buildIndividualSession(
                session,
                index + 1,
                subjectName,
                subjectCode,
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INDIVIDUAL SESSION
  // ============================================================

  Widget _buildIndividualSession(
    Map<String, dynamic> session,
    int sessionNumber,
    String subjectName,
    String subjectCode,
  ) {
    // ----------------------------------------------------------
    // SUMMARY
    // ----------------------------------------------------------

    final dynamic summaryValue = session['summary'];

    final Map<String, dynamic> summary = summaryValue is Map
        ? Map<String, dynamic>.from(summaryValue)
        : <String, dynamic>{};

    // ----------------------------------------------------------
    // STUDENTS
    // ----------------------------------------------------------

    final dynamic studentsValue = session['students'];

    final List<dynamic> students = studentsValue is List
        ? List<dynamic>.from(studentsValue)
        : <dynamic>[];

    // ----------------------------------------------------------
    // COUNTS
    // ----------------------------------------------------------

    int totalStudents = _toInt(
      summary['total_students'] ?? session['total_students'],
    );

    int presentCount = _toInt(summary['present'] ?? session['present']);

    int absentCount = _toInt(summary['absent'] ?? session['absent']);

    int lateCount = _toInt(summary['late'] ?? session['late']);

    double attendancePercentage = _toDouble(
      summary['attendance_percentage'] ?? session['attendance_percentage'],
    );

    // ----------------------------------------------------------
    // FALLBACK FROM STUDENTS
    // ----------------------------------------------------------

    if (students.isNotEmpty) {
      totalStudents = students.length;

      presentCount = 0;
      absentCount = 0;
      lateCount = 0;

      for (final student in students) {
        if (student is! Map) {
          continue;
        }

        final String studentStatus = _toStringValue(
          student['status'],
        ).trim().toLowerCase();

        if (studentStatus == 'present') {
          presentCount++;
        } else if (studentStatus == 'late') {
          lateCount++;
        } else {
          absentCount++;
        }
      }

      attendancePercentage = totalStudents > 0
          ? ((presentCount + lateCount) / totalStudents) * 100
          : 0.0;
    }

    // ----------------------------------------------------------
    // SESSION INFORMATION
    // ----------------------------------------------------------

    final String attendanceDate = _toStringValue(session['attendance_date']);

    final String startTime = _toStringValue(session['start_time']);

    final String endTime = _toStringValue(session['end_time']);

    final String status = _toStringValue(session['status']);

    // ==========================================================
    // LOCATION
    // ==========================================================

    final dynamic lengthValue = session['classroom_length'];

    final dynamic widthValue = session['classroom_width'];

    final dynamic latitudeValue =
        session['teacher_latitude'] ?? session['allowed_latitude'];

    final dynamic longitudeValue =
        session['teacher_longitude'] ?? session['allowed_longitude'];

    final double classroomLength = _toDouble(lengthValue);

    final double classroomWidth = _toDouble(widthValue);

    final String latitude = _toStringValue(latitudeValue);

    final String longitude = _toStringValue(longitudeValue);

    // ==========================================================
    // SESSION CARD
    // ==========================================================

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ==================================================
          // DATE + SESSION NUMBER
          // ==================================================
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.calendar_today,
                    color: Colors.indigo.shade700,
                    size: 24,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attendanceDate.isEmpty
                            ? 'Date not available'
                            : attendanceDate,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        'Session $sessionNumber',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                if (status.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: status.toLowerCase() == 'active'
                          ? Colors.green.shade100
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: status.toLowerCase() == 'active'
                            ? Colors.green.shade800
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ==================================================
          // DOWNLOAD SESSION BUTTON
          // ==================================================
          _buildDownloadButton(
            label: 'Download Session $sessionNumber',
            icon: Icons.download,
            onPressed: () {
              _downloadSessionPdf(
                session: session,
                sessionNumber: sessionNumber,
                subjectName: subjectName,
                subjectCode: subjectCode,
              );
            },
          ),

          const SizedBox(height: 20),

          // ==================================================
          // SESSION INFORMATION
          // ==================================================
          const Text(
            'Session Information',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 14),

          _buildInfoRow(Icons.calendar_today, 'Date', attendanceDate),

          _buildInfoRow(Icons.access_time, 'Time', '$startTime - $endTime'),

          _buildInfoRow(
            Icons.school,
            'Semester',
            _toStringValue(session['semester']),
          ),

          _buildInfoRow(
            Icons.groups,
            'Division',
            _toStringValue(session['division']),
          ),

          _buildInfoRow(
            Icons.location_on,
            'Geofence radius',
            'Classroom Size: '
                '${classroomLength.toStringAsFixed(1)} m × '
                '${classroomWidth.toStringAsFixed(1)} m',
          ),

          _buildInfoRow(
            Icons.location_pin,
            'Teacher latitude',
            latitude.isEmpty ? 'Not available' : latitude,
          ),

          _buildInfoRow(
            Icons.location_pin,
            'Teacher longitude',
            longitude.isEmpty ? 'Not available' : longitude,
          ),

          const SizedBox(height: 18),

          // ==================================================
          // ATTENDANCE SUMMARY
          // ==================================================
          const Text(
            'Attendance Summary',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.check_circle,
                  value: presentCount,
                  label: 'Present',
                  color: Colors.green,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.cancel,
                  value: absentCount,
                  label: 'Absent',
                  color: Colors.red,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.access_time,
                  value: lateCount,
                  label: 'Late',
                  color: Colors.orange,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ==================================================
          // TOTAL STUDENTS
          // ==================================================
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.lightBlue.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.groups, color: Colors.lightBlue.shade700, size: 28),

                const SizedBox(width: 12),

                const Expanded(
                  child: Text(
                    'Total students',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),

                Text(
                  totalStudents.toString(),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.lightBlue.shade700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ==================================================
          // ATTENDANCE PERCENTAGE
          // ==================================================
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.percent, color: Colors.indigo.shade700, size: 28),

                const SizedBox(width: 12),

                const Expanded(
                  child: Text(
                    'Attendance percentage',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),

                Text(
                  '${attendancePercentage.toStringAsFixed(2)}%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ==================================================
          // STUDENT ATTENDANCE
          // ==================================================
          const Text(
            'Student Attendance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          if (students.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                'No student attendance records found for this session.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            ...students.map((student) {
              if (student is! Map) {
                return const SizedBox.shrink();
              }

              return _buildStudentAttendance(
                Map<String, dynamic>.from(student),
              );
            }),
        ],
      ),
    );
  }

  // ============================================================
  // INFO ROW
  // ============================================================

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Icon(icon, color: Colors.indigo, size: 28),
          ),

          const SizedBox(width: 10),

          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUMMARY CARD
  // ============================================================

  Widget _buildSummaryCard({
    required IconData icon,
    required int value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 34),

          const SizedBox(height: 10),

          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            label,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STUDENT ATTENDANCE
  // ============================================================

  Widget _buildStudentAttendance(Map<String, dynamic> student) {
    final String name = _toStringValue(student['student_name']).isEmpty
        ? 'Unknown Student'
        : _toStringValue(student['student_name']);

    final String usn = _toStringValue(student['usn']).isEmpty
        ? '-'
        : _toStringValue(student['usn']);

    final String status = _toStringValue(student['status']).isEmpty
        ? 'Absent'
        : _toStringValue(student['status']);

    final bool faceVerified = student['face_verified'] == true;

    final bool gpsVerified = student['gps_verified'] == true;

    final dynamic distanceValue = student['distance'];

    final dynamic attendanceDate = student['attendance_date'];

    final dynamic attendanceTime = student['attendance_time'];

    Color statusColor;

    switch (status.toLowerCase()) {
      case 'present':
        statusColor = Colors.green;
        break;

      case 'late':
        statusColor = Colors.orange;
        break;

      default:
        statusColor = Colors.red;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ==================================================
          // STUDENT HEADER
          // ==================================================
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  status.toLowerCase() == 'present'
                      ? Icons.check
                      : status.toLowerCase() == 'late'
                      ? Icons.access_time
                      : Icons.close,
                  color: statusColor,
                  size: 26,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      usn,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          // ==================================================
          // MARKED DATE/TIME
          // ==================================================
          if (status.toLowerCase() != 'absent' &&
              attendanceDate != null &&
              attendanceDate.toString().isNotEmpty &&
              attendanceDate.toString() != 'null') ...[
            const SizedBox(height: 10),

            Text(
              'Marked: '
              '${attendanceDate.toString()}'
              '${attendanceTime != null ? ' ${attendanceTime.toString()}' : ''}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],

          // ==================================================
          // VERIFICATION
          // ==================================================
          if (status.toLowerCase() != 'absent') ...[
            const SizedBox(height: 12),

            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      faceVerified ? Icons.face : Icons.face_retouching_off,
                      color: faceVerified ? Colors.green : Colors.red,
                      size: 20,
                    ),

                    const SizedBox(width: 6),

                    Text(
                      faceVerified ? 'Face verified' : 'Face not verified',
                      style: TextStyle(
                        color: faceVerified ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      gpsVerified ? Icons.location_on : Icons.location_off,
                      color: gpsVerified ? Colors.green : Colors.red,
                      size: 20,
                    ),

                    const SizedBox(width: 6),

                    Text(
                      gpsVerified ? 'GPS verified' : 'GPS not verified',
                      style: TextStyle(
                        color: gpsVerified ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (distanceValue != null) ...[
              const SizedBox(height: 7),

              Text(
                'Distance from teacher: '
                '${_toDouble(distanceValue).toStringAsFixed(2)} m',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadReports,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 60,
                      color: Colors.red,
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'Unable to load reports',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(_errorMessage!, textAlign: TextAlign.center),

                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: _loadReports,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _reports.isEmpty
          ? const Center(
              child: Text(
                'No attendance reports found.',
                style: TextStyle(fontSize: 18),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadReports,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Attendance Reports',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Each subject is grouped by subject code, with every class shown as a separate session.',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 20),

                  ..._reports.map((report) => _buildSessionReport(report)),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// ADMIN DASHBOARD
// ============================================================
