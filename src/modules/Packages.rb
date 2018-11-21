# encoding: utf-8
require "yast"

# html_escape()
require "erb"
require "fileutils"
require "uri"
require "cgi"

# Yast namespace
module Yast
  # Package selections
  class PackagesClass < Module
    include Yast::Logger
    include ERB::Util

    attr_reader :missing_remote_packages, :missing_remote_kind

    # All known types of resolvables
    RESOLVABLE_TYPES = [:product, :patch, :package, :pattern, :language].freeze

    # Key to sort by resolvable selection
    RESOLVABLE_SORT_ORDER = { product: "source", pattern: "order" }.freeze

    # Minimum set of packages tags required to enable VNC server
    VNC_BASE_TAGS = ["xorg-x11", "xorg-x11-Xvnc", "xorg-x11-fonts"].freeze
    # Additional packages tags needed to run second stage in graphical mode
    AUTOYAST_X11_TAGS = ["libyui-qt", "yast2-x11"].freeze
    # Default window manager for VNC if none is installed
    DEFAULT_WM = "icewm".freeze
    # Minimum set of packages required for installation with remote X11 server
    REMOTE_X11_BASE_TAGS = ["xorg-x11-server", "xorg-x11-fonts", "icewm"].freeze
    # Graphical packages for VNC installation
    GRAPHIC_PACKAGES = ["xorg-x11-server", "xorg-x11-server-glx", "libusb", "yast2-x11"].freeze

    BASE_PRODUCT_FILE = "/etc/products.d/baseproduct".freeze

    def main
      Yast.import "UI"
      Yast.import "Pkg"
      Yast.import "Mode"

      textdomain "packager"

      Yast.import "AddOnProduct"
      Yast.import "WorkflowManager"
      Yast.import "Arch"
      Yast.import "Directory"
      Yast.import "InstURL"
      Yast.import "Kernel"
      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "Linuxrc"
      Yast.import "Language"
      Yast.import "ProductFeatures"
      Yast.import "ProductControl"
      Yast.import "Report"
      Yast.import "Slides"
      Yast.import "SlideShow"
      Yast.import "SpaceCalculation"
      Yast.import "String"
      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "Wizard"
      Yast.import "PackageCallbacks"
      Yast.import "Product"
      Yast.import "DefaultDesktop"
      Yast.import "SourceDialogs"
      Yast.import "FileUtils"
      Yast.import "Installation"
      Yast.import "URL"
      Yast.import "PackagesProposal"
      Yast.import "HTML"

      Yast.include self, "packager/load_release_notes.rb"

      # Force full proposal routine next run
      @full_repropose = false

      # repository has been initialized?
      @init_called = false

      # repository initialization is WIP
      @init_in_progress = false

      # Error which occurred during repository initialization
      @init_error = nil

      # cache for the proposed summary
      @cached_proposal = nil

      # the selection used for the cached proposal
      # the default values 'nil' say that the proposal hasn't been called yet
      @cached_proposal_packages = nil
      @cached_proposal_patterns = nil
      @cached_proposal_products = nil
      @cached_proposal_patches = nil
      @cached_proposal_languages = nil

      @install_sources = false # Installing source packages ?
      @timestamp = 0 # last time of getting the target map

      @metadir = "/yast-install"
      @metadir_used = false # true if meta data and inst-sys is in ramdisk

      @theSources = [] # id codes of repositories in priority order
      @theSourceDirectories = [] # product directories on repositories
      @theSourceOrder = {} # installation order

      @servicepack_metadata = "/servicepack.tar.gz"

      # to remember if warning should occurre if switching base selection
      @base_selection_modified = false

      @base_selection_changed = false

      # Local variables

      @choosen_base_selection = ""

      # count of errors during packages solver
      @solve_errors = 0

      # Packages to be selected when proposing the list
      @additional_packages = []

      @system_packages_selected = false

      @add_on_products_list = []

      # list of basic system directories, if any of them cannot be mounted
      # the installation will be blocked
      @basic_dirs = [
        "/",
        "/bin",
        "/boot",
        "/etc",
        "/lib",
        "/lib64",
        "/opt",
        "/sbin",
        "/usr",
        "/var"
      ]

      @base_source_id = nil

      @old_packages_proposal = nil

      # Remote kinds (vnc, ssh,...) which cannot be used in an
      # installed system.
      @missing_remote_kind = []
      # Packages which are missed to enable remote handling in
      # an installed system.
      @missing_remote_packages = []
    end

    # summary functions

    def ResetProposalCache
      Builtins.y2milestone("Reseting the software proposal cache")

      @cached_proposal_packages = nil
      @cached_proposal_patterns = nil
      @cached_proposal_products = nil
      @cached_proposal_patches = nil
      @cached_proposal_languages = nil

      nil
    end

    # List selected resolvables of specified kind
    # @param [Symbol] what symbol specifying the kind of resolvables to select
    # @param [String] format string format string to print summaries in
    # @return a list of selected resolvables
    def ListSelected(what, format)
      selected = Pkg.ResolvableProperties("", what, "")

      selected.select! { |r| r["status"] == :selected }

      selected.select! { |r| r["user_visible"] } if what == :pattern

      sort_resolvable!(selected, what)

      formatted_resolvables(selected, format)
    end

    # Count the total size of packages to be installed
    # @return [String] formatted size of packages to be installed
    def CountSizeToBeInstalled
      sz = 0
      media_sizes = Pkg.PkgMediaSizes

      Builtins.foreach(media_sizes) do |inst_sizes|
        Builtins.foreach(inst_sizes) do |inst_size|
          sz = Ops.add(sz, inst_size)
        end
      end

      Builtins.y2milestone(
        "Total size of packages to install %1 (%2kB)",
        sz,
        Ops.divide(sz, 1024)
      )
      String.FormatSizeWithPrecision(sz, 1, true)
    end

    def SrcMapping
      index = 0

      src_list = Pkg.PkgMediaNames
      Builtins.y2debug("source names: %1", src_list)

      srcid_to_current_src_no = Builtins.listmap(src_list) do |src|
        index = Ops.add(index, 1)
        { Ops.get_integer(src, 1, -1) => index }
      end

      Builtins.y2milestone(
        "Repository mapping information: %1",
        srcid_to_current_src_no
      )
      deep_copy(srcid_to_current_src_no)
    end

    # Count the total size of packages to be installed
    # @return [Fixnum] size of packages to be installed (in bytes)
    def CountSizeToBeDownloaded
      ret = 0

      # get list of remote repositories
      # consider only http(s) and ftp protocols as remote

      # all enabled sources
      repos = Pkg.SourceGetCurrent(true)
      remote_repos = []

      Builtins.foreach(repos) do |repo|
        url = Ops.get_string(Pkg.SourceGeneralData(repo), "url", "")
        scheme = Builtins.tolower(Ops.get_string(URL.Parse(url), "scheme", ""))
        if scheme == "http" || scheme == "https" || scheme == "ftp"
          Builtins.y2milestone("Found remote repository %1: %2", repo, url)
          remote_repos = Builtins.add(remote_repos, repo)
        end
      end

      # shortcut, no remote repository found
      if Builtins.size(remote_repos).zero?
        Builtins.y2milestone("No remote repository found")
        return 0
      end

      repo_mapping = SrcMapping()

      media_sizes = Pkg.PkgMediaPackageSizes
      Builtins.y2debug("Media sizes: %1", media_sizes)

      Builtins.foreach(remote_repos) do |repoid|
        repo_media_sizes = Ops.get(
          media_sizes,
          Ops.subtract(Ops.get(repo_mapping, repoid, -1), 1),
          []
        )
        Builtins.foreach(repo_media_sizes) do |media_size|
          ret = Ops.add(ret, media_size)
        end
      end

      Builtins.y2milestone(
        "Total size of packages to download: %1 (%2kB)",
        ret,
        Ops.divide(ret, 1024)
      )
      ret
    end

    # Return information about suboptimal distribution if relevant
    # @return [String] the information string or empty string
    def InfoAboutSubOptimalDistribution
      if ProductFeatures.GetBooleanFeature(
        "software",
        "inform_about_suboptimal_distribution"
      ) &&
          Arch.i386
        tmp = Convert.to_string(
          SCR.Read(path(".proc.cpuinfo.value.\"0\".\"flags\""))
        )
        flags = tmp.empty? ? [] : tmp.split(" ")

        # this depends on the cpu (lm = long mode)
        if Builtins.contains(flags, "lm")
          # warning text
          return _(
            "Your computer is a 64-bit x86-64 system, " \
              "but you are trying to install a 32-bit distribution."
          )
        end
      end
      ""
    end

    def SummaryHelp(flags)
      flags = deep_copy(flags)
      ret = ""

      if Builtins.contains(flags, :pattern)
        # help text for software proposal
        ret = Ops.add(
          ret,
          _(
            "<P>The pattern list states which functionality will be available " \
              "after installing the system.</P>"
          )
        )
      end

      if Builtins.contains(flags, :size)
        ret = Ops.add(
          Ops.add(
            ret,
            # (see bnc#178357 why these numbers)
            # translators: help text for software proposal
            _(
              "<P>The proposal reports the total size of files which will be installed " \
                "to the system. However, the system will contain some other files " \
                "(temporary and working files) so the used space will be slightly larger " \
                "than the proposed value. Therefore it is a good idea to have at least " \
                "25% (or about 300MB) free space before starting the installation.</P>"
            )
          ),
          # help text for software proposal
          _(
            "<P>The total 'size to download' is the size of the packages which will be\n" \
              "downloaded from remote (network) repositories. This value is important if " \
              "the connection is slow or if there is a data limit for downloading.</P>\n"
          )
        )
      end

      # add a header if the result is not empty
      if ret != ""
        # help text for software proposal - header
        ret = Ops.add(_("<P><B>Software Proposal</B></P>"), ret)
      end

      ret
    end

    # Return the summary output lines
    # @param [Array<Symbol>] flags a list of flags, allowed are `product, `pattern, `selection,
    #  `size, `desktop
    # @return a list of the output lines
    def SummaryOutput(flags)
      flags = deep_copy(flags)
      output = [InfoAboutSubOptimalDistribution()]
      if Builtins.contains(flags, :product)
        # installation proposal - SW summary, %1 is name of the installed product
        # (e.g. openSUSE 10.3, SUSE Linux Enterprise ...)
        output = Convert.convert(
          Builtins.merge(output, ListSelected(:product, _("Product: %1"))),
          from: "list",
          to:   "list <string>"
        )
      end

      if Builtins.contains(flags, :desktop)
        # BNC #422077, Desktop doesn't need to be defined, e.g. in SLED
        # BNC #431336 ... and even if it is defined, it needn't be visible
        ddd = DefaultDesktop.Description
        if ddd != ""
          # installation proposal - SW summary, %1 is name of the selected desktop or
          # system type (e.g. KDE)
          output = Builtins.add(
            output,
            Builtins.sformat(_("System Type: %1"), ddd)
          )
        end
      end

      if Builtins.contains(flags, :pattern)
        patterns = ListSelected(:pattern, "%1")

        if Ops.greater_than(Builtins.size(patterns), 0)
          output = Builtins.add(
            output,
            # TODO: simply delete the br once we can afford to break translations again
            Ops.add(_("Patterns:<br>").chomp("<br>"), HTML.List(patterns))
          )
        end
      end

      if Builtins.contains(flags, :size)
        output = Builtins.add(
          output,
          # installation proposal - SW summary, %1 is size of the selected packages (in MB or GB)
          Builtins.sformat(
            _("Size of Packages to Install: %1"),
            CountSizeToBeInstalled()
          )
        )

        # add download size
        download_size = CountSizeToBeDownloaded()
        if Ops.greater_than(download_size, 0)
          output = Builtins.add(
            output,
            # installation proposal - SW summary, %1 is download size of the selected packages
            # which will be installed from an ftp or http repository (in MB or GB)
            Builtins.sformat(
              _("Downloading from Remote Repositories: %1"),
              String.FormatSizeWithPrecision(download_size, 1, true)
            )
          )
        end
      end

      output = Builtins.filter(output) { |o| o != "" && !o.nil? }

      deep_copy(output)
    end

    # Check if selected software fits on the partitions
    # @param [Boolean] init boolean true if partition sizes have changed
    # @return [Boolean] true if selected software fits, false otherwise
    def CheckDiskSize(init)
      if init
        Builtins.y2milestone("Resetting space calculation")
        SpaceCalculation.GetPartitionInfo
      end
      SpaceCalculation.CheckDiskSize
    end

    # Checks which products have been selected for removal and modifies
    # the warning messages accordingly.
    #
    # @param [Yast::ArgRef] ret reference to map MakeProposal->Summary
    def CheckOldAddOns(ret)
      products = Pkg.ResolvableProperties("", :product, "")
      products = Builtins.filter(products) do |one_product|
        Ops.get_symbol(one_product, "status_detail", :unknown) == :S_AutoDel
      end

      # no such products
      if Builtins.size(products).zero?
        Builtins.y2milestone("No products marked for auto-removal")
        return
      end

      Builtins.y2warning("Product marked for auto-removal: %1", products)

      warning = ""

      Builtins.foreach(products) do |one_product|
        warning = Ops.add(
          Ops.add(
            Ops.add(warning, "<li>"),
            Ops.get_locale(
              one_product,
              "display_name",
              Ops.get_locale(
                one_product,
                "name",
                Ops.get_locale(one_product, "NCL", _("Unknown Product"))
              )
            )
          ),
          "</li>\n"
        )
      end

      warning = Builtins.sformat(
        _("These add-on products have been marked for auto-removal: %1"),
        Ops.add(Ops.add("<ul>\n", warning), "</ul>\n")
      )

      # raising warning level if needed
      if Ops.get(ret.value, "warning_level").nil? ||
          Builtins.contains(
            [:notice, :ok],
            Ops.get_symbol(ret.value, "warning_level", :warning)
          )
        Ops.set(ret.value, "warning_level", :warning)
      end

      if Ops.greater_than(
        Builtins.size(Ops.get_string(ret.value, "warning", "")),
        0
      )
        Ops.set(
          ret.value,
          "warning",
          Ops.add(
            Ops.add(Ops.get_string(ret.value, "warning", ""), "<br>\n"),
            if Ops.greater_than(Builtins.size(products), 1)
              # Warning message when some add-ons are marked to be removed automatically
              _(
                "Contact the vendors of these add-ons to provide you with new installation media."
              )
            else
              # Warning message when some add-ons are marked to be removed automatically
              _(
                "Contact the vendor of the add-on to provide you with a new installation media."
              )
            end
          )
        )
      end

      Ops.set(
        ret.value,
        "warning",
        Ops.add(Ops.get_string(ret.value, "warning", ""), warning)
      )

      nil
    end

    def AddFailedMounts(summary)
      summary = deep_copy(summary)
      failed_mounts = SpaceCalculation.GetFailedMounts
      Builtins.y2milestone(
        "Failed mounts: %1: %2",
        Builtins.size(failed_mounts),
        failed_mounts
      )

      Builtins.foreach(failed_mounts) do |failed_mount|
        delim = summary.fetch("warning", "").empty? ? "" : "<BR>"
        if Builtins.contains(
          @basic_dirs,
          failed_mount.mountpoint
        )
          Ops.set(
            summary,
            "warning",
            Ops.add(
              Ops.add(Ops.get_string(summary, "warning", ""), delim),
              # error message: %1: e.g. "/usr", %2: "/dev/sda2"
              Builtins.sformat(
                _(
                  "Error: Cannot check free space in basic directory %1 (device %2), " \
                    "cannot start installation."
                ),
                failed_mount.mountpoint,
                fs_dev_name(failed_mount)
              )
            )
          )

          # we could not mount a basic directory, this indicates
          # a severe problem in partition setup
          Ops.set(summary, "warning_level", :blocker)
        else
          Ops.set(
            summary,
            "warning",
            Ops.add(
              Ops.add(Ops.get_string(summary, "warning", ""), delim),
              # error message: %1: e.g. "/local", %2: "/dev/sda2"
              Builtins.sformat(
                _(
                  "Warning: Cannot check free space in directory %1 (device %2)."
                ),
                failed_mount.mountpoint,
                fs_dev_name(failed_mount)
              )
            )
          )

          # keep blocker, fatal and error level, they are higher than warning
          if !Builtins.contains(
            [:blocker, :fatal, :error],
            Ops.get_symbol(summary, "warning_level", :ok)
          )
            Ops.set(summary, "warning_level", :warning)
          end
        end
      end

      Builtins.y2milestone("Proposal summary: %1", summary)

      deep_copy(summary)
    end

    # Print the installatino proposal summary
    # @param [Array<Symbol>] flags a list of symbols, see above
    # @param [Boolean] use_cache if true, use previous proposal if possible
    # @return [Hash] a map with proposal summary
    def Summary(flags, use_cache)
      flags = deep_copy(flags)
      if !@init_error.nil?
        return { "warning" => @init_error, "warning_level" => :blocker }
      end
      ret = {}

      if !CheckDiskSize(!use_cache)
        fixed_selection = ProductFeatures.GetFeature("software", "selection_type") == :fixed
        ret = {
          "warning"       => if fixed_selection
                               # summary warning
                               _("Not enough disk space.")
                             else
                               # summary warning
                               _(
                                 "Not enough disk space. Remove some packages " \
                                   "in the single selection."
                               )
                             end,
          "warning_level" => Mode.update ? :error : :blocker
        }
      else
        # check available free space (less than 25% and less than 750MB) (see bnc#178357)
        free_space = SpaceCalculation.CheckDiskFreeSpace(25, 750 * 1024)

        if Ops.greater_than(Builtins.size(free_space), 0)
          warning = ""

          Builtins.foreach(free_space) do |df|
            partition = Ops.get_string(df, "dir", "")
            # add a backslash if it's missing
            if partition == "" || Builtins.substring(partition, 0, 1) != "/"
              partition = Ops.add("/", partition)
            end
            free_pct = Ops.get_integer(df, "free_percent", 0)
            free_kB = Ops.get_integer(df, "free_size", 0)
            w = Builtins.sformat(
              _("Only %1 (%2%%) free space available on partition %3.<BR>"),
              String.FormatSize(Ops.multiply(free_kB, 1024)),
              free_pct,
              partition
            )
            warning = Ops.add(warning, w)
          end

          if warning != ""
            Ops.set(ret, "warning", warning)
            Ops.set(ret, "warning_level", :warning)
          end
        end
      end

      # Check the YaST required packages.
      missing_resolvables = check_missing_resolvables
      if !missing_resolvables.empty?
        texts = missing_resolvables.map { |type, list| format_missing_resolvables(type, list) }
        texts << _("Please manually select the needed items to install.")

        # include the existing warning if defined
        texts.unshift(ret["warning"]) if ret["warning"]

        ret["warning"] = texts.join("<br>")
        ret["warning_level"] = :blocker
      end

      # add failed mounts
      ret = AddFailedMounts(ret)

      # FATE #304488
      if Mode.update
        ret_ref = arg_ref(ret)
        CheckOldAddOns(ret_ref)
        ret = ret_ref.value
      end

      Ops.set(ret, "raw_proposal", SummaryOutput(flags))
      Ops.set(ret, "help", SummaryHelp(flags))
      deep_copy(ret)
    end

    # group products according to the current state
    # @param [Array<Hash>] products list of products (returned by Pkg.ResolvableProperties call)
    # @return [Hash<Symbol,Object>] grouped products
    #   the keys are :new, :removed, :kept, :updated
    #   For each key the value is a list of products, except for :updated
    #   key which contains a Hash with old_product => new_product mapping
    def group_products_by_status(products)
      to_install = products_to_install(products)
      to_remove = products_to_remove(products)
      to_update = products_to_update(to_install, to_remove)

      # remove the updated products from selected and removed lists
      to_remove -= to_update.keys
      to_install -= to_update.values

      ret = {
        new:     to_install,
        removed: to_remove,
        kept:    kept_products(products),
        updated: to_update
      }

      log.info "Product update status: #{ret}"

      ret
    end

    # create a product update summary (in rich text format)
    # usable in update proposal
    # @see #product_update_warning how to set and display possible issues
    # @param [Array<Hash>] products list of products (returned by Pkg.ResolvableProperties call)
    # @return [Array<String>] list of rich text descriptions
    def product_update_summary(products)
      status = group_products_by_status(products)

      # newly installed products
      ret = status[:new].map do |product|
        log.info "New product will be installed: #{product}"
        _("New product <b>%s</b> will be installed") % h(product_label(product))
      end

      ret += status[:updated].map do |removed, installed|
        old_product = product_label(removed)
        new_product = product_label(installed)
        log.info "Detected product update: #{old_product} -> #{new_product}"

        if old_product == new_product
          # product update: %s is a product name
          _("Product <b>%s</b> will be updated") % h(old_product)
        else
          # product update: %{old_product} is an old product, %{new_product} is the new one
          _("Product <b>%{old_product}</b> will be updated to <b>%{new_product}</b>") % {
            old_product: h(old_product), new_product: h(new_product)
          }
        end
      end

      ret += status[:kept].map do |product|
        log.info "Unchanged product: #{product}"
        _("Product <b>%s</b> will stay installed") % h(product_label(product))
      end

      ret += status[:removed].map do |product|
        transact_by = product["transact_by"]
        log.warn "Product will be removed (by #{transact_by}): #{product}"

        # Removing another product might be an issue
        # (just warn if removed by user or by YaST)
        msg = if [:user, :app_high].include?(transact_by)
          _("<b>Warning:</b> Product <b>%s</b> will be removed.") % h(product_label(product))
        else
          _("<b>Error:</b> Product <b>%s</b> will be automatically removed.") %
            h(product_label(product))
        end

        HTML.Colorize(msg, "red")
      end

      log.info "Product update summary: #{ret}"
      ret
    end

    # create a warning for product update summary (in rich text format) if
    # there is an update problem
    # @see #product_update_summary how to get the summary text
    # @param [Array<Hash>] products list of products (returned by Pkg.ResolvableProperties call)
    # @return [Hash] hash with warning attributes or empty if there is no problem
    def product_update_warning(products)
      status = group_products_by_status(products)

      return {} if status[:removed].all? { |product| product["transact_by"] != :solver }

      # Automatic product removal MUST be confirmed by user, otherwise update
      # cannot be started.
      {
        "warning_level" => :blocker,
        # TRANSLATORS: update proposal warning, do NOT translate "-release",
        # it is part of a package name (like "sles-release")
        "warning"       => _(
          "<ul><li><b>Some products are marked for automatic removal.</b></li>\n" \
            "<ul><li>Contact the vendor of the removed add-on to provide you with a new\n" \
            "installation media</li><li>Or select the appropriate online extension or module\n" \
            "in the registration step</li><li>Or to continue with product upgrade go to the\n" \
            "software selection and mark the product (the -release package) for removal.\n" \
            "</li></ul></li></ul>"
        )
      }
    end

    # return a printable name of product resolvable
    # @param [Hash] product the product (returned by Pkg.ResolvableProperties call)
    # @return [String] product name
    def product_label(product)
      display_name = product["display_name"]
      return display_name if display_name && !display_name.empty?

      short_name = product["short_name"]
      return short_name if short_name && !short_name.empty?

      product["name"]
    end

    # proposal control functions

    def ForceFullRepropose
      @full_repropose = true

      nil
    end

    # Reset package selection, but keep the selected objects of the specified type
    # @param [Array<Symbol>] keep a list of symbols specifying type of objects to be kept selected
    def Reset(keep)
      restore = []

      # collect the currently selected resolvables
      keep.each do |type|
        resolvables = Pkg.ResolvableProperties("", type, "")

        resolvables.each do |resolvable|
          # only selected items but ignore the selections done by solver,
          # during restoration they would be changed to be selected by YaST and they
          # will be selected by solver again anyway
          next if resolvable["status"] != :selected || resolvable["transact_by"] == :solver

          restore << [resolvable["name"], type]
        end
      end

      # This keeps the user-made changes (BNC#446406)
      Pkg.PkgApplReset

      restore.each { |name, type| Pkg.ResolvableInstall(name, type) }

      @system_packages_selected = false

      nil
    end

    # Initialize add-on products provided by the repository
    def InitializeAddOnProducts
      PackageCallbacks.SetMediaCallbacks

      # Set the base workflow before adding more AddOnProducts using the add_on_products file
      # Do not force "base workflow" if there is already any base one stored
      # bugzilla #269625
      WorkflowManager.SetBaseWorkflow(false)

      if @add_on_products_list != []
        Builtins.y2milestone(
          "Found list of add-on products to preselect: %1",
          @add_on_products_list
        )
        AddOnProduct.AddPreselectedAddOnProducts(@add_on_products_list)
        @add_on_products_list = [] # do not select them any more
      end

      nil
    end

    # When the NTP configuration has been modified, it checks whether the
    # service package is selected to be installed or not.
    # @return [String] empty string or error message if the package is missing
    def check_ntp_installation_packages
      Yast.import "NtpClient"

      return "" unless NtpClient.modified
      return "" if pkg_will_be_installed(NtpClientClass::REQUIRED_PACKAGE)

      # TRANSLATORS: warning message
      _("The NTP configuration (chrony) has been modified, " \
        "but the package is not selected to be installed.")
    end

    # Checking if all needed packages for remote installation
    # will be installed on the target system.
    # @return [String] empty string or error message if there are missing packages
    def check_remote_installation_packages
      @missing_remote_kind = []
      @missing_remote_packages = []

      if Linuxrc.braille
        missing = braille_packages.reject { |tag| pkg_will_be_installed(tag) }
        unless missing.empty?
          @missing_remote_packages << missing
          @missing_remote_kind << "BRAILLE"
        end
      end
      if Linuxrc.usessh
        missing = ssh_packages.reject { |tag| pkg_will_be_installed(tag) }
        unless missing.empty?
          @missing_remote_packages << missing
          @missing_remote_kind << "SSH"
        end
      end
      if Linuxrc.vnc
        missing = vnc_packages.reject { |tag| pkg_will_be_installed(tag) }
        unless missing.empty?
          @missing_remote_packages << missing
          @missing_remote_kind << "VNC"
        end
      end
      if Linuxrc.display_ip
        missing = remote_x11_packages.reject { |tag| pkg_will_be_installed(tag) }
        unless missing.empty?
          @missing_remote_packages << missing
          @missing_remote_kind << "DISPLAY_IP"
        end
      end

      missing_remote_packages.flatten!
      unless missing_remote_packages.empty?
        error_string = format(_("Cannot support %s remote access in the installed system" \
          " due to missing packages \n%s. \nIt will be disabled."),
          @missing_remote_kind.join(", "), @missing_remote_packages.join(", "))
        if Mode.auto
          error_string << " \n"
          error_string << _("But the AutoYaST installation will be still finished automatically " \
            "without any user interaction.")
        end
        log.warn("Cannot support #{@missing_remote_kind} remote access in the " \
          "installed system due missing packages #{@missing_remote_packages}")
        return error_string
      end
      ""
    end

    #-----------------------------------------------------------------------
    # LOCALE FUNCTIONS
    #-----------------------------------------------------------------------

    # Add a package to list to be selected before proposal
    # Can be called only before the installation proposal, later doesn't
    # have any effect.
    # OBSOLETE! Please, use PackagesProposal::AddResolvables() instead.
    #
    # @param [String] package string package to be selected
    def addAdditionalPackage(package)
      Builtins.y2warning(
        "OBSOLETE! Please, use PackagesProposal::AddResolvables() instead"
      )
      @additional_packages = Builtins.add(@additional_packages, package)

      nil
    end

    # Compute architecture packages
    # @return [Array](string)
    def architecturePackages
      packages = []

      # remove unneeded / add needed packages for ppc
      if Arch.ppc
        packages = Builtins.add(packages, "mouseemu") if Arch.board_mac

        if Arch.board_mac_new || Arch.board_mac_old
          pmac_board = ""
          pmac_compatible = Convert.convert(
            SCR.Read(path(".probe.cpu")),
            from: "any",
            to:   "list <map>"
          )
          Builtins.foreach(pmac_compatible) do |pmac_compatible_tmp|
            pmac_board = Ops.get_string(pmac_compatible_tmp, "system", "")
          end

          # install pbbuttonsd on PowerBooks and iMacs
          if Builtins.issubstring(pmac_board, "PowerBook") ||
              Builtins.issubstring(pmac_board, "PowerMac2,1") ||
              Builtins.issubstring(pmac_board, "PowerMac2,2") ||
              Builtins.issubstring(pmac_board, "PowerMac4,1") ||
              Builtins.issubstring(pmac_board, "iMac,1")
            packages = Builtins.add(packages, "pbbuttonsd")
            packages = Builtins.add(packages, "powerprefs")
          end
        end

        if Arch.ppc64 && (Arch.board_chrp || Arch.board_iseries)
          packages = Builtins.add(packages, "iprutils")
        end
      end

      if Arch.ia64
        # install fpswa if the firmware has an older version
        if SCR.Execute(path(".target.bash"), "/sbin/fpswa_check_version").nonzero?
          packages = Builtins.add(packages, "fpswa")
        end
      end

      if Arch.is_xenU
        # xen-tools-domU are required for registration of a Xen VM (domU)
        packages = Builtins.add(packages, "xen-tools-domU")
      end

      # add numactl on x86_64 with SMP
      if Arch.has_smp && Arch.x86_64
        packages = Builtins.add(packages, "numactl")
        packages = Builtins.add(packages, "irqbalance")
      end

      deep_copy(packages)
    end

    # Compute special packages
    # @return [Array](string)
    def modePackages
      packages = []
      packages << braille_packages if Linuxrc.braille
      packages << ssh_packages if Linuxrc.usessh
      packages << vnc_packages if Linuxrc.vnc
      packages << remote_x11_packages if Linuxrc.display_ip
      packages.flatten!
      log.info("Installation mode packages: #{packages}")
      packages
    end

    # CHeck whether this is a Dell system
    def DellSystem
      command = "/usr/sbin/hwinfo --bios | grep -q '^[[:space:]]*Vendor:.*Dell Inc\\.'"
      Builtins.y2milestone("Executing: %1", command)

      ret = SCR.Execute(path(".target.bash"), command).zero?
      Builtins.y2milestone("Detected a Dell system") if ret

      ret
    end

    def kernelCmdLinePackages
      ret = []

      add_biosdevname = false
      options = SCR.Read(path(".proc.cmdline"))
      option = options.grep(/^biosdevname=/i).first if options
      value = (option[/^biosdevname=(\d+)/i, 1] if option)

      if value == "1"
        Builtins.y2milestone("Biosdevname explicitly enabled")
        add_biosdevname = true
      elsif value == "0"
        Builtins.y2milestone("Biosdevname explicitly disabled")
        add_biosdevname = false
      else
        Builtins.y2milestone("Missing biosdevname option, autodetecting...")
        add_biosdevname = true if DellSystem()
      end
      ret << "biosdevname" if add_biosdevname

      Builtins.y2milestone("Packages added by kernel command line: %1", ret)

      deep_copy(ret)
    end

    # Compute board (vendor) dependant packages
    # @return [Array](string)
    def boardPackages
      probe = Convert.convert(
        SCR.Read(path(".probe.system")),
        from: "any",
        to:   "list <map <string, any>>"
      )
      packages = Ops.get_list(probe, [0, "requires"], [])
      Builtins.y2milestone("Board/Vendor specific packages: %1", packages)

      packages
    end

    # Compute packages required to access the repositories
    # @return [Array](string) list of the required packages
    def sourceAccessPackages
      packages = []
      schemes = repo_schemes

      # /sbin/mount.cifs is required to mount a SMB/CIFS share
      packages << "cifs-mount" if schemes.include?("smb") || schemes.include?("cifs")

      # portmap is required to mount an NFS export
      packages << "nfs-client" if schemes.include?("nfs")

      log.info("Packages for accessing the repositories: #{packages.inspect}")
      packages
    end

    # Return the URL schemes for the currently defined repositories (only enabled
    # repositories are evaluated). For ISO repositories the base URL schema
    # is returned (i.e. the location of the ISO), invalid URLs are ignored.
    # @return [Array<String>] the list of the URL schemes, empty if
    #   no repository is defined
    def repo_schemes
      schemes = []

      # all enabled repositories
      Pkg.SourceGetCurrent(true).each do |repo|
        url = Pkg.SourceURL(repo)

        begin
          uri = URI(url)

          # handle the ISO scheme specifically
          # Note: scheme is converted to lowercase by Ruby
          if uri.scheme == "iso" && uri.query
            # parse the query string into a hash, extract the base URL from the query
            # CGI.parse output is a hash: key => [val1, val2, ...]
            params = CGI.parse(uri.query)
            # expect only one "url" parameter
            scheme = URI(params["url"].first).scheme if params["url"] && !params["url"].empty?
          else
            scheme = uri.scheme
          end

          schemes << scheme if scheme && !schemes.include?(scheme)
        # normally should not happen, the URLs from libzypp should be always valid
        rescue URI::InvalidURIError => e
          log.error(e.message)
        end
      end

      schemes
    end

    # Additional kernel packages from control file
    # @return [Array<String>] Additional Kernel packages
    def ComputeAdditionalKernelPackages
      final_kernel = Kernel.GetFinalKernel
      pos = Builtins.findfirstof(final_kernel, "-")
      extension = Builtins.substring(
        final_kernel,
        pos,
        Builtins.size(final_kernel)
      )
      akp = []
      if extension != ""
        kernel_packages = Convert.convert(
          ProductFeatures.GetFeature("software", "kernel_packages"),
          from: "any",
          to:   "list <string>"
        )
        if Ops.greater_than(Builtins.size(kernel_packages), 0) &&
            !kernel_packages.nil?
          akp = Builtins.maplist(kernel_packages) do |p|
            Ops.add(Ops.add(p, "-"), extension)
          end
        end
      end
      deep_copy(akp)
    end

    #-----------------------------------------------------------------------
    # GLOBAL FUNCTIONS
    #-----------------------------------------------------------------------

    def ComputeSystemPatternList
      pattern_list = extra_system_patterns

      # FATE #302116, BNC #431580
      # select both mandatory and optional patterns
      proposed_patterns = (resolvable_mandatory_patterns | resolvable_optional_patterns)

      log.info("PackagesProposal patterns: #{proposed_patterns}")
      pattern_list.concat(proposed_patterns)

      log.info("System patterns: #{pattern_list}")
      pattern_list
    end

    # Build and return list of packages which depends on the
    # the current target system and the preselected packages
    # (architecture, X11....)
    # @return [Array<String>] packages
    def ComputeSystemPackageList
      install_list = architecturePackages
      install_list.concat(modePackages)

      if !@additional_packages.empty?
        log.warn("Additional packages are still in use, please, " \
          "change it to use PackagesProposal API")
        log.info("Additional packages: #{@additional_packages}")
        install_list.concat(@additional_packages)
      end

      # bnc #431580
      # New API for packages selected by other modules
      # use both mandatory and optional packages
      packages_proposal_all_packages = PackagesProposal.GetAllResolvables(:package, optional: true)
      packages_proposal_all_packages.concat(PackagesProposal.GetAllResolvables(:package))

      log.info("PackagesProposal packages: #{packages_proposal_all_packages}")
      install_list.concat(packages_proposal_all_packages)

      # Kernel is added in autoinstPackages () if autoinst is enabled
      if !Mode.update || !Mode.autoinst
        kernel_pkgs = Kernel.ComputePackages
        install_list.concat(kernel_pkgs)

        kernel_pkgs_additional = ComputeAdditionalKernelPackages()
        install_list.concat(kernel_pkgs_additional)
      end

      # TODO: um, VNC packages are also selected in modePackages(),... ???
      if Pkg.IsSelected("xorg-x11-Xvnc") && Linuxrc.vnc && !Linuxrc.serial_console
        log.info("Selecting graphic packages: #{GRAPHIC_PACKAGES}")
        install_list.concat(GRAPHIC_PACKAGES)
      end

      install_list.concat(kernelCmdLinePackages)

      install_list.concat(boardPackages)

      # add packages required to access the repository in the 2nd stage and at run-time
      install_list.concat(sourceAccessPackages)

      # and the most flexible enhancement for other products
      # NOTE: not really flexible, because it requires the client
      # in the instsys, instead use <kernel-packages> in the control file.
      pkg_mogrify_client = ProductFeatures.GetFeature("software", "packages_transmogrify")
      if !pkg_mogrify_client.empty?
        tmp_list = Convert.convert(
          WFM.CallFunction(pkg_mogrify_client, [install_list]),
          from: "any",
          to:   "list <string>"
        )

        # Make sure we did not get a nil from calling the client, i.e.
        # if the client does not exist at all..
        install_list = deep_copy(tmp_list) if !tmp_list.nil?
      end

      packages = ProductFeatures.GetFeature("software", "packages")
      if !packages.empty?
        log.info("Adding packages from control file: #{packages}")
        install_list.concat(packages)
      end

      install_list.uniq!
      log.info("Computed packages for the system: #{install_list}")
      install_list
    end

    # Import GPG keys found in the inst-sys
    def ImportGPGKeys
      out = Convert.to_map(
        SCR.Execute(path(".target.bash_output"), "/bin/ls -d /*.gpg")
      )
      Builtins.foreach(
        Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n")
      ) { |file| Pkg.ImportGPGKey(file, true) if file != "" }

      nil
    end

    def UpdateSourceURL(url)
      ret = ""
      while ret == ""
        msg = Ops.add(
          Ops.add(
            Ops.add(
              Ops.add(
                Ops.add(
                  Ops.add(
                    Builtins.sformat(
                      _("Unable to create repository\nfrom URL '%1'."),
                      URL.HidePassword(url)
                    ),
                    "\n\n"
                  ),
                  _("Details:")
                ),
                "\n"
              ),
              Pkg.LastError
            ),
            "\n\n"
          ),
          _("Try again?")
        )

        if Popup.YesNo(msg)
          ret = SourceDialogs.EditPopup(url)
        else
          # error in proposal, %1 is URL
          @init_error = Builtins.sformat(
            _("No repository found at '%1'."),
            URL.HidePassword(url)
          )
          return ""
        end
      end
      ret
    end

    def LocaleVersions(lang)
      ret = [lang]
      components = Builtins.splitstring(lang, ".")
      if Ops.get(components, 0, "") != lang && Ops.get(components, 0, "") != ""
        lang = Ops.get(components, 0, "")
        ret = Builtins.add(ret, lang)
      end
      components = Builtins.splitstring(lang, "_")
      if Ops.get(components, 0, "") != lang && Ops.get(components, 0, "") != ""
        lang = Ops.get(components, 0, "")
        ret = Builtins.add(ret, lang)
      end
      deep_copy(ret)
    end

    # Returns ID of the base product repository.
    #
    # @return [Fixnum] base source ID
    def GetBaseSourceID
      @base_source_id
    end

    def FindAndCopySlideDir(our_slidedir, source, search_for_dir, lang_long,
      lang_short, fallback_lang)
      # directory used as a source of texts
      providedir = nil

      # one of the localizations (long or short)
      used_loc_dir = ""

      Builtins.foreach([lang_long, lang_short, fallback_lang]) do |try_this_lang|
        next if try_this_lang.nil? || try_this_lang == ""
        test_dir = Builtins.sformat("%1/txt/%2", search_for_dir, try_this_lang)
        Builtins.y2milestone("Checking '%1'", test_dir)
        providedir = Pkg.SourceProvideSignedDirectory(
          source,
          1,
          test_dir,
          true,
          true
        )
        if !providedir.nil?
          Builtins.y2milestone("%1 lang found", try_this_lang)
          used_loc_dir = try_this_lang
          # don't check for other langs
          raise Break
        end
      end

      # no wanted localization found
      if providedir.nil?
        Builtins.y2milestone(
          "Neither %1 nor %2 localization found",
          lang_long,
          lang_short
        )
        return false
      end

      # where texts are stored later
      loc_slidedir = Builtins.sformat("%1/txt/%2/", our_slidedir, used_loc_dir)
      WFM.Execute(
        path(".local.bash"),
        Builtins.sformat("mkdir -p '%1'", String.Quote(loc_slidedir))
      )

      # copy all files to our own cache
      copy_command = Builtins.sformat(
        "cp -r '%1/%2/txt/%3'/* '%4'",
        String.Quote(providedir),
        String.Quote(search_for_dir),
        String.Quote(used_loc_dir),
        String.Quote(loc_slidedir)
      )

      Builtins.y2milestone("Copying: %1", copy_command)
      WFM.Execute(path(".local.bash"), copy_command)

      # where images are stored
      imagesdir = Builtins.sformat("%1/pic", search_for_dir)

      imagesdir = Pkg.SourceProvideSignedDirectory(
        source,
        1,
        imagesdir,
        true,
        true
      )

      if !imagesdir.nil?
        # where images should be cached
        our_imagesdir = Builtins.sformat("%1/pic/", our_slidedir)
        WFM.Execute(
          path(".local.bash"),
          Builtins.sformat("mkdir -p '%1'", String.Quote(our_imagesdir))
        )

        copy_command = Builtins.sformat(
          "cp -r '%1/%2/pic'/* '%3'",
          String.Quote(imagesdir),
          String.Quote(search_for_dir),
          String.Quote(our_imagesdir)
        )

        Builtins.y2milestone("Copying: %1", copy_command)
        WFM.Execute(path(".local.bash"), copy_command)
      else
        Builtins.y2error("No such dir: %1", imagesdir)
      end

      true
    end

    def FindAndCopySlideDirWithoutCallbacks(our_slidedir, source, search_for_dir,
      lang_long, lang_short, fallback_lang)
      # disable callbacks
      PackageCallbacks.RegisterEmptyProgressCallbacks

      ret = FindAndCopySlideDir(
        our_slidedir,
        source,
        search_for_dir,
        lang_long,
        lang_short,
        fallback_lang
      )

      # restore callbacks
      PackageCallbacks.RestorePreviousProgressCallbacks

      ret
    end

    def SlideShowSetUp(wanted_language)
      # bnc #432668
      # Do not call init
      if Mode.live_installation
        Builtins.y2milestone("live_installation, not calling Init")
        # bnc #427935
        # Initialize the base_source_id first
      else
        Init(true)
      end

      # Do not reinitialize the SlideShow if not needed
      # bnc #444612
      if Ops.greater_than(Builtins.size(SlideShow.GetSetup), 0)
        Builtins.y2milestone("SlideShow has been already set, skipping...")
        return
      end

      source = @base_source_id

      lang_long = ""
      lang_short = ""

      # de_DE.UTF-8 -> de_DE
      # es_ES       -> es_ES
      # blah        -> ""
      if !wanted_language.nil? && wanted_language != ""
        Builtins.y2milestone("Selected language: %1", wanted_language)

        if Builtins.regexpmatch(wanted_language, "^.+_.+$")
          lang_long = wanted_language
        elsif !wanted_language.nil? && wanted_language != "" &&
            Builtins.regexpmatch(wanted_language, "^.+_.+..*$")
          lang_long = Builtins.regexpsub(
            wanted_language,
            "^(.+)_(.+)..*",
            "\\1_\\2"
          )
        end

        if !lang_long.nil? && lang_long != "" &&
            Builtins.regexpmatch(lang_long, ".*_.*")
          lang_short = Builtins.regexpsub(lang_long, "(.*)_.*", "\\1")
        elsif !wanted_language.nil? && wanted_language != ""
          lang_short = wanted_language
        end

        Builtins.y2milestone(
          "Slide Show lang_long: %1, lang_short: %2",
          lang_long,
          lang_short
        )
      else
        Builtins.y2error("Wrong language definition: %1", wanted_language)
      end

      # setup slidedir
      productmap = Pkg.SourceProductData(source)
      datadir = Ops.get_string(productmap, "datadir", "suse")

      # target slideshow directory
      our_slidedir = Builtins.sformat(
        "%1/slidedir/",
        Convert.to_string(WFM.Read(path(".local.tmpdir"), ""))
      )
      WFM.Execute(
        path(".local.bash"),
        Builtins.sformat("mkdir -p '%1'", our_slidedir)
      )

      # media directory
      # bugzilla #305097
      #
      # bugzilla #326327
      # try to download only slides that are needed (by selected language)
      # no images are cached
      search_for_dir = Builtins.sformat("/%1/setup/slide/", datadir)
      FindAndCopySlideDirWithoutCallbacks(
        our_slidedir,
        source,
        search_for_dir,
        lang_long,
        lang_short,
        Slides.fallback_lang
      )
      # Language has to be set otherwise it uses a fallback language
      # BNC #444612 comment #2
      SlideShow.SetLanguage(Language.language)

      Builtins.y2milestone(
        "Setting up the slide directory local copy: %1",
        our_slidedir
      )
      Slides.SetSlideDir(our_slidedir)

      if load_release_notes(source)
        # TRANSLATORS: beginning of the rich text with the release notes
        SlideShow.relnotes = Ops.add(
          _(
            "<p><b>The release notes for the initial release are part of the installation\n" \
              "media. If an Internet connection is available during configuration, you can\n" \
              "download updated release notes from the SUSE Linux Web server.</b></p>\n"
          ),
          @media_text
        )
      end

      nil
    end

    def IntegrateServicePack(show_popup, base_url)
      # Check for Service Pack
      if Ops.greater_than(
        Convert.to_integer(
          WFM.Read(path(".local.size"), @servicepack_metadata)
        ),
        0
      )
        Builtins.y2milestone("Service Pack data available")
        popup_open = false
        if show_popup
          UI.OpenDialog(
            Opt(:decorated),
            # popup - information label
            Label(_("Integrating booted media..."))
          )
          popup_open = true
        end
        spdir = Ops.add(@metadir, "/Service-Pack/CD1")
        WFM.Execute(path(".local.mkdir"), spdir)
        Builtins.y2milestone("Filling %1", spdir)
        WFM.Execute(
          path(".local.bash"),
          Ops.add(
            Ops.add(Ops.add("tar -zxvf ", @servicepack_metadata), " -C "),
            spdir
          )
        )
        sp_url = Ops.add("dir:", spdir)
        # close the popup in order to be able to ask about the license
        UI.CloseDialog if popup_open
        sp_source = Pkg.SourceCreate(sp_url, "")
        if sp_source == -1
          Report.Error(_("Failed to integrate the service pack repository."))
          return nil
        end
        if !AddOnProduct.AcceptedLicenseAndInfoFile(sp_source)
          Builtins.y2milestone("service pack license rejected")
          Pkg.SourceDelete(sp_source)
          return nil
        end
        if FileUtils.Exists(Ops.add(spdir, "/installation.xml"))
          WorkflowManager.AddWorkflow(:addon, sp_source, "")
          WorkflowManager.MergeWorkflows
        end
        if FileUtils.Exists(Ops.add(spdir, "/y2update.tgz"))
          AddOnProduct.UpdateInstSys(Ops.add(spdir, "/y2update.tgz"))
        end
        @theSources = Builtins.add(@theSources, sp_source)
        Builtins.y2milestone(
          "Service pack repository: %1, changing to URL: %2",
          sp_source,
          base_url
        )
        Pkg.SourceChangeUrl(sp_source, base_url)
      end

      nil
    end

    def Initialize_BaseInit(show_popup, base_url, log_url)
      popup_open = false
      if show_popup
        UI.OpenDialog(
          Opt(:decorated),
          # popup - information label
          Label(_("Initializing repositories..."))
        )
        popup_open = true
      end

      PackageCallbacks.InitPackageCallbacks

      # Initialize package manager
      @init_error = nil
      Builtins.y2milestone("Packages::Initialize_BaseInit()")

      base_url.value = if Mode.test
        # Fake values for testing purposes
        "dir:///dist/next-i386"
      else
        InstURL.installInf2Url("")
      end

      # '\' is not reserved nor unreserved according to rfc https://tools.ietf.org/html/rfc3986#section-2.1
      # but ruby URI does not handle it. So to make life easier encode it (bsc#1032506)
      base_url.value.gsub!("\\", "%5C")

      # hide password from URL if present
      log_url.value = URL.HidePassword(base_url.value)
      Builtins.y2milestone("Initialize Package Manager: %1", log_url.value)

      # Set languages for packagemanager. Always set the UI language. Set
      # language for additional packages only in Stage::initial ().
      Pkg.SetTextLocale(Language.language)

      UI.CloseDialog if popup_open

      true
    end

    # Adjusts repository name according to a first product found on the media.
    #
    # @param [Fixnum] src_id repository ID
    # @return [Boolean] if successful
    #
    # @see BNC #481828
    def AdjustSourcePropertiesAccordingToProduct(src_id)
      # This function is used from several places (also YaST Add-On)

      if src_id.nil? || Ops.less_than(src_id, 0)
        Builtins.y2error("Wrong source ID: %1", src_id)
        return nil
      end

      Builtins.y2milestone("Trying to get repository name from products")
      all_products = Pkg.ResolvableProperties("", :product, "")
      new_name = nil
      Builtins.foreach(all_products) do |one_product|
        # source ID matches
        if Ops.get_integer(one_product, "source", -1) == src_id
          name = one_product["name"] || ""
          if name != ""
            new_name = name
            Builtins.y2milestone("Product name found: %1", new_name)
            raise Break
          end
        end
      end

      # Finally, some (new) name has been adjusted
      if !new_name.nil? && new_name != ""
        Builtins.y2milestone("Adjusting repository name")
        sources_got = Pkg.SourceEditGet
        sources_set = []
        Builtins.foreach(sources_got) do |one_source|
          if Ops.get_integer(one_source, "SrcId", -1) == src_id
            Ops.set(one_source, "name", new_name)
          end
          sources_set = Builtins.add(sources_set, one_source)
        end

        return Pkg.SourceEditSet(sources_set)
        # Bad luck, nothing useful found
      else
        Builtins.y2warning("No name found")

        return false
      end
    end

    def FindAndRememberAddOnProductsFiles(initial_repository)
      tmp_add_on_products = nil
      @add_on_products_list = []

      filename = nil
      tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))

      # #303675: Support several AddOns on standard SLE medium
      # at first, try to find XML configuration
      # then as a fallback/backward compatibility the old plain configuration
      Builtins.foreach(
        [["/add_on_products.xml", "xml"], ["/add_on_products", "plain"]]
      ) do |one_aop|
        file = Ops.get(one_aop, 0, "")
        type = Ops.get(one_aop, 1, "")
        # BNC #496404: These files should not be checked for signatures
        tmp_add_on_products = Pkg.SourceProvideOptionalFile(
          initial_repository,
          1,
          file
        )
        if !tmp_add_on_products.nil?
          filename = Builtins.sformat(
            "%1/add_on_products_defined_by_repository",
            tmpdir
          )
          @add_on_products_list = Builtins.add(
            @add_on_products_list,
            "file" => filename, "type" => type
          )
          WFM.Execute(
            path(".local.bash"),
            Builtins.sformat(
              "cp '%1' '%2'",
              String.Quote(tmp_add_on_products),
              String.Quote(filename)
            )
          )
          Builtins.y2milestone(
            "Found add_on_products (repository) %1 type %2",
            tmp_add_on_products,
            type
          )
          raise Break
        end
      end

      # FATE #312263 Files in the root of inst-sys
      Builtins.foreach(
        [["/add_on_products.xml", "xml"], ["/add_on_products", "plain"]]
      ) do |one_aop|
        file = Ops.get(one_aop, 0, "")
        type = Ops.get(one_aop, 1, "")
        # In inst-sys, files are already stored locally
        if FileUtils.Exists(file)
          filename = Builtins.sformat(
            "%1/add_on_products_defined_by_inst_sys",
            tmpdir
          )
          @add_on_products_list = Builtins.add(
            @add_on_products_list,
            "file" => filename, "type" => type
          )
          WFM.Execute(
            path(".local.bash"),
            Builtins.sformat(
              "cp '%1' '%2'",
              String.Quote(file),
              String.Quote(filename)
            )
          )
          Builtins.y2milestone(
            "Found add_on_products (inst-sys) %1 type %2",
            file,
            type
          )
          raise Break
        end
      end

      Ops.greater_than(Builtins.size(@add_on_products_list), 0)
    end

    def Initialize_StageInitial(show_popup, base_url, log_url)
      initial_repository = nil
      ImportGPGKeys()

      # Create the baseproduct link if it does not exist yet,
      # openSUSE includes the file in the inst-sys while SLES/SLED do not.
      create_baseproduct_symlink unless File.exist?(BASE_PRODUCT_FILE)

      # prefer CD/DVD media to download during installation/update
      # (BNC#780617,865819)
      Builtins.y2milestone("Prefer CD/DVD media to download")
      Pkg.SetZConfig("download_media_prefer_download" => false)

      while initial_repository.nil?
        initial_repository = Pkg.SourceCreateBase(base_url, "/")
        next unless initial_repository == -1 || initial_repository.nil?
        Builtins.y2error("No repository in '%1'", log_url)
        base_url = UpdateSourceURL(base_url)
        if base_url != ""
          initial_repository = nil
        else
          @init_in_progress = false
          return
        end
      end

      # BNC #481828: Using LABEL from product
      AdjustSourcePropertiesAccordingToProduct(@base_source_id)

      @base_source_id = initial_repository
      Builtins.y2milestone("Base source ID: %1", @base_source_id)

      @theSources = [initial_repository]
      sp_source = IntegrateServicePack(show_popup, base_url)
      @theSources = Builtins.add(@theSources, sp_source) if !sp_source.nil?

      if ProductFeatures.GetFeature("software", "selection_type") == :fixed
        # selections not supported anymore, install a pattern
        Pkg.ResolvableInstall(
          ProductFeatures.GetStringFeature("software", "base_selection"),
          :pattern
        )
      end

      FindAndRememberAddOnProductsFiles(initial_repository)

      nil
    end

    def Initialize_StageNonInitial(_show_popup, base_url, _log_url)
      if @theSources.nil? || Ops.less_or_equal(Builtins.size(@theSources), 0)
        Builtins.y2error("Pkg::SourceStartCache failed")
        @theSources = []
      elsif Stage.cont && # rewrite URL if cd/dvd since ide-scsi might have changed it
          (Builtins.substring(base_url, 0, 2) == "cd" ||
            Builtins.substring(base_url, 0, 3) == "dvd")
        Builtins.foreach(@theSources) do |source|
          data = Pkg.SourceGeneralData(source) # get repository data
          url = Ops.get_string(data, "url", "")
          if Builtins.substring(url, 0, 2) == "cd" || # repository comes from cd/dvd
              Builtins.substring(url, 0, 3) == "dvd"
            new_url = InstURL.RewriteCDUrl(url)
            Builtins.y2milestone(
              "rewrite url: '%1'->'%2'",
              url,
              URL.HidePassword(new_url)
            )
            Pkg.SourceChangeUrl(source, new_url)
          end
        end
      end

      nil
    end

    # Initialize the repositories
    # @param [Boolean] show_popup boolean true to display information about initialization
    def Initialize(show_popup)
      if @init_called || @init_in_progress
        Builtins.y2milestone("Packages::Initialize() already called")
        return
      end

      @init_in_progress = true

      # usual mountpoint for the medium
      base_url = ""
      # url with hidden password for logging purpose
      log_url = ""

      base_url_ref = arg_ref(base_url)
      log_url_ref = arg_ref(log_url)
      Initialize_BaseInit(show_popup, base_url_ref, log_url_ref)
      base_url = base_url_ref.value
      log_url = log_url_ref.value

      if !Stage.initial
        Builtins.y2milestone("Initializing the target...")
        Pkg.TargetInitialize(Installation.destdir)
      end

      @theSources = Stage.initial ? [] : Pkg.SourceStartCache(true) # dummy in 1st stage

      again = true

      while again
        if Stage.initial
          Initialize_StageInitial(show_popup, base_url, log_url) # cont or normal mode
        else
          Initialize_StageNonInitial(show_popup, base_url, log_url)
        end

        Builtins.y2milestone("theSources %1", @theSources)
        Builtins.y2milestone("theSourceDirectories %1", @theSourceDirectories)

        if Ops.greater_or_equal(Builtins.size(@theSources), 0)
          @init_called = true
          again = false
        else
          # an error message
          errortext = Ops.add(
            Ops.add(
              Builtins.sformat(
                _(
                  "Error while initializing package descriptions.\n" \
                    "Check the log file %1 for more details."
                ),
                Ops.add(Directory.logdir, "/y2log")
              ),
              "\n"
            ),
            Pkg.LastError
          )

          # FIXME: somewhere get correct current_label and wanted_label
          PackageCallbacks.MediaChange(
            "NO_ERROR",
            errortext,
            base_url,
            "",
            0,
            "",
            1,
            "",
            false,
            [],
            0
          )
        end
      end

      # FATE #302123
      AddOnProduct.SetBaseProductURL(base_url)

      @init_in_progress = false

      nil
    end

    def Init(_unused)
      Initialize(true)

      nil
    end

    # Selects system-specific and default patterns for installation
    #
    # @param [Boolean] reselect whether to re-select all already selected patterns
    def SelectSystemPatterns(reselect)
      patterns = patterns_to_install.dup
      log.info "Selecting system patterns #{patterns}"

      if !reselect
        patterns.each do |pattern_name|
          prop = Pkg.ResolvableProperties(pattern_name, :pattern, "").first

          if prop.nil?
            report_missing_pattern(pattern_name)
            next
          elsif prop["status"] == :available && prop["transact_by"] == :user
            log.info "Skipping pattern #{pattern_name} deselected by user"
          else
            Pkg.ResolvableInstall(pattern_name, :pattern)
          end
        end
      else
        patterns.select! do |pattern_name|
          descrs = Pkg.ResolvableProperties(pattern_name, :pattern, "")
          report_missing_pattern(pattern_name) if descrs.empty?
          descrs.any? { |descr| descr["status"] == :selected }
        end

        log.info "Selected patterns to be reselected: #{patterns}"

        patterns.each do |pattern_name|
          Pkg.ResolvableRemove(pattern_name, :pattern)
          Pkg.ResolvableInstall(pattern_name, :pattern)
        end
      end

      nil
    end

    # Select system packages
    # @param [Boolean] reselect boolean true to select only those which are alrady selected
    def SelectSystemPackages(reselect)
      system_packages = ComputeSystemPackageList()
      if !reselect
        Builtins.y2milestone("Selecting system packages %1", system_packages)
      else
        Builtins.y2milestone(
          "Re-selecting new versions of system packages %1",
          system_packages
        )
        # first deselect the package (and filter selected ones)
        system_packages = Builtins.filter(system_packages) do |p|
          if Pkg.IsProvided(p) || Pkg.IsSelected(p)
            Pkg.PkgDelete(p)
            next true
          end
          false
        end
        Builtins.y2milestone(
          "System packages to be reselected: %1",
          system_packages
        )
      end
      res = Pkg.DoProvide(system_packages)
      Builtins.foreach(res) do |s, a|
        Builtins.y2warning("Pkg::DoProvide failed for %1: %2", s, a)
      end if Ops.greater_than(
        Builtins.size(res),
        0
      )

      nil
    end

    # Check whether the list of needed packages has been changed since the last
    # package proposal
    #
    # @return [boolean] true if PackagesProposal has been changed
    def PackagesProposalChanged
      new_packages_proposal = PackagesProposal.GetAllResolvablesForAllTypes

      # Force reinit
      changed = new_packages_proposal != @old_packages_proposal
      Builtins.y2milestone("PackagesProposal has been changed: %1", changed)
      Builtins.y2debug("PackagesProposal: %1 -> %2", @old_packages_proposal, new_packages_proposal)

      changed
    end

    # Make a proposal for package selection
    #
    # @param [Boolean] force_reset force reset (fully resets the proposal and creates a new one)
    # @param [Boolean] reinit re-initialize
    #   (soft-reset, doesn't reset resolvable manually selected by user)
    #
    # @return [Hash] for the API proposal
    def Proposal(force_reset, reinit, _simple)
      # Handle the default desktop
      DefaultDesktop.Init

      # set ignoreAlreadyRecommended solver flag
      Pkg.SetSolverFlags("ignoreAlreadyRecommended" => Mode.normal)

      # Force reinit
      if PackagesProposalChanged()
        @old_packages_proposal = PackagesProposal.GetAllResolvablesForAllTypes
        Builtins.y2milestone("Reinit package proposal")
        reinit = true
      end

      # Reinit forced by application, see ForceFullRepropose
      if @full_repropose == true
        Builtins.y2milestone("Fully reproposing")
        force_reset = true
        @full_repropose = false
      end

      if force_reset
        Builtins.y2milestone("Forcing full reset")
        # Full reset has been forced, bnc #446406
        # It resets even the user-selected/removed resolvables
        Pkg.PkgReset
        ResetProposalCache()
        reinit = true
      end

      # if the cache is valid and reset or reinitialization is not required
      # then the cached proposal can be used
      if !@cached_proposal.nil? && force_reset == false && reinit == false
        # selected packages
        selected_packages = Pkg.GetPackages(:selected, false)

        # selected patterns
        selected_patterns = Builtins.filter(
          Pkg.ResolvableProperties("", :pattern, "")
        ) do |p|
          Ops.get_symbol(p, "status", :unknown) == :selected
        end

        # selected products
        selected_products = Builtins.filter(
          Pkg.ResolvableProperties("", :product, "")
        ) do |p|
          Ops.get_symbol(p, "status", :unknown) == :selected
        end

        # selected patches
        selected_patches = Builtins.filter(
          Pkg.ResolvableProperties("", :patch, "")
        ) do |p|
          Ops.get_symbol(p, "status", :unknown) == :selected
        end

        # selected languages
        selected_languages = Convert.convert(
          Builtins.union([Pkg.GetPackageLocale], Pkg.GetAdditionalLocales),
          from: "list",
          to:   "list <string>"
        )

        # if the package selection has not been changed the cache is up to date
        if selected_packages == @cached_proposal_packages &&
            selected_patterns == @cached_proposal_patterns &&
            selected_products == @cached_proposal_products &&
            selected_patches == @cached_proposal_patches &&
            selected_languages == @cached_proposal_languages
          Builtins.y2milestone("using cached software proposal")
          return deep_copy(@cached_proposal)
        # do not show the error message during the first proposal
        # (and the only way to change to software selection manually -> software_proposal/AskUser)
        #
        # 'nil' is the default value
        # See also ResetProposalCache()
        elsif !@cached_proposal_packages.nil? &&
            !@cached_proposal_patterns.nil? &&
            !@cached_proposal_products.nil? &&
            !@cached_proposal_patches.nil? &&
            !@cached_proposal_languages.nil?
          Builtins.y2error(
            "invalid cache: the software selection has been chaged"
          )
          # bnc #436925
          Report.Message(
            _(
              "The software selection has been changed externally.\n" \
                "Software proposal will be called again."
            )
          )
        end
      else
        Builtins.y2milestone(
          "the cached proposal is empty or reset is required"
        )
      end

      if Installation.dirinstall_installing_into_dir && !force_reset && @init_called
        return Summary([:product, :pattern, :size, :desktop], false)
      end

      UI.OpenDialog(
        Opt(:decorated),
        # popup label
        Label(_("Evaluating package selection..."))
      )

      # Lower the priority of the initial DVD installation repository
      # to prefer the packages from the DVD addons, in the other cases the
      # priority is not changed. (bsc#1071742)
      adjust_repo_priority

      Builtins.y2milestone(
        "Packages::Proposal: force_reset %1, reinit %2, lang '%3'",
        force_reset,
        reinit,
        Language.language
      )

      # Soft proposal reset
      if !Mode.autoinst && reinit
        Builtins.y2milestone("Re/Proposing software selection")
        Kernel.ProbeKernel
        Reset([:product])
        reinit = true
      end

      initial_run = reinit || !@init_called
      Initialize(true)

      if !@init_error.nil?
        UI.CloseDialog
        return Summary([], false)
      end

      if initial_run
        # autoyast can configure AdditionalLocales
        # we don't want to overwrite this
        Pkg.SetAdditionalLocales([Language.language]) if !Mode.autoinst
      end

      if ProductFeatures.GetFeature("software", "selection_type") == :auto
        Builtins.y2milestone("Doing pattern-based software selection")

        SelectSystemPackages(@system_packages_selected && !initial_run)
        SelectSystemPatterns(@system_packages_selected && !initial_run)
        @system_packages_selected = true
      elsif ProductFeatures.GetFeature("software", "selection_type") == :fixed
        Builtins.y2milestone("Selection type: fixed")
      else
        Builtins.y2error(
          "unknown value %1 for ProductFeatures::GetFeature (software, selection_type)",
          Convert.to_symbol(
            ProductFeatures.GetFeature("software", "selection_type")
          )
        )
      end

      @solve_errors = Pkg.PkgSolveErrors if !Pkg.PkgSolve(false)

      # Question: is `desktop appropriate for SLE?
      ret = Summary([:product, :pattern, :size, :desktop], false)
      # TODO: simple proposal

      # cache the proposal
      @cached_proposal = deep_copy(ret)

      # remember the status
      @cached_proposal_packages = Pkg.GetPackages(:selected, false)
      @cached_proposal_patterns = Builtins.filter(
        Pkg.ResolvableProperties("", :pattern, "")
      ) do |p|
        Ops.get_symbol(p, "status", :unknown) == :selected
      end
      @cached_proposal_products = Builtins.filter(
        Pkg.ResolvableProperties("", :product, "")
      ) do |p|
        Ops.get_symbol(p, "status", :unknown) == :selected
      end
      @cached_proposal_patches = Builtins.filter(
        Pkg.ResolvableProperties("", :patch, "")
      ) do |p|
        Ops.get_symbol(p, "status", :unknown) == :selected
      end
      @cached_proposal_languages = Convert.convert(
        Builtins.union([Pkg.GetPackageLocale], Pkg.GetAdditionalLocales),
        from: "list",
        to:   "list <string>"
      )

      UI.CloseDialog

      Builtins.y2milestone("Software proposal: %1", ret)

      deep_copy(ret)
    end

    # Make a proposal for package selection during update
    #
    # As a side effect, it stores the current proposal.
    #
    # @see PackagesProposalChanged
    def proposal_for_update
      return unless PackagesProposalChanged()
      @old_packages_proposal = PackagesProposal.GetAllResolvablesForAllTypes
      Packages.SelectSystemPackages(false)
    end

    # Initialize the repositories with popup feedback
    # Use Packages::Initialize (true) instead
    def InitializeCatalogs
      Initialize(true)

      nil
    end

    def InitFailed
      ret = !@init_error.nil?
      Builtins.y2milestone("Package manager initialization failed: %1", ret)
      ret
    end

    # see bug 302398
    def SelectKernelPackages
      provides = Pkg.PkgQueryProvides("kernel")
      # e.g.: [["kernel-bigsmp", `CAND, `NONE], ["kernel-default", `CAND, `CAND],
      # ["kernel-default", `BOTH, `INST]]
      Builtins.y2milestone("provides: %1", provides)

      # these kernels would be installed
      kernels = Builtins.filter(provides) do |l|
        Ops.get_symbol(l, 1, :NONE) == :BOTH ||
          Ops.get_symbol(l, 1, :NONE) == Ops.get_symbol(l, 2, :NONE)
      end

      if Builtins.size(kernels) != 1
        Builtins.y2warning("not exactly one package provides tag kernel")
      end

      selected_kernel = Ops.get_string(kernels, [0, 0], "none")
      recom_kernel = Kernel.ComputePackages
      recommended_kernel = Ops.get(recom_kernel, 0, "")

      Builtins.y2milestone(
        "Selected kernel: %1, recommended kernel: %2",
        selected_kernel,
        recom_kernel
      )

      # when the recommended Kernel is not available (installable)
      if recommended_kernel != "" && !Pkg.IsAvailable(recommended_kernel)
        recommended_kernel = selected_kernel
      end

      # recommended package is different to the selected one
      # select the recommended one
      if recommended_kernel != "" && recommended_kernel != selected_kernel
        # list of kernels to be installed
        kernels_to_be_installed = Convert.convert(
          Builtins.maplist(kernels) { |one_kernel| Ops.get(one_kernel, 0) },
          from: "list",
          to:   "list <string>"
        )
        kernels_to_be_installed = Builtins.filter(kernels_to_be_installed) do |one_kernel|
          !one_kernel.nil? && one_kernel != ""
        end

        # remove all kernels (with some exceptions)
        Builtins.foreach(kernels_to_be_installed) do |one_kernel|
          # XEN can be installed in parallel
          next if one_kernel == "kernel-xen"
          next if one_kernel == "kernel-xenpae"
          # don't remove the recommended one
          next if one_kernel == recommended_kernel
          # remove all packages of that kernel
          packages_to_remove = Kernel.ComputePackagesForBase(one_kernel, false)
          if !packages_to_remove.nil? &&
              Ops.greater_than(Builtins.size(packages_to_remove), 0)
            Builtins.y2milestone(
              "Removing installed packages %1",
              packages_to_remove
            )
            Pkg.DoRemove(packages_to_remove)
          end
        end

        # compute recommended kernel packages
        kernel_packs = Kernel.ComputePackages

        Builtins.y2milestone("Install kernel packages: %1", kernel_packs)

        # installing all recommended packages
        Builtins.foreach(kernel_packs) do |p|
          if Pkg.PkgAvailable(p)
            Builtins.y2milestone("Selecting package %1 for installation", p)
            Pkg.PkgInstall(p)
          else
            Builtins.y2error("Package %1 is not available", p)
          end
        end
      end

      nil
    end

    # Reads software->default_patterns and returns lisf of patterns that should
    # be selected for installation by default
    #
    # @return [Array] list of patterns
    def default_patterns
      product_feature_items("software", "default_patterns")
    end

    # Reads software->optional_default_patterns and returns lisf of patterns that should
    # be selected for installation by default (if they exist)
    #
    # @return [Array] list of patterns
    def optional_default_patterns
      product_feature_items("software", "optional_default_patterns")
    end

    # @return [Array] list of optional patterns
    def resolvable_optional_patterns
      PackagesProposal.GetAllResolvables(:pattern, optional: true)
    end

    # Get all the mandatory patterns
    #
    # @return [Array] list of mandatory patterns
    def resolvable_mandatory_patterns
      PackagesProposal.GetAllResolvables(:pattern)
    end

    # Extra patterns for the current target system
    #
    # @return [Array<String>] packages
    def extra_system_patterns
      pattern_list = []

      # 'laptop' selection if PCMCIA detected
      if Arch.is_laptop || Arch.has_pcmcia
        ["laptop", "Laptop"].each do |pat_name|
          pat_list = Pkg.ResolvableProperties(pat_name, :pattern, "")
          pattern_list << pat_name unless pat_list.empty?
        end
      end

      # is the FIPS compliant mode enabled?
      return pattern_list unless File.exist?(FIPS_FILE) && File.read(FIPS_FILE).chomp == "1"

      # install the FIPS pattern when the FIPS mode is enabled
      # see https://en.wikipedia.org/wiki/FIPS_140-2 for more details
      if Pkg.ResolvableProperties(FIPS_PATTERN, :pattern, "").empty?
        # TRANSLATORS: error popup, use at most 70 characters per line
        # the %{fips_option} string is replaced by the FIPS boot option ("fips=1"),
        # the %{fips_pattern} is replaced by the FIPS pattern name ("fips").
        Report.Error(_("The FIPS compliant mode has been enabled\n" \
          "but the '%{fips_pattern}' pattern is not available to install.\n\n" \
          "The installation will very likely fail and the installed system\n" \
          "might not work properly.\n\n" \
          "Either add an additional software repository providing\n" \
          "the '%{fips_pattern}' pattern or reboot the installation\n"\
          "without the '%{fips_option}' boot option.") %
            { fips_option: FIPS_BOOT_OPTION, fips_pattern: FIPS_PATTERN })
      else
        log.info "#{FIPS_BOOT_OPTION} boot option detected, adding '#{FIPS_PATTERN}' pattern"
        pattern_list << FIPS_PATTERN
      end

      pattern_list
    end

    # the name of the FIPS pattern
    FIPS_PATTERN = "fips".freeze
    # the kernel boot option which activates the FIPS behavior
    FIPS_BOOT_OPTION = "fips=1".freeze
    # the kernel file indicating whether the FIPS mode is supported and active
    # - if the kernel does not support the FIPS mode the file does not exist (openSUSE)
    # - if the kernel supports the FIPS mode the file exists (SLES)
    #   - if the FIPS mode is not active "0\n" is read
    #   - if the FIPS mode is active "1\n" is read
    FIPS_FILE = "/proc/sys/crypto/fips_enabled".freeze

    # Log only resolvables with resolvable["status"] matching these below
    LOG_RESOLVABLE_STATUS = [:selected, :removed].freeze

    # Log only resolvables with resolvable["transact_by"] matching these below
    LOG_RESOLVABLE_TRANSACT_BY = [:user, :app_high].freeze

    # Reads the current user selection and dumps it to log
    def log_software_selection
      log.info "-" * 10 << " Transaction Status Begin " << "-" * 10

      # we do not log packages as it can be increase significantly memory usage (see bsc#1076768)
      [:product, :pattern].each do |type|
        resolvables = Pkg.ResolvableProperties("", type, "")
        resolvables.select! { |r| LOG_RESOLVABLE_TRANSACT_BY.include? r["transact_by"] }

        LOG_RESOLVABLE_TRANSACT_BY.each do |transact_by|
          changed_resolvables = resolvables.select { |r| r["transact_by"] == transact_by }
          next if changed_resolvables.empty?

          decided_resolvables = changed_resolvables
                                .select { |r| LOG_RESOLVABLE_STATUS.include? r["status"] }
          log_resolvables("Resolvables of type #{type} set by #{transact_by}:", decided_resolvables)

          locked_resolvables = changed_resolvables.select { |r| r["locked"] }
          log_resolvables("Locked resolvables of type #{type} set by #{transact_by}:",
            locked_resolvables)
        end
      end

      log.info "-" * 10 << " Transaction Status End " << "-" * 10
      nil
    end

    # List of packages expected to be installed in order to enable
    # ssh.
    #
    # @return [Array<String>] package list
    def ssh_packages
      # "ip" tool is needed by the YaST2.ssh start script (bnc#920175)
      tags = ["openssh", "iproute2"]
      find_providers(tags)
    end

    # List of packages expected to be installed in order to enable
    # braille
    #
    # @return [Array<String>] package list
    def braille_packages
      tags = ["sbl"]
      find_providers(tags)
    end

    # List of packages expected to be installed in order to enable
    # remote administration (VNC)
    #
    # @return [Array<String>] package list
    def vnc_packages
      tags = VNC_BASE_TAGS.dup
      # At least one windowmanager must be installed (#427044)
      # If none is there, use a fallback
      tags << DEFAULT_WM unless has_window_manager?
      tags.concat(AUTOYAST_X11_TAGS) if Mode.autoinst
      find_providers(tags)
    end

    # List of packages expected to be installed in order to use
    # a remote X11 server
    #
    # @return [Array<String>] package list
    def remote_x11_packages
      tags = REMOTE_X11_BASE_TAGS.dup
      tags.concat(AUTOYAST_X11_TAGS) if Mode.autoinst
      find_providers(tags)
    end

    publish variable: :install_sources, type: "boolean"
    publish variable: :timestamp, type: "integer"
    publish variable: :metadir, type: "string"
    publish variable: :metadir_used, type: "boolean"
    publish variable: :theSources, type: "list <integer>"
    publish variable: :theSourceDirectories, type: "list <string>"
    publish variable: :theSourceOrder, type: "map <integer, integer>"
    publish variable: :base_selection_modified, type: "boolean"
    publish variable: :base_selection_changed, type: "boolean"
    publish variable: :solve_errors, type: "integer"
    publish variable: :add_on_products_list, type: "list <map <string, string>>"
    publish function: :ResetProposalCache, type: "void ()"
    publish function: :ListSelected, type: "list <string> (symbol, string)"
    publish function: :CountSizeToBeInstalled, type: "string ()"
    publish function: :CountSizeToBeDownloaded, type: "integer ()"
    publish function: :InfoAboutSubOptimalDistribution, type: "string ()"
    publish function: :SummaryOutput, type: "list <string> (list <symbol>)"
    publish function: :CheckDiskSize, type: "boolean (boolean)"
    publish function: :CheckOldAddOns, type: "void (map &)"
    publish function: :Summary, type: "map (list <symbol>, boolean)"
    publish function: :ForceFullRepropose, type: "void ()"
    publish function: :Reset, type: "void (list <symbol>)"
    publish function: :InitializeAddOnProducts, type: "void ()"
    publish function: :addAdditionalPackage, type: "void (string)"
    publish function: :ComputeSystemPatternList, type: "list <string> ()"
    publish function: :ComputeSystemPackageList, type: "list <string> ()"
    publish function: :GetBaseSourceID, type: "integer ()"
    publish function: :Init, type: "void (boolean)"
    publish function: :SlideShowSetUp, type: "void (string)"
    publish function: :AdjustSourcePropertiesAccordingToProduct, type: "boolean (integer)"
    publish function: :Initialize_StageInitial, type: "void (boolean, string, string)"
    publish function: :Initialize_StageNonInitial, type: "void (boolean, string, string)"
    publish function: :Initialize, type: "void (boolean)"
    publish function: :Proposal, type: "map (boolean, boolean, boolean)"
    publish function: :InitializeCatalogs, type: "void ()"
    publish function: :InitFailed, type: "boolean ()"
    publish function: :SelectKernelPackages, type: "void ()"
    publish function: :default_patterns, type: "list <string> ()"
    publish function: :log_software_selection, type: "void ()"
    publish function: :vnc_packages, type: "list <string> ()"
    publish function: :remote_x11_packages, type: "list <string> ()"
    publish variable: :init_called, type: "boolean"
    publish function: :check_remote_installation_packages, type: "void (string)"

  private

    # Reads product feature defined by parameters, logs what it gets
    # and returns list of items split by whitespaces
    #
    # @param [String] section in control file
    # @param [String] feature in section
    # @return [Array] of items
    def product_feature_items(section, feature)
      feature_items = ProductFeatures.GetStringFeature(section, feature)
      log.info "Product feature #{section}->#{feature} items: #{feature_items.inspect}"
      feature_items.strip.split
    end

    def log_resolvables(text, resolvables)
      return if resolvables.empty?

      log.info text

      resolvables.each do |r|
        r_info = { name: r["name"], version: r["version"], arch: r["arch"], status: r["status"] }
        log.info "- #{r_info}"
      end
    end

    # Prepares a list of formatted selected resolvables
    #
    # @param [Array<Hash>] selected list of selected resolvables to format
    # @param [String] format string format to use
    def formatted_resolvables(selected, format)
      format = "%1" if format == "" || format.nil?

      Builtins.maplist(selected) do |r|
        disp = Ops.get_string(r, "summary", Ops.get_string(r, "name", ""))
        Builtins.sformat(format, disp)
      end
    end

    # Sort selected resolvables of specified type
    #
    # :pattern resolvables are sorted by "order"
    # :product resolvables are sorted by "source"
    #
    # @param [Array<Hash>] selected list of selected resolvables to sort
    # @param [Symbol] what symbol specifying the type of resolvables to select
    # @see RESOLVABLE_SORT_ORDER
    def sort_resolvable!(selected, what)
      order = RESOLVABLE_SORT_ORDER[what]

      selected.sort_by! { |r| r[order].to_i } if order
    end

    # Computes all patterns that are expected to be selected for default installation
    def patterns_to_install
      patterns = ComputeSystemPatternList().dup

      # autoinstallation has patterns specified in the profile
      if !Mode.autoinst
        (default_patterns | optional_default_patterns).inject(patterns, :<<)
      end

      # preselect the default product patterns (FATE#320199)
      # note: must be called *after* selecting the products
      require "packager/product_patterns"
      product_patterns = ProductPatterns.new
      log.info "Found default product patterns: #{product_patterns.names}"
      patterns.concat(product_patterns.names)

      patterns.uniq
    end

    def report_missing_pattern(pattern_name)
      if (default_patterns | resolvable_mandatory_patterns).include?(pattern_name)
        log.error "Mandatory pattern #{pattern_name} does not exist"
        # Error message, %{pattern_name} is replaced with the missing pattern name in runtime
        Report.Error(_(
          "Failed to select default product pattern %{pattern_name}.\n" \
          "Pattern has not been found."
        ) % { pattern_name: pattern_name })
      else
        log.info "Optional pattern #{pattern_name} does not exist, skipping..."
      end
    end

    # Search for providers for a list of tags
    #
    # The use case of this method is to convert and array of tags into an array
    # of packages. If a tag does not have a provider, then the tag will be
    # included in the array and an error will be logged.
    #
    # @param tags [Array<String>] List of tags (ie. package names) to search for.
    # @return     [Array<String>] List contaning a package for each tag.
    # @see find_provider
    def find_providers(tags)
      tags.each_with_object([]) do |tag, providers|
        provider = find_provider(tag)
        if provider.nil?
          log.error "Provider not found for '#{tag}'"
          providers << tag
        else
          providers << provider
        end
      end
    end

    # Search a provider for a tag
    #
    # If more than one provider is found, a warning will be logged.
    #
    # @param tag [String]     Tag to search a package for.
    # @return    [String,nil] Name of the package which provides that tag.
    #                         It returns nil if no provider is found.
    # @see find_providers
    def find_provider(tag)
      providers = Pkg.PkgQueryProvides(tag).select { |pr| pr[1] != :NONE }
      filtered = providers.select { |pr| pr[1] == :BOTH }
      filtered = providers.select { |pr| pr[1] == :CAND } if filtered.empty?
      names = filtered.map(&:first)
      provider = names.include?(tag) ? tag : names.sort.first
      if names.size > 1
        log.warn "More than one provider was found for '#{tag}': "\
          "#{names.join(", ")}. Selecting '#{provider}'."
      end
      provider
    end

    # list of all products that will be installed (are selected)
    def products_to_install(products)
      products.select { |product| product["status"] == :selected }
    end

    # list of all products that will be removed
    def products_to_remove(products)
      products.select { |product| product["status"] == :removed }
    end

    def products_to_update(installed_products, removed_products)
      # process the selected and removed products and find product updates
      # map content: old_product => new_product
      updated_products = {}
      installed_products.each do |installed_product|
        removed = removed_products.select do |removed_product|
          installed_name = installed_product["name"]
          removed_name = removed_product["name"]

          # check the current product names or product renames
          removed_name == installed_name ||
            AddOnProduct.renamed?(removed_name, installed_name)
        end

        removed.each { |r| updated_products[r] = installed_product }
      end

      updated_products
    end

    # list of all products that will be unchanged (kept installed)
    def kept_products(products)
      products.select { |product| product["status"] == :installed }
    end

    # Checks if a window manager is installed or selected for installation
    #
    # @return [Boolean] true if there is a window manager
    def has_window_manager?
      Pkg.IsSelected("windowmanager") || Pkg.IsProvided("windowmanager")
    end

    # Check whether all packages needed by YaST will be installed (the user can
    # override the YaST settings)
    # @return [Hash<Symbol,Array<String>>] The key is resolvable type (:pattern or
    #   :package), the value is list of names.
    #   If nothing is missing an empty Hash is returned.
    def check_missing_resolvables
      missing = {}
      proposed = PackagesProposal.GetAllResolvablesForAllTypes

      proposed.each do |type, list|
        list.each do |item|
          statuses = Pkg.ResolvableProperties(item, type, "")

          # :selected = selected to install/update, :installed = keep installed (at upgrade)
          if !statuses.nil? && statuses.find { |s| [:selected, :installed].include?(s["status"]) }
            next
          end
          missing[type] = [] unless missing[type]
          # use quoted "summary" value for patterns as they usually contain spaces
          name = type == :pattern ? statuses.first["summary"].inspect : item
          missing[type] << name
        end
      end

      missing
    end

    # Build a human readable string describing missing resolvables.
    # @param [Symbol] type resolvable type, either :pattern or :packages
    # @param [Array<String>] list of names
    # @return [String] Translated message containing missing resolvables
    def format_missing_resolvables(type, list)
      list_str = list.join(", ")

      case type
      when :package
        # TRANSLATORS: %s is a package list
        _("These packages need to be selected to install: %s") % list_str
      when :pattern
        # TRANSLATORS: %s is a pattern list
        _("These patterns need to be selected to install: %s") % list_str
      else
        # TRANSLATORS: %{type} is a resolvable type, %{list} is a list of names
        # This is a fallback message for unknown types, normally it should not be displayed
        _("These items (%{type}) need to be selected to install: %{list}") %
          { type: type, list: list }
      end
    end

    # Device name of the given filesystem, used to identify the filesystem in
    # the log messages
    def fs_dev_name(filesystem)
      blk_device = filesystem.blk_devices[0]
      return "" unless blk_device
      blk_device.name
    end

    # Create the baseproduct file pointing to a found product file.
    def create_baseproduct_symlink
      prod_files = Dir["/etc/products.d/*.prod"]

      if prod_files.empty?
        log.warn("No product file found, not creating the baseproduct symlink")
        return
      end

      log.warn("More than one product found: #{prod_files}") if prod_files.size > 1

      product_file = prod_files.first
      log.info("Creating #{BASE_PRODUCT_FILE} symlink pointing to #{product_file}")
      ::FileUtils.ln_s(product_file, BASE_PRODUCT_FILE)
    end

    # Checking if a package will be installed or is already installed
    # on a system and will not be deleted.
    # @param tag [String] package name
    # @return [Boolean] true if the package will be on the installed system
    def pkg_will_be_installed(tag)
      provides = Pkg.PkgQueryProvides(tag)
      # e.g.: [["kernel-bigsmp", :CAND, :NONE], ["kernel-default", :CAND, :CAND],
      # ["kernel-default", `BOTH, :INST]]
      ret = provides.any? { |p| p[2] != :NONE }
      log.info("#{tag} will #{ret ? "" : "not "}be installed")
      ret
    end

    # the default libzypp repository priority
    DEFAULT_PRIORITY = 99

    # Adjust the priority of the initial installation repository. (bsc#1071742)
    #
    # The initial repository priority is decreased (a higher number used!) to
    # prefer the packages from the other media to avoid unecessary media changes
    # for the same packages present on multiple media only if:
    #  - The initial repository is volatile (CD or DVD)
    #  - If all repositories are local (CD, DVD, HDD, USB...)
    #  - If there is at least one more volatile (CD or DVD) repository used
    #    as an addon
    #
    # Otherwise changing the priority does not make sense (installing from DVD
    # without any addon, installing from DVD + network addon, installing from
    # USB + a DVD addon,...).
    #
    # If there is a remote addon then the priority for the installation DVD
    # cannot be lowered because that would break the DVD preference set via the
    # "download_media_prefer_download" libzypp option.
    def adjust_repo_priority
      # all enabled repositories
      enabled_repos = Pkg.SourceGetCurrent(true)
      # just a sanity check, should not happen (TM)
      return if enabled_repos.empty?

      # all enabled repositories are local (CD, DVD, HDD, USB...)
      all_local = true
      # number of volatile media (CD or DVD)
      volatile_media = 0

      enabled_repos.each do |repo|
        url = Pkg.SourceGeneralData(repo)["url"]
        next if url.nil? || url.empty?
        scheme = URI(url).scheme
        all_local &= Pkg.UrlSchemeIsLocal(scheme)
        volatile_media += 1 if Pkg.UrlSchemeIsVolatile(scheme)
      end

      repo_id = enabled_repos.first
      repo_priority = Pkg.SourceGeneralData(repo_id)["priority"]
      repo_url = Pkg.SourceGeneralData(repo_id)["url"]
      repo_volatile = repo_url.empty? ? false : Pkg.UrlSchemeIsVolatile(URI(repo_url).scheme)

      log.info("All installation repositories are local: #{all_local}")
      log.info("Installing from volatile medium: #{repo_volatile}")
      log.info("Number of volatile media: #{volatile_media}")

      # change the priority only if:
      # - installing from a CD or DVD
      # - all repositories are local, no remote repository is used
      # - at least one CD or DVD addon is used (more than 2 media in total)
      if repo_volatile && all_local && volatile_media >= 2
        # decrease the priority (the higher number the lower priority!)
        Pkg.SourceSetPriority(repo_id, repo_priority + 1) if repo_priority == DEFAULT_PRIORITY
      # set the default if not set (e.g. reset after going back and adding
      # a remote repository or removing all other repositories)
      elsif repo_priority != DEFAULT_PRIORITY
        Pkg.SourceSetPriority(repo_id, DEFAULT_PRIORITY)
      end
    end
  end

  Packages = PackagesClass.new
  Packages.main
end
