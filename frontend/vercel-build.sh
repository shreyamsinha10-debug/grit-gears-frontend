#!/usr/bin/env bash
set -e
# Avoid exit 128 from Flutter's internal git calls on Vercel (no git config)
git config --global user.email "build@vercel.app" 2>/dev/null || true
git config --global user.name "Vercel" 2>/dev/null || true
if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter..."
  FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.2-stable.tar.xz"
  curl -fSL --retry 3 --retry-delay 5 -o /tmp/flutter.tar.xz "$FLUTTER_URL" || {
    echo "Flutter download failed. Try Option B (GitHub Actions) for reliable deploy."
    exit 1
  }
  tar xf /tmp/flutter.tar.xz -C /tmp
  export PATH="$PATH:/tmp/flutter/bin"
fi
export PATH="$PATH:/tmp/flutter/bin"
flutter pub get
flutter build web --release
