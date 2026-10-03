local o = require("ouro")
local document = require("document")
local commands = require("commands")
local M = {}
M.default_font_size = 23

-- The app theme omits color_scheme so the host's Settings portal chooses light
-- or dark; M.content then applies Folio's palette for that scheme.
M.theme = {
  typography = { family = "sans-serif", size = 14 },
  controls = { height = 32, radius = 4, border_width = 0 },
}
M.palettes = {
  light = {
    colors = {
      background = "#F8F6F1", foreground = "#34352F", surface = "#F8F6F1",
      primary = "#A65337", primary_foreground = "#FFFFFF", border = "#DDD9D0",
      ring = "#A65337", selection = "#E8D7BE",
    },
    muted = "#85847B", panel = "#FFFFFF", backdrop = "#0000006E", shadow = "#00000050",
  },
  dark = {
    colors = {
      background = "#1D1C19", foreground = "#DCD7CB", surface = "#1D1C19",
      primary = "#DB8A66", primary_foreground = "#1D1C19", border = "#3A3833",
      ring = "#DB8A66", selection = "#4B3F31", card = "#282723",
    },
    muted = "#8E8A7F", panel = "#282723", backdrop = "#00000099", shadow = "#00000080",
  },
}

-- Stateless renders receive resolved colors, not the scheme name.
function M.scheme(theme)
  local r, g, b = theme.colors.background:match("^#(%x%x)(%x%x)(%x%x)")
  local luma = 0.2126 * tonumber(r, 16) + 0.7152 * tonumber(g, 16) + 0.0722 * tonumber(b, 16)
  return luma < 128 and "dark" or "light"
end

local motions = {
  H = "visual_left", J = "line_down", K = "line_up", L = "visual_right",
  W = "vim_word_start_next", E = "vim_word_end_next", B = "vim_word_start_previous",
  ["0"] = "logical_line_start", ["Shift+4"] = "logical_line_end",
  ["Shift+G"] = "document_end", ["Ctrl+Home"] = "document_start",
  Brace_Left = "paragraph_previous", ["Shift+Brace_Left"] = "paragraph_previous",
  Brace_Right = "paragraph_next", ["Shift+Brace_Right"] = "paragraph_next",
  Left = "visual_left", Right = "visual_right", Up = "line_up", Down = "line_down",
  Home = "line_start", End = "line_end",
}
M.normal_bindings = {
  inherit = false, I = { "normalize_caret", "submit" }, V = { "normalize_caret", "select_characters" }, Escape = "normalize_caret",
  ["Shift+V"] = "select_line",
  A = "append_character", ["Shift+A"] = "move_logical_line_end", ["Shift+I"] = "move_logical_line_start",
  O = "insert_line_below", ["Shift+O"] = "insert_line_above",
  U = { "undo", "normalize_caret" }, ["Ctrl+R"] = { "redo", "normalize_caret" },
  X = { "select_character_forward", "yank", "delete_selection" },
  ["Shift+X"] = { "select_character_backward", "yank", "delete_selection" },
  P = "put_after", ["Shift+P"] = "put_before", ["Ctrl+C"] = "copy",
  ["D D"] = { "select_line", "yank_lines", "delete_lines" },
  ["C C"] = { "select_line", "yank_lines", "begin_undo_group", "clear_lines", "submit" },
  ["Y Y"] = { "select_line", "yank_lines", "collapse_selection", "normalize_caret" },
  ["G G"] = "move_normal_document_start",
  ["Shift+D"] = { "select_logical_line_end", "yank", "delete_selection" },
  ["Shift+C"] = { "select_logical_line_end", "yank", "begin_undo_group", "delete_selection", "submit" },
  ["Shift+S"] = { "select_line", "yank_lines", "begin_undo_group", "clear_lines", "submit" },
  ["D W"] = { "select_vim_word_forward", "yank", "delete_selection" },
  ["C W"] = { "select_vim_change_word", "yank", "begin_undo_group", "delete_selection", "submit" },
  ["Y W"] = { "select_vim_word_forward", "yank", "collapse_selection_start" },
}
M.visual_bindings = {
  inherit = false, V = "normalize_caret", Escape = "normalize_caret", O = "swap_selection",
  ["Shift+V"] = "select_line", ["G G"] = "select_inclusive_document_start",
  Y = { "yank", "collapse_selection_start", "cancel" }, ["Ctrl+C"] = "copy",
  D = { "yank", "delete_selection" }, X = { "yank", "delete_selection" }, C = { "yank", "begin_undo_group", "delete_selection" },
}
M.visual_line_bindings = {
  inherit = false, V = "select_characters", ["Shift+V"] = "normalize_caret", Escape = "normalize_caret",
  J = "select_lines_down", K = "select_lines_up", Down = "select_lines_down", Up = "select_lines_up",
  H = "select_lines_left", L = "select_lines_right", Left = "select_lines_left", Right = "select_lines_right",
  W = "select_lines_word_start_next", B = "select_lines_word_start_previous", E = "select_lines_word_end_next",
  ["0"] = "select_lines_line_start", ["Shift+4"] = "select_lines_line_end",
  Home = "select_lines_line_start", End = "select_lines_line_end", O = "select_lines_swap",
  ["G G"] = "select_lines_start", ["Ctrl+Home"] = "select_lines_start", ["Shift+G"] = "select_lines_end",
  Brace_Left = "select_lines_paragraph_previous", ["Shift+Brace_Left"] = "select_lines_paragraph_previous",
  Brace_Right = "select_lines_paragraph_next", ["Shift+Brace_Right"] = "select_lines_paragraph_next",
  Y = { "yank_lines", "collapse_selection_start", "cancel" }, ["Ctrl+C"] = "copy",
  D = { "yank_lines", "delete_lines" }, X = { "yank_lines", "delete_lines" }, C = { "yank_lines", "begin_undo_group", "clear_lines" },
}
for key, destination in pairs(motions) do
  M.normal_bindings[key] = "move_normal_" .. destination
  M.visual_bindings[key] = "select_inclusive_" .. destination
