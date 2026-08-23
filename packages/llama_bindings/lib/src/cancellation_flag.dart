import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

/// A cancellation signal that works across an isolate boundary without message passing.
///
/// The problem this solves: the inference isolate spends almost all its time inside a
/// synchronous native decode loop. A `cancel` sent over a `SendPort` only gets seen when
/// that isolate returns to its event loop, so cancellation latency would be tied to how
/// often the loop yields — and during a long prompt prefill it may not yield at all.
///
/// llama.cpp's own `abort_callback` cannot help either: it needs a *synchronous* return
/// value from Dart, and `NativeCallable.listener` — the only callable that can be invoked
/// from a foreign thread — is asynchronous by design and returns nothing.
///
/// So instead: one 32-bit integer in native memory, allocated by whoever owns the engine and
/// read directly by the loop between decodes. Isolates cannot share Dart objects, but they
/// can both hold a pointer to the same address, and an aligned 32-bit read/write is atomic
/// on every architecture this ships on. Setting it takes effect on the very next iteration,
/// mid-prefill included.
///
/// The allocating side must call [dispose] exactly once. The isolate side reconstructs its
/// view with [fromAddress] and must not dispose.
class CancellationFlag {
  CancellationFlag._(this._pointer, this._owned);

  /// Allocates a new flag, initialised to "not cancelled". The caller owns it.
  factory CancellationFlag.allocate() =>
      CancellationFlag._(calloc<ffi.Int32>(), true);

  /// Reconstructs a view of a flag allocated elsewhere. Does not take ownership.
  factory CancellationFlag.fromAddress(int address) =>
      CancellationFlag._(ffi.Pointer<ffi.Int32>.fromAddress(address), false);

  final ffi.Pointer<ffi.Int32> _pointer;
  final bool _owned;

  /// Send this across the isolate boundary; reconstruct with [fromAddress].
  int get address => _pointer.address;

  bool get isCancelled => _pointer.value != 0;

  void cancel() => _pointer.value = 1;

  /// Clears the flag before starting a new generation. Forgetting this makes the next
  /// generation stop immediately, which is a confusing failure, so the engine resets at the
  /// start of every run rather than at the end of the previous one.
  void reset() => _pointer.value = 0;

  void dispose() {
    if (_owned) {
      calloc.free(_pointer);
    }
  }
}
