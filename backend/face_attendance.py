import cv2
import json
import numpy as np
from datetime import datetime

from insightface.app import FaceAnalysis

from database import get_db_connection
from geofence import (
    check_geofence,
    CAMPUS_LATITUDE,
    CAMPUS_LONGITUDE
)


# ============================================================
# ANTIPROXY ATTENDANCE
# ============================================================
#
# SECURITY FLOW:
#
# Student ID
#      ↓
# Student exists?
#      ↓
# Face registered?
#      ↓
# Camera
#      ↓
# Exactly ONE face
#      ↓
# Compare ONLY with that student's registered face
#      ↓
# Multiple valid samples
#      ↓
# Robust face decision
#      ↓
# Geofence
#      ↓
# Attendance
#
# ============================================================


# ============================================================
# SETTINGS
# ============================================================

# Keep this at 0.60 initially.
# Do NOT keep lowering this to force a match.
FACE_MATCH_THRESHOLD = 0.60

# Number of valid face samples required
REQUIRED_FACE_SAMPLES = 7

# Number of samples that must pass the frame threshold
REQUIRED_MATCHES = 5

# Average similarity required
MIN_AVERAGE_SIMILARITY = 0.60

# Median similarity is useful because one bad camera frame
# should not dominate the entire decision.
MIN_MEDIAN_SIMILARITY = 0.60

# Minimum acceptable number of good samples
MIN_GOOD_SAMPLES = 5

# Camera delay
CAMERA_DELAY_MS = 300


# ============================================================
# LOAD INSIGHTFACE
# ============================================================

print()
print("Loading InsightFace model...")

face_app = FaceAnalysis(
    name="buffalo_l",
    providers=["CPUExecutionProvider"]
)

face_app.prepare(
    ctx_id=0,
    det_size=(640, 640)
)

print("InsightFace model loaded successfully.")


# ============================================================
# DATABASE - GET STUDENT
# ============================================================

def get_student(student_id):

    db = None
    cursor = None

    try:

        db = get_db_connection()

        cursor = db.cursor(dictionary=True)

        cursor.execute(
            """
            SELECT
                id,
                student_id,
                full_name,
                face_encoding,
                face_registered
            FROM students
            WHERE student_id = %s
            LIMIT 1
            """,
            (student_id,)
        )

        return cursor.fetchone()

    except Exception as e:

        print()
        print("DATABASE ERROR")
        print(e)

        return None

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()


# ============================================================
# COSINE SIMILARITY
# ============================================================

def cosine_similarity(embedding1, embedding2):

    embedding1 = np.asarray(
        embedding1,
        dtype=np.float32
    )

    embedding2 = np.asarray(
        embedding2,
        dtype=np.float32
    )

    norm1 = np.linalg.norm(embedding1)
    norm2 = np.linalg.norm(embedding2)

    if norm1 == 0 or norm2 == 0:
        return 0.0

    return float(
        np.dot(embedding1, embedding2)
        /
        (norm1 * norm2)
    )


# ============================================================
# NORMALIZE EMBEDDING
# ============================================================

def normalize_embedding(embedding):

    embedding = np.asarray(
        embedding,
        dtype=np.float32
    )

    if embedding.shape != (512,):
        return None

    norm = np.linalg.norm(embedding)

    if norm == 0:
        return None

    return embedding / norm


# ============================================================
# LOAD REGISTERED FACE
# ============================================================

def load_registered_embedding(student):

    face_encoding = student.get("face_encoding")

    if not face_encoding:

        print()
        print("ERROR: No registered face encoding.")

        return None

    try:

        registered_embedding = json.loads(
            face_encoding
        )

    except Exception as e:

        print()
        print("ERROR: Could not read registered face.")
        print("Error:", e)

        return None

    registered_embedding = normalize_embedding(
        registered_embedding
    )

    if registered_embedding is None:

        print()
        print(
            "ERROR: Registered face embedding "
            "must contain exactly 512 valid values."
        )

        return None

    return registered_embedding


# ============================================================
# FACE VERIFICATION
# ============================================================

