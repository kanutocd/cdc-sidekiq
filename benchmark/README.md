# Benchmarks

## `bin/cdc-sidekiq-load`

`bin/cdc-sidekiq-load` is intentionally aligned with Sidekiq's own `bin/sidekiq-load` benchmark style.

Sidekiq's load benchmark creates a large number of no-op jobs and drains them as fast as possible. `cdc-sidekiq-load` keeps the no-op workload shape but measures the downstream `cdc-sidekiq` execution model:

```text
Sidekiq-style job payload
      |
      v
CDC::Sidekiq::Runtime
      |
      +--> :direct
      +--> :concurrent
      +--> :parallel
      |
      v
process_many(items)
```

This benchmark does **not** replace Sidekiq's Redis-backed load benchmark. It measures the inner execution primitive that a CDC-aware Sidekiq job can use after Sidekiq has already started the job.

## Examples

```bash
COUNT=500000 RUNTIME=direct \
  bundle exec bin/cdc-sidekiq-load
```

```bash
COUNT=500000 RUNTIME=concurrent CDC_CONCURRENCY=100 \
  bundle exec bin/cdc-sidekiq-load
```

```bash
COUNT=500000 RUNTIME=parallel CDC_PARALLEL_SIZE=7 \
  bundle exec bin/cdc-sidekiq-load
```

## Knobs

| Environment variable | Purpose | Default |
| --- | --- | --- |
| `COUNT` | Total number of no-op work items | `500000` |
| `BATCH_SIZE` | Number of items per `process_many` call | `COUNT` |
| `RUNTIME` | `direct`, `concurrent`, or `parallel` | `concurrent` |
| `CDC_CONCURRENCY` | Async task limit for `cdc-concurrent` | `100` |
| `CDC_PARALLEL_SIZE` | Ractor worker count for `cdc-parallel` | `Etc.nprocessors - 1` |
| `CDC_TIMEOUT` | Per-item timeout in seconds | unset |
| `PRESERVE_ORDER` | Preserve result order for concurrent runtime | `true` |
| `WARMUP` | Warmup items before timing | `min(COUNT / 50, 10000)` |
| `JSON` | Print machine-readable JSON when set to `1` | unset |

## Snapshot: 500,000 No-op Items

Environment:

```text
ruby=ruby 4.0.5 (2026-05-20 revision 64336ffd0e) +PRISM [x86_64-linux]
count=500,000
batch_size=500,000
preserve_order=true
warmup=10,000
```

Results:

| Runtime | Knobs | Elapsed | Throughput | GC count |
| --- | --- | ---: | ---: | ---: |
| `direct` | default direct execution | `0.085821 sec` | `5,826,083 items/sec` | `0` |
| `parallel` | `CDC_PARALLEL_SIZE=7` | `6.613177 sec` | `75,607 items/sec` | `58` |
| `parallel` | `CDC_PARALLEL_SIZE=7` | `5.830767 sec` | `85,752 items/sec` | `44` |
| `concurrent` | `CDC_CONCURRENCY=100` | `12.667181 sec` | `39,472 items/sec` | `45` |

## Interpretation

This snapshot is intentionally a no-op workload. It is useful for measuring runtime overhead, not real downstream work.

The `:direct` runtime wins by a huge margin because it performs no fan-out, no Ractor messaging, no Async task scheduling, and no pool coordination. For tiny no-op processors, `:direct` should be expected to dominate.

The `:parallel` runtime is slower than `:direct` for this workload because every item pays Ractor dispatch and result-collection cost. It is still faster than `:concurrent` in this snapshot, which suggests the Async task orchestration overhead is not worthwhile for a tiny CPU-free processor.

The `:concurrent` runtime is intended for I/O-heavy processors. A no-op benchmark is a poor workload for proving its value because there is no socket wait, remote API latency, database latency, or scheduler-friendly blocking work to hide.

## Tuning Recommendations

Use `:direct` when:

- each item is very cheap;
- the processor does little or no I/O;
- the payload is already batched efficiently;
- predictable low overhead is more important than fan-out.

Use `:parallel` when:

- the processor is CPU-heavy;
- the processor and payloads are Ractor-shareable;
- batches are large enough to amortize Ractor dispatch overhead;
- the machine has spare CPU cores.

Start with:

```bash
CDC_PARALLEL_SIZE=$((nproc - 1))
```

then test lower values. More Ractors are not automatically better. Watch throughput, GC count, memory use, and downstream resource pressure.

Use `:concurrent` when:

- the processor is I/O-heavy;
- work spends meaningful time waiting on HTTP, Redis, PostgreSQL, MySQL, object storage, or other external systems;
- downstream services can tolerate the requested concurrency;
- preserving result order is either required or intentionally disabled.

Start with:

```bash
CDC_CONCURRENCY=25
```

then increase gradually. A concurrency value of `100` can be reasonable for I/O-bound workloads, but it is pure overhead for no-op work.

## Benchmark Rule of Thumb

```text
Tiny/no-op work  -> :direct
CPU-heavy work   -> :parallel
I/O-heavy work   -> :concurrent
Mixed topology   -> commercial orchestrator layer
```

The benchmark is useful for comparing:

```text
one Sidekiq job with many internal work items
  vs.
many Sidekiq jobs with one work item each
```

That distinction is the core `cdc-sidekiq` value proposition.
