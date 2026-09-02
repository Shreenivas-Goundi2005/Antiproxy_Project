from database import get_db_connection

db = get_db_connection()
cursor = db.cursor()

student_id = "2BA23CS032"
full_name = "Deepak"

cursor.execute(
    """
    INSERT INTO students
    (student_id, full_name, face_registered)
    VALUES (%s, %s, %s)
    """,
    (student_id, full_name, 0)
)

db.commit()

print("======================================")
print("STUDENT CREATED SUCCESSFULLY")
print("======================================")
print("Student ID:", student_id)
print("Name:", full_name)
print("Face registered: NO")
print("======================================")

cursor.close()
db.close()