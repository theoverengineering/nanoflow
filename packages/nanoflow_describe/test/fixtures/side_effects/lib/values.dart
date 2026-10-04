// Values of dart:io that touch nothing — constants, enum values, exceptions —
// warn nowhere; a static final value is not a constant.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';

Future<void> values(Flow f, String url) async {
  final status = await f.effect('fetch', () => 200);
  if (status == HttpStatus.notFound) throw HttpException('missing $url');
  if (status != HttpStatus.ok) throw ProcessException('curl', [url]);
  print(FileMode.append);
  print(HttpClientResponseCompressionState.notCompressed);
  print(ContentType.json);
  await f.effect('done', () => url);
}
