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
    def main
      textdomain "packager"
      Yast.import "Linuxrc"
      Yast.import "URL"
      Yast.import "CheckMedia"


      @is_network = true
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

    # Get device options for CD/DVD
    # @return [String] device options (devices=/dev/cdrom)
    def GetDevicesOption
      options = ""
      devicelist = Convert.convert(
        SCR.Read(path(".probe.cdrom")),
        :from => "any",
        :to   => "list <map>"
      )
      devlist = Builtins.maplist(devicelist) do |d|
        Ops.get_string(d, "dev_name", "")
      end

      ready = []
      Builtins.foreach(devicelist) do |d|
        dname = Ops.get_string(d, "dev_name", "")
        if Ops.get_boolean(d, "notready", true) == false && dname != nil &&
            dname != ""
          ready = Builtins.add(ready, dname)
        end
      end 



      devlist = deep_copy(ready) if Builtins.size(ready) != 0

      # add the Linuxrc medium to the beginning
      repo_url = Linuxrc.InstallInf("RepoURL")

      repo_url = "" if repo_url == nil

      if Builtins.regexpmatch(Builtins.tolower(repo_url), "^cd:") ||
          Builtins.regexpmatch(Builtins.tolower(repo_url), "^dvd:")
        Builtins.y2milestone(
          "Found CD/DVD device in Linuxrc RepoURL: %1",
          repo_url
        )
        linuxrc_device = Builtins.regexpsub(repo_url, "device=(.*)$", "\\1")
        if linuxrc_device != nil && linuxrc_device != ""
          linuxrc_device = Ops.add("/dev/", linuxrc_device)
          Builtins.y2milestone("Using Linuxrc device: %1", linuxrc_device)

          # remove the device if it is already in the list
          devlist = Builtins.filter(devlist) { |d| d != linuxrc_device }
          # put the linuxrc device at the beginning
          devlist = Builtins.prepend(devlist, linuxrc_device)

          Builtins.y2milestone("Using CD/DVD device list: %1", devlist)
        end
      end

      Builtins.foreach(devlist) do |d|
        if d != ""
          options = Ops.add(options, ",") if options != ""
          options = Ops.add(options, d)
        end
      end
      options = Ops.add("devices=", options) if options != ""
      options
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
    def installInf2Url(extra_dir)
      repo_url = ""

      # bnc #406162
      repo_url_from_inf = false
      Builtins.foreach(["ZyppRepoURL"]) do |in_inf_key|
        repo_url = Linuxrc.InstallInf(in_inf_key)
        if repo_url != nil && repo_url != ""
          Builtins.y2milestone(
            "Using %1 directly from install.inf: %2",
            in_inf_key,
            URL.HidePassword(repo_url)
          )
          repo_url_from_inf = true
          raise Break
        end
      end

      return repo_url if repo_url_from_inf

      # Initial repository hasn't been found in install.inf
      # Trying to guess it ...
      Builtins.y2warning("Initial repository not found in install.inf")

      options = ""
      url_tokens = {}

      instmode = Linuxrc.InstallInf("InstMode") # mode
      instmode = "cd" if instmode == nil # defaults to "CD"

      if instmode == "cd" || # CD or DVD
          instmode == "dvd"
        @is_network = false
        options = GetDevicesOption()
      elsif instmode == "hd" # Harddisk
        @is_network = false
        partition = Linuxrc.InstallInf("Partition")
        if partition != nil
          options = Ops.add(
            Ops.add("device=/dev/", partition),
            "&filesystem=auto"
          )
        else
          Builtins.y2error("no partition specified")
        end
      end

      Ops.set(url_tokens, "scheme", instmode)

      if @is_network
        username = Linuxrc.InstallInf("Username")
        if username != nil && username != ""
          Ops.set(url_tokens, "user", username)
          password = Linuxrc.InstallInf("Password")
          if password != nil && password != ""
            Ops.set(url_tokens, "pass", password)
          end
        end
        servername = Linuxrc.InstallInf("ServerName")
        server = Linuxrc.InstallInf("Server")
        serverip = Linuxrc.InstallInf("ServerIP")

        if servername != nil && servername != ""
          Ops.set(url_tokens, "host", servername)
        elsif server != nil && server != ""
          Ops.set(url_tokens, "host", server)
        elsif serverip != nil && serverip != ""
          Ops.set(url_tokens, "host", serverip)
        end
      end # is_network

      isoimg = ""
      serverdir = Linuxrc.InstallInf("Serverdir")
      if Linuxrc.InstallInf("SourceType") == "file"
        if serverdir != "" && serverdir != nil
          sd_items = Builtins.splitstring(serverdir, "/")
          sd_items = Builtins.filter(sd_items) { |i| i != "" }
          last = Ops.subtract(Builtins.size(sd_items), 1)
          isoimg = Ops.get(sd_items, last, "")
          Ops.set(sd_items, last, "")
          serverdir = Builtins.mergestring(sd_items, "/")
        end
      end

      # 	if (((instmode == "hd") || is_network)				// if serverdir needed
      # 	    && ((serverdir != nil) && (serverdir != "")))		// and is valid
      # 	{
      # 	    // for smb mounts it is usual to not have a leading slash
      # 	    if (substring (serverdir, 0, 1) != "/")
      # 		serverdir = "/" + serverdir;
      # 	}
      share = Linuxrc.InstallInf("Share")

      if extra_dir != ""
        if serverdir != nil
          # avoid too many slashes
          if Builtins.findlastof(serverdir, "/") ==
              Ops.subtract(Builtins.size(serverdir), 1)
            serverdir = Builtins.substring(
              serverdir,
              0,
              Ops.subtract(Builtins.size(serverdir), 1)
            )
          end

          slash = ""
          slash = "/" if Builtins.substring(extra_dir, 0, 1) != "/"
          serverdir = Ops.add(Ops.add(serverdir, slash), extra_dir)
          slash = ""
        else
          serverdir = extra_dir
        end
      end

      if serverdir != nil && serverdir != ""
        fs = ""
        if instmode == "ftp"
          # ftp://foo/%2fbar is %2fbar on foo  (relative)
          # ftp://foo/bar is bar on foo (absolute)
          # ftp://foo//bar is /bar on foo (relative)
          # Note: %2f is added by URL.ycp if the path starts with /
          if Builtins.substring(serverdir, 0, 3) == "%2f"
            serverdir = Ops.add("/", Builtins.substring(serverdir, 3))
          end
          fs = serverdir
        elsif instmode == "smb" && share != nil && share != ""
          fs = Ops.add(Ops.add(share, "/"), serverdir)
        else
          fs = serverdir
        end
        Ops.set(url_tokens, "path", fs)
      else
        # FIXME don't know why it is needed
        # Needed as a seperator between URL and options (!)
        # bnc#571648 - smb installation source: linuxrc path failed for YaST repositories
        if instmode == "smb" && share != nil && share != ""
          Ops.set(url_tokens, "path", Ops.add(share, "/"))
        else
          Ops.set(url_tokens, "path", "/")
        end
      end

      port = Linuxrc.InstallInf("Port")
      Ops.set(url_tokens, "port", port) if port != nil && port != ""

      url = URL.Build(url_tokens)
      option_separator = "?"

      if @is_network
        proxy = Linuxrc.InstallInf("Proxy")
        if proxy != nil && proxy != ""
          url = Ops.add(
            Ops.add(Ops.add(url, option_separator), "proxy="),
            proxy
          )
          option_separator = "&"
        end
        proxyport = Linuxrc.InstallInf("ProxyPort")
        if proxyport != nil && proxyport != ""
          url = Ops.add(
            Ops.add(Ops.add(url, option_separator), "proxyport="),
            proxyport
          )
          option_separator = "&"
        end
        proxyproto = Linuxrc.InstallInf("ProxyProto")
        if proxyproto != nil && proxyproto != ""
          url = Ops.add(
            Ops.add(Ops.add(url, option_separator), "proxyproto="),
            proxyproto
          )
          option_separator = "&"
        end
        proxyuser = Linuxrc.InstallInf("ProxyUser")
        if proxyuser != nil && proxyuser != ""
          url = Ops.add(
            Ops.add(Ops.add(url, option_separator), "proxyuser="),
            proxyuser
          )
          option_separator = "&"
        end
        proxypassword = Linuxrc.InstallInf("ProxyPassword")
        if proxypassword != nil && proxypassword != ""
          url = Ops.add(
            Ops.add(Ops.add(url, option_separator), "proxypassword="),
            proxypassword
          )
          option_separator = "&"
        end
        workgroup = Linuxrc.InstallInf("WorkDomain")
        if workgroup != nil && workgroup != ""
          url = Ops.add(
            Ops.add(Ops.add(url, option_separator), "workgroup="),
            workgroup
          )
          option_separator = "&"
        end

        if instmode == "https"
          Builtins.y2milestone("HTTPS instmode detected")

          if !SSLVerificationEnabled()
            Builtins.y2security(
              "Disabling certificate check for the installation repository"
            )

            # libzypp uses ssl_verify=no option
            url = Ops.add(Ops.add(url, option_separator), "ssl_verify=no")
            option_separator = "&"
          end
        end
      end # is_network

      if options != ""
        url = Ops.add(Ops.add(url, option_separator), options)
        option_separator = "&"
        Builtins.y2milestone("options %1", options)
      end

      url = Builtins.sformat("iso:/?iso=%1&url=%2", isoimg, url) if isoimg != ""

      Builtins.y2debug("URL %1", URL.HidePassword(url))
      url
    end

    publish :variable => :is_network, :type => "boolean"
    publish :function => :HidePassword, :type => "string (string)"
    publish :function => :RewriteCDUrl, :type => "string (string)"
    publish :function => :installInf2Url, :type => "string (string)"
  end

  InstURL = InstURLClass.new
  InstURL.main
end
