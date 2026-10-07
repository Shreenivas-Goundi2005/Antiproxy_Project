from flask import Blueprint, request, jsonify
from database import get_db_connection
from utils.auth import token_required
from geofence import check_geofence,haversine_distance

import cv2
import numpy as np
import json

from datetime import datetime, time, timedelta

from mysql.connector import IntegrityError

from insightface.app import FaceAnalysis


# ============================================================
# ATTENDANCE BLUEPRINT
# ============================================================

attendance_bp = Blueprint("attendance", __name__)


# ============================================================
# LOAD INSIGHTFACE MODEL
# ============================================================

face_app = FaceAnalysis(
    name="buffalo_l",
    providers=["CPUExecutionProvider"]
)

face_app.prepare(
    ctx_id=0,
    det_size=(640, 640)
)


# ============================================================
# VERIFY FACE
# ============================================================

def verify_face(image_bytes, registered_encoding):

    image_array = np.frombuffer(
        image_bytes,
        np.uint8
    )

    image = cv2.imdecode(
        image_array,
        cv2.IMREAD_COLOR
    )

    if image is None:

        return (
            False,
            "Could not read uploaded image",
            0.0
        )

    faces = face_app.get(image)

    if len(faces) == 0:

        return (
            False,
            "No face detected",
            0.0
        )

    if len(faces) > 1:

        return (
            False,
            "Only one person is allowed",
            0.0
        )

    face = faces[0]

    current_embedding = face.embedding.astype(
        np.float32
    )

    current_norm = np.linalg.norm(
        current_embedding
    )

    if current_norm == 0:

        return (
            False,
            "Invalid face embedding",
            0.0
        )

    current_embedding = (
        current_embedding / current_norm
    )

    try:

        registered = np.array(
            json.loads(registered_encoding),
            dtype=np.float32
        )

    except Exception:

        return (
            False,
            "Invalid registered face data",
            0.0
        )

    registered_norm = np.linalg.norm(
        registered
    )

    if registered_norm == 0:

        return (
            False,
            "Invalid registered face data",
            0.0
        )

    registered = (
        registered / registered_norm
    )

    similarity = float(
        np.dot(
            registered,
            current_embedding
        )
    )

    similarity = round(
        similarity,
        4
    )

    print(
        "Face similarity:",
        similarity
    )

    # ========================================================
    # FACE MATCH THRESHOLD
    # ========================================================

    threshold = 0.50

    if similarity >= threshold:

        return (
            True,
            "Face verified successfully",
            similarity
        )

    return (
        False,
        "Face does not match registered student",
        similarity
    )


# ============================================================
# VALIDATE GPS
# ============================================================

def validate_location(
    latitude_raw,
    longitude_raw,
    accuracy_raw
):

    if (
        latitude_raw is None
        or longitude_raw is None
    ):

        return (
            None,
            None,
            None,
            "GPS location is required"
        )

    try:

        latitude = float(
            latitude_raw
        )

        longitude = float(
            longitude_raw
        )

    except (
        ValueError,
        TypeError
    ):

        return (
            None,
            None,
            None,
            "Invalid GPS coordinates"
        )

    if not (
        -90 <= latitude <= 90
    ):

        return (
            None,
            None,
            None,
            "Invalid latitude"
        )

    if not (
        -180 <= longitude <= 180
    ):

        return (
            None,
            None,
            None,
            "Invalid longitude"
        )

    accuracy = None

    if accuracy_raw is not None:

        try:

            accuracy = float(
                accuracy_raw
            )

        except (
            ValueError,
            TypeError
        ):

            accuracy = None

    return (
        latitude,
        longitude,
        accuracy,
        None
    )


# ============================================================
# MYSQL TIME CONVERSION
#
# MySQL TIME values can sometimes be returned by the connector
# as datetime.time and sometimes as datetime.timedelta.
#
# This function converts both into datetime.time.
# ============================================================

def mysql_time_to_time(value):

    if value is None:

        return None

    # Already datetime.time
    if isinstance(value, time):

        return value

    # MySQL TIME returned as timedelta
    if isinstance(value, timedelta):

        total_seconds = int(
            value.total_seconds()
        )

        # Protect against negative/overflow values
        total_seconds %= 24 * 60 * 60

        hours = (
            total_seconds // 3600
        )

        minutes = (
            (total_seconds % 3600) // 60
        )

        seconds = (
            total_seconds % 60
        )

        return time(
            hour=hours,
            minute=minutes,
            second=seconds
        )

    # Some connectors may return datetime
    if isinstance(value, datetime):

        return value.time()

    raise TypeError(
        f"Unsupported MySQL TIME value: "
        f"{type(value)}"
    )


# ============================================================
# GET STUDENT
# ============================================================

def get_student(
    cursor,
    usn
):

    cursor.execute(
        """
        SELECT
            id,
            student_id,
            full_name,
            face_encoding,
            face_registered
        FROM students
        WHERE student_id = %s
        """,
        (usn,)
    )

    return cursor.fetchone()


# ============================================================
# LEGACY ATTENDANCE API
# ============================================================

@attendance_bp.route(
    "/attendance/mark",
    methods=["POST"]
)
def mark_attendance():

    db = None
    cursor = None

    try:

        print()
        print("======================================")
        print("LEGACY ATTENDANCE REQUEST")
        print("======================================")

        # ====================================================
        # FORM DATA
        # ====================================================

        usn = request.form.get(
            "usn"
        )

        latitude_raw = request.form.get(
            "latitude"
        )

        longitude_raw = request.form.get(
            "longitude"
        )

        accuracy_raw = request.form.get(
            "accuracy"
        )

        print(
            "USN:",
            usn
        )

        print(
            "Latitude:",
            latitude_raw
        )

        print(
            "Longitude:",
            longitude_raw
        )

        print(
            "Accuracy:",
            accuracy_raw
        )

        # ====================================================
        # USN
        # ====================================================

        if not usn:

            return jsonify({
                "success": False,
                "message": "USN is required"
            }), 400

        usn = usn.strip()

        # ====================================================
        # LOCATION
        # ====================================================

        (
            latitude,
            longitude,
            accuracy,
            location_error
        ) = validate_location(
            latitude_raw,
            longitude_raw,
            accuracy_raw
        )

        if location_error:

            return jsonify({
                "success": False,
                "message": location_error
            }), 400

        # ====================================================
        # LEGACY CAMPUS GEOFENCE
        # ====================================================

        geofence = check_geofence(
            latitude,
            longitude
        )

        print(
            "Location distance:",
            geofence["distance"],
            "meters"
        )

        print(
            "Allowed radius:",
            geofence["allowed_radius"],
            "meters"
        )

        print(
            "Inside:",
            geofence["inside"]
        )

        if not geofence["inside"]:

            return jsonify({

                "success": False,

                "message":
                    "Attendance rejected: you are outside the allowed campus area",

                "reason":
                    "outside_geofence",

                "location": {

                    "latitude":
                        latitude,

                    "longitude":
                        longitude,

                    "accuracy":
                        accuracy,

                    "distance":
                        geofence["distance"],

                    "allowed_radius":
                        geofence["allowed_radius"],

                    "inside":
                        False
                }

            }), 403

        # ====================================================
        # FACE FILE
        # ====================================================

        if "face" not in request.files:

            return jsonify({
                "success": False,
                "message": "Face image is required"
            }), 400

        face_file = request.files[
            "face"
        ]

        image_bytes = face_file.read()

        if not image_bytes:

            return jsonify({
                "success": False,
                "message": "Empty face image"
            }), 400

        # ====================================================
        # DATABASE
        # ====================================================

        db = get_db_connection()

        cursor = db.cursor(
            dictionary=True
        )

        # ====================================================
        # STUDENT
        # ====================================================

        student = get_student(
            cursor,
            usn
        )

        if not student:

            return jsonify({
                "success": False,
                "message": "Student not found"
            }), 404

        # ====================================================
        # FACE REGISTRATION
        # ====================================================

        if (
            not student["face_registered"]
            or not student["face_encoding"]
        ):

            return jsonify({
                "success": False,
                "message": "Face is not registered"
            }), 400

        # ====================================================
        # FACE VERIFICATION
        # ====================================================

        (
            verified,
            face_message,
            similarity
        ) = verify_face(
            image_bytes,
            student["face_encoding"]
        )

        if not verified:

            return jsonify({

                "success": False,

                "message":
                    face_message,

                "reason":
                    "face_verification_failed",

                "face": {

                    "verified":
                        False,

                    "similarity":
                        round(
                            similarity,
                            4
                        )
                }

            }), 403

        # ====================================================
        # DAILY DUPLICATE CHECK
        # ====================================================

        today = datetime.now().date()

        cursor.execute(
            """
            SELECT id
            FROM attendance
            WHERE student_id = %s
              AND attendance_date = %s
            LIMIT 1
            """,
            (
                student["id"],
                today
            )
        )

        existing_attendance = (
            cursor.fetchone()
        )

        if existing_attendance:

            return jsonify({

                "success": False,

                "message":
                    "Attendance has already been marked today",

                "reason":
                    "already_marked"

            }), 409

        # ====================================================
        # INSERT LEGACY ATTENDANCE
        # ====================================================

        now = datetime.now()

        cursor.execute(
            """
            INSERT INTO attendance
            (
                student_id,
                session_id,
                attendance_date,
                attendance_time,
                status,
                latitude,
                longitude,
                face_verified
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
                %s
            )
            """,
            (
                student["id"],
                None,
                now.date(),
                now.time(),
                "present",
                latitude,
                longitude,
                1
            )
        )

        db.commit()

        return jsonify({

            "success": True,

            "message":
                "Attendance marked successfully",

            "student": {

                "usn":
                    student["student_id"],

                "name":
                    student["full_name"]
            },

            "face": {

                "verified":
                    True,

                "similarity":
                    round(
                        similarity,
                        4
                    )
            },

            "location": {

                "latitude":
                    latitude,

                "longitude":
                    longitude,

                "accuracy":
                    accuracy,

                "distance":
                    geofence["distance"],

                "allowed_radius":
                    geofence["allowed_radius"],

                "inside":
                    True
            },

            "attendance": {

                "status":
                    "present"
            }

        }), 200

    except Exception as error:

        print()
        print("======================================")
        print("LEGACY ATTENDANCE API ERROR")
        print("======================================")

        print(
            error
        )

        if db:

            try:
                db.rollback()
            except Exception:
                pass

        return jsonify({

            "success":
                False,

            "message":
                "Attendance marking failed",

            "error":
                str(error)

        }), 500

    finally:

        if cursor:

            try:
                cursor.close()
            except Exception:
                pass

        if db:

            try:
                db.close()
            except Exception:
                pass


