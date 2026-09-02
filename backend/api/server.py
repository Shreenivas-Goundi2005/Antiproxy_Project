import sys
import os

sys.path.insert(
    0,
    os.path.dirname(
        os.path.dirname(
            os.path.abspath(__file__)
        )
    )
)

from flask import Flask, request, jsonify
from flask_cors import CORS

from database import get_db_connection
from geofence import check_geofence

app = Flask(__name__)
CORS(app)


# ============================================================
# HOME / TEST
# ============================================================

@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "success": True,
        "message": "AntiProxy API is running"
    })


# ============================================================
# STUDENT LOGIN / VERIFICATION
# ============================================================

@app.route("/api/student/<student_id>", methods=["GET"])
def get_student(student_id):

    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        cursor.execute(
            """
            SELECT
                id,
                user_id,
                student_id,
                full_name,
                email,
                department,
                semester,
                face_registered
            FROM students
            WHERE student_id = %s
            """,
            (student_id,)
        )

        student = cursor.fetchone()

        if not student:
            return jsonify({
                "success": False,
                "message": "Student not found"
            }), 404

        return jsonify({
            "success": True,
            "student": student
        })

    except Exception as e:

        return jsonify({
            "success": False,
            "message": "Database error",
            "error": str(e)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()


# ============================================================
# GEOFENCE CHECK
# ============================================================

@app.route("/api/geofence", methods=["POST"])
def geofence():

    try:

        data = request.get_json()

        if not data:
            return jsonify({
                "success": False,
                "message": "No JSON data received"
            }), 400

        latitude = float(data.get("latitude"))
        longitude = float(data.get("longitude"))

        result = check_geofence(
            latitude,
            longitude
        )

        return jsonify({
            "success": True,
            "latitude": latitude,
            "longitude": longitude,
            "inside": result["inside"],
            "distance": result["distance"],
            "allowed_radius": result["allowed_radius"]
        })

    except Exception as e:

        return jsonify({
            "success": False,
            "message": "Invalid location data",
            "error": str(e)
        }), 400


# ============================================================
# ATTENDANCE HISTORY
# ============================================================

@app.route("/api/attendance/<student_id>", methods=["GET"])
def attendance_history(student_id):

    db = None
    cursor = None

    try:

        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        cursor.execute(
            """
            SELECT
                a.id,
                s.student_id,
                s.full_name,
                a.attendance_date,
                a.attendance_time,
                a.status,
                a.latitude,
                a.longitude,
                a.face_verified
            FROM attendance a
            INNER JOIN students s
                ON a.student_id = s.id
            WHERE s.student_id = %s
            ORDER BY
                a.attendance_date DESC,
                a.attendance_time DESC
            """,
            (student_id,)
        )

        records = cursor.fetchall()

        return jsonify({
            "success": True,
            "student_id": student_id,
            "attendance": records
        })

    except Exception as e:

        return jsonify({
            "success": False,
            "message": "Could not load attendance",
            "error": str(e)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()


# ============================================================
# RUN SERVER
# ============================================================

if __name__ == "__main__":

    print()
    print("======================================")
    print("       ANTIPROXY API SERVER")
    print("======================================")
    print()
    print("Server running on:")
    print("http://0.0.0.0:5000")
    print()
    print("Press CTRL+C to stop.")
    print("======================================")

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True
    )