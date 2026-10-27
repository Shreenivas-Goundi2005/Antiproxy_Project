from pathlib import Path

import cv2

source = Path("Silent-Face-Anti-Spoofing/images/sample/real_face_test.jpg")
output = Path("test_small_face.jpg")

image = cv2.imread(str(source))
if image is None:
    raise RuntimeError(f"Could not read {source}")

# Resize the image so the face should be much smaller than 40 pixels.
small = cv2.resize(image, (120, 160), interpolation=cv2.INTER_AREA)

# Place it on a larger neutral canvas.
canvas = cv2.copyMakeBorder(
    small,
    160,
    160,
    260,
    260,
    cv2.BORDER_CONSTANT,
    value=(220, 220, 220),
)

if not cv2.imwrite(str(output), canvas):
    raise RuntimeError(f"Could not write {output}")

print(f"Created {output}: {canvas.shape[1]} x {canvas.shape[0]}")
