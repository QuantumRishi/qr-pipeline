#!/bin/bash
# Verify all actions in workflows are SHA-pinned
# qr-pipeline - QuantumRishi

set -e

echo "🔍 Checking action SHA pinning..."

# Find all workflow files
WORKFLOW_FILES=$(find . -name '*.yml' -o -name '*.yaml' | grep -E '(workflows|.github)' || true)

if [ -z "$WORKFLOW_FILES" ]; then
  echo "⚠️  No workflow files found"
  exit 0
fi

ERRORS=0

for file in $WORKFLOW_FILES; do
  echo "Checking $file..."
  
  # Find uses: statements that don't have SHA pinning
  # SHA format: 40 hex characters
  UNPINNED=$(grep -n 'uses:' "$file" | grep -v '@[0-9a-f]\{40\}' | grep -v '#' || true)
  
  if [ -n "$UNPINNED" ]; then
    echo "❌ Found unpinned actions in $file:"
    echo "$UNPINNED"
    ERRORS=$((ERRORS + 1))
  fi
done

if [ $ERRORS -gt 0 ]; then
  echo ""
  echo "❌ Found $ERRORS files with unpinned actions"
  echo ""
  echo "To fix, pin actions by SHA:"
  echo "  uses: actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332 # v4.1.7"
  echo ""
  echo "Use https://github.com/step-security/secure-repo to auto-pin"
  exit 1
fi

echo "✅ All actions are SHA-pinned"
