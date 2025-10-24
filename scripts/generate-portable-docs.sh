#!/bin/bash
# Generate documentation package for external consumption

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$PROJECT_ROOT/docs"
OUTPUT_DIR="$PROJECT_ROOT/dist/docs-portable"
REPO_URL="https://github.com/developmentseed/eoapi-k8s"

echo "Generating portable documentation package..."

# Clean and create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Process markdown files
find "$DOCS_DIR" -name "*.md" -type f | while read -r file; do
    # Get relative path from docs directory
    rel_path=$(realpath --relative-to="$DOCS_DIR" "$file")
    output_file="$OUTPUT_DIR/$(basename "$file")"

    echo "Processing: $rel_path -> $(basename "$file")"

    # Process file to make links external-friendly
    sed \
        -e "s|](\\./|]($REPO_URL/blob/main/docs/|g" \
        -e "s|](\\.\\./*|]($REPO_URL/blob/main/|g" \
        -e "s|](docs/|]($REPO_URL/blob/main/docs/|g" \
        -e "s|](images/|]($REPO_URL/blob/main/docs/images/|g" \
        -e "s|](\\./images/|]($REPO_URL/blob/main/docs/images/|g" \
        "$file" > "$output_file"
done

# Copy assets directory
if [ -d "$DOCS_DIR/images" ]; then
    echo "Copying images directory..."
    cp -r "$DOCS_DIR/images" "$OUTPUT_DIR/"
fi

# Copy includes directory if it exists
if [ -d "$DOCS_DIR/_includes" ]; then
    echo "Copying _includes directory..."
    cp -r "$DOCS_DIR/_includes" "$OUTPUT_DIR/"
fi

# Copy docs config file if it exists
if [ -f "$DOCS_DIR/docs-config.json" ]; then
    echo "Copying docs-config.json..."
    cp "$DOCS_DIR/docs-config.json" "$OUTPUT_DIR/"
fi

# Generate index file with all documentation
cat > "$OUTPUT_DIR/README.md" << EOF
# eoAPI Kubernetes Documentation (Portable)

This is a portable version of the eoAPI Kubernetes documentation, generated from the [eoapi-k8s repository]($REPO_URL).

## Available Documentation

$(find "$OUTPUT_DIR" -name "*.md" -not -name "README.md" | sort | while read -r file; do
    filename=$(basename "$file" .md)
    title=$(grep "^# " "$file" | head -1 | sed 's/^# //' || echo "$filename")
    echo "- [$title](./$filename.md)"
done)

## Source Repository

For the latest version of this documentation, visit the [eoapi-k8s repository]($REPO_URL).

Generated on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF

# Create manifest file
cat > "$OUTPUT_DIR/manifest.json" << EOF
{
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "source_repo": "$REPO_URL",
  "version": "portable",
  "files": [
$(find "$OUTPUT_DIR" -name "*.md" | sort | while read -r file; do
    filename=$(basename "$file")
    size=$(wc -c < "$file")
    echo "    {\"name\": \"$filename\", \"size\": $size}"
done | paste -sd ',' -)
  ]
}
EOF

echo "Portable documentation generated in: $OUTPUT_DIR"
echo "Files created:"
find "$OUTPUT_DIR" -type f | sort | sed 's|^|  - |'

# Optionally create a tarball
if command -v tar >/dev/null 2>&1; then
    tarball="$PROJECT_ROOT/dist/eoapi-k8s-docs-portable.tar.gz"
    echo "Creating tarball: $tarball"
    (cd "$PROJECT_ROOT/dist" && tar -czf "eoapi-k8s-docs-portable.tar.gz" docs-portable/)
    echo "Tarball created: $tarball"
fi

echo "Done!"