# ============================================================
# QR SESSION ATTENDANCE API
#
# SECURITY FLOW
#
# 1. Student must be authenticated
# 2. Student role is verified
# 3. QR token is validated
# 4. Mock/fake GPS is rejected
# 5. Student GPS coordinates are validated
# 6. Active session is verified
# 7. Session date/time is verified
# 8. Student location is checked against the
#    RECTANGULAR CLASSROOM GEOFENCE
# 9. Face is verified
# 10. Duplicate attendance is rejected
# 11. Attendance is inserted
#
# RECTANGULAR GEOFENCE
#
# Teacher's stable GPS coordinate:
#     allowed_latitude
#     allowed_longitude
#
# is treated as the CENTER of the classroom.
#
# Classroom dimensions:
#     classroom_length = north/south dimension
#     classroom_width  = east/west dimension
#
# Student is inside when:
#
#     abs(north_south_distance) <= length / 2
#     abs(east_west_distance)  <= width  / 2
#
# No circular radius is used for the new session geofence.
# ============================================================

@attendance_bp.route(
    "/attendance/mark-session",
    methods=["POST"]
)
@token_required
def mark_session_attendance():
    """
    Mark attendance for an active attendance session.

    Location policy:
    - Student sends one stable GPS position produced by the Flutter app.
    - Backend performs one rectangular classroom-geofence calculation.
    - No repeated GPS/recheck loop is performed here.
    - Classroom dimensions are Length x Width, centred on teacher position.
    """

    from math import radians, cos, sqrt

    conn = None
    cursor = None

    try:
        # ---------------------------------------------------------
        # 1. AUTHENTICATION
        # ---------------------------------------------------------
        user = getattr(request, "user", None)

        if not user:
            return jsonify({
                "success": False,
                "message": "Authentication required."
            }), 401

        # ---------------------------------------------------------
        # 2. REQUEST DATA
        # ---------------------------------------------------------
        student_id = request.form.get("student_id")
        session_id = request.form.get("session_id")
        qr_token = request.form.get("qr_token")
        latitude = request.form.get("latitude")
        longitude = request.form.get("longitude")
        accuracy = request.form.get("accuracy")
        is_mocked = request.form.get("is_mocked", "false")

        # Face image can come through multipart/form-data.
        face_file = request.files.get("face")

        if not student_id:
            return jsonify({
                "success": False,
                "message": "Student ID is required."
            }), 400

        if not session_id:
            return jsonify({
                "success": False,
                "message": "Session ID is required."
            }), 400

        if not qr_token:
            return jsonify({
                "success": False,
                "message": "QR token is required."
            }), 400

        if latitude is None or longitude is None:
            return jsonify({
                "success": False,
                "message": "Student GPS coordinates are required."
            }), 400

        # ---------------------------------------------------------
        # 3. PARSE GPS
        # ---------------------------------------------------------
        try:
            student_lat = float(latitude)
            student_lon = float(longitude)
            gps_accuracy = float(accuracy) if accuracy is not None else 999.0
        except (TypeError, ValueError):
            return jsonify({
                "success": False,
                "message": "Invalid GPS coordinates."
            }), 400

        if not (-90 <= student_lat <= 90):
            return jsonify({
                "success": False,
                "message": "Invalid latitude."
            }), 400

        if not (-180 <= student_lon <= 180):
            return jsonify({
                "success": False,
                "message": "Invalid longitude."
            }), 400

        # ---------------------------------------------------------
        # 4. MOCK / FAKE GPS CHECK
        # ---------------------------------------------------------
        mocked = str(is_mocked).lower() in (
            "true",
            "1",
            "yes",
            "on"
        )

        if mocked:
            return jsonify({
                "success": False,
                "message": "Attendance rejected. Mock or fake GPS detected.",
                "security": {
                    "mock_location": True
                }
            }), 403

        # ---------------------------------------------------------
        # 5. GPS ACCURACY CHECK
        # ---------------------------------------------------------
        if gps_accuracy <= 0:
            return jsonify({
                "success": False,
                "message": "Invalid GPS accuracy."
            }), 400

        if gps_accuracy > 50:
            return jsonify({
                "success": False,
                "message": (
                    "GPS accuracy is too low. "
                    "Please ensure Location/GPS is enabled."
                ),
                "location": {
                    "latitude": student_lat,
                    "longitude": student_lon,
                    "accuracy": gps_accuracy
                }
            }), 400

        # ---------------------------------------------------------
        # 6. DATABASE
        # ---------------------------------------------------------
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # ---------------------------------------------------------
        # 7. STUDENT
        # ---------------------------------------------------------
        cursor.execute("""
            SELECT
                id,
                user_id,
                usn,
                full_name,
                email,
                department,
                semester,
                division
            FROM students
            WHERE id = %s
            LIMIT 1
        """, (student_id,))

        student = cursor.fetchone()

        if not student:
            return jsonify({
                "success": False,
                "message": "Student not found."
            }), 404

        # ---------------------------------------------------------
        # 8. SESSION
        # ---------------------------------------------------------
        cursor.execute("""
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
                qr_token,
                status,
                classroom_length,
                classroom_width,
                created_at
            FROM attendance_sessions
            WHERE id = %s
            LIMIT 1
        """, (session_id,))

        session = cursor.fetchone()

        if not session:
            return jsonify({
                "success": False,
                "message": "Attendance session not found."
            }), 404

        # ---------------------------------------------------------
        # 9. SESSION STATUS
        # ---------------------------------------------------------
        if str(session.get("status", "")).lower() != "active":
            return jsonify({
                "success": False,
                "message": "This attendance session is no longer active."
            }), 400

        # ---------------------------------------------------------
        # 10. QR TOKEN
        # ---------------------------------------------------------
        stored_qr = str(session.get("qr_token") or "").strip()
        received_qr = str(qr_token).strip()

        if not stored_qr or stored_qr != received_qr:
            return jsonify({
                "success": False,
                "message": "Invalid or expired QR code."
            }), 403

        # ---------------------------------------------------------
        # 11. CLASS / SEMESTER / DIVISION VALIDATION
        # ---------------------------------------------------------
        session_semester = session.get("semester")
        session_division = session.get("division")

        student_semester = student.get("semester")
        student_division = student.get("division")

        if (
            session_semester is not None
            and student_semester is not None
            and str(session_semester).strip()
            != str(student_semester).strip()
        ):
            return jsonify({
                "success": False,
                "message": "You are not registered for this semester."
            }), 403

        if (
            session_division is not None
            and student_division is not None
            and str(session_division).strip().upper()
            != str(student_division).strip().upper()
        ):
            return jsonify({
                "success": False,
                "message": "You are not registered for this division."
            }), 403

        # ---------------------------------------------------------
        # 12. DATE / TIME VALIDATION
        # ---------------------------------------------------------
        now = datetime.now()
        current_date = now.date()
        current_time = now.time()

        attendance_date = session.get("attendance_date")
        start_time = session.get("start_time")
        end_time = session.get("end_time")

        if attendance_date and attendance_date != current_date:
            return jsonify({
                "success": False,
                "message": "This attendance session is for another date."
            }), 400

        if start_time:
            start_time = mysql_time_to_time(start_time)

        if end_time:
            end_time = mysql_time_to_time(end_time)

        if start_time and current_time < start_time:
            return jsonify({
                "success": False,
                "message": "Attendance has not started yet."
            }), 400

        if end_time and current_time > end_time:
            return jsonify({
                "success": False,
                "message": "Attendance session has expired."
            }), 400

        # ---------------------------------------------------------
        # 13. CLASSROOM DIMENSIONS
        # ---------------------------------------------------------
        try:
            classroom_length = float(
                session.get("classroom_length") or 0
            )
            classroom_width = float(
                session.get("classroom_width") or 0
            )
        except (TypeError, ValueError):
            classroom_length = 0
            classroom_width = 0

        if (
            classroom_length <= 0
            or classroom_width <= 0
            or classroom_length > 500
            or classroom_width > 500
        ):
            return jsonify({
                "success": False,
                "message": "Invalid classroom dimensions."
            }), 400

        # ---------------------------------------------------------
        # 14. TEACHER / CLASSROOM CENTRE
        # ---------------------------------------------------------
        teacher_lat = session.get("allowed_latitude")
        teacher_lon = session.get("allowed_longitude")

        try:
            teacher_lat = float(teacher_lat)
            teacher_lon = float(teacher_lon)
        except (TypeError, ValueError):
            return jsonify({
                "success": False,
                "message": "Teacher classroom location is invalid."
            }), 500

        if not (-90 <= teacher_lat <= 90):
            return jsonify({
                "success": False,
                "message": "Invalid classroom centre latitude."
            }), 500

        if not (-180 <= teacher_lon <= 180):
            return jsonify({
                "success": False,
                "message": "Invalid classroom centre longitude."
            }), 500

        # ---------------------------------------------------------
        # 15. RECTANGULAR GEO-FENCE
        #
        # Length = north/south dimension
        # Width  = east/west dimension
        #
        # Teacher is the centre of the classroom.
        # ---------------------------------------------------------
        north_south_meters = (
            student_lat - teacher_lat
        ) * 111320.0

        longitude_scale = 111320.0 * cos(
            radians(teacher_lat)
        )

        east_west_meters = (
            student_lon - teacher_lon
        ) * longitude_scale

        half_length = classroom_length / 2.0
        half_width = classroom_width / 2.0

        inside_length = (
            abs(north_south_meters) <= half_length
        )

        inside_width = (
            abs(east_west_meters) <= half_width
        )

        inside_classroom = (
            inside_length and inside_width
        )

        # ---------------------------------------------------------
        # 16. STRAIGHT-LINE DISTANCE FROM TEACHER
        # ---------------------------------------------------------
        distance_meters = sqrt(
            (north_south_meters ** 2)
            +
            (east_west_meters ** 2)
        )

        location_payload = {
            "latitude": student_lat,
            "longitude": student_lon,
            "accuracy": gps_accuracy,

            "teacher_latitude": teacher_lat,
            "teacher_longitude": teacher_lon,

            "distance_meters": round(distance_meters, 2),

            "north_south_distance": round(
                north_south_meters,
                2
            ),

            "east_west_distance": round(
                east_west_meters,
                2
            ),

            "classroom_length": classroom_length,
            "classroom_width": classroom_width,

            "half_length": half_length,
            "half_width": half_width,

            "inside_length": inside_length,
            "inside_width": inside_width,
            "inside": inside_classroom
        }

        print(
            "\n========== ANTIPROXY LOCATION =========="
        )
        print(
            f"Teacher Centre : "
            f"{teacher_lat}, {teacher_lon}"
        )
        print(
            f"Student GPS    : "
            f"{student_lat}, {student_lon}"
        )
        print(
            f"Accuracy       : "
            f"{gps_accuracy:.2f} m"
        )
        print(
            f"NS displacement: "
            f"{north_south_meters:.2f} m"
        )
        print(
            f"EW displacement: "
            f"{east_west_meters:.2f} m"
        )
        print(
            f"Distance       : "
            f"{distance_meters:.2f} m"
        )
        print(
            f"Classroom      : "
            f"{classroom_length:.2f} x "
            f"{classroom_width:.2f} m"
        )
        print(
            f"Inside Length   : "
            f"{inside_length}"
        )
        print(
            f"Inside Width    : "
            f"{inside_width}"
        )
        print(
            f"Inside Classroom: "
            f"{inside_classroom}"
        )
        print(
            "==========================================\n"
        )

        # ---------------------------------------------------------
        # 17. GEO-FENCE REJECTION
        # ---------------------------------------------------------
        if not inside_classroom:
            return jsonify({
                "success": False,
                "message": (
                    "Attendance rejected. "
                    "You are outside the classroom boundary."
                ),
                "status": "OUTSIDE_CLASSROOM",
                "location": location_payload
            }), 403

        # ---------------------------------------------------------
        # 18. FACE VERIFICATION
        # ---------------------------------------------------------
        face_verified = False
        face_similarity = None

        if face_file:
            try:
                face_result = verify_face(
                    student_id,
                    face_file
                )

                if isinstance(face_result, dict):
                    face_verified = bool(
                        face_result.get("verified")
                        or face_result.get("success")
                    )

                    similarity_value = (
                        face_result.get("similarity")
                        or face_result.get("confidence")
                    )

                    if similarity_value is not None:
                        try:
                            face_similarity = float(
                                similarity_value
                            )
                        except (TypeError, ValueError):
                            face_similarity = None

                else:
                    face_verified = bool(face_result)

            except Exception as face_error:
                print(
                    f"[FACE] Verification error: "
                    f"{face_error}"
                )

                return jsonify({
                    "success": False,
                    "message": (
                        "Face verification failed."
                    ),
                    "location": location_payload
                }), 403

        else:
            return jsonify({
                "success": False,
                "message": "Face image is required.",
                "location": location_payload
            }), 400

        if not face_verified:
            return jsonify({
                "success": False,
                "message": "Face verification failed.",
                "face_verified": False,
                "similarity": face_similarity,
                "location": location_payload
            }), 403

        # ---------------------------------------------------------
        # 19. DUPLICATE ATTENDANCE CHECK
        # ---------------------------------------------------------
        cursor.execute("""
            SELECT
                id,
                status,
                marked_at
            FROM attendance
            WHERE session_id = %s
              AND student_id = %s
            LIMIT 1
        """, (
            session_id,
            student_id
        ))

        existing = cursor.fetchone()

        if existing:
            return jsonify({
                "success": False,
                "message": "Attendance has already been marked.",
                "status": "ALREADY_MARKED",
                "attendance_id": existing.get("id"),
                "face_verified": face_verified,
                "similarity": face_similarity,
                "location": location_payload
            }), 409

        # ---------------------------------------------------------
        # 20. INSERT ATTENDANCE
        # ---------------------------------------------------------
        cursor.execute("""
            INSERT INTO attendance (
                session_id,
                student_id,
                status,
                marked_at
            )
            VALUES (
                %s,
                %s,
                %s,
                %s
            )
        """, (
            session_id,
            student_id,
            "present",
            now
        ))

        attendance_id = cursor.lastrowid

        conn.commit()

        # ---------------------------------------------------------
        # 21. SUCCESS
        # ---------------------------------------------------------
        print(
            f"[ATTENDANCE] PRESENT | "
            f"Student={student_id} | "
            f"Session={session_id} | "
            f"Distance={distance_meters:.2f}m | "
            f"Face={face_verified}"
        )

        return jsonify({
            "success": True,
            "message": "Attendance marked successfully.",
            "status": "PRESENT",

            "attendance_id": attendance_id,
            "student_id": student_id,
            "session_id": session_id,

            "face_verified": True,
            "similarity": face_similarity,

            "location": location_payload
        }), 200

    except IntegrityError as e:
        if conn:
            conn.rollback()

        print(
            f"[ATTENDANCE] Database integrity error: {e}"
        )

        return jsonify({
            "success": False,
            "message": (
                "Attendance could not be recorded. "
                "It may already have been marked."
            )
        }), 409

    except Exception as e:
        if conn:
            conn.rollback()

        print(
            f"[ATTENDANCE] Unexpected error: {e}"
        )

        return jsonify({
            "success": False,
            "message": "Unable to mark attendance.",
            "error": str(e)
        }), 500

    finally:
        try:
            if cursor:
                cursor.close()
        except Exception:
            pass

        try:
            if conn:
                conn.close()
        except Exception:
            pass
