import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dart:html' as html;

class FilePickerHelper {
  /// Prompts browser file upload dialog and returns image raw bytes
  static Future<Uint8List?> pickImageBytes() async {
    if (!kIsWeb) return null;

    final Completer<Uint8List?> completer = Completer();
    final html.FileUploadInputElement input = html.FileUploadInputElement();
    input.accept = 'image/*';
    input.click();

    input.onChange.listen((e) {
      final files = input.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        reader.onLoadEnd.listen((e) {
          if (reader.result is Uint8List) {
            completer.complete(reader.result as Uint8List);
          } else if (reader.result is ByteBuffer) {
            completer.complete((reader.result as ByteBuffer).asUint8List());
          } else {
            completer.complete(null);
          }
        });
      } else {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  /// Triggers browser download of PNG file bytes
  static void downloadPngWeb(Uint8List bytes, String filename) {
    if (!kIsWeb) return;

    final blob = html.Blob([bytes], 'image/png');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
