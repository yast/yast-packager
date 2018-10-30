# encoding: utf-8

require "yast"
require "yast2/hw_detection"

Yast.import "UI"
Yast.import "Pkg"

Yast.import "Wizard"
Yast.import "Sequencer"

Yast.import "NetworkService"
Yast.import "Mode"
Yast.import "Popup"
Yast.import "Label"
Yast.import "Installation"
Yast.import "PackageLock"
Yast.import "ProductFeatures"
Yast.import "Directory"
Yast.import "Progress"
Yast.import "Stage"
Yast.import "Report"
Yast.import "CommandLine"
Yast.import "PackageCallbacks"
Yast.import "SourceManager"

Yast.import "FileUtils"
Yast.import "HTTP"
Yast.import "FTP"
Yast.import "XML"
Yast.import "ProductControl"
Yast.import "AddOnProduct"
Yast.import "GetInstArgs"
Yast.import "OneClickInstallStandard"
Yast.import "Language"
Yast.import "String"
Yast.import "URL"
# documentation cop is broken for this document, so lets disable it

module Yast
  # This is a stand-alone YaST client that allows you to add suggested
  # repositories (repositories) to the libzypp.
  # How it works:
  # - First a list of servers/links is extracted from the YaST control file
  #   (/etc/YaST2/control.xml)
  # - Then servers/links are asked one by one to provide the suggested sources
  # Only installation_repo=true (trusted) links are used during installation.
  # See Bugzilla #293811.
  # @example Format of the initial list of servers:
  #   <?xml version="1.0"?>
  #   <productDefines xmlns="http://www.suse.com/1.0/yast2ns"
  #       xmlns:config="http://www.suse.com/1.0/configns">
  #     <servers config:type="list">
  #       <item>
  #         <link>http://some.server/some_link.xml</link>
  #	       <official config:type="boolean">true</official>
  #         <installation_repo config:type="boolean">true</installation_repo>
  #       </item>
  #       <item>
  #         <link>ftp://some.other.server/some_link.xml</link>
  #         <official config:type="boolean">false</official>
  #       </item>
  #     </servers>
  #   </productDefines>
  # @example Format of Suggested sources:
  #   <?xml version="1.0"?>
  #   <metapackage xmlns:os="http://opensuse.org/Standards/One_Click_Install"
  #       xmlns="http://opensuse.org/Standards/One_Click_Install">
  #     <group distversion="openSUSE Factory">
  #       <repositories>
  #         <repository recommended="true" format="yast">
  #           <name>Some name</name>
  #           <name lang="en_GB">Some name</name>
  #           <summary>Summary...</summary>
  #           <summary lang="en_GB">Summary...</summary>
  #           <description>Description...</description>
  #           <url>http://some.server/some.dir/10.3/</url>
  #         </repository>
  #         <repository recommended="false" format="yast">
  #           <name>Another name</name>
  #           <summary>Summary...</summary>
  #           <description>Description...</description>
  #           <url>http://another.server/another.dir/10.3/</url>
  #         </repository>
  #       </repositories>
  #     </group>
  #   </metapackage>
  class InstProductsourcesClient < Client
    # too low memory for using online repositories (in MiB),
    # at least 1GiB is recommended
    LOW_MEMORY_MIB = 1024

    def main
      textdomain "packager"

      Yast.include self, "installation/misc.rb"

      if AddOnProduct.skip_add_ons
        Builtins.y2milestone("Skipping module (as requested before)")
        return :auto
      end

      if GetInstArgs.going_back
        Builtins.y2milestone("Going back...")
        return :back
      end

      @args = WFM.Args
      Builtins.y2milestone("Script args: %1", @args)

      # similar to commandline mode but actually it's called from another YaST script
      @script_noncmdline_args = {}
      @script_noncmdline_args = @args.first if @args.first.is_a?(Hash)

      if Mode.normal && !@args.empty? && @script_noncmdline_args.empty?
        CommandLine.Run("id" => "inst_productsources")
        return :auto
      end

      # (Applicable only in inst-sys)
      @preselect_recommended = true

      @skip_already_used_repos = false

      @script_called_from_another = false

      if @script_noncmdline_args["skip_already_used_repos"]
        Builtins.y2milestone("Already used repos will be hidden")
        @skip_already_used_repos = true
        @script_called_from_another = true
      end

      # useful when do not want to skip already used repos, but need to call it from another client
      if @script_noncmdline_args["script_called_from_another"]
        @script_called_from_another = true
      end

      @main_link = ""

      @list_of_repos = {}

      @list_of_servers = []

      # List of IDs of URLs to be added
      @repos_to_be_used = []

      @language_long = ""
      @language_short = ""

      # Map of already used suggested repositories
      # $[ "($url|$path)" : src_id ]
      @repos_already_used = {}

      @repos_visible_now = []

      @already_selected_in_dialog = []

      # visible but not selected items
      # used for filter together with recommended repos
      # not to select them 'again' when filter matches
      @currently_NOT_selected = []

      @casesenschars = "^[abcdefghijklmnopqrstuvwyxzABCDEFGHIJKLMNOPQRSTUVWXYZ]$"

      # *********************
      Wizard.CreateDialog if Mode.normal

      @client_ret = RunMain()

      Wizard.CloseDialog if Mode.normal
      # *********************

      @client_ret
    end

    def CreateRepoId(s_url, s_path)
      Builtins.sformat("(%1|%2)", s_url, s_path)
    end

    # See bugzilla #309317
    def GetUniqueAlias(alias_orig)
      alias_orig = "" if alias_orig.nil?

      # all current aliases
      aliases = Builtins.maplist(Pkg.SourceGetCurrent(false)) do |i|
        info = Pkg.SourceGeneralData(i)
        Ops.get_string(info, "alias", "")
      end

      # default
      alias_name = alias_orig

      # repository alias must be unique
      # if it already exists add "_<number>" suffix to it
      idx = 1
      while Builtins.contains(aliases, alias_name)
        alias_name = Builtins.sformat("%1_%2", alias_orig, idx)
        idx = Ops.add(idx, 1)
      end

      if alias_orig != alias_name
        Builtins.y2milestone("Alias '%1' changed to '%2'", alias_orig, alias_name)
      end

      alias_name
    end

    # See bugzilla #307680
    # Proxy needs to be read from sysconfig and
    # set by setenv() builtin
    def InitProxySettings
      Builtins.y2milestone("Adjusting proxy settings")

      proxy_items = {
        "http_proxy"  => "HTTP_PROXY",
        "FTP_PROXY"   => "FTP_PROXY",
        "HTTPS_PROXY" => "HTTPS_PROXY",
        "NO_PROXY"    => "NO_PROXY"
      }
      use_proxy = false

      SCR.RegisterAgent(
        path(".current_proxy_settings"),
        term(:ag_ini, term(:SysConfigFile, "/etc/sysconfig/proxy"))
      )

      use_proxy = SCR.Read(path(".sysconfig.proxy.PROXY_ENABLED")) != "no"

      item_value = ""
      Builtins.foreach(proxy_items) do |proxy_item, sysconfig_item|
        item_value = Convert.to_string(
          SCR.Read(Builtins.add(path(".sysconfig.proxy"), sysconfig_item))
        )
        item_value = "" if item_value.nil?
        if use_proxy == true && item_value != ""
          Builtins.y2milestone("Adjusting '%1'='%2'", proxy_item, item_value)
          Builtins.setenv(proxy_item, item_value)
        end
      end

      SCR.UnregisterAgent(path(".current_proxy_settings"))

      nil
    end

    # Function returns whether user wants to abort the installation / configuration
    # true  - abort
    # false - do not abort
    #
    # Bugzilla #298049
    def UserWantsToAbort
      ret = UI.PollInput

      return false if ret != :abort

      function_ret = false

      # `abort pressed
      if Stage.initial
        function_ret = Popup.ConfirmAbort(:painless)
      else
        function_ret = Popup.ContinueCancelHeadline(
          # TRANSLATORS: popup header
          _("Aborting Configuration of Online Repository"),
          # TRANSLATORS: popup question
          _("Are you sure you want to abort the configuration?")
        )
      end

      Builtins.y2milestone("User decided to abort: %1", function_ret)

      # Clean-up the progress
      Progress.Finish if function_ret == true

      function_ret
    end

    def NetworkRunning
      ret = false

      # bnc #327519
      if Mode.normal
        if !NetworkService.isNetworkRunning
          Builtins.y2warning("No network is running...")
          return false
        end
      end

      loop do
        if NetworkService.isNetworkRunning
          ret = true
          break
        end

        # Network is not running
        if !Popup.AnyQuestion(
          # TRANSLATORS: popup header
          _("Network is not configured."),
          # TRANSLATORS: popup question
          _(
            "Online sources defined by product require an Internet connection.\n" \
              "\n" \
              "Would you like to configure it?"
          ),
          Label.YesButton,
          Label.NoButton,
          :yes
        )
          Builtins.y2milestone("User decided not to setup the network")
          ret = false
          break
        end

        Builtins.y2milestone("User wants to setup the network")
        # Call InstLan client
        netret = WFM.call(
          "inst_lan",
          [GetInstArgs.argmap.merge("skip_detection" => true)]
        )

        if netret == :abort
          Builtins.y2milestone("Aborting the network setup")
          break
        end
      end

      ret
    end

    # Removes slashes from the end of the URL (or just string).
    # Needed to fix bug #329629.
    def NormalizeURL(url_string)
      return url_string if url_string.nil? || url_string == ""

      if Builtins.regexpmatch(url_string, "/+$")
        url_string = Builtins.regexpsub(url_string, "(.*)/+$", "\\1")
      end

      # URL is escaped
      if Builtins.regexpmatch(url_string, "%")
        # unescape it
        url_string = URL.UnEscapeString(url_string, URL.transform_map_filename)
      end

      url_string
    end

    # Returns whether this URL/Path is already added as a source
    # -1 == not added
    # 0 or 1 or 2 ... or 'n' means 'added as source $id'
    def IsAddOnAlreadySelected(s_url, s_path)
      ret = -1

      s_url = NormalizeURL(s_url)

      Builtins.foreach(AddOnProduct.add_on_products) do |one_add_on|
        Ops.set(
          one_add_on,
          "media_url",
          NormalizeURL(Ops.get_string(one_add_on, "media_url", ""))
        )
        if Ops.get(one_add_on, "media_url") == s_url &&
            Ops.get(one_add_on, "product_dir") == s_path
          ret = Ops.get_integer(one_add_on, "media", -1)
          raise Break
        end
      end

      if Builtins.contains(SourceManager.just_removed_sources, ret)
        Builtins.y2milestone("Just deleted: %1", ret)
        ret = -1
      end

      ret
    end

    def InitializeSources
      #	if (Mode::installation()) {
      #	    y2milestone ("Sources already initialized");
      #	    return true;
      #	}

      Builtins.y2milestone("Initializing...")
      return false if !PackageLock.Check

      Pkg.TargetInitialize(Installation.destdir)
      # the fastest way
      Pkg.SourceRestore

      if !Mode.installation
        # repos_already_used
        Builtins.foreach(Pkg.SourceGetCurrent(true)) do |one_id|
          source_data = Pkg.SourceGeneralData(one_id)
          if Ops.greater_or_equal(
            IsAddOnAlreadySelected(
              Ops.get_string(source_data, "url", ""),
              Ops.get_string(source_data, "product_dir", "")
            ),
            -1
          )
            AddOnProduct.add_on_products = Builtins.add(
              AddOnProduct.add_on_products,
              "media"            => one_id,
              "media_url"        => Ops.get_string(source_data, "url", ""),
              "product_dir"      => Ops.get_string(
                source_data,
                "product_dir",
                ""
              ),
              "product"          => "",
              "autoyast_product" => ""
            )
          end
        end
      end

      true
    end

    def ReadControlFile
      software_features = ProductFeatures.GetSection("software")
      if !software_features.nil?
        @main_link = Ops.get_string(
          software_features,
          "external_sources_link",
          ""
        )
      else
        @main_link = ""
      end
      Builtins.y2milestone("Got link: %1", @main_link)

      if @main_link.nil? || @main_link == ""
        @main_link = ""
        Builtins.y2warning("No link")
        return false
      end

      Builtins.y2milestone("Using link: %1", @main_link)

      !@main_link.nil? && @main_link != ""
    end

    def UseDownloadFile
      Builtins.sformat("%1/inst_productsources_downloadfile", Directory.tmpdir)
    end

    def RemoveFileIfExists(file)
      if FileUtils.Exists(file)
        Builtins.y2milestone("Removing file: %1", file)
        return Convert.to_boolean(SCR.Execute(path(".target.remove"), file))
      end

      true
    end

    def DownloadFile(from, to)
      RemoveFileIfExists(to)
      server_response = {}

      if Builtins.regexpmatch(from, "^[hH][tT][tT][pP]://")
        from = Builtins.regexpsub(
          from,
          "^[hH][tT][tT][pP]://(.*)",
          "http://\\1"
        )

        server_response = HTTP.Get(from, to)
      elsif Builtins.regexpmatch(from, "^[fF][tT][pP]://")
        from = Builtins.regexpsub(from, "^[fF][tT][pP]://(.*)", "ftp://\\1")

        server_response = FTP.Get(from, to)
      elsif Builtins.regexpmatch(from, "^[hH][tT][tT][pP][sS]://")
        from = Builtins.regexpsub(
          from,
          "^[hH][tT][tT][pP][sS]://(.*)",
          "https://\\1"
        )

        server_response = HTTP.Get(from, to)
      else
        Builtins.y2error("Not a supported type: %1", from)
        return false
      end

      Builtins.y2milestone("Server response: %1", server_response)

      return false if server_response.nil?

      true
    end

    def ParseListOfServers(download_file)
      if !FileUtils.Exists(download_file)
        Builtins.y2error("File %1 does not exist", download_file)
        return false
      end

      xml_file_content = XML.XMLToYCPFile(download_file)

      if xml_file_content.nil?
        Builtins.y2error("Reading file %1 failed", download_file)
        return false
      end

      if xml_file_content == {}
        Builtins.y2milestone("XML file is empty")
        return false
      end

      if Ops.get_list(xml_file_content, "servers", []) == []
        Builtins.y2milestone("List of servers is empty")
        return false
      end

      @list_of_servers = Ops.get_list(xml_file_content, "servers", [])

      # bugzilla #293811
      # only installation_repo (trusted) links are used during installation
      @list_of_servers = Builtins.filter(@list_of_servers) do |one_server|
        next true if Ops.get_boolean(one_server, "installation_repo", false)

        Builtins.y2milestone(
          "Server %1 is not used during installation...",
          one_server
        )
        false
      end if Stage.initial

      true
    end

    def ParseListOfSources(download_file, url_from)
      if !FileUtils.Exists(download_file)
        Builtins.y2error("File %1 does not exist", download_file)
        return false
      end

      xml_file_content = OneClickInstallStandard.GetRepositoriesFromXML(
        download_file
      )

      if xml_file_content.nil?
        Builtins.y2error("Parsing file %1 failed", download_file)
        return false
      end

      if xml_file_content == []
        Builtins.y2milestone("XML file is empty")
        return false
      end

      Builtins.foreach(xml_file_content) do |one_repo|
        Ops.set(one_repo, "url_from", url_from)
        repo_id = CreateRepoId(
          Ops.get_string(one_repo, "url", ""),
          Ops.get_string(one_repo, "path", "/")
        )
        # do not redefine already added one
        if !Builtins.haskey(@list_of_repos, repo_id)
          Ops.set(@list_of_repos, repo_id, one_repo)
        end
      end

      true
    end

    def DownloadAndParseSources
      @list_of_repos = {}
      @list_of_servers = []

      if !DownloadFile(@main_link, UseDownloadFile())
        Builtins.y2error("Unable to download list of online repositories")
        return false
      end

      if !ParseListOfServers(UseDownloadFile())
        Builtins.y2error("Unable to parse list of servers")
        return false
      end

      Builtins.foreach(@list_of_servers) do |one_server|
        if Ops.get_string(one_server, "link", "") != ""
          Builtins.y2milestone(
            "Downloading list of repos from %1",
            Ops.get_string(one_server, "link", "")
          )

          if !DownloadFile(
            Ops.get_string(one_server, "link", ""),
            UseDownloadFile()
          )
            Builtins.y2error("Unable to download list of online repositories")
            next
          end
          if !ParseListOfSources(
            UseDownloadFile(),
            Ops.get_string(one_server, "link", "")
          )
            Builtins.y2error("Unable to parse list of repositories")
            next
          end
        end
      end

      # just for debugging purposes
      Builtins.y2debug("list_of_repos: %1", @list_of_repos)

      true
    end

    def GetCurrentLang
      cmd = Convert.to_map(
        SCR.Execute(path(".target.bash_output"), "echo -n $LANG")
      )
      ret = Builtins.tostring(Ops.get_string(cmd, "stdout", ""))

      ret = nil if ret == "C" || ret == "" || ret == "POSIX"

      Builtins.y2milestone("Using lang: %1", ret)
      ret
    end

    def ReadDialog
      actions_todo =
        # TRANSLATORS: progress step
        [
          # TRANSLATORS: progress step
          _("Check network configuration"),
          # TRANSLATORS: progress step
          _("Download list of online repositories")
        ]

      actions_doing = [
        # TRANSLATORS: progress step
        _("Checking network configuration..."),
        # TRANSLATORS: progress step
        _("Downloading list of online repositories...")
      ]

      icons_for_progress = ["yast-network.png", "yast-restore.png"]

      if !Stage.initial
        # TRANSLATORS: progress step
        actions_todo = Builtins.add(
          actions_todo,
          _("Initialize the repository manager")
        )
        # TRANSLATORS: progress step
        actions_doing = Builtins.add(
          actions_doing,
          _("Initializing the repository manager...")
        )
        icons_for_progress = Builtins.add(
          icons_for_progress,
          "yast-sw_source.png"
        )
      end

      Progress.NewProgressIcons(
        # TRANSLATORS: dialog caption
        _("Reading List of Online Repositories"),
        " ",
        Builtins.size(actions_todo),
        actions_todo,
        actions_doing,
        # TRANSLATORS: dialog help
        _(
          "<p>The packager is being initialized and \n" \
            "the list of servers downloaded from the Web.</p>\n"
        ),
        [icons_for_progress]
      )
      Wizard.SetTitleIcon("yast-network")

      Progress.NextStage

      return :abort if UserWantsToAbort()

      # Bugzilla #305554
      # Check if there is enough memory (only in inst-sys)
      # Called via WFM::call because of breaking RPM dependencies
      # on yast2-add-on package.
      if Stage.initial
        client_ret = WFM.call("inst_check_memsize")

        if client_ret == :skip
          # do not use them next time
          Installation.add_on_selected = false
          Installation.productsources_selected = false
          Builtins.y2milestone("Skipping inst_productsources")

          return :skip
        end
      end

      if !NetworkRunning()
        Builtins.y2warning("Cannot proceed, no network configured...")
        # TRANSLATORS: error report
        Report.Error(
          _("Cannot download list of repositories,\nno network configured.")
        )

        return :nosources
      end

      return :abort if UserWantsToAbort()

      # In the installation, recommended repositories will be preselected
      if Stage.initial
        # Set preselect_recommended to the correct state
        filename = Builtins.sformat(
          "%1/productsources_already_called",
          Directory.tmpdir
        )

        # Client must have been already called
        if FileUtils.Exists(filename)
          @preselect_recommended = false
          # Really for the very first time
        else
          @preselect_recommended = true
          SCR.Execute(
            path(".target.bash"),
            Builtins.sformat("touch '%1'", String.Quote(filename))
          )
          Builtins.y2milestone("Running for the first time...")
        end
        # ...but never on the running system
      else
        @preselect_recommended = false
      end

      Progress.NextStage

      return :abort if UserWantsToAbort()

      # hotfix for bug #307680
      # yast2-transfer ignores proxy settings
      # will be fixed globally after 10.3
      InitProxySettings() if Mode.normal

      return :abort if UserWantsToAbort()

      # language used for possible translations
      @language_long = GetCurrentLang() if !Stage.initial

      # fallback if no LANG variable set
      if @language_long.nil? || @language_long == ""
        @language_long = Language.language
      end

      # de_DE.UTF-8 --> de_DE
      dot_pos = Builtins.search(@language_long, ".")
      if !dot_pos.nil?
        @language_long = Builtins.substring(@language_long, 0, dot_pos)
      end

      if !@language_long.nil?
        @language_short = if Ops.greater_or_equal(Builtins.size(@language_long), 2)
          Builtins.substring(@language_long, 0, 2)
        else
          @language_long
        end
      end

      Builtins.y2milestone(
        "Preferred language: %1 %2",
        @language_long,
        @language_short
      )

      return :abort if UserWantsToAbort()

      if !ReadControlFile()
        Builtins.y2milestone("Feature not supported by the product")
        # TRANSLATORS: light-warning message
        Report.Message(
          _(
            "No product URL defined from which to download\nlist of repositories.\n"
          )
        )

        return :nosources
      end

      return :abort if UserWantsToAbort()

      if !DownloadAndParseSources()
        Builtins.y2error("Cannot download or parse repositories")
        # TRANSLATORS: warning message
        Report.Warning(
          _(
            "Unable to download list of repositories\nor no repositories defined."
          )
        )

        return :nosources
      end

      return :abort if UserWantsToAbort()

      if !Stage.initial
        Progress.NextStage
        InitializeSources()
      end

      return :abort if UserWantsToAbort()

      Progress.Finish
      Builtins.sleep(600)

      :next
    end

    # Returns a localized string using given parametters.
    #
    # @param [String] current_id to identify the source in list_of_repos map
    # @param [Array<String>] possible_keys containing which keys in the map
    #        should be tried (something is always better than amty string)
    #
    #
    # **Structure:**
    #
    #     $[
    #          // key
    #          "description" : "repository description",
    #          // "localized" + key
    #          "localized_description" : $[
    #              "en_GB" : "repository description (localized to en_GB)",
    #              ...
    #          ],
    #      ]
    def GetLocalizedString(current_id, possible_keys)
      possible_keys = deep_copy(possible_keys)
      ret = ""

      # try localized strings at first
      Builtins.foreach(possible_keys) do |possible_key|
        loc_key = Builtins.sformat("localized_%1", possible_key)
        if Ops.get_string(
          @list_of_repos,
          [current_id, loc_key, @language_long],
          ""
        ) != ""
          ret = Ops.get_string(
            @list_of_repos,
            [current_id, loc_key, @language_long],
            ""
          )
          raise Break
        elsif Ops.get_string(
          @list_of_repos,
          [current_id, loc_key, @language_short],
          ""
        ) != ""
          ret = Ops.get_string(
            @list_of_repos,
            [current_id, loc_key, @language_short],
            ""
          )
          raise Break
        end
      end

      return ret if ret != ""

      # try default strings
      Builtins.foreach(possible_keys) do |possible_key|
        if Ops.get_string(@list_of_repos, [current_id, possible_key], "") != ""
          ret = Ops.get_string(@list_of_repos, [current_id, possible_key], "")
          raise Break
        end
      end

      ret
    end

    def PrintRepositoryDescription
      current_id = Convert.to_string(
        UI.QueryWidget(Id("addon_repos"), :CurrentItem)
      )

      # Nothing selected, no description
      if current_id.nil? || current_id == ""
        UI.ChangeWidget(Id("addon_description"), :Value, "")
        return
      end

      recommended = if Ops.get_boolean(
        @list_of_repos,
        [current_id, "recommended"],
        false
      )
        Builtins.sformat(
          # TRANSLATORS: HTML-formatted summary text
          # %1 is replaced with "Yes" (currently only "Yes")
          # see *4
          _("<b>Recommended:</b> %1<br>"),
          # TRANSLATORS: used for "Recommended: Yes" (see *4)
          _("Yes")
        )
      else
        ""
      end

      description = Builtins.sformat(
        # TRANSLATORS: This is a complex HTML-formatted information about
        # selected external repository
        # It contains "key: value" pair, one per line, separated by <br> tags
        # %1 is replaced with an URL of the selected repository
        # %2 is replaced with an URL from which we've got this repository information
        # %3 is replaced with a summary text for the selected repository
        # %4 is replaced with a description text for the selected repository
        # %5 is replaced with an emty string or "Recommended: Yes" (*4)
        _(
          "<p>\n" \
            "<b>URL:</b> %1<br>\n" \
            "<b>Linked from:</b> %2<br>\n" \
            "<b>Summary:</b> %3<br>\n" \
            "<b>Description:</b> %4<br>\n" \
            "%5\n" \
            "</p>"
        ),
        Ops.get_string(@list_of_repos, [current_id, "url"], ""),
        Ops.get_string(@list_of_repos, [current_id, "url_from"], ""),
        GetLocalizedString(current_id, ["summary", "name"]),
        GetLocalizedString(current_id, ["description"]),
        recommended
      )

      UI.ChangeWidget(Id("addon_description"), :Value, description)

      nil
    end

    def IsSelectedInDialog(repo_id)
      Builtins.contains(@already_selected_in_dialog, repo_id)
    end

    # This function fills up the table repositories found on a web servers
    # linked from control file.
    #
    # Order of appearance:
    #   Running system: sorted by repository name
    #   Inst-Sys:       sorted by "recommended tag", then by name
    #
    # Preselections:
    #   Running sustem: no repositories are preselected
    #   Inst-Sys:       "recommended" repositories are prelected
    #                   but only for the first time when running this client
    #
    # @see bugzilla #297628
    def InitRepositoriesWidget(filter_string, first_init, _current_item)
      items = []
      recommended_items = []
      @repos_visible_now = []
      counter = -1

      # used for recommended repos
      some_repo_already_selected = false

      #	boolean current_item_is_listed = false;

      Builtins.foreach(@list_of_repos) do |url, one_repo|
        repo_id = CreateRepoId(
          Ops.get_string(one_repo, "url", ""),
          Ops.get_string(one_repo, "path", "/")
        )
        src_id = IsAddOnAlreadySelected(
          Ops.get_string(one_repo, "url", ""),
          Ops.get_string(one_repo, "path", "/")
        )
        already_used = false
        # repository has been already initialized
        if Ops.greater_than(src_id, -1)
          Ops.set(@repos_already_used, repo_id, src_id)
          already_used = true

          # in some modes, it's required to hide alerady used repos
          if @skip_already_used_repos
            if Builtins.contains(SourceManager.just_removed_sources, src_id)
              Builtins.y2milestone(
                "Not skipping repo %1, known as removed ID %2",
                repo_id,
                src_id
              )
            end

            next
          end
          # repository has been already selected
        elsif IsSelectedInDialog(repo_id)
          already_used = true
        end
        # If this variable is true, no recoomended repos are preselected
        if already_used
          some_repo_already_selected = true
          # List of not-selected repos
        elsif !first_init
          @currently_NOT_selected = Builtins.add(
            @currently_NOT_selected,
            repo_id
          )
        end
        # bugzilla #358001
        # filter works with localized names
        localized_name = GetLocalizedString(repo_id, ["name", "url"])
        # do filter (filter after some_repo_already_selected is set)
        if filter_string != ""
          # neither "url" nor "name" matching
          if !Builtins.regexpmatch(
            Ops.get_string(one_repo, "url", ""),
            filter_string
          ) &&
              !Builtins.regexpmatch(localized_name, filter_string)
            next
          end
        end
        counter = Ops.add(counter, 1)
        if url == ""
          Builtins.y2error("Repository %1 has no 'url'", one_repo)
          next
        end
        # always fill-up this list -- later used for sorting using 'recommended' tag
        # Bugzilla #297628
        recommended = Ops.get_boolean(one_repo, "recommended", false)
        if recommended
          recommended_items = Builtins.add(recommended_items, repo_id)
        end

        Ops.set(items, counter, Item(Id(repo_id), localized_name, already_used))
        Ops.set(@repos_visible_now, counter, repo_id)
      end

      items = Builtins.sort(items) do |one_item_a, one_item_b|
        Ops.less_than(
          Ops.get_string(one_item_a, 1, ""),
          Ops.get_string(one_item_b, 1, "")
        )
      end

      # Preselect the recommended repositories when ne repository has been selected yet
      if @preselect_recommended
        tmp_items = deep_copy(items)
        counter2 = -1
        current_repoid = ""

        Builtins.foreach(tmp_items) do |one_item|
          counter2 = Ops.add(counter2, 1)
          current_repoid = Ops.get_string(one_item, [0, 0], "---")
          # recommended_items contain list of all recommended items (visible on the screen)
          if Builtins.contains(recommended_items, current_repoid)
            Builtins.y2milestone("Preselecting: %1", current_repoid)
            Ops.set(one_item, 2, true)
            Ops.set(items, counter2, one_item)
          end
        end
      end

      # In the initial stage, repos are additionally sorted whether they are recommended or not
      #	if (Stage::initial()) {
      items = Builtins.sort(items) do |one_item_a, one_item_b|
        Ops.greater_than(
          Builtins.contains(
            recommended_items,
            Ops.get_string(one_item_a, [0, 0], "")
          ),
          Builtins.contains(
            recommended_items,
            Ops.get_string(one_item_b, [0, 0], "")
          )
        )
      end
      #	}

      UI.ChangeWidget(Id("addon_repos"), :Items, items)

      # disabled
      #	if (current_item_is_listed) {
      #	    UI::ChangeWidget (`id ("addon_repos"), `CurrentItem, current_item);
      #	} else if (size (items) > 0) {
      #	    UI::ChangeWidget (`id ("addon_repos"), `CurrentItem, items[0,0,0]:"");
      #	}

      PrintRepositoryDescription()

      # Preselect recommended repos only once
      @preselect_recommended = false

      nil
    end

    def StoreSelectedInDialog
      # remember already selected items before filtering
      currently_selected = Convert.convert(
        UI.QueryWidget(Id("addon_repos"), :SelectedItems),
        from: "any",
        to:   "list <string>"
      )

      # all visible repos - just now
      Builtins.foreach(@repos_visible_now) do |one_repo|
        # visible repository is not selected
        if !Builtins.contains(currently_selected, one_repo)
          # was already selected
          if Builtins.contains(@already_selected_in_dialog, one_repo)
            @already_selected_in_dialog = Builtins.filter(
              @already_selected_in_dialog
            ) { |o_r| o_r != one_repo }
          end

        # visible repository is selected now
        # wasn't selected
        elsif !Builtins.contains(@already_selected_in_dialog, one_repo)
          # add it
          @already_selected_in_dialog = Builtins.add(
            @already_selected_in_dialog,
            one_repo
          )
        end
      end

      nil
    end

    def HandleSelectedSources
      StoreSelectedInDialog()
      @repos_to_be_used = deep_copy(@already_selected_in_dialog)

      # FIXME: handle no repositories selected (warning)

      # FIXME: a lot of repositories selected (warning)

      true
    end

    def EscapeChars(input)
      return input if input == "" || input.nil?

      # \ must be the first character!
      escape = "\\(){}[]+^$|"
      ret = input

      i = 0
      sz = Builtins.size(escape)

      while Ops.less_than(i, sz)
        ch = Builtins.substring(escape, i, 1)
        Builtins.y2debug("Escaping %1", ch)
        ret = Builtins.mergestring(
          Builtins.splitstring(ret, ch),
          Ops.add("\\", ch)
        )
        i = Ops.add(i, 1)
      end

      ret
    end

    # Example:
    # <- "aBc/iop"
    # -> "[Aa][Bb][Cc]/[Ii][Oo][Pp]"
    def MakeCaseInsensitiveRegexp(input)
      return input if input.nil? || input == ""

      characters = []
      counter = 0
      input_size = Builtins.size(input)

      while Ops.less_than(counter, input_size)
        Ops.set(characters, counter, Builtins.substring(input, counter, 1))
        counter = Ops.add(counter, 1)
      end
      input = ""

      Builtins.foreach(characters) do |onechar|
        if Builtins.regexpmatch(onechar, @casesenschars)
          onechar = Builtins.sformat(
            "[%1%2]",
            Builtins.toupper(onechar),
            Builtins.tolower(onechar)
          )
        end
        input = Ops.add(input, onechar)
      end

      input
    end

    def HandleFilterButton
      StoreSelectedInDialog()

      filter_string = Convert.to_string(
        UI.QueryWidget(Id("filter_text"), :Value)
      )
      current_item = Convert.to_string(
        UI.QueryWidget(Id("addon_repos"), :CurrentItem)
      )

      filter_string = EscapeChars(filter_string)
      filter_string = MakeCaseInsensitiveRegexp(filter_string)

      InitRepositoriesWidget(filter_string, false, current_item)

      UI.SetFocus(Id("filter_text"))

      nil
    end

    def SourcesDialog
      Wizard.SetContents(
        # TRANSLATORS: dialog caption
        _("List of Online Repositories"),
        VBox(
          HBox(
            HVSquash(
              MinWidth(20, InputField(Id("filter_text"), Opt(:hstretch), ""))
            ),
            # TRANSLATORS: push button
            Bottom(PushButton(Id("do_filter"), Opt(:default), _("&Filter"))),
            HStretch()
          ),
          VSpacing(0.5),
          VWeight(
            2,
            MultiSelectionBox(
              Id("addon_repos"),
              Opt(:notify, :hstretch),
              # TRANSLATORS: multi-selection box, contains a list of online repositories
              _("&Use Additional Online Repositories"),
              []
            )
          ),
          VSpacing(0.5),
          # TRANSLATORS: Rich-text widget (HTML)
          Left(Label(_("Repository Description"))),
          VWeight(1, RichText(Id("addon_description"), ""))
        ),
        # TRANSLATORS: dialog help 1/3
        _(
          "<p>List of default online repositories.\nClick on a repository for details.</p>\n"
        ) +
          (
            if Stage.initial
              # TRANSLATORS: dialog help 2/3 (version for installation)
              _(
                "<p>Select the online repositories you want to use then click <b>Next</b>.</p>\n"
              )
            else
              # TRANSLATORS: dialog help 2/3 (version for running system)
              _(
                "<p>Select the online repositories you want to use then click <b>Finish</b>.</p>\n"
              )
            end
          ) +
          # TRANSLATORS: dialog help 3/3
          (
            if @skip_already_used_repos
              ""
            else
              _("<p>To remove a used repository, simply deselect it.</p>")
            end
          ),
        Mode.installation ? GetInstArgs.enable_back : false,
        Mode.installation ? GetInstArgs.enable_next : true
      )
      Wizard.SetTitleIcon("yast-sw_source")

      if !Stage.initial
        Wizard.DisableBackButton

        if @script_called_from_another
          Wizard.SetAbortButton(:cancel, Label.CancelButton)
          Wizard.SetNextButton(:next, Label.OKButton)
        else
          Wizard.SetNextButton(:next, Label.FinishButton)
        end
      else
        # Next button must be always enabled
        # bnc #392111
        Wizard.RestoreNextButton
        Wizard.EnableNextButton
        Wizard.DisableBackButton

        # from add-ons
        if @script_called_from_another
          Wizard.SetAbortButton(:cancel, Label.CancelButton)
        else
          Wizard.RestoreAbortButton
        end
      end

      @repos_already_used = {}
      InitRepositoriesWidget("", true, nil)

      dialog_ret = nil

      # warn if there is low memory
      check_memory_size

      loop do
        dialog_ret = UI.UserInput

        case dialog_ret
        when :back
          Builtins.y2milestone("Going back")
          dialog_ret = :special_go_back
          break
        when :next
          HandleSelectedSources() ? break : next
        when :abort, :cancel
          dialog_ret = :abort
          if Stage.initial
            # from add-ons
            if @script_called_from_another
              Builtins.y2milestone("Back to add-ons")
              break
              # from workflow
            elsif Popup.ConfirmAbort(:painless)
              break
            end
          elsif @script_called_from_another
            break
          elsif Popup.ContinueCancelHeadline(
            # TRANSLATORS: popup header
            _("Aborting Configuration of Online Repository"),
            # TRANSLATORS: popup question
            _("Are you sure you want to abort the configuration?")
          )
            break
          end
        when "addon_repos"
          PrintRepositoryDescription()
        when "do_filter"
          HandleFilterButton()
        else
          Builtins.y2error("Unknown ret: %1", dialog_ret)
        end
      end

      Wizard.EnableBackButton
      Wizard.RestoreAbortButton

      Convert.to_symbol(dialog_ret)
    end

    def CreateAndAdjustWriteProgress(actions_todo, actions_doing)
      actions_doing = deep_copy(actions_doing)
      Builtins.y2milestone("Creating new Write() progress")

      Progress.New(
        # TRANSLATORS: dialog caption
        _("Writing List of Online Repositories"),
        " ",
        Builtins.size(actions_todo.value),
        actions_todo.value,
        actions_doing,
        # TRANSLATORS: dialog help
        _("<p>The repository manager is downloading repository details...</p>")
      )

      Wizard.SetTitleIcon("yast-sw_source")

      nil
    end

    def CreateSource(url, pth, repo_name, _actions_todo, _actions_doing, _no_progress_updates)
      src_id = nil

      repo_type = Pkg.RepositoryProbe(url, pth)
      Builtins.y2milestone("Probed repository type: %1", repo_type)

      # probing succeeded?
      if !repo_type.nil? && repo_type != "NONE"
        # create alias in form "<hostname>-<last_path_element>"
        parsed_url = URL.Parse(url)
        alias_name = Ops.get_string(parsed_url, "host", "")

        path_parts = Builtins.splitstring(
          Ops.get_string(parsed_url, "path", ""),
          "/"
        )
        # remove empty parts
        path_parts = Builtins.filter(path_parts) do |p|
          Ops.greater_than(Builtins.size(p), 0)
        end

        if Ops.greater_than(Builtins.size(path_parts), 0)
          suffix = Ops.get(
            path_parts,
            Ops.subtract(Builtins.size(path_parts), 1),
            ""
          )

          if Builtins.regexpmatch(suffix, "[0-9]+$") &&
              Ops.greater_than(Builtins.size(path_parts), 1)
            Builtins.y2milestone("Version string detected in path element")
            suffix = Ops.get(
              path_parts,
              Ops.subtract(Builtins.size(path_parts), 2),
              ""
            )
          end

          alias_name = Ops.add(Ops.add(alias_name, "-"), suffix)
        end

        alias_name = GetUniqueAlias(alias_name)
        Builtins.y2milestone("Using alias: %1", alias_name)

        src_id = Pkg.RepositoryAdd(
          "enabled"   => false,
          "name"      => repo_name,
          "base_urls" => [url],
          "prod_dir"  => pth,
          # alias needs to be unique
          # bugzilla #309317
          "alias"     => alias_name,
          "type"      => repo_type
        )
      end

      if src_id.nil?
        error = ""
        details = ""

        if repo_type.nil?
          error = Pkg.LastError
          if Ops.greater_than(Builtins.size(error), 0)
            error = Ops.add("\n\n", error)
          end

          details = Pkg.LastErrorDetails
          if Ops.greater_than(Builtins.size(details), 0)
            details = Ops.add("\n\n", details)
          end
        end

        Report.Error(
          Ops.add(
            Ops.add(
              Builtins.sformat(
                # TRANSLATORS: pop-up error message
                # %1 is replaced with a repository name or URL
                _("Adding repository %1 failed."),
                repo_name != "" ? repo_name : url
              ),
              error
            ),
            details
          )
        )
        # FIXME: retry ?
        return false
      end

      if !AddOnProduct.AcceptedLicenseAndInfoFile(src_id)
        Pkg.SourceDelete(src_id)
        return false
      end

      if !Pkg.SourceRefreshNow(src_id)
        Report.Error(
          Ops.add(
            Ops.add(
              Builtins.sformat(
                # TRANSLATORS: pop-up error message
                # %1 is replaced with a repository name or URL
                _("Adding repository %1 failed."),
                repo_name != "" ? repo_name : url
              ),
              "\n"
            ),
            Pkg.LastError
          )
        )
        return false
      end

      if !Pkg.SourceSetEnabled(src_id, true)
        Report.Error(
          Ops.add(
            Ops.add(
              Builtins.sformat(
                # TRANSLATORS: pop-up error message
                # %1 is replaced with a repository name or URL
                _("Adding repository %1 failed."),
                repo_name != "" ? repo_name : url
              ),
              "\n"
            ),
            Pkg.LastError
          )
        )
        return false
      end

      if Stage.initial
        AddOnProduct.Integrate(src_id)

        prod = Pkg.SourceProductData(src_id)
        Builtins.y2milestone("Product Data: %1", prod)

        repo_id = CreateRepoId(url, pth)
        Builtins.y2milestone("Addind repository with ID: %1", repo_id)

        AddOnProduct.add_on_products = Builtins.add(
          AddOnProduct.add_on_products,
          "media"            => src_id,
          "product"          => repo_name,
          "autoyast_product" => Ops.get_string(prod, "productname", ""),
          "media_url"        => url,
          "product_dir"      => pth
        )
      end

      nil
    end

    def WriteDialog
      actions_todo = []
      actions_doing = []
      at_once = false

      repos_to_be_deleted = []

      # repos_to_be_used
      # repos_already_used

      # y2milestone ("ToBeDeleted: %1", repos_to_be_deleted);
      # y2milestone ("ReposAlreadyUsed: %1", repos_already_used);
      # y2milestone ("ReposToBeUsed: %1", repos_to_be_used);

      # go through all already initialized repositories
      # add unselected repository to 'repos_to_be_deleted'
      # remove already selected repository from 'repos_to_be_used'

      # Currently, Mode::normal doesn't show already used repos
      # (when 'skip_already_used_repos' is 'true')
      # and thus doesn't support removing them
      Builtins.foreach(@repos_already_used) do |id_used, src_id|
        # was used, but isn't anymore
        if !Builtins.contains(@repos_to_be_used, id_used)
          repos_to_be_deleted = Builtins.add(repos_to_be_deleted, src_id)

          # was used and remains used
        else
          Builtins.y2milestone("NotUsingAgain: %1", id_used)
          @repos_to_be_used = Builtins.filter(@repos_to_be_used) do |id_already_used|
            id_used != id_already_used
          end
        end
      end if @skip_already_used_repos != true

      # y2milestone ("WillBeDeleted: %1", repos_to_be_deleted);
      # y2milestone ("WillBeUsed: %1", repos_to_be_used);

      if repos_to_be_deleted != []
        Builtins.y2milestone("Repos to be deleted: %1", repos_to_be_deleted)

        # TRANSLATORS: progress step
        actions_todo = [_("Delete deselected online repositories")]
        # TRANSLATORS: progress step
        actions_doing = [_("Deleting deselected online repositories...")]
      end

      if Ops.greater_than(Builtins.size(@repos_to_be_used), 12)
        at_once = true
        # TRANSLATORS: progress step
        actions_todo = Builtins.add(
          actions_todo,
          _("Add all selected online repositories")
        )
        # TRANSLATORS: progress step
        actions_doing = Builtins.add(
          actions_doing,
          _("Adding all selected online repositories...")
        )
      else
        Builtins.foreach(@repos_to_be_used) do |repo_id|
          actions_todo = Builtins.add(
            actions_todo,
            Builtins.sformat(
              # TRANSLATORS: progress step
              # %1 is replaced with repository name or URL
              _("Add repository: %1"),
              GetLocalizedString(repo_id, ["name", "url"])
            )
          )
          actions_doing = Builtins.add(
            actions_doing,
            Builtins.sformat(
              # TRANSLATORS: progress step,
              # %1 is replaced with repository name or URL
              _("Adding repository: %1 ..."),
              GetLocalizedString(repo_id, ["name", "url"])
            )
          )
        end
      end

      if Builtins.size(actions_todo).zero?
        Builtins.y2milestone("Nothing to do...")
        return :next
      end

      # Create writing dialog - initial state
      actions_todo_ref = arg_ref(actions_todo)
      CreateAndAdjustWriteProgress(actions_todo_ref, actions_doing)
      actions_todo = actions_todo_ref.value

      return :abort if UserWantsToAbort()

      if repos_to_be_deleted != []
        Progress.NextStage
        Builtins.foreach(repos_to_be_deleted) do |src_id|
          success = Pkg.SourceDelete(src_id)
          Builtins.y2error("Couldn't delete repository %1", src_id) if !success
          AddOnProduct.Disintegrate(src_id)
          # filter it also from the list of Add-Ons
          AddOnProduct.add_on_products = Builtins.filter(
            AddOnProduct.add_on_products
          ) do |one_addon|
            Ops.get_integer(one_addon, "media", -1) != src_id
          end
        end
      end

      return :abort if UserWantsToAbort()

      # One progress stage for all repositories
      Progress.NextStage if at_once

      Builtins.foreach(@repos_to_be_used) do |repo_id|
        # If not at once, call one stage per repository
        Progress.NextStage if !at_once
        next :abort if UserWantsToAbort()
        actions_todo_ref = arg_ref(actions_todo)
        actions_doing_ref = arg_ref(actions_doing)
        CreateSource(
          Ops.get_string(@list_of_repos, [repo_id, "url"], ""),
          Ops.get_string(@list_of_repos, [repo_id, "path"], "/"),
          GetLocalizedString(repo_id, ["name"]),
          actions_todo_ref,
          actions_doing_ref,
          at_once
        )
        actions_todo = actions_todo_ref.value
        actions_doing = actions_doing_ref.value
      end

      return :abort if UserWantsToAbort()

      # Redraw installation wizard
      if Stage.initial
        UpdateWizardSteps()
        # Store repositories
      else
        Pkg.SourceSaveAll
      end

      Progress.Finish

      Builtins.sleep(1000) if !Stage.initial

      :next
    end

    def RunMain
      aliases = {
        "read"    => -> { ReadDialog() },
        "sources" => -> { SourcesDialog() },
        "write"   => -> { WriteDialog() }
      }

      sequence = {
        "ws_start" => "read",
        "read"     => {
          next:      "sources",
          # not enough memory
          skip:      :next,
          nosources: :next,
          abort:     :abort
        },
        "sources"  => {
          special_go_back: :back,
          next:            "write",
          abort:           :abort
        },
        "write"    => { next: :next, abort: :abort }
      }

      ret = Sequencer.Run(aliases, sequence)
      Builtins.y2milestone("Sequencer::Run %1", ret)

      Convert.to_symbol(ret)
    end

  private

    # display a warning when online repositories are used on a system
    # with low memory (the installer may crash or freeze, see bnc#854755)
    def check_memory_size
      return if !Mode.installation
      # less than LOW_MEMORY_MIB RAM, the 64MiB buffer is for possible
      # rounding in hwinfo memory detection (bsc#1045915)
      return if Yast2::HwDetection.memory >= ((LOW_MEMORY_MIB - 64) << 20)

      Report.Warning(_("Low memory detected.\n\nUsing online repositories " \
            "during initial installation with less than\n" \
            "%dMiB system memory is not recommended.\n\n" \
            "The installer may crash or freeze if the additional package data\n" \
            "need too much memory.\n\n" \
            "Using the online repositories later in the installed system is\n" \
            "recommended in this case.") % LOW_MEMORY_MIB)
    end
  end
end
