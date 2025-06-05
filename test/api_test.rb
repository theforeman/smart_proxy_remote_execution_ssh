require 'test_helper'
require 'tempfile'
require 'smart_proxy_remote_execution_ssh/actions/pull_script'
require 'smart_proxy_remote_execution_ssh/job_storage'
require 'smart_proxy_dynflow/otp_manager'

KNOWN_HOSTS = <<EOF
c7s62.lxc,192.168.122.200 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFAMEcFeBHeY8AD7xw2weF6vIE0BZXBk0oOm7sM+iJ4ld7BvQDf0mF6EeyyjzDmMUTyR2q9q0OdYiTbyEiKHQF4=
centos7-sat62.sn,192.168.122.237 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBF34XaWrMrhjctlpuKS+Y6wIgHb/N4QHb9eHBNd2R+ka1sFiG3b0/zS4PR77cMt1K/qGQqi0OngWksGE2AAy+K8=
centos7-sat63.sn,192.168.122.49 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBF34XaWrMrhjctlpuKS+Y6wIgHb/N4QHb9eHBNd2R+ka1sFiG3b0/zS4PR77cMt1K/qGQqi0OngWksGE2AAy+K8=
192.168.122.62 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBG+IQJd+yLbmalsj0vciWPyAbx8vDHVy0wMTYR9Jq2ZD6zgcIPOwtouo/7AgUt393SRKKvGFrltCHu5divMurBA=
192.168.122.63 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPIJnNWAwU7Xs+imiZr2QJ5k0+QrO+XiZZ6cOivawe/+Cn6zvFgZq+b45JcLo1FRucCdhs6oWjSRrXqsyg9ptPM=
foreman-katello-115,192.168.122.235 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIJ9I2Sn9dX/uZXqwYvXUgFx9sgugEhBZz+DgKjqRmkwCoymhXIAamz97Pgtt50PRnNAfIDgwhWDzPJycHIiEH4=
192.168.122.15 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBJJdUJbl8HNYKzpALdhheiprRPXsHFl007XxZwVerY2QD0Sr2kNrwvWMRA9gGOGI9pMJ7IjGdRHQcQbWDV5Ipbo=
192.168.122.233 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHD00Agl4EsbdMIHGo8iGB0Sw0wlVG+vQqi1FZ4Pui9t2zvb2QATuA+PtN9xJE9KLBeZPWyFbwNXZn588k0crng=
192.168.122.13 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKLI/Ndyu1qRc/URRY0vDuXSTmlX/kowgK7FqC4iTw4bGYFVDILammcrx3/FYEF0PPSlj98L0FcL08JMDnrwMtU=
192.168.122.153 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHS5GQueYd2LY859G7fNSpu9Q10ffIh+oy/4x6/WrbXx1tIUYSPDQ/FyKGc4ktAdpV3UZRkWyUEGKuhTq81cPrI=
192.168.122.80 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCXET6dCMjs19MS9fLmabIHF+EfoDpbGenVEizzJIaoLpy9Vnxgqy7EjqCWImSfyFMbG99hSSGKeIXRa/WM/E9s=
192.168.122.151 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCbcV6+ZBnseP5MR2hOFmQqpEiepNqVfSJItx+rVPxOJQPri98LpMCT5HpvbP3ZYN/8THtj9sO3RL94EKtuKap8=
192.168.122.83 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGurYj+BoscTiCNx/WUURwMUQKgvYu2za6mnJCMTdWCuCpeo+xeaeeZioG25JDAKa22EcJlCZnvSlzyXNVen3QQ=
[192.168.122.83]:2222 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBO5nEM475GXY9S+QKydacP0i2DiH2JU7ogs0cDHvHohiu401aKnLAA6Ggw8DlO8kscxYd8FVrkp0A5gj44vNTM=
EOF

