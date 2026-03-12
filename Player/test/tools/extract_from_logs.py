import os
import glob
import re

history_dir = r"C:\Users\ken\.gemini\antigravity\brain\331a0ce5-e9d7-49b5-9ccb-f7766c71b5a9\.system_generated\logs"
out_path = r"D:\Game\Ember_of_Star_Islands\Player\test\tools\extracted_original.txt"

all_logs = glob.glob(os.path.join(history_dir, "*.txt"))
extracted_lines = set() # using a set to gather unique sub-resources and nodes just in case
full_content = ""

for log_path in all_logs:
    with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
        
        # Look for the output of `view_file` which always formats lines as "LineNum: text"
        # We want to find the exact block where lines 600 to 920 of PlayerCapsuleTest.tscn were listed.
        if "PlayerCapsuleTest.tscn" in content and "Showing lines" in content:
            # Let's extract the actual lines
            # Pattern: <number>: <content>
            matches = re.findall(r'^(\d{1,4}): (.*)$', content, re.MULTILINE)
            for match in matches:
                line_num = int(match[0])
                line_text = match[1]
                if line_text:
                    extracted_lines.add((line_num, line_text))

# Sort by line number to reconstruct
sorted_lines = sorted(list(extracted_lines), key=lambda x: x[0])

if sorted_lines:
    with open(out_path, "w", encoding="utf-8") as out_f:
        for idx, text in sorted_lines:
            out_f.write(f"{idx}: {text}\n")
    print(f"Extracted {len(sorted_lines)} lines to {out_path}")
else:
    print("No lines found in logs.")
