from functools import wraps
from flask import Blueprint, request, jsonify
from database import get_db_connection
from utils.auth import token_required

admin_bp = Blueprint("admin", __name__, url_prefix="/admin")


# ============================================================
# HELPERS
# ============================================================

def admin_required(view_func):
    """
    Admin-only decorator.

    token_required validates the Bearer token and stores the
    authenticated user on request.auth_user.
    """
    @wraps(view_func)
    @token_required
    def wrapped(*args, **kwargs):
        user = getattr(request, "auth_user", None)

        if not user:
            return jsonify({
                "success": False,
                "message": "Authentication required"
            }), 401

        role = str(user.get("role", "")).lower()

        if role not in ("admin", "administrator"):
            return jsonify({
                "success": False,
                "message": "Admin access required"
            }), 403

        return view_func(*args, **kwargs)

    return wrapped


def get_connection():
    return get_db_connection()


def serialize_value(value):
    if value is None:
        return None

    if hasattr(value, "total_seconds"):
        total_seconds = int(value.total_seconds())
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        seconds = total_seconds % 60
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"

    if hasattr(value, "isoformat"):
        return value.isoformat()

    return value


def serialize_rows(rows):
    result = []

    for row in rows:
        item = {}

        for key, value in row.items():
            item[key] = serialize_value(value)

        result.append(item)

    return result


def query_rows(sql, params=()):
    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)
        cursor.execute(sql, params)
        return serialize_rows(cursor.fetchall())

    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()


def query_one(sql, params=()):
    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)
        cursor.execute(sql, params)
        row = cursor.fetchone()

        if not row:
            return None

        return serialize_rows([row])[0]

    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()


def get_query_param(name, default=None):
    value = request.args.get(name)

    if value is None:
        return default

    value = value.strip()

    return value if value else default


def parse_int_param(name):
    value = get_query_param(name)

    if value is None:
        return None

    try:
        return int(value)
    except (TypeError, ValueError):
        return None


# ============================================================
# 1. ADMIN DASHBOARD
# ============================================================

@admin_bp.route("/dashboard", methods=["GET"])
@admin_required
def admin_dashboard():
    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("SELECT COUNT(*) AS total_departments FROM departments")
        total_departments = cursor.fetchone()["total_departments"]

        cursor.execute("SELECT COUNT(*) AS total_students FROM students")
        total_students = cursor.fetchone()["total_students"]

        cursor.execute("SELECT COUNT(*) AS total_faculty FROM faculty")
        total_faculty = cursor.fetchone()["total_faculty"]

        cursor.execute("SELECT COUNT(*) AS total_subjects FROM subjects")
        total_subjects = cursor.fetchone()["total_subjects"]

        cursor.execute("SELECT COUNT(*) AS total_sessions FROM attendance_sessions")
        total_sessions = cursor.fetchone()["total_sessions"]

        cursor.execute("SELECT COUNT(*) AS total_attendance_records FROM attendance")
        total_attendance_records = cursor.fetchone()["total_attendance_records"]

        cursor.execute("""
            SELECT COUNT(*) AS active_sessions
            FROM attendance_sessions
            WHERE status = 'active'
        """)
        active_sessions = cursor.fetchone()["active_sessions"]

        # Department overview.
        cursor.execute("""
            SELECT
                d.id,
                d.department_code,
                d.department_name,

                (
                    SELECT COUNT(*)
                    FROM students s
                    WHERE s.department = d.department_code
                       OR s.department = d.department_name
                ) AS student_count,

                (
                    SELECT COUNT(*)
                    FROM faculty f
                    WHERE f.department = d.department_code
                       OR f.department = d.department_name
                ) AS faculty_count,

                (
                    SELECT COUNT(*)
                    FROM subjects sub
                    WHERE sub.department_id = d.id
                ) AS subject_count

            FROM departments d

            ORDER BY d.department_name
        """)

        departments = serialize_rows(cursor.fetchall())

        department_overview = []

        for department in departments:
            department_overview.append({
                "department_id": department.get("id"),
                "department_code": department.get("department_code"),
                "department_name": department.get("department_name"),
                "total_students": department.get("student_count", 0),
                "total_faculty": department.get("faculty_count", 0),
                "total_teachers": department.get("faculty_count", 0),
                "total_subjects": department.get("subject_count", 0)
            })

        # Recent sessions.
        cursor.execute("""
            SELECT
                a.id,
                a.class_name,
                a.subject_name,
                a.subject_code,
                a.semester,
                a.division,
                a.attendance_date,
                a.start_time,
                a.end_time,
                a.status,
                f.faculty_id,
                f.full_name AS faculty_name

            FROM attendance_sessions a

            LEFT JOIN faculty f
                ON f.id = a.faculty_id

            ORDER BY
                a.attendance_date DESC,
                a.start_time DESC,
                a.id DESC

            LIMIT 10
        """)

        recent_sessions = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,

            "overview": {
                "active_sessions": active_sessions,
                "total_attendance_records": total_attendance_records,
                "total_departments": total_departments,
                "total_faculty": total_faculty,
                "total_sessions": total_sessions,
                "total_students": total_students,
                "total_subjects": total_subjects
            },

            "departments": departments,

            "department_overview": department_overview,

            "recent_sessions": recent_sessions
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load admin dashboard",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# 2. DEPARTMENT DETAILS
# ============================================================

