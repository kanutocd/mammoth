#!/bin/sh
set -e

CONFIG_PATH="${MAMMOTH_CONFIG:-/app/config/mammoth.config.yaml}"

if [ "$#" -eq 0 ]; then
  exec mammoth start "$CONFIG_PATH"
fi

case "$1" in
  start)
    shift
    exec mammoth start "${1:-$CONFIG_PATH}"
    ;;
  validate)
    shift
    exec mammoth validate "${1:-$CONFIG_PATH}"
    ;;
  mammoth|ruby|bundle|sh|bash)
    exec "$@"
    ;;
  *)
    exec mammoth "$@"
    ;;
esac