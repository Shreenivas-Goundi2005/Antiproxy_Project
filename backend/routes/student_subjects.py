
from flask import Blueprint, request, jsonify
from database import get_db_connection
from utils.auth import token_required
from mysql.connector import IntegrityError

student_subjects_bp = Blueprint(
    "student_subjects",
    __name__,
    url_prefix="/api/student-subjects"
)


def get_student(cursor, user_id):
    cursor.execute(
        """
        SELECT id, semester, division, department
        FROM students
        WHERE user_id = %s
        LIMIT 1
        """,
        (user_id,)
    )
    return cursor.fetchone()


def subject_matches_student(cursor, subject_id, student):
    """
    Validate subject eligibility using the existing student and subject
    columns. Department matching supports a department name or ID stored
    in students.department.
    """
    cursor.execute(
        """
        SELECT s.id
        FROM subjects s
        JOIN departments d ON d.id = s.department_id
        WHERE s.id = %s
          AND s.semester = %s
          AND s.is_active = 1
          AND (
                d.department_name = %s
                OR d.department_code = %s
                OR CAST(d.id AS CHAR) = %s
              )
        LIMIT 1
        """,
        (
            subject_id,
            student["semester"],
            student["department"],
            student["department"],
            str(student["department"])
        )
    )
    return cursor.fetchone() is not None


@student_subjects_bp.route("", methods=["GET"])
@token_required
def list_subjects():
    user = request.auth_user

    if user.get("role") != "student":
        return jsonify({
            "success": False,
            "message": "Only students can view available subjects"
        }), 403

    connection = None
    cursor = None

    try:
        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        student = get_student(cursor, user["user_id"])

        if not student:
            return jsonify({
                "success": False,
                "message": "Student profile not found"
            }), 404

        if student["semester"] is None or not student["department"]:
            return jsonify({
                "success": False,
                "message": "Student department or semester is not configured"
            }), 400

        cursor.execute(
            """
            SELECT
                s.id AS subject_id,
                s.subject_code,
                s.subject_name,
                s.semester,
                d.department_name,
                CASE
                    WHEN r.id IS NULL THEN 0
                    ELSE 1
                END AS is_registered
            FROM subjects s
            JOIN departments d
                ON d.id = s.department_id
            LEFT JOIN student_subject_registrations r
                ON r.subject_id = s.id
                AND r.student_id = %s
            WHERE s.semester = %s
              AND s.is_active = 1
              AND (
                    d.department_name = %s
                    OR d.department_code = %s
                    OR CAST(d.id AS CHAR) = %s
                  )
            ORDER BY s.subject_name
            """,
            (
                student["id"],
                student["semester"],
                student["department"],
                student["department"],
                str(student["department"])
            )
        )

        subjects = cursor.fetchall()

        return jsonify({
            "success": True,
            "subjects": subjects
        }), 200

    except Exception as error:
        print("List student subjects error:", error)
        return jsonify({
            "success": False,
            "message": "Unable to retrieve subjects"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()


@student_subjects_bp.route("/register", methods=["POST"])
@token_required
def register_subject():
    user = request.auth_user

    if user.get("role") != "student":
        return jsonify({
            "success": False,
            "message": "Only students can register for subjects"
        }), 403

    data = request.get_json(silent=True) or {}
    subject_id = data.get("subject_id")

    if subject_id is None:
        return jsonify({
            "success": False,
            "message": "subject_id is required"
        }), 400

    try:
        if isinstance(subject_id, bool):
            raise ValueError
        subject_id = int(subject_id)
        if subject_id <= 0:
            raise ValueError
    except (TypeError, ValueError):
        return jsonify({
            "success": False,
            "message": "subject_id must be a positive integer"
        }), 400

    connection = None
    cursor = None

    try:
        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        student = get_student(cursor, user["user_id"])

        if not student:
            return jsonify({
                "success": False,
                "message": "Student profile not found"
            }), 404

        if student["semester"] is None or not student["department"]:
            return jsonify({
                "success": False,
                "message": "Student department or semester is not configured"
            }), 400

        if not subject_matches_student(cursor, subject_id, student):
            return jsonify({
                "success": False,
                "message": (
                    "Subject is inactive or unavailable for your "
                    "department and semester"
                )
            }), 403

        cursor.execute(
            """
            SELECT id
            FROM student_subject_registrations
            WHERE student_id = %s AND subject_id = %s
            LIMIT 1
            """,
            (student["id"], subject_id)
        )

        if cursor.fetchone():
            return jsonify({
                "success": False,
                "message": "You are already registered for this subject"
            }), 409

        cursor.execute(
            """
            INSERT INTO student_subject_registrations
                (student_id, subject_id)
            VALUES (%s, %s)
            """,
            (student["id"], subject_id)
        )

        registration_id = cursor.lastrowid
        connection.commit()

        return jsonify({
            "success": True,
            "message": "Subject registration successful",
            "registration_id": registration_id
        }), 201

    except IntegrityError as error:
        if connection:
            connection.rollback()

        # The unique composite index also protects against simultaneous
        # duplicate registration requests.
        if getattr(error, "errno", None) == 1062:
            return jsonify({
                "success": False,
                "message": "You are already registered for this subject"
            }), 409

        print("Register student subject integrity error:", error)
        return jsonify({
            "success": False,
            "message": "Unable to register for this subject"
        }), 500

    except Exception as error:
        if connection:
            connection.rollback()

        print("Register student subject error:", error)
        return jsonify({
            "success": False,
            "message": "Unable to register for this subject"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()


@student_subjects_bp.route("/<int:subject_id>", methods=["DELETE"])
@token_required
def unregister_subject(subject_id):
    user = request.auth_user

    if user.get("role") != "student":
        return jsonify({
            "success": False,
            "message": "Only students can unregister from subjects"
        }), 403

    connection = None
    cursor = None

    try:
        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        student = get_student(cursor, user["user_id"])

        if not student:
            return jsonify({
                "success": False,
                "message": "Student profile not found"
            }), 404

        cursor.execute(
            """
            SELECT id
            FROM student_subject_registrations
            WHERE student_id = %s AND subject_id = %s
            LIMIT 1
            """,
            (student["id"], subject_id)
        )

        if not cursor.fetchone():
            return jsonify({
                "success": False,
                "message": "Registration not found"
            }), 404

        # Preserve registration history and attendance relationships.
        # This endpoint does not delete existing registration records.
        return jsonify({
            "success": False,
            "message": (
                "Unregistration is disabled to preserve registration "
                "and attendance history"
            )
        }), 409

    except Exception as error:
        print("Unregister student subject error:", error)
        return jsonify({
            "success": False,
            "message": "Unable to remove subject registration"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()
