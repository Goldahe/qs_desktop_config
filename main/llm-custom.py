#!/usr/bin/env python3
"""Inspect GGUF metadata and safely launch llama-server from Quickshell."""

import argparse
import json
import os
import re
import shlex
import struct
import subprocess
import sys
from pathlib import Path

LLAMA_SERVER = "/usr/bin/llama-server"
LLAMA_FIT_PARAMS = "/usr/bin/llama-fit-params"
DEFAULT_MODELS_DIR = Path(os.environ.get("LLAMA_MODELS_DIR", str(Path.home() / "Work" / "AI_Dev" / "Llama" / "Models")))
FIT_KEYS = {
    "threads", "threads-batch", "cpu-range", "cpu-strict", "prio", "poll", "numa",
    "ctx-size", "batch-size", "ubatch-size", "keep", "flash-attn", "swa-full",
    "rope-scaling", "rope-scale", "rope-freq-base", "rope-freq-scale", "yarn-orig-ctx",
    "yarn-ext-factor", "yarn-attn-factor", "yarn-beta-slow", "yarn-beta-fast",
    "kv-offload", "cache-type-k", "cache-type-v", "load-mode", "lazy-mode", "repack",
    "device", "n-gpu-layers", "split-mode", "tensor-split", "main-gpu", "fit",
    "fit-target", "fit-ctx", "op-offload", "cpu-moe", "n-cpu-moe", "n-cpu-ffn",
    "override-kv", "override-tensor", "lora", "lora-scaled",
    "control-vector", "control-vector-scaled", "parallel",
}
PROFILE_FLAGS = {
    "-t": "threads", "--threads": "threads", "-tb": "threads-batch",
    "--threads-batch": "threads-batch", "-c": "ctx-size", "--ctx-size": "ctx-size",
    "-b": "batch-size", "--batch-size": "batch-size", "-ub": "ubatch-size",
    "--ubatch-size": "ubatch-size", "-fa": "flash-attn", "--flash-attn": "flash-attn",
    "-ctk": "cache-type-k", "--cache-type-k": "cache-type-k",
    "-ctv": "cache-type-v", "--cache-type-v": "cache-type-v",
    "-dev": "device", "--device": "device", "-ngl": "n-gpu-layers",
    "--n-gpu-layers": "n-gpu-layers", "-sm": "split-mode", "--split-mode": "split-mode",
    "-ts": "tensor-split", "--tensor-split": "tensor-split", "-mg": "main-gpu",
    "--main-gpu": "main-gpu", "-fit": "fit", "--fit": "fit",
    "-fitt": "fit-target", "--fit-target": "fit-target", "-fitc": "fit-ctx",
    "--fit-ctx": "fit-ctx", "-ncmoe": "n-cpu-moe", "--n-cpu-moe": "n-cpu-moe",
    "-ncffn": "n-cpu-ffn", "--n-cpu-ffn": "n-cpu-ffn", "-np": "parallel",
    "--parallel": "parallel",
}
PROFILE_BOOL_FLAGS = {
    "-kvo": ("kv-offload", "true"), "--kv-offload": ("kv-offload", "true"),
    "-nkvo": ("kv-offload", "false"), "--no-kv-offload": ("kv-offload", "false"),
    "-cmoe": ("cpu-moe", "true"), "--cpu-moe": ("cpu-moe", "true"),
    "--swa-full": ("swa-full", "true"), "--repack": ("repack", "true"),
    "--no-repack": ("repack", "false"), "--op-offload": ("op-offload", "true"),
    "--no-op-offload": ("op-offload", "false"),
}
GGUF_TYPES = {
    0: ("B", 1), 1: ("b", 1), 2: ("H", 2), 3: ("h", 2),
    4: ("I", 4), 5: ("i", 4), 6: ("f", 4), 7: ("?", 1),
    10: ("Q", 8), 11: ("q", 8), 12: ("d", 8),
}
BUILTIN_TEMPLATES = [
    "bailing", "bailing-think", "bailing2", "chatglm3", "chatglm4", "chatml",
    "command-r", "deepseek", "deepseek-ocr", "deepseek2", "deepseek3", "exaone-moe",
    "exaone3", "exaone4", "falcon3", "gemma", "gigachat", "glmedge", "gpt-oss",
    "granite", "granite-4.0", "granite-4.1", "grok-2", "hunyuan-dense", "hunyuan-moe",
    "hunyuan-vl", "kimi-k2", "llama2", "llama2-sys", "llama2-sys-bos",
    "llama2-sys-strip", "llama3", "llama4", "megrez", "minicpm", "mistral-v1",
    "mistral-v3", "mistral-v3-tekken", "mistral-v7", "mistral-v7-tekken", "monarch",
    "openchat", "orion", "pangu-embedded", "phi3", "phi4", "rwkv-world", "seed_oss",
    "smolvlm", "solar-open", "vicuna", "vicuna-orca", "yandex", "zephyr",
]
KV_TYPES = ["f32", "f16", "bf16", "q8_0", "q4_0", "q4_1", "iq4_nl", "q5_0", "q5_1"]


