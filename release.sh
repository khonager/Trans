#!/bin/bash

# 1. Read the version from pubspec.yaml
# We use grep and awk to extract the version string (e.g., "1.0.0+1")
VERSION=$(grep 'version:' pubspec.yaml | head -n 1 | awk '{print $2}')

if [ -z "$VERSION" ]; then
  echo "Error: Could not find version in pubspec.yaml"
  exit 1
fi

TAG="v$VERSION"

# 2. Check if the tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists."
  read -p "Do you want to delete the local and remote tag and re-create it? (y/N) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    git tag -d "$TAG"
    git push origin :refs/tags/"$TAG"
  else
    echo "Aborting."
    exit 0
  fi
fi

# 3. Create and push the tag
echo "Creating tag $TAG..."
git tag "$TAG"
echo "Pushing tag to origin..."
git push origin "$TAG"

echo "✅ Successfully tagged $TAG and pushed to GitHub."
