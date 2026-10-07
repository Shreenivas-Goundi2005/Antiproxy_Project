from flask import Blueprint, request, jsonify

from database import get_db_connection
from utils.hashing import hash_password
from utils.auth import token_required


student_bp = Blueprint("student", __name__)


# ============================================================
# AVAILABLE SUBJECTS
#
# There is currently no separate subjects table.
# Therefore the currently supported subjects are defined here.
# ============================================================

AVAILABLE_SUBJECTS = {
    "22UCS113C": {
        "subject_name": "RM",
        "semester": "7",
    },
    "22UCS124C": {
        "subject_name": "CC",
        "semester": "7",
    },
    "22UCS132C": {
        "subject_name": "PE",
        "semester": "7",
    },
    "22UCS142C": {
        "subject_name": "WSN",
        "semester": "7",
    },
}


# ============================================================
# SUBJECT NAME HELPER
# ============================================================

def get_subject_name(subject_code):
    """
    Returns the subject name for a subject code.

    Currently subject names come from AVAILABLE_SUBJECTS
    because there is no separate subjects table.
    """

    subject_code = str(
        subject_code or ""
    ).strip().upper()

    subject_info = AVAILABLE_SUBJECTS.get(
        subject_code
    )

    if subject_info:
        return subject_info["subject_name"]

    return subject_code


# ============================================================
# ATTENDANCE STATUS HELPER
# ============================================================

def get_attendance_status(
    percentage,
    total_classes
):
    """
    Returns the subject-wise attendance status.

    85% and above:
        Safe

    65% to below 85%:
        Monitor

    Below 65%:
        Low

    No conducted classes:
        Not started
    """

    if total_classes <= 0:
        return "Not started"

    if percentage >= 85:
        return "Safe"

    if percentage >= 65:
        return "Monitor"

    return "Low"


# ============================================================
# STUDENT REGISTRATION
# ============================================================

