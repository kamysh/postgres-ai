{ pkgs, postgresql }:

let
  # PostgreSQL configuration files as a separate derivation (changes less frequently)
  postgresConfigs = pkgs.runCommand "postgres-configs" {} ''
    mkdir -p $out/etc/postgresql
    cp ${./pg_hba.conf} $out/etc/postgresql/pg_hba.conf
    cp ${./pg_ident.conf} $out/etc/postgresql/pg_ident.conf
    cp ${./postgresql.conf} $out/etc/postgresql/postgresql.conf
  '';

  # Init scripts as a separate derivation (may change frequently during development)
  initScripts = pkgs.runCommand "postgres-init" {} ''
    mkdir -p $out/var/lib/postgresql/initdb.d
    cp ${./init.sql} $out/var/lib/postgresql/initdb.d/init.sql
  '';

  # Entrypoint script as a separate derivation (rarely changes)
  entrypoint = pkgs.runCommand "postgres-entrypoint" {} ''
    mkdir -p $out/usr/local/bin
    substitute ${./docker-entrypoint.sh} $out/usr/local/bin/docker-entrypoint.sh \
      --replace '@POSTGRESQL_BIN@' '${postgresql}/bin'
    chmod 755 $out/usr/local/bin/docker-entrypoint.sh
  '';
in

pkgs.dockerTools.buildLayeredImage {
  name = "postgres-ai";
  tag = "latest";

  contents = [
    postgresql
    pkgs.bash
    pkgs.coreutils
    pkgs.shadow
    postgresConfigs
    initScripts
    entrypoint
  ];

  enableFakechroot = true;

  fakeRootCommands = ''
    ${pkgs.dockerTools.shadowSetup}
    groupadd -r postgres --gid=999
    useradd -r -g postgres --uid=999 --home-dir=/var/lib/postgresql postgres
    mkdir -p /var/lib/postgresql/data /run/postgresql
    chown -R postgres:postgres /var/lib/postgresql /etc/postgresql /run/postgresql /usr/local/bin/docker-entrypoint.sh
    chmod 600 /etc/postgresql/pg_hba.conf /etc/postgresql/pg_ident.conf /etc/postgresql/postgresql.conf
  '';

  config = {
    User = "postgres";
    WorkingDir = "/var/lib/postgresql";
    Cmd = [ "/usr/local/bin/docker-entrypoint.sh" ];
    Env = [
      "PATH=${postgresql}/bin:/bin"
      "PGDATA=/var/lib/postgresql/data"
    ];
    ExposedPorts = {
      "5432/tcp" = {};
    };
  };
}
