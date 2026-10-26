/// Moving an item to the Windows Recycle Bin through the shell API.
///
/// `SHFileOperationW` with `FO_DELETE` and `FOF_ALLOWUNDO` is the call
/// Explorer's own delete makes. Calling it directly replaces a PowerShell
/// process that loaded the VisualBasic assembly for one call: that took a
/// second or more per delete, depended on PowerShell being on `PATH`, and
/// passed the path inside a command string, where quoting was the part that
/// had to be right.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// `SHFILEOPSTRUCTW`. On 64-bit Windows `shellapi.h` packs it at 8, which is
/// natural alignment and therefore what an ffi struct lays out.
final class _ShFileOpStruct extends Struct {
  external Pointer<Void> hwnd;
  @Uint32()
  external int wFunc;
  external Pointer<Uint16> pFrom;
  external Pointer<Uint16> pTo;
  @Uint16()
  external int fFlags;
  @Int32()
  external int fAnyOperationsAborted;
  external Pointer<Void> hNameMappings;
  external Pointer<Uint16> lpszProgressTitle;
}

typedef _ShFileOperationNative = Int32 Function(Pointer<_ShFileOpStruct>);
typedef _ShFileOperation = int Function(Pointer<_ShFileOpStruct>);

const _foDelete = 0x0003;
const _fofSilent = 0x0004;
const _fofNoConfirmation = 0x0010;
const _fofAllowUndo = 0x0040;
const _fofNoErrorUi = 0x0400;

/// Moves [absolute] — a file or a folder, a full Windows path — to the
/// Recycle Bin. Answers whether it went there; nothing is asked of the user
/// and no dialog is shown.
bool tomWindowsRecycle(String absolute) {
  final shell32 = DynamicLibrary.open('shell32.dll');
  final operate = shell32
      .lookupFunction<_ShFileOperationNative, _ShFileOperation>(
        'SHFileOperationW',
      );
  final units = absolute.replaceAll('/', r'\').codeUnits;
  // pFrom is a list of paths, each NUL-terminated, the list ending in a
  // second NUL.
  final from = calloc<Uint16>(units.length + 2);
  final op = calloc<_ShFileOpStruct>();
  try {
    for (var i = 0; i < units.length; i++) {
      from[i] = units[i];
    }
    op.ref
      ..wFunc = _foDelete
      ..pFrom = from
      ..fFlags =
          _fofAllowUndo | _fofNoConfirmation | _fofSilent | _fofNoErrorUi;
    final result = operate(op);
    return result == 0 && op.ref.fAnyOperationsAborted == 0;
  } finally {
    calloc.free(from);
    calloc.free(op);
  }
}
