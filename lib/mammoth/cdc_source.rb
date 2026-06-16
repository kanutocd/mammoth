# frozen_string_literal: true

module Mammoth
  # Backwards-compatible internal alias for the PostgreSQL CDC source.
  #
  # New code should use {Mammoth::Sources::Postgres}. Mammoth v0.1.0 keeps this
  # constant so older tests or examples that referenced the transitional
  # CdcSource name continue to work while the product-facing source name moves
  # to PostgreSQL.
  CdcSource = Sources::Postgres
end
