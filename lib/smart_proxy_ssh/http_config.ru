map "/ssh" do
  run Proxy::Ssh::Api
end

map "/dynflow" do
  run Proxy::Ssh.dynflow.web_console
end
