{
  outputs = { ... }: {
    modules = ./.;
    hasTmpDir = true;
  };
}