@student_bp.route(
    "/students/register",
    methods=["POST"]
)
def register_student():

    data = request.get_json()

    if not data:
        return jsonify({
            "success": False,
            "message": "Request data is required"
        }), 400

    student_id = data.get("student_id")
    username = data.get("username") or student_id
    password = data.get("password")
    full_name = data.get("full_name")
    email = data.get("email")
    department = data.get("department")
    semester = data.get("semester")
    division = data.get("division")

    if not password or not student_id or not full_name:
        return jsonify({
            "success": False,
            "message": (
                "password, student_id and full_name "
                "are required"
            )
        }), 400

    connection = None
    cursor = None

    try:

        connection = get_db_connection()

        cursor = connection.cursor()

        password_hash = hash_password(password)

        # ----------------------------------------------------
        # Create login account
        # ----------------------------------------------------

        cursor.execute(
            """
            INSERT INTO users
            (username, password_hash, role)
            VALUES (%s, %s, 'student')
            """,
            (
                username,
                password_hash
            )
        )

        user_id = cursor.lastrowid

        # ----------------------------------------------------
        # Create student profile
        # ----------------------------------------------------

        cursor.execute(
            """
            INSERT INTO students
            (
                user_id,
                student_id,
                full_name,
                email,
                department,
                semester,
                division
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            (
                user_id,
                student_id,
                full_name,
                email,
                department,
                semester,
                division
            )
        )

        student_database_id = cursor.lastrowid

        connection.commit()

        return jsonify({
            "success": True,
            "message": "Student registered successfully",
            "student": {
                "id": student_database_id,
                "user_id": user_id,
                "student_id": student_id,
                "full_name": full_name,
                "email": email,
                "department": department,
                "semester": semester,
                "division": division
            }
        }), 201

    except Exception as error:

        if connection:
            try:
                connection.rollback()
            except Exception:
                pass

        print(
            "Student registration error:",
            error
        )

        return jsonify({
            "success": False,
            "message": "Student registration failed",
            "error": str(error)
        }), 400

    finally:

        if cursor:
            try:
                cursor.close()
            except Exception:
                pass

        if connection:
            try:
                connection.close()
            except Exception:
                pass


# ============================================================
# GET STUDENT PROFILE
#
# GET /student/profile/user/<user_id>
#
# Requires:
#     Authorization: Bearer <token>
#
# The user_id in the URL must belong to the authenticated
# student.
# ============================================================

@student_bp.route(
    "/student/profile/user/<int:user_id>",
    methods=["GET"]
)
@token_required
def get_student_profile_by_user(user_id):

    connection = None
    cursor = None

    try:

        connection = get_db_connection()

        cursor = connection.cursor(
            dictionary=True
        )

        # ----------------------------------------------------
        # Get authenticated user from token
        # ----------------------------------------------------

        authenticated_user = request.auth_user

        # ----------------------------------------------------
        # Make sure URL user_id matches logged-in user.
        # ----------------------------------------------------

        if int(
            authenticated_user["user_id"]
        ) != int(user_id):

            return jsonify({
                "success": False,
                "message": (
                    "You are not authorized "
                    "to access this profile"
                )
            }), 403

        # ----------------------------------------------------
        # Make sure the authenticated account is a student.
        # ----------------------------------------------------

        if authenticated_user.get("role") != "student":

            return jsonify({
                "success": False,
                "message": (
                    "Only students can access "
                    "student profiles"
                )
            }), 403

        # ----------------------------------------------------
        # Get student profile
        # ----------------------------------------------------

        cursor.execute(
            """
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
            INNER JOIN users u
                ON s.user_id = u.id
            WHERE s.user_id = %s
              AND u.role = 'student'
            LIMIT 1
            """,
            (user_id,)
        )

        student = cursor.fetchone()

        if not student:

            return jsonify({
                "success": False,
                "message": "Student profile not found"
            }), 404

        student_database_id = student["id"]

        # ----------------------------------------------------
        # Get registered subjects
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT DISTINCT
                cr.subject_code,
                cr.semester,
                cr.division
            FROM class_roster cr
            WHERE cr.student_id = %s
            ORDER BY cr.subject_code
            """,
            (student_database_id,)
        )

        roster_subjects = cursor.fetchall()

        subjects = []

        for roster_subject in roster_subjects:

            subject_code = (
                roster_subject["subject_code"]
            )

            # ------------------------------------------------
            # Try to get subject name from attendance sessions.
            # ------------------------------------------------

            cursor.execute(
                """
                SELECT
                    subject_name,
                    class_name
                FROM attendance_sessions
                WHERE subject_code = %s
                ORDER BY id DESC
                LIMIT 1
                """,
                (subject_code,)
            )

            subject_data = cursor.fetchone()

            subject_name = None

            if subject_data:

                subject_name = (
                    subject_data.get("subject_name")
                    or subject_data.get("class_name")
                )

            # ------------------------------------------------
            # Subject name fallback.
            # ------------------------------------------------

            if not subject_name:

                subject_name = get_subject_name(
                    subject_code
                )

            subjects.append({
                "subject_name": subject_name,
                "subject_code": subject_code,
                "semester": roster_subject["semester"],
                "division": roster_subject["division"]
            })

        # ----------------------------------------------------
        # Convert database values for JSON
        # ----------------------------------------------------

        if student.get("created_at") is not None:

            student["created_at"] = str(
                student["created_at"]
            )

        student["face_registered"] = bool(
            student.get(
                "face_registered",
                False
            )
        )

        return jsonify({
            "success": True,
            "student": student,
            "subjects": subjects,
            "subject_count": len(subjects)
        })

    except Exception as error:

        print(
            "Student profile error:",
            error
        )

        if connection:
            try:
                connection.rollback()
            except Exception:
                pass

        return jsonify({
            "success": False,
            "message": "Could not fetch student profile",
            "error": str(error)
        }), 500

    finally:

        if cursor:
            try:
                cursor.close()
            except Exception:
                pass

        if connection:
            try:
                connection.close()
            except Exception:
                pass


# ============================================================
# UPDATE STUDENT PROFILE
#
# PUT /student/profile/user/<user_id>
#
# Editable:
#   full_name
#   email
#   department
#   semester
#   division
#
# Protected:
#   student_id / USN
#   user_id
#   face_registered
#
# Requires authentication.
# ============================================================

