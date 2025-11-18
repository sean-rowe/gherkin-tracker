# Local LLM Setup Guide

## Overview

The agent now supports running with a local LLM instead of Claude Code. This provides:

- **Cost savings**: No API costs
- **Privacy**: All code stays local
- **Speed**: GPU-accelerated inference (Metal on macOS, CUDA on Linux)
- **Offline capability**: Works without internet

## Quick Start

```bash
# 1. Run the setup script
cd /Users/srowe/Projects/gherkin-tracker
./setup_local_llm.sh

# 2. Use local LLM with agent
python3 agent_claude.py --project cuemap --use-local-llm --max-tasks 5
```

## Technology Stack

- **llama.cpp**: Fast C++ inference engine with GPU support
- **llama-cpp-python**: Python bindings for llama.cpp
- **Recommended models**:
  - **Qwen2.5-Coder 7B** (5.2 GB) - Best for code, requires 32GB+ RAM
  - **DeepSeek-Coder 6.7B** (4.8 GB) - Excellent for code, runs on 16GB RAM

## GPU Acceleration

### macOS (Metal)
Metal GPU acceleration is automatically enabled on macOS:
```bash
CMAKE_ARGS="-DLLAMA_METAL=on" pip install llama-cpp-python
```

Benefits:
- Offloads all layers to GPU
- ~10-20x faster than CPU
- Supports M1/M2/M3 chips

### Linux (NVIDIA CUDA)
For NVIDIA GPUs:
```bash
CMAKE_ARGS="-DLLAMA_CUDA=on" pip install llama-cpp-python
```

Requirements:
- NVIDIA GPU with CUDA support
- CUDA Toolkit installed

### CPU Only (Fallback)
If no GPU detected:
```bash
pip install llama-cpp-python
```

Performance: ~5-10 tokens/sec (slower)

## Manual Setup

### 1. Install Dependencies

```bash
# Install llama-cpp-python with GPU support (macOS)
CMAKE_ARGS="-DLLAMA_METAL=on" pip install llama-cpp-python

# Or for Linux with NVIDIA GPU
CMAKE_ARGS="-DLLAMA_CUDA=on" pip install llama-cpp-python

# Install other dependencies
pip install psutil
```

### 2. Download a Model

Create models directory:
```bash
mkdir -p ~/models
cd ~/models
```

#### Option A: Qwen2.5-Coder 7B (Recommended for 32GB+ RAM)
```bash
curl -L -o qwen2.5-coder-7b-instruct-q5_k_m.gguf \
  "https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q5_k_m.gguf"
```

- Size: 5.2 GB
- Quality: Excellent
- Context: 8K tokens
- Speed: ~20-30 tokens/sec (with GPU)

#### Option B: DeepSeek-Coder 6.7B (Recommended for 16-32GB RAM)
```bash
curl -L -o deepseek-coder-6.7b-instruct.Q5_K_M.gguf \
  "https://huggingface.co/TheBloke/deepseek-coder-6.7B-instruct-GGUF/resolve/main/deepseek-coder-6.7b-instruct.Q5_K_M.gguf"
```

- Size: 4.8 GB
- Quality: Very Good
- Context: 4K tokens
- Speed: ~25-35 tokens/sec (with GPU)

#### Option C: Codestral 22B (For High-End Systems, 64GB+ RAM)
```bash
curl -L -o codestral-22b-v0.1-q5_k_m.gguf \
  "https://huggingface.co/bartowski/Codestral-22B-v0.1-GGUF/resolve/main/Codestral-22B-v0.1-Q5_K_M.gguf"
```

- Size: 15 GB
- Quality: Best
- Context: 32K tokens
- Speed: ~10-15 tokens/sec (with GPU)

### 3. Test the Setup

```bash
cd /Users/srowe/Projects/gherkin-tracker
python3 local_llm.py
```

Expected output:
```
LOCAL LLM SETUP TEST
================================================================================

Recommended Configuration:
  Model: Qwen2.5-Coder-7B-Instruct (Q5_K_M)
  Size: 5.2 GB
  Quality: Excellent
  Speed: Fast (with GPU)
  GPU: Metal

Testing model...
✓ Model loaded successfully
✓ GPU acceleration enabled

Test prompt: Write a simple C++ function that adds two integers:

✓ Generation successful

Output:
--------------------------------------------------------------------------------
int add(int a, int b) {
    return a + b;
}
--------------------------------------------------------------------------------

✅ LOCAL LLM SETUP COMPLETE
```

## Usage

### Method 1: Command Line Flag
```bash
python3 agent_claude.py --project cuemap --use-local-llm
```

### Method 2: Environment Variable
```bash
export USE_LOCAL_LLM=1
python3 agent_claude.py --project cuemap
```

### Method 3: Automatic Fallback
The agent will automatically fall back to local LLM if Claude Code fails:
```bash
# If 'claude' command not found, uses local LLM
python3 agent_claude.py --project cuemap
```

## Configuration

### Model Path
Set custom model path:
```bash
export LOCAL_LLM_MODEL_PATH="$HOME/models/my-custom-model.gguf"
python3 agent_claude.py --project cuemap --use-local-llm
```

