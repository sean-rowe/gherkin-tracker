#!/usr/bin/env python3
"""
Local LLM Interface using llama-cpp-python with GPU acceleration
Provides fallback from Claude Code to local models when needed
"""

import os
import logging
from typing import Optional, Dict
from pathlib import Path


class LocalLLM:
    """
    Interface to local LLM using llama-cpp-python.

    Supports GPU acceleration:
    - macOS: Metal (via n_gpu_layers)
    - Linux/Windows: CUDA (via n_gpu_layers)

    No Ollama required - direct model loading.
    """

    # Supported models with their configurations
    MODELS = {
        'deepseek-coder-6.7b': {
            'path': str(Path.home() / 'models' / 'deepseek-coder-6.7b-instruct.Q5_K_M.gguf'),
            'n_ctx': 8192,
            'prompt_format': 'chatml'
        },
        'kimi-k2-instruct': {
            'path': str(Path.home() / 'models' / 'kimi-k2' / 'instruct-2bit' / 'Kimi-K2-Instruct-UD-Q2_K_XL.gguf'),
            'n_ctx': 32768,  # 128K capable, but 32K for memory safety
            'prompt_format': 'chatml'
        },
        'kimi-k2-thinking': {
            'path': str(Path.home() / 'models' / 'kimi-k2' / 'thinking-4bit' / 'moonshotai_Kimi-K2-Thinking-Q4_K_M.gguf'),
            'n_ctx': 32768,  # 128K capable, but 32K for memory safety
            'prompt_format': 'chatml'
        }
    }

    def __init__(self,
                 model_path: Optional[str] = None,
                 model_name: Optional[str] = None,
                 n_gpu_layers: int = 0,   # 0 = CPU only (GPU not compatible with older AMD)
                 n_ctx: Optional[int] = None,
                 n_threads: int = 10):     # CPU threads (use all cores)
        """
        Initialize local LLM.

        Args:
            model_path: Path to GGUF model file. If None, uses model_name or env.
            model_name: Model preset ('deepseek-coder-6.7b', 'kimi-k2-instruct', 'kimi-k2-thinking')
            n_gpu_layers: Number of layers to offload to GPU (-1 = all, 0 = CPU)
            n_ctx: Context window size (overrides model default)
            n_threads: CPU threads for parts not on GPU
        """
        # Determine model configuration
        if model_name and model_name in self.MODELS:
            config = self.MODELS[model_name]
            self.model_path = model_path or config['path']
            self.n_ctx = n_ctx or config['n_ctx']
            self.prompt_format = config['prompt_format']
            self.model_name = model_name
        else:
            self.model_path = model_path or os.getenv(
                'LOCAL_LLM_MODEL_PATH',
                str(Path.home() / 'models' / 'deepseek-coder-6.7b-instruct.Q5_K_M.gguf')
            )
            self.n_ctx = n_ctx or 8192
            self.prompt_format = 'chatml'
            self.model_name = 'custom'

        self.n_gpu_layers = n_gpu_layers
        self.n_threads = n_threads
        self.llm = None

        logging.info(f"LocalLLM configured: {self.model_name} (ctx={self.n_ctx})")

        # Check if llama-cpp-python is installed
        try:
            from llama_cpp import Llama
            self.Llama = Llama
        except ImportError:
            logging.error("llama-cpp-python not installed!")
            logging.error("Install with GPU support:")
            logging.error("  macOS Metal: CMAKE_ARGS='-DLLAMA_METAL=on' pip install llama-cpp-python")
            logging.error("  Linux CUDA:  CMAKE_ARGS='-DLLAMA_CUDA=on' pip install llama-cpp-python")
            raise

    def load_model(self) -> bool:
        """
        Load the model into memory.

        Returns:
            True if successful, False otherwise
        """
        if self.llm is not None:
            logging.info("Model already loaded")
            return True

        if not Path(self.model_path).exists():
            logging.error(f"Model file not found: {self.model_path}")
            logging.info("Download a model:")
            logging.info("  DeepSeek Coder 6.7B (recommended for code):")
            logging.info("    https://huggingface.co/TheBloke/deepseek-coder-6.7B-instruct-GGUF")
            logging.info("  Codestral 22B (larger, more capable):")
            logging.info("    https://huggingface.co/bartowski/Codestral-22B-v0.1-GGUF")
            logging.info("  Qwen2.5-Coder 7B (excellent code performance):")
            logging.info("    https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF")
            return False

        try:
            logging.info(f"Loading model: {self.model_name}")
            logging.info(f"Path: {self.model_path}")
            logging.info(f"GPU layers: {self.n_gpu_layers} (-1 = all, 0 = CPU)")
            logging.info(f"Context window: {self.n_ctx} tokens")

            self.llm = self.Llama(
                model_path=self.model_path,
                n_gpu_layers=self.n_gpu_layers,  # GPU acceleration
                n_ctx=self.n_ctx,                # Context window
                n_threads=self.n_threads,        # CPU threads
                verbose=False                    # Suppress llama.cpp logs
            )

            logging.info("✓ Model loaded successfully")

            # Log GPU offload status
            if self.n_gpu_layers > 0 or self.n_gpu_layers == -1:
                logging.info("✓ GPU acceleration enabled")
            else:
                logging.warning("⚠️  Running on CPU only (slower)")

            return True

        except Exception as e:
            logging.error(f"Failed to load model: {e}")
            return False

    def generate(self,
                 prompt: str,
                 max_tokens: int = 4096,
                 temperature: float = 0.1,  # Lower = more deterministic
                 top_p: float = 0.95,
                 stop: Optional[list] = None) -> Dict:
        """
        Generate completion from prompt.

        Args:
            prompt: Input prompt
            max_tokens: Maximum tokens to generate
            temperature: Sampling temperature (0.0-1.0)
            top_p: Nucleus sampling threshold
            stop: List of stop sequences

        Returns:
            Dict with 'success', 'output', 'error'
        """
        if self.llm is None:
            if not self.load_model():
                return {
                    'success': False,
                    'output': '',
                    'error': 'Failed to load model'
                }

        try:
            logging.info(f"Generating completion (max_tokens={max_tokens})...")

            # Format prompt for code models (using ChatML format)
            formatted_prompt = f"""<|im_start|>system
You are an expert software engineer implementing BDD test steps. Write complete, production-quality code with no TODOs or placeholders.<|im_end|>
<|im_start|>user
{prompt}<|im_end|>
<|im_start|>assistant
"""

            response = self.llm(
                formatted_prompt,
                max_tokens=max_tokens,
                temperature=temperature,
                top_p=top_p,
                stop=stop or ["<|im_end|>", "<|im_start|>"],
                echo=False  # Don't include prompt in output
            )

            output = response['choices'][0]['text'].strip()

            logging.info(f"✓ Generated {len(output)} characters")

            return {
                'success': True,
                'output': output,
                'error': ''
            }

        except Exception as e:
            logging.error(f"Generation failed: {e}")
            return {
                'success': False,
                'output': '',
                'error': str(e)
            }

    def unload_model(self):
        """Unload model from memory"""
        if self.llm is not None:
            del self.llm
            self.llm = None
            logging.info("Model unloaded from memory")


