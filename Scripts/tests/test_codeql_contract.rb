#!/usr/bin/env ruby
require 'tmpdir'
require 'fileutils'
require 'open3'

root = File.expand_path('../..', __dir__)
gate = File.join(root, 'Scripts/check_codeql_contract.rb')
workflow = File.read(File.join(root, '.github/workflows/codeql.yml'))
config = File.read(File.join(root, '.github/dependabot.yml'))
cases = {
  'matched control' => [workflow, config, true],
  'mismatched analyze' => [workflow.sub(/(codeql-action\/analyze@)[0-9a-f]{40}/, '\\1' + '0' * 40), config, false],
  'paired update control' => [workflow.gsub(/(codeql-action\/(?:init|analyze)@)[0-9a-f]{40}/, '\\1' + '1' * 40), config, true],
  'missing analyze' => [workflow.gsub(/^.*uses: github\/codeql-action\/analyze@.*\n/, ''), config, false],
  'floating ref' => [workflow.sub(/(codeql-action\/init@)[0-9a-f]{40}/, '\\1v4'), config, false],
  'split version updates' => [workflow, config.sub('applies-to: version-updates', 'applies-to: security-updates'), false],
  'split security updates' => [workflow, config.sub('applies-to: security-updates', 'applies-to: version-updates'), false],
  'partial group' => [workflow, config.sub('github/codeql-action/*', 'github/codeql-action/init'), false],
}
Dir.mktmpdir('stream-codeql-contract-') do |scratch|
  FileUtils.mkdir_p(File.join(scratch, '.github/workflows'))
  cases.each do |name, (source, groups, should_pass)|
    File.write(File.join(scratch, '.github/workflows/codeql.yml'), source)
    File.write(File.join(scratch, '.github/dependabot.yml'), groups)
    output, status = Open3.capture2e('ruby', gate, scratch)
    abort "codeql test #{name}: unexpected result\n#{output}" unless status.success? == should_pass
  end
end
puts "codeql-contract tests: OK (#{cases.length} positive/negative controls)"
