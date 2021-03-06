#
# Copyright:: Copyright (c) 2016 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require_relative "bundle_util"
require_relative "bundle"
require_relative "../version_policy"
require_relative "helpers"

desc "Tasks to update and check dependencies"
namespace :dependencies do

  # Running update_ci on your local system wont' work. The best way to update
  # dependencies locally is by running the dependency update script.
  desc "Update all dependencies."
  task :update do |t, rake_args|
    system("#{File.join(Dir.pwd, "ci", "dependency_update.sh")}")
  end

  desc "Force update (when adding new gems to Gemfiles)"
  task :force_update do |t, rake_args|
    FileUtils.rm_f(File.join(Dir.pwd, ".bundle", "config"))
    system("#{File.join(Dir.pwd, "ci", "dependency_update.sh")}")
  end

  # Update all dependencies to the latest constraint-matching version
  desc "Update all dependencies. (CI Only)"
  task :update_ci => %w{
                    dependencies:update_stable_channel_gems
                    dependencies:update_gemfile_lock
                    dependencies:update_omnibus_overrides
                    dependencies:update_omnibus_gemfile_lock
                    dependencies:update_acceptance_gemfile_lock
                  }

  desc "Update Gemfile.lock and all Gemfile.<platform>.locks."
  task :update_gemfile_lock do |t, rake_args|
    Rake::Task["bundle:update"].invoke
  end

  def gemfile_lock_task(task_name, dirs: [], other_platforms: true, leave_frozen: true)
    dirs.each do |dir|
      desc "Update #{dir}/Gemfile.lock."
      task task_name do |t, rake_args|
        extend BundleUtil
        puts ""
        puts "-------------------------------------------------------------------"
        puts "Updating #{dir}/Gemfile.lock ..."
        puts "-------------------------------------------------------------------"
        with_bundle_unfrozen(cwd: dir, leave_frozen: leave_frozen) do
          bundle "install", cwd: dir, delete_gemfile_lock: true
          if other_platforms
            # Include all other supported platforms into the lockfile as well
            platforms.each do |platform|
              bundle "lock", cwd: dir, platform: platform
            end
          end
        end
      end
    end
  end

  def berksfile_lock_task(task_name, dirs: [])
    dirs.each do |dir|
      desc "Update #{dir}/Berksfile.lock."
      task task_name do |t, rake_args|
        extend BundleUtil
        puts ""
        puts "-------------------------------------------------------------------"
        puts "Updating #{dir}/Berksfile.lock ..."
        puts "-------------------------------------------------------------------"
        if File.exist?("#{project_root}/#{dir}/Berksfile.lock")
          File.delete("#{project_root}/#{dir}/Berksfile.lock")
        end
        Dir.chdir("#{project_root}/#{dir}") do
          Bundler.with_clean_env do
            sh "bundle exec berks install"
          end
        end
      end
    end
  end

  include RakeDependenciesTaskHelpers

  gemfile_lock_task :update_omnibus_gemfile_lock, dirs: %w{omnibus}
  gemfile_lock_task :update_acceptance_gemfile_lock, dirs: %w{acceptance},
                                                     other_platforms: false, leave_frozen: false

  desc "Update gems to the versions specified by the stable channel."
  task :update_stable_channel_gems do |t, rake_args|
    extend BundleUtil
    puts ""
    puts "-------------------------------------------------------------------"
    puts "Updating Gemfile ..."
    puts "-------------------------------------------------------------------"

    # Modify the gemfile to pin to stable chef
    gemfile_path = File.join(project_root, "Gemfile")
    gemfile = IO.read(gemfile_path)
    update_gemfile_from_stable(gemfile, "chef", "chef", "v")
    # TODO: Uncomment this when push-job-client builds are passing again.
    # Right now, the latest version is pinned to a super old version of Chef
    # so it could be build standalone.
    # update_gemfile_from_stable(gemfile, "push-jobs-client", "opscode-pushy-client")

    if gemfile != IO.read(gemfile_path)
      puts "Writing modified #{gemfile_path} ..."
      IO.write(gemfile_path, gemfile)
    end
  end

  desc "Update omnibus overrides, including versions in version_policy.rb and latest version of gems: #{OMNIBUS_RUBYGEMS_AT_LATEST_VERSION.keys}."
  task :update_omnibus_overrides do |t, rake_args|
    puts ""
    puts "-------------------------------------------------------------------"
    puts "Updating omnibus_overrides.rb ..."
    puts "-------------------------------------------------------------------"

    # Generate the new overrides file
    overrides = "# DO NOT EDIT. Generated by \"rake dependencies\". Edit version_policy.rb instead.\n"

    # Replace the bundler and rubygems versions
    OMNIBUS_RUBYGEMS_AT_LATEST_VERSION.each do |override_name, gem_name|
      # Get the latest bundler version
      puts "Running gem list -r #{gem_name} ..."
      gem_list = `gem list -r #{gem_name}`
      unless gem_list =~ /^#{gem_name}\s*\(([^)]*)\)$/
        raise "gem list -r #{gem_name} failed with output:\n#{gem_list}"
      end

      # Emit it
      puts "Latest version of #{gem_name} is #{$1}"
      overrides << "override #{override_name.inspect}, version: #{$1.inspect}\n"
    end

    # Add explicit overrides
    OMNIBUS_OVERRIDES.each do |override_name, version|
      overrides << "override #{override_name.inspect}, version: #{version.inspect}\n"
    end

    # Write the file out (if changed)
    overrides_path = File.expand_path("../../omnibus_overrides.rb", __FILE__)
    if overrides != IO.read(overrides_path)
      puts "Overrides changed!"
      puts `git diff #{overrides_path}`
      puts "Writing modified #{overrides_path} ..."
      IO.write(overrides_path, overrides)
    end
  end
end
desc "Update all dependencies and check for outdated gems."
task :dependencies_ci => [ "dependencies:update_ci", "bundle:outdated" ]
task :dependencies => [ "dependencies:update" ]
task :update => [ "dependencies:update", "bundle:outdated" ]