@student_bp.route(
    "/student/profile/user/<int:user_id>",
    methods=["PUT"]
)
@token_required
def update_student_profile(user_id):

    data = request.get_json()

    if not data:

        return jsonify({
            "success": False,
            "message": "Request data is required"
        }), 400

    # --------------------------------------------------------
    # Get authenticated user from token
    # --------------------------------------------------------

    authenticated_user = request.auth_user

    # --------------------------------------------------------
    # Make sure authenticated account is a student.
    # --------------------------------------------------------

    if authenticated_user.get("role") != "student":

        return jsonify({
            "success": False,
            "message": (
                "Only students can modify "
                "student profiles"
            )
        }), 403

    # --------------------------------------------------------
    # Make sure URL user_id matches logged-in user.
    # --------------------------------------------------------

    if int(
        authenticated_user["user_id"]
    ) != int(user_id):

        return jsonify({
            "success": False,
            "message": (
                "You are not authorized "
                "to modify this profile"
            )
        }), 403

    # --------------------------------------------------------
    # Read editable fields
    # --------------------------------------------------------

    full_name = data.get("full_name")
    email = data.get("email")
    department = data.get("department")
    semester = data.get("semester")
    division = data.get("division")

    # --------------------------------------------------------
    # Validate full name
    # --------------------------------------------------------

    if (
        full_name is None
        or not str(full_name).strip()
    ):

        return jsonify({
            "success": False,
            "message": "Full name is required"
        }), 400

    # --------------------------------------------------------
    # Convert values to strings
    # --------------------------------------------------------

    full_name = str(
        full_name
    ).strip()

    if email is not None:
        email = str(email).strip()

    if department is not None:
        department = str(department).strip()

    if semester is not None:
        semester = str(semester).strip()

    if division is not None:
        division = str(division).strip()

    connection = None
    cursor = None

    try:

        connection = get_db_connection()

        cursor = connection.cursor(
            dictionary=True
        )

        # ----------------------------------------------------
        # Verify student account
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                s.id,
                s.user_id,
                s.student_id,
                s.full_name,
                s.email,
                s.department,
                s.semester,
                s.division,
                s.face_registered
            FROM students s
            INNER JOIN users u
                ON s.user_id = u.id
            WHERE s.user_id = %s
              AND u.role = 'student'
            LIMIT 1
            """,
            (user_id,)
        )

        student = cursor.fetchone()

        if not student:

            return jsonify({
                "success": False,
                "message": "Student profile not found"
            }), 404

        # ----------------------------------------------------
        # Update editable fields only.
        #
        # student_id is intentionally NOT updated.
        # ----------------------------------------------------

        cursor.execute(
            """
            UPDATE students
            SET
                full_name = %s,
                email = %s,
                department = %s,
                semester = %s,
                division = %s
            WHERE user_id = %s
            """,
            (
                full_name,
                email,
                department,
                semester,
                division,
                user_id
            )
        )

        connection.commit()

        # ----------------------------------------------------
        # Get updated profile
        # ----------------------------------------------------

        cursor.execute(
            """
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
            INNER JOIN users u
                ON s.user_id = u.id
            WHERE s.user_id = %s
              AND u.role = 'student'
            LIMIT 1
            """,
            (user_id,)
        )

        updated_student = cursor.fetchone()

        if updated_student.get("created_at") is not None:

            updated_student["created_at"] = str(
                updated_student["created_at"]
            )

        updated_student["face_registered"] = bool(
            updated_student.get(
                "face_registered",
                False
            )
        )

        return jsonify({
            "success": True,
            "message": (
                "Student profile updated successfully"
            ),
            "student": updated_student
        }), 200

    except Exception as error:

        if connection:
            try:
                connection.rollback()
            except Exception:
                pass

        print(
            "Student profile update error:",
            error
        )

        return jsonify({
            "success": False,
            "message": "Could not update student profile",
            "error": str(error)
        }), 500

    finally:

        if cursor:
            try:
                cursor.close()
            except Exception:
                pass

        if connection:
            try:
                connection.close()
            except Exception:
                pass


# ============================================================
# STUDENT DASHBOARD
#
# GET /student/dashboard
#
# Requires:
#     Authorization: Bearer <token>
#
# IMPORTANT:
#     The student is identified ONLY from the authentication
#     token.
#
# This endpoint returns:
#
#     Student profile
#     Registered subjects
#     Present classes per subject
#     Total classes per subject
#     Subject-wise attendance percentage
#     Subject-wise attendance status
#
# It intentionally DOES NOT return:
#
#     Overall attendance percentage
#     Recent attendance
# ============================================================

@student_bp.route(
    "/student/dashboard",
    methods=["GET"]
)
@token_required
def get_student_dashboard():

    connection = None
    cursor = None

    try:

        authenticated_user = request.auth_user

        # ----------------------------------------------------
        # Only students can access the student dashboard.
        # ----------------------------------------------------

        if authenticated_user.get("role") != "student":

            return jsonify({
                "success": False,
                "message": (
                    "Only students can access "
                    "the student dashboard"
                )
            }), 403

        connection = get_db_connection()

        cursor = connection.cursor(
            dictionary=True
        )

        authenticated_user_id = (
            authenticated_user["user_id"]
        )

        # ----------------------------------------------------
        # Get authenticated student.
        #
        # IMPORTANT:
        # We do NOT accept student_id/USN from the client.
        # The token determines the student.
        # ----------------------------------------------------

        cursor.execute(
            """
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
            INNER JOIN users u
                ON s.user_id = u.id
            WHERE s.user_id = %s
              AND u.role = 'student'
            LIMIT 1
            """,
            (
                authenticated_user_id,
            )
        )

        student = cursor.fetchone()

        if not student:

            return jsonify({
                "success": False,
                "message": "Student profile not found"
            }), 404

        student_database_id = student["id"]

        student_semester = str(
            student["semester"] or ""
        ).strip()

        student_division = str(
            student["division"] or ""
        ).strip().upper()

        # ----------------------------------------------------
        # Convert profile values for JSON.
        # ----------------------------------------------------

        if student.get("created_at") is not None:

            student["created_at"] = str(
                student["created_at"]
            )

        student["face_registered"] = bool(
            student.get(
                "face_registered",
                False
            )
        )

        # ----------------------------------------------------
        # Get the student's registered subjects.
        #
        # A student only gets subjects actually registered
        # for that student's class roster.
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT DISTINCT
                cr.subject_code,
                cr.semester,
                cr.division
            FROM class_roster cr
            WHERE cr.student_id = %s
              AND cr.semester = %s
              AND UPPER(cr.division) = %s
            ORDER BY cr.subject_code
            """,
            (
                student_database_id,
                student_semester,
                student_division
            )
        )

        registered_subjects = cursor.fetchall()

        subjects = []

        # ----------------------------------------------------
        # Calculate attendance separately for every registered
        # subject.
        # ----------------------------------------------------

        for roster_subject in registered_subjects:

            subject_code = str(
                roster_subject["subject_code"]
            ).strip().upper()

            subject_semester = str(
                roster_subject["semester"]
            ).strip()

            subject_division = str(
                roster_subject["division"]
            ).strip().upper()

            subject_name = get_subject_name(
                subject_code
            )

            # ------------------------------------------------
            # Total classes conducted for this subject.
            #
            # Only sessions matching:
            #
            #     subject
            #     semester
            #     division
            #
            # are included.
            # ------------------------------------------------

            cursor.execute(
                """
                SELECT
                    COUNT(*) AS total_classes
                FROM attendance_sessions ats
                WHERE ats.subject_code = %s
                  AND ats.semester = %s
                  AND UPPER(ats.division) = %s
                """,
                (
                    subject_code,
                    subject_semester,
                    subject_division
                )
            )

            total_row = cursor.fetchone()

            total_classes = int(
                total_row["total_classes"] or 0
            )

            # ------------------------------------------------
            # Count classes attended by this student.
            #
            # Present and Late are treated as attended.
            # ------------------------------------------------

            cursor.execute(
                """
                SELECT
                    COUNT(*) AS attended_classes
                FROM attendance_sessions ats
                INNER JOIN attendance a
                    ON a.session_id = ats.id
                   AND a.student_id = %s
                WHERE ats.subject_code = %s
                  AND ats.semester = %s
                  AND UPPER(ats.division) = %s
                  AND LOWER(
                        COALESCE(a.status, '')
                      ) IN ('present', 'late')
                """,
                (
                    student_database_id,
                    subject_code,
                    subject_semester,
                    subject_division
                )
            )

            attended_row = cursor.fetchone()

            attended_classes = int(
                attended_row["attended_classes"] or 0
            )

            # ------------------------------------------------
            # Calculate subject-wise percentage.
            # ------------------------------------------------

            if total_classes > 0:

                percentage = round(
                    (
                        attended_classes
                        / total_classes
                    ) * 100,
                    1
                )

            else:

                percentage = None

            status = get_attendance_status(
    percentage,
    total_classes
)

            # ------------------------------------------------
            # Add subject data.
            #
            # There is deliberately NO overall percentage.
            # ------------------------------------------------

            subjects.append({
                "subject_code": subject_code,
                "subject_name": subject_name,
                "semester": subject_semester,
                "division": subject_division,
                "present": attended_classes,
                "total": total_classes,
                "percentage": percentage,
                "status": status
            })

        # ----------------------------------------------------
        # Return dashboard.
        # ----------------------------------------------------

        return jsonify({
            "success": True,

            "student": student,

            "subjects": subjects,

            "subject_count": len(subjects)
        }), 200

    except Exception as error:

        print(
            "Student dashboard error:",
            error
        )

        if connection:
            try:
                connection.rollback()
            except Exception:
                pass

        return jsonify({
            "success": False,
            "message": (
                "Could not load student dashboard"
            ),
            "error": str(error)
        }), 500

    finally:

        if cursor:
            try:
                cursor.close()
            except Exception:
                pass

        if connection:
            try:
                connection.close()
            except Exception:
                pass


