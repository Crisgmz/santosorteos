import 'dart:typed_data';
import 'package:image_gallery_saver/image_gallery_saver.dart';

Future<void> saveTicketImage(Uint8List bytes, String filename) async {
  if (bytes.isEmpty) return;
  await ImageGallerySaver.saveImage(bytes, name: filename);
}
