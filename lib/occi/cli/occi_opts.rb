require 'ostruct'
require 'optparse'
require 'uri'
require 'base64'

module Occi::Cli

  class OcciOpts

    AUTH_METHODS = [:x509, :basic, :digest, :none].freeze
    MEDIA_TYPES = ["application/occi+json", "application/occi+xml", "text/plain,text/occi", "text/plain"].freeze
    ACTIONS = [:list, :describe, :create, :delete, :trigger].freeze
    LOG_OUTPUTS = [:stdout, :stderr].freeze
    ALLOWED_CONTEXT_VARS = [:public_key, :user_data].freeze

    MIXIN_REGEXP = /^(https?:\/\/\S+?)#(\S+)$/
    CONTEXT_REGEXP = ATTR_REGEXP = /^(.+?)=(.+)$/

    def self.parse(args, test_env = false)

      @@quiet = test_env

      options = OpenStruct.new
      
      options.debug = false
      options.verbose = false
      
      options.log = {}
      options.log[:out] = STDERR
      options.log[:level] = Occi::Log::WARN

      options.filter = nil
      options.dump_model = false

      options.endpoint = "https://localhost:3300/"
      
      options.auth = {}
      options.auth[:type] = "none"
      options.auth[:user_cert] = ENV['HOME'] + "/.globus/usercred.pem"
      options.auth[:ca_path] = "/etc/grid-security/certificates"
      options.auth[:username] = "anonymous"
      options.auth[:ca_file] = nil
      options.auth[:voms] = nil

      options.output_format = :plain

      options.mixins = Occi::Core::Mixins.new
      options.links = nil
      options.attributes = nil
      options.context_vars = nil
      
      # TODO: change media type back to occi+json after the rOCCI-server update
      #options.media_type = "application/occi+json"
      options.media_type = "text/plain,text/occi"

      opts = OptionParser.new do |opts|
        opts.banner = %{Usage: occi [OPTIONS]

Examples:

occi --endpoint https://localhost:3300/ --action list --resource os_tpl --auth x509

occi --endpoint https://localhost:3300/ --action list --resource resource_tpl --auth x509

occi --endpoint https://localhost:3300/ --action describe --resource os_tpl#debian6 --auth x509

occi --endpoint https://localhost:3300/ --action create --resource compute --mixin os_tpl#debian6 --mixin resource_tpl#small --attribute title="My rOCCI VM" --auth x509

occi --endpoint https://localhost:3300/ --action delete --resource /compute/65sd4f654sf65g4-s5fg65sfg465sfg-sf65g46sf5g4sdfg --auth x509}

        opts.separator ""
        opts.separator "Options:"

        opts.on("-e",
                "--endpoint URI",
                String,
                "OCCI server URI, defaults to '#{options.endpoint}'") do |endpoint|
          options.endpoint = URI(endpoint).to_s
        end

        opts.on("-n",
                "--auth METHOD",
                AUTH_METHODS,
                "Authentication method, defaults to '#{options.auth[:type]}'") do |auth|
          options.auth[:type] = auth.to_s
        end

        opts.on("-u",
                "--username USER",
                String,
                "Username for basic or digest authentication, defaults to '#{options.auth[:username]}'") do |username|
          options.auth[:username] = username
        end

        opts.on("-p",
                "--password PASSWORD",
                String,
                "Password for basic, digest and x509 authentication") do |password|
          options.auth[:password] = password
          options.auth[:user_cert_password] = password
        end

        opts.on("-c",
                "--ca-path PATH",
                String,
                "Path to CA certificates directory, defaults to '#{options.auth[:ca_path]}'") do |ca_path|
          raise ArgumentError, "Path specified in --ca-path is not a directory!" unless File.directory? ca_path
          raise ArgumentError, "Path specified in --ca-path is not readable!" unless File.readable? ca_path

          options.auth[:ca_path] = ca_path
        end

        opts.on("-f",
                "--ca-file PATH",
                String,
                "Path to CA certificates in a file") do |ca_file|
          raise ArgumentError, "File specified in --ca-file is not a file!" unless File.file? ca_file
          raise ArgumentError, "File specified in --ca-file is not readable!" unless File.readable? ca_file

          options.auth[:ca_file] = ca_file
        end

        opts.on("-F",
                "--filter CATEGORY",
                String,
                "Category type identifier to filter categories from model, must be used together with the -m option") do |filter|
          options.filter = filter
        end

        opts.on("-x",
                "--user-cred FILE",
                String,
                "Path to user's x509 credentials, defaults to '#{options.auth[:user_cert]}'") do |user_cred|
          raise ArgumentError, "File specified in --user-cred is not a file!" unless File.file? user_cred
          raise ArgumentError, "File specified in --user-cred is not readable!" unless File.readable? user_cred

          options.auth[:user_cert] = user_cred
        end

        opts.on("-X",
                "--voms",
                "Using VOMS credentials; modifies behavior of the X509 authN module") do |voms|

          options.auth[:voms] = true
        end

        opts.on("-y",
                "--media-type MEDIA_TYPE",
                MEDIA_TYPES,
                "Media type for client <-> server communication, defaults to '#{options.media_type}'") do |media_type|
          options.media_type = media_type
        end

        opts.on("-r",
                "--resource RESOURCE",
                String,
                "Resource to be queried (e.g. network, compute, storage etc.), required") do |resource|
          options.resource = resource
        end

        opts.on("-t",
                "--attribute ATTRS",
                Array,
                "Comma separated attributes for new resources such as title=\"Name\", required") do |attributes|
          options.attributes ||= {}

          attributes.each do |attribute|
            ary = ATTR_REGEXP.match(attribute).to_a.drop 1
            raise ArgumentError, "Attribute must always contain ATTR=VALUE pairs!" unless ary.length == 2

            options.attributes[ary[0].to_sym] = ary[1]
          end
        end

        opts.on("-T",
                "--context CTX_VARS",
                Array,
                "Comma separated context variables for new compute resources such as public_key=\"ssh-rsa dfsdf...adfdf== user@localhost\"") do |context|
          options.context_vars ||= {}

          context.each do |ctx|
            ary = CONTEXT_REGEXP.match(ctx).to_a.drop 1
            raise ArgumentError, "Context variables must always contain ATTR=VALUE pairs!" unless ary.length == 2

            symbol = ary[0].to_sym
            if ALLOWED_CONTEXT_VARS.include?(symbol)
              context_data = ary[1]
              if context_data.gsub!(/^file:\/\//,'')
                raise 'File does not exist! #{context_data}' unless File.exist? context_data
                context_data = File.read(context_data)
              end

              if symbol == :user_data
                context_data = Base64.encode64(context_data).gsub("\n", '')
              end

              options.context_vars[symbol] = context_data.strip
            else
              Occi::Log.warn "Only #{ALLOWED_CONTEXT_VARS.join(', ')} context variables are supported! Skipping #{ary[0].to_s} ..."
            end
          end
        end

        opts.on("-a",
                "--action ACTION",
                ACTIONS,
                "Action to be performed on the resource, required") do |action|
          options.action = action
        end

        opts.on("-M",
                "--mixin NAME",
                Array,
                "Type and name of the mixin as SCHEME#NAME (e.g. http://localhost/os_tpl#monitoring, http://localhost/resource_tpl#medium)") do |mixins|
          options.mixins ||= Occi::Core::Mixins.new

          mixins.each do |mixin|
            parts = MIXIN_REGEXP.match(mixin).to_a.drop(1)
            raise "Unknown mixin format #{mixin.inspect}! Use SCHEME#NAME!" unless parts.length == 2

            options.mixins << Occi::Core::Mixin.new("#{parts[0]}#", parts[1])
          end
        end

        opts.on("-j",
                "--link URI",
                Array,
                "Link specified resource to the resource being created, only for action CREATE and resource COMPUTE") do |links|
          options.links ||= []

          links.each do |link|
            link_relative_path = URI(link).path
            raise ArgumentError, "Specified link URI is not valid!" unless link_relative_path.start_with? '/'
            options.links << link_relative_path
          end
        end

        opts.on("-g",
                "--trigger-action TRIGGER",
                String,
                "Action to be triggered on the resource") do |trigger_action|
          options.trigger_action = trigger_action
        end

        opts.on("-l",
                "--log-to OUTPUT",
                LOG_OUTPUTS,
                "Log to the specified device, defaults to 'STDERR'") do |log_to|
          options.log[:out] = STDOUT if log_to == :stdout or log_to == :STDOUT
        end

        opts.on("-o",
                "--output-format FORMAT",
                Occi::Cli::ResourceOutputFactory.allowed_formats,
                "Output format, defaults to human-readable 'plain'") do |output_format|
          options.output_format = output_format
        end

        opts.on_tail("-m",
                     "--dump-model",
                     "Contact the endpoint and dump its model") do |dump_model|
          options.dump_model = dump_model
        end

        opts.on_tail("-d",
                     "--debug",
                     "Enable debugging messages") do |debug|
          options.debug = debug
          options.log[:level] = Occi::Log::DEBUG
        end

        opts.on_tail("-b",
                     "--verbose",
                     "Be more verbose, less intrusive than debug mode") do |verbose|
          options.verbose = verbose
          options.log[:level] = Occi::Log::INFO unless options.log[:level] == Occi::Log::DEBUG
        end

        opts.on_tail("-h",
                     "--help",
                     "Show this message") do
          if @@quiet
            exit true
          else
            puts opts
            exit! true
          end
        end

        opts.on_tail("-v",
                     "--version",
                     "Show version") do
          if @@quiet
            exit true
          else
            if options.debug
              puts "CLI:  #{Occi::Cli::VERSION}"
              puts "API:  #{Occi::Api::VERSION}"
              puts "Core: #{Occi::VERSION}"
            else
              puts Occi::Cli::VERSION
            end
            exit! true
          end
        end
      end

      begin
        opts.parse!(args)
      rescue Exception => ex
        if @@quiet
          exit false
        else
          puts ex.message.capitalize
          puts opts
          exit!
        end
      end

      check_restrictions options, opts

      options
    end

    private

    def self.check_restrictions(options, opts)
      if !options.dump_model && options.filter
        if @@quiet
          exit false
        else
          puts "You cannot use '--filter' without '--dump-model'!"
          puts opts
          exit!
        end
      end

      if options.voms && options.auth[:type] != "x509"
        if @@quiet
          exit false
        else
          puts "You cannot use '--voms' without '--auth x509'!"
          puts opts
          exit!
        end
      end

      return if options.dump_model

      mandatory = []

      if options.action == :trigger
        mandatory << :trigger_action
      end

      if options.action == :create
        if options.links
          mandatory << :links
        else
          mandatory << :mixins
        end

        mandatory << :attributes
        check_attrs = true
      end

      mandatory.concat [:resource, :action]

      check_hash options, mandatory, opts

      if check_attrs
        mandatory = [:title]
        check_hash options.attributes, mandatory, opts
      end
    end

    def self.check_hash(hash, mandatory, opts)
      unless hash.is_a?(Hash)
        hash = hash.marshal_dump
      end

      missing = mandatory.select{ |param| hash[param].nil? }
      unless missing.empty?
        if @@quiet
          exit false
        else
          puts "Missing required arguments: #{missing.join(', ')}"
          puts opts
          exit!
        end
      end
    end
  end

end