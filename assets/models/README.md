# Bundled model directory

`pubspec.yaml` declares this directory as an asset directory:

```yaml
flutter:
  assets:
    - assets/models/
```

Drop a single GGUF file in here and it ships inside the app. On first launch, if no model is
already installed, the app copies it out of the asset bundle into the platform's application
support directory exactly once and loads only from that copy — the bundled original is never
modified, and never mmapped directly (an asset on Android lives inside the APK; on iOS it
lives in a read-only bundle).

This file you are reading is also what keeps the directory present in git. An empty asset
directory makes `flutter build` fail with *"unable to find directory entry in pubspec.yaml"*,
so do not delete it.

## Why no model is committed

A GGUF file is model weights: 533 MB for the recommended default, 2.74 GB for the largest
suggested option. Git stores it as an undeltifiable binary blob, every clone pays for it
forever, and one accidental commit of a wrong-quantization file can never be removed from
history without a rewrite. It is also somebody else's licensed artifact — see the root
`README.md`, "Model and llama.cpp licensing".

So: the repository ships the loader, not the weights.

## What to put here

The recommended default, matching the root `README.md`:

```
assets/models/Qwen3.5-0.8B-Q4_K_M.gguf      533 MB
```

Any instruction-tuned GGUF with an embedded chat template works. The app **rejects a model
whose GGUF carries no usable chat template rather than guessing one**, so a base
(non-instruct) model or a bare conversion will fail to load with
`LlamaError.missingChatTemplate` — that is deliberate.

Download it from the model's own repository (Hugging Face, `Qwen/…-GGUF` or an equivalent
quantizer's mirror), verify the file size and hash against the model card, and copy it in
under exactly the name above.

## Not bundling anything

Perfectly supported, and the right call for a build you intend to distribute over the air —
a 500 MB app binary is a bad first impression. Leave this directory with only this README in
it. On first launch, with no bundled asset and no previously installed model, the app shows
its setup screen with **Import GGUF Model** (a document picker; on iOS you can also drop the
file into the app's folder in Files first — see `UIFileSharingEnabled` in
`ios/Runner/Info.plist`) and the in-app download option for the larger models.

## A note on packaging

Android's build is configured not to compress this asset
(`androidResources { noCompress += ["gguf"] }` in `android/app/build.gradle`). A quantized
model does not compress meaningfully, and leaving it STORED means the first-launch copy is a
straight byte stream out of the APK instead of a full inflate pass with a same-sized
transient buffer.
