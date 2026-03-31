#!/bin/sh
  #!/bin/sh
  set -e

  MARKER="${PODS_TARGET_SRCROOT}/rive_marker_macos_setup_complete"
  DEV_MARKER="${PODS_TARGET_SRCROOT}/rive_marker_macos_development"


  if [ -f "$MARKER" ] || [ -f "$DEV_MARKER" ]; then
    echo "[rive_native] Setup already complete. Skipping."
  else
    echo "[rive_native] Setup marker not found. Running setup script..."
    echo "[rive_native] If this fails, make sure you have Dart installed and available in your PATH."
    echo "[rive_native] You can run the setup manually with:"
    echo "  dart run rive_native:setup --verbose --platform macos"

    # macOS path to Flutter-Generated.xcconfig
    GENERATED_XCCONFIG="${SRCROOT}/../Flutter/ephemeral/Flutter-Generated.xcconfig"
    if [ -f "$GENERATED_XCCONFIG" ]; then
      FLUTTER_ROOT=$(grep FLUTTER_ROOT "$GENERATED_XCCONFIG" | cut -d '=' -f2 | tr -d '[:space:]')
    fi

    if [ -n "$FLUTTER_ROOT" ] && [ -x "$FLUTTER_ROOT/bin/dart" ]; then
      echo "[rive_native] Using dart from FLUTTER_ROOT: $FLUTTER_ROOT"
      "$FLUTTER_ROOT/bin/dart" run rive_native:setup --verbose --platform macos
    else
      echo "[rive_native] FLUTTER_ROOT not set or dart not found in FLUTTER_ROOT. Using system dart..."
      dart run rive_native:setup --verbose --platform macos
    fi
  fi

