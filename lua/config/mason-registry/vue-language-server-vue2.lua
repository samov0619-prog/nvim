-- Update server and plugin together, only after testing a new 3.0.x release.
local version = "3.0.11"

return {
  schema = "registry+v1",
  name = "vue-language-server-vue2",
  description = "Official Vue language tools, legacy Vue 2 / class-component branch (3.0.x).",
  homepage = "https://github.com/vuejs/language-tools",
  licenses = { "MIT" },
  languages = { "Vue" },
  categories = { "LSP" },
  source = {
    id = "pkg:npm/%40vue/language-server@" .. version,
    extra_packages = { "@vue/typescript-plugin@" .. version, "typescript@6.0.3" },
  },
  bin = { ["vue-language-server-vue2"] = "npm:vue-language-server" },
}
