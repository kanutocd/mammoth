# Reference Benchmark Results

This directory contains selected, publishable Mammoth benchmark snapshots.
Routine local runs remain ignored. A timestamped result is tracked only when
its measurements are useful as a documented baseline and the supporting
commands, environment, and raw output are retained with it.

Start with [`benchmark/README.md`](../README.md) for benchmark scope, commands,
configuration knobs, and the current result interpretation. The published
documentation mirrors that interpretation in
[`docs/BENCHMARKS.md`](../../docs/BENCHMARKS.md).

## Artifact contract

Each retained timestamp directory contains:

| Artifact | Purpose | Required |
| --- | --- | --- |
| `snapshot.md` | Generated human-readable commands, metadata, and result tables | Yes |
| `snapshot.json` | Generated machine-readable environment, inputs, statuses, and measurements | Yes |
| `*-trial-*.out` | Raw standard output for every retained successful trial | Yes |
| `*-trial-*.err` | Diagnostic output from a trial | Only when non-empty and safe to publish |

The JSON file is the canonical structured record. The generated Markdown and
raw output make it possible to review the record without custom tooling and to
diagnose parser or presentation mistakes.

Empty stderr files are not retained even though `snapshot.json` records their
generated filenames. Their absence means the corresponding stderr file was
empty at publication time. A missing stdout file is not acceptable.

## Acceptance criteria

A reference snapshot should normally satisfy all of the following:

- use the `full` preset unless it intentionally documents a narrower surface;
- run from a clean Git worktree and record the exact commit SHA;
- complete every selected benchmark and trial with status `0`;
- contain parsed, non-empty JSON results for every successful trial;
- retain the exact command and effective benchmark environment;
- use a supported Ruby and a described operating-system/architecture context;
- include raw stdout for independent inspection;
- contain no credentials, tokens, private URLs, usernames, absolute home paths,
  or other sensitive host information;
- have an interpretation in `benchmark/README.md` and
  `docs/BENCHMARKS.md` that separates measurements from inference; and
- pass the repository quality and documentation gates.

Use at least three trials when establishing a regression threshold, comparing
implementations, or making a release-level performance statement. A
single-trial snapshot may be retained as an initial descriptive baseline, but
it must be labeled as such and must not be presented as a confidence interval
or capacity commitment.

## Publishing a new reference

1. Start from the intended clean commit and record relevant host conditions,
   including competing workloads, power mode, and storage type when they may
   affect interpretation.
2. Prefer a multi-trial full run:

   ```bash
   MAMMOTH_SNAPSHOT_TRIALS=3 bundle exec ruby benchmark/snapshot.rb
   ```

3. Inspect every status, parsed result, `.out`, and non-empty `.err` file.
   Investigate failures or missing JSON rather than publishing a partial run as
   a complete reference.
4. Review `snapshot.md`, `snapshot.json`, and raw output for sensitive or
   machine-specific information. The runner records a hostname, and the CPU
   description may repeat it.
5. Redact host identity consistently in Markdown and JSON. Do not alter
   commands, inputs, statuses, timings, rates, allocation counts, byte counts,
   or other measurements.
6. Add narrow `.gitignore` exceptions for only the selected timestamp,
   generated reports, and publishable raw output. Leave other local runs and
   empty stderr files ignored.
7. Add the snapshot to the retained-snapshot index below and update the
   benchmark interpretation in both repository and published documentation.
8. Validate the selected artifacts:

   ```bash
   ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' \
     benchmark/results/<timestamp>/snapshot.json
   git diff --check
   bundle exec rake
   ```

Do not hand-edit measured values to make tables agree. Fix the runner or parser
and generate a new snapshot if the source data is wrong. Privacy-only
redactions must be obvious and must leave the structured document valid.

## Interpreting and comparing snapshots

Treat results as local observations, not universal performance claims.
Meaningful comparisons require the same:

- commit or explicitly identified code change;
- Ruby version and architecture;
- benchmark preset, environment overrides, trial count, and warmup;
- destination latency, event count, payload shape, fanout, and concurrency;
- filesystem and SQLite volume characteristics; and
- relevant host load and power-management conditions.

When multiple trials are available, report a median and the observed range or
another stated dispersion measure. Do not infer a regression from small
single-trial differences. PostgreSQL transport, WAL decoding, network
variability, receiver rate limits, and production storage behavior remain
outside a local benchmark unless the selected script explicitly includes them.

Retained timestamp directories are historical evidence. Do not overwrite a
published measurement with a later run. Add a new timestamp and explain which
snapshot it supersedes. Removal is appropriate only for accidental sensitive
data, invalid measurements, or artifacts that cannot be legally or safely
distributed; document the reason in the replacing change.

## Retained snapshots

### `20260724T104950Z`

- [Generated report](20260724T104950Z/snapshot.md)
- [Machine-readable snapshot](20260724T104950Z/snapshot.json)
- Full preset covering all eight benchmark surfaces
- One successful trial per benchmark with parsed JSON results
- Ruby 4.0.5 on x86-64 Linux
- Clean Git commit `b6889c0f37a19c7d1950c28d5524c2742c5feddb`
- Host identity redacted; runtime, kernel, commands, inputs, and measurements
  retained
- Accepted as the initial descriptive baseline; not a statistical regression
  threshold or capacity commitment
- Interpretation:
  [`benchmark/README.md`](../README.md#reference-snapshot-2026-07-24)
