require 'rubygems'
require 'bundler/setup'

require 'rspec'

begin
  # Only load this on ruby 2.x
  if RUBY_VERSION =~ /^2\./
    require 'allocation_counter/rspec'
  end
rescue LoadError
end

# Trigger hard-crash if C-ext is missing
ENV["SKYLIGHT_REQUIRED"] = "true"

require 'yaml'
require 'skylight'
require 'timecop'
require 'beefcake'

# Begin Probed libraries

begin
  require 'excon'
  require 'skylight/probes/excon'
rescue LoadError
end

require 'net/http'
require 'skylight/probes/net_http'

# End Probed Libraries


# Begin Normalize Libraries

begin
  require 'moped'
rescue LoadError
end

# End Normalize Libraries

Dir[File.expand_path('../support/*.rb', __FILE__)].each { |f| require f }

all_probes = %w(Excon Net::HTTP)
installed_probes = Skylight::Probes.installed.keys
skipped_probes = all_probes - installed_probes

puts "Testing probes: #{installed_probes.join(", ")}" unless installed_probes.empty?
puts "Skipping probes: #{skipped_probes.join(", ")}"  unless skipped_probes.empty?

RSpec.configure do |config|
  unless defined?(AllocationCounter)
    config.filter_run_excluding allocations: true
  end

  unless skipped_probes.empty?
    args = {}

    skipped_probes.each do |p|
      probe_name = p.downcase.gsub('::', '_')
      args["#{probe_name}_probe".to_sym] = true
    end

    config.filter_run_excluding args
  end

  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.include SpecHelper

  original_wd   = Dir.pwd
  original_home = ENV['HOME']

  config.before :each do
    Skylight::Util::Clock.default = SpecHelper::TestClock.new

    if File.exist?(tmp)
      FileUtils.rm_rf tmp
    end

    FileUtils.mkdir_p(tmp)
    Dir.chdir(tmp)
    ENV['HOME'] = tmp.to_s
  end

  config.before :each, http: true do
    start_server
  end

  config.after :each do
    begin
      cleanup_all_spawned_workers
    ensure
      Dir.chdir original_wd
      ENV['HOME'] = original_home
    end
  end

  config.after :each do
    # Reset the starting paths
    Skylight::Probes.instance_variable_set(:@require_hooks, {})

    # Remove the ProbeTestClass if it exists so that the probe won't find it
    if defined?(SpecHelper::ProbeTestClass)
      SpecHelper.send(:remove_const, :ProbeTestClass)
    end
  end

end
