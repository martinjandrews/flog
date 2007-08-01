require 'rubygems'
require 'parse_tree'
require 'sexp_processor'
require 'unified_ruby'

class Flog < SexpProcessor
  VERSION = '1.0.2'

  include UnifiedRuby

  THRESHOLD = 0.60

  SCORES = Hash.new(1)

  SCORES.merge!(:define_method => 5,
                :eval => 5,
                :module_eval => 5,
                :class_eval => 5,
                :instance_eval => 5)

  SCORES.merge!(:alias_method => 2,
                :include => 2,
                :extend => 2,
                :instance_method => 2,
                :instance_methods => 2,
                :method_added => 2,
                :method_defined? => 2,
                :method_removed => 2,
                :method_undefined => 2,
                :private_class_method => 2,
                :private_instance_methods => 2,
                :private_method_defined? => 2,
                :protected_instance_methods => 2,
                :protected_method_defined? => 2,
                :public_class_method => 2,
                :public_instance_methods => 2,
                :public_method_defined? => 2,
                :remove_method => 2,
                :undef_method => 2)

  @@no_class = :none
  @@no_method = :none

  def initialize
    super
    @pt = ParseTree.new(false)
    @klass_name, @method_name = @@no_class, @@no_method
    self.auto_shift_type = true
    self.require_empty = false # HACK
    @totals = Hash.new 0
    @multiplier = 1.0

    @calls = Hash.new { |h,k| h[k] = Hash.new 0 }
  end

  def process_files *files
    files.flatten.each do |file|
      next unless File.file? file or file == "-"
      ruby = file == "-" ? $stdin.read : File.read(file)
      sexp = @pt.parse_tree_for_string(ruby, file)
      process Sexp.from_array(sexp)
    end
  end

  def report
    total_score = @totals.values.inject(0) { |sum,n| sum + n }
    max = total_score * THRESHOLD
    current = 0

    puts "Total score = #{total_score}"
    puts

    @calls.sort_by { |k,v| -@totals[k] }.each do |klass_method, calls|
      total = @totals[klass_method]
      puts "%s: (%d)" % [klass_method, total]
      calls.sort_by { |k,v| -v }.each do |call, count|
        puts "  %4d: %s" % [count, call]
      end

      current += total
      break if current >= max
    end
  rescue
    # do nothing
  end

  def add_to_score(name, score)
    @totals["#{@klass_name}##{@method_name}"] += score * @multiplier
    @calls["#{@klass_name}##{@method_name}"][name] += score * @multiplier
  end

  def bad_dog! bonus
    @multiplier += bonus
    yield
    @multiplier -= bonus
  end

  ############################################################
  # Process Methods:

  def process_alias(exp)
    process exp.shift
    process exp.shift
    add_to_score :alias, 2
    s()
  end

  # [:block_pass, [:lit, :blah], [:fcall, :foo]]
  def process_block_pass(exp)
    arg = exp.shift
    call = exp.shift

    case arg.first
    when :iter then
      add_to_score :to_proc_iter_wtf?, 6
    when :lit, :call, :iter then
      add_to_score :to_proc, 3
    when :lvar, :dvar, :ivar, :nil then
      # do nothing
    else
      raise({:block_pass => [call, arg]}.inspect)
    end

    call = process call
    s()
  end

  def process_call(exp)
    bad_dog! 0.2 do
      recv = process exp.shift
    end
    name = exp.shift
    bad_dog! 0.2 do
      args = process exp.shift
    end

    score = SCORES[name]
    add_to_score name, score

    s()
  end

  def process_class(exp)
    @klass_name = exp.shift
    bad_dog! 1.0 do
      supr = process exp.shift
    end
    until exp.empty?
      process exp.shift
    end
    @klass_name = @@no_class
    s()
  end

  def process_defn(exp)
    @method_name = exp.shift
    process exp.shift until exp.empty?
    @method_name = @@no_method
    s()
  end

  def process_defs(exp)
    process exp.shift
    @method_name = exp.shift
    process exp.shift until exp.empty?
    @method_name = @@no_method
    s()
  end

  def process_lit(exp)
    value = exp.shift
    case value
    when 0, -1 then
      # ignore those because they're used as array indicies instead of first/last
    when Integer then
      add_to_score :lit_fixnum, 0.25
    when Float, Symbol, Regexp, Range then
      # do nothing
    else
      raise value.inspect
    end
    s()
  end

  def process_module(exp)
    @klass_name = exp.shift
    until exp.empty?
      process exp.shift
    end
    @klass_name = @@no_class
    s()
  end

  def process_sclass(exp)
    bad_dog! 0.5 do
      recv = process exp.shift
      process exp.shift until exp.empty?
    end

    add_to_score :sclass, 5
    s()
  end
end