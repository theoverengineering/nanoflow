// Functions that call themselves: each is drawn once, and its call goes back
// to its own graph.
import 'package:nanoflow/nanoflow.dart';

/// Tries again, a little later each time, until the deploy goes through.
Future<void> deploy(Flow f, int attempt) async {
  final ok = await f.effect('try-deploy', () => attempt > 2);
  if (!ok) {
    await backoff(attempt);
    await deploy(f, attempt + 1);
  }
}

/// Calls itself but no effect: not a function with effects.
Future<void> backoff(int attempt) async {
  if (attempt == 0) return;
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await backoff(attempt - 1);
}

/// Fetches a page and visits the pages it links to.
Future<void> crawl(Flow f, String url) async {
  final links = await f.effect('fetch', () => linksOf(url));
  for (final link in links) {
    await visit(f, link);
  }
}

/// Calls no effect of its own, but crawls a page that is a directory: a
/// function with effects through [crawl], which calls it back.
Future<void> visit(Flow f, String url) async {
  if (url.endsWith('/')) await crawl(f, url);
}

List<String> linksOf(String url) => [
  if (url.split('/').length < 5) ...['${url}a/', '${url}b.html'],
];