# ============================================================
# ATTENDANCE HISTORY API
# ============================================================

@attendance_bp.route(
    "/attendance/history/<usn>",
    methods=["GET"]
)
def attendance_history(usn):

    db = None
    cursor = None

    try:

        # ======================================================
        # CLEAN USN
        # ======================================================

        usn = usn.strip().upper()

        if not usn:
            return jsonify({
                "success": False,
                "message": "USN is required"
            }), 400

        # ======================================================
        # DATABASE CONNECTION
        # ======================================================

        db = get_db_connection()

        cursor = db.cursor(
            dictionary=True
        )

        # ======================================================
        # FETCH ONLY THIS STUDENT'S ATTENDANCE
        # ======================================================

        cursor.execute(
            """
            SELECT
                s.student_id AS usn,
                s.full_name AS name,

                a.attendance_date,
                a.attendance_time,
                a.status,

                a.latitude,
                a.longitude,

                a.face_verified,
                a.created_at,

                a.session_id,

                sess.subject_name,
                sess.subject_code,
                sess.semester,
                sess.division,

                sess.class_name,
                sess.start_time,
                sess.end_time

            FROM attendance a

            INNER JOIN students s
                ON a.student_id = s.id

            LEFT JOIN attendance_sessions sess
                ON a.session_id = sess.id

            WHERE UPPER(s.student_id) = %s

            ORDER BY
                a.attendance_date DESC,
                a.attendance_time DESC

            """,
            (usn,)
        )

        records = cursor.fetchall()

        # ======================================================
        # CONVERT DATABASE VALUES TO JSON-SAFE VALUES
        # ======================================================

        for record in records:

            # --------------------------------------------------
            # DATE
            # --------------------------------------------------

            if record["attendance_date"] is not None:
                record["attendance_date"] = str(
                    record["attendance_date"]
                )

            # --------------------------------------------------
            # TIME
            # --------------------------------------------------

            if record["attendance_time"] is not None:
                record["attendance_time"] = str(
                    record["attendance_time"]
                )

            # --------------------------------------------------
            # CREATED AT
            # --------------------------------------------------

            if record["created_at"] is not None:
                record["created_at"] = str(
                    record["created_at"]
                )

            # --------------------------------------------------
            # SESSION START TIME
            # --------------------------------------------------

            if record["start_time"] is not None:
                record["start_time"] = str(
                    record["start_time"]
                )

            # --------------------------------------------------
            # SESSION END TIME
            # --------------------------------------------------

            if record["end_time"] is not None:
                record["end_time"] = str(
                    record["end_time"]
                )

            # --------------------------------------------------
            # GPS
            # --------------------------------------------------

            if record["latitude"] is not None:
                record["latitude"] = float(
                    record["latitude"]
                )

            if record["longitude"] is not None:
                record["longitude"] = float(
                    record["longitude"]
                )

            # --------------------------------------------------
            # FACE VERIFICATION
            # --------------------------------------------------

            record["face_verified"] = bool(
                record["face_verified"]
            )

            # --------------------------------------------------
            # SESSION ID
            # --------------------------------------------------

            if record["session_id"] is not None:
                record["session_id"] = int(
                    record["session_id"]
                )

        # ======================================================
        # RESPONSE
        # ======================================================

        return jsonify({

            "success": True,

            "student": usn,

            "count": len(records),

            "attendance": records

        }), 200

    # ==========================================================
    # ERROR
    # ==========================================================

    except Exception as error:

        print(
            "Attendance history error:",
            error
        )

        if db:

            try:
                db.rollback()

            except Exception:
                pass

        return jsonify({

            "success": False,

            "message":
                "Could not fetch attendance history",

            "error":
                str(error)

        }), 500

    # ==========================================================
    # CLEANUP
    # ==========================================================

    finally:

        if cursor:

            try:
                cursor.close()

            except Exception:
                pass

        if db:

            try:
                db.close()

            except Exception:
                pass

