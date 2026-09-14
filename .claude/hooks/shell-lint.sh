#!/bin/bash

# PostToolUse(Write|Edit): format and lint shell scripts in this repo.
#
# No-ops silently when shfmt/shellcheck are absent, so the hook is safe to commit
# before those tools are installed (`omarchy pkg add shellcheck shfmt`).
# shfmt uses -i 2 to match Omarchy's house style in /usr/share/omarchy/bin.

file=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)
[[ -n $file && -f $file ]] || exit 0

# .bats files are not valid bash (@test syntax), so they are deliberately excluded.
case "$file" in
  *.bats) exit 0 ;;
  *.sh | *.bash) ;;
  */bin/*)
    head -1 "$file" | grep -qE '^#!.*(bash|sh)\b' || exit 0
    ;;
  *) exit 0 ;;
esac

if command -v shfmt >/dev/null 2>&1; then
  shfmt -i 2 -w "$file" 2>/dev/null || true
fi

if command -v shellcheck >/dev/null 2>&1; then
  out=$(shellcheck -f gcc "$file" 2>&1) || true
  if [[ -n $out ]]; then
    jq -nc --arg ctx "shellcheck findings for $file:"$'\n'"$out" \
      '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
  fi
fi

exit 0
