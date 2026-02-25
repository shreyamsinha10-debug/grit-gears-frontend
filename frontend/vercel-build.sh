#!/usr/bin/env bash
set -e
if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter..."
  curl -sL -o /tmp/flutter.zip "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.zip"
  unzip -q /tmp/flutter.zip -d /tmp
  export PATH="$PATH:/tmp/flutter/bin"
fi
export PATH="$PATH:/tmp/flutter/bin"
flutter pub get
flutter build web --release
