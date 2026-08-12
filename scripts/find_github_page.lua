-- nvim   -l find_github_page.lua 1>list.md 2>no_found.md

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

  local cmd = string.format("%s %s %s %s", fd_bin, filename, opts.ext, vim.fn.shellescape(opts.wkdir))
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

---@param filepath string
---@return GithubInfo?
local function get_github_info(filepath)
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

local function main()
  ---@type GithubInfo[]
  local github_pages = {}

  local count_ok = 0
  local count_err = 0
  local err = nil
  local ofl_dir = script_dir .. "/../ofl"

  for filepath in search_files("ARTICLE.en_us.html", {
    ext = "-e html",
    wkdir = ofl_dir,
  }) do
    local normalized = (vim.fs and vim.fs.normalize and vim.fs.normalize(filepath)) or filepath
    local dirname = normalized:match("/ofl/([^/]+)")
    if not dirname then
      dirname = vim.fn.fnamemodify(filepath, ":h:h:t") -- fallback: parent of article/
    end

    local item = get_github_info(filepath)
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

  if err then
    io.stderr:write(string.format("\n失敗總數量:%d\n", count_err))
    -- 設定error code. stderr與error code不是絕對的，不代表有stderr error code就一定會有
    -- Non-zero exit when there are failures (useful for CI awareness)
    vim.cmd("cquit 1")
  end
end

main()
