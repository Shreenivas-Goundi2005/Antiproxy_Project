import cv2
from insightface.app import FaceAnalysis

# Load InsightFace
app = FaceAnalysis(
    name="buffalo_l",
    providers=["CPUExecutionProvider"]
)

app.prepare(ctx_id=0, det_size=(640, 640))

# Change this to your image filename
image_path = "test.jpeg"

# Read image
image = cv2.imread(image_path)

if image is None:
    print("ERROR: Could not read image:", image_path)
    exit()

# Detect faces
faces = app.get(image)

print("Number of faces detected:", len(faces))

for i, face in enumerate(faces):
    print(f"\nFace {i + 1}")
    print("Bounding box:", face.bbox)
    print("Detection score:", face.det_score)
    print("Embedding size:", len(face.embedding))