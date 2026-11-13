import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_pqc/tom_pqc.dart';

void main() {
  test('allocate gives zero bytes of the length asked', () {
    final s = SecretBytes.allocate(16);
    addTearDown(s.dispose);
    expect(s.length, 16);
    expect(s.extractBytes(), Uint8List(16));
  });

  test('fromBytes copies; extractBytes copies back', () {
    final source = Uint8List.fromList([1, 2, 3, 4]);
    final s = SecretBytes.fromBytes(source);
    addTearDown(s.dispose);
    source[0] = 9;
    final out = s.extractBytes();
    expect(out, [1, 2, 3, 4]);
    out[1] = 9;
    expect(s.extractBytes(), [1, 2, 3, 4]);
  });

  test('dispose is idempotent and ends every use', () {
    final s = SecretBytes.fromBytes(Uint8List.fromList([7, 7]));
    expect(s.isDisposed, isFalse);
    s.dispose();
    s.dispose();
    expect(s.isDisposed, isTrue);
    expect(s.extractBytes, throwsStateError);
    expect(() => s.pointer, throwsStateError);
  });

  test('a non-positive length is refused', () {
    expect(() => SecretBytes.allocate(0), throwsArgumentError);
    expect(() => SecretBytes.fromBytes(Uint8List(0)), throwsArgumentError);
  });
}
