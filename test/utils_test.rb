require 'test_helper'
require 'stringio'
require 'tmpdir'
require 'smart_proxy_remote_execution_ssh/utils'

module Proxy::RemoteExecution
  class UtilsTest < Minitest::Test
    def setup
      super
      @original_home = ENV['HOME']
      @home = Dir.mktmpdir('rex-known-hosts-')
      ENV['HOME'] = @home
      @known_hosts = File.join(@home, '.ssh', 'known_hosts')
      FileUtils.mkdir_p(File.dirname(@known_hosts))
      @logger = Logger.new(File::NULL)
    end

    def teardown
      ENV['HOME'] = @original_home
      FileUtils.rm_rf(@home)
      super
    end

    def test_removes_only_the_matching_host
      File.write(@known_hosts, "host.example #{public_key}\nother.example #{public_key}\n")

      Utils.prune_known_hosts!('host.example', 22, @logger)

      assert_equal "other.example #{public_key}\n", File.read(@known_hosts)
    end

    def test_removes_a_hashed_host
      File.write(@known_hosts, "host.example #{public_key}\n")
      _stdout, stderr, status = Open3.capture3('ssh-keygen', '-H', '-f', @known_hosts)
      assert status.success?, stderr
      File.delete("#{@known_hosts}.old")
      assert_match(/\A\|1\|/, File.read(@known_hosts))

      Utils.prune_known_hosts!('host.example', 22, @logger)

      assert_empty File.read(@known_hosts)
    end

    def test_removes_only_the_requested_port
      File.write(@known_hosts, "host.example #{public_key}\n[host.example]:2222 #{public_key}\n")

      Utils.prune_known_hosts!('host.example', 2222, @logger)

      assert_equal "host.example #{public_key}\n", File.read(@known_hosts)
    end

    def test_leaves_an_unmatched_file_untouched
      content = "other.example #{public_key}\n"
      File.write(@known_hosts, content)

      Utils.prune_known_hosts!('host.example', 22, @logger)

      assert_equal content, File.read(@known_hosts)
      refute File.exist?("#{@known_hosts}.old")
    end

    def test_skips_an_absent_file
      Utils.prune_known_hosts!('host.example', 22, @logger)

      refute File.exist?(@known_hosts)
    end

    def test_warns_when_ssh_keygen_fails
      File.write(@known_hosts, "host.example #{public_key}\n")
      status = mock('status')
      status.stubs(:success?).returns(false)
      Open3.stubs(:capture3).returns(['', 'Permission denied', status])
      log_output = StringIO.new

      Utils.prune_known_hosts!('host.example', 22, Logger.new(log_output))

      assert_match(/Could not remove host.example from known_hosts: Permission denied/, log_output.string)
    end

    private

    def public_key
      return @public_key if @public_key

      key_file = File.join(@home, 'key')
      _stdout, stderr, status = Open3.capture3('ssh-keygen', '-q', '-t', 'ecdsa', '-b', '256', '-N', '', '-f', key_file)
      assert status.success?, stderr
      @public_key = File.read("#{key_file}.pub").split.first(2).join(' ')
    end
  end
end
