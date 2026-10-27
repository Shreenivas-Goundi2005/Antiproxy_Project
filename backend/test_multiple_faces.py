from pathlib import Path

import cv2
import numpy as np

source = Path("Silent-Face-Anti-Spoofing/images/sample/real_face_test.jpg")
output = Path("test_multiple_faces.jpg")

image = cv2.imread(str(source))
if image is None:
    raise RuntimeError(f"Could not read {source}")

# Make two side-by-side copies, each large enough to detect a face.
face_image = cv2.resize(image, (600, 800), interpolation=cv2.INTER_AREA)
canvas = np.full((800, 1200, 3), 220, dtype=np.uint8)
canvas[:, :600] = face_image
canvas[:, 600:] = face_image

if not cv2.imwrite(str(output), canvas):
    raise RuntimeError(f"Could not write {output}")

print(f"Created {output}: {canvas.shape[1]} x {canvas.shape[0]}")