# ============================================================
# STUDENT ATTENDANCE REPORT API
#
# SECURITY:
#   - Requires valid login token
#   - Token user must be a student
#   - Token user's USN must match requested USN
#
# Example:
#
# Logged-in student:
#     user_id = 16
#     USN = 2BA23CS112
#
# Allowed:
#     /attendance/student-report/2BA23CS112
#
# Rejected:
#     /attendance/student-report/ANOTHER_STUDENT_USN
#
# ============================================================

@attendance_bp.route(
    "/attendance/student-report/<usn>",
    methods=["GET"]
)
@token_required
def student_attendance_report(usn):

    db = None
    cursor = None

    try:

        # ====================================================
        # GET AUTHENTICATED USER FROM TOKEN
        # ====================================================

        authenticated_user = request.auth_user

        authenticated_user_id = (
            authenticated_user.get("user_id")
        )

        authenticated_role = (
            authenticated_user.get("role")
        )

        print()
        print("======================================")
        print("STUDENT ATTENDANCE REPORT REQUEST")
        print("======================================")

        print(
            "Authenticated User ID:",
            authenticated_user_id
        )

        print(
            "Authenticated Role:",
            authenticated_role
        )

        print(
            "Requested USN:",
            usn
        )

        # ====================================================
        # ONLY STUDENTS CAN USE THIS ENDPOINT
        # ====================================================

        if str(authenticated_role).lower() != "student":

            print(
                "REPORT REJECTED: "
                "NON-STUDENT USER"
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "Only students can access this attendance report"

            }), 403

        # ====================================================
        # CLEAN REQUESTED USN
        # ====================================================

        usn = usn.strip().upper()

        if not usn:

            return jsonify({

                "success":
                    False,

                "message":
                    "Student USN is required"

            }), 400

        # ====================================================
        # DATABASE CONNECTION
        # ====================================================

        db = get_db_connection()

        cursor = db.cursor(
            dictionary=True
        )

        # ====================================================
        # FIND THE STUDENT BELONGING TO THE AUTHENTICATED
        # USER ACCOUNT
        #
        # IMPORTANT:
        #
        # We DO NOT trust the USN from the URL.
        #
        # The token contains user_id.
        #
        # We find the student's USN from:
        #
        # users.id
        #     ↓
        # students.user_id
        #
        # ====================================================

        cursor.execute(
            """
            SELECT
                id,
                user_id,
                student_id,
                full_name
            FROM students
            WHERE user_id = %s
            LIMIT 1
            """,
            (
                authenticated_user_id,
            )
        )

        authenticated_student = (
            cursor.fetchone()
        )

        # ====================================================
        # AUTHENTICATED USER MUST HAVE STUDENT PROFILE
        # ====================================================

        if not authenticated_student:

            print(
                "REPORT REJECTED: "
                "STUDENT PROFILE NOT FOUND FOR TOKEN"
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "Student profile not found"

            }), 404

        authenticated_usn = str(
            authenticated_student["student_id"]
        ).strip().upper()

        authenticated_student_id = (
            authenticated_student["id"]
        )

        # ====================================================
        # CRITICAL SECURITY CHECK
        #
        # The USN requested in the URL must belong to the
        # student who is logged in.
        # ====================================================

        if authenticated_usn != usn:

            print(
                "REPORT REJECTED: "
                "USN DOES NOT BELONG TO AUTHENTICATED USER"
            )

            print(
                "Authenticated USN:",
                authenticated_usn
            )

            print(
                "Requested USN:",
                usn
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "You are not authorized to access this attendance report"

            }), 403

        # ====================================================
        # GET EVERY CLASS SESSION FOR THIS STUDENT
        #
        # LEFT JOIN attendance is intentional:
        #
        # attendance exists
        #     -> Present / Late
        #
        # attendance does not exist
        #     -> Absent
        #
        # ====================================================

        cursor.execute(
            """
            SELECT

                sess.id AS session_id,

                sess.subject_code,

                sess.subject_name,

                sess.class_name,

                sess.semester,

                sess.division,

                sess.attendance_date,

                sess.start_time,

                sess.end_time,

                sess.status AS session_status,

                a.status AS attendance_status,

                a.attendance_time,

                a.face_verified,

                a.latitude,

                a.longitude,

                a.created_at AS attendance_created_at

            FROM attendance_sessions sess

            INNER JOIN class_roster cr
                ON cr.subject_code = sess.subject_code
                AND cr.semester = sess.semester
                AND cr.division = sess.division

            INNER JOIN students roster_student
                ON cr.student_id = roster_student.id
                AND roster_student.id = %s

            LEFT JOIN attendance a
                ON a.session_id = sess.id
                AND a.student_id = roster_student.id

            WHERE sess.status = 'closed'

            ORDER BY

                sess.attendance_date DESC,

                sess.start_time DESC,

                sess.id DESC

            """,
            (
                authenticated_student_id,
            )
        )

        records = cursor.fetchall()

        # ====================================================
        # CONVERT DATABASE VALUES TO JSON-SAFE VALUES
        # ====================================================

        for record in records:

            # ------------------------------------------------
            # DATE
            # ------------------------------------------------

            if record.get(
                "attendance_date"
            ) is not None:

                record[
                    "attendance_date"
                ] = str(
                    record[
                        "attendance_date"
                    ]
                )

            # ------------------------------------------------
            # START TIME
            # ------------------------------------------------

            if record.get(
                "start_time"
            ) is not None:

                record[
                    "start_time"
                ] = str(
                    record[
                        "start_time"
                    ]
                )

            # ------------------------------------------------
            # END TIME
            # ------------------------------------------------

            if record.get(
                "end_time"
            ) is not None:

                record[
                    "end_time"
                ] = str(
                    record[
                        "end_time"
                    ]
                )

            # ------------------------------------------------
            # ATTENDANCE TIME
            # ------------------------------------------------

            if record.get(
                "attendance_time"
            ) is not None:

                record[
                    "attendance_time"
                ] = str(
                    record[
                        "attendance_time"
                    ]
                )

            # ------------------------------------------------
            # ATTENDANCE CREATED AT
            # ------------------------------------------------

            if record.get(
                "attendance_created_at"
            ) is not None:

                record[
                    "attendance_created_at"
                ] = str(
                    record[
                        "attendance_created_at"
                    ]
                )

            # ------------------------------------------------
            # GPS LATITUDE
            # ------------------------------------------------

            if record.get(
                "latitude"
            ) is not None:

                record[
                    "latitude"
                ] = float(
                    record[
                        "latitude"
                    ]
                )

            # ------------------------------------------------
            # GPS LONGITUDE
            # ------------------------------------------------

            if record.get(
                "longitude"
            ) is not None:

                record[
                    "longitude"
                ] = float(
                    record[
                        "longitude"
                    ]
                )

            # ------------------------------------------------
            # FACE VERIFICATION
            # ------------------------------------------------

            if record.get(
                "face_verified"
            ) is not None:

                record[
                    "face_verified"
                ] = bool(
                    record[
                        "face_verified"
                    ]
                )

            # ------------------------------------------------
            # DETERMINE FINAL ATTENDANCE STATUS
            #
            # No attendance row = ABSENT
            # ------------------------------------------------

            if record.get(
                "attendance_status"
            ):

                record[
                    "status"
                ] = str(
                    record[
                        "attendance_status"
                    ]
                ).lower()

            else:

                record[
                    "status"
                ] = "absent"

            # ------------------------------------------------
            # Remove internal field
            # ------------------------------------------------

            record.pop(
                "attendance_status",
                None
            )

        # ====================================================
        # OVERALL ATTENDANCE SUMMARY
        # ====================================================

        total_classes = len(
            records
        )

        present_classes = sum(

            1

            for record in records

            if record[
                "status"
            ] in (
                "present",
                "late"
            )

        )

        absent_classes = (
            total_classes
            -
            present_classes
        )

        attendance_percentage = (

            (
                present_classes
                /
                total_classes
            )
            *
            100

            if total_classes > 0

            else 0

        )

        attendance_percentage = round(
            attendance_percentage,
            2
        )

        # ====================================================
        # SUBJECT-WISE SUMMARY
        # ====================================================

        subjects = {}

        for record in records:

            subject_code = (
                record.get(
                    "subject_code"
                )
                or ""
            )

            subject_name = (
                record.get(
                    "subject_name"
                )
                or
                record.get(
                    "class_name"
                )
                or
                ""
            )

            key = (
                subject_code
                if subject_code
                else subject_name
            )

            if key not in subjects:

                subjects[key] = {

                    "subject_code":
                        subject_code,

                    "subject_name":
                        subject_name,

                    "total_classes":
                        0,

                    "present_classes":
                        0,

                    "absent_classes":
                        0,

                    "attendance_percentage":
                        0,

                    "records":
                        []
                }

            subject = subjects[
                key
            ]

            subject[
                "total_classes"
            ] += 1

            if record[
                "status"
            ] in (
                "present",
                "late"
            ):

                subject[
                    "present_classes"
                ] += 1

            else:

                subject[
                    "absent_classes"
                ] += 1

            subject[
                "records"
            ].append(
                record
            )

        # ====================================================
        # CALCULATE SUBJECT PERCENTAGES
        # ====================================================

        for subject in subjects.values():

            total = (
                subject[
                    "total_classes"
                ]
            )

            present = (
                subject[
                    "present_classes"
                ]
            )

            subject[
                "attendance_percentage"
            ] = round(

                (
                    present
                    /
                    total
                )
                *
                100

                if total > 0

                else 0,

                2

            )

        # ====================================================
        # RESPONSE
        # ====================================================

        print(
            "REPORT SUCCESS"
        )

        print(
            "Student:",
            authenticated_usn
        )

        print(
            "Total Classes:",
            total_classes
        )

        print(
            "Present:",
            present_classes
        )

        print(
            "Absent:",
            absent_classes
        )

        print(
            "Percentage:",
            attendance_percentage
        )

        print(
            "======================================"
        )

        return jsonify({

            "success":
                True,

            "student": {

                "id":
                    authenticated_student[
                        "id"
                    ],

                "usn":
                    authenticated_student[
                        "student_id"
                    ],

                "name":
                    authenticated_student[
                        "full_name"
                    ]
            },

            "summary": {

                "total_classes":
                    total_classes,

                "present_classes":
                    present_classes,

                "absent_classes":
                    absent_classes,

                "attendance_percentage":
                    attendance_percentage
            },

            "subjects":
                list(
                    subjects.values()
                ),

            "attendance":
                records

        }), 200

    # ========================================================
    # ERROR HANDLING
    # ========================================================

    except Exception as error:

        print()
        print("======================================")
        print("STUDENT ATTENDANCE REPORT API ERROR")
        print("======================================")

        print(
            "Error:",
            error
        )

        if db:

            try:
                db.rollback()

            except Exception:
                pass

        return jsonify({

            "success":
                False,

            "message":
                "Could not fetch student attendance report",

            "error":
                str(error)

        }), 500

    # ========================================================
    # CLEANUP
    # ========================================================

    finally:

        if cursor:

            try:
                cursor.close()

            except Exception:
                pass

        if db:

            try:
                db.close()

            except Exception:
                pass
