# WorkAdventure monorepo build: the play (front + pusher + Room API), back,
# map-storage and uploader services share one npm workspace and one lockfile.
#
# The services run straight from their TypeScript sources through tsx (as in
# their Docker images), so the output keeps the whole workspace, its
# node_modules and the built front-end bundles under $out/share/workadventure.
{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs,
  git,
  workadventure-messages,
}:
let
  # A flake source is already limited to git-tracked files, but devenv imports
  # straight from the working tree: filter it the same way, so that local
  # node_modules, .devenv state, .env files, etc. stay out of the build.
  tracked = if builtins.pathExists ../.git then lib.fileset.gitTracked ../. else ../.;
in
buildNpmPackage {
  pname = "workadventure";
  version = "0-unstable";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      (lib.fileset.difference tracked (
        lib.fileset.unions [
          (lib.fileset.maybeMissing ../.github)
          (lib.fileset.maybeMissing ../.claude)
          (lib.fileset.maybeMissing ../.codex)
          (lib.fileset.maybeMissing ../docs)
          (lib.fileset.maybeMissing ../maps)
          (lib.fileset.maybeMissing ../desktop)
          (lib.fileset.maybeMissing ../synapse)
          (lib.fileset.maybeMissing ../cd)
          (lib.fileset.maybeMissing ../flake.nix)
          (lib.fileset.maybeMissing ../flake.lock)
          (lib.fileset.maybeMissing ../nix)
          (lib.fileset.maybeMissing ../devenv.nix)
          (lib.fileset.maybeMissing ../devenv.yaml)
          (lib.fileset.maybeMissing ../devenv.lock)
          (lib.fileset.maybeMissing ../messages)
          (lib.fileset.maybeMissing ../tests/tests)
        ]
      ))
      # Part of the API version hash, see buildPhase
      ../messages/protos/messages.proto
    ];
  };

  inherit nodejs;
  npmDepsHash = "sha256-6j/s9R19FetccAOt3JT4sxC3BvurUDS8N95Qz20gWJU=";
  # Skip install scripts (sentry-cli, playwright, node-datachannel... download binaries);
  # the phaser patch is applied explicitly below.
  npmFlags = [
    "--ignore-scripts"
  ];
  makeCacheWritable = true;
  nativeBuildInputs = [
    makeWrapper
    git
  ];

  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild

    export NODE_ENV=production
    # patch-package: fixes phaser's TilemapGPULayer rendering
    node node_modules/patch-package/index.js

    # Protobuf TypeScript, and the API version hash that pusher and back check
    cp -r ${workadventure-messages}/. libs/messages/src/ts-proto-generated/
    chmod -R u+w libs/messages/src/ts-proto-generated
    # (same command and relative paths as messages' tag-version script, so the hash matches the Docker images)
    apiVersionHash=$(cd messages && sha1sum protos/messages.proto ../libs/messages/src/JsonMessages/* | sha1sum | cut -c1-8)
    sed -i "s/apiVersionHash = \".*\"/apiVersionHash = \"$apiVersionHash\"/" \
      libs/messages/src/JsonMessages/ApiVersion.ts

    (cd play && npm run typesafe-i18n && npm run build-iframe-api && npm run build)
    (cd map-storage && npm run front:build)

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    root=$out/share/workadventure
    mkdir -p $root $out/bin
    cp -r . $root
    # Drop workspaces that no service needs at runtime
    rm -rf $root/benchmark $root/tests $root/contrib $root/messages

    wrap() {
      makeWrapper $root/node_modules/.bin/tsx $out/bin/workadventure-$1 \
        --chdir $root/$2 \
        --prefix PATH : ${lib.makeBinPath [ nodejs ]} \
        --set-default NODE_ENV production \
        ''${@:4} \
        --add-flags "$3"
    }
    wrap play play ./src/server.ts --set TSX_TSCONFIG_PATH tsconfig-pusher.json
    wrap back back ./src/server.ts
    wrap map-storage map-storage ./src/index.ts --set ESBK_TSCONFIG_PATH tsconfig-node.json
    wrap uploader uploader ./server.ts

    runHook postInstall
  '';

  # tsx and the services resolve symlinked workspaces relative to $root
  dontFixup = true;

  meta = {
    description = "Collaborative virtual worlds (play, back, map-storage and uploader services)";
    homepage = "https://github.com/workadventure/workadventure";
    mainProgram = "workadventure-play";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
