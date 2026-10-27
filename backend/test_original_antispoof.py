
import os
import sys
import cv2
import numpy as np
import onnxruntime as ort

# ---------------------------------------------------------
# AntiProxy: Standalone anti-spoofing preprocessing test
# Uses YuNet + original MiniFASNetV2 ONNX model
# ---------------------------------------------------------

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

MODEL_PATH = os.path.join(
    BASE_DIR, "models", "antispoof", "minifasnet_v2.onnx"
)

YUNET_PATH = os.path.join(
    BASE_DIR, "models", "face_detection", "face_detection_yunet_2023mar.onnx"
)
SAMPLE_DIR = os.path.join(
    BASE_DIR, "Silent-Face-Anti-Spoofing", "images", "sample"
)

# Add your own test images here if they exist.

TEST_IMAGES = [
    os.path.join(SAMPLE_DIR, "real_face_test.jpg"),
    os.path.join(SAMPLE_DIR, "screen_replay_test.jpg"),
    os.path.join(SAMPLE_DIR, "image_F1.jpg"),
    os.path.join(SAMPLE_DIR, "image_F2.jpg"),
    os.path.join(SAMPLE_DIR, "image_T1.jpg"),
]


INPUT_WIDTH = 80
INPUT_HEIGHT = 80
CROP_SCALE = 2.7

# MiniFASNetV2 output labels from the original project:
# class 1 = real; classes 0 and 2 = fake.
CLASS_NAMES = {
    0: "FAKE",
    1: "REAL",
    2: "FAKE",
}


def softmax(logits):
    """Convert model logits into probabilities safely."""
    logits = np.asarray(logits, dtype=np.float32)
    logits = logits - np.max(logits, axis=1, keepdims=True)
    exp_values = np.exp(logits)
    return exp_values / np.sum(exp_values, axis=1, keepdims=True)


def load_models():
    if not os.path.isfile(MODEL_PATH):
        raise FileNotFoundError(
            f"Anti-spoofing ONNX model not found:\n{MODEL_PATH}"
        )

    if not os.path.isfile(YUNET_PATH):
        raise FileNotFoundError(
            "YuNet model not found:\n"
            f"{YUNET_PATH}\n\n"
            "Place the YuNet face detector ONNX file at this path."
        )

    session = ort.InferenceSession(
        MODEL_PATH,
        providers=["CPUExecutionProvider"],
    )

    detector = cv2.FaceDetectorYN.create(
        YUNET_PATH,
        "",
        (320, 320),
        0.6,
        0.3,
        5000,
    )

    return session, detector


def get_face_bbox(image, detector):
    """
    Detect faces with YuNet.

    Returns the largest usable face bounding box in
    [x, y, width, height] format, plus the detection confidence.
    """
    height, width = image.shape[:2]
    detector.setInputSize((width, height))

    result = detector.detect(image)
    faces = result[1]

    if faces is None or len(faces) == 0:
        return None, None

    candidates = []

    for face in faces:
        x, y, w, h = face[:4]
        confidence = float(face[-1])

        x1 = max(0, int(x))
        y1 = max(0, int(y))
        x2 = min(width, int(x + w))
        y2 = min(height, int(y + h))

        box_width = x2 - x1
        box_height = y2 - y1

        # Ignore tiny detections, such as thumbnail faces.
        if box_width < 40 or box_height < 40:
            continue

        candidates.append(
            (
                box_width * box_height,
                [x1, y1, box_width, box_height],
                confidence,
            )
        )

    if not candidates:
        return None, None

    # The original RetinaFace implementation selects the
    # highest-confidence face. YuNet scores are not identical,
    # so this test selects the largest usable face instead.
    _, bbox, confidence = max(candidates, key=lambda item: item[0])

    return bbox, confidence


def original_style_crop(image, bbox, scale=2.7):
    """
    Reproduce the original repository's CropImage geometry:
    expand around the face center, clamp to image boundaries,
    then resize to 80 x 80.
    """
    src_h, src_w = image.shape[:2]
    x, y, box_w, box_h = bbox

    if box_w <= 0 or box_h <= 0:
        raise ValueError("Invalid face bounding box.")

    scale = min(
        (src_h - 1) / box_h,
        (src_w - 1) / box_w,
        scale,
    )

    new_width = box_w * scale
    new_height = box_h * scale

    center_x = box_w / 2 + x
    center_y = box_h / 2 + y

    left = center_x - new_width / 2
    top = center_y - new_height / 2
    right = center_x + new_width / 2
    bottom = center_y + new_height / 2

    if left < 0:
        right -= left
        left = 0

    if top < 0:
        bottom -= top
        top = 0

    if right > src_w - 1:
        left -= right - src_w + 1
        right = src_w - 1

    if bottom > src_h - 1:
        top -= bottom - src_h + 1
        bottom = src_h - 1

    left = max(0, int(left))
    top = max(0, int(top))
    right = min(src_w - 1, int(right))
    bottom = min(src_h - 1, int(bottom))

    # The original implementation uses right_bottom + 1.
    crop = image[top:bottom + 1, left:right + 1]

    if crop.size == 0:
        raise ValueError("Face crop is empty.")

    crop = cv2.resize(
        crop,
        (INPUT_WIDTH, INPUT_HEIGHT),
        interpolation=cv2.INTER_LINEAR,
    )

    return crop


