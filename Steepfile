# frozen_string_literal: true

target :lib do
  library "date"
  library "fileutils"
  library "json"
  library "net-http"
  library "socket"
  library "securerandom"
  library "stringio"
  library "time"
  library "timeout"
  library "uri"
  library "yaml"

  # Runtime gem libraries. These are intentionally referenced directly instead
  # of masking them with local shims.
  # json-schema does not publish an RBS library. Keep Mammoth signatures
  # honest by typing the tiny surface we use in sig/json_schema.rbs instead.
  # sqlite3 does not publish an RBS library in this bundle. Keep the
  # small Database API Mammoth uses in sig/sqlite3.rbs instead.

  signature "sig"

  check "lib"
end
