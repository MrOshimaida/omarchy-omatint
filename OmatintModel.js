.pragma library

// Pure logic for Omatint. No Qt, no shell: everything here is
// testable on its own (see test/model-test.js).

var DEFAULT_INTENSITY = 35
var MIN_INTENSITY = 5
var MAX_INTENSITY = 100
// Even at full strength the overlay stays translucent: a tint should colour
// the screen, not replace it.
var MAX_ALPHA = 0.45

// Preset tints, chosen from the circadian/comfort literature. Melanopsin peaks
// near 480 nm, so what preserves melatonin at night is cutting the 460-500 nm
// band: amber/brown filters do that best, red (631 nm) barely stimulates it at
// all. Yellow only trims the deep blue and is a daytime contrast/glare tint,
// not a night filter. Green is the low-glare, least-photophobic comfort wash.
// (Eye strain itself is driven more by glare and breaks than by hue.)
var DEFAULT_COLOR = "green"
var PRESETS = [
  { id: "green", label: "Green", r: 0, g: 1, b: 0 },
  { id: "amber", label: "Amber", r: 1, g: 0.6, b: 0.18 },
  { id: "yellow", label: "Yellow", r: 1, g: 0.92, b: 0.25 },
  { id: "red", label: "Red", r: 1, g: 0.12, b: 0.06 }
]

function clampIntensity(value) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) n = DEFAULT_INTENSITY
  return Math.max(MIN_INTENSITY, Math.min(MAX_INTENSITY, n))
}

function defaultIntensity() { return DEFAULT_INTENSITY }

// Strength (5-100) -> overlay alpha (0.0225-0.45). Linear so the slider feels
// even; the overlay is the preset colour with this alpha.
function alphaFor(intensity) {
  return clampIntensity(intensity) / 100 * MAX_ALPHA
}

// Unknown/missing ids fall back to green so a stale shell.json never makes the
// overlay go invisible.
function normalizeColor(id) {
  var wanted = String(id === undefined || id === null ? "" : id)
  for (var i = 0; i < PRESETS.length; i++) {
    if (PRESETS[i].id === wanted) return wanted
  }
  return DEFAULT_COLOR
}

function presetFor(id) {
  var wanted = normalizeColor(id)
  for (var i = 0; i < PRESETS.length; i++) {
    if (PRESETS[i].id === wanted) return PRESETS[i]
  }
  return PRESETS[0]
}

// The overlay is summoned with a payload that carries the strength and colour.
// Accept a bare number, an object, a JSON string, or nothing at all.
function parsePayload(payloadJson) {
  if (payloadJson === undefined || payloadJson === null || payloadJson === "") {
    return { intensity: DEFAULT_INTENSITY, color: DEFAULT_COLOR }
  }
  if (typeof payloadJson === "number") {
    return { intensity: clampIntensity(payloadJson), color: DEFAULT_COLOR }
  }
  var text = String(payloadJson).trim()
  if (text.charAt(0) === "{") {
    try {
      var obj = JSON.parse(text)
      return {
        intensity: clampIntensity(obj && obj.intensity),
        color: normalizeColor(obj && obj.color)
      }
    } catch (e) {
      return { intensity: DEFAULT_INTENSITY, color: DEFAULT_COLOR }
    }
  }
  var n = Number(text)
  if (isFinite(n) && n > 0) return { intensity: clampIntensity(n), color: DEFAULT_COLOR }
  return { intensity: DEFAULT_INTENSITY, color: DEFAULT_COLOR }
}

function strengthLabel(intensity) {
  return clampIntensity(intensity) + "%"
}

function tooltip(on, intensity, color) {
  return presetFor(color).label + " tint — " + (on ? "on" : "off")
    + " (" + clampIntensity(intensity) + "%)\n"
    + "Left-click: toggle. Right-click: colour and strength."
}
