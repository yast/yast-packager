require "yast"

require "shellwords"
require "y2packager/resolvable"

# Yast namespace
module Yast
  # Representation of the configuration of source-manager.
  # Input and output routines.
  class SourceManagerClass < Module
    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "packager"

      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "Summary"
      Yast.import "HTML"
      Yast.import "Mode"
      Yast.import "URL"
      Yast.import "Linuxrc"
      Yast.import "Installation"
      Yast.import "String"

      @newSources = []

      @numSources = 0

      @sourceStates = []

      @sourceStatesIn = []

      @sourceStatesOut = []

      @url_tokens = {}

      @currentUrl = ""

      # Sources that are removed in memory but still not in libzypp
      # They will be removed in Write() at the end
      @just_removed_sources = []

      # Data was modified?
      @modified = false

      @proposal_valid = false
    end

    # Abort function
    # return boolean return true if abort
    def AbortFunction
      false
    end

    # Abort function
    # @return [Boolean] return true if abort
    def Abort
      return false if fun_ref(method(:AbortFunction), "boolean ()").nil?

      AbortFunction()
    end

    # Data was modified?
    # @return true if modified
    def Modified
      Builtins.y2debug("modified=%1", @modified)
      # return modified;
      @sourceStatesIn != @sourceStatesOut
    end

    def ReadSources
      success = Pkg.SourceStartManager(false)
      return success if !success

      @sourceStates = Pkg.SourceStartCache(false)
      @sourceStatesIn = Pkg.SourceEditGet
      @sourceStatesOut = deep_copy(@sourceStatesIn)
      true
    end

    # Read all source-manager settings
    # @return true on success
    def Read
      # SourceManager read dialog caption
      caption = _("Initializing Available Repositories")

      steps = 2

      # We do not set help text here, because it was set outside
      Progress.New(
        caption,
        " ",
        steps,
        [
          # Progress stage 1/3
          _("Read configured repositories"),
          # Progress stage 2/3
          _("Detect available repositories via SLP")
        ],
        [
          # Progress step 1/3
          _("Reading configured repositories..."),
          # Progress step 2/3
          _("Detecting available repositories..."),
          # Progress finished
          _("Finished")
        ],
        ""
      )

      # read database
      return false if Abort()

      Progress.NextStage

      # Error message
      Report.Error(_("Cannot read repositories.")) if !ReadSources()

      # read another database
      return false if Abort()

      Progress.NextStep

      return false if Abort()

      # Progress finished
      Progress.NextStage

      return false if Abort()

      @modified = false
      true
    end

    # Commit changed repositories
    def CommitSources
      Builtins.y2debug("In: %1  Out: %2", @sourceStatesIn, @sourceStatesOut)
      success = false
      loop do
        success = Pkg.SourceEditSet(@sourceStatesOut)
        break if success

        # popup message header
        message1 = _("Unable to save changes to the repository.\n")
        # popup message, after message header, header of details
        message2 = Ops.add(_("Details:") + "\n", Pkg.LastError)
        # end of popup message, question
        message2 = Ops.add(Ops.add(message2, "\n"), _("Try again?"))

        tryagain = Popup.YesNo(Ops.add(Ops.add(message1, "\n"), message2))
        break if !tryagain
      end
      success
    end

    # Write all repository-manager settings
    # @return true on success
    def Write
      # SourceManager read dialog caption
      caption = _("Saving Repository Configuration")

      steps = 1

      # We do not set help text here, because it was set outside
      Progress.New(
        caption,
        " ",
        steps,
        [
          # Progress stage 1/1
          _("Write repository settings")
        ],
        [
          # Progress step 1/1
          _("Writing the settings..."),
          # Progress finished
          _("Finished")
        ],
        ""
      )

      # write settings
      return false if Abort()

      Progress.NextStage
      # Error message

      exit = CommitSources()

      return false if Abort()

      # Progress finished
      Progress.NextStage

      return false if Abort()

      exit
    end

    # Get all repository-manager settings from the first parameter
    # (For use by autoinstallation.)
    # @param [Hash] _settings The YCP structure to be imported.
    # @return [Boolean] True on success
    def Import(_settings)
      true
    end

    # Dump the repository-manager settings to a single map
    # (For use by autoinstallation.)
    # @return [Hash] Dumped settings (later acceptable by Import ())
    def Export
      {}
    end

    # Get Repository ID by index
    def GetSrcIdByIndex(idx)
      Ops.get_integer(@sourceStatesOut, [idx, "SrcId"], -1)
    end

    # Set current used repository URL by index
    def SetUrlByIndex(idx)
      src_id = Ops.get_integer(@sourceStatesOut, [idx, "SrcId"], -1)
      @currentUrl = Ops.get_string(Pkg.SourceGeneralData(src_id), "url", "")
      nil
    end

    # Get Repository ID when only URL is known
    def getSourceId(url)
      @numSources = Builtins.size(@sourceStatesOut)
      i = 0
      id = -1
      while Ops.less_than(i, @numSources)
        generalData = Pkg.SourceGeneralData(
          Ops.get_integer(@sourceStatesOut, [i, "SrcId"], -1)
        )
        if Ops.get_string(generalData, "url", "") == url
          id = Ops.get_integer(@sourceStatesOut, [i, "SrcId"], -1)
          break
        end

        i = Ops.add(i, 1)
      end

      id
    end

    # Gather Repository Metadata
    def SourceData(source)
      g = Pkg.SourceGeneralData(source)
      Builtins.y2milestone("generalData: %1", g)
      p = Pkg.SourceProductData(source)
      p = {} if p.nil?

      Builtins.y2milestone("productData: %1", p)
      Builtins.union(g, p)
    end

    # Create a repository from an URL
    def createSource(url)
      return :cancel if url == ""

      if !Mode.commandline
        UI.OpenDialog(
          VBox(VSpacing(0.2), Label(_("Adding repository...")), VSpacing(0.2))
        )
      end
      @newSources = Pkg.SourceScan(url, "")

      UI.CloseDialog if !Mode.commandline

      if Builtins.size(@newSources).zero?
        message1 = Builtins.sformat(
          _("Unable to create repository\nfrom URL '%1'."),
          URL.HidePassword(url)
        )

        message2 = Ops.add(_("Details:") + "\n", Pkg.LastError)
        # end of popup message, question
        message2 = Ops.add(Ops.add(message2, "\n"), _("Try again?"))

        tryagain = Popup.YesNo(Ops.add(Ops.add(message1, "\n"), message2))
        if tryagain
          :again
        else
          :cancel
        end
      else
        ul_sources = Builtins.filter(@newSources) do |s|
          src_data = Pkg.SourceGeneralData(s)
          src_type = Ops.get_string(src_data, "type", "")
          src_type == "YaST"
        end
        if Builtins.size(ul_sources).zero?
          if !Popup.AnyQuestion(
            Popup.NoHeadline,
            # continue-back popup
            _(
              "There is no product information available at the given location.\n" \
                "If you expected to to point a product, go back and enter\n" \
                "the correct location.\n" \
                "To make rpm packages located at the specified location available\n" \
                "in the packages selection, continue.\n"
            ),
            Label.ContinueButton,
            Label.BackButton,
            :focus_yes
          )
            return :again
          end
        end
        Builtins.foreach(@newSources) do |id|
          sourceState = { "SrcId" => id, "enabled" => true }
          @sourceStatesOut = Builtins.add(@sourceStatesOut, sourceState)
        end
        :ok
      end
    end

    # Delete repository by Repository ID
    def deleteSourceBySrcId(src_id)
      Builtins.y2debug("removing repository: %1 %2", src_id, @sourceStatesOut)
      @numSources = Builtins.size(@sourceStatesOut)
      i = 0

      while Ops.less_than(i, @numSources)
        if Ops.get_integer(@sourceStatesOut, [i, "SrcId"], -1) == src_id
          @sourceStatesOut = Builtins.remove(@sourceStatesOut, i)
          break
        end

        i = Ops.add(i, 1)
      end
      nil
    end

    # Delete Repository by the repository index
    def deleteSourceByIndex(idx)
      @sourceStatesOut = Builtins.remove(@sourceStatesOut, idx)
      nil
    end

    # Delete Repository by repository URL
    def deleteSourceByUrl(url)
      deleteSourceBySrcId(getSourceId(url))
      nil
    end

    # Create Summary Item
    def createItem(_index, source)
      source = deep_copy(source)
      id = Ops.get_integer(source, "SrcId", 0)
      generalData = Pkg.SourceGeneralData(id)
      productData = Pkg.SourceProductData(id)
      sitem = ""
      # status info, to be used inside summary
      status = Ops.get_boolean(source, "enabled", true) ? _("Enabled") : _("Disabled")
      color = Ops.get_boolean(source, "enabled", true) ? "#006600" : "#FF0000"
      sitem = Ops.add(
        sitem,
        HTML.Colorize(Ops.add(Ops.add("[", status), "] "), color)
      )
      # translators: name of a repository if no other idenfication found
      sitem = Ops.add(
        sitem,
        Ops.get_locale(
          productData,
          "label",
          Ops.get_locale(generalData, "type", _("unknown"))
        )
      )
      sitem = Ops.add(
        Ops.add(Ops.add(sitem, " ( "), Ops.get_string(generalData, "url", "")),
        ")"
      )
      sitem
    end

    # Create Repository Item for Overview
    def createOverviewItem(index, source)
      source = deep_copy(source)
      id = Ops.get_integer(source, "SrcId", 0)
      generalData = Pkg.SourceGeneralData(id)
      productData = Pkg.SourceProductData(id)

      item = Item(
        Id(index),
        # corresponds to the "Enable/Disable" button
        Ops.get_boolean(source, "enabled", true) ? _("On") : _("Off"),
        Ops.get_locale(
          productData,
          "label",
          Ops.get_locale(generalData, "type", _("Unknown"))
        ),
        Ops.get_string(generalData, "url", "")
      )

      deep_copy(item)
    end

    # Handle Multiple repositories URLs (order/instorder)
    def HandleMultipleSources(url)
      Pkg.SourceStartManager(false)
      initial_source = Ops.get(Pkg.SourceScan(url, ""), 0)
      if initial_source.nil?
        Builtins.y2error("No repository in '%1'", url)
        return false
      end

      false
    end

    # Create a textual summary and a list of unconfigured cards
    # @return summary of the current configuration
    def Summary
      summary = ""
      # summary header
      summary = Summary.AddHeader(summary, _("Configured Repositories"))
      summary = Summary.OpenList(summary)
      @numSources = Builtins.size(@sourceStatesOut)
      i = 0
      while Ops.less_than(i, @numSources)
        summary = Summary.AddListItem(
          summary,
          createItem(i, Ops.get(@sourceStatesOut, i, {}))
        )
        i = Ops.add(i, 1)
      end
      summary = Summary.CloseList(summary)

      [summary, []]
    end

    # Create an overview table with all configured cards
    # @return table items
    def Overview
      @numSources = Builtins.size(@sourceStatesOut)
      i = 0
      source_overview = []
      while Ops.less_than(i, @numSources)
        source_overview = Builtins.add(
          source_overview,
          createOverviewItem(i, Ops.get(@sourceStatesOut, i, {}))
        )
        i = Ops.add(i, 1)
      end
      deep_copy(source_overview)
    end

    # Parse a URL query (already unescaped) to a map.
    # If no equal sign, the value will be nil.
    # @param [String] query foo=bar&baz=qux
    # @return [Hash] hash with "param" => "value" mapping,
    #    e.g. ["foo": "bar", "baz": "qux"]
    def ParseUrlQuery(query)
      q_items = Builtins.splitstring(query, "&")
      q_map = Builtins.listmap(q_items) do |q_item|
        eqpos = Builtins.search(q_item, "=")
        if eqpos.nil?
          { q_item => nil }
        else
          key = Builtins.substring(q_item, 0, eqpos)
          val = Builtins.substring(q_item, Ops.add(eqpos, 1))
          { key => val }
        end
      end
      deep_copy(q_map)
    end

    # @param [String] attr SourceGeneralData item
    # @return For existing repositories, get a mapping from an attribute to the id
    def get_attr_to_id(attr)
      src_ids = Pkg.SourceGetCurrent(
        false # enabled only?
      )
      a2i = Builtins.listmap(src_ids) do |src_id|
        gendata = Pkg.SourceGeneralData(src_id)
        alias_name = Ops.get_string(gendata, attr, "")
        { alias_name => src_id }
      end
      deep_copy(a2i)
    end

    # @return For existing repositories, get a mapping from the alias to the id
    def get_alias_to_id
      get_attr_to_id("alias")
    end

    # @return For existing repositories, get a mapping from the URL to the id
    def get_url_to_id
      get_attr_to_id("url")
    end

    # Extract an alias parameter from the URL and check whether we have
    # such a repository already.
    # @param [String] url a repository with an alias parameter (actually optional)
    # @param [Hash{String => Fixnum}] alias_to_id a premade mapping, @see get_alias_to_id
    # @return the repository id or -1
    def SourceByAliasOrUrl(url, alias_to_id, url_to_id)
      alias_to_id = deep_copy(alias_to_id)
      url_to_id = deep_copy(url_to_id)
      # parse the URL
      parsed_url = URL.Parse(url)
      Builtins.y2milestone("parsed: %1", parsed_url)
      # (reassemble and warn if it differs)
      reassembled = URL.Build(parsed_url)
      Builtins.y2warning("reassembled differs: %1", reassembled) if url != reassembled
      # get the alias
      q_map = ParseUrlQuery(Ops.get_string(parsed_url, "query", ""))
      Builtins.y2milestone("query: %1", q_map)
      alias_name = Ops.get(q_map, "alias", "")

      # (empty: box safeguard)
      if alias_name != "" && Builtins.haskey(alias_to_id, alias_name)
        return Ops.get(alias_to_id, alias_name, -1)
      end

      # #188572: if no match by alias, try url
      Ops.get(url_to_id, url, -1)
    end

    # Used by registration. ZMD sync has been disabled - ZLM7.3 on sle11 supports
    # only HTTP and FTP repositories, sync would fail for other types.
    # See bnc#480845 for more details.
    #
    # @param [Array<String>] urls URLs to add
    # @return a list of added URLs
    def AddUpdateSources(urls)
      urls = deep_copy(urls)
      ret = []

      # prepare for lookup of known aliases
      aliases = get_alias_to_id
      Builtins.y2milestone("alias mapping: %1", aliases)
      by_url = get_url_to_id
      Builtins.y2milestone("url mapping: %1", by_url)

      # add the repositories
      # but do not make duplicates (#168740)
      # we detect them based on alias that suse_register gives us (#158850#c17)
      # / (but only for SLE... :-/ )
      # / Need to test what happens when we get two different update
      # / servers for SL
      # / Anyway that means only that #168740 remains unfixed for SL
      Builtins.foreach(urls) do |url|
        Builtins.y2milestone("Should add an update repository: %1", url)
        # inst_addon_update_sources also calls Pkg::SourceCreate
        # but it already skips duplicates

        # check if alias already there
        # if yes, delete the old one
        todel = SourceByAliasOrUrl(url, aliases, by_url)
        if todel != -1
          Builtins.y2milestone("deleting the old copy, repository %1", todel)
          Pkg.SourceDelete(todel)
        end
        # then add the new one
        Builtins.y2milestone("Adding update repository...")
        toadd = Pkg.SourceCreate(url, "/")
        # adding failed, try http fallback for ftp repo (#227059)
        if toadd.nil? || Ops.less_than(toadd, 0)
          parsed_url = URL.Parse(url)
          scheme = Ops.get_string(parsed_url, "scheme", "")

          if Builtins.tolower(scheme) == "ftp"
            Builtins.y2milestone(
              "Cannot add FTP update repository, trying HTTP..."
            )

            Ops.set(parsed_url, "scheme", "http")
            fallback_url = URL.Build(parsed_url)

            toadd = Pkg.SourceCreate(fallback_url, "/")
            url = fallback_url
          end
        end
        if toadd != -1 && !toadd.nil?
          ret = Builtins.add(ret, url) # #180820#c26

          # is there any patch available?
          patches = Y2Packager::Resolvable.find(kind: :patch)

          if Ops.greater_than(Builtins.size(patches), 0)
            # loaded target is required to get list of applicable patches (#270919)
            Builtins.y2milestone(
              "Repository %1 provides %2 patches, loading target...",
              url,
              Builtins.size(patches)
            )
            # suppose that we are running in an installed system and use "/" directory
            Pkg.TargetInitialize("/")
            Pkg.TargetLoad
          end
        end
      end

      deep_copy(ret)
    end

    def AskForCD(message)
      cdroms = SCR.Read(path(".probe.cdrom"))
      multiple_drives = (cdroms.size > 1)
      drives_sel = Empty()
      if multiple_drives
        devices = cdroms.map do |d|
          Item(Id(d["dev_name"] || ""), "#{d["model"]} (#{d["dev_name"]})")
        end
        # To adjust the width of the dialog, look for the more lengthy device label
        # (and add some extra space for the frame)
        min_width = devices.map { |d| d[1].to_s.size }.max + 4
        drives_sel = MinSize(min_width, 5, SelectionBox(Id(:drives), _("&Drive to eject"), devices))
      end
      contents = HBox(
        HSpacing(1),
        VBox(
          VSpacing(0.5),
          Label(message),
          VSpacing(0.5),
          drives_sel,
          VSpacing(0.5),
          HBox(
            HStretch(),
            HWeight(1, PushButton(Id(:cont), Label.ContinueButton)),
            HWeight(1, PushButton(Id(:cancel), Label.CancelButton)),
            HWeight(1, PushButton(Id(:eject), _("&Eject"))),
            HStretch()
          ),
          VSpacing(0.5)
        ),
        HSpacing(1)
      )
      UI.OpenDialog(contents)
      if multiple_drives
        UI.ChangeWidget(
          Id(:drives),
          :CurrentItem,
          Ops.get_string(cdroms, [0, "dev_name"], "")
        )
      end
      UI.SetFocus(Id(:cont))
      ret = nil
      loop do
        ret = Convert.to_symbol(UI.UserInput)
        break if [:cont, :cancel].include?(ret)

        if ret == :eject
          if multiple_drives
            device = Convert.to_string(UI.QueryWidget(Id(:drives), :Value))
            SCR.Execute(
              path(".target.bash"),
              "/usr/bin/eject #{device.shellescape}"
            )
          else
            SCR.Execute(
              path(".target.bash"),
              Builtins.sformat(
                "/usr/bin/eject %1",
                Ops.get_string(cdroms, [0, "dev_name"], "").shellescape
              )
            )
          end
        end
        ret = nil
      end

      result = { "continue" => ret == :cont }

      if multiple_drives
        result = Builtins.add(
          result,
          "device",
          Convert.to_string(UI.QueryWidget(Id(:drives), :Value))
        )
      end

      UI.CloseDialog

      deep_copy(result)
    end

    # Function returns the partiton name which is used as a repository for the installation
    # (IF any partition is used as a repository for installation, of course).
    # Otherwise it returns an empty string "". See bugzilla #208222 for more information.
    #
    # @return [String] partition name
    def InstallationSourceOnPartition
      install_mode = Linuxrc.InstallInf("InstMode")

      # Hard Disk is used for the installation
      if install_mode == "hd"
        install_partition = Linuxrc.InstallInf("Partition")

        # No partiton is defined - error
        if install_partition == "" || install_partition.nil?
          Builtins.y2error(
            "Despite the fact that the install-mode is '%1', install-partition is '%2'",
            install_mode,
            install_partition
          )
          ""
        else
          install_partition
        end
      else
        ""
      end
    end

    # Finds the biggest temporary directory and uses it as
    # packager download area.
    def InstInitSourceMoveDownloadArea
      spaces = Pkg.TargetGetDU
      root_info = Ops.get_list(
        spaces,
        "/tmp",
        Ops.get_list(spaces, "/tmp/", Ops.get_list(spaces, "/", []))
      )
      total = Ops.get_integer(root_info, 0, 0)
      current = Ops.get_integer(root_info, 1, 0)
      future = Ops.get_integer(root_info, 2, 0)
      future = current if Ops.less_than(future, current)
      tmp_space = Ops.subtract(total, future)
      # no temp space left or read-only
      tmp_space = 0 if Ops.less_than(tmp_space, 0) || Ops.get_integer(root_info, 3, 1) == 1

      var_info = Ops.get_list(
        spaces,
        "/var/tmp",
        Ops.get_list(
          spaces,
          "/var/tmp/",
          Ops.get_list(
            spaces,
            "/var",
            Ops.get_list(spaces, "/var/", Ops.get_list(spaces, "/", []))
          )
        )
      )
      total = Ops.get_integer(var_info, 0, 0)
      current = Ops.get_integer(var_info, 1, 0)
      future = Ops.get_integer(var_info, 2, 0)
      future = current if Ops.less_than(future, current)
      var_tmp_space = Ops.subtract(total, future)
      # no temp space left or read-only
      var_tmp_space = 0 if Ops.less_than(var_tmp_space, 0) || Ops.get_integer(var_info, 3, 1) == 1

      #-------
      # /tmp or /var/tmp ?

      download_dir = Ops.greater_than(tmp_space, var_tmp_space) ? "/tmp" : "/var/tmp"
      download_dir = Ops.add(Installation.destdir, download_dir)
      # TODO: check the size of the largest package on CD1
      successful = SCR.Execute(
        path(".target.bash"),
        "/usr/bin/mkdir -p #{download_dir.shellescape}"
      )
      if successful.zero?
        Pkg.SourceMoveDownloadArea(download_dir)
      else
        Builtins.y2error("Unable to create %1 directory", download_dir)
      end

      nil
    end

    publish variable: :newSources, type: "list <integer>"
    publish variable: :numSources, type: "integer"
    publish variable: :sourceStates, type: "list <integer>"
    publish variable: :sourceStatesIn, type: "list <map <string, any>>"
    publish variable: :sourceStatesOut, type: "list <map <string, any>>"
    publish variable: :url_tokens, type: "map"
    publish variable: :currentUrl, type: "string"
    publish variable: :just_removed_sources, type: "list <integer>"
    publish function: :Modified, type: "boolean ()"
    publish function: :createSource, type: "symbol (string)"
    publish variable: :modified, type: "boolean"
    publish variable: :proposal_valid, type: "boolean"
    publish function: :AbortFunction, type: "boolean ()"
    publish function: :Abort, type: "boolean ()"
    publish function: :ReadSources, type: "boolean ()"
    publish function: :Read, type: "boolean ()"
    publish function: :CommitSources, type: "boolean ()"
    publish function: :Write, type: "boolean ()"
    publish function: :Import, type: "boolean (map)"
    publish function: :Export, type: "map ()"
    publish function: :GetSrcIdByIndex, type: "integer (integer)"
    publish function: :SetUrlByIndex, type: "void (integer)"
    publish function: :getSourceId, type: "integer (string)"
    publish function: :SourceData, type: "map (integer)"
    publish function: :deleteSourceBySrcId, type: "void (integer)"
    publish function: :deleteSourceByIndex, type: "void (integer)"
    publish function: :deleteSourceByUrl, type: "void (string)"
    publish function: :Summary, type: "list ()"
    publish function: :Overview, type: "list ()"
    publish function: :AddUpdateSources, type: "list <string> (list <string>)"
    publish function: :AskForCD, type: "map <string, any> (string)"
    publish function: :InstallationSourceOnPartition, type: "string ()"
    publish function: :InstInitSourceMoveDownloadArea, type: "void ()"
  end

  SourceManager = SourceManagerClass.new
  SourceManager.main
end
