local o = require("ouro")
local document = require("document")
local view = require("view")
local commands = require("commands")
local changed = o.signal(0)
local s = { doc = document.new(), mode = "normal", focus = 0, busy = false }
local actions = { commands = {} }
local filters = { { name = "Plain text", patterns = { "*.txt", "*.md", "*.markdown" } } }

local function refresh() changed:set(changed() + 1) end
local function refocus() s.focus = s.focus + 1; refresh() end
local function failure(err)
  s.error = type(err) == "table" and (err.message or err.name) or tostring(err)
  refresh()
end

local function save(save_as)
  if s.busy then return false end
  s.busy, s.error = true, nil; refresh()
  local snapshot = document.snapshot(s.doc)
  local path = not save_as and s.doc.path
  if not path then
    local err
    path, err = o.desktop.choose_save_file { parent = "main", current_name = s.doc.path and document.name(s.doc) or "Untitled.md", filters = filters }
    if not path then
      s.busy = false
      if err and err.name ~= "Canceled" then failure(err) end
      refocus(); return false
    end
  end
  local ok, err = o.files.write(path, snapshot.text)
  s.busy = false
  if ok then document.saved(s.doc, snapshot, path) else failure(err) end
  refocus()
  return ok and not document.dirty(s.doc)
end

local function open()
  s.busy, s.error = true, nil; refresh()
  local paths, err = o.desktop.choose_file { parent = "main", multiple = false, filters = filters }
  if paths and paths[1] then
    local bytes
    bytes, err = o.files.read(paths[1], { max_bytes = 1024 * 1024 })
    if bytes then
      local text
      text, err = document.decode(bytes)
      if text then document.replace(s.doc, text, paths[1]); s.mode = "normal" end
    end
  end
  s.busy = false
  if err and (type(err) ~= "table" or err.name ~= "Canceled") then failure(err) end
  refocus()
end

local function perform(intent)
  s.pending, s.error = nil, nil
  if intent == "close" then o.exit(0)
  elseif intent == "open" then open()
  elseif intent == "new" then document.replace(s.doc, "", nil); s.mode = "normal"; refocus() end
end

local function request(intent)
  if s.busy or s.pending then return end
  s.palette = nil
  if document.dirty(s.doc) then s.pending = intent; refresh() else perform(intent) end
end

function actions.edit(text)
  local was_dirty, error = document.dirty(s.doc), s.error
  s.doc.text = text; s.error = nil
  -- Native text/selection/history already changed. Only rebuild their Lua
  -- surroundings when an edit changes something displayed outside the editor.
  if was_dirty ~= document.dirty(s.doc) or error then refresh() end
end

function actions.mode(command)
  if s.busy or s.pending or s.palette then return end
  if command == "submit" then s.mode = "insert"
  elseif command == "cancel" then s.mode = "normal" end
  refresh()
end

-- The nonconsuming listener only changes mode. The editor's key bindings
-- own selection and undoable edits, before these Lua callbacks run.
function actions.editor_key(event)
  if s.busy or s.pending or s.palette then return end
  local key = event.key
  if key == "COLON" and s.mode ~= "insert" then
    s.palette = { query = "", selected = 1 }
  elseif key == "Escape" then s.mode = "normal"
  elseif key == "V" and s.mode ~= "insert" then
    s.mode = s.mode == "visual" and "normal" or "visual"
  elseif s.mode == "normal" and (key == "A" or key == "I" or key == "O") then
    s.mode = "insert"
  elseif s.mode == "visual" then
    if key == "C" then s.mode = "insert"
    elseif key == "D" or key == "X" then s.mode = "normal" end
  end
  refresh()
end

function actions.palette_edit(text)
  if not s.palette then return end
  s.palette.query, s.palette.selected = text, 1
  refresh()
end
function actions.palette_cancel() s.palette = nil; refocus() end
function actions.palette_run(id)
  if not s.palette or s.busy or s.pending then return end
  s.palette = nil
  refocus()
  -- Closing the palette retires its widget task scope. File/portal awaits
  -- must outlive that scope, but still cancel when the app generation ends.
  o.spawn_app(actions.commands[id])
end
function actions.palette_command(command)
  if not s.palette then return end
  local matches = commands.matches(s.palette.query)
  if command == "cancel" then actions.palette_cancel()
  elseif command == "submit" then
    local selected = matches[s.palette.selected]
    if selected then actions.palette_run(selected.id) end
  elseif #matches > 0 then
    local delta = command == "previous" and -1 or command == "next" and 1 or 0
    s.palette.selected = (s.palette.selected - 1 + delta) % #matches + 1
    refresh()
  end
end

function actions.cancel() s.pending = nil; refocus() end
function actions.discard() if not s.busy then perform(s.pending) end end
function actions.save_continue()
  local intent = s.pending
  if save(false) and s.pending == intent then perform(intent) end
end
actions.commands.save = function() s.palette = nil; save(false) end
actions.commands.save_as = function() s.palette = nil; save(true) end
actions.commands.save_quit = function() if save(false) then perform("close") end end
actions.commands.open = function() request("open") end
actions.commands.new = function() request("new") end
actions.commands.close = function() request("close") end

return o.app {
  id = "dev.rockorager.folio", theme = view.theme,
  run = function()
    return { windows = {
      o.window { id = "main", title = "Folio", width = 960, height = 760,
        on_close_request = actions.commands.close,
        content = function() changed(); return view.content(s, actions) end,
      },
    } }
  end,
}
