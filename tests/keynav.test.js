// node tests/keynav.test.js -- the cursor's geometry (src/quickshell/keynav/KeyNavLogic.js)
const fs = require("fs"), path = require("path"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "../src/quickshell/keynav/KeyNavLogic.js"), "utf8").replace(/^\.pragma library\s*/, "")
const m = { exports: {} }
new Function("module", src)(m)
const L = m.exports
const R = (x, y, w, h) => ({ x, y, w, h })
let n = 0
const t = (name, fn) => { fn(); n++; console.log("ok", name) }

// A 3x2 grid of tiles, 100 wide, 50 tall, 10 apart.
const grid = []
for (let r = 0; r < 2; r++) for (let c = 0; c < 3; c++) grid.push(R(c * 110, r * 60, 100, 50))
t("right in a row", () => assert.strictEqual(L.pick(grid[0], grid, 1, 0, 0), 1))
t("left stops at the edge", () => assert.strictEqual(L.pick(grid[0], grid, -1, 0, 0), -1))
t("down keeps the column", () => assert.strictEqual(L.pick(grid[1], grid, 0, 1, 1), 4))
t("up from the second row", () => assert.strictEqual(L.pick(grid[5], grid, 0, -1, 5), 2))

// A wide slider under three buttons: down from any button lands on it, up
// from it goes to the button above its centre.
const ui = [R(0, 0, 90, 40), R(100, 0, 90, 40), R(200, 0, 90, 40), R(0, 60, 290, 20)]
t("down to a wide slider", () => assert.strictEqual(L.pick(ui[2], ui, 0, 1, 2), 3))
t("up from a wide slider", () => assert.strictEqual(L.pick(ui[3], ui, 0, -1, 3), 1))

// In the beam beats nearer but off to the side.
const beam = [R(0, 0, 50, 50), R(60, 200, 50, 50), R(0, 300, 50, 50)]
t("beam wins over a diagonal", () => assert.strictEqual(L.pick(beam[0], beam, 0, 1, 0), 2))

// A card around a button doesn't count as "past" it.
const nest = [R(0, 0, 300, 100), R(200, 30, 60, 40), R(0, 120, 300, 40)]
t("enclosing card is not a step", () => assert.strictEqual(L.pick(nest[1], nest, -1, 0, 1), -1))
t("down out of a card", () => assert.strictEqual(L.pick(nest[1], nest, 0, 1, 1), 2))

t("reading order with a list block", () => {
  const es = [
    { r: R(0, 300, 10, 10), block: null, sub: 0 },          // footer button
    { r: R(0, 100, 1, 1), block: "list", sub: 1 },          // list row 2
    { r: R(0, 100, 1, 1), block: "list", sub: 0 },          // list row 1
    { r: R(50, 0, 10, 10), block: null, sub: 0 },           // header, right
    { r: R(0, 0, 10, 10), block: null, sub: 0 },            // header, left
  ]
  assert.deepStrictEqual(L.readingOrder(es), [4, 3, 2, 1, 0])
})
t("reveal scrolls down to a row", () => assert.strictEqual(L.revealOffset(500, 40, 0, 300, 1000, 8), 248))
t("reveal keeps a visible row", () => assert.strictEqual(L.revealOffset(100, 40, 0, 300, 1000, 8), 0))
t("reveal clamps at the end", () => assert.strictEqual(L.revealOffset(980, 40, 0, 300, 1000, 8), 700))
console.log(n, "passed")