def _read_exact(handle, size):
    data = handle.read(size)
    if len(data) != size:
        raise ValueError("truncated GGUF metadata")
    return data


def _u32(handle):
    return struct.unpack("<I", _read_exact(handle, 4))[0]


def _u64(handle):
    return struct.unpack("<Q", _read_exact(handle, 8))[0]


def _string(handle, keep=True):
    size = _u64(handle)
    if size > 256 * 1024 * 1024:
        raise ValueError("invalid GGUF string length")
    if not keep:
        handle.seek(size, os.SEEK_CUR)
        return None
    return _read_exact(handle, size).decode("utf-8", errors="replace")


def _scalar(handle, value_type):
    if value_type == 8:
        return _string(handle)
    fmt = GGUF_TYPES.get(value_type)
    if not fmt:
        raise ValueError(f"unsupported GGUF value type {value_type}")
    return struct.unpack("<" + fmt[0], _read_exact(handle, fmt[1]))[0]


def _skip_value(handle, value_type):
    if value_type == 8:
        _string(handle, keep=False)
    elif value_type == 9:
        element_type = _u32(handle)
        count = _u64(handle)
        if count > 1_000_000_000:
            raise ValueError("invalid GGUF array length")
        if element_type in GGUF_TYPES:
            handle.seek(GGUF_TYPES[element_type][1] * count, os.SEEK_CUR)
        else:
            for _ in range(count):
                _skip_value(handle, element_type)
    elif value_type in GGUF_TYPES:
        handle.seek(GGUF_TYPES[value_type][1], os.SEEK_CUR)
    else:
        raise ValueError(f"unsupported GGUF value type {value_type}")


def _wanted_key(key):
    return (key in {"general.architecture", "general.type", "general.name", "general.basename",
                    "general.size_label", "general.tags", "tokenizer.chat_template"}
            or key.endswith((".context_length", ".block_count", ".expert_count",
                             ".expert_used_count", ".pooling_type")))


def read_gguf_metadata(path):
    """Read only small capability metadata; never read tensor payloads or token arrays."""
    path = Path(path)
    with path.open("rb") as handle:
        if _read_exact(handle, 4) != b"GGUF":
            raise ValueError("not a GGUF file")
        version = _u32(handle)
        if version not in (2, 3):
            raise ValueError(f"unsupported GGUF version {version}")
        _u64(handle)  # tensor count; tensor descriptors and data are deliberately untouched
        metadata_count = _u64(handle)
        if metadata_count > 1_000_000:
            raise ValueError("invalid GGUF metadata count")
        result = {"gguf.version": version}
        for _ in range(metadata_count):
            key = _string(handle)
            value_type = _u32(handle)
            wanted = _wanted_key(key)
            if value_type == 9:
                element_type = _u32(handle)
                count = _u64(handle)
                if count > 1_000_000_000:
                    raise ValueError("invalid GGUF array length")
                if wanted and key == "general.tags" and element_type == 8 and count <= 256:
                    result[key] = [_string(handle) for _ in range(count)]
                elif element_type in GGUF_TYPES:
                    handle.seek(GGUF_TYPES[element_type][1] * count, os.SEEK_CUR)
                else:
                    for _ in range(count):
                        _skip_value(handle, element_type)
            elif wanted:
                result[key] = _scalar(handle, value_type)
            else:
                _skip_value(handle, value_type)
        return result


def _first_suffix(metadata, suffix, default=0):
    for key, value in metadata.items():
        if key.endswith(suffix):
            return value
    return default


def classify_model(metadata, filename):
    architecture = str(metadata.get("general.architecture", "unknown"))
    name = str(metadata.get("general.name") or Path(filename).stem)
    tags_value = metadata.get("general.tags", [])
    tags = [str(x) for x in tags_value] if isinstance(tags_value, list) else [str(tags_value)]
    template = str(metadata.get("tokenizer.chat_template", ""))
    searchable = " ".join([architecture, name, Path(filename).stem, *tags, template]).lower()
    expert_count = int(_first_suffix(metadata, ".expert_count", 0) or 0)
    moe = expert_count > 0 or "moe" in architecture.lower() or "moe" in name.lower()
    reasoning = any(term in searchable for term in (
        "enable_thinking", "reasoning_content", "<think>", "reasoning", "deepseek-r1", "qwen3"))
    identity = " ".join([architecture, name, Path(filename).stem, *tags]).lower()
    multimodal = (any(term in identity for term in (
        "vision", "multimodal", "image-text", "llava", "minicpmv", "qwen2vl", "qwen3vl"))
        or architecture.lower().endswith("vl"))
    embedding = any(term in searchable for term in ("embedding", "embed", "sentence-transform"))
    rerank = any(term in searchable for term in ("rerank", "cross-encoder"))
    context_length = int(_first_suffix(metadata, ".context_length", 0) or 0)
    block_count = int(_first_suffix(metadata, ".block_count", 0) or 0)
    has_chat_template = bool(template)
    server_compatible = bool(block_count or context_length or has_chat_template or embedding or rerank)
    return {
        "name": name,
        "architecture": architecture,
        "type": str(metadata.get("general.type", "model")),
        "sizeLabel": str(metadata.get("general.size_label", "")),
        "contextLength": context_length,
        "blockCount": block_count,
        "expertCount": expert_count,
        "moe": moe,
        "reasoning": reasoning,
        "multimodal": multimodal,
        "embedding": embedding,
        "rerank": rerank,
        "hasChatTemplate": has_chat_template,
        "serverCompatible": server_compatible,
        "tags": tags,
    }


