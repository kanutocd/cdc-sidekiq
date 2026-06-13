# F-002 Prewarmed Ractor Fan-Out Exists

Evidence:

1 worker -> 51.77 sec
3 workers -> 17.49 sec
7 workers -> 7.55 sec

Observed speedup:

- 3 workers -> 2.96x
- 7 workers -> 6.86x

Conclusion:

Work is distributed across the configured Ractor pool and scales nearly
linearly for this workload.
