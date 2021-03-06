# Author: Yaron Dror (yaron.dror.bb@gmail.com)
# Description: The file contains 'Params' module implementation.
# Notes:
#   module.init should be called if user wants to override defined parameters by file or command line.
#   Parameter can be defined only once.
#   Parameters have to be defined before they are accessed. see examples below.
#
# Examples of definitions:
#   Params.string('parameter_str', 'this is a string' ,'description_for_string')
#   Params.path('parameter_path', '/Users/username/example/ect' ,'description_for_directory')
#   Params.integer('parameter_int',1 , 'description_for_integer')
#   Params.float('parameter_float',2.6 , 'description_for_float')
#   Params.boolean('parameter_true', true, 'description_for_true')
#   Params.boolean('parameter_false',false , 'description_for_false')
#   Params.complex('parameter_complex', [a,b,{b=>c}], 'description for dict or list of strings.')
#   Note. Parameters have to be defined before they are accessed.
#
# Examples of usages (get\set access is through the [] operator).
#   local_var_of_type_string = Params['parameter_str']
#   puts local_var_of_type_string  # Will produce --> this is a string
#   Params['parameter_float'] = 3.8
#   puts Params['parameter_float']  # Will produce --> 3.8
#   Params['parameter_float'] = 3
#   puts Params['parameter_float']  # Will produce --> 3.0 (note the casting)
#   Note. only after definition, the [] operator will work. Else an error is raised.
#     Params['new_param'] = true  # will raise an error, since the param was not defined yet.
#     Params.boolean 'new_param', true, 'this is correct'  # this is the definition.
#     Params['new_param'] = false  # Will set new value.
#     puts Params['new_param']  # Will produce --> false
#
# Type check.
#   A type check is forced both when overriding with file or command line and in [] usage.
#   if parameter was defined as a Float using Params.float method (e.g. 2.6) and user
#   provided an integer when overriding or when using [] operator then the integer will
#   be casted to float.
#
# Params.Init - override parameters.
#   implementation of the init sequence allows the override of
#   defined parameters with new values through input file and\or command line args.
#   Note that only defined parameters can be overridden. If new parameter is parsed
#   through file\command line, then an error will be raised.
#   Input config file override:
#     Default configuration input file path is: '~/.bbfs/conf/<executable name>.conf'
#     This path can be overridden by the command line arguments (see ahead).
#     If path and file exist then the parameters in the file will override the defined
#     parameters. File parameters format per line:<param_name>: <param value>
#     Note: Space char after the colon is mandatory
#   Command line arguments override:
#     General format per argument is:--<param_name>=<param_value>
#     those parameters will override the defined parameters and the file parameters.
#   Override input config file:
#     User can override the input file by using:--conf_file=<new_file_path>
#
# More examples in bbfs/examples/params/rb

require 'optparse'
require 'stringio'
require 'yaml'

