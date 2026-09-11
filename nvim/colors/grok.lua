-- GrokDay (light) / GrokNight (dark). vim.o.background picks the palette;
-- Ghostty mode 2031 flips that option, so no poller.
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.g.colors_name = "grok"
vim.o.termguicolors = true
require("grok").apply()