end
for keys, object in pairs {
  ["I W"] = "vim_word_inner", ["A W"] = "vim_word_around",
  ["I P"] = "paragraph_inner", ["A P"] = "paragraph_around",
} do
  local select = "select_" .. object
  local paragraph = object:find("paragraph", 1, true)
  local yank = paragraph and "yank_lines" or "yank"
  M.visual_bindings[keys] = { select, "select_characters" }
  M.normal_bindings["D " .. keys] = { select, yank, paragraph and "delete_lines" or "delete_selection" }
  M.normal_bindings["C " .. keys] = { select, yank, "begin_undo_group", paragraph and "clear_lines" or "delete_selection", "submit" }
  M.normal_bindings["Y " .. keys] = { select, yank, "collapse_selection_start" }
end
for key, destination in pairs { E = "vim_word_end_next", B = "vim_word_start_previous" } do
  local select = "select_" .. destination
  M.normal_bindings["D " .. key] = { select, "yank", "delete_selection" }
  M.normal_bindings["C " .. key] = { select, "yank", "begin_undo_group", "delete_selection", "submit" }
  M.normal_bindings["Y " .. key] = { select, "yank", "collapse_selection_anchor" }
end
-- Deletions return to a character position; changes keep the insertion edge.
for _, bindings in ipairs { M.normal_bindings, M.visual_bindings, M.visual_line_bindings } do
  for key, recipe in pairs(bindings) do
    if key ~= "C" and type(recipe) == "table" and (recipe[#recipe] == "delete_selection" or recipe[#recipe] == "delete_lines") then
      recipe[#recipe + 1] = "normalize_caret"
    end
  end
end
local mode_keys = {
  normal = { "V", "Shift+V", "Escape", "A", "Shift+A", "Shift+I", "O", "Shift+O", "Colon", "Shift+Colon" },
  visual = { "V", "Shift+V", "Escape", "D", "X", "C", "Colon", "Shift+Colon" },
  ["visual-line"] = { "V", "Shift+V", "Escape", "D", "X", "C", "Colon", "Shift+Colon" },
  insert = { "Escape" },
}

local function page(s, actions, p)
  local c = p.colors
  local d = s.doc
  local dirty = document.dirty(d)
  local inserting = s.mode == "insert"
  local bindings = s.mode == "visual-line" and M.visual_line_bindings
    or s.mode == "visual" and M.visual_bindings
    or not inserting and M.normal_bindings or { Escape = "normalize_caret" }
  local modal
  if s.pending then
    modal = o.dialog { key = "confirm", label = "Unsaved changes", width = 420,
      on_cancel = actions.cancel,
      o.column { key = "body", gap = 18,
        o.text { key = "title", text = "Keep this draft?", size = 23 },
        o.text { key = "description", text = "Save changes to “" .. document.name(d) .. "” before continuing." },
        s.error and o.text { key = "error", text = s.error, foreground = c.primary } or o.box { key = "no-error" },
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
        background = index == s.palette.selected and c.selection or "#00000000",
        on_press = function() actions.palette_run(command.id) end,
        o.row { key = "row", gap = 20, cross_alignment = "center",
          o.text { key = "name", text = command.label, flex = 1 },
          o.text { key = "alias", text = ":" .. command.aliases[1], foreground = p.muted },
        },
      }
    end
    if #rows == 0 then rows[1] = o.text { key = "empty", text = "No matching commands", foreground = p.muted } end
    modal = o.box { key = "palette", role = "dialog", label = "Commands", on_cancel = actions.palette_cancel,
      width = "fill", height = "fill", alignment = "center", background = p.backdrop,
      o.box { key = "panel", semantic = false, width = 440, padding = 16,
        background = p.panel, border = c.border, border_width = 1, radius = 8,
        shadow = { x = 0, y = 8, blur = 24, spread = 0, color = p.shadow },
        o.column { key = "body", gap = 12, cross_alignment = "stretch",
          o.theme { key = "prompt", typography = { family = "sans-serif", size = 16 },
            o.row { key = "line", gap = 2, cross_alignment = "center",
              o.text { key = "colon", text = ":", foreground = c.primary },
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
  return o.box { key = "root", width = "fill", height = "fill",
    commands = actions.commands,
    shortcuts = { ["Ctrl+S"] = "save", ["Ctrl+Shift+S"] = "save_as",
      ["Ctrl+O"] = "open", ["Ctrl+N"] = "new", ["Ctrl+Q"] = "close",
      ["Ctrl+Equal"] = "font_increase", ["Ctrl+Plus"] = "font_increase", ["Ctrl+Shift+Plus"] = "font_increase",
      ["Ctrl+Minus"] = "font_decrease", ["Ctrl+0"] = "font_reset" },
    -- A viewport-sized floating child escapes the native window's content
    -- inset, whose color follows only the app theme. The outer layer repaints
    -- that inset in the scheme's palette; the inner layer's zero margin clamps
    -- either dialog's backdrop to the window edges.
    o.anchored { key = "surface", margin = 0, gap = 0, flip = false,
      o.box { key = "anchor" },
      o.box { key = "window", width = "fill", height = "fill", padding = o.tokens.foundation.spacing_3,
        background = c.background,
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
                o.theme { key = "prose", typography = { family = "serif", size = s.font_size or M.default_font_size },
                  o.text_editor { key = "draft-" .. d.generation, default_text = d.text, label = "Draft",
                    multiline = true, height = "fill", autofocus = true, focus_request = s.focus,
                    read_only = s.busy or s.pending ~= nil or s.palette ~= nil, text_entry = inserting,
                    caret_color = c.primary, selection_color = c.selection,
                    caret_shape = inserting and "beam" or "block", caret_blink = false,
                    key_bindings = bindings,
                    on_change = actions.edit, on_command = actions.mode,
                  },
                },
              },
            },
            o.box { key = "footer", padding_x = 24, padding_y = 16,
              o.column { key = "status", gap = 8,
                s.error and o.text { key = "error", text = s.error, foreground = c.primary } or o.box { key = "no-error" },
                o.row { key = "row", gap = 16, cross_alignment = "center",
                  o.text { key = "mode", text = s.mode:upper(), foreground = c.primary, size = 12 },
                  s.busy and o.text { key = "activity", flex = 1, alignment = "end", size = 12,
                    foreground = p.muted, text = "Working…" } or nil,
                },
              },
            },
          },
          modal,
        },
      },
    },
  }
end

local Themed = o.stateless(function(props, _, theme)
  local scheme = M.scheme(theme)
  local p = M.palettes[scheme]
  return o.theme { key = props.key, color_scheme = scheme, colors = p.colors, props.build(p) }
end)

function M.content(s, actions)
  return Themed { key = "folio-theme", build = function(p) return page(s, actions, p) end }
end

return M
