# cdc-sidekiq

[![Gem Version](https://badge.fury.io/rb/cdc-sidekiq.svg)](https://badge.fury.io/rb/cdc-sidekiq)
[![CI](https://github.com/kanutocd/cdc-sidekiq/workflows/CI/badge.svg)](https://github.com/kanutocd/cdc-sidekiq/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%203.4-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

`cdc-sidekiq` integrates Sidekiq with CDC execution primitives.

Sidekiq remains the durable job system. It owns scheduling, retries, queues, Redis persistence, and operational behavior.

`cdc-sidekiq` owns what happens inside selected jobs: processor contracts, runtime selection, fan-out/fan-in execution, and normalized processor results.

```text
Sidekiq Job
      |
      v
CDC::Sidekiq::ProcessorJob
      |
      +--> :direct
      |       sequential processor calls
      |
      +--> cdc-parallel
      |       Ractor fan-out / fan-in
      |
      +--> cdc-concurrent
              Async task fan-out / fan-in
```

## Why cdc-sidekiq Exists

Sidekiq is excellent at durable background job execution.

It provides:

- scheduling
- retries
- queues
- Redis-backed persistence
- operational familiarity

However, Sidekiq intentionally leaves the internal execution strategy of a job to the application.

`cdc-sidekiq` extends Sidekiq with CDC execution primitives:

- processor contracts
- parallel execution with `cdc-parallel`
- concurrent execution with `cdc-concurrent`
- fan-out / fan-in processing
- ordered result collection
- normalized processor results

The goal is not to replace Sidekiq.

The goal is to make execution topology an explicit choice inside Sidekiq jobs.

```text
Sidekiq schedules the work.
CDC primitives execute the work.
```

---

## Roadmap

### Community Edition

The open-source edition focuses on execution primitives.

Current OSS capabilities:

- `:direct` runtime
- `:concurrent` runtime
- `:parallel` runtime
- ProcessorJob abstraction
- `process`
- `process_many`
- ordered result collection
- normalized ProcessorResult handling

### Commercial Orchestration Boundary

The open-source edition focuses on Sidekiq integration and explicit execution primitives.

Advanced orchestration belongs above this gem. Commercial orchestration features such as hybrid runtimes, nested worker topologies, worker-local resource pools, adaptive sizing, capacity guards, telemetry, and advanced failure policies live in the commercial orchestrator layer.

```text
cdc-sidekiq
    Sidekiq integration
    ProcessorJob abstraction
    :direct / :concurrent / :parallel runtime selection

cdc-orchestrator-pro
    Hybrid runtime
    Nested runtime / worker-local resource pools
    Orchestration, backpressure, telemetry, tuning
```

This keeps the OSS gem small and useful while leaving operational orchestration to the commercial layer.

## Runtime Selection Guide

Choose the smallest runtime that matches the work.

| Runtime | Best fit | Avoid when |
| --- | --- | --- |
| `:direct` | Tiny, cheap, already-batched work | You need internal fan-out |
| `:parallel` | CPU-heavy, Ractor-shareable processing | Payloads/processors are not shareable or work is too tiny |
| `:concurrent` | I/O-heavy processing with scheduler-friendly waits | Work is CPU-bound or effectively no-op |

A useful rule of thumb:

```text
Sidekiq controls how many jobs run.
cdc-sidekiq controls how one selected job executes its internal payload.
```

Do not increase both Sidekiq concurrency and CDC runtime concurrency blindly. That can multiply downstream pressure on Redis, PostgreSQL, HTTP APIs, and other shared resources.

## Correctness Boundary

`cdc-sidekiq` controls execution topology. It does not make shared downstream state automatically safe.

When multiple jobs or multiple internal work items update the same database rows, files, search documents, Redis keys, or external API resources, the processor or sink must provide the correctness policy. Common strategies include:

- database transactions;
- row-level locks such as `SELECT ... FOR UPDATE`;
- optimistic locking;
- idempotency keys;
- conflict-safe writes;
- single-writer sink patterns.

The runtime can provide controlled execution. Application-specific correctness remains the responsibility of the processor and sink implementation.

## Benchmarks

See [benchmark/README.md](./benchmark/README.md) for the `bin/cdc-sidekiq-load` benchmark, recent 500,000-item snapshots, interpretation, and runtime tuning guidance.

## Requirements

Ruby 3.4 or newer.

Runtime support depends on the selected CDC execution substrate:

| Runtime | Ruby | Required gems |
| --- | --- | --- |
| `:direct` | 3.4+ | `sidekiq`, `cdc-core` |
| `:concurrent` | 3.4+ | `sidekiq`, `cdc-core`, `cdc-concurrent` |
| `:parallel` | 4.0+ | `sidekiq`, `cdc-core`, `cdc-parallel` |

`cdc-parallel` remains optional because it requires Ruby 4+. Ruby 3.4 users can still use `:direct` and `:concurrent`.

## Installation

```ruby
gem "cdc-sidekiq"
```

Runtime gems are installed by the application according to the execution model it uses:

```ruby
gem "cdc-concurrent" # for Async-backed execution
gem "cdc-parallel"   # for Ractor-backed execution
```

Applications that only use `:direct` do not need either optional runtime gem.

## Configuration

```ruby
Sidekiq.configure_server do |_config|
  CDC::Sidekiq.configure do |cdc|
    cdc.default_runtime = :concurrent
    cdc.parallel_size = Etc.nprocessors - 1
    cdc.concurrency = 100
    cdc.timeout = nil
    cdc.preserve_order = true
    cdc.raise_on_failure = true
    cdc.batch_payloads = true
  end
end
```

Configuration defaults:

| Option | Default | Meaning |
| --- | --- | --- |
| `default_runtime` | `:concurrent` | Runtime used when a job does not declare `cdc_runtime`. |
| `parallel_size` | `Etc.nprocessors - 1`, minimum `1` | Ractor worker count for `:parallel` jobs. |
| `concurrency` | `100` | Async task limit for `:concurrent` jobs. |
| `timeout` | `nil` | Optional per-item timeout passed to CDC processor pools. |
| `preserve_order` | `true` | Preserve input order for `:concurrent` result arrays. |
| `raise_on_failure` | `true` | Raise failed `ProcessorResult` objects so Sidekiq can retry. |
| `batch_payloads` | `true` | Process array payloads with `process_many` instead of treating the array as one item. |

Sidekiq concurrency and CDC runtime concurrency are intentionally separate.

```text
Sidekiq concurrency
  = how many Sidekiq jobs run at once

CDC parallel size
  = how many Ractors one CDC-enabled job may use internally

CDC concurrency
  = how many Async tasks one CDC-enabled job may use internally
```

## Usage

### Parallel processor job

```ruby
class UserIndexer < CDC::Core::Processor
  ractor_safe!

  def process(user_id)
    # CPU-heavy or shareable work
    CDC::Core::ProcessorResult.success(user_id)
  end
end

class ReindexUsersJob
  include Sidekiq::Job
  include CDC::Sidekiq::ProcessorJob

  cdc_processor UserIndexer
  cdc_runtime :parallel
  cdc_parallel_size Etc.nprocessors - 1
end

ReindexUsersJob.perform_async([1, 2, 3, 4])
```

Array payloads are processed with `process_many` by default.

```text
Sidekiq job payload
      |
      v
process_many
      |
      v
cdc-parallel ProcessorPool
      |
      v
ordered ProcessorResult array
```

### Concurrent processor job

```ruby
class WebhookDeliverer < CDC::Core::Processor
  def concurrent_safe? = true

  def process(webhook_payload)
    # I/O-heavy scheduler-friendly work
    CDC::Core::ProcessorResult.success(webhook_payload)
  end
end

class DeliverWebhooksJob
  include Sidekiq::Job
  include CDC::Sidekiq::ProcessorJob

  cdc_processor WebhookDeliverer
  cdc_runtime :concurrent
  cdc_concurrency 250
  cdc_timeout 5.0
end
```

### Per-job runtime override

Global configuration provides defaults. Each job can override the runtime.

```ruby
class ProjectionJob
  include Sidekiq::Job
  include CDC::Sidekiq::ProcessorJob

  cdc_processor ProjectionProcessor
  cdc_runtime :parallel
end
```

## Failure behavior

By default, failed `ProcessorResult` objects raise `CDC::Sidekiq::ProcessorFailureError` so Sidekiq can apply its normal retry behavior.

```ruby
class BestEffortJob
  include Sidekiq::Job
  include CDC::Sidekiq::ProcessorJob

  cdc_processor BestEffortProcessor
  cdc_runtime :concurrent
  cdc_raise_on_failure false
end
```

## Benchmarking

`cdc-sidekiq` includes `bin/cdc-sidekiq-load`, a benchmark aligned with Sidekiq's `bin/sidekiq-load` style.

Sidekiq's benchmark creates many no-op jobs and drains them as fast as possible. `cdc-sidekiq-load` keeps the no-op workload shape but measures the downstream CDC runtime path inside one CDC-aware Sidekiq job.

```bash
COUNT=500000 RUNTIME=concurrent CDC_CONCURRENCY=100 \
  bundle exec bin/cdc-sidekiq-load
```

```bash
COUNT=500000 RUNTIME=parallel CDC_PARALLEL_SIZE=7 \
  bundle exec bin/cdc-sidekiq-load
```

See [`benchmark/README.md`](https://github.com/kanutocd/cdc-sidekiq/tree/main/benchmark) for interpretation notes and all benchmark knobs.

## Current scope

This gem currently implements the downstream/runtime integration only:

```text
Sidekiq Job
    ↓
CDC execution primitives

Future:

PostgreSQL WAL
    ↓
pgoutput*
    ↓
Sidekiq Job
    ↓
CDC execution primitives
```

A future upstream/source integration may map PostgreSQL logical replication events into Sidekiq work through the `pgoutput*` family and `pgoutput-source-adapter`, but that is intentionally out of scope for the initial release.

## License

[MIT](./LICENSE.txt).
