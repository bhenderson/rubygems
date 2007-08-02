require 'test/unit'
require 'test/gemutilities'
require 'rubygems/commands/specification_command'

class TestGemCommandsSpecificationCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::SpecificationCommand.new
    @ui = MockGemUi.new
  end

  def test_execute
    foo = quick_gem 'foo'

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{foo.to_yaml}\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_all
    foo1 = quick_gem 'foo', '0.0.1'
    foo2 = quick_gem 'foo', '0.0.2'

    @cmd.options[:args] = %w[foo]
    @cmd.options[:all] = true

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{foo1.to_yaml}\n#{foo2.to_yaml}\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_bad_name
    @cmd.options[:args] = %w[foo]

    assert_raise MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output
    assert_equal "ERROR:  Unknown gem 'foo'\n", @ui.error
  end

  def test_execute_remote
    foo = quick_gem 'foo'

    util_setup_source_info_cache foo

    FileUtils.rm File.join(@gemhome, 'specifications',
                           "#{foo.full_name}.gemspec")

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{foo.to_yaml}\n", @ui.output
    assert_equal "WARNING:  Remote information is not complete\n\n", @ui.error
  end

end
