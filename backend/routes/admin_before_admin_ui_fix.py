from flask import Blueprint, jsonify, request

from database import get_db_connection
from utils.auth import token_required


admin_bp = Blueprint(
    "admin",
    __name__,
    url_prefix="/admin"
)


# ============================================================
# COMMON HELPERS
# ============================================================

def admin_required():
    """
    Check whether the authenticated user is an administrator.
    token_required must run before this function.
    """
    user = getattr(request, "auth_user", None)

    if not user:
        return jsonify({
            "success": False,
            "message": "Authentication required"
        }), 401

    if user.get("role") != "admin":
        return jsonify({
            "success": False,
            "message": "Admin access required"
        }), 403

    return None


def serialize_value(value):
    """
    Convert MySQL/Python date, time and timedelta values
    into JSON-compatible values.
    """
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


def get_connection():
    return get_db_connection()


# ============================================================
# ADMIN DASHBOARD
# ============================================================

@admin_bp.route("/dashboard", methods=["GET"])
@token_required
def admin_dashboard():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        # ----------------------------------------------------
        # INSTITUTION OVERVIEW
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total_students
            FROM students
        """)
        total_students = cursor.fetchone()["total_students"]

        cursor.execute("""
            SELECT COUNT(*) AS total_faculty
            FROM faculty
        """)
        total_faculty = cursor.fetchone()["total_faculty"]

        cursor.execute("""
            SELECT COUNT(*) AS total_departments
            FROM departments
        """)
        total_departments = cursor.fetchone()["total_departments"]

        cursor.execute("""
            SELECT COUNT(*) AS total_subjects
            FROM subjects
        """)
        total_subjects = cursor.fetchone()["total_subjects"]

        cursor.execute("""
            SELECT COUNT(*) AS total_sessions
            FROM attendance_sessions
        """)
        total_sessions = cursor.fetchone()["total_sessions"]

        cursor.execute("""
            SELECT COUNT(*) AS total_attendance_records
            FROM attendance
        """)
        total_attendance_records = cursor.fetchone()[
            "total_attendance_records"
        ]

        cursor.execute("""
            SELECT COUNT(*) AS active_sessions
            FROM attendance_sessions
            WHERE status = 'active'
        """)
        active_sessions = cursor.fetchone()["active_sessions"]

        # ----------------------------------------------------
        # DEPARTMENT OVERVIEW
        # ----------------------------------------------------

        cursor.execute("""
            SELECT
                d.id,
                d.department_code,
                d.department_name,

                (
                    SELECT COUNT(*)
                    FROM students s
                    WHERE s.department = d.department_name
                ) AS student_count,

                (
                    SELECT COUNT(*)
                    FROM faculty f
                    WHERE f.department = d.department_name
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

        # ----------------------------------------------------
        # RECENT SESSIONS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT
                s.id,
                s.faculty_id,
                s.class_name,
                s.subject_name,
                s.subject_code,
                s.semester,
                s.division,
                s.attendance_date,
                s.start_time,
                s.end_time,
                s.status,
                f.full_name AS faculty_name

            FROM attendance_sessions s

            LEFT JOIN faculty f
                ON f.id = s.faculty_id

            ORDER BY
                s.attendance_date DESC,
                s.start_time DESC

            LIMIT 10
        """)

        recent_sessions = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,

            "overview": {
                "total_students": total_students,
                "total_faculty": total_faculty,
                "total_departments": total_departments,
                "total_subjects": total_subjects,
                "total_sessions": total_sessions,
                "total_attendance_records":
                    total_attendance_records,
                "active_sessions": active_sessions
            },

            "departments": departments,
            "recent_sessions": recent_sessions
        })

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
# 1. DEPARTMENT DETAILS
# ============================================================

@admin_bp.route("/departments/details", methods=["GET"])
@token_required
def department_details():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                d.id AS department_id,
                d.department_code,
                d.department_name,

                (
                    SELECT COUNT(*)
                    FROM faculty f
                    WHERE f.department = d.department_name
                ) AS total_teachers,

                (
                    SELECT COUNT(*)
                    FROM students s
                    WHERE s.department = d.department_name
                ) AS total_students

            FROM departments d

            ORDER BY d.department_name
        """)

        departments = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "departments": departments
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load department details",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# 2. STUDENT MANAGEMENT
# ============================================================

