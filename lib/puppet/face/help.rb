require 'puppet/face'
require 'puppet/application/face_base'
require 'puppet/util/command_line'
require 'puppet/util/constant_inflector'
require 'pathname'
require 'erb'

Puppet::Face.define(:help, '0.0.1') do
  copyright "Puppet Labs", 2011
  license   "Apache 2 license; see COPYING"

  summary "Display Puppet help."

  action(:help) do
    summary "Display help about Puppet subcommands and their actions."
    arguments "[<subcommand>] [<action>]"
    returns "Short help text for the specified subcommand or action."
    examples <<-'EOT'
      Get help for an action:

      $ puppet help
    EOT

    option "--version VERSION" do
      summary "The version of the subcommand for which to show help."
    end

    default
    when_invoked do |*args|
      # Check our invocation, because we want varargs and can't do defaults
      # yet.  REVISIT: when we do option defaults, and positional options, we
      # should rewrite this to use those. --daniel 2011-04-04
      options = args.pop
      if options.nil? or args.length > 2 then
        if args.select { |x| x == 'help' }.length > 2 then
          c = "\n %'(),-./=ADEFHILORSTUXY\\_`gnv|".split('')
          i = <<-'EOT'.gsub(/\s*/, '').to_i(36)
            3he6737w1aghshs6nwrivl8mz5mu9nywg9tbtlt081uv6fq5kvxse1td3tj1wvccmte806nb
            cy6de2ogw0fqjymbfwi6a304vd56vlq71atwmqsvz3gpu0hj42200otlycweufh0hylu79t3
            gmrijm6pgn26ic575qkexyuoncbujv0vcscgzh5us2swklsp5cqnuanlrbnget7rt3956kam
            j8adhdrzqqt9bor0cv2fqgkloref0ygk3dekiwfj1zxrt13moyhn217yy6w4shwyywik7w0l
            xtuevmh0m7xp6eoswin70khm5nrggkui6z8vdjnrgdqeojq40fya5qexk97g4d8qgw0hvokr
            pli1biaz503grqf2ycy0ppkhz1hwhl6ifbpet7xd6jjepq4oe0ofl575lxdzjeg25217zyl4
            nokn6tj5pq7gcdsjre75rqylydh7iia7s3yrko4f5ud9v8hdtqhu60stcitirvfj6zphppmx
            7wfm7i9641d00bhs44n6vh6qvx39pg3urifgr6ihx3e0j1ychzypunyou7iplevitkyg6gbg
            wm08oy1rvogcjakkqc1f7y1awdfvlb4ego8wrtgu9vzw4vmj59utwifn2ejcs569dh1oaavi
            sc581n7jjg1dugzdu094fdobtx6rsvk3sfctvqnr36xctold
          EOT
          353.times{i,x=i.divmod(1184);a,b=x.divmod(37);print(c[a]*b)}
        end
        raise ArgumentError, "Puppet help only takes two (optional) arguments: a subcommand and an action"
      end

      version = :current
      if options.has_key? :version then
        if options[:version].to_s !~ /^current$/i then
          version = options[:version]
        else
          if args.length == 0 then
            raise ArgumentError, "Version only makes sense when a Faces subcommand is given"
          end
        end
      end

      # Name those parameters...
      facename, actionname = args

      if facename then
        if legacy_applications.include? facename then
          actionname and raise ArgumentError, "Legacy subcommands don't take actions"
          return Puppet::Application[facename].help
        else
          face = Puppet::Face[facename.to_sym, version]
          actionname and action = face.get_action(actionname.to_sym)
        end
      end

      case args.length
      when 0 then
        template = erb 'global.erb'
      when 1 then
        face or fail ArgumentError, "Unable to load face #{facename}"
        template = erb 'face.erb'
      when 2 then
        face or fail ArgumentError, "Unable to load face #{facename}"
        action or fail ArgumentError, "Unable to load action #{actionname} from #{face}"
        template = erb 'action.erb'
      else
        fail ArgumentError, "Too many arguments to help action"
      end

      # Run the ERB template in our current binding, including all the local
      # variables we established just above. --daniel 2011-04-11
      return template.result(binding)
    end
  end

  def erb(name)
    template = (Pathname(__FILE__).dirname + "help" + name)
    erb = ERB.new(template.read, nil, '-')
    erb.filename = template.to_s
    return erb
  end

  # Return a list of applications that are not simply just stubs for Faces.
  def legacy_applications
    Puppet::Util::CommandLine.available_subcommands.reject do |appname|
      (is_face_app?(appname)) or (exclude_from_docs?(appname))
    end.sort
  end

  # Return a list of all applications (both legacy and Face applications), along with a summary
  #  of their functionality.
  # @returns [Array] An Array of Arrays.  The outer array contains one entry per application; each
  #  element in the outer array is a pair whose first element is a String containing the application
  #  name, and whose second element is a String containing the summary for that application.
  def all_application_summaries()
    Puppet::Util::CommandLine.available_subcommands.sort.inject([]) do |result, appname|
      next result if exclude_from_docs?(appname)

      if (is_face_app?(appname))
        face = Puppet::Face[appname, :current]
        result << [appname, face.summary]
      else
        result << [appname, horribly_extract_summary_from(appname)]
      end
    end
  end

  def horribly_extract_summary_from(appname)
    begin
      # it sucks that this 'require' is necessary, and it sucks even more that we are
      #  doing it in two different places in this class (#horribly_extract_summary_from,
      #  #is_face_app?).  However, we can take some solace in the fact that ruby will
      #  at least recognize that it's already done a 'require' for any individual app
      #  and basically treat it as a no-op if we try to 'require' it twice.
      require "puppet/application/#{appname}"
      help = Puppet::Application[appname].help.split("\n")
      # Now we find the line with our summary, extract it, and return it.  This
      # depends on the implementation coincidence of how our pages are
      # formatted.  If we can't match the pattern we expect we return the empty
      # string to ensure we don't blow up in the summary. --daniel 2011-04-11
      while line = help.shift do
        if md = /^puppet-#{appname}\([^\)]+\) -- (.*)$/.match(line) then
          return md[1]
        end
      end
    rescue Exception
      # Damn, but I hate this: we just ignore errors here, no matter what
      # class they are.  Meh.
    end
    return ''
  end
  # This should absolutely be a private method, but for some reason it appears
  #  that you can't use the 'private' keyword inside of a Face definition.
  #  See #14205.
  #private :horribly_extract_summary_from

  def exclude_from_docs?(appname)
    %w{face_base indirection_base}.include? appname
  end
  # This should absolutely be a private method, but for some reason it appears
  #  that you can't use the 'private' keyword inside of a Face definition.
  #  See #14205.
  #private :exclude_from_docs?

  def is_face_app?(appname)
    # it sucks that this 'require' is necessary, and it sucks even more that we are
    #  doing it in two different places in this class (#horribly_extract_summary_from,
    #  #is_face_app?).  However, we can take some solace in the fact that ruby will
    #  at least recognize that it's already done a 'require' for any individual app
    #  and basically treat it as a no-op if we try to 'require' it twice.
    require "puppet/application/#{appname}"
    # Would much rather use "const_get" than "eval" here, but for some reason it is not available.
    #  See #14205.
    clazz = eval("Puppet::Application::#{Puppet::Util::ConstantInflector.file2constant(appname)}")
    clazz.ancestors.include?(Puppet::Application::FaceBase)
  end
  # This should probably be a private method, but for some reason it appears
  #  that you can't use the 'private' keyword inside of a Face definition.
  #  See #14205.
  #private :is_face_app?

end
