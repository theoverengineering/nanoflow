// Values of dart:io that touch nothing — constants, enum values, exceptions
// and their members — warn nowhere; a static final value is not a constant.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';

final fetch = node('fetch', (String url) async => 200);

final values = Graph<String, void>('values', [
  Graph.start(fetch).next((status) {
    if (status == HttpStatus.notFound) throw HttpException('missing $status');
    if (status != HttpStatus.ok) throw ProcessException('curl', ['$status']);
    print(FileMode.append);
    print(HttpClientResponseCompressionState.notCompressed);
    print(ContentType.json);
    try {
      print(status);
    } on HttpException catch (e) {
      print(e.message);
    }
    print(SocketException('refused').osError);
    return null;
  }),
]);
