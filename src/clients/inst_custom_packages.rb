# encoding: utf-8
module Yast
  # Client for 3rd prodcuts/addon products package installations
  class InstCustomPackagesClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "packager"
      Yast.import "ProductFeatures"
      Yast.import "SourceManager"
      Yast.import "Directory"
      Yast.import "Popup"
      Yast.import "SlideShow"
      Yast.import "PackageSlideShow"
      Yast.import "Kernel"
      Yast.import "Installation"
      Yast.import "GetInstArgs"
      Yast.import "Mode"
      Yast.import "PackagesUI"

      @packages = Convert.convert(
        ProductFeatures.GetFeature("software", "packages"),
        from: "any",
        to:   "list <string>"
      )
      if !probeSource(Ops.add("dir://", Directory.custom_workflow_dir))
        # error popup
        Popup.Error(_("Could not read package information."))
        return :abort
      end

      if Ops.greater_than(Builtins.size(@packages), 0)
        Builtins.y2milestone("installing packages: %1", @packages)
        Builtins.foreach(@packages) do |pkg|
          Pkg.DoProvide([pkg]) if !Pkg.PkgInstall(pkg)
        end
        @solve = Pkg.PkgSolve(false)
        Builtins.y2error("Error solving package dependencies") if !@solve
      end
      @result = PackagesUI.RunPackageSelector("mode" => :summaryMode)
      Builtins.y2milestone("Package selector returned: %1", @result)
      @result = :next if @result == :accept

      if @result == :next # packages selected ?
        @anyToDelete = Pkg.IsAnyResolvable(:package, :to_remove)
        SlideShow.SetLanguage(UI.GetLanguage(true))
        PackageSlideShow.InitPkgData(false)
        SlideShow.OpenDialog

        Yast.import "PackageInstallation"
        @oldvmlinuzsize = Convert.to_integer(
          SCR.Read(path(".target.size"), "/boot/vmlinuz")
        )
        @commit_result = PackageInstallation.CommitPackages(0, 0) # Y: commit them !
        @newvmlinuzsize = Convert.to_integer(
          SCR.Read(path(".target.size"), "/boot/vmlinuz")
        )

        SlideShow.CloseDialog

        if Installation.destdir == "/" &&
            (Ops.greater_than(Ops.get_integer(@commit_result, 0, 0), 0) || @anyToDelete)
          # prepare "you must boot" popup
          Kernel.SetInformAboutKernelChange(@oldvmlinuzsize != @newvmlinuzsize)
          Kernel.InformAboutKernelChange
        end
      end

      if Builtins.size(SourceManager.newSources) == 1
        Pkg.SourceChangeUrl(Ops.get(SourceManager.newSources, 0, -1), "cd:///")
      end

      :next
    end

    def probeSource(url)
      ret = SourceManager.createSource(url)
      if ret != :ok
        Builtins.y2error("no repositories available on media")
        return false
      else
        SourceManager.CommitSources
        return true
      end
    end
  end
end

Yast::InstCustomPackagesClient.new.main
