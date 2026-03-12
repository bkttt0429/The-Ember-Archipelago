"""Validate a .tscn file: find all SubResource/ExtResource references and check they have definitions."""
import re, sys

path = r"D:\Game\Ember_of_Star_Islands\Player\test\PlayerCapsuleTest.tscn"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
    lines = content.splitlines()

# 1. Collect all defined sub_resource IDs
defined_sub = set()
for m in re.finditer(r'\[sub_resource\s+[^\]]*id="([^"]+)"', content):
    defined_sub.add(m.group(1))

# 2. Collect all defined ext_resource IDs
defined_ext = set()
for m in re.finditer(r'\[ext_resource\s+[^\]]*id="([^"]+)"', content):
    defined_ext.add(m.group(1))

# 3. Find all SubResource("...") references
ref_sub = {}
for i, line in enumerate(lines, 1):
    for m in re.finditer(r'SubResource\("([^"]+)"\)', line):
        rid = m.group(1)
        if rid not in ref_sub:
            ref_sub[rid] = []
        ref_sub[rid].append(i)

# 4. Find all ExtResource("...") references
ref_ext = {}
for i, line in enumerate(lines, 1):
    for m in re.finditer(r'ExtResource\("([^"]+)"\)', line):
        rid = m.group(1)
        if rid not in ref_ext:
            ref_ext[rid] = []
        ref_ext[rid].append(i)

print("=== DEFINED sub_resources ===")
for sid in sorted(defined_sub):
    print(f"  {sid}")

print(f"\nTotal defined sub_resources: {len(defined_sub)}")

print("\n=== REFERENCED sub_resources ===")
for sid in sorted(ref_sub.keys()):
    status = "OK" if sid in defined_sub else "MISSING!"
    print(f"  {sid} (lines {ref_sub[sid]}) -> {status}")

print("\n=== MISSING sub_resource definitions ===")
missing_sub = set(ref_sub.keys()) - defined_sub
if missing_sub:
    for sid in sorted(missing_sub):
        print(f"  ❌ {sid} referenced at lines {ref_sub[sid]}")
else:
    print("  ✅ All sub_resources are defined!")

print("\n=== DEFINED ext_resources ===")
for eid in sorted(defined_ext):
    print(f"  {eid}")

print("\n=== MISSING ext_resource definitions ===")
missing_ext = set(ref_ext.keys()) - defined_ext
if missing_ext:
    for eid in sorted(missing_ext):
        print(f"  ❌ {eid} referenced at lines {ref_ext[eid]}")
else:
    print("  ✅ All ext_resources are defined!")

# 5. Check for duplicate sub_resource IDs
dupes = {}
for m in re.finditer(r'\[sub_resource\s+[^\]]*id="([^"]+)"', content):
    sid = m.group(1)
    if sid not in dupes:
        dupes[sid] = 0
    dupes[sid] += 1
print("\n=== DUPLICATE sub_resource definitions ===")
has_dupes = False
for sid, count in dupes.items():
    if count > 1:
        print(f"  ⚠️ {sid} defined {count} times!")
        has_dupes = True
if not has_dupes:
    print("  ✅ No duplicates")

print(f"\nTotal lines: {len(lines)}")
