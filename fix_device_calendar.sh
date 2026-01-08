#!/bin/bash

# Script to fix device_calendar package namespace issue
# Run this after 'flutter pub get' if you encounter namespace errors

DEVICE_CALENDAR_BUILD_GRADLE="$HOME/.pub-cache/hosted/pub.dev/device_calendar-3.9.0/android/build.gradle"

if [ -f "$DEVICE_CALENDAR_BUILD_GRADLE" ]; then
    # Check if namespace is already set
    if ! grep -q "namespace 'com.builttoroam.devicecalendar'" "$DEVICE_CALENDAR_BUILD_GRADLE"; then
        # Add namespace after the android { line
        if grep -q "android {" "$DEVICE_CALENDAR_BUILD_GRADLE"; then
            # Use sed to add namespace after android {
            sed -i '' "/^android {/a\\
    namespace 'com.builttoroam.devicecalendar'
" "$DEVICE_CALENDAR_BUILD_GRADLE"
            echo "✓ Fixed device_calendar namespace issue"
        else
            echo "✗ Could not find 'android {' in build.gradle"
        fi
    else
        echo "✓ device_calendar namespace already set"
    fi
else
    echo "✗ device_calendar package not found at expected location"
    echo "  Looking for: $DEVICE_CALENDAR_BUILD_GRADLE"
    echo "  Try running 'flutter pub get' first"
fi

