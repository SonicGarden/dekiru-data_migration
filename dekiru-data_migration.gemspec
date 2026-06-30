# frozen_string_literal: true

require_relative "lib/dekiru/data_migration/version"

Gem::Specification.new do |spec|
  spec.name = "dekiru-data_migration"
  spec.version = Dekiru::DataMigration::VERSION
  spec.authors = ["SonicGarden"]
  spec.email = ["info@sonicgarden.jp"]

  spec.summary = "A Ruby on Rails library for executing data migration tasks safely and efficiently."
  spec.description =
    "Dekiru::DataMigration provides features for data migration tasks including progress display, " \
    "transaction management, execution confirmation, side effect monitoring, and detailed logging."
  spec.homepage = "https://github.com/SonicGarden/dekiru-data_migration"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/SonicGarden/dekiru-data_migration"
  spec.metadata["changelog_uri"] = "https://github.com/SonicGarden/dekiru-data_migration/releases"
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rails"
  spec.add_dependency "ruby-progressbar"
end
