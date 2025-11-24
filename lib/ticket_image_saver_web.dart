import 'dart:typed_data';
import 'dart:html' as html;

Future<void> saveTicketImage(Uint8List bytes, String filename) async {
  if (bytes.isEmpty) return;

  final blob = html.Blob([bytes], 'image/jpeg');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..click();

  html.Url.revokeObjectUrl(url);
}