def discover_devices():
    try:
        result = subprocess.run([LLAMA_SERVER, "--list-devices"], text=True,
                                capture_output=True, timeout=8, check=False)
    except (OSError, subprocess.SubprocessError):
        return []
    devices = []
    for line in (result.stdout + "\n" + result.stderr).splitlines():
        match = re.match(r"\s*([^:\s]+):\s+", line)
        if match and match.group(1) != "Available":
            devices.append(match.group(1))
    return devices


def opt(key, label, kind="text", default="", choices=None, minimum=None, maximum=None,
        help_text="", true_flag=None, false_flag=None, step=None, slider_max=None):
    item = {"key": key, "label": label, "type": kind, "default": str(default),
            "help": help_text, "flag": "--" + key}
    if choices is not None:
        item["choices"] = [str(value) for value in choices]
    if minimum is not None:
        item["min"] = minimum
    if maximum is not None:
        item["max"] = maximum
    if step is not None:
        item["step"] = step
    if slider_max is not None:
        item["sliderMax"] = slider_max
    if kind == "bool":
        item["trueFlag"] = true_flag or "--" + key
        item["falseFlag"] = false_flag if false_flag is not None else "--no-" + key
        item["choices"] = ["true", "false"]
    return item


def section(name, options, note=""):
    return {"name": name, "note": note, "options": options}


