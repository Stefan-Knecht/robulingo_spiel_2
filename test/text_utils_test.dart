import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/utils/text_utils.dart';

void main() {
  test('normalizeText keeps non-latin scripts', () {
    expect(normalizeText('فم فم'), 'فم فم');
    expect(normalizeText('水'), '水');
    expect(normalizeText('みず'), 'みず');
  });

  test('normalizeText strips punctuation and collapses whitespace', () {
    expect(normalizeText('  Wasser!!!  '), 'wasser');
    expect(normalizeText('Wasser\t\nBrot'), 'wasser brot');
  });

  test('normalizeText removes Arabic diacritics (harakat)', () {
    // بَابَا -> بابا
    expect(normalizeText('بَابَا'), 'بابا');
  });
}

