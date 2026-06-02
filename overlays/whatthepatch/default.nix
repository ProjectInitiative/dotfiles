{ channels, ... }: final: prev: {
  python3Packages = prev.python3Packages.override {
    overrides = pyfinal: pyprev: {
      whatthepatch = channels.upstream.python3Packages.whatthepatch;
    };
  };
  python312Packages = prev.python312Packages.override {
    overrides = pyfinal: pyprev: {
      whatthepatch = channels.upstream.python312Packages.whatthepatch;
    };
  };
}
