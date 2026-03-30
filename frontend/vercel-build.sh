#!/usr/bin/env bash
set -e
# Avoid exit 128 from Flutter's internal git calls on Vercel (no git config)
git config --global user.email "build@vercel.app" 2>/dev/null || true
git config --global user.name "Vercel" 2>/dev/null || true
# Suppress "run flutter as root" warning (Flutter's shared.sh checks this)
export CI=true
if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter (git clone for proper .git so Flutter tool runs)..."
  if [[ -d /tmp/flutter ]]; then rm -rf /tmp/flutter; fi
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git /tmp/flutter
  export PATH="$PATH:/tmp/flutter/bin"
fi
export PATH="$PATH:/tmp/flutter/bin"
flutter pub get
flutter build web --release
