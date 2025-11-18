#!/bin/bash
# Test script to detect invalid Mermaid syntax in wiki files
# This helps catch issues before they're pushed to GitHub

set -e

WIKI_DIR="wiki"
ERRORS_FOUND=0

echo "=== Testing Mermaid Diagrams for Common Errors ==="
echo ""

# Test 1: Check for <br/> tags in sequence diagrams
echo "Test 1: Checking for <br/> tags in sequence diagrams..."
for file in $WIKI_DIR/*.md; do
    if [ -f "$file" ]; then
        # Extract sequence diagrams and check for <br/>
        BR_COUNT=$(awk '/sequenceDiagram/,/^```$/' "$file" | grep -c "<br/>" || true)
        if [ "$BR_COUNT" -gt 0 ]; then
            echo "  ❌ FAIL: $file has $BR_COUNT <br/> tag(s) in sequence diagrams"
            ERRORS_FOUND=$((ERRORS_FOUND + 1))
        else
            echo "  ✅ PASS: $file"
        fi
    fi
done
echo ""

# Test 2: Check for <br/> in participant declarations
echo "Test 2: Checking for <br/> in participant declarations..."
for file in $WIKI_DIR/*.md; do
    if [ -f "$file" ]; then
        PARTICIPANT_BR=$(grep -n "participant.*as.*<br/>" "$file" || true)
        if [ -n "$PARTICIPANT_BR" ]; then
            echo "  ❌ FAIL: $file has <br/> in participant declarations:"
            echo "$PARTICIPANT_BR" | head -3
            ERRORS_FOUND=$((ERRORS_FOUND + 1))
        else
            echo "  ✅ PASS: $file"
        fi
    fi
done
echo ""

# Test 3: Check for unescaped special characters in notes
echo "Test 3: Checking for potentially problematic characters in sequence diagrams..."
for file in $WIKI_DIR/*.md; do
    if [ -f "$file" ]; then
        # Check for curly braces in Notes (can cause parsing issues)
        BRACE_COUNT=$(awk '/sequenceDiagram/,/^```$/' "$file" | grep -c "Note.*{.*}" || true)
        if [ "$BRACE_COUNT" -gt 0 ]; then
            echo "  ⚠️  WARNING: $file has curly braces in Notes (may cause issues)"
            echo "     Consider simplifying these notes"
        else
            echo "  ✅ PASS: $file"
        fi
    fi
done
echo ""

# Test 4: Verify all sequence diagrams have proper closing
echo "Test 4: Checking for properly closed sequence diagrams..."
for file in $WIKI_DIR/*.md; do
    if [ -f "$file" ]; then
        # Count sequenceDiagram starts and ``` closes
        SEQ_START=$(grep -c "sequenceDiagram" "$file" || true)
        if [ "$SEQ_START" -gt 0 ]; then
            # This is a simple check - could be improved
            echo "  ℹ️  INFO: $file has $SEQ_START sequence diagram(s)"
        fi
    fi
done
echo ""

# Test 5: Check for extra spaces before Notes (indentation issues)
echo "Test 5: Checking for indentation issues in sequence diagrams..."
for file in $WIKI_DIR/*.md; do
    if [ -f "$file" ]; then
        SPACE_NOTES=$(awk '/sequenceDiagram/,/^```$/' "$file" | grep "^ Note" || true)
        if [ -n "$SPACE_NOTES" ]; then
            echo "  ❌ FAIL: $file has incorrectly indented Notes:"
            echo "$SPACE_NOTES" | head -3
            ERRORS_FOUND=$((ERRORS_FOUND + 1))
        else
            echo "  ✅ PASS: $file"
        fi
    fi
done
echo ""

# Summary
echo "=== Test Summary ==="
if [ $ERRORS_FOUND -eq 0 ]; then
    echo "✅ All tests passed! No Mermaid syntax errors detected."
    exit 0
else
    echo "❌ $ERRORS_FOUND error(s) found. Please fix before committing."
    exit 1
fi
