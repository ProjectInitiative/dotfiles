local o = vim.o -- For the globals options
local w = vim.wo -- For the window local options
local b = vim.bo -- For the buffer local options    



-- spaces and tabs

b.autoindent = true
b.expandtab = true
b.softtabstop = 4
b.shiftwidth = 4
b.tabstop = 4
b.smartindent = true
b.modeline = false

o.hidden = true

w.number = true
w.relativenumber = false


-- key mappings
vim.api.nvim_set_keymap(
    "t",
    "<Esc>",
    "<C-\\><C-n>",
    { noremap = true }
)

