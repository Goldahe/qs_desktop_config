#!/usr/bin/env python3
import importlib.util
import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "llm-custom.py"
MODELS = Path.home() / "Work" / "AI_Dev" / "Llama" / "Models"


def load_helper():
    spec = importlib.util.spec_from_file_location("llm_custom", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def gguf_string(value):
    raw = value.encode("utf-8")
    return struct.pack("<Q", len(raw)) + raw


def gguf_value(value):
    if isinstance(value, bool):
        return 7, struct.pack("<?", value)
    if isinstance(value, int):
        return 11, struct.pack("<q", value)
    if isinstance(value, float):
        return 12, struct.pack("<d", value)
    if isinstance(value, str):
        return 8, gguf_string(value)
    if isinstance(value, list):
        parts = [struct.pack("<IQ", 8, len(value))]
        parts.extend(gguf_string(item) for item in value)
        return 9, b"".join(parts)
    raise TypeError(value)


def write_fixture(path, metadata):
    chunks = [b"GGUF", struct.pack("<IQQ", 3, 0, len(metadata))]
    for key, value in metadata.items():
        value_type, encoded = gguf_value(value)
        chunks.extend([gguf_string(key), struct.pack("<I", value_type), encoded])
    path.write_bytes(b"".join(chunks))


class LlmCustomTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.models = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_reads_selected_gguf_metadata_without_tensor_data(self):
        path = self.models / "moe.gguf"
        write_fixture(path, {
            "general.architecture": "qwen3moe",
            "general.name": "Fixture MoE",
            "general.tags": ["chat", "reasoning"],
            "qwen3moe.context_length": 131072,
            "qwen3moe.block_count": 40,
            "qwen3moe.expert_count": 128,
            "tokenizer.chat_template": "{% if enable_thinking %}<think>{% endif %}",
            "tokenizer.ggml.tokens": ["a", "b", "c"],
        })
        helper = load_helper()
        metadata = helper.read_gguf_metadata(path)
        self.assertEqual(metadata["general.architecture"], "qwen3moe")
        self.assertEqual(metadata["qwen3moe.context_length"], 131072)
        self.assertEqual(metadata["general.tags"], ["chat", "reasoning"])
        self.assertNotIn("tokenizer.ggml.tokens", metadata)

    def test_model_capabilities_drive_conditional_options(self):
        helper = load_helper()
        caps = helper.classify_model({
            "general.architecture": "qwen3moe",
            "general.name": "Qwen reasoning MoE",
            "qwen3moe.context_length": 131072,
            "qwen3moe.block_count": 40,
            "qwen3moe.expert_count": 128,
            "tokenizer.chat_template": "enable_thinking reasoning_content",
        }, "qwen.gguf")
        self.assertTrue(caps["moe"])
        self.assertTrue(caps["reasoning"])
        self.assertEqual(caps["contextLength"], 131072)
        keys = {option["key"] for section in helper.option_schema(caps, [], ["ROCm0"])
                for option in section["options"]}
        self.assertIn("cpu-moe", keys)
        self.assertIn("n-cpu-moe", keys)
        self.assertNotIn("n-cpu-ffn", keys)
        self.assertIn("reasoning", keys)
        ctx = next(option for section in helper.option_schema(caps, [], ["ROCm0"])
                   for option in section["options"] if option["key"] == "ctx-size")
        self.assertEqual(ctx["sliderMax"], 131072)
        self.assertNotIn("max", ctx)

    def test_dense_model_gets_dense_not_moe_controls(self):
        helper = load_helper()
        caps = helper.classify_model({
            "general.architecture": "llama",
            "llama.context_length": 32768,
            "llama.block_count": 32,
        }, "dense.gguf")
        keys = {option["key"] for section in helper.option_schema(caps, [], ["ROCm0"])
                for option in section["options"]}
        self.assertFalse(caps["moe"])
        self.assertIn("n-cpu-ffn", keys)
        self.assertNotIn("cpu-moe", keys)
        self.assertNotIn("reasoning", keys)

    def test_multimodal_detection_does_not_match_incidental_template_text(self):
        helper = load_helper()
        caps = helper.classify_model({
            "general.architecture": "llama",
            "tokenizer.chat_template": "{% set value = messages %}",
        }, "chat.gguf")
        self.assertFalse(caps["multimodal"])
        tagged = helper.classify_model({
            "general.architecture": "qwen35",
            "general.tags": ["image-text-to-text"],
        }, "vision.gguf")
        self.assertTrue(tagged["multimodal"])

    def test_non_text_gguf_is_identified_and_refused(self):
        helper = load_helper()
        caps = helper.classify_model({"general.architecture": "pig"}, "hy-3d.gguf")
        self.assertFalse(caps["serverCompatible"])
        model = self.models / "hy-3d.gguf"
        write_fixture(model, {"general.architecture": "pig"})
        with self.assertRaisesRegex(ValueError, "llama-server text model"):
            helper.build_command(model, {}, self.models, ["ROCm0"])

    def test_positive_only_flags_default_to_enabled_when_selected(self):
        helper = load_helper()
        caps = helper.classify_model({"general.architecture": "llama"}, "dense.gguf")
        options = [option for section in helper.option_schema(caps, [], ["ROCm0"])
                   for option in section["options"]]
        one_way = [option for option in options
                   if option["type"] == "bool" and option.get("falseFlag") == ""]
        self.assertGreater(len(one_way), 5)
        self.assertTrue(all(option["default"] == "true" for option in one_way))

    def test_build_command_validates_and_emits_explicit_arguments(self):
        model = self.models / "model.gguf"
        write_fixture(model, {"general.architecture": "llama", "llama.block_count": 32})
        helper = load_helper()
        command = helper.build_command(model, {
            "ctx-size": "32768",
            "device": "ROCm0",
            "n-gpu-layers": "auto",
            "fit": "on",
            "kv-offload": "false",
            "cache-type-k": "q8_0",
            "port": "8081",
        }, self.models, ["ROCm0"])
        self.assertEqual(command[:3], ["/usr/bin/llama-server", "--model", str(model)])
        self.assertIn("--no-kv-offload", command)
        self.assertEqual(command[command.index("--ctx-size") + 1], "32768")
        self.assertEqual(command[command.index("--device") + 1], "ROCm0")
        self.assertEqual(command[command.index("--port") + 1], "8081")

    def test_build_command_rejects_unknown_or_invalid_values(self):
        model = self.models / "model.gguf"
        write_fixture(model, {"general.architecture": "llama", "llama.block_count": 1})
        helper = load_helper()
        with self.assertRaisesRegex(ValueError, "unsupported option"):
            helper.build_command(model, {"invented": "yes"}, self.models, ["ROCm0"])
        with self.assertRaisesRegex(ValueError, "port"):
            helper.build_command(model, {"port": "70000"}, self.models, ["ROCm0"])
        with self.assertRaisesRegex(ValueError, "device"):
            helper.build_command(model, {"device": "CUDA0"}, self.models, ["ROCm0"])

    def test_schema_flags_exist_in_installed_llama_server(self):
        helper = load_helper()
        help_text = subprocess.run(["/usr/bin/llama-server", "--help"], text=True,
                                   capture_output=True, check=True).stdout
        caps = {"moe": True, "reasoning": True, "multimodal": True,
                "embedding": True, "rerank": True, "blockCount": 40,
                "expertCount": 128, "contextLength": 131072}
        missing = []
        for section in helper.option_schema(caps, [self.models / "draft.gguf"], ["ROCm0"]):
            for option in section["options"]:
                flags = [option["flag"]]
                if option["type"] == "bool":
                    flags = [option["trueFlag"]]
                    if option.get("falseFlag"):
                        flags.append(option["falseFlag"])
                missing.extend(flag for flag in flags if flag not in help_text)
        self.assertEqual(missing, [])

    def test_parse_fit_output_aggregates_host_and_device_breakdown(self):
        helper = load_helper()
        estimate = helper.parse_fit_output("ROCm0 5133 178 505\nHost 545 0 20\n")
        self.assertEqual(estimate["vramMiB"], 5816)
        self.assertEqual(estimate["ramMiB"], 565)
        self.assertEqual(estimate["totalMiB"], 6381)
        self.assertEqual(estimate["modelMiB"], 5678)
        self.assertEqual(estimate["contextMiB"], 178)
        self.assertEqual(estimate["computeMiB"], 525)
        self.assertEqual(estimate["devices"][0]["name"], "ROCm0")

    def test_estimate_resources_passes_only_memory_relevant_selected_options(self):
        model = self.models / "model.gguf"
        write_fixture(model, {
            "general.architecture": "qwen3moe",
            "qwen3moe.block_count": 32,
            "qwen3moe.context_length": 8192,
            "qwen3moe.expert_count": 64,
        })
        helper = load_helper()
        completed = subprocess.CompletedProcess([], 0,
            stdout="ROCm0 1000 300 200\nHost 4000 0 100\n", stderr="")
        with mock.patch.object(helper.subprocess, "run", return_value=completed) as runner:
            estimate = helper.estimate_resources(model, {
                "ctx-size": "32768", "cache-type-k": "q8_0",
                "cache-type-v": "q8_0", "kv-offload": "false",
                "n-gpu-layers": "12", "cpu-moe": "true",
                "port": "8081", "temperature": "0.2",
            }, self.models, ["ROCm0"])
        command = runner.call_args.args[0]
        self.assertEqual(command[0], "/usr/bin/llama-fit-params")
        self.assertIn("--fit-print", command)
        self.assertEqual(command[command.index("--ctx-size") + 1], "32768")
        self.assertIn("--no-kv-offload", command)
        self.assertIn("--cpu-moe", command)
        self.assertNotIn("--port", command)
        self.assertNotIn("--temperature", command)
        self.assertEqual(estimate["vramMiB"], 1500)
        self.assertEqual(estimate["ramMiB"], 4100)

    def test_estimate_resources_adds_draft_model_allocation(self):
        model = self.models / "model.gguf"
        draft = self.models / "draft.gguf"
        metadata = {"general.architecture": "llama", "llama.block_count": 2,
                    "llama.context_length": 8192}
        write_fixture(model, metadata)
        write_fixture(draft, metadata)
        helper = load_helper()
        main_result = subprocess.CompletedProcess([], 0,
            stdout="ROCm0 1000 200 100\nHost 100 0 20\n", stderr="")
        draft_result = subprocess.CompletedProcess([], 0,
            stdout="Host 500 100 50\n", stderr="")
        with mock.patch.object(helper.subprocess, "run",
                               side_effect=[main_result, draft_result]) as runner:
            estimate = helper.estimate_resources(model, {
                "model-draft": str(draft), "device-draft": "none",
                "n-gpu-layers-draft": "0", "ctx-size": "8192",
            }, self.models, ["ROCm0"])
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(estimate["totalMiB"], 2070)
        self.assertEqual(estimate["ramMiB"], 770)
        self.assertEqual(estimate["vramMiB"], 1300)
        self.assertEqual(estimate["draftMiB"], 650)

    def test_estimate_resources_adds_cpu_multimodal_projector(self):
        model = self.models / "vision.gguf"
        write_fixture(model, {"general.architecture": "qwen3vl", "qwen3vl.block_count": 2})
        projector = self.models / "mmproj.gguf"
        projector.write_bytes(b"x" * 1048576)
        helper = load_helper()
        completed = subprocess.CompletedProcess([], 0, stdout="Host 100 20 10\n", stderr="")
        with mock.patch.object(helper.subprocess, "run", return_value=completed):
            estimate = helper.estimate_resources(model, {
                "mmproj": str(projector), "mmproj-offload": "false",
            }, self.models, ["ROCm0"])
        self.assertEqual(estimate["ramMiB"], 131)
        self.assertEqual(estimate["totalMiB"], 131)
        self.assertEqual(estimate["auxiliaryMiB"], 1)

    def test_quick_profile_is_statically_decoded_without_execution(self):
        helper = load_helper()
        script = self.models / "profile"
        script.write_text("""#!/usr/bin/env bash
set -euo pipefail
MODEL=\"${1:?model}\"
CTX=\"${CTX:-32768}\"
THREADS=\"${THREADS:-8}\"
exec llama-server \\
    -m \"$MODEL\" \\
    -dev ROCm0 \\
    -c \"$CTX\" \\
    -nkvo \\
    -ctk q8_0 \\
    -t \"$THREADS\" \\
    --port 8080
""")
        values = helper.read_quick_profile(script)
        self.assertEqual(values["device"], "ROCm0")
        self.assertEqual(values["ctx-size"], "32768")
        self.assertEqual(values["kv-offload"], "false")
        self.assertEqual(values["cache-type-k"], "q8_0")
        self.assertEqual(values["threads"], "8")
        self.assertNotIn("port", values)

    def test_inspect_cli_returns_json_schema(self):
        model = self.models / "model.gguf"
        write_fixture(model, {
            "general.architecture": "llama",
            "general.name": "Fixture",
            "llama.context_length": 8192,
        })
        result = subprocess.run(
            ["python", str(HELPER), "inspect", str(model), "--models-dir", str(self.models),
             "--devices", "ROCm0"], text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["model"]["name"], "Fixture")
        self.assertEqual(payload["model"]["contextLength"], 8192)
        self.assertGreater(len(payload["sections"]), 8)


if __name__ == "__main__":
    unittest.main()
