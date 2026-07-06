import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class PickedImage {
  final Uint8List bytes;
  final String mime;
  const PickedImage(this.bytes, this.mime);
}

/// Picks an image (camera on mobile, file picker elsewhere) and returns it
/// resized to at most [maxDimension] on the longest side, re-encoded as JPEG.
class ImagePickService {
  final ImagePicker _picker;
  ImagePickService([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  static const int maxDimension = 1280;
  static const int jpegQuality = 80;

  /// [fromCamera] only applies on mobile; ignored on web/desktop, where the
  /// platform always shows a file picker.
  Future<PickedImage?> pick({required bool fromCamera}) async {
    final source =
        (!kIsWeb && fromCamera) ? ImageSource.camera : ImageSource.gallery;
    final file = await _picker.pickImage(source: source);
    if (file == null) return null;
    final raw = await file.readAsBytes();
    return PickedImage(resizeToJpeg(raw), 'image/jpeg');
  }

  /// Pure function: decode, downscale so the longest side <= [maxDimension],
  /// re-encode as JPEG. Returns the input unchanged if it cannot be decoded.
  static Uint8List resizeToJpeg(Uint8List input) {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;
    final resized =
        (decoded.width > maxDimension || decoded.height > maxDimension)
            ? img.copyResize(
                decoded,
                width: decoded.width >= decoded.height ? maxDimension : null,
                height: decoded.height > decoded.width ? maxDimension : null,
              )
            : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: jpegQuality));
  }
}
