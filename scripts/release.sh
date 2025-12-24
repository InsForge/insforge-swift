#!/bin/bash

# InsForge Swift SDK Release Script
# Usage: ./scripts/release.sh <version> [--dry-run]
#
# Example:
#   ./scripts/release.sh 1.0.1
#   ./scripts/release.sh 1.1.0 --dry-run

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if version argument is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Version number required${NC}"
    echo "Usage: $0 <version> [--dry-run]"
    echo "Example: $0 1.0.1"
    exit 1
fi

VERSION=$1
DRY_RUN=false

if [ "$2" == "--dry-run" ]; then
    DRY_RUN=true
    echo -e "${YELLOW}Running in DRY RUN mode - no changes will be made${NC}"
fi

# Validate version format (semver)
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Error: Invalid version format. Use semver (e.g., 1.0.1)${NC}"
    exit 1
fi

echo -e "${GREEN}Starting release process for version ${VERSION}${NC}"

# Check if on main branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${RED}Error: Must be on main branch to release${NC}"
    echo "Current branch: $CURRENT_BRANCH"
    exit 1
fi

# Check if working directory is clean
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${RED}Error: Working directory is not clean${NC}"
    echo "Please commit or stash your changes first"
    git status --short
    exit 1
fi

# Pull latest changes
echo -e "${GREEN}Pulling latest changes...${NC}"
if [ "$DRY_RUN" = false ]; then
    git pull origin main
fi

# Run tests
echo -e "${GREEN}Running tests...${NC}"
swift test

# Run SwiftLint
echo -e "${GREEN}Running SwiftLint...${NC}"
if command -v swiftlint &> /dev/null; then
    swiftlint
else
    echo -e "${YELLOW}Warning: SwiftLint not installed. Skipping...${NC}"
fi

# Update version in InsForgeClient.swift
echo -e "${GREEN}Updating version number...${NC}"
VERSION_FILE="Sources/InsForge/InsForgeClient.swift"
if [ "$DRY_RUN" = false ]; then
    sed -i '' "s/static let version = \".*\"/static let version = \"$VERSION\"/" "$VERSION_FILE"
    git add "$VERSION_FILE"
fi

# Update CHANGELOG.md
echo -e "${GREEN}Please update CHANGELOG.md with release notes${NC}"
echo "Press enter when done..."
read

if [ "$DRY_RUN" = false ]; then
    git add CHANGELOG.md
fi

# Create release commit
COMMIT_MSG="chore: release version $VERSION"
echo -e "${GREEN}Creating release commit: $COMMIT_MSG${NC}"
if [ "$DRY_RUN" = false ]; then
    git commit -m "$COMMIT_MSG"
fi

# Create git tag
TAG_MSG="Release version $VERSION"
echo -e "${GREEN}Creating git tag: $VERSION${NC}"
if [ "$DRY_RUN" = false ]; then
    git tag -a "$VERSION" -m "$TAG_MSG"
fi

# Push changes
echo -e "${GREEN}Pushing changes and tag...${NC}"
if [ "$DRY_RUN" = false ]; then
    git push origin main
    git push origin "$VERSION"
else
    echo "Would push: git push origin main"
    echo "Would push: git push origin $VERSION"
fi

# Create GitHub release
echo -e "${GREEN}Creating GitHub release...${NC}"
if command -v gh &> /dev/null; then
    if [ "$DRY_RUN" = false ]; then
        # Extract release notes from CHANGELOG
        RELEASE_NOTES=$(awk "/## \[$VERSION\]/,/## \[.*\]/{if (/## \[$VERSION\]/) next; if (/## \[.*\]/) exit; print}" CHANGELOG.md)

        gh release create "$VERSION" \
            --title "v$VERSION" \
            --notes "$RELEASE_NOTES"
    else
        echo "Would create GitHub release for version $VERSION"
    fi
else
    echo -e "${YELLOW}Warning: GitHub CLI (gh) not installed${NC}"
    echo "Please create the release manually at:"
    echo "https://github.com/YOUR_ORG/insforge-swift/releases/new?tag=$VERSION"
fi

# Optional: Publish to CocoaPods
echo -e "${GREEN}Do you want to publish to CocoaPods? (y/n)${NC}"
read -r PUBLISH_COCOAPODS

if [ "$PUBLISH_COCOAPODS" = "y" ]; then
    if command -v pod &> /dev/null; then
        echo -e "${GREEN}Publishing to CocoaPods...${NC}"
        if [ "$DRY_RUN" = false ]; then
            pod trunk push InsForge.podspec --allow-warnings
        else
            echo "Would run: pod trunk push InsForge.podspec --allow-warnings"
        fi
    else
        echo -e "${YELLOW}Warning: CocoaPods not installed${NC}"
    fi
fi

echo -e "${GREEN}✅ Release process completed successfully!${NC}"
echo ""
echo "Next steps:"
echo "1. Verify the release on GitHub"
echo "2. Update documentation site"
echo "3. Announce the release on social media"
echo "4. Monitor for any issues"
echo ""
echo "Release URL: https://github.com/YOUR_ORG/insforge-swift/releases/tag/$VERSION"
