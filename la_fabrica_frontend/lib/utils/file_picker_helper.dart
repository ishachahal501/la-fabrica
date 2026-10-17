import 'dart:typed_data';
import 'file_picker_helper_stub.dart'
    if (dart.library.html) 'file_picker_helper_web.dart';

class FilePickerHelper {
  /// Prompts browser/platform file upload dialog and returns image raw bytes
  static Future<Uint8List?> pickImageBytes() => pickImageBytesPlatform();

  /// Triggers browser download of PNG file bytes
  static void downloadPngWeb(Uint8List bytes, String filename) => downloadPngPlatform(bytes, filename);
}
