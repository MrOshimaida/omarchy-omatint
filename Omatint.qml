import Quickshell
import Quickshell.Wayland
import QtQuick
import "OmatintModel.js" as Model

// Omatint, a tinted-glass layer: a full-screen, translucent colour wash
// over every monitor. The surfaces are deliberately click-through and never
// take keyboard focus, so the desktop underneath keeps working untouched --
// this is a colour filter, not a modal overlay.
//
// It is a pure companion to its bar widget: summoning it paints the screen,
// hiding it lifts the paint. Nothing else on screen, no UI of its own.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool enabled: false
  property int intensity: Model.DEFAULT_INTENSITY
  property string colorId: Model.DEFAULT_COLOR

  readonly property string pluginId: (manifest && manifest.id) || "xero.omatint"
  readonly property real effectiveAlpha: Model.alphaFor(root.intensity)
  readonly property var preset: Model.presetFor(root.colorId)

  // Callers may hand us [{intensity: 40, color: "amber"}] or just 40.
  // Re-summoning while the tint is on (the bar slider does this as it is
  // dragged) only updates the strength/colour -- the layer stays up.
  function open(payloadJson) {
    var parsed = Model.parsePayload(payloadJson)
    root.intensity = parsed.intensity
    root.colorId = parsed.color
    root.enabled = true
    root.opened = true
  }

  function close() {
    if (!root.enabled) return
    root.enabled = false
    root.opened = false
  }

  function hide() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: surface
      required property var modelData

      screen: modelData
      visible: root.enabled
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "xero-omatint"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // The whole layer is click-through: the input region is empty, so every
      // press rolls straight through to the windows underneath. Same idiom as
      // the OSD overlay.
      mask: Region {}

      Rectangle {
        id: tint
        anchors.fill: parent
        // Glass for the chosen preset: green is a low-glare wash, amber and red
        // cut the blue band that suppresses melatonin, yellow trims deep blue
        // for daytime contrast.
        color: Qt.rgba(root.preset.r, root.preset.g, root.preset.b, root.effectiveAlpha)

        Behavior on color {
          ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
      }
    }
  }
}