#!/bin/sh
# Tester script for assignment 1 and assignment 2
# Author: Siddhant Jajoo

set -e
set -u


# === Config ===
CONF_DIR="${FINDER_CONF_DIR:-/etc/finder-app/conf}"
RESULT_FILE="/tmp/assignment4-result.txt"
WRITEDIR="/tmp/aeld-data"
NUMFILES=10
WRITESTR="AELD_IS_FUN"

# === Ensure required tools on PATH ===
command -v writer >/dev/null 2>&1
command -v finder.sh >/dev/null 2>&1


# === Optional metadata (not strictly required by grader) ===
USERNAME_FILE="$CONF_DIR/username.txt"
ASSIGNMENT_FILE="$CONF_DIR/assignment.txt"
ASSIGNMENT="assignment4"
USERNAME="unknown"|
[ -f "$USERNAME_FILE" ] && USERNAME="$(cat "$USERNAME_FILE")"
[ -f "$ASSIGNMENT_FILE" ] && ASSIGNMENT="$(cat "$ASSIGNMENT_FILE")"

# === Args: [numfiles] [writestring] [subdir] ===
if [ "$#" -ge 1 ]; then NUMFILES="$1"; fi
if [ "$#" -ge 2 ]; then WRITESTR="$2"; fi
if [ "$#" -ge 3 ]; then WRITEDIR="/tmp/aeld-data/$3"; fi

MATCHSTR="The number of files are ${NUMFILES} and the number of matching lines are ${NUMFILES}"
echo "Writing ${NUMFILES} files containing string '${WRITESTR}' to ${WRITEDIR}"

# Fresh work dir
rm -rf "$WRITEDIR"
mkdir -p "$WRITEDIR"


# Create files using the **binary** writer (on PATH), NOT ./writer.sh
i=1
while [ $i -le "$NUMFILES" ]; do
  writer "$WRITEDIR/${USERNAME}${i}.txt" "$WRITESTR"
  i=$((i+1))
done

# Run finder (on PATH) and capture output
OUTPUTSTRING="$(finder.sh "$WRITEDIR" "$WRITESTR")"

# Save required A4 result file
# (append a small trailer with username/assignment for traceability)
{
  echo "$OUTPUTSTRING"
  echo "username:$USERNAME assignment:$ASSIGNMENT"
} > "$RESULT_FILE"

# Clean temp dir (optional)
rm -rf /tmp/aeld-data

# Validate expected string appears
echo "$OUTPUTSTRING" | grep -F "$MATCHSTR" >/dev/null 2>&1 && {
  echo "success"
  exit 0
}

echo "failed: expected '${MATCHSTR}' in '${OUTPUTSTRING}'"
exit 1
