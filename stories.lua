local o = require("ouro")
local document = require("document")
local view = require("view")
local sample = [[A room for words

The first thing I noticed was the quiet. Not the absence of sound, but the space between things: a cup on the table, rain at the window, a sentence waiting to be finished.

I had spent the morning moving words around. A paragraph moved up. A sentence disappeared. What remained was closer to what I meant.

Writing is sometimes like that. Less a matter of finding something new than making enough room to see what is already there.]]
local function noop() end
local actions = { commands = { save = noop, save_as = noop, open = noop, new = noop, close = noop,
    font_increase = noop, font_decrease = noop, font_reset = noop },
  edit = noop, mode = noop, editor_key = noop, cancel = noop, discard = noop, save_continue = noop,
  palette_run = noop, palette_cancel = noop, palette_edit = noop, palette_command = noop }
local stories = {}
for _, state in ipairs {
  { id = "normal", mode = "normal", width = 960 },
  { id = "insert", mode = "insert", width = 960 },
  { id = "narrow", mode = "normal", width = 540 },
  { id = "unsaved", mode = "insert", width = 960, pending = "close" },
  { id = "empty", mode = "normal", width = 960, empty = true },
  { id = "commands", mode = "normal", width = 960, palette = { query = "", selected = 1 } },
  { id = "commands-filtered", mode = "normal", width = 540, palette = { query = "wq", selected = 1 } },
  { id = "commands-empty", mode = "normal", width = 960, palette = { query = "unknown", selected = 1 } },
  { id = "dark-normal", mode = "normal", width = 960, color_scheme = "dark" },
  { id = "dark-insert", mode = "insert", width = 960, color_scheme = "dark" },
  { id = "dark-unsaved", mode = "insert", width = 960, pending = "close", color_scheme = "dark" },
  { id = "dark-commands", mode = "normal", width = 960, palette = { query = "", selected = 1 }, color_scheme = "dark" },
} do
  stories[#stories + 1] = o.story {
    id = "folio/" .. state.id, name = state.id, group = "Folio",
    viewport = { width = state.width, height = 760 }, snapshot_scale = 2, color_scheme = state.color_scheme,
    content = function()
      local d = document.new(state.empty and "" or sample)
      if not state.empty then d.path = "/tmp/A room for words.md" end
      if state.pending then d.saved = "" end
      return o.theme { key = "app-theme", typography = view.theme.typography, controls = view.theme.controls,
        view.content({ doc = d, mode = state.mode, focus = 0, pending = state.pending, palette = state.palette }, actions),
      }
    end,
  }
end
return o.storybook { stories = stories }
