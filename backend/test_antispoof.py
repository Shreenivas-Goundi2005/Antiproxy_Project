from pathlib import Path

import cv2
import numpy as np
import torch
import onnxruntime as ort

ROOT = Path(__file__).resolve().parent
REPO = ROOT / "Silent-Face-Anti-Spoofing"

import sys
sys.path.insert(0, str(REPO))

from src.model_lib.MiniFASNet import MiniFASNetV2
from src.utility import get_kernel
from src.generate_patches import CropImage

SAMPLE_DIR = REPO / "images" / "sample"
WEIGHTS = ROOT / "models" / "antispoof" / "2.7_80x80_MiniFASNetV2.pth"
ONNX_MODEL = ROOT / "models" / "antispoof" / "minifasnet_v2.onnx"
DETECTOR_DIR = REPO / "resources" / "detection_model"

detector = cv2.dnn.readNetFromCaffe(
    str(DETECTOR_DIR / "deploy.prototxt"),
    str(DETECTOR_DIR / "Widerface-RetinaFace.caffemodel"),
)

weights = torch.load(WEIGHTS, map_location="cpu", weights_only=True)
weights = {
    key.removeprefix("module."): value
    for key, value in weights.items()
}

model = MiniFASNetV2(conv6_kernel=get_kernel(80, 80))
model.load_state_dict(weights, strict=True)
model.eval()

session = ort.InferenceSession(
    str(ONNX_MODEL),
    providers=["CPUExecutionProvider"],
)
cropper = CropImage()


def softmax(scores):
    scores = scores - scores.max(axis=1, keepdims=True)
    exp_scores = np.exp(scores)
    return exp_scores / exp_scores.sum(axis=1, keepdims=True)


def prepare_image(img):
    height, width = img.shape[:2]
    ratio = width / height

    if height * width >= 192 * 192:
        small = cv2.resize(
            img,
            (
                int(192 * np.sqrt(ratio)),
                int(192 / np.sqrt(ratio)),
            ),
        )
    else:
        small = img

    detector.setInput(
        cv2.dnn.blobFromImage(small, 1, mean=(104, 117, 123)),
        "data",
    )

    detections = detector.forward("detection_out").reshape(-1, 7)
    valid = detections[detections[:, 2] >= 0.6]

    if len(valid) == 0:
        return None, None

    face = valid[np.argmax(valid[:, 2])]
    bbox = [
        int(face[3] * width),
        int(face[4] * height),
        int((face[5] - face[3]) * width + 1),
        int((face[6] - face[4]) * height + 1),
    ]

    crop = cropper.crop(img, bbox, 2.7, 80, 80, True)
    tensor = np.ascontiguousarray(
    np.transpose(crop, (2, 0, 1))[None],
    dtype=np.float32,
)

    return tensor, float(face[2])


print("\n========== ANTI-SPOOFING SAMPLE TEST ==========")

for image_path in sorted(SAMPLE_DIR.glob("*.jpg")):
    print(f"\nImage: {image_path.name}")

    img = cv2.imread(str(image_path))
    if img is None:
        print("RESULT: Could not read image")
        continue

    x, confidence = prepare_image(img)

    if x is None:
        print("RESULT: No face detected")
        continue

    with torch.no_grad():
        pytorch_scores = model(torch.from_numpy(x)).numpy()

    onnx_scores = session.run(None, {"image": x})[0]

    pytorch_prob = softmax(pytorch_scores)
    onnx_prob = softmax(onnx_scores)

    difference = float(np.max(np.abs(pytorch_prob - onnx_prob)))
    predicted_class = int(np.argmax(onnx_prob))

    print(f"Face detection confidence: {confidence:.4f}")
    print("PyTorch probabilities:", np.round(pytorch_prob[0], 6))
    print("ONNX probabilities:   ", np.round(onnx_prob[0], 6))
    print(f"Maximum probability difference: {difference:.10f}")
    print("Numerical agreement:", bool(np.allclose(
        pytorch_prob, onnx_prob, rtol=1e-3, atol=1e-4
    )))
    print(f"Predicted class: {predicted_class}")

    if predicted_class == 1:
        print("Model classification: REAL")
    else:
        print("Model classification: FAKE")

print("\nNote: These repository samples are not a substitute for testing")
print("with independently collected real faces, printed photos, and screen replays.")