def get_recommended_model_config() -> Dict:
    """
    Get recommended model configuration based on system.

    Returns:
        Dict with model_path, n_gpu_layers, and download URLs
    """
    import platform
    import psutil
    import subprocess

    system = platform.system()
    total_ram_gb = psutil.virtual_memory().total / (1024**3)

    # Detect GPU
    has_metal = False
    has_cuda = False
    gpu_info = "Unknown"

    # Check for Metal support (Apple Silicon or AMD on macOS)
    if system == "Darwin":
        try:
            # Check if Metal is available
            result = subprocess.run(
                ['system_profiler', 'SPDisplaysDataType'],
                capture_output=True,
                text=True
            )
            if 'Metal Support: Metal' in result.stdout:
                has_metal = True
                # Extract GPU name
                for line in result.stdout.split('\n'):
                    if 'Chipset Model:' in line:
                        gpu_info = line.split(':')[1].strip()
                        break
        except:
            pass

    # Check for NVIDIA CUDA
    try:
        nvidia_smi = subprocess.run(['nvidia-smi'], capture_output=True)
        has_cuda = nvidia_smi.returncode == 0
        if has_cuda:
            gpu_info = "NVIDIA GPU (CUDA)"
    except:
        pass

    # Recommend model based on RAM and GPU
    # For 128GB systems, recommend the 32B model for best quality
    if total_ram_gb >= 100:
        recommended = {
            'model_name': 'Qwen2.5-Coder-32B-Instruct (Q5_K_M)',
            'model_path': str(Path.home() / 'models' / 'qwen2.5-coder-32b-instruct-q5_k_m.gguf'),
            'download_url': 'https://huggingface.co/Qwen/Qwen2.5-Coder-32B-Instruct-GGUF/resolve/main/qwen2.5-coder-32b-instruct-q5_k_m.gguf',
            'size_gb': 22.0,
            'quality': 'Excellent (Best Available)',
            'speed': 'Fast (with GPU)' if (has_metal or has_cuda) else 'Moderate (CPU)'
        }
    elif total_ram_gb >= 32:
        # Can run 7B models
        recommended = {
            'model_name': 'Qwen2.5-Coder-7B-Instruct (Q5_K_M)',
            'model_path': str(Path.home() / 'models' / 'qwen2.5-coder-7b-instruct-q5_k_m.gguf'),
            'download_url': 'https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q5_k_m.gguf',
            'size_gb': 5.2,
            'quality': 'Excellent',
            'speed': 'Very Fast (with GPU)' if (has_metal or has_cuda) else 'Fast (CPU)'
        }
    else:
        # Smaller model for systems with less RAM
        recommended = {
            'model_name': 'DeepSeek-Coder-6.7B-Instruct (Q5_K_M)',
            'model_path': str(Path.home() / 'models' / 'deepseek-coder-6.7b-instruct.Q5_K_M.gguf'),
            'download_url': 'https://huggingface.co/TheBloke/deepseek-coder-6.7B-instruct-GGUF/resolve/main/deepseek-coder-6.7b-instruct.Q5_K_M.gguf',
            'size_gb': 4.8,
            'quality': 'Very Good',
            'speed': 'Very Fast (with GPU)' if (has_metal or has_cuda) else 'Fast (CPU)'
        }

    # GPU configuration
    if has_metal or has_cuda:
        recommended['n_gpu_layers'] = -1  # Offload all to GPU
        recommended['gpu_type'] = f"{gpu_info} (Metal)" if has_metal else 'CUDA'
        recommended['gpu_enabled'] = True
    else:
        recommended['n_gpu_layers'] = 0  # CPU only
        recommended['gpu_type'] = 'CPU only (slower)'
        recommended['gpu_enabled'] = False

    return recommended


