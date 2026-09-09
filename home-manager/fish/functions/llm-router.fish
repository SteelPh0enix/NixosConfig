function llm-router
    llama-server \
        --models-dir /mnt/SSD/LLMs/llama-models/ \
        --models-preset /mnt/SSD/LLMs/llama-models.ini \
        --host 0.0.0.0 \
        --port 51536 \
        --models-max 1 \
        --load-mode mlock \
        --webui \
        --metrics \
        --props \
        --slots
end
