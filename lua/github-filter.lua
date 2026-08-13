--- 過濾: ../site/data.json, 依條件取出指定的內容

---@class Workflow @field name string
---@field path string
---@field url string

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
---@field updated_at string  -- ISO8601 UTC, 例如 "2026-08-01T23:47:38Z"
---@field created_at string
---@field workflows Workflow[]
---@field issue_templates any[]

---@class RepoData  參考: ../site/data.json
---@field generated_at string
---@field items RepoItem[]

local M = {}

---計算 n 天前的 UTC ISO8601 字串（可直接用字串比較）
---@param days integer
---@return string|osdate
local function cutoff_iso(days)
  local ts = os.time() - days * 86400
  return os.date("!%Y-%m-%dT%H:%M:%SZ", ts)
end

---篩選條件
---1. workflows 非空
---2. updated_at ≥ 一週內（字串比較，O(1)）
---3. stars > 150
---@param data RepoData
---@param max_age_days integer? 預設 7
---@param min_stars integer? 預設 150
---@return RepoItem[]
function M.filter(data, max_age_days, min_stars)
  max_age_days = max_age_days or 7
  min_stars = min_stars or 150

  local cutoff = cutoff_iso(max_age_days)
  local items = data.items
  local result = {}
  local n = 0

  for i = 1, #items do
    local item = items[i]
    -- 先做 cheap 條件，減少字串比較次數
    if item.stars > min_stars
        and item.workflows
        and #item.workflows > 0
        and item.updated_at >= cutoff
    then
      n = n + 1
      result[n] = item
    end
  end

  return result
end

---從檔案讀取並篩選（方便直接 :luafile 或 require）
---@param path string
---@param max_age_days integer?
---@param min_stars integer?
---@return RepoItem[]
function M.filter_file(path, max_age_days, min_stars)
  local f = assert(io.open(path, "r"))
  local content = f:read("*a")
  f:close()

  local data = vim.json.decode(content) --[[@as RepoData]]
  return M.filter(data, max_age_days, min_stars)
end

return M
