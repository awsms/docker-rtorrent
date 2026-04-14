# docker-rtorrent

This fork strips `crazy-max/docker-rtorrent-rutorrent` down to `rtorrent`
only. It keeps the useful bootstrap logic, non-root runtime, and the
`rtorrent` tuning knobs, while removing `ruTorrent`, PHP, nginx, WebDAV, and
the related runtime baggage.

## Versioning

The build is designed so an image tag maps cleanly to an upstream release.

For example, building `docker-rtorrent:0.16.7` uses:

* git tag `v0.16.7` from `rakshasa/libtorrent`
* git tag `v0.16.7` from `rakshasa/rtorrent`

By default, both `LIBTORRENT_VERSION` and `RTORRENT_VERSION` are `0.16.7`.
You can override them independently, but most of the time they should match.

## Features

* Runs as a non-root user
* Builds `libtorrent` and `rtorrent` from upstream git tags
* Uses plain Alpine for the runtime image
* Keeps the tuned bootstrap config in [rootfs/tpls/.rtorrent.rc](/home/ash/Appz/forks/docker-rtorrent/rootfs/tpls/.rtorrent.rc) and [rootfs/tpls/etc/rtorrent/.rtlocal.rc](/home/ash/Appz/forks/docker-rtorrent/rootfs/tpls/etc/rtorrent/.rtlocal.rc)
* Keeps the runtime knobs for logging, session persistence, tracker scrape delay, socket buffers, and preallocation
* Keeps the DHT and incoming peer port configuration driven by environment variables

## Build

```sh
podman build -t docker-rtorrent:0.16.7 \
  --build-arg LIBTORRENT_VERSION=0.16.7 \
  --build-arg RTORRENT_VERSION=0.16.7 .
```

Or with Docker:

```sh
docker build \
  --build-arg LIBTORRENT_VERSION=0.16.7 \
  --build-arg RTORRENT_VERSION=0.16.7 \
  -t docker-rtorrent:0.16.7 .
```

## Environment Variables

### General

* `TZ`: The timezone assigned to the container. Default `UTC`
* `PUID`: rTorrent user id. Default `1000`
* `PGID`: rTorrent group id. Default `1000`
* `WAN_IP`: Public IP address announced to trackers. Empty by default
* `WAN_IP_CMD`: Command used to resolve `WAN_IP` when it is unset. Set to `false` or leave empty to disable it
* `RT_BASEDIR`: Base directory for rTorrent state and `.rtorrent.rc`. Default `/data/rtorrent`
* `RT_DOWNLOAD_DIR`: Download root. Default `/downloads`
* `RT_DOWNLOAD_COMPLETE_DIR`: Completed downloads directory. Default `${RT_DOWNLOAD_DIR}/complete`
* `RT_DOWNLOAD_TEMP_DIR`: In-progress downloads directory. Default `${RT_DOWNLOAD_DIR}/temp`
* `RT_LOG_DIR`: Log directory. Default `${RT_BASEDIR}/log`
* `RT_SESSION_DIR`: Session directory. Default `${RT_BASEDIR}/.session`
* `RT_WATCH_DIR`: Watch directory. Default `${RT_BASEDIR}/watch`
* `RT_RUNTIME_DIR`: Runtime directory for PID and SCGI socket. Default `/var/run/rtorrent`

### rTorrent

* `RT_LOG_LEVEL`: rTorrent log level. Default `info`
* `RT_LOG_EXECUTE`: Log executed commands to `/data/rtorrent/log/execute.log`. Default `false`
* `RT_LOG_XMLRPC`: Log XMLRPC queries to `/data/rtorrent/log/xmlrpc.log`. Default `false`
* `RT_SESSION_SAVE_SECONDS`: Seconds between writing torrent information to disk. Default `3600`
* `RT_SESSION_FDATASYNC`: Force fdatasync when saving sessions via `system.files.session.fdatasync.set`. Default `false`
* `RT_TRACKER_DELAY_SCRAPE`: Delay tracker announces at startup. Default `true`
* `RT_DHT_PORT`: DHT UDP port via `dht.override_port.set`. Default `6881`
* `RT_INC_PORT`: Incoming connections via `network.port_range.set`. Default `50000`
* `RT_SEND_BUFFER_SIZE`: Default TCP send buffer via `network.send_buffer.size.set`. Default `4M`
* `RT_RECEIVE_BUFFER_SIZE`: Default TCP receive buffer via `network.receive_buffer.size.set`. Default `4M`
* `RT_PREALLOCATE_TYPE`: Disk space preallocation mode via `system.file.allocate.set`. Default `0`

