from flask import Blueprint, request, jsonify
from database import get_db_connection
from utils.auth import token_required

import secrets
from datetime import datetime


session_bp = Blueprint("session", __name__)


# ============================================================
# HELPER: AUTOMATICALLY CLOSE EXPIRED SESSIONS
# ============================================================

def auto_close_expired_sessions(cursor):
    """
    Automatically closes all active sessions whose end time
    has already passed.
    """

    now = datetime.now()
    current_date = now.date()
    current_time = now.time()

    cursor.execute(
        """
        UPDATE attendance_sessions
        SET status = 'closed'
        WHERE status = 'active'
          AND attendance_date < %s
        """,
        (current_date,)
    )

    cursor.execute(
        """
        UPDATE attendance_sessions
        SET status = 'closed'
        WHERE status = 'active'
          AND attendance_date = %s
          AND end_time <= %s
        """,
        (current_date, current_time)
    )


# ============================================================
# HELPER: FIND AUTHENTICATED FACULTY
# ============================================================

def get_authenticated_faculty(cursor, user_id):
    """
    Finds the faculty profile belonging to an authenticated
    user account.
    """

    cursor.execute(
        """
        SELECT
            f.id,
            f.user_id,
            f.faculty_id,
            f.full_name
        FROM faculty f
        INNER JOIN users u
            ON u.id = f.user_id
        WHERE f.user_id = %s
          AND u.role = 'faculty'
        LIMIT 1
        """,
        (user_id,)
    )

    return cursor.fetchone()


# ============================================================
# START ATTENDANCE SESSION
# ============================================================

