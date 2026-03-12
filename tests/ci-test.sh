#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════╗"
echo "║       IPED CI Integration Test Suite                   ║"
echo "║       Validates processing_report.json generation      ║"
echo "╚════════════════════════════════════════════════════════╝"

RELEASE_DIR="${1:-target/release/iped-4.4.0-SNAPSHOT}"
if [ ! -f "$RELEASE_DIR/iped.jar" ]; then
    echo "[!] ERROR: iped.jar not found. Please build IPED first."
    exit 1
fi

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "[!] ERROR: jq is not installed. Required for JSON assertions."
    exit 1
fi

TEST_IN=$(mktemp -d)
TEST_OUT=$(mktemp -d)

echo "[INFO] Creating dummy evidence dataset in $TEST_IN..."
echo "Confidential evidence material" > "$TEST_IN/doc1.txt"
echo "invoice,amount" > "$TEST_IN/data.csv"
echo "101,150.00" >> "$TEST_IN/data.csv"

echo "[INFO] Running IPED indexer in headless mode... (this may take a moment)"

# Run in subshell to avoid directory switching issues
(
    cd "$RELEASE_DIR"
    java -jar iped.jar -d "$TEST_IN" -o "$TEST_OUT" --nogui --json-log > "$TEST_OUT/iped_cli.log"
)

REPORT_FILE="$TEST_OUT/processing_report.json"
echo "[INFO] Checking for $REPORT_FILE..."

if [ ! -f "$REPORT_FILE" ]; then
    echo "[!] ERROR: processing_report.json was not generated at $REPORT_FILE!"
    echo "-------- CLI LOG --------"
    cat "$TEST_OUT/iped_cli.log"
    exit 1
fi

echo "[INFO] Parsing JSON report with jq..."
PROCESSED=$(jq -r '.processedFiles' "$REPORT_FILE")
VERSION=$(jq -r '.version' "$REPORT_FILE")
ERRORS=$(jq -r '.errors.parsingExceptions' "$REPORT_FILE")

echo " - IPED Version:    $VERSION"
echo " - Processed Files: $PROCESSED"
echo " - Parser Errors:   $ERRORS"

if [ "$PROCESSED" -lt 2 ]; then
    echo "[!] ERROR: Expected at least 2 processed files, got $PROCESSED."
    cat "$REPORT_FILE"
    exit 1
fi

echo ""
echo "[OK] SUCCESS! The JSON reporting module is fully functional."
echo ""
echo "Output Snapshot:"
cat "$REPORT_FILE" | jq .

# Cleanup
rm -rf "$TEST_IN" "$TEST_OUT"
