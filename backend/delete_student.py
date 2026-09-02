from database import get_db_connection

STUDENT_ID = "2BA23CS032"

db = get_db_connection()
cursor = db.cursor()

try:
    # Find the linked user first
    cursor.execute(
        "SELECT user_id FROM students WHERE student_id = %s",
        (STUDENT_ID,)
    )

    row = cursor.fetchone()

    if not row:
        print("Student 2BA23CS032 not found.")
    else:
        user_id = row[0]

        # Delete student record
        cursor.execute(
            "DELETE FROM students WHERE student_id = %s",
            (STUDENT_ID,)
        )

        # Delete linked user account
        cursor.execute(
            "DELETE FROM users WHERE id = %s",
            (user_id,)
        )

        db.commit()

        print("======================================")
        print("STUDENT DELETED SUCCESSFULLY")
        print("======================================")
        print("Student ID:", STUDENT_ID)
        print("Linked user ID:", user_id)
        print("Face record: DELETED")
        print("======================================")

except Exception as e:
    db.rollback()
    print("ERROR:", e)

finally:
    cursor.close()
    db.close()