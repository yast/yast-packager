# encoding: utf-8

# File:	packager/repositories_include.ycp
#
# Author:	Cornelius Schumacher <cschum@suse.de>
#		Ladislav Slezak <lslezak@suse.cz>
#		Lukas Ocilka <locilka@suse.cz>
#
# Purpose:	Include file to be shared by yast2-packager and yast2-add-on
#
# $Id$
#
module Yast
  module PackagerRepositoriesIncludeInclude
    def initialize_packager_repositories_include(include_target)
      Yast.import "Pkg"
      Yast.import "Stage"
      Yast.import "Wizard"
      Yast.import "AddOnProduct"
      Yast.import "URL"
      Yast.import "PackageSystem"
      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "SourceDialogs"
      Yast.import "Report"
      Yast.import "Progress"

      textdomain "packager"

      @sourceStatesIn = []
      @sourceStatesOut = []

      @serviceStatesIn = []
      @serviceStatesOut = []

      # constant Plaindir
      @plaindir_type = "Plaindir"

      @download_meta = true
    end

    def LicenseAccepted(id)
      ret = AddOnProduct.AcceptedLicenseAndInfoFile(id)
      ret
    end

    def createSourceImpl(url, plaindir, download, preffered_name, force_alias)
      Builtins.y2milestone(
        "createSource: %1, plaindir: %2, download: %3, name: %4",
        URL.HidePassword(url),
        plaindir,
        download,
        preffered_name
      )

      if url != ""
        expanded_url = Pkg.ExpandedUrl(url)

        # for Plaindir repository we have to use SourceCreateType() binding
        parsed = URL.Parse(url)
        scheme = Ops.get_string(parsed, "scheme", "")

        if plaindir == true
          Builtins.y2milestone("Using PlainDir repository type")
        end

        # check if SMB/CIFS share can be mounted
        if scheme == "smb" &&
            Ops.less_than(SCR.Read(path(".target.size"), "/sbin/mount.cifs"), 0)
          Builtins.y2milestone(
            "SMB/CIFS share cannot be mounted, installing missing 'cifs-mount' package..."
          )
          # install cifs-mount package
          PackageSystem.CheckAndInstallPackages(["cifs-mount"])
        end

        Progress.New(
          # TRANSLATORS: dialog caption
          _("Adding a New Repository"),
          " ",
          3,
          [
            _("Check Repository Type"),
            _("Add Repository"),
            _("Read Repository License")
          ],
          [
            _("Checking Repository Type"),
            _("Adding Repository"),
            _("Reading Repository License")
          ],
          # TRANSLATORS: dialog help
          _(
            "<p>The repository manager is downloading repository details...</p>"
          )
        )

        Progress.NextStage
        service_type = Pkg.ServiceProbe(expanded_url)
        Builtins.y2milestone("Probed service type: %1", service_type)

        if service_type != nil && service_type != "NONE"
          Builtins.y2milestone("Adding a service of type %1...", service_type)
          _alias = "service"

          # all current aliases
          aliases = Builtins.maplist(@serviceStatesOut) do |s|
            Ops.get_string(s, "alias", "")
          end

          # service alias must be unique
          # if it already exists add "_<number>" suffix to it
          idx = 1
          while Builtins.contains(aliases, _alias)
            _alias = Builtins.sformat("service_%1", idx)
            idx = Ops.add(idx, 1)
          end

          autorefresh = true
          schema = Builtins.tolower(Builtins.substring(url, 0, 3))

          if schema == "cd:" || schema == "dvd"
            autorefresh = false
            Builtins.y2milestone("Disabling autorefresh for a CD/DVD service")
          end

          # use alias as the name if it's missing
          if preffered_name == nil || preffered_name == ""
            preffered_name = _alias
          end

          new_service = {
            "alias"       => _alias,
            "autorefresh" => autorefresh,
            "enabled"     => true,
            "name"        => preffered_name,
            "url"         => url
          }

          Builtins.y2milestone("Added new service: %1", new_service)

          @serviceStatesOut = Builtins.add(@serviceStatesOut, new_service)

          return :ok
        end

        new_repos = Pkg.RepositoryScan(expanded_url)
        Builtins.y2milestone("new_repos: %1", new_repos)

        # add at least one product if the scan result is empty (no product info available)
        if Builtins.size(new_repos) == 0
          url_path = Ops.get_string(URL.Parse(url), "path", "")
          p_elems = Builtins.splitstring(url_path, "/")
          fallback = _("Repository")

          if Ops.greater_than(Builtins.size(p_elems), 1)
            url_path = Ops.get(
              p_elems,
              Ops.subtract(Builtins.size(p_elems), 1),
              fallback
            )

            if url_path == nil || url_path == ""
              url_path = Ops.get(
                p_elems,
                Ops.subtract(Builtins.size(p_elems), 2),
                fallback
              )

              url_path = fallback if url_path == nil || url_path == ""
            end
          end

          new_repos = [[url_path, "/"]]
        end

        newSources = []
        auto_refresh = true

        # disable autorefresh for ISO images
        iso_prefix = "iso:"
        if Builtins.substring(url, 0, Builtins.size(iso_prefix)) == iso_prefix
          Builtins.y2milestone(
            "ISO image detected, disabling autorefresh (%1)",
            URL.HidePassword(url)
          )
          auto_refresh = false
        end

        # CD or DVD repository?
        cd_scheme = Builtins.contains(
          ["cd", "dvd"],
          Builtins.tolower(Ops.get_string(URL.Parse(url), "scheme", ""))
        )
        if cd_scheme
          Builtins.y2milestone(
            "CD/DVD repository detected, disabling autorefresh (%1)",
            URL.HidePassword(url)
          )
          auto_refresh = false
        end

        enter_again = false

        Builtins.foreach(new_repos) do |repo|
          next if enter_again
          name = Ops.get(repo, 0, "")
          name = preffered_name if preffered_name != nil && preffered_name != ""
          prod_dir = Ops.get(repo, 1, "/")
          # probe repository type (do not probe plaindir repo)
          repo_type = plaindir ?
            @plaindir_type :
            Pkg.RepositoryProbe(expanded_url, prod_dir)
          Builtins.y2milestone(
            "Repository type (%1,%2): %3",
            URL.HidePassword(url),
            prod_dir,
            repo_type
          )
          # the probing has failed
          if repo_type == nil || repo_type == "NONE"
            if scheme == "dir"
              if !Popup.AnyQuestion(
                  Popup.NoHeadline,
                  # continue-back popup
                  _(
                    "There is no product information available at the given location.\n" +
                      "If you expected to to point a product, go back and enter\n" +
                      "the correct location.\n" +
                      "To make rpm packages located at the specified location available\n" +
                      "in the packages selection, continue.\n"
                  ),
                  Label.ContinueButton,
                  Label.BackButton,
                  :focus_no
                )
                enter_again = true
                next
              end

              repo_type = @plaindir_type
              Builtins.y2warning(
                "Probing has failed, using Plaindir repository type."
              )
            else
              next
            end
          end
          _alias = ""
          if force_alias == ""
            # replace " " -> "_" (avoid spaces in .repo file name)
            _alias = Builtins.mergestring(Builtins.splitstring(name, " "), "_")
            alias_orig = _alias

            # all current aliases
            aliases = Builtins.maplist(Pkg.SourceGetCurrent(false)) do |i|
              info = Pkg.SourceGeneralData(i)
              Ops.get_string(info, "alias", "")
            end

            # repository alias must be unique
            # if it already exists add "_<number>" suffix to it
            idx = 1
            while Builtins.contains(aliases, _alias)
              _alias = Builtins.sformat("%1_%2", alias_orig, idx)
              idx = Ops.add(idx, 1)
            end
          else
            _alias = force_alias
          end
          # map with repository parameters: $[ "enabled" : boolean,
          # "autorefresh" : boolean, "name" : string, "alias" : string,
          # "base_urls" : list<string>, "prod_dir" : string, "type" : string ]
          repo_prop = {}
          Ops.set(repo_prop, "enabled", true)
          Ops.set(repo_prop, "autorefresh", auto_refresh)
          Ops.set(repo_prop, "name", name)
          Ops.set(repo_prop, "prod_dir", Ops.get(repo, 1, "/"))
          Ops.set(repo_prop, "alias", _alias)
          Ops.set(repo_prop, "base_urls", [url])
          Ops.set(repo_prop, "type", repo_type)
          if force_alias != ""
            # don't check uniqueness of the alias, force the alias
            Ops.set(repo_prop, "check_alias", false)
          end
          Progress.NextStage
          new_repo_id = Pkg.RepositoryAdd(repo_prop)
          repo_prop_log = deep_copy(repo_prop)
          Ops.set(repo_prop_log, "base_urls", [URL.HidePassword(url)])
          Builtins.y2milestone(
            "Added repository: %1: %2",
            new_repo_id,
            repo_prop_log
          )
          newSources = Builtins.add(newSources, new_repo_id)
          if cd_scheme
            # for CD/DVD repo download the metadata immediately,
            # the medium is in the drive right now, it can be changed later
            # and accidentaly added a different repository
            Builtins.y2milestone(
              "Adding a CD or DVD repository, refreshing now..."
            )
            Pkg.SourceRefreshNow(new_repo_id)
          end
        end 


        # broken repository or wrong URL - enter the URL again
        if enter_again
          Pkg.SourceReleaseAll
          return :again
        end

        Builtins.y2milestone("New sources: %1", newSources)

        if Builtins.size(newSources) == 0
          Builtins.y2error("Cannot add the repository")

          # popup message part 1
          msg = Builtins.sformat(
            _("Unable to create repository\nfrom URL '%1'."),
            URL.HidePassword(url)
          )

          if Builtins.regexpmatch(url, "\\.iso$")
            parsed_url = URL.Parse(url)
            scheme2 = Builtins.tolower(Ops.get_string(parsed_url, "scheme", ""))

            if Builtins.contains(["ftp", "sftp", "http", "https"], scheme2)
              # error message
              msg = Ops.add(
                Ops.add(msg, "\n\n"),
                _(
                  "Using an ISO image over ftp or http protocol is not possible.\nChange the protocol or unpack the ISO image on the server side."
                )
              )
            end
          end

          # popup message part 2
          msg = Ops.add(
            Ops.add(msg, "\n\n"),
            _("Change the URL and try again?")
          )

          tryagain = Popup.YesNo(msg)
          return :again if tryagain

          return :cancel
        else
          Progress.NextStage
          license_accepted = true
          Builtins.foreach(newSources) do |id|
            if !LicenseAccepted(id)
              Builtins.y2milestone("License NOT accepted, removing the source")
              Pkg.SourceDelete(id)
              license_accepted = false
            else
              src_data = Pkg.SourceGeneralData(id)
              Builtins.y2milestone("Addded repository: %1", src_data)

              sourceState = {
                "SrcId"       => id,
                "enabled"     => Ops.get_boolean(src_data, "enabled", true),
                "autorefresh" => Ops.get_boolean(src_data, "autorefresh", true),
                "name"        => Ops.get_string(src_data, "name", ""),
                "do_refresh"  => download
              }
              @sourceStatesOut = Builtins.add(@sourceStatesOut, sourceState)
            end
          end

          # relese (unmount) the medium
          Pkg.SourceReleaseAll

          return license_accepted ? :ok : :abort
        end
      else
        Builtins.y2error(-1, "Empty URL! Backtrace:")
        return :again
      end
    end

    # start createSource() function in extra wizard dialog
    def createSource(url, plaindir, download, preffered_name)
      Wizard.CreateDialog
      ret = createSourceImpl(url, plaindir, download, preffered_name, "")
      Wizard.CloseDialog
      ret
    end

    # create source with alias
    # *IMPORTANT*: make sure the alias is unique!! Otherwise the repo will be overwritten!!
    def createSourceWithAlias(url, plaindir, download, preffered_name, _alias)
      Wizard.CreateDialog
      ret = createSourceImpl(url, plaindir, download, preffered_name, _alias)
      Wizard.CloseDialog
      ret
    end

    def StoreSource
      url = SourceDialogs.GetURL
      name = SourceDialogs.GetRepoName
      plaindir = SourceDialogs.IsPlainDir

      # special case, bugzilla #238680
      if url == "slp://"
        required_package = "yast2-slp"
        installed_before = PackageSystem.Installed(required_package)

        if !Stage.initial && !installed_before
          # Tries to Check and Install packages
          if !PackageSystem.CheckAndInstallPackagesInteractive(
              [required_package]
            ) ||
              !PackageSystem.Installed(required_package)
            Report.Error(
              Builtins.sformat(
                # popup error message, %1 is the package name
                _(
                  "Cannot search for SLP repositories\nwithout having %1 package installed.\n"
                ),
                required_package
              )
            )
            Builtins.y2warning("Not searching for SLP repositories")
            return :back 
            # New .slp agent has been added
            # FIXME: lazy loading of agents will make this obsolete
          else
            SCR.RegisterAgent(path(".slp"), term(:ag_slp, term(:SlpAgent)))
          end
        end

        service = Convert.to_string(WFM.call("select_slp_source"))

        if service == nil
          Builtins.y2milestone("No SLP service selected, returning back...")
          return :back
        else
          url = service
        end
      elsif url == "commrepos://"
        commrepos = WFM.call(
          "inst_productsources",
          [{ "skip_already_used_repos" => true }]
        )
        Builtins.y2milestone("Community Repositories returned: %1", commrepos)

        if commrepos == :abort || commrepos == :cancel
          Builtins.y2milestone("Using CR have been canceled")
          return :back
        else
          return :next
        end
      elsif url == "sccrepos://"
        sccrepos = WFM.call("inst_scc", ["select_extensions"])
        Builtins.y2milestone("Registration Repositories returned: %1", sccrepos)

        return (sccrepos == :abort || sccrepos == :cancel) ? :back : :next
      end

      ret = createSource(url, plaindir, @download_meta, name)

      if ret == :again
        return :back
      elsif ret == :abort || ret == :cancel
        return :abort
      end
      :next
    end

    def TypeDialogOpts(download, url)
      SourceDialogs.SetDownloadOption(download)
      SourceDialogs.SetURL(url)

      td = SourceDialogs.TypeDialogDownloadOpt

      ret = Ops.get_symbol(td, "ui", :next)
      @download_meta = Ops.get_boolean(td, "download", true)
      ret
    end

    def TypeDialog
      # download metadata, reset the stored URL
      TypeDialogOpts(true, "")
    end

    def EditDialog
      ret = SourceDialogs.EditDialog
      ret
    end
  end
end
