const assert = require("assert")
const fs = require("fs")

// Run the REAL library file, comments included, so the test can never drift
// from what QML actually loads.
const source = fs.readFileSync(__dirname + "/../OmatintModel.js", "utf8")
const body = source.replace(/^\.pragma library\s*/, "").trim()

// Bridge the top-level `var`s into an object, mirroring how Quickshell exposes
// library members on Model.*.
const bridge = new Function("exports", body + "\nexports._ = { DEFAULT_INTENSITY, MIN_INTENSITY, MAX_INTENSITY, MAX_ALPHA, PRESETS, DEFAULT_COLOR, clampIntensity, defaultIntensity, alphaFor, normalizeColor, presetFor, parsePayload, strengthLabel, tooltip }")
const out = {}
bridge(out)
const M = out._

function approx(a, b, tol) { assert.ok(Math.abs(a - b) <= tol, `${a} vs ${b}`) }

// --- clampIntensity -------------------------------------------------------
assert.strictEqual(M.clampIntensity(40), 40)
assert.strictEqual(M.clampIntensity(0), 5)     // floor
assert.strictEqual(M.clampIntensity(-12), 5)
assert.strictEqual(M.clampIntensity(150), 100) // ceiling
assert.strictEqual(M.clampIntensity(99.6), 100)
assert.strictEqual(M.clampIntensity(54.4), 54) // rounds
assert.strictEqual(M.clampIntensity("35"), 35)
assert.strictEqual(M.clampIntensity("banana"), 35) // default
assert.strictEqual(M.clampIntensity(NaN), 35)
assert.strictEqual(M.clampIntensity(undefined), 35)
assert.strictEqual(M.defaultIntensity(), 35)

// --- alphaFor -------------------------------------------------------------
assert.strictEqual(M.alphaFor(50), M.MAX_ALPHA / 2)
assert.strictEqual(M.alphaFor(100), M.MAX_ALPHA)
approx(M.alphaFor(5), M.MAX_ALPHA * (5 / 100), 1e-9) // starts low, stays glass
assert.strictEqual(M.alphaFor(0), M.alphaFor(5)) // clamped, never 0
assert.strictEqual(M.alphaFor(500), M.MAX_ALPHA)
// monotonic in its range
let prev = -1
for (let i = 5; i <= 100; i += 5) {
  const a = M.alphaFor(i)
  assert.ok(a > prev, `alpha must rise with intensity at ${i}`)
  prev = a
}

// --- presets --------------------------------------------------------------
assert.strictEqual(M.PRESETS.length, 4)
assert.deepStrictEqual(M.normalizeColor("amber"), "amber")
assert.deepStrictEqual(M.normalizeColor("red"), "red")
assert.deepStrictEqual(M.normalizeColor("green"), "green")
assert.strictEqual(M.normalizeColor(undefined), "green") // fallback
assert.strictEqual(M.normalizeColor(null), "green")
assert.strictEqual(M.normalizeColor("chartreuse"), "green")
assert.strictEqual(M.normalizeColor("sepia"), "green") // retired preset -> fallback
assert.strictEqual(M.presetFor("yellow").id, "yellow")
assert.strictEqual(M.presetFor("nope").id, "green") // unknown -> green
const seen = {}
for (const p of M.PRESETS) {
  assert.ok(typeof p.label === "string" && p.label.length > 0, "every preset is labelled")
  assert.ok(!seen[p.id], "preset ids are unique: " + p.id)
  seen[p.id] = true
  assert.ok(p.r >= 0 && p.r <= 1 && p.g >= 0 && p.g <= 1 && p.b >= 0 && p.b <= 1,
    "channels are 0..1 for " + p.id)
}

// --- parsePayload ---------------------------------------------------------
const DEF = { intensity: 35, color: "green" }
assert.deepStrictEqual(M.parsePayload(""), DEF)
assert.deepStrictEqual(M.parsePayload(undefined), DEF)
assert.deepStrictEqual(M.parsePayload(null), DEF)
assert.deepStrictEqual(M.parsePayload('{"intensity":60}'), { intensity: 60, color: "green" })
assert.deepStrictEqual(M.parsePayload('{"intensity":0}'), { intensity: 5, color: "green" })
assert.deepStrictEqual(M.parsePayload('{"intensity":300}'), { intensity: 100, color: "green" })
assert.deepStrictEqual(M.parsePayload('{"intensity":"25"}'), { intensity: 25, color: "green" })
assert.deepStrictEqual(M.parsePayload('{"intensity":60,"color":"amber"}'), { intensity: 60, color: "amber" })
assert.deepStrictEqual(M.parsePayload('{"color":"yellow"}'), { intensity: 35, color: "yellow" })
assert.deepStrictEqual(M.parsePayload('{"color":"bogus"}'), { intensity: 35, color: "green" })
assert.deepStrictEqual(M.parsePayload(45), { intensity: 45, color: "green" })
assert.deepStrictEqual(M.parsePayload("75"), { intensity: 75, color: "green" })
assert.deepStrictEqual(M.parsePayload("0"), DEF) // degenerate string
assert.deepStrictEqual(M.parsePayload("{nope"), DEF) // broken json
assert.deepStrictEqual(M.parsePayload("[]"), DEF)
assert.deepStrictEqual(M.parsePayload('{"mode":"nearfar"}'), DEF) // missing key

// --- labels ---------------------------------------------------------------
assert.strictEqual(M.strengthLabel(60), "60%")
assert.strictEqual(M.strengthLabel(150), "100%")
const t1 = M.tooltip(true, 50, "amber")
assert.ok(t1.includes("on") && t1.includes("50%") && t1.includes("Amber"))
const t2 = M.tooltip(false, 20)
assert.ok(t2.includes("off") && t2.includes("20%") && t2.includes("Green"))

console.log("OmatintModel: all tests passed")