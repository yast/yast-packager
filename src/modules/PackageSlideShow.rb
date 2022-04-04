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
      Yast.import "Packages"

      init_member_vars
    end

    def init_member_vars
      @init_pkg_data_complete = false

      @total_pkgs_to_install = 0
      @total_size_to_install = 0 # directly accessed in one click installer :-(
      @total_installed_size = 0
      @expected_total_download_size = 0
      @finished_total_download_size = 0

      @active_downloads = 0 # Number of pkg downloads currently going on
      @detected_parallel_download = false

      # Those @current_download_pkg_... variables keep track of the most recent
      # current download. Avoid using them if parallel downloads are in effect.

      @current_download_pkg_size = 0 # RPM size, not installed size
      @current_download_pkg_percent = 0
      @current_download_pkg_name = ""

      # Lists of package names that were installed / updated / removed
      # (after that operation is finished)

      @installed_pkg_list = []
      @updated_pkg_list = []
      @removed_pkg_list = []

      # This is a kludge to pass information from one callback that gets the
      # needed information (the pkg name) to another that doesn't.
      @updating = false
      nil
    end

    def ResetPackageSummary
      init_member_vars
      nil
    end

    def GetPackageSummary
      {
        "installed"        => @installed_pkg_list.size,
        "updated"          => @updated_pkg_list.size,
        "removed"          => @removed_pkg_list.size,
        "installed_list"   => @installed_pkg_list,
        "updated_list"     => @updated_pkg_list,
        "removed_list"     => @removed_pkg_list,
        "downloaded_bytes" => @finished_total_download_size,
        "installed_bytes"  => @total_installed_size
      }
    end

    # Sum up all list items. It flattens the list and also skips all negative values.
    #
    # @param sizes [Array<Fixnum|Array>] Sizes to sum
    # @return [Fixnum] Sizes sum
    def ListSum(sizes)
      sizes.flatten.select(&:positive?).reduce(0, :+)
    end

    # The total size in bytes to install.
    def TotalSizeToInstall
      @total_size_to_install
    end

    # The current size in bytes that is already installed.
    def TotalInstalledSize
      @total_installed_size
    end

    # Format number of remaining bytes to be installed as string.
    # @param [Fixnum] remaining    bytes remaining, -1 for 'done'
    # @return [String] human readable remaining time or byte / kB/ MB size
    #
    def FormatRemainingSize(remaining)
      if remaining < 0
        # Nothing more to install from this CD (very concise - little space!!)
        return _("Done.")
      end
      return "" if remaining.zero?

      String.FormatSize(remaining)
    end

    # Format number of remaining packages to be installed as string.
    # @param [Fixnum] remaining    bytes remaining, -1 for 'done'
    # @return [String] human readable remaining time or byte / kB/ MB size
    #
    def FormatRemainingCount(remaining)
      if remaining < 0
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

      total_sizes_per_cd_per_src = Pkg.PkgMediaSizes
      total_pkg_count_per_cd_per_src = Pkg.PkgMediaCount

      @total_size_to_install = ListSum(total_sizes_per_cd_per_src)
      @total_pkgs_to_install = ListSum(total_pkg_count_per_cd_per_src)
      @expected_total_download_size = Packages.CountSizeToBeDownloaded
      @init_pkg_data_complete = true

      log.info "Total size to install: #{String.FormatSize(@total_size_to_install)}"
      log.info "Expected download size: #{String.FormatSize(@expected_total_download_size)}"
      log.info "Parallel download (initial): #{parallel_download?}"
      nil
    end

    # Check if package are downloaded in parallel to being installed.
    def parallel_download?
      # Did the callbacks here clearly detect parallel operation?
      return true if @detected_parallel_download

      # Use heuristics based on installation modes
      #
      # 15.4: Not in the installed system, only during system installation
      # (and upgrade / autoinstallation (?)).
      !Mode.normal
    end

    # Update the overall progress value of the progress bar.
    #
    # If libzypp is downloading and installing in parallel, keep this simple
    # and only use the installed package size for the total vs. the current
    # progress, disregarding the download size since the downloads are not
    # causing additional delays.
    #
    # Otherwise, take the download into account so the progress bar doesn't
    # appear to be stuck at zero while libzypp downloads a whole lot of
    # packages and waits for that to finish before starting installing any of
    # them.
    #
    # In that case, use the download size plus the installed (unpacked) package
    # size for the total vs. the current progress.
    #
    # Caveat 1: Of course the time to download a package cannot really be
    # compared to the time it takes to install it after it is downloaded; it
    # depends on the network (Internet or LAN) speed. It may be slower, or it
    # may even be faster than installing the package.
    #
    # This progress reporting is not meant to be an accurate prediction of the
    # remaining time; that would only be wild guessing anyway since network
    # operations with wildly unpredictable time behavior are involved.
    #
    # Caveat 2: Only real downloads are considered, not getting packages that
    # are directly available from a local repo (installation media or local
    # directories) since that causes no noticeable delay, so it's irrelevant
    # for progress reporting.
    #
    def UpdateTotalProgressValue
      total_size = @total_size_to_install
      total_size += @expected_total_download_size unless parallel_download?

      if total_size.zero? # Prevent division by zero
        total_progress = 100 # Nothing to install. Should not happen.
      else
        current = TotalInstalledSize()
        current += CurrentDownloadSize() unless parallel_download?
        log.debug "Current: #{String.FormatSize(current)} of #{String.FormatSize(total_size)}"
        total_progress = 100.0 * current / total_size
      end

      log.debug "Total progress: #{total_progress.round(2)}%"
      SlideShow.StageProgress(total_progress.round, nil)
    end

    # Calculate the size of the current downloads from finished downloads and
    # the percentage of the current download.
    #
    # A partial download of the current package is relevant if there are only
    # very few packages to download, or if the current one is very large in
    # comparison to the total expected download; which is a common scenario in
    # the installed system (e.g. kernel updates).
    #
    def CurrentDownloadSize
      current_pkg = @current_download_pkg_size * @current_download_pkg_percent / 100
      @finished_total_download_size + current_pkg
    end

    # Update progress widgets
    #
    def UpdateTotalProgress(_silent_check)
      # update the overall progress value (download + installation)
      UpdateTotalProgressValue()
    end

    # @deprecated Misleading method name. For API backwards compatibility.
    #
    def DisplayGlobalProgress
      log.warn "DEPRECATED. Use UpdateTotalProgressText() instead."
      UpdateTotalProgressText()
    end

    # Update the total progress text (not the value!).
    #
    def UpdateTotalProgressText
      if @active_downloads > 0 && !parallel_download?
        UpdateDownloadProgressText()
      else
        UpdateInstallationProgressText()
      end
    end

    # Update the total progress text for downloading.
    # This should only be used if parallel download + installation is not in effect.
    #
    def UpdateDownloadProgressText
      SlideShow.SetGlobalProgressLabel(
        _("Downloading...") +
        Builtins.sformat(
          # TRANSLATORS: This is about a remaining download size.
          # %1 is the remaining size with a unit (kiB, MiB, GiB etc.),
          # %2 the total download size, also with a unit.
          _(" (Remaining: %1 of %2)"),
          String.FormatSize(@expected_total_download_size - CurrentDownloadSize()),
          String.FormatSize(@expected_total_download_size)
        )
      )

      nil
    end

    # Update the total progress text for installing / updating / removing
    # packages; or, for parallel download + installation, also for downloading.
    #
    def UpdateInstallationProgressText
      installed_pkg = @installed_pkg_list.size
      updated_pkg = @updated_pkg_list.size
      remaining_string = FormatRemainingSize(@total_size_to_install - @total_installed_size)
      remaining_string += ", " unless remaining_string.empty?

      SlideShow.SetGlobalProgressLabel(
        SlideShow.CurrentStageDescription +
        Builtins.sformat(
          _(" (Remaining: %1%2 packages)"),
          remaining_string,
          @total_pkgs_to_install - installed_pkg - updated_pkg
        )
      )

      nil
    end

    # Notification when download of a package starts
    def DownloadStart(pkg_name, download_size)
      @active_downloads += 1
      log.info "Starting download of #{pkg_name} (#{String.FormatSize(download_size)})"
      log.info "active downloads: #{@active_downloads}" if @active_downloads > 1
      @current_download_pkg_name = pkg_name
      @current_download_pkg_size = download_size
      @current_download_pkg_percent = 0
      return if parallel_download?

      # Update the progress text since it may change from "Installing..." to
      # "Downloading...".
      UpdateTotalProgressText()
      UpdateTotalProgressValue()
      nil
    end

    # Update the download progress for the current package
    def DownloadProgress(pkg_percent)
      log.debug "#{@current_download_pkg_name}: #{pkg_percent}%"
      @current_download_pkg_percent = pkg_percent
      return if parallel_download?

      UpdateTotalProgressValue()
      nil
    end

    # Notification when download of a package is finished
    def DownloadEnd(pkg_name)
      log.info "Downloading #{pkg_name} finished"
      return if parallel_download?

      CurrentDownloadFinished()
      UpdateTotalProgressValue()
      nil
    end

    # Notification about a download error
    #
    # @param [Integer] error   Numeric error code
    # @param [String]  reason
    # @param [String]  pkg_name
    def DownloadError(error, reason, pkg_name)
      log.error "Download error #{error} for #{pkg_name}: #{reason}"
      return if parallel_download?

      CurrentDownloadFinished()
      UpdateTotalProgressValue()
      nil
    end

    # Finalize the sums for the current download
    def CurrentDownloadFinished
      @active_downloads -= 1 if @active_downloads > 0
      @finished_total_download_size += @current_download_pkg_size
      @current_download_pkg_size = 0
      @current_download_pkg_percent = 0
      @current_download_pkg_name = ""
    end

    # Notification that a package starts being installed, updated or removed.
    # Not to be confused with DownloadStart.
    #
    # @param [String]  pkg_name      package name
    # @param [String]  _pkg_location full path to a package
    # @param [String]  _pkg_summary  package summary (short description)
    # @param [Integer] _pkg_size     installed package size in bytes
    # @param [Boolean] deleting      Flag: deleting (true) or installing (false) package?
    #
    def PkgInstallStart(pkg_name, _pkg_location, _pkg_summary, _pkg_size, deleting)
      if @active_downloads > 0 && !@detected_parallel_download
        @detected_parallel_download = true
        log.info "Detected parallel download and installation"
      end

      @updating = Pkg.PkgInstalled(pkg_name) unless deleting
      UpdateTotalProgressText()

      # Don't update the progress value since it cannot have changed right now:
      # Only fully installed packages are taken into account, and this one has
      # just begun.

      nil
    end

    # Progress notification while a package is finished being installed, updated or removed.
    #
    # @param [Integer] _pkg_percent percent of progress of this package
    #
    def PkgInstallProgress(_pkg_percent)
      # For future use and to mirror the callbacks one call level above
      # (SlideShowCallbacks).
      #
      # Right now, not doing anything here since we only take the fully
      # installed packages into account for progress reporting.
      nil
    end

    # Notification that a package is finished being installed, updated or removed.
    #
    # @param [String] pkg_name    package name
    # @param [String] pkg_size    package size in bytes
    # @param [Boolean] deleting   Flag: deleting (true) or installing (false) package
    #
    def PkgInstallDone(pkg_name, pkg_size, deleting)
      if deleting
        @removed_pkg_list << pkg_name if Mode.normal
        log.info "Uninstalled package #{pkg_name}"
      else # installing or updating
        @total_installed_size += pkg_size

        UpdateTotalProgressValue()
        UpdateTotalProgressText()

        if @updating
          @updated_pkg_list << pkg_name if Mode.normal
          log.info "Updated package #{pkg_name}"
        else
          @installed_pkg_list << pkg_name if Mode.normal
          log.info "Installed package #{pkg_name}"
        end
      end

      nil
    end

    # rubocop:disable Layout/LineLength
    #
    publish variable: :total_size_to_install, type: "integer" # Deprecated; used in one click installer
    publish function: :TotalSizeToInstall, type: "integer ()" # Better substitute for the above
    publish function: :GetPackageSummary, type: "map <string, any> ()"
    publish function: :InitPkgData, type: "void (boolean)"
    publish function: :DisplayGlobalProgress, type: "void ()" # Deprecated
    publish function: :UpdateTotalProgressText, type: "void ()" # Better substitute for the above
    publish function: :DownloadStart, type: "void (string, integer)"
    publish function: :DownloadProgress, type: "void (integer)"
    publish function: :DownloadEnd, type: "void (string)"
    publish function: :DownloadError, type: "void (integer, string, string)"
    publish function: :PkgInstallStart, type: "void (string, integer, string, boolean)"
    publish function: :PkgInstallProgress, type: "void (integer)"
    publish function: :PkgInstallDone, type: "void (string, integer, boolean)"
    #
    # rubocop:enable Layout/LineLength
  end

  PackageSlideShow = PackageSlideShowClass.new
  PackageSlideShow.main
end
