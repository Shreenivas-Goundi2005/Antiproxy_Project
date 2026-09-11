from flask import Blueprint, request, jsonify
from database import get_db_connection
from geofence import check_geofence

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
# ============================================================

@attendance_bp.route(
    "/attendance/mark-session",
    methods=["POST"]
)
def mark_session_attendance():

    db = None
    cursor = None

    try:

        print()
        print("======================================")
        print("QR SESSION ATTENDANCE REQUEST")
        print("======================================")

        # ====================================================
        # GET FORM DATA
        # ====================================================

        usn = request.form.get(
            "usn"
        )

        qr_token = request.form.get(
            "qr_token"
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

        is_mocked_raw = request.form.get(
            "is_mocked"
        )

        print(
            "USN:",
            usn
        )

        print(
            "QR Token:",
            qr_token
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

        print(
            "Is mocked:",
            is_mocked_raw
        )

        # ====================================================
        # VALIDATE USN
        # ====================================================

        if not usn:

            return jsonify({

                "success":
                    False,

                "message":
                    "USN is required",

                "reason":
                    "missing_usn"

            }), 400

        usn = usn.strip()

        # ====================================================
        # VALIDATE QR TOKEN
        # ====================================================

        if not qr_token:

            return jsonify({

                "success":
                    False,

                "message":
                    "Attendance QR code is required",

                "reason":
                    "missing_qr_token"

            }), 400

        qr_token = qr_token.strip()

        # ====================================================
        # MOCK LOCATION CHECK
        # ====================================================

        if is_mocked_raw is not None:

            mocked_value = str(
                is_mocked_raw
            ).strip().lower()

            if mocked_value in (
                "true",
                "1",
                "yes"
            ):

                print(
                    "ATTENDANCE REJECTED: "
                    "MOCK LOCATION"
                )

                return jsonify({

                    "success":
                        False,

                    "message":
                        "Attendance rejected: "
                        "fake or mock GPS location detected",

                    "reason":
                        "mock_location"

                }), 403

        # ====================================================
        # GPS VALIDATION
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

                "success":
                    False,

                "message":
                    location_error,

                "reason":
                    "invalid_location"

            }), 400

        # ====================================================
        # DATABASE
        # ====================================================

        db = get_db_connection()

        cursor = db.cursor(
            dictionary=True
        )

        # ====================================================
        # FIND SESSION USING QR TOKEN
        # ====================================================

        cursor.execute(
            """
            SELECT
                id,
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
            FROM attendance_sessions
            WHERE qr_token = %s
            LIMIT 1
            """,
            (qr_token,)
        )

        session = cursor.fetchone()

        # ====================================================
        # INVALID QR
        # ====================================================

        if not session:

            print(
                "ATTENDANCE REJECTED: "
                "INVALID QR TOKEN"
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "Invalid attendance QR code",

                "reason":
                    "invalid_qr"

            }), 404

        # ====================================================
        # SESSION STATUS
        # ====================================================

        if str(
            session["status"]
        ).lower() != "active":

            print(
                "ATTENDANCE REJECTED: "
                "SESSION NOT ACTIVE"
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "This attendance session is no longer active",

                "reason":
                    "session_not_active"

            }), 403

        # ====================================================
        # CURRENT DATE / TIME
        # ====================================================

        now = datetime.now()

        # ====================================================
        # SESSION DATE CHECK
        # ====================================================

        session_date = session[
            "attendance_date"
        ]

        if isinstance(
            session_date,
            datetime
        ):

            session_date = (
                session_date.date()
            )

        if session_date != now.date():

            print(
                "ATTENDANCE REJECTED: "
                "SESSION DATE EXPIRED"
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "This attendance session is not valid today",

                "reason":
                    "session_date_invalid"

            }), 403

        # ====================================================
        # SESSION TIME CHECK
        # ====================================================

        session_start = mysql_time_to_time(
            session["start_time"]
        )

        session_end = mysql_time_to_time(
            session["end_time"]
        )

        current_time = now.time()

        print(
            "Session start:",
            session_start
        )

        print(
            "Session end:",
            session_end
        )

        print(
            "Current time:",
            current_time
        )

        if session_start is None:

            return jsonify({

                "success":
                    False,

                "message":
                    "Session start time is invalid",

                "reason":
                    "invalid_session_start"

            }), 500

        if session_end is None:

            return jsonify({

                "success":
                    False,

                "message":
                    "Session end time is invalid",

                "reason":
                    "invalid_session_end"

            }), 500

        if current_time < session_start:

            print(
                "ATTENDANCE REJECTED: "
                "SESSION NOT STARTED"
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "Attendance session has not started yet",

                "reason":
                    "session_not_started"

            }), 403

        if current_time > session_end:

            print(
                "ATTENDANCE REJECTED: "
                "SESSION EXPIRED"
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "Attendance session has expired",

                "reason":
                    "session_expired"

            }), 403

        # ====================================================
        # SESSION GEOFENCE
        # ====================================================

        from math import (
            radians,
            sin,
            cos,
            sqrt,
            atan2
        )

        earth_radius = 6371000.0

        lat1 = radians(
            float(
                session["allowed_latitude"]
            )
        )

        lon1 = radians(
            float(
                session["allowed_longitude"]
            )
        )

        lat2 = radians(
            latitude
        )

        lon2 = radians(
            longitude
        )

        dlat = lat2 - lat1
        dlon = lon2 - lon1

        a = (
            sin(dlat / 2) ** 2
            +
            cos(lat1)
            *
            cos(lat2)
            *
            sin(dlon / 2) ** 2
        )

        c = 2 * atan2(
            sqrt(a),
            sqrt(1 - a)
        )

        distance = (
            earth_radius * c
        )

        allowed_radius = float(
            session["allowed_radius"]
        )

        inside = (
            distance <= allowed_radius
        )

        print(
            "Session distance:",
            round(
                distance,
                2
            ),
            "meters"
        )

        print(
            "Session allowed radius:",
            allowed_radius,
            "meters"
        )

        print(
            "Inside session geofence:",
            inside
        )

        # ====================================================
        # OUTSIDE SESSION GEOFENCE
        # ====================================================

        if not inside:

            print(
                "ATTENDANCE REJECTED: "
                "OUTSIDE SESSION GEOFENCE"
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "Attendance rejected: you are outside "
                    "the teacher's allowed attendance area",

                "reason":
                    "outside_session_geofence",

                "location": {

                    "latitude":
                        latitude,

                    "longitude":
                        longitude,

                    "accuracy":
                        accuracy,

                    "distance":
                        round(
                            distance,
                            2
                        ),

                    "allowed_radius":
                        allowed_radius,

                    "inside":
                        False
                },

                "session": {

                    "id":
                        session["id"],

                    "class_name":
                        session["class_name"],

                    "subject_name":
                        session["subject_name"]
                }

            }), 403

        # ====================================================
        # FACE IMAGE
        # ====================================================

        if "face" not in request.files:

            return jsonify({

                "success":
                    False,

                "message":
                    "Face image is required",

                "reason":
                    "missing_face"

            }), 400

        face_file = request.files[
            "face"
        ]

        image_bytes = face_file.read()

        if not image_bytes:

            return jsonify({

                "success":
                    False,

                "message":
                    "Empty face image",

                "reason":
                    "empty_face"

            }), 400

        # ====================================================
        # FIND STUDENT
        # ====================================================

        student = get_student(
            cursor,
            usn
        )

        if not student:

            print(
                "ATTENDANCE REJECTED: "
                "STUDENT NOT FOUND"
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "Student not found",

                "reason":
                    "student_not_found"

            }), 404

        # ====================================================
        # FACE REGISTRATION
        # ====================================================

        if (
            not student["face_registered"]
            or not student["face_encoding"]
        ):

            return jsonify({

                "success":
                    False,

                "message":
                    "Face is not registered",

                "reason":
                    "face_not_registered"

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

        # ====================================================
        # FACE REJECTED
        # ====================================================

        if not verified:

            print(
                "ATTENDANCE REJECTED: "
                "FACE VERIFICATION FAILED"
            )

            return jsonify({

                "success":
                    False,

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
                },

                "location": {

                    "latitude":
                        latitude,

                    "longitude":
                        longitude,

                    "accuracy":
                        accuracy,

                    "distance":
                        round(
                            distance,
                            2
                        ),

                    "allowed_radius":
                        allowed_radius,

                    "inside":
                        True
                }

            }), 403

        # ====================================================
        # SESSION DUPLICATE CHECK
        #
        # One student = one attendance for one session.
        # ====================================================

        cursor.execute(
            """
            SELECT
                id,
                attendance_date,
                attendance_time
            FROM attendance
            WHERE student_id = %s
              AND session_id = %s
            LIMIT 1
            """,
            (
                student["id"],
                session["id"]
            )
        )

        existing_attendance = (
            cursor.fetchone()
        )

        if existing_attendance:

            print(
                "ATTENDANCE REJECTED: "
                "ALREADY MARKED FOR SESSION"
            )

            return jsonify({

                "success":
                    False,

                "message":
                    "Attendance has already been marked "
                    "for this session",

                "reason":
                    "already_marked_for_session",

                "student": {

                    "usn":
                        student["student_id"],

                    "name":
                        student["full_name"]
                },

                "session": {

                    "id":
                        session["id"],

                    "subject_name":
                        session["subject_name"]
                }

            }), 409

        # ====================================================
        # INSERT SESSION ATTENDANCE
        # ====================================================

        try:

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
                    session["id"],
                    now.date(),
                    now.time(),
                    "present",
                    latitude,
                    longitude,
                    1
                )
            )

            db.commit()

        except IntegrityError as error:

            print(
                "ATTENDANCE REJECTED: "
                "DUPLICATE SESSION ATTENDANCE"
            )

            print(
                "Database error:",
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
                    "Attendance has already been marked "
                    "for this session",

                "reason":
                    "already_marked_for_session",

                "student": {

                    "usn":
                        student["student_id"],

                    "name":
                        student["full_name"]
                },

                "session": {

                    "id":
                        session["id"],

                    "subject_name":
                        session["subject_name"]
                }

            }), 409

        # ====================================================
        # SUCCESS
        # ====================================================

        print()
        print("======================================")
        print("QR SESSION ATTENDANCE MARKED")
        print("======================================")

        return jsonify({

            "success":
                True,

            "message":
                "Attendance marked successfully",

            "student": {

                "usn":
                    student["student_id"],

                "name":
                    student["full_name"]
            },

            "session": {

                "id":
                    session["id"],

                "class_name":
                    session["class_name"],

                "subject_name":
                    session["subject_name"],

                "attendance_date":
                    str(
                        session["attendance_date"]
                    ),

                "start_time":
                    str(
                        session["start_time"]
                    ),

                "end_time":
                    str(
                        session["end_time"]
                    )
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
                    round(
                        distance,
                        2
                    ),

                "allowed_radius":
                    allowed_radius,

                "inside":
                    True
            },

            "attendance": {

                "status":
                    "present"
            }

        }), 200

    # ========================================================
    # ERROR HANDLING
    # ========================================================

    except Exception as error:

        print()
        print("======================================")
        print("QR SESSION ATTENDANCE API ERROR")
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
                "Session attendance marking failed",

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

        usn = usn.strip()

        db = get_db_connection()

        cursor = db.cursor(
            dictionary=True
        )

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
                a.session_id
            FROM attendance a
            JOIN students s
                ON a.student_id = s.id
            WHERE s.student_id = %s
            ORDER BY
                a.attendance_date DESC,
                a.attendance_time DESC
            """,
            (usn,)
        )

        records = cursor.fetchall()

        for record in records:

            record["attendance_date"] = str(
                record["attendance_date"]
            )

            record["attendance_time"] = str(
                record["attendance_time"]
            )

            record["created_at"] = str(
                record["created_at"]
            )

            if record["latitude"] is not None:

                record["latitude"] = float(
                    record["latitude"]
                )

            if record["longitude"] is not None:

                record["longitude"] = float(
                    record["longitude"]
                )

            record["face_verified"] = bool(
                record["face_verified"]
            )

            if record["session_id"] is not None:

                record["session_id"] = int(
                    record["session_id"]
                )

        return jsonify({

            "success":
                True,

            "student":
                usn,

            "count":
                len(records),

            "attendance":
                records

        }), 200

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

            "success":
                False,

            "message":
                "Could not fetch attendance history",

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