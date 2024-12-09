#!/bin/bash

JSON_FILE="benchmark_results.json"
START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
RESULTS="{}"

trap 'echo "Script interrupted. Cleaning up..."; exit 1' SIGINT SIGTERM

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1"
}

append_to_results() {
    local key="$1"
    local value="$2"
    RESULTS=$(echo "$RESULTS" | jq --argjson val "$value" ". += {\"$key\": \$val}")
}

collect_system_info() {
    log "Collecting system information..."
    ARCH=$(lscpu | awk -F: '/Architecture/ {print $2}' | xargs)
    CORES=$(lscpu | awk -F: '/^CPU\(s\)/ {print $2}' | xargs)
    MODEL=$(lscpu | awk -F: '/Model name/ {print $2}' | xargs)

    # Attempt detailed GPU detection if nvidia-smi available
    if command -v nvidia-smi &> /dev/null; then
        GPU_VENDOR="NVIDIA"
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
        GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1)
        if [ -n "$GPU_MODEL" ]; then
            GPU_INFO="$GPU_VENDOR $GPU_MODEL (${GPU_MEM}MiB)"
        else
            # fallback if unexpected nvidia-smi output
            GPU_LINE=$(lspci | grep -i -E "vga|3d|display" | head -n1)
            if [ -n "$GPU_LINE" ]; then
                GPU_INFO=$(echo "$GPU_LINE" | awk -F': ' '{print $2}' | xargs)
            else
                GPU_INFO="None detected"
            fi
        fi
    else
        # fallback if no nvidia-smi
        GPU_LINE=$(lspci | grep -i -E "vga|3d|display" | head -n1)
        if [ -n "$GPU_LINE" ]; then
            GPU_INFO=$(echo "$GPU_LINE" | awk -F': ' '{print $2}' | xargs)
        else
            GPU_INFO="None detected"
        fi
    fi

    log "ARCH: $ARCH"
    log "CORES: $CORES"
    log "MODEL: $MODEL"
    log "GPU: ${GPU_INFO:-None detected}"

    SYSTEM_INFO=$(jq -n \
        --arg arch "$ARCH" \
        --arg cores "$CORES" \
        --arg model "$MODEL" \
        --arg gpu "${GPU_INFO:-None detected}" \
        '{"architecture": $arch, "cpu_cores": $cores, "cpu_model": $model, "gpu_info": $gpu}')
    append_to_results "system_info" "$SYSTEM_INFO"
}

benchmark_cpu() {
    log "Running CPU benchmark: Calculating Pi to measure decimal places computed..."
    CORES=$(nproc)
    START=$(date +%s)
    DECIMAL_PLACES=0

    for i in $(seq 1 "$CORES"); do
        (
            COUNT=0
            while true; do
                CURRENT_TIME=$(date +%s)
                ELAPSED=$((CURRENT_TIME - START))
                if [ "$ELAPSED" -ge 30 ]; then
                    break
                fi
                echo "scale=5000; 4*a(1)" | bc -lq > /dev/null
                COUNT=$((COUNT + 5000))
            done
            echo "$COUNT" >> /tmp/cpu_benchmark_results
        ) &
    done

    wait
    END=$(date +%s)
    CPU_DURATION=$((END - START))

    if [ -f /tmp/cpu_benchmark_results ]; then
        DECIMAL_PLACES=$(awk '{sum += $1} END {print sum}' /tmp/cpu_benchmark_results)
        rm -f /tmp/cpu_benchmark_results
    fi

    CPU_METRIC=$((DECIMAL_PLACES / CPU_DURATION))
    CPU_INFO=$(jq -n \
        --argjson duration "$CPU_DURATION" \
        --argjson places "$DECIMAL_PLACES" \
        --argjson metric "$CPU_METRIC" \
        '{"duration_sec": $duration, "decimal_places": $places, "metric": $metric, "unit": "decimal_places/sec"}')
    append_to_results "cpu" "$CPU_INFO"
    log "CPU benchmark completed: $DECIMAL_PLACES decimal places in $CPU_DURATION seconds ($CPU_METRIC decimal_places/sec)."
}

benchmark_ram() {
    log "Running RAM benchmark..."
    START=$(date +%s)
    RAM_THROUGHPUT=$(dd if=/dev/zero of=/dev/null bs=1M count=1000 2>&1 | awk '/copied/ {print $(NF-1)" "$NF}')
    END=$(date +%s)
    RAM_DURATION=$((END - START))
    log "RAM benchmark raw output: $RAM_THROUGHPUT"
    RAM_INFO=$(jq -n --arg speed "$RAM_THROUGHPUT" '{"throughput_gb_s": $speed}')
    append_to_results "ram" "$RAM_INFO"
}

benchmark_storage() {
    log "Running storage benchmark..."
    # Reduced size to 5GB
    TEMP_FILE=$(mktemp)
    WRITE_OUTPUT=$(dd if=/dev/urandom of="$TEMP_FILE" bs=1M count=5120 oflag=direct 2>&1)
    rm -f "$TEMP_FILE"
    WRITE_SPEED=$(echo "$WRITE_OUTPUT" | awk '/copied/ {print $(NF-1)" "$NF}')
    log "Parsed write speed: $WRITE_SPEED"
    STORAGE_INFO=$(jq -n --arg speed "$WRITE_SPEED" '{"write_speed_gb_s": $speed}')
    append_to_results "storage" "$STORAGE_INFO"
}

