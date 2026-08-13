--         nvim   -l         find_github_page.lua 1>list.md 2>no_found.md
-- (cd ..; nvim   -l scripts/find_github_page.lua 1>list.md 2>no_found.md)

-- Compatible with Neovim 0.9+
-- Requires: fd (or fdfind) in PATH


local script_file = debug.getinfo(1, "S").source:sub(2)
-- Prefer vim.fs if available, fallback for older nvim
local script_dir
if vim.fs and vim.fs.dirname then
  local abs = (vim.fs.abspath and vim.fs.abspath(script_file)) or vim.fn.fnamemodify(script_file, ":p")
  script_dir = vim.fs.dirname(abs)
else
  script_dir = vim.fn.fnamemodify(script_file, ":p:h")
end

local git_root = vim.fn.fnamemodify(script_dir, ":h:p") -- 使得 git_root/lua/*.lua 下的內容可以被當成require的對像
vim.opt.runtimepath:prepend(git_root)

local utils = require("utils")

---@class SearchOpt
---@field wkdir string
---@field ext   string

---@param filename string
---@param opts     SearchOpt
---@return fun():string, ...
local function search_files(filename, opts)
  opts = opts or {}
  opts = vim.tbl_deep_extend("force", {
    wkdir = ".",
    opts = "", -- -HI
    ext = "",
  }, opts)

  -- Prefer `fd`, fall back to `fdfind` (Debian/Ubuntu package name)
  local fd_bin = "fd"
  if vim.fn.executable("fd") == 0 then
    if vim.fn.executable("fdfind") == 1 then
      fd_bin = "fdfind"
    else
      error("Neither 'fd' nor 'fdfind' found in PATH. Install fd-find.")
    end
  end

  local cmd = string.format("%s %s %s %s %s",
    fd_bin, filename, opts.ext, opts.opts,
    vim.fn.shellescape(opts.wkdir))
  local lines = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    error(string.format("fd failed (code %s): %s", vim.v.shell_error, table.concat(lines, "\n")))
  end

  local i = 0
  return function()
    i = i + 1
    return lines[i]
  end
end

---@class GithubInfo
---@field repo_name string
---@field username  string
---@field url       string
---@field dirname   string?


--- 不是每個專案都有這個檔案
---@param filepath string
---@return GithubInfo?
local function get_github_info_article_html(filepath)
  assert(vim.fn.fnamemodify(filepath, ":t") == "ARTICLE.en_us.html" or true, "expected ARTICLE.en_us.html")
  -- Use :edit! to avoid modified buffer issues in batch
  vim.cmd("edit! " .. vim.fn.fnameescape(filepath))

  -- Search for github link (double or single quoted)
  local found = vim.fn.search([[href=['"]https://github.com/[^'"]*['"]>]], "w")
  if found == 0 then
    return nil
  end

  -- Try to yank the URL inside quotes
  vim.fn.setreg('"', "")
  -- Move to the href value and yank inside quotes
  vim.cmd([[normal! f"vi"y]])
  local url = vim.fn.getreg('"')
  if #url < 20 then
    -- try single quote
    vim.cmd("normal! gg")
    vim.fn.search([[href=['"]https://github.com/[^'"]*['"]>]], "w")
    vim.fn.setreg('"', "")
    vim.cmd([[normal! f'vi'y]])
    url = vim.fn.getreg('"')
  end

  if #url > 20 then
    -- Clean trailing slash or fragments if any
    url = url:gsub("/$", "")
    local username, repo_name = url:match("^https?://github%.com/([^/]+)/([^/#?]+)")
    if username and repo_name then
      return {
        username = username,
        repo_name = repo_name,
        url = url,
      }
    end
  end
  return nil
end


--- 有的比較舊的專案，裡面不會寫到任何的url, 例如: https://github.com/google/fonts/tree/038b637da7b3fd956a4ed93ffc607c3d5e4ce172/ofl/rumraisin
---
---@param filepath string
---@return GithubInfo?
local function get_github_info_from_upstream_info(filepath)
  assert(vim.fn.fnamemodify(filepath, ":t") == "upstream_info.md" or true, "expected upstream_info.md")
  -- Use :edit! to avoid modified buffer issues in batch
  vim.cmd("edit! " .. vim.fn.fnameescape(filepath))

  -- Search for github link (double or single quoted)
  local link_type = 1
  local found = vim.fn.search([[.*|.*https://github.com/[^'"]*]], "w") -- | Repository URL | https://github.com/42dot/42dot-Sans |
  if found == 0 then
    vim.cmd("normal! gg")
    if vim.fn.search([[(https://github.com/[^'"]*)]], "w") == 0 then -- 有的是寫這樣，不是用table: - **URL**: https://github.com/notofonts/hanunoo
      -- error("github url not found: " .. filepath)
      return nil
    end
    link_type = 2
  end

  -- Try to yank the URL inside quotes
  if link_type == 1 then
    vim.cmd([[normal! 0f|fhviWy]])
  elseif link_type == 2 then
    -- vim.cmd([[normal! 0]])
    -- vim.fn.search("https://github.com", "w")
    vim.cmd("normal! lviby")
  end
  vim.fn.setreg('"', "")
  local url = vim.fn.getreg('"')
  url = url:gsub("/$", "")
  local username, repo_name = url:match("^https?://github%.com/([^/]+)/([^/#?]+)")
  if username and repo_name then
    return {
      username = username,
      repo_name = repo_name,
      url = url,
    }
  end
  -- error("url not match: " .. url)
  return nil
end


---@param filepath string
---@return GithubInfo?
local function get_github_info_from_metadata(filepath)
  assert(vim.fn.fnamemodify(filepath, ":t") == "METADATA.pb" or true, "expected METADATA.pb")
  vim.cmd("edit! " .. vim.fn.fnameescape(filepath))


  -- https://github.com/google/fonts/blob/038b637da7b3fd956a4ed93ffc607c3d5e4ce172/ofl/notoserifsc/METADATA.pb#L27 它用的是連結是www, 而不是github開頭: https://www.github.com/notofonts/noto-cjk
  -- local found = vim.fn.search([["https://github.com/[^'"]*"]], "w")
  local found = vim.fn.search([[\v"https://(www.)?github.com/[^'"]*"]], "w")
  if found == 0 then
    -- error("url not found")
    return
  end
  vim.cmd([[normal! lvi"y]])
  local url = vim.fn.getreg('"')
  url = url:gsub("/$", "")
  -- local url = "https://www.github.com/notofonts/noto-cjk"
  url = url:gsub("^(https?://)www%.", "%1") -- 去除www 即 www.github.com => github.com 就好
  -- print(url)
  -- local url = "https://github.com/notofonts/noto-cjk"
  local username, repo_name = url:match("^https?://github%.com/([^/]+)/([^/#?]+)")
  -- print(url, username, repo_name)

  if username and repo_name then
    return {
      username = username,
      repo_name = repo_name,
      url = url,
    }
  end
  -- error("url not match: " .. url .. "\n" .. filepath)
  return nil
end

---@param filepath string
---@return GithubInfo?
local function get_github_info_from_ofl_txt(filepath)
  assert(vim.fn.fnamemodify(filepath, ":t") == "OFL.txt" or true, "expected OFL.txt")
  vim.cmd("edit! " .. vim.fn.fnameescape(filepath))
  vim.cmd("set fileformat=unix") -- 轉成\n

  local found = vim.fn.search([[\vhttps://(www.)?github.com/[^'"]*]], "w")
  if found == 0 then
    return
  end

  vim.cmd([[normal! viWy]])
  local url = vim.fn.getreg('"')
  url = url:gsub("/$", "")
  url = utils.strip_outer(url) -- 去除', (, ), "
  local username, repo_name = url:match("^https?://github%.com/([^/]+)/([^/#?]+)")
  if username and repo_name then
    return {
      username = username,
      repo_name = repo_name,
      url = url,
    }
  end
  return nil
end

--- 輸出範本參考: ../site/data.json
--- 當中items中的每一個項目，會再後續用GITHUB_TOKEN呼叫GitHub API為每個 unique repo 補上 `stars` / `forks` / `language`
---
---@param items GithubInfo[]
---@param count_ok  integer
---@param count_err integer
---@return boolean
local function gen_summary_json(items, count_ok, count_err)
  -- Also write structured JSON for the GitHub Pages frontend
  -- Path relative to CWD (workflow runs from repo root)
  local json_path = "data.json"
  local payload = {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    success_count = count_ok,
    fail_count = count_err,
    items = items,
  }
  local ok_json, encoded = pcall(vim.json.encode, payload)
  if ok_json and encoded then
    local f = io.open(json_path, "w")
    if f then
      f:write(encoded)
      f:close()
      -- note on stderr so it doesn't pollute list.md
      io.stderr:write(string.format("Wrote %s (%d items)\n", json_path, count_ok))
    end
  else
    io.stderr:write("WARN: failed to encode data.json\n")
  end
end

local function main()
  ---@type GithubInfo[]
  local github_pages = {}

  local count_ok = 0
  local count_err = 0
  local err = nil
  local ofl_dir = script_dir .. "/../ofl"

  -- fd upstream_info.md -e md -HI ../ofl
  for filepath in search_files("upstream_info.md", {
    ext = "-e md",
    opts = "-HI",
    wkdir = ofl_dir,
  }) do
    local normalized = (vim.fs and vim.fs.normalize and vim.fs.normalize(filepath)) or filepath
    local dirname = normalized:match("/ofl/([^/]+)")
    if not dirname then
      dirname = vim.fn.fnamemodify(filepath, ":h:h:t") -- fallback: parent of article/
    end

    local abs_dir_path = vim.fn.fnamemodify(filepath, ":h:p")
    local metadata_path = vim.fs.joinpath(abs_dir_path, "METADATA.pb")
    local ofl_txt_path = vim.fs.joinpath(abs_dir_path, "OFL.txt")

    -- local item = get_github_info_article_html(filepath)
    local item = get_github_info_from_upstream_info(filepath) or
        get_github_info_from_metadata(metadata_path) or
        get_github_info_from_ofl_txt(ofl_txt_path)

    -- if item == nil then
    --   error(string.format("github url not in %s\n%s\n%s", filepath, metadata_path, ofl_txt_path))
    -- end

    if item then
      count_ok = count_ok + 1
      item.dirname = dirname
      table.insert(github_pages, item)
    else
      count_err = count_err + 1
      if err == nil then
        err = "⚠️ 找不到對應的 https://github.com/...\n\n"
        io.stderr:write(err)
      end
      io.stderr:write(string.format("- %s\n", dirname or filepath))
    end
  end

  -- Sort for stable output
  table.sort(github_pages, function(a, b)
    return (a.dirname or "") < (b.dirname or "")
  end)

  for _, info in ipairs(github_pages) do
    io.write(string.format("- [%s %s/%s](%s)\n", info.dirname, info.username, info.repo_name, info.url))
  end
  io.write(string.format("\n成功數量:%d\n", count_ok))

  gen_summary_json(github_pages, count_ok, count_err)

  if err then
    io.stderr:write(string.format("\n失敗總數量:%d\n", count_err))
    -- 設定error code與stderr不是絕對的，不代表有stderr有，而error code就一定會有                                                                    │
    -- Non-zero exit when there are failures (useful for CI awareness)
    vim.cmd("cquit 1")
  end
end

main()
