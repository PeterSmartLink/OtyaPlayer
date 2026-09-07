import 'package:flutter_test/flutter_test.dart';
import 'package:otya_player/features/transfer/data/transfer_security_policy.dart';

void main() {
  const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  group('private transfer hosts', () {
    test('accepts RFC1918 and loopback IPv4 only', () {
      expect(isPrivateTransferIpv4Host('10.0.0.1'), isTrue);
      expect(isPrivateTransferIpv4Host('172.16.0.1'), isTrue);
      expect(isPrivateTransferIpv4Host('172.31.255.254'), isTrue);
      expect(isPrivateTransferIpv4Host('192.168.1.2'), isTrue);
      expect(isPrivateTransferIpv4Host('127.0.0.1'), isTrue);

      expect(isPrivateTransferIpv4Host('172.15.0.1'), isFalse);
      expect(isPrivateTransferIpv4Host('172.32.0.1'), isFalse);
      expect(isPrivateTransferIpv4Host('100.64.0.1'), isFalse);
      expect(isPrivateTransferIpv4Host('169.254.1.1'), isFalse);
      expect(isPrivateTransferIpv4Host('8.8.8.8'), isFalse);
      expect(isPrivateTransferIpv4Host('::1'), isFalse);
      expect(
        isPrivateTransferIpv4Host('127.0.0.1', allowLoopback: false),
        isFalse,
      );
    });
  });

  group('transfer URI policy', () {
    test('accepts authenticated single and indexed media URLs locally', () {
      expect(
        isAllowedTransferUri(
          Uri.parse('http://192.168.1.20:8080/media?t=$token&name=song.mp3'),
        ),
        isTrue,
      );
      expect(
        isAllowedTransferUri(
          Uri.parse('http://192.168.1.20:8080/media/0?t=$token'),
        ),
        isTrue,
      );
      expect(
        isAllowedTransferUri(
          Uri.parse('http://10.0.0.8:8080/media/199?t=$token'),
        ),
        isTrue,
      );
    });

    test('accepts only an authenticated local batch manifest URL', () {
      expect(
        isAllowedTransferBatchUri(
          Uri.parse('http://192.168.1.20:8080/batch?t=$token'),
        ),
        isTrue,
      );
      expect(
        isAllowedTransferBatchUri(
          Uri.parse('https://192.168.1.20:8080/batch?t=$token'),
        ),
        isFalse,
      );
      expect(
        isAllowedTransferBatchUri(
          Uri.parse('http://example.com:8080/batch?t=$token'),
        ),
        isFalse,
      );
      expect(
        isAllowedTransferUri(
          Uri.parse('http://192.168.1.20:8080/batch?t=$token'),
        ),
        isFalse,
      );
    });

    test('accepts the internal Together proxy only on IPv4 loopback', () {
      expect(
        isAllowedTransferUri(
          Uri.parse('http://127.0.0.1:49152/together-stream?t=$token'),
        ),
        isTrue,
      );
      expect(
        isAllowedTransferUri(
          Uri.parse('http://192.168.1.20:49152/together-stream?t=$token'),
        ),
        isFalse,
      );
    });

    test('rejects malformed, ambiguous and non-local URLs', () {
      final rejected = <String>[
        'https://192.168.1.20:8080/media?t=$token',
        'http://example.com/media?t=$token',
        'http://169.254.1.2/media?t=$token',
        'http://192.168.1.20/other?t=$token',
        'http://192.168.1.20/media/not-an-index?t=$token',
        'http://user@192.168.1.20/media?t=$token',
        'http://192.168.1.20/media?t=short',
        'http://192.168.1.20/media?t=$token&t=$token',
        'http://192.168.1.20/media?t=$token#fragment',
        'http://127.0.0.1/together-stream?t=short',
      ];

      for (final value in rejected) {
        expect(isAllowedTransferUri(Uri.parse(value)), isFalse, reason: value);
      }
    });
  });
}
