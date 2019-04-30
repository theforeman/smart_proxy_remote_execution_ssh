module SmartProxyRemoteExecutionSsh
  module WEBrickExt
    # An extension to ::WEBrick::HTTPRequest to expost the socket object for highjacking for cockpit
    module HTTPRequestExt
      def meta_vars
        super.merge('ext.hijack!' => -> {
                      # This stops Webrick from sending its own reply.
                      @request_line = nil;
                      # This stops Webrick from trying to read the next request on the socket.
                      @keep_alive = false;
                      return @socket;
                    })
      end
    end
  end
  ::WEBrick::HTTPRequest.send(:prepend, WEBrickExt::HTTPRequestExt)
end
