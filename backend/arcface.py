import cv2
from insightface.app import FaceAnalysis

app = FaceAnalysis(
    name="buffalo_l",
    providers=["CPUExecutionProvider"]
)

app.prepare(
    ctx_id=0,
    det_size=(640, 640)
)


def get_face_embedding(image_path):
    image = cv2.imread(image_path)

    if image is None:
        print("ERROR: Could not read image.")
        return None

    faces = app.get(image)

    print("Faces detected:", len(faces))

    if len(faces) == 0:
        print("ERROR: No face detected.")
        return None

    if len(faces) > 1:
        print("ERROR: Multiple faces detected.")
        return None

    embedding = faces[0].normed_embedding

    print("Face detected successfully!")
    print("Embedding length:", len(embedding))
    print("First 5 values:", embedding[:5])

    return embedding


if __name__ == "__main__":
    get_face_embedding(r"C:\Users\Shreenivas\Downloads\AntiProxy\backend\test_face.jpg")