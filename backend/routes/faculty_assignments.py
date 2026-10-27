from flask import Blueprint, request, jsonify
from database import get_db_connection
from routes.admin import admin_required
from utils.auth import token_required

faculty_assignments_bp = Blueprint(
    "faculty_assignments",
    __name__,
    url_prefix="/api/assignments"
)

VALID_STATUSES = {"Pending", "Accepted", "Rejected"}


def positive_int(value):
    try:
        number = int(value)
        return number if number > 0 else None
    except (TypeError, ValueError):
        return None


def assignment_details(cursor, assignment_id):
    cursor.execute(
        """
        SELECT
            a.id AS assignment_id,
            a.faculty_id,
            f.faculty_id AS faculty_code,
            f.full_name AS faculty_name,
            f.email AS faculty_email,
            a.subject_id,
            s.subject_code,
            s.subject_name,
            s.department_id,
            d.department_name,
            a.semester,
            a.division,
            a.status,
            a.assigned_at,
            a.updated_at
        FROM faculty_subject_assignments a
        JOIN faculty f ON f.id = a.faculty_id
        JOIN subjects s ON s.id = a.subject_id
        JOIN departments d ON d.id = s.department_id
        WHERE a.id = %s
        """,
        (assignment_id,)
    )
    return cursor.fetchone()


def validate_assignment(cursor, faculty_id, subject_id, semester, division):
    cursor.execute(
        """
        SELECT id, semester, department_id
        FROM subjects
        WHERE id = %s
        """,
        (subject_id,)
    )
    subject = cursor.fetchone()

    if not subject:
        return None, (jsonify({
            "success": False,
            "message": "Subject not found"
        }), 404)

    if int(subject["semester"]) != semester:
        return None, (jsonify({
            "success": False,
            "message": "Semester does not match the subject"
        }), 400)

    cursor.execute(
        """
        SELECT id
        FROM faculty
        WHERE id = %s
        """,
        (faculty_id,)
    )
    faculty = cursor.fetchone()

    if not faculty:
        return None, (jsonify({
            "success": False,
            "message": "Faculty not found"
        }), 404)

    return subject, None


