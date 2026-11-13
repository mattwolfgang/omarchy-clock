// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const qml = fs.readdirSync(root).filter(f => f.endsWith(".qml"))
const read = f => fs.readFileSync(path.join(root, f), "utf8")

// A plain Qt text field reads the whole clipboard by itself; see BoundedField.qml.
test("every text input is a BoundedField", () => {
  for (const file of qml.filter(f => f !== "BoundedField.qml")) {
    assert.doesNotMatch(read(file), /^\s*(Ui\.|Controls\.)?(TextField|TextInput|TextEdit|TextArea)\s*\{/m, file)
  }
  assert.ok(qml.some(f => /^\s*BoundedField\s*\{/m.test(read(f))))
})

test("every BoundedField is told when its popup is open", () => {
  for (const file of qml) {
    const blocks = read(file).split(/^\s*BoundedField\s*\{/m).slice(1)
    for (const block of blocks) assert.match(block.split("\n").slice(0, 3).join("\n"), /live:/, file)
  }
})

test("BoundedField is a TextEdit that takes over every clipboard read", () => {
  const source = read("BoundedField.qml")
  // TextEdit decides whether Paste is available from the offered formats;
  // TextInput (under TextField) fetches the offer to decide.
  assert.match(source, /^\s*TextEdit\s*\{/m)
  assert.doesNotMatch(source, /^\s*(Ui\.|Controls\.)?(TextField|TextInput|TextArea)\s*\{/m)
  // Its two fetch paths: the Paste key sequence and middle-click.
  assert.match(source, /event\.matches\(StandardKey\.Paste\)/)
  assert.match(source, /Keys\.priority: Keys\.BeforeItem/)
  assert.match(source, /acceptedButtons: Qt\.MiddleButton/)
  assert.doesNotMatch(source, /\.paste\(/)
  // The bounded helper.
  assert.match(source, /"timeout", "-k", "1", "2", "bash", "-c"/)
  assert.match(source, /set -o pipefail/)
  assert.match(source, /head -c " \+ \(pasteLimit \+ 1\)/)
  assert.match(source, /pasteExit === 0 \? pasteOutput : ""/)
})
