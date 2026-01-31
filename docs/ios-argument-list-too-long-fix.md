# Fix: "unable to spawn process '/bin/sh' (Argument list too long)"

This error occurs when build environment variables (HEADER_SEARCH_PATHS, etc.) exceed system limits. **Try solution 1 first** — it usually fixes the issue.

## 1. Shorter Derived Data path (recommended)

1. Open `ios/Runner.xcworkspace` in Xcode
2. **File → Workspace Settings** (or **Project Settings**)
3. **Advanced** → **Custom** for Derived Data
4. Set path to: `/tmp/xc-dd` or `~/xd`
5. Click **Done**
6. Run `flutter build ios` again

## 2. Shorter project path

Move or symlink the project to a shorter path:

```bash
ln -s /Users/alexey/RoadMate_Flutter/RoadMate_flutter ~/rm
cd ~/rm
flutter build ios --no-codesign
```

## 3. Legacy Build System

1. Open `ios/Runner.xcworkspace` in Xcode
2. **File → Workspace Settings → Advanced**
3. Select **Legacy** build system
4. Click **Done**
