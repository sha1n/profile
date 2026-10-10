#!/bin/bash

# Enforce strict error handling
set -euo pipefail

# Contract: The script requires exactly two arguments: a target directory path and an integer max-depth.
if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 <path> <max-depth>"
    echo "Example: $0 /Users/shai 2"
    exit 1
fi

TARGET_PATH="$1"
MAX_DEPTH="$2"

# Validate input
if [[ ! -d "$TARGET_PATH" ]]; then
    echo "Error: Target path '$TARGET_PATH' does not exist or is not a directory."
    exit 1
fi

if ! [[ "$MAX_DEPTH" =~ ^[0-9]+$ ]]; then
    echo "Error: max-depth must be a non-negative integer."
    exit 1
fi

echo "Analyzing disk usage for '$TARGET_PATH' up to depth $MAX_DEPTH..."

# Calculate disk usage, suppress permission denied errors, sort by human-readable sizes descending.
du -h -d "$MAX_DEPTH" "$TARGET_PATH" 2>/dev/null | sort -hr | head -n 50
