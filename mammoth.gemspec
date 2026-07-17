# frozen_string_literal: true

require_relative "lib/mammoth/version"

Gem::Specification.new do |spec|
  spec.name = "mammoth"
  spec.version = Mammoth::VERSION
  spec.authors = ["Ken C. Demanawa"]
  spec.email = ["kenneth.c.demanawa@gmail.com"]

  spec.summary = "Reliable delivery of PostgreSQL logical replication events with retries, dead letters, and operational state."
  spec.description = <<~TEXT
    Mammoth is an OSS PostgreSQL change-event delivery appliance for Ruby.

    It realizes the CDC Ecosystem pgoutput and cdc-core libraries for PostgreSQL,
    then delivers normalized changes to webhook endpoints with durable
    checkpointing, retry state, dead letters, and operational visibility.

    Mammoth is application-first: it can be installed as a Ruby gem, packaged
    into a container image, or deployed into Kubernetes with Helm.
  TEXT

  spec.homepage = "https://kanutocd.github.io/mammoth/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kanutocd/mammoth"
  spec.metadata["changelog_uri"] = "https://github.com/kanutocd/mammoth/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "#{spec.homepage}Mammoth.html"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir.glob(
      [
        "CHANGELOG.md",
        "LICENSE.txt",
        "README.md",
        "config/mammoth.example.yml",
        "config/mammoth.schema.json",
        "exe/mammoth",
        "lib/**/*.rb",
        "lib/**/*.sql"
      ],
      File::FNM_DOTMATCH
    ).select { |file| File.file?(file) }
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |file| File.basename(file) }
  spec.require_paths = ["lib"]

  spec.add_dependency "cdc-concurrent", "~> 0.1"
  spec.add_dependency "cdc-core", "~> 0.1"
  spec.add_dependency "json-schema", "~> 6.2"
  spec.add_dependency "pgoutput-client", "~> 0.4"
  spec.add_dependency "pgoutput-decoder", "~> 0.1"
  spec.add_dependency "pgoutput-parser", "~> 0.1"
  spec.add_dependency "pgoutput-source-adapter", "~> 0.2", ">= 0.2.0"
  spec.add_dependency "sqlite3", "~> 2.9"
  spec.add_dependency "webrick", "~> 1.9"
end
