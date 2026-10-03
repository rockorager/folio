local o = require("ouro")
local document = require("document")
local view = require("view")
local commands = require("commands")
local changed = o.signal(0)
local s = { doc = document.new(), mode = "normal", focus = 0, busy = false, font_size = view.default_font_size }
local actions = { commands = {} }
local filters = { { name = "Plain text", patterns = { "*.txt", "*.md", "*.markdown" } } }

local function refresh() changed:set(changed() + 1) end
local function refocus() s.focus = s.focus + 1; refresh() end
local function failure(err)
  if type(err) == "table" and err.committed then
    s.error = "The file was replaced, but its survival across a power loss could not be confirmed. The draft remains marked unsaved."
  elseif type(err) == "table" and err.name == "SymlinkNotAllowed" then
    s.error = "This path is a symbolic link. Use Save As to choose its target or another file."
  else
    s.error = type(err) == "table" and (err.message or err.name) or tostring(err)
  end
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
  if ok or (err and err.committed) then document.saved(s.doc, snapshot, path, ok == true) end
  if not ok then failure(err) end
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

local function mode(name)
  if s.busy or s.pending or s.palette then return end
  s.mode = name
  refresh()
end
actions.commands.insert = function() mode("insert") end
actions.commands.normal = function() mode("normal") end
actions.commands.visual = function() mode("visual") end
actions.commands.visual_line = function() mode("visual-line") end
function actions.commands.palette()
  if s.busy or s.pending or s.palette or s.mode == "insert" then return end
  s.palette = { query = "", selected = 1 }
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
  actions.commands[id]()
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
actions.discard = o.app_command(function() if not s.busy then perform(s.pending) end end)
actions.save_continue = o.app_command(function()
  local intent = s.pending
  if save(false) and s.pending == intent then perform(intent) end
end)
actions.commands.save = function() s.palette = nil; save(false) end
actions.commands.save_as = function() s.palette = nil; save(true) end
actions.commands.save_quit = function() if save(false) then perform("close") end end
actions.commands.open = function() request("open") end
actions.commands.new = function() request("new") end
actions.commands.close = function() request("close") end
-- File commands outlive the palette/button that invokes them, but not reload.
for _, command in ipairs(commands.items) do
  actions.commands[command.id] = o.app_command(actions.commands[command.id])
end

local function font_size(size)
  size = math.max(12, math.min(48, size))
  if size ~= s.font_size then s.font_size = size; refresh() end
end
actions.commands.font_increase = function() font_size(s.font_size + 2) end
actions.commands.font_decrease = function() font_size(s.font_size - 2) end
actions.commands.font_reset = function() font_size(view.default_font_size) end

return o.app {
  id = "dev.rockorager.folio", theme = view.theme,
  run = function()
    return { windows = {
      o.window { id = "main", title = "Folio", width = 960, height = 760, padding = 0,
        on_close_request = actions.commands.close,
        content = function() changed(); return view.content(s, actions) end,
      },
    } }
  end,
}
