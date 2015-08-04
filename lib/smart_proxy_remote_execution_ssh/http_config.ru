# This plugin just adds new Dynflow actions to be triggered from the Foreman
map "/ssh" do
  run Proxy::RemoteExecution::Ssh::Api
end
