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
    def installInf2Url(extra_dir = "")
      return @installInf2Url unless @installInf2Url.nil?

      @installInf2Url = Linuxrc.InstallInf("ZyppRepoURL")

      if @installInf2Url.to_s.empty?
        # Make it compatible with the current behaviour when
        # install.inf does not exist.
        log.warn "No URL specified through ZyppRepoURL"
        @installInf2Url = "cd:///"
      end

      # The URL is parsed/build only if needed to avoid potential problems with corner cases.
      @installInf2Url = add_extra_dir_to_url(@installInf2Url, extra_dir) unless extra_dir.empty?
      @installInf2Url = add_ssl_verify_no_to_url(@installInf2Url) unless SSLVerificationEnabled()

      log.info "Using install URL: #{URL.HidePassword(@installInf2Url)}"
      @installInf2Url
    end

    # Schemes considered local for installInf2Url
    LOCAL_SCHEMES = ["cd", "dvd", "hd"]

    # Determines whether the installation URL is remote or not
    #
    # @return [Boolean] true if it's remote; false otherwise.
    # @see installInf2Url
    def is_network
      return @is_network unless @is_network.nil?
      scheme = URL.Parse(installInf2Url("")).fetch("scheme")
      @is_network = !LOCAL_SCHEMES.include?(scheme.downcase)
    end

  private

    # Helper method to add extra_dir to a given URL
    #
    # @param url       [String] URL
    # @param extra_dir [String] Path to add
    # @return [String] URL with the added path
    def add_extra_dir_to_url(url, extra_dir)
      parts = URL.Parse(url)
      parts["path"] = File.join(parts["path"], extra_dir)
      URL.Build(parts)
    end

    # Helper method to add ssl_verify parameter if needed
    #
    # Only applicable if scheme is 'https'.
    #
    # @param url       [String] URL
    # @return [String] URL (with ssl_verify set to 'no' if needed)
    def add_ssl_verify_no_to_url(url)
      parts = URL.Parse(url)
      return url if parts["scheme"].downcase != "https"
      log.error "Disabling certificate check for the installation repository"
      parts["query"] << "&" unless parts["query"].empty?
      parts["query"] << "ssl_verify=no"
      URL.Build(parts)
    end

    publish :function => :is_network, :type => "boolean ()"
    publish :function => :HidePassword, :type => "string (string)"
    publish :function => :RewriteCDUrl, :type => "string (string)"
    publish :function => :installInf2Url, :type => "string (string)"
  end

  InstURL = InstURLClass.new
  InstURL.main
end
