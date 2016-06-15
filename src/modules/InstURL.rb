# encoding: utf-8

# Module:		InstURL.ycp
#
# Authors:		Klaus Kaempf (kkaempf@suse.de)
#
# Purpose:		Convert /etc/install.inf data to URL
#
#
# $Id$
require "yast"
require "uri"

module Yast
  class InstURLClass < Module
    include Yast::Logger

    def main
      textdomain "packager"
      Yast.import "Linuxrc"
      Yast.import "URL"
      Yast.import "CheckMedia"

      @is_network = nil
      @installInf2Url = nil
    end

    # Hide Password
    # @param [String] url original URL
    # @return [String] new URL with hidden password
    def HidePassword(url)
      Builtins.y2warning(
        "InstURL::HidePassword() is obsoleted, use URL::HidePassword() instead"
      )
      URL.HidePassword(url)
    end

    #
    def GetURLOptions(url)
      option_map = {}
      pos = Builtins.findfirstof(url, "?")
      if pos != nil
        opts = Builtins.substring(url, pos, Builtins.size(url))
        optpairs = Builtins.splitstring(opts, "?")
        option_map = Builtins.listmap(optpairs) do |op|
          tmp = Builtins.splitstring(op, "=")
          { Ops.get(tmp, 0, "") => Ops.get(tmp, 1, "") }
        end
      end
      deep_copy(option_map)
    end

    # check if SSL certificate check is enabled (default) or explicitely disabled by user
    def SSLVerificationEnabled
      ssl_verify = Linuxrc.InstallInf("ssl_verify")
      Builtins.y2milestone("Option ssl_verify: %1", ssl_verify)

      ssl_verify != "no"
    end

    #
    def RewriteCDUrl(url)
      tokens = URL.Parse(url)
      new_url = ""
      if Ops.get_string(tokens, "scheme", "") == "cd" ||
          Ops.get_string(tokens, "scheme", "") == "dvd"
        Builtins.y2milestone("Old options: %1", GetURLOptions(url))
        pos = Builtins.findfirstof(url, "?")
        if pos != nil
          new_options = GetDevicesOption()
          new_url = Builtins.substring(url, 0, pos)
          if Ops.greater_than(Builtins.size(new_options), 0)
            new_url = Ops.add(Ops.add(new_url, "?"), GetDevicesOption())
          else
            new_url = url
          end
        end
      else
        new_url = url
      end
      new_url
    end

    # Convert install.inf to a URL useable by the package manager
    # @param [String] extra_dir append path to original URL
    # @return [String] new repository URL
    def installInf2Url(_extra_dir)
      return @installInf2Url unless @installInf2Url.nil?
      repo_url = Linuxrc.InstallInf("ZyppRepoURL")
      @installInf2Url =
        if repo_url.nil? || repo_url.empty?
          log.warn "No URL specified through ZyppRepoURL."
          "cd:///"
        else
          log.info "Using ZyppRepoURL: #{URL.HidePassword(repo_url)}"
          repo_url
        end
    end

    # Schemes considered local for installInf2Url
    LOCAL_SCHEMES = ["cd", "dvd", "hd"]

    # Determines whether the installation URL is remote or not
    #
    # @return [Boolean] true if it's remote; false otherwise.
    # @see installInf2Url
    def is_network
      return @is_network unless @is_network.nil?
      @is_network = !LOCAL_SCHEMES.include?(URI(installInf2Url("")).scheme)
    end

    publish :function => :is_network, :type => "boolean ()"
    publish :function => :HidePassword, :type => "string (string)"
    publish :function => :RewriteCDUrl, :type => "string (string)"
    publish :function => :installInf2Url, :type => "string (string)"
  end

  InstURL = InstURLClass.new
  InstURL.main
end