if __name__ == '__main__':
    """Test script to verify local LLM setup"""
    import sys

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s | %(levelname)-8s | %(message)s'
    )

    print("=" * 80)
    print("LOCAL LLM SETUP TEST")
    print("=" * 80)

    # Show recommended config
    config = get_recommended_model_config()
    print("\nRecommended Configuration:")
    print(f"  Model: {config['model_name']}")
    print(f"  Size: {config['size_gb']} GB")
    print(f"  Quality: {config['quality']}")
    print(f"  Speed: {config['speed']}")
    print(f"  GPU: {config['gpu_type']}")
    print(f"\nDownload command:")
    print(f"  mkdir -p ~/models")
    print(f"  curl -L -o '{config['model_path']}' '{config['download_url']}'")

    # Check if model exists
    if not Path(config['model_path']).exists():
        print(f"\n⚠️  Model not found at: {config['model_path']}")
        print("   Download the model using the command above")
        sys.exit(1)

    # Test load and generation
    print("\nTesting model...")
    llm = LocalLLM(
        model_path=config['model_path'],
        n_gpu_layers=config['n_gpu_layers']
    )

    if llm.load_model():
        print("\n✓ Model loaded successfully")

        # Test generation
        test_prompt = "Write a simple C++ function that adds two integers:"
        print(f"\nTest prompt: {test_prompt}")

        result = llm.generate(test_prompt, max_tokens=256)

        if result['success']:
            print("\n✓ Generation successful")
            print("\nOutput:")
            print("-" * 80)
            print(result['output'][:500])
            print("-" * 80)
            print("\n✅ LOCAL LLM SETUP COMPLETE")
        else:
            print(f"\n❌ Generation failed: {result['error']}")
            sys.exit(1)
    else:
        print("\n❌ Model loading failed")
        sys.exit(1)