def predict_antispoof(image, detector, session):
    bbox, detection_confidence = get_face_bbox(image, detector)

    if bbox is None:
        return {
            "status": "NO_FACE",
            "message": "No usable face detected.",
        }

    crop = original_style_crop(image, bbox, CROP_SCALE)

    # Original NumPy ToTensor path:
    # HWC -> CHW, float32, pixel range remains 0..255.
    tensor = np.transpose(crop, (2, 0, 1))
    tensor = tensor.astype(np.float32)
    tensor = np.expand_dims(tensor, axis=0)

    input_name = session.get_inputs()[0].name
    output_name = session.get_outputs()[0].name

    logits = session.run(
        [output_name],
        {input_name: tensor},
    )[0]

    probabilities = softmax(logits)[0]
    predicted_class = int(np.argmax(probabilities))

    return {
        "status": "OK",
        "bbox": bbox,
        "detection_confidence": detection_confidence,
        "probabilities": probabilities,
        "predicted_class": predicted_class,
        "prediction": CLASS_NAMES.get(
            predicted_class, "UNKNOWN"
        ),
        "class_confidence": float(
            probabilities[predicted_class]
        ),
        "crop": crop,
    }


def main():
    print("=" * 65)
    print("AntiProxy - Standalone Anti-Spoofing Test")
    print("=" * 65)

    print(f"OpenCV version: {cv2.__version__}")
    print(f"ONNX Runtime version: {ort.__version__}")
    print(f"Anti-spoofing model: {MODEL_PATH}")
    print(f"YuNet detector: {YUNET_PATH}")

    try:
        session, detector = load_models()
    except Exception as exc:
        print(f"\nMODEL LOADING FAILED: {exc}")
        sys.exit(1)

    print("ONNX providers:", session.get_providers())
    print("Input shape:", session.get_inputs()[0].shape)
    print("Output shape:", session.get_outputs()[0].shape)

    existing_images = [
        path for path in TEST_IMAGES
        if os.path.isfile(path)
    ]

    if not existing_images:
        print("\nNo test images found.")
        print("Expected images include:")
        print("  real_face_test.jpg")
        print("  screen_replay_test.jpg")
        print("  Silent-Face-Anti-Spoofing/images/sample/")
        sys.exit(1)

    print("\nIMPORTANT:")
    print("This is a preliminary test, not a deployment security verdict.")
    print("YuNet boxes differ from the original RetinaFace detector.")
    print("Do not integrate until genuine and spoof tests are validated.")

    for image_path in existing_images:
        print("\n" + "-" * 65)
        print("Image:", os.path.relpath(image_path, BASE_DIR))

        image = cv2.imread(image_path)

        if image is None:
            print("ERROR: Could not read image.")
            continue

        print("Image dimensions:", image.shape[1], "x", image.shape[0])

        try:
            result = predict_antispoof(image, detector, session)
        except Exception as exc:
            print("TEST ERROR:", repr(exc))
            continue

        if result["status"] != "OK":
            print("Result:", result["message"])
            continue

        probabilities = result["probabilities"]

        print("Face bounding box:", result["bbox"])
        print(
            "Face detector confidence:",
            f'{result["detection_confidence"]:.4f}',
        )
        print("Class 0 probability:", f"{probabilities[0]:.6f}")
        print("Class 1 probability:", f"{probabilities[1]:.6f}")
        print("Class 2 probability:", f"{probabilities[2]:.6f}")
        print("Predicted class:", result["predicted_class"])
        print("Predicted label:", result["prediction"])
        print(
            "Predicted-class confidence:",
            f'{result["class_confidence"]:.4f}',
        )

        crop_path = os.path.join(
            BASE_DIR,
            "antispoof_crop_" + os.path.basename(image_path),
        )

        if cv2.imwrite(crop_path, result["crop"]):
            print("Saved preprocessing crop:", crop_path)

    print("\n" + "=" * 65)
    print("Test completed.")
    print("Review all results before considering integration.")
    print("=" * 65)


if __name__ == "__main__":
    main()
