# TypeScript sources generated from messages/protos (ts-proto).
# messages/ has its own package-lock.json, so it is built separately from the
# main workspace. The generated files are consumed by ./package.nix.
{
  lib,
  buildNpmPackage,
  nodejs,
  protobuf,
}:
buildNpmPackage {
  pname = "workadventure-messages";
  version = "0-unstable";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../messages/package.json
      ../messages/package-lock.json
      ../messages/protos
    ];
  };
  sourceRoot = "source/messages";

  inherit nodejs;
  npmDepsHash = "sha256-/uZFVeCTDITFdCwn2WpfmaNvNkBBnEvRR9Sx+7tcq4I=";
  # grpc-tools downloads a protoc binary in its install script: use nixpkgs' protoc instead.
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;
  nativeBuildInputs = [ protobuf ];

  buildPhase = ''
    runHook preBuild
    mkdir -p generated
    protoc \
      --plugin=protoc-gen-ts_proto=./node_modules/.bin/protoc-gen-ts_proto \
      --ts_proto_out=generated \
      --ts_proto_opt=outputServices=grpc-js \
      --ts_proto_opt=oneof=unions \
      --ts_proto_opt=esModuleInterop=true \
      -I ./protos protos/*.proto
    sed -i '1i\//@ts-nocheck' generated/*.ts
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r generated/. $out/
    runHook postInstall
  '';

  dontFixup = true;
}
