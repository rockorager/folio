local o = require("ouro")
local document = require("document")
local commands = require("commands")
local M = {}

M.theme = {
  color_scheme = "light",
  colors = {
    background = "#F8F6F1", foreground = "#34352F", surface = "#F8F6F1",
    primary = "#A65337", primary_foreground = "#FFFFFF", border = "#DDD9D0",
    ring = "#A65337", selection = "#E8D7BE",
  },
  typography = { family = "sans-serif", size = 14 },
  controls = { height = 32, radius = 4, border_width = 0 },
}

local motions = {
  H = "visual_left", J = "line_down", K = "line_up", L = "visual_right",
  W = "word_next", E = "word_next", B = "word_previous",
  ["0"] = "logical_line_start", ["Shift+4"] = "logical_line_end",
  ["Shift+G"] = "document_end", ["Ctrl+Home"] = "document_start",
  Left = "visual_left", Right = "visual_right", Up = "line_up", Down = "line_down",
  Home = "line_start", End = "line_end",
}
M.normal_bindings = {
  inherit = false, I = "submit", V = "collapse_selection", Escape = "collapse_selection",
  A = "move_visual_right", ["Shift+A"] = "move_logical_line_end", ["Shift+I"] = "move_logical_line_start",
  O = "insert_line_below", ["Shift+O"] = "insert_line_above",
  U = "undo", ["Ctrl+R"] = "redo", X = "delete_forward", ["Shift+X"] = "delete_backward",
  P = "paste", ["Ctrl+C"] = "copy",
}
M.visual_bindings = {
  inherit = false, I = "submit", V = "collapse_selection", Escape = "collapse_selection",
  Y = "copy", ["Ctrl+C"] = "copy", D = "delete_forward", X = "delete_forward", C = "delete_forward",
}
for key, destination in pairs(motions) do
  M.normal_bindings[key] = "move_" .. destination
  M.visual_bindings[key] = "select_" .. destination
end
local mode_keys = {
  normal = { "V", "Escape", "A", "Shift+A", "Shift+I", "O", "Shift+O", "Colon", "Shift+Colon" },
  visual = { "V", "Escape", "D", "X", "C", "Colon", "Shift+Colon" },
  insert = { "Escape" },
}

function M.content(s, actions)
  local d = s.doc
  local dirty = document.dirty(d)
  local inserting = s.mode == "insert"
  local selecting = s.mode == "visual"
  local modal
  if s.pending then
    modal = o.dialog { key = "confirm", label = "Unsaved changes", width = 420,
      on_cancel = actions.cancel,
      o.column { key = "body", gap = 18,
        o.text { key = "title", text = "Keep this draft?", size = 23 },
        o.text { key = "description", text = "Save changes to “" .. document.name(d) .. "” before continuing." },
        s.error and o.text { key = "error", text = s.error, foreground = "#A65337" } or o.box { key = "no-error" },
        o.row { key = "buttons", gap = 8,
          o.button { key = "cancel", label = "Cancel", variant = "ghost", on_press = actions.cancel },
          o.button { key = "discard", label = "Discard", variant = "ghost", enabled = not s.busy, on_press = actions.discard },
          o.button { key = "save", label = "Save", enabled = not s.busy, on_press = actions.save_continue },
        },
      },
    }
  elseif s.palette then
    local matches, rows = commands.matches(s.palette.query), {}
    for index, command in ipairs(matches) do
      rows[#rows + 1] = o.button { key = command.id, label = command.label, variant = "ghost", tone = "neutral",
        background = index == s.palette.selected and "#E8D7BE" or "#00000000",
        on_press = function() actions.palette_run(command.id) end,
        o.row { key = "row", gap = 20, cross_alignment = "center",
          o.text { key = "name", text = command.label, flex = 1 },
          o.text { key = "alias", text = ":" .. command.aliases[1], foreground = "#85847B" },
        },
      }
    end
    if #rows == 0 then rows[1] = o.text { key = "empty", text = "No matching commands", foreground = "#85847B" } end
    modal = o.box { key = "palette", role = "dialog", label = "Commands", on_cancel = actions.palette_cancel,
      width = "fill", height = "fill", alignment = "center", background = "#0000006E",
      o.box { key = "panel", semantic = false, width = 440, padding = 16,
        background = "#FFFFFF", border = M.theme.colors.border, border_width = 1, radius = 8,
        shadow = { x = 0, y = 8, blur = 24, spread = 0, color = "#00000050" },
        o.column { key = "body", gap = 12, cross_alignment = "stretch",
          o.theme { key = "prompt", typography = { family = "monospace", size = 16 },
            o.row { key = "line", gap = 2, cross_alignment = "center",
              o.text { key = "colon", text = ":", foreground = "#A65337" },
              o.text_editor { key = "query", label = "Command", text = s.palette.query,
                flex = 1, autofocus = true, caret_blink = false,
                on_change = actions.palette_edit, on_command = actions.palette_command },
            },
          },
          o.column { key = "results", gap = 4, cross_alignment = "stretch", children = rows },
        },
      },
    }
  end
  return o.box { key = "root", width = "fill", height = "fill", background = "#F8F6F1",
    commands = actions.commands,
    shortcuts = { ["Ctrl+S"] = "save", ["Ctrl+Shift+S"] = "save_as",
      ["Ctrl+O"] = "open", ["Ctrl+N"] = "new", ["Ctrl+Q"] = "close" },
    -- A viewport-sized floating child escapes the native window's content
    -- inset. Zero margin clamps either dialog's backdrop to the window edges.
    o.anchored { key = "layers", margin = 0, gap = 0, flip = false,
      o.column { key = "page", width = "fill", height = "fill", cross_alignment = "stretch",
        o.box { key = "header", padding_x = 24, padding_y = 14,
          o.row { key = "row", cross_alignment = "center", gap = 8,
            o.text { key = "filename", text = document.name(d) .. (dirty and "  •" or ""), flex = 1, max_lines = 1, overflow = "ellipsis" },
          },
        },
        o.box { key = "margin", flex = 1, padding_x = 32, padding_y = 38, alignment = "top",
          o.box { key = "measure", width = "fill", max_width = 680, height = "fill",
            on_key = { keys = mode_keys[s.mode], states = { "pressed" }, propagate = true,
              handler = actions.editor_key },
            o.theme { key = "prose", typography = { family = "serif", size = 23 },
              o.text_editor { key = "draft-" .. d.generation, default_text = d.text, label = "Draft",
                multiline = true, height = "fill", autofocus = true, focus_request = s.focus,
                read_only = s.busy or s.pending ~= nil or s.palette ~= nil, text_entry = inserting,
                caret_color = M.theme.colors.primary, selection_color = "#E8D7BE",
                caret_shape = inserting and "beam" or "block", caret_blink = false,
                key_bindings = selecting and M.visual_bindings or (not inserting and M.normal_bindings
                  or { Escape = "collapse_selection" }),
                on_change = actions.edit, on_command = actions.mode,
              },
            },
          },
        },
        o.box { key = "footer", padding_x = 24, padding_y = 16,
          o.column { key = "status", gap = 8,
            s.error and o.text { key = "error", text = s.error, foreground = "#A65337" } or o.box { key = "no-error" },
            o.row { key = "row", gap = 16, cross_alignment = "center",
              o.text { key = "mode", text = s.mode:upper(), foreground = "#A65337", size = 12 },
              s.busy and o.text { key = "activity", flex = 1, alignment = "end", size = 12,
                foreground = "#85847B", text = "Working…" } or nil,
            },
          },
        },
      },
      modal,
    },
  }
end

return M