# ============================================================
# FACULTY ATTENDANCE REPORT API
# ============================================================
# ============================================================
# FACULTY ATTENDANCE REPORT API
#
# Reports are MERGED by:
#     faculty
#     subject_code
#     semester
#     division
#
# Example:
#
# CC / 22UCS124C / 7 / B
#
# Session 1
# Session 2
# Session 3
#
# becomes ONE report:
#
# CC / 22UCS124C / 7 / B
# Sessions conducted: 3
#
# ============================================================

# ============================================================
# FACULTY ATTENDANCE REPORT API
#
# SAME SUBJECT + SEMESTER + DIVISION = ONE MERGED REPORT
#
# Example:
#
# CC / 22UCS124C / 7 / B
#
# Session 48
# Session 50
# Session 52
#
# are shown as ONE CC report with:
#
# Sessions conducted: 3
#
# Each student's attendance is calculated across
# all 3 sessions.
# ============================================================

# ============================================================
# FACULTY ATTENDANCE REPORT API
#
# SAME SUBJECT + SEMESTER + DIVISION = ONE SUBJECT REPORT
#
# BUT EACH SESSION HAS ITS OWN:
#     - date
#     - session number
#     - summary
#     - student list
#
# Example:
#
# CC
# 22UCS124C / Semester 7 / Division B
#
# 16-09-2026 - Session 1
#     Present: 5
#     Absent: 1
#     Late: 0
#     Students:
#         Student 1 - Present
#         Student 2 - Absent
#         ...
#
# 16-09-2026 - Session 2
#     Present: 4
#     Absent: 2
#     Late: 0
#     Students:
#         Student 1 - Present
#         Student 2 - Absent
#         ...
#
# IMPORTANT:
# Students are NEVER merged between individual sessions.
# ============================================================

