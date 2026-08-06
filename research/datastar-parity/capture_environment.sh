#!/bin/sh
set -eu

GO_BIN=${GO_BIN:-go}

printf 'captured_utc: '
date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'git_commit: '
git rev-parse HEAD
printf 'go: '
"$GO_BIN" version
printf 'kernel: '
uname -srvmo
printf 'architecture: '
uname -m
printf 'cpu_count: '
getconf _NPROCESSORS_ONLN
printf 'page_size: '
getconf PAGESIZE
printf 'memory_kib: '
awk '/^MemTotal:/ { print $2 }' /proc/meminfo
printf 'file_descriptor_soft_limit: '
ulimit -Sn
printf 'file_descriptor_hard_limit: '
ulimit -Hn
printf 'cpu_model: '
awk -F ': ' '/^model name/ { print $2; exit }' /proc/cpuinfo
printf 'go_env: '
"$GO_BIN" env GOOS GOARCH GOAMD64 GOMAXPROCS