### GPU Layers
Control GPU offloading in `local_llm.py`:
```python
llm = LocalLLM(
    n_gpu_layers=-1,  # -1 = offload all to GPU
    n_ctx=8192,       # Context window
    n_threads=8       # CPU threads for non-GPU ops
)
```

### Generation Parameters
Adjust in `local_llm.py`:
```python
result = llm.generate(
    prompt,
    max_tokens=4096,     # Max output length
    temperature=0.1,     # Lower = more deterministic
    top_p=0.95          # Nucleus sampling
)
```

## Performance Comparison

| Setup                     | Speed       | Cost      | Quality     |
|---------------------------|-------------|-----------|-------------|
| Claude Code (Sonnet)      | Fast        | $$$       | Excellent   |
| Local LLM (GPU)           | Very Fast   | Free      | Very Good   |
| Local LLM (CPU)           | Slow        | Free      | Very Good   |

### Benchmark (on M2 MacBook Pro, 32GB RAM)

**Qwen2.5-Coder 7B (Q5_K_M) with Metal GPU:**
- Model load: ~3 seconds
- Generation speed: ~25 tokens/sec
- Memory usage: ~6 GB
- CPU usage: ~10% (mostly idle)

**Same model on CPU only:**
- Model load: ~3 seconds
- Generation speed: ~5 tokens/sec
- Memory usage: ~6 GB
- CPU usage: ~800% (all cores)

## Troubleshooting

### Issue: Model Loading Fails
**Symptom**: `Failed to load model: [Errno 2] No such file or directory`

**Solution**: Download the model first:
```bash
cd ~/models
curl -L -o deepseek-coder-6.7b-instruct.Q5_K_M.gguf \
  "https://huggingface.co/TheBloke/deepseek-coder-6.7B-instruct-GGUF/resolve/main/deepseek-coder-6.7b-instruct.Q5_K_M.gguf"
```

### Issue: No GPU Acceleration
**Symptom**: `⚠️  Running on CPU only (slower)`

**Solution**: Reinstall with GPU support:
```bash
# macOS
pip uninstall llama-cpp-python
CMAKE_ARGS="-DLLAMA_METAL=on" pip install llama-cpp-python

# Linux with NVIDIA GPU
pip uninstall llama-cpp-python
CMAKE_ARGS="-DLLAMA_CUDA=on" pip install llama-cpp-python
```

### Issue: Out of Memory
**Symptom**: `Failed to allocate memory`

**Solution**: Use a smaller model or reduce context:
```python
# In local_llm.py, reduce context window
llm = LocalLLM(n_ctx=4096)  # Instead of 8192
```

Or use a smaller quantized model (Q4_K_M instead of Q5_K_M).

### Issue: Slow Generation
**Symptom**: <5 tokens/sec

**Possible causes**:
1. Running on CPU instead of GPU
2. Model too large for system
3. Context window too large

**Solutions**:
1. Verify GPU acceleration is enabled (check setup)
2. Use smaller model (DeepSeek 6.7B instead of Codestral 22B)
3. Reduce context window to 4096

## Hybrid Mode

You can use Claude Code for complex tasks and local LLM for simple ones:

```python
# In agent_claude.py, modify run_claude():
if complexity_score < 0.5:
    # Simple task - use local LLM
    return self.local_llm.generate(prompt)
else:
    # Complex task - use Claude Code
    return subprocess.run(['claude', '-p', prompt])
```

## Best Practices

1. **Start with local LLM for testing**: Verify the setup works before scaling
2. **Use GPU acceleration**: 10-20x faster than CPU
3. **Choose appropriate model**: Bigger isn't always better
4. **Monitor memory usage**: Ensure model fits in RAM with headroom
5. **Adjust temperature**: Lower (0.1-0.3) for code, higher (0.7-0.9) for creativity

## Cost Analysis

### Claude Code (100 tasks/day for 30 days)
- ~3,000 tasks/month
- ~15M tokens input + 10M tokens output
- Cost: ~$150-300/month

### Local LLM (same workload)
- One-time setup: ~1 hour
- Electricity cost: ~$5-10/month (GPU usage)
- **Savings: ~$140-290/month**

## Recommended Workflow

1. **Development/Testing**: Use local LLM
   ```bash
   python3 agent_claude.py --project cuemap --use-local-llm --max-tasks 10
   ```

2. **Production/Quality**: Use Claude Code
   ```bash
   python3 agent_claude.py --project cuemap --max-tasks 100
   ```

3. **Overnight Runs**: Use local LLM (cost-effective)
   ```bash
   nohup python3 agent_claude.py --project cuemap --use-local-llm &
   ```

## Summary

✅ **DO**:
- Use GPU acceleration (Metal/CUDA)
- Choose appropriate model for your RAM
- Test with small batches first
- Monitor memory and performance

❌ **DON'T**:
- Run CPU-only in production (too slow)
- Use models larger than your RAM
- Forget to set temperature low for code (0.1-0.3)
- Skip the test script before using in production

The local LLM provides excellent code quality at a fraction of the cost, making it ideal for development and testing workflows.
