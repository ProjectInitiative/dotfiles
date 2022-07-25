require("nvim-lsp-installer").setup {
  automatic_installation = true
}

local lspconfig = require("lspconfig")

lspconfig.ansiblels.setup{}
lspconfig.bashls.setup{}
lspconfig.dockerls.setup{}
lspconfig.pylsp.setup{}
lspconfig.rust_analyzer.setup{}
