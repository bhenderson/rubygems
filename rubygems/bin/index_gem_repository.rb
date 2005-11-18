#!/usr/bin/env ruby

# Generate the yaml/yaml.Z index files for a gem server directory.
#
# Usage:  generate_yaml_index.rb --dir DIR [--verbose]

$:.unshift '~/rubygems' if File.exist? "~/rubygems"

require 'optparse'
require 'rubygems'
require 'zlib'
require 'digest/sha2'

Gem.manage_gems

# ====================================================================
# Compressor provides a +compress+ method for compressing files on
# disk.
module Compressor
  # Compress the given file.
  def compress(filename, ext="rz")
    File.open(filename + ".#{ext}", "w") do |file|
      file.write(zip(File.read(filename)))
    end
  end

  # Return a compressed version of the given string.
  def zip(string)
    Zlib::Deflate.deflate(string)
  end
end

# ====================================================================
# Announcer provides a way of announcing activities to the user.
module Announcer

  # Announce +msg+ to the user.
  def announce(msg)
    puts msg if @options[:verbose]
  end
end

# ====================================================================
class AbstractIndexBuilder
  include Compressor
  include Announcer

  def build
    if ! @enabled
      yield
    else
      unless File.exist?(@directory)
	FileUtils.mkdir_p(@directory)
      end
      fail "not a directory: #{@directory}" unless File.directory?(@directory)
      File.open(File.join(@directory, @filename), "w") do |file|
	@file = file
	start_index
	yield
	end_index
      end
      cleanup
    end
  ensure
    @file = nil
  end

  def start_index
  end

  def end_index
  end

  def cleanup
  end
end

class MasterIndexBuilder < AbstractIndexBuilder
  def initialize(filename, options)
    @filename = filename
    @options = options
    @directory = options[:directory]
    @enabled = true
  end

  def start_index
    super
    @file.puts "--- !ruby/object:Gem::Cache"
    @file.puts "gems:"
  end

  def end_index
    super
    compress(File.join(@directory, @filename), "Z")
  end

  def add(spec)
    @file.puts "  #{spec.full_name}: #{nest(spec.to_yaml)}"
  end

  def nest(yaml_string)
    yaml_string[4..-1].gsub(/\n/, "\n    ")
  end
end

class QuickIndexBuilder < AbstractIndexBuilder
  def initialize(filename, options)
    @filename = filename
    @options = options
    @directory = options[:quick_directory]
    @enabled = options[:quick]
  end

  def cleanup
    compress(File.join(@directory, @filename))
  end

  def add(spec)
    return unless @enabled
    @file.puts spec.full_name
    fn = File.join(@directory, "#{spec.full_name}.gemspec.rz")
    File.open(fn, "w") do |gsfile|
      gsfile.write(zip(spec.to_yaml))
    end
  end
end

# ====================================================================
# Top level class for building the repository index.  Initialize with
# an options hash and call +build_index+.
class Indexer
  include Compressor
  include Announcer

  # Create an indexer with the options specified by the options hash.
  def initialize(options)
    @options = options.dup
    @directory = @options[:directory]
    @options[:quick_directory] = File.join(@directory, "quick")
    @master_index = MasterIndexBuilder.new("yaml", @options)
    @quick_index = QuickIndexBuilder.new("index", @options)
  end

  # Build the index.
  def build_index
    announce "Building Server Index"
    FileUtils.rm_r(@options[:quick_directory]) rescue nil
    @master_index.build do
      @quick_index.build do 
	gem_file_list.each do |gemfile|
	  spec = Gem::Format.from_file_by_path(gemfile).spec
	  abbreviate(spec)	  
	  announce "   ... adding #{spec.full_name}"
	  @master_index.add(spec)
	  @quick_index.add(spec)
	end
      end
    end
  end

  # List of gem file names to index.
  def gem_file_list
    Dir.glob(File.join(@directory, "gems", "*.gem"))
  end

  # Abbreviate the spec for downloading.  Abbreviated specs are only
  # used for searching, downloading and related activities and do not
  # need deployment specific information (e.g. list of files).  So we
  # abbreviate the spec, making it much smaller for quicker downloads.
  def abbreviate(spec)
    spec.files = []
    spec.test_files = []
    spec.rdoc_options = []
    spec.extra_rdoc_files = []
    spec.cert_chain = []
    spec
  end
end


def handle_options(args)
  # default options
  options = {
    :directory => '.',
    :verbose => false,
    :quick => true,
  }
  
  args.options do |opts|
    opts.on_tail("--help", "show this message") do
      puts opts
      exit
    end
    opts.on(
      '-d', '--dir=DIRNAME', '--directory=DIRNAME',
      "repository base dir containing gems subdir",
      String) do |value|
      options[:directory] = value
    end
    opts.on('--[no-]quick', "include quick index") do |value|
      options[:quick] = value
    end
    opts.on('-v', '--verbose', "show verbose output") do |value|
      options[:verbose] = value
    end
    opts.on('-V', '--version',
      "show version") do |value|
      puts Gem::RubyGemsVersion
      exit
    end
    opts.parse!
  end
  
  if options[:directory].nil?
    puts "Error, must specify directory name. Use --help"
    exit
  elsif ! File.exist?(options[:directory]) ||
      ! File.directory?(options[:directory])
    puts "Error, unknown directory name #{directory}."
    exit
  end
  options
end

# Main program.
def main_index(args)
  options = handle_options(args)
  Indexer.new(options).build_index
end

if __FILE__ == $0 then
  main_index(ARGV)
end
