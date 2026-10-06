{ lib, stdenvNoCC, fetchurl, unzip }:

stdenvNoCC.mkDerivation rec {
  pname = "receptor";
  version = "2.0.3";

  src = fetchurl {
    url = "https://github.com/alexjmiller5/receptor/releases/download/v${version}/Receptor-v${version}.zip";
    hash = "sha256-ryQS9Xp/FN6IZIfWcqsPr2l7GG78jzhQRLaLDAdG2vU=";
  };

  nativeBuildInputs = [ unzip ];
  dontUnpack = true;
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    unzip -q "$src" -d "$out/Applications"
    runHook postInstall
  '';

  meta = {
    description = "Offline-first thought capture for macOS";
    homepage = "https://github.com/alexjmiller5/receptor";
    platforms = lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
