from functools import wraps

from flask import request, jsonify

from routes.login import verify_auth_token


def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")

        if not auth_header:
            return jsonify({
                "success": False,
                "message": "Authorization token is required"
            }), 401

        if not auth_header.startswith("Bearer "):
            return jsonify({
                "success": False,
                "message": "Invalid authorization format"
            }), 401

        token = auth_header[7:].strip()

        if not token:
            return jsonify({
                "success": False,
                "message": "Authorization token is required"
            }), 401

        user = verify_auth_token(token)

        if not user:
            return jsonify({
                "success": False,
                "message": "Invalid or expired authorization token"
            }), 401

        request.auth_user = user

        return f(*args, **kwargs)

    return decorated