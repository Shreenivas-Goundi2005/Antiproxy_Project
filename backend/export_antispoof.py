import sys
from pathlib import Path

import torch
import onnx

ROOT = Path(__file__).resolve().parent
REPO = ROOT / "Silent-Face-Anti-Spoofing"
WEIGHTS = ROOT / "models" / "antispoof" / "2.7_80x80_MiniFASNetV2.pth"
OUTPUT = ROOT / "models" / "antispoof" / "minifasnet_v2.onnx"

if not WEIGHTS.is_file():
    raise FileNotFoundError(f"Missing weights: {WEIGHTS}")

if not (REPO / "src" / "model_lib" / "MiniFASNet.py").is_file():
    raise FileNotFoundError(f"Missing model source: {REPO}")

sys.path.insert(0, str(REPO))

from src.model_lib.MiniFASNet import MiniFASNetV2
from src.utility import get_kernel

model = MiniFASNetV2(conv6_kernel=get_kernel(80, 80))

state = torch.load(WEIGHTS, map_location="cpu", weights_only=True)
if any(key.startswith("module.") for key in state):
    state = {
        key.removeprefix("module."): value
        for key, value in state.items()
    }

model.load_state_dict(state, strict=True)
model.eval()

example = torch.zeros(1, 3, 80, 80, dtype=torch.float32)

with torch.no_grad():
    expected = model(example)
    if tuple(expected.shape) != (1, 3):
        raise RuntimeError(f"Unexpected output shape: {tuple(expected.shape)}")

torch.onnx.export(
    model,
    example,
    str(OUTPUT),
    input_names=["image"],
    output_names=["class_scores"],
    opset_version=17,
    dynamo=False,
)

onnx_model = onnx.load(str(OUTPUT))
onnx.checker.check_model(onnx_model)

print("Export successful:", OUTPUT)
print("Input shape: [1, 3, 80, 80]")
print("Output shape:", list(expected.shape))
print("ONNX validation: passed")