@admin_bp.route("/departments/details", methods=["GET"])
@admin_required
def department_details():
    try:
        departments = query_rows("""
            SELECT
                d.id AS department_id,
                d.department_code,
                d.department_name,

                (
                    SELECT COUNT(*)
                    FROM faculty f
                    WHERE f.department = d.department_code
                       OR f.department = d.department_name
                ) AS total_teachers,

                (
                    SELECT COUNT(*)
                    FROM students s
                    WHERE s.department = d.department_code
                       OR s.department = d.department_name
                ) AS total_students

            FROM departments d
            ORDER BY d.department_name
        """)

        return jsonify({
            "success": True,
            "departments": departments
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load department details",
            "error": str(e)
        }), 500


# ============================================================
# 3. STUDENT MANAGEMENT
# ============================================================

@admin_bp.route("/students/departments", methods=["GET"])
@admin_required
def student_departments():
    try:
        rows = query_rows("""
            SELECT DISTINCT
                department
            FROM students
            WHERE department IS NOT NULL
              AND TRIM(department) <> ''
            ORDER BY department
        """)

        return jsonify({
            "success": True,
            "departments": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load student departments",
            "error": str(e)
        }), 500


@admin_bp.route("/students/groups", methods=["GET"])
@admin_required
def student_groups():
    department = get_query_param("department")

    if not department:
        return jsonify({
            "success": False,
            "message": "department is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT DISTINCT
                semester,
                division
            FROM students
            WHERE department = %s
              AND semester IS NOT NULL
              AND division IS NOT NULL
            ORDER BY semester, division
        """, (department,))

        return jsonify({
            "success": True,
            "department": department,
            "groups": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load student groups",
            "error": str(e)
        }), 500


@admin_bp.route("/students/list", methods=["GET"])
@admin_required
def student_list():
    department = get_query_param("department")
    semester = parse_int_param("semester")
    division = get_query_param("division")

    if not department:
        return jsonify({
            "success": False,
            "message": "department is required"
        }), 400

    if semester is None:
        return jsonify({
            "success": False,
            "message": "semester is required"
        }), 400

    if not division:
        return jsonify({
            "success": False,
            "message": "division is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT
                id,
                user_id,
                student_id,
                full_name,
                email,
                department,
                semester,
                division,
                face_registered,
                created_at

            FROM students

            WHERE department = %s
              AND semester = %s
              AND division = %s

            ORDER BY student_id, full_name
        """, (
            department,
            semester,
            division
        ))

        return jsonify({
            "success": True,
            "department": department,
            "semester": semester,
            "division": division,
            "students": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load students",
            "error": str(e)
        }), 500


@admin_bp.route("/students/<int:student_id>", methods=["GET"])
@admin_required
def student_details(student_id):
    try:
        student = query_one("""
            SELECT
                id,
                user_id,
                student_id,
                full_name,
                email,
                department,
                semester,
                division,
                face_registered,
                created_at

            FROM students

            WHERE id = %s
        """, (student_id,))

        if not student:
            return jsonify({
                "success": False,
                "message": "Student not found"
            }), 404

        return jsonify({
            "success": True,
            "student": student
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load student details",
            "error": str(e)
        }), 500


# ============================================================
# 4. FACULTY MANAGEMENT
# ============================================================

@admin_bp.route("/faculty/departments", methods=["GET"])
@admin_required
def faculty_departments():
    try:
        rows = query_rows("""
            SELECT DISTINCT
                department
            FROM faculty
            WHERE department IS NOT NULL
              AND TRIM(department) <> ''
            ORDER BY department
        """)

        return jsonify({
            "success": True,
            "departments": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load faculty departments",
            "error": str(e)
        }), 500


@admin_bp.route("/faculty/list", methods=["GET"])
@admin_required
def faculty_list():
    department = get_query_param("department")

    if not department:
        return jsonify({
            "success": False,
            "message": "department is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT
                id,
                user_id,
                faculty_id,
                full_name,
                email,
                department,
                created_at

            FROM faculty

            WHERE department = %s

            ORDER BY full_name, faculty_id
        """, (department,))

        return jsonify({
            "success": True,
            "department": department,
            "faculty": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load faculty",
            "error": str(e)
        }), 500


@admin_bp.route("/faculty/<int:faculty_id>", methods=["GET"])
@admin_required
def faculty_details(faculty_id):
    try:
        faculty = query_one("""
            SELECT
                id,
                user_id,
                faculty_id,
                full_name,
                email,
                department,
                created_at

            FROM faculty

            WHERE id = %s
        """, (faculty_id,))

        if not faculty:
            return jsonify({
                "success": False,
                "message": "Faculty member not found"
            }), 404

        return jsonify({
            "success": True,
            "faculty": faculty
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load faculty details",
            "error": str(e)
        }), 500


# ============================================================
# 5. SUBJECT MANAGEMENT
# ============================================================

@admin_bp.route("/subjects/departments", methods=["GET"])
@admin_required
def subject_departments():
    try:
        rows = query_rows("""
            SELECT
                id AS department_id,
                department_code,
                department_name

            FROM departments

            ORDER BY department_name
        """)

        return jsonify({
            "success": True,
            "departments": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load subject departments",
            "error": str(e)
        }), 500


@admin_bp.route("/subjects/groups", methods=["GET"])
@admin_required
def subject_groups():
    department_id = parse_int_param(
        "department_id"
    )

    if department_id is None:
        return jsonify({
            "success": False,
            "message": "department_id is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT DISTINCT
                cr.semester,
                cr.division

            FROM class_roster cr

            INNER JOIN subjects s
                ON s.subject_code = cr.subject_code

            WHERE s.department_id = %s

            ORDER BY
                CAST(cr.semester AS UNSIGNED),
                cr.division
        """, (department_id,))

        return jsonify({
            "success": True,
            "department_id": department_id,
            "groups": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load subject groups",
            "error": str(e)
        }), 500


@admin_bp.route("/subjects/list", methods=["GET"])
@admin_required
def subject_list():
    department_id = parse_int_param(
        "department_id"
    )
    semester = parse_int_param("semester")
    division = get_query_param("division")

    if department_id is None:
        return jsonify({
            "success": False,
            "message": "department_id is required"
        }), 400

    if semester is None:
        return jsonify({
            "success": False,
            "message": "semester is required"
        }), 400

    if not division:
        return jsonify({
            "success": False,
            "message": "division is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT
                s.id,
                s.subject_code,
                s.subject_name,
                s.department_id,

                %s AS semester,
                %s AS division,

                COALESCE(
                    GROUP_CONCAT(
                        DISTINCT f.full_name
                        ORDER BY f.full_name
                        SEPARATOR ', '
                    ),
                    'Not assigned'
                ) AS faculty_handling

            FROM subjects s

            LEFT JOIN attendance_sessions a
                ON a.subject_code = s.subject_code
               AND a.semester = %s
               AND a.division = %s

            LEFT JOIN faculty f
                ON f.id = a.faculty_id

            WHERE s.department_id = %s

            GROUP BY
                s.id,
                s.subject_code,
                s.subject_name,
                s.department_id

            ORDER BY s.subject_code
        """, (
            semester,
            division,
            str(semester),
            division,
            department_id
        ))

        return jsonify({
            "success": True,
            "department_id": department_id,
            "semester": semester,
            "division": division,
            "subjects": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load subjects",
            "error": str(e)
        }), 500


# ============================================================
# 6. ATTENDANCE SESSION MANAGEMENT
# ============================================================

@admin_bp.route("/attendance-sessions/departments", methods=["GET"])
@admin_required
def attendance_session_departments():
    try:
        rows = query_rows("""
            SELECT
                d.id AS department_id,
                d.department_code,
                d.department_name

            FROM departments d

            WHERE EXISTS (
                SELECT 1
                FROM subjects s
                WHERE s.department_id = d.id
            )

            ORDER BY d.department_name
        """)

        return jsonify({
            "success": True,
            "departments": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load attendance-session departments",
            "error": str(e)
        }), 500


@admin_bp.route("/attendance-sessions/groups", methods=["GET"])
@admin_required
def attendance_session_groups():
    department_id = parse_int_param(
        "department_id"
    )

    if department_id is None:
        return jsonify({
            "success": False,
            "message": "department_id is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT DISTINCT
                a.semester,
                a.division

            FROM attendance_sessions a

            INNER JOIN subjects s
                ON s.subject_code = a.subject_code

            WHERE s.department_id = %s

            ORDER BY
                CAST(a.semester AS UNSIGNED),
                a.division
        """, (department_id,))

        return jsonify({
            "success": True,
            "department_id": department_id,
            "groups": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load attendance-session groups",
            "error": str(e)
        }), 500


@admin_bp.route("/attendance-sessions/subjects", methods=["GET"])
@admin_required
def attendance_session_subjects():
    department_id = parse_int_param(
        "department_id"
    )
    semester = parse_int_param("semester")
    division = get_query_param("division")

    if department_id is None:
        return jsonify({
            "success": False,
            "message": "department_id is required"
        }), 400

    if semester is None:
        return jsonify({
            "success": False,
            "message": "semester is required"
        }), 400

    if not division:
        return jsonify({
            "success": False,
            "message": "division is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT DISTINCT
                a.subject_code,
                COALESCE(
                    NULLIF(a.subject_name, ''),
                    s.subject_name
                ) AS subject_name

            FROM attendance_sessions a

            INNER JOIN subjects s
                ON s.subject_code = a.subject_code

            WHERE s.department_id = %s
              AND a.semester = %s
              AND a.division = %s

            ORDER BY a.subject_code
        """, (
            department_id,
            str(semester),
            division
        ))

        return jsonify({
            "success": True,
            "department_id": department_id,
            "semester": semester,
            "division": division,
            "subjects": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load attendance-session subjects",
            "error": str(e)
        }), 500


@admin_bp.route("/attendance-sessions/list", methods=["GET"])
@admin_required
def attendance_session_list():
    department_id = parse_int_param(
        "department_id"
    )
    semester = parse_int_param("semester")
    division = get_query_param("division")
    subject_code = get_query_param(
        "subject_code"
    )

    if department_id is None:
        return jsonify({
            "success": False,
            "message": "department_id is required"
        }), 400

    if semester is None:
        return jsonify({
            "success": False,
            "message": "semester is required"
        }), 400

    if not division:
        return jsonify({
            "success": False,
            "message": "division is required"
        }), 400

    if not subject_code:
        return jsonify({
            "success": False,
            "message": "subject_code is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT
                a.id,
                a.faculty_id,
                a.class_name,
                a.subject_name,
                a.subject_code,
                a.semester,
                a.division,
                a.attendance_date,
                a.start_time,
                a.end_time,
                a.allowed_latitude,
                a.allowed_longitude,
                a.allowed_radius,
                a.status,
                a.created_at,

                f.faculty_id AS faculty_employee_id,
                f.full_name AS faculty_name

            FROM attendance_sessions a

            INNER JOIN subjects s
                ON s.subject_code = a.subject_code

            LEFT JOIN faculty f
                ON f.id = a.faculty_id

            WHERE s.department_id = %s
              AND a.semester = %s
              AND a.division = %s
              AND a.subject_code = %s

            ORDER BY
                a.attendance_date DESC,
                a.start_time DESC,
                a.id DESC
        """, (
            department_id,
            str(semester),
            division,
            subject_code
        ))

        return jsonify({
            "success": True,
            "department_id": department_id,
            "semester": semester,
            "division": division,
            "subject_code": subject_code,
            "sessions": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load attendance sessions",
            "error": str(e)
        }), 500


# ============================================================
# 7. ATTENDANCE RECORD MANAGEMENT
# ============================================================

@admin_bp.route("/attendance-records/departments", methods=["GET"])
@admin_required
def attendance_record_departments():
    try:
        rows = query_rows("""
            SELECT
                d.id AS department_id,
                d.department_code,
                d.department_name

            FROM departments d

            WHERE EXISTS (
                SELECT 1
                FROM subjects s
                WHERE s.department_id = d.id
            )

            ORDER BY d.department_name
        """)

        return jsonify({
            "success": True,
            "departments": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load attendance-record departments",
            "error": str(e)
        }), 500


@admin_bp.route("/attendance-records/groups", methods=["GET"])
@admin_required
def attendance_record_groups():
    department_id = parse_int_param(
        "department_id"
    )

    if department_id is None:
        return jsonify({
            "success": False,
            "message": "department_id is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT DISTINCT
                a.semester,
                a.division

            FROM attendance_sessions a

            INNER JOIN subjects s
                ON s.subject_code = a.subject_code

            WHERE s.department_id = %s

            ORDER BY
                CAST(a.semester AS UNSIGNED),
                a.division
        """, (department_id,))

        return jsonify({
            "success": True,
            "department_id": department_id,
            "groups": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load attendance-record groups",
            "error": str(e)
        }), 500


@admin_bp.route("/attendance-records/subjects", methods=["GET"])
@admin_required
def attendance_record_subjects():
    department_id = parse_int_param(
        "department_id"
    )
    semester = parse_int_param("semester")
    division = get_query_param("division")

    if department_id is None:
        return jsonify({
            "success": False,
            "message": "department_id is required"
        }), 400

    if semester is None:
        return jsonify({
            "success": False,
            "message": "semester is required"
        }), 400

    if not division:
        return jsonify({
            "success": False,
            "message": "division is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT DISTINCT
                a.subject_code,
                COALESCE(
                    NULLIF(a.subject_name, ''),
                    s.subject_name
                ) AS subject_name

            FROM attendance_sessions a

            INNER JOIN subjects s
                ON s.subject_code = a.subject_code

            WHERE s.department_id = %s
              AND a.semester = %s
              AND a.division = %s

            ORDER BY a.subject_code
        """, (
            department_id,
            str(semester),
            division
        ))

        return jsonify({
            "success": True,
            "department_id": department_id,
            "semester": semester,
            "division": division,
            "subjects": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load attendance-record subjects",
            "error": str(e)
        }), 500


@admin_bp.route("/attendance-records/list", methods=["GET"])
@admin_required
def attendance_record_list():
    department_id = parse_int_param(
        "department_id"
    )
    semester = parse_int_param("semester")
    division = get_query_param("division")
    subject_code = get_query_param(
        "subject_code"
    )

    if department_id is None:
        return jsonify({
            "success": False,
            "message": "department_id is required"
        }), 400

    if semester is None:
        return jsonify({
            "success": False,
            "message": "semester is required"
        }), 400

    if not division:
        return jsonify({
            "success": False,
            "message": "division is required"
        }), 400

    if not subject_code:
        return jsonify({
            "success": False,
            "message": "subject_code is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT
                a.id,
                a.student_id,
                s.student_id AS student_usn,
                s.full_name AS student_name,
                s.email AS student_email,
                s.department,
                s.semester,
                s.division,

                a.session_id,
                a.attendance_date,
                a.attendance_time,
                a.status,
                a.latitude,
                a.longitude,
                a.face_verified,
                a.created_at,

                ses.subject_code,
                ses.subject_name,
                ses.class_name,
                ses.start_time,
                ses.end_time,
                ses.status AS session_status,

                f.faculty_id AS faculty_employee_id,
                f.full_name AS faculty_name

            FROM attendance a

            INNER JOIN students s
                ON s.id = a.student_id

            INNER JOIN attendance_sessions ses
                ON ses.id = a.session_id

            INNER JOIN subjects sub
                ON sub.subject_code = ses.subject_code

            LEFT JOIN faculty f
                ON f.id = ses.faculty_id

            WHERE sub.department_id = %s
              AND ses.semester = %s
              AND ses.division = %s
              AND ses.subject_code = %s

            ORDER BY
                a.attendance_date DESC,
                a.attendance_time DESC,
                s.student_id
        """, (
            department_id,
            str(semester),
            division,
            subject_code
        ))

        return jsonify({
            "success": True,
            "department_id": department_id,
            "semester": semester,
            "division": division,
            "subject_code": subject_code,
            "records": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load attendance records",
            "error": str(e)
        }), 500


# ============================================================
# 8. COMPLETE STUDENT ATTENDANCE HISTORY
# ============================================================

@admin_bp.route("/attendance-records/student-history", methods=["GET"])
@admin_required
def attendance_student_history():
    department_id = parse_int_param(
        "department_id"
    )
    semester = parse_int_param("semester")
    division = get_query_param("division")
    subject_code = get_query_param(
        "subject_code"
    )
    student_id = parse_int_param("student_id")

    if department_id is None:
        return jsonify({
            "success": False,
            "message": "department_id is required"
        }), 400

    if semester is None:
        return jsonify({
            "success": False,
            "message": "semester is required"
        }), 400

    if not division:
        return jsonify({
            "success": False,
            "message": "division is required"
        }), 400

    if not subject_code:
        return jsonify({
            "success": False,
            "message": "subject_code is required"
        }), 400

    if student_id is None:
        return jsonify({
            "success": False,
            "message": "student_id is required"
        }), 400

    try:
        rows = query_rows("""
            SELECT
                s.id AS student_record_id,
                s.student_id AS student_usn,
                s.full_name AS student_name,

                ses.id AS session_id,
                ses.subject_code,
                ses.subject_name,
                ses.attendance_date,
                ses.start_time,
                ses.end_time,
                ses.status AS session_status,

                COALESCE(
                    a.status,
                    'absent'
                ) AS attendance_status,

                a.attendance_time,
                a.latitude,
                a.longitude,
                COALESCE(
                    a.face_verified,
                    0
                ) AS face_verified

            FROM students s

            CROSS JOIN attendance_sessions ses

            INNER JOIN subjects sub
                ON sub.subject_code = ses.subject_code

            LEFT JOIN attendance a
                ON a.student_id = s.id
               AND a.session_id = ses.id

            WHERE s.id = %s
              AND sub.department_id = %s
              AND s.semester = %s
              AND s.division = %s
              AND ses.subject_code = %s
              AND ses.semester = %s
              AND ses.division = %s

            ORDER BY
                ses.attendance_date DESC,
                ses.start_time DESC,
                ses.id DESC
        """, (
            student_id,
            department_id,
            semester,
            division,
            subject_code,
            str(semester),
            division
        ))

        return jsonify({
            "success": True,
            "student_id": student_id,
            "department_id": department_id,
            "semester": semester,
            "division": division,
            "subject_code": subject_code,
            "history": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load student attendance history",
            "error": str(e)
        }), 500


# ============================================================
# 9. USER MANAGEMENT
# ============================================================

@admin_bp.route("/users", methods=["GET"])
@admin_required
def admin_users():
    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        # Students are joined to users so both account and
        # student-profile information are available.
        cursor.execute("""
            SELECT
                u.id AS user_id,
                u.username,
                u.role,

                s.id AS student_record_id,
                s.student_id,
                s.full_name,
                s.email,
                s.department,
                s.semester,
                s.division,
                s.face_registered,
                s.created_at

            FROM users u

            INNER JOIN students s
                ON s.user_id = u.id

            ORDER BY
                s.department,
                s.semester,
                s.division,
                s.student_id
        """)

        students = serialize_rows(
            cursor.fetchall()
        )

        # Faculty are joined to users for account/profile data.
        cursor.execute("""
            SELECT
                u.id AS user_id,
                u.username,
                u.role,

                f.id AS faculty_record_id,
                f.faculty_id,
                f.full_name,
                f.email,
                f.department,
                f.created_at

            FROM users u

            INNER JOIN faculty f
                ON f.user_id = u.id

            ORDER BY
                f.department,
                f.full_name
        """)

        faculty = serialize_rows(
            cursor.fetchall()
        )

        # Administrators only expose non-sensitive account data.
        cursor.execute("""
            SELECT
                id,
                username,
                role,
                created_at

            FROM users

            WHERE LOWER(role) IN (
                'admin',
                'administrator'
            )

            ORDER BY username
        """)

        administrators = serialize_rows(
            cursor.fetchall()
        )

        return jsonify({
            "success": True,
            "students": students,
            "faculty": faculty,
            "administrators": administrators
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load user management data",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route("/users/<int:user_id>", methods=["GET"])
@admin_required
def admin_user_details(user_id):
    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                id,
                username,
                role,
                created_at

            FROM users

            WHERE id = %s
        """, (user_id,))

        user = cursor.fetchone()

        if not user:
            return jsonify({
                "success": False,
                "message": "User not found"
            }), 404

        role = str(
            user.get("role") or ""
        ).lower()

        profile = None
        profile_type = None

        if role == "student":
            cursor.execute("""
                SELECT
                    id,
                    user_id,
                    student_id,
                    full_name,
                    email,
                    department,
                    semester,
                    division,
                    face_registered,
                    created_at

                FROM students

                WHERE user_id = %s
            """, (user_id,))

            profile = cursor.fetchone()
            profile_type = "student"

        elif role in ("faculty", "teacher"):
            cursor.execute("""
                SELECT
                    id,
                    user_id,
                    faculty_id,
                    full_name,
                    email,
                    department,
                    created_at

                FROM faculty

                WHERE user_id = %s
            """, (user_id,))

            profile = cursor.fetchone()
            profile_type = "faculty"

        user = serialize_rows([user])[0]

        if profile:
            profile = serialize_rows([profile])[0]

        return jsonify({
            "success": True,
            "user": user,
            "profile_type": profile_type,
            "profile": profile
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load user details",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# 10. EXISTING GENERAL DEPARTMENT API
# ============================================================

@admin_bp.route("/departments", methods=["GET"])
@admin_required
def admin_departments():
    try:
        rows = query_rows("""
            SELECT
                id,
                department_code,
                department_name,
                created_at

            FROM departments

            ORDER BY department_name
        """)

        return jsonify({
            "success": True,
            "departments": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load departments",
            "error": str(e)
        }), 500


# ============================================================
# 11. EXISTING GENERAL STUDENT API
# ============================================================

@admin_bp.route("/students", methods=["GET"])
@admin_required
def admin_students():
    try:
        rows = query_rows("""
            SELECT
                id,
                user_id,
                student_id,
                full_name,
                email,
                department,
                semester,
                division,
                face_registered,
                created_at

            FROM students

            ORDER BY
                department,
                semester,
                division,
                student_id
        """)

        return jsonify({
            "success": True,
            "students": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load students",
            "error": str(e)
        }), 500


# ============================================================
# 12. EXISTING GENERAL FACULTY API
# ============================================================

@admin_bp.route("/faculty", methods=["GET"])
@admin_required
def admin_faculty():
    try:
        rows = query_rows("""
            SELECT
                id,
                user_id,
                faculty_id,
                full_name,
                email,
                department,
                created_at

            FROM faculty

            ORDER BY
                department,
                full_name
        """)

        return jsonify({
            "success": True,
            "faculty": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load faculty",
            "error": str(e)
        }), 500


# ============================================================
# 13. EXISTING GENERAL SUBJECT API
# ============================================================

@admin_bp.route("/subjects", methods=["GET"])
@admin_required
def admin_subjects():
    try:
        rows = query_rows("""
            SELECT
                s.id,
                s.subject_code,
                s.subject_name,
                s.department_id,
                d.department_code,
                d.department_name,
                s.semester,
                s.created_at

            FROM subjects s

            LEFT JOIN departments d
                ON d.id = s.department_id

            ORDER BY
                d.department_name,
                s.semester,
                s.subject_code
        """)

        return jsonify({
            "success": True,
            "subjects": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load subjects",
            "error": str(e)
        }), 500


# ============================================================
# 14. EXISTING GENERAL ATTENDANCE API
# ============================================================

@admin_bp.route("/attendance", methods=["GET"])
@admin_required
def admin_attendance():
    try:
        rows = query_rows("""
            SELECT
                a.id,
                a.student_id,
                s.student_id AS student_usn,
                s.full_name AS student_name,

                a.session_id,
                ses.subject_code,
                ses.subject_name,
                ses.semester,
                ses.division,

                a.attendance_date,
                a.attendance_time,
                a.status,
                a.latitude,
                a.longitude,
                a.face_verified,
                a.created_at

            FROM attendance a

            LEFT JOIN students s
                ON s.id = a.student_id

            LEFT JOIN attendance_sessions ses
                ON ses.id = a.session_id

            ORDER BY
                a.attendance_date DESC,
                a.attendance_time DESC,
                a.id DESC
        """)

        return jsonify({
            "success": True,
            "attendance": rows
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load attendance",
            "error": str(e)
        }), 500


# ============================================================
# 15. SECURITY CENTER
# ============================================================

@admin_bp.route("/security", methods=["GET"])
@admin_required
def admin_security():
    try:
        summary = query_one("""
            SELECT
                COUNT(*) AS total_records,

                COALESCE(
                    SUM(
                        CASE
                            WHEN status = 'present'
                            THEN 1
                            ELSE 0
                        END
                    ),
                    0
                ) AS present_records,

                COALESCE(
                    SUM(
                        CASE
                            WHEN status = 'late'
                            THEN 1
                            ELSE 0
                        END
                    ),
                    0
                ) AS late_records,

                COALESCE(
                    SUM(
                        CASE
                            WHEN face_verified = 1
                            THEN 1
                            ELSE 0
                        END
                    ),
                    0
                ) AS face_verified_records

            FROM attendance
        """)

        # The current database schema contains face verification
        # information, but it does not contain a dedicated mock-GPS
        # or suspicious-event table. Therefore no fabricated
        # security count is returned for those categories.
        return jsonify({
            "success": True,

            "security": {
                "total_records": int(
                    summary.get(
                        "total_records", 0
                    ) or 0
                ),
                "present_records": int(
                    summary.get(
                        "present_records", 0
                    ) or 0
                ),
                "late_records": int(
                    summary.get(
                        "late_records", 0
                    ) or 0
                ),
                "face_verified_records": int(
                    summary.get(
                        "face_verified_records", 0
                    ) or 0
                )
            },

            "available_controls": [
                "Bearer-token authentication",
                "Admin role authorization",
                "Face verification records"
            ],

            "unavailable_in_database": [
                "Dedicated mock-location event history",
                "Dedicated suspicious-activity event history"
            ]
        }), 200

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load security information",
            "error": str(e)
        }), 500
