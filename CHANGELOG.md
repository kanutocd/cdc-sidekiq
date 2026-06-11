## [Unreleased]

## [0.1.1] - 2026-06-12

- Improved unit test coverage for runtime selection, configuration copying, class-level job declarations, failure policies, and batch payload behavior.
- Added RBS signatures and validation coverage for the public cdc-sidekiq API.
- Fixed RBS validation issues around stdlib `Etc`, `default_runtime`, and dynamic processor-job class helpers.
- Documented all configuration defaults, including `raise_on_failure` and `batch_payloads`.
- Expanded benchmark documentation with the 500,000-item Ruby 4.0.5 snapshot, interpretation, and runtime tuning guidance.
- Clarified benchmark prerequisites, runtime knobs, and snapshot variance notes.
- Documented runtime-selection guidance and the shared-state correctness boundary between cdc-sidekiq and consumer processors/sinks.
- Filled missing YARD tag descriptions for void-returning APIs.
- Updated gem metadata documentation URI and description.


## [0.1.0] - 2026-06-08

- Initial release