def option_schema(caps, sibling_models, devices):
    context_default = str(caps.get("contextLength") or 0)
    device_choices = list(dict.fromkeys([*devices, "none"])) or ["none"]
    draft_choices = [str(Path(p)) for p in sibling_models]
    sections = [
        section("CPU & Threads", [
            opt("threads", "Generation threads", "int", -1, minimum=-1, maximum=4096),
            opt("threads-batch", "Batch threads", "int", -1, minimum=-1, maximum=4096),
            opt("cpu-range", "CPU range", default="", help_text="Example: 0-7"),
            opt("cpu-strict", "Strict CPU placement", "enum", 0, [0, 1]),
            opt("prio", "Thread priority", "enum", 0, [-1, 0, 1, 2, 3]),
            opt("poll", "Polling intensity", "int", 50, minimum=0, maximum=100),
            opt("numa", "NUMA policy", "enum", "distribute", ["distribute", "isolate", "numactl"]),
        ]),
        section("Context & Batching", [
            opt("ctx-size", "Context tokens", "int", context_default, minimum=0,
                slider_max=max(0, int(caps.get("contextLength") or 0)) or None),
            opt("n-predict", "Maximum generated tokens", "int", -1, minimum=-1),
            opt("batch-size", "Logical batch", "int", 2048, minimum=1),
            opt("ubatch-size", "Physical micro-batch", "int", 512, minimum=1),
            opt("keep", "Prompt tokens retained", "int", 0, minimum=-1),
            opt("flash-attn", "Flash Attention", "enum", "auto", ["auto", "on", "off"]),
            opt("swa-full", "Full SWA cache", "bool", "true", false_flag=""),
        ]),
        section("RoPE & Context Extension", [
            opt("rope-scaling", "RoPE scaling", "enum", "none", ["none", "linear", "yarn"]),
            opt("rope-scale", "RoPE scale", "float", 1.0, minimum=0.000001),
            opt("rope-freq-base", "RoPE base frequency", "float", 0, minimum=0),
            opt("rope-freq-scale", "RoPE frequency scale", "float", 1.0, minimum=0.000001),
            opt("yarn-orig-ctx", "YaRN original context", "int", 0, minimum=0),
            opt("yarn-ext-factor", "YaRN extension factor", "float", -1),
            opt("yarn-attn-factor", "YaRN attention factor", "float", -1),
            opt("yarn-beta-slow", "YaRN beta slow", "float", -1),
            opt("yarn-beta-fast", "YaRN beta fast", "float", -1),
        ], "Leave disabled unless deliberately extending the model context."),
        section("KV Cache", [
            opt("kv-offload", "Offload KV cache", "bool", "true"),
            opt("cache-type-k", "K cache type", "enum", "f16", KV_TYPES),
            opt("cache-type-v", "V cache type", "enum", "f16", KV_TYPES),
            opt("kv-unified", "Unified KV buffer", "bool", "true"),
            opt("kv-unified-per-slot", "Context per parallel slot", "int", 0, minimum=0),
            opt("cache-ram", "Prompt cache RAM (MiB)", "int", 8192, minimum=-1),
            opt("cache-idle-slots", "Cache idle slots", "bool", "true"),
            opt("context-shift", "Infinite context shifting", "bool", "false"),
            opt("cache-prompt", "Prompt caching", "bool", "true"),
            opt("cache-reuse", "Minimum reusable chunk", "int", 0, minimum=0),
            opt("ctx-checkpoints", "Context checkpoints per slot", "int", 32, minimum=0),
            opt("checkpoint-min-step", "Checkpoint spacing", "int", 8192, minimum=0),
        ]),
        section("Model Loading", [
            opt("load-mode", "Load mode", "enum", "auto", ["auto", "none", "mmap", "mlock", "mmap+mlock", "dio"]),
            opt("lazy-mode", "Lazy tensor loading", "enum", "auto", ["auto", "on", "off"]),
            opt("repack", "Repack weights", "bool", "true"),
            opt("check-tensors", "Check tensor values", "bool", "true", false_flag=""),
            opt("offline", "Offline mode", "bool", "true", false_flag=""),
        ]),
        section("GPU & Accelerator", [
            opt("device", "Offload device", "enum", device_choices[0], device_choices),
            opt("n-gpu-layers", "GPU layers", "gpu_layers", "auto", minimum=0,
                maximum=max(0, int(caps.get("blockCount") or 0)) or None),
            opt("split-mode", "Multi-GPU split mode", "enum", "none", ["none", "layer", "row", "tensor"]),
            opt("tensor-split", "Tensor split proportions", default=""),
            opt("main-gpu", "Main GPU index", "int", 0, minimum=0),
            opt("fit", "Automatic VRAM fitting", "enum", "on", ["on", "off"]),
            opt("fit-target", "Free VRAM target (MiB)", "int", 2048, minimum=0),
            opt("fit-ctx", "Minimum fitted context", "int", 4096, minimum=1),
            opt("op-offload", "Offload host operations", "bool", "true"),
        ]),
    ]
    if caps.get("moe"):
        sections.append(section("MoE Expert Placement", [
            opt("cpu-moe", "Keep all experts on CPU", "bool", "true", false_flag=""),
            opt("n-cpu-moe", "Expert layers on CPU", "int", 0, minimum=0,
                maximum=max(0, int(caps.get("blockCount") or 0)) or None),
        ], f"Detected {caps.get('expertCount', 0)} experts."))
    else:
        sections.append(section("Dense FFN Placement", [
            opt("n-cpu-ffn", "Dense FFN layers on CPU", "int", 0, minimum=0,
                maximum=max(0, int(caps.get("blockCount") or 0)) or None),
        ]))
    sections.extend([
        section("Server Generation", [
            opt("parallel", "Parallel slots", "int", 1, minimum=-1),
            opt("cont-batching", "Continuous batching", "bool", "true"),
            opt("warmup", "Warmup run", "bool", "true"),
            opt("sleep-idle-seconds", "Sleep after idle seconds", "int", -1, minimum=-1),
            opt("reverse-prompt", "Reverse prompt", default=""),
            opt("special", "Output special tokens", "bool", "true", false_flag=""),
            opt("spm-infill", "SPM infill order", "bool", "true", false_flag=""),
        ]),
        section("Sampling", [
            opt("samplers", "Sampler chain", default="penalties;dry;top_n_sigma;top_k;typ_p;top_p;min_p;xtc;temperature"),
            opt("seed", "Random seed", "int", -1),
            opt("temperature", "Temperature", "float", 0.8, minimum=0),
            opt("top-k", "Top-K", "int", 40, minimum=0),
            opt("top-p", "Top-P", "float", 0.95, minimum=0, maximum=1),
            opt("min-p", "Min-P", "float", 0.05, minimum=0, maximum=1),
            opt("top-n-sigma", "Top-N sigma", "float", -1),
            opt("xtc-probability", "XTC probability", "float", 0, minimum=0, maximum=1),
            opt("xtc-threshold", "XTC threshold", "float", 0.1, minimum=0, maximum=1),
            opt("typical-p", "Typical-P", "float", 1.0, minimum=0, maximum=1),
            opt("repeat-last-n", "Repeat window", "int", 64, minimum=0),
            opt("repeat-penalty", "Repeat penalty", "float", 1.0, minimum=0),
            opt("presence-penalty", "Presence penalty", "float", 0),
            opt("frequency-penalty", "Frequency penalty", "float", 0),
            opt("dry-multiplier", "DRY multiplier", "float", 0, minimum=0),
            opt("dry-base", "DRY base", "float", 1.75, minimum=0),
            opt("dry-allowed-length", "DRY allowed length", "int", 2, minimum=0),
            opt("dry-penalty-last-n", "DRY penalty window", "int", 64, minimum=0),
            opt("adaptive-target", "Adaptive-P target", "float", -1, minimum=-1, maximum=1),
            opt("adaptive-decay", "Adaptive-P decay", "float", 0.9, minimum=0, maximum=0.99),
            opt("dynatemp-range", "Dynamic temperature range", "float", 0, minimum=0),
            opt("dynatemp-exp", "Dynamic temperature exponent", "float", 1, minimum=0),
            opt("mirostat", "Mirostat mode", "enum", 0, [0, 1, 2]),
            opt("mirostat-lr", "Mirostat learning rate", "float", 0.1, minimum=0),
            opt("mirostat-ent", "Mirostat target entropy", "float", 5, minimum=0),
        ]),
        section("Structured Generation", [
            opt("grammar-file", "Grammar file", "path", ""),
            opt("json-schema-file", "JSON schema file", "path", ""),
            opt("backend-sampling", "Backend sampling (experimental)", "bool", "true", false_flag=""),
        ]),
        section("Chat & Templates", [
            opt("jinja", "Jinja templates", "bool", "true"),
            opt("chat-template", "Built-in chat template", "enum", BUILTIN_TEMPLATES[0], BUILTIN_TEMPLATES),
            opt("chat-template-file", "Custom template file", "path", ""),
            opt("chat-template-kwargs", "Template kwargs JSON", default="{}"),
            opt("skip-chat-parsing", "Pure content parser", "bool", "false"),
            opt("prefill-assistant", "Assistant prefill", "bool", "true"),
            opt("slot-prompt-similarity", "Slot prompt similarity", "float", 0.10, minimum=0, maximum=1),
        ]),
    ])
    if caps.get("reasoning"):
        sections.append(section("Reasoning / Thinking", [
            opt("reasoning", "Reasoning mode", "enum", "auto", ["auto", "on", "off"]),
            opt("reasoning-format", "Reasoning response format", "enum", "auto", ["auto", "none", "deepseek", "deepseek-legacy"]),
            opt("reasoning-effort", "Reasoning effort", "enum", "default", ["default", "minimal", "low", "medium", "high", "xhigh", "max"]),
            opt("reasoning-budget", "Reasoning token budget", "int", -1, minimum=-1),
            opt("reasoning-budget-message", "Budget exhausted message", default=""),
            opt("reasoning-preserve", "Preserve reasoning history", "bool", "true"),
        ], "Shown because the model name, tags, or embedded chat template indicates reasoning support."))
    if caps.get("embedding") or caps.get("rerank"):
        mode_options = []
        if caps.get("embedding"):
            mode_options.extend([
                opt("embedding", "Embedding-only endpoint", "bool", "true", false_flag=""),
                opt("pooling", "Embedding pooling", "enum", "none", ["none", "mean", "cls", "last", "rank"]),
                opt("embd-normalize", "Embedding normalization", "int", 2, minimum=-1),
            ])
        if caps.get("rerank"):
            mode_options.append(opt("rerank", "Reranking endpoint", "bool", "true", false_flag=""))
        sections.append(section("Detected Model Mode", mode_options))
    if caps.get("multimodal"):
        sections.append(section("Multimodal", [
            opt("mmproj", "Multimodal projector", "path", ""),
            opt("mmproj-auto", "Automatic projector", "bool", "true", false_flag="--no-mmproj"),
            opt("mmproj-offload", "Offload projector", "bool", "true"),
            opt("mmproj-device", "Projector device", "enum", device_choices[0], device_choices),
            opt("image-min-tokens", "Minimum image tokens", "int", 0, minimum=0),
            opt("image-max-tokens", "Maximum image tokens", "int", 0, minimum=0),
            opt("mtmd-batch-max-tokens", "Image batch token maximum", "int", 1024, minimum=1),
            opt("video-fps", "Video FPS", "float", 4, minimum=0.01),
            opt("video-timestamp-interval", "Video timestamp interval (ms)", "int", 5000, minimum=0),
        ]))
    sections.extend([
        section("Speculative Decoding", [
            opt("model-draft", "Draft GGUF model", "enum", draft_choices[0] if draft_choices else "", draft_choices),
            opt("spec-type", "Speculation algorithms", "text", "none"),
            opt("n-gpu-layers-draft", "Draft GPU layers", "gpu_layers", "auto"),
            opt("device-draft", "Draft device", "enum", device_choices[0], device_choices),
            opt("cache-type-k-draft", "Draft K cache type", "enum", "f16", KV_TYPES),
            opt("cache-type-v-draft", "Draft V cache type", "enum", "f16", KV_TYPES),
            opt("spec-draft-n-max", "Maximum draft tokens", "int", 3, minimum=0),
            opt("spec-draft-n-min", "Minimum draft tokens", "int", 0, minimum=0),
            opt("spec-draft-p-split", "Draft split probability", "float", 0.1, minimum=0, maximum=1),
            opt("spec-draft-p-min", "Minimum draft probability", "float", 0, minimum=0, maximum=1),
        ]),
        section("Network & HTTP", [
            opt("host", "Listen address", default="127.0.0.1"),
            opt("port", "Port", "int", 8080, minimum=1, maximum=65535),
            opt("api-prefix", "API path prefix", default=""),
            opt("timeout", "Read/write timeout", "int", 3600, minimum=0),
            opt("sse-ping-interval", "SSE ping interval", "int", 30, minimum=-1),
            opt("threads-http", "HTTP threads", "int", -1, minimum=-1),
            opt("cors-origins", "CORS origins", default="localhost"),
            opt("cors-methods", "CORS methods", default="GET,POST,DELETE,OPTIONS"),
            opt("cors-headers", "CORS headers", default="*"),
            opt("cors-credentials", "Allow CORS credentials", "bool", "true"),
        ]),
        section("Web UI, Auth & Endpoints", [
            opt("ui", "Web UI", "bool", "true"),
            opt("ui-config-file", "Web UI config JSON", "path", ""),
            opt("api-key-file", "API key file", "path", ""),
            opt("ssl-key-file", "TLS private key", "path", ""),
            opt("ssl-cert-file", "TLS certificate", "path", ""),
            opt("metrics", "Prometheus metrics", "bool", "true", false_flag=""),
            opt("props", "Mutable /props endpoint", "bool", "true", false_flag=""),
            opt("slots", "Slots endpoint", "bool", "true"),
            opt("slot-save-path", "Slot cache directory", "path", ""),
            opt("media-path", "Local media directory", "path", ""),
        ]),
        section("Adapters & Overrides", [
            opt("lora", "LoRA adapters (comma-separated)", "path", ""),
            opt("lora-scaled", "Scaled LoRA adapters", default=""),
            opt("lora-init-without-apply", "Load LoRA inactive", "bool", "true", false_flag=""),
            opt("control-vector", "Control vectors", "path", ""),
            opt("control-vector-scaled", "Scaled control vectors", default=""),
            opt("override-kv", "Metadata overrides", default=""),
            opt("override-tensor", "Tensor buffer overrides", default=""),
        ]),
        section("Agent & MCP (Dangerous)", [
            opt("agent", "Built-in agent mode", "bool", "true", false_flag=""),
            opt("tools", "Built-in tools", default=""),
            opt("tools-runtime", "Isolated tool runtime", default=""),
            opt("mcp-servers-config", "MCP servers config", "path", ""),
        ], "Execution-capable tools grant substantial system access. Keep disabled unless intentionally isolated."),
        section("Logging & Identity", [
            opt("alias", "API aliases", default=""),
            opt("tags", "Informational tags", default=""),
            opt("log-file", "Log file", "path", ""),
            opt("log-colors", "Log colors", "enum", "auto", ["auto", "on", "off"]),
            opt("log-verbosity", "Log verbosity", "enum", 3, [0, 1, 2, 3, 4, 5]),
            opt("log-prefix", "Log prefixes", "bool", "false"),
            opt("log-timestamps", "Log timestamps", "bool", "false"),
            opt("log-prompts-dir", "Prompt log directory", "path", ""),
        ]),
    ])
    return sections


