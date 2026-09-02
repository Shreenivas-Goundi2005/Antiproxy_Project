import cv2
import json
import numpy as np
from insightface.app import FaceAnalysis

from database import get_db_connection


# ============================================================
# LOAD INSIGHTFACE MODEL
# ============================================================

face_app = FaceAnalysis(
    name="buffalo_l",
    providers=["CPUExecutionProvider"]
)

face_app.prepare(
    ctx_id=0,
    det_size=(640, 640)
)


# ============================================================
# REGISTER FACE
# ============================================================

def register_face(student_id):

    # --------------------------------------------------------
    # DATABASE CONNECTION
    # --------------------------------------------------------

    db = get_db_connection()
    cursor = db.cursor(dictionary=True)

    # --------------------------------------------------------
    # FIND STUDENT
    # --------------------------------------------------------

    cursor.execute(
        """
        SELECT id, student_id, full_name
        FROM students
        WHERE student_id = %s
        """,
        (student_id,)
    )

    student = cursor.fetchone()

    if not student:

        print()
        print("Student not found.")

        cursor.close()
        db.close()

        return

    print()
    print("Student found!")
    print("Student ID:", student["student_id"])
    print("Name:", student["full_name"])

    print()
    print("Starting camera...")
    print("Look directly at the camera.")
    print("Only one person should be visible.")
    print("Your face will be captured automatically.")
    print("Press Q to cancel.")

    # --------------------------------------------------------
    # OPEN CAMERA
    # --------------------------------------------------------

    camera = cv2.VideoCapture(0)

    if not camera.isOpened():

        print("Could not open camera.")

        cursor.close()
        db.close()

        return

    embedding = None

    # --------------------------------------------------------
    # CAMERA LOOP
    # --------------------------------------------------------

    while True:

        success, frame = camera.read()

        if not success:

            print("Could not read camera.")
            break

        # ----------------------------------------------------
        # INSIGHTFACE FACE DETECTION
        # ----------------------------------------------------

        faces = face_app.get(frame)

        # ----------------------------------------------------
        # EXACTLY ONE FACE
        # ----------------------------------------------------

        if len(faces) == 1:

            face = faces[0]

            # Face embedding
            embedding = face.embedding

            # Normalize embedding
            embedding = embedding / np.linalg.norm(embedding)

            # Draw bounding box
            bbox = face.bbox.astype(int)

            x1, y1, x2, y2 = bbox

            cv2.rectangle(
                frame,
                (x1, y1),
                (x2, y2),
                (0, 255, 0),
                2
            )

            cv2.putText(
                frame,
                "FACE DETECTED",
                (20, 40),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 255, 0),
                2
            )

            cv2.imshow(
                "AntiProxy - Face Registration",
                frame
            )

            # Give the camera a moment to display
            cv2.waitKey(500)

            break

        # ----------------------------------------------------
        # NO FACE
        # ----------------------------------------------------

        elif len(faces) == 0:

            cv2.putText(
                frame,
                "NO FACE DETECTED",
                (20, 40),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 0, 255),
                2
            )

        # ----------------------------------------------------
        # MULTIPLE FACES
        # ----------------------------------------------------

        else:

            cv2.putText(
                frame,
                "ONLY ONE PERSON ALLOWED",
                (20, 40),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 0, 255),
                2
            )

        # ----------------------------------------------------
        # SHOW CAMERA
        # ----------------------------------------------------

        cv2.imshow(
            "AntiProxy - Face Registration",
            frame
        )

        key = cv2.waitKey(1) & 0xFF

        # Q = Cancel
        if key == ord("q"):

            embedding = None
            break

    # --------------------------------------------------------
    # RELEASE CAMERA
    # --------------------------------------------------------

    camera.release()
    cv2.destroyAllWindows()

    # --------------------------------------------------------
    # REGISTRATION CANCELLED
    # --------------------------------------------------------

    if embedding is None:

        print()
        print("Face registration cancelled.")

        cursor.close()
        db.close()

        return

    # --------------------------------------------------------
    # CONVERT EMBEDDING TO JSON
    # --------------------------------------------------------

    embedding_json = json.dumps(
        embedding.astype(float).tolist()
    )

    # --------------------------------------------------------
    # SAVE EMBEDDING
    # --------------------------------------------------------

    cursor.execute(
        """
        UPDATE students
        SET face_encoding = %s,
            face_registered = 1
        WHERE student_id = %s
        """,
        (
            embedding_json,
            student_id
        )
    )

    db.commit()

    # --------------------------------------------------------
    # SUCCESS MESSAGE
    # --------------------------------------------------------

    print()
    print("======================================")
    print("FACE REGISTRATION SUCCESSFUL")
    print("======================================")

    print("Student ID:", student["student_id"])
    print("Name:", student["full_name"])
    print("Embedding size:", len(embedding))
    print("Face registered: YES")

    print("======================================")

    # --------------------------------------------------------
    # CLOSE DATABASE
    # --------------------------------------------------------

    cursor.close()
    db.close()


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    print("======================================")
    print("AntiProxy Face Registration")
    print("======================================")

    student_id = input(
        "Enter Student ID: "
    ).strip()

    register_face(student_id)