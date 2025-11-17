#!/usr/bin/env python3
"""
Benchmark script for local LLM performance testing.
Measures model loading time, generation speed, and GPU utilization.
"""

import sys
import time
import logging
from pathlib import Path

# Add current directory to path
sys.path.insert(0, str(Path(__file__).parent))

from local_llm import LocalLLM, get_recommended_model_config

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)-8s | %(message)s'
)


def benchmark_model(model_path: str, n_gpu_layers: int = -1):
    """
    Run comprehensive benchmark of local LLM.

    Args:
        model_path: Path to GGUF model
        n_gpu_layers: GPU layers (-1 = all)
    """
    print("=" * 80)
    print("LOCAL LLM PERFORMANCE BENCHMARK")
    print("=" * 80)

    # Initialize
    print("\n1. Initializing LLM...")
    llm = LocalLLM(
        model_path=model_path,
        n_gpu_layers=n_gpu_layers,
        n_ctx=8192
    )

    # Test 1: Model Loading Time
    print("\n2. Testing model load time...")
    load_start = time.time()
    if not llm.load_model():
        print("❌ Failed to load model")
        return
    load_time = time.time() - load_start
    print(f"   ✓ Model loaded in {load_time:.2f} seconds")

    # Test 2: Short Generation (100 tokens)
    print("\n3. Testing short generation (100 tokens)...")
    test_prompt = "Write a C++ function that validates an email address:"

    gen_start = time.time()
    result = llm.generate(test_prompt, max_tokens=100, temperature=0.1)
    gen_time = time.time() - gen_start

    if result['success']:
        output_length = len(result['output'])
        # Rough token count (chars / 4 is approximate)
        approx_tokens = output_length / 4
        tokens_per_sec = approx_tokens / gen_time if gen_time > 0 else 0

        print(f"   ✓ Generated in {gen_time:.2f} seconds")
        print(f"   ✓ Output: {output_length} chars (~{int(approx_tokens)} tokens)")
        print(f"   ✓ Speed: ~{tokens_per_sec:.1f} tokens/second")
        print(f"\n   Output preview:")
        print(f"   {'-' * 76}")
        preview = result['output'][:200]
        print(f"   {preview}{'...' if len(result['output']) > 200 else ''}")
        print(f"   {'-' * 76}")
    else:
        print(f"   ❌ Generation failed: {result['error']}")

    # Test 3: Medium Generation (500 tokens)
    print("\n4. Testing medium generation (500 tokens)...")
    test_prompt = """Write a C++ class for a binary search tree with the following methods:
- insert(value)
- find(value)
- remove(value)
Include proper memory management."""

    gen_start = time.time()
    result = llm.generate(test_prompt, max_tokens=500, temperature=0.1)
    gen_time = time.time() - gen_start

    if result['success']:
        output_length = len(result['output'])
        approx_tokens = output_length / 4
        tokens_per_sec = approx_tokens / gen_time if gen_time > 0 else 0

        print(f"   ✓ Generated in {gen_time:.2f} seconds")
        print(f"   ✓ Output: {output_length} chars (~{int(approx_tokens)} tokens)")
        print(f"   ✓ Speed: ~{tokens_per_sec:.1f} tokens/second")
    else:
        print(f"   ❌ Generation failed: {result['error']}")

    # Test 4: Long Generation (1000 tokens)
    print("\n5. Testing long generation (1000 tokens)...")
    test_prompt = """Implement a complete C++ class for a thread-safe queue with the following requirements:
- Support for multiple producers and consumers
- Blocking wait when queue is empty
- Maximum capacity with blocking when full
- Exception safety
- Move semantics support
Include full implementation with comments."""

    gen_start = time.time()
    result = llm.generate(test_prompt, max_tokens=1000, temperature=0.1)
    gen_time = time.time() - gen_start

    if result['success']:
        output_length = len(result['output'])
        approx_tokens = output_length / 4
        tokens_per_sec = approx_tokens / gen_time if gen_time > 0 else 0

        print(f"   ✓ Generated in {gen_time:.2f} seconds")
        print(f"   ✓ Output: {output_length} chars (~{int(approx_tokens)} tokens)")
        print(f"   ✓ Speed: ~{tokens_per_sec:.1f} tokens/second")
    else:
        print(f"   ❌ Generation failed: {result['error']}")

    # Summary
    print("\n" + "=" * 80)
    print("BENCHMARK SUMMARY")
    print("=" * 80)
    print(f"Model: {Path(model_path).name}")
    print(f"GPU Layers: {n_gpu_layers} (-1 = all)")
    print(f"Load Time: {load_time:.2f}s")
    print(f"\nThis benchmark used character-based token estimation (chars/4).")
    print("Actual token counts may vary based on tokenizer.")
    print("=" * 80)

    # Cleanup
    llm.unload_model()


if __name__ == '__main__':
    print("\nDetecting system configuration...")
    config = get_recommended_model_config()

    print("\nSystem Information:")
    print(f"  GPU: {config['gpu_type']}")
    print(f"  GPU Enabled: {config['gpu_enabled']}")
    print(f"  Recommended Model: {config['model_name']}")
    print(f"  Model Size: {config['size_gb']} GB")
    print(f"  Expected Quality: {config['quality']}")
    print(f"  Expected Speed: {config['speed']}")

    model_path = config['model_path']

    if not Path(model_path).exists():
        print(f"\n❌ Model not found: {model_path}")
        print("\nDownload the model first:")
        print(f"  mkdir -p ~/models")
        print(f"  curl -L -o '{model_path}' '{config['download_url']}'")
        sys.exit(1)

    print(f"\nUsing model: {model_path}")
    print(f"File size: {Path(model_path).stat().st_size / (1024**3):.1f} GB")

    # Run benchmark
    benchmark_model(
        model_path=model_path,
        n_gpu_layers=config['n_gpu_layers']
    )

    print("\n✅ Benchmark complete!")
