// ---------------------------------------------------------------------------
// Image compression – keep uploads under 500 KB for a lightweight app.
// ---------------------------------------------------------------------------
// Use [compressImageToMaxBytes] before base64Encode when uploading profile
// photos, logos, or ID document images. PDFs are left unchanged.
// ---------------------------------------------------------------------------

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Target max size for uploaded images (500 KB).
const int kMaxImageBytes = 500 * 1024;

/// Compress image bytes to at most [maxBytes] (default 500 KB).
/// Returns JPEG bytes. If input is not a supported image or compression fails, returns original bytes.
Uint8List compressImageToMaxBytes(
  Uint8List bytes, {
  int maxBytes = kMaxImageBytes,
}) {
  if (bytes.length <= maxBytes) return bytes;

  img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  const int maxSide = 1200;
  if (decoded.width > maxSide || decoded.height > maxSide) {
    decoded = img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? maxSide : null,
      height: decoded.height > decoded.width ? maxSide : null,
      interpolation: img.Interpolation.linear,
    );
  }

  int quality = 85;
  Uint8List encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));

  while (encoded.length > maxBytes && quality > 20) {
    quality -= 15;
    if (quality < 20) quality = 20;
    encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  }

  if (encoded.length > maxBytes) {
    final smaller = img.copyResize(decoded, width: 800, height: 800, interpolation: img.Interpolation.linear);
    encoded = Uint8List.fromList(img.encodeJpg(smaller, quality: 75));
    quality = 75;
    while (encoded.length > maxBytes && quality > 25) {
      quality -= 10;
      encoded = Uint8List.fromList(img.encodeJpg(smaller, quality: quality));
    }
  }

  return encoded;
}

/// Returns true if bytes look like JPEG/PNG. PDF and other types upload as-is.
bool isCompressibleImage(Uint8List bytes) {
  if (bytes.length < 4) return false;
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
  return false;
}
