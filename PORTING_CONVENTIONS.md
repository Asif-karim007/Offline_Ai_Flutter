# Porting conventions

Rules this port follows. They exist so that a reviewer can diff a Dart file against its Swift
original and account for every difference.

## Fidelity

1. **Prompt strings, thresholds, keyword lists and token caps are copied, not paraphrased.**
   They are tuned against a 0.6B model's actual behaviour. A reworded system prompt is a
   behaviour change, not a style change.
2. **Preserve deliberate limitations.** The clearest example: the agent layer passes no GBNF
   grammar, because grammar-constrained sampling threw a C++ exception on Qwen3's `<think>`
   preamble and killed the process. The plumbing exists and stays unused. Do not "fix" this.
3. **User-visible strings are verbatim**, including the exact ellipsis character `…`, curly
   quotes and em dashes.
4. **UserDefaults keys carry across unchanged** so a future migration path stays open.

## Structure

- Layer boundaries match the Swift app: `domain/`, `llm/`, `agent/`, `persistence/`,
  `model_management/`, `utilities/`, `viewmodels/`, `views/`.
- One Swift file maps to one Dart file with a `snake_case` name. `AgentOrchestrator.swift`
  becomes `agent_orchestrator.dart`.
- Nothing outside `lib/llm/` and `packages/llama_bindings/` imports `dart:ffi`.
- Nothing outside `lib/llm/` imports `package:llama_bindings`.

## Dart choices

- **No code generation anywhere.** No freezed, no json_serializable, no drift, no
  build_runner. A fresh clone is `flutter pub get && flutter run`. This is why persistence is
  hand-written sqflite and state is `ChangeNotifier` rather than drift and Riverpod.
- Swift `actor` becomes an isolate (for the engine, where native state demands it) or an
  ordinary class with a guard flag (everywhere else, where the actor was only providing
  mutual exclusion that Dart's single-threaded event loop already gives).
- Swift `struct` becomes a Dart class with `final` fields, a `copyWith`, and `==`/`hashCode`.
- `AsyncThrowingStream` becomes `Stream`; `Task.isCancelled` becomes either a subscription
  cancel or the shared native cancellation flag.
- Swift `enum` with associated values becomes a `sealed class` when the payloads differ, and
  an `enum` with a `wireValue` when they do not.
- `Result`-style throwing stays throwing. Errors are `LlamaError` with a `kind` discriminator.

## Comments

Comments explain *why*, and only where the reason is not evident from the code. A comment
that restates the line above it is noise. The ones worth writing are the ones that record a
decision: why the KV cache is cleared every turn, why grammar sampling is unused, why the
sampler order is fixed, why a template is rejected rather than guessed.

## Naming

- Dart `lowerCamelCase` for members, `UpperCamelCase` for types — Swift names carry over
  directly since both languages share the convention.
- Swift's `nonisolated struct X: Sendable` prefix drops; the Dart equivalent is just a class.
