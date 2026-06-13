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

Run the benchmark from the gem checkout with `bundle exec`. It does not require Redis or a running Sidekiq process, but the selected optional runtime gem must be installed when using `RUNTIME=concurrent` or `RUNTIME=parallel`.

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
| `CDC_PARALLEL_SIZE` | Ractor worker count for `cdc-parallel` | `Etc.nprocessors - 1`, minimum `1` |
| `CDC_TIMEOUT` | Per-item timeout in seconds | `nil` |
| `PRESERVE_ORDER` | Preserve result order for the `:concurrent` runtime | `true` |
| `WARMUP` | Warmup items before timing | `min(COUNT / 50, 10_000)` |
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
| `parallel` | `CDC_PARALLEL_SIZE=7`, run 1 | `6.613177 sec` | `75,607 items/sec` | `58` |
| `parallel` | `CDC_PARALLEL_SIZE=7`, run 2 | `5.830767 sec` | `85,752 items/sec` | `44` |
| `concurrent` | `CDC_CONCURRENCY=100` | `12.667181 sec` | `39,472 items/sec` | `45` |

The duplicate `parallel` rows are separate sample runs with the same settings. Keep that variance in mind when comparing small differences between runtimes.

## Interpretation

This snapshot is intentionally a no-op workload. It is useful for measuring runtime overhead, not real downstream work.

The `:direct` runtime wins by a huge margin because it performs no fan-out, no Ractor messaging, no Async task scheduling, and no pool coordination. For tiny no-op processors, `:direct` should be expected to dominate.

The `:parallel` runtime is slower than `:direct` for this workload because every item pays Ractor dispatch and result-collection cost. It is still faster than `:concurrent` in this snapshot, which suggests the Async task orchestration overhead is not worthwhile for a tiny CPU-free processor.

The `:concurrent` runtime is intended for I/O-heavy processors. A no-op benchmark is a poor workload for proving its value because there is no socket wait, remote API latency, database latency, or scheduler-friendly blocking work to hide.

## Snapshot: 50,000,000 No-op Items (`:parallel`)

Environment:

```text
started_at=2026-06-13T23:15:01+08:00
ruby=ruby 4.0.5 (2026-05-20 revision 64336ffd0e) +PRISM [x86_64-linux]

runtime=parallel
count=50,000,000
batch_size=50,000

cdc_parallel_size=3
cdc_concurrency=100

timeout=nil
preserve_order=false
warmup=10,000
```

Results:

| Runtime | Elapsed | Throughput | GC count |
| --- | ---: | ---: | ---: |
| `parallel` | `354.658167 sec` | `140,981 items/sec` | `5,010` |

Output:

```text
processed=50,000,000
elapsed=354.658167 sec
throughput=140,981 items/sec
gc_count=5010
```

### Interpretation

This benchmark processed fifty million no-op work items through the
`cdc-sidekiq` runtime boundary.

The benchmark used:

```text
COUNT=50,000,000
BATCH_SIZE=50,000
```

which means approximately:

```text
1,000 process_many(...) invocations
```

were executed:

```text
50,000,000 ÷ 50,000 = 1,000
```

Conceptually:

```text
Sidekiq-style job payload
        |
        v
50,000 items
        |
        v
CDC::Sidekiq::Runtime.process_many(...)
        |
        v
cdc-parallel
```

repeated one thousand times.

It is important to understand what this benchmark does and does not measure.

This benchmark does **not** measure:

- Redis throughput;
- Sidekiq enqueue performance;
- Sidekiq fetch performance;
- network I/O;
- PostgreSQL I/O;
- real CDC source adapters.

Instead it measures the downstream execution primitive used after a
Sidekiq job has already started and handed a batch of work items to
`cdc-sidekiq`.

The result demonstrates that a single `process_many(...)` invocation can
successfully drain large batches and that the runtime can sustain roughly:

```text
140k item executions/sec
```

across an aggregate workload of fifty million item executions.

A useful mental model is:

```text
1 Sidekiq job
      ↓
50,000 CDC events
      ↓
cdc-sidekiq
      ↓
cdc-parallel
```

rather than:

```text
50,000 individual Sidekiq jobs
```

The benchmark therefore validates the scalability of the downstream
`cdc-sidekiq` execution layer rather than the scalability of Sidekiq's
Redis-backed job transport.

Environment:

```text
count=5,000
batch_size=500
preserve_order=false
```

### Why `preserve_order=false` Matters

This benchmark intentionally disables result ordering:

```text
preserve_order=false
```

This allows the runtime to maximize throughput by returning results as
workers complete them rather than coordinating result reordering.

Conceptually:

```text
Worker A finishes
      ↓
result emitted immediately

Worker B finishes later
      ↓
result emitted later
```

instead of:

```text
Worker B finishes first
      ↓
wait

Worker C finishes second
      ↓
wait

Worker A finally finishes
      ↓
release A
release B
release C
```

Disabling ordering removes a coordination cost and allows the benchmark to
focus on raw fan-out behavior.

### Interpretation

This benchmark was designed to verify that:

```text
process_many(...)
        ↓
cdc-parallel
        ↓
prewarmed Ractor pool
```

was actually occurring.

With ordering disabled:

```text
preserve_order=false
```

the runtime achieved:

```text
1 worker  -> 51.77 sec
3 workers -> 17.49 sec
7 workers ->  7.55 sec
```

corresponding to:

```text
3 workers -> 2.96x speedup
7 workers -> 6.86x speedup
```

This demonstrates that work is being distributed across the configured
prewarmed Ractor pool and that the pool is capable of near-linear scaling
when ordering constraints are removed.

### Important

These results should not be interpreted as ordered CDC processing results.

Many CDC workloads require ordering guarantees.

When ordering is required:

```text
preserve_order=true
```

additional coordination is necessary and throughput may be lower.

This benchmark intentionally represents the maximum-throughput,
unordered execution path.

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

When comparing results, keep `COUNT`, `BATCH_SIZE`, Ruby version, CPU count, and runtime gem versions fixed. Changing any of those can shift the result more than a runtime tuning change.

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

