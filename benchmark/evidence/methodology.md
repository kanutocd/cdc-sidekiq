# Methodology

Measures:
- Runtime dispatch overhead
- Batch execution throughput
- Worker pool coordination
- Ractor fan-out behavior

Does not measure:
- Redis throughput
- Sidekiq enqueue/dequeue throughput
- PostgreSQL throughput
- CDC source adapter throughput

Keep COUNT, BATCH_SIZE, Ruby version, CPU count, and gem versions fixed.
