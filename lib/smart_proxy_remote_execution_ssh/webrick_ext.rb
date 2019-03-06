module SmartProxyRemoteExecutionSsh
  module WEBrickExt
    # An extension to ::WEBrick::HTTPRequest to expost the socket object for highjacking for cockpit
    module HTTPRequestExt
      def meta_vars
        super.merge('WEBRICK_SOCKET' => @socket)
      end
    end
  end
  ::WEBrick::HTTPRequest.send(:prepend, WEBrickExt::HTTPRequestExt)
end
