from database import get_db_connection


STUDENT_ID = "2BA23CS032"
FULL_NAME = "Deepak"
USERNAME = "2BA23CS032"


db = get_db_connection()
cursor = db.cursor()


try:
    # --------------------------------------------------
    # Check whether user already exists
    # --------------------------------------------------

    cursor.execute(
        "SELECT id FROM users WHERE username = %s",
        (USERNAME,)
    )

    existing_user = cursor.fetchone()

    if existing_user:
        user_id = existing_user[0]

        print("User already exists.")
        print("User ID:", user_id)

    else:
        # --------------------------------------------------
        # Create student user
        # --------------------------------------------------

        cursor.execute(
            """
            INSERT INTO users
            (username, password_hash, role)
            VALUES (%s, %s, %s)
            """,
            (
                USERNAME,
                "student123",
                "student"
            )
        )

        user_id = cursor.lastrowid

        print("User created successfully.")
        print("User ID:", user_id)

    # --------------------------------------------------
    # Check whether student already exists
    # --------------------------------------------------

    cursor.execute(
        """
        SELECT id, user_id, student_id, full_name
        FROM students
        WHERE student_id = %s
        """,
        (STUDENT_ID,)
    )

    existing_student = cursor.fetchone()

    if existing_student:

        print()
        print("Student already exists.")
        print("Student record:", existing_student)

    else:

        # --------------------------------------------------
        # Create student
        # --------------------------------------------------

        cursor.execute(
            """
            INSERT INTO students
            (
                user_id,
                student_id,
                full_name,
                face_registered
            )
            VALUES (%s, %s, %s, %s)
            """,
            (
                user_id,
                STUDENT_ID,
                FULL_NAME,
                0
            )
        )

        print()
        print("Student created successfully.")
        print("Student ID:", STUDENT_ID)
        print("Name:", FULL_NAME)
        print("User ID:", user_id)

    db.commit()

    print()
    print("======================================")
    print("DEEPAK CREATED SUCCESSFULLY")
    print("======================================")
    print("Student ID:", STUDENT_ID)
    print("Name:", FULL_NAME)
    print("Username:", USERNAME)
    print("Role: student")
    print("======================================")


except Exception as e:

    db.rollback()

    print()
    print("ERROR:")
    print(e)


finally:

    cursor.close()
    db.close()