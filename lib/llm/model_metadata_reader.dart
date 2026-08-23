import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:llama_bindings/llama_bindings.dart';

import 'llama_error.dart';

class ModelMetadata {
  const ModelMetadata({
    required this.hasChatTemplate,
    required this.fileSizeBytes,
    this.architecture,
    this.quantization,
    this.nativeContextLength,
  });

  final String? architecture;
  final String? quantization;
  final int? nativeContextLength;
  final bool hasChatTemplate;
  final int fileSizeBytes;

  Map<String, Object?> toIsolateMap() => {
        'architecture': architecture,
        'quantization': quantization,
        'nativeContextLength': nativeContextLength,
        'hasChatTemplate': hasChatTemplate,
        'fileSizeBytes': fileSizeBytes,
      };

  static ModelMetadata fromIsolateMap(Map<String, Object?> map) => ModelMetadata(
        architecture: map['architecture'] as String?,
        quantization: map['quantization'] as String?,
        nativeContextLength: map['nativeContextLength'] as int?,
        hasChatTemplate: map['hasChatTemplate']! as bool,
        fileSizeBytes: map['fileSizeBytes']! as int,
      );

  @override
  bool operator ==(Object other) =>
      other is ModelMetadata &&
      other.architecture == architecture &&
      other.quantization == quantization &&
      other.nativeContextLength == nativeContextLength &&
      other.hasChatTemplate == hasChatTemplate &&
      other.fileSizeBytes == fileSizeBytes;

  @override
  int get hashCode => Object.hash(
      architecture, quantization, nativeContextLength, hasChatTemplate, fileSizeBytes);
}

/// Reads GGUF metadata without loading a model's weights.
///
/// Runs in a short-lived isolate of its own — not the inference isolate — so probing an
/// installed-but-inactive model in the model manager can never touch the live context or
/// stall a generation in progress. A vocab-only load is cheap: it maps the header and the
/// tokenizer and skips the tensors entirely, so this stays fast even for a multi-gigabyte
/// file.
class ModelMetadataReader {
  const ModelMetadataReader();

  Future<ModelMetadata> read(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw LlamaError.modelFileMissing(path);
    }
    final fileSize = file.lengthSync();

    final raw = await Isolate.run(() => _readInIsolate(path, fileSize));
    return ModelMetadata.fromIsolateMap(raw);
  }

  /// Derives a quantization label from the file name.
  ///
  /// GGUF metadata has no single clean quantization string, so this reads the well-known
  /// suffix that every quantization tool — llama.cpp's own `llama-quantize` included — puts
  /// in the name: `Q4_K_M`, `IQ3_XXS`, `Q8_0`, `F16`.
  static String? quantizationLabelFromFileName(String fileName) {
    final pattern = RegExp(
      r'\b(Q\d(?:_[0-9A-Z]+)+|IQ\d(?:_[A-Z]+)?|F16|F32|BF16)\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(fileName);
    return match?.group(0)?.toUpperCase();
  }
}

/// Top-level so it can be sent to [Isolate.run].
Map<String, Object?> _readInIsolate(String path, int fileSize) {
  final native = LlamaNative.forCurrentIsolate();
  native.backendInit();
  native.disableNativeLogging();

  ffi.Pointer<ffi.Void> model = ffi.nullptr;
  try {
    model = native.loadModel(path: path, gpuLayers: 0, vocabOnly: true);

    final architecture = native.modelMetadataString(model, 'general.architecture');
    final trainedContext = native.modelTrainedContextLength(model);
    final template = native.modelChatTemplate(model);

    return ModelMetadata(
      architecture: architecture,
      quantization: ModelMetadataReader.quantizationLabelFromFileName(
          path.split(Platform.pathSeparator).last),
      nativeContextLength: trainedContext > 0 ? trainedContext : null,
      hasChatTemplate: template != null && template.isNotEmpty,
      fileSizeBytes: fileSize,
    ).toIsolateMap();
  } on LlamaNativeException catch (error) {
    throw LlamaError.modelLoadFailed(
        'vocab-only load failed while reading metadata: ${error.message}');
  } finally {
    if (model != ffi.nullptr) {
      native.freeModel(model);
    }
  }
}
