#!/usr/bin/env ruby
require 'yaml'

def check_codeql_contract(root)
  workflow_path = File.join(root, '.github/workflows/codeql.yml')
  workflow = YAML.safe_load(File.read(workflow_path), aliases: true, filename: workflow_path)
  steps = workflow.fetch('jobs').values.flat_map { |job| job.fetch('steps', []) }
  actions = steps.map { |step| step['uses'] }.compact.select { |action| action.start_with?('github/codeql-action/') }
  refs = actions.map do |action|
    match = /\Agithub\/codeql-action\/([a-z-]+)@([0-9a-f]{40})\z/.match(action)
    raise 'CodeQL actions must pin a complete immutable SHA' unless match
    [match[1], match[2]]
  end
  raise 'CodeQL init and analyze must both exist' unless %w[init analyze].all? { |name| refs.any? { |pair| pair[0] == name } }
  raise 'CodeQL actions must all use the same version' unless refs.map(&:last).uniq.length == 1

  config_path = File.join(root, '.github/dependabot.yml')
  config = YAML.safe_load(File.read(config_path), aliases: true, filename: config_path)
  entries = config.fetch('updates').select { |entry| entry['package-ecosystem'] == 'github-actions' && entry['directory'] == '/' }
  raise 'One root github-actions update entry is required' unless entries.length == 1
  groups = entries.first.fetch('groups', {}).values
  %w[version-updates security-updates].each do |kind|
    raise "CodeQL #{kind} must group every coupled action" unless groups.any? { |group|
      group.fetch('applies-to', 'version-updates') == kind &&
        group['patterns'] == ['github/codeql-action/*'] &&
        group.fetch('exclude-patterns', []).empty? &&
        (!group.key?('update-types') || group['update-types'].sort == %w[major minor patch])
    }
  end
  puts "codeql-contract: OK (#{actions.length} coupled actions; version/security groups)"
end

if $PROGRAM_NAME == __FILE__
  begin
    raise 'Usage: ruby Scripts/check_codeql_contract.rb [repository-root]' if ARGV.length > 1
    check_codeql_contract(ARGV.first || File.expand_path('..', __dir__))
  rescue KeyError, Psych::Exception, RuntimeError => error
    warn "codeql-contract: #{error.message}"
    exit 1
  end
end
