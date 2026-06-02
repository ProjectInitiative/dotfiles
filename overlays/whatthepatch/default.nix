{ ... }: final: prev: {
  whatthepatch = prev.whatthepatch.overrideAttrs (o: {
    doCheck = false;
  });
}
