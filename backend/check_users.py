from database import get_db_connection

db = get_db_connection()
cursor = db.cursor()

cursor.execute("DESCRIBE users")
print("USERS TABLE:")
for row in cursor.fetchall():
    print(row)

print("\nEXISTING USERS:")
cursor.execute("SELECT * FROM users")
for row in cursor.fetchall():
    print(row)

cursor.close()
db.close()