module Aptible
  module CLI
    module Subcommands
      module Apps
        def self.included(thor)
          thor.class_eval do
            include Helpers::App
            include Helpers::Environment
            include Helpers::Token

            desc 'apps', 'List all applications'
            option :environment
            def apps
              scoped_environments(options).each do |env|
                say "=== #{env.handle}"
                env.apps.each do |app|
                  say app.handle
                end
                say ''
              end
            end

            desc 'apps:create HANDLE', 'Create a new application'
            option :environment
            define_method 'apps:create' do |handle|
              environment = ensure_environment(options)
              app = environment.create_app(handle: handle)

              if app.errors.any?
                raise Thor::Error, app.errors.full_messages.first
              else
                say "App #{handle} created!"
                say "Git remote: #{app.git_repo}"
              end
            end

            desc 'apps:scale SERVICE ' \
                 '[--container-count COUNT] [--container-size SIZE_MB]',
                 'Scale a service'
            app_options
            option :container_count, type: :numeric
            option :container_size, type: :numeric
            option :size, type: :numeric,
                          desc: 'DEPRECATED, use --container-size'
            define_method 'apps:scale' do |type, *more|
              app = ensure_app(options)
              service = app.services.find { |s| s.process_type == type }

              container_count = options[:container_count]
              container_size = options[:container_size]

              # There are two legacy options we have to process here:
              # - We used to accept apps:scale SERVICE COUNT
              # - We used to accept --size
              case more.size
              when 0
                # Noop
              when 1
                if container_count.nil?
                  m = yellow('Passing container count as a positional ' \
                             'argument is deprecated, use --container-count')
                  $stderr.puts m
                  container_count = Integer(more.first)
                else
                  raise Thor::Error, 'Container count was passed via both ' \
                                     'the --container-count keyword argument ' \
                                     'and a positional argument. ' \
                                     'Use only --container-count to proceed.'
                end
              else
                # Unfortunately, Thor does not want to let us easily hook into
                # its usage formatting, so we have to work around it here.
                command = thor.commands.fetch('apps:scale')
                error = ArgumentError.new
                args = [type] + more
                thor.handle_argument_error(command, error, args, 1)
              end

              if options[:size]
                if container_size.nil?
                  m = yellow('Passing container size via the --size keyword ' \
                             'argument is deprecated, use --container-size')
                  $stderr.puts m
                  container_size = options[:size]
                else
                  raise Thor::Error, 'Container size was passed via both ' \
                                     '--container-size and --size. ' \
                                     'Use only --container-size to proceed.'
                end
              end

              if container_count.nil? && container_size.nil?
                raise Thor::Error,
                      'Provide at least --container-count or --container-size'
              end

              if service.nil?
                valid_types = if app.services.empty?
                                'NONE (deploy the app first)'
                              else
                                app.services.map(&:process_type).join(', ')
                              end
                raise Thor::Error, "Service with type #{type} does not " \
                                   "exist for app #{app.handle}. Valid " \
                                   "types: #{valid_types}."
              end

              # We don't validate any parameters here: API will do that for us.
              opts = { type: 'scale' }
              opts[:container_count] = container_count if container_count
              opts[:container_size] = container_size if container_size

              op = service.create_operation!(opts)
              attach_to_operation_logs(op)
            end

            desc 'apps:deprovision', 'Deprovision an app'
            app_options
            define_method 'apps:deprovision' do
              app = ensure_app(options)
              say "Deprovisioning #{app.handle}..."
              app.create_operation!(type: 'deprovision')
            end
          end
        end
      end
    end
  end
end
