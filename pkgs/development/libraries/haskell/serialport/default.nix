# This file was auto-generated by cabal2nix. Please do NOT edit manually!

{ cabal, HUnit }:

cabal.mkDerivation (self: {
  pname = "serialport";
  version = "0.4.7";
  sha256 = "1z2drw7ighyws72wqms015n5hy0zxbrphdca7ldn34pz28122z07";
  testDepends = [ HUnit ];
  doCheck = false;
  meta = {
    homepage = "https://github.com/jputcu/serialport";
    description = "Cross platform serial port library";
    license = self.stdenv.lib.licenses.bsd3;
    platforms = self.ghc.meta.platforms;
  };
})