benchmark_gpu() {
    log "Detecting GPU and running appropriate benchmark..."
    # Original logic: glmark2-es2 first
    if command -v glmark2-es2 &> /dev/null; then
        log "Running OpenGL benchmark using glmark2-es2 (shading test only)..."
        GLMARK_OUTPUT=$(glmark2-es2 --off-screen -b shading 2>&1 | awk '/Score/ {print $NF}')
        GPU_INFO=$(jq -n --arg status "completed" --arg score "$GLMARK_OUTPUT" '{"status": $status, "score": $score}')
        append_to_results "gpu" "$GPU_INFO"
        log "GPU benchmark completed: OpenGL Shading Score = $GLMARK_OUTPUT"
    elif command -v vulkaninfo &> /dev/null; then
        log "Running Vulkan benchmark (future implementation)..."
        append_to_results "gpu" '{"status": "vulkan not implemented yet"}'
    elif command -v glxgears &> /dev/null; then
        log "Running OpenGL benchmark using glxgears for 30 seconds..."
        GLX_OUT=$(timeout 30s glxgears -info 2>&1 || true)

        # Try parsing "frames in" lines first:
        FRAMES_LINE=$(echo "$GLX_OUT" | grep "frames in")
        if [ -n "$FRAMES_LINE" ]; then
            # Format: "300 frames in 5.0 seconds = 60.0 FPS"
            FRAMES=$(echo "$FRAMES_LINE" | awk '{print $1}')
            SECS=$(echo "$FRAMES_LINE" | awk '{print $4}')
            if [ "$SECS" != "0" ]; then
                FPS=$(awk -v f="$FRAMES" -v s="$SECS" 'BEGIN{print f/s}')
            fi
        fi

        # If no FPS from frames line, try a direct FPS line
        if [ -z "$FPS" ]; then
            FPS=$(echo "$GLX_OUT" | grep -m1 FPS | awk '{print $NF}')
            # Ensure FPS is numeric
            [[ $FPS =~ ^[0-9.]+$ ]] || FPS=""
        fi

        if [ -n "$FPS" ]; then
            GPU_INFO=$(jq -n --arg status "completed" --arg fps "$FPS" '{"status": $status, "fps": $fps}')
            append_to_results "gpu" "$GPU_INFO"
            log "GPU benchmark completed: OpenGL FPS = $FPS"
        else
            GPU_INFO=$(jq -n --arg status "completed" '{"status": $status, "fps":"", "note":"No numeric FPS found"}')
            append_to_results "gpu" "$GPU_INFO"
            log "GPU benchmark completed: No numeric FPS reported."
        fi
    else
        log "No GPU benchmarking tools available."
        append_to_results "gpu" '{"status": "no suitable GPU tools found"}'
    fi
}

compile_results() {
    log "Compiling results into JSON..."
    RESULTS=$(echo "$RESULTS" | jq --arg start_time "$START_TIME" '. + {"start_time":$start_time}')
    echo "$RESULTS" | jq . > "$JSON_FILE" || {
        log "Failed to write results to $JSON_FILE. Check JSON structure."
        exit 1
    }
    log "Results saved to $JSON_FILE"
}

print_summary() {
    log "Benchmark Summary:"
    echo "--------------------------------------------------"
    echo "System Information:"
    SYS_ARCH=$(echo "$RESULTS" | jq -r '.system_info.architecture')
    SYS_CORES=$(echo "$RESULTS" | jq -r '.system_info.cpu_cores')
    SYS_MODEL=$(echo "$RESULTS" | jq -r '.system_info.cpu_model')
    SYS_GPU=$(echo "$RESULTS" | jq -r '.system_info.gpu_info')

    echo "Architecture: $SYS_ARCH"
    echo "CPU Cores: $SYS_CORES"
    echo "CPU Model: $SYS_MODEL"
    echo "GPU Info: $SYS_GPU"
    echo "--------------------------------------------------"

    echo "CPU Benchmark:"
    CPU_DURATION=$(echo "$RESULTS" | jq -r '.cpu.duration_sec')
    CPU_PLACES=$(echo "$RESULTS" | jq -r '.cpu.decimal_places')
    CPU_METRIC=$(echo "$RESULTS" | jq -r '.cpu.metric')
    echo "Duration (sec): $CPU_DURATION"
    echo "Decimal Places: $CPU_PLACES"
    echo "Metric: $CPU_METRIC decimal_places/sec"
    echo "--------------------------------------------------"

    echo "RAM Benchmark:"
    RAM_SPEED=$(echo "$RESULTS" | jq -r '.ram.throughput_gb_s')
    echo "Throughput: $RAM_SPEED"
    echo "--------------------------------------------------"

    echo "Storage Benchmark:"
    STORAGE_SPEED=$(echo "$RESULTS" | jq -r '.storage.write_speed_gb_s')
    echo "Write Speed: $STORAGE_SPEED"
    echo "--------------------------------------------------"

    echo "GPU Benchmark:"
    GPU_STATUS=$(echo "$RESULTS" | jq -r '.gpu.status')
    GPU_SCORE=$(echo "$RESULTS" | jq -r '.gpu.score? // empty')
    GPU_FPS=$(echo "$RESULTS" | jq -r '.gpu.fps? // empty')
    
    echo "Status: $GPU_STATUS"
    if [ -n "$GPU_SCORE" ]; then
        if [ "$GPU_SCORE" = "" ]; then
            echo "No numeric GPU metric reported."
        else
            echo "Shading Score: $GPU_SCORE"
        fi
    elif [ -n "$GPU_FPS" ]; then
        if [ "$GPU_FPS" = "" ]; then
            echo "No numeric GPU metric reported."
        else
            echo "FPS: $GPU_FPS"
        fi
    else
        echo "No numeric GPU metric reported."
    fi
    echo "--------------------------------------------------"
}

log "Starting benchmarking script..."
RESULTS=${RESULTS:-"{}"}
collect_system_info
benchmark_cpu
benchmark_ram
benchmark_storage
benchmark_gpu
compile_results
print_summary
log "Script completed."

