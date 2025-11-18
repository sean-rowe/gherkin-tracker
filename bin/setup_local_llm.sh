#!/bin/bash
# Setup script for local LLM with GPU acceleration

set -e

echo "========================================="
echo "Local LLM Setup"
echo "========================================="

# Detect platform
PLATFORM=$(uname)
echo "Platform: $PLATFORM"

# Create models directory
MODELS_DIR="$HOME/models"
mkdir -p "$MODELS_DIR"
echo "Models directory: $MODELS_DIR"

# Install llama-cpp-python with GPU support
echo ""
echo "Installing llama-cpp-python..."

if [[ "$PLATFORM" == "Darwin" ]]; then
    echo "macOS detected - checking for Metal support..."

    # Check if Metal is available
    if system_profiler SPDisplaysDataType | grep -q "Metal Support: Metal"; then
        GPU_NAME=$(system_profiler SPDisplaysDataType | grep "Chipset Model:" | head -1 | cut -d: -f2 | xargs)
        echo "✓ Metal GPU detected: $GPU_NAME"
        echo "Installing llama-cpp-python with Metal support..."
        CMAKE_ARGS="-DLLAMA_METAL=on" pip install --upgrade llama-cpp-python
        echo "✓ Installed with Metal GPU acceleration"
    else
        echo "⚠️  No Metal support detected"
        echo "Installing CPU-only version..."
        pip install --upgrade llama-cpp-python
        echo "⚠️  Installed CPU-only version"
    fi

elif command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA GPU detected - installing with CUDA support..."
    CMAKE_ARGS="-DLLAMA_CUDA=on" pip install --upgrade llama-cpp-python
    echo "✓ Installed with CUDA GPU acceleration"

else
    echo "No GPU detected - installing CPU-only version (slower)..."
    pip install --upgrade llama-cpp-python
    echo "⚠️  Installed CPU-only version"
fi

# Install other dependencies
echo ""
echo "Installing other dependencies..."
pip install psutil

echo ""
echo "========================================="
echo "Download Recommended Model"
echo "========================================="

# Recommend model based on RAM
TOTAL_RAM_GB=$(python3 -c "import psutil; print(int(psutil.virtual_memory().total / (1024**3)))")
echo "System RAM: ${TOTAL_RAM_GB} GB"

if [ "$TOTAL_RAM_GB" -ge 32 ]; then
    MODEL_NAME="qwen2.5-coder-7b-instruct-q5_k_m.gguf"
    MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q5_k_m.gguf"
    MODEL_SIZE="5.2 GB"
    echo "Recommended model: Qwen2.5-Coder 7B (excellent code performance)"
else
    MODEL_NAME="deepseek-coder-6.7b-instruct.Q5_K_M.gguf"
    MODEL_URL="https://huggingface.co/TheBloke/deepseek-coder-6.7B-instruct-GGUF/resolve/main/deepseek-coder-6.7b-instruct.Q5_K_M.gguf"
    MODEL_SIZE="4.8 GB"
    echo "Recommended model: DeepSeek-Coder 6.7B (good code performance, smaller)"
fi

MODEL_PATH="$MODELS_DIR/$MODEL_NAME"

if [ -f "$MODEL_PATH" ]; then
    echo "✓ Model already downloaded: $MODEL_PATH"
else
    echo ""
    echo "Model: $MODEL_NAME ($MODEL_SIZE)"
    echo "Download to: $MODEL_PATH"
    echo ""
    read -p "Download model now? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Downloading model (this may take a while)..."
        curl -L --progress-bar -o "$MODEL_PATH" "$MODEL_URL"
        echo "✓ Model downloaded successfully"
    else
        echo "Skipped model download"
        echo "To download later, run:"
        echo "  curl -L -o '$MODEL_PATH' '$MODEL_URL'"
    fi
fi

# Test the setup
echo ""
echo "========================================="
echo "Testing Setup"
echo "========================================="

if [ -f "$MODEL_PATH" ]; then
    echo "Running test..."
    cd "$(dirname "$0")/.."
    python3 -m gherkin_tracker.infrastructure.local_llm

    if [ $? -eq 0 ]; then
        echo ""
        echo "========================================="
        echo "✅ SETUP COMPLETE"
        echo "========================================="
        echo ""
        echo "To use local LLM with agent:"
        echo "  python3 agent_claude.py --project cuemap --use-local-llm"
        echo ""
        echo "Or set environment variable:"
        echo "  export USE_LOCAL_LLM=1"
        echo "  python3 agent_claude.py --project cuemap"
    else
        echo "❌ Test failed - check errors above"
        exit 1
    fi
else
    echo "⚠️  Model not downloaded - setup incomplete"
    echo ""
    echo "To complete setup, download the model:"
    echo "  curl -L -o '$MODEL_PATH' '$MODEL_URL'"
    echo ""
    echo "Then test with:"
    echo "  python3 local_llm.py"
fi
