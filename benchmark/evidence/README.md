# Benchmarks

## `bin/cdc-sidekiq-load`

Benchmark runner for evaluating the downstream execution primitives used by
`cdc-sidekiq` after a Sidekiq job has already started and handed work to:

```text
CDC::Sidekiq::Runtime.process_many(...)
```

## Published Snapshots

- [2026-06-13-500k-noop.md](./snapshots/2026-06-13-500k-noop.md)
- [2026-06-13-50m-noop.md](./snapshots/2026-06-13-50m-noop.md)
- [2026-06-14-ractor-fanout.md](./snapshots/2026-06-14-ractor-fanout.md)
- [2026-06-14-preserve-order.md](./snapshots/2026-06-14-preserve-order.md)
- [2026-06-14-cpu-bound.md (planned)](./snapshots/2026-06-14-cpu-bound.md)

## Additional Documentation

- [methodology.md](./methodology.md)
- [hardware.md](./hardware.md)
- [benchmark-timeline.md](./benchmark-timeline.md)
- findings/

## Benchmark Rule of Thumb

Tiny/no-op work  -> :direct
CPU-heavy work   -> :parallel
I/O-heavy work   -> :concurrent
Mixed topology   -> commercial orchestrator layer
