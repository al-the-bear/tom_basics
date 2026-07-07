import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('OutputFormat', () {
    test('BB-OUT-1: canonical names parse case-insensitively [2026-07-05]', () {
      expect(OutputFormat.tryParse('plain'), OutputFormat.plain);
      expect(OutputFormat.tryParse('csv'), OutputFormat.csv);
      expect(OutputFormat.tryParse('json'), OutputFormat.json);
      expect(OutputFormat.tryParse('md'), OutputFormat.md);
      // Case-insensitive.
      expect(OutputFormat.tryParse('PLAIN'), OutputFormat.plain);
      expect(OutputFormat.tryParse('Csv'), OutputFormat.csv);
      expect(OutputFormat.tryParse('JSON'), OutputFormat.json);
      expect(OutputFormat.tryParse('Md'), OutputFormat.md);
    });

    test('BB-OUT-2: text/markdown aliases resolve [2026-07-05]', () {
      expect(OutputFormat.tryParse('text'), OutputFormat.plain);
      expect(OutputFormat.tryParse('TEXT'), OutputFormat.plain);
      expect(OutputFormat.tryParse('markdown'), OutputFormat.md);
      expect(OutputFormat.tryParse('Markdown'), OutputFormat.md);
    });

    test('BB-OUT-3: null/empty/unknown return null [2026-07-05]', () {
      expect(OutputFormat.tryParse(null), isNull);
      expect(OutputFormat.tryParse(''), isNull);
      expect(OutputFormat.tryParse('xml'), isNull);
      expect(OutputFormat.tryParse('html'), isNull);
    });
  });

  group('OutputSpec', () {
    test('BB-OUT-4: format-only spec targets stdout [2026-07-05]', () {
      final spec = OutputSpec.tryParse('csv');
      expect(spec, isNotNull);
      expect(spec!.format, OutputFormat.csv);
      expect(spec.filePath, isNull);
      expect(spec.hasFile, isFalse);
    });

    test('BB-OUT-5: format:file spec captures the file path [2026-07-05]', () {
      final spec = OutputSpec.tryParse('csv:output.csv');
      expect(spec, isNotNull);
      expect(spec!.format, OutputFormat.csv);
      expect(spec.filePath, 'output.csv');
      expect(spec.hasFile, isTrue);
    });

    test('BB-OUT-6: aliases work inside a spec [2026-07-05]', () {
      final spec = OutputSpec.tryParse('markdown:report.md');
      expect(spec!.format, OutputFormat.md);
      expect(spec.filePath, 'report.md');
    });

    test('BB-OUT-7: trailing empty file part yields no file [2026-07-05]', () {
      final spec = OutputSpec.tryParse('json:');
      expect(spec, isNotNull);
      expect(spec!.format, OutputFormat.json);
      expect(spec.filePath, isNull);
      expect(spec.hasFile, isFalse);
    });

    test('BB-OUT-8: only the first colon splits format from file '
        '[2026-07-05]', () {
      // A Windows-style path retains its own colons in the file part.
      final spec = OutputSpec.tryParse('json:C:/tmp/out.json');
      expect(spec, isNotNull);
      expect(spec!.format, OutputFormat.json);
      expect(spec.filePath, 'C:/tmp/out.json');
    });

    test('BB-OUT-9: null/empty/unknown-format specs return null [2026-07-05]',
        () {
      expect(OutputSpec.tryParse(null), isNull);
      expect(OutputSpec.tryParse(''), isNull);
      expect(OutputSpec.tryParse('xml:output.xml'), isNull);
      expect(OutputSpec.tryParse('nope'), isNull);
    });

    test('BB-OUT-10: defaultSpec is plain to stdout [2026-07-05]', () {
      const spec = OutputSpec.defaultSpec;
      expect(spec.format, OutputFormat.plain);
      expect(spec.filePath, isNull);
      expect(spec.hasFile, isFalse);
    });
  });
}
