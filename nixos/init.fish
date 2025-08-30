function serve-llm
    set model_gguf_path $argv[1]
    set model_name (basename $argv[1] .gguf)

    if test -z "$model_gguf_path"
        echo "Error: Model path not provided" >&2
        echo "Usage: serve-llm <path-to-model.gguf> <context-length> [additional arguments for llama-server]" >&2
        return 1
    end

    if not test -f "$model_gguf_path"
        echo "Error: Model file not found at: $model_gguf_path" >&2
        return 2
    end

    set context_length $argv[2]

    if test -z "$context_length"
        echo "Error: Context length not provided" >&2
        return 3
    end

    if test "$context_length" -lt 0
        echo "Error: Context length must be >= 0" >&2
        return 4
    end

    if test "$context_length" -gt 0
        echo "Serving $model_name with $context_length tokens context, additional flags: $argv[3..-1]"
    else
        echo "Serving $model_name with maximum available context, additional flags: $argv[3..-1]"
    end

    llama-server \
        --ctx-size $context_length \
        --model $model_gguf_path \
        --alias $model_name \
        $argv[3..-1]
end

function serve-llm-jinja
    serve-llm $argv[1] $argv[2] \
        --jinja \
        $argv[3..-1]
end

function serve-llm-jinja-ext
    set template_path $argv[3]

    if test -z "$template_path"
        echo "Error: Chat template path not provided" >&2
        echo "Usage: serve-llm-jinja-ext <path-to-model.gguf> <context-length> <chat-template.jinja> [additional arguments for llama-server]" >&2
        return 1
    end

    if not test -f "$template_path"
        echo "Error: Chat template file not found at: $template_path" >&2
        return 10
    end

    serve-llm-jinja $argv[1] $argv[2] \
        --chat-template-file $template_path \
        $argv[4..-1]
end

function serve-llm-qwen
    serve-llm-jinja $argv[1] $argv[2] \
        --temp 0.6 \
        --top-p 0.95 \
        --top-k 20 \
        --min-p 0 \
        --presence-penalty 1.5 \
        $argv[3..-1]
end

function serve-llm-qwen-ext
    serve-llm-jinja-ext $argv[1] $argv[2] $argv[3] \
        --temp 0.6 \
        --top-p 0.95 \
        --top-k 20 \
        --min-p 0 \
        --presence-penalty 1.5 \
        $argv[4..-1]
end

function serve-llm-qwen-coder
    set -gx OPENAI_MODEL Qwen3-Coder-30B-A3B-Instruct-UD-Q3_K_XL
    serve-llm-jinja-ext "$HOME/llms/Qwen3-Coder-30B-A3B-Instruct-UD-Q3_K_XL.gguf" \
        81920 \
        "$HOME/llms/repos/Qwen3-Coder-30B-A3B-Instruct/chat-template.jinja" \
        --n-cpu-moe 3 \
        --cache-type-k q8_0 \
        --cache-type-v q8_0 \
        --temp 0.7 \
        --top-p 0.8 \
        --top-k 20 \
        --repeat-penalty 1.05
end

function serve-llm-gpt-oss
    serve-llm-jinja \
        "$HOME/llms/gpt-oss-20b.auto.gguf" \
        0 \
        --temp 1.0 \
        --top-p 1.0 \
        --top-k 100 \
        --min-p 0.01
end

function serve-llm-mistral
    serve-llm-jinja \
        "$HOME/llms/Mistral-Small-3.2-24B-Instruct-2506-UD-Q4_K_XL.gguf" \
        32768 \
        --temp 0.15 \
        --cache-type-k q8_0 \
        --cache-type-v q8_0
end
