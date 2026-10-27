import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Keep this URL in sync with the backendUrl in main.dart.
const String backendUrl = 'http://10.41.202.207:5000';

class StudentSubjectRegistrationPage extends StatefulWidget {
  const StudentSubjectRegistrationPage({super.key, required this.username});

  final String username;

  @override
  State<StudentSubjectRegistrationPage> createState() =>
      _StudentSubjectRegistrationPageState();
}

class _StudentSubjectRegistrationPageState
    extends State<StudentSubjectRegistrationPage> {
  bool _loading = true;
  String? _errorMessage;
  final Set<int> _registering = <int>{};
  List<Map<String, dynamic>> _subjects = <Map<String, dynamic>>[];

  static const Color _navy = Color(0xFF173B67);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _canvas = Color(0xFFF6F8FC);

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return (token == null || token.isEmpty) ? null : token;
  }

  Future<void> _loadSubjects() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final token = await _getToken();
      if (token == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorMessage = 'Your session has expired. Please sign in again.';
        });
        return;
      }

      // This matches the Flask blueprint registered in run.py.
      final response = await http.get(
        Uri.parse('$backendUrl/api/student-subjects'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final dynamic decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode == 200 && data['success'] == true) {
        final raw = data['subjects'];
        final items = raw is List
            ? raw
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : <Map<String, dynamic>>[];
        if (!mounted) return;
        setState(() {
          _subjects = items;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorMessage =
              (data['message'] ??
                      (response.statusCode == 401
                          ? 'Your session has expired. Please sign in again.'
                          : 'Could not load subjects (HTTP ${response.statusCode}).'))
                  .toString();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Unable to connect to the server. Please try again.';
      });
      debugPrint('Student subject loading error: $e');
    }
  }

  Future<void> _registerSubject(Map<String, dynamic> subject) async {
    final id = int.tryParse(subject['subject_id']?.toString() ?? '');
    if (id == null || id <= 0 || _registering.contains(id)) return;

    final token = await _getToken();
    if (token == null) {
      _showMessage(
        'Your session has expired. Please sign in again.',
        error: true,
      );
      return;
    }

    setState(() => _registering.add(id));
    try {
      // Backend expects subject_id, not subject_code.
      final response = await http.post(
        Uri.parse('$backendUrl/api/student-subjects/register'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'subject_id': id}),
      );
      final dynamic decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode == 201 && data['success'] == true) {
        _showMessage(
          data['message']?.toString() ?? 'Subject registered successfully.',
        );
        await _loadSubjects();
      } else {
        _showMessage(
          data['message']?.toString() ??
              'Registration failed (HTTP ${response.statusCode}).',
          error: true,
        );
        if (response.statusCode == 409) await _loadSubjects();
      }
    } catch (e) {
      _showMessage(
        'Unable to connect to the server. Please try again.',
        error: true,
      );
      debugPrint('Student subject registration error: $e');
    } finally {
      if (mounted) setState(() => _registering.remove(id));
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? const Color(0xFFB42318)
            : const Color(0xFF16794B),
      ),
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5EAF2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _blue, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF667085),
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

  Widget _subjectCard(Map<String, dynamic> subject) {
    final code = subject['subject_code']?.toString() ?? '—';
    final name = subject['subject_name']?.toString() ?? 'Unnamed subject';
    final semester = subject['semester']?.toString() ?? '—';
    final department = subject['department_name']?.toString() ?? '';
    final id = int.tryParse(subject['subject_id']?.toString() ?? '') ?? -1;
    final registeredValue = subject['is_registered'];
    final registered =
        registeredValue == true ||
        registeredValue == 1 ||
        registeredValue == '1';
    final busy = _registering.contains(id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EAF2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.menu_book_rounded, color: _blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      code,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (registered)
                const _StatusPill(
                  label: 'Registered',
                  color: Color(0xFF16794B),
                  background: Color(0xFFE8F7EF),
                )
              else
                const _StatusPill(
                  label: 'Available',
                  color: Color(0xFF2457C5),
                  background: Color(0xFFEAF1FF),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DetailPill(
                icon: Icons.school_outlined,
                text: 'Semester $semester',
              ),
              if (department.isNotEmpty)
                _DetailPill(
                  icon: Icons.account_balance_outlined,
                  text: department,
                ),
            ],
          ),
          if (!registered) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : () => _registerSubject(subject),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_circle_outline, size: 18),
                label: Text(busy ? 'Registering…' : 'Register for subject'),
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final registeredCount = _subjects.where((s) {
      final v = s['is_registered'];
      return v == true || v == 1 || v == '1';
    }).length;

    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        elevation: 0,
        title: const Text(
          'Subject Registration',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadSubjects,
            tooltip: 'Refresh subjects',
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5EAF2)),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSubjects,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 70),
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 52,
                    color: Color(0xFF98A2B3),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF475467)),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _loadSubjects,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE5EAF2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your subjects',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Hello ${widget.username}, view available subjects and manage your registrations.',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Color(0xFF667085),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _summaryCard(
                              icon: Icons.library_books_outlined,
                              label: 'Available subjects',
                              value: '${_subjects.length}',
                            ),
                            const SizedBox(width: 10),
                            _summaryCard(
                              icon: Icons.verified_outlined,
                              label: 'Registered',
                              value: '$registeredCount',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Subject catalogue',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Registration status is updated from the server.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
                  ),
                  const SizedBox(height: 12),
                  if (_subjects.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5EAF2)),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            size: 38,
                            color: Color(0xFF98A2B3),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'No subjects are currently available for your academic group.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF667085)),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._subjects.map(_subjectCard),
                ],
              ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.background,
  });
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 280),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F8FC),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF667085)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF475467)),
          ),
        ),
      ],
    ),
  );
}
