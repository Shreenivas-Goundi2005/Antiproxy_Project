from database import get_db_connection

db = get_db_connection()
cursor = db.cursor()

cursor.execute("DESCRIBE students")

for row in cursor.fetchall():
    print(row)

cursor.close()
db.close()