def verify_face(student):

    registered_embedding = load_registered_embedding(
        student
    )

    if registered_embedding is None:
        return False

    print()
    print("======================================")
    print("FACE VERIFICATION")
    print("======================================")

    print()
    print("Student ID:")
    print(student["student_id"])

    print()
    print("Student name:")
    print(student["full_name"])

    print()
    print("Look directly at the camera.")
    print("ONLY ONE PERSON must be visible.")

    print()
    print(
        f"Required samples: "
        f"{REQUIRED_FACE_SAMPLES}"
    )

    print(
        f"Required matching samples: "
        f"{REQUIRED_MATCHES}"
    )

    print(
        f"Frame threshold: "
        f"{FACE_MATCH_THRESHOLD:.2f}"
    )

    print(
        f"Average threshold: "
        f"{MIN_AVERAGE_SIMILARITY:.2f}"
    )

    print(
        f"Median threshold: "
        f"{MIN_MEDIAN_SIMILARITY:.2f}"
    )

    print()
    print("Press Q to cancel.")

    # ========================================================
    # CAMERA
    # ========================================================

    camera = cv2.VideoCapture(0)

    if not camera.isOpened():

        print()
        print("ERROR: Could not open camera.")

        return False

    similarities = []

    frames_checked = 0
    matching_frames = 0

    # ========================================================
    # CAMERA LOOP
    # ========================================================

    while frames_checked < REQUIRED_FACE_SAMPLES:

        success, frame = camera.read()

        if not success:

            print()
            print("ERROR: Could not read camera.")

            break

        # ----------------------------------------------------
        # Detect faces
        # ----------------------------------------------------

        faces = face_app.get(frame)

        # ====================================================
        # NO FACE
        # ====================================================

        if len(faces) == 0:

            cv2.putText(
                frame,
                "NO FACE DETECTED",
                (20, 40),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 0, 255),
                2
            )

        # ====================================================
        # MULTIPLE FACES
        # ====================================================

        elif len(faces) > 1:

            cv2.putText(
                frame,
                f"REJECTED - {len(faces)} FACES",
                (20, 40),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.75,
                (0, 0, 255),
                2
            )

            cv2.putText(
                frame,
                "ONLY ONE PERSON ALLOWED",
                (20, 75),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.65,
                (0, 0, 255),
                2
            )

        # ====================================================
        # EXACTLY ONE FACE
        # ====================================================

        else:

            face = faces[0]

            current_embedding = normalize_embedding(
                face.embedding
            )

            # ------------------------------------------------
            # Invalid embedding
            # ------------------------------------------------

            if current_embedding is None:

                cv2.putText(
                    frame,
                    "INVALID FACE EMBEDDING",
                    (20, 40),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.7,
                    (0, 0, 255),
                    2
                )

            else:

                # =================================================
                # IMPORTANT SECURITY RULE
                #
                # Compare ONLY against the registered embedding
                # belonging to the entered Student ID.
                #
                # There is NO global student search.
                # =================================================

                similarity = cosine_similarity(
                    registered_embedding,
                    current_embedding
                )

                similarities.append(similarity)

                frames_checked += 1

                # ------------------------------------------------
                # Individual frame result
                # ------------------------------------------------

                if similarity >= FACE_MATCH_THRESHOLD:

                    matching_frames += 1

                    status = "MATCH"

                    box_color = (
                        0,
                        255,
                        0
                    )

                else:

                    status = "NO MATCH"

                    box_color = (
                        0,
                        0,
                        255
                    )

                # =================================================
                # FACE BOX
                # =================================================

                bbox = face.bbox.astype(int)

                x1, y1, x2, y2 = bbox

                cv2.rectangle(
                    frame,
                    (x1, y1),
                    (x2, y2),
                    box_color,
                    2
                )

                # =================================================
                # DISPLAY
                # =================================================

                cv2.putText(
                    frame,
                    (
                        f"Sample: "
                        f"{frames_checked}/"
                        f"{REQUIRED_FACE_SAMPLES}"
                    ),
                    (20, 40),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.7,
                    box_color,
                    2
                )

                cv2.putText(
                    frame,
                    (
                        f"Similarity: "
                        f"{similarity:.3f}"
                    ),
                    (20, 75),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.7,
                    box_color,
                    2
                )

                cv2.putText(
                    frame,
                    status,
                    (20, 110),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.7,
                    box_color,
                    2
                )

                cv2.putText(
                    frame,
                    (
                        f"Matches: "
                        f"{matching_frames}/"
                        f"{REQUIRED_MATCHES}"
                    ),
                    (20, 145),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.65,
                    box_color,
                    2
                )

        # ====================================================
        # SHOW CAMERA
        # ====================================================

        cv2.imshow(
            "AntiProxy - Face Verification",
            frame
        )

        key = cv2.waitKey(
            CAMERA_DELAY_MS
        ) & 0xFF

        # ====================================================
        # Q = CANCEL
        # ====================================================

        if key == ord("q"):

            print()
            print("Face verification cancelled.")

            camera.release()
            cv2.destroyAllWindows()

            return False

    # ========================================================
    # RELEASE CAMERA
    # ========================================================

    camera.release()
    cv2.destroyAllWindows()

    # ========================================================
    # NOT ENOUGH SAMPLES
    # ========================================================

    if frames_checked < REQUIRED_FACE_SAMPLES:

        print()
        print(
            "ERROR: Not enough valid face samples."
        )

        print(
            "Frames checked:",
            frames_checked
        )

        return False

    # ========================================================
    # CALCULATE RESULTS
    # ========================================================

    average_similarity = float(
        np.mean(similarities)
    )

    minimum_similarity = float(
        np.min(similarities)
    )

    maximum_similarity = float(
        np.max(similarities)
    )

    median_similarity = float(
        np.median(similarities)
    )

    # ========================================================
    # RESULTS
    # ========================================================

    print()
    print("======================================")
    print("FACE VERIFICATION RESULTS")
    print("======================================")

    print(
        "Student ID:",
        student["student_id"]
    )

    print(
        "Student name:",
        student["full_name"]
    )

    print(
        "Frames checked:",
        frames_checked
    )

    print(
        "Matching frames:",
        matching_frames
    )

    print(
        "Required matches:",
        REQUIRED_MATCHES
    )

    print(
        f"Average similarity: "
        f"{average_similarity:.3f}"
    )

    print(
        f"Median similarity: "
        f"{median_similarity:.3f}"
    )

    print(
        f"Minimum similarity: "
        f"{minimum_similarity:.3f}"
    )

    print(
        f"Maximum similarity: "
        f"{maximum_similarity:.3f}"
    )

    print(
        f"Frame threshold: "
        f"{FACE_MATCH_THRESHOLD:.2f}"
    )

    print(
        f"Average threshold: "
        f"{MIN_AVERAGE_SIMILARITY:.2f}"
    )

    print(
        f"Median threshold: "
        f"{MIN_MEDIAN_SIMILARITY:.2f}"
    )

    # ========================================================
    # FINAL SECURITY DECISION
    # ========================================================

    passed = (
        matching_frames >= REQUIRED_MATCHES
        and
        average_similarity >= MIN_AVERAGE_SIMILARITY
        and
        median_similarity >= MIN_MEDIAN_SIMILARITY
    )

    if passed:

        print()
        print("FACE MATCHED")
        print("======================================")

        return True

    print()
    print("FACE NOT MATCHED")
    print("======================================")

    return False


