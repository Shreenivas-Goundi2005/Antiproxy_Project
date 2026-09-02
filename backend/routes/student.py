from flask import Blueprint, request, jsonify
from database import get_db_connection
from utils.hashing import hash_password

student_bp = Blueprint("student", __name__)


@student_bp.route("/students/register", methods=["POST"])
def register_student():
    data = request.get_json()

    student_id = data.get("student_id")
    username = data.get("username") or student_id
    password = data.get("password")
    full_name = data.get("full_name")
    email = data.get("email")
    department = data.get("department")
    semester = data.get("semester")

    if not password or not student_id or not full_name:
        return jsonify({
            "success": False,
            "message": "password, student_id and full_name are required"
        }), 400

    connection = get_db_connection()
    cursor = connection.cursor()

    try:
        password_hash = hash_password(password)

        cursor.execute(
            """
            INSERT INTO users (username, password_hash, role)
            VALUES (%s, %s, 'student')
            """,
            (username, password_hash)
        )

        user_id = cursor.lastrowid

        cursor.execute(
            """
            INSERT INTO students
            (user_id, student_id, full_name, email, department, semester)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (
                user_id,
                student_id,
                full_name,
                email,
                department,
                semester
            )
        )

        connection.commit()

        return jsonify({
            "success": True,
            "message": "Student registered successfully",
            "student": {
                "id": cursor.lastrowid,
                "student_id": student_id,
                "full_name": full_name
            }
        }), 201

    except Exception as error:
        connection.rollback()

        return jsonify({
            "success": False,
            "message": "Student registration failed",
            "error": str(error)
        }), 400

    finally:
        cursor.close()
        connection.close()