@session_bp.route("/sessions/start", methods=["POST"])
@token_required
def start_session():

    db = None
    cursor = None

    try:

        # ----------------------------------------------------
        # AUTHENTICATION AND ROLE VALIDATION
        # ----------------------------------------------------

        authenticated_user = request.auth_user

        if str(authenticated_user.get("role", "")).lower() != "faculty":

            return jsonify({
                "success": False,
                "message": "Only authenticated faculty can start attendance"
            }), 403

        data = request.get_json(silent=True)

        if not data:
            return jsonify({
                "success": False,
                "message": "Request body is required"
            }), 400

        # ----------------------------------------------------
        # GET DATA
        # ----------------------------------------------------

        faculty_user_id = data.get("faculty_user_id")
        class_name = data.get("class_name")
        subject_name = data.get("subject_name")
        subject_code = data.get("subject_code")

        semester = data.get("semester")
        division = data.get("division")

        attendance_date = data.get("attendance_date")
        start_time = data.get("start_time")
        end_time = data.get("end_time")

        allowed_latitude = data.get("allowed_latitude")
        allowed_longitude = data.get("allowed_longitude")

        # Classroom dimensions in meters.
        classroom_length = data.get("classroom_length")
        classroom_width = data.get("classroom_width")

        # ----------------------------------------------------
        # REQUIRED FIELDS
        # ----------------------------------------------------

        if not faculty_user_id:
            return jsonify({
                "success": False,
                "message": "faculty_user_id is required"
            }), 400

        if not class_name or not str(class_name).strip():
            return jsonify({
                "success": False,
                "message": "class_name is required"
            }), 400

        if not subject_name or not str(subject_name).strip():
            return jsonify({
                "success": False,
                "message": "subject_name is required"
            }), 400

        if not subject_code or not str(subject_code).strip():
            return jsonify({
                "success": False,
                "message": "subject_code is required"
            }), 400

        if semester is None or not str(semester).strip():
            return jsonify({
                "success": False,
                "message": "semester is required"
            }), 400

        if division is None or not str(division).strip():
            return jsonify({
                "success": False,
                "message": "division is required"
            }), 400

        if not attendance_date:
            attendance_date = datetime.now().date().isoformat()

        if not start_time or not end_time:
            return jsonify({
                "success": False,
                "message": "start_time and end_time are required"
            }), 400

        if (
            allowed_latitude is None
            or allowed_longitude is None
        ):
            return jsonify({
                "success": False,
                "message": (
                    "allowed_latitude and allowed_longitude are required"
                )
            }), 400

        # ----------------------------------------------------
        # CLASSROOM DIMENSIONS
        # ----------------------------------------------------

        if classroom_length is None:
            return jsonify({
                "success": False,
                "message": "classroom_length is required"
            }), 400

        if classroom_width is None:
            return jsonify({
                "success": False,
                "message": "classroom_width is required"
            }), 400

        # ----------------------------------------------------
        # VALIDATE NUMBERS
        # ----------------------------------------------------

        try:

            faculty_user_id = int(faculty_user_id)
            semester = int(semester)

            allowed_latitude = float(allowed_latitude)
            allowed_longitude = float(allowed_longitude)

            classroom_length = float(classroom_length)
            classroom_width = float(classroom_width)

            authenticated_user_id = int(
                authenticated_user["user_id"]
            )

        except (TypeError, ValueError):

            return jsonify({
                "success": False,
                "message": "Invalid numeric value"
            }), 400

        # ----------------------------------------------------
        # VERIFY FACULTY ACCOUNT OWNERSHIP
        # ----------------------------------------------------

        if faculty_user_id != authenticated_user_id:

            return jsonify({
                "success": False,
                "message": (
                    "You cannot start a session for another faculty member"
                )
            }), 403

        # ----------------------------------------------------
        # VALIDATE SEMESTER AND DIVISION
        # ----------------------------------------------------

        if semester < 1 or semester > 12:

            return jsonify({
                "success": False,
                "message": "Semester must be between 1 and 12"
            }), 400

        division = str(division).strip().upper()

        if not division:

            return jsonify({
                "success": False,
                "message": "Division is required"
            }), 400

        # ----------------------------------------------------
        # VALIDATE GPS RANGE
        # ----------------------------------------------------

        if not -90 <= allowed_latitude <= 90:

            return jsonify({
                "success": False,
                "message": "Invalid latitude"
            }), 400

        if not -180 <= allowed_longitude <= 180:

            return jsonify({
                "success": False,
                "message": "Invalid longitude"
            }), 400

        # ----------------------------------------------------
        # VALIDATE CLASSROOM DIMENSIONS
        # ----------------------------------------------------

        if classroom_length <= 0:

            return jsonify({
                "success": False,
                "message": "classroom_length must be greater than 0"
            }), 400

        if classroom_width <= 0:

            return jsonify({
                "success": False,
                "message": "classroom_width must be greater than 0"
            }), 400

        # Prevent unrealistic classroom dimensions.
        if classroom_length > 500:

            return jsonify({
                "success": False,
                "message": "classroom_length cannot exceed 500 meters"
            }), 400

        if classroom_width > 500:

            return jsonify({
                "success": False,
                "message": "classroom_width cannot exceed 500 meters"
            }), 400

        # ----------------------------------------------------
        # VALIDATE DATE/TIME
        # ----------------------------------------------------

        try:

            parsed_date = datetime.strptime(
                str(attendance_date),
                "%Y-%m-%d"
            ).date()

            parsed_start_time = datetime.strptime(
                str(start_time),
                "%H:%M:%S"
            ).time()

            parsed_end_time = datetime.strptime(
                str(end_time),
                "%H:%M:%S"
            ).time()

        except ValueError:

            try:

                parsed_start_time = datetime.strptime(
                    str(start_time),
                    "%H:%M"
                ).time()

                parsed_end_time = datetime.strptime(
                    str(end_time),
                    "%H:%M"
                ).time()

                parsed_date = datetime.strptime(
                    str(attendance_date),
                    "%Y-%m-%d"
                ).date()

            except ValueError:

                return jsonify({
                    "success": False,
                    "message": (
                        "Invalid date or time format. "
                        "Use YYYY-MM-DD and HH:MM or HH:MM:SS."
                    )
                }), 400

        # ----------------------------------------------------
        # START MUST BE BEFORE END
        # ----------------------------------------------------

        if parsed_end_time <= parsed_start_time:

            return jsonify({
                "success": False,
                "message": (
                    "Session end time must be later than start time"
                )
            }), 400

        # ----------------------------------------------------
        # SESSION MUST NOT HAVE ALREADY ENDED
        # ----------------------------------------------------

        now = datetime.now()

        if parsed_date < now.date():

            return jsonify({
                "success": False,
                "message": "Cannot create a session for a previous date"
            }), 400

        if (
            parsed_date == now.date()
            and parsed_end_time <= now.time()
        ):

            return jsonify({
                "success": False,
                "message": "Session end time has already passed"
            }), 400

        # ----------------------------------------------------
        # DATABASE
        # ----------------------------------------------------

        db = get_db_connection()

        cursor = db.cursor(dictionary=True)

        # ----------------------------------------------------
        # AUTOMATICALLY CLOSE EXPIRED SESSIONS
        # ----------------------------------------------------

        auto_close_expired_sessions(cursor)

        db.commit()

        # ----------------------------------------------------
        # FIND AUTHENTICATED FACULTY
        # ----------------------------------------------------

        faculty = get_authenticated_faculty(
            cursor,
            authenticated_user_id
        )

        if not faculty:

            return jsonify({
                "success": False,
                "message": "Faculty account not found"
            }), 404

        # ----------------------------------------------------
        # VERIFY ACCEPTED SUBJECT ASSIGNMENT
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                a.id AS assignment_id,
                a.faculty_id,
                a.subject_id,
                a.semester,
                a.division,
                a.status,
                s.subject_code,
                s.subject_name,
                s.semester AS subject_semester
            FROM faculty_subject_assignments a
            INNER JOIN subjects s
                ON s.id = a.subject_id
            WHERE a.faculty_id = %s
              AND s.subject_code = %s
              AND s.subject_name = %s
              AND s.semester = %s
              AND a.semester = %s
              AND UPPER(a.division) = %s
              AND a.status = 'Accepted'
            LIMIT 1
            """,
            (
                faculty["id"],
                str(subject_code).strip(),
                str(subject_name).strip(),
                semester,
                semester,
                division
            )
        )

        accepted_assignment = cursor.fetchone()

        if not accepted_assignment:

            return jsonify({
                "success": False,
                "message": (
                    "You cannot start attendance without an accepted "
                    "assignment for this exact subject, semester and division"
                )
            }), 403

        # ----------------------------------------------------
        # CHECK ACTIVE SESSION
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                id,
                end_time,
                attendance_date
            FROM attendance_sessions
            WHERE faculty_id = %s
              AND status = 'active'
            LIMIT 1
            """,
            (faculty["id"],)
        )

        existing_session = cursor.fetchone()

        if existing_session:

            return jsonify({
                "success": False,
                "message": (
                    "Faculty already has an active attendance session"
                ),
                "session_id": existing_session["id"]
            }), 409

        # ----------------------------------------------------
        # GENERATE SECURE QR TOKEN
        # ----------------------------------------------------

        qr_token = secrets.token_urlsafe(32)

        # ----------------------------------------------------
        # INSERT SESSION
        # ----------------------------------------------------

        cursor.execute(
            """
            INSERT INTO attendance_sessions
            (
                faculty_id,
                class_name,
                subject_name,
                subject_code,
                semester,
                division,
                attendance_date,
                start_time,
                end_time,
                allowed_latitude,
                allowed_longitude,
                allowed_radius,
                classroom_length,
                classroom_width,
                qr_token,
                status
            )
            VALUES
            (
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                'active'
            )
            """,
            (
                faculty["id"],
                str(class_name).strip(),
                accepted_assignment["subject_name"],
                accepted_assignment["subject_code"],
                str(semester),
                division,
                parsed_date,
                parsed_start_time,
                parsed_end_time,
                allowed_latitude,
                allowed_longitude,

                # Kept for backward database compatibility.
                # It is no longer used for geofencing.
                0,

                classroom_length,
                classroom_width,
                qr_token
            )
        )

        session_id = cursor.lastrowid

        db.commit()

        # ----------------------------------------------------
        # SUCCESS
        # ----------------------------------------------------

        return jsonify({

            "success": True,

            "message": "Attendance session started successfully",

            "session": {

                "id": session_id,

                "faculty_id": faculty["id"],

                "faculty_user_id": faculty["user_id"],

                "faculty_code": faculty["faculty_id"],

                "faculty_name": faculty["full_name"],

                "class_name": str(class_name).strip(),

                "subject_name": accepted_assignment["subject_name"],

                "subject_code": accepted_assignment["subject_code"],

                "semester": str(semester),

                "division": division,

                "attendance_date": str(parsed_date),

                "start_time": str(parsed_start_time),

                "end_time": str(parsed_end_time),

                "allowed_latitude": allowed_latitude,

                "allowed_longitude": allowed_longitude,

                "classroom_length": classroom_length,

                "classroom_width": classroom_width,

                "qr_token": qr_token,

                "status": "active"
            }

        }), 201

    except Exception as error:

        if db:
            db.rollback()

        print("Start session error:", error)

        return jsonify({
            "success": False,
            "message": "Could not start attendance session",
            "error": str(error)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()


# ============================================================
# CLOSE ATTENDANCE SESSION
# ============================================================

@session_bp.route(
    "/sessions/<int:session_id>/close",
    methods=["POST"]
)
@token_required
def close_session(session_id):

    db = None
    cursor = None

    try:

        # ----------------------------------------------------
        # AUTHENTICATION AND ROLE VALIDATION
        # ----------------------------------------------------

        authenticated_user = request.auth_user

        if str(authenticated_user.get("role", "")).lower() != "faculty":

            return jsonify({
                "success": False,
                "message": "Only faculty can close attendance sessions"
            }), 403

        db = get_db_connection()

        cursor = db.cursor(dictionary=True)

        # ----------------------------------------------------
        # FIND AUTHENTICATED FACULTY
        # ----------------------------------------------------

        faculty = get_authenticated_faculty(
            cursor,
            authenticated_user["user_id"]
        )

        if not faculty:

            return jsonify({
                "success": False,
                "message": "Faculty account not found"
            }), 404

        # ----------------------------------------------------
        # FIND SESSION
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                id,
                faculty_id,
                class_name,
                subject_name,
                subject_code,
                semester,
                division,
                attendance_date,
                start_time,
                end_time,
                allowed_latitude,
                allowed_longitude,
                allowed_radius,
                classroom_length,
                classroom_width,
                qr_token,
                status
            FROM attendance_sessions
            WHERE id = %s
            """,
            (session_id,)
        )

        session = cursor.fetchone()

        if not session:

            return jsonify({
                "success": False,
                "message": "Attendance session not found"
            }), 404

        # ----------------------------------------------------
        # VERIFY SESSION OWNERSHIP
        # ----------------------------------------------------

        if int(session["faculty_id"]) != int(faculty["id"]):

            return jsonify({
                "success": False,
                "message": (
                    "You cannot close another faculty member's session"
                )
            }), 403

        if session["status"] == "closed":

            return jsonify({
                "success": False,
                "message": "Attendance session is already closed",
                "session_id": session_id
            }), 409

        # ----------------------------------------------------
        # CLOSE SESSION
        # ----------------------------------------------------

        cursor.execute(
            """
            UPDATE attendance_sessions
            SET status = 'closed'
            WHERE id = %s
              AND faculty_id = %s
            """,
            (session_id, faculty["id"])
        )

        db.commit()

        # ----------------------------------------------------
        # SUCCESS
        # ----------------------------------------------------

        return jsonify({

            "success": True,

            "message": "Attendance session closed successfully",

            "session": {

                "id": session["id"],

                "faculty_id": session["faculty_id"],

                "class_name": session["class_name"],

                "subject_name": session["subject_name"],

                "subject_code": session["subject_code"],

                "semester": session["semester"],

                "division": session["division"],

                "attendance_date": str(session["attendance_date"]),

                "start_time": str(session["start_time"]),

                "end_time": str(session["end_time"]),

                "allowed_latitude": float(session["allowed_latitude"]),

                "allowed_longitude": float(session["allowed_longitude"]),

                "classroom_length": float(session["classroom_length"]),

                "classroom_width": float(session["classroom_width"]),

                "qr_token": session["qr_token"],

                "status": "closed"
            }

        }), 200

    except Exception as error:

        if db:
            db.rollback()

        print("Close session error:", error)

        return jsonify({
            "success": False,
            "message": "Could not close attendance session",
            "error": str(error)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()


# ============================================================
# GET ACTIVE SESSION FOR FACULTY
# ============================================================

@session_bp.route(
    "/sessions/active/<int:faculty_user_id>",
    methods=["GET"]
)
@token_required
def get_active_session(faculty_user_id):

    db = None
    cursor = None

    try:

        # ----------------------------------------------------
        # AUTHENTICATION AND ROLE VALIDATION
        # ----------------------------------------------------

        authenticated_user = request.auth_user

        if str(authenticated_user.get("role", "")).lower() != "faculty":

            return jsonify({
                "success": False,
                "message": "Only faculty can retrieve active sessions"
            }), 403

        # ----------------------------------------------------
        # VERIFY REQUESTED ACCOUNT OWNERSHIP
        # ----------------------------------------------------

        if int(authenticated_user["user_id"]) != faculty_user_id:

            return jsonify({
                "success": False,
                "message": (
                    "You cannot access another faculty member's session"
                )
            }), 403

        db = get_db_connection()

        cursor = db.cursor(dictionary=True)

        auto_close_expired_sessions(cursor)

        db.commit()

        # ----------------------------------------------------
        # FIND AUTHENTICATED FACULTY
        # ----------------------------------------------------

        faculty = get_authenticated_faculty(
            cursor,
            authenticated_user["user_id"]
        )

        if not faculty:

            return jsonify({
                "success": False,
                "message": "Faculty account not found"
            }), 404

        # ----------------------------------------------------
        # FIND ACTIVE SESSION
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                id,
                faculty_id,
                class_name,
                subject_name,
                subject_code,
                semester,
                division,
                attendance_date,
                start_time,
                end_time,
                allowed_latitude,
                allowed_longitude,
                allowed_radius,
                classroom_length,
                classroom_width,
                qr_token,
                status
            FROM attendance_sessions
            WHERE faculty_id = %s
              AND status = 'active'
            ORDER BY id DESC
            LIMIT 1
            """,
            (faculty["id"],)
        )

        session = cursor.fetchone()

        if not session:

            return jsonify({
                "success": True,
                "active": False,
                "session": None
            }), 200

        # ----------------------------------------------------
        # SUCCESS
        # ----------------------------------------------------

        return jsonify({

            "success": True,

            "active": True,

            "session": {

                "id": session["id"],

                "faculty_id": session["faculty_id"],

                "faculty_user_id": faculty["user_id"],

                "faculty_code": faculty["faculty_id"],

                "faculty_name": faculty["full_name"],

                "class_name": session["class_name"],

                "subject_name": session["subject_name"],

                "subject_code": session["subject_code"],

                "semester": session["semester"],

                "division": session["division"],

                "attendance_date": str(session["attendance_date"]),

                "start_time": str(session["start_time"]),

                "end_time": str(session["end_time"]),

                "allowed_latitude": float(session["allowed_latitude"]),

                "allowed_longitude": float(session["allowed_longitude"]),

                "classroom_length": float(session["classroom_length"]),

                "classroom_width": float(session["classroom_width"]),

                "qr_token": session["qr_token"],

                "status": session["status"]
            }

        }), 200

    except Exception as error:

        if db:
            db.rollback()

        print("Get active session error:", error)

        return jsonify({
            "success": False,
            "message": "Could not retrieve active session",
            "error": str(error)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()