# ============================================================
# CHECK DUPLICATE ATTENDANCE
# ============================================================

def attendance_already_marked(student_id):

    db = None
    cursor = None

    try:

        db = get_db_connection()

        cursor = db.cursor()

        today = datetime.now().date()

        cursor.execute(
            """
            SELECT id
            FROM attendance
            WHERE student_id = %s
            AND attendance_date = %s
            LIMIT 1
            """,
            (
                student_id,
                today
            )
        )

        result = cursor.fetchone()

        return result is not None

    except Exception as e:

        print()
        print(
            "DATABASE ERROR WHILE "
            "CHECKING ATTENDANCE"
        )

        print(e)

        return None

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()


# ============================================================
# MARK ATTENDANCE
# ============================================================

def mark_attendance(
    student,
    latitude,
    longitude
):

    db = None
    cursor = None

    try:

        db = get_db_connection()

        cursor = db.cursor()

        now = datetime.now()

        cursor.execute(
            """
            INSERT INTO attendance
            (
                student_id,
                attendance_date,
                attendance_time,
                status,
                latitude,
                longitude,
                face_verified
            )
            VALUES
            (
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s
            )
            """,
            (
                student["id"],
                now.date(),
                now.time(),
                "present",
                latitude,
                longitude,
                1
            )
        )

        db.commit()

        return True

    except Exception as e:

        if db:
            db.rollback()

        print()
        print("ERROR MARKING ATTENDANCE")
        print(e)

        return False

    finally:

        if cursor:
            cursor.close()

        if db:
            db.close()


# ============================================================
# MAIN
# ============================================================