module Params

  # Represents a parameter.
  class Param
    attr_accessor :name
    attr_accessor :value
    attr_accessor :desc
    attr_accessor :type

    # value_type_check method:
    # 1. Check if member:'type' is one of:Integer, Float, String or Boolean.
    # 2. input parameter:'value' class type is valid to override this parameter.
    # 3. Return value. The value to override with correct type. A cast from integer to Float will
    #    be made for Float parameters which are set with integer values.
    # 4. Check will be skipped for nil value.
    def value_type_check(value)
      if value.nil?
        return value
      end

      case( @type )
        when 'Integer' then
          if not @value.nil?
            if not ((value.class.eql? Integer) or
                (value.class.eql? Fixnum))
              raise "Parameter:'#{@name}' type:'Integer' but value type to override " \
                      "is:'#{value.class}'."
            end
          end
        when 'Float' then
          if not @value.nil?
            if not value.class.eql? Float
              if not ((value.class.eql? Integer) or
                  (value.class.eql? Fixnum))
                raise("Parameter:'#{@name}' type:'Float' but value type to override " \
                        "is:'#{value.class}'.")
              else
                return value.to_f
              end
            end
          end
        when 'String' then
        when 'Path' then
          # TODO(kolman): Override the type check with regexp of path in Linux and/or Windows
          if not @value.nil?
            if not value.class.eql? String
              raise("Parameter:'#{@name}' type:'String' but value type to override " \
                      "is:'#{value.class}'.")
            end
          end
        when 'Boolean' then
          if not @value.nil?
            if not((value.class.eql? TrueClass) or (value.class.eql? FalseClass))
              raise("Parameter:'#{@name}' type:'Boolean' but value type to override " \
                      "is:'#{value.class}'.")
            end
          end
        when 'Complex' then
          unless @value.nil?
            unless (value.class.eql? Hash) or (value.class.eql? Array)
              raise("Parameter:'#{@name}' type:'Complex' but value type to override " \
                      "is:'#{value.class}'.")
            end
          end
        else
          raise("Parameter:'#{@name}' type:'#{@value.class}' but parameter " \
                  "type to override:'#{value.class}' is not supported. " + \
                  "Supported types are:Integer, Float, String or Boolean.")
      end
      return value
    end

    # supported types are: String, Integer, Float, Boolean, Path or Complex
    def initialize(name, value, type, desc)
      @name = name
      @type = type
      @desc = desc
      @value = value_type_check value
    end
  end

  @params_data_base = Hash.new # The parameters data structure.
  @init_info_messages = []
  @show_help_and_exit = false

  def Params.get_init_info_messages
    return @init_info_messages
  end

  def Params.get_init_warning_messages
    return @init_warning_messages
  end

  def Params.raise_error_if_param_does_not_exist(name)
    if not @params_data_base[name]
      raise("before using parameter:'#{name}', it should first be defined through Param module methods:" \
               "Params.string, Params.path, Params.integer, Params.float, Params.complex, or Params.boolean.")
    end
  end

  def Params.raise_error_if_param_exists(name)
    if @params_data_base[name]
      raise("Parameter:'#{name}', can only be defined once.")
    end
  end

  # Read param value by other modules.
  # Note that this operator should only be used, after parameter has been defined through
  # one of Param module methods: Params.string, Params.integer,
  # Params.float or Params.boolean."
  def Params.[](name)
    raise_error_if_param_does_not_exist(name)
    @params_data_base[name].value
  end

  def Params.each(&block)
    @params_data_base.each(&block)
  end

  # Write param value by other modules.
  # Note that this operator should only be used, after parameter has been defined through
  # one of Param module methods: Params.string, Params.integer,
  # Params.float or Params.boolean."
  def Params.[]=(name, value)
    raise_error_if_param_does_not_exist(name)
    set_value = @params_data_base[name].value_type_check(value)
    @params_data_base[name].value = set_value
  end

  def Params.has_key?(name)
    @params_data_base.has_key?(name)
  end

  #override parameter should only be called by Params module methods.
  def Params.override_param(name, value)
    existing_param = @params_data_base[name]
    if existing_param.nil?
      raise("Parameter:'#{name}' has not been defined and can not be overridden. " \
              "It should first be defined through Param module methods:" \
              "Params.string, Params.path, Params.integer, Params.float, Params.complex, or Params.boolean.")
    end
    if value.nil?
      existing_param.value = nil
    elsif existing_param.type.eql?('String')
      existing_param.value = value.to_s
    elsif existing_param.type.eql?('Path')
      existing_param.value = File.expand_path(value.to_s)
    elsif existing_param.type.eql?('Complex')
      if value.class.eql?(Hash) || value.class.eql?(Array)
        existing_param.value = value
      else
        existing_param.value = YAML::load(StringIO.new(value.to_s))
      end
    else
      set_value = existing_param.value_type_check(value)
      existing_param.value = set_value
    end
  end

  # Define new parameter of type Integer.
  def Params.integer(name, value, description)
    raise_error_if_param_exists(name)
    @params_data_base[name] = Param.new(name, value, 'Integer', description)
  end

  # Define new parameter of type Float.
  def Params.float(name, value, description)
    raise_error_if_param_exists(name)
    @params_data_base[name] = Param.new(name, value, 'Float', description)
  end

  # Define new parameter of type String.
  def Params.string(name, value, description)
    raise_error_if_param_exists(name)
    @params_data_base[name] = Param.new(name, value, 'String', description)
  end

  # Define new parameter of type path (the only difference with string is that the path expends '~' to
  # full user directory).
  def Params.path(name, value, description)
    raise_error_if_param_exists(name)
    value = File.expand_path(value) unless value.nil?
    @params_data_base[name] = Param.new(name, value, 'Path', description)
  end

  def Params.complex(name, value, description)
    raise_error_if_param_exists(name)
    @params_data_base[name] = Param.new(name, value, 'Complex', description)
  end

  # Define new parameter of type Boolean.
  def Params.boolean(name, value, description)
    raise_error_if_param_exists(name)
    @params_data_base[name] = Param.new(name, value, 'Boolean', description)
  end

  # Initializes the project parameters.
  # Precedence is: Defined params, file and command line is highest.
  # If no args provided then only default values used.
  def Params.init(args=nil)
    #define default configuration file
    Params['conf_file'] = "~/.bbfs/etc/config_#{File.basename($PROGRAM_NAME)}.yml"

    @init_info_messages = []
    @init_warning_messages = []

    results = Hash.new  # Hash to store parsing results.

    # Parse command line argument and set configuration file if provided by user.
    unless (args.nil?)
      results = parse_command_line_arguments(args)
    end
    if results['conf_file']
      Params['conf_file'] = File.expand_path(results['conf_file'])
      if !File.exist?(Params['conf_file']) or File.directory?(Params['conf_file'])
        raise("Param:'conf_file' value:'#{Params['conf_file']}' is a file name which does not exist" +
                  " or a directory name")
      end
    end

    Params['conf_file'] = File.expand_path(Params['conf_file'])

    #load yml params if path is provided and exists
    if File.exist?(Params['conf_file'])
      @init_info_messages << "Loading parameters from configuration file:'#{Params['conf_file']}'"
      if not read_yml_params(File.open(Params['conf_file'], 'r'))
        raise("Bad configuration file #{Params['conf_file']}.")
      end
    else
      @init_warning_messages << "Configuration file path:'#{Params['conf_file']}' does not exist. " + \
                                "Skipping loading file parameters."
    end

    #override command line argument
    results.keys.each do |result_name|
      override_param(result_name, results[result_name])
    end

    # Prints help and parameters if needed.
    if @show_help_and_exit
      # Print parameters + description and exit.
      puts "Full list of parameters:"
      Params.each do |name, param|
        puts "--#{name}, #{param.type}, default:#{param.value}\n\t#{param.desc}"
      end
      exit
    end

    # Add parameters to log init messages (used by Log.init if param:print_params_to_stdout is true)
    @init_info_messages << 'Initialized executable parameters:'
    @init_info_messages << '---------------------------------'
    counter=0
    @params_data_base.values.each do |param|
      counter += 1
      @init_info_messages << "Param ##{counter}: #{param.name}=#{param.value}"
    end
    @init_info_messages << '---------------------------------'
  end

  # Load yml params and override default values.
  # raise exception if a loaded yml param does not exist. or if types mismatch occurs.
  def Params.read_yml_params(yml_input_io)
    proj_params = YAML::load(yml_input_io)
    return false unless proj_params.is_a?(Hash)
    proj_params.keys.each do |param_name|
      override_param(param_name, proj_params[param_name])
    end
    true
  end

  #  Parse command line arguments
  def Params.parse_command_line_arguments(args)
    # Define options switch for parsing
    # Define List of options see example on
    # http://ruby.about.com/od/advancedruby/a/optionparser2.htm

    results = Hash.new  # Hash to store parsing results.
    options = Hash.new  # Hash of parsing options from Params.

    opts = OptionParser.new do |opts|
      @params_data_base.values.each do |param|
        tmp_name_long = "--#{param.name} #{param.name.upcase}"  # Define a command with single mandatory parameter
        tmp_value = param.desc + " Default value:" + param.value.to_s  #  Description and Default value

        # Define type of the mandatory value
        # It can be integer, float or String(for all other types).
        case(param.type)
          when 'Integer' then value_type = Integer
          when 'Float' then value_type = Float
          else value_type = String
        end
        # Switches definition - according to what
        # was pre-defined in the Params
        opts.on(tmp_name_long, value_type, tmp_value) do |result|
          if result.to_s.upcase.eql? 'TRUE'
            results[param.name] = true
          elsif result.to_s.upcase.eql? 'FALSE'
            results[param.name] = false
          else
            results[param.name] = result
          end
        end
      end

      # Define introduction text for help command
      opts.banner =
          "Usage: content_serve [options] or \n"  +
          "     : backup_server [options] \n\n" +
          "Description: This application for backuping files and folders\n" +
          "There is two application: \n" +
          "backup_server is server run on machine where files is backuped,\n" +
          "content_server is application that run on machine from where files is copied.\n\n" +
          "Before run applications:" +
          "Before running backup_server and content server you need to prepare two configuration files\n" +
          "Create configuration file for content server which should be located at ~/.bbfs/etc/file_monitoring.yml\n" +
          "the content of the file is:
