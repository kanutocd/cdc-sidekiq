# frozen_string_literal: true

require_relative "lib/cdc/sidekiq/version"

Gem::Specification.new do |spec|
  spec.name = "cdc-sidekiq"
  spec.version = CDC::Sidekiq::VERSION
  spec.authors = ["Ken C. Demanawa"]
  spec.email = ["kenneth.c.demanawa@gmail.com"]

  spec.summary = "Sidekiq integration for CDC execution runtimes."
  spec.description = <<~DESC
    Adds CDC-aware processor jobs and runtime selection to Sidekiq,
    allowing selected jobs to execute payloads directly, through cdc-parallel, or through cdc-concurrent.
  DESC
  spec.homepage = "https://github.com/kanutocd/cdc-sidekiq"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://kanutocd.github.io/cdc-sidekiq/"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "examples/**/*.rb",
    "README.md",
    "CHANGELOG.md",
    "benchmark/README.md",
    "LICENSE.txt"
  ]
  spec.add_dependency "cdc-core", ">= 0.1"
  spec.add_dependency "sidekiq", ">= 7.0"

  # Runtime gems are optional so applications can install only the execution
  # substrate they need. Jobs using :parallel require cdc-parallel. Jobs using
  # :concurrent require cdc-concurrent.

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
