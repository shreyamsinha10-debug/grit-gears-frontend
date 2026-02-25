#!/usr/bin/env bash
set -e
if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter..."
  curl -fSL --retry 3 --retry-delay 5 -o /tmp/flutter.zip \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.zip" || {
    echo "Flutter download failed. Try Option B (GitHub Actions) for reliable deploy."
    exit 1
  }
  unzip -q /tmp/flutter.zip -d /tmp
  export PATH="$PATH:/tmp/flutter/bin"
fi
export PATH="$PATH:/tmp/flutter/bin"
flutter pub get
flutter build web --release
