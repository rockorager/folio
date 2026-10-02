-- Plain-text document state. Persistence snapshots must not swallow later edits.
local M = {}

function M.new(text, path)
  text = text or ""
  return { text = text, saved = text, path = path, generation = 1 }
end

function M.decode(bytes)
  if bytes:find("\0", 1, true) or not utf8.len(bytes) then
    return nil, "This file is not UTF-8 plain text."
  end
  -- Keep the editor and saved baseline in its native LF representation.
  return (bytes:gsub("\r\n", "\n"):gsub("[\r\v\f]", "\n")
    :gsub(utf8.char(0x85), "\n"):gsub(utf8.char(0x2028), "\n"):gsub(utf8.char(0x2029), "\n"))
end

function M.dirty(d)
  return d.text ~= d.saved
end

function M.replace(d, text, path)
  d.text, d.saved, d.path = text, text, path
  d.generation = d.generation + 1
end

function M.snapshot(d)
  return { text = d.text, generation = d.generation }
end

function M.saved(d, snapshot, path)
  if snapshot.generation ~= d.generation then return false end
  d.saved, d.path = snapshot.text, path
  return true
end

function M.name(d)
  if not d.path then return "Untitled" end
  local name = d.path:match("([^/]+)$") or d.path
  if d.path:match("^file:") then
    name = name:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
  end
  return name
end

function M.words(text)
  -- Whitespace-delimited words, not a language-specific tokenizer.
  local count, inside = 0, false
  for _, cp in utf8.codes(text) do
    local space = cp <= 32 or cp == 0x85 or cp == 0xa0 or cp == 0x1680
      or (cp >= 0x2000 and cp <= 0x200a) or cp == 0x2028 or cp == 0x2029
      or cp == 0x202f or cp == 0x205f or cp == 0x3000
    if not space and not inside then count = count + 1 end
    inside = not space
  end
  return count
end

return M
