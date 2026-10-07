from flask import Blueprint, request, jsonify

from database import get_db_connection


# ============================================================
# ROSTER BLUEPRINT
# ============================================================

roster_bp = Blueprint(
    "roster",
    __name__
)


# ============================================================
# ADD ONE STUDENT TO CLASS ROSTER
# ============================================================

@roster_bp.route("/roster/add", methods=["POST"])
def add_student_to_roster():

    db = None
    cursor = None

    try:

        data = request.get_json()

        if not data:
            return jsonify({
                "success": False,
                "message": "Request body is required"
            }), 400

        subject_code = data.get("subject_code")
        semester = data.get("semester")
        division = data.get("division")
        student_id = data.get("student_id")

        # ----------------------------------------------------
        # VALIDATION
        # ----------------------------------------------------

        if not subject_code or not str(subject_code).strip():
            return jsonify({
                "success": False,
                "message": "subject_code is required"
            }), 400

        if semester is None or not str(semester).strip():
            return jsonify({
                "success": False,
                "message": "semester is required"
            }), 400

        if division is None or not str(division).strip():
            return jsonify({
                "success": False,
                "message": "division is required"
            }), 400

        if student_id is None:
            return jsonify({
                "success": False,
                "message": "student_id is required"
            }), 400

        # ----------------------------------------------------
        # CONVERT STUDENT ID
        # ----------------------------------------------------

        try:
            student_id = int(student_id)
        except (TypeError, ValueError):
            return jsonify({
                "success": False,
                "message": "student_id must be an integer"
            }), 400

        subject_code = str(
            subject_code
        ).strip().upper()

        semester = str(
            semester
        ).strip()

        division = str(
            division
        ).strip().upper()

        # ----------------------------------------------------
        # DATABASE
        # ----------------------------------------------------

        db = get_db_connection()

        cursor = db.cursor(
            dictionary=True
        )

        # ----------------------------------------------------
        # VERIFY STUDENT EXISTS
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                id,
                student_id,
                full_name,
                department,
                semester,
                division
            FROM students
            WHERE id = %s
            LIMIT 1
            """,
            (student_id,)
        )

        student = cursor.fetchone()

        if not student:

            return jsonify({
                "success": False,
                "message": "Student not found"
            }), 404

        # ----------------------------------------------------
        # VERIFY STUDENT BELONGS TO SAME SEMESTER/DIVISION
        # ----------------------------------------------------

        student_semester = student.get(
            "semester"
        )

        student_division = student.get(
            "division"
        )

        if (
            student_semester is not None
            and str(student_semester).strip() != semester
        ):

            return jsonify({
                "success": False,
                "message":
                    "Student does not belong to the selected semester"
            }), 400

        if (
            student_division is not None
            and str(student_division).strip().upper()
            != division
        ):

            return jsonify({
                "success": False,
                "message":
                    "Student does not belong to the selected division"
            }), 400

        # ----------------------------------------------------
        # CHECK DUPLICATE
        # ----------------------------------------------------

        cursor.execute(
            """
            SELECT
                id
            FROM class_roster
            WHERE subject_code = %s
              AND semester = %s
              AND division = %s
              AND student_id = %s
            LIMIT 1
            """,
            (
                subject_code,
                semester,
                division,
                student_id
            )
        )

        existing = cursor.fetchone()

        if existing:

            return jsonify({
                "success": False,
                "message":
                    "Student is already present in this class roster",
                "roster_id":
                    existing["id"]
            }), 409

        # ----------------------------------------------------
        # ADD STUDENT
        # ----------------------------------------------------

        cursor.execute(
            """
            INSERT INTO class_roster
            (
                subject_code,
                semester,
                division,
                student_id
            )
            VALUES
            (
                %s,
                %s,
                %s,
                %s
            )
            """,
            (
                subject_code,
                semester,
                division,
                student_id
            )
        )

        roster_id = cursor.lastrowid

        db.commit()

        # ----------------------------------------------------
        # SUCCESS
        # ----------------------------------------------------

        return jsonify({

            "success": True,

            "message":
                "Student added to class roster",

            "roster": {

                "id":
                    roster_id,

                "subject_code":
                    subject_code,

                "semester":
                    semester,

                "division":
                    division,

                "student_id":
                    student["id"],

                "student_usn":
                    student["student_id"],

                "student_name":
                    student["full_name"]
            }

        }), 201

    except Exception as error:

        if db:
            db.rollback()

        return jsonify({
            "success": False,
            "message":
                "Could not add student to roster",
            "error":
                str(error)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()


# ============================================================
# GET CLASS ROSTER
# ============================================================

@roster_bp.route("/roster", methods=["GET"])
def get_class_roster():

    db = None
    cursor = None

    try:

        subject_code = request.args.get(
            "subject_code"
        )

        semester = request.args.get(
            "semester"
        )

        division = request.args.get(
            "division"
        )

        # ----------------------------------------------------
        # VALIDATION
        # ----------------------------------------------------

        if not subject_code:
            return jsonify({
                "success": False,
                "message": "subject_code is required"
            }), 400

        if semester is None:
            return jsonify({
                "success": False,
                "message": "semester is required"
            }), 400

        if not division:
            return jsonify({
                "success": False,
                "message": "division is required"
            }), 400

        subject_code = str(
            subject_code
        ).strip().upper()

        semester = str(
            semester
        ).strip()

        division = str(
            division
        ).strip().upper()

        # ----------------------------------------------------
        # DATABASE
        # ----------------------------------------------------

        db = get_db_connection()

        cursor = db.cursor(
            dictionary=True
        )

        cursor.execute(
            """
            SELECT
                cr.id AS roster_id,
                cr.subject_code,
                cr.semester,
                cr.division,
                s.id AS student_id,
                s.student_id AS student_usn,
                s.full_name,
                s.department
            FROM class_roster cr
            INNER JOIN students s
                ON s.id = cr.student_id
            WHERE cr.subject_code = %s
              AND cr.semester = %s
              AND cr.division = %s
            ORDER BY s.full_name
            """,
            (
                subject_code,
                semester,
                division
            )
        )

        rows = cursor.fetchall()

        roster = []

        for row in rows:

            roster.append({

                "roster_id":
                    row["roster_id"],

                "subject_code":
                    row["subject_code"],

                "semester":
                    row["semester"],

                "division":
                    row["division"],

                "student_id":
                    row["student_id"],

                "student_usn":
                    row["student_usn"],

                "full_name":
                    row["full_name"],

                "department":
                    row["department"]
            })

        return jsonify({

            "success": True,

            "count":
                len(roster),

            "roster":
                roster

        }), 200

    except Exception as error:

        return jsonify({
            "success": False,
            "message":
                "Could not load class roster",
            "error":
                str(error)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()


# ============================================================
# REMOVE STUDENT FROM CLASS ROSTER
# ============================================================

@roster_bp.route(
    "/roster/remove/<int:roster_id>",
    methods=["DELETE"]
)
def remove_student_from_roster(
    roster_id
):

    db = None
    cursor = None

    try:

        db = get_db_connection()

        cursor = db.cursor(
            dictionary=True
        )

        cursor.execute(
            """
            SELECT
                id
            FROM class_roster
            WHERE id = %s
            LIMIT 1
            """,
            (roster_id,)
        )

        roster = cursor.fetchone()

        if not roster:

            return jsonify({
                "success": False,
                "message": "Roster entry not found"
            }), 404

        cursor.execute(
            """
            DELETE FROM class_roster
            WHERE id = %s
            """,
            (roster_id,)
        )

        db.commit()

        return jsonify({

            "success": True,

            "message":
                "Student removed from class roster"

        }), 200

    except Exception as error:

        if db:
            db.rollback()

        return jsonify({
            "success": False,
            "message":
                "Could not remove student from roster",
            "error":
                str(error)
        }), 500

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()