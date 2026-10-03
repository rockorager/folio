local o = require("ouro")
local document = require("document")
local commands = require("commands")
local view = require("view")

return {
  ["normal bindings delete whole graphemes and undo"] = function(t)
    local original = "a é 👩‍💻\nend"
    t:mount(function()
      return o.text_editor { key = "draft", label = "Draft", default_text = original,
        multiline = true, autofocus = true, text_entry = false,
        key_bindings = view.normal_bindings }
    end)
    t:key("home", { control = true })
    t:key("w")
    assert(t:node("draft").selection.extent == 2)
    t:key("x")
    assert(t:node("draft").value == "a  👩‍💻\nend")
    t:key("u")
    assert(t:node("draft").value == original)
    t:key("w")
    t:key("x")
    assert(t:node("draft").value == "a é \nend")
    t:key("u")
    assert(t:node("draft").value == original)
  end,

  ["change-to-line-end and Insert typing share undo"] = function(t)
    local inserting = o.signal(false)
    local original = "alpha βeta\nsecond line"
    t:mount(function()
      return o.text_editor { key = "draft", label = "Draft", default_text = original,
        multiline = true, autofocus = true, text_entry = inserting(),
        key_bindings = not inserting() and view.normal_bindings or nil,
        on_command = function(command)
          assert(command == "submit")
          inserting:set(true)
        end }
    end)
    t:key("home", { control = true })
    t:key("l")
    t:key("c", { shift = true })
    assert(inserting() and t:node("draft").value == "a\nsecond line")
    t:text("tail")
    assert(t:node("draft").value == "atail\nsecond line")
    t:key("z", { control = true })
    assert(t:node("draft").value == original)
  end,

  ["font changes retain the view's native editor and undo history"] = function(t)
    local size = o.signal(view.default_font_size)
    local original = "A café draft"
    local state = { doc = document.new(original), mode = "insert", focus = 0 }
    local actions = { commands = {
      font_increase = function() size:set(size() + 2) end,
      font_decrease = function() size:set(size() - 2) end,
      font_reset = function() size:set(view.default_font_size) end,
    }, edit = function(text) state.doc.text = text end,
      editor_key = function() end, mode = function() end }
    for _, command in ipairs(commands.items) do
      actions.commands[command.id] = function() error("unexpected file command") end
    end
    t:mount(function()
      state.font_size = size()
      return view.content(state, actions)
    end, { width = 960, height = 760 })
    local path = "folio-theme/root/surface/window/layers/page/margin/measure/prose/draft-1"
    local before = t:node(path)
    t:key("end", { control = true })
    t:text("!")
    t:key("equal", { control = true })
    local enlarged = t:node(path)
    assert(enlarged.id == before.id and enlarged.value == original .. "!")
    assert(enlarged.caret_bounds.height > before.caret_bounds.height)
    t:key("digit_0", { control = true })
    assert(t:node(path).caret_bounds.height == before.caret_bounds.height)
    t:key("z", { control = true })
    assert(t:node(path).value == original)
  end,
}
