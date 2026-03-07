// Platform-specific: get token from URL (web) or null (mobile stub).
// Used to show ResetPasswordScreen when user opens the reset link.
export 'url_token_helper_stub.dart'
    if (dart.library.html) 'url_token_helper_web.dart';
