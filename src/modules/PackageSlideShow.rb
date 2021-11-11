require "yast"
require "yast2/system_time"

# Yast namespace
module Yast
  # Module to access slides from installation repository
  class PackageSlideShowClass < Module
    include Yast::Logger

    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "packager"

      Yast.import "SlideShow"
      Yast.import "String"
      Yast.import "Mode"

      @inst_src_names = [] # a list of strings identifying each repository
      @total_size_installed = 0
      @total_size_to_install = 0

      @init_pkg_data_complete = false

      # package summary
      # package counters
      @installed_packages = 0
      @updated_packages = 0
      @removed_packages = 0

      @total_downloaded = 0
      @total_installed = 0

      # package list (only used in installed system)
      @installed_packages_list = []
      @updated_packages_list = []
      @removed_packages_list = []

      @updating = false
    end

    def ResetPackageSummary
      @installed_packages = 0
      @updated_packages = 0
      @removed_packages = 0
      @total_downloaded = 0
      @total_installed = 0

      @installed_packages_list = []
      @updated_packages_list = []
      @removed_packages_list = []

      # temporary values
      @updating = false

      nil
    end

    def GetPackageSummary
      {
        "installed"        => @installed_packages,
        "updated"          => @updated_packages,
        "removed"          => @removed_packages,
        "installed_list"   => @installed_packages_list,
        "updated_list"     => @updated_packages_list,
        "removed_list"     => @removed_packages_list,
        "downloaded_bytes" => @total_downloaded,
        "installed_bytes"  => @total_installed
      }
    end

    # ***************************************************************************
    # **************  Formatting functions and helpers **************************
    # ***************************************************************************

    # Sum up all list items. It flattens list and also skip all negative values.
    #
    # @param sizes [Array<Fixnum|Array>] Sizes to sum
    # @return [Fixnum] Sizes sum
    def ListSum(sizes)
      sizes.flatten.select(&:positive?).reduce(0, :+)
    end

    def TotalInstalledSize
      @total_size_installed
    end

    # Format number of remaining bytes to be installed as string.
    # @param [Fixnum] remaining    bytes remaining, -1 for 'done'
    # @return      [String] human readable remaining time or byte / kB/ MB size
    #
    def FormatRemainingSize(remaining)
      if Ops.less_than(remaining, 0)
        # Nothing more to install from this CD (very concise - little space!!)
        return _("Done.")
      end
      return "" if remaining.zero?

      String.FormatSize(remaining)
    end

    # Format number of remaining packages to be installed as string.
    # @param [Fixnum] remaining    bytes remaining, -1 for 'done'
    # @return      [String] human readable remaining time or byte / kB/ MB size
    #
    def FormatRemainingCount(remaining)
      if Ops.less_than(remaining, 0)
        # Nothing more to install from this CD (very concise - little space!!)
        return _("Done.")
      end
      return "" if remaining.zero?

      Builtins.sformat("%1", remaining)
    end

    # Initialize internal pacakge data, such as remaining package sizes and
    # times. This may not be called before the pkginfo server is up and
    # running, so this cannot be reliably done from the constructor in all
    # cases.
    # @param [Boolean] force true to force reinitialization
    #
    def InitPkgData(force)
      return if @init_pkg_data_complete && !force

      ResetPackageSummary()
      # Reinititalize some globals (in case this is a second run)
      @total_size_installed = 0

      total_sizes_per_cd_per_src = Pkg.PkgMediaSizes
      total_pkg_count_per_cd_per_src = Pkg.PkgMediaCount

      @total_size_to_install = ListSum(total_sizes_per_cd_per_src)
      log.info "total_size_to_install: #{@total_size_to_install}"
      @total_pkgs_to_install = ListSum(total_pkg_count_per_cd_per_src)
      @init_pkg_data_complete = true
    end

    # Recalculate remaining times per CD based on package sizes remaining
    # and data rate so far. Recalculation is only done each 'recalc_interval'
    # seconds unless 'force_recalc' is set to 'true'.
    #
    # @param [Boolean] force_recalc force recalculation even if timeout not reached yet
    # @return true if recalculated, false if not
    #
    # @see SlideShow.next_recalc_time
    # @see Yast2::SystemTime.uptime
    def RecalcRemainingTimes(force_recalc)
      true
    end

    # Switch unit to seconds if necessary and recalc everything accordingly.
    # @return true if just switched from sizes to seconds, false otherwise
    #
    def SwitchToSecondsIfNecessary
      false
    end

    # ***************************************************************************
    # *****************  Callbacks and progress bars ****************************
    # ***************************************************************************

    # Update progress widgets for the current CD: Label and ProgressBar.
    # Use global statistics variables for that.
    # @param [Boolean] silent_check  don't complain in log file
    #
    def UpdateCurrentCdProgress(silent_check)
    end

    # update the overall progress value (download + installation)
    def UpdateTotalProgressValue
      total_progress = if @total_size_to_install.zero?
        100 # nothing to install. Should not happen
      else
        TotalInstalledSize() * 100 / @total_size_to_install
      end

      log.debug "Total package installation progress: #{total_progress}%"
      SlideShow.StageProgress(total_progress, nil)
    end

    # Update progress widgets
    #
    def UpdateTotalProgress(silent_check)
      # update the overall progress value (download + installation)
      UpdateTotalProgressValue()
    end

    # Progress display update
    # This is called via the packager's progress callbacks.
    #
    # @param [Fixnum] pkg_percent  package percentage
    #
    def UpdateCurrentPackageProgress(pkg_percent)
    end

    # update the download rate
    def UpdateCurrentPackageRateProgress(pkg_percent, bps_avg, bps_current)
      nil
    end

    def DisplayGlobalProgress
      rem_string = FormatRemainingSize(@total_size_to_install - @total_size_installed)

      rem_string += ", " unless rem_string.empty?

      SlideShow.SetGlobalProgressLabel(
        Ops.add(
          SlideShow.CurrentStageDescription,
          Builtins.sformat(
            _(" (Remaining: %1%2 packages)"),
            rem_string,
            @total_pkgs_to_install - @total_installed
          )
        )
      )

      nil
    end

    # Callback when file is downloaded ( but not yet installed )
    # @param error[Integer] error code
    def DoneProvide(error, _reason, _name)
      return if error.nonzero?

      # move the progress also for downloaded files
      UpdateTotalProgressValue()
      nil
    end

    # Update progress widgets for all CDs.
    # Uses global statistics variables.
    # Redraw whole table, time consuming, but called only when all times recalculated.
    #
    def UpdateAllCdProgress(silent_check)
      nil
    end

    # Return a CD's progress bar ID
    # @param [Fixnum] src_no number of the repository (from 0 on)
    # @param [Fixnum] cd_no number of the CD within that repository (from 0 on)
    #
    def CdProgressId(src_no, cd_no)
      Builtins.sformat("Src %1 CD %2", src_no, cd_no)
    end

    # package start display update
    # - this is called at the end of a new package
    #
    # @param [String] pkg_name    package name
    # @param [String] pkg_size    package size in bytes
    # @param [Boolean] deleting    Flag: deleting (true) or installing (false) package
    #
    def SlideDisplayDone(pkg_name, pkg_size, deleting)
      if !deleting
        @total_size_installed += pkg_size

        UpdateTotalProgress(false)

        # Update global progress bar
        DisplayGlobalProgress()

        if @updating
          @updated_packages = Ops.add(@updated_packages, 1)

          if Mode.normal
            @updated_packages_list = Builtins.add(
              @updated_packages_list,
              pkg_name
            )
          end
        else
          @installed_packages = Ops.add(@installed_packages, 1)

          if Mode.normal
            @installed_packages_list = Builtins.add(
              @installed_packages_list,
              pkg_name
            )
          end
        end

        @total_installed = Ops.add(@total_installed, pkg_size)
      else
        @removed_packages += 1

        @removed_packages_list << pkg_name if Mode.normal
      end

      nil
    end

    # package start display update
    # - this is called at the beginning of a new package
    #
    # @param [String] pkg_name    package name
    # @param [String] pkg_location  full path to a package
    # @param [String] _pkg_summary  package summary (short description)
    # @param [Integer] pkg_size    package size in bytes
    # @param [Boolean] deleting    Flag: deleting (true) or installing (false) package?
    #
    def SlideDisplayStart(pkg_name, pkg_location, _pkg_summary, pkg_size, deleting)
      @updating = Pkg.PkgInstalled(pkg_name) if !deleting
      # Update global progress bar
      DisplayGlobalProgress()

      nil
    end

    def SlideGenericProvideStart(pkg_name, size, pattern, remote)
    end

    def SlideDeltaApplyStart(pkg_name)
      nil
    end

    # Package providal start
    def SlideProvideStart(pkg_name, size, remote)
      nil
    end

    publish variable: :total_size_to_install, type: "integer" # Used in installation client
    publish function: :GetPackageSummary, type: "map <string, any> ()"
    publish function: :InitPkgData, type: "void (boolean)"
    publish function: :SetCurrentCdNo, type: "void (integer, integer)"
    publish function: :UpdateCurrentPackageProgress, type: "void (integer)"
    publish function: :UpdateCurrentPackageRateProgress, type: "void (integer, integer, integer)"
    publish function: :DisplayGlobalProgress, type: "void ()"
    publish function: :DoneProvide, type: "void (integer, string, string)"
    publish function: :UpdateAllCdProgress, type: "void (boolean)"
    publish function: :SlideDisplayDone, type: "void (string, integer, boolean)"
    publish function: :SlideDisplayStart, type: "void (string, string, string, integer, boolean)"
    publish function: :SlideGenericProvideStart, type: "void (string, integer, string, boolean)"
    publish function: :SlideDeltaApplyStart, type: "void (string)"
    publish function: :SlideProvideStart, type: "void (string, integer, boolean)"
  end

  PackageSlideShow = PackageSlideShowClass.new
  PackageSlideShow.main
end
