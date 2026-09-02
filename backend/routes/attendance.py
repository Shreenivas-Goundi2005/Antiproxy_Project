from flask import Blueprint, request, jsonify
from database import get_db_connection
from geofence import check_geofence

import cv2
import numpy as np
import json
from datetime import datetime
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
        return False, "Could not read uploaded image", 0.0

    faces = face_app.get(image)

    if len(faces) == 0:
        return False, "No face detected", 0.0

    if len(faces) > 1:
        return False, "Only one person is allowed", 0.0

    face = faces[0]

    current_embedding = face.embedding.astype(np.float32)

    current_norm = np.linalg.norm(current_embedding)

    if current_norm == 0:
        return False, "Invalid face embedding", 0.0

    current_embedding = current_embedding / current_norm

    try:
        registered = np.array(
            json.loads(registered_encoding),
            dtype=np.float32
        )
    except Exception:
        return False, "Invalid registered face data", 0.0

    registered_norm = np.linalg.norm(registered)

    if registered_norm == 0:
        return False, "Invalid registered face data", 0.0

    registered = registered / registered_norm

    similarity = float(
        np.dot(
            registered,
            current_embedding
        )
    )

    similarity = round(similarity, 4)

    print("Face similarity:", similarity)

    # --------------------------------------------------------
    # FACE MATCH THRESHOLD
    # --------------------------------------------------------

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
# ATTENDANCE API
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
        print("ATTENDANCE REQUEST")
        print("======================================")

        # ====================================================
        # GET FORM DATA
        # ====================================================

        usn = request.form.get("usn")

        latitude_raw = request.form.get("latitude")
        longitude_raw = request.form.get("longitude")
        accuracy_raw = request.form.get("accuracy")

        print("USN:", usn)
        print("Latitude:", latitude_raw)
        print("Longitude:", longitude_raw)
        print("Accuracy:", accuracy_raw)

        # ====================================================
        # VALIDATE USN
        # ====================================================

        if not usn:

            return jsonify({
                "success": False,
                "message": "USN is required"
            }), 400

        usn = usn.strip()

        # ====================================================
        # VALIDATE LOCATION
        # ====================================================

        if latitude_raw is None or longitude_raw is None:

            return jsonify({
                "success": False,
                "message": "GPS location is required"
            }), 400

        try:

            latitude = float(latitude_raw)
            longitude = float(longitude_raw)

        except ValueError:

            return jsonify({
                "success": False,
                "message": "Invalid GPS coordinates"
            }), 400

        # ====================================================
        # VALIDATE GPS RANGE
        # ====================================================

        if not (-90 <= latitude <= 90):

            return jsonify({
                "success": False,
                "message": "Invalid latitude"
            }), 400

        if not (-180 <= longitude <= 180):

            return jsonify({
                "success": False,
                "message": "Invalid longitude"
            }), 400

        # ====================================================
        # ACCURACY
        # ====================================================

        accuracy = None

        if accuracy_raw is not None:

            try:
                accuracy = float(accuracy_raw)
            except ValueError:
                accuracy = None

        # ====================================================
        # CHECK GEOFENCE FIRST
        # ====================================================

        geofence = check_geofence(
            latitude,
            longitude
        )

        print("Location distance:",
              geofence["distance"],
              "meters")

        print("Allowed radius:",
              geofence["allowed_radius"],
              "meters")

        print("Inside:",
              geofence["inside"])

        # ====================================================
        # LOCATION REJECTED
        # ====================================================

        if not geofence["inside"]:

            print("ATTENDANCE REJECTED: OUTSIDE GEOFENCE")

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
        # CHECK FACE IMAGE
        # ====================================================

        if "face" not in request.files:

            return jsonify({
                "success": False,
                "message": "Face image is required"
            }), 400

        face_file = request.files["face"]

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
        # FIND STUDENT
        # ====================================================

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

        student = cursor.fetchone()

        if not student:

            cursor.close()
            db.close()

            return jsonify({
                "success": False,
                "message": "Student not found"
            }), 404

        # ====================================================
        # FACE REGISTRATION CHECK
        # ====================================================

        if (
            not student["face_registered"]
            or not student["face_encoding"]
        ):

            cursor.close()
            db.close()

            return jsonify({
                "success": False,
                "message": "Face is not registered"
            }), 400

        # ====================================================
        # FACE VERIFICATION
        # ====================================================

        verified, face_message, similarity = verify_face(
            image_bytes,
            student["face_encoding"]
        )

        # ====================================================
        # FACE REJECTED
        # ====================================================

        if not verified:

            cursor.close()
            db.close()

            print(
                "ATTENDANCE REJECTED: FACE VERIFICATION FAILED"
            )

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
                }

            }), 403

        # ====================================================
        # OPTIONAL: DUPLICATE ATTENDANCE CHECK
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

        existing_attendance = cursor.fetchone()

        if existing_attendance:

            cursor.close()
            db.close()

            print(
                "ATTENDANCE REJECTED: ALREADY MARKED TODAY"
            )

            return jsonify({

                "success": False,

                "message":
                    "Attendance has already been marked today",

                "reason":
                    "already_marked",

                "student": {

                    "usn":
                        student["student_id"],

                    "name":
                        student["full_name"]
                }

            }), 409

        # ====================================================
        # MARK ATTENDANCE
        # ====================================================

        now = datetime.now()

        cursor.execute(
            """
            INSERT INTO attendance
            (
                student_id,
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
                %s
            )
            """,
            (
                student["id"],
                now.date(),
                now.time(),
                "present",
                latitude,
                longitude,
                1
            )
        )

        db.commit()

        cursor.close()
        db.close()

        print()
        print("======================================")
        print("ATTENDANCE MARKED SUCCESSFULLY")
        print("======================================")

        # ====================================================
        # SUCCESS RESPONSE
        # ====================================================

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

    # ========================================================
    # ERROR HANDLING
    # ========================================================

    except Exception as error:

        print()
        print("======================================")
        print("ATTENDANCE API ERROR")
        print("======================================")
        print(error)

        if db:

            try:
                db.rollback()
            except Exception:
                pass

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

        return jsonify({

            "success":
                False,

            "message":
                "Attendance marking failed",

            "error":
                str(error)

        }), 500
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
        cursor = db.cursor(dictionary=True)

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
                a.created_at
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

        return jsonify({
            "success": True,
            "student": usn,
            "count": len(records),
            "attendance": records
        }), 200

    except Exception as error:

        if db:
            try:
                db.rollback()
            except Exception:
                pass

        return jsonify({
            "success": False,
            "message": "Could not fetch attendance history",
            "error": str(error)
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