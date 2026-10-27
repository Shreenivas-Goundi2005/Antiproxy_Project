from antispoof import verify_live_face

tests = [
    ("empty input", b""),
    ("invalid image bytes", b"this is not a valid image"),
]

for name, image_bytes in tests:
    try:
        accepted, message, probability = verify_live_face(image_bytes)
        print(
            f"{name}: "
            f"{'ACCEPTED' if accepted else 'REJECTED'} | "
            f"probability={probability} | {message}"
        )
    except Exception as error:
        print(f"{name}: UNHANDLED ERROR | {type(error).__name__}: {error}")
