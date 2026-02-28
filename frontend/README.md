# frontend

A new Flutter project.

## Running the app (web)

**Do not** launch Chrome with `--disable-web-security`. The backend allows all origins (CORS), so that flag is unnecessary and causes a browser warning and can lead to a blank or unstable page.

- **From terminal:**  
  `flutter run -d chrome`  
  (no `--web-browser-flag`)

- **From VS Code/Cursor:**  
  Use **Run > Start Debugging** (or F5), then choose **Chrome** as the device. Use the `.vscode/launch.json` "Flutter (Chrome)" config so no unsafe browser flags are added.

If the page is blank, wait a few seconds for the first build, or open DevTools (F12) and check the Console for errors. Ensure the backend is running (e.g. `uvicorn main:app --reload --host 0.0.0.0 --port 8000` in the `backend` folder) and set the app’s server URL to `http://localhost:8000` if you’re testing locally.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
