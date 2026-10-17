import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

class ImageHelper {
  /// Processes raw image bytes: decodes, resizes to max 400px width/height,
  /// compresses to PNG, and converts to a base64 Data URI with strict size checks.
  static Future<String> processAndCompressImage(Uint8List rawBytes) async {
    // 1. Check raw bytes input size limit (max 5 MB)
    if (rawBytes.length > 5 * 1024 * 1024) {
      throw Exception('Original image file is too large (max 5MB limit).');
    }

    try {
      // 2. Decode original image frame size
      final ui.Codec codec = await ui.instantiateImageCodec(rawBytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image originalImage = frameInfo.image;

      int origWidth = originalImage.width;
      int origHeight = originalImage.height;

      // Calculate target width & height maintaining aspect ratio (max 400x400)
      int targetWidth = origWidth;
      int targetHeight = origHeight;
      const int maxDim = 400;

      if (origWidth > maxDim || origHeight > maxDim) {
        if (origWidth >= origHeight) {
          targetWidth = maxDim;
          targetHeight = (origHeight * (maxDim / origWidth)).round();
        } else {
          targetHeight = maxDim;
          targetWidth = (origWidth * (maxDim / origHeight)).round();
        }
      }

      // Re-instantiate codec with target dimensions if scaling needed
      final ui.Codec targetCodec = await ui.instantiateImageCodec(
        rawBytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final ui.FrameInfo targetFrame = await targetCodec.getNextFrame();
      final ui.Image resizedImage = targetFrame.image;

      // Render resized image to PictureRecorder Canvas
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      final ui.Paint paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;

      canvas.drawImage(resizedImage, ui.Offset.zero, paint);
      final ui.Picture picture = recorder.endRecording();
      final ui.Image finalImage = await picture.toImage(targetWidth, targetHeight);

      final ByteData? byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Failed to compress image.');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Safeguard: Check compressed PNG byte limit (MVP limit: 1MB payload capacity)
      const int maxCompressedSizeBytes = 1024 * 1024;
      if (pngBytes.length > maxCompressedSizeBytes) {
        throw Exception('Compressed image is too large (exceeds 1MB limit).');
      }

      final String base64Data = base64Encode(pngBytes);
      return 'data:image/png;base64,$base64Data';
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Could not process selected image: ${e.toString()}');
    }
  }
}
