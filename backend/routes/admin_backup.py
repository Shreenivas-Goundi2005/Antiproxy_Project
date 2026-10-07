from flask import Blueprint, jsonify, request

from database import get_db_connection
from utils.auth import token_required


admin_bp = Blueprint(
    "admin",
    __name__,
    url_prefix="/admin"
)


# ============================================================
# HELPER FUNCTIONS
# ============================================================

def serialize_value(value):
    """
    Convert MySQL date/time values into JSON-safe strings.

    MySQL TIME columns are returned by mysql-connector as
    datetime.timedelta objects. Flask jsonify() cannot directly
    serialize timedelta, so we convert them to strings.
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
    """
    Convert every value in a list of dictionaries into
    JSON-safe values.
    """

    serialized = []

    for row in rows:
        serialized_row = {}

        for key, value in row.items():
            serialized_row[key] = serialize_value(value)

        serialized.append(serialized_row)

    return serialized


# ============================================================
# ADMIN AUTHORIZATION
# ============================================================

def admin_required():
    """
    Check whether the authenticated user has the admin role.

    token_required() stores the authenticated user in
    request.auth_user.
    """

    user = getattr(request, "auth_user", None)

    if not user:
        return None, (
            jsonify({
                "success": False,
                "message": "Authentication required"
            }),
            401
        )

    role = str(user.get("role", "")).lower()

    if role != "admin":
        return None, (
            jsonify({
                "success": False,
                "message": "Admin access required"
            }),
            403
        )

    return user, None


# ============================================================
# ADMIN DASHBOARD
# ============================================================

@admin_bp.route("/dashboard", methods=["GET"])
@token_required
def admin_dashboard():

    user, error = admin_required()

    if error:
        return error

    connection = None
    cursor = None

    try:
        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        # ----------------------------------------------------
        # TOTAL STUDENTS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM students
        """)

        total_students = cursor.fetchone()["total"]

        # ----------------------------------------------------
        # TOTAL FACULTY
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM faculty
        """)

        total_faculty = cursor.fetchone()["total"]

        # ----------------------------------------------------
        # TOTAL DEPARTMENTS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM departments
        """)

        total_departments = cursor.fetchone()["total"]

        # ----------------------------------------------------
        # TOTAL SUBJECTS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM subjects
        """)

        total_subjects = cursor.fetchone()["total"]

        # ----------------------------------------------------
        # TOTAL ATTENDANCE SESSIONS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM attendance_sessions
        """)

        total_sessions = cursor.fetchone()["total"]

        # ----------------------------------------------------
        # TOTAL ATTENDANCE RECORDS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM attendance
        """)

        total_attendance_records = cursor.fetchone()["total"]

        # ----------------------------------------------------
        # ACTIVE SESSIONS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM attendance_sessions
            WHERE end_time IS NULL
        """)

        active_sessions = cursor.fetchone()["total"]

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

        departments = cursor.fetchall()

        # ----------------------------------------------------
        # RECENT ATTENDANCE SESSIONS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT
                id,
                subject_code,
                semester,
                division,
                start_time,
                end_time
            FROM attendance_sessions
            ORDER BY id DESC
            LIMIT 10
        """)

        recent_sessions = cursor.fetchall()

        # Convert MySQL TIME / DATETIME values into strings.
        departments = serialize_rows(departments)
        recent_sessions = serialize_rows(recent_sessions)

        return jsonify({
            "success": True,

            "admin": {
                "id": user.get("id"),
                "username": user.get("username"),
                "role": user.get("role")
            },

            "overview": {
                "total_students": total_students,
                "total_faculty": total_faculty,
                "total_departments": total_departments,
                "total_subjects": total_subjects,
                "total_sessions": total_sessions,
                "total_attendance_records": total_attendance_records,
                "active_sessions": active_sessions
            },

            "departments": departments,

            "recent_sessions": recent_sessions
        })

    except Exception as e:

        print("Admin dashboard error:", e)

        return jsonify({
            "success": False,
            "message": "Unable to load admin dashboard",
            "error": str(e)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# DEPARTMENTS
# ============================================================

@admin_bp.route("/departments", methods=["GET"])
@token_required
def admin_departments():

    user, error = admin_required()

    if error:
        return error

    connection = None
    cursor = None

    try:

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                d.id,
                d.department_code,
                d.department_name,
                d.created_at,

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

        departments = cursor.fetchall()

        departments = serialize_rows(departments)

        return jsonify({
            "success": True,
            "count": len(departments),
            "departments": departments
        })

    except Exception as e:

        print("Admin departments error:", e)

        return jsonify({
            "success": False,
            "message": "Unable to load departments",
            "error": str(e)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# STUDENTS
# ============================================================

@admin_bp.route("/students", methods=["GET"])
@token_required
def admin_students():

    user, error = admin_required()

    if error:
        return error

    department = request.args.get("department")
    semester = request.args.get("semester")
    division = request.args.get("division")
    search = request.args.get("search")

    connection = None
    cursor = None

    try:

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        query = """
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

            WHERE 1 = 1
        """

        params = []

        if department:
            query += """
                AND department = %s
            """
            params.append(department)

        if semester:
            query += """
                AND semester = %s
            """
            params.append(semester)

        if division:
            query += """
                AND division = %s
            """
            params.append(division)

        if search:

            query += """
                AND (
                    student_id LIKE %s
                    OR full_name LIKE %s
                    OR email LIKE %s
                )
            """

            search_value = f"%{search}%"

            params.extend([
                search_value,
                search_value,
                search_value
            ])

        query += """
            ORDER BY full_name
        """

        cursor.execute(query, params)

        students = cursor.fetchall()

        students = serialize_rows(students)

        return jsonify({
            "success": True,
            "count": len(students),
            "students": students
        })

    except Exception as e:

        print("Admin students error:", e)

        return jsonify({
            "success": False,
            "message": "Unable to load students",
            "error": str(e)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# FACULTY
# ============================================================

@admin_bp.route("/faculty", methods=["GET"])
@token_required
def admin_faculty():

    user, error = admin_required()

    if error:
        return error

    department = request.args.get("department")
    search = request.args.get("search")

    connection = None
    cursor = None

    try:

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        query = """
            SELECT
                id,
                user_id,
                faculty_id,
                full_name,
                email,
                department,
                created_at

            FROM faculty

            WHERE 1 = 1
        """

        params = []

        if department:

            query += """
                AND department = %s
            """

            params.append(department)

        if search:

            query += """
                AND (
                    faculty_id LIKE %s
                    OR full_name LIKE %s
                    OR email LIKE %s
                )
            """

            search_value = f"%{search}%"

            params.extend([
                search_value,
                search_value,
                search_value
            ])

        query += """
            ORDER BY full_name
        """

        cursor.execute(query, params)

        faculty = cursor.fetchall()

        faculty = serialize_rows(faculty)

        return jsonify({
            "success": True,
            "count": len(faculty),
            "faculty": faculty
        })

    except Exception as e:

        print("Admin faculty error:", e)

        return jsonify({
            "success": False,
            "message": "Unable to load faculty",
            "error": str(e)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# SUBJECTS
# ============================================================

@admin_bp.route("/subjects", methods=["GET"])
@token_required
def admin_subjects():

    user, error = admin_required()

    if error:
        return error

    department_id = request.args.get("department_id")
    semester = request.args.get("semester")

    connection = None
    cursor = None

    try:

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        query = """
            SELECT
                s.id,
                s.subject_code,
                s.subject_name,
                s.semester,
                s.created_at,

                d.id AS department_id,
                d.department_code,
                d.department_name

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
                d.department_name,
                s.semester,
                s.subject_code
        """

        cursor.execute(query, params)

        subjects = cursor.fetchall()

        subjects = serialize_rows(subjects)

        return jsonify({
            "success": True,
            "count": len(subjects),
            "subjects": subjects
        })

    except Exception as e:

        print("Admin subjects error:", e)

        return jsonify({
            "success": False,
            "message": "Unable to load subjects",
            "error": str(e)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# ATTENDANCE SESSIONS
# ============================================================

@admin_bp.route("/attendance", methods=["GET"])
@token_required
def admin_attendance():

    user, error = admin_required()

    if error:
        return error

    semester = request.args.get("semester")
    division = request.args.get("division")
    subject_code = request.args.get("subject_code")

    connection = None
    cursor = None

    try:

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        query = """
            SELECT
                a.id,
                a.subject_code,
                a.semester,
                a.division,
                a.start_time,
                a.end_time

            FROM attendance_sessions a

            WHERE 1 = 1
        """

        params = []

        if semester:

            query += """
                AND a.semester = %s
            """

            params.append(semester)

        if division:

            query += """
                AND a.division = %s
            """

            params.append(division)

        if subject_code:

            query += """
                AND a.subject_code = %s
            """

            params.append(subject_code)

        query += """
            ORDER BY a.id DESC
        """

        cursor.execute(query, params)

        sessions = cursor.fetchall()

        sessions = serialize_rows(sessions)

        return jsonify({
            "success": True,
            "count": len(sessions),
            "sessions": sessions
        })

    except Exception as e:

        print("Admin attendance error:", e)

        return jsonify({
            "success": False,
            "message": "Unable to load attendance sessions",
            "error": str(e)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if connection:
            connection.close()


# ============================================================
# SECURITY SUMMARY
# ============================================================

@admin_bp.route("/security", methods=["GET"])
@token_required
def admin_security():

    user, error = admin_required()

    if error:
        return error

    connection = None
    cursor = None

    try:

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        # ----------------------------------------------------
        # TOTAL ATTENDANCE RECORDS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM attendance
        """)

        total_records = cursor.fetchone()["total"]

        # ----------------------------------------------------
        # PRESENT RECORDS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM attendance
            WHERE status = 'present'
        """)

        present_records = cursor.fetchone()["total"]

        # ----------------------------------------------------
        # LATE RECORDS
        # ----------------------------------------------------

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM attendance
            WHERE status = 'late'
        """)

        late_records = cursor.fetchone()["total"]

        return jsonify({
            "success": True,

            "security": {
                "total_attendance_records": total_records,
                "present_records": present_records,
                "late_records": late_records
            }
        })

    except Exception as e:

        print("Admin security error:", e)

        return jsonify({
            "success": False,
            "message": "Unable to load security information",
            "error": str(e)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if connection:
            connection.close()