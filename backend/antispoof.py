
"""Server-side MiniFASNetV2 anti-spoofing verification for AntiProxy."""

import os

import cv2
import numpy as np
import onnxruntime as ort


BASE_DIR = os.path.dirname(os.path.abspath(__file__))

MODEL_PATH = os.path.join(
    BASE_DIR, "models", "antispoof", "minifasnet_v2.onnx"
)

DETECTOR_PATH = os.path.join(
    BASE_DIR, "models", "face_detection",
    "face_detection_yunet_2023mar.onnx"
)

INPUT_SIZE = 80
CROP_SCALE = 2.7

# Initial conservative threshold; validate with a larger test set.
REAL_THRESHOLD = 0.80
MIN_FACE_SIZE = 40


class AntiSpoofVerifier:
    def __init__(self):
        if not os.path.isfile(MODEL_PATH):
            raise FileNotFoundError(
                f"Anti-spoof model not found: {MODEL_PATH}"
            )

        if not os.path.isfile(DETECTOR_PATH):
            raise FileNotFoundError(
                f"YuNet detector not found: {DETECTOR_PATH}"
            )

        self.session = ort.InferenceSession(
            MODEL_PATH,
            providers=["CPUExecutionProvider"],
        )
        self.input_name = self.session.get_inputs()[0].name
        self.output_name = self.session.get_outputs()[0].name

        self.detector = cv2.FaceDetectorYN.create(
            DETECTOR_PATH, "", (320, 320), 0.6, 0.3, 5000
        )

    @staticmethod
    def _softmax(logits):
        logits = np.asarray(logits, dtype=np.float32)
        logits -= np.max(logits, axis=1, keepdims=True)
        values = np.exp(logits)
        return values / np.sum(values, axis=1, keepdims=True)

    @staticmethod
    def _expanded_crop(image, bbox):
        src_h, src_w = image.shape[:2]
        x, y, width, height = bbox

        scale = min(
            (src_h - 1) / height,
            (src_w - 1) / width,
            CROP_SCALE,
        )

        crop_w = width * scale
        crop_h = height * scale
        center_x = x + width / 2
        center_y = y + height / 2

        left = center_x - crop_w / 2
        top = center_y - crop_h / 2
        right = center_x + crop_w / 2
        bottom = center_y + crop_h / 2

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

        crop = image[top:bottom + 1, left:right + 1]
        if crop.size == 0:
            raise ValueError("Empty anti-spoof face crop")

        return cv2.resize(
            crop, (INPUT_SIZE, INPUT_SIZE),
            interpolation=cv2.INTER_LINEAR,
        )

    def verify(self, image_bytes):
        """Return (accepted, message, real_probability)."""
        if not image_bytes:
            return False, "Invalid face image.", None

        image_array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)

        if image is None:
            return False, "Invalid face image.", None

        height, width = image.shape[:2]
        self.detector.setInputSize((width, height))
        _, faces = self.detector.detect(image)

        if faces is None or len(faces) == 0:
            return False, "Anti-spoof check could not detect a face.", None

        usable = []
        for face in faces:
            x, y, w, h = face[:4]
            if w >= MIN_FACE_SIZE and h >= MIN_FACE_SIZE:
                usable.append((w * h, face))

        if not usable:
            return False, "No sufficiently large face detected.", None

        # Reject ambiguous/multiple usable faces rather than guessing.
        if len(usable) > 1:
            return False, "Multiple faces detected in anti-spoof check.", None

        _, face = usable[0]
        bbox = [
            max(0, int(face[0])),
            max(0, int(face[1])),
            int(face[2]),
            int(face[3]),
        ]

        try:
            crop = self._expanded_crop(image, bbox)
            tensor = np.transpose(crop, (2, 0, 1))
            tensor = np.expand_dims(tensor.astype(np.float32), axis=0)

            logits = self.session.run(
                [self.output_name],
                {self.input_name: tensor},
            )[0]
            probabilities = self._softmax(logits)[0]

            # MiniFASNetV2 class 1 represents a real face.
            real_probability = float(probabilities[1])

            if real_probability < REAL_THRESHOLD:
                return (
                    False,
                    "Anti-spoof verification failed. Use a live camera image.",
                    real_probability,
                )

            return True, "Anti-spoof verification passed.", real_probability

        except Exception:
            # Fail closed if the verification stage errors.
            return False, "Anti-spoof verification could not be completed.", None


# Initialize lazily when the first attendance request needs the model.
_verifier = None


def verify_live_face(image_bytes):
    global _verifier

    if _verifier is None:
        _verifier = AntiSpoofVerifier()

    return _verifier.verify(image_bytes)
