module Coinbase
  module Exchange
    # Net-HTTP adapter
    class NetHTTPClient < APIClient
      def initialize(api_key = '', api_secret = '', api_pass = '', options = {})
        super(api_key, api_secret, api_pass, options)
        @conn = Net::HTTP.new(@api_uri.host, @api_uri.port)
        if @api_uri.scheme == 'https'
          # options_mask = OpenSSL::SSL::OP_NO_SSLv2 + OpenSSL::SSL::OP_NO_SSLv3 + OpenSSL::SSL::OP_NO_COMPRESSION
          @conn.use_ssl = true 
          # @conn.verify_mode = OpenSSL::SSL::VERIFY_PEER
          # @conn.ssl_options = options_mask
        end
        # @conn.cert_store = self.class.whitelisted_certificates
        # @conn.ssl_version = :TLSv1_2
      end

      def auth_headers!(req, method = '', path = '', body = nil)
        req_ts = Time.now.utc.to_i.to_s
        signature = Base64.encode64(
          OpenSSL::HMAC.digest(
            'sha256', Base64.decode64(@api_secret).strip,
            "#{req_ts}#{method}#{path}#{body}"
          )
        ).strip

        req['Content-Type'] = 'application/json'
        req['CB-ACCESS-TIMESTAMP'] = req_ts
        req['CB-ACCESS-PASSPHRASE'] = @api_pass
        req['CB-ACCESS-KEY'] = @api_key
        req['CB-ACCESS-SIGN'] = signature
        req
      end

      private

      def http_verb(method, path, body = nil)
        case method
        when 'GET' then req = Net::HTTP::Get.new(path)
        when 'POST' then req = Net::HTTP::Post.new(path)
        when 'DELETE' then req = Net::HTTP::Delete.new(path)
        else fail
        end

        req.body = body if method != 'GET'
        req = auth_headers!(req, method, path, body)

        resp = @conn.request(req)
        case resp.code
        when "200" then yield(NetHTTPResponse.new(resp))
        when "400" then fail BadRequestError, resp.body
        when "401" then fail NotAuthorizedError, resp.body
        when "403" then fail ForbiddenError, resp.body
        when "404" then fail NotFoundError, resp.body
        when "429" then fail RateLimitError, resp.body
        when "500" then fail InternalServerError, resp.body
        end
        resp.body
      end
    end

    # Net-Http response object
    class NetHTTPResponse < APIResponse
      def body
        @response.body
      end

      def headers
        out = @response.to_hash.map do |key, val|
          [ key.upcase.gsub('_', '-'), val.count == 1 ? val.first : val ]
        end
        out.to_h
      end

      def status
        @response.code.to_i
      end
    end
  end
end