## Volumes

* `/data`: default location for `rtorrent` config, session files, and logs
* `/downloads`: default payload location

The container expects the configured `RT_*DIR` paths to be writable by `PUID:PGID`.

## Ports

* `6881/udp` or `RT_DHT_PORT`: DHT
* `50000/tcp` or `RT_INC_PORT`: incoming BitTorrent traffic

## Usage

Use the example in [examples/compose](/home/ash/Appz/forks/docker-rtorrent/examples/compose):

```sh
mkdir -p data downloads
chown ${PUID}:${PGID} data downloads
podman-compose up -d
podman-compose logs -f
```

The example compose builds and tags the image as:

```sh
docker-rtorrent:${RTORRENT_VERSION:-0.16.7}
```

Minimal `docker run`:

```sh
mkdir -p data downloads
chown ${PUID}:${PGID} data downloads
docker run -d --name rtorrent \
  --ulimit nproc=65535 \
  --ulimit nofile=32000:40000 \
  -p 6881:6881/udp \
  -p 50000:50000 \
  -v "$(pwd)/data:/data" \
  -v "$(pwd)/downloads:/downloads" \
  docker-rtorrent:0.16.7
```

## Notes

This image now uses plain Alpine rather than `crazymax/alpine-s6`. That is
intentional: once `ruTorrent`, PHP, and nginx were removed, the s6 supervision
stack no longer bought us much. A single entrypoint is enough for one service,
and the runtime is easier to inspect and debug.

When `rtorrent` starts, it imports [.rtlocal.rc](/home/ash/Appz/forks/docker-rtorrent/rootfs/tpls/etc/rtorrent/.rtlocal.rc), which defines:

* `/data/rtorrent` as the base directory
* `/downloads/temp` and `/downloads/complete` as payload directories
* `/data/rtorrent/.session` and `/data/rtorrent/log` as state directories
* a local SCGI socket at `/var/run/rtorrent/scgi.socket`
* the logging and performance-related settings controlled by the `RT_*` environment variables

If `/data/rtorrent/.rtorrent.rc` does not exist, the container seeds it from
[.rtorrent.rc](/home/ash/Appz/forks/docker-rtorrent/rootfs/tpls/.rtorrent.rc).

`WAN_IP` is optional. If you need to force the announced public IP, set it
directly or provide a `WAN_IP_CMD` such as:

* `dig +short myip.opendns.com @resolver1.opendns.com`
* `curl -s ifconfig.me`
* `curl -s ident.me`

Set `WAN_IP_CMD=false` or leave it empty if you do not want the container to
attempt public IP discovery at startup.

If you seed a large session, increase the container stop timeout so `rtorrent`
has time to shut down cleanly and clear its lock file.

If your existing torrents already use absolute `/data/...` paths, set
`RT_DOWNLOAD_DIR=/data` and move the state elsewhere with `RT_BASEDIR`, such as
`RT_BASEDIR=/config/rtorrent1`.

`RT_SESSION_SAVE_SECONDS` defaults to 3600 to reduce disk churn compared to
much more aggressive session flush intervals.

`RT_TRACKER_DELAY_SCRAPE=true` helps large sessions start more reliably.

`RT_SEND_BUFFER_SIZE` and `RT_RECEIVE_BUFFER_SIZE` can be tuned for faster
links, but the defaults are a reasonable middle ground.

`RT_PREALLOCATE_TYPE` accepts:

* `0`: disabled
* `1`: allocate when a file is opened for write
* `2`: allocate the whole torrent up front

## License

MIT. See `LICENSE`.
