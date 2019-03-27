# encoding: utf-8

# Module: 		sw_single.ycp
#
# Authors: 		Gabriele Strattner (gs@suse.de)
#			Klaus Kaempf <kkaempf@suse.de>
#
require "shellwords"

require "y2packager/known_repositories"
require "y2packager/system_packages"

module Yast
  # Purpose: 		contains dialog loop for workflows:
  #	"Install/Remove software"
  #
  # @note: sw_single accepts a map parameter: $[ "dialog_type" : symbol,
  #   "repo_mgmt" : boolean ], dialog_type" can be `patternSelector, `searchMode, `summaryMode
  #   "repo_mgmt" enables "Repositories" -> "Repository Manager..." menu option
  class SwSingleClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "packager"

      Yast.import "Confirm"
      Yast.import "Installation"
      Yast.import "Mode"
      Yast.import "PackageCallbacks"
      Yast.import "PackageLock"
      Yast.import "PackageSlideShow"
      Yast.import "SlideShow"
      Yast.import "SlideShowCallbacks"
      Yast.import "Kernel"
      Yast.import "Wizard"
      Yast.import "Popup"
      Yast.import "GetInstArgs"
      Yast.import "PackageSystem"
      Yast.import "Report"
      Yast.import "FileUtils"
      Yast.import "PackagesUI"
      Yast.import "CommandLine"
      Yast.import "Progress"
      Yast.import "Directory"
      Yast.import "String"
      Yast.import "URL"

      @force_summary = false

      # `install
      # `remove, `update: used from gnome-main-menu (#222757)
      @action = :install
      @test_popup = false
      @packagelist = [] # list of packages to act on

      # Start commandline interface only when the parameter is "help", otherwise start standard GUI.
      # The reason is that "yast2 -i package" is translated to "yast2 sw_single package",
      # we don't know wheter "package" is a command or a package name.
      # Package name is assumed for backward compatibility.
      if WFM.Args == ["help"]
        @cmdline_description = {
          "id"         => "sw_single",
          # Command line help text for the software management module, %1 is "zypper"
          "help"       => Builtins.sformat(
            _(
              "Software Installation - This module does not support the command " \
                "line interface, use '%1' instead."
            ),
            "zypper"
          ),
          "guihandler" => fun_ref(method(:StartSWSingle), "symbol ()")
        }

        return CommandLine.Run(@cmdline_description)
      end

      StartSWSingle()
    end

    # =============================================================

    # check test_popup
    # test_mode is checked for in Installation constructor

    def CheckArguments
      arg_n = Ops.subtract(Builtins.size(WFM.Args), 1)

      arg_list = []

      while Ops.greater_or_equal(arg_n, 0)
        if WFM.Args(arg_n) == path(".test")
          Mode.SetTest("test")
        elsif WFM.Args(arg_n) == path(".testp")
          Mode.SetTest("test") # .testp implies .test
          @test_popup = true
        elsif Ops.is_string?(WFM.Args(arg_n))
          s = Builtins.tostring(WFM.Args(arg_n))
          if s == "--install"
            @action = :install
          elsif s == "--remove"
            @action = :remove
          elsif s == "--update"
            @action = :update
          else
            arg_list = Builtins.add(arg_list, s)
          end
        elsif Ops.is_list?(WFM.Args(arg_n))
          Builtins.foreach(Convert.to_list(WFM.Args(arg_n))) do |arg|
            arg_list = Builtins.add(arg_list, Builtins.tostring(arg))
          end
        end
        arg_n = Ops.subtract(arg_n, 1)
      end

      Builtins.y2milestone("action: %1", @action)
      deep_copy(arg_list)
    end # CheckArguments

    #
    # CheckWhichPackages
    #
    # Check arg_list:
    # If we're called with an absolute package path just install
    # this package without paying attention to dependencies.
    #
    # returns	`done		all done
    #		`failed		package not found
    #		`found_descr	started package manager
    #

    def CheckWhichPackages(arg_list)
      arg_list = deep_copy(arg_list)
      if !Pkg.TargetInit("/", false)
        # error message
        Report.Error("Cannot read the list of installed packages.")
        return :failed
      end

      Builtins.y2milestone("CheckWhichPackages (%1)", arg_list)
      # if sw_single is called with a list of packages or a package name

      first_arg = ""

      if Ops.greater_than(Builtins.size(arg_list), 0)
        first_arg = Ops.get(arg_list, 0, "")
      end

      # If the first argument is a package ending with .rpm call Pkg::TargetInstall for
      # each arg.
      if Builtins.regexpmatch(first_arg, "\\.rpm$") # package name given
        PackageSystem.EnsureSourceInit

        # if sw_single is called with an absolute package-pathname, there is no need to
        # mount the source medium or check SuSE version or dependencies

        PackageSlideShow.InitPkgData(true) # force reinitialization

        # create a temporary Plaindir repository
        tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
        tmprepo = Ops.add(tmpdir, "/tmp_install_repo")

        # create mount point directory
        SCR.Execute(path(".target.mkdir"), tmprepo)

        Builtins.foreach(arg_list) do |package|
          # a symbolic link
          command = "/usr/bin/ln -- #{package.shellescape} #{tmprepo.shellescape}"
          Builtins.y2milestone("Linking package using command: %1", command)
          out = SCR.Execute(path(".target.bash_output"), command)
          if Ops.get_integer(out, "exit", -1).nonzero?
            Builtins.y2warning(
              "Could not link the package, creating a full copy instead..."
            )
            command = "/usr/bin/cp -- #{package.shellescape} #{tmprepo.shellescape}"

            Builtins.y2milestone("Copying package using command: %1", command)
            out = SCR.Execute(path(".target.bash_output"), command)

            if Ops.get_integer(out, "exit", -1).nonzero?
              # error message (%1 is a package file name)
              Report.Error(
                Builtins.sformat(
                  _("Error: Cannot copy package %1 to temporary repository."),
                  package
                )
              )
              next :failed
            end
          end
        end

        url = URL.Build("scheme" => "file", "path" => tmprepo)
        Builtins.y2milestone("Using tmp repo URL: %1", url)

        repo_id = nil

        return :failed if url == ""

        repo_id = Pkg.SourceCreateType(url, "", "Plaindir")
        Builtins.y2milestone("Adde temporary repository with ID %1", repo_id)

        if repo_id.nil?
          # error message
          Report.Error(
            Builtins.sformat(
              _(
                "Error: Cannot add a temporary directory, packages cannot be installed."
              )
            )
          )
          return :failed
        end

        Builtins.foreach(arg_list) do |package|
          if Ops.greater_than(SCR.Read(path(".target.size"), package), 0)
            out = SCR.Execute(
              path(".target.bash_output"),
              "/bin/rpm -q --qf '%{NAME}' -p #{package.shellescape}"
            )

            if Ops.get_integer(out, "exit", -1).nonzero?
              # error message
              Report.Error(
                Builtins.sformat(
                  _("Error: Cannot query package file %1."),
                  package
                )
              )
              next :failed
            end

            package_name = Ops.get_string(out, "stdout", "")

            # is it a source package?
            out = SCR.Execute(
              path(".target.bash_output"),
              "/bin/rpm -q --qf '%{SOURCEPACKAGE}' -p #{package.shellescape}"
            )
            if Ops.get_integer(out, "exit", -1).nonzero?
              # error message
              Report.Error(
                Builtins.sformat(
                  _("Error: Cannot query package file %1."),
                  package
                )
              )
              next :failed
            end

            srcpackage = Ops.get_string(out, "stdout", "") == "1"
            Builtins.y2milestone(
              "File %1: package name: %2, src package: %3",
              package,
              package_name,
              srcpackage
            )

            Builtins.y2milestone(
              "Installing %1 from file %2 (repository %3)",
              package_name,
              package,
              repo_id
            )
            installed = Pkg.ResolvableInstallRepo(
              package_name,
              srcpackage ? :srcpackage : :package,
              repo_id
            )

            if !installed
              # Error message:
              # %1 = package name (may include complete RPM file name)
              # %2 = error message
              Report.Error(
                Builtins.sformat(
                  _(
                    "Package %1 could not be installed.\n" \
                      "\n" \
                      "Details:\n" \
                      "%2\n"
                  ),
                  package,
                  Pkg.LastError
                )
              )
            end
          else
            # error popup, %1 is the name of the .rpm package
            message = Builtins.sformat(
              _("Package %1 was not found on the medium."),
              package
            )
            Builtins.y2error(
              "SW_SINGLE: Package %1 was not found on the medium",
              package
            )
            Popup.Message(message)
            next :failed
          end
        end

        Pkg.PkgSolve(false)
        @force_summary = true
      elsif first_arg != "" # firstarg given, but not *.rpm
        arg_name = Ops.get(arg_list, 0, "")

        if !FileUtils.IsFile(arg_name) ||
            Ops.less_or_equal(FileUtils.GetSize(arg_name), 0) # Check: a local file ? bigger than 0?
          @packagelist = deep_copy(arg_list) # No: expect package names # Yes: try to read the file
        else
          Builtins.y2milestone("Reading file %1", arg_name)
          @packagelist = Convert.convert(
            SCR.Read(path(".target.ycp"), arg_name),
            from: "any",
            to:   "list <string>"
          ) # try .ycp list first
          if @packagelist.nil? || @packagelist == []
            packagestr = Convert.to_string(
              SCR.Read(path(".target.string"), arg_name)
            ) # string ascii file next
            @packagelist = Builtins.splitstring(packagestr, "\n")
            # filter empty lines out,  bug #158226
            @packagelist = Builtins.filter(@packagelist) do |package|
              !Builtins.regexpmatch(package, "^ *$")
            end
          end
        end
        Builtins.y2milestone("packagelist: %1", @packagelist)
      end

      # start package manager
      enabled_only = true

      Progress.NextStage
      mgr_ok = Pkg.SourceStartManager(enabled_only)
      if !mgr_ok
        Report.LongWarning(
          Ops.add(
            _("An error occurred during repository initialization.") + "\n",
            Pkg.LastError
          )
        )
      end
      if Builtins.size(Pkg.SourceGetCurrent(enabled_only)).zero?
        Report.Warning(
          _("No repository is defined.\nOnly installed packages are displayed.")
        )
      end

      # reset the target if needed (e.g. dirinstall mode)
      # EnsureTargetInit() uses "/" as root
      if Installation.destdir != "/"
        Builtins.y2milestone("Setting a new target: %1", Installation.destdir)
        Progress.NextStage
        Pkg.TargetInit(Installation.destdir, false)
      end

      :found_descr
    end # CheckWhichPackages

    # originally stolen from inst_do_net_test.ycp:IsDownloadedVersionNewer
    # Function checks two versions of installed rpm and decides
    # whether the second one is newer than the first one. This
    # function ignores non-numerical values in versions.
    # Version and Release parts are merged!
    # FIXME make a binding to librpm.
    # @param a_version [String] first version
    # @param b_version [String] second version
    # @return [Boolean] true if the second one is newer than the first one
    def VersionALtB(a_version, b_version)
      a_version_l = Builtins.filter(Builtins.splitstring(a_version, "-.")) do |s|
        Builtins.regexpmatch(s, "^[0123456789]+$")
      end
      b_version_l = Builtins.filter(Builtins.splitstring(b_version, "-.")) do |s|
        Builtins.regexpmatch(s, "^[0123456789]+$")
      end

      Builtins.y2milestone(
        "Comparing versions %1 and %2",
        a_version_l,
        b_version_l
      )
      a_size = Builtins.size(a_version_l)
      b_size = Builtins.size(b_version_l)
      longer_size = Ops.greater_than(a_size, b_size) ? a_size : b_size

      compare = 0 # <0 if a<b, =0 if a==b, >0 if a>b
      i = 0
      while Ops.less_than(i, longer_size)
        # -1 will make the desirable outcome of "2" < "2.0"
        a_item = Builtins.tointeger(Ops.get(a_version_l, i, "-1"))
        b_item = Builtins.tointeger(Ops.get(b_version_l, i, "-1"))
        if Ops.less_than(a_item, b_item)
          compare = -1
          break
        end
        if Ops.greater_than(a_item, b_item)
          compare = 1
          break
        end
        i = Ops.add(i, 1)
      end

      Builtins.y2milestone("%1 <=> %2 -> %3", a_version, b_version, compare)
      Ops.less_than(compare, 0)
    end

    # Check if there is an uninstalled package of the same name with a
    # higher version. Otherwise we would forcefully reinstall it. #222757#c9
    def CanBeUpdated(package)
      props = Pkg.ResolvableProperties(
        package, # any version
        :package,
        ""
      )
      # find maximum version and remember
      # if it is installed
      max_ver = "0"
      max_is_installed = false
      Builtins.foreach(props) do |prop|
        cur_ver = Ops.get_string(prop, "version", "0")
        if VersionALtB(max_ver, cur_ver)
          max_ver = cur_ver
          # `installed or `selected is ok
          max_is_installed = Ops.get_symbol(prop, "status", :available) != :available
          Builtins.y2milestone("new max: installed: %1", max_is_installed)
        end
      end
      !max_is_installed
    end

    def GetPackagerOptions
      # defaults
      mode = nil
      repo_management = nil

      Builtins.y2milestone("Args: %1", WFM.Args)

      Builtins.foreach(WFM.Args) do |a|
        if Ops.is_map?(a)
          m = Convert.to_map(a)

          if Builtins.haskey(m, "dialog_type")
            mode = Ops.get_symbol(m, "dialog_type", :searchMode)
          end

          if Builtins.haskey(m, "repo_mgmt")
            repo_management = Ops.get_boolean(m, "repo_mgmt", false)
          end
        end
      end

      # use default parameters for missing or invalid values
      if mode.nil?
        preselect_system_packages

        # use summary mode if there is something to install
        # (probably a suggested or recommended package) (bnc#465194)
        mode = if Pkg.IsAnyResolvable(:any, :to_install) || Pkg.IsAnyResolvable(:any, :to_remove)
          :summaryMode
        else
          :searchMode
        end
      end
      repo_management = Mode.normal if repo_management.nil?

      ret = { "mode" => mode, "enable_repo_mgr" => repo_management }

      Builtins.y2milestone("PackagesUI::RunPackageSelector() options: %1", ret)

      deep_copy(ret)
    end

    # select the system packages (drivers) from the new repositories
    def preselect_system_packages
      known_repos = Y2Packager::KnownRepositories.new
      system_packages = Y2Packager::SystemPackages.new(known_repos.new_repositories)
      system_packages.select
    end

    def save_known_repositories
      known_repos = Y2Packager::KnownRepositories.new
      # nothing new, no need to update the file
      return if known_repos.new_repositories.empty?

      known_repos.update
      known_repos.write
    end

    # =============================================================
    def StartSWSingle
      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("sw_single")

      # a stage in the progress dialog
      stages = [
        _("Initialize the Target System"),
        _("Load the Configured Repositories")
      ]

      # an extra step is needed in dir inst mode
      if Installation.destdir != "/"
        Builtins.y2milestone("Extra step is needed")
        # %1 is path to the target system (e.g. /tmp/dirinstall
        Builtins.sformat(
          _("Reset the target system to %1"),
          Installation.destdir
        )
      end

      # a stage in the progress dialog
      Progress.New(_("Starting the Software Manager"), "", 2, stages, [], "")
      Progress.NextStage

      Yast.import "Packages"

      # check whether running as root
      # and having the packager for ourselves
      if !Confirm.MustBeRoot
        UI.CloseDialog
        return :abort
      end

      if !Ops.get_boolean(PackageLock.Connect(false), "connected", false)
        # SW management is already in use, access denied
        # the yast module cannot be started
        UI.CloseDialog
        return :abort
      end

      # check Args
      # set test_mode, test_popup
      arg_list = CheckArguments()

      # check the arguments and try the mount/search for local description
      result = CheckWhichPackages(arg_list)

      # clear the progress dialog so it's not displayed by accident at the end (bnc#637201)
      Wizard.SetContents("", Empty(), "", false, false)

      Pkg.SetTextLocale(UI.GetLanguage(true))

      Builtins.y2milestone("SW_SINGLE: result CheckWhichPackages %1", result)

      if result == :done || result == :failed
        UI.CloseDialog
        return :next
      end

      force_restart = false
      found_descr = result == :found_descr
      begin
        # reset summary
        PackagesUI.ResetPackageSummary

        force_restart = false

        old_failed_packs = []
        if Ops.greater_than(
          Convert.to_integer(
            SCR.Read(path(".target.size"), "/var/lib/YaST2/failed_packages")
          ),
          0
        )
          old_failed_packs = Convert.convert(
            SCR.Read(path(".target.ycp"), "/var/lib/YaST2/failed_packages"),
            from: "any",
            to:   "list <string>"
          )
        end
        if Ops.greater_than(Builtins.size(old_failed_packs), 0) &&
            Popup.YesNo(
              _(
                "During the last package installation\n" \
                  "several packages failed to install.\n" \
                  "Install them now?\n"
              )
            )
          Builtins.foreach(old_failed_packs) { |p| Pkg.PkgInstall(p) }
        end

        if found_descr
          if Builtins.size(@packagelist).zero? # packages given ?
            opts = GetPackagerOptions()
            Builtins.y2milestone("Using packager widget options: %1", opts)

            result = PackagesUI.RunPackageSelector(opts) # No: ask user via package selection widget
            Builtins.y2milestone("Package selector retured: %1", result)
            if result == :accept
              result = :next
            # start the repository manager
            elsif result == :repo_mgr
              save_known_repositories
              WFM.CallFunction("repositories", [:sw_single_mode])
              # preselect the driver packages from new repositories
              preselect_system_packages
              force_restart = true
            elsif result == :online_update_configuration
              required_package = "yast2-online-update-configuration"

              if !PackageSystem.Installed(required_package) &&
                  !PackageSystem.CheckAndInstallPackages([required_package])
                Report.Error(
                  Builtins.sformat(
                    _(
                      "Cannot configure online update repository \n" \
                        "without having package %1 installed"
                    ),
                    required_package
                  )
                )
              else
                cfg_result = Convert.to_symbol(
                  WFM.CallFunction(
                    "online_update_configuration",
                    [:no_source_finish]
                  )
                )
                Builtins.y2milestone(
                  "online_update_configuration result: %1",
                  cfg_result
                )
              end
              force_restart = true
            elsif result == :webpin
              required_package = "yast2-packager-webpin"

              if !PackageSystem.Installed(required_package)
                if !PackageSystem.CheckAndInstallPackages([required_package])
                  Report.Error(
                    Builtins.sformat(
                      _(
                        "Cannot search packages in online repositories\n" \
                          "without having package %1 installed"
                      ),
                      required_package
                    )
                  )
                end
              else
                WFM.CallFunction("webpin_package_search", [])
              end
              force_restart = true
            end
          else
            nonexisting = Builtins.filter(@packagelist) do |p|
              !Pkg.IsAvailable(p)
            end
            if @action != :remove &&
                Ops.greater_than(Builtins.size(nonexisting), 0)
              Builtins.y2error(
                "Tags %1 aren't available",
                Builtins.mergestring(nonexisting, ", ")
              )
              Report.LongError(
                Builtins.sformat(
                  # error report, %1 is a list of packages
                  _(
                    "The following packages have not been found on the medium:\n%1\n"
                  ),
                  Builtins.mergestring(nonexisting, "\n")
                )
              )
              return :cancel
            end
            Builtins.foreach(
              @packagelist # Yes: install them
            ) do |package|
              if @action == :install ||
                  # TODO: `update: tell the user if already up to date
                  @action == :update && CanBeUpdated(package)
                # select package for installation
                if !Pkg.PkgInstall(package)
                  # oops, package not found ? try capability
                  Pkg.DoProvide([package])
                end
              elsif @action == :remove
                if !Pkg.PkgDelete(package)
                  # package failed, try capability
                  Pkg.DoRemove([package])
                end
              end
            end

            # confirm removal by user (bnc#399795)
            if @action == :remove
              opts = { "dialog_type" => :summaryMode, "repo_mgmt" => true }
              Builtins.y2milestone("Using packager widget options: %1", opts)

              result = PackagesUI.RunPackageSelector(opts)

              return :abort if result != :accept
            end

            if Pkg.PkgSolve(false) # Solve dependencies
              result = :next # go-on if no conflicts
            else
              # ask user if there is a problem
              opts = { "dialog_type" => :summaryMode, "repo_mgmt" => true }

              result = PackagesUI.RunPackageSelector(opts)

              Builtins.y2milestone("Packager returned: %1", result)
              result = :next if result == :accept
            end
          end
        end

        if result == :next # packages selected ?
          # ask user to confirm all remaining licenses (#242298)
          licenses_accepted = PackagesUI.ConfirmLicenses

          # all licenses accepted?
          if !licenses_accepted
            # no, go back to the package selection
            force_restart = true
            next
          end

          SCR.Write(path(".target.ycp"), "/var/lib/YaST2/failed_packages", [])
          anyToDelete = Pkg.IsAnyResolvable(:package, :to_remove)
          SlideShow.SetLanguage(UI.GetLanguage(true))
          PackageSlideShow.InitPkgData(true) # force reinitialization
          SlideShow.OpenDialog

          stages2 = [
            {
              "name"        => "packages",
              "description" => _("Installing Packages..."),
              "value"       => Ops.divide(
                PackageSlideShow.total_size_to_install,
                1024
              ), # kilobytes
              "units"       => :kb
            }
          ]

          SlideShow.Setup(stages2)

          SlideShow.MoveToStage("packages")

          Yast.import "PackageInstallation"
          oldvmlinuzsize = Convert.to_integer(
            SCR.Read(path(".target.size"), "/boot/vmlinuz")
          )
          commit_result = PackageInstallation.CommitPackages(0, 0) # Y: commit them !
          newvmlinuzsize = Convert.to_integer(
            SCR.Read(path(".target.size"), "/boot/vmlinuz")
          )

          Builtins.y2milestone("Commit result: %1", commit_result)

          SlideShow.CloseDialog

          if Mode.normal && # show new kernel popup only in normal system, not during installation
              Installation.destdir == "/" &&
              (Ops.greater_than(Ops.get_integer(commit_result, 0, 0), 0) || anyToDelete)
            # prepare "you must boot" popup
            Kernel.SetInformAboutKernelChange(oldvmlinuzsize != newvmlinuzsize)
            Kernel.InformAboutKernelChange
          end

          if Mode.normal
            pkgmgr_action_at_exit = Convert.to_string(
              SCR.Read(path(".sysconfig.yast2.PKGMGR_ACTION_AT_EXIT"))
            )

            pkgmgr_action_at_exit = "close" if pkgmgr_action_at_exit.nil?

            Builtins.y2milestone(
              "PKGMGR_ACTION_AT_EXIT: %1, force_summary: %2",
              pkgmgr_action_at_exit,
              @force_summary
            )

            # display installation summary if there has been an error
            # or if it's enabled in sysconfig
            if pkgmgr_action_at_exit == "summary" || @force_summary ||
                commit_result == [-1] || # aborted by user
                Ops.greater_than(
                  Builtins.size(Ops.get_list(commit_result, 1, [])),
                  0
                )
              Builtins.y2milestone("Summary dialog needed")
              if PackagesUI.ShowInstallationSummary == :back &&
                  Builtins.size(@packagelist).zero?
                force_restart = true
              end
            elsif pkgmgr_action_at_exit == "restart" &&
                Builtins.size(@packagelist).zero?
              force_restart = true
            end

            # remember the current repositories for the next time
            save_known_repositories
          end
        end
      end while force_restart

      UI.CloseDialog

      result
    end
  end
end

Yast::SwSingleClient.new.main
