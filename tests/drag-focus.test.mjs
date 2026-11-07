import assert from "node:assert/strict"
import fs from "node:fs"
import test from "node:test"
import { fileURLToPath } from "node:url"

const modelPath = fileURLToPath(new URL("../Model.js", import.meta.url))
const source = fs.readFileSync(modelPath, "utf8").replace(/^\.pragma library\r?\n/, "")
const model = new Function(`${source}\nreturn { keyboardFocusMode };`)()

test("a drop that is still mapping keeps keyboard focus off", () => {
  assert.equal(model.keyboardFocusMode(true, true, false, false), "none")
  assert.equal(model.keyboardFocusMode(true, true, false, true), "none")
})

test("the file chooser keeps keyboard focus off", () => {
  assert.equal(model.keyboardFocusMode(true, false, true, true), "none")
})

test("a closed panel keeps keyboard focus off", () => {
  assert.equal(model.keyboardFocusMode(false, false, false, true), "none")
})

test("a click-opened panel starts exclusive, then stays on demand", () => {
  assert.equal(model.keyboardFocusMode(true, false, false, false), "exclusive")
  assert.equal(model.keyboardFocusMode(true, false, false, true), "ondemand")
})