# ============================================================
# GET AVAILABLE SUBJECTS
#
# GET /student/subjects/available
#
# Requires:
#     Authorization: Bearer <token>
#
# Returns subjects matching the authenticated student's
# semester and division.
# ============================================================

@student_bp.route(
    "/student/subjects/available",
    methods=["GET"]
)
@token_required
def get_available_subjects():

    connection = None
    cursor = None

    try:

        authenticated_user = request.auth_user

        # ----------------------------------------------------
        # Make sure authenticated account is a student.
        # ----------------------------------------------------

        if authenticated_user.get("role") != "student":

            return jsonify({
                "success": False,
                "message": (
                    "Only students can access "
                    "subject registration"
                )
            }), 403

        connection = get_db_connection()

        cursor = connection.cursor(
            dictionary=True
        )

        # ----------------------------------------------------
        # Get authenticated student's profile.
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                s.id,
                s.student_id,
                s.full_name,
                s.semester,
                s.division
            FROM students s
            INNER JOIN users u
                ON s.user_id = u.id
            WHERE s.user_id = %s
              AND u.role = 'student'
            LIMIT 1
            """,
            (
                authenticated_user["user_id"],
            )
        )

        student = cursor.fetchone()

        if not student:

            return jsonify({
                "success": False,
                "message": "Student profile not found"
            }), 404

        student_database_id = student["id"]

        student_semester = str(
            student["semester"]
        ).strip()

        student_division = str(
            student["division"]
        ).strip().upper()

        # ----------------------------------------------------
        # Get subjects already registered by student.
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT DISTINCT
                subject_code
            FROM class_roster
            WHERE student_id = %s
            """,
            (student_database_id,)
        )

        registered_rows = cursor.fetchall()

        registered_codes = {
            str(row["subject_code"])
            .strip()
            .upper()
            for row in registered_rows
        }

        # ----------------------------------------------------
        # Build available subject list.
        # ----------------------------------------------------

        subjects = []

        for subject_code, subject_info in (
            AVAILABLE_SUBJECTS.items()
        ):

            subject_semester = str(
                subject_info["semester"]
            ).strip()

            # ------------------------------------------------
            # Only show subjects for the student's semester.
            # ------------------------------------------------

            if subject_semester != student_semester:
                continue

            # ------------------------------------------------
            # Check whether this subject/class exists for the
            # student's division in class_roster.
            # ------------------------------------------------

            cursor.execute(
                """
                SELECT 1
                FROM class_roster
                WHERE subject_code = %s
                  AND semester = %s
                  AND UPPER(division) = %s
                LIMIT 1
                """,
                (
                    subject_code,
                    student_semester,
                    student_division
                )
            )

            class_exists = cursor.fetchone()

            if not class_exists:
                continue

            subjects.append({
                "subject_code": subject_code,
                "subject_name": (
                    subject_info["subject_name"]
                ),
                "semester": student_semester,
                "division": student_division,
                "registered": (
                    subject_code.upper()
                    in registered_codes
                )
            })

        return jsonify({
            "success": True,
            "student": {
                "student_id": student["student_id"],
                "full_name": student["full_name"],
                "semester": student_semester,
                "division": student_division
            },
            "subjects": subjects
        }), 200

    except Exception as error:

        print(
            "Available subjects error:",
            error
        )

        if connection:
            try:
                connection.rollback()
            except Exception:
                pass

        return jsonify({
            "success": False,
            "message": (
                "Could not fetch available subjects"
            ),
            "error": str(error)
        }), 500

    finally:

        if cursor:
            try:
                cursor.close()
            except Exception:
                pass

        if connection:
            try:
                connection.close()
            except Exception:
                pass


