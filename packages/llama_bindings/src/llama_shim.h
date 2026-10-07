// llama_shim.h
//
// A flat, plain-C surface over llama.cpp, designed for `dart:ffi`.
//
// Two problems this solves, both of which make direct ffigen bindings a bad idea here:
//
//  1. `dart:ffi` cannot call C++, and it cannot safely mirror llama.cpp's structs.
//     `llama_model_params`, `llama_context_params` and `llama_batch` change shape between
//     llama.cpp releases; a Dart-side struct definition that drifts out of sync corrupts
//     memory silently. Everything here takes primitives and opaque pointers only, so the
//     Dart side never needs to know a single struct layout, and a llama.cpp upgrade is
//     contained entirely within this file.
//
//  2. llama.cpp's functions are declared `extern "C"` but *implemented* in C++, and they
//     can throw. An uncaught C++ exception unwinding across the FFI boundary hits
//     std::terminate and kills the process — Dart cannot catch it any more than Swift
//     could. This is not theoretical: the Swift original hit
//     `Unexpected empty grammar stack after accepting piece` from grammar-constrained
//     sampling. Every call below that can throw is wrapped in a real try/catch and
//     converts the exception into a return value plus a message in a caller-owned buffer.
//
// This is a direct port of `LLM/Native/LlamaSafeCalls.{h,mm}` from the Swift app, widened
// to cover the whole API surface the engine uses so that no raw llama.cpp symbol is ever
// looked up from Dart.
//
// Error convention: every fallible function takes `char *err, int32_t err_len`. On failure
// a NUL-terminated message is written there (truncated if necessary). Pass NULL/0 to
// discard. The buffer is caller-owned, so there is no thread-local lifetime hazard of the
// kind the Objective-C++ original had to document.

#ifndef LLAMA_SHIM_H
#define LLAMA_SHIM_H

#include <stdbool.h>
#include <stdint.h>

#if defined(_WIN32)
#define LC_EXPORT __declspec(dllexport)
#else
#define LC_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#if defined(__cplusplus)
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

/// Idempotent. Safe to call more than once; only the first call reaches llama.cpp.
LC_EXPORT void lc_backend_init(void);

/// Silences llama.cpp's own stderr logging. The app logs structural metadata only and
/// must never let model or prompt text reach the system log.
LC_EXPORT void lc_log_disable(void);

/// True when this build has a GPU backend compiled in (Metal on Apple, OpenCL on Adreno).
LC_EXPORT bool lc_supports_gpu_offload(void);

/// Physical core count as llama.cpp sees it. The engine derives its thread count from this.
LC_EXPORT int32_t lc_cpu_count(void);

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Loads a GGUF model. Returns NULL on failure with a message in `err`.
/// `vocab_only` skips the weights entirely — that is how metadata is read for a model that
/// is installed but not active, without disturbing the live context.
LC_EXPORT void *lc_model_load(const char *path,
                              int32_t n_gpu_layers,
                              bool vocab_only,
                              char *err,
                              int32_t err_len);

LC_EXPORT void lc_model_free(void *model);

/// Borrowed pointer, owned by the model. Do not free.
LC_EXPORT const void *lc_model_vocab(void *model);

/// The context length the model was trained at, or 0 when unknown.
LC_EXPORT int32_t lc_model_n_ctx_train(void *model);

LC_EXPORT uint64_t lc_model_size(void *model);
LC_EXPORT uint64_t lc_model_n_params(void *model);

/// Copies the GGUF-embedded chat template into `buf`. Returns the number of bytes written,
/// 0 when the model has no template (which the engine treats as fatal rather than guessing
/// one), or the required capacity as a negative number when `buf` is too small.
LC_EXPORT int32_t lc_model_chat_template(void *model, char *buf, int32_t buf_len);

/// Reads a single GGUF metadata string, e.g. "general.architecture".
/// Returns bytes written, or a negative value when absent.
LC_EXPORT int32_t lc_model_meta_val_str(void *model,
                                        const char *key,
                                        char *buf,
                                        int32_t buf_len);

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

LC_EXPORT void *lc_context_new(void *model,
                               uint32_t n_ctx,
                               uint32_t n_batch,
                               int32_t n_threads,
                               char *err,
                               int32_t err_len);

LC_EXPORT void lc_context_free(void *ctx);

/// The context length actually allocated, after llama.cpp clamped the request.
LC_EXPORT uint32_t lc_n_ctx(void *ctx);

/// Clears the KV cache without unloading weights. This is the "full prompt rebuild"
/// strategy's reset, and the same call that switching conversations makes.
LC_EXPORT void lc_memory_clear(void *ctx);

/// Sequence-0 state snapshots: the KV cache — and for hybrid models such as Qwen3.5 the
/// recurrent state — after a prompt prefix has been decoded. Restoring one replaces decoding
/// that prefix again. A snapshot rather than trimming the cache back with `seq_rm`, because a
/// recurrent state cannot be rolled back to an earlier position; a snapshot works for every
/// architecture.
///
/// `lc_state_size` is the byte size a snapshot needs now (0 when there is nothing to save).
/// `lc_state_save` / `lc_state_restore` return the bytes written / read, 0 on failure.
/// Sets the generation and prompt-processing thread counts separately. On a measured
/// Snapdragon 732G, reading a prompt kept getting faster up to all 8 cores (9.8 vs 8.3 tok/s
/// at 6) while generation barely moved (5.1 vs 4.8) — so prompts use every core, and
/// generation leaves two free for the UI that is streaming the answer.
LC_EXPORT void lc_set_threads(void *ctx, int32_t n_threads, int32_t n_threads_batch);