module Proxy::RemoteExecution::Ssh
  class ApiTest < Minitest::Spec
    include Rack::Test::Methods

    let(:app) { Proxy::RemoteExecution::Ssh::Api.new }

    def setup
      super
      dispatcher = mock
      dispatcher.stubs(:running)
      ::Proxy::RemoteExecution::Ssh::MQTT::Dispatcher.stubs(:instance).returns(dispatcher)
    end

    describe '/pubkey' do
      it 'returns the content of the public key' do
        get '/pubkey'
        _(last_response.body).must_equal '===public-key==='
      end
    end

    describe '/ca_pubkey' do
      it 'returns the content of the CA public key' do
        get '/ca_pubkey'
        _(last_response.body).must_equal '===ca-public-key==='
      end
    end

    describe 'job storage' do
      let(:uuid) { SecureRandom.uuid }
      let(:execution_plan_uuid) { SecureRandom.uuid }
      let(:run_step_id) { 1 }
      let(:hostname) { 'something.somewhere.com' }
      let(:content) { 'content' }

      before do
        store = Proxy::RemoteExecution::Ssh::JobStorage.new
        Proxy::RemoteExecution::Ssh.stubs(:job_storage).returns(store)
        Proxy::RemoteExecution::Ssh
          .job_storage
          .store_job(hostname,
                     execution_plan_uuid,
                     run_step_id,
                     content,
                     uuid: uuid)
      end

      describe '/jobs/update' do
        it 'returns 403 if HTTPS is used and no cert is provided' do
          post '/jobs/12345/update', {}, 'HTTPS' => 1
          _(last_response.status).must_equal 403
        end

        it 'returns 403 if wrong credentials are supplied' do
          auth = Proxy::Dynflow::OtpManager.tokenize('username', 'password')
          post '/jobs/12345/update', {}, 'HTTP_AUTHORIZATION' => "Basic #{auth}"
          _(last_response.status).must_equal 403
        end

        it 'returns 404 if job does not exist' do
          Proxy::RemoteExecution::Ssh::Api.any_instance.expects(:https_cert_cn).returns(hostname)
          post '/jobs/12345/update', {}
          _(last_response.status).must_equal 404
        end

        it 'dispatches an event' do
          Proxy::RemoteExecution::Ssh::Api.any_instance.expects(:https_cert_cn).returns(hostname)
          fake_world = mock
          fake_world.expects(:event) do |task_id, step_id, _payload|
            task_id == execution_plan_uuid && step_id == run_step_id
          end
          Proxy::RemoteExecution::Ssh::Api.any_instance.expects(:world).returns(fake_world)

          post "/jobs/#{uuid}/update", '{}'
          _(last_response.status).must_equal 200
        end
      end

      describe '/jobs/:job_uuid' do
        it 'returns 403 if HTTPS is used and no cert is provided' do
          get '/jobs/12345', {}, 'HTTPS' => 1
          _(last_response.status).must_equal 403
        end

        it 'returns 403 when wrong credentials are supplied' do
          auth = Proxy::Dynflow::OtpManager.tokenize('username', 'password')
          get '/jobs/12345', {}, 'HTTP_AUTHORIZATION' => "Basic #{auth}"
          _(last_response.status).must_equal 403
        end

        it 'returns content if there is some and notifies the action' do
          Proxy::RemoteExecution::Ssh::Api.any_instance.expects(:https_cert_cn).returns(hostname)
          fake_world = mock
          fake_world.expects(:event).with(execution_plan_uuid, run_step_id, Actions::PullScript::JobDelivered)
          Proxy::RemoteExecution::Ssh::Api.any_instance.expects(:world).returns(fake_world)

          get "/jobs/#{uuid}"
          _(last_response.status).must_equal 200
          _(last_response.body).must_equal content
          assert_nil last_response.headers['X-Foreman-Effective-User']
        end

        it 'returns 404 if there is no content' do
          Proxy::RemoteExecution::Ssh::Api.any_instance.expects(:https_cert_cn).returns(hostname)

          get '/jobs/12345'
          _(last_response.status).must_equal 404
        end

        it 'includes effective user header' do
          uuid = SecureRandom.uuid
          Proxy::RemoteExecution::Ssh
            .job_storage
            .store_job(hostname,
                       execution_plan_uuid,
                       run_step_id,
                       content,
                       uuid: uuid,
                       effective_user: 'toor')

          Proxy::RemoteExecution::Ssh::Api.any_instance.expects(:https_cert_cn).returns(hostname)
          fake_world = mock
          fake_world.stubs(:event)
          Proxy::RemoteExecution::Ssh::Api.any_instance.expects(:world).returns(fake_world)

          get "/jobs/#{uuid}"
          _(last_response.status).must_equal 200
          _(last_response.headers['X-Foreman-Effective-User']).must_equal 'toor'
        end
      end

      describe '/jobs' do
        it 'returns 403 if HTTPS is used and no cert is provided' do
          get '/jobs', {}, 'HTTPS' => 1
          _(last_response.status).must_equal 403
        end

        it 'returns a list of job uuids for a given host' do
          Proxy::RemoteExecution::Ssh::Api.any_instance.expects(:https_cert_cn).returns(hostname)
          Proxy::RemoteExecution::Ssh
            .job_storage
            .store_job('another.host', SecureRandom.uuid, 1, 'hello')

          get '/jobs'
          _(last_response.status).must_equal 200
          data = MultiJson.load(last_response.body)
          _(data).must_equal [uuid]
        end
      end
    end
  end
end
