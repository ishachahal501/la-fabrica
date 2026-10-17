// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Web implementation using dart:html
Future<Uint8List?> pickImageBytesPlatform() async {
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

/// Triggers download of PNG bytes and revokes object URL after a delay
void downloadPngPlatform(Uint8List bytes, String filename) {
  final blob = html.Blob([bytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute("download", filename)
    ..click();

  // Allow browser sufficient time to begin the download before revoking the blob URL
  Timer(const Duration(seconds: 4), () {
    try {
      html.Url.revokeObjectUrl(url);
    } catch (_) {}
  });
}
