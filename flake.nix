{
  description = "My Neovim config";

  outputs =
    { self, ... }:
    {
      neovimConfig = self;
    };
}
