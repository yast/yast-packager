require "yast"
require "yast2/system_time"

# Yast namespace
module Yast
  # Perfoms package installation
  class PackageInstallationClass < Module
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "packager"

      Yast.import "Mode"
      Yast.import "Installation"
      Yast.import "Directory"
      Yast.import "Packages"
      Yast.import "SlideShow"
      Yast.import "PackageSlideShow"
      Yast.import "PackagesUI"

      Yast.import "Label"

      @download_in_advance = nil
    end

    def DownloadInAdvance
      @download_in_advance
    end

    def SetDownloadInAdvance(enable)
      @download_in_advance = enable

      nil
    end

    #  Show a dialog with either the list of failed packages (string a) or
    #  the complete log (string b).
    def ShowFailedPackages(a, b)
      rbuttons = RadioButtonGroup(
        VBox(
          Left(
            RadioButton(
              Id(:a),
              Opt(:notify),
              # button label
              _("&Show Failed Packages List"),
              true
            )
          ),
          Left(
            RadioButton(
              Id(:b),
              Opt(:notify),
              # button label
              _("&Show Full Log"),
              false
            )
          )
        )
      )

      UI.OpenDialog(
        Opt(:decorated),
        VBox(
          HSpacing(40),
          # dialog headline
          Left(Heading(_("Installation of some Packages Failed"))),
          rbuttons,
          RichText(Id(:text), Opt(:plainText), a),
          PushButton(Id(:ok), Opt(:default, :key_F10), Label.OKButton)
        )
      )

      loop do
        ret = Convert.to_symbol(UI.UserInput)

        if ret == :a || ret == :b
          UI.ChangeWidget(
            Id(:text),
            :Value,
            Convert.to_boolean(UI.QueryWidget(Id(:a), :Value)) ? a : b
          )
          next
        end

        break if ret == :ok
      end

      UI.CloseDialog

      nil
    end

    # commitPackages marked for deletion or installation
    # @return [Array] containing [ int successful, list failed, list remaining,
    #   list srcremaining, list update_messages ]
    def Commit(config)
      config = deep_copy(config)
      if Mode.test
        FakePackager([], "suse", false) # not deleting packages
        return []
      end
      # install packages from this media

      PackageSlideShow.InitPkgData(false)

      # structure: [ ["source_name", id] ]
      src_list = Pkg.PkgMediaNames

      # get ID of the first repository
      first_source = Ops.get_integer(src_list, [0, 1], 1)

      Builtins.y2milestone("ID of the first repository: %1", first_source)

      if Ops.get_integer(config, "medium_nr", 0).zero?
        PackageSlideShow.SetCurrentCdNo(first_source, 1)
      else
        PackageSlideShow.SetCurrentCdNo(
          first_source,
          Ops.get_integer(config, "medium_nr", 0)
        )
      end
      PackageSlideShow.UpdateAllCdProgress(false)
      SlideShow.StartTimer

      start_time = Yast2::SystemTime.uptime

      # returns [ int successful, list failed, list remaining, list srcremaining ]
      Builtins.y2milestone("Calling Pkg::Commit (%1)", config)
      commit_result = Pkg.Commit(config)

      SlideShow.StopTimer

      if commit_result.nil?
        Builtins.y2error("Commit failed: %1", Pkg.LastError)
        return []
      end

      installation_time = Yast2::SystemTime.uptime - start_time
      Builtins.y2milestone(
        "Installation took %1 seconds, commit result: %2",
        installation_time,
        commit_result
      )

      # see if installation of some packages failed
      errpacks = Ops.get_list(commit_result, 1, [])
      if Ops.greater_than(Builtins.size(errpacks), 0)
        full_log = Ops.get_string(
          PackagesUI.GetPackageSummary,
          "install_log",
          ""
        )
        ShowFailedPackages(Builtins.mergestring(errpacks, "\n"), full_log)

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
        SCR.Write(
          path(".target.ycp"),
          "/var/lib/YaST2/failed_packages",
          Builtins.merge(old_failed_packs, errpacks)
        )
      end

      PackagesUI.show_update_messages(commit_result) unless Mode.installation || Mode.autoinst

      if Mode.normal
        # collect and set installation summary data
        summary = PackageSlideShow.GetPackageSummary

        Ops.set(summary, "time_seconds", installation_time)
        Ops.set(summary, "success", Builtins.size(errpacks).zero?)
        Ops.set(summary, "remaining", package_names(commit_result[2] || []))
        Ops.set(summary, "install_log", SlideShow.inst_log)

        if Ops.greater_than(Builtins.size(errpacks), 0)
          Ops.set(summary, "error", Pkg.LastError)
          Ops.set(summary, "failed", errpacks)
        end

        if commit_result == [-1]
          Ops.set(summary, "error", _("Installation aborted by user."))
          Ops.set(summary, "success", false)
        end

        PackagesUI.SetPackageSummary(summary)
      end

      deep_copy(commit_result)
    end

    # commitPackages marked for deletion or installation
    # @return [Array] with content [ int successful, list failed, list remaining,
    #   list srcremaining, list update_messages ]
    def CommitPackages(media_number, packages_installed)
      # this is a backward compatible wrapper for Commit()
      Builtins.y2milestone(
        "CommitPackages (%1,%2): Pkg::TargetGetDU() %3",
        media_number,
        packages_installed,
        Pkg.TargetGetDU
      )
      Commit("medium_nr" => media_number)
    end

    #
    # Fake progress bars for Mode::test ()
    #
    # NOTE: This is currently completely broken.
    # -- sh 2003-12-15
    #
    def FakePackager(packages, _inst_source, _deleting)
      packages = deep_copy(packages)
      disk_usage = 20
      ret = nil
      number = 0

      Builtins.y2debug(
        "FakePackager - handling %1 packages",
        Builtins.size(packages)
      )

      Builtins.foreach(packages) do |_pac|
        pkg_size = 42 * 1024
        bytes_installed = 0
        if Ops.less_than(pkg_size, 0)
          # pkginfo doesn't know anything about the kernel RPM, so its
          # size can't be obtained, e.g. pkg_size is -1. To make up for
          # this, let's assume a negative starting size to keep things
          # going for a while (this is test_mode only, anyway).
          bytes_installed = -857 * 1024
        end
        while Ops.less_than(bytes_installed, pkg_size) && ret != :cancel &&
            ret != :diskfull
          Builtins.sleep(300) # millisec
          bytes_installed = Ops.add(bytes_installed, 300 * 1024)
        end
        disk_usage = Ops.add(disk_usage, 1)
        number = Ops.add(number, 1)
      end

      ret = if ret == :cancel || ret == :abort
        :cancel
      elsif ret == :diskfull
        :diskfull
      else
        :ok
      end

      Builtins.y2debug("FakePackager returning with %1", ret)
      deep_copy(ret)
    end

    publish function: :DownloadInAdvance, type: "boolean ()"
    publish function: :SetDownloadInAdvance, type: "void (boolean)"
    publish function: :FakePackager, type: "any (list <list>, string, boolean)"
    publish function: :Commit, type: "list (map <string, any>)"
    publish function: :CommitPackages, type: "list (integer, integer)"

  private

    # Get a human readable list of installed packages
    # @param [Array<Hash>] packages list of package data
    # @return [Array<String>] list of package names
    def package_names(packages)
      packages.map { |p| p["name"] }
    end
  end

  PackageInstallation = PackageInstallationClass.new
  PackageInstallation.main
end
