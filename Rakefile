# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"
require "yard"
require "yard/rake/yardoc_task"
require "rake/testtask"

Minitest::TestTask.create(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.warning = false
  t.test_globs = ["test/mammoth/**/*.rb"]
end

RuboCop::RakeTask.new

namespace :test do
  desc "Run end-to-end tests"
  Rake::TestTask.new(:e2e) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.warning = false
    t.pattern = "test/e2e/**/*_test.rb"
  end
end

YARD::Rake::YardocTask.new(:yard)

namespace :rbs do
  desc "Remove generated RBS prototype files"
  task :clobber do
    sh "rm -rf tmp/sig"
  end

  desc "Generate disposable RBS prototypes into tmp/sig"
  task :prototype do
    sh "rm -rf tmp/sig"
    sh "mkdir -p tmp/sig"
    sh "bundle exec rbs prototype rb --out-dir=tmp/sig --base-dir=lib lib"

    unless Dir.exist?("sig")
      puts "sig/ does not exist; seeding curated signatures from tmp/sig"
      sh "cp -R tmp/sig sig"
    end
  end

  desc "Validate curated RBS signatures with Steep"
  task :validate do
    sh "bundle exec steep check"
  end

  desc "Open diff between curated and generated signatures"
  task :diff do
    sh "diff -ru sig tmp/sig || true"
  end

  desc "Generate disposable RBS prototypes and validate curated signatures"
  task check: %i[prototype validate]
end

task default: %i[test rubocop rbs:validate yard]
