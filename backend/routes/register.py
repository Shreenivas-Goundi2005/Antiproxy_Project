import os
import re
import json
import shutil

import cv2
import numpy as np
import bcrypt

from flask import Blueprint, request, jsonify
from database import get_db_connection
from insightface.app import FaceAnalysis


register_bp = Blueprint("register", __name__)

# Store original registration photos in the existing dataset.
DATASET_PATH = (
    r"C:\Users\Shreenivas\Downloads\AntiProxy\face_dataset"
)

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
MAX_PHOTOS = 4
MIN_PHOTOS = 3


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

    connection = None
    cursor = None
    student_folder = None
    registration_succeeded = False

    try:
        # --------------------------
        # Get text fields
        # --------------------------

        name = (request.form.get("name") or "").strip()
        usn = (request.form.get("usn") or "").strip().upper()
        semester = (request.form.get("semester") or "").strip()
        division = (request.form.get("division") or "").strip().upper()
        department = (request.form.get("department") or "").strip()
        password = request.form.get("password") or ""

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

        if not semester.isdigit():
            return jsonify({
                "success": False,
                "message": "Semester must be a number"
            }), 400

        # Prevent path traversal in the student folder name.
        if not re.fullmatch(r"[A-Z0-9_-]{1,50}", usn):
            return jsonify({
                "success": False,
                "message": "USN contains invalid characters"
            }), 400

        # --------------------------
        # Get uploaded photos
        # --------------------------

        photos = request.files.getlist("photos")

        if not MIN_PHOTOS <= len(photos) <= MAX_PHOTOS:
            return jsonify({
                "success": False,
                "message": "Please upload 3 or 4 photos"
            }), 400

        if any(not photo or not photo.filename for photo in photos):
            return jsonify({
                "success": False,
                "message": "One or more photos are missing"
            }), 400

        # --------------------------
        # Check database records
        # --------------------------

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute(
            """
            SELECT id
            FROM students
            WHERE student_id = %s
            """,
            (usn,)
        )

        if cursor.fetchone():
            return jsonify({
                "success": False,
                "message": "USN is already registered"
            }), 409

        cursor.execute(
            """
            SELECT id
            FROM users
            WHERE username = %s
            """,
            (usn,)
        )

        if cursor.fetchone():
            return jsonify({
                "success": False,
                "message": "User account already exists"
            }), 409

        # --------------------------
        # Prepare dataset directory
        # --------------------------

        os.makedirs(DATASET_PATH, exist_ok=True)

        student_folder = os.path.join(DATASET_PATH, usn)

        # Never overwrite an existing student's photo folder.
        if os.path.exists(student_folder):
            return jsonify({
                "success": False,
                "message": (
                    "A photo folder for this USN already exists. "
                    "Please check the existing dataset before retrying."
                )
            }), 409

        # --------------------------
        # Validate photos and extract
        # face embeddings
        # --------------------------

        embeddings = []
        decoded_images = []

        for index, photo in enumerate(photos, start=1):

            extension = os.path.splitext(photo.filename)[1].lower()

            if extension not in ALLOWED_EXTENSIONS:
                return jsonify({
                    "success": False,
                    "message": (
                        f"Photo {index} has an unsupported format. "
                        "Use JPG, JPEG, PNG or WEBP."
                    )
                }), 400

            image_bytes = photo.read()

            if not image_bytes:
                return jsonify({
                    "success": False,
                    "message": f"Photo {index} is empty"
                }), 400

            image_array = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)

            if image is None:
                return jsonify({
                    "success": False,
                    "message": f"Photo {index} is invalid"
                }), 400

            faces = face_app.get(image)

            if len(faces) == 0:
                return jsonify({
                    "success": False,
                    "message": f"No face detected in photo {index}"
                }), 400

            if len(faces) > 1:
                return jsonify({
                    "success": False,
                    "message": (
                        f"Multiple faces detected in photo {index}. "
                        "Each photo must contain only one person."
                    )
                }), 400

            embedding = faces[0].embedding
            norm = np.linalg.norm(embedding)

            if not np.isfinite(norm) or norm == 0:
                return jsonify({
                    "success": False,
                    "message": f"Could not process the face in photo {index}"
                }), 400

            embeddings.append(embedding / norm)
            decoded_images.append(image)

        # --------------------------
        # Average face embeddings
        # --------------------------

        final_embedding = np.mean(embeddings, axis=0)
        final_norm = np.linalg.norm(final_embedding)

        if not np.isfinite(final_norm) or final_norm == 0:
            return jsonify({
                "success": False,
                "message": "Could not generate a valid face encoding"
            }), 400

        final_embedding = final_embedding / final_norm
        embedding_json = json.dumps(final_embedding.tolist())

        # --------------------------
        # Save original photos
        # as JPEG files
        # --------------------------

        os.makedirs(student_folder, exist_ok=False)

        for index, image in enumerate(decoded_images, start=1):
            image_path = os.path.join(
                student_folder,
                f"photo_{index}.jpg"
            )

            if not cv2.imwrite(image_path, image):
                raise OSError(
                    f"Could not save registration photo {index}"
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
            (usn, password_hash)
        )

        user_id = cursor.lastrowid

        # --------------------------
        # Insert student and
        # existing face encoding
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
            VALUES (%s, %s, %s, %s, %s, %s, 1, %s)
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
        registration_succeeded = True

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

    except Exception as error:

        if connection:
            try:
                connection.rollback()
            except Exception:
                pass

        print("Registration error:", error)

        return jsonify({
            "success": False,
            "message": "Registration failed",
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

        # Remove newly created photo files if registration failed.
        if not registration_succeeded and student_folder:
            if os.path.isdir(student_folder):
                try:
                    shutil.rmtree(student_folder)
                except Exception as cleanup_error:
                    print(
                        "Could not clean up registration folder:",
                        cleanup_error
                    )