------- begin of file_monitoring.yml --------
paths:
- path: ~/.bbfs/test_files  # <=== replace with your local dir.
scan_period: 1
stable_state: 5
------- end of file_monitoring.yml --------\n" +
            "Create configuration file for backup server which should be located at \n" +
            "~/.bbfs/etc/backup_file_monitoring.yml\n" +
            "File content:
------- begin of backup_file_monitoring.yml --------
paths:
   - path:  ~/.bbfs/backup_data  # <=== replace with your local dir.
     scan_period: 1
     stable_state: 5
------- end of backup_file_monitoring.yml --------\n\n" +
            "Explanation about file_monitoring.yml and backup_file_monitoring.yml configuration files:

\"path:\" - say to program which folder to scan recursively in order to find  new/changed files and folders.
\"scan_period:\" - how much time in seconds passed before two consecutive scans for files and directories.
\"stable_state:\" - how many scan_period passed until the file is considered stable.\n\n" +
             "List of options:"


      # Define help command for available options
      # executing --help will printout all pre-defined switch options
      opts.on_tail("-h", "--help", "Show this message") do
        @show_help_and_exit = true
      end

      opts.parse(args)  # Parse command line
    end
    return results
  end # end of Parse function

  def Params.to_simple_hash
    @params_data_base.map { |param|
      param.value
    }
  end

  Params.path('conf_file', nil, 'Configuration file path.')
  Params.boolean('print_params_to_stdout', false, 'print_params_to_stdout or not during Params.init')

  private_class_method :parse_command_line_arguments, \
                       :raise_error_if_param_exists, :raise_error_if_param_does_not_exist, \
                       :read_yml_params, :override_param
end