def _validated_model(model, models_dir):
    root = Path(models_dir).expanduser().resolve()
    path = Path(model).expanduser().resolve()
    if path.suffix.lower() != ".gguf" or not path.is_file():
        raise ValueError("model must be an existing GGUF file")
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ValueError("model must be inside the configured models directory") from exc
    return path, root


def _validate_value(descriptor, value):
    value = str(value)
    kind = descriptor["type"]
    key = descriptor["key"]
    if kind == "enum":
        if value not in descriptor.get("choices", []):
            raise ValueError(f"invalid value for {key}")
    elif kind == "bool":
        if value not in ("true", "false"):
            raise ValueError(f"invalid boolean for {key}")
    elif kind == "int":
        try:
            parsed = int(value)
        except ValueError as exc:
            raise ValueError(f"invalid integer for {key}") from exc
        if "min" in descriptor and parsed < descriptor["min"]:
            raise ValueError(f"{key} is below its minimum")
        if "max" in descriptor and parsed > descriptor["max"]:
            raise ValueError(f"{key} is above its maximum")
    elif kind == "float":
        try:
            parsed = float(value)
        except ValueError as exc:
            raise ValueError(f"invalid number for {key}") from exc
        if not (float("-inf") < parsed < float("inf")):
            raise ValueError(f"invalid number for {key}")
        if "min" in descriptor and parsed < descriptor["min"]:
            raise ValueError(f"{key} is below its minimum")
        if "max" in descriptor and parsed > descriptor["max"]:
            raise ValueError(f"{key} is above its maximum")
    elif kind == "gpu_layers":
        if value not in ("auto", "all"):
            try:
                parsed = int(value)
            except ValueError as exc:
                raise ValueError(f"invalid GPU layer count for {key}") from exc
            if "min" in descriptor and parsed < descriptor["min"]:
                raise ValueError(f"{key} is below its minimum")
            if "max" in descriptor and parsed > descriptor["max"]:
                raise ValueError(f"{key} is above its maximum")
    if "\x00" in value:
        raise ValueError(f"invalid NUL byte in {key}")
    return value


