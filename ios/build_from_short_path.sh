#!/bin/bash
# Build iOS from shortest path to fix "Argument list too long"
# Run from project root: ./ios/build_from_short_path.sh
#
# Fixes applied:
# - Legacy Build System (ios/Runner.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings)
# - Short symlink path (~/p)
# - Optional: Xcode → File → Workspace Settings → Custom Derived Data → /tmp/xc-dd

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHORT_PATH="$HOME/p"

# Create symlink if needed
if [ ! -L "$SHORT_PATH" ]; then
  ln -sf "$PROJECT_ROOT" "$SHORT_PATH"
  echo "Created symlink: $SHORT_PATH -> $PROJECT_ROOT"
fi

# Build from short path (~/p = ~10 chars vs ~/rm = ~13 chars)
cd "$SHORT_PATH"
flutter build ios --no-codesign
