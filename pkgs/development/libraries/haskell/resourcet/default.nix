# This file was auto-generated by cabal2nix. Please do NOT edit manually!

{ cabal, exceptions, hspec, liftedBase, mmorph, monadControl, mtl
, transformers, transformersBase
}:

cabal.mkDerivation (self: {
  pname = "resourcet";
  version = "1.1.3.1";
  sha256 = "13g8vj9hc59q8n696j0w79k5bhp3mgs923y4d2cffnd0p7yd8r8x";
  buildDepends = [
    exceptions liftedBase mmorph monadControl mtl transformers
    transformersBase
  ];
  testDepends = [ hspec liftedBase transformers ];
  meta = {
    homepage = "http://github.com/snoyberg/conduit";
    description = "Deterministic allocation and freeing of scarce resources";
    license = self.stdenv.lib.licenses.bsd3;
    platforms = self.ghc.meta.platforms;
  };
})
