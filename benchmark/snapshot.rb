#!/usr/bin/env ruby
# frozen_string_literal: true

# Run Mammoth benchmark scripts and write publishable snapshot artifacts.
#
# Defaults are intentionally moderate. Override any benchmark knob with normal
# MAMMOTH_BENCH_* environment variables, or set MAMMOTH_SNAPSHOT_PRESET=smoke
# for a quick validation run.

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "shellwords"
require "socket"
require "time"

ROOT = File.expand_path("..", __dir__)
RESULT_ROOT = File.join(ROOT, "benchmark", "results")

BenchmarkSpec = Data.define(:name, :script, :defaults)

class BenchmarkSnapshotRunner
  SMOKE_DEFAULTS = {
    "serialization" => {
      "MAMMOTH_BENCH_SERIALIZATIONS" => "100",
      "MAMMOTH_BENCH_WARMUP_SERIALIZATIONS" => "10",
      "MAMMOTH_BENCH_EVENTS_PER_TRANSACTION" => "4"
    },
    "concurrent_delivery" => {
      "MAMMOTH_BENCH_TRANSACTIONS" => "20",
      "MAMMOTH_BENCH_WARMUP_TRANSACTIONS" => "2",
      "MAMMOTH_BENCH_EVENTS_PER_TRANSACTION" => "4",
      "MAMMOTH_BENCH_LATENCY_MS" => "0",
      "MAMMOTH_BENCH_CONCURRENCY" => "1,2",
      "MAMMOTH_BENCH_PRESERVE_ORDER" => "false"
    },
    "webhook_delivery" => {
      "MAMMOTH_BENCH_REQUESTS" => "10",
      "MAMMOTH_BENCH_LATENCY_MS" => "0",
      "MAMMOTH_BENCH_DELIVERY_UNIT" => "transaction",
      "MAMMOTH_BENCH_AUTH" => "true",
      "MAMMOTH_BENCH_SIGNING" => "true"
    },
    "webhook_fanout" => {
      "MAMMOTH_BENCH_TRANSACTIONS" => "10",
      "MAMMOTH_BENCH_EVENTS_PER_TRANSACTION" => "4",
      "MAMMOTH_BENCH_DESTINATIONS" => "1,2",
      "MAMMOTH_BENCH_LATENCY_MS" => "0"
    },
    "sqlite_operational_state" => {
      "MAMMOTH_BENCH_RECORDS" => "20",
      "MAMMOTH_BENCH_DEAD_LETTERS" => "5",
      "MAMMOTH_BENCH_CHECKPOINT_INTERVAL" => "5"
    },
    "observability_snapshot" => {
      "MAMMOTH_BENCH_DELIVERED" => "20",
      "MAMMOTH_BENCH_DEAD_LETTERS" => "5",
      "MAMMOTH_BENCH_SNAPSHOTS" => "5"
    },
    "dlq_replay" => {
      "MAMMOTH_BENCH_DEAD_LETTERS" => "20",
      "MAMMOTH_BENCH_DESTINATIONS" => "2",
      "MAMMOTH_BENCH_DELIVERY_UNIT" => "transaction",
      "MAMMOTH_BENCH_EVENTS_PER_TRANSACTION" => "4"
    }
  }.freeze

  FULL_DEFAULTS = {
    "serialization" => {
      "MAMMOTH_BENCH_SERIALIZATIONS" => "100000",
      "MAMMOTH_BENCH_WARMUP_SERIALIZATIONS" => "5000",
      "MAMMOTH_BENCH_EVENTS_PER_TRANSACTION" => "4"
    },
    "concurrent_delivery" => {
      "MAMMOTH_BENCH_TRANSACTIONS" => "5000",
      "MAMMOTH_BENCH_WARMUP_TRANSACTIONS" => "100",
      "MAMMOTH_BENCH_EVENTS_PER_TRANSACTION" => "4",
      "MAMMOTH_BENCH_LATENCY_MS" => "25",
      "MAMMOTH_BENCH_CONCURRENCY" => "1,5,10,25,50",
      "MAMMOTH_BENCH_PRESERVE_ORDER" => "false"
    },
    "webhook_delivery" => {
      "MAMMOTH_BENCH_REQUESTS" => "1000",
      "MAMMOTH_BENCH_LATENCY_MS" => "10",
      "MAMMOTH_BENCH_DELIVERY_UNIT" => "transaction",
      "MAMMOTH_BENCH_AUTH" => "true",
      "MAMMOTH_BENCH_SIGNING" => "true"
    },
    "webhook_fanout" => {
      "MAMMOTH_BENCH_TRANSACTIONS" => "250",
      "MAMMOTH_BENCH_EVENTS_PER_TRANSACTION" => "4",
      "MAMMOTH_BENCH_DESTINATIONS" => "1,2,5,10",
      "MAMMOTH_BENCH_LATENCY_MS" => "10"
    },
    "sqlite_operational_state" => {
      "MAMMOTH_BENCH_RECORDS" => "10000",
      "MAMMOTH_BENCH_DEAD_LETTERS" => "1000",
      "MAMMOTH_BENCH_CHECKPOINT_INTERVAL" => "100"
    },
    "observability_snapshot" => {
      "MAMMOTH_BENCH_DELIVERED" => "10000",
      "MAMMOTH_BENCH_DEAD_LETTERS" => "1000",
      "MAMMOTH_BENCH_SNAPSHOTS" => "100"
    },
    "dlq_replay" => {
      "MAMMOTH_BENCH_DEAD_LETTERS" => "1000",
      "MAMMOTH_BENCH_DESTINATIONS" => "2",
      "MAMMOTH_BENCH_DELIVERY_UNIT" => "transaction",
      "MAMMOTH_BENCH_EVENTS_PER_TRANSACTION" => "4"
    }
  }.freeze

  attr_reader :preset, :trials, :selected, :output_dir

  def initialize(
    preset: ENV.fetch("MAMMOTH_SNAPSHOT_PRESET", "full"),
    trials: self.class.integer_env("MAMMOTH_SNAPSHOT_TRIALS", 1),
    selected: ENV.fetch("MAMMOTH_SNAPSHOT_BENCHMARKS", "").split(",").map(&:strip).reject(&:empty?)
  )
    @preset = preset
    @trials = trials
    @selected = selected
    @output_dir = File.join(RESULT_ROOT, Time.now.utc.strftime("%Y%m%dT%H%M%SZ"))
  end

  def run
    FileUtils.mkdir_p(output_dir)
    snapshot = {
      generated_at: Time.now.utc.iso8601,
      preset: preset,
      trials: trials,
      environment: environment,
      benchmarks: specs.map { |spec| run_spec(spec) }
    }
    write_json(snapshot)
    write_markdown(snapshot)
    puts "Benchmark snapshot written to #{output_dir}"
    snapshot
  end

  private

  def specs
    defaults.keys.filter_map do |name|
      next if selected.any? && !selected.include?(name)

      BenchmarkSpec.new(name, File.join("benchmark", "#{name}.rb"), defaults.fetch(name))
    end
  end

  def defaults
    case preset
    when "smoke" then SMOKE_DEFAULTS
    when "full" then FULL_DEFAULTS
    else
      raise ArgumentError, "unknown MAMMOTH_SNAPSHOT_PRESET=#{preset.inspect}; expected smoke or full"
    end
  end

  def run_spec(spec)
    trial_results = trials.times.map do |index|
      run_trial(spec, index + 1)
    end
    {
      name: spec.name,
      script: spec.script,
      defaults: spec.defaults,
      command: command_for(spec),
      trials: trial_results
    }
  end

  def run_trial(spec, trial)
    env = spec.defaults.merge(external_overrides(spec)).merge("MAMMOTH_BENCH_JSON" => "1")
    started_at = Time.now.utc.iso8601
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, spec.script, chdir: ROOT)
    write_trial_log(spec.name, trial, stdout, stderr)
    {
      trial: trial,
      started_at: started_at,
      status: status.exitstatus,
      success: status.success?,
      stdout_file: "#{spec.name}-trial-#{trial}.out",
      stderr_file: "#{spec.name}-trial-#{trial}.err",
      command_env: env,
      results: parse_json_results(stdout)
    }
  end

  def external_overrides(spec)
    spec.defaults.keys.each_with_object({}) do |key, overrides|
      overrides[key] = ENV.fetch(key) if ENV.key?(key)
    end
  end

  def command_for(spec)
    env = spec.defaults.merge(external_overrides(spec))
    env.map { |key, value| "#{key}=#{Shellwords.escape(value)}" }.join(" ") +
      " bundle exec ruby #{spec.script}"
  end

  def write_trial_log(name, trial, stdout, stderr)
    File.write(File.join(output_dir, "#{name}-trial-#{trial}.out"), stdout)
    File.write(File.join(output_dir, "#{name}-trial-#{trial}.err"), stderr)
  end

  def parse_json_results(stdout)
    JSON.parse(stdout[stdout.rindex("\n[") || stdout.rindex("[")..])
  rescue JSON::ParserError, TypeError
    nil
  end

  def write_json(snapshot)
    File.write(File.join(output_dir, "snapshot.json"), JSON.pretty_generate(snapshot))
  end

  def write_markdown(snapshot)
    File.write(File.join(output_dir, "snapshot.md"), markdown(snapshot))
  end

  def markdown(snapshot)
    lines = [
      "# Mammoth Benchmark Snapshot",
      "",
      "- Generated at: #{snapshot.fetch(:generated_at)}",
      "- Preset: #{snapshot.fetch(:preset)}",
      "- Trials: #{snapshot.fetch(:trials)}",
      "- Git SHA: #{snapshot.fetch(:environment).fetch(:git_sha)}",
      "- Ruby: #{snapshot.fetch(:environment).fetch(:ruby)}",
      "- Platform: #{snapshot.fetch(:environment).fetch(:platform)}",
      "- Host: #{snapshot.fetch(:environment).fetch(:hostname)}",
      "",
      "These are local benchmark snapshots, not universal performance claims.",
      "Publish the command, environment, and Mammoth commit SHA with any interpretation.",
      ""
    ]
    snapshot.fetch(:benchmarks).each { |benchmark| append_benchmark(lines, benchmark) }
    "#{lines.join("\n")}\n"
  end

  def append_benchmark(lines, benchmark)
    lines.concat([
                   "## #{benchmark.fetch(:name)}",
                   "",
                   "Command:",
                   "",
                   "```bash",
                   benchmark.fetch(:command),
                   "```",
                   ""
                 ])
    benchmark.fetch(:trials).each do |trial|
      lines << "### Trial #{trial.fetch(:trial)}"
      lines << ""
      lines << "- Status: #{trial.fetch(:status)}"
      lines << "- Output: `#{trial.fetch(:stdout_file)}`"
      lines << ""
      append_results(lines, trial.fetch(:results))
    end
  end

  def append_results(lines, results)
    return lines.concat(["JSON results were not detected.", ""]) unless results.is_a?(Array) && results.any?

    keys = results.flat_map(&:keys).uniq
    lines << "| #{keys.join(" | ")} |"
    lines << "| #{keys.map { "---" }.join(" | ")} |"
    results.each do |result|
      lines << "| #{keys.map { |key| result[key].inspect }.join(" | ")} |"
    end
    lines << ""
  end

  def environment
    {
      git_sha: capture("git", "rev-parse", "HEAD"),
      git_status: capture("git", "status", "--short"),
      ruby: RUBY_DESCRIPTION,
      platform: RUBY_PLATFORM,
      hostname: Socket.gethostname,
      cpu: capture("uname", "-a")
    }
  end

  def capture(*command)
    stdout, = Open3.capture2(*command, chdir: ROOT)
    stdout.strip
  rescue StandardError => e
    "#{e.class}: #{e.message}"
  end

  def self.integer_env(name, default)
    value = ENV[name]
    return default if value.nil? || value.empty?

    Integer(value, 10)
  end
end

BenchmarkSnapshotRunner.new.run if $PROGRAM_NAME == __FILE__
