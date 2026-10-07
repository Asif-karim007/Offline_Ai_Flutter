import 'dart:ffi' as ffi;

import 'llama_library.dart';

// ---------------------------------------------------------------------------
// Native signatures
// ---------------------------------------------------------------------------
//
// Hand-written rather than generated. There are only thirty-odd of them, they are all
// primitives and opaque pointers by construction (see `src/llama_shim.h`), and hand-writing
// them removes ffigen and an LLVM toolchain from every contributor's setup.
//
// `ffigen.yaml` in the repository root regenerates an equivalent file if the shim's surface
// ever grows enough to make that worthwhile.

typedef _VoidNative = ffi.Void Function();
typedef _VoidDart = void Function();

typedef _BoolRetNative = ffi.Bool Function();
typedef _BoolRetDart = bool Function();

typedef _Int32RetNative = ffi.Int32 Function();
typedef _Int32RetDart = int Function();

typedef _Uint32RetNative = ffi.Uint32 Function();
typedef _Uint32RetDart = int Function();

typedef _ModelLoadNative = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Char>, ffi.Int32, ffi.Bool, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _ModelLoadDart = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Char>, int, bool, ffi.Pointer<ffi.Char>, int);

typedef _PtrArgVoidNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _PtrArgVoidDart = void Function(ffi.Pointer<ffi.Void>);

typedef _PtrToPtrNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>);
typedef _PtrToPtrDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>);

typedef _PtrToInt32Native = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _PtrToInt32Dart = int Function(ffi.Pointer<ffi.Void>);

typedef _PtrToUint32Native = ffi.Uint32 Function(ffi.Pointer<ffi.Void>);
typedef _PtrToUint32Dart = int Function(ffi.Pointer<ffi.Void>);

typedef _SetThreadsNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32);
typedef _SetThreadsDart = void Function(ffi.Pointer<ffi.Void>, int, int);

typedef _StateSizeNative = ffi.Size Function(ffi.Pointer<ffi.Void>);
typedef _StateSizeDart = int Function(ffi.Pointer<ffi.Void>);
typedef _StateSaveNative = ffi.Size Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _StateSaveDart = int Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Char>, int);

typedef _PtrToUint64Native = ffi.Uint64 Function(ffi.Pointer<ffi.Void>);
typedef _PtrToUint64Dart = int Function(ffi.Pointer<ffi.Void>);

typedef _ChatTemplateNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _ChatTemplateDart = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, int);

typedef _MetaValNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _MetaValDart = int Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, int);

typedef _ContextNewNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Uint32,
    ffi.Uint32, ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _ContextNewDart = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>, int, int, int, ffi.Pointer<ffi.Char>, int);

typedef _BatchNewNative = ffi.Pointer<ffi.Void> Function(ffi.Int32);
typedef _BatchNewDart = ffi.Pointer<ffi.Void> Function(int);

typedef _BatchAddNative = ffi.Bool Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Bool);
typedef _BatchAddDart = bool Function(ffi.Pointer<ffi.Void>, int, int, bool);

typedef _DecodeNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _DecodeDart = int Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, int);

typedef _TokenizeNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>,
    ffi.Int32, ffi.Pointer<ffi.Int32>, ffi.Int32, ffi.Bool, ffi.Bool);
typedef _TokenizeDart = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, int,
    ffi.Pointer<ffi.Int32>, int, bool, bool);

typedef _TokenToPieceNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _TokenToPieceDart = int Function(
    ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Char>, int);

typedef _IsEogNative = ffi.Bool Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _IsEogDart = bool Function(ffi.Pointer<ffi.Void>, int);

typedef _ApplyTemplateNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Pointer<ffi.Char>>,
    ffi.Pointer<ffi.Pointer<ffi.Char>>,
    ffi.Int32,
    ffi.Bool,
    ffi.Pointer<ffi.Char>,
    ffi.Int32);
typedef _ApplyTemplateDart = int Function(
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Pointer<ffi.Char>>,
    ffi.Pointer<ffi.Pointer<ffi.Char>>,
    int,
    bool,
    ffi.Pointer<ffi.Char>,
    int);

typedef _ChainNewNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _ChainNewDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>, int);

typedef _AddGrammarNative = ffi.Bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _AddGrammarDart = bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, int);

