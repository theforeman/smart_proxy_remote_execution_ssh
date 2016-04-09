require 'rake'
require 'rake/testtask'

desc 'Default: run unit tests.'
task :default => :test

namespace :test do
  desc 'Test Ssh plugin.'
  Rake::TestTask.new(:api) do |t|
    t.libs << '.'
    t.libs << 'lib'
    t.libs << 'test/api'
    t.test_files = FileList['test/api/*_test.rb']
    t.verbose = true
  end

  desc 'Test Ssh plugin.'
  Rake::TestTask.new(:core) do |t|
    t.libs << '.'
    t.libs << 'lib'
    t.libs << 'test/core'
    t.test_files = FileList['test/core/*_test.rb']
    t.verbose = true
  end
end

task :test do
  Rake::Task['test:api'].invoke
  Rake::Task['test:core'].invoke
end

require 'rubocop/rake_task'

desc 'Run RuboCop on the lib directory'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.patterns = ['lib/**/*.rb', 'test/**/*.rb']
  task.fail_on_error = false
end
