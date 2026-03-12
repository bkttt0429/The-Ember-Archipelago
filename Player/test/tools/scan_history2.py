import os
from pathlib import Path

history_dir = Path(os.path.expandvars(r"%APPDATA%\Code\User\History"))
hits = []
if history_dir.exists():
    for f in history_dir.rglob("*"):
        if f.is_file():
            try:
                content = f.read_text(encoding="utf-8")
                if '[node name="CapsuleTest" type="Node3D"' in content and '[node name="SimpleFootIK" type="Node3D"' in content:
                    lines = len(content.splitlines())
                    if lines > 850:
                        hits.append((str(f), lines, f.stat().st_mtime))
            except Exception:
                pass

hits.sort(key=lambda x: x[2], reverse=True)
for hit in hits[:10]:
    print(f"File: {hit[0]}, Lines: {hit[1]}")
if not hits:
    print("No matches >850 lines found in VS Code history.")