typedef _AddFloatKeepNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Float, ffi.Int32);
typedef _AddFloatKeepDart = void Function(ffi.Pointer<ffi.Void>, double, int);

typedef _AddFloatNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Float);
typedef _AddFloatDart = void Function(ffi.Pointer<ffi.Void>, double);

typedef _AddSeedNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Uint32);
typedef _AddSeedDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _SampleNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _SampleDart = int Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Char>, int);

typedef _AcceptNative = ffi.Bool Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _AcceptDart = bool Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Char>, int);

/// Returned by `lc_decode` when a C++ exception was caught. Keep in sync with the
/// `LC_DECODE_EXCEPTION` macro in `src/llama_shim.h`.
const int lcDecodeException = -1000;

/// Returned by `lc_sampler_sample` on a caught C++ exception. Token ids are non-negative,
/// so this cannot collide with a real result.
const int lcSampleError = -1;

/// Thin, stateless holder for the resolved `lc_*` function pointers.
///
/// Every method maps 1:1 onto a shim function; no policy lives here. The engine layer above
/// owns lifetimes, error translation and buffer sizing.
class LlamaFfi {
  LlamaFfi._(ffi.DynamicLibrary lib)
      : backendInit = lib.lookupFunction<_VoidNative, _VoidDart>('lc_backend_init'),
        logDisable = lib.lookupFunction<_VoidNative, _VoidDart>('lc_log_disable'),
        supportsGpuOffload =
            lib.lookupFunction<_BoolRetNative, _BoolRetDart>('lc_supports_gpu_offload'),
        cpuCount = lib.lookupFunction<_Int32RetNative, _Int32RetDart>('lc_cpu_count'),
        modelLoad = lib.lookupFunction<_ModelLoadNative, _ModelLoadDart>('lc_model_load'),
        modelFree = lib.lookupFunction<_PtrArgVoidNative, _PtrArgVoidDart>('lc_model_free'),
        modelVocab = lib.lookupFunction<_PtrToPtrNative, _PtrToPtrDart>('lc_model_vocab'),
        modelNCtxTrain =
            lib.lookupFunction<_PtrToInt32Native, _PtrToInt32Dart>('lc_model_n_ctx_train'),
        modelSize = lib.lookupFunction<_PtrToUint64Native, _PtrToUint64Dart>('lc_model_size'),
        modelNParams =
            lib.lookupFunction<_PtrToUint64Native, _PtrToUint64Dart>('lc_model_n_params'),
        modelChatTemplate = lib
            .lookupFunction<_ChatTemplateNative, _ChatTemplateDart>('lc_model_chat_template'),
        modelMetaValStr =
            lib.lookupFunction<_MetaValNative, _MetaValDart>('lc_model_meta_val_str'),
        contextNew = lib.lookupFunction<_ContextNewNative, _ContextNewDart>('lc_context_new'),
        contextFree =
            lib.lookupFunction<_PtrArgVoidNative, _PtrArgVoidDart>('lc_context_free'),
        nCtx = lib.lookupFunction<_PtrToUint32Native, _PtrToUint32Dart>('lc_n_ctx'),
        memoryClear =
            lib.lookupFunction<_PtrArgVoidNative, _PtrArgVoidDart>('lc_memory_clear'),
        batchNew = lib.lookupFunction<_BatchNewNative, _BatchNewDart>('lc_batch_new'),
        batchFree = lib.lookupFunction<_PtrArgVoidNative, _PtrArgVoidDart>('lc_batch_free'),
        batchClear = lib.lookupFunction<_PtrArgVoidNative, _PtrArgVoidDart>('lc_batch_clear'),
        batchAdd = lib.lookupFunction<_BatchAddNative, _BatchAddDart>('lc_batch_add'),
        decode = lib.lookupFunction<_DecodeNative, _DecodeDart>('lc_decode'),
        setThreads = lib.lookupFunction<_SetThreadsNative, _SetThreadsDart>('lc_set_threads'),
        stateSize = lib.lookupFunction<_StateSizeNative, _StateSizeDart>('lc_state_size'),
        stateSave = lib.lookupFunction<_StateSaveNative, _StateSaveDart>('lc_state_save'),
        stateRestore = lib.lookupFunction<_StateSaveNative, _StateSaveDart>('lc_state_restore'),
        tokenize = lib.lookupFunction<_TokenizeNative, _TokenizeDart>('lc_tokenize'),
        tokenToPiece =
            lib.lookupFunction<_TokenToPieceNative, _TokenToPieceDart>('lc_token_to_piece'),
        vocabIsEog = lib.lookupFunction<_IsEogNative, _IsEogDart>('lc_vocab_is_eog'),
        chatApplyTemplate = lib
            .lookupFunction<_ApplyTemplateNative, _ApplyTemplateDart>('lc_chat_apply_template'),
        samplerChainNew =
            lib.lookupFunction<_ChainNewNative, _ChainNewDart>('lc_sampler_chain_new'),
        samplerAddGrammar =
            lib.lookupFunction<_AddGrammarNative, _AddGrammarDart>('lc_sampler_add_grammar'),
        samplerAddMinP =
            lib.lookupFunction<_AddFloatKeepNative, _AddFloatKeepDart>('lc_sampler_add_min_p'),
        samplerAddTopP =
            lib.lookupFunction<_AddFloatKeepNative, _AddFloatKeepDart>('lc_sampler_add_top_p'),
        samplerAddTemp =
            lib.lookupFunction<_AddFloatNative, _AddFloatDart>('lc_sampler_add_temp'),
        samplerAddDist =
            lib.lookupFunction<_AddSeedNative, _AddSeedDart>('lc_sampler_add_dist'),
        samplerFree =
            lib.lookupFunction<_PtrArgVoidNative, _PtrArgVoidDart>('lc_sampler_free'),
        samplerSample = lib.lookupFunction<_SampleNative, _SampleDart>('lc_sampler_sample'),
        samplerAccept = lib.lookupFunction<_AcceptNative, _AcceptDart>('lc_sampler_accept'),
        defaultSeed =
            lib.lookupFunction<_Uint32RetNative, _Uint32RetDart>('lc_default_seed');

