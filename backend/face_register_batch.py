import os
import json
import cv2
import numpy as np
import mysql.connector
from insightface.app import FaceAnalysis


# ==============================
# PATH
# ==============================

DATASET_PATH = r"C:\Users\Shreenivas\Downloads\AntiProxy\face_dataset"


# ==============================
# DATABASE
# ==============================

def get_db_connection():
    return mysql.connector.connect(
        host="localhost",
        user="root",
        password="Kshree@01",
        database="antiproxy"
    )


# ==============================
# LOAD INSIGHTFACE
# ==============================

print("Loading InsightFace model...")

app = FaceAnalysis(
    name="buffalo_l",
    providers=["CPUExecutionProvider"]
)

app.prepare(ctx_id=0, det_size=(640, 640))

print("InsightFace model loaded.\n")


# ==============================
# PROCESS STUDENTS
# ==============================

connection = get_db_connection()
cursor = connection.cursor(dictionary=True)

student_folders = [
    folder for folder in os.listdir(DATASET_PATH)
    if os.path.isdir(os.path.join(DATASET_PATH, folder))
]

print(f"Found {len(student_folders)} student folders.\n")

for student_id in sorted(student_folders):

    folder_path = os.path.join(DATASET_PATH, student_id)

    print("=" * 60)
    print(f"Processing: {student_id}")

    # --------------------------------
    # Find student in database
    # --------------------------------

    cursor.execute(
        """
        SELECT id, student_id, full_name, face_registered
        FROM students
        WHERE student_id = %s
        """,
        (student_id,)
    )

    student = cursor.fetchone()

    if not student:
        print("❌ Student not found in database. Skipping.")
        continue

    print(f"Student: {student['full_name']}")

    # --------------------------------
    # Don't overwrite existing face
    # --------------------------------

    if student["face_registered"] == 1:
        print("⚠️ Face already registered. Skipping.")
        continue

    # --------------------------------
    # Find image files
    # --------------------------------

    image_files = [
        file for file in os.listdir(folder_path)
        if file.lower().endswith(
            (".jpg", ".jpeg", ".png", ".webp")
        )
    ]

    if not image_files:
        print("❌ No images found. Skipping.")
        continue

    print(f"Images found: {len(image_files)}")

    embeddings = []

    # --------------------------------
    # Process each image
    # --------------------------------

    for image_file in image_files:

        image_path = os.path.join(folder_path, image_file)

        print(f"  Processing: {image_file}")

        image = cv2.imread(image_path)

        if image is None:
            print("  ❌ Could not read image.")
            continue

        faces = app.get(image)

        if len(faces) == 0:
            print("  ❌ No face detected.")
            continue

        if len(faces) > 1:
            print("  ❌ Multiple faces detected. Use an image with one person.")
            continue

        embedding = faces[0].embedding

        # Normalize embedding
        embedding = embedding / np.linalg.norm(embedding)

        embeddings.append(embedding)

        print("  ✅ Face detected.")

    # --------------------------------
    # Check successful images
    # --------------------------------

    if len(embeddings) == 0:
        print("❌ No valid face images for this student.")
        continue

    # --------------------------------
    # Average multiple embeddings
    # --------------------------------

    final_embedding = np.mean(embeddings, axis=0)

    # Normalize again
    final_embedding = final_embedding / np.linalg.norm(final_embedding)

    embedding_json = json.dumps(final_embedding.tolist())

    # --------------------------------
    # Store in database
    # --------------------------------

    cursor.execute(
        """
        UPDATE students
        SET face_encoding = %s,
            face_registered = 1
        WHERE id = %s
        """,
        (embedding_json, student["id"])
    )

    connection.commit()

    print(
        f"✅ REGISTERED: {student_id} "
        f"({student['full_name']})"
    )
    print(
        f"   Valid images used: {len(embeddings)}"
    )


cursor.close()
connection.close()

print("\n" + "=" * 60)
print("FACE BATCH REGISTRATION COMPLETE")
print("=" * 60)