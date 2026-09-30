# Claude Code `PreToolUse` hook for its `Edit` and `Write` tools.
#
# Saves a snapshot of a file right before Claude changes it. Neovim uses it as
# the "before" version to show Claude's changes as hunks to accept or reject.
# See 'plugin/95_claude_review.lua'.
#
# Usage: python3 claude_review_snapshot.py <snapshot directory>
# Hook input (JSON) is read from stdin.
import json
import os
import shutil
import sys

root = sys.argv[1]
tool_input = json.load(sys.stdin).get("tool_input") or {}
path = tool_input.get("file_path")
if not path:
    sys.exit(0)

# Snapshot name is file's path with '/' replaced by '%'. Files which existed
# before Claude's edit go to 'files/', files created by Claude go to 'new/'.
path = os.path.realpath(path)
name = path.replace("/", "%")
existing = os.path.join(root, "files", name)
created = os.path.join(root, "new", name)

# Keep the oldest snapshot: it is the "before" version of all changes which are
# not yet reviewed
if os.path.exists(existing) or os.path.exists(created):
    sys.exit(0)

if os.path.isfile(path):
    os.makedirs(os.path.dirname(existing), exist_ok=True)
    shutil.copyfile(path, existing)
else:
    os.makedirs(os.path.dirname(created), exist_ok=True)
    open(created, "w").close()
