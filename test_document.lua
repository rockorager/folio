local d = require("document")
local doc = d.new("alpha βeta\n\nthird", "/tmp/a.md")
assert(not d.dirty(doc))
doc.text = "changed"
assert(d.dirty(doc))
doc.text = "alpha βeta\n\nthird"
assert(not d.dirty(doc), "undoing to disk contents should clear dirty")

doc.text = "first save"
local snapshot = d.snapshot(doc)
doc.text = "edited while saving"
assert(d.saved(doc, snapshot, "/tmp/b.md"))
assert(doc.path == "/tmp/b.md" and d.dirty(doc))
assert(doc.saved == "first save")
d.replace(doc, "another document", "/tmp/c.md")
assert(not d.saved(doc, snapshot, "/tmp/stale.md"))
assert(doc.path == "/tmp/c.md" and not d.dirty(doc))

assert(d.decode("one\r\ntwo\rthree\n") == "one\ntwo\nthree\n")
assert(d.decode("a\vb\fc" .. utf8.char(0x85) .. "d" .. utf8.char(0x2028) .. "e" .. utf8.char(0x2029) .. "f") == "a\nb\nc\nd\ne\nf")
assert(d.decode("caf\195\169 — 日本語") == "café — 日本語")
assert(d.decode("binary\0text") == nil)
assert(d.decode("invalid\255") == nil)
assert(d.decode("") == "")
assert(d.name(d.new()) == "Untitled")
assert(d.name(d.new("", "file:///tmp/hello%20world.md")) == "hello world.md")
assert(d.name(d.new("", "/tmp/100%20real.txt")) == "100%20real.txt")
assert(d.words("  one\t two\n\nthree four café 日本語 ") == 6)
assert(d.words("") == 0)
assert(d.words(" \n\t ") == 0)
print("PASS: document snapshots, dirty tracking, UTF-8, line endings, names, word counts")
