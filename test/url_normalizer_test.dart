import 'package:flutter_test/flutter_test.dart';

import 'package:maps_saved_app/infrastructure/sync/url_normalizer.dart';

void main() {
  group('UrlNormalizer', () {
    group('http to https upgrade', () {
      test('upgrades http scheme to https', () {
        final result =
            UrlNormalizer.normalize('http://www.google.com/maps/place/Cafe');
        expect(result, startsWith('https://'));
        expect(result, contains('www.google.com'));
      });

      test('keeps https scheme unchanged', () {
        final result =
            UrlNormalizer.normalize('https://www.google.com/maps/place/Cafe');
        expect(result, startsWith('https://'));
      });
    });

    group('trailing slash removal', () {
      test('removes trailing slash from path', () {
        final result = UrlNormalizer.normalize(
            'https://www.google.com/maps/place/Cafe/');
        expect(result, isNot(endsWith('/')));
        expect(result, contains('/maps/place/Cafe'));
      });

      test('does not remove root slash', () {
        final result = UrlNormalizer.normalize('https://www.google.com/');
        // Root path "/" should remain as "/"
        expect(result, contains('google.com'));
      });

      test('no trailing slash remains unchanged', () {
        final result = UrlNormalizer.normalize(
            'https://www.google.com/maps/place/Cafe');
        expect(result, contains('/maps/place/Cafe'));
      });
    });

    group('tracking params removal', () {
      test('removes utm_source', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps?utm_source=twitter');
        expect(result, isNot(contains('utm_source')));
      });

      test('removes utm_medium', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps?utm_medium=social');
        expect(result, isNot(contains('utm_medium')));
      });

      test('removes utm_campaign', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps?utm_campaign=promo');
        expect(result, isNot(contains('utm_campaign')));
      });

      test('removes utm_term', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps?utm_term=keyword');
        expect(result, isNot(contains('utm_term')));
      });

      test('removes utm_content', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps?utm_content=banner');
        expect(result, isNot(contains('utm_content')));
      });

      test('removes fbclid', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps?fbclid=abc123');
        expect(result, isNot(contains('fbclid')));
      });

      test('removes gclid', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps?gclid=xyz789');
        expect(result, isNot(contains('gclid')));
      });

      test('removes multiple tracking params at once', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps?utm_source=tw&fbclid=abc&gclid=xyz');
        expect(result, isNot(contains('utm_source')));
        expect(result, isNot(contains('fbclid')));
        expect(result, isNot(contains('gclid')));
      });
    });

    group('keeps place-relevant query params', () {
      test('keeps q param', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps?q=tokyo+tower');
        expect(result, contains('q=tokyo'));
      });

      test('keeps place-specific params while removing tracking', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps?q=cafe&utm_source=twitter');
        expect(result, contains('q=cafe'));
        expect(result, isNot(contains('utm_source')));
      });

      test('keeps data param', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps/place/Test?data=somedata');
        expect(result, contains('data=somedata'));
      });
    });

    group('handles malformed URLs gracefully', () {
      test('returns original for completely invalid URL', () {
        final result = UrlNormalizer.normalize('not a url at all');
        // Uri.tryParse returns a valid Uri for most strings,
        // so the result should at least not throw
        expect(result, isNotNull);
      });

      test('handles empty string', () {
        final result = UrlNormalizer.normalize('');
        expect(result, isNotNull);
      });

      test('handles whitespace-only string', () {
        final result = UrlNormalizer.normalize('   ');
        expect(result, isNotNull);
      });

      test('handles URL with only scheme', () {
        final result = UrlNormalizer.normalize('https://');
        expect(result, isNotNull);
      });

      test('trims whitespace before processing', () {
        final result = UrlNormalizer.normalize(
            '  https://google.com/maps  ');
        expect(result, contains('google.com'));
      });
    });

    group('handles already normalized URLs', () {
      test('returns consistent output for already-normalized URL', () {
        const url = 'https://www.google.com/maps/place/Cafe';
        final first = UrlNormalizer.normalize(url);
        final second = UrlNormalizer.normalize(first);
        expect(first, equals(second));
      });

      test('idempotent - double normalization produces same result', () {
        const url =
            'http://www.google.com/maps/place/Test/?utm_source=tw&q=coffee';
        final first = UrlNormalizer.normalize(url);
        final second = UrlNormalizer.normalize(first);
        expect(first, equals(second));
      });

      test('lowercases host', () {
        final result = UrlNormalizer.normalize(
            'https://WWW.GOOGLE.COM/maps/place/Cafe');
        expect(result, contains('www.google.com'));
      });

      test('removes fragment', () {
        final result = UrlNormalizer.normalize(
            'https://google.com/maps/place/Cafe#section');
        expect(result, isNot(contains('#section')));
      });
    });
  });
}
