import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> consolidateHttpClientResponseBytes(
  HttpClientResponse response
) async {
  final List<List<int>> chunks = <List<int>>[];
  int contentLength = 0;
  
  await for (final List<int> chunk in response) {
    chunks.add(chunk);
    contentLength += chunk.length;
  }
  
  final Uint8List bytes = Uint8List(contentLength);
  int offset = 0;
  for (final List<int> chunk in chunks) {
    bytes.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  
  return bytes;
}
