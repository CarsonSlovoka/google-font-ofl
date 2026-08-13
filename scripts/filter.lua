local script_file = debug.getinfo(1, "S").source:sub(2)
local script_dir = vim.fn.fnamemodify(script_file, ":p:h")
local git_root = vim.fn.fnamemodify(script_dir, ":h:p")
vim.opt.runtimepath:prepend(git_root)

local site_data_json_path = vim.fs.joinpath(git_root, "/site/data.json")

local filter = require("github-filter")

local filtered = filter.filter_file(site_data_json_path, 7, 150)

-- 快速查看結果
for _, item in ipairs(filtered) do
  print(string.format("%s/%s  ★%d  %s", item.username, item.repo_name, item.stars, item.updated_at))
end

local out = vim.json.encode({ items = filtered }, { indent = "  " })
vim.fn.writefile(vim.split(out, "\n"), "filtered_repos.json")
