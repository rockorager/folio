-- File commands shared by the palette view and its keyboard controller.
local M = {}
M.items = {
  { id = "save", label = "Save", aliases = { "w", "write" } },
  { id = "open", label = "Open", aliases = { "e", "edit" } },
  { id = "save_as", label = "Save as", aliases = { "saveas" } },
  { id = "new", label = "New document", aliases = { "enew" } },
  { id = "save_quit", label = "Save and quit", aliases = { "wq" } },
  { id = "close", label = "Quit", aliases = { "q", "quit" } },
}

function M.matches(query)
  query = query:lower():match("^%s*(.-)%s*$"):gsub("^:", "")
  local result = {}
  for _, command in ipairs(M.items) do
    local matches = command.label:lower():find(query, 1, true) ~= nil
    for _, alias in ipairs(command.aliases) do
      if query == alias then return { command } end
      matches = matches or alias:sub(1, #query) == query
    end
    if matches then result[#result + 1] = command end
  end
  return result
end

return M
