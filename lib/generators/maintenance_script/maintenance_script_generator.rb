# frozen_string_literal: true

require "rails/generators"

# Generates a maintenance script file from a template.
#
# This generator creates a new maintenance script file in the directory specified by
# `Dekiru::DataMigration.configuration.maintenance_script_directory`. The generated file is named
# with the current date (in YYYYMMDD format) followed by the provided name.
#
# Example usage:
#   rails generate maintenance_script MyScript
class MaintenanceScriptGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  def copy_maintenance_script_file
    template "maintenance_script.rb.erb",
             "#{Dekiru::DataMigration.configuration.maintenance_script_directory}/#{filename_date}_#{file_name}.rb"
  end

  private

  def filename_date
    Time.current.strftime("%Y%m%d")
  end
end
