# Snapshot: Prewarmed Ractor Pool Fan-Out

Processor:

sleep 0.01

| Workers | Order | Elapsed | Throughput |
|---:|---|---:|---:|
| 1 | false | 51.766215 | 97/sec |
| 3 | false | 17.492817 | 286/sec |
| 7 | false | 7.549787 | 662/sec |

Observed NLWP:

1 -> 3
3 -> 5
7 -> 9
