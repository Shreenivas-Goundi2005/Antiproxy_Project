import json
import cv2
import numpy as np
import bcrypt

from flask import Blueprint, request, jsonify
from database import get_db_connection
from insightface.app import FaceAnalysis


register_bp = Blueprint("register", __name__)


# ==============================
# LOAD INSIGHTFACE
# ==============================

face_app = FaceAnalysis(
    name="buffalo_l",
    providers=["CPUExecutionProvider"]
)

face_app.prepare(
    ctx_id=0,
    det_size=(640, 640)
)


# ==============================
# REGISTER STUDENT
# ==============================

@register_bp.route("/register", methods=["POST"])
def register_student():

    try:

        # --------------------------
        # Get text fields
        # --------------------------

        name = request.form.get("name")
        usn = request.form.get("usn")
        semester = request.form.get("semester")
        division = request.form.get("division")
        department = request.form.get("department")
        password = request.form.get("password")

        # --------------------------
        # Validate fields
        # --------------------------

        if not all([
            name,
            usn,
            semester,
            division,
            department,
            password
        ]):
            return jsonify({
                "success": False,
                "message": "All fields are required"
            }), 400

        if len(password) < 6:
            return jsonify({
                "success": False,
                "message": "Password must contain at least 6 characters"
            }), 400

        # --------------------------
        # Get photos
        # --------------------------

        photos = request.files.getlist("photos")

        if len(photos) < 3 or len(photos) > 4:
            return jsonify({
                "success": False,
                "message": "Please upload 3 or 4 photos"
            }), 400

        # --------------------------
        # Database connection
        # --------------------------

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        # --------------------------
        # Check existing USN
        # --------------------------

        cursor.execute(
            """
            SELECT id
            FROM students
            WHERE student_id = %s
            """,
            (usn,)
        )

        existing_student = cursor.fetchone()

        if existing_student:

            cursor.close()
            connection.close()

            return jsonify({
                "success": False,
                "message": "USN is already registered"
            }), 409

        # --------------------------
        # Check username
        # --------------------------

        cursor.execute(
            """
            SELECT id
            FROM users
            WHERE username = %s
            """,
            (usn,)
        )

        existing_user = cursor.fetchone()

        if existing_user:

            cursor.close()
            connection.close()

            return jsonify({
                "success": False,
                "message": "User account already exists"
            }), 409

        # --------------------------
        # Process faces
        # --------------------------

        embeddings = []

        for photo in photos:

            image_bytes = photo.read()

            image_array = np.frombuffer(
                image_bytes,
                np.uint8
            )

            image = cv2.imdecode(
                image_array,
                cv2.IMREAD_COLOR
            )

            if image is None:
                cursor.close()
                connection.close()

                return jsonify({
                    "success": False,
                    "message": "One of the uploaded images is invalid"
                }), 400

            faces = face_app.get(image)

            if len(faces) == 0:
                cursor.close()
                connection.close()

                return jsonify({
                    "success": False,
                    "message": "No face detected in one of the photos"
                }), 400

            if len(faces) > 1:
                cursor.close()
                connection.close()

                return jsonify({
                    "success": False,
                    "message": "Multiple faces detected. Each photo must contain only one person"
                }), 400

            embedding = faces[0].embedding

            embedding = embedding / np.linalg.norm(embedding)

            embeddings.append(embedding)

        # --------------------------
        # Average embeddings
        # --------------------------

        final_embedding = np.mean(
            embeddings,
            axis=0
        )

        final_embedding = (
            final_embedding /
            np.linalg.norm(final_embedding)
        )

        embedding_json = json.dumps(
            final_embedding.tolist()
        )

        # --------------------------
        # Hash password
        # --------------------------

        password_hash = bcrypt.hashpw(
            password.encode("utf-8"),
            bcrypt.gensalt()
        ).decode("utf-8")

        # --------------------------
        # Insert user
        # --------------------------

        cursor.execute(
            """
            INSERT INTO users
            (username, password_hash, role)
            VALUES (%s, %s, 'student')
            """,
            (
                usn,
                password_hash
            )
        )

        user_id = cursor.lastrowid

        # --------------------------
        # Insert student
        # --------------------------

        cursor.execute(
            """
            INSERT INTO students
            (
                user_id,
                student_id,
                full_name,
                department,
                semester,
                division,
                face_registered,
                face_encoding
            )
            VALUES
            (%s, %s, %s, %s, %s, %s, 1, %s)
            """,
            (
                user_id,
                usn,
                name,
                department,
                int(semester),
                division,
                embedding_json
            )
        )

        connection.commit()

        cursor.close()
        connection.close()

        return jsonify({
            "success": True,
            "message": "Student registration successful",
            "student": {
                "name": name,
                "usn": usn,
                "semester": semester,
                "division": division,
                "department": department
            }
        }), 201

    except Exception as e:

        try:
            connection.rollback()
            cursor.close()
            connection.close()
        except:
            pass

        print("Registration error:", e)

        return jsonify({
            "success": False,
            "message": "Registration failed",
            "error": str(e)
        }), 500