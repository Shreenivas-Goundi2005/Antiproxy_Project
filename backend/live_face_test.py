import cv2
from insightface.app import FaceAnalysis

print("Loading InsightFace...")

app = FaceAnalysis(
    name="buffalo_l",
    providers=["CPUExecutionProvider"]
)

app.prepare(
    ctx_id=0,
    det_size=(640, 640)
)

print("InsightFace loaded.")
print("Starting camera...")
print("Press Q to quit.")

camera = cv2.VideoCapture(0)

if not camera.isOpened():
    print("ERROR: Camera could not be opened.")
    exit()

while True:

    success, frame = camera.read()

    if not success:
        print("ERROR: Could not read frame.")
        break

    faces = app.get(frame)

    # Draw information
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

    elif len(faces) == 1:

        face = faces[0]

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

        cv2.putText(
            frame,
            f"Score: {face.det_score:.2f}",
            (20, 75),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.7,
            (0, 255, 0),
            2
        )

        print(
            f"Face detected | "
            f"Score: {face.det_score:.3f} | "
            f"Embedding: {len(face.embedding)}"
        )

    else:

        cv2.putText(
            frame,
            f"MULTIPLE FACES: {len(faces)}",
            (20, 40),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (0, 0, 255),
            2
        )

    cv2.imshow(
        "AntiProxy - Live Face Test",
        frame
    )

    key = cv2.waitKey(1) & 0xFF

    if key == ord("q"):
        break

camera.release()
cv2.destroyAllWindows()

print("Camera stopped.")