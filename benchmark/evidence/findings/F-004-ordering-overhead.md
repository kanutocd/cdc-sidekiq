# F-004 Ordering Overhead Depends On Workload

Uniform sleep workload:

size=7
- preserve_order=false -> 7.549787 sec
- preserve_order=true  -> 7.675939 sec

Conclusion:

Ordering overhead was negligible for homogeneous-duration work.
