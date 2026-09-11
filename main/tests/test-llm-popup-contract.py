#!/usr/bin/env python3
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class LlmPopupContractTests(unittest.TestCase):
    def test_popup_has_two_named_tabs_and_scrollable_custom_form(self):
        source = (ROOT / "LlmPopup.qml").read_text()
        self.assertIn('model: ["Quick Start", "Custom"]', source)
        self.assertIn("id: customScroll", source)
        self.assertIn("id: customSectionRepeater", source)

    def test_custom_mode_inspects_and_launches_through_validating_helper(self):
        source = (ROOT / "LlmPopup.qml").read_text()
        self.assertIn('"inspect"', source)
        self.assertIn('"estimate"', source)
        self.assertIn('"run"', source)
        self.assertIn("customValuesJson()", source)
        self.assertIn("modelInspection.model", source)

    def test_popup_shows_reactive_total_ram_and_vram_estimate_at_top(self):
        source = (ROOT / "LlmPopup.qml").read_text()
        self.assertIn("id: resourceCard", source)
        self.assertIn("resourceEstimate.totalMiB", source)
        self.assertIn("resourceEstimate.ramMiB", source)
        self.assertIn("resourceEstimate.vramMiB", source)
        self.assertIn("estimateDebounce", source)

    def test_bounded_numeric_options_use_slider_editor_with_text_fallback(self):
        source = (ROOT / "LlmPopup.qml").read_text()
        self.assertIn("boundedNumeric", source)
        self.assertIn("id: rangeSlider", source)
        self.assertIn("optionData.sliderMax", source)
        self.assertIn("id: rangeValue", source)

    def test_custom_configuration_persistence_is_model_keyed(self):
        source = (ROOT / "LlmPopup.qml").read_text()
        self.assertIn("customStatePath", source)
        self.assertIn("restoreCustomState()", source)
        self.assertIn("writeCustomState()", source)
        self.assertIn("models[modelPath()]", source)
        self.assertIn("onLoadFailed", source)

    def test_quick_start_keeps_script_and_model_selection(self):
        source = (ROOT / "LlmPopup.qml").read_text()
        self.assertIn("id: scriptCombo", source)
        self.assertIn("id: quickModelCombo", source)
        self.assertIn("startQuickLlama()", source)

    def test_lifecycle_ipc_exposes_llm_tab_and_inspection_state(self):
        source = (ROOT / "Bar.qml").read_text()
        self.assertIn("function llmTab(index: int)", source)
        self.assertIn("out.llm.tab", source)
        self.assertIn("out.llm.sections", source)
        self.assertIn("function llmSection(index: int, expanded: bool)", source)
        self.assertIn("function llmOption(key: string, value: string, enabled: bool)", source)
        self.assertIn("out.llm.estimate", source)


if __name__ == "__main__":
    unittest.main()
