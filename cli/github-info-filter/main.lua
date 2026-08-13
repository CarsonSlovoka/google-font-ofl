#!/usr/bin/env -S nvim -u NONE --headless -l

--- nvim -l main.lua ../../site/data.json "pushed_at>=2026-08-01T00:00:00+08:00" "stars>=1000"
--- nvim -l main.lua "$(git rev-parse --show-toplevel)/site/data.json" "pushed_at>=2026-08-01T00:00:00+08:00" "stars>=1000" | jq .

local script_file = debug.getinfo(1, "S").source:sub(2)
local script_dir = vim.fn.fnamemodify(script_file, ":p:h")
local git_root = vim.fn.fnamemodify(script_dir, ":h:h:p")
vim.opt.runtimepath:prepend(git_root)

local gf = require("github-filter")

local function print_help()
  io.stdout:write([[
Usage:
  nvim -l filter.lua <json-file> [condition...]
  nvim -l filter.lua --help

Conditions (AND logic). Examples:
  stars>150
  stars>=100
  pushed_at>=2026-08-01
  pushed_at>=2026-08-01T00:00:00Z
  pushed_at>=2026-08-01T00:00:00Z
  language==Python
  language!=
  workflows nonempty
  workflows empty
  workflows length>0
  issue_templates length>=1

Output: JSON array of matching items on stdout.
Errors go to stderr; exit code 1 on failure.

datetime format: ISO 8601
]])
end

local function main(args)
  if #args == 0 or args[1] == "--help" or args[1] == "-h" then
    print_help()
    return 0
  end

  local path = args[1]
  local conditions = {}
  for i = 2, #args do
    conditions[#conditions + 1] = args[i]
  end

  local result, err = gf.filter_file(path, conditions)
  if not result then
    io.stderr:write("error: " .. err .. "\n")
    return 1
  end

  -- pretty-print JSON array
  local encoded = vim.json.encode(result)
  -- simple pretty (neovim json.encode is compact; we keep it compact for speed)
  io.stdout:write(encoded)
  io.stdout:write("\n")
  return 0
end

main(_G.arg)
