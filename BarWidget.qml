import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "OmatintModel.js" as Model

// Bar home for Omatint. Left-click flips the tint on and off at the
// saved strength; right-click opens a popup with the strength slider (and a
// second switch). The slider re-paints the screen live while the tint is on.
BarWidget {
  id: root
  moduleName: "xero.omatint"

  property int intensity: Model.clampIntensity(Number(setting("intensity", Model.DEFAULT_INTENSITY)))
  property string colorId: Model.normalizeColor(String(setting("color", Model.DEFAULT_COLOR)))
  property bool useNightKey: setting("useNightKey", false) === true
  property bool remindRest: setting("remind", false) === true
  property int remindMinutes: Math.max(1, Math.round(Number(setting("remindMinutes", 45)) || 45))
  property bool tintOn: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Either the stock bar hands us the scoped plugin shell (via PluginBarApi)
  // or, on a foreign bar, there is no way to reach the overlay at all -- in
  // that case the button silently does nothing rather than spew errors.
  readonly property var pluginShell: root.bar && root.bar.shell ? root.bar.shell : null

  function refreshState() {
    if (root.pluginShell && typeof root.pluginShell.isPluginOpen === "function")
      root.tintOn = root.pluginShell.isPluginOpen(root.moduleName) === true
  }

  function payload() {
    return JSON.stringify({ intensity: root.intensity, color: root.colorId })
  }

  // Optimistic flip: reflect the click immediately, let refreshState() correct
  // any drift (the overlay disappearing for a reason we cannot see).
  function setEnabled(on) {
    if (!root.pluginShell) return
    if (on) root.pluginShell.summon(root.moduleName, root.payload())
    else if (typeof root.pluginShell.hide === "function") root.pluginShell.hide(root.moduleName)
    root.tintOn = on
  }

  // The slider re-fitting the live layer calls this while it is dragged.
  function setIntensity(value) {
    root.intensity = Model.clampIntensity(value)
    if (root.tintOn && root.pluginShell
        && typeof root.pluginShell.summon === "function")
      root.pluginShell.summon(root.moduleName, root.payload())
  }

  function setColor(id) {
    root.colorId = Model.normalizeColor(id)
    if (root.tintOn && root.pluginShell
        && typeof root.pluginShell.summon === "function")
      root.pluginShell.summon(root.moduleName, root.payload())
    root.persistSettings()
  }

  function setUseNightKey(on) {
    root.useNightKey = on === true
    root.persistSettings()
  }

  function setRemindRest(on) {
    root.remindRest = on === true
    root.persistSettings()
  }

  // Persist settings into the bar entry so they survive a shell restart.
  // updateEntryInline REPLACES the entry rather than merging, so every key has
  // to travel together -- sending just one would drop the rest.
  function persistSettings() {
    if (!root.pluginShell || typeof root.pluginShell.updateEntryInline !== "function") return
    root.pluginShell.updateEntryInline(root.moduleName, {
      intensity: root.intensity,
      color: root.colorId,
      useNightKey: root.useNightKey,
      remind: root.remindRest,
      remindMinutes: root.remindMinutes
    })
  }

  // The stock bar text color, which the toggle/knob and bar glyphs actually
  // render with. Kept explicit because Color.muted/Color.popups.text evaluate
  // far darker than the bar foreground in some themes.
  readonly property color text1: root.bar && root.bar.barForeground ? root.bar.barForeground : Color.foreground
  readonly property color text2: Util.alpha(root.text1, 0.85)
  readonly property color text3: Util.alpha(root.text1, 0.7)

  // The chosen preset's actual colour, so the glyph (and the bead when live)
  // advertise which tint is selected rather than a fixed green. Dimmed while
  // the tint is off, full strength while it is on.
  readonly property color tintColor: {
    var p = Model.presetFor(root.colorId)
    return Qt.rgba(p.r, p.g, p.b, 1)
  }
  readonly property color tintColorDim: Util.alpha(root.tintColor, 0.55)

  FontMetrics {
    id: popupSpaceFm
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }

  // Width of a single space in the number's font; used to widen the card by a
  // fixed number of visible "spaces" so the % never crowds the frame.
  readonly property int popupSpaceW: popupSpaceFm.advanceWidth(" ")

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.refreshState()
  }

  // Eye-rest reminder: runs only while the tint is on, and restarts whenever it
  // is toggled, so it counts continuous tint time rather than wall-clock time.
  Timer {
    id: restTimer
    interval: root.remindMinutes * 60000
    repeat: true
    running: root.tintOn && root.remindRest
    onTriggered: notifyRest.running = true
  }

  Process {
    id: notifyRest
    command: [
      "omarchy-notification-send", "--app-name", "Omatint", "-u", "normal", "Eye rest",
      "The tint has been on for " + root.remindMinutes
        + " minutes. Look 20 feet away for 20 seconds."
    ]
  }

  Component.onCompleted: root.refreshState()

WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // fa-chalkboard_user (U+EDE6): a figure before a chalkboard, the app logo.
    // Solid and filled, so it reads at bar size; it is the whole artwork.
    text: ""
    foreground: root.tintOn ? root.tintColor : root.tintColorDim
    tooltipText: Model.tooltip(root.tintOn, root.intensity, root.colorId)

    // A status dot under the glyph: a visible grey bead when the tint is off
    // (so the button never looks empty), the preset colour when it is live.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.max(1, Math.round(parent.height * 0.1))
      width: Math.max(4, Math.round(parent.height * 0.16))
      height: width
      radius: width / 2
      color: root.tintOn ? root.tintColor : Color.muted
      opacity: root.tintOn ? 1 : 0.7
    }

    onPressed: function (b) {
      if (b === Qt.RightButton) {
        popup.open = !popup.open
      } else if (popup.open) {
        popup.open = false
      } else {
        root.setEnabled(!root.tintOn)
      }
    }
  }

  PopupCard {
    id: popup
    owner: root
    bar: root.bar
    anchorItem: button
    open: false
    padding: Style.space(14)
    // 3 spaces of extra width so "100%" and its gap clear the right frame.
    contentWidth: popup.fittedContentWidth(Style.space(252) + root.popupSpaceW * 3)
    contentHeight: popup.fittedContentHeight(popupColumn.implicitHeight)
    // A dedicated frame so the card reads as a closed box on every theme
    // (some themes render only the side borders, dropping the bottom line).
    borderSpec: Border.flat(Util.alpha(root.text1, 0.7), Math.max(1, Math.round(Style.space(2))))

    Column {
      id: popupColumn
      anchors.fill: parent
      spacing: Style.space(8)

      // Header row: droplet pinned flush-left, toggle pinned flush-right. The
      // card padding is symmetric, so both get the same gap to their frame —
      // whichever side's spacing is larger wins for the whole row.
      Item {
        id: headerRow
        width: parent.width
        height: Math.max(
          Math.max(iconGlyph.implicitHeight, toggle.implicitHeight),
          titleBlock.implicitHeight)

        Text {
          id: iconGlyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          // Same chalkboard-user glyph, held in the selected preset's colour.
          text: ""
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.tintOn ? root.tintColor : root.tintColorDim
        }

        ToggleSwitch {
          id: toggle
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.tintOn
          onToggled: root.setEnabled(!root.tintOn)
        }

        Column {
          id: titleBlock
          anchors.left: iconGlyph.right
          anchors.leftMargin: Style.space(10)
          anchors.right: toggle.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: "Omatint"
            color: root.text1
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: (root.tintOn ? "On" : "Off") + " — " + Model.strengthLabel(root.intensity)
            color: root.text2
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Item { width: parent.width; height: Style.space(2) }

      Row {
        id: swatchRow
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: Model.PRESETS

          delegate: Item {
            required property var modelData
            width: (swatchRow.width - swatchRow.spacing * (Model.PRESETS.length - 1))
              / Model.PRESETS.length
            height: swatchColumn.implicitHeight

            Column {
              id: swatchColumn
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(Style.space(22))
                height: width
                radius: width / 2
                color: Qt.rgba(modelData.r, modelData.g, modelData.b, 0.9)
                border.width: root.colorId === modelData.id
                  ? Math.max(1, Math.round(Style.space(2))) : 1
                border.color: root.colorId === modelData.id
                  ? root.text1 : Util.alpha(root.text1, 0.4)
              }

              Text {
                width: swatchRow.width / Model.PRESETS.length
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                text: modelData.label
                color: root.colorId === modelData.id ? root.text1 : root.text3
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.setColor(modelData.id)
            }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: circleGlyph
          width: Math.round(Style.space(26))
          anchors.verticalCenter: parent.verticalCenter
          text: "◐"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.text2
        }

        PanelSlider {
          id: slider
          bar: root.bar
          // Reserve the ◐ glyph, the value, and a spacing for each of the
          // three children so the row never clips the % off its right edge.
          width: Math.max(Style.space(90),
                          parent.width - strengthText.implicitWidth - circleGlyph.width - parent.spacing * 3)
          anchors.verticalCenter: parent.verticalCenter
          value: root.intensity
          minimum: Model.MIN_INTENSITY
          maximum: Model.MAX_INTENSITY
          step: 5
          integer: true
          onMoved: function (value) { root.setIntensity(value) }
          onReleased: function (value) { root.setIntensity(value); root.persistSettings() }
        }

        Text {
          id: strengthText
          anchors.verticalCenter: parent.verticalCenter
          text: Model.strengthLabel(root.intensity)
          color: root.text1
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Util.alpha(root.text1, 0.25)
      }

      // Use the stock night-light key (SUPER + CTRL + N) for this tint. When
      // on, that key runs the Omatint toggle instead of hyprsunset; off
      // leaves the stock night light untouched.
      Item {
        width: parent.width
        height: Math.max(keyLabel.implicitHeight, keyToggle.implicitHeight)

        Text {
          id: keyLabel
          anchors.left: parent.left
          anchors.right: keyToggle.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          wrapMode: Text.WordWrap
          text: "Use the night-light key (Super + Ctrl + N)"
          color: root.text2
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        ToggleSwitch {
          id: keyToggle
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.useNightKey
          onToggled: root.setUseNightKey(!root.useNightKey)
        }
      }

      Item {
        width: parent.width
        height: Math.max(restLabel.implicitHeight, restToggle.implicitHeight)

        Text {
          id: restLabel
          anchors.left: parent.left
          anchors.right: restToggle.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          wrapMode: Text.WordWrap
          text: "Remind me to rest every " + root.remindMinutes + " min"
          color: root.text2
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        ToggleSwitch {
          id: restToggle
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.remindRest
          onToggled: root.setRemindRest(!root.remindRest)
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "A click-through tint. The overlay never blocks the desktop, "
          + "so you can leave it on while you work."
        color: root.text3
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}