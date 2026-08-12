local current_file = debug.getinfo(1, "S").source:sub(2)
local tests_dir = vim.fs.dirname(vim.fs.abspath(current_file))
vim.opt.runtimepath:prepend(tests_dir)

vim.pack.add({ "https://github.com/CarsonSlovoka/testing.nvim" })

local t = require("testing").new()
t:test("test strip_outer", function()
  for _, s in ipairs({
    "(https://github.com/Gue3bara/Lemonada)",
    '"https://github.com/Gue3bara/Lemonada"',
    "'https://github.com/Gue3bara/Lemonada'",
  }) do
    t:eq(require("utils").strip_outer(s), "https://github.com/Gue3bara/Lemonada")
  end
end)

_ = t:finish() or vim.cmd.cquit(1)
