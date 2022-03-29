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

      @total_installed_size = 0
      @total_size_to_install = 0 # also used in one click installer
      @expected_total_download_size = 0
      @finished_total_download_size = 0
      @current_pkg_download_size = 0
      @current_pkg_download_percent = 0
      @current_pkg_name = ""
      @active_downloads = 0
      @detected_parallel_download = false

      @installed_pkg_list = []
      @updated_pkg_list = []
      @removed_pkg_list = []

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

      log.info "Total size to install: #{@total_size_to_install}"
      log.info "Expected total download size: #{@expected_total_download_size}"
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
    # and only use the installed package size for both the total and the
    # current progress, disregarding the download size since the downloads are
    # not causing additional delays.
    #
    # Otherwise, take the download into account so the progress bar doesn't
    # appear to be stuck at zero while libzypp downloads a whole lot of
    # packages and waits for that to finish before starting installing any of
    # them.
    #
    # In that case, use the download size plus the installed (unpacked) package
    # size for both the total and the current progress.
    #
    # Caveat 1: Of course the time to download a package cannot really be
    # compared to the time it takes to install it after it is downloaded; it
    # depends on the network (Internet or LAN) speed. Normally, the download
    # takes longer than the installation. But that only means that the progress
    # will speed up once the download phase is over. If that surprises the
    # user, it will be a pleasant surprise, not an annoyance (which it would be
    # if it would slow down).
    #
    # This progress reporting is not meant to be a prediction of remaining time
    # (much less an accurate one); that would only be wild guessing whenever
    # network operations are involved.
    #
    # Caveat 2: Only real downloads are considered, not using packages that are
    # directly available from a local repo (installation media or local
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
        log.debug "Current: #{current} of #{total_size}"
        total_progress = (100.0 * current / total_size).round
      end

      log.info "Total progress: #{total_progress}%"
      SlideShow.StageProgress(total_progress, nil)
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
      current_pkg = @current_pkg_download_size * @current_pkg_download_percent / 100
      @finished_total_download_size + current_pkg
    end

    # Update progress widgets
    #
    def UpdateTotalProgress(_silent_check)
      # update the overall progress value (download + installation)
      UpdateTotalProgressValue()
    end

    # For backwards compatibility:
    # Update the total progress text.
    def DisplayGlobalProgress
      UpdateTotalProgressText()
    end

    # Update the total progress text (not the value!).
    #
    def UpdateTotalProgressText
      action =
        if @active_downloads > 0 && !parallel_download?
          _("Downloading...")
        else
          SlideShow.CurrentStageDescription
        end

      installed_pkg = @installed_pkg_list.size
      updated_pkg = @updated_pkg_list.size
      remaining_string = FormatRemainingSize(@total_size_to_install - @total_installed_size)
      remaining_string += ", " unless remaining_string.empty?

      SlideShow.SetGlobalProgressLabel(
        action +
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
      log.info "DownloadStart #{pkg_name} size: #{download_size}"
      log.info "active downloads: #{@active_downloads}" if @active_downloads > 1
      @current_pkg_name = pkg_name
      @current_pkg_download_size = download_size
      @current_pkg_download_percent = 0
      return if parallel_download?

      # Update the progress text since it may change from "Installing..." to
      # "Downloading...".
      UpdateTotalProgressText()
      UpdateTotalProgressValue()
      nil
    end

    # Update the download progress for the current package
    def DownloadProgress(pkg_percent)
      log.info "#{@current_pkg_name}: #{pkg_percent}%"
      @current_pkg_download_percent = pkg_percent
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
      @finished_total_download_size += @current_pkg_download_size
      @current_pkg_download_size = 0
      @current_pkg_download_percent = 0
      @current_pkg_name = ""
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
      # Not doing anything here since we only take the fully installed packages
      # into account for progress reporting.
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
      else # installing or updating
        @total_installed_size += pkg_size

        UpdateTotalProgressValue()
        UpdateTotalProgressText()

        if Mode.normal
          if @updating
            @updated_pkg_list << pkg_name
          else
            @installed_pkg_list << pkg_name
          end
        end
      end

      nil
    end

    publish variable: :total_size_to_install, type: "integer" # Used in one click installer client
    publish function: :TotalSizeToInstall, type: "integer ()" # Better substitute for the above
    publish function: :GetPackageSummary, type: "map <string, any> ()"
    publish function: :InitPkgData, type: "void (boolean)"
    publish function: :DisplayGlobalProgress, type: "void ()"
    publish function: :DownloadStart, type: "void (string, integer)"
    publish function: :DownloadProgress, type: "void (integer)"
    publish function: :DownloadEnd, type: "void (string)"
    publish function: :DownloadError, type: "void (integer, string, string)"
    publish function: :PkgInstallStart, type: "void (string, integer, string, boolean)"
    publish function: :PkgInstallProgress, type: "void (integer)"
    publish function: :PkgInstallDone, type: "void (string, integer, boolean)"
  end

  PackageSlideShow = PackageSlideShowClass.new
  PackageSlideShow.main
end
