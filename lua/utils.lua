local M = {}

--- 去除', (, ), "
---
---@param s string
---@return string
function M.strip_outer(s)
  return s:match("^%((.-)%)$")
      or s:match('^"(.-)"$')
      or s:match("^'(.-)'$")
      or s
end

return M
