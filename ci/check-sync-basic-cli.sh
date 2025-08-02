#!/bin/bash

# Exit on any error
set -e

# Repository URL
REPO_URL="https://github.com/roc-lang/basic-cli"
CLONE_DIR="basic-cli"

# List of files to compare
FILES=("Cmd.roc" "Dir.roc" "Env.roc" "EnvDecoding.roc" "File.roc" "Http.roc" "InternalCmd.roc" "InternalDateTime.roc" "InternalHttp.roc" "InternalIOErr.roc" "InternalPath.roc" "InternalSqlite.roc" "Path.roc" "Sleep.roc" "Sqlite.roc" "Stderr.roc" "Stdout.roc" "Tcp.roc" "Url.roc" "Utc.roc")

# Track differing files
DIFFERING_FILES=()

# Function to normalize file endings (remove trailing newlines)
normalize_file() {
    local file="$1"
    local temp_file=$(mktemp)
    # Remove trailing newlines - much faster approach
    printf '%s' "$(cat "$file")" > "$temp_file"
    echo "$temp_file"
}

# Remove existing clone directory if it exists
if [[ -d "$CLONE_DIR" ]]; then
    echo "Removing existing $CLONE_DIR directory..."
    rm -rf "$CLONE_DIR"
fi

# Clone the repository with depth 1
echo "Cloning repository..."
git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
echo "Done cloning."

echo "Comparing files..."

# Compare each file
for file in "${FILES[@]}"; do
    LOCAL_FILE="./platform/$file"
    REMOTE_FILE="./$CLONE_DIR/platform/$file"
    
    # Check if both files exist
    if [[ ! -f "$LOCAL_FILE" ]]; then
        echo "Warning: Local file $LOCAL_FILE does not exist"
        DIFFERING_FILES+=("$file")
        continue
    fi
    
    if [[ ! -f "$REMOTE_FILE" ]]; then
        echo "Warning: Remote file $REMOTE_FILE does not exist"
        DIFFERING_FILES+=("$file")
        continue
    fi
    
    # Create normalized versions of both files
    LOCAL_NORMALIZED=$(normalize_file "$LOCAL_FILE")
    REMOTE_NORMALIZED=$(normalize_file "$REMOTE_FILE")
    
    # Perform diff on normalized files and check if files differ
    if ! diff -q "$LOCAL_NORMALIZED" "$REMOTE_NORMALIZED" > /dev/null; then
        echo "=== Start of diff for $file  ==="
        diff "$LOCAL_NORMALIZED" "$REMOTE_NORMALIZED" || true
        echo "=== End of diff for $file ==="
        echo
        DIFFERING_FILES+=("$file")
    else
        echo "Files match: $file"
    fi
    
    # Clean up temporary files
    rm -f "$LOCAL_NORMALIZED" "$REMOTE_NORMALIZED"
done

# Clean up cloned directory
rm -rf "$CLONE_DIR"

# Output results
if [[ ${#DIFFERING_FILES[@]} -gt 0 ]]; then
    echo
    echo "Some files differ with what's in basic-cli/platform, they should probably be identical:"
    printf '%s\n' "${DIFFERING_FILES[@]}"
    exit 1
else
    echo
    echo "All files match!"
    exit 0
fi