from getpass import getpass

from database import get_db_connection
from utils.hashing import hash_password


def reset_admin_password():
    new_password = getpass("New admin password: ")
    if not new_password:
        raise ValueError("Password cannot be empty.")

    new_hash = hash_password(new_password)

    connection = get_db_connection()
    cursor = connection.cursor()

    cursor.execute(
        """
        UPDATE users
        SET password_hash = %s
        WHERE username = 'admin'
          AND role = 'admin'
        """,
        (new_hash,)
    )

    connection.commit()

    if cursor.rowcount == 0:
        print("ERROR: Admin user was not found.")
    else:
        print("Admin password updated successfully.")
        print("Username: admin")

    cursor.close()
    connection.close()


if __name__ == "__main__":
    reset_admin_password()