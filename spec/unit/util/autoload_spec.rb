#!/usr/bin/env rspec
require 'spec_helper'

require 'puppet/util/autoload'

describe Puppet::Util::Autoload do
  before do
    @autoload = Puppet::Util::Autoload.new("foo", "tmp")

    @autoload.stubs(:eachdir).yields "/my/dir"
    @loaded = {}
    @autoload.class.stubs(:loaded).returns(@loaded)
  end

  describe "when building the search path" do
    before :each do
      @dira = File.expand_path('/a')
      @dirb = File.expand_path('/b')
      @dirc = File.expand_path('/c')
    end

    it "should collect all of the plugins and lib directories that exist in the current environment's module path" do
      Puppet.settings.expects(:value).with(:environment).returns "foo"
      Puppet.settings.expects(:value).with(:modulepath, :foo).returns "#{@dira}#{File::PATH_SEPARATOR}#{@dirb}#{File::PATH_SEPARATOR}#{@dirc}"
      Dir.expects(:entries).with(@dira).returns %w{one two}
      Dir.expects(:entries).with(@dirb).returns %w{one two}

      FileTest.stubs(:directory?).returns false
      FileTest.expects(:directory?).with(@dira).returns true
      FileTest.expects(:directory?).with(@dirb).returns true
      ["#{@dira}/one/plugins", "#{@dira}/two/lib", "#{@dirb}/one/plugins", "#{@dirb}/two/lib"].each do |d|
        FileTest.expects(:directory?).with(d).returns true
      end

      @autoload.class.module_directories.should == ["#{@dira}/one/plugins", "#{@dira}/two/lib", "#{@dirb}/one/plugins", "#{@dirb}/two/lib"]
    end

    it "should not look for lib directories in directories starting with '.'" do
      Puppet.settings.expects(:value).with(:environment).returns "foo"
      Puppet.settings.expects(:value).with(:modulepath, :foo).returns @dira
      Dir.expects(:entries).with(@dira).returns %w{. ..}

      FileTest.expects(:directory?).with(@dira).returns true
      FileTest.expects(:directory?).with("#{@dira}/./lib").never
      FileTest.expects(:directory?).with("#{@dira}/./plugins").never
      FileTest.expects(:directory?).with("#{@dira}/../lib").never
      FileTest.expects(:directory?).with("#{@dira}/../plugins").never

      @autoload.class.module_directories
    end

    it "should include the module directories, the Puppet libdir, and all of the Ruby load directories" do
      Puppet[:libdir] = %w{/libdir1 /lib/dir/two /third/lib/dir}.join(File::PATH_SEPARATOR)
      @autoload.class.expects(:module_directories).returns %w{/one /two}
      @autoload.class.search_directories.should == %w{/one /two} + Puppet[:libdir].split(File::PATH_SEPARATOR) + $LOAD_PATH
    end
  end

  describe "when loading a file" do
    before do
      @autoload.class.stubs(:search_directories).returns %w{/a}
      FileTest.stubs(:directory?).returns true
      @time_a = Time.utc(2010, 'jan', 1, 6, 30)
      File.stubs(:mtime).returns @time_a
    end

    [RuntimeError, LoadError, SyntaxError].each do |error|
      it "should die with Puppet::Error if a #{error.to_s} exception is thrown" do
        File.stubs(:exist?).returns true

        Kernel.expects(:load).raises error

        lambda { @autoload.load("foo") }.should raise_error(Puppet::Error)
      end
    end

    it "should not raise an error if the file is missing" do
      @autoload.load("foo").should == false
    end

    it "should register loaded files with the autoloader" do
      File.stubs(:exist?).returns true
      Kernel.stubs(:load)
      @autoload.load("myfile")

      @autoload.class.loaded?("tmp/myfile.rb").should be

      $LOADED_FEATURES.delete("tmp/myfile.rb")
    end

    it "should register loaded files with the main loaded file list so they are not reloaded by ruby" do
      File.stubs(:exist?).returns true
      Kernel.stubs(:load)

      @autoload.load("myfile")

      $LOADED_FEATURES.should be_include("tmp/myfile.rb")

      $LOADED_FEATURES.delete("tmp/myfile.rb")
    end

    it "should load the first file in the searchpath" do
      @autoload.stubs(:search_directories).returns %w{/a /b}
      FileTest.stubs(:directory?).returns true
      File.stubs(:exist?).returns true
      Kernel.expects(:load).with("/a/tmp/myfile.rb", optionally(anything))

      @autoload.load("myfile")

      $LOADED_FEATURES.delete("tmp/myfile.rb")
    end

    it "should treat equivalent paths to a loaded file as loaded" do
      File.stubs(:exist?).returns true
      Kernel.stubs(:load)
      @autoload.load("myfile")

      @autoload.class.loaded?("tmp/myfile").should be
      @autoload.class.loaded?("tmp/./myfile.rb").should be
      @autoload.class.loaded?("./tmp/myfile.rb").should be
      @autoload.class.loaded?("tmp/../tmp/myfile.rb").should be

      $LOADED_FEATURES.delete("tmp/myfile.rb")
    end
  end

  describe "when loading all files" do
    before do
      @autoload.class.stubs(:search_directories).returns %w{/a}
      FileTest.stubs(:directory?).returns true
      Dir.stubs(:glob).returns "/a/foo/file.rb"
      File.stubs(:exist?).returns true
      @time_a = Time.utc(2010, 'jan', 1, 6, 30)
      File.stubs(:mtime).returns @time_a

      @autoload.class.stubs(:loaded?).returns(false)
    end

    [RuntimeError, LoadError, SyntaxError].each do |error|
      it "should die an if a #{error.to_s} exception is thrown", :'fails_on_ruby_1.9.2' => true do
        Kernel.expects(:load).raises error

        lambda { @autoload.loadall }.should raise_error(Puppet::Error)
      end
    end

    it "should require the full path to the file", :'fails_on_ruby_1.9.2' => true do
      Kernel.expects(:load).with("/a/foo/file.rb", optionally(anything))

      @autoload.loadall
    end
  end

  describe "when reloading files" do
    before :each do
      @file_a = "/a/file.rb"
      @file_b = "/b/file.rb"
      @first_time = Time.utc(2010, 'jan', 1, 6, 30)
      @second_time = @first_time + 60
    end

    after :each do
      $LOADED_FEATURES.delete("a/file.rb")
      $LOADED_FEATURES.delete("b/file.rb")
    end

    describe "in one directory" do
      before :each do
        @autoload.class.stubs(:search_directories).returns %w{/a}
        File.expects(:mtime).with(@file_a).returns(@first_time)
        @autoload.class.mark_loaded("file", @file_a)
      end

      it "should reload if mtime changes" do
        File.stubs(:mtime).with(@file_a).returns(@first_time + 60)
        File.stubs(:exist?).with(@file_a).returns true
        Kernel.expects(:load).with(@file_a, optionally(anything))
        @autoload.class.reload_changed
      end

      it "should do nothing if the file is deleted" do
        File.stubs(:mtime).with(@file_a).raises(Errno::ENOENT)
        File.stubs(:exist?).with(@file_a).returns false
        Kernel.expects(:load).never
        @autoload.class.reload_changed
      end
    end

    describe "in two directories" do
      before :each do
        @autoload.class.stubs(:search_directories).returns %w{/a /b}
      end

      it "should load b/file when a/file is deleted" do
        File.expects(:mtime).with(@file_a).returns(@first_time)
        @autoload.class.mark_loaded("file", @file_a)
        File.stubs(:mtime).with(@file_a).raises(Errno::ENOENT)
        File.stubs(:exist?).with(@file_a).returns false
        File.stubs(:exist?).with(@file_b).returns true
        File.stubs(:mtime).with(@file_b).returns @first_time
        Kernel.expects(:load).with(@file_b, optionally(anything))
        @autoload.class.reload_changed
        @autoload.class.send(:loaded)["file"].should == [@file_b, @first_time]
      end

      it "should load a/file when b/file is loaded and a/file is created" do
        File.stubs(:mtime).with(@file_b).returns @first_time
        File.stubs(:exist?).with(@file_b).returns true
        @autoload.class.mark_loaded("file", @file_b)

        File.stubs(:mtime).with(@file_a).returns @first_time
        File.stubs(:exist?).with(@file_a).returns true
        Kernel.expects(:load).with(@file_a, optionally(anything))
        @autoload.class.reload_changed
        @autoload.class.send(:loaded)["file"].should == [@file_a, @first_time]
      end
    end
  end
end