  /// Resolves the shim once per isolate.
  ///
  /// Deliberately not a process-wide singleton: each isolate that touches llama.cpp does its
  /// own lookup, because a `DynamicLibrary` and the function pointers derived from it cannot
  /// be sent across an isolate boundary as objects. Lookup is cheap; the loader has already
  /// mapped the library by the time the second isolate asks.
  static LlamaFfi? _instance;

  static LlamaFfi get instance => _instance ??= LlamaFfi._(openLlamaLibrary());

  final _VoidDart backendInit;
  final _VoidDart logDisable;
  final _BoolRetDart supportsGpuOffload;
  final _Int32RetDart cpuCount;

  final _ModelLoadDart modelLoad;
  final _PtrArgVoidDart modelFree;
  final _PtrToPtrDart modelVocab;
  final _PtrToInt32Dart modelNCtxTrain;
  final _PtrToUint64Dart modelSize;
  final _PtrToUint64Dart modelNParams;
  final _ChatTemplateDart modelChatTemplate;
  final _MetaValDart modelMetaValStr;

  final _ContextNewDart contextNew;
  final _PtrArgVoidDart contextFree;
  final _PtrToUint32Dart nCtx;
  final _PtrArgVoidDart memoryClear;

  final _BatchNewDart batchNew;
  final _PtrArgVoidDart batchFree;
  final _PtrArgVoidDart batchClear;
  final _BatchAddDart batchAdd;
  final _DecodeDart decode;
  final _SetThreadsDart setThreads;
  final _StateSizeDart stateSize;
  final _StateSaveDart stateSave;
  final _StateSaveDart stateRestore;

  final _TokenizeDart tokenize;
  final _TokenToPieceDart tokenToPiece;
  final _IsEogDart vocabIsEog;

  final _ApplyTemplateDart chatApplyTemplate;

  final _ChainNewDart samplerChainNew;
  final _AddGrammarDart samplerAddGrammar;
  final _AddFloatKeepDart samplerAddMinP;
  final _AddFloatKeepDart samplerAddTopP;
  final _AddFloatDart samplerAddTemp;
  final _AddSeedDart samplerAddDist;
  final _PtrArgVoidDart samplerFree;
  final _SampleDart samplerSample;
  final _AcceptDart samplerAccept;

  final _Uint32RetDart defaultSeed;
}
