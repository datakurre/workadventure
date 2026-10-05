# Try WorkAdventure without Docker:
#
#   devenv up
#
# then open http://play.workadventure.localhost:8000 (*.localhost resolves to
# the loopback address in browsers, no /etc/hosts entry needed).
#
# This runs the Nix-packaged build (./nix/package.nix, also exposed by flake.nix)
# against a local Redis, with Caddy standing in for the Traefik reverse proxy of
# docker-compose.yaml. It is meant for trying WorkAdventure out, not for
# development: use docker-compose (see docs/agent/dev-setup.md) to hack on it.
# Omitted compared to docker-compose: OIDC mock server, Synapse (chat), LiveKit,
# the icon server.
#
# Caddy and the Room API only listen on loopback, but the services' own ports
# (see `ports` below) can't be bound to it and stay reachable from the network.
{ pkgs, config, ... }:
let
  nodejs = pkgs.nodejs_24;
  workadventure = pkgs.callPackage ./nix/package.nix {
    inherit nodejs;
    workadventure-messages = pkgs.callPackage ./nix/messages.nix { inherit nodejs; };
  };

  port = 8000;
  domain = "workadventure.localhost";
  playUrl = "http://play.${domain}:${toString port}";
  mapStorageUrl = "http://map-storage.${domain}:${toString port}";
  mapsUrl = "http://maps.${domain}:${toString port}";
  uploaderUrl = "http://uploader.${domain}:${toString port}";

  # Local ports of the services behind Caddy
  ports = {
    pusher = 3010;
    pusherWs = 3011;
    roomApi = 50051;
    back = 8081;
    backGrpc = 50061;
    mapStorage = 3000;
    mapStorageGrpc = 50053;
    uploader = 8080;
  };

  secretKey = "yourSecretKey2020";
  mapStorageApiToken = "FFVSGBSGBSGFB23SFGBSFG4BS";
in
{
  env = {
    # The pusher serves the maps through the same host name as in docker-compose.
    WORKADVENTURE_URL = playUrl;
  };

  services.redis.enable = true;

  services.caddy = {
    enable = true;
    # Plain HTTP only, on an unprivileged port, reachable from this machine only
    config = ''
      {
        auto_https off
        http_port ${toString port}
        default_bind 127.0.0.1 [::1]
      }
    '';
    virtualHosts = {
      "http://play.${domain}:${toString port}".extraConfig = ''
        handle /ws/* {
          reverse_proxy 127.0.0.1:${toString ports.pusherWs}
        }
        handle {
          reverse_proxy 127.0.0.1:${toString ports.pusher}
        }
      '';
      "http://map-storage.${domain}:${toString port}".extraConfig = ''
        reverse_proxy 127.0.0.1:${toString ports.mapStorage}
      '';
      "http://uploader.${domain}:${toString port}".extraConfig = ''
        reverse_proxy 127.0.0.1:${toString ports.uploader}
      '';
      "http://room-api.${domain}:${toString port}".extraConfig = ''
        reverse_proxy h2c://127.0.0.1:${toString ports.roomApi}
      '';
      "http://maps.${domain}:${toString port}".extraConfig = ''
        root * ${config.devenv.root}/maps
        header Access-Control-Allow-Origin *
        file_server
      '';
    };
  };

  # back must be up before the pusher and map-storage connect to it.
  processes = {
    back = {
      exec = "${workadventure}/bin/workadventure-back";
      after = [ "devenv:processes:redis" ];
      ready.http.get = {
        port = ports.back;
        path = "/ping";
      };
    };
    play = {
      exec = "${workadventure}/bin/workadventure-play";
      after = [ "devenv:processes:back" ];
    };
    map-storage = {
      exec = ''
        mkdir -p "$STORAGE_DIRECTORY"
        exec ${workadventure}/bin/workadventure-map-storage
      '';
      after = [ "devenv:processes:back" ];
    };
    uploader = {
      exec = "${workadventure}/bin/workadventure-uploader";
      after = [ "devenv:processes:redis" ];
    };
  };

  processes.back.env = {
    HTTP_PORT = toString ports.back;
    GRPC_PORT = toString ports.backGrpc;
    PLAY_URL = playUrl;
    SECRET_KEY = secretKey;
    REDIS_HOST = "127.0.0.1";
    MAP_STORAGE_URL = "127.0.0.1:${toString ports.mapStorageGrpc}";
    PUBLIC_MAP_STORAGE_URL = mapStorageUrl;
    INTERNAL_MAP_STORAGE_URL = "http://127.0.0.1:${toString ports.mapStorage}";
    ENABLE_MAP_EDITOR = "true";
    STORE_VARIABLES_FOR_LOCAL_MAPS = "true";
  };

  processes.play.env = {
    PUSHER_HTTP_PORT = toString ports.pusher;
    PUSHER_WS_PORT = toString ports.pusherWs;
    ROOM_API_PORT = toString ports.roomApi;
    ROOM_API_SECRET_KEY = "dev-room-api-secret-key";
    ROOM_API_BIND_HOST = "127.0.0.1";
    API_URL = "127.0.0.1:${toString ports.backGrpc}";
    SECRET_KEY = secretKey;
    REDIS_HOST = "127.0.0.1";
    ALLOWED_CORS_ORIGIN = playUrl;
    PUSHER_URL = playUrl;
    FRONT_URL = playUrl;
    UPLOADER_URL = uploaderUrl;
    ICON_URL = "${playUrl}/icon";
    PUBLIC_MAP_STORAGE_URL = mapStorageUrl;
    INTERNAL_MAP_STORAGE_URL = "http://127.0.0.1:${toString ports.mapStorage}";
    MAP_STORAGE_API_TOKEN = mapStorageApiToken;
    START_ROOM_URL = "/_/global/maps.${domain}:${toString port}/starter/map.json";
    ENABLE_MAP_EDITOR = "true";
    MAP_EDITOR_ALLOW_ALL_USERS = "true";
    ENABLE_CHAT = "false";
    DISABLE_NOTIFICATIONS = "true";
    STUN_SERVER = "stun:stun.l.google.com:19302";
  };

  processes.map-storage.env = {
    STORAGE_DIRECTORY = "${config.devenv.state}/map-storage";
    API_URL = "127.0.0.1:${toString ports.backGrpc}";
    PUSHER_URL = playUrl;
    MAP_STORAGE_API_TOKEN = mapStorageApiToken;
    SECRET_KEY = secretKey;
    ENABLE_BASIC_AUTHENTICATION = "true";
    AUTHENTICATION_USER = "john.doe";
    AUTHENTICATION_PASSWORD = "password";
    ENABLE_BEARER_AUTHENTICATION = "true";
    AUTHENTICATION_TOKEN = "123";
    WHITELISTED_RESOURCE_URLS = "";
  };

  processes.uploader.env = {
    UPLOADER_URL = uploaderUrl;
    REDIS_HOST = "127.0.0.1";
  };
}
