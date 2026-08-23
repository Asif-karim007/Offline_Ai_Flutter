// llama_shim.cpp — see llama_shim.h for the rationale.

#include "llama_shim.h"

#include "llama.h"

#include <cstring>
#include <exception>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

namespace {

// The batch is allocated by value by llama.cpp but must live behind a pointer to cross the
// plain-C boundary, so it is boxed together with its capacity. Capacity is tracked here
// because llama_batch itself does not expose it, and lc_batch_add must refuse to overrun.
struct BoxedBatch {
    llama_batch batch;
    int32_t capacity;
};

void writeError(char *err, int32_t err_len, const char *message) {
    if (err == nullptr || err_len <= 0 || message == nullptr) {
        return;
    }
    const size_t max_copy = static_cast<size_t>(err_len) - 1;
    const size_t len = std::strlen(message);
    const size_t n = len < max_copy ? len : max_copy;
    std::memcpy(err, message, n);
    err[n] = '\0';
}

void writeException(char *err, int32_t err_len, const std::exception &e) {
    writeError(err, err_len, e.what());
}

void writeUnknownException(char *err, int32_t err_len) {
    writeError(err, err_len, "Unknown native (C++) exception in llama.cpp");
}

/// Swallows llama.cpp's own logging entirely. Registered by lc_log_disable.
void silentLog(ggml_log_level, const char *, void *) {}

std::once_flag g_backend_once;

/// Copies `source` into `buf`, returning bytes written, or -(required) when it will not fit.
int32_t copyOut(const char *source, char *buf, int32_t buf_len) {
    const int32_t required = static_cast<int32_t>(std::strlen(source));
    if (buf == nullptr || buf_len <= required) {
        return -required;
    }
    std::memcpy(buf, source, static_cast<size_t>(required));
    buf[required] = '\0';
    return required;
}

} // namespace

