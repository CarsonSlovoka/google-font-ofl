--- 過濾: ../site/data.json, 依條件取出指定的內容

-- ---@diagnostic disable: undefined-field

-- filter.lua
-- Neovim 0.12+ dual-purpose module: library + CLI
-- Efficient single-pass filter for ~3000 items.
-- Errors are soft (return nil, err) like Go; caller decides.

local M = {}

----------------------------------------------------------------------
-- Types (luadoc)
----------------------------------------------------------------------

---@class Condition
---@field field string
---@field op string              -- ">", ">=", "<", "<=", "==", "!=", "empty", "nonempty", "length"
---@field value any              -- number|string|nil
---@field length_op string|nil   -- only when op=="length": ">", ">=", "<", "<=", "==", "!="

---@class RepoItem
---@field username string
---@field dirname string
---@field url string
---@field repo_name string
---@field stars integer
---@field forks integer
---@field language string
---@field description string
---@field pushed_at string
---@field updated_at string
---@field created_at string
---@field workflows table[]
---@field issue_templates table[]

---@class RepoData
---@field generated_at string
---@field items RepoItem[]

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local OPS = {
  [">"] = true,
  [">="] = true,
  ["<"] = true,
  ["<="] = true,
  ["=="] = true,
  ["!="] = true,
}

---Trim whitespace
---@param s string
---@return string
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

----------------------------------------------------------------------
-- Condition parser (efficient pattern matching, no backtracking)
----------------------------------------------------------------------

---Extract operator from the beginning of a string (no Lua | needed).
---Returns op, remaining_string or nil.
---@param rest string
---@return string|nil op
---@return string|nil remaining
local function extract_op(rest)
  if #rest < 1 then return nil end
  local two = rest:sub(1, 2)
  if two == ">=" or two == "<=" or two == "==" or two == "!=" then
    return two, rest:sub(3)
  end
  local one = rest:sub(1, 1)
  if one == ">" or one == "<" then
    return one, rest:sub(2)
  end
  return nil
end

---Parse a single condition string into Condition table.
---Supported forms (spaces optional when quoted by caller):
---  stars>150
---  stars > 150
---  updated_at>=2026-08-01
---  language==Python
---  workflows empty
---  workflows nonempty
---  workflows length>0
---  issue_templates length >= 1
---@param s string
---@return Condition|nil
---@return string? error
function M.parse_condition(s)
  if type(s) ~= "string" then
    return nil, "condition must be string"
  end
  s = trim(s)
  if s == "" then
    return nil, "empty condition"
  end

  -- 1. field empty / nonempty
  do
    local field, special = s:match("^([%w_]+)%s+(empty)$")
    if field then
      return { field = field, op = special, value = nil }
    end
    field, special = s:match("^([%w_]+)%s+(nonempty)$")
    if field then
      return { field = field, op = special, value = nil }
    end
  end

  -- 2. field length OP NUMBER
  do
    local field, after = s:match("^([%w_]+)%s+length%s*(.*)$")
    if field and after then
      local op, rest = extract_op(after)
      if op then
        local num = rest:match("^%s*(%d+)%s*$")
        if num then
          return {
            field = field,
            op = "length",
            length_op = op,
            value = tonumber(num),
          }
        end
      end
    end
  end

  -- 3. fieldOP value   (no spaces around op)  e.g. stars>150
  do
    local field, rest = s:match("^([%w_]+)(.*)$")
    if field and rest and rest ~= "" then
      local op, value = extract_op(rest)
      if op then
        value = trim(value)
        if value == "" then
          return nil, "missing value in condition: " .. s
        end
        return { field = field, op = op, value = value }
      end
    end
  end

  -- 4. field OP value  (with spaces)  e.g. stars > 150
  do
    local field, rest = s:match("^([%w_]+)%s+(.*)$")
    if field and rest then
      local op, value = extract_op(rest)
      if op then
        value = trim(value)
        if value ~= "" then
          return { field = field, op = op, value = value }
        end
      end
    end
  end

  return nil, "invalid condition syntax: " .. s
end

----------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------

---Compare two values with the given operator.
---Prefer numeric comparison when both sides can be numbers;
---otherwise fall back to string comparison (works for ISO8601 dates).
---@param left any
---@param op string
---@param right any
---@return boolean
local function compare(left, op, right)
  local nleft  = tonumber(left)
  local nright = tonumber(right)

  if nleft and nright then
    if op == ">" then return nleft > nright end
    if op == ">=" then return nleft >= nright end
    if op == "<" then return nleft < nright end
    if op == "<=" then return nleft <= nright end
    if op == "==" then return nleft == nright end
    if op == "!=" then return nleft ~= nright end
  end

  -- string (or date) comparison
  local sleft  = tostring(left)
  local sright = tostring(right)
  if op == ">" then return sleft > sright end
  if op == ">=" then return sleft >= sright end
  if op == "<" then return sleft < sright end
  if op == "<=" then return sleft <= sright end
  if op == "==" then return sleft == sright end
  if op == "!=" then return sleft ~= sright end

  return false
end

---Test whether one item satisfies one condition.
---Missing field or wrong type → false (soft, never error).
---@param item table
---@param cond Condition
---@return boolean
local function match_item(item, cond)
  local val = item[cond.field]

  if cond.op == "empty" then
    return type(val) == "table" and #val == 0
  end
  if cond.op == "nonempty" then
    return type(val) == "table" and #val > 0
  end
  if cond.op == "length" then
    if type(val) ~= "table" then return false end
    return compare(#val, cond.length_op, cond.value)
  end

  -- normal operators
  if val == nil then
    return false
  end
  return compare(val, cond.op, cond.value)
end

----------------------------------------------------------------------
-- Public library API
----------------------------------------------------------------------

---Filter items by a list of condition strings (AND logic).
---@param data RepoData|table  must contain .items array
---@param conditions string[]
---@return RepoItem[]|nil
---@return string? error
function M.filter(data, conditions)
  if type(data) ~= "table" or type(data.items) ~= "table" then
    return nil, "invalid data: expected table with .items array"
  end
  if type(conditions) ~= "table" then
    return nil, "conditions must be a list of strings"
  end

  ---@type Condition[]
  local parsed = {}
  for i, s in ipairs(conditions) do
    local c, err = M.parse_condition(s)
    if not c then
      return nil, string.format("condition #%d: %s", i, err)
    end
    parsed[#parsed + 1] = c
  end

  local result = {}
  local n = 0
  local items = data.items

  for i = 1, #items do
    local item = items[i]
    local ok = true
    for j = 1, #parsed do
      if not match_item(item, parsed[j]) then
        ok = false
        break
      end
    end
    if ok then
      n = n + 1
      result[n] = item
    end
  end

  return result
end

---Read JSON file and filter.
---@param path string
---@param conditions string[]
---@return RepoItem[]|nil
---@return string? error
function M.filter_file(path, conditions)
  if type(path) ~= "string" or path == "" then
    return nil, "path must be a non-empty string"
  end

  local f, err = io.open(path, "r")
  if not f then
    return nil, "cannot open file: " .. tostring(err)
  end
  local content = f:read("*a")
  f:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil, "json decode failed: " .. tostring(data)
  end

  return M.filter(data, conditions)
end

return M
