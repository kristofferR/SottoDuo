import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: root
    required property var ui
    clip: true
    contentWidth: availableWidth
    ColumnLayout {
        width: root.availableWidth
        spacing: 22
        SLabel {
            ui: root.ui
            text: "This computer"
            font.pixelSize: 28
            font.weight: Font.DemiBold
        }
        SLabel {
            ui: root.ui
            text: "Connection, appearance and desktop integration."
            color: root.ui.c.muted
        }
        Group {
            ui: root.ui
            title: "CONNECTION"
            Setting {
                ui: root.ui
                title: "Server address"
                detail: root.ui.snapshot.server || "Available after dictation connects"
            }
            Setting {
                ui: root.ui
                title: "Device name"
                SLabel {
                    ui: root.ui
                    text: root.ui.snapshot.device ? root.ui.snapshot.device.name : "This computer"
                }
            }
            Setting {
                ui: root.ui
                title: root.ui.connection
                SButton {
                    ui: root.ui
                    text: "Reconnect"
                    onClicked: {
                        bridge.request("snapshot");
                        root.ui.refresh();
                    }
                }
            }
        }
        Group {
            ui: root.ui
            title: "APPEARANCE"
            Setting {
                ui: root.ui
                title: "Theme"
                detail: "Only this computer. All themes use the same layout."
                ComboBox {
                    implicitWidth: 245
                    model: ["Follow system", "Sotto · Warm light", "Sotto · Glacier dark", "Omarchy · Active theme"]
                    currentIndex: ["system", "light", "dark", "omarchy"].indexOf(bridge.theme)
                    onActivated: bridge.theme = ["system", "light", "dark", "omarchy"][currentIndex]
                }
            }
            Setting {
                ui: root.ui
                visible: bridge.theme === "omarchy"
                title: "Omarchy colors"
                detail: bridge.themeNote
            }
        }
        Group {
            ui: root.ui
            title: "DJI RECEIVER ON SERVER"
            Setting {
                ui: root.ui
                title: "Pairing-button destination"
                detail: root.ui.snapshot.button && root.ui.snapshot.button.selected ? root.ui.snapshot.button.selected.device.name : "No destination selected"
                SButton {
                    ui: root.ui
                    text: "Use this computer"
                    enabled: bridge.connected && root.ui.snapshot.buttonEnabled
                    onClicked: bridge.request("arm")
                }
                SButton {
                    ui: root.ui
                    text: "Release"
                    enabled: bridge.connected && root.ui.snapshot.buttonEnabled
                    onClicked: bridge.request("disarm")
                }
            }
            Setting {
                ui: root.ui
                title: "Receiver dictation"
                detail: root.ui.snapshot.buttonEnabled ? "Select this computer, focus your text field, then tap the transmitter’s pairing button." : !bridge.connected ? "Connect dictation to check receiver availability." : "Pairing-button dictation hasn’t been enabled on this computer."
            }
        }
        Group {
            ui: root.ui
            title: "DESKTOP INTEGRATION"
            Setting {
                ui: root.ui
                title: "Shortcuts and text insertion"
                detail: "Use your Sotto shortcut while a text field is focused. This build supports dictation on Omarchy/Hyprland."
            }
            Setting {
                ui: root.ui
                title: "Background dictation"
                detail: "Once set up, Sotto can keep dictation available in the background when this window is closed."
            }
            Setting {
                ui: root.ui
                title: "Connection setup"
                detail: "In-app setup is not available in this build yet. Dictation needs a server connection and a keyboard shortcut configured before use."
            }
        }
    }
}
