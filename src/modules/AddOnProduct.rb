# encoding: utf-8
require "yast"

require "shellwords"

require "packager/product_patterns"

# Yast namespace
module Yast
  # This module provides integration of the add-on products
  class AddOnProductClass < Module
    include Yast::Logger

    # @return [Hash] Product renames default map. Used when information is not
    #                found elsewhere.
    DEFAULT_PRODUCT_RENAMES = {
      "SUSE_SLES"                         => ["SLES"],
      # SLED or Workstation extension
      "SUSE_SLED"                         => ["SLED", "sle-we"],
      # SLE11 HA has been renamed since SLE12
      "sle-hae"                           => ["sle-ha"],
      # SLE11 HA GEO is now included in SLE15 HA
      "sle-haegeo"                        => ["sle-ha"],
      # SLE12 HA GEO is now included in SLE15 HA
      "sle-ha-geo"                        => ["sle-ha"],
      "SUSE_SLES_SAP"                     => ["SLES_SAP"],
      # SLES-12 with HPC module can be replaced by SLE_HPC-15
      "SLES"                              => ["SLE_HPC"],
      # this is an internal product so far...
      "SLE-HPC"                           => ["SLE_HPC"],
      # SMT is now integrated into the base SLES
      "sle-smt"                           => ["SLES"],
      # Live patching is a module now (bsc#1074154)
      "sle-live-patching"                 => ["sle-module-live-patching"],
      # The Advanced Systems Management Module has been moved to the Basesystem module
      "sle-module-adv-systems-management" => ["sle-module-basesystem"],
      # Toolchain and SDK are now included in the Development Tools SLE15 module
      "sle-module-toolchain"              => ["sle-module-development-tools"],
      "sle-sdk"                           => ["sle-module-development-tools"],
      # openSUSE => SLES migration
      "openSUSE"                          => ["SLES"]
    }.freeze

    # @return [Hash] Product renames added externally through the #add_rename method
    attr_accessor :external_product_renames
    private :external_product_renames, :external_product_renames=

    # Products which are selected for installation in libzypp.
    attr_reader :selected_installation_products

    def main
      Yast.import "UI"
      Yast.import "Pkg"

      # IMPORTANT: maintainer of yast2-add-on is responsible for this module

      textdomain "packager"

      Yast.import "Label"
      Yast.import "Mode"
      Yast.import "ProductControl"
      Yast.import "ProductFeatures"
      Yast.import "Report"
      Yast.import "XML"
      Yast.import "Wizard"
      Yast.import "FileUtils"
      Yast.import "Popup"
      Yast.import "InstShowInfo"
      Yast.import "ProductLicense"
      Yast.import "Directory"
      Yast.import "String"
      Yast.import "WorkflowManager"
      Yast.import "URL"
      Yast.import "Stage"
      Yast.import "Icon"
      Yast.import "Package"
      Yast.import "PackageCallbacks"
      Yast.import "PackagesProposal"
      Yast.import "SourceManager"

      Yast.include self, "packager/load_release_notes.rb"

      # variables for installation with product
      # ID for cache in the inst-sys
      @src_cache_id = -1

      # System proposals have already been prepared for merging?
      @system_proposals_prepared = false

      # System workflows have already been prepared for merging?
      @system_workflows_prepared = false

      # List of all selected repositories
      #
      #
      # **Structure:**
      #
      #     add_on_products = [
      #        $[
      #          "media" : 4, // ID of the source
      #          "product_dir" : "/",
      #          "product" : "openSUSE version XX.Y",
      #          "autoyast_product" : "'PRODUCT' tag for AutoYaST Export",
      #        ],
      #        ...
      #      ]
      @add_on_products = []

      # ID of currently added repository for the add-on product
      @src_id = nil

      # for the add-on product workflow - needed for dialog skipping
      # return value of last step in the product adding workflow
      @last_ret = nil

      @modified = false

      @mode_config_sources = []

      @current_addon = {}

      # Bugzilla #239630
      # In installation: check for low-memory machines
      @low_memory_already_reported = false

      # Bugzilla #305554
      # Both online-repositories and add-ons use the same function and variable
      # if true, both are skipped at once without asking
      @skip_add_ons = false

      #
      # **Structure:**
      #
      #     $["src_id|media|filename" : "/path/to/the/file"]
      @source_file_cache = {}

      @filecachedir = Builtins.sformat("%1/AddOns_CacheDir/", Directory.tmpdir)

      @filecachecounter = -1

      # Which part installation.xml will be used
      @_inst_mode = "installation"

      # --> FATE #302123: Allow relative paths in "add_on_products" file
      @base_product_url = nil

      # Contains list of repository IDs that request registration
      @addons_requesting_registration = []

      # Every Add-On can preselect some patterns.
      # Only patterns that are not selected/installed yet will be used.
      #
      #
      # **Structure:**
      #
      #     $[
      #        src_id : [
      #          "pattern_1", "pattern_2", "pattern_6"
      #        ]
      #      ]
      @patterns_preselected_by_addon = {}

      # additional product renames needed for detecting the product update
      # @see #add_rename
      @external_product_renames = {}

      # Products which are selected for installation in libzypp.
      # Due the "buddy" libzypp functionality also the release packages will
      # be regarded.
      # E.g.: product:sle-module-basesystem-15-0.x86_64 has buddy
      # sle-module-basesystem-release-15-91.2.x86_64
      @selected_installation_products = [] # e.g.:  ["sle-module-basesystem"]
    end

    # Downloads a requested file, caches it and returns path to that cached file.
    # If a file is alerady cached, just returns the path to a cached file.
    # Parameter 'sod' defines whether a file is 'signed' (file + file.asc) or 'digested'
    # (file digest mentioned in signed content file).
    #
    # @param [Fixnum] src_id
    # @param [Fixnum] media
    # @param [String] filename
    # @param [String] sod ("signed" or "digested")
    # @param [Boolean] optional (false if mandatory)
    # @return [String] path to a cached file
    #
    # @example
    #   // content file is usually signed with content.asc
    #   AddOnProduct::GetCachedFileFromSource (8, 1, "/content", "signed", false);
    #   // the other files are usually digested in content file
    #   AddOnProduct::GetCachedFileFromSource (8, 1, "/images/images.xml", "digested", true);
    def GetCachedFileFromSource(src_id, media, filename, sod, optional)
      # BNC #486785: Jukebox when using more physical media-based Add-Ons at once
      file_ID = Builtins.sformat("%1|%2|%3", src_id, media, filename)

      provided_file = Ops.get(@source_file_cache, file_ID, "")

      if !provided_file.nil? && provided_file != ""
        # Checking whether the cached file exists
        if FileUtils.Exists(provided_file)
          Builtins.y2milestone(
            "File %1 found in cache: %2",
            file_ID,
            provided_file
          )

          return provided_file
        else
          Builtins.y2warning("Cached file %1 not accessible!", provided_file)
          @source_file_cache = Builtins.remove(@source_file_cache, file_ID)
        end
      end

      optional = true if optional.nil?

      if sod == "signed"
        provided_file = Pkg.SourceProvideSignedFile(
          src_id,
          media,
          filename,
          optional
        )
      elsif sod == "digested"
        provided_file = Pkg.SourceProvideDigestedFile(
          src_id,
          media,
          filename,
          optional
        )
      else
        Builtins.y2error(
          "Unknown SoD: %1. It can be only 'signed' or 'digested'",
          sod
        )
        provided_file = nil
      end

      # A file has been found, caching...
      if !provided_file.nil?
        @filecachecounter = Ops.add(@filecachecounter, 1)

        # Where the file is finally cached
        cached_file = Builtins.sformat("%1%2", @filecachedir, @filecachecounter)

        cmd = "/usr/bin/mkdir -p #{@filecachedir.shellescape}; " \
          "/usr/bin/cp #{provided_file.shellescape} #{cached_file.shellescape}"
        cmd_run = Convert.to_map(SCR.Execute(path(".target.bash_output"), cmd))

        # Unable to cache a file, the original file will be returned
        if Ops.get_integer(cmd_run, "exit", -1).nonzero?
          Builtins.y2warning("Error caching file: %1: %2", cmd, cmd_run)
        else
          Builtins.y2milestone("File %1 cached as %2", file_ID, cached_file)
          # Writes entry into cache database
          Ops.set(@source_file_cache, file_ID, cached_file)
          # Path to a cached file will be returned
          provided_file = cached_file
        end
      end

      provided_file
    end

    # Returns the current add-on installation mode.
    #
    # @return [String] current mode
    # @see #SetMode()
    def GetMode
      @_inst_mode
    end

    # Sets internal add-on installation mode to either "installation" or "update".
    # Mode is used later when deciding which part of the installation.xml to use.
    #
    # @param [String] new_mode ("installation" or "update")
    # @see #GetMode();
    def SetMode(new_mode)
      if new_mode.nil? ||
          !Builtins.contains(["installation", "update"], new_mode)
        Builtins.y2error("Wrong Add-On mode: %1", new_mode)
      end

      @_inst_mode = new_mode

      nil
    end

    # Returns whether add-on product got as parameter (source id)
    # replaces some already installed add-on or whether it is a new
    # installation. Repositories and target have to be initialized.
    #
    # @param [Fixnum] source_id source ID
    def AddOnMode(source_id)
      all_products = Pkg.ResolvableProperties("", :product, "")

      check_add_on = {}

      # Search for an add-on using source ID
      Builtins.foreach(all_products) do |one_product|
        if Ops.get_integer(one_product, "source", -1) == source_id
          check_add_on = deep_copy(one_product)
          raise Break
        end
      end

      ret = "installation"

      supported_statuses = [:installed, :selected]
      already_found = false

      # Found the
      if check_add_on != {} && Builtins.haskey(check_add_on, "replaces")
        product_replaces = Ops.get_list(check_add_on, "replaces", [])

        # Run through through all products that the add-on can replace
        Builtins.foreach(product_replaces) do |one_replaces|
          raise Break if already_found
          # Run through all installed (or selected) products
          Builtins.foreach(all_products) do |one_product|
            # checking the status
            if !Builtins.contains(
              supported_statuses,
              Ops.get_symbol(one_product, "status", :unknown)
            )
              next
            end
            # ignore itself
            next if Ops.get_integer(one_product, "source", -42) == source_id
            # check name to replace
            if Ops.get_string(one_product, "name", "-A-") !=
                Ops.get_string(one_replaces, "name", "-B-")
              next
            end
            # check version to replace
            if Ops.get_string(one_product, "version", "-A-") !=
                Ops.get_string(one_replaces, "version", "-B-")
              next
            end
            # check version to replace
            if Ops.get_string(one_product, "arch", "-A-") !=
                Ops.get_string(one_replaces, "arch", "-B-")
              next
            end
            Builtins.y2milestone(
              "Found product matching update criteria: %1 -> %2",
              one_product,
              check_add_on
            )
            ret = "update"
            already_found = true
            raise Break
          end
        end
      end

      ret
    end

    def SetBaseProductURL(url)
      Builtins.y2warning("Empty base url") if url == "" || url.nil?

      @base_product_url = url
      Builtins.y2milestone(
        "New base URL: %1",
        URL.HidePassword(@base_product_url)
      )

      nil
    end

    def GetBaseProductURL
      @base_product_url
    end

    # Returns an absolute URL from base + relative url.
    # Relative URL needs to start with 'reulrl://' othewise
    # it is not considered being relative and it's returned
    # as it is (just the relative_url parameter).
    #
    # @param [String] base_url
    # @param [String] url URL relative to the base
    #
    # @example
    #   AddOnProduct::GetAbsoluteURL (
    #     "http://www.example.org/some%20dir/another%20dir",
    #     "relurl://../AnotherProduct/"
    #   ) -> "http://www.example.org/some%20dir/AnotherProduct/"
    #   AddOnProduct::GetAbsoluteURL (
    #     "username:password@ftp://www.example.org/dir/",
    #     "relurl://./Product_CD1/"
    #   ) -> "username:password@ftp://www.example.org/dir/Product_CD1/"
    def GetAbsoluteURL(base_url, url)
      if !Builtins.regexpmatch(url, "^relurl://")
        Builtins.y2debug("Not a relative URL: %1", URL.HidePassword(url))
        return url
      end

      if base_url.nil? || base_url == ""
        Builtins.y2error("No base_url defined")
        return url
      end

      # bugzilla #306670
      base_params_pos = Builtins.search(base_url, "?")
      base_params = ""

      if !base_params_pos.nil? && Ops.greater_or_equal(base_params_pos, 0)
        base_params = Builtins.substring(base_url, Ops.add(base_params_pos, 1))
        base_url = Builtins.substring(base_url, 0, base_params_pos)
      end

      added_params_pos = Builtins.search(url, "?")
      added_params = ""

      if !added_params_pos.nil? && Ops.greater_or_equal(added_params_pos, 0)
        added_params = Builtins.substring(url, Ops.add(added_params_pos, 1))
        url = Builtins.substring(url, 0, added_params_pos)
      end

      base_url = Ops.add(base_url, "/") if !Builtins.regexpmatch(base_url, "/$")

      Builtins.y2milestone(
        "Merging '%1' (params '%2') to '%3' (params '%4')",
        url,
        added_params,
        base_url,
        base_params
      )
      url = Builtins.regexpsub(url, "^relurl://(.*)$", "\\1")

      url = Builtins.sformat("%1%2", base_url, url)

      # merge /something/../
      max_count = 100

      while Ops.greater_than(max_count, 0) &&
          Builtins.regexpmatch(url, "(.*/)[^/]+/+\\.\\./")
        max_count = Ops.subtract(max_count, 1)
        str_offset_l = Builtins.regexppos(url, "/\\.\\./")
        str_offset = Ops.get(str_offset_l, 0)

        next unless !str_offset.nil? && Ops.greater_than(str_offset, 0)
        stringfirst = Builtins.substring(url, 0, str_offset)
        stringsecond = Builtins.substring(url, str_offset)

        Builtins.y2debug(
          "Pos: %1 First: >%2< Second: >%3<",
          str_offset,
          stringfirst,
          stringsecond
        )

        stringfirst = Builtins.regexpsub(stringfirst, "^(.*/)[^/]+/*$", "\\1")
        stringsecond = Builtins.regexpsub(
          stringsecond,
          "^/\\.\\./(.*)$",
          "\\1"
        )

        url = Ops.add(stringfirst, stringsecond)
      end

      # remove /./
      max_count = 100

      while Ops.greater_than(max_count, 0) && Builtins.regexpmatch(url, "/\\./")
        max_count = Ops.subtract(max_count, 1)
        url = Builtins.regexpsub(url, "^(.*)/\\./(.*)", "\\1/\\2")
      end

      base_params_map = URL.MakeMapFromParams(base_params)
      added_params_map = URL.MakeMapFromParams(added_params)
      final_params_map = Convert.convert(
        Builtins.union(base_params_map, added_params_map),
        from: "map",
        to:   "map <string, string>"
      )

      if Ops.greater_than(Builtins.size(final_params_map), 0)
        Builtins.y2milestone(
          "%1 merge %2 -> %3",
          base_params_map,
          added_params_map,
          final_params_map
        )

        url = Ops.add(
          Ops.add(url, "?"),
          URL.MakeParamsFromMap(final_params_map)
        )
      end

      Builtins.y2milestone("Final URL: '%1'", URL.HidePassword(url))
      url
    end
    # <--

    # Adapts the inst-sys from the tarball
    # @param [String] filename string the filename with the tarball to use to the update
    # @return [Boolean] true on success
    def UpdateInstSys(filename)
      @src_cache_id = Ops.add(@src_cache_id, 1)
      tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      tmpdir = Builtins.sformat("%1/%2", tmpdir, @src_cache_id)
      out = SCR.Execute(
        path(".target.bash_output"),
        Builtins.sformat(
          "\n" \
            "/usr/bin/mkdir %1;\n" \
            "cd %1;\n" \
            "/bin/tar -xvf %2;\n" \
            "/sbin/adddir %1 /;\n",
          tmpdir.shellescape,
          filename.shellescape
        )
      )
      if Ops.get_integer(out, "exit", 0).nonzero?
        Builtins.y2error("Including installation image failed: %1", out)
        return false
      end
      Builtins.y2milestone("Including installation image succeeded")
      true
    end

    # New add-on product might add also new agents.
    # Functions Rereads all available agents.
    #
    # @see bugzilla #239055, #245508
    def RereadAllSCRAgents
      Builtins.y2milestone("Registering new agents...")
      ret = SCR.RegisterNewAgents

      if ret
        Builtins.y2milestone("Successful")
      else
        Builtins.y2error("Error occured during registering new agents!")
        Report.Error(
          _("An error occurred while preparing the installation system.")
        )
      end

      nil
    end

    # Remove the /y2update directory from the system
    def CleanY2Update
      SCR.Execute(path(".target.bash"), "/bin/rm -rf /y2update")

      nil
    end

    # Show beta file in a pop-up message if such file exists.
    # Show license if such exists and return whether users accepts it.
    # Returns 'nil' when did not succed.
    #
    # @return [Boolean] whether the license has been accepted
    def AcceptedLicenseAndInfoFile(src_id)
      ret = ProductLicense.AskAddOnLicenseAgreement(src_id)
      return nil if ret.nil?

      if ret == :abort || ret == :back
        Builtins.y2milestone("License confirmation failed")
        return false
      end

      true
    end

    def AnyPatternInRepo
      patterns = Pkg.ResolvableProperties("", :pattern, "")

      Builtins.y2milestone(
        "Total number of patterns: %1",
        Builtins.size(patterns)
      )

      patterns = Builtins.filter(patterns) do |pat|
        Ops.get(pat, "source") == @src_id
      end

      Builtins.y2milestone("Found %1 add-on patterns", Builtins.size(patterns))
      Builtins.y2debug("Found add-on patterns: %1", patterns)

      Ops.greater_than(Builtins.size(patterns), 0)
    end

    def DoInstall_NoControlFile
      Builtins.y2milestone(
        "File /installation.xml not found, running sw_single for this repository"
      )

      # display pattern the dialog when there is a pattern provided by the addon
      # otherwise use the summary mode
      mode = AnyPatternInRepo() ? :patternSelector : :summaryMode
      # enable repository management if not in installation mode
      enable_repo_management = Mode.normal

      args = { "dialog_type" => mode, "repo_mgmt" => enable_repo_management }
      Builtins.y2milestone("Arguments for sw_single: %1", args)

      ret = WFM.CallFunction("sw_single", [args])
      Builtins.y2milestone("sw_single returned: %1", ret)

      return :abort if ret == :abort || ret == :cancel || ret == :close

      :register
    end

    def IntegrateY2Update(src_id)
      # this works only with the SUSE tags repositories
      binaries = GetCachedFileFromSource(
        src_id, # optional
        1,
        "/y2update.tgz",
        "digested",
        true
      )

      # try the package containing the installer update, works with all repositories,
      # including RPM-MD
      binaries ||= y2update_path(src_id)

      # File /y2update.tgz exists
      if !binaries.nil?
        # Try to extract files from the archive
        out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat(
              "\n" \
                "/usr/bin/test -d /y2update && /usr/bin/rm -rf /y2update;\n" \
                "/bin/mkdir -p /y2update/all;\n" \
                "cd /y2update/all;\n" \
                "/bin/tar -xvf %1;\n" \
                "cd /y2update;\n" \
                "/usr/bin/ln -s all/usr/share/YaST2/* .;\n" \
                "/usr/bin/ln -s all/usr/lib/YaST2/* .;\n",
              binaries.shellescape
            )
          )
        )

        # Failed
        if Ops.get_integer(out, "exit", 0).nonzero?
          # error report
          Report.Error(
            _("An error occurred while preparing the installation system.")
          )
          CleanY2Update()
          return false
        else
          # bugzilla #239055
          RereadAllSCRAgents()
        end
      else
        Builtins.y2milestone("File /y2update.tgz not provided")
      end

      true
    end

    def DoInstall_WithControlFile(control)
      Builtins.y2milestone(
        "File /installation.xml was found, running own workflow..."
      )
      # copy the control file to local filesystem - in case of media release
      tmp = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      tmp = Ops.add(tmp, "/installation.xml")
      SCR.Execute(
        path(".target.bash"),
        "/usr/bin/cp #{control.shellescape} #{tmp.shellescape}"
      )
      control = tmp

      return nil if !IntegrateY2Update(@src_id)

      # set control file
      ProductControl.custom_control_file = control
      if !ProductControl.Init
        # error report
        Report.Error(
          Builtins.sformat(_("Control file %1 not found on media."), control)
        )
        CleanY2Update()
        return nil
      end

      current_stage = "normal"
      current_mode = "installation"

      # Special add-on mode (GetMode()) returns the same
      # add-on can be either installed (first time) or updated by another add-on
      ProductControl.SetAdditionalWorkflowParams(
        "add_on_mode" => AddOnMode(@src_id)
      )

      steps = ProductControl.getModules(current_stage, current_mode, :enabled)
      if steps.nil? || Ops.less_than(Builtins.size(steps), 1)
        Builtins.y2warning(
          "Add-On product workflow for stage: %1, mode: %2 not defined",
          current_stage,
          current_mode
        )
        ProductControl.ResetAdditionalWorkflowParams
        return nil
      end

      # start workflow
      Wizard.OpenNextBackStepsDialog
      # dialog caption
      Wizard.SetContents(_("Initializing..."), Empty(), "", false, false)

      stage_mode = [{ "stage" => current_stage, "mode" => current_mode }]
      Builtins.y2milestone("Using Add-On control file parts: %1", stage_mode)
      ProductControl.AddWizardSteps(stage_mode)

      old_mode = nil
      # Running system, not installation, not update
      if Stage.normal && Mode.normal
        old_mode = Mode.mode
        Mode.SetMode(current_mode)
      end

      # Run the workflow
      ret = ProductControl.Run

      Mode.SetMode(old_mode) if !old_mode.nil?

      UI.CloseDialog
      CleanY2Update()

      ProductControl.ResetAdditionalWorkflowParams

      ret
    end

    def ClearRegistrationRequest(src_id)
      Builtins.y2milestone(
        "Clearing registration flag for repository ID %1",
        src_id
      )
      if !src_id.nil?
        @addons_requesting_registration = Builtins.filter(
          @addons_requesting_registration
        ) { |one_source| one_source != src_id }
      end

      nil
    end

    # Returns whether registration is requested by at least one of
    # used Add-On products.
    #
    # @return [Boolean] if requested
    def ProcessRegistration
      force_registration = false

      # checking add-on products one by one
      Builtins.foreach(@add_on_products) do |prod|
        srcid = Ops.get_integer(prod, "media")
        if !srcid.nil? &&
            Builtins.contains(@addons_requesting_registration, srcid)
          force_registration = true
          raise Break
        end
      end

      Builtins.y2milestone("Requesting registration: %1", force_registration)
      force_registration
    end

    # Add-On product might have been added into products requesting
    # registration. This pruduct has been removed (during configuring
    # list of add-on products).
    def RemoveRegistrationFlag(src_id)
      # filtering out src_id
      @addons_requesting_registration = Builtins.filter(
        @addons_requesting_registration
      ) { |one_id| one_id != src_id }

      # removing cached file
      tmpdir = Ops.add(
        Convert.to_string(SCR.Read(path(".target.tmpdir"))),
        "/add-on-content-files/"
      )
      cachedfile = Builtins.sformat("%1content-%2", tmpdir, src_id)
      if FileUtils.Exists(cachedfile)
        Builtins.y2milestone("Removing cached file %1", cachedfile)
        SCR.Execute(path(".target.remove"), cachedfile)
      end

      nil
    end

    # Checks whether the addon at src_id need registration
    # If it has, product is added into list of products that need registration.
    #
    # @param [Fixnum] src_id source id
    def PrepareForRegistration(src_id)
      control_file = WorkflowManager.GetCachedWorkflowFilename(:addon, src_id, "")

      return unless WorkflowManager.IncorporateControlFileOptions(control_file)
      # FATE #305578: Add-On Product Requiring Registration
      return unless WorkflowManager.WorkflowRequiresRegistration(src_id)

      log.info "REGISTERPRODUCT (require_registration) defined in control file"
      @addons_requesting_registration << deep_copy(src_id)
    end

    # Calls registration client if needed.
    #
    # @param [Fixnum] src_id source id
    def RegisterAddOnProduct(src_id)
      # FATE #305578: Add-On Product Requiring Registration
      if WorkflowManager.WorkflowRequiresRegistration(src_id) ||
          Builtins.contains(@addons_requesting_registration, src_id)
        Builtins.y2milestone("Repository ID %1 requests registration", src_id)

        if !WFM.ClientExists("inst_scc")
          package_installed = Package.Install("yast2-registration")

          if !package_installed
            Report.Error(_("Package '%s' is not installed.\n" \
              "The add-on product cannot be registered.") % "yast2-registration")
            return nil
          end
        end

        # pass the addon so it could be registered
        WFM.CallFunction("inst_scc", ["register_media_addon", src_id])
      else
        Builtins.y2milestone(
          "Repository ID %1 doesn't need registration",
          src_id
        )
      end

      nil
    end

    # Do installation of the add-on product within an installed system
    # srcid is got via AddOnProduct::src_id
    #
    # @param install_packages [Boolean] install the selected packages if no
    #   installation.xml is found on the addon, can be optionally disabled
    # @return [Symbol] the result symbol from wizard sequencer
    def DoInstall(install_packages: true)
      # Display beta file if such file exists
      # Display license and wait for agreement
      # Not needed here, license already shown in the workflow
      # boolean license_ret = AcceptedLicenseAndInfoFile(src_id);
      # if (license_ret != true) {
      # 	y2milestone("Removing the current source ID %1", src_id);
      # 	Pkg::SourceDelete(src_id);
      # 	return nil;
      # }

      # FATE #301312
      PrepareForRegistration(@src_id)

      # FATE #301997: Support update of add-on products properly
      add_on_mode = AddOnMode(@src_id)
      SetMode(add_on_mode)

      # BNC #468449
      # Always store the current set of repositories as they might get
      # changed by registration or the called add-on workflow
      Pkg.SourceSaveAll

      ret = nil

      control = WorkflowManager.GetCachedWorkflowFilename(:addon, @src_id, "")
      if !control.nil?
        # FATE #305578: Add-On Product Requiring Registration
        WorkflowManager.AddWorkflow(:addon, @src_id, "")

        Builtins.y2milestone("Add-On has own control file")
        ret = DoInstall_WithControlFile(control)
      end
      # Fallback -- Repository didn't provide needed control file
      # or control file doesn't contain needed stage/mode
      # Handling as it was a repository
      ret = DoInstall_NoControlFile() if install_packages && (control.nil? || ret.nil?)

      Builtins.y2milestone("Result of the add-on installation: %1", ret)

      if !ret.nil? && ret != :abort
        # registers Add-On product if requested
        RegisterAddOnProduct(@src_id)
      end

      if ret == :abort
        # cleanup after abort
        Builtins.y2milestone(
          "Add-on installation aborted, removing installation source %1: %2",
          @src_id,
          Pkg.SourceGeneralData(@src_id)
        )
        Pkg.SourceDelete(@src_id)
        Pkg.SourceSaveAll

        # remove from the internal list
        @add_on_products = Builtins.filter(@add_on_products) do |add_on_product|
          Ops.get_integer(add_on_product, "media", -1) != @src_id
        end

        # reset the src id, it's not valid
        @src_id = nil
      end

      Builtins.y2milestone("Returning: %1", ret)
      ret
    end

    def PackagesProposalAddonID(src_id)
      "Add-On-Product-ID:#{src_id}"
    end

    # Integrate the add-on product to the installation workflow, including
    # preparations for 2nd stage and inst-sys update
    # @param [Fixnum] srcid integer the ID of the repository
    # @return [Boolean] true on success
    def Integrate(srcid)
      Builtins.y2milestone("Integrating repository %1", srcid)

      # Updating inst-sys, this works only with the SUSE tags repositories
      y2update = GetCachedFileFromSource(
        srcid, # optional
        1,
        "/y2update.tgz",
        "digested",
        true
      )

      # try the package containing the installer update, works with all repositories,
      # including RPM-MD
      y2update ||= y2update_path(srcid)

      if y2update.nil?
        Builtins.y2milestone("No YaST update found on the media")
      else
        UpdateInstSys(y2update)
      end

      # FATE #302398: PATTERNS keyword in content file
      # changed for software section in installation.xml
      # or 'defaultpattern()' product Provides (FATE#320199)

      # Adds workflow to the Workflow Store if any workflow exists
      WorkflowManager.AddWorkflow(:addon, srcid, "")

      true
    end

    # Opposite to Integrate()
    #
    # @param [Fixnum] srcid integer the ID of the repository
    def Disintegrate(srcid)
      WorkflowManager.RemoveWorkflow(:addon, srcid, "")

      nil
    end

    # Some product(s) were removed, reintegrating their control files from scratch.
    def ReIntegrateFromScratch
      Builtins.y2milestone("Reintegration workflows from scratch...")

      # bugzilla #239055
      RereadAllSCRAgents()

      # Should have been done before (by calling AddOnProduct::Integrate()
      #    foreach (map<string,any> prod, AddOnProduct::add_on_products, {
      #        integer srcid = (integer) prod["media"]:nil;
      #
      #        if (srcid == nil) {
      #            y2error ("Wrong definition of Add-on product: %1, cannot reintegrate", srcid);
      #            return;
      #        } else {
      #            y2milestone ("Reintegrating product %1", prod);
      #            Integrate (srcid);
      #        }
      #    });
      redraw = WorkflowManager.SomeWorkflowsWereChanged

      # New implementation: Control files are cached, just merging them into the Base Workflow
      WorkflowManager.MergeWorkflows

      # steps might have been changed, forcing redraw
      if redraw
        Builtins.y2milestone("Forcing RedrawWizardSteps()")
        WorkflowManager.RedrawWizardSteps
      end

      true
    end

    def CheckProductDependencies(_products)
      # TODO: check the dependencies of the product
      true
    end

    # Reads temporary add_on_products file, parses supported products,
    # merges base URL if products use relative URL and returns list of
    # maps defining additional products to add.
    #
    # @see FATE #303675
    # @param [String] parse_file
    # @param [String] base_url
    # @return [Array<Hash>] of products to add
    #
    #
    # **Structure:**
    #
    #
    #       [
    #         // product defined with URL and additional path (typically "/")
    #         $["url":(string) url, "path":(string) path]
    #         // additional list of products to install
    #         // media URL can contain several products at once
    #         $["url":(string) url, "path":(string) path, "install_products":(list <string>) pti]
    #       ]
    def ParsePlainAddOnProductsFile(parse_file, base_url)
      if !FileUtils.Exists(parse_file)
        Builtins.y2error("Cannot parse missing file: %1", parse_file)
        return []
      end

      products = Builtins.splitstring(
        Convert.to_string(SCR.Read(path(".target.string"), parse_file)),
        "\r\n"
      )

      if products.nil?
        # TRANSLATORS: error report
        Report.Error(_("Unable to use additional products."))
        Builtins.y2error("Erroneous file: %1", parse_file)
        return []
      end

      ret = []

      Builtins.foreach(products) do |p|
        next if p == ""
        elements = Builtins.splitstring(p, " \t")
        elements = Builtins.filter(elements) { |e| e != "" }
        url = Ops.get(elements, 0, "")
        pth = Ops.get(elements, 1, "/")
        elements = Builtins.remove(elements, 0) unless Ops.get(elements, 0).nil?
        elements = Builtins.remove(elements, 0) unless Ops.get(elements, 0).nil?
        # FATE #302123
        url = GetAbsoluteURL(base_url, url) if !base_url.nil? && base_url != ""
        ret = Builtins.add(
          ret,
          "url" => url, "path" => pth, "install_products" => elements
        )
      end

      deep_copy(ret)
    end

    def UserSelectsRequiredAddOns(products)
      products = deep_copy(products)
      return [] if products.nil? || products == []

      ask_user_products = []
      ask_user_products_map = {}

      # key in ask_user_products_map
      id_counter = -1
      visible_string = ""

      # filter those that are selected by default (without 'ask_user')
      selected_products = Builtins.filter(products) do |one_product|
        next true if Ops.get_boolean(one_product, "ask_user", false) == false
        # wrong definition, 'url' is mandatory
        if !Builtins.haskey(one_product, "url")
          Builtins.y2error("No 'url' defined: %1", one_product)
          next false
        end
        # user is asked for the rest
        id_counter = Ops.add(id_counter, 1)
        # fill up internal map (used later when item selected)
        Ops.set(ask_user_products_map, id_counter, one_product)
        if Builtins.haskey(one_product, "name")
          visible_string = Builtins.sformat(
            _("%1, URL: %2"),
            Ops.get_string(one_product, "name", ""),
            Ops.get_string(one_product, "url", "")
          )
        elsif Builtins.haskey(one_product, "install_products")
          visible_string = Builtins.sformat(
            _("%1, URL: %2"),
            Builtins.mergestring(
              Ops.get_list(one_product, "install_products", []),
              ", "
            ),
            Ops.get_string(one_product, "url", "")
          )
        elsif Builtins.haskey(one_product, "path") &&
            Ops.get_string(one_product, "path", "/") != "/"
          visible_string = Builtins.sformat(
            _("URL: %1, Path: %2"),
            Ops.get_string(one_product, "url", ""),
            Ops.get_string(one_product, "path", "")
          )
        else
          visible_string = Builtins.sformat(
            _("URL: %1"),
            Ops.get_string(one_product, "url", "")
          )
        end
        # create items
        ask_user_products = Builtins.add(
          ask_user_products,
          Item(
            Id(id_counter),
            visible_string,
            Ops.get_boolean(one_product, "selected", false)
          )
        )
        false
      end

      ask_user_products = Builtins.sort(ask_user_products) do |x, y|
        Ops.less_than(Ops.get_string(x, 1, ""), Ops.get_string(y, 1, ""))
      end

      UI.OpenDialog(
        VBox(
          # TRANSLATORS: popup heading
          Left(Heading(Id(:search_heading), _("Additional Products"))),
          VSpacing(0.5),
          # TRANSLATORS: additional dialog information
          Left(
            Label(
              _(
                "The installation repository also contains the listed additional repositories.\n" \
                  "Select the ones you want to use.\n"
              )
            )
          ),
          VSpacing(0.5),
          MinSize(
            70,
            16,
            MultiSelectionBox(
              Id(:products),
              _("Additional Products to Select"),
              ask_user_products
            )
          ),
          HBox(
            HStretch(),
            # push button label
            PushButton(Id(:ok), _("Add Selected &Products")),
            HSpacing(1),
            PushButton(Id(:cancel), Label.CancelButton)
          )
        )
      )

      ret = UI.UserInput
      Builtins.y2milestone("User ret: %1", ret)

      # add also selected
      if ret == :ok
        selprods = Convert.convert(
          UI.QueryWidget(:products, :SelectedItems),
          from: "any",
          to:   "list <integer>"
        )
        Builtins.foreach(selprods) do |one_product|
          selected_products = Builtins.add(
            selected_products,
            Ops.get(ask_user_products_map, one_product, {})
          )
        end
      end

      UI.CloseDialog

      Builtins.y2milestone("Selected products: %1", selected_products)

      deep_copy(selected_products)
    end

    def ParseXMLBasedAddOnProductsFile(parse_file, base_url)
      if !FileUtils.Exists(parse_file)
        Builtins.y2error("Cannot parse missing file: %1", parse_file)
        return []
      end

      xmlfile_products = XML.XMLToYCPFile(parse_file)

      if xmlfile_products.nil?
        # TRANSLATORS: error report
        Report.Error(_("Unable to use additional products."))
        Builtins.y2error("Erroneous file %1", parse_file)
        return []
      elsif Ops.get_list(xmlfile_products, "product_items", []) == []
        Builtins.y2warning("Empty file %1", parse_file)
        return []
      end

      products = []

      run_ask_user = false

      Builtins.foreach(Ops.get_list(xmlfile_products, "product_items", [])) do |one_prod|
        if !Builtins.haskey(one_prod, "url")
          Builtins.y2error("No 'url' defined in %1", one_prod)
          next
        end
        # FATE #302123
        if !base_url.nil? && base_url != ""
          Ops.set(
            one_prod,
            "url",
            GetAbsoluteURL(base_url, Ops.get_string(one_prod, "url", ""))
          )
        end
        if Ops.get_boolean(one_prod, "ask_user", false) == true
          run_ask_user = true
        end
        products = Builtins.add(products, one_prod)
      end

      products = UserSelectsRequiredAddOns(products) if run_ask_user

      deep_copy(products)
    end

    # Installs selected products from repository. If list of prods_to_install
    # is empty, all products found are installed.
    #
    # @param [Array<String>,nil] prods_to_install list of product names to install
    # @param [Fixnum] src source ID
    # @return [Boolean] success flag
    def InstallProductsFromRepository(prods_to_install, src)
      prods_to_install = deep_copy(prods_to_install)
      # there are more products at the destination
      # install the listed ones only
      if !prods_to_install.nil? &&
          Ops.greater_than(Builtins.size(prods_to_install), 0)
        Builtins.foreach(prods_to_install) do |one_prod|
          Builtins.y2milestone(
            "Selecting product '%1' for installation",
            one_prod
          )
          if !Pkg.ResolvableInstall(one_prod, :product)
            Report.Error(
              # TRANSLATORS: Product cannot be set for installation.
              # %1 is the product name.
              Builtins.sformat(_("Product %1 not found on media."), one_prod)
            )
          else
            @selected_installation_products << one_prod
          end
        end

        # install all products from the destination
      else
        products = Pkg.ResolvableProperties("", :product, "")
        # only those that come from the new source
        products = Builtins.filter(products) do |p|
          Ops.get_integer(p, "source", -1) == src
        end

        Builtins.foreach(products) do |p|
          Builtins.y2milestone(
            "Selecting product '%1' for installation",
            Ops.get_string(p, "name", "")
          )
          one_prod = p["name"] || ""
          Pkg.ResolvableInstall(one_prod, :product)
          @selected_installation_products << one_prod
        end
      end
      @selected_installation_products.uniq!

      nil
    end

    # Ask for a product medium
    #
    # @param [String] url medium url (either "cd:///" or "dvd:///")
    # @param [String] product_name expected product name
    # @return [String,nil] nil if aborted, otherwise URL with the selected CD device

    def AskForCD(url, product_name)
      parsed = URL.Parse(url)
      scheme = Builtins.tolower(Ops.get_string(parsed, "scheme", ""))

      msg = if product_name.nil? || product_name == ""
        # %1 is either "CD" or "DVD"
        Builtins.sformat(
          _("Insert the addon %1 medium"),
          Builtins.toupper(scheme)
        )
      else
        # %1 is the product name, %2 is either "CD" or "DVD"
        Builtins.sformat(
          _("Insert the %1 %2 medium"),
          product_name,
          Builtins.toupper(scheme)
        )
      end

      # make sure no medium is mounted (the drive is not locked)
      Pkg.SourceReleaseAll

      ui = SourceManager.AskForCD(msg)

      return nil if !Ops.get_boolean(ui, "continue", false)

      cd_device = Ops.get_string(ui, "device", "")
      if !cd_device.nil? && cd_device != ""
        Builtins.y2milestone("Selected CD/DVD device: %1", cd_device)
        query = Ops.get_string(parsed, "query", "")

        query = Ops.add(query, "&") if query != ""

        query = Ops.add(Ops.add(query, "devices="), cd_device)

        Ops.set(parsed, "query", query)
        url = URL.Build(parsed)
      end

      url
    end

    # Add a new repository
    # @param url repo url
    # @param pth product path
    # @param priority
    # @return integer repository ID
    def AddRepo(url, pth, priority)
      # update the URL to the selected device
      new_repo = { "enabled" => true, "base_urls" => [url], "prod_dir" => pth }

      # BNC #714027: Possibility to adjust repository priority (usually higher)
      new_repo["priority"] = priority if priority > -1

      log.info "Adding Repository: #{URL.HidePassword(url)}, product path: #{pth}"
      new_repo_id = Pkg.RepositoryAdd(new_repo)
      log.info "New repository id: #{new_repo_id}"

      if new_repo_id.nil? || new_repo_id < 0
        log.error "Unable to add product: #{URL.HidePassword(url)}"
        # TRANSLATORS: error message, %1 is replaced with product URL
        Report.Error(format(_("Unable to add product %s."), URL.HidePassword(url)))
        return nil
      end

      # Make sure all changes are refreshed
      Pkg.SourceSaveAll
      # download metadata, build repo cache
      Pkg.SourceRefreshNow(new_repo_id)
      # load resolvables to zypp pool
      Pkg.SourceLoad

      new_repo_id
    end

    # Repository network schemes
    NETWORK_SCHEMES = ["http", "https", "ftp", "nfs", "cifs", "slp"].freeze
    # Repository CD/DVD schemes
    CD_SCHEMES = ["cd", "dvd"].freeze

    # Auto-integrate add-on products in specified file (usually add_on_products or
    # add_on_products.xml file)
    #
    # @param [Array<Hash{String => String>}] filelist list of maps describing one
    #   or several add_on_products files
    # @see FATE #303675: Support several add-ons on standard medium
    # @return [Boolean] true on exit
    #
    #
    # **Structure:**
    #
    #
    #      Format of /add_on_products.xml file on media root:
    #      <?xml version="1.0"?>
    #      <add_on_products xmlns="http://www.suse.com/1.0/yast2ns"
    #     	xmlns:config="http://www.suse.com/1.0/configns">
    #     	<product_items config:type="list">
    #     		<product_item>
    #     			<!-- Product name visible in UI when offered to user (optional item) -->
    #     			<name>Add-on Name to Display</name>
    #           <!--
    #             Check product's name (optional item). If set to false, <name> won't be checked
    #             against product's name found in the media (CD/DVD only).
    #           -->
    #           <check_name config:type="boolean">true</check_name>
    #     			<!-- Product URL (mandatory item) -->
    #     			<url>http://product.repository/url/</url>
    #     			<!-- Product path, default is "/" (optional item) -->
    #     			<path>/relative/product/path</path>
    #     			<!--
    #     				List of products to install from media, by default all products
    #     				from media are installed (optional item)
    #     			-->
    #     			<install_products config:type="list">
    #     				<!--
    #     					Product to install - matching the metadata product 'name'
    #     					(mandatory to fully define 'install_products')
    #     				-->
    #     				<product>Product-ID-From-Repository</product>
    #     				<product>...</product>
    #     			</install_products>
    #     			<!--
    #     				If set to 'true', user is asked whether to install this product,
    #     				default is 'false' (optional)
    #     			-->
    #     			<ask_user config:type="boolean">true</ask_user>
    #     			<!--
    #     				Connected to 'ask_user', sets the default status of product,
    #     				default is 'false' (optional)
    #     			-->
    #     			<selected config:type="boolean">true</selected>
    #     			<!--
    #     				Defines priority of the newly added repository (optional).
    #     				Libzypp uses its default priority if not set.
    #     			-->
    #     			<priority config:type="integer">20</priority>
    #     			<!--
    #     				User has to accept license?
    #     			-->
    #                           <confirm_license config:type="boolean">true</confirm_license>
    #     		</product_item>
    #     		<product_item>
    #     			...
    #     		</product_item>
    #     	</product_items>
    #      </add_on_products>
    #
    #
    # **Structure:**
    #
    #     Filelist map is in format
    #      [
    #          $[ "file" : "/local/path/to/an/add_on_products/file",     "type":"plain" ],
    #          $[ "file" : "/local/path/to/an/add_on_products/file.xml", "type":"xml" ]
    #      ]
    def AddPreselectedAddOnProducts(filelist)
      if filelist.nil? || filelist.empty?
        log.info "No add-on products defined on the media or by inst-sys"
        return true
      end

      base_url = GetBaseProductURL()
      log.info "Base URL: #{URL.HidePassword(base_url)}"

      # Processes all add_on_products files found
      filelist.each do |file|
        add_products = parse_add_on_products_file(
          file.fetch("file", ""), file.fetch("type", ""), base_url
        )
        next unless add_products

        log.info "Adding products: #{add_products}"
        add_products.each do |one_product|
          url = one_product.fetch("url", "")
          pth = one_product.fetch("path", "")
          priority = one_product.fetch("priority", -1).to_i
          prodname = one_product.fetch("name", "")
          check_name = one_product.fetch("check_name", true)
          # the default value in AutoYaST is false, otherwise it is true
          confirm_license = one_product.fetch("confirm_license", !Mode.auto)
          Builtins.y2milestone("confirm_license: %1", confirm_license)

          # Check URL and setup network if required or prompt to insert CD/DVD
          parsed = URL.Parse(url)
          scheme = parsed.fetch("scheme", "").downcase
          # check if network needs to be configured
          if NETWORK_SCHEMES.include?(scheme)
            inc_ret = Convert.to_symbol(
              WFM.CallFunction("inst_network_check", [])
            )
            Builtins.y2milestone("inst_network_check ret: %1", inc_ret)
          end

          # a CD/DVD repository
          repo_id =
            if CD_SCHEMES.include?(scheme)
              add_product_from_cd(url, pth, priority, prodname, check_name)
            else
              # a non CD/DVD repository
              AddRepo(url, pth, priority)
            end
          next false unless repo_id

          if confirm_license && !AcceptedLicenseAndInfoFile(repo_id)
            log.warn "License not accepted, delete the repository"
            Pkg.SourceDelete(repo_id)
            next false
          end
          Integrate(repo_id)
          # adding the product to the list of products (BNC #269625)
          prod = Pkg.SourceProductData(repo_id)
          log.info "Repository (#{repo_id} product data: #{prod})"
          @selected_installation_products = []
          InstallProductsFromRepository(one_product.fetch("install_products", []), repo_id)
          new_add_on_product = {
            "media"            => repo_id,
            "product"          => Ops.get_locale(
              one_product,
              "name",
              Ops.get_locale(
                prod,
                "label",
                Ops.get_locale(prod, "productname", _("Unknown Product"))
              )
            ),
            "autoyast_product" => Ops.get_locale(
              prod,
              "productname",
              Ops.get_locale(one_product, "name", _("Unknown Product"))
            ),
            "media_url"        => url,
            "product_dir"      => pth
          }
          new_add_on_product["priority"] = priority if priority > -1
          @add_on_products = Builtins.add(@add_on_products, new_add_on_product)
        end
      end

      # reread agents, redraw wizard steps, etc.
      ReIntegrateFromScratch()

      true
    end

    # Export/Import -->

    # Returns map describing all used add-ons.
    #
    # @return [Hash]
    #
    # @example This is an XML file created from exported map:
    #      <add-on>
    #        <add_on_products config:type="list">
    #          <listentry>
    #            <media_url>ftp://server.name/.../</media_url>
    #            <product>NEEDS_TO_MATCH_"PRODUCT"_TAG_FROM_content_FILE!</product>
    #            <product_dir>/</product_dir>
    #          </listentry>
    #          ...
    #        </add_on_products>
    #      </add-on>
    def Export
      Builtins.y2milestone("Add-Ons Input: %1", @add_on_products)

      exp = Builtins.maplist(@add_on_products) do |p|
        p = Builtins.remove(p, "media") if Builtins.haskey(p, "media")
        # bugzilla #279893
        if Builtins.haskey(p, "autoyast_product")
          Ops.set(p, "product", Ops.get_string(p, "autoyast_product", ""))
          p = Builtins.remove(p, "autoyast_product")
        end
        deep_copy(p)
      end

      Builtins.y2milestone("Add-Ons Output: %1", exp)

      { "add_on_products" => exp }
    end

    # Create URL with required alias from a URL.
    # If alias is empty the name is used as a fallback.
    # If both are empty the URL is not modified.
    # If alias is already included in the URL then it is modified
    # only if the requested alias is not empty otherwise it is kept unchanged.
    def SetRepoUrlAlias(url, alias_name, name)
      if url.nil? || url == ""
        Builtins.y2error("Invalid 'url' parameter: %1", url)
        return url
      end

      # set repository alias to product name or alias if specified
      if !name.nil? && name != "" || !alias_name.nil? && alias_name != ""
        url_p = URL.Parse(url)
        params = URL.MakeMapFromParams(Ops.get_string(url_p, "query", ""))
        new_alias = ""

        if !alias_name.nil? && alias_name != ""
          new_alias = alias_name
          Builtins.y2milestone("Using repository alias: '%1'", new_alias)
        # no alias present in the URL, use the product name
        elsif Ops.get(params, "alias", "") != ""
          new_alias = name
          Builtins.y2milestone(
            "Using product name '%1' as repository alias",
            new_alias
          )
        else
          Builtins.y2milestone(
            "Keeping the original alias set in the URL: %1",
            Ops.get(params, "alias", "")
          )
          return url
        end

        Ops.set(params, "alias", new_alias)
        Ops.set(url_p, "query", URL.MakeParamsFromMap(params))
        url = URL.Build(url_p)
      end

      url
    end

    def Import(settings)
      settings = deep_copy(settings)
      @add_on_products = Ops.get_list(settings, "add_on_products", [])
      @modified = false
      Builtins.foreach(@add_on_products) do |prod|
        Builtins.y2milestone("Add-on product: %1", prod)
        pth = Ops.get_string(prod, "product_dir", "/")
        url = SetRepoUrlAlias(
          Ops.get_string(prod, "media_url", ""),
          Ops.get_string(prod, "alias", ""),
          Ops.get_string(prod, "name", "")
        )
        src = Pkg.SourceCreate(url, pth)
        if src != -1
          if Ops.get_string(prod, "product", "") != ""
            repo = {
              "SrcId" => src,
              "name"  => Ops.get_string(prod, "product", "")
            }
            if Ops.greater_than(Ops.get_integer(prod, "priority", -1), -1)
              Ops.set(repo, "priority", Ops.get_integer(prod, "priority", -1))
            end
            Builtins.y2milestone("Setting new repo properties: %1", repo)
            Pkg.SourceEditSet([repo])
          end
          @mode_config_sources = Builtins.add(@mode_config_sources, src)
        end
      end if Mode.config

      true
    end

    def CleanModeConfigSources
      Builtins.foreach(@mode_config_sources) { |src| Pkg.SourceDelete(src) }
      @mode_config_sources = []

      nil
    end

    # Returns the path where Add-Ons configuration is stored during the fist stage installation.
    # This path reffers to the installed system.
    #
    # @see bugzilla #187558
    def TmpExportFilename
      Ops.add(Directory.vardir, "/exported_add_ons_configuration")
    end

    # Reads the Add-Ons configuration stored on disk during the first stage installation.
    #
    # @see bugzilla #187558
    def ReadTmpExportFilename
      tmp_filename = TmpExportFilename()
      @modified = true

      if FileUtils.Exists(tmp_filename)
        Builtins.y2milestone("Reading %1 content", tmp_filename)

        # there might be something already set, store the current configuration
        already_in_configuration = deep_copy(@add_on_products)
        configuration_from_disk = Convert.to_map(
          SCR.Read(path(".target.ycp"), tmp_filename)
        )
        Builtins.y2milestone(
          "Configuration from disk: %1",
          configuration_from_disk
        )

        if !configuration_from_disk.nil?
          Import(configuration_from_disk)
          if already_in_configuration != [] && !already_in_configuration.nil?
            @add_on_products = Convert.convert(
              Builtins.union(@add_on_products, already_in_configuration),
              from: "list",
              to:   "list <map <string, any>>"
            )
          end
          return true
        else
          Builtins.y2error("Reading %1 file returned nil result!", tmp_filename)
          return false
        end
      else
        Builtins.y2warning("File %1 doesn't exists, skipping...", tmp_filename)
        return true
      end
    end

    def AcceptUnsignedFile(file, repo)
      Builtins.y2milestone(
        "Accepting unsigned file %1 from repository %2",
        file,
        repo
      )
      true
    end

    def RejectUnsignedFile(file, repo)
      Builtins.y2milestone(
        "Rejecting unsigned file %1 from repository %2",
        file,
        repo
      )
      false
    end

    def AcceptFileWithoutChecksum(file)
      Builtins.y2milestone("Accepting file without checksum: %1", file)
      true
    end

    def RejectFileWithoutChecksum(file)
      Builtins.y2milestone("Rejecting file without checksum: %1", file)
      false
    end

    def AcceptVerificationFailed(file, key, repo)
      key = deep_copy(key)
      Builtins.y2milestone(
        "Accepting failed verification of file %1 with key %2 from repository %3",
        file,
        key,
        repo
      )
      true
    end

    def RejectVerificationFailed(file, key, repo)
      key = deep_copy(key)
      Builtins.y2milestone(
        "Rejecting failed verification of file %1 with key %2 from repository %3",
        file,
        key,
        repo
      )
      false
    end

    def AcceptUnknownGpgKeyCallback(filename, keyid, repo)
      Builtins.y2milestone(
        "AcceptUnknownGpgKeyCallback %1: %2 (from repository %3)",
        filename,
        keyid,
        repo
      )

      Ops.get_boolean(
        @current_addon,
        ["signature-handling", "accept_unknown_gpg_key", "all"],
        false
      ) ||
        Builtins.contains(
          Ops.get_list(
            @current_addon,
            ["signature-handling", "accept_unknown_gpg_key", "keys"],
            []
          ),
          keyid
        )
    end

    def ImportGpgKeyCallback(key, repo)
      key = deep_copy(key)
      Builtins.y2milestone(
        "ImportGpgKeyCallback: %1 from repository %2",
        key,
        repo
      )

      Ops.get_boolean(
        @current_addon,
        ["signature-handling", "import_gpg_key", "all"],
        false
      ) ||
        Builtins.contains(
          Ops.get_list(
            @current_addon,
            ["signature-handling", "import_gpg_key", "keys"],
            []
          ),
          Ops.get_string(key, "id", "")
        )
    end

    def AcceptNonTrustedGpgKeyCallback(key)
      key = deep_copy(key)
      Builtins.y2milestone("AcceptNonTrustedGpgKeyCallback %1", key)

      Ops.get_boolean(
        @current_addon,
        ["signature-handling", "accept_non_trusted_gpg_key", "all"],
        false
      ) ||
        Builtins.contains(
          Ops.get_list(
            @current_addon,
            ["signature-handling", "accept_non_trusted_gpg_key", "keys"],
            []
          ),
          Ops.get_string(key, "id", "")
        )
    end

    # <-- Export/Import
    # @example
    #   <add-on>
    #     <add_on_products config:type="list">
    #       <listentry>
    #         <media_url>http://software.opensuse.org/download/server:/dns/SLE_10/</media_url>
    #         <product>buildservice</product>
    #         <product_dir>/</product_dir>
    #         <signature-handling>
    #            <accept_unsigned_file config:type="boolean">true</accept_unsigned_file>
    #            <accept_file_without_checksum config:type="boolean">
    #              true
    #            </accept_file_without_checksum>
    #            <accept_verification_failed config:type="boolean">true</accept_verification_failed>
    #            <accept_unknown_gpg_key>
    #              <all config:type="boolean">true</all>
    #              <keys config:type="list">
    #                 <keyid>...</keyid>
    #                 <keyid>3B3011B76B9D6523</keyid>
    #              </keys>
    #            </accept_unknown_gpg_key>
    #            <accept_non_trusted_gpg_key>
    #              <all config:type="boolean">true</all>
    #              <keys config:type="list">
    #                 <keyid>...</keyid>
    #              </keys>
    #            </accept_non_trusted_gpg_key>
    #            <import_gpg_key>
    #              <all config:type="boolean">true</all>
    #              <keys config:type="list">
    #                 <keyid>...</keyid>
    #              </keys>
    #            </import_gpg_key>
    #         </signature-handling>
    #       </listentry>
    #     </add_on_products>
    #   </add-on>
    def SetSignatureCallbacks(product)
      @current_addon = {}
      Builtins.foreach(@add_on_products) do |addon|
        next if Ops.get_string(addon, "product", "") != product
        @current_addon = deep_copy(addon) # remember the current addon for the Callbacks
        if Builtins.haskey(
          Ops.get_map(addon, "signature-handling", {}),
          "accept_unsigned_file"
        )
          Pkg.CallbackAcceptUnsignedFile(
            if Ops.get_boolean(
              addon,
              ["signature-handling", "accept_unsigned_file"],
              false
            )
              fun_ref(method(:AcceptUnsignedFile), "boolean (string, integer)")
            else
              fun_ref(method(:RejectUnsignedFile), "boolean (string, integer)")
            end
          )
        end
        if Builtins.haskey(
          Ops.get_map(addon, "signature-handling", {}),
          "accept_file_without_checksum"
        )
          Pkg.CallbackAcceptFileWithoutChecksum(
            if Ops.get_boolean(
              addon,
              ["signature-handling", "accept_file_without_checksum"],
              false
            )
              fun_ref(method(:AcceptFileWithoutChecksum), "boolean (string)")
            else
              fun_ref(method(:RejectFileWithoutChecksum), "boolean (string)")
            end
          )
        end
        if Builtins.haskey(
          Ops.get_map(addon, "signature-handling", {}),
          "accept_verification_failed"
        )
          Pkg.CallbackAcceptVerificationFailed(
            if Ops.get_boolean(
              addon,
              ["signature-handling", "accept_verification_failed"],
              false
            )
              fun_ref(
                method(:AcceptVerificationFailed),
                "boolean (string, map <string, any>, integer)"
              )
            else
              fun_ref(
                method(:RejectVerificationFailed),
                "boolean (string, map <string, any>, integer)"
              )
            end
          )
        end
        if Builtins.haskey(
          Ops.get_map(addon, "signature-handling", {}),
          "accept_unknown_gpg_key"
        )
          Pkg.CallbackAcceptUnknownGpgKey(
            fun_ref(
              method(:AcceptUnknownGpgKeyCallback),
              "boolean (string, string, integer)"
            )
          )
        end
        if Builtins.haskey(
          Ops.get_map(addon, "signature-handling", {}),
          "import_gpg_key"
        )
          Pkg.CallbackImportGpgKey(
            fun_ref(
              method(:ImportGpgKeyCallback),
              "boolean (map <string, any>, integer)"
            )
          )
        end
        raise Break
      end
      nil
    end

    # Determine whether a product has been renamed
    #
    # @param old_name [String] Old product's name
    # @param new_name [String] New product's name
    # @return [Boolean] +true+ if the product was renamed; otherwise, +false+.
    def renamed?(old_name, new_name)
      renamed_externally?(old_name, new_name) ||
        renamed_by_libzypp?(old_name, new_name) ||
        renamed_by_default?(old_name, new_name)
    end

    # Add a product's rename
    #
    # This method won't try to update the rename if it already exists.
    # Renames added will be tracked in order to not loose information.
    #
    # @param old_name [String] Old product's name
    # @param new_name [String] New product's name
    def add_rename(old_name, new_name)
      # already known
      return if renamed_externally?(old_name, new_name)
      log.info "Adding product rename: '#{old_name}' => '#{new_name}'"
      self.external_product_renames = add_rename_to_hash(external_product_renames,
        old_name, new_name)
    end

    publish variable: :add_on_products, type: "list <map <string, any>>"
    publish variable: :src_id, type: "integer"
    publish variable: :last_ret, type: "symbol"
    publish variable: :modified, type: "boolean"
    publish variable: :mode_config_sources, type: "list <integer>"
    publish variable: :current_addon, type: "map <string, any>"
    publish variable: :low_memory_already_reported, type: "boolean"
    publish variable: :skip_add_ons, type: "boolean"
    publish function: :GetCachedFileFromSource,
            type:     "string (integer, integer, string, string, boolean)"
    publish function: :AddOnMode, type: "string (integer)"
    publish function: :SetBaseProductURL, type: "void (string)"
    publish function: :GetBaseProductURL, type: "string ()"
    publish function: :GetAbsoluteURL, type: "string (string, string)"
    publish function: :UpdateInstSys, type: "boolean (string)"
    publish function: :RereadAllSCRAgents, type: "void ()"
    publish function: :AcceptedLicenseAndInfoFile, type: "boolean (integer)"
    publish function: :ClearRegistrationRequest, type: "void (integer)"
    publish function: :ProcessRegistration, type: "boolean ()"
    publish function: :RemoveRegistrationFlag, type: "void (integer)"
    publish function: :PrepareForRegistration, type: "void (integer)"
    publish function: :RegisterAddOnProduct, type: "void (integer)"
    publish function: :DoInstall, type: "symbol ()"
    publish function: :Integrate, type: "boolean (integer)"
    publish function: :Disintegrate, type: "void (integer)"
    publish function: :ReIntegrateFromScratch, type: "boolean ()"
    publish function: :CheckProductDependencies, type: "boolean (list <string>)"
    publish function: :AddPreselectedAddOnProducts, type: "boolean (list <map <string, string>>)"
    publish function: :Export, type: "map ()"
    publish function: :SetRepoUrlAlias, type: "string (string, string, string)"
    publish function: :Import, type: "boolean (map)"
    publish function: :CleanModeConfigSources, type: "void ()"
    publish function: :TmpExportFilename, type: "string ()"
    publish function: :ReadTmpExportFilename, type: "boolean ()"
    publish function: :AcceptUnknownGpgKeyCallback, type: "boolean (string, string, integer)"
    publish function: :ImportGpgKeyCallback, type: "boolean (map <string, any>, integer)"
    publish function: :AcceptNonTrustedGpgKeyCallback, type: "boolean (map <string, any>)"
    publish function: :SetSignatureCallbacks, type: "void (string)"

  private

    # Determine whether a rename for a product was added
    #
    # This method will return true if a rename was added through
    # the #add_rename method (for example, a rename taken from
    # SCC).
    #
    # @param old_name [String] Old product's name
    # @param new_name [String] New product's name
    # @return [Boolean] +true+ if the product was renamed; otherwise, +false+.
    #
    # @see #renamed_at?
    def renamed_externally?(old_name, new_name)
      log.info "Search #{old_name} -> #{new_name} rename in added renames map: " \
        "#{external_product_renames.inspect}"
      renamed_at?(external_product_renames, old_name, new_name)
    end

    # Determine whether a product was renamed using libzypp
    #
    # libzypp (through #ResolvableProperties and #ResolvableDependencies method) is used
    # to determine whether the product was renamed or not.
    #
    # @param old_name [String] Old product's name
    # @param new_name [String] New product's name
    # @return [Boolean] +true+ if the product was renamed; otherwise, +false+.
    #
    # @see #renamed_at?
    def renamed_by_libzypp?(old_name, new_name)
      renames = product_renames_from_libzypp
      log.info "Search #{old_name} -> #{new_name} rename in libzypp: " \
        "#{renames.inspect}"
      renamed_at?(renames, old_name, new_name)
    end

    # Determine whether a product rename is included in the fallback map
    #
    # @see DEFAULT_PRODUCT_RENAMES
    # @see #renamed_at?
    def renamed_by_default?(old_name, new_name)
      log.info "Search #{old_name} -> #{new_name} rename in default map: " \
        "#{DEFAULT_PRODUCT_RENAMES.inspect}"
      renamed_at?(DEFAULT_PRODUCT_RENAMES, old_name, new_name)
    end

    # Determine whether a product rename is present on a given hash
    #
    # @param renames  [Hash] Product renames in form old_name => [new_name1, new_name2, ...]
    # @param old_name [String] Old product's name
    # @param new_name [String] New product's name
    # @return [Boolean] +true+ if the product was renamed; otherwise, +false+.
    def renamed_at?(renames, old_name, new_name)
      return false unless renames[old_name]
      renames[old_name].include?(new_name)
    end

    # Get product renames from libzypp
    #
    # @see names_from_product_package
    # @see add_rename_to_hash
    def product_renames_from_libzypp
      renames = {}
      # Dependencies are not included in this call
      products = Pkg.ResolvableProperties("", :product, "")
      products.each do |product|
        renames = names_from_product_packages(product["product_package"])
                  .reduce(renames) do |hash, rename|
          add_rename_to_hash(hash, rename, product["name"])
        end
      end
      renames
    end

    # Regular expresion to extract the product name. It supports two different
    # formats: "product:NAME" and "product(NAME)"
    # @see product_name_from_dep
    PRODUCTS_REGEXP = /\Aproduct(?::|\()([^\)\b]+)/

    # Extracts product's name from dependency
    #
    #
    # @see renamed_by_libzypp?
    def product_name_from_dep(dependency)
      matches = PRODUCTS_REGEXP.match(dependency)
      matches.nil? ? nil : matches[1]
    end

    # Add a product's rename to a given hash
    #
    # It will be ignored if:
    #
    # * old and new names are the same or
    # * the rename it's already included
    #
    # @param renames  [Hash]   Renames following the format <old_name> => [ <new_name> ]
    # @param old_name [String] Old product's name
    # @param new_name [String] New product's name
    # @return [Hash] Product renames hash adding the new rename if needed
    #
    # @see #add_rename
    def add_rename_to_hash(renames, old_name, new_name)
      return renames if old_name == new_name || renamed_at?(renames, old_name, new_name)
      log.info "Adding product rename: '#{old_name}' => '#{new_name}'"
      renames.merge(old_name => [new_name]) do |_key, old_val, new_val|
        old_val.nil? ? [new_val] : old_val + new_val
      end
    end

    # Determines the products for a product package
    #
    # The renames are extracted from the "obsoletes" and "provides" dependencies
    # (renames like 'SUSE_SLES' to 'SLES' are defined in the "provides"
    # dependencies only).
    #
    # @return [Array<String>] Old names
    def names_from_product_packages(package_name)
      # Get package dependencies (not retrieved when using Pkg.ResolvableProperties)
      packages = Pkg.ResolvableDependencies(package_name, :package, "")
      return [] if packages.nil? || packages.empty?
      result = packages.each_with_object([]) do |package, names|
        next names unless package.key?("deps")
        # Get information from 'obsoletes' and 'provides' keys
        relevant_deps = package["deps"].map { |d| d["obsoletes"] || d["provides"] }.compact
        names.concat(relevant_deps.map { |d| product_name_from_dep(d) })
      end
      result.compact.uniq
    end

    # Adds a product from a CD/DVD
    #
    # To add the product, the name should match +prodname+ argument.
    #
    # @param url         [String]  Repository URL (cd: or dvd: schemas are expected)
    # @param pth         [String]  Repository path (in the media)
    # @param priority    [Integer] Repository priority
    # @param prodname    [String]  Expected product's name
    # @param check_name  [Boolean] Check product's name
    # @return            [Integer,nil] Repository id; nil if product was not found
    #   and user cancelled.
    #
    # @see add_repo_from_cd
    def add_product_from_cd(url, pth, priority, prodname, check_name)
      current_url = url
      loop do
        # just try if it's there and ask if not
        repo_id = AddRepo(current_url, pth, priority)
        if repo_id
          return repo_id if !check_name || prodname.empty?
          found_product = Pkg.SourceProductData(repo_id)
          return repo_id if found_product["label"] == prodname
          log.info("Removing repo #{repo_id}: Add-on found #{found_product["label"]}," \
            "expected: #{prodname}")
          Pkg.SourceDelete(repo_id)
        end

        # ask for a different medium
        current_url = AskForCD(url, prodname)
        return nil if current_url.nil?
      end
    end

    # Parse a add-on products file
    #
    # @param filename [String] File path
    # @param type     [String] File type ("xml" or "plain")
    # @param base_url [String] Product's base URL
    # @return [Hash] Add-on specification (allowed keys
    #                are "name", "url", "path", "install_products",
    #                "check_name", "ask_user", "selected" and "priority").
    #
    # @see ParseXMLBasedAddOnProductsFile
    # @see ParsePlainAddOnProductsFile
    # @see AddPreselectedAddOnProducts
    def parse_add_on_products_file(filename, type, base_url)
      case type.downcase
      when "xml"
        ParseXMLBasedAddOnProductsFile(filename, base_url)
      when "plain"
        ParsePlainAddOnProductsFile(filename, base_url)
      else
        log.error "Unsupported type: #{type}"
        false
      end
    end

    # Download the y2update from the addon package.
    # @param src_id [Fixnum] repository ID
    # @return [String,nil] full path to the `y2update.tgz` file or nil if not found
    def y2update_path(src_id)
      # fetch and extract the "installerextension" package
      WorkflowManager.GetCachedWorkflowFilename(:addon, src_id, nil)
      y2update = File.join(WorkflowManager.addon_control_dir(src_id), "y2update.tgz")
      return nil unless File.exist?(y2update)

      log.info("Found y2update.tgz file from the installer extension package: #{y2update}")
      y2update
    end
  end

  AddOnProduct = AddOnProductClass.new
  AddOnProduct.main
end
