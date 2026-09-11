import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

LifecyclePopup {
    id: llmPopup
    property var barWindow
    property int selectedTab: 0
    property string selectedScript: scripts.length > 0 ? scripts[0] : ""
    property string selectedModel: models.length > 0 ? models[0] : ""
    property string launchUrl: "http://127.0.0.1:8080"
    property string scriptsText: ""
    property string modelsText: ""
    property var scripts: []
    property var models: []
    property var modelInspection: ({})
    property var customSections: []
    property var customValues: ({})
    property var customEnabled: ({})
    property var savedCustomState: ({version: 1, models: ({})})
    property bool customStateLoaded: false
    property var resourceEstimate: ({})
    property string estimateStatus: "Select a model to calculate memory requirements."
    property int estimateRequestSerial: 0
    property string expectedEstimateRequest: ""
    property string inspectionStatus: "Select a GGUF model to inspect its capabilities."
    property string processStatus: "Idle"
    property string runningMode: ""
    readonly property bool inspectorActive: inspectorProcess.running
    readonly property bool estimateActive: estimateProcess.running
    readonly property bool serverRunning: llamaProcess.running

    onSelectedTabChanged: scheduleEstimate()
    onSelectedScriptChanged: scheduleEstimate()
    onSelectedModelChanged: scheduleEstimate()
    onVisibleChanged: {
        if (visible) {
            refreshDiscovery()
            scheduleEstimate()
        } else {
            estimateRequestSerial += 1
            expectedEstimateRequest = String(estimateRequestSerial)
            estimateDebounce.stop()
            if (estimateProcess.running) estimateProcess.running = false
        }
    }

    readonly property string llamaDirectory: Quickshell.env("LLAMA_DIR") || ((Quickshell.env("HOME") || "") + "/Work/AI_Dev/Llama")
    readonly property string modelsDirectory: llamaDirectory + "/Models"
    readonly property string helperPath: Qt.resolvedUrl("llm-custom.py").toString().replace("file://", "")
    readonly property string customStatePath: (Quickshell.env("XDG_CONFIG_HOME") ||
                                                ((Quickshell.env("HOME") || "") + "/.config")) +
                                               "/quickshell/main/llm-custom-state.json"

    anchor.window: barWindow
    anchor.rect.x: (barWindow.width - width) / 2
    anchor.rect.y: barWindow.height - barWindow.taskbarHeight - 3
    anchor.gravity: Edges.Top | Edges.Right
    implicitWidth: selectedTab === 0 ? 430 : Math.min(780, barWindow.width - 40)
    implicitHeight: selectedTab === 0 ? 510 : Math.min(780, barWindow.screen.height - barWindow.taskbarHeight - 54)
    color: "transparent"
    visible: false
    grabFocus: true

    Process {
        id: scriptListProcess
        command: ["bash", "-c", "find '" + llmPopup.llamaDirectory + "' -maxdepth 1 -type f -executable -printf '%f\\n' | sort"]
        running: true
        stdout: StdioCollector { id: scriptOutput }
        onExited: {
            llmPopup.scriptsText = scriptOutput.text.trim()
            llmPopup.scripts = llmPopup.scriptsText ? llmPopup.scriptsText.split("\n") : []
            if (llmPopup.scripts.indexOf(llmPopup.selectedScript) < 0)
                llmPopup.selectedScript = llmPopup.scripts.length ? llmPopup.scripts[0] : ""
            llmPopup.scheduleEstimate()
        }
    }

    Process {
        id: modelListProcess
        command: ["bash", "-c", "find '" + llmPopup.modelsDirectory + "' -maxdepth 1 -type f -iname '*.gguf' -printf '%f\\n' | sort"]
        running: true
        stdout: StdioCollector { id: modelOutput }
        onExited: {
            llmPopup.modelsText = modelOutput.text.trim()
            llmPopup.models = llmPopup.modelsText ? llmPopup.modelsText.split("\n") : []
            if (llmPopup.models.indexOf(llmPopup.selectedModel) < 0)
                llmPopup.selectedModel = llmPopup.models.length ? llmPopup.models[0] : ""
            llmPopup.requestInspection()
        }
    }

    Process {
        id: inspectorProcess
        running: false
        stdout: StdioCollector { id: inspectorOutput }
        stderr: StdioCollector { id: inspectorError }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                llmPopup.modelInspection = ({})
                llmPopup.customSections = []
                llmPopup.inspectionStatus = inspectorError.text.trim() || "GGUF inspection failed."
                return
            }
            try {
                const payload = JSON.parse(inspectorOutput.text)
                const expected = llmPopup.modelsDirectory + "/" + llmPopup.selectedModel
                if (payload.file !== expected) return
                llmPopup.modelInspection = payload
                llmPopup.customSections = payload.sections || []
                const values = {}
                const enabled = {}
                for (const group of llmPopup.customSections) {
                    for (const option of group.options || []) {
                        values[option.key] = String(option.default ?? "")
                        enabled[option.key] = false
                    }
                }
                llmPopup.customValues = values
                llmPopup.customEnabled = enabled
                llmPopup.restoreCustomState()
                const model = payload.model || {}
                const kind = model.moe ? "MoE" : "dense"
                const context = model.contextLength ? (" | context " + model.contextLength) : ""
                const compatibility = model.serverCompatible ? "" : " | incompatible with llama-server"
                llmPopup.inspectionStatus = (model.name || llmPopup.selectedModel) + " | " +
                    (model.architecture || "unknown") + " | " + kind + context + compatibility
                llmPopup.scheduleEstimate()
            } catch (error) {
                llmPopup.modelInspection = ({})
                llmPopup.customSections = []
                llmPopup.inspectionStatus = "Invalid inspector response: " + error
            }
        }
    }

    Timer {
        id: estimateDebounce
        interval: 350
        repeat: false
        onTriggered: llmPopup.requestResourceEstimate()
    }

    Timer {
        id: customStateSaveDebounce
        interval: 250
        repeat: false
        onTriggered: llmPopup.writeCustomState()
    }

    FileView {
        id: customStateFile
        path: llmPopup.customStatePath
        preload: true
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (parsed && typeof parsed === "object" && parsed.models && typeof parsed.models === "object")
                    llmPopup.savedCustomState = {version: 1, models: parsed.models}
            } catch (error) {
                llmPopup.savedCustomState = {version: 1, models: ({})}
            }
            llmPopup.customStateLoaded = true
            llmPopup.restoreCustomState()
        }
        onLoadFailed: {
            // First run: an absent state file is a valid empty state.
            llmPopup.customStateLoaded = true
            llmPopup.restoreCustomState()
        }
    }

    Process {
        id: estimateProcess
        property string requestId: ""
        running: false
        stdout: StdioCollector { id: estimateOutput }
        stderr: StdioCollector { id: estimateError }
        onExited: function(exitCode) {
            if (requestId !== llmPopup.expectedEstimateRequest) return
            if (exitCode !== 0) {
                if (llmPopup.expectedEstimateRequest !== "") {
                    llmPopup.resourceEstimate = ({})
                    llmPopup.estimateStatus = estimateError.text.trim() || "Memory estimate unavailable."
                }
                return
            }
            try {
                const payload = JSON.parse(estimateOutput.text)
                if (String(payload.requestId) !== llmPopup.expectedEstimateRequest) return
                if (payload.file !== llmPopup.modelPath()) return
                llmPopup.resourceEstimate = payload
                llmPopup.estimateStatus = payload.note || "Upstream llama.cpp allocation estimate."
            } catch (error) {
                llmPopup.resourceEstimate = ({})
                llmPopup.estimateStatus = "Invalid memory-estimator response: " + error
            }
        }
    }

    Process {
        id: llamaProcess
        running: false
        stdout: StdioCollector { id: llamaOutput }
        stderr: StdioCollector { id: llamaError }
        onExited: function(exitCode) {
            llmPopup.processStatus = exitCode === 0 ? "Stopped" :
                (llamaError.text.trim() || ("Exited with code " + exitCode))
            llmPopup.runningMode = ""
        }
    }

    function modelPath() {
        return selectedModel ? modelsDirectory + "/" + selectedModel : ""
    }

    function refreshDiscovery() {
        if (modelListProcess.running) modelListProcess.running = false
        if (scriptListProcess.running) scriptListProcess.running = false
        Qt.callLater(function() {
            modelListProcess.running = true
            scriptListProcess.running = true
        })
    }

    function requestInspection() {
        if (!selectedModel) return
        if (inspectorProcess.running) inspectorProcess.running = false
        inspectionStatus = "Reading GGUF metadata..."
        const command = ["/usr/bin/python", helperPath, "inspect", modelPath(),
                         "--models-dir", modelsDirectory]
        Qt.callLater(function() {
            inspectorProcess.command = command
            inspectorProcess.running = true
        })
    }

    function scheduleEstimate() {
        estimateRequestSerial += 1
        expectedEstimateRequest = String(estimateRequestSerial)
        resourceEstimate = ({})
        estimateStatus = selectedModel ? "Calculating model, context, compute, RAM and VRAM..." :
                                         "Select a model to calculate memory requirements."
        if (!visible) {
            estimateDebounce.stop()
            return
        }
        estimateDebounce.restart()
    }

    function requestResourceEstimate() {
        if (!selectedModel) return
        if (estimateProcess.running) estimateProcess.running = false
        const requestId = expectedEstimateRequest
        const command = ["/usr/bin/python", helperPath, "estimate", modelPath(),
                         selectedTab === 1 ? customValuesJson() : "{}",
                         "--models-dir", modelsDirectory, "--request-id", requestId]
        if (selectedTab === 0) {
            if (!selectedScript) return
            command.push("--script", llamaDirectory + "/" + selectedScript)
        }
        Qt.callLater(function() {
            if (requestId !== llmPopup.expectedEstimateRequest) return
            estimateProcess.requestId = requestId
            estimateProcess.command = command
            estimateProcess.running = true
        })
    }

    function formatMemory(mib) {
        const bytes = Number(mib || 0) * 1048576
        if (bytes >= 1000000000) return (bytes / 1000000000).toFixed(2) + " GB"
        return Math.round(bytes / 1000000) + " MB"
    }

    function setCustomEnabled(key, enabled) {
        const copy = Object.assign({}, customEnabled)
        copy[key] = enabled
        customEnabled = copy
        scheduleCustomStateSave()
        scheduleEstimate()
    }

    function setCustomValue(key, value) {
        const copy = Object.assign({}, customValues)
        copy[key] = String(value)
        customValues = copy
        scheduleCustomStateSave()
        scheduleEstimate()
    }

    function restoreCustomState() {
        if (!customStateLoaded || !selectedModel || !customSections.length)
            return
        const stored = savedCustomState.models[modelPath()]
        if (!stored || typeof stored !== "object")
            return
        const values = Object.assign({}, customValues)
        const enabled = Object.assign({}, customEnabled)
        for (const key of Object.keys(values)) {
            if (stored.values && stored.values[key] !== undefined)
                values[key] = String(stored.values[key])
            if (stored.enabled && stored.enabled[key] !== undefined)
                enabled[key] = !!stored.enabled[key]
        }
        customValues = values
        customEnabled = enabled
    }

    function scheduleCustomStateSave() {
        if (customStateLoaded && selectedModel)
            customStateSaveDebounce.restart()
    }

    function writeCustomState() {
        if (!customStateLoaded || !selectedModel)
            return
        const models = Object.assign({}, savedCustomState.models || {})
        models[modelPath()] = {
            values: Object.assign({}, customValues),
            enabled: Object.assign({}, customEnabled)
        }
        savedCustomState = {version: 1, models: models}
        customStateFile.setText(JSON.stringify(savedCustomState, null, 2))
        customStateFile.writeAdapter()
    }

    function customValuesJson() {
        const selected = {}
        for (const key of Object.keys(customEnabled))
            if (customEnabled[key]) selected[key] = String(customValues[key] ?? "")
        return JSON.stringify(selected)
    }

    function applyRecommendedBaseline() {
        const keys = ["device", "n-gpu-layers", "fit", "fit-target", "fit-ctx",
                      "flash-attn", "kv-offload", "cache-type-k", "cache-type-v",
                      "parallel", "host", "port"]
        const enabled = Object.assign({}, customEnabled)
        for (const key of keys)
            if (customValues[key] !== undefined) enabled[key] = true
        customEnabled = enabled
        scheduleEstimate()
    }

    function clearOverrides() {
        const enabled = Object.assign({}, customEnabled)
        for (const key of Object.keys(enabled)) enabled[key] = false
        customEnabled = enabled
        scheduleEstimate()
    }

    function setSectionExpanded(index, expanded) {
        const card = customSectionRepeater.itemAt(index)
        if (card) card.expanded = expanded
    }

    function startQuickLlama() {
        if (llamaProcess.running || !selectedScript || !selectedModel) return
        llamaProcess.command = ["bash", llamaDirectory + "/" + selectedScript, modelPath()]
        runningMode = "Quick Start"
        processStatus = "Starting Quick Start profile..."
        llamaProcess.running = true
    }

    function startCustomLlama() {
        if (llamaProcess.running || !selectedModel || !modelInspection.model || !modelInspection.model.serverCompatible) return
        llamaProcess.command = ["/usr/bin/python", helperPath, "run", modelPath(),
                                customValuesJson(), "--models-dir", modelsDirectory]
        runningMode = "Custom"
        processStatus = "Validating and starting custom configuration..."
        llamaProcess.running = true
    }

    function stopLlama() {
        if (llamaProcess.running) {
            processStatus = "Stopping..."
            llamaProcess.running = false
        }
    }

    function effectiveLaunchUrl() {
        if (selectedTab !== 1) return launchUrl
        let host = customEnabled.host ? customValues.host : "127.0.0.1"
        const port = customEnabled.port ? customValues.port : "8080"
        if (host === "0.0.0.0" || host === "::") host = "127.0.0.1"
        if (String(host).endsWith(".sock")) return "Unix socket: " + host
        return "http://" + host + ":" + port
    }

    function openUi() {
        const url = effectiveLaunchUrl()
        if (url.startsWith("http")) Quickshell.execDetached(["xdg-open", url])
    }

    component SelectorCombo: ComboBox {
        id: combo
        signal optionSelected(string value)
        property string selectedValue: ""
        width: parent ? parent.width : 200
        height: 34
        font.pixelSize: 12
        model: []

        function syncSelection() {
            const values = Array.from(combo.model || [])
            const found = values.indexOf(combo.selectedValue)
            combo.currentIndex = found >= 0 ? found : (values.length ? 0 : -1)
        }
        onModelChanged: syncSelection()
        onSelectedValueChanged: syncSelection()
        Component.onCompleted: syncSelection()

        contentItem: Text {
            leftPadding: 10
            rightPadding: combo.indicator.width + 10
            text: combo.currentText || "No options found"
            color: "#e4f5ff"
            elide: Text.ElideMiddle
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 5
            color: combo.popup.visible ? "#36586b" : "#263843"
            border.color: "#668faabd"
        }
        indicator: Text {
            x: combo.width - width - 10
            y: (combo.height - height) / 2
            text: combo.popup.visible ? "▲" : "▼"
            color: "#bfeaff"
            font.pixelSize: 10
        }
        popup: Popup {
            y: combo.height + 4
            width: combo.width
            modal: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            padding: 1
            contentItem: ListView {
                clip: true
                implicitHeight: Math.min(240, contentHeight)
                model: combo.model
                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: combo.width - 2
                    height: 30
                    text: String(modelData)
                    font.pixelSize: 12
                    highlighted: combo.highlightedIndex === index
                    onClicked: {
                        combo.currentIndex = index
                        combo.optionSelected(String(modelData))
                        combo.popup.close()
                    }
                }
            }
            background: Rectangle {
                radius: 5
                color: "#18242c"
                border.color: "#668faabd"
            }
        }
    }

    component ActionButton: Rectangle {
        id: action
        property string label: ""
        property bool active: true
        property color normalColor: "#2f513d"
        signal clicked()
        height: 34
        radius: 5
        color: !active ? "#252b30" : (actionMouse.containsMouse ? Qt.lighter(normalColor, 1.18) : normalColor)
        opacity: active ? 1 : 0.45
        Text { anchors.centerIn: parent; text: action.label; color: action.active ? "#d9f4e0" : "#7f8a90"; font.bold: true; font.pixelSize: 12 }
        MouseArea {
            id: actionMouse
            anchors.fill: parent
            enabled: action.active
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.clicked()
        }
    }

    component OptionEditor: Item {
        id: editor
        required property var optionData
        width: 310
        height: 32
        readonly property bool boundedNumeric: (optionData.type === "int" || optionData.type === "float" || optionData.type === "gpu_layers") &&
                                                optionData.min !== undefined &&
                                                (optionData.max !== undefined || optionData.sliderMax !== undefined)
        Loader {
            anchors.fill: parent
            sourceComponent: (editor.optionData.type === "enum" || editor.optionData.type === "bool") ? enumEditor :
                             (editor.boundedNumeric ? rangeEditor : textEditor)
        }
        Component {
            id: enumEditor
            SelectorCombo {
                model: editor.optionData.choices || []
                selectedValue: String(llmPopup.customValues[editor.optionData.key] ?? editor.optionData.default ?? "")
                onOptionSelected: llmPopup.setCustomValue(editor.optionData.key, value)
            }
        }
        Component {
            id: rangeEditor
            Row {
                spacing: 6
                property real lowerBound: Number(editor.optionData.min)
                property real upperBound: Number(editor.optionData.sliderMax ?? editor.optionData.max)
                property real increment: Number(editor.optionData.step || (editor.optionData.type === "float" ? 0.01 : 1))
                property real currentNumber: Number(llmPopup.customValues[editor.optionData.key] ?? editor.optionData.default)
                Slider {
                    id: rangeSlider
                    width: parent.width - rangeValue.width - 6
                    height: parent.height
                    from: parent.lowerBound
                    to: parent.upperBound
                    stepSize: parent.increment
                    snapMode: Slider.SnapAlways
                    value: Number.isFinite(parent.currentNumber) ? Math.min(to, Math.max(from, parent.currentNumber)) : from
                    onMoved: llmPopup.setCustomValue(editor.optionData.key,
                        editor.optionData.type === "float" ? Number(value.toFixed(4)) : Math.round(value))
                }
                TextField {
                    id: rangeValue
                    width: 86
                    height: 32
                    text: String(llmPopup.customValues[editor.optionData.key] ?? editor.optionData.default ?? "")
                    color: "#e4f5ff"
                    font.pixelSize: 12
                    selectByMouse: true
                    horizontalAlignment: Text.AlignRight
                    onEditingFinished: llmPopup.setCustomValue(editor.optionData.key, text)
                    background: Rectangle {
                        radius: 5
                        color: "#263843"
                        border.color: parent.activeFocus ? "#8fcdf0" : "#668faabd"
                    }
                }
            }
        }
        Component {
            id: textEditor
            TextField {
                text: String(llmPopup.customValues[editor.optionData.key] ?? editor.optionData.default ?? "")
                color: "#e4f5ff"
                font.pixelSize: 12
                selectByMouse: true
                placeholderText: editor.optionData.help || "Optional value"
                onEditingFinished: llmPopup.setCustomValue(editor.optionData.key, text)
                background: Rectangle {
                    radius: 5
                    color: "#263843"
                    border.color: parent.activeFocus ? "#8fcdf0" : "#668faabd"
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "#f0262626"
        border.color: "#555555"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            Text {
                width: parent.width
                height: 24
                text: "󰚩  Llama Server"
                color: "#bfeaff"
                font.family: "Symbols Nerd Font"
                font.bold: true
                font.pixelSize: 15
                verticalAlignment: Text.AlignVCenter
            }

            Row {
                width: parent.width
                height: 34
                spacing: 6
                Repeater {
                    model: ["Quick Start", "Custom"]
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: (parent.width - 6) / 2
                        height: 34
                        radius: 5
                        color: llmPopup.selectedTab === index ? "#36586b" : (tabMouse.containsMouse ? "#2f4654" : "#202f38")
                        border.color: llmPopup.selectedTab === index ? "#8fcdf0" : "#4f6570"
                        Text { anchors.centerIn: parent; text: modelData; color: llmPopup.selectedTab === index ? "#dff6ff" : "#94a9b5"; font.bold: true; font.pixelSize: 12 }
                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: llmPopup.selectedTab = index
                        }
                    }
                }
            }

            Rectangle {
                id: resourceCard
                width: parent.width
                height: 82
                radius: 6
                color: "#1d3039"
                border.color: llmPopup.resourceEstimate.totalMiB !== undefined ? "#58829a" : "#41525c"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    text: "Estimated allocation"
                    color: "#a9d8ea"
                    font.bold: true
                    font.pixelSize: 11
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    text: estimateProcess.running ? "calculating..." : "llama.cpp fit estimator"
                    color: "#7693a2"
                    font.pixelSize: 9
                }
                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    anchors.top: parent.top
                    anchors.topMargin: 26
                    text: llmPopup.resourceEstimate.totalMiB !== undefined ?
                          ("Total " + llmPopup.formatMemory(llmPopup.resourceEstimate.totalMiB) +
                           "   •   RAM " + llmPopup.formatMemory(llmPopup.resourceEstimate.ramMiB) +
                           "   •   VRAM " + llmPopup.formatMemory(llmPopup.resourceEstimate.vramMiB)) :
                          llmPopup.estimateStatus
                    color: llmPopup.resourceEstimate.totalMiB !== undefined ? "#d9f4e0" : "#c8ab84"
                    font.bold: llmPopup.resourceEstimate.totalMiB !== undefined
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Text {
                    visible: llmPopup.resourceEstimate.totalMiB !== undefined
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    anchors.top: parent.top
                    anchors.topMargin: 47
                    text: "Weights " + llmPopup.formatMemory(llmPopup.resourceEstimate.modelMiB) +
                          "   •   Context/KV " + llmPopup.formatMemory(llmPopup.resourceEstimate.contextMiB) +
                          "   •   Compute " + llmPopup.formatMemory(llmPopup.resourceEstimate.computeMiB)
                    color: "#aabfc9"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                Text {
                    visible: llmPopup.resourceEstimate.totalMiB !== undefined
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    text: llmPopup.estimateStatus
                    color: "#718b98"
                    font.pixelSize: 8
                    elide: Text.ElideRight
                }
            }

            Item {
                width: parent.width
                height: parent.height - 24 - 34 - resourceCard.height - 24

                Column {
                    visible: llmPopup.selectedTab === 0
                    anchors.fill: parent
                    spacing: 9

                    Text { text: "Script"; color: "#8da7b7"; font.pixelSize: 11 }
                    SelectorCombo {
                        id: scriptCombo
                        model: llmPopup.scripts
                        selectedValue: llmPopup.selectedScript
                        onOptionSelected: llmPopup.selectedScript = value
                    }

                    Text { text: "Model"; color: "#8da7b7"; font.pixelSize: 11 }
                    SelectorCombo {
                        id: quickModelCombo
                        model: llmPopup.models
                        selectedValue: llmPopup.selectedModel
                        onOptionSelected: {
                            llmPopup.selectedModel = value
                            llmPopup.requestInspection()
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 60
                        radius: 5
                        color: "#202c33"
                        Text {
                            anchors.fill: parent
                            anchors.margins: 9
                            text: "Quick Start preserves the existing script profiles and their tuned AMD ROCm settings."
                            color: "#9fb2bd"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }

                    Item { width: 1; height: 3 }
                    Text {
                        text: llmPopup.effectiveLaunchUrl()
                        color: "#8fb8ff"
                        font.pixelSize: 12
                        font.underline: true
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: llmPopup.openUi() }
                    }
                    Text { width: parent.width; text: llmPopup.processStatus; color: "#9fb2bd"; font.pixelSize: 11; elide: Text.ElideRight }
                    Item { width: 1; height: 1 }
                    Row {
                        width: parent.width
                        spacing: 10
                        ActionButton {
                            width: (parent.width - 10) / 2
                            label: "Start"
                            active: !llamaProcess.running && !!llmPopup.selectedScript && !!llmPopup.selectedModel
                            onClicked: llmPopup.startQuickLlama()
                        }
                        ActionButton {
                            width: (parent.width - 10) / 2
                            label: "Stop"
                            active: llamaProcess.running
                            normalColor: "#533636"
                            onClicked: llmPopup.stopLlama()
                        }
                    }
                }

                Column {
                    visible: llmPopup.selectedTab === 1
                    anchors.fill: parent
                    spacing: 7

                    Text { text: "GGUF model"; color: "#8da7b7"; font.pixelSize: 11 }
                    SelectorCombo {
                        id: customModelCombo
                        model: llmPopup.models
                        selectedValue: llmPopup.selectedModel
                        onOptionSelected: {
                            llmPopup.selectedModel = value
                            llmPopup.requestInspection()
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 44
                        radius: 5
                        color: "#202c33"
                        Text {
                            anchors.fill: parent
                            anchors.margins: 8
                            text: llmPopup.inspectionStatus
                            color: llmPopup.modelInspection.model && llmPopup.modelInspection.model.serverCompatible ? "#b9e7c5" : "#d6b58a"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        width: parent.width
                        height: 30
                        spacing: 7
                        ActionButton {
                            width: (parent.width - 14) / 3
                            height: 30
                            label: "Suggested baseline"
                            active: !!llmPopup.modelInspection.model
                            onClicked: llmPopup.applyRecommendedBaseline()
                        }
                        ActionButton {
                            width: (parent.width - 14) / 3
                            height: 30
                            label: "Clear overrides"
                            normalColor: "#3c4850"
                            active: !!llmPopup.modelInspection.model
                            onClicked: llmPopup.clearOverrides()
                        }
                        ActionButton {
                            width: (parent.width - 14) / 3
                            height: 30
                            label: "Reinspect GGUF"
                            normalColor: "#3c4850"
                            active: !inspectorProcess.running && !!llmPopup.selectedModel
                            onClicked: llmPopup.requestInspection()
                        }
                    }

                    ScrollView {
                        id: customScroll
                        width: parent.width
                        height: parent.height - 206
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        Column {
                            width: customScroll.availableWidth
                            spacing: 7

                            Repeater {
                                id: customSectionRepeater
                                model: llmPopup.customSections
                                delegate: Rectangle {
                                    id: sectionCard
                                    required property var modelData
                                    property bool expanded: false
                                    width: parent.width
                                    height: header.height + (expanded ? optionsColumn.implicitHeight + 12 : 0)
                                    radius: 6
                                    color: "#202c33"
                                    border.color: expanded ? "#668faabd" : "#41525c"

                                    Rectangle {
                                        id: header
                                        width: parent.width
                                        height: 38
                                        radius: 6
                                        color: headerMouse.containsMouse ? "#2b414d" : "#24343d"
                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: (sectionCard.expanded ? "▼  " : "▶  ") + sectionCard.modelData.name
                                            color: "#c6e9f7"
                                            font.bold: true
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            anchors.right: parent.right
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: (sectionCard.modelData.options || []).length + " options"
                                            color: "#7993a1"
                                            font.pixelSize: 10
                                        }
                                        MouseArea {
                                            id: headerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: sectionCard.expanded = !sectionCard.expanded
                                        }
                                    }

                                    Column {
                                        id: optionsColumn
                                        visible: sectionCard.expanded
                                        anchors.top: header.bottom
                                        anchors.topMargin: 6
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.margins: 6
                                        spacing: 4

                                        Text {
                                            visible: !!sectionCard.modelData.note
                                            width: parent.width
                                            text: sectionCard.modelData.note || ""
                                            color: sectionCard.modelData.name.indexOf("Dangerous") >= 0 ? "#f0b28f" : "#8fa5b0"
                                            font.pixelSize: 10
                                            wrapMode: Text.WordWrap
                                        }

                                        Repeater {
                                            model: sectionCard.modelData.options || []
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: parent.width
                                                height: 38
                                                radius: 4
                                                color: llmPopup.customEnabled[modelData.key] ? "#293d48" : "#1b272e"

                                                Rectangle {
                                                    id: overrideBox
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 8
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 18
                                                    height: 18
                                                    radius: 3
                                                    color: llmPopup.customEnabled[modelData.key] ? "#4d89a5" : "#172027"
                                                    border.color: "#7398aa"
                                                    Text { anchors.centerIn: parent; text: llmPopup.customEnabled[modelData.key] ? "✓" : ""; color: "white"; font.pixelSize: 12 }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: llmPopup.setCustomEnabled(modelData.key, !llmPopup.customEnabled[modelData.key])
                                                    }
                                                }

                                                Text {
                                                    anchors.left: overrideBox.right
                                                    anchors.leftMargin: 8
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Math.max(180, parent.width * 0.38)
                                                    text: modelData.label
                                                    color: llmPopup.customEnabled[modelData.key] ? "#d2e8f2" : "#8296a0"
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }

                                                OptionEditor {
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Math.max(250, parent.width * 0.48)
                                                    optionData: modelData
                                                    opacity: llmPopup.customEnabled[modelData.key] ? 1 : 0.55
                                                    enabled: !!llmPopup.customEnabled[modelData.key]
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: llmPopup.processStatus
                        color: "#9fb2bd"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                    Row {
                        width: parent.width
                        height: 34
                        spacing: 8
                        ActionButton {
                            width: (parent.width - 16) * 0.44
                            label: "Start Custom"
                            active: !llamaProcess.running && !!llmPopup.modelInspection.model && !!llmPopup.modelInspection.model.serverCompatible && !inspectorProcess.running
                            onClicked: llmPopup.startCustomLlama()
                        }
                        ActionButton {
                            width: (parent.width - 16) * 0.28
                            label: "Stop"
                            active: llamaProcess.running
                            normalColor: "#533636"
                            onClicked: llmPopup.stopLlama()
                        }
                        ActionButton {
                            width: (parent.width - 16) * 0.28
                            label: "Open UI"
                            normalColor: "#3c4850"
                            active: llmPopup.effectiveLaunchUrl().startsWith("http")
                            onClicked: llmPopup.openUi()
                        }
                    }
                }
            }
        }
    }
}
