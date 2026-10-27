from pathlib import Path
from antispoof import verify_live_face

sample_dir = Path("Silent-Face-Anti-Spoofing/images/sample")

files = [
    "image_F1.jpg",
    "image_F2.jpg",
    "image_T1.jpg",
    "real_face_test.jpg",
    "screen_replay_detections.jpg",
    "screen_replay_test.jpg",
]

for filename in files:
    image_path = sample_dir / filename

    try:
        accepted, message, probability = verify_live_face(
            image_path.read_bytes()
        )

        status = "ACCEPTED" if accepted else "REJECTED"

        print(
            f"{filename}: {status} | "
            f"real_probability={probability:.6f} | {message}"
        )

    except Exception as error:
        print(f"{filename}: TEST ERROR | {error}")
