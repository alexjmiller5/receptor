{ lib, stdenvNoCC, fetchurl, unzip }:

stdenvNoCC.mkDerivation rec {
  pname = "receptor";
  version = "2.0.5";

  src = fetchurl {
    url = "https://github.com/alexjmiller5/receptor/releases/download/v${version}/Receptor-v${version}.zip";
    hash = "sha256-rYTAB1Kp3fIxDN9/8UKS7DXBnyDsTrzO4qqqWthxAS8=";
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
