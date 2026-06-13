# F-001 No-op Workloads Are Coordination Bound

Evidence:

| Workers | Throughput |
|---:|---:|
| 1 | 210,675/sec |
| 3 | 140,981/sec |
| 7 | 116,157/sec |

Conclusion:

When useful work is near zero, additional workers increase coordination
cost and reduce throughput.