def build_command(model, values, models_dir=DEFAULT_MODELS_DIR, devices=None):
    model, root = _validated_model(model, models_dir)
    metadata = read_gguf_metadata(model)
    caps = classify_model(metadata, model.name)
    if not caps["serverCompatible"]:
        raise ValueError("selected GGUF does not appear to be a llama-server text model")
    siblings = [path for path in sorted(root.glob("*.gguf")) if path != model]
    devices = discover_devices() if devices is None else list(devices)
    descriptors = {item["key"]: item for group in option_schema(caps, siblings, devices)
                   for item in group["options"]}
    command = [LLAMA_SERVER, "--model", str(model)]
    for key, raw_value in values.items():
        if key not in descriptors:
            raise ValueError(f"unsupported option: {key}")
        descriptor = descriptors[key]
        value = _validate_value(descriptor, raw_value)
        if key in ("device", "device-draft", "mmproj-device") and value not in [*devices, "none"]:
            raise ValueError(f"invalid device: {value}")
        if key == "model-draft":
            draft, _ = _validated_model(value, root)
            if draft == model:
                raise ValueError("draft model must differ from the main model")
            value = str(draft)
        if descriptor["type"] == "bool":
            flag = descriptor["trueFlag"] if value == "true" else descriptor.get("falseFlag", "")
            if flag:
                command.append(flag)
        else:
            command.extend([descriptor["flag"], value])
    return command


