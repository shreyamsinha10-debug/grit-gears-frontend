// ---------------------------------------------------------------------------
// App constants – version and other build-time or app-wide values.
// ---------------------------------------------------------------------------
// [kAppVersion] is used when calling /version to prompt user to update if
// backend returns a higher min_app_version.
// ---------------------------------------------------------------------------

/// App version for update check. Must match pubspec version or be passed via --dart-define.
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.2.1',
);

/// Display string for app version and date (e.g. "GS 1.0.0 (16 Mar 2026)").
const String kAppVersionDisplay = 'GS $kAppVersion (16 Mar 2026)';

/// Footer branding shown in settings and splash.
const String kPoweredBy = 'Powered By Dertz Infotech';

/// URL for "Powered By" link.
const String kPoweredByUrl = 'https://www.dertzinfotech.com/';
