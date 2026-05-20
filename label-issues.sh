#!/bin/bash
# Label GitHub Issues for Secure Bidding API
# Run with: bash label-issues.sh

set -e  # Exit on error

echo "Creating labels..."

# Create labels
gh label create "security" --color "d73a4a" --description "Security vulnerability or concern" 2>/dev/null || echo "✓ security label exists"
gh label create "priority:high" --color "b60205" --description "High priority issue requiring immediate attention" 2>/dev/null || echo "✓ priority:high label exists"
gh label create "feature" --color "0075ca" --description "New feature or enhancement" 2>/dev/null || echo "✓ feature label exists"
gh label create "refactor" --color "fbca04" --description "Code refactoring or improvement" 2>/dev/null || echo "✓ refactor label exists"

echo ""
echo "Applying labels to issues..."

# CRITICAL Security Issues
echo "Labeling #1 (Authentication)..."
gh issue edit 1 --add-label "security,priority:high"

echo "Labeling #4 (HTTPS)..."
gh issue edit 4 --add-label "security,priority:high"

# Feature Requests
echo "Labeling #8 (Atomic Reveal)..."
gh issue edit 8 --add-label "feature"

echo "Labeling #9 (Payment Integration)..."
gh issue edit 9 --add-label "feature"

# Security Issues
echo "Labeling #2 (Input Validation)..."
gh issue edit 2 --add-label "security"

echo "Labeling #3 (Encryption at Rest)..."
gh issue edit 3 --add-label "security"

echo "Labeling #5 (Rate Limiting)..."
gh issue edit 5 --add-label "security"

echo "Labeling #6 (Audit Logging)..."
gh issue edit 6 --add-label "security"

echo "Labeling #10 (Directory Traversal)..."
gh issue edit 10 --add-label "security"

# Refactor
echo "Labeling #7 (ID Generation)..."
gh issue edit 7 --add-label "refactor"

echo ""
echo "✅ All labels created and applied successfully!"
echo ""
echo "View labeled issues at:"
echo "https://github.com/EAA-IMAGINATION/secure-bidding-api/issues"
