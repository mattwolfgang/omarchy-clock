// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const dir = path.join(__dirname, "..", "i18n")
const codes = fs.readdirSync(dir).filter(f => f.endsWith(".json")).map(f => f.slice(0, -5))
const load = code => JSON.parse(fs.readFileSync(path.join(dir, code + ".json"), "utf8"))
const en = load("en")
const placeholders = text => (text.match(/%\d/g) || []).sort().join()

test("every language has exactly the English keys", () => {
  for (const code of codes)
    assert.deepEqual(Object.keys(load(code)).sort(), Object.keys(en).sort(), code)
})

test("no string is empty and placeholders match English", () => {
  for (const code of codes) {
    const catalog = load(code)
    for (const key of Object.keys(en)) {
      assert.ok(catalog[key].length > 0, code + " " + key)
      assert.equal(placeholders(catalog[key]), placeholders(en[key]), code + " " + key)
    }
  }
})

test("hints keep examples the parser can read", () => {
  for (const code of codes) {
    const catalog = load(code)
    for (const token of ["1:30", "1h 30m"]) assert.ok(catalog["timer.hint"].includes(token), code)
    for (const token of ["7:30", "19:30", "7pm"]) assert.ok(catalog["alarm.hint"].includes(token), code)
  }
})

test("every key the QML asks for exists", () => {
  const root = path.join(__dirname, "..")
  const source = fs.readdirSync(root).filter(f => f.endsWith(".qml"))
    .map(f => fs.readFileSync(path.join(root, f), "utf8")).join("\n")
  const used = [...source.matchAll(/(?:strings|clockStrings)\.t\("([^"]+)"\)/g)].map(m => m[1])
  assert.ok(used.length > 10)
  for (const key of used) assert.ok(key in en, key)
})

test("the QML reads only the plugin's own strings, never Omarchy's catalog", () => {
  const root = path.join(__dirname, "..")
  for (const file of fs.readdirSync(root).filter(f => f.endsWith(".qml"))) {
    const source = fs.readFileSync(path.join(root, file), "utf8")
    assert.doesNotMatch(source, /I18n\.tn?\(/, file)
  }
})

test("percent keeps its sign, and counted tabs keep both parts", () => {
  for (const code of codes) {
    const catalog = load(code)
    assert.match(catalog["percent"], /[%٪]/, code)
    assert.equal(placeholders(catalog["tab.counted"]), "%1,%2", code)
  }
})

test("every Omarchy language is covered, when Omarchy is installed", { skip: !fs.existsSync("/usr/share/omarchy/default/i18n/locales.json") }, () => {
  const registry = JSON.parse(fs.readFileSync("/usr/share/omarchy/default/i18n/locales.json", "utf8"))
  assert.deepEqual(codes.slice().sort(), Object.keys(registry).sort())
})