# ============================================================
# REGISTER SUBJECT
#
# POST /student/subjects/register
#
# Body:
# {
#     "subject_code": "22UCS113C"
# }
#
# The student is determined from the authentication token.
# The client cannot choose another student's identity.
# ============================================================

@student_bp.route(
    "/student/subjects/register",
    methods=["POST"]
)
@token_required
def register_subject():

    data = request.get_json()

    if not data:

        return jsonify({
            "success": False,
            "message": "Request data is required"
        }), 400

    authenticated_user = request.auth_user

    # --------------------------------------------------------
    # Only students can register subjects.
    # --------------------------------------------------------

    if authenticated_user.get("role") != "student":

        return jsonify({
            "success": False,
            "message": (
                "Only students can register subjects"
            )
        }), 403

    subject_code = (
        data.get("subject_code")
        if data.get("subject_code") is not None
        else ""
    )

    subject_code = str(
        subject_code
    ).strip().upper()

    if not subject_code:

        return jsonify({
            "success": False,
            "message": "subject_code is required"
        }), 400

    # --------------------------------------------------------
    # Check whether subject is supported.
    # --------------------------------------------------------

    subject_info = AVAILABLE_SUBJECTS.get(
        subject_code
    )

    if not subject_info:

        return jsonify({
            "success": False,
            "message": (
                "This subject is not available "
                "for registration"
            )
        }), 400

    connection = None
    cursor = None

    try:

        connection = get_db_connection()

        cursor = connection.cursor(
            dictionary=True
        )

        # ----------------------------------------------------
        # Get authenticated student's profile.
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                s.id,
                s.user_id,
                s.student_id,
                s.full_name,
                s.semester,
                s.division
            FROM students s
            INNER JOIN users u
                ON s.user_id = u.id
            WHERE s.user_id = %s
              AND u.role = 'student'
            LIMIT 1
            """,
            (
                authenticated_user["user_id"],
            )
        )

        student = cursor.fetchone()

        if not student:

            return jsonify({
                "success": False,
                "message": "Student profile not found"
            }), 404

        student_database_id = student["id"]

        student_semester = str(
            student["semester"]
        ).strip()

        student_division = str(
            student["division"]
        ).strip().upper()

        subject_semester = str(
            subject_info["semester"]
        ).strip()

        # ----------------------------------------------------
        # Semester validation.
        # ----------------------------------------------------

        if student_semester != subject_semester:

            return jsonify({
                "success": False,
                "message": (
                    "This subject is not available "
                    "for your semester"
                )
            }), 400

        # ----------------------------------------------------
        # Verify that the subject exists for the student's
        # semester and division.
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                subject_code,
                semester,
                division
            FROM class_roster
            WHERE subject_code = %s
              AND semester = %s
              AND UPPER(division) = %s
            LIMIT 1
            """,
            (
                subject_code,
                student_semester,
                student_division
            )
        )

        class_record = cursor.fetchone()

        if not class_record:

            return jsonify({
                "success": False,
                "message": (
                    "This subject is not available "
                    "for your division"
                )
            }), 400

        # ----------------------------------------------------
        # Check duplicate registration.
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                id
            FROM class_roster
            WHERE subject_code = %s
              AND semester = %s
              AND UPPER(division) = %s
              AND student_id = %s
            LIMIT 1
            """,
            (
                subject_code,
                student_semester,
                student_division,
                student_database_id
            )
        )

        existing_registration = cursor.fetchone()

        if existing_registration:

            return jsonify({
                "success": False,
                "message": (
                    "You are already registered "
                    "for this subject"
                ),
                "subject": {
                    "subject_code": subject_code,
                    "subject_name": (
                        subject_info["subject_name"]
                    ),
                    "semester": student_semester,
                    "division": student_division
                }
            }), 409

        # ----------------------------------------------------
        # Register student.
        # ----------------------------------------------------

        cursor.execute(
            """
            INSERT INTO class_roster
            (
                subject_code,
                semester,
                division,
                student_id
            )
            VALUES (%s, %s, %s, %s)
            """,
            (
                subject_code,
                student_semester,
                student_division,
                student_database_id
            )
        )

        connection.commit()

        return jsonify({
            "success": True,
            "message": (
                "Subject registered successfully"
            ),
            "subject": {
                "subject_code": subject_code,
                "subject_name": (
                    subject_info["subject_name"]
                ),
                "semester": student_semester,
                "division": student_division
            }
        }), 201

    except Exception as error:

        if connection:
            try:
                connection.rollback()
            except Exception:
                pass

        print(
            "Subject registration error:",
            error
        )

        return jsonify({
            "success": False,
            "message": (
                "Could not register subject"
            ),
            "error": str(error)
        }), 500

    finally:

        if cursor:
            try:
                cursor.close()
            except Exception:
                pass

        if connection:
            try:
                connection.close()
            except Exception:
                pass