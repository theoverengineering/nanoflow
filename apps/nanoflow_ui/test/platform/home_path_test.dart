import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/platform/home_path.dart';

void main() {
  const home = '/Users/me';

  test('a path under the home directory starts with ~', () {
    expect(
      abbreviateHome('/Users/me/Projects/review/review.yaml', home: home),
      '~/Projects/review/review.yaml',
    );
    expect(
      abbreviateHome('/Users/me/Projects/', home: '/Users/me/'),
      '~/Projects/',
    );
  });

  test('the home directory itself is ~', () {
    expect(abbreviateHome('/Users/me', home: home), '~');
  });

  test('other paths stay as they are', () {
    expect(
      abbreviateHome('/Users/meg/review.yaml', home: home),
      '/Users/meg/review.yaml',
    );
    expect(abbreviateHome('/tmp/review.yaml', home: home), '/tmp/review.yaml');
    expect(abbreviateHome('/tmp/review.yaml', home: ''), '/tmp/review.yaml');
  });
}