def _clean_mib(value):
    return int(value) if float(value).is_integer() else round(value, 2)


def parse_fit_output(text):
    """Parse llama-fit-params' authoritative device/model/context/compute table."""
    rows = []
    for line in text.splitlines():
        match = re.fullmatch(r"\s*(\S+)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*", line)
        if not match:
            continue
        name = match.group(1)
        model, context, compute = (float(match.group(i)) for i in range(2, 5))
        total = model + context + compute
        rows.append({"name": name, "modelMiB": model, "contextMiB": context,
                     "computeMiB": compute, "totalMiB": total})
    if not rows:
        raise ValueError("llama-fit-params returned no memory estimate")
    host = sum(row["totalMiB"] for row in rows if row["name"].lower() == "host")
    vram = sum(row["totalMiB"] for row in rows if row["name"].lower() != "host")
    for row in rows:
        for key in ("modelMiB", "contextMiB", "computeMiB", "totalMiB"):
            row[key] = _clean_mib(row[key])
    return {
        "method": "llama-fit-params",
        "totalMiB": _clean_mib(host + vram),
        "ramMiB": _clean_mib(host),
        "vramMiB": _clean_mib(vram),
        "modelMiB": _clean_mib(sum(row["modelMiB"] for row in rows)),
        "contextMiB": _clean_mib(sum(row["contextMiB"] for row in rows)),
        "computeMiB": _clean_mib(sum(row["computeMiB"] for row in rows)),
        "devices": rows,
        "note": "Upstream allocation estimate; actual peak use can vary with backend and requests.",
    }


def read_quick_profile(path):
    """Statically decode the memory-relevant arguments of a trusted launcher profile."""
    text = Path(path).read_text(encoding="utf-8")
    defaults = {}
    for name, default in re.findall(r'^([A-Z_][A-Z0-9_]*)="\$\{\1:-([^}]*)\}"', text, re.MULTILINE):
        defaults[name] = default
    command_match = re.search(r"^\s*exec\s+llama-server\s+(.*?)(?:\n\s*\n|\Z)",
                              text, re.MULTILINE | re.DOTALL)
    if not command_match:
        raise ValueError("launcher profile has no static llama-server command")
    command_text = re.sub(r"\\\s*\n", " ", command_match.group(1))
    tokens = shlex.split(command_text, posix=True)
    resolved = []
    for token in tokens:
        if token in ("${SOURCE[@]}", "$MODEL", "${MODEL}"):
            resolved.append(token)
            continue
        variable = re.fullmatch(r"\$\{?([A-Z_][A-Z0-9_]*)\}?", token)
        resolved.append(defaults.get(variable.group(1), token) if variable else token)
    values = {}
    index = 0
    while index < len(resolved):
        token = resolved[index]
        if token in ("${SOURCE[@]}",):
            index += 1
            continue
        if token in ("-m", "--model"):
            index += 2
            continue
        if token in PROFILE_BOOL_FLAGS:
            key, value = PROFILE_BOOL_FLAGS[token]
            values[key] = value
            index += 1
            continue
        key = PROFILE_FLAGS.get(token)
        if key:
            if index + 1 >= len(resolved):
                raise ValueError(f"missing value after {token} in launcher profile")
            values[key] = resolved[index + 1]
            index += 2
            continue
        # Unknown server-only arguments are ignored with their apparent value.
        index += 2 if token.startswith("-") and index + 1 < len(resolved) and not resolved[index + 1].startswith("-") else 1
    return values


def _run_fit_estimate(model, values, root, devices):
    command = build_command(model, values, root, devices)
    command[0] = LLAMA_FIT_PARAMS
    command.extend(["--fit-print", "on"])
    result = subprocess.run(command, text=True, capture_output=True, timeout=45, check=False)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "resource estimator failed"
        raise ValueError(detail.splitlines()[-1])
    return parse_fit_output(result.stdout)


def _add_estimate(target, addition):
    for key in ("totalMiB", "ramMiB", "vramMiB", "modelMiB", "contextMiB", "computeMiB"):
        target[key] = _clean_mib(float(target.get(key, 0)) + float(addition.get(key, 0)))
    by_name = {row["name"]: row for row in target["devices"]}
    for source in addition["devices"]:
        row = by_name.get(source["name"])
        if row is None:
            row = {"name": source["name"], "modelMiB": 0, "contextMiB": 0,
                   "computeMiB": 0, "totalMiB": 0}
            target["devices"].append(row)
            by_name[source["name"]] = row
        for key in ("modelMiB", "contextMiB", "computeMiB", "totalMiB"):
            row[key] = _clean_mib(float(row[key]) + float(source[key]))