def main():

    print()
    print("======================================")
    print("       ANTIPROXY ATTENDANCE")
    print("======================================")

    # ========================================================
    # STUDENT ID
    # ========================================================

    student_id = input(
        "Enter Student ID: "
    ).strip()

    if not student_id:

        print()
        print("Student ID cannot be empty.")

        return

    # ========================================================
    # STEP 1 - STUDENT
    # ========================================================

    print()
    print("--------------------------------------")
    print("STEP 1: STUDENT VERIFICATION")
    print("--------------------------------------")

    student = get_student(
        student_id
    )

    if not student:

        print()
        print("Student not found.")
        print("Attendance rejected.")

        return

    print()
    print("Student found!")

    print(
        "Student ID:",
        student["student_id"]
    )

    print(
        "Name:",
        student["full_name"]
    )

    # ========================================================
    # FACE REGISTRATION
    # ========================================================

    if (
        not student["face_registered"]
        or
        not student["face_encoding"]
    ):

        print()
        print("Face registration: NO")
        print("Attendance rejected.")

        return

    print(
        "Face registration: YES"
    )

    # ========================================================
    # DUPLICATE CHECK
    # ========================================================

    duplicate_status = (
        attendance_already_marked(
            student["id"]
        )
    )

    if duplicate_status is None:

        print()
        print(
            "Could not verify today's attendance."
        )

        print(
            "Attendance rejected for safety."
        )

        return

    if duplicate_status:

        print()
        print("--------------------------------------")
        print("ATTENDANCE ALREADY MARKED TODAY")
        print("--------------------------------------")

        print(
            "Student:",
            student["full_name"]
        )

        print(
            "Date:",
            datetime.now().date()
        )

        print()
        print(
            "We will STILL perform "
            "face verification."
        )

        print(
            "No duplicate attendance "
            "will be inserted."
        )

    else:

        print()
        print(
            "No attendance found for today."
        )

    # ========================================================
    # STEP 2 - FACE VERIFICATION
    # ========================================================

    print()
    print("--------------------------------------")
    print("STEP 2: FACE VERIFICATION")
    print("--------------------------------------")

    matched = verify_face(
        student
    )

    # ========================================================
    # FACE REJECTED
    # ========================================================

    if not matched:

        print()
        print("======================================")
        print("       ATTENDANCE REJECTED")
        print("======================================")

        print()
        print(
            "Reason: Camera person does not "
            "match the registered face."
        )

        print(
            "Student ID:",
            student["student_id"]
        )

        print(
            "Student name:",
            student["full_name"]
        )

        return

    # ========================================================
    # FACE PASSED
    # ========================================================

    print()
    print("FACE VERIFICATION PASSED.")

    # ========================================================
    # STEP 3 - LOCATION
    # ========================================================

    print()
    print("--------------------------------------")
    print("STEP 3: LOCATION VERIFICATION")
    print("--------------------------------------")

    # TEMPORARY:
    # Later Android GPS should replace this.

    latitude = CAMPUS_LATITUDE
    longitude = CAMPUS_LONGITUDE

    print(
        "Latitude:",
        latitude
    )

    print(
        "Longitude:",
        longitude
    )

    geofence = check_geofence(
        latitude,
        longitude
    )

    print()
    print(
        "Distance from campus:",
        geofence["distance"],
        "meters"
    )

    print(
        "Allowed radius:",
        geofence["allowed_radius"],
        "meters"
    )

    # ========================================================
    # GEOFENCE FAILED
    # ========================================================

    if not geofence["inside"]:

        print()
        print("GEOFENCE FAILED.")

        print(
            "You are outside the "
            "allowed attendance area."
        )

        print(
            "Attendance rejected."
        )

        return

    print()
    print("GEOFENCE PASSED.")

    # ========================================================
    # ALREADY ATTENDED
    # ========================================================

    if duplicate_status:

        print()
        print("======================================")
        print("       FACE TEST SUCCESSFUL")
        print("======================================")

        print(
            "Student ID:",
            student["student_id"]
        )

        print(
            "Name:",
            student["full_name"]
        )

        print(
            "Face verified: YES"
        )

        print(
            "Location verified: YES"
        )

        print()
        print(
            "Existing attendance was "
            "already present."
        )

        print(
            "No new attendance row inserted."
        )

        print("======================================")

        return

    # ========================================================
    # STEP 4 - INSERT
    # ========================================================

    print()
    print("--------------------------------------")
    print("STEP 4: MARK ATTENDANCE")
    print("--------------------------------------")

    success = mark_attendance(
        student,
        latitude,
        longitude
    )

    if not success:

        print()
        print(
            "Attendance could not be saved."
        )

        return

    # ========================================================
    # SUCCESS
    # ========================================================

    now = datetime.now()

    print()
    print("======================================")
    print(" ATTENDANCE MARKED SUCCESSFULLY")
    print("======================================")

    print(
        "Student ID:",
        student["student_id"]
    )

    print(
        "Name:",
        student["full_name"]
    )

    print(
        "Face verified: YES"
    )

    print(
        "Location verified: YES"
    )

    print(
        "Distance:",
        geofence["distance"],
        "meters"
    )

    print(
        "Status: PRESENT"
    )

    print(
        "Date:",
        now.date()
    )

    print(
        "Time:",
        now.strftime("%H:%M:%S")
    )

    print("======================================")


# ============================================================
# PROGRAM START
# ============================================================

if __name__ == "__main__":
    main()