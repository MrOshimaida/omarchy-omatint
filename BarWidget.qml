import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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

  // The lock service, if the stock shell provides it. The reminder pauses while
  // the session is locked so it counts desk time, not calendar time -- a night
  // of lock + suspend must not make the notification fire on next login.
  readonly property var lockService: root.pluginShell && typeof root.pluginShell.firstPartyServiceFor === "function"
    ? root.pluginShell.firstPartyServiceFor("omarchy.lock") : null

  // The idle service is the shell's own screensaver/lock pacer, so it is live
  // even when the lock plugin is disabled (as it is by default in some set-ups).
  // It reports the session as idle once the screensaver threshold is crossed,
  // which is exactly when the screen stops being looked at -- pause on it so
  // the eye-rest clock counts active desktop time, not wall-clock time.
  readonly property var idleService: root.pluginShell && typeof root.pluginShell.firstPartyServiceFor === "function"
    ? root.pluginShell.firstPartyServiceFor("omarchy.idle") : null

  // Standalone eyes-on-screen detector: Omarchy's own IdleMonitor, owned by
  // this widget rather than the shell's pacer, so it works even when the shell
  // idle cycle is disabled (stay-awake state-file, lock plugin off, etc.).
  // After this many seconds of real inactivity the display stops being watched
  // and the eye-rest clock freezes until the user is back at the desk.
  readonly property int remindPauseIdleSeconds: 120
  property bool idleForPause: false
  IdleMonitor {
    id: eyeRestIdle
    enabled: root.remindRest
    timeout: root.remindPauseIdleSeconds
    respectInhibitors: true
    onIsIdleChanged: root.idleForPause = eyeRestIdle.isIdle
  }
  readonly property bool sessionIdle:
    root.idleForPause
    || (root.idleService && root.idleService.idledThisCycle === true)
    || (root.lockService && root.lockService.locked === true)

  function refreshState() {
    if (root.pluginShell && typeof root.pluginShell.isPluginOpen === "function") {
      var on = root.pluginShell.isPluginOpen(root.moduleName) === true
      if (root.tintOn !== on) {
        root.tintOn = on
        // Outside the boot window a drift means the overlay changed under us
        // (external hide/summon), so the persisted flag must follow. During
        // boot the first refreshState() runs before the restore re-summons,
        // so a false write there would erase the intent we are about to keep.
        if (root._bootSettled) root.persistTintOnly()
      }
    }
  }

  // Drift correction follows an external hide/summon, so it must align ONLY
  // the on/off flag in the live entry -- never re-write the whole entry. A
  // full write here could clobber other fields (colour, strength, reminder)
  // with a stale snapshot, because the base hands widgets a settings snapshot
  // taken at instantiation rather than a live reference. Mutating the live
  // config leaves every other key exactly as it currently sits in shell.json.
  function persistTintOnly() {
    if (!root.pluginShell || typeof root.pluginShell.mutateShellConfig !== "function") return
    root.pluginShell.mutateShellConfig(function (cfg) {
      var layout = cfg && cfg.bar && cfg.bar.layout ? cfg.bar.layout : null
      var sections = ["left", "center", "right"]
      for (var s = 0; layout && s < sections.length; s++) {
        var arr = layout[sections[s]] || []
        for (var i = 0; i < arr.length; i++)
          if (arr[i] && arr[i].id === root.moduleName) arr[i].tintOn = root.tintOn
      }
    })
  }

  function payload() {
    return JSON.stringify({ intensity: root.intensity, color: root.colorId })
  }

  // Optimistic flip: reflect the click immediately, let refreshState() correct
  // any drift (the overlay disappearing for a reason we cannot see). The flag
  // is persisted so a shell restart can bring the tint back as it was.
  function setEnabled(on) {
    if (!root.pluginShell) return
    if (on) root.pluginShell.summon(root.moduleName, root.payload())
    else if (typeof root.pluginShell.hide === "function") root.pluginShell.hide(root.moduleName)
    root.tintOn = on
    if (on) {
      root.restElapsedSec = 0
      root.restLastActiveWall = 0
      root.persistEyeClock()
    }
    // Left-clicking the bar button happens with no popup open, so that write
    // is safe and immediate. The popup's own switch must wait for dismissal.
    if (popup.open) root.markDirty()
    else root.persistSettings()
  }

  // The slider re-fitting the live layer calls this while it is dragged.
  function setIntensity(value) {
    root.intensity = Model.clampIntensity(value)
    if (root.tintOn && root.pluginShell
        && typeof root.pluginShell.summon === "function")
      root.pluginShell.summon(root.moduleName, root.payload())
    if (popup.open) root.markDirty()
  }

  function setColor(id) {
    root.colorId = Model.normalizeColor(id)
    if (root.tintOn && root.pluginShell
        && typeof root.pluginShell.summon === "function")
      root.pluginShell.summon(root.moduleName, root.payload())
    root.markDirty()
  }

  function setUseNightKey(on) {
    root.useNightKey = on === true
    root.markDirty()
  }

  function setRemindRest(on) {
    root.remindRest = on === true
    root.markDirty()
  }

  // Nothing inside the popup may write the bar config.
  //
  // A shell.json write makes the host reload its layout, and under Shibumi that
  // reload rebuilds the widget hosting this popup. The PopupCard holds a
  // Hyprland focus grab; when its host is destroyed the grab is cleared, which
  // fires PopupCard's onCleared and slams the popup shut on the very click the
  // user just made -- so picking a colour or releasing the strength slider
  // closed the menu before the strength could ever be adjusted.
  //
  // So colour, strength, and the switches apply live (the overlay repaints from
  // memory) and are written once, when the popup is dismissed. The settings
  // survive a restart exactly as before; they just stop costing a bar rebuild
  // per interaction.
  property bool _pendingPersist: false

  function markDirty() {
    root._pendingPersist = true
  }

  function flushPersist() {
    if (!root._pendingPersist) return
    root._pendingPersist = false
    root.persistSettings()
  }

  // Persist settings into the bar entry so they survive a shell restart.
  // updateEntryInline REPLACES the entry rather than merging, so every key has
  // to travel together -- sending just one would drop the rest. The eye-rest
  // clock is deliberately absent: it lives in the state file, not the bar
  // config, so no bar reload is ever triggered by a checkpoint.
  function persistSettings() {
    if (!root.pluginShell || typeof root.pluginShell.updateEntryInline !== "function") return
    root.pluginShell.updateEntryInline(root.moduleName, {
      intensity: root.intensity,
      color: root.colorId,
      useNightKey: root.useNightKey,
      remind: root.remindRest,
      remindMinutes: root.remindMinutes,
      tintOn: root.tintOn
    })
  }

  // User-facing setters may persist the whole entry: they always carry freshly
  // chosen values, so a full write there is intent, not drift.

  // The boot path persists nothing but tintOn (see persistTintOnly), so colour,
  // strength, and reminder settings can only ever be written by explicit user
  // action, never by a stale reload snapshot.

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
    onTriggered: root.updateRestClock()
  }

  // Eye-rest reminder: a cumulative seconds counter rather than a one-shot
  // wall-clock Timer, because a paused QML Timer restarts its whole interval on
  // resume -- every quiet gap would silently reset "45 minutes" to zero. Each
  // qualifying tick adds one second of desk time; idle stretches merely freeze
  // it, so the reminder fires once a genuine 45 active minutes have banked up.
  // A long real-world break -- ten or more minutes wall-clock away, including
  // any suspension -- erases the banked time, so yesterday's minutes can never
  // fire a toast the moment you sit back down this morning.
  property int restElapsedSec: Math.max(0, Math.round(Number(setting("restSec", 0)) || 0))
  // Date.now() of the most recent qualifying active tick. A long wall-clock
  // gap between qualifying ticks is a genuine break and wipes the bank.
  // Tick-counting alone cannot see a suspension: the 1-second ticker does not
  // run while the machine sleeps, so last night's idle never accumulated and
  // the banked minutes would otherwise survive into the new day untouched.
  // Declared double on purpose: Date.now() is ~1.79e12 ms, which a plain
  // int wraps to a huge negative and would make every tick look like a break.
  property double restLastActiveWall: Number(setting("restWall", 0)) || 0
  readonly property int restIdleResetSec: 10 * 60

  // The clock lives in its own state file, never in shell.json. Writing the
  // bar's config file makes the host shell reload its layout, and a bar that
  // cannot patch the change in place rebuilds every widget it hosts -- which
  // visibly restarts the whole center pill. Paying that cost every 45 seconds
  // to checkpoint a countdown was the single worst trade in this widget, so
  // the countdown now goes to plain state the bar never reads.
  readonly property string stateDir:
    (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy/omatint"
  readonly property string statePath: stateDir + "/eye-rest.json"

  function updateRestClock() {
    root.refreshState()
    if (!root.tintOn || !root.remindRest) return
    if (root.restLastActiveWall !== 0
        && Date.now() - root.restLastActiveWall >= root.restIdleResetSec * 1000) {
      root.restElapsedSec = 0
      root.persistEyeClock()
    }
    if (root.sessionIdle) return
    root.restLastActiveWall = Date.now()
    if (++root.restElapsedSec % 45 === 0) root.persistEyeClock()
    if (root.restElapsedSec < root.remindMinutes * 60) return
    root.restElapsedSec = 0
    root.persistEyeClock()
    notifyRest.running = true
  }

  // Persist the eye-rest clock so a shell crash, keepLoaded reload, or restart
  // does not lose progress: a restart resumes the count where it was instead of
  // zeroing it. Written to a private state file every 45 ticks, and only there:
  // touching shell.json instead would make the host reload the bar layout on
  // every checkpoint. Written through a temp file and renamed, so a restart
  // landing mid-write can never leave a half-parsed clock behind.
  Process {
    id: eyeClockWriter
    running: false
  }

  // Both values are forced to non-negative integers before they reach the
  // command line, so the printf operand is always bare JSON numbers.
  function persistEyeClock() {
    var sec = Math.max(0, Math.round(Number(root.restElapsedSec) || 0))
    var wall = Math.max(0, Math.round(Number(root.restLastActiveWall) || 0))
    eyeClockWriter.command = ["sh", "-c",
      "mkdir -p '" + root.stateDir + "'"
      + " && printf '{\"restSec\":" + sec + ",\"restWall\":" + wall + "}\\n'"
      + " > '" + root.statePath + ".tmp'"
      + " && mv '" + root.statePath + ".tmp' '" + root.statePath + "'"]
    eyeClockWriter.running = true
  }

  // One-shot read at boot. A missing or unreadable file simply leaves the
  // values the widget already carries, which is exactly the first-run case.
  Process {
    id: eyeClockReader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.adoptEyeClock(text)
    }
  }

  function loadEyeClock() {
    eyeClockReader.command = ["cat", root.statePath]
    eyeClockReader.running = true
  }

  function adoptEyeClock(raw) {
    var text = String(raw === undefined || raw === null ? "" : raw).trim()
    if (text === "") return
    var parsed = null
    try { parsed = JSON.parse(text) } catch (e) { return }
    if (!parsed) return
    var wall = Number(parsed.restWall)
    // Newest write wins. The read is asynchronous, so on the one boot that
    // still carries legacy keys a stale file could otherwise land after the
    // migration has already banked fresher values and undo them.
    if (!isFinite(wall) || wall <= 0) return
    if (root.restLastActiveWall > 0 && wall < root.restLastActiveWall) return
    var sec = Math.round(Number(parsed.restSec))
    if (isFinite(sec) && sec >= 0) root.restElapsedSec = sec
    root.restLastActiveWall = wall
  }

  // Older builds banked the clock in the bar entry. Seed the state file from
  // those keys so no progress is lost, then drop them: leaving them in place
  // would resurrect a stale count if the state file were ever removed. This is
  // the last shell.json write this widget makes, and the keys are gone on the
  // next boot, so it cannot come back.
  function migrateLegacyEyeClock() {
    var legacySec = root.setting("restSec", null)
    var legacyWall = root.setting("restWall", null)
    if (legacySec === null && legacyWall === null) return
    root.persistEyeClock()
    if (!root.pluginShell || typeof root.pluginShell.mutateShellConfig !== "function") return
    root.pluginShell.mutateShellConfig(function (cfg) {
      var layout = cfg && cfg.bar && cfg.bar.layout ? cfg.bar.layout : null
      var sections = ["left", "center", "right"]
      for (var s = 0; layout && s < sections.length; s++) {
        var arr = layout[sections[s]] || []
        for (var i = 0; arr && i < arr.length; i++) {
          if (!arr[i] || arr[i].id !== root.moduleName) continue
          delete arr[i].restSec
          delete arr[i].restWall
        }
      }
    })
  }

  Process {
    id: notifyRest
    command: [
      "omarchy-notification-send", "--app-name", "Omatint", "-u", "normal", "Eye rest",
      "The tint has been on for " + root.remindMinutes
        + " minutes. Look 20 feet away for 20 seconds."
    ]
  }

  // Bring the tint back up across a shell restart if it was on. The overlay
  // panel is keepLoaded, so summon() queues until its loader is ready even
  // when the bar connects before the panel.
  //
  // The host injects bar/shell/settings onto the widget AFTER construction, so
  // the boot path cannot fire from Component.onCompleted alone: it retries
  // until the bar shell and settings are actually in place, then refreshes the
  // optimistic flag, restores, and finally lets drift-persistence engage.
  property bool _mounted: false
  property bool _bootSettled: false
  property int _bootRetries: 0

  function restoreIfWasOn() {
    if (setting("tintOn", false) !== true) return
    if (!root.pluginShell || typeof root.pluginShell.summon !== "function") return
    // Build the payload from the persisted entry directly. The colorId and
    // intensity bindings may lag one binding pass behind settings injection,
    // so summoning root.payload() here could paint the overlay with the model
    // defaults until the next re-summon. Reading the entry guarantees the
    // restored layer matches exactly what was left on.
    var restored = {
      intensity: Model.clampIntensity(Number(setting("intensity", Model.DEFAULT_INTENSITY))),
      color: Model.normalizeColor(String(setting("color", Model.DEFAULT_COLOR)))
    }
    root.pluginShell.summon(root.moduleName, JSON.stringify(restored))
  }

  function maybeBoot() {
    if (root._mounted) return
    if (!root.moduleName || !root.bar || !root.bar.shell || !root.settings) {
      if (root._bootRetries++ < 30) Qt.callLater(root.maybeBoot)
      return
    }
    root._mounted = true
    Qt.callLater(root.onWidgetReady)
  }

  function onWidgetReady() {
    root.refreshState()
    root.loadEyeClock()
    root.migrateLegacyEyeClock()
    root.restoreIfWasOn()
    Qt.callLater(function () { root._bootSettled = true })
  }

  onBarChanged: root.maybeBoot()
  onSettingsChanged: root.maybeBoot()
  Component.onCompleted: root.maybeBoot()

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

  // Flush the deferred write when the popup is dismissed. Connections rather
  // than a plain onOpenChanged handler: PopupCard already implements onOpenChanged
  // to manage the bar's popout ownership, and redeclaring it here would replace
  // that handler instead of adding to it.
  Connections {
    target: popup
    function onOpenChanged() {
      if (!popup.open) root.flushPersist()
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
          onReleased: function (value) { root.setIntensity(value) }
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