def _add_auxiliary_file(target, path, offloaded, device):
    file_path = Path(path).expanduser().resolve()
    if not file_path.is_file():
        raise ValueError(f"auxiliary model file does not exist: {file_path}")
    mib = file_path.stat().st_size / 1048576
    name = device if offloaded and device and device != "none" else "Host"
    addition = {
        "totalMiB": mib,
        "ramMiB": 0 if name != "Host" else mib,
        "vramMiB": mib if name != "Host" else 0,
        "modelMiB": mib, "contextMiB": 0, "computeMiB": 0,
        "devices": [{"name": name, "modelMiB": mib, "contextMiB": 0,
                     "computeMiB": 0, "totalMiB": mib}],
    }
    _add_estimate(target, addition)
    return _clean_mib(mib)


def estimate_resources(model, values, models_dir=DEFAULT_MODELS_DIR, devices=None,
                       script=None, request_id=""):
    model, root = _validated_model(model, models_dir)
    devices = discover_devices() if devices is None else list(devices)
    selected = dict(values)
    if script:
        script_path = Path(script).expanduser().resolve()
        allowed_root = root.parent.resolve()
        try:
            script_path.relative_to(allowed_root)
        except ValueError as exc:
            raise ValueError("launcher profile must be inside the Llama directory") from exc
        if not script_path.is_file():
            raise ValueError("launcher profile does not exist")
        selected = read_quick_profile(script_path)
    # Validate the complete user selection with the server schema, then pass only
    # allocation-affecting options supported by llama-fit-params.
    build_command(model, selected, root, devices)
    fit_values = {key: value for key, value in selected.items() if key in FIT_KEYS}
    estimate = _run_fit_estimate(model, fit_values, root, devices)

    if selected.get("model-draft"):
        draft_model, _ = _validated_model(selected["model-draft"], root)
        shared = {key: selected[key] for key in (
            "ctx-size", "batch-size", "ubatch-size", "parallel", "flash-attn", "swa-full",
            "fit", "fit-target", "fit-ctx", "op-offload", "load-mode", "lazy-mode", "repack"
        ) if key in selected}
        draft_map = {
            "device-draft": "device", "n-gpu-layers-draft": "n-gpu-layers",
            "cache-type-k-draft": "cache-type-k", "cache-type-v-draft": "cache-type-v",
        }
        for source, destination in draft_map.items():
            if source in selected:
                shared[destination] = selected[source]
        draft_estimate = _run_fit_estimate(draft_model, shared, root, devices)
        estimate["draftMiB"] = draft_estimate["totalMiB"]
        _add_estimate(estimate, draft_estimate)
    else:
        estimate["draftMiB"] = 0

    estimate["auxiliaryMiB"] = 0
    if selected.get("mmproj"):
        offloaded = selected.get("mmproj-offload", "true") == "true"
        device = selected.get("mmproj-device") or (devices[0] if devices else "none")
        estimate["auxiliaryMiB"] = _add_auxiliary_file(
            estimate, selected["mmproj"], offloaded, device)
        estimate["note"] = ("Upstream allocation estimate plus GGUF projector size; "
                            "actual multimodal scratch use varies by request.")

    estimate.update({"file": str(model), "requestId": str(request_id),
                     "mode": "quick" if script else "custom"})
    return estimate


def inspect_model(model, models_dir=DEFAULT_MODELS_DIR, devices=None):
    model, root = _validated_model(model, models_dir)
    metadata = read_gguf_metadata(model)
    caps = classify_model(metadata, model.name)
    siblings = [path for path in sorted(root.glob("*.gguf")) if path != model]
    devices = discover_devices() if devices is None else list(devices)
    return {"file": str(model), "model": caps, "devices": devices,
            "sections": option_schema(caps, siblings, devices)}


def main(argv=None):
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="action", required=True)
    for name in ("inspect", "estimate", "preview", "run"):
        cmd = sub.add_parser(name)
        cmd.add_argument("model")
        cmd.add_argument("config", nargs="?", default="{}")
        cmd.add_argument("--models-dir", default=str(DEFAULT_MODELS_DIR))
        cmd.add_argument("--devices", default=None,
                         help="comma-separated test override; normally discovered from llama-server")
        cmd.add_argument("--script", default=None,
                         help="trusted Quick Start profile to decode statically for estimation")
        cmd.add_argument("--request-id", default="")
    args = parser.parse_args(argv)
    devices = None if args.devices is None else [x for x in args.devices.split(",") if x]
    try:
        if args.action == "inspect":
            print(json.dumps(inspect_model(args.model, args.models_dir, devices), separators=(",", ":")))
            return 0
        values = json.loads(args.config)
        if not isinstance(values, dict):
            raise ValueError("configuration must be a JSON object")
        if args.action == "estimate":
            estimate = estimate_resources(args.model, values, args.models_dir, devices,
                                          args.script, args.request_id)
            print(json.dumps(estimate, separators=(",", ":")))
            return 0
        command = build_command(args.model, values, args.models_dir, devices)
        if args.action == "preview":
            print(json.dumps(command, separators=(",", ":")))
            return 0
        os.execv(command[0], command)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"error": str(exc)}, separators=(",", ":")), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
