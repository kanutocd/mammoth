#!/usr/bin/env sh
set -eu

exec bundle exec ruby -Ilib exe/mammoth "$@"