@admin_bp.route("/students/departments", methods=["GET"])
@token_required
def student_departments():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                department

            FROM students

            WHERE department IS NOT NULL
              AND TRIM(department) <> ''

            ORDER BY department
        """)

        departments = cursor.fetchall()

        return jsonify({
            "success": True,
            "departments": departments
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load student departments",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route("/students/groups", methods=["GET"])
@token_required
def student_groups():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department = request.args.get("department", "").strip()

    if not department:
        return jsonify({
            "success": False,
            "message": "Department is required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                semester,
                division

            FROM students

            WHERE department = %s
              AND semester IS NOT NULL
              AND division IS NOT NULL

            ORDER BY semester, division
        """, (department,))

        groups = cursor.fetchall()

        return jsonify({
            "success": True,
            "department": department,
            "groups": groups
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load student groups",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route("/students/list", methods=["GET"])
@token_required
def student_list():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department = request.args.get("department", "").strip()
    semester = request.args.get("semester", "").strip()
    division = request.args.get("division", "").strip()

    if not department or not semester or not division:
        return jsonify({
            "success": False,
            "message":
                "Department, semester and division are required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                s.id,
                s.user_id,
                s.student_id,
                s.full_name,
                s.email,
                s.department,
                s.semester,
                s.division,
                s.face_registered,
                s.created_at

            FROM students s

            WHERE s.department = %s
              AND s.semester = %s
              AND s.division = %s

            ORDER BY s.student_id
        """, (
            department,
            semester,
            division
        ))

        students = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "students": students
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load students",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route(
    "/students/<int:student_id>",
    methods=["GET"]
)
@token_required
def student_details(student_id):
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                s.id,
                s.user_id,
                s.student_id,
                s.full_name,
                s.email,
                s.department,
                s.semester,
                s.division,
                s.face_registered,
                s.created_at

            FROM students s

            WHERE s.id = %s
        """, (student_id,))

        student = cursor.fetchone()

        if not student:
            return jsonify({
                "success": False,
                "message": "Student not found"
            }), 404

        student = serialize_rows([student])[0]

        return jsonify({
            "success": True,
            "student": student
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load student details",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# 3. FACULTY MANAGEMENT
# ============================================================

@admin_bp.route("/faculty/departments", methods=["GET"])
@token_required
def faculty_departments():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                department

            FROM faculty

            WHERE department IS NOT NULL
              AND TRIM(department) <> ''

            ORDER BY department
        """)

        departments = cursor.fetchall()

        return jsonify({
            "success": True,
            "departments": departments
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load faculty departments",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route("/faculty/list", methods=["GET"])
@token_required
def faculty_list():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department = request.args.get("department", "").strip()

    if not department:
        return jsonify({
            "success": False,
            "message": "Department is required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                f.id,
                f.user_id,
                f.faculty_id,
                f.full_name,
                f.email,
                f.department,
                f.created_at

            FROM faculty f

            WHERE f.department = %s

            ORDER BY f.full_name
        """, (department,))

        faculty = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "faculty": faculty
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load faculty",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route(
    "/faculty/<int:faculty_id>",
    methods=["GET"]
)
@token_required
def faculty_details(faculty_id):
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                f.id,
                f.user_id,
                f.faculty_id,
                f.full_name,
                f.email,
                f.department,
                f.created_at

            FROM faculty f

            WHERE f.id = %s
        """, (faculty_id,))

        faculty = cursor.fetchone()

        if not faculty:
            return jsonify({
                "success": False,
                "message": "Faculty member not found"
            }), 404

        faculty = serialize_rows([faculty])[0]

        return jsonify({
            "success": True,
            "faculty": faculty
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load faculty details",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# 4. SUBJECT MANAGEMENT
# ============================================================

@admin_bp.route("/subjects/departments", methods=["GET"])
@token_required
def subject_departments():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                d.id AS department_id,
                d.department_code,
                d.department_name

            FROM departments d

            INNER JOIN subjects s
                ON s.department_id = d.id

            GROUP BY
                d.id,
                d.department_code,
                d.department_name

            ORDER BY d.department_name
        """)

        departments = cursor.fetchall()

        return jsonify({
            "success": True,
            "departments": departments
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load subject departments",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route("/subjects/groups", methods=["GET"])
@token_required
def subject_groups():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department_id = request.args.get(
        "department_id",
        ""
    ).strip()

    if not department_id:
        return jsonify({
            "success": False,
            "message": "Department ID is required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                s.semester,
                r.division

            FROM subjects s

            INNER JOIN class_roster r
                ON r.subject_code = s.subject_code
                AND r.semester = s.semester

            WHERE s.department_id = %s

            ORDER BY
                s.semester,
                r.division
        """, (department_id,))

        groups = cursor.fetchall()

        return jsonify({
            "success": True,
            "groups": groups
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load subject groups",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route("/subjects/list", methods=["GET"])
@token_required
def subject_list():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department_id = request.args.get(
        "department_id",
        ""
    ).strip()

    semester = request.args.get(
        "semester",
        ""
    ).strip()

    division = request.args.get(
        "division",
        ""
    ).strip()

    if not department_id or not semester or not division:
        return jsonify({
            "success": False,
            "message":
                "Department, semester and division are required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                s.id,
                s.subject_code,
                s.subject_name,
                s.department_id,
                s.semester,

                GROUP_CONCAT(
                    DISTINCT f.full_name
                    ORDER BY f.full_name
                    SEPARATOR ', '
                ) AS faculty_handling

            FROM subjects s

            INNER JOIN class_roster r
                ON r.subject_code = s.subject_code
                AND r.semester = s.semester
                AND r.division = %s

            LEFT JOIN attendance_sessions a
                ON a.subject_code = s.subject_code
                AND a.semester = s.semester
                AND a.division = %s

            LEFT JOIN faculty f
                ON f.id = a.faculty_id

            WHERE s.department_id = %s
              AND s.semester = %s

            GROUP BY
                s.id,
                s.subject_code,
                s.subject_name,
                s.department_id,
                s.semester

            ORDER BY s.subject_code
        """, (
            division,
            division,
            department_id,
            semester
        ))

        subjects = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "subjects": subjects
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load subjects",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# 5. ATTENDANCE SESSION MANAGEMENT
# ============================================================

@admin_bp.route(
    "/attendance-sessions/departments",
    methods=["GET"]
)
@token_required
def attendance_session_departments():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                d.id AS department_id,
                d.department_code,
                d.department_name

            FROM departments d

            INNER JOIN subjects sub
                ON sub.department_id = d.id

            INNER JOIN attendance_sessions a
                ON a.subject_code = sub.subject_code
                AND a.semester = sub.semester

            ORDER BY d.department_name
        """)

        departments = cursor.fetchall()

        return jsonify({
            "success": True,
            "departments": departments
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message":
                "Failed to load attendance session departments",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route(
    "/attendance-sessions/groups",
    methods=["GET"]
)
@token_required
def attendance_session_groups():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department_id = request.args.get(
        "department_id",
        ""
    ).strip()

    if not department_id:
        return jsonify({
            "success": False,
            "message": "Department ID is required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                a.semester,
                a.division

            FROM attendance_sessions a

            INNER JOIN subjects s
                ON s.subject_code = a.subject_code
                AND s.semester = a.semester

            WHERE s.department_id = %s

            ORDER BY
                a.semester,
                a.division
        """, (department_id,))

        groups = cursor.fetchall()

        return jsonify({
            "success": True,
            "groups": groups
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message":
                "Failed to load attendance session groups",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route(
    "/attendance-sessions/subjects",
    methods=["GET"]
)
@token_required
def attendance_session_subjects():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department_id = request.args.get(
        "department_id",
        ""
    ).strip()

    semester = request.args.get(
        "semester",
        ""
    ).strip()

    division = request.args.get(
        "division",
        ""
    ).strip()

    if not department_id or not semester or not division:
        return jsonify({
            "success": False,
            "message":
                "Department, semester and division are required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                a.subject_code,
                a.subject_name

            FROM attendance_sessions a

            INNER JOIN subjects s
                ON s.subject_code = a.subject_code
                AND s.semester = a.semester

            WHERE s.department_id = %s
              AND a.semester = %s
              AND a.division = %s

            ORDER BY a.subject_code
        """, (
            department_id,
            semester,
            division
        ))

        subjects = cursor.fetchall()

        return jsonify({
            "success": True,
            "subjects": subjects
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message":
                "Failed to load attendance session subjects",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route(
    "/attendance-sessions/list",
    methods=["GET"]
)
@token_required
def attendance_session_list():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department_id = request.args.get(
        "department_id",
        ""
    ).strip()

    semester = request.args.get(
        "semester",
        ""
    ).strip()

    division = request.args.get(
        "division",
        ""
    ).strip()

    subject_code = request.args.get(
        "subject_code",
        ""
    ).strip()

    if (
        not department_id
        or not semester
        or not division
        or not subject_code
    ):
        return jsonify({
            "success": False,
            "message":
                "Department, semester, division and subject "
                "are required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                a.id,
                a.faculty_id,
                f.faculty_id AS faculty_code,
                f.full_name AS faculty_name,
                a.class_name,
                a.subject_name,
                a.subject_code,
                a.semester,
                a.division,
                a.attendance_date,
                a.start_time,
                a.end_time,
                a.status,
                a.created_at

            FROM attendance_sessions a

            INNER JOIN subjects s
                ON s.subject_code = a.subject_code
                AND s.semester = a.semester

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
            semester,
            division,
            subject_code
        ))

        sessions = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "sessions": sessions
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message":
                "Failed to load attendance sessions",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# 6. ATTENDANCE RECORD MANAGEMENT
# ============================================================

@admin_bp.route(
    "/attendance-records/departments",
    methods=["GET"]
)
@token_required
def attendance_record_departments():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                d.id AS department_id,
                d.department_code,
                d.department_name

            FROM departments d

            INNER JOIN subjects s
                ON s.department_id = d.id

            INNER JOIN attendance_sessions a
                ON a.subject_code = s.subject_code
                AND a.semester = s.semester

            INNER JOIN attendance ar
                ON ar.session_id = a.id

            ORDER BY d.department_name
        """)

        departments = cursor.fetchall()

        return jsonify({
            "success": True,
            "departments": departments
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message":
                "Failed to load attendance record departments",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route(
    "/attendance-records/groups",
    methods=["GET"]
)
@token_required
def attendance_record_groups():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department_id = request.args.get(
        "department_id",
        ""
    ).strip()

    if not department_id:
        return jsonify({
            "success": False,
            "message": "Department ID is required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                a.semester,
                a.division

            FROM attendance_sessions a

            INNER JOIN subjects s
                ON s.subject_code = a.subject_code
                AND s.semester = a.semester

            INNER JOIN attendance ar
                ON ar.session_id = a.id

            WHERE s.department_id = %s

            ORDER BY
                a.semester,
                a.division
        """, (department_id,))

        groups = cursor.fetchall()

        return jsonify({
            "success": True,
            "groups": groups
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message":
                "Failed to load attendance record groups",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route(
    "/attendance-records/subjects",
    methods=["GET"]
)
@token_required
def attendance_record_subjects():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department_id = request.args.get(
        "department_id",
        ""
    ).strip()

    semester = request.args.get(
        "semester",
        ""
    ).strip()

    division = request.args.get(
        "division",
        ""
    ).strip()

    if not department_id or not semester or not division:
        return jsonify({
            "success": False,
            "message":
                "Department, semester and division are required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT DISTINCT
                a.subject_code,
                a.subject_name

            FROM attendance_sessions a

            INNER JOIN subjects s
                ON s.subject_code = a.subject_code
                AND s.semester = a.semester

            INNER JOIN attendance ar
                ON ar.session_id = a.id

            WHERE s.department_id = %s
              AND a.semester = %s
              AND a.division = %s

            ORDER BY a.subject_code
        """, (
            department_id,
            semester,
            division
        ))

        subjects = cursor.fetchall()

        return jsonify({
            "success": True,
            "subjects": subjects
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message":
                "Failed to load attendance record subjects",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


@admin_bp.route(
    "/attendance-records/list",
    methods=["GET"]
)
@token_required
def attendance_record_list():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department_id = request.args.get(
        "department_id",
        ""
    ).strip()

    semester = request.args.get(
        "semester",
        ""
    ).strip()

    division = request.args.get(
        "division",
        ""
    ).strip()

    subject_code = request.args.get(
        "subject_code",
        ""
    ).strip()

    if (
        not department_id
        or not semester
        or not division
        or not subject_code
    ):
        return jsonify({
            "success": False,
            "message":
                "Department, semester, division and subject "
                "are required"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                ar.id,
                s.student_id,
                s.full_name,
                s.email,
                a.id AS session_id,
                a.subject_code,
                a.subject_name,
                a.semester,
                a.division,
                a.attendance_date,
                a.start_time,
                a.end_time,
                ar.attendance_date AS record_date,
                ar.attendance_time,
                ar.status,
                ar.face_verified,
                ar.latitude,
                ar.longitude,
                ar.created_at

            FROM attendance ar

            INNER JOIN attendance_sessions a
                ON a.id = ar.session_id

            INNER JOIN students s
                ON s.id = ar.student_id

            INNER JOIN subjects sub
                ON sub.subject_code = a.subject_code
                AND sub.semester = a.semester

            WHERE sub.department_id = %s
              AND a.semester = %s
              AND a.division = %s
              AND a.subject_code = %s

            ORDER BY
                a.attendance_date DESC,
                a.start_time DESC,
                s.student_id
        """, (
            department_id,
            semester,
            division,
            subject_code
        ))

        records = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "records": records
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message":
                "Failed to load attendance records",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# EXISTING GENERAL DEPARTMENT API
# ============================================================

@admin_bp.route("/departments", methods=["GET"])
@token_required
def departments():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                d.id,
                d.department_code,
                d.department_name,
                d.created_at
            FROM departments d
            ORDER BY d.department_name
        """)

        rows = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "departments": rows
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load departments",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# EXISTING GENERAL STUDENT API
# ============================================================

@admin_bp.route("/students", methods=["GET"])
@token_required
def students():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department = request.args.get(
        "department",
        ""
    ).strip()

    semester = request.args.get(
        "semester",
        ""
    ).strip()

    division = request.args.get(
        "division",
        ""
    ).strip()

    search = request.args.get(
        "search",
        ""
    ).strip()

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        query = """
            SELECT
                s.id,
                s.user_id,
                s.student_id,
                s.full_name,
                s.email,
                s.department,
                s.semester,
                s.division,
                s.face_registered,
                s.created_at

            FROM students s

            WHERE 1 = 1
        """

        params = []

        if department:
            query += """
                AND s.department = %s
            """
            params.append(department)

        if semester:
            query += """
                AND s.semester = %s
            """
            params.append(semester)

        if division:
            query += """
                AND s.division = %s
            """
            params.append(division)

        if search:
            query += """
                AND (
                    s.student_id LIKE %s
                    OR s.full_name LIKE %s
                    OR s.email LIKE %s
                )
            """

            search_value = f"%{search}%"

            params.extend([
                search_value,
                search_value,
                search_value
            ])

        query += """
            ORDER BY s.student_id
        """

        cursor.execute(query, tuple(params))

        rows = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "students": rows
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load students",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# EXISTING GENERAL FACULTY API
# ============================================================

@admin_bp.route("/faculty", methods=["GET"])
@token_required
def faculty():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department = request.args.get(
        "department",
        ""
    ).strip()

    search = request.args.get(
        "search",
        ""
    ).strip()

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        query = """
            SELECT
                f.id,
                f.user_id,
                f.faculty_id,
                f.full_name,
                f.email,
                f.department,
                f.created_at

            FROM faculty f

            WHERE 1 = 1
        """

        params = []

        if department:
            query += """
                AND f.department = %s
            """
            params.append(department)

        if search:
            query += """
                AND (
                    f.faculty_id LIKE %s
                    OR f.full_name LIKE %s
                    OR f.email LIKE %s
                )
            """

            search_value = f"%{search}%"

            params.extend([
                search_value,
                search_value,
                search_value
            ])

        query += """
            ORDER BY f.full_name
        """

        cursor.execute(query, tuple(params))

        rows = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "faculty": rows
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load faculty",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# EXISTING GENERAL SUBJECT API
# ============================================================

@admin_bp.route("/subjects", methods=["GET"])
@token_required
def subjects():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    department_id = request.args.get(
        "department_id",
        ""
    ).strip()

    semester = request.args.get(
        "semester",
        ""
    ).strip()

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        query = """
            SELECT
                s.id,
                s.subject_code,
                s.subject_name,
                s.department_id,
                d.department_name,
                s.semester,
                s.created_at

            FROM subjects s

            INNER JOIN departments d
                ON d.id = s.department_id

            WHERE 1 = 1
        """

        params = []

        if department_id:
            query += """
                AND s.department_id = %s
            """
            params.append(department_id)

        if semester:
            query += """
                AND s.semester = %s
            """
            params.append(semester)

        query += """
            ORDER BY
                s.semester,
                s.subject_code
        """

        cursor.execute(query, tuple(params))

        rows = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "subjects": rows
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load subjects",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# EXISTING GENERAL ATTENDANCE API
# ============================================================

@admin_bp.route("/attendance", methods=["GET"])
@token_required
def attendance():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    semester = request.args.get(
        "semester",
        ""
    ).strip()

    division = request.args.get(
        "division",
        ""
    ).strip()

    subject_code = request.args.get(
        "subject_code",
        ""
    ).strip()

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        query = """
            SELECT
                a.id,
                a.student_id,
                s.student_id AS usn,
                s.full_name,
                a.session_id,
                a.attendance_date,
                a.attendance_time,
                a.status,
                a.face_verified,
                a.created_at,

                ats.subject_code,
                ats.subject_name,
                ats.semester,
                ats.division

            FROM attendance a

            INNER JOIN students s
                ON s.id = a.student_id

            INNER JOIN attendance_sessions ats
                ON ats.id = a.session_id

            WHERE 1 = 1
        """

        params = []

        if semester:
            query += """
                AND ats.semester = %s
            """
            params.append(semester)

        if division:
            query += """
                AND ats.division = %s
            """
            params.append(division)

        if subject_code:
            query += """
                AND ats.subject_code = %s
            """
            params.append(subject_code)

        query += """
            ORDER BY
                a.attendance_date DESC,
                a.attendance_time DESC,
                s.student_id
        """

        cursor.execute(query, tuple(params))

        rows = serialize_rows(cursor.fetchall())

        return jsonify({
            "success": True,
            "attendance": rows
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load attendance",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# SECURITY
# ============================================================

@admin_bp.route("/security", methods=["GET"])
@token_required
def security():
    auth_error = admin_required()

    if auth_error:
        return auth_error

    connection = None
    cursor = None

    try:
        connection = get_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                COUNT(*) AS total_records,

                SUM(
                    CASE
                        WHEN status = 'present'
                        THEN 1
                        ELSE 0
                    END
                ) AS present_records,

                SUM(
                    CASE
                        WHEN status = 'late'
                        THEN 1
                        ELSE 0
                    END
                ) AS late_records,

                SUM(
                    CASE
                        WHEN face_verified = 1
                        THEN 1
                        ELSE 0
                    END
                ) AS face_verified_records

            FROM attendance
        """)

        security_data = cursor.fetchone()

        return jsonify({
            "success": True,
            "security": security_data
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Failed to load security information",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()

        if connection:
            connection.close()