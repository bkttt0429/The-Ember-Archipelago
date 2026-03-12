import os

history_dir = os.path.expandvars(r"%APPDATA%\Code\User\History")
hits = []
if os.path.exists(history_dir):
    for root, dirs, files in os.path.walk(history_dir):
        for f in files:
            path = os.path.join(root, f)
            try:
                with open(path, "r", encoding="utf-8") as file:
                    content = file.read()
                    if '[node name="CapsuleTest" type="Node3D"' in content and '[node name="SimpleFootIK" type="Node3D"' in content:
                        lines = len(content.splitlines())
                        hits.append((path, lines, os.path.getmtime(path)))
            except Exception:
                pass

hits.sort(key=lambda x: x[2], reverse=True)
for hit in hits[:10]:
    print(f"File: {hit[0]}, Lines: {hit[1]}, Time: {hit[2]}")
if not hits:
    print("No matches found in VS Code history.")
