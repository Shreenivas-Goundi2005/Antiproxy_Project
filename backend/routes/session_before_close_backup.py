from flask import Blueprint, request, jsonify
from database import get_db_connection

import secrets
from datetime import datetime


session_bp = Blueprint("session", __name__)


# ============================================================
# START ATTENDANCE SESSION
# ============================================================

@session_bp.route("/sessions/start", methods=["POST"])
def start_session():

    db = None
    cursor = None

    try:

        data = request.get_json()

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

        attendance_date = data.get("attendance_date")
        start_time = data.get("start_time")
        end_time = data.get("end_time")

        allowed_latitude = data.get("allowed_latitude")
        allowed_longitude = data.get("allowed_longitude")
        allowed_radius = data.get("allowed_radius", 100)

        # ----------------------------------------------------
        # REQUIRED FIELDS
        # ----------------------------------------------------

        if not faculty_user_id:
            return jsonify({
                "success": False,
                "message": "faculty_user_id is required"
            }), 400

        if not class_name:
            return jsonify({
                "success": False,
                "message": "class_name is required"
            }), 400

        if not subject_name:
            return jsonify({
                "success": False,
                "message": "subject_name is required"
            }), 400

        if not attendance_date:
            attendance_date = datetime.now().date().isoformat()

        if not start_time or not end_time:
            return jsonify({
                "success": False,
                "message": "start_time and end_time are required"
            }), 400

        if allowed_latitude is None or allowed_longitude is None:
            return jsonify({
                "success": False,
                "message":
                    "allowed_latitude and allowed_longitude are required"
            }), 400

        # ----------------------------------------------------
        # VALIDATE NUMBERS
        # ----------------------------------------------------

        try:

            faculty_user_id = int(faculty_user_id)

            allowed_latitude = float(
                allowed_latitude
            )

            allowed_longitude = float(
                allowed_longitude
            )

            allowed_radius = int(
                allowed_radius
            )

        except (TypeError, ValueError):

            return jsonify({
                "success": False,
                "message": "Invalid numeric value"
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

        if allowed_radius <= 0:

            return jsonify({
                "success": False,
                "message": "allowed_radius must be greater than 0"
            }), 400

        # ----------------------------------------------------
        # DATABASE
        # ----------------------------------------------------

        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        # ----------------------------------------------------
        # FIND FACULTY
        #
        # faculty_user_id refers to users.id
        # ----------------------------------------------------

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
            """,
            (faculty_user_id,)
        )

        faculty = cursor.fetchone()

        if not faculty:

            return jsonify({
                "success": False,
                "message": "Faculty account not found"
            }), 404

        # ----------------------------------------------------
        # CHECK FOR EXISTING ACTIVE SESSION
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT id
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
                "message":
                    "Faculty already has an active attendance session",
                "session_id":
                    existing_session["id"]
            }), 409

        # ----------------------------------------------------
        # GENERATE UNIQUE QR TOKEN
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
                attendance_date,
                start_time,
                end_time,
                allowed_latitude,
                allowed_longitude,
                allowed_radius,
                qr_token,
                status
            )
            VALUES
            (
                %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, 'active'
            )
            """,
            (
                faculty["id"],
                class_name.strip(),
                subject_name.strip(),
                attendance_date,
                start_time,
                end_time,
                allowed_latitude,
                allowed_longitude,
                allowed_radius,
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

            "message":
                "Attendance session started successfully",

            "session": {

                "id": session_id,

                "faculty_id":
                    faculty["id"],

                "faculty_user_id":
                    faculty["user_id"],

                "faculty_code":
                    faculty["faculty_id"],

                "faculty_name":
                    faculty["full_name"],

                "class_name":
                    class_name.strip(),

                "subject_name":
                    subject_name.strip(),

                "attendance_date":
                    attendance_date,

                "start_time":
                    start_time,

                "end_time":
                    end_time,

                "allowed_latitude":
                    allowed_latitude,

                "allowed_longitude":
                    allowed_longitude,

                "allowed_radius":
                    allowed_radius,

                "qr_token":
                    qr_token,

                "status":
                    "active"
            }

        }), 201

    except Exception as error:

        if db:
            db.rollback()

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