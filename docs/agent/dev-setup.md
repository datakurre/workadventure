# Development Setup

## Initial setup
```bash
cp .env.template .env
npm install
npm run prepare
docker-compose up
```

## Nix

Alternative to Docker for trying WorkAdventure out (see `flake.nix`, `nix/`, `devenv.nix`):

```bash
nix build                # packages play, back, map-storage and uploader
nix run .#back           # run a single service (also: play, map-storage, uploader)
devenv up                # Redis + all services + Caddy, then open http://play.workadventure.localhost:8000
```

After changing `package-lock.json` (or `messages/package-lock.json`), update `npmDepsHash` in `nix/package.nix` (or `nix/messages.nix`): set it to `lib.fakeHash`, build, and copy the hash from the error.

`flake.lock` and `devenv.lock` pin nixpkgs separately: update them together (`nix flake update && devenv update`) so that `nix build` and `devenv up` build the same package.
