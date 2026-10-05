# Claude Code against the local Ollama server.  Sourced from ~/.bashrc.d/.
#
# Ollama has served an Anthropic-compatible /v1/messages endpoint since v0.14.0,
# so Claude Code runs on a local model with three variables - `ollama launch
# claude` sets those and starts it, and this does the same thing in a shell
# function so the model and its context window travel together.
#
# THE FOURTH VARIABLE IS THE ONE THAT MATTERS. Claude Code does not know these
# model names:
#
#   "qwen3:8b" isn't described by this version's model catalog ...
#   auto-compact keeps this session within 200k tokens (the context window it
#   assumes)
#
# 200k against a model that loads at 40960, so a session would grow far past
# what the model can hold before auto-compact ever fired. CLAUDE_CODE_MAX_CONTEXT_TOKENS
# tells it the truth. `ollama ps` prints the real CONTEXT of a loaded model, and
# that - not the model's advertised maximum - is the number to use: asking for
# 65536 with OLLAMA_CONTEXT_LENGTH gave qwen3:8b 40960, because its trained
# context is 32k and Ollama will not stretch it the whole way.
#
# Measured on fedora-gaming00, RTX 5090: qwen3:8b runs at ~235 tok/s on the GPU.
# Thinking is ON by default in qwen3 and cost 1188 tokens against 34 for the
# same answer, so expect latency on small agent steps.
#
# WHAT IS NOT SUPPORTED, from Ollama's own documentation: hosted WebSearch and
# the advanced tool controls. Chat, file edits and tool calling do work - tool
# calls were verified returning stop_reason tool_use with well-formed input.
if command -v ollama >/dev/null 2>&1; then
    claude-local() {
        local model="${1:-qwen3-coder:30b}" ctx
        (( $# )) && shift

        # The loaded context if the model is up, else a sensible guess per model.
        ctx="$(ollama ps 2>/dev/null | awk -v m="$model" '$1 == m {print $(NF-1)}')"
        if [[ -z $ctx ]]; then
            case "$model" in
                qwen3:8b)     ctx=40960 ;;
                qwen3-coder*) ctx=65536 ;;
                *)            ctx=32768 ;;
            esac
        fi

        ANTHROPIC_BASE_URL=http://localhost:11434 \
        ANTHROPIC_AUTH_TOKEN=ollama \
        ANTHROPIC_API_KEY= \
        CLAUDE_CODE_MAX_CONTEXT_TOKENS="$ctx" \
        command claude --model "$model" "$@"
    }
fi
