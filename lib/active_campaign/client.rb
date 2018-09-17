require 'active_campaign/configurable'
require 'active_campaign/client/contacts'
require 'active_campaign/client/lists'
require 'active_campaign/client/campaigns'
require 'httpi'
require 'hashie'

module ActiveCampaign
  class Client
    include ActiveCampaign::Configurable
    include ActiveCampaign::Client::Contacts
    include ActiveCampaign::Client::Lists
    include ActiveCampaign::Client::Campaigns

    def initialize(options = {})
      ActiveCampaign::Configurable.keys.each do |key|
        instance_variable_set(:"@#{key}", options[key] ||
          ActiveCampaign.instance_variable_get(:"@#{key}"))
      end
    end

    # Compares client options to a Hash of requested options
    #
    # @param opts [Hash] Options to compare with current client options
    # @return [Boolean]
    def same_options?(opts)
      opts.hash == options.hash
    end

      # Make a HTTP GET request
    #
    # @param url [String] The path, relative to {#api_endpoint}
    # @param options [Hash] Query and header params for request
    # @return [Hash]
    def get(api_method, options = {})
      request :get, api_method, options
    end

    # Make a HTTP POST request
    #
    # @param url [String] The path, relative to {#api_endpoint}
    # @param options [Hash] Body and header params for request
    # @return [Hash]
    def post(api_method, options = {})
      request :post, api_method, options
    end

    private

      def request(method, api_method, data)
        req = create_request method, api_method, data

        response = HTTPI.send(method, req)
        response = JSON.parse(response.body)
        normalize(response)
      end


      def create_request(method, api_method, options = {})
        request = HTTPI::Request.new url: File.join(api_endpoint, api_path)

        request.headers              = request_headers
        request.auth.ssl.verify_mode = :none
        request.query                = query(method, api_method, options)
        request.body                 = body(method, api_method, options)

        request
      end

      def query(method, api_method, options = {})
        q = options.delete(:query) { Hash.new }
        q.merge!({
          :api_key => api_key,
          :api_action => api_method.to_s,
          :api_output => api_output
        })

        if method == :get
          q.merge!(options)
        end

        q
      end

      def body(method, api_method, options = {})
        return nil unless method == :post

        fields = options.delete(:fields){ Hash.new }
        options[:field] = fields.inject({}) do |hash, (k,v)|
          hash.merge("%#{k}%,0" => v)
        end

        options.to_query
      end

      def normalize(response)
        keys, values = keys_values(response)

        if keys.all?{|key| is_numeric?(key) }
          response[:results] = values
          keys.each do |key|
            response.delete(key)
          end
        end

        if mash
          Hashie::Mash.new response
        else
          ActiveSupport::HashWithIndifferentAccess.new(response)
        end

      end

      def is_numeric?(string)
        string.to_s.match(/\A[+-]?\d+\Z/) == nil ? false : true
      end

      def keys_values(response)
        results = results(response)
        [results.keys, results.values]
      end

      def results(response)
        response.reject{|k,v| %w(result_code result_message result_output).include?(k) }
      end

      def request_headers
        {
          'User-Agent' => user_agent,
          'Content-Type' => 'application/x-www-form-urlencoded'
        }
      end
  end
end
