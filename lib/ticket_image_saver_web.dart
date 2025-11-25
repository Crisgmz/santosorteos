import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

Future<void> saveTicketImage(Uint8List bytes, String filename) async {
  if (bytes.isEmpty) return;

  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/jpeg'));
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.click();

  web.URL.revokeObjectURL(url);
}
