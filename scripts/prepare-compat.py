#!/usr/bin/env python3
"""Local workaround for partially upgraded Apple CLT; never edits system files."""
import json
import pathlib
import shlex
import shutil
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
dest = root / ".build" / "compat"
dest.mkdir(parents=True, exist_ok=True)
compiler = pathlib.Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip())
usr = compiler.parent.parent
manifest = usr / "lib/swift/pm/ManifestAPI"
local_manifest = dest / "ManifestAPI"
shutil.copytree(manifest, local_manifest, dirs_exist_ok=True)
# Public interfaces match the installed dylib; older private interfaces can shadow them.
for interface in local_manifest.rglob("*.private.swiftinterface"):
    interface.unlink()
(dest / "empty.modulemap").write_text("")
roots = []
include = usr / "include/swift"
if (include / "module.modulemap").exists() and (include / "bridging.modulemap").exists():
    roots.append({"type": "file", "name": str(include / "module.modulemap"),
                  "external-contents": str(dest / "empty.modulemap")})
overlay = dest / "overlay.json"
overlay.write_text(json.dumps({"version": 0, "case-sensitive": "false", "roots": roots}))
args = [str(compiler), "-I", str(local_manifest), "-vfsoverlay", str(overlay),
        "-Xcc", "-ivfsoverlay", "-Xcc", str(overlay), "-module-cache-path", str(dest / "cache2")]
wrapper = dest / "swiftc"
wrapper.write_text('#!/bin/bash\nexec ' + shlex.join(args) + ' "$@"\n')
wrapper.chmod(0o755)
print(wrapper)
