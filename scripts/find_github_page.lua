-- nvim   -l find_github_page.lua 1>list.md 2>no_found.md

local script_file = debug.getinfo(1, "S").source:sub(2)
local script_dir = vim.fs.dirname(vim.fs.abspath(script_file))

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
  local r = vim.system({ "sh", "-c",
    string.format("fd %s %s %s", filename, opts.ext, opts.wkdir)
  }):wait()

  if r.code ~= 0 then
    error(r.code .. r.stderr)
  end
  return r.stdout:gmatch("[^\n]+")
end


---@class GithubInfo
---@field repo_name string
---@field username  string
---@field url       string
---@field dirname   string?

---@param filepath string
---@return GithubInfo?
local function get_github_info(filepath)
  assert(vim.fn.fnamemodify(filepath, ":t"), "ARTICLE.en_us.html")
  vim.cmd("edit " .. filepath)
  if vim.fn.search([[href=['"]https://github.com/.*['"]>]]) > 0 then -- 只抓一筆，抓錯就算了
    vim.fn.setreg([["]], "")
    vim.cmd([[normal! fhvi"y]])
    local url = vim.fn.getreg('"')
    if #url < 20 then
      -- 再抓一次，它可能是用單引號來包的
      vim.cmd("normal! gg")
      vim.fn.search([[href=['"]https://github.com/.*['"]>]])
      vim.fn.setreg([[']], "")
      vim.cmd([[normal! fhvi'y]])
      url = vim.fn.getreg('"')
    end
    if #url > 20 then
      local username, repo_name = url:match("^https?://github%.com/([^/]+)/([^/]+)")
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
  for filepath in search_files("ARTICLE.en_us.html", {
    ext = "-e html",
    wkdir = script_dir .. "/../ofl",
  }) do
    local dirname = vim.fs.normalize(filepath):match("/ofl/([^/]+)") -- /path/to/scripts/../ofl/ancizarserif/article/ARTICLE.en_us.html
    local item = get_github_info(filepath)
    if item then
      count_ok = count_ok + 1
      item.dirname = dirname
      table.insert(github_pages, item)
    else
      count_err = count_err + 1
      if err == nil then
        err = "⚠️ 找不到對應的http://github.com/...\n\n"
        io.stderr:write(err)
      end
      io.stderr:write(string.format("- %s\n", dirname))
    end
  end

  for _, info in ipairs(github_pages) do
    io.write(string.format('- [%s %s/%s](%s)\n', info.dirname, info.username, info.repo_name, info.url))
  end
  io.write(string.format("\n成功數量:%d\n", count_ok))

  if err then
    io.stderr:write(string.format("\n失敗總數量:%d\n", count_err))
    -- 設定error code. stderr與error code不是絕對的，不代表有stderr error code就一定會有
    vim.cmd.cquit(1)
  end
end

main()
