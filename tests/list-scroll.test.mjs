import assert from "node:assert/strict"
import fs from "node:fs"
import test from "node:test"
import { fileURLToPath } from "node:url"

const modelPath = fileURLToPath(new URL("../Model.js", import.meta.url))
const source = fs.readFileSync(modelPath, "utf8").replace(/^\.pragma library\r?\n/, "")
const model = new Function(`${source}\nreturn { listRoom, listContentHeight, listViewport };`)()

const row = 48
const rowGap = 4
const columnGap = 10
const inner = 492
const chrome = [28, 22, 22]

test("a short app list keeps its own height", () => {
  const content = model.listContentHeight(2, row, rowGap)
  const room = model.listRoom(inner, chrome, columnGap, true)
  assert.equal(content, 100)
  assert.equal(room, 390)
  assert.equal(model.listViewport(content, room), content)
})

test("a long app list stops at the room left above the switches", () => {
  const content = model.listContentHeight(12, row, rowGap)
  const room = model.listRoom(inner, chrome, columnGap, true)
  const view = model.listViewport(content, room)
  assert.equal(content, 620)
  assert.ok(content > room)
  assert.equal(view, room)
  assert.equal(view + chrome[0] + chrome[1] + chrome[2] + (3 * columnGap), inner)
})

test("no room and no rows produce an empty viewport", () => {
  assert.equal(model.listContentHeight(0, row, rowGap), 0)
  assert.equal(model.listContentHeight(4, 0, rowGap), 0)
  assert.equal(model.listViewport(200, 0), 0)
  assert.equal(model.listViewport(0, 200), 0)
  assert.equal(model.listViewport(-1, 40), 0)
  assert.equal(model.listRoom(100, [90, 40], columnGap, true), 0)
})

test("a hidden chrome row does not take a gap", () => {
  assert.equal(model.listRoom(200, [0, 28], columnGap, false), 172)
  assert.equal(model.listContentHeight(1, row, rowGap), row)
})
