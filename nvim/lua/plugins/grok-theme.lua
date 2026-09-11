-- Ghostty announces macOS light/dark through mode 2031; Neovim flips
-- vim.o.background and this reapplies GrokDay / GrokNight. No poller.
vim.api.nvim_create_autocmd("OptionSet", {
  group = vim.api.nvim_create_augroup("grok-theme", { clear = true }),
  pattern = "background",
  callback = function()
    if vim.g.colors_name == "grok" then
      vim.cmd.colorscheme("grok")
    end
  end,
})

return {
  { "catppuccin/nvim", enabled = false },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "grok" },
  },
}
