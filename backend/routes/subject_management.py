
from flask import Blueprint, request, jsonify
from database import get_db_connection
from routes.admin import admin_required

subject_management_bp = Blueprint(
    "subject_management",
    __name__,
    url_prefix="/api/management"
)


def valid_positive_int(value):
    try:
        number = int(value)
        return number if number > 0 else None
    except (TypeError, ValueError):
        return None


def get_department(cursor, department_id):
    cursor.execute(
        """
        SELECT id, department_code, department_name
        FROM departments
        WHERE id = %s
        """,
        (department_id,)
    )
    return cursor.fetchone()


def get_subject(cursor, subject_id):
    cursor.execute(
        """
        SELECT
            s.id,
            s.subject_code,
            s.subject_name,
            s.department_id,
            d.department_code,
            d.department_name,
            s.semester,
            s.created_at
        FROM subjects s
        JOIN departments d ON d.id = s.department_id
        WHERE s.id = %s
        """,
        (subject_id,)
    )
    return cursor.fetchone()


def subject_exists(cursor, subject_id):
    cursor.execute(
        "SELECT id FROM subjects WHERE id = %s",
        (subject_id,)
    )
    return cursor.fetchone() is not None


@subject_management_bp.route("/departments", methods=["GET"])
@admin_required
def list_departments():
    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        cursor.execute(
            """
            SELECT id, department_code, department_name
            FROM departments
            ORDER BY department_name
            """
        )

        departments = cursor.fetchall()

        return jsonify({
            "success": True,
            "count": len(departments),
            "departments": departments
        }), 200

    except Exception as exc:
        print("List departments error:", exc)
        return jsonify({
            "success": False,
            "message": "Failed to load departments"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()


@subject_management_bp.route("/subjects", methods=["GET"])
@admin_required
def list_subjects():
    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        query = """
            SELECT
                s.id,
                s.subject_code,
                s.subject_name,
                s.department_id,
                d.department_code,
                d.department_name,
                s.semester,
                s.created_at
            FROM subjects s
            JOIN departments d ON d.id = s.department_id
            WHERE 1 = 1
        """
        params = []

        department_id = request.args.get("department_id")
        semester = request.args.get("semester")
        search = request.args.get("search", "").strip()

        if department_id:
            department_id = valid_positive_int(department_id)

            if not department_id:
                return jsonify({
                    "success": False,
                    "message": "Invalid department_id"
                }), 400

            query += " AND s.department_id = %s"
            params.append(department_id)

        if semester:
            semester = valid_positive_int(semester)

            if not semester or semester > 12:
                return jsonify({
                    "success": False,
                    "message": "Semester must be between 1 and 12"
                }), 400

            query += " AND s.semester = %s"
            params.append(semester)

        if search:
            query += """
                AND (
                    s.subject_code LIKE %s
                    OR s.subject_name LIKE %s
                    OR d.department_name LIKE %s
                )
            """
            term = f"%{search}%"
            params.extend([term, term, term])

        query += """
            ORDER BY
                d.department_name,
                s.semester,
                s.subject_name
        """

        cursor.execute(query, tuple(params))
        subjects = cursor.fetchall()

        return jsonify({
            "success": True,
            "count": len(subjects),
            "subjects": subjects
        }), 200

    except Exception as exc:
        print("List subjects error:", exc)
        return jsonify({
            "success": False,
            "message": "Failed to load subjects"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()


@subject_management_bp.route("/subjects", methods=["POST"])
@admin_required
def create_subject():
    data = request.get_json(silent=True) or {}

    subject_code = str(
        data.get("subject_code", "")
    ).strip().upper()

    subject_name = str(
        data.get("subject_name", "")
    ).strip()

    department_id = valid_positive_int(
        data.get("department_id")
    )

    semester = valid_positive_int(
        data.get("semester")
    )

    if not subject_code or not subject_name:
        return jsonify({
            "success": False,
            "message": "Subject code and name are required"
        }), 400

    if len(subject_code) > 50 or len(subject_name) > 150:
        return jsonify({
            "success": False,
            "message": "Subject code or name exceeds the allowed length"
        }), 400

    if not department_id:
        return jsonify({
            "success": False,
            "message": "A valid department_id is required"
        }), 400

    if not semester or semester > 12:
        return jsonify({
            "success": False,
            "message": "Semester must be between 1 and 12"
        }), 400

    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        if not get_department(cursor, department_id):
            return jsonify({
                "success": False,
                "message": "Department not found"
            }), 404

        cursor.execute(
            """
            INSERT INTO subjects
                (subject_code, subject_name, department_id, semester)
            VALUES (%s, %s, %s, %s)
            """,
            (
                subject_code,
                subject_name,
                department_id,
                semester
            )
        )

        subject_id = cursor.lastrowid
        db.commit()

        return jsonify({
            "success": True,
            "message": "Subject created successfully",
            "subject": get_subject(cursor, subject_id)
        }), 201

    except Exception as exc:
        if db:
            db.rollback()

        if getattr(exc, "errno", None) == 1062:
            return jsonify({
                "success": False,
                "message": "A matching subject already exists"
            }), 409

        print("Create subject error:", exc)

        return jsonify({
            "success": False,
            "message": "Failed to create subject"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()


@subject_management_bp.route(
    "/subjects/<int:subject_id>",
    methods=["GET"]
)
@admin_required
def get_subject_details(subject_id):
    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        subject = get_subject(cursor, subject_id)

        if not subject:
            return jsonify({
                "success": False,
                "message": "Subject not found"
            }), 404

        return jsonify({
            "success": True,
            "subject": subject
        }), 200

    except Exception as exc:
        print("Get subject error:", exc)

        return jsonify({
            "success": False,
            "message": "Failed to load subject"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()


@subject_management_bp.route(
    "/subjects/<int:subject_id>",
    methods=["PUT", "PATCH"]
)
@admin_required
def update_subject(subject_id):
    data = request.get_json(silent=True) or {}

    if not data:
        return jsonify({
            "success": False,
            "message": "Provide at least one field to update"
        }), 400

    allowed_fields = {
        "subject_code",
        "subject_name",
        "department_id",
        "semester"
    }

    unknown_fields = set(data.keys()) - allowed_fields

    if unknown_fields:
        return jsonify({
            "success": False,
            "message": "Unsupported fields provided",
            "fields": sorted(unknown_fields)
        }), 400

    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        current = get_subject(cursor, subject_id)

        if not current:
            return jsonify({
                "success": False,
                "message": "Subject not found"
            }), 404

        subject_code = str(
            data.get("subject_code", current["subject_code"])
        ).strip().upper()

        subject_name = str(
            data.get("subject_name", current["subject_name"])
        ).strip()

        department_id = valid_positive_int(
            data.get("department_id", current["department_id"])
        )

        semester = valid_positive_int(
            data.get("semester", current["semester"])
        )

        if not subject_code or len(subject_code) > 50:
            return jsonify({
                "success": False,
                "message": "Subject code is required and must be at most 50 characters"
            }), 400

        if not subject_name or len(subject_name) > 150:
            return jsonify({
                "success": False,
                "message": "Subject name is required and must be at most 150 characters"
            }), 400

        if not department_id:
            return jsonify({
                "success": False,
                "message": "A valid department_id is required"
            }), 400

        if not semester or semester > 12:
            return jsonify({
                "success": False,
                "message": "Semester must be between 1 and 12"
            }), 400

        if not get_department(cursor, department_id):
            return jsonify({
                "success": False,
                "message": "Department not found"
            }), 404

        cursor.execute(
            """
            UPDATE subjects
            SET subject_code = %s,
                subject_name = %s,
                department_id = %s,
                semester = %s
            WHERE id = %s
            """,
            (
                subject_code,
                subject_name,
                department_id,
                semester,
                subject_id
            )
        )

        db.commit()

        return jsonify({
            "success": True,
            "message": "Subject updated successfully",
            "subject": get_subject(cursor, subject_id)
        }), 200

    except Exception as exc:
        if db:
            db.rollback()

        if getattr(exc, "errno", None) == 1062:
            return jsonify({
                "success": False,
                "message": "A matching subject already exists"
            }), 409

        print("Update subject error:", exc)

        return jsonify({
            "success": False,
            "message": "Failed to update subject"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()


@subject_management_bp.route(
    "/subjects/<int:subject_id>",
    methods=["DELETE"]
)
@admin_required
def delete_subject(subject_id):
    db = None
    cursor = None

    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)

        if not subject_exists(cursor, subject_id):
            return jsonify({
                "success": False,
                "message": "Subject not found"
            }), 404

        cursor.execute(
            """
            SELECT COUNT(*) AS total
            FROM student_subject_registrations
            WHERE subject_id = %s
            """,
            (subject_id,)
        )
        registration_count = cursor.fetchone()["total"]

        cursor.execute(
            """
            SELECT COUNT(*) AS total
            FROM faculty_subject_assignments
            WHERE subject_id = %s
            """,
            (subject_id,)
        )
        assignment_count = cursor.fetchone()["total"]

        if registration_count or assignment_count:
            return jsonify({
                "success": False,
                "message": (
                    "This subject has student registrations or faculty "
                    "assignments. Remove those dependencies before deleting it."
                ),
                "student_registrations": registration_count,
                "faculty_assignments": assignment_count
            }), 409

        cursor.execute(
            "DELETE FROM subjects WHERE id = %s",
            (subject_id,)
        )
        db.commit()

        return jsonify({
            "success": True,
            "message": "Subject deleted successfully"
        }), 200

    except Exception as exc:
        if db:
            db.rollback()

        if getattr(exc, "errno", None) == 1451:
            return jsonify({
                "success": False,
                "message": (
                    "This subject is referenced by other records and "
                    "cannot be deleted safely."
                )
            }), 409

        print("Delete subject error:", exc)

        return jsonify({
            "success": False,
            "message": "Failed to delete subject"
        }), 500

    finally:
        if cursor:
            cursor.close()
        if db:
            db.close()
