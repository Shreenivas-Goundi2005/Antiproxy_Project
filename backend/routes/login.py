from flask import Blueprint, request, jsonify
from database import get_db_connection
from utils.hashing import verify_password

login_bp = Blueprint("login", __name__)


@login_bp.route("/login", methods=["POST"])
def login():
    data = request.get_json()

    username = data.get("username")
    password = data.get("password")

    if not username or not password:
        return jsonify({
            "success": False,
            "message": "Username and password are required"
        }), 400

    connection = get_db_connection()
    cursor = connection.cursor(dictionary=True)

    cursor.execute(
        """
        SELECT id, username, password_hash, role
        FROM users
        WHERE username = %s
        """,
        (username,)
    )

    user = cursor.fetchone()

    cursor.close()
    connection.close()

    if not user:
        return jsonify({
            "success": False,
            "message": "Invalid username or password"
        }), 401

    if not verify_password(password, user["password_hash"]):
        return jsonify({
            "success": False,
            "message": "Invalid username or password"
        }), 401

    return jsonify({
        "success": True,
        "message": "Login successful",
        "user": {
            "id": user["id"],
            "username": user["username"],
            "role": user["role"]
        }
    }), 200