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

test("BoundedField stays read-only unless focused, visible and live, and caps paste", () => {
  const source = read("BoundedField.qml")
  assert.match(source, /readonly property bool usable: live && visible && enabled/)
  assert.match(source, /readOnly: !\(usable && activeFocus\)/)
  assert.match(source, /Controls\.ContextMenu\.menu: null/)
  assert.match(source, /"timeout", "-k", "1", "2", "bash", "-c"/)
  assert.match(source, /head -c " \+ \(pasteLimit \+ 1\)/)
  assert.match(source, /set -o pipefail/)
  assert.match(source, /pasteExit === 0 \? pasteOutput : ""/)
})