LC_EXPORT size_t lc_state_size(void *ctx);
LC_EXPORT size_t lc_state_save(void *ctx, uint8_t *dst, size_t size, char *err, int32_t err_len);
LC_EXPORT size_t lc_state_restore(void *ctx,
                                  const uint8_t *src,
                                  size_t size,
                                  char *err,
                                  int32_t err_len);

// ---------------------------------------------------------------------------
// Batch
// ---------------------------------------------------------------------------

/// Allocates a batch sized for `n_tokens`, single sequence, no embeddings.
LC_EXPORT void *lc_batch_new(int32_t n_tokens);
LC_EXPORT void lc_batch_free(void *batch);

/// Resets `n_tokens` to 0 without reallocating.
LC_EXPORT void lc_batch_clear(void *batch);

/// Appends one token at `pos` in sequence 0. `logits` marks it as the position whose
/// logits are wanted — exactly one token per decode should set it.
/// Returns false when the batch is already at capacity.
LC_EXPORT bool lc_batch_add(void *batch, int32_t token, int32_t pos, bool logits);

/// Wraps `llama_decode`. Returns llama_decode's own result code (0 = success) on success.
/// Returns LC_DECODE_EXCEPTION when a C++ exception was caught.
#define LC_DECODE_EXCEPTION (-1000)
LC_EXPORT int32_t lc_decode(void *ctx, void *batch, char *err, int32_t err_len);

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------

/// Mirrors `llama_tokenize`: returns the token count, or a negative number whose
/// magnitude is the required capacity when `out_cap` is too small.
LC_EXPORT int32_t lc_tokenize(const void *vocab,
                              const char *text,
                              int32_t text_len,
                              int32_t *out,
                              int32_t out_cap,
                              bool add_special,
                              bool parse_special);

/// Mirrors `llama_token_to_piece`. Writes raw bytes, no NUL terminator, because a single
/// token is frequently only part of a multi-byte scalar — the caller reassembles.
LC_EXPORT int32_t lc_token_to_piece(const void *vocab,
                                    int32_t token,
                                    char *buf,
                                    int32_t buf_cap);

LC_EXPORT bool lc_vocab_is_eog(const void *vocab, int32_t token);

// ---------------------------------------------------------------------------
// Chat template
// ---------------------------------------------------------------------------

/// Applies the model's embedded chat template to parallel role/content arrays.
///
/// Passing two arrays of C strings rather than an array of `llama_chat_message` structs is
/// deliberate: it keeps `llama_chat_message`'s layout out of Dart entirely. This function
/// builds the struct array itself.
///
/// Returns the total byte length of the formatted prompt — which may exceed `buf_len`, in
/// which case nothing usable was written and the caller should retry with that capacity.
/// Returns a negative value when the template could not be applied at all.
LC_EXPORT int32_t lc_chat_apply_template(const char *tmpl,
                                         const char **roles,
                                         const char **contents,
                                         int32_t n_msg,
                                         bool add_assistant,
                                         char *buf,
                                         int32_t buf_len);

// ---------------------------------------------------------------------------
// Sampler chain
// ---------------------------------------------------------------------------

/// Builds an empty chain. The engine then adds, in this order:
/// optional grammar → min-p → top-p → temperature → distribution.
LC_EXPORT void *lc_sampler_chain_new(char *err, int32_t err_len);

/// Adds a GBNF grammar constraint at the head of the chain.
///
/// Present because the Swift original has it, and unused for the same reason: grammar
/// parsing and acceptance are the documented source of the thrown exceptions this shim
/// exists to contain. The agent layer passes no grammar and relies on tolerant parsing
/// plus a deterministic fallback instead. Do not "fix" that.
LC_EXPORT bool lc_sampler_add_grammar(void *chain,
                                      const void *vocab,
                                      const char *grammar,
                                      const char *root,
                                      char *err,
                                      int32_t err_len);

LC_EXPORT void lc_sampler_add_min_p(void *chain, float p, int32_t min_keep);
LC_EXPORT void lc_sampler_add_top_p(void *chain, float p, int32_t min_keep);
LC_EXPORT void lc_sampler_add_temp(void *chain, float t);
LC_EXPORT void lc_sampler_add_dist(void *chain, uint32_t seed);

LC_EXPORT void lc_sampler_free(void *chain);

/// Samples the next token. Returns LC_SAMPLE_ERROR on a caught C++ exception —
/// distinguishable from a real token because llama.cpp token ids are non-negative.
#define LC_SAMPLE_ERROR (-1)
LC_EXPORT int32_t lc_sampler_sample(void *chain,
                                    void *ctx,
                                    int32_t idx,
                                    char *err,
                                    int32_t err_len);

LC_EXPORT bool lc_sampler_accept(void *chain, int32_t token, char *err, int32_t err_len);

/// The default seed llama.cpp uses when none is specified.
LC_EXPORT uint32_t lc_default_seed(void);

#if defined(__cplusplus)
}
#endif

#endif // LLAMA_SHIM_H
