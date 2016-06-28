# encoding: utf-8

# Module:		PackageSlideShow.ycp
#
# Purpose:		Module to access slides from installation repository
#
# Author:		Stefan Hundhammer <sh@suse.de>
#                      Stanislav Visnovsky <visnov@suse.cz>
#
require "yast"

module Yast
  class PackageSlideShowClass < Module
    include Yast::Logger

    # seconds to cut off predicted time
    MAX_TIME_PER_CD = 7200

    # minimum time displayed per CD if there is something to install
    MIN_TIME_PER_CD = 5

    # Column index for refreshing statistics: remaining size
    SIZE_COLUMN_POSITION = 1
    # Column index for refreshing statistics: remaining number of packages
    PKG_COUNT_COLUMN_POSITION = 2
    # Column index for refreshing statistics: remaining time
    TIME_COLUMN_POSITION = 3

    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "packager"

      Yast.import "Slides"
      Yast.import "SlideShow"
      Yast.import "String"
      Yast.import "Mode"
      Yast.import "URL"
      Yast.import "Installation"

      @total_sizes_per_cd_per_src = [] # total sizes per inst-src: [ [42, 43, 44], [12, 13, 14] ]
      @remaining_sizes_per_cd_per_src = [] # remaining sizes
      @remaining_times_per_cd_per_src = [] # remaining times
      @inst_src_names = [] # a list of strings identifying each repository
      @total_pkg_count_per_cd_per_src = [] # number of pkgs per inst-src: [ [7, 5, 3], [2, 3, 4] ]
      @remaining_pkg_count_per_cd_per_src = [] # remaining number of pkgs
      @srcid_to_current_src_no = {}
      # the string is follwed by a media number, e.g. "Medium 1"
      @media_type = _("Medium %1")
      @total_size_installed = 0
      @total_size_to_install = 0
      @total_count_to_download = 0
      @total_count_downloaded = 0
      @downloading_pct = 0

      @current_src_no = -1 # 1..n
      @current_cd_no = -1 # 1..n
      @next_src_no = -1
      @next_cd_no = -1
      @last_cd = false
      @total_cd_count = 0
      @unit_is_seconds = false # begin with package sizes
      @bytes_per_second = 1
      @init_pkg_data_complete = false

      @debug = false # more debugging info
      @provide_name = "" # currently downlaoded package name
      @provide_size = "" # currently downlaoded package size

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
      #    integer avg_download_rate = 0;

      @current_provide_size = 0
      @current_install_size = 0
      @updating = false
    end

    def ResetPackageSummary
      @installed_packages = 0
      @updated_packages = 0
      @removed_packages = 0
      @total_downloaded = 0
      @total_installed = 0
      #	avg_download_rate = 0;

      @installed_packages_list = []
      @updated_packages_list = []
      @removed_packages_list = []

      # temporary values
      @current_provide_size = 0
      @current_install_size = 0
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


    #***************************************************************************
    #**************  Formatting functions and helpers **************************
    #***************************************************************************

    # Sum up all list items
    #
    def ListSum(sizes)
      sizes.each_with_object(0) do |i, r|
        next if i == -1
        r += i
      end
    end

    # Sum up all positive list items, but cut off individual items at a maximum value.
    # Negative return values indicate overflow of any individual item at "max_cutoff".
    # In this case, the absolute value of the return value is "max_cutoff" * number of overflows.
    # (e.g. >2hour + >2hours + 1:13:20 => >4hours
    #
    def ListSumCutOff(sizes, max_cutoff)
      sizes = deep_copy(sizes)
      overflow = 0
      sum = 0

      Builtins.foreach(sizes) do |item|
        if Ops.greater_than(item, 0)
          if Ops.greater_than(item, max_cutoff)
            overflow = Ops.add(overflow, 1)
          else
            sum = Ops.add(sum, item)
          end
        end
      end

      if Ops.greater_than(overflow, 0)
        sum = Ops.multiply(Ops.unary_minus(overflow), max_cutoff)
      end

      sum
    end


    def TotalRemainingSize
      ListSum(Builtins.flatten(@remaining_sizes_per_cd_per_src))
    end


    def TotalRemainingTime
      ListSumCutOff(
        Builtins.flatten(@remaining_times_per_cd_per_src),
        MAX_TIME_PER_CD
      )
    end


    def TotalRemainingPkgCount
      ListSum(Builtins.flatten(@remaining_pkg_count_per_cd_per_src))
    end


    def TotalInstalledSize
      Ops.subtract(@total_size_to_install, TotalRemainingSize())
    end

    # Format an integer seconds value with min:sec or hours:min:sec
    #
    # Negative values are interpreted as overflow - ">" is prepended and the
    # absolute value is used.
    #
    def FormatTimeShowOverflow(seconds)
      text = ""

      if Ops.less_than(seconds, 0) # Overflow (indicated by negative value)
        # When data throughput goes downhill (stalled network connection etc.),
        # cut off the predicted time at a reasonable maximum.
        # "%1" is a predefined maximum time.

        text = Builtins.sformat(
          _(">%1"),
          String.FormatTime(Ops.unary_minus(seconds))
        )
      else
        text = String.FormatTime(seconds)
      end

      text
    end


    # Format number of remaining bytes to be installed as string.
    # @param [Fixnum] remaining		bytes remaining, -1 for 'done'
    # @return			[String] human readable remaining time or byte / kB/ MB size
    #
    def FormatRemainingSize(remaining)
      if Ops.less_than(remaining, 0)
        # Nothing more to install from this CD (very concise - little space!!)
        return _("Done.")
      end
      return "" if remaining == 0

      String.FormatSize(remaining)
    end


    # Format number of remaining packages to be installed as string.
    # @param [Fixnum] remaining		bytes remaining, -1 for 'done'
    # @return			[String] human readable remaining time or byte / kB/ MB size
    #
    def FormatRemainingCount(remaining)
      if Ops.less_than(remaining, 0)
        # Nothing more to install from this CD (very concise - little space!!)
        return _("Done.")
      end
      return "" if remaining == 0

      Builtins.sformat("%1", remaining)
    end


    def FormatNextMedia
      text = ""

      if Ops.greater_or_equal(@next_src_no, 0) &&
          Ops.greater_or_equal(@next_cd_no, 0)
        next_media_name = Builtins.sformat(
          "%1 %2",
          Ops.get(@inst_src_names, @next_src_no, ""),
          Builtins.sformat(@media_type, Ops.add(@next_cd_no, 1))
        )

        if @unit_is_seconds
          # Status line informing about the next CD that will be used
          # %1: Media type ("CD" / "DVD", ???)
          # %2: Media name ("SuSE Linux Professional CD 2" )
          # %3: Time remaining until this media will be needed
          text = Builtins.sformat(
            _("Next: %1 -- %2"),
            next_media_name,
            String.FormatTime(
              Ops.get(
                @remaining_times_per_cd_per_src,
                [
                  Ops.subtract(@current_src_no, 1),
                  Ops.subtract(@current_cd_no, 1)
                ],
                1
              )
            )
          )
        else
          # Status line informing about the next CD that will be used
          # %1: Media type ("CD" / "DVD", ???)
          # %2: Media name ("SuSE Linux Professional CD 2" )
          text = Builtins.sformat(_("Next: %1"), next_media_name)
        end
      end

      text
    end

    #***************************************************************************
    #**********************  Computing Helpers *********************************
    #***************************************************************************


    # Perform sanity check for correct initialzation etc.
    # @param [Boolean] silent	don't complain in log file
    # @return		true if OK, false if any error
    #
    def SanityCheck(silent)
      return true # FIXME!
      if !@init_pkg_data_complete
        if !silent
          Builtins.y2error(
            "PackageSlideShow::SanityCheck(): Slide show not correctly initialized: " +
              "PackageSlideShow::InitPkgData() never called!"
          )
        end
        return false
      end

      if Ops.less_than(@current_src_no, 1) || Ops.less_than(@current_cd_no, 1)
        # nothing to install but something is going to be deleted, so it's OK
        if Pkg.IsAnyResolvable(:package, :to_remove)
          return true
        elsif !silent
          Builtins.y2error(
            -1,
            "PackageSlideShow::SanityCheck(): Illegal values for current_src_no (%1) or current_cd_no (%2)",
            @current_src_no,
            @current_cd_no
          )
          Builtins.y2milestone("total sizes: %1", @total_sizes_per_cd_per_src)
        end
        return false
      end

      true
    end

    # Update internal bookkeeping: subtract size of one package from the
    # global list of remaining sizes per CD
    #
    def SubtractPackageSize(pkg_size)
      remaining = Ops.get(
        @remaining_sizes_per_cd_per_src,
        [Ops.subtract(@current_src_no, 1), Ops.subtract(@current_cd_no, 1)],
        1
      )
      remaining = Ops.subtract(remaining, pkg_size)
      @total_size_installed = Ops.add(@total_size_installed, pkg_size)

      if Ops.less_or_equal(remaining, 0)
        # -1 is the indicator for "done with this CD" - not to be
        # confused with 0 for "nothing to install from this CD".
        remaining = -1
      end

      Ops.set(
        @remaining_sizes_per_cd_per_src,
        [Ops.subtract(@current_src_no, 1), Ops.subtract(@current_cd_no, 1)],
        remaining
      )
      Ops.set(
        @remaining_pkg_count_per_cd_per_src,
        [Ops.subtract(@current_src_no, 1), Ops.subtract(@current_cd_no, 1)],
        Ops.subtract(
          Ops.get(
            @remaining_pkg_count_per_cd_per_src,
            [Ops.subtract(@current_src_no, 1), Ops.subtract(@current_cd_no, 1)],
            0
          ),
          1
        )
      )

      if @unit_is_seconds
        seconds = 0

        if Ops.greater_than(remaining, 0) &&
            Ops.greater_than(@bytes_per_second, 0)
          seconds = Ops.divide(remaining, @bytes_per_second)
        end

        seconds = MIN_TIME_PER_CD if seconds < MIN_TIME_PER_CD
        log.debug "Updating remaining time for source #{@current_src_no} " \
          "(medium #{@current_cd_no}): #{seconds}"
        Ops.set(
          @remaining_times_per_cd_per_src,
          [Ops.subtract(@current_src_no, 1), Ops.subtract(@current_cd_no, 1)],
          seconds
        )
      end

      if @debug
        Builtins.y2milestone(
          "SubtractPackageSize( %1 ) -> %2",
          pkg_size,
          @remaining_sizes_per_cd_per_src
        )
      end

      nil
    end

    def packages_to_download(src_mapping)
      src_mapping = deep_copy(src_mapping)
      # src_mapping contains only enabled repos, get indices of the enabled repos here
      # and remap enabled index to the global repo ID
      enabled_sources = Pkg.SourceGetCurrent(true)

      Builtins.y2milestone("Packages to download input: %1", src_mapping)

      ret = 0

      i = 0
      Builtins.foreach(src_mapping) do |media_mapping|
        if Ops.greater_than(Builtins.size(media_mapping), 0)
          # check if the repository is remote
          repo_url = Ops.get_string(
            Pkg.SourceGeneralData(Ops.get(enabled_sources, i, -1)),
            "url",
            ""
          )
          repo_schema = Builtins.tolower(
            Ops.get_string(URL.Parse(repo_url), "scheme", "")
          )

          # iso repos get also downloaded according to experience; the addition is not a perfect
          # fix, but still improves the progress (bnc#724486)
          if Builtins.contains(["http", "https", "ftp", "sftp", "iso"], repo_schema)
            total = 0
            Builtins.foreach(media_mapping) do |count|
              total = Ops.add(total, count)
            end


            Builtins.y2milestone(
              "Downloading %1 packages from remote repository %2",
              total,
              Ops.get(enabled_sources, i, -1)
            )
            ret = Ops.add(ret, total)
          end
        end
        i = Ops.add(i, 1)
      end


      Builtins.y2milestone("Total number of packages to download: %1", ret)

      ret
    end

    def packages_to_install(src_mapping)
      src_mapping = deep_copy(src_mapping)
      ret = ListSum(Builtins.flatten(src_mapping))
      Builtins.y2milestone("Total number of packages to install: %1", ret)
      ret
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
      #total_time_elapsed	= 0;
      #start_time		= -1;
      @current_src_no = -1 # 1..n
      @current_cd_no = -1 # 1..n
      @next_src_no = -1
      @next_cd_no = -1
      @last_cd = false
      @unit_is_seconds = false # begin with package sizes
      @bytes_per_second = 1

      src_list = Pkg.PkgMediaNames
      @inst_src_names = Builtins.maplist(src_list) do |src|
        Ops.get_string(src, 0, "CD")
      end

      Builtins.y2milestone("Media names: %1", @inst_src_names)

      index = 0

      @srcid_to_current_src_no = Builtins.listmap(src_list) do |src|
        index = Ops.add(index, 1)
        { Ops.get_integer(src, 1, -1) => index }
      end

      Builtins.y2milestone(
        "Repository  mapping information: %1",
        @srcid_to_current_src_no
      )

      @total_sizes_per_cd_per_src = Pkg.PkgMediaSizes
      @total_pkg_count_per_cd_per_src = Pkg.PkgMediaCount


      @total_size_to_install = ListSum(
        Builtins.flatten(@total_sizes_per_cd_per_src)
      )
      Builtins.y2milestone("total_size_to_install: %1", @total_size_to_install)
      @remaining_sizes_per_cd_per_src = Builtins.eval(
        @total_sizes_per_cd_per_src
      )
      @remaining_pkg_count_per_cd_per_src = Builtins.eval(
        @total_pkg_count_per_cd_per_src
      )
      @total_cd_count = Builtins.size(
        Builtins.flatten(@total_sizes_per_cd_per_src)
      )
      @total_count_to_download = packages_to_download(
        @total_pkg_count_per_cd_per_src
      )
      @total_count_downloaded = 0
      total_count_to_install = packages_to_install(
        @total_pkg_count_per_cd_per_src
      )
      total = Ops.add(total_count_to_install, @total_count_to_download)
      @downloading_pct = Ops.divide(
        Ops.multiply(total == 0 ? 0 : 100, @total_count_to_download),
        total
      )
      @init_pkg_data_complete = true

      # reset the history log
      SlideShow.inst_log = ""

      Builtins.y2milestone(
        "PackageSlideShow::InitPkgData() done; total_sizes_per_cd_per_src: %1",
        @total_sizes_per_cd_per_src
      )
      Builtins.y2milestone(
        "PackageSlideShow::InitPkgData(): pkg: %1",
        @total_pkg_count_per_cd_per_src
      )

      # RebuildDialog(true);

      nil
    end

    # Try to figure out what media will be needed next
    # and set next_src_no and next_cd_no accordingly.
    #
    def FindNextMedia
      # Normally we would have to use current_cd_no+1,
      # but since this uses 1..n and we need 0..n-1
      # for array subscripts anyway, use it as it is.
      @next_cd_no = @current_cd_no
      @next_src_no = Ops.subtract(@current_src_no, 1)
      @last_cd = false

      while Ops.less_than(
          @next_src_no,
          Builtins.size(@remaining_sizes_per_cd_per_src)
        )
        remaining_sizes = Ops.get(
          @remaining_sizes_per_cd_per_src,
          @next_src_no,
          []
        )

        while Ops.less_than(@next_cd_no, Builtins.size(remaining_sizes))
          if Ops.greater_than(Ops.get(remaining_sizes, @next_cd_no, 0), 0)
            if @debug
              Builtins.y2milestone(
                "Next media: src: %1 CD: %2",
                @next_src_no,
                @next_cd_no
              )
            end
            return
          else
            @next_cd_no = Ops.add(@next_cd_no, 1)
          end
        end

        @next_src_no = Ops.add(@next_src_no, 1)
      end

      Builtins.y2milestone("No next media - all done") if @debug

      @next_src_no = -1
      @next_cd_no = -1
      @last_cd = true

      nil
    end


    # Set the current repository and CD number. Must be called for each CD change.
    # src_no: 1...n
    # cd_no:  1...n
    #
    def SetCurrentCdNo(src_no, cd_no)
      if cd_no == 0
        Builtins.y2milestone("medium number 0, using medium number 1")
        cd_no = 1
      end

      Builtins.y2milestone("SetCurrentCdNo() - src: %1 , CD: %2", src_no, cd_no)
      @current_src_no = Ops.get(@srcid_to_current_src_no, src_no, -1)
      @current_cd_no = cd_no

      SlideShow.CheckForSlides
      FindNextMedia()

      if Slides.HaveSlides && Slides.HaveSlideSupport
        if !SlideShow.HaveSlideWidget
          SlideShow.RebuildDialog

          SlideShow.SwitchToDetailsView if SlideShow.user_switched_to_details
        end

        if !SlideShow.user_switched_to_details # Don't override explicit user request!
          SlideShow.SwitchToSlideView
        end
      else
        SlideShow.RebuildDialog if !SlideShow.ShowingDetails
      end

      nil
    end



    # Recalculate remaining times per CD based on package sizes remaining
    # and data rate so far. Recalculation is only done each 'recalc_interval'
    # seconds unless 'force_recalc' is set to 'true'.
    #
    # @param [Boolean] force_recalc force recalculation even if timeout not reached yet
    # @return true if recalculated, false if not
    #
    def RecalcRemainingTimes(force_recalc)
      if !force_recalc && ::Time.now.to_i < SlideShow.next_recalc_time
        # Nothing to do (yet) - simply return
        return false
      end

      elapsed = SlideShow.total_time_elapsed

      if SlideShow.start_time >= 0
        elapsed += ::Time.now.to_i - SlideShow.start_time
      end

      if elapsed == 0
        # Called too early - no calculation possible yet.
        # This happens regularly during initialization, so an error
        # message wouldn't be a good idea here.

        return false
      end

      # This is the real thing.

      real_bytes_per_second = @total_size_installed.to_f / elapsed

      # But this turns out to be way to optimistic - RPM gets slower and
      # slower while installing. So let's add some safety margin to make
      # sure initial estimates are on the pessimistic side - the
      # installation being faster than initially estimated will be a
      # pleasant surprise to the user. Most users don't like it the other
      # way round.
      #
      # The "pessimistic factor" progressively decreases as the installation
      # proceeds.  It begins with about 1.7, i.e. the data transfer rate is
      # halved to what it looks like initially. It decreases to 1.0 towards
      # the end.

      pessimistic_factor = 1.0

      if @total_size_to_install > 0
        pessimistic_factor = 1.7 - @total_size_installed.to_f / @total_size_to_install
      end

      @bytes_per_second = (real_bytes_per_second / pessimistic_factor + 1).floor

      @remaining_times_per_cd_per_src = []

      # Recalculate remaining times for the individual CDs

      Builtins.foreach(@remaining_sizes_per_cd_per_src) do |remaining_sizes_list|
        remaining_times_list = []
        remaining_time = -1

        remaining_sizes_list.each do |remaining_size|
          remaining_time = remaining_size

          if remaining_size > 0
            remaining_time = (remaining_size.to_f / @bytes_per_second).round

            if remaining_time < MIN_TIME_PER_CD
              # It takes at least this long for the CD drive to spin up and
              # for RPM to do _anything_. Times below this values are
              # ridiculously unrealistic.
              remaining_time = MIN_TIME_PER_CD
            elsif remaining_time > MAX_TIME_PER_CD # clip off at 2 hours
              # When data throughput goes downhill (stalled network connection etc.),
              # cut off the predicted time at a reasonable maximum.
              remaining_time = MAX_TIME_PER_CD
            end
          end

          remaining_times_list << remaining_time
        end

        @remaining_times_per_cd_per_src << remaining_times_list
        log.debug "Recalculated remaining time: #{@remaining_times_per_cd_per_src}"
      end

      SlideShow.next_recalc_time = ::Time.now.to_i + SlideShow.recalc_interval

      true
    end

    # Switch unit to seconds if necessary and recalc everything accordingly.
    # @return true if just switched from sizes to seconds, false otherwise
    #
    def SwitchToSecondsIfNecessary
      if @unit_is_seconds ||
          Ops.less_than(
            ::Time.now.to_i,
            Ops.add(SlideShow.start_time, SlideShow.initial_recalc_delay)
          )
        return false # no need to switch
      end

      RecalcRemainingTimes(true) # force recalculation
      @unit_is_seconds = true

      true # just switched
    end



    #***************************************************************************
    #*****************  Callbacks and progress bars ****************************
    #***************************************************************************



    # Update progress widgets for the current CD: Label and ProgressBar.
    # Use global statistics variables for that.
    #
    def UpdateCurrentCdProgress(silent_check)
      return if !SanityCheck(silent_check)
      return if !UI.WidgetExists(:cdStatisticsTable)


      #
      # Update table entries for current CD
      #

      remaining = Ops.get(
        @remaining_sizes_per_cd_per_src,
        [Ops.subtract(@current_src_no, 1), Ops.subtract(@current_cd_no, 1)],
        0
      )
      UI.ChangeWidget(
        Id(:cdStatisticsTable),
        term(
          :Item,
          Builtins.sformat(
            "cd(%1,%2)",
            Ops.subtract(@current_src_no, 1),
            Ops.subtract(@current_cd_no, 1)
          ),
          SIZE_COLUMN_POSITION
        ),
        FormatRemainingSize(remaining)
      )

      UI.ChangeWidget(
        Id(:cdStatisticsTable),
        term(
          :Item,
          Builtins.sformat(
            "cd(%1,%2)",
            Ops.subtract(@current_src_no, 1),
            Ops.subtract(@current_cd_no, 1)
          ),
          PKG_COUNT_COLUMN_POSITION
        ),
        FormatRemainingCount(
          Ops.get(
            @remaining_pkg_count_per_cd_per_src,
            [Ops.subtract(@current_src_no, 1), Ops.subtract(@current_cd_no, 1)],
            0
          )
        )
      )

      if @unit_is_seconds
        # Convert 'remaining' from size (bytes) to time (seconds)

        remaining = Ops.divide(remaining, @bytes_per_second)

        remaining = 0 if Ops.less_or_equal(remaining, 0)

        if Ops.greater_than(remaining, MAX_TIME_PER_CD) # clip off at 2 hours
          # When data throughput goes downhill (stalled network connection etc.),
          # cut off the predicted time at a reasonable maximum.
          remaining = Ops.unary_minus(MAX_TIME_PER_CD)
        end

        UI.ChangeWidget(
          Id(:cdStatisticsTable),
          term(
            :Item,
            Builtins.sformat(
              "cd(%1,%2)",
              Ops.subtract(@current_src_no, 1),
              Ops.subtract(@current_cd_no, 1)
            ),
            TIME_COLUMN_POSITION
          ),
          FormatTimeShowOverflow(remaining)
        )
      end


      #
      # Update "total" table entries
      #

      UI.ChangeWidget(
        Id(:cdStatisticsTable),
        term(:Item, "total", SIZE_COLUMN_POSITION),
        FormatRemainingSize(TotalRemainingSize())
      )

      UI.ChangeWidget(
        Id(:cdStatisticsTable),
        term(:Item, "total", PKG_COUNT_COLUMN_POSITION),
        FormatRemainingCount(TotalRemainingPkgCount())
      )

      if @unit_is_seconds
        UI.ChangeWidget(
          Id(:cdStatisticsTable),
          term(:Item, "total", TIME_COLUMN_POSITION),
          FormatTimeShowOverflow(TotalRemainingTime())
        )
      end

      nil
    end

    # update the overall progress value (download + installation)
    def UpdateTotalProgressValue
      total_progress = 0

      if @total_count_to_download == 0
        # no package to download, just use the install size
        total_progress = Ops.divide(
          Ops.multiply(TotalInstalledSize(), 100),
          @total_size_to_install
        )
      else
        # compute the total progress (use both download and  installation size)
        total_progress = Ops.add(
          Ops.divide(
            Ops.multiply(@total_count_downloaded, @downloading_pct),
            @total_count_to_download
          ),
          Ops.divide(
            Ops.multiply(
              TotalInstalledSize(),
              Ops.subtract(100, @downloading_pct)
            ),
            @total_size_to_install
          )
        )
      end

      Builtins.y2debug(
        "Total package installation progress: %1%%",
        total_progress
      )
      SlideShow.StageProgress(total_progress, nil)

      nil
    end

    # Update progress widgets
    #
    def UpdateTotalProgress(silent_check)
      total_size_to_install_kB = Ops.shift_right(@total_size_to_install, 10)

      # avoid division by zero
      if Ops.less_or_equal(total_size_to_install_kB, 0)
        total_size_to_install_kB = 1
      end

      # update the overall progress value (download + installation)
      UpdateTotalProgressValue()

      UpdateCurrentCdProgress(silent_check)

      if UI.WidgetExists(:nextMedia)
        nextMedia = FormatNextMedia()

        if nextMedia != "" || @last_cd
          UI.ChangeWidget(:nextMedia, :Value, nextMedia)
          UI.RecalcLayout
          @last_cd = false
        end
      end

      nil
    end


    # Returns a table widget item list for CD statistics
    #
    def CdStatisticsTableItems
      itemList = []

      #
      # Add "Total" item - at the top so it is visible by default even if there are many items
      #

      # List column header for total remaining MB and time to install
      caption = _("Total")
      remaining = TotalRemainingSize()
      rem_size = FormatRemainingSize(remaining)
      rem_count = FormatRemainingCount(TotalRemainingPkgCount())
      rem_time = ""

      if @unit_is_seconds && Ops.greater_than(@bytes_per_second, 0)
        rem_time = FormatTimeShowOverflow(TotalRemainingTime())
      end

      itemList = Builtins.add(
        itemList,
        SlideShow.TableItem(
          "total",
          caption,
          Ops.add("   ", rem_size),
          Ops.add("   ", rem_count),
          Ops.add("   ", rem_time)
        )
      )


      #
      # Now go through all repositories
      #

      src_no = 0

      Builtins.foreach(@remaining_sizes_per_cd_per_src) do |inst_src|
        Builtins.y2milestone("src #%1: %2", src_no, inst_src)
        if Ops.greater_than(ListSum(inst_src), 0) # Ignore repositories from where there is nothing is to install
          # Add heading for this repository
          itemList = Builtins.add(
            itemList,
            SlideShow.TableItem(
              Builtins.sformat("src(%1)", src_no),
              Ops.get(@inst_src_names, src_no, ""),
              "",
              "",
              ""
            )
          )

          cd_no = 0

          Builtins.foreach(inst_src) do |remaining|
            if Ops.greater_than(remaining, 0) ||
                Ops.add(src_no, 1) == @current_src_no &&
                  Ops.add(cd_no, 1) == @current_cd_no # suppress current CD
              caption = Builtins.sformat(@media_type, Ops.add(cd_no, 1)) # "Medium 1" - column #0
              rem_size = FormatRemainingSize(remaining) # column #1
              rem_count = FormatRemainingCount(
                Ops.get(@remaining_pkg_count_per_cd_per_src, [src_no, cd_no], 0)
              )
              rem_time = ""

              if @unit_is_seconds && Ops.greater_than(@bytes_per_second, 0)
                remaining = Ops.divide(remaining, @bytes_per_second)
                remaining = MIN_TIME_PER_CD if remaining < MIN_TIME_PER_CD
                rem_time = String.FormatTime(remaining) # column #2

                if Ops.greater_than(remaining, MAX_TIME_PER_CD) # clip off at 2 hours
                  # When data throughput goes downhill (stalled network connection etc.),
                  # cut off the predicted time at a reasonable maximum.
                  # "%1" is a predefined maximum time.
                  rem_time = FormatTimeShowOverflow(
                    Ops.unary_minus(MAX_TIME_PER_CD)
                  )
                end
              end

              itemList = Builtins.add(
                itemList,
                SlideShow.TableItem(
                  Builtins.sformat("cd(%1,%2)", src_no, cd_no), # ID
                  caption,
                  Ops.add("   ", rem_size),
                  Ops.add("   ", rem_count),
                  Ops.add("   ", rem_time)
                )
              )
            end
            cd_no = Ops.add(cd_no, 1)
          end
        end
        src_no = Ops.add(src_no, 1)
      end

      if @debug
        Builtins.y2milestone("Remaining: %1", @remaining_sizes_per_cd_per_src)
        Builtins.y2milestone("CD table item list:\n%1", itemList)
      end

      deep_copy(itemList)
    end



    # Progress display update
    # This is called via the packager's progress callbacks.
    #
    # @param [Fixnum] pkg_percent	package percentage
    #
    def UpdateCurrentPackageProgress(pkg_percent)
      SlideShow.SubProgress(pkg_percent, nil)

      nil
    end

    # update the download rate
    def UpdateCurrentPackageRateProgress(pkg_percent, bps_avg, bps_current)
      #	avg_download_rate = bps_avg;

      return if !SlideShow.ShowingDetails

      new_text = nil # no update of the label
      if Ops.greater_than(bps_current, 0)
        # do not show the average download rate if the space is limited
        if SlideShow.textmode && Ops.less_than(SlideShow.display_width, 100)
          bps_avg = -1
        end
        new_text = String.FormatRateMessage(
          Ops.add(@provide_name, " - %1"),
          bps_avg,
          bps_current
        )
        new_text = Builtins.sformat(
          _("Downloading %1 (download size %2)"),
          new_text,
          @provide_size
        )
      end

      SlideShow.SubProgress(pkg_percent, new_text)

      nil
    end

    def DisplayGlobalProgress
      rem_string = ""
      tot_rem_t = TotalRemainingTime()

      rem_string = @unit_is_seconds && Ops.greater_than(@bytes_per_second, 0) &&
        Ops.greater_than(tot_rem_t, 0) ?
        Builtins.sformat(
          "%1 / %2",
          FormatRemainingSize(TotalRemainingSize()),
          FormatTimeShowOverflow(tot_rem_t)
        ) :
        FormatRemainingSize(TotalRemainingSize())

      rem_string = Ops.add(rem_string, ", ") if rem_string != ""

      SlideShow.SetGlobalProgressLabel(
        Ops.add(
          SlideShow.CurrentStageDescription,
          Builtins.sformat(
            _(" (Remaining: %1%2 packages)"),
            rem_string,
            TotalRemainingPkgCount()
          )
        )
      )

      nil
    end

    def DoneProvide(error, reason, name)
      if error == 0
        @total_downloaded = Ops.add(@total_downloaded, @current_provide_size)

        @total_count_downloaded = Ops.add(@total_count_downloaded, 1)
        Builtins.y2milestone(
          "Downloaded %1/%2 packages",
          @total_count_downloaded,
          @total_count_to_download
        )

        # move the progress also for downloaded files
        UpdateTotalProgressValue()

        d_mode = Ops.get_symbol(Pkg.CommitPolicy, "download_mode", :default)

        if d_mode == :download_in_advance ||
            d_mode == :default && Mode.normal &&
              !Installation.dirinstall_installing_into_dir
          # display download progress in DownloadInAdvance mode
          # translations: progress message (part1)
          SlideShow.SetGlobalProgressLabel(
            Ops.add(
              _("Downloading Packages..."),
              # progress message (part2)
              Builtins.sformat(
                _(" (Downloaded %1 of %2 packages)"),
                @total_count_downloaded,
                @total_count_to_download
              )
            )
          )
        end
      end

      nil
    end

    # Update progress widgets for all CDs.
    # Uses global statistics variables.
    #
    def UpdateAllCdProgress(silent_check)
      return if !SanityCheck(silent_check)

      RecalcRemainingTimes(true) if @unit_is_seconds # force

      SlideShow.UpdateTable(CdStatisticsTableItems())

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
    # @param [String] pkg_name		package name
    # @param [Boolean] deleting		Flag: deleting (true) or installing (false) package?
    #
    def SlideDisplayDone(pkg_name, pkg_size, deleting)
      if !deleting
        SubtractPackageSize(pkg_size)

        if SwitchToSecondsIfNecessary() || RecalcRemainingTimes(false) # no forced recalculation
          Builtins.y2debug("Updating progress for all CDs")
          UpdateAllCdProgress(false)
        else
          UpdateCurrentCdProgress(false)
        end

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

        @total_installed = Ops.add(@total_installed, @current_install_size)
      else
        @removed_packages = Ops.add(@removed_packages, 1)

        if Mode.normal
          @removed_packages_list = Builtins.add(
            @removed_packages_list,
            pkg_name
          )
        end
      end

      nil
    end


    # package start display update
    # - this is called at the beginning of a new package
    #
    # @param [String] pkg_name		package name
    # @param [String] pkg_location	full path to a package
    # @param [String] pkg_summary	package summary (short description)
    # @param [Integer] pkg_size		package size in bytes
    # @param [Boolean] deleting		Flag: deleting (true) or installing (false) package?
    #
    def SlideDisplayStart(pkg_name, pkg_location, pkg_summary, pkg_size, deleting)
      return if !SanityCheck(false)

      # remove path
      pkg_location ||= ""
      pkg_filename = File.basename(pkg_location)
      log.info "pkg_name: #{pkg_name}"

      if deleting
        pkg_size = -1

        # This is a kind of misuse of insider knowledge: If there are packages to delete, this
        # deletion comes first, and only then packages are installed. This, however, greatly
        # distorts the estimated times based on data throughput so far: While packages are
        # deleted, throughput is zero, and estimated times rise to infinity (they are cut off
        # at max_time_per_cd to hide this). So we make sure the time spent deleting packages is
        # not counted for estimating remaining times - reset the timer.
        #
        # Note: This will begin to fail when some day packages are deleted in the middle of the
        # installaton process.

        # FIXME: SlideShow.PauseTimer
        SlideShow.ResetTimer
      end

      pkg_summary ||= ""

      msg = ""

      if deleting
        # Heading for the progress bar for the current package
        # while it is deleted. "%1" is the package name.
        msg = Builtins.sformat(_("Deleting %1"), pkg_name)
      else
        @updating = Pkg.PkgInstalled(pkg_name)

        # package installation - summary text
        # %1 is RPM name, %2 is installed (unpacked) size (e.g. 6.20MB)
        msg = Builtins.sformat(
          _("Installing %1 (installed size %2)"),
          pkg_filename,
          String.FormatSize(pkg_size)
        )

        @current_install_size = pkg_size
      end


      #
      # Update package progress bar
      #
      SlideShow.SubProgress(0, msg)

      # Update global progress bar
      DisplayGlobalProgress()

      #
      # Update (user visible) installation log
      #
      SlideShow.AppendMessageToInstLog(msg)

      #
      # Update the current slide if applicable
      #
      SlideShow.ChangeSlideIfNecessary if SlideShow.ShowingSlide

      nil
    end



    def SlideGenericProvideStart(pkg_name, sz, pattern, remote)
      return if !SanityCheck(false)
      return if !SlideShow.ShowingDetails

      provide_msg = ""

      if remote
        @provide_name = pkg_name
        @provide_size = String.FormatSize(sz)

        provide_msg = Builtins.sformat(
          _("Downloading %1 (download size %2)"),
          @provide_name,
          @provide_size
        )
      else
        provide_msg = pkg_name
      end

      SlideShow.SubProgress(0, provide_msg)

      #
      # Update (user visible) installation log
      # for remote download only
      #

      return if !remote

      Builtins.y2milestone("Package '%1' is remote", pkg_name)

      # message in the installatino log, %1 is package name,
      # %2 is package size
      SlideShow.AppendMessageToInstLog(
        Builtins.sformat(pattern, pkg_name, String.FormatSize(sz))
      )

      nil
    end

    def SlideDeltaApplyStart(pkg_name)
      return if !SanityCheck(false)
      return if !SlideShow.ShowingDetails

      SlideShow.SubProgress(0, pkg_name)

      SlideShow.AppendMessageToInstLog(
        Builtins.sformat(_("Applying delta RPM: %1"), pkg_name)
      )

      nil
    end


    # Package providal start
    def SlideProvideStart(pkg_name, sz, remote)
      @current_provide_size = remote ? sz : 0

      if remote
        # message in the installatino log, %1 is package name,
        # %2 is package size
        SlideGenericProvideStart(
          pkg_name,
          sz,
          _("Downloading %1 (download size %2)"),
          remote
        )
      end

      nil
    end

    publish :variable => :total_sizes_per_cd_per_src, :type => "list <list <integer>>"
    publish :variable => :remaining_sizes_per_cd_per_src, :type => "list <list <integer>>"
    publish :variable => :remaining_times_per_cd_per_src, :type => "list <list <integer>>"
    publish :variable => :inst_src_names, :type => "list <string>"
    publish :variable => :total_pkg_count_per_cd_per_src, :type => "list <list <integer>>"
    publish :variable => :remaining_pkg_count_per_cd_per_src, :type => "list <list <integer>>"
    publish :variable => :srcid_to_current_src_no, :type => "map <integer, integer>"
    publish :variable => :media_type, :type => "string"
    publish :variable => :total_size_installed, :type => "integer"
    publish :variable => :total_size_to_install, :type => "integer"
    publish :variable => :total_count_to_download, :type => "integer"
    publish :variable => :total_count_downloaded, :type => "integer"
    publish :variable => :downloading_pct, :type => "integer"
    publish :variable => :min_time_per_cd, :type => "integer"
    publish :variable => :max_time_per_cd, :type => "integer"
    publish :variable => :size_column, :type => "integer"
    publish :variable => :pkg_count_column, :type => "integer"
    publish :variable => :time_column, :type => "integer"
    publish :variable => :current_src_no, :type => "integer"
    publish :variable => :current_cd_no, :type => "integer"
    publish :variable => :next_src_no, :type => "integer"
    publish :variable => :next_cd_no, :type => "integer"
    publish :variable => :last_cd, :type => "boolean"
    publish :variable => :total_cd_count, :type => "integer"
    publish :variable => :unit_is_seconds, :type => "boolean"
    publish :variable => :bytes_per_second, :type => "integer"
    publish :variable => :init_pkg_data_complete, :type => "boolean"
    publish :function => :GetPackageSummary, :type => "map <string, any> ()"
    publish :function => :InitPkgData, :type => "void (boolean)"
    publish :function => :SetCurrentCdNo, :type => "void (integer, integer)"
    publish :function => :UpdateCurrentCdProgress, :type => "void (boolean)"
    publish :function => :UpdateCurrentPackageProgress, :type => "void (integer)"
    publish :function => :UpdateCurrentPackageRateProgress, :type => "void (integer, integer, integer)"
    publish :function => :DisplayGlobalProgress, :type => "void ()"
    publish :function => :DoneProvide, :type => "void (integer, string, string)"
    publish :function => :UpdateAllCdProgress, :type => "void (boolean)"
    publish :function => :SlideDisplayDone, :type => "void (string, integer, boolean)"
    publish :function => :SlideDisplayStart, :type => "void (string, string, string, integer, boolean)"
    publish :function => :SlideGenericProvideStart, :type => "void (string, integer, string, boolean)"
    publish :function => :SlideDeltaApplyStart, :type => "void (string)"
    publish :function => :SlideProvideStart, :type => "void (string, integer, boolean)"
  end

  PackageSlideShow = PackageSlideShowClass.new
  PackageSlideShow.main
end
