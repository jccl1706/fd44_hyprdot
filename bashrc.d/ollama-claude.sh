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
# WHY qwen3.8:27b IS THE DEFAULT, measured on fedora-gaming00 (RTX 5090) rather
# than taken from release notes. Against qwen3-coder:30b on the same three tasks:
#
#   described bugs with tests   both passed; qwen3.8 in a 6-line diff against 13,
#                               and it actually ran the tests rather than saying
#                               they "should" pass
#   an UNDESCRIBED failure      qwen3-coder guarded the crash and missed the
#                               second bug corrupting the data that caused it;
#                               qwen3.8 found both
#   a repo-wide question        qwen3-coder invented a Hyprland option in a script
#                               that has none; qwen3.8 invented nothing and found
#                               a real inconsistency nobody had asked it to look
#                               for
#
# It costs speed - ~100 tok/s against ~287, being a dense 27B where qwen3-coder is
# a mixture-of-experts with about 3B active - and uses 7 GiB less VRAM. Being
# wrong faster is not worth anything, so this is the trade taken.
#
# Thinking is on in this family. qwen3:8b spent 1188 tokens where 34 would do;
# qwen3.8 spent about 65 words on the same question, so the overhead is real but
# no longer the dominant cost.
#
# WHAT IS NOT SUPPORTED, from Ollama's own documentation: hosted WebSearch and
# the advanced tool controls. Chat, file edits and tool calling do work - tool
# calls were verified returning stop_reason tool_use with well-formed input.
if command -v ollama >/dev/null 2>&1; then
    claude-local() {
        local model="${OLLAMA_CLAUDE_MODEL:-qwen3.8:27b}" ctx

        # A FIRST ARGUMENT IS A MODEL ONLY IF IT IS NOT A FLAG. Taking $1 as the
        # model unconditionally meant `claude-local -p "..."` passed `-p` as the
        # model name and Claude Code answered "API Error: 400 invalid model
        # name" - the flag had been eaten, and nothing said so.
        if [[ -n ${1-} && ${1-} != -* ]]; then
            model="$1"
            shift
        fi

        # THE LOADED CONTEXT, FROM THE API AND NOT FROM `ollama ps`. The table's
        # UNTIL column is several words ("4 minutes from now"), so counting
        # fields from the end lands in the middle of it - the first version of
        # this read `from` and handed that to Claude Code, which silently
        # ignored it and went back to assuming 200k. /api/ps gives
        # context_length as a number.
        ctx="$(curl -fsS --max-time 2 http://localhost:11434/api/ps 2>/dev/null |
            python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit
for m in d.get("models", []):
    if m.get("name") == sys.argv[1] and m.get("context_length"):
        print(m["context_length"])
        break
' "$model" 2>/dev/null)"

        # Anything that is not a plain number is no answer at all.
        [[ $ctx =~ ^[0-9]+$ ]] || ctx=""

        if [[ -z $ctx ]]; then
            case "$model" in
                qwen3:8b)     ctx=40960 ;;
                qwen3.8*)     ctx=131072 ;;
                qwen3.6*)     ctx=131072 ;;
                qwen3-coder*) ctx=131072 ;;
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
