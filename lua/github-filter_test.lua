vim.pack.add({ "https://github.com/CarsonSlovoka/testing.nvim" })

local t = require("testing").new()
local M = require("github-filter")


----------------------------------------------------------------
-- parse_condition
----------------------------------------------------------------
t:test("parse glued numeric", function()
  local c, err = M.parse_condition("stars>150")
  t:eq(err, nil)
  assert(c)
  t:eq(c.field, "stars")
  t:eq(c.op, ">")
  t:eq(c.value, "150")
end)

t:test("parse spaced numeric", function()
  local c = M.parse_condition("stars >= 100")
  assert(c)
  t:eq(c.op, ">=")
  t:eq(c.value, "100")
end)

t:test("parse date", function()
  local c = M.parse_condition("updated_at>=2026-08-01")
  assert(c)
  t:eq(c.field, "updated_at")
  t:eq(c.op, ">=")
  t:eq(c.value, "2026-08-01")
end)

t:test("parse string equality", function()
  local c = M.parse_condition("language==Python")
  assert(c)
  t:eq(c.op, "==")
  t:eq(c.value, "Python")
end)

t:test("parse empty / nonempty", function()
  local c1 = M.parse_condition("workflows empty")
  assert(c1)
  t:eq(c1.op, "empty")
  local c2 = M.parse_condition("workflows nonempty")
  assert(c2)
  t:eq(c2.op, "nonempty")
end)

t:test("parse length", function()
  local c = M.parse_condition("workflows length>0")
  assert(c)
  t:eq(c.op, "length")
  t:eq(c.length_op, ">")
  t:eq(c.value, 0)

  local c2 = M.parse_condition("issue_templates length >= 2")
  assert(c2)
  t:eq(c2.length_op, ">=")
  t:eq(c2.value, 2)
end)

t:test("parse invalid", function()
  local c, err = M.parse_condition("foobar")
  t:eq(c, nil)
  t:eq(type(err), "string")
  assert(err)
  t:eq(err:find("invalid") ~= nil, true)
end)

----------------------------------------------------------------
-- match & filter with fixture
----------------------------------------------------------------
local fixture = {
  generated_at = "2026-08-13T00:00:00Z",
  items = {
    {
      username = "42dot",
      repo_name = "42dot-Sans",
      stars = 56,
      language = "Makefile",
      updated_at = "2026-08-01T23:47:38Z",
      workflows = { { name = "build.yaml" } },
      issue_templates = {},
    },
    {
      username = "googlefonts",
      repo_name = "abel",
      stars = 200,
      language = "Python",
      updated_at = "2026-08-10T21:07:46Z",
      workflows = { { name = "build.yaml" } },
      issue_templates = { { name = "bug.md" } },
    },
    {
      username = "googlefonts",
      repo_name = "abeezee",
      stars = 14,
      language = "",
      updated_at = "2026-04-24T17:35:54Z",
      workflows = {},
      issue_templates = {},
    },
    {
      username = "test",
      repo_name = "big",
      stars = 300,
      language = "Lua",
      updated_at = "2026-08-12T10:00:00Z",
      workflows = { { name = "ci.yml" }, { name = "release.yml" } },
      issue_templates = {},
    },
  },
}

t:test("filter stars>150", function()
  local res, err = M.filter(fixture, { "stars>150" })
  t:eq(err, nil)
  t:eq(#res, 2)
  assert(res)
  t:eq(res[1].repo_name, "abel")
  t:eq(res[2].repo_name, "big")
end)

t:test("filter workflows nonempty AND stars>=200", function()
  local res = M.filter(fixture, { "workflows nonempty", "stars>=200" })
  t:eq(#res, 2)
end)

t:test("filter updated_at date", function()
  local res = M.filter(fixture, { "updated_at>=2026-08-10" })
  t:eq(#res, 2) -- abel + big
end)

t:test("filter length", function()
  local res = M.filter(fixture, { "workflows length>1" })
  assert(res)
  t:eq(#res, 1)
  t:eq(res[1].repo_name, "big")
end)

t:test("filter empty workflows", function()
  local res = M.filter(fixture, { "workflows empty" })
  assert(res)
  t:eq(#res, 1)
  t:eq(res[1].repo_name, "abeezee")
end)

t:test("filter language==Python", function()
  local res = M.filter(fixture, { "language==Python" })
  assert(res)
  t:eq(#res, 1)
  t:eq(res[1].repo_name, "abel")
end)

t:test("AND combination", function()
  local res = M.filter(fixture, {
    "stars>100",
    "workflows nonempty",
    "updated_at>=2026-08-01",
  })
  t:eq(#res, 2)
end)

t:test("no match returns empty list", function()
  local res = M.filter(fixture, { "stars>9999" })
  t:eq(#res, 0)
end)

t:test("invalid data", function()
  local res, err = M.filter({}, { "stars>1" })
  assert(err)
  t:eq(res, nil)
  t:eq(type(err), "string")
  t:eq(err:find("items") ~= nil, true)
end)

t:test("soft missing field", function()
  local res = M.filter(fixture, { "nonexistent>1" })
  t:eq(#res, 0) -- never errors, just no match
end)

_ = t:finish() or vim.cmd.cquit(1)
