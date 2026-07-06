import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:averias_app/services/image_pick_service.dart';

void main() {
  test('resizeToJpeg downscales longest side to maxDimension', () {
    final big = img.Image(width: 2000, height: 1000);
    final input = img.encodePng(big);
    final out = ImagePickService.resizeToJpeg(input);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, ImagePickService.maxDimension);
    expect(decoded.height, 640);
  });

  test('resizeToJpeg keeps small images within bounds and re-encodes to jpeg', () {
    final small = img.Image(width: 400, height: 300);
    final input = img.encodePng(small);
    final out = ImagePickService.resizeToJpeg(input);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 400);
    expect(decoded.height, 300);
    // JPEG magic bytes 0xFF 0xD8
    expect(out[0], 0xFF);
    expect(out[1], 0xD8);
  });
}
