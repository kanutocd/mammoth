# frozen_string_literal: true

target :lib do
  library "date"
  library "fileutils"
  library "json"
  library "net/http"
  library "securerandom"
  library "stringio"
  library "time"
  library "timeout"
  library "uri"
  library "yaml"

  # Runtime gem libraries. These are intentionally referenced directly instead
  # of masking them with local shims.
  library "json-schema"
  library "sqlite3"

  signature "sig"

  check "lib"
end
