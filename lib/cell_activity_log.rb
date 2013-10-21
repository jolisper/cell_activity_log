require "cell_activity_log/version"
require "digest/md5"

module CellActivityLog
  class LogFlusher
    include Celluloid

    exclusive :begin, :end, :exception

    def begin klass, method_name, begin_time, message, call_hash
      flush format(begin_format,
                   begin_time.strftime(time_format),
                   call_hash,
                   "BEG",
                   "#{klass}##{method_name}",
                   message)
    end

    def end klass, method_name, begin_time, end_time, message, call_hash
      flush format(end_format,
                   end_time.strftime(time_format),
                   call_hash,
                   "END",
                   "#{klass}##{method_name}",
                   message,
                   end_time - begin_time)
    end
    
    def exception klass, method_name, begin_time, message, call_hash, exception
      flush format(exception_format,
                   begin_time.strftime(time_format),
                   call_hash,
                   "EXC",
                   "#{klass}##{method_name}",
                   exception.class,
                   exception.message,
                   exception.backtrace.join("\n"))
    end

    private

    def flush string
      puts string
      $stdout.flush
    end

    def time_diff begin_time, end_time
      end_time - begin_time
    end

    def begin_format
      common_format + "| %-40s |"
    end
    
    def end_format
      begin_format + " %s |"
    end

    def exception_format
      common_format + "| %-40s | %-40s | \n%s |" 
    end

    def common_format
      "%s | %-6.6s | %-3.3s | %-40s "
    end

    def time_format
      "%F %T:%L"
    end
  end
end

module CellActivityLog
  module Logger

    @flusher = LogFlusher.new 
    
    class << self
      attr_reader :flusher 
    end

    def self.included base
      base.extend ClassMethods
    end

    module ClassMethods
      def logged *config

        method_configs = {}
        config.each_with_index do |param, index|
          if param.instance_of? Symbol
            # Gets the original method implementation
            method = instance_method param
            # Check for extra config in the next parameter
            next_param = config[ index + 1 ]
            if next_param.instance_of? Symbol
              method_configs[param] = MethodConfig.new method
            else
              method_configs[param] = MethodConfig.new method, next_param
            end
          end
        end

        method_configs.each do |name, method_config|
          # Defines the logged version of the original method
          define_method name do |*args, &block|
            LoggedCall.new(self, method_config, args, block, Logger).execute 
          end
        end 
      end
    end

    class MethodConfig
      attr_reader :method, :config, :param_names

      def initialize method, param=nil
        @method = method

        @config = { template: nil }
        if param.instance_of? String
          @config[:template] = param
        elsif param.instance_of? Hash
          @config.merge! param
        end
      end
      
      def get(key)
        value = config[key]
        if value
          value.clone
        else
          value
        end
      end

      private :config
    end
    
    class LoggedCall
      attr_reader(:instance, 
                  :method, 
                  :arguments,
                  :block,
                  :flusher,
                  :config,
                  :call_hash, 
                  :begin_time,
                  :param_names)
      
      def initialize instance, method_config, arguments, block, logger 
        @instance  = instance
        @config    = method_config
        @method    = method_config.method
        @flusher   = logger.flusher
        @arguments = arguments
        @block     = block
        build_method_names_hash!
      end

      def build_method_names_hash!
        index = 0
        @param_names = method.parameters.each_with_object({}) do |config, object| 
          object[config[1]] = index
          index += 1
        end
      end

      def param_index param_name
        param_names[param_name]
      end
      
      def execute
        set_begin_time!
        build_call_hash!
        make_call
      end
      
      def make_call
        begin_call
        response = with_exception_log { method.bind(instance).(*arguments, &block) }
        end_call
        
        response.tap { |obj| raise obj if obj.kind_of? Exception }
      end

      def set_begin_time!
        @begin_time = Time.now
      end

      def build_call_hash!
        @call_hash = Digest::MD5.hexdigest "#{instance.class}#{method.name}#{begin_time.to_f}"
      end
      
      def begin_call
        flusher.async.begin(instance.class, method.name, begin_time, build_message, call_hash)
      end

      def end_call
        flusher.async.end(instance.class, method.name, begin_time, Time.now, build_message, call_hash)
      end

      def with_exception_log &block
        begin
          block.call
        rescue Exception => exception
          flusher.async.exception(instance.class, method.name, begin_time, build_message, call_hash, exception)
          exception
        end
      end

      def build_message
        template = config.get(:template)
        
        return nil unless template
        
        replace_return! template
 
        template.scan(/\{[^\{\}]+\}/).each_with_object template.clone do |substr, sustitution|
          param_index, message = get_param_index_and_message substr
          next unless param_index

          if message
            begin
              sustitution.sub! "#{substr}", arguments[param_index].send(message).to_s
            rescue Exception => e
              sustitution.sub! "#{substr}", "{#{e.inspect}}"
            end
          else
            sustitution.sub! "#{substr}", arguments[param_index].to_s
          end
        end
      end

      def replace_return! template
        template.scan(/{return#.+}/).each do |match|
          _, message = match.delete("{}").split('#')
          begin
            if message
              template.sub! "{return##{message}}", @return.send(message).to_s
            else
              template.sub! "{return#}", @return.to_s
            end
          rescue Exception => e
            template.sub! "{return##{message}}", "{#{e.inspect.to_s}}"
          end  
        end

        template.scan(/{return}/).each do |match|
          template.sub! "{return}", @return.to_s
        end
      end

      def get_param_index_and_message substr
        name, message = substr.delete("{}").split("#")
        name ||= substr
        param_index = param_names[name.to_sym]
        [param_index, message]
      end
        
      private :instance, 
              :method, 
              :arguments,
              :block,
              :flusher,
              :config,
              :call_hash, 
              :begin_time,
              :param_names
    end
  end
end
