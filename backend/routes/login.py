from flask import Blueprint, request, jsonify, current_app
from database import get_db_connection
from utils.hashing import verify_password
from itsdangerous import URLSafeTimedSerializer


login_bp = Blueprint("login", __name__)


# ============================================================
# AUTHENTICATION TOKEN
# ============================================================

def _get_token_serializer():
    """
    Creates the serializer used to generate and verify
    authentication tokens.

    The Flask application's SECRET_KEY is used to sign
    the token so that the token cannot be modified by
    the client.
    """

    secret_key = current_app.config.get("SECRET_KEY")

    if not secret_key:
        raise RuntimeError(
            "Flask SECRET_KEY is not configured."
        )

    return URLSafeTimedSerializer(
        secret_key,
        salt="antiproxy-auth"
    )


def create_auth_token(user):
    """
    Creates a signed authentication token.

    The token contains only the information required
    to identify the authenticated user.
    """

    serializer = _get_token_serializer()

    payload = {
        "user_id": user["id"],
        "username": user["username"],
        "role": user["role"]
    }

    return serializer.dumps(payload)


def verify_auth_token(token, max_age=86400):
    """
    Verifies a signed authentication token.

    max_age:
        86400 seconds = 24 hours

    Returns:
        User payload when valid.
        None when invalid or expired.
    """

    if not token:
        return None

    try:
        serializer = _get_token_serializer()

        payload = serializer.loads(
            token,
            max_age=max_age
        )

        if not isinstance(payload, dict):
            return None

        if "user_id" not in payload:
            return None

        if "username" not in payload:
            return None

        if "role" not in payload:
            return None

        return payload

    except Exception as error:

        print(
            "Authentication token verification error:",
            error
        )

        return None


# ============================================================
# LOGIN
# ============================================================

@login_bp.route("/login", methods=["POST"])
def login():

    data = request.get_json()

    if not data:

        return jsonify({
            "success": False,
            "message": "Request data is required"
        }), 400

    username = data.get("username")
    password = data.get("password")

    if not username or not password:

        return jsonify({
            "success": False,
            "message": "Username and password are required"
        }), 400

    connection = None
    cursor = None

    try:

        connection = get_db_connection()

        cursor = connection.cursor(
            dictionary=True
        )

        # ----------------------------------------------------
        # Find user account
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                id,
                username,
                password_hash,
                role
            FROM users
            WHERE username = %s
            LIMIT 1
            """,
            (username,)
        )

        user = cursor.fetchone()

        if not user:

            return jsonify({
                "success": False,
                "message": "Invalid username or password"
            }), 401

        # ----------------------------------------------------
        # Verify password
        # ----------------------------------------------------

        if not verify_password(
            password,
            user["password_hash"]
        ):

            return jsonify({
                "success": False,
                "message": "Invalid username or password"
            }), 401

        # ----------------------------------------------------
        # Create authentication token
        # ----------------------------------------------------

        try:

            token = create_auth_token(user)

        except Exception as token_error:

            print(
                "Authentication token creation error:",
                token_error
            )

            return jsonify({
                "success": False,
                "message": "Authentication configuration error"
            }), 500

        # ----------------------------------------------------
        # Successful login
        # ----------------------------------------------------

        return jsonify({
            "success": True,
            "message": "Login successful",

            "token": token,

            "user": {
                "id": user["id"],
                "username": user["username"],
                "role": user["role"]
            }
        }), 200

    except Exception as error:

        print(
            "Login error:",
            error
        )

        return jsonify({
            "success": False,
            "message": "Login failed",
            "error": str(error)
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