@faculty_assignments_bp.route("", methods=["POST"])
@admin_required
def create_assignment():
    data = request.get_json(silent=True) or {}

    faculty_id = positive_int(data.get("faculty_id"))
    subject_id = positive_int(data.get("subject_id"))
    semester = positive_int(data.get("semester"))
    division = str(data.get("division", "")).strip().upper()

    if not faculty_id or not subject_id or not semester:
        return jsonify({
            "success": False,
            "message": "Valid faculty_id, subject_id and semester are required"
        }), 400

    if semester > 12 or not division or len(division) > 50:
        return jsonify({
            "success": False,
            "message": "Provide a valid semester and division"
        }), 400

    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        _, error_response = validate_assignment(
            cursor, faculty_id, subject_id, semester, division
        )
        if error_response:
            return error_response

        cursor.execute(
            """
            INSERT INTO faculty_subject_assignments
                (faculty_id, subject_id, semester, division, status)
            VALUES (%s, %s, %s, %s, 'Pending')
            ON DUPLICATE KEY UPDATE
                status = 'Pending',
                updated_at = CURRENT_TIMESTAMP
            """,
            (faculty_id, subject_id, semester, division)
        )

        db.commit()

        cursor.execute(
            """
            SELECT id
            FROM faculty_subject_assignments
            WHERE faculty_id = %s
              AND subject_id = %s
              AND semester = %s
              AND division = %s
            """,
            (faculty_id, subject_id, semester, division)
        )
        assignment = cursor.fetchone()

        return jsonify({
            "success": True,
            "message": "Faculty assignment saved as Pending",
            "assignment": assignment_details(cursor, assignment["id"])
        }), 201

    except Exception as exc:
        if db:
            db.rollback()
        print("Create assignment error:", exc)
        return jsonify({
            "success": False,
            "message": "Failed to create faculty assignment"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()


@faculty_assignments_bp.route("", methods=["GET"])
@admin_required
def list_all_assignments():
    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        query = """
            SELECT
                a.id AS assignment_id,
                a.faculty_id,
                f.faculty_id AS faculty_code,
                f.full_name AS faculty_name,
                f.email AS faculty_email,
                a.subject_id,
                s.subject_code,
                s.subject_name,
                s.department_id,
                d.department_name,
                a.semester,
                a.division,
                a.status,
                a.assigned_at,
                a.updated_at
            FROM faculty_subject_assignments a
            JOIN faculty f ON f.id = a.faculty_id
            JOIN subjects s ON s.id = a.subject_id
            JOIN departments d ON d.id = s.department_id
            WHERE 1 = 1
        """
        params = []

        faculty_id = request.args.get("faculty_id")
        subject_id = request.args.get("subject_id")
        semester = request.args.get("semester")
        division = request.args.get("division", "").strip().upper()
        status = request.args.get("status", "").strip().title()

        for value, column, label in [
            (faculty_id, "a.faculty_id", "faculty_id"),
            (subject_id, "a.subject_id", "subject_id"),
            (semester, "a.semester", "semester")
        ]:
            if value:
                number = positive_int(value)
                if not number:
                    return jsonify({
                        "success": False,
                        "message": f"Invalid {label}"
                    }), 400

                if label == "semester" and number > 12:
                    return jsonify({
                        "success": False,
                        "message": "Semester must be between 1 and 12"
                    }), 400

                query += f" AND {column} = %s"
                params.append(number)

        if division:
            query += " AND UPPER(a.division) = %s"
            params.append(division)

        if status:
            if status not in VALID_STATUSES:
                return jsonify({
                    "success": False,
                    "message": "Invalid assignment status"
                }), 400

            query += " AND a.status = %s"
            params.append(status)

        query += " ORDER BY a.assigned_at DESC, a.id DESC"

        cursor.execute(query, tuple(params))
        assignments = cursor.fetchall()

        return jsonify({
            "success": True,
            "count": len(assignments),
            "assignments": assignments
        }), 200

    except Exception as exc:
        print("List assignments error:", exc)
        return jsonify({
            "success": False,
            "message": "Failed to load assignments"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()


@faculty_assignments_bp.route("/faculty", methods=["GET"])
@token_required
def get_faculty_assignments():
    user = getattr(request, "auth_user", None) or {}
    user_id = user.get("user_id")

    if not user_id:
        return jsonify({
            "success": False,
            "message": "Authenticated user ID missing"
        }), 401

    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        cursor.execute(
            "SELECT id FROM faculty WHERE user_id = %s",
            (user_id,)
        )
        faculty = cursor.fetchone()

        if not faculty:
            return jsonify({
                "success": False,
                "message": "Faculty profile not found"
            }), 404

        cursor.execute(
            """
            SELECT
                a.id AS assignment_id,
                a.semester,
                a.division,
                a.status,
                a.assigned_at,
                a.updated_at,
                s.id AS subject_id,
                s.subject_code,
                s.subject_name,
                d.department_name
            FROM faculty_subject_assignments a
            JOIN subjects s ON s.id = a.subject_id
            JOIN departments d ON d.id = s.department_id
            WHERE a.faculty_id = %s
              AND s.is_active = 1
            ORDER BY a.assigned_at DESC, a.id DESC
            """,
            (faculty["id"],)
        )

        assignments = cursor.fetchall()

        return jsonify({
            "success": True,
            "assignments": assignments
        }), 200

    except Exception as exc:
        print("Get faculty assignments error:", exc)
        return jsonify({
            "success": False,
            "message": "Failed to load assignments"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()


@faculty_assignments_bp.route(
    "/<int:assignment_id>",
    methods=["PATCH"]
)
@admin_required
def edit_assignment(assignment_id):
    data = request.get_json(silent=True) or {}

    allowed_fields = {
        "faculty_id",
        "subject_id",
        "semester",
        "division"
    }

    if not data or set(data.keys()) - allowed_fields:
        return jsonify({
            "success": False,
            "message": "Provide valid assignment fields to update"
        }), 400

    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        cursor.execute(
            """
            SELECT faculty_id, subject_id, semester, division, status
            FROM faculty_subject_assignments
            WHERE id = %s
            """,
            (assignment_id,)
        )
        current = cursor.fetchone()

        if not current:
            return jsonify({
                "success": False,
                "message": "Assignment not found"
            }), 404

        faculty_id = positive_int(
            data.get("faculty_id", current["faculty_id"])
        )
        subject_id = positive_int(
            data.get("subject_id", current["subject_id"])
        )
        semester = positive_int(
            data.get("semester", current["semester"])
        )
        division = str(
            data.get("division", current["division"])
        ).strip().upper()

        if not faculty_id or not subject_id or not semester or semester > 12:
            return jsonify({
                "success": False,
                "message": "Invalid faculty, subject or semester"
            }), 400

        if not division or len(division) > 50:
            return jsonify({
                "success": False,
                "message": "A valid division is required"
            }), 400

        _, error_response = validate_assignment(
            cursor, faculty_id, subject_id, semester, division
        )
        if error_response:
            return error_response

        changed = (
            faculty_id != current["faculty_id"]
            or subject_id != current["subject_id"]
            or semester != current["semester"]
            or division != current["division"]
        )

        # A changed assignment requires the new faculty member to respond.
        new_status = "Pending" if changed else current["status"]

        cursor.execute(
            """
            UPDATE faculty_subject_assignments
            SET faculty_id = %s,
                subject_id = %s,
                semester = %s,
                division = %s,
                status = %s
            WHERE id = %s
            """,
            (
                faculty_id,
                subject_id,
                semester,
                division,
                new_status,
                assignment_id
            )
        )

        db.commit()

        return jsonify({
            "success": True,
            "message": "Assignment updated successfully",
            "assignment": assignment_details(cursor, assignment_id)
        }), 200

    except Exception as exc:
        if db:
            db.rollback()

        if getattr(exc, "errno", None) == 1062:
            return jsonify({
                "success": False,
                "message": (
                    "An assignment already exists for this faculty, "
                    "subject, semester and division"
                )
            }), 409

        print("Edit assignment error:", exc)
        return jsonify({
            "success": False,
            "message": "Failed to update assignment"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()


@faculty_assignments_bp.route(
    "/<int:assignment_id>/status",
    methods=["PATCH"]
)
@token_required
def update_assignment_status(assignment_id):
    user = getattr(request, "auth_user", None) or {}
    user_id = user.get("user_id")
    role = str(user.get("role", "")).lower()

    if role not in ("faculty", "teacher"):
        return jsonify({
            "success": False,
            "message": "Faculty access required"
        }), 403

    data = request.get_json(silent=True) or {}
    status = str(data.get("status", "")).strip().title()

    if status not in ("Accepted", "Rejected"):
        return jsonify({
            "success": False,
            "message": "Status must be Accepted or Rejected"
        }), 400

    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        cursor.execute(
            "SELECT id FROM faculty WHERE user_id = %s",
            (user_id,)
        )
        faculty = cursor.fetchone()

        if not faculty:
            return jsonify({
                "success": False,
                "message": "Faculty profile not found"
            }), 404

        cursor.execute(
            """
            SELECT id
            FROM faculty_subject_assignments
            WHERE id = %s AND faculty_id = %s
            """,
            (assignment_id, faculty["id"])
        )

        if not cursor.fetchone():
            return jsonify({
                "success": False,
                "message": "Assignment not found for this faculty member"
            }), 404

        cursor.execute(
            """
            UPDATE faculty_subject_assignments
            SET status = %s
            WHERE id = %s AND faculty_id = %s
            """,
            (status, assignment_id, faculty["id"])
        )

        db.commit()

        return jsonify({
            "success": True,
            "message": f"Assignment {status.lower()} successfully",
            "assignment_id": assignment_id,
            "status": status
        }), 200

    except Exception as exc:
        if db:
            db.rollback()

        print("Update assignment status error:", exc)
        return jsonify({
            "success": False,
            "message": "Failed to update assignment status"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()
