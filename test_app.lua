-- Exercise the actual application callbacks with controlled async file/portal results.
local document = require("document")
local next_path, next_bytes, read_error, write_error, yield_write, exited
local writes = {}
local refreshes = 0
local function identity(v) return v end
package.preload.ouro = function()
  return {
    signal = function(value)
      return setmetatable({ set = function(_, v) value = v; refreshes = refreshes + 1 end },
        { __call = function() return value end })
    end,
    app = identity, window = identity, exit = function() exited = true end,
    spawn_app = function(fn) fn() end,
    desktop = {
      choose_save_file = function() return next_path, next_path and nil or { name = "Canceled" } end,
      choose_file = function() return next_path and { next_path } or nil end,
    },
    files = {
      read = function() return next_bytes, read_error end,
      write = function(path, bytes)
        writes[#writes + 1] = { path, bytes }
        if yield_write then coroutine.yield() end
        if write_error then return nil, write_error end
        return true
      end,
    },
  }
end
package.preload.view = function()
  return { content = function(s, a) return { state = s, actions = a } end }
end
local app = require("app")
local window = app.run().windows[1]
local rendered = window.content()
local s, a = rendered.state, rendered.actions

-- Editing retains native state; only dirty/error transitions rebuild the view.
local before = refreshes
a.edit("d"); assert(refreshes == before + 1)
a.edit("dd"); a.edit("ddd")
assert(refreshes == before + 1 and s.doc.text == "ddd")
a.edit(""); assert(refreshes == before + 2 and not document.dirty(s.doc))
s.error = "Disk full"
a.edit(""); assert(refreshes == before + 3 and not s.error)

local commands = require("commands")
assert(#commands.matches("") == 6)
assert(commands.matches("w")[1].id == "save")
assert(commands.matches("wq")[1].id == "save_quit")
assert(commands.matches(" :SAVEAS ")[1].id == "save_as")
assert(commands.matches("enew")[1].id == "new")
assert(commands.matches("enew")[1].aliases[1] == "enew")
assert(#commands.matches("x") == 0, "Vim x only writes a changed file; this palette does not implement it")
assert(#commands.matches("q!") == 0)
a.editor_key { key = "COLON" }; assert(s.palette and s.palette.selected == 1)
a.palette_command("previous"); assert(s.palette.selected == 6)
a.palette_command("next"); assert(s.palette.selected == 1)
a.palette_edit("unknown"); a.palette_command("submit"); assert(s.palette and not exited)
a.palette_command("cancel"); assert(not s.palette)

a.editor_key { key = "V" }; assert(s.mode == "visual")
a.editor_key { key = "V", modifiers = { shift = true } }; assert(s.mode == "visual-line")
a.editor_key { key = "V", modifiers = { shift = true } }; assert(s.mode == "normal")
a.editor_key { key = "V", modifiers = { shift = true } }
a.editor_key { key = "C" }; assert(s.mode == "insert")
a.editor_key { key = "Escape" }
a.editor_key { key = "V", modifiers = { shift = true } }
a.editor_key { key = "D" }; assert(s.mode == "normal")
a.editor_key { key = "V" }; a.mode("cancel"); assert(s.mode == "normal")
a.editor_key { key = "Escape" }; assert(s.mode == "normal")
a.editor_key { key = "O" }; assert(s.mode == "insert")
a.editor_key { key = "Escape" }; assert(s.mode == "normal")
a.editor_key { key = "V" }; a.editor_key { key = "C" }; assert(s.mode == "insert")
a.editor_key { key = "Escape" }; a.editor_key { key = "V" }
a.editor_key { key = "D" }; assert(s.mode == "normal")
a.mode("submit"); assert(s.mode == "insert")
a.editor_key { key = "V" }; assert(s.mode == "insert", "Insert typing must not enter Visual")
a.editor_key { key = "COLON" }; assert(not s.palette, "Insert colon must remain text")
a.edit("unsaved α\nsecond")
a.commands.new(); assert(s.pending == "new")
a.editor_key { key = "Escape" }; assert(s.mode == "insert", "dialog must fence mode changes")
a.cancel(); assert(s.pending == nil and s.doc.text == "unsaved α\nsecond")

-- Canceled and failed saves never proceed with the pending destructive action.
a.commands.close(); a.save_continue()
assert(not exited and s.pending == "close" and document.dirty(s.doc) and not s.busy)
next_path, write_error = "/tmp/draft.md", { message = "Disk full" }
a.save_continue()
assert(not exited and s.pending == "close" and s.error == "Disk full" and document.dirty(s.doc))
assert(s.doc.path == nil)
a.cancel()

-- Palette commands retain the same cancellation and failure protections.
a.editor_key { key = "Escape" }
a.editor_key { key = "COLON" }; a.palette_edit("q"); a.palette_command("submit")
assert(s.pending == "close" and not s.palette and not exited)
a.cancel()
a.editor_key { key = "COLON" }; a.palette_edit("wq"); a.palette_command("submit")
assert(not exited and document.dirty(s.doc) and s.error == "Disk full")
next_path, write_error = nil, nil
a.editor_key { key = "COLON" }; a.palette_edit("wq"); a.palette_command("submit")
assert(not exited and document.dirty(s.doc))
next_path = "/tmp/draft.md"
a.mode("submit")

-- Save snapshots isolate late edits, and another operation cannot replace a busy document.
write_error, yield_write = nil, true
local save = coroutine.create(a.commands.save)
assert(coroutine.resume(save)); assert(s.busy)
a.commands.new(); assert(s.pending == nil)
a.editor_key { key = "Escape" }; assert(s.mode == "insert", "busy document must fence mode changes")
a.edit("a late edit")
assert(coroutine.resume(save)); assert(not s.busy and document.dirty(s.doc))
assert(writes[#writes][2] == "unsaved α\nsecond")
assert(s.doc.saved == "unsaved α\nsecond" and s.doc.text == "a late edit")
yield_write = false
a.commands.save(); assert(not document.dirty(s.doc))

-- Bad open never destroys the current text or path.
next_path, next_bytes = "/tmp/binary.txt", "bad\0bytes"
a.commands.open()
assert(s.doc.text == "a late edit" and s.doc.path == "/tmp/draft.md" and s.error)
next_bytes, read_error = nil, { message = "Permission denied" }
a.commands.open(); assert(s.error == "Permission denied" and s.doc.text == "a late edit")

next_path, next_bytes, read_error = "/tmp/new.txt", "fresh\r\ntext", nil
a.commands.open()
assert(s.doc.text == "fresh\ntext" and s.mode == "normal" and not document.dirty(s.doc))
a.edit("dirty again"); a.commands.new(); a.discard()
assert(s.doc.text == "" and s.doc.path == nil and s.pending == nil)
a.edit("final"); window.on_close_request(); a.save_continue()
assert(exited and not document.dirty(s.doc) and writes[#writes][2] == "final")
exited = false
a.editor_key { key = "COLON" }; a.palette_edit("wq"); a.palette_command("submit")
assert(exited and not document.dirty(s.doc))
print("PASS: app open/save/cancel/failure, async snapshots, busy guards, unsaved-change protection")
