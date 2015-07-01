require 'nokogiri'
require 'open-uri'
require 'nori'

module EasyUpnp
  class DeviceControlPoint
    attr_reader :service_methods

    def initialize(client, service_type, definition_url, options)
      @client = client
      @service_type = service_type
      @options = options

      service_methods = []
      definition = Nokogiri::XML(open(definition_url))
      definition.remove_namespaces!

      definition.xpath('//actionList/action').map do |action|
        service_methods.push define_action(action)
      end

      @service_methods = service_methods
    end

    private

    def define_action(action)
      action = Nori.new.parse(action.to_xml)['action']
      action_name = action['name']
      args = action['argumentList']['argument']
      args = [args] unless args.is_a? Array

      input_args = args.
          reject { |x| x['direction'] != 'in' }.
          map { |x| x['name'].to_sym }
      output_args = args.
          reject { |x| x['direction'] != 'out' }.
          map { |x| x['name'].to_sym }

      define_singleton_method(action['name']) do |args_hash = {}|
        if !args_hash.is_a? Hash
          raise RuntimeError.new "Input arg must be a hash"
        elsif
          (args_hash.keys - input_args).any?
          raise RuntimeError.new "Unsupported arguments: #{(args_hash.keys - input_args)}." <<
                                     " Supported args: #{input_args}"
        end

        attrs = {
            soap_action: "#{@service_type}##{action_name}",
            attributes: {
                :'xmlns:u' => @service_type
            },
        }.merge(@options)

        response = @client.call action['name'], attrs do
          message(args_hash)
        end

        # Response is usually wrapped in <#{ActionName}Response></>. For example:
        # <BrowseResponse>...</BrowseResponse>. Extract the body since consumers
        # won't care about wrapper stuff.
        if response.body.keys.count > 1
          raise RuntimeError.new "Unexpected keys in response body: #{response.body.keys}"
        end
        result = response.body.first[1]
        output = {}

        # Keys returned by savon are underscore style. Convert them to camelcase.
        output_args.map do |arg|
          output[arg] = result[underscore(arg.to_s).to_sym]
        end

        output
      end

      action['name']
    end

    # This is included in ActiveSupport, but don't want to pull that in for just this method...
    def underscore s
      s.gsub(/::/, '/').
          gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
          gsub(/([a-z\d])([A-Z])/, '\1_\2').
          tr("-", "_").
          downcase
    end
  end
end