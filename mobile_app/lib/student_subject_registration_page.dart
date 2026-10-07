import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String backendUrl = 'http://10.252.141.207:5000';

class StudentSubjectRegistrationPage extends StatefulWidget {
  const StudentSubjectRegistrationPage({
    super.key,
    required this.username,
  });

  final String username;

  @override
  State<StudentSubjectRegistrationPage> createState() =>
      _StudentSubjectRegistrationPageState();
}

class _StudentSubjectRegistrationPageState
    extends State<StudentSubjectRegistrationPage> {
  bool _loading = true;
  String? _errorMessage;
  List<dynamic> _subjects = [];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null || token.isEmpty) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _errorMessage = 'Login session expired. Please login again.';
        });
        return;
      }

      final response = await http.get(
        Uri.parse('$backendUrl/student/subjects/available'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;

        setState(() {
          _subjects = data['subjects'] ?? [];
          _loading = false;
        });
      } else if (response.statusCode == 401) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _errorMessage = 'Session expired. Please login again.';
        });
      } else {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _errorMessage =
              data['message']?.toString() ?? 'Failed to load subjects.';
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = 'Unable to connect to the server.';
      });
    }
  }

  Future<void> _registerSubject(String subjectCode) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null || token.isEmpty) {
      _showMessage(
        'Login session expired. Please login again.',
        isError: true,
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/student/subjects/register'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'subject_code': subjectCode,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        _showMessage(
          data['message']?.toString() ??
              'Subject registered successfully.',
        );

        await _loadSubjects();
      } else if (response.statusCode == 409) {
        _showMessage(
          data['message']?.toString() ??
              'Already registered for this subject.',
          isError: true,
        );

        await _loadSubjects();
      } else if (response.statusCode == 401) {
        _showMessage(
          'Session expired. Please login again.',
          isError: true,
        );
      } else {
        _showMessage(
          data['message']?.toString() ??
              'Subject registration failed.',
          isError: true,
        );
      }
    } catch (e) {
      _showMessage(
        'Unable to connect to the server.',
        isError: true,
      );
    }
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildSubjectCard(Map<String, dynamic> subject) {
    final String code =
        subject['subject_code']?.toString() ?? '';

    final String name =
        subject['subject_name']?.toString() ?? '';

    final String semester =
        subject['semester']?.toString() ?? '';

    final String division =
        subject['division']?.toString() ?? '';

    final bool registered =
        subject['registered'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.menu_book_outlined,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Semester $semester • Division $division',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (registered)
              Chip(
                avatar: const Icon(
                  Icons.check_circle,
                  size: 18,
                ),
                label: const Text('Registered'),
              )
            else
              ElevatedButton(
                onPressed: () {
                  _registerSubject(code);
                },
                child: const Text('Register'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return ListView(
      children: const [
        SizedBox(height: 280),
        Center(
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 120),
        const Icon(
          Icons.error_outline,
          size: 64,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _errorMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            onPressed: _loadSubjects,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectList() {
    final List<Widget> subjectWidgets = [];

    if (_subjects.isEmpty) {
      subjectWidgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text(
                'No subjects are currently available.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    } else {
      for (final subject in _subjects) {
        subjectWidgets.add(
          _buildSubjectCard(
            Map<String, dynamic>.from(subject),
          ),
        );
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Student: ${widget.username}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Register for the subjects available for your semester and division.',
        ),
        const SizedBox(height: 20),
        ...subjectWidgets,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_loading) {
      body = _buildLoadingView();
    } else if (_errorMessage != null) {
      body = _buildErrorView();
    } else {
      body = _buildSubjectList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subject Registration'),
        actions: [
          IconButton(
            onPressed: _loadSubjects,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSubjects,
        child: body,
      ),
    );
  }
}