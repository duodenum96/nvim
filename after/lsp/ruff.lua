-- Config of 'ruff' language server (linting, code actions, formatting).
-- Source: https://docs.astral.sh/ruff/editors/setup/#neovim
--
-- Used together with 'ty', which is responsible for hover and type info.
return {
  on_attach = function(client, buf_id)
    -- Let 'ty' handle hover
    client.server_capabilities.hoverProvider = false
  end,
}