extern "C" {

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

void lc_backend_init(void) {
    std::call_once(g_backend_once, []() { llama_backend_init(); });
}

void lc_log_disable(void) {
    llama_log_set(silentLog, nullptr);
}

bool lc_supports_gpu_offload(void) {
    return llama_supports_gpu_offload();
}

int32_t lc_cpu_count(void) {
    // llama.cpp does not export a portable core count, so this mirrors what the Swift app
    // read from ProcessInfo. std::thread::hardware_concurrency is the portable equivalent
    // and is what the Dart side then clamps with max(1, min(8, n - 2)).
    const unsigned int n = std::thread::hardware_concurrency();
    return n == 0 ? 1 : static_cast<int32_t>(n);
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

void *lc_model_load(const char *path,
                    int32_t n_gpu_layers,
                    bool vocab_only,
                    char *err,
                    int32_t err_len) {
    try {
        llama_model_params params = llama_model_default_params();
        params.n_gpu_layers = n_gpu_layers;
        params.vocab_only = vocab_only;

        llama_model *model = llama_model_load_from_file(path, params);
        if (model == nullptr) {
            writeError(err, err_len, "llama_model_load_from_file returned NULL");
            return nullptr;
        }
        return model;
    } catch (const std::exception &e) {
        writeException(err, err_len, e);
        return nullptr;
    } catch (...) {
        writeUnknownException(err, err_len);
        return nullptr;
    }
}

void lc_model_free(void *model) {
    if (model == nullptr) {
        return;
    }
    llama_model_free(static_cast<llama_model *>(model));
}

const void *lc_model_vocab(void *model) {
    if (model == nullptr) {
        return nullptr;
    }
    return llama_model_get_vocab(static_cast<llama_model *>(model));
}

int32_t lc_model_n_ctx_train(void *model) {
    if (model == nullptr) {
        return 0;
    }
    return llama_model_n_ctx_train(static_cast<llama_model *>(model));
}

uint64_t lc_model_size(void *model) {
    if (model == nullptr) {
        return 0;
    }
    return llama_model_size(static_cast<llama_model *>(model));
}

uint64_t lc_model_n_params(void *model) {
    if (model == nullptr) {
        return 0;
    }
    return llama_model_n_params(static_cast<llama_model *>(model));
}

int32_t lc_model_chat_template(void *model, char *buf, int32_t buf_len) {
    if (model == nullptr) {
        return 0;
    }
    const char *tmpl = llama_model_chat_template(static_cast<llama_model *>(model), nullptr);
    if (tmpl == nullptr) {
        return 0;
    }
    return copyOut(tmpl, buf, buf_len);
}

int32_t lc_model_meta_val_str(void *model, const char *key, char *buf, int32_t buf_len) {
    if (model == nullptr || buf == nullptr || buf_len <= 0) {
        return -1;
    }
    return llama_model_meta_val_str(static_cast<llama_model *>(model),
                                    key,
                                    buf,
                                    static_cast<size_t>(buf_len));
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

void *lc_context_new(void *model,
                     uint32_t n_ctx,
                     uint32_t n_batch,
                     int32_t n_threads,
                     char *err,
                     int32_t err_len) {
    if (model == nullptr) {
        writeError(err, err_len, "no model loaded");
        return nullptr;
    }
    try {
        llama_context_params params = llama_context_default_params();
        params.n_ctx = n_ctx;
        params.n_batch = n_batch;
        params.n_threads = n_threads;
        params.n_threads_batch = n_threads;

        llama_context *ctx = llama_init_from_model(static_cast<llama_model *>(model), params);
        if (ctx == nullptr) {
            writeError(err, err_len, "llama_init_from_model returned NULL");
            return nullptr;
        }
        return ctx;
    } catch (const std::exception &e) {
        writeException(err, err_len, e);
        return nullptr;
    } catch (...) {
        writeUnknownException(err, err_len);
        return nullptr;
    }
}

void lc_context_free(void *ctx) {
    if (ctx == nullptr) {
        return;
    }
    llama_free(static_cast<llama_context *>(ctx));
}

uint32_t lc_n_ctx(void *ctx) {
    if (ctx == nullptr) {
        return 0;
    }
    return llama_n_ctx(static_cast<llama_context *>(ctx));
}

void lc_memory_clear(void *ctx) {
    if (ctx == nullptr) {
        return;
    }
    llama_memory_t mem = llama_get_memory(static_cast<llama_context *>(ctx));
    if (mem != nullptr) {
        llama_memory_clear(mem, true);
    }
}

// ---------------------------------------------------------------------------
// Batch
// ---------------------------------------------------------------------------

void *lc_batch_new(int32_t n_tokens) {
    if (n_tokens <= 0) {
        return nullptr;
    }
    auto *boxed = new (std::nothrow) BoxedBatch();
    if (boxed == nullptr) {
        return nullptr;
    }
    boxed->batch = llama_batch_init(n_tokens, 0, 1);
    boxed->capacity = n_tokens;
    boxed->batch.n_tokens = 0;
    return boxed;
}

void lc_batch_free(void *batch) {
    if (batch == nullptr) {
        return;
    }
    auto *boxed = static_cast<BoxedBatch *>(batch);
    llama_batch_free(boxed->batch);
    delete boxed;
}

void lc_batch_clear(void *batch) {
    if (batch == nullptr) {
        return;
    }
    static_cast<BoxedBatch *>(batch)->batch.n_tokens = 0;
}

bool lc_batch_add(void *batch, int32_t token, int32_t pos, bool logits) {
    if (batch == nullptr) {
        return false;
    }
    auto *boxed = static_cast<BoxedBatch *>(batch);
    const int32_t i = boxed->batch.n_tokens;
    if (i >= boxed->capacity) {
        return false;
    }
    boxed->batch.token[i] = token;
    boxed->batch.pos[i] = pos;
    boxed->batch.n_seq_id[i] = 1;
    boxed->batch.seq_id[i][0] = 0;
    boxed->batch.logits[i] = logits ? 1 : 0;
    boxed->batch.n_tokens += 1;
    return true;
}

int32_t lc_decode(void *ctx, void *batch, char *err, int32_t err_len) {
    if (ctx == nullptr || batch == nullptr) {
        writeError(err, err_len, "no model loaded");
        return LC_DECODE_EXCEPTION;
    }
    auto *boxed = static_cast<BoxedBatch *>(batch);
    try {
        return llama_decode(static_cast<llama_context *>(ctx), boxed->batch);
    } catch (const std::exception &e) {
        writeException(err, err_len, e);
        return LC_DECODE_EXCEPTION;
    } catch (...) {
        writeUnknownException(err, err_len);
        return LC_DECODE_EXCEPTION;
    }
}

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------

int32_t lc_tokenize(const void *vocab,
                    const char *text,
                    int32_t text_len,
                    int32_t *out,
                    int32_t out_cap,
                    bool add_special,
                    bool parse_special) {
    if (vocab == nullptr) {
        return 0;
    }
    return llama_tokenize(static_cast<const llama_vocab *>(vocab),
                          text,
                          text_len,
                          out,
                          out_cap,
                          add_special,
                          parse_special);
}

int32_t lc_token_to_piece(const void *vocab, int32_t token, char *buf, int32_t buf_cap) {
    if (vocab == nullptr) {
        return 0;
    }
    return llama_token_to_piece(static_cast<const llama_vocab *>(vocab),
                                token,
                                buf,
                                buf_cap,
                                0,
                                false);
}

bool lc_vocab_is_eog(const void *vocab, int32_t token) {
    if (vocab == nullptr) {
        return true;
    }
    return llama_vocab_is_eog(static_cast<const llama_vocab *>(vocab), token);
}

// ---------------------------------------------------------------------------
// Chat template
// ---------------------------------------------------------------------------

int32_t lc_chat_apply_template(const char *tmpl,
                               const char **roles,
                               const char **contents,
                               int32_t n_msg,
                               bool add_assistant,
                               char *buf,
                               int32_t buf_len) {
    if (tmpl == nullptr || n_msg < 0) {
        return -1;
    }
    try {
        std::vector<llama_chat_message> messages;
        messages.reserve(static_cast<size_t>(n_msg));
        for (int32_t i = 0; i < n_msg; ++i) {
            llama_chat_message m;
            m.role = roles[i];
            m.content = contents[i];
            messages.push_back(m);
        }
        return llama_chat_apply_template(tmpl,
                                         messages.empty() ? nullptr : messages.data(),
                                         static_cast<size_t>(n_msg),
                                         add_assistant,
                                         buf,
                                         buf_len);
    } catch (const std::exception &) {
        return -1;
    } catch (...) {
        return -1;
    }
}

// ---------------------------------------------------------------------------
// Sampler chain
// ---------------------------------------------------------------------------

void *lc_sampler_chain_new(char *err, int32_t err_len) {
    try {
        llama_sampler_chain_params params = llama_sampler_chain_default_params();
        llama_sampler *chain = llama_sampler_chain_init(params);
        if (chain == nullptr) {
            writeError(err, err_len, "llama_sampler_chain_init returned NULL");
        }
        return chain;
    } catch (const std::exception &e) {
        writeException(err, err_len, e);
        return nullptr;
    } catch (...) {
        writeUnknownException(err, err_len);
        return nullptr;
    }
}

bool lc_sampler_add_grammar(void *chain,
                            const void *vocab,
                            const char *grammar,
                            const char *root,
                            char *err,
                            int32_t err_len) {
    if (chain == nullptr || vocab == nullptr) {
        writeError(err, err_len, "no sampler chain or vocabulary");
        return false;
    }
    try {
        llama_sampler *g = llama_sampler_init_grammar(static_cast<const llama_vocab *>(vocab),
                                                      grammar,
                                                      root);
        if (g == nullptr) {
            writeError(err, err_len,
                       "llama_sampler_init_grammar returned NULL (invalid grammar)");
            return false;
        }
        llama_sampler_chain_add(static_cast<llama_sampler *>(chain), g);
        return true;
    } catch (const std::exception &e) {
        writeException(err, err_len, e);
        return false;
    } catch (...) {
        writeUnknownException(err, err_len);
        return false;
    }
}

void lc_sampler_add_min_p(void *chain, float p, int32_t min_keep) {
    if (chain == nullptr) {
        return;
    }
    llama_sampler_chain_add(static_cast<llama_sampler *>(chain),
                            llama_sampler_init_min_p(p, static_cast<size_t>(min_keep)));
}

void lc_sampler_add_top_p(void *chain, float p, int32_t min_keep) {
    if (chain == nullptr) {
        return;
    }
    llama_sampler_chain_add(static_cast<llama_sampler *>(chain),
                            llama_sampler_init_top_p(p, static_cast<size_t>(min_keep)));
}

void lc_sampler_add_temp(void *chain, float t) {
    if (chain == nullptr) {
        return;
    }
    llama_sampler_chain_add(static_cast<llama_sampler *>(chain), llama_sampler_init_temp(t));
}

void lc_sampler_add_dist(void *chain, uint32_t seed) {
    if (chain == nullptr) {
        return;
    }
    llama_sampler_chain_add(static_cast<llama_sampler *>(chain), llama_sampler_init_dist(seed));
}

void lc_sampler_free(void *chain) {
    if (chain == nullptr) {
        return;
    }
    // Frees the chain and every sampler added to it.
    llama_sampler_free(static_cast<llama_sampler *>(chain));
}

int32_t lc_sampler_sample(void *chain, void *ctx, int32_t idx, char *err, int32_t err_len) {
    if (chain == nullptr || ctx == nullptr) {
        writeError(err, err_len, "no model loaded");
        return LC_SAMPLE_ERROR;
    }
    try {
        return llama_sampler_sample(static_cast<llama_sampler *>(chain),
                                    static_cast<llama_context *>(ctx),
                                    idx);
    } catch (const std::exception &e) {
        writeException(err, err_len, e);
        return LC_SAMPLE_ERROR;
    } catch (...) {
        writeUnknownException(err, err_len);
        return LC_SAMPLE_ERROR;
    }
}

bool lc_sampler_accept(void *chain, int32_t token, char *err, int32_t err_len) {
    if (chain == nullptr) {
        writeError(err, err_len, "no model loaded");
        return false;
    }
    try {
        llama_sampler_accept(static_cast<llama_sampler *>(chain), token);
        return true;
    } catch (const std::exception &e) {
        writeException(err, err_len, e);
        return false;
    } catch (...) {
        writeUnknownException(err, err_len);
        return false;
    }
}

uint32_t lc_default_seed(void) {
    return LLAMA_DEFAULT_SEED;
}

} // extern "C"
