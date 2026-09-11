import bcrypt

from flask import Blueprint, request, jsonify
from database import get_db_connection

faculty_register_bp = Blueprint("faculty_register", __name__)


@faculty_register_bp.route("/faculty/register", methods=["POST"])
def register_faculty():

    connection = None
    cursor = None

    try:
        data = request.get_json()

        if not data:
            return jsonify({
                "success": False,
                "message": "Request data is required"
            }), 400

        name = data.get("name", "").strip()
        faculty_id = data.get("faculty_id", "").strip().upper()
        department = data.get("department", "").strip()
        password = data.get("password", "")

        if not all([name, faculty_id, department, password]):
            return jsonify({
                "success": False,
                "message": "All fields are required"
            }), 400

        if len(password) < 6:
            return jsonify({
                "success": False,
                "message": "Password must contain at least 6 characters"
            }), 400

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        # Check whether faculty ID already exists
        cursor.execute(
            "SELECT id FROM faculty WHERE faculty_id = %s",
            (faculty_id,)
        )

        if cursor.fetchone():
            return jsonify({
                "success": False,
                "message": "Employee ID is already registered"
            }), 409

        # Check username in users table
        cursor.execute(
            "SELECT id FROM users WHERE username = %s",
            (faculty_id,)
        )

        if cursor.fetchone():
            return jsonify({
                "success": False,
                "message": "User account already exists"
            }), 409

        # Hash password
        password_hash = bcrypt.hashpw(
            password.encode("utf-8"),
            bcrypt.gensalt()
        ).decode("utf-8")

        # Create faculty login account
        cursor.execute(
            """
            INSERT INTO users
            (username, password_hash, role)
            VALUES (%s, %s, 'faculty')
            """,
            (faculty_id, password_hash)
        )

        user_id = cursor.lastrowid

        # Create faculty profile
        cursor.execute(
            """
            INSERT INTO faculty
            (user_id, faculty_id, full_name, department)
            VALUES (%s, %s, %s, %s)
            """,
            (user_id, faculty_id, name, department)
        )

        connection.commit()

        return jsonify({
            "success": True,
            "message": "Faculty registration successful",
            "faculty": {
                "name": name,
                "faculty_id": faculty_id,
                "department": department
            }
        }), 201

    except Exception as e:

        if connection:
            try:
                connection.rollback()
            except:
                pass

        print("Faculty registration error:", e)

        return jsonify({
            "success": False,
            "message": "Faculty registration failed",
            "error": str(e)
        }), 500

    finally:
        if cursor:
            try:
                cursor.close()
            except:
                pass

        if connection:
            try:
                connection.close()
            except:
                pass