@attendance_bp.route("/faculty/attendance-report/<int:faculty_id>", methods=["GET"])
def faculty_attendance_report(faculty_id):

    db = None
    cursor = None

    try:

        print()
        print("======================================")
        print("FACULTY ATTENDANCE REPORT REQUEST")
        print("======================================")

        # ====================================================
        # QUERY PARAMETERS
        # ====================================================

        faculty_user_id = request.args.get(
            "faculty_user_id"
        )

        session_id_filter = request.args.get(
            "session_id"
        )

        subject_code_filter = request.args.get(
            "subject_code"
        )

        attendance_date_filter = request.args.get(
            "attendance_date"
        )

        print(
            "Faculty User ID:",
            faculty_user_id
        )

        print(
            "Session ID:",
            session_id_filter
        )

        print(
            "Subject Code:",
            subject_code_filter
        )

        print(
            "Attendance Date:",
            attendance_date_filter
        )

        # ====================================================
        # DATABASE
        # ====================================================

        db = get_db_connection()

        cursor = db.cursor(
            dictionary=True
        )

        # ====================================================
        # GET ALL SESSIONS BELONGING TO FACULTY
        # ====================================================

        session_query = """
            SELECT

                s.id AS session_id,

                s.faculty_id,

                s.class_name,

                s.subject_name,

                s.subject_code,

                s.semester,

                s.division,

                s.attendance_date,

                s.start_time,

                s.end_time,

                s.allowed_latitude,

                s.allowed_longitude,

                s.allowed_radius,

                s.status,

                s.created_at

            FROM attendance_sessions s

            INNER JOIN faculty f
                ON s.faculty_id = f.id

            WHERE 1 = 1
        """

        session_params = []

        # ====================================================
        # FACULTY FILTER
        # ====================================================

        if faculty_user_id:

            session_query += """
                AND f.user_id = %s
            """

            session_params.append(
                faculty_user_id
            )

        # ====================================================
        # SESSION FILTER
        # ====================================================

        if session_id_filter:

            session_query += """
                AND s.id = %s
            """

            session_params.append(
                session_id_filter
            )

        # ====================================================
        # SUBJECT FILTER
        # ====================================================

        if subject_code_filter:

            session_query += """
                AND UPPER(
                    TRIM(
                        s.subject_code
                    )
                )
                =
                UPPER(
                    TRIM(%s)
                )
            """

            session_params.append(
                subject_code_filter
            )

        # ====================================================
        # DATE FILTER
        # ====================================================

        if attendance_date_filter:

            session_query += """
                AND s.attendance_date = %s
            """

            session_params.append(
                attendance_date_filter
            )

        # ====================================================
        # IMPORTANT:
        #
        # Sessions are ordered OLD → NEW.
        #
        # This guarantees:
        #
        # Session 1
        # Session 2
        # Session 3
        #
        # in chronological order.
        # ====================================================

        session_query += """
            ORDER BY
                s.attendance_date ASC,
                s.start_time ASC,
                s.id ASC
        """

        cursor.execute(
            session_query,
            tuple(session_params)
        )

        sessions = cursor.fetchall()

        print(
            "SESSIONS FOUND:",
            len(sessions)
        )

        # ====================================================
        # NO SESSIONS
        # ====================================================

        if not sessions:

            return jsonify({

                "success":
                    True,

                "reports":
                    [],

                "message":
                    "No attendance sessions found."

            }), 200

        # ====================================================
        # GROUP SESSIONS
        #
        # SAME:
        #
        # subject_code
        # semester
        # division
        #
        # = ONE SUBJECT REPORT
        # ====================================================

        grouped_sessions = {}

        for session in sessions:

            subject_code = str(
                session.get(
                    "subject_code"
                )
                or ""
            ).strip().upper()

            semester = str(
                session.get(
                    "semester"
                )
                or ""
            ).strip()

            division = str(
                session.get(
                    "division"
                )
                or ""
            ).strip().upper()

            group_key = (
                subject_code,
                semester,
                division
            )

            if group_key not in grouped_sessions:

                grouped_sessions[
                    group_key
                ] = []

            grouped_sessions[
                group_key
            ].append(
                session
            )

        print(
            "SUBJECT GROUPS:",
            len(grouped_sessions)
        )

        reports = []

        # ====================================================
        # PROCESS EACH SUBJECT
        # ====================================================

        for group_key, subject_sessions in (
            grouped_sessions.items()
        ):

            (
                subject_code,
                semester,
                division
            ) = group_key

            # =================================================
            # EXTRA SAFETY:
            #
            # Sort sessions again inside the group.
            # =================================================

            subject_sessions = sorted(
                subject_sessions,
                key=lambda session: (
                    str(
                        session.get(
                            "attendance_date"
                        )
                        or ""
                    ),
                    str(
                        session.get(
                            "start_time"
                        )
                        or ""
                    ),
                    int(
                        session.get(
                            "session_id"
                        )
                        or 0
                    )
                )
            )

            session_count = len(
                subject_sessions
            )

            # =================================================
            # LATEST SESSION
            #
            # Kept for backward compatibility with existing
            # Flutter code.
            # =================================================

            latest_session = (
                subject_sessions[-1]
            )

            print()
            print("--------------------------------------")
            print("SUBJECT REPORT")
            print(
                "Subject Code:",
                subject_code
            )
            print(
                "Semester:",
                semester
            )
            print(
                "Division:",
                division
            )
            print(
                "Sessions:",
                session_count
            )
            print("--------------------------------------")

            # =================================================
            # GET CLASS ROSTER
            # =================================================

            cursor.execute(
                """
                SELECT

                    cr.student_id
                        AS roster_student_id,

                    st.student_id
                        AS usn,

                    st.full_name
                        AS student_name

                FROM class_roster cr

                INNER JOIN students st
                    ON cr.student_id = st.id

                WHERE

                    UPPER(
                        TRIM(
                            cr.subject_code
                        )
                    )
                    =
                    UPPER(
                        TRIM(%s)
                    )

                    AND TRIM(
                        CAST(
                            cr.semester AS CHAR
                        )
                    )
                    =
                    TRIM(
                        CAST(
                            %s AS CHAR
                        )
                    )

                    AND UPPER(
                        TRIM(
                            cr.division
                        )
                    )
                    =
                    UPPER(
                        TRIM(%s)
                    )

                ORDER BY
                    st.student_id ASC
                """,
                (
                    subject_code,
                    semester,
                    division
                )
            )

            roster_students = (
                cursor.fetchall()
            )

            print(
                "ROSTER STUDENTS:",
                len(roster_students)
            )

            roster_count = len(
                roster_students
            )

            # =================================================
            # CUMULATIVE STUDENT DATA
            #
            # This is retained only for compatibility.
            #
            # Flutter's session UI will use:
            #
            # session["students"]
            #
            # instead.
            # =================================================

            student_data = {}

            for roster_student in (
                roster_students
            ):

                student_id = (
                    roster_student[
                        "roster_student_id"
                    ]
                )

                student_data[
                    student_id
                ] = {

                    "usn":
                        roster_student[
                            "usn"
                        ],

                    "student_name":
                        roster_student[
                            "student_name"
                        ],

                    "present_sessions":
                        0,

                    "late_sessions":
                        0,

                    "absent_sessions":
                        0,

                    "attendance_records":
                        []
                }

            # =================================================
            # SESSION DETAILS
            #
            # IMPORTANT:
            #
            # Every object in this list gets its own
            # "students" array.
            # =================================================

            session_details = []

            # =================================================
            # OVERALL TOTALS
            # =================================================

            total_present = 0

            total_late = 0

            total_absent = 0

            # =================================================
            # PROCESS EVERY SESSION SEPARATELY
            # =================================================

            for session_index, current_session in enumerate(
                subject_sessions,
                start=1
            ):

                current_session_id = int(
                    current_session[
                        "session_id"
                    ]
                )

                print()
                print(
                    "Processing Session:",
                    current_session_id
                )

                print(
                    "Session Number:",
                    session_index
                )

                # =============================================
                # GET ATTENDANCE FOR THIS SESSION ONLY
                # =============================================

                cursor.execute(
                    """
                    SELECT

                        a.id AS attendance_id,

                        a.student_id,

                        a.attendance_date,

                        a.attendance_time,

                        a.status,

                        a.latitude,

                        a.longitude,

                        a.face_verified

                    FROM attendance a

                    WHERE
                        a.session_id = %s

                    ORDER BY
                        a.attendance_time ASC,
                        a.id ASC
                    """,
                    (
                        current_session_id,
                    )
                )

                attendance_records = (
                    cursor.fetchall()
                )

                # =============================================
                # CREATE QUICK LOOKUP
                #
                # student_id -> attendance record
                # =============================================

                attendance_by_student = {}

                for attendance in (
                    attendance_records
                ):

                    student_id = (
                        attendance[
                            "student_id"
                        ]
                    )

                    # Ignore students who are not in
                    # this class roster.

                    if student_id not in student_data:

                        continue

                    attendance_by_student[
                        student_id
                    ] = attendance

                # =============================================
                # SESSION STUDENT LIST
                #
                # THIS IS THE IMPORTANT CHANGE.
                #
                # Every session receives a completely
                # independent student list.
                # =============================================

                session_students = []

                session_present = 0

                session_late = 0

                session_absent = 0

                # =============================================
                # PROCESS EVERY ROSTER STUDENT
                # =============================================

                for roster_student in (
                    roster_students
                ):

                    student_id = (
                        roster_student[
                            "roster_student_id"
                        ]
                    )

                    usn = (
                        roster_student[
                            "usn"
                        ]
                    )

                    student_name = (
                        roster_student[
                            "student_name"
                        ]
                    )

                    attendance = (
                        attendance_by_student.get(
                            student_id
                        )
                    )

                    # =========================================
                    # DEFAULT = ABSENT
                    #
                    # If there is no attendance record for
                    # this student in THIS SESSION, the student
                    # is absent for THIS SESSION.
                    # =========================================

                    if attendance is None:

                        session_status = "Absent"

                        session_absent += 1

                        student_record = {

                            "usn":
                                usn,

                            "student_name":
                                student_name,

                            "status":
                                "Absent",

                            "attendance_date":
                                (
                                    str(
                                        current_session[
                                            "attendance_date"
                                        ]
                                    )
                                    if current_session.get(
                                        "attendance_date"
                                    ) is not None
                                    else None
                                ),

                            "attendance_time":
                                None,

                            "face_verified":
                                False,

                            "gps_verified":
                                False,

                            "mock_location":
                                None,

                            "distance":
                                None,

                            "latitude":
                                None,

                            "longitude":
                                None,

                            "session_id":
                                current_session_id,

                            "attendance_records":
                                []
                        }

                    else:

                        # =====================================
                        # GET STATUS
                        # =====================================

                        raw_status = str(
                            attendance.get(
                                "status"
                            )
                            or "present"
                        ).strip().lower()

                        # =====================================
                        # NORMALIZE STATUS
                        # =====================================

                        if raw_status == "late":

                            session_status = "Late"

                            session_late += 1

                        else:

                            session_status = "Present"

                            session_present += 1

                        # =====================================
                        # GPS DETAILS
                        # =====================================

                        gps_verified = False

                        distance = None

                        student_latitude = (
                            attendance.get(
                                "latitude"
                            )
                        )

                        student_longitude = (
                            attendance.get(
                                "longitude"
                            )
                        )

                        if (
                            student_latitude is not None
                            and student_longitude is not None
                            and current_session.get(
                                "allowed_latitude"
                            ) is not None
                            and current_session.get(
                                "allowed_longitude"
                            ) is not None
                            and current_session.get(
                                "allowed_radius"
                            ) is not None
                        ):

                            try:

                                from math import (
                                    radians,
                                    sin,
                                    cos,
                                    sqrt,
                                    atan2
                                )

                                earth_radius = (
                                    6371000.0
                                )

                                session_latitude = float(
                                    current_session[
                                        "allowed_latitude"
                                    ]
                                )

                                session_longitude = float(
                                    current_session[
                                        "allowed_longitude"
                                    ]
                                )

                                session_radius = float(
                                    current_session[
                                        "allowed_radius"
                                    ]
                                )

                                lat1 = radians(
                                    session_latitude
                                )

                                lon1 = radians(
                                    session_longitude
                                )

                                lat2 = radians(
                                    float(
                                        student_latitude
                                    )
                                )

                                lon2 = radians(
                                    float(
                                        student_longitude
                                    )
                                )

                                dlat = (
                                    lat2 - lat1
                                )

                                dlon = (
                                    lon2 - lon1
                                )

                                a = (
                                    sin(dlat / 2) ** 2
                                    +
                                    cos(lat1)
                                    *
                                    cos(lat2)
                                    *
                                    sin(dlon / 2) ** 2
                                )

                                c = (
                                    2
                                    *
                                    atan2(
                                        sqrt(a),
                                        sqrt(1 - a)
                                    )
                                )

                                distance = (
                                    earth_radius * c
                                )

                                gps_verified = (
                                    distance
                                    <=
                                    session_radius
                                )

                            except Exception as gps_error:

                                print(
                                    "GPS calculation error:",
                                    gps_error
                                )

                        # =====================================
                        # ATTENDANCE DATE
                        # =====================================

                        attendance_date = (
                            str(
                                attendance[
                                    "attendance_date"
                                ]
                            )
                            if attendance.get(
                                "attendance_date"
                            ) is not None
                            else None
                        )

                        # =====================================
                        # ATTENDANCE TIME
                        # =====================================

                        attendance_time = (
                            str(
                                attendance[
                                    "attendance_time"
                                ]
                            )
                            if attendance.get(
                                "attendance_time"
                            ) is not None
                            else None
                        )

                        # =====================================
                        # ONE ATTENDANCE RECORD
                        # =====================================

                        one_attendance_record = {

                            "session_id":
                                current_session_id,

                            "attendance_date":
                                attendance_date,

                            "attendance_time":
                                attendance_time,

                            "status":
                                raw_status,

                            "face_verified":
                                bool(
                                    attendance.get(
                                        "face_verified"
                                    )
                                ),

                            "latitude":
                                (
                                    float(
                                        student_latitude
                                    )
                                    if student_latitude is not None
                                    else None
                                ),

                            "longitude":
                                (
                                    float(
                                        student_longitude
                                    )
                                    if student_longitude is not None
                                    else None
                                )
                        }

                        # =====================================
                        # SESSION STUDENT RECORD
                        # =====================================

                        student_record = {

                            "usn":
                                usn,

                            "student_name":
                                student_name,

                            "status":
                                session_status,

                            "attendance_date":
                                attendance_date,

                            "attendance_time":
                                attendance_time,

                            "face_verified":
                                bool(
                                    attendance.get(
                                        "face_verified"
                                    )
                                ),

                            "gps_verified":
                                gps_verified,

                            "mock_location":
                                None,

                            "distance":
                                (
                                    round(
                                        distance,
                                        2
                                    )
                                    if distance is not None
                                    else None
                                ),

                            "latitude":
                                (
                                    float(
                                        student_latitude
                                    )
                                    if student_latitude is not None
                                    else None
                                ),

                            "longitude":
                                (
                                    float(
                                        student_longitude
                                    )
                                    if student_longitude is not None
                                    else None
                                ),

                            "session_id":
                                current_session_id,

                            "attendance_records":
                                [
                                    one_attendance_record
                                ]
                        }

                    # =========================================
                    # ADD STUDENT TO THIS SESSION ONLY
                    # =========================================

                    session_students.append(
                        student_record
                    )

                    # =========================================
                    # UPDATE CUMULATIVE DATA
                    #
                    # This does NOT affect session_students.
                    # =========================================

                    if attendance is None:

                        student_data[
                            student_id
                        ][
                            "absent_sessions"
                        ] += 1

                    else:

                        raw_status = str(
                            attendance.get(
                                "status"
                            )
                            or "present"
                        ).strip().lower()

                        if raw_status == "late":

                            student_data[
                                student_id
                            ][
                                "late_sessions"
                            ] += 1

                        else:

                            student_data[
                                student_id
                            ][
                                "present_sessions"
                            ] += 1

                        # Add cumulative attendance record

                        student_data[
                            student_id
                        ][
                            "attendance_records"
                        ].append({

                            "session_id":
                                current_session_id,

                            "attendance_date":
                                (
                                    str(
                                        attendance[
                                            "attendance_date"
                                        ]
                                    )
                                    if attendance.get(
                                        "attendance_date"
                                    ) is not None
                                    else None
                                ),

                            "attendance_time":
                                (
                                    str(
                                        attendance[
                                            "attendance_time"
                                        ]
                                    )
                                    if attendance.get(
                                        "attendance_time"
                                    ) is not None
                                    else None
                                ),

                            "status":
                                raw_status,

                            "face_verified":
                                bool(
                                    attendance.get(
                                        "face_verified"
                                    )
                                ),

                            "latitude":
                                (
                                    float(
                                        attendance[
                                            "latitude"
                                        ]
                                    )
                                    if attendance.get(
                                        "latitude"
                                    ) is not None
                                    else None
                                ),

                            "longitude":
                                (
                                    float(
                                        attendance[
                                            "longitude"
                                        ]
                                    )
                                    if attendance.get(
                                        "longitude"
                                    ) is not None
                                    else None
                                )
                        })

                # =============================================
                # SESSION TOTALS
                # =============================================

                session_total = (
                    session_present
                    +
                    session_late
                    +
                    session_absent
                )

                # Safety: total must equal roster size.

                if session_total < roster_count:

                    session_absent += (
                        roster_count
                        -
                        session_total
                    )

                elif session_total > roster_count:

                    print(
                        "WARNING: Session counts exceed roster."
                    )

                # =============================================
                # SESSION ATTENDANCE PERCENTAGE
                #
                # Present + Late are counted as attended.
                # =============================================

                session_percentage = 0.0

                if roster_count > 0:

                    session_percentage = round(
                        (
                            (
                                session_present
                                +
                                session_late
                            )
                            /
                            roster_count
                        )
                        *
                        100,
                        2
                    )

                # =============================================
                # OVERALL TOTALS
                # =============================================

                total_present += (
                    session_present
                )

                total_late += (
                    session_late
                )

                total_absent += (
                    session_absent
                )

                # =============================================
                # SESSION OBJECT
                #
                # THIS NOW CONTAINS:
                #
                # "students": session_students
                #
                # This is what Flutter will use.
                # =============================================

                session_details.append({
    "session_id": current_session_id,
    "session_number": session_index,

    # ====================================================
    # SESSION DATE & TIME
    # ====================================================

    "attendance_date": (
        current_session["attendance_date"].isoformat()
        if current_session["attendance_date"]
        else None
    ),

    "start_time": (
        str(current_session["start_time"])
        if current_session["start_time"]
        else None
    ),

    "end_time": (
        str(current_session["end_time"])
        if current_session["end_time"]
        else None
    ),

    # ====================================================
    # CLASS INFORMATION
    # ====================================================

    "subject_code": current_session["subject_code"],
    "subject_name": current_session["subject_name"],
    "class_name": current_session["class_name"],
    "semester": current_session["semester"],
    "division": current_session["division"],

    # ====================================================
    # GEOFENCE INFORMATION
    # ====================================================

    "teacher_latitude": current_session["allowed_latitude"],
    "teacher_longitude": current_session["allowed_longitude"],
    "geofence_radius": current_session["allowed_radius"],

    # ====================================================
    # SESSION STATUS
    # ====================================================

    "status": current_session["status"],

    # ====================================================
    # ATTENDANCE SUMMARY
    # ====================================================

    "present": session_present,
    "late": session_late,
    "absent": session_absent,
    "total_students": roster_count,
    "attendance_percentage": session_percentage,

    # ====================================================
    # THIS SESSION'S STUDENTS ONLY
    # ====================================================

    "students": session_students
})
                print(
                    "Session",
                    session_index,
                    "| ID:",
                    current_session_id,
                    "| Present:",
                    session_present,
                    "| Late:",
                    session_late,
                    "| Absent:",
                    session_absent,
                    "| Students:",
                    len(
                        session_students
                    )
                )

            # =================================================
            # BUILD CUMULATIVE STUDENT REPORT
            #
            # Kept for backward compatibility.
            # =================================================

            students = []

            for student_id, data in (
                student_data.items()
            ):

                present_sessions = (
                    data[
                        "present_sessions"
                    ]
                )

                late_sessions = (
                    data[
                        "late_sessions"
                    ]
                )

                absent_sessions = (
                    data[
                        "absent_sessions"
                    ]
                )

                attended_sessions = (
                    present_sessions
                    +
                    late_sessions
                )

                percentage = 0.0

                if session_count > 0:

                    percentage = round(
                        (
                            attended_sessions
                            /
                            session_count
                        )
                        *
                        100,
                        2
                    )

                latest_attendance = None

                if data[
                    "attendance_records"
                ]:

                    latest_attendance = (
                        data[
                            "attendance_records"
                        ][-1]
                    )

                latest_status = "Absent"

                if latest_attendance:

                    raw_latest_status = str(
                        latest_attendance.get(
                            "status"
                        )
                        or "present"
                    ).lower()

                    if raw_latest_status == "late":

                        latest_status = "Late"

                    else:

                        latest_status = "Present"

                face_verified = False

                gps_verified = False

                distance = None

                if latest_attendance:

                    face_verified = bool(
                        latest_attendance.get(
                            "face_verified"
                        )
                    )

                    student_latitude = (
                        latest_attendance.get(
                            "latitude"
                        )
                    )

                    student_longitude = (
                        latest_attendance.get(
                            "longitude"
                        )
                    )

                    if (
                        student_latitude is not None
                        and student_longitude is not None
                    ):

                        try:

                            from math import (
                                radians,
                                sin,
                                cos,
                                sqrt,
                                atan2
                            )

                            earth_radius = (
                                6371000.0
                            )

                            session_latitude = float(
                                latest_session[
                                    "allowed_latitude"
                                ]
                            )

                            session_longitude = float(
                                latest_session[
                                    "allowed_longitude"
                                ]
                            )

                            session_radius = float(
                                latest_session[
                                    "allowed_radius"
                                ]
                            )

                            lat1 = radians(
                                session_latitude
                            )

                            lon1 = radians(
                                session_longitude
                            )

                            lat2 = radians(
                                float(
                                    student_latitude
                                )
                            )

                            lon2 = radians(
                                float(
                                    student_longitude
                                )
                            )

                            dlat = (
                                lat2 - lat1
                            )

                            dlon = (
                                lon2 - lon1
                            )

                            a = (
                                sin(dlat / 2) ** 2
                                +
                                cos(lat1)
                                *
                                cos(lat2)
                                *
                                sin(dlon / 2) ** 2
                            )

                            c = (
                                2
                                *
                                atan2(
                                    sqrt(a),
                                    sqrt(1 - a)
                                )
                            )

                            distance = (
                                earth_radius * c
                            )

                            gps_verified = (
                                distance
                                <=
                                session_radius
                            )

                        except Exception as gps_error:

                            print(
                                "GPS calculation error:",
                                gps_error
                            )

                students.append({

                    "usn":
                        data[
                            "usn"
                        ],

                    "student_name":
                        data[
                            "student_name"
                        ],

                    "status":
                        latest_status,

                    "present_sessions":
                        present_sessions,

                    "late_sessions":
                        late_sessions,

                    "absent_sessions":
                        absent_sessions,

                    "attended_sessions":
                        attended_sessions,

                    "total_sessions":
                        session_count,

                    "attendance_percentage":
                        percentage,

                    "attendance_date":
                        (
                            latest_attendance[
                                "attendance_date"
                            ]
                            if latest_attendance
                            else None
                        ),

                    "attendance_time":
                        (
                            latest_attendance[
                                "attendance_time"
                            ]
                            if latest_attendance
                            else None
                        ),

                    "face_verified":
                        face_verified,

                    "gps_verified":
                        gps_verified,

                    "mock_location":
                        None,

                    "distance":
                        (
                            round(
                                distance,
                                2
                            )
                            if distance is not None
                            else None
                        ),

                    "latitude":
                        (
                            latest_attendance[
                                "latitude"
                            ]
                            if latest_attendance
                            else None
                        ),

                    "longitude":
                        (
                            latest_attendance[
                                "longitude"
                            ]
                            if latest_attendance
                            else None
                        ),

                    "attendance_records":
                        data[
                            "attendance_records"
                        ]
                })

            # =================================================
            # OVERALL TOTALS
            # =================================================

            total_students = len(
                roster_students
            )

            total_possible = (
                total_students
                *
                session_count
            )

            overall_percentage = 0.0

            if total_possible > 0:

                overall_percentage = round(
                    (
                        (
                            total_present
                            +
                            total_late
                        )
                        /
                        total_possible
                    )
                    *
                    100,
                    2
                )

            # =================================================
            # FINAL SUBJECT REPORT
            # =================================================

            reports.append({

                # =============================================
                # SUBJECT INFORMATION
                # =============================================

                "session": {

                    "session_id":
                        int(
                            latest_session[
                                "session_id"
                            ]
                        ),

                    "subject_name":
                        latest_session.get(
                            "subject_name"
                        ),

                    "subject_code":
                        latest_session.get(
                            "subject_code"
                        ),

                    "class_name":
                        latest_session.get(
                            "class_name"
                        ),

                    "semester":
                        latest_session.get(
                            "semester"
                        ),

                    "division":
                        latest_session.get(
                            "division"
                        ),

                    "attendance_date":
                        (
                            str(
                                latest_session[
                                    "attendance_date"
                                ]
                            )
                            if latest_session.get(
                                "attendance_date"
                            ) is not None
                            else None
                        ),

                    "start_time":
                        (
                            str(
                                latest_session[
                                    "start_time"
                                ]
                            )
                            if latest_session.get(
                                "start_time"
                            ) is not None
                            else None
                        ),

                    "end_time":
                        (
                            str(
                                latest_session[
                                    "end_time"
                                ]
                            )
                            if latest_session.get(
                                "end_time"
                            ) is not None
                            else None
                        ),

                    "allowed_latitude":
                        (
                            float(
                                latest_session[
                                    "allowed_latitude"
                                ]
                            )
                            if latest_session.get(
                                "allowed_latitude"
                            ) is not None
                            else None
                        ),

                    "allowed_longitude":
                        (
                            float(
                                latest_session[
                                    "allowed_longitude"
                                ]
                            )
                            if latest_session.get(
                                "allowed_longitude"
                            ) is not None
                            else None
                        ),

                    "allowed_radius":
                        (
                            float(
                                latest_session[
                                    "allowed_radius"
                                ]
                            )
                            if latest_session.get(
                                "allowed_radius"
                            ) is not None
                            else None
                        ),

                    "status":
                        latest_session.get(
                            "status"
                        ),

                    "created_at":
                        (
                            str(
                                latest_session[
                                    "created_at"
                                ]
                            )
                            if latest_session.get(
                                "created_at"
                            ) is not None
                            else None
                        )
                },

                # =============================================
                # NUMBER OF SESSIONS
                # =============================================

                "session_count":
                    session_count,

                # =============================================
                # EACH SESSION SEPARATELY
                #
                # Every item contains its own students[].
                # =============================================

                "sessions":
                    session_details,

                # =============================================
                # CUMULATIVE SUMMARY
                # =============================================

                "summary": {

                    "total_students":
                        total_students,

                    "total_sessions":
                        session_count,

                    "present":
                        total_present,

                    "absent":
                        total_absent,

                    "late":
                        total_late,

                    "total_possible":
                        total_possible,

                    "attendance_percentage":
                        overall_percentage
                },

                # =============================================
                # CUMULATIVE STUDENTS
                #
                # Kept for compatibility only.
                # =============================================

                "students":
                    students
            })

        # ====================================================
        # LATEST SUBJECT FIRST
        # ====================================================

        reports.reverse()

        # ====================================================
        # DEBUG OUTPUT
        # ====================================================

        print()
        print("======================================")
        print("FACULTY REPORT COMPLETE")
        print("======================================")

        print(
            "REPORTS:",
            len(reports)
        )

        for report in reports:

            print(
                "REPORT:",
                report[
                    "session"
                ][
                    "subject_code"
                ],

                "| Sessions:",
                report[
                    "session_count"
                ],

                "| Students:",
                report[
                    "summary"
                ][
                    "total_students"
                ],

                "| Present:",
                report[
                    "summary"
                ][
                    "present"
                ],

                "| Absent:",
                report[
                    "summary"
                ][
                    "absent"
                ],

                "| Late:",
                report[
                    "summary"
                ][
                    "late"
                ],

                "| Percentage:",
                report[
                    "summary"
                ][
                    "attendance_percentage"
                ]
            )

            for session in report[
                "sessions"
            ]:

                print(
                    "   Session",
                    session[
                        "session_number"
                    ],

                    "| ID:",
                    session[
                        "session_id"
                    ],

                    "| Date:",
                    session[
                        "attendance_date"
                    ],

                    "| Present:",
                    session[
                        "present"
                    ],

                    "| Absent:",
                    session[
                        "absent"
                    ],

                    "| Late:",
                    session[
                        "late"
                    ],

                    "| Students:",
                    len(
                        session[
                            "students"
                        ]
                    )
                )

        print(
            "======================================"
        )

        # ====================================================
        # RESPONSE
        # ====================================================

        return jsonify({

            "success":
                True,

            "reports":
                reports

        }), 200

    # ========================================================
    # ERROR HANDLING
    # ========================================================

    except Exception as error:

        print()
        print("======================================")
        print("FACULTY REPORT API ERROR")
        print("======================================")

        print(
            "Error:",
            error
        )

        if db:

            try:
                db.rollback()
            except Exception:
                pass

        return jsonify({

            "success":
                False,

            "message":
                "Failed to generate attendance report.",

            "error":
                str(error)

        }), 500

    # ========================================================
    # CLEANUP
    # ========================================================

    finally:

        if cursor:

            try:
                cursor.close()
            except Exception:
                pass

        if db:

            try:
                db.close()
            except Exception:
                pass