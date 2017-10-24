
require "y2packager/product_location"

# encoding: utf-8
module Yast
  # Include file to be shared by yast2-packager and yast2-add-on
  module PackagerRepositoriesIncludeInclude
    include Yast::Logger

    # constant Plaindir
    PLAINDIR_TYPE = "Plaindir".freeze

    # shell unfriendly characters we want to remove from alias, so it is easier to use with zypper
    SHELL_UNFRIENDLY = "()/!'\"*?;&|<>{}$#`".freeze

    def initialize_packager_repositories_include(_include_target)
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

      @download_meta = true
    end

    def LicenseAccepted(id)
      AddOnProduct.AcceptedLicenseAndInfoFile(id)
    end

    # Create a new repository or service.
    # @param url [String] repository or service URL
    # @param plaindir [Boolean] true to use "PlainDir" format (no repository
    #   metadata present at the URL)
    # @param download [Boolean] whether to refresh the repository or not
    # @param preffered_name [String] (optional) preferred repository name, use
    #   empty string "" to generate the name
    # @param force_alias [String] alias for the new repository, if a repository
    #   with this alias already exists then it is overwritten, use empty string ""
    #   to generate an unique alias
    # @return [Symbol] the result
    #   :ok => successfully added
    #   :again => failed, but user wants to edit the URL and try again
    #   :cancel => failed, don't retry
    #   :abort => repository added successfully, but user rejected the license
    def createSourceImpl(url, plaindir, download, preffered_name, force_alias)
      log.info("createSource: #{URL.HidePassword(url)}, plaindir: #{plaindir}," \
        "download: #{download}, name: #{preffered_name}, force_alias: #{force_alias}")

      if url.nil? || url.empty?
        Builtins.y2error(-1, "Empty URL! Backtrace:")
        return :again
      end

      expanded_url = Pkg.ExpandedUrl(url)

      if expanded_url.nil?
        # TRANSLATORS: Error message, %{url} is replaced by the real URL
        Report.Error(_("Invalid URL:\n%{url}") % { url: url })
        return :again
      end

      # for Plaindir repository we have to use SourceCreateType() binding
      parsed = URL.Parse(url)
      scheme = parsed["scheme"].downcase

      # check if the URL can be accessed/mounted, install the missing packages
      install_mount_package(scheme)

      initialize_progress

      Progress.NextStage
      service_type = Pkg.ServiceProbe(expanded_url)
      Builtins.y2milestone("Probed service type: %1", service_type)

      # create a new service if a service is detected at the URL
      if ![nil, "NONE"].include?(service_type)
        Builtins.y2milestone("Adding a service of type %1...", service_type)
        add_service(url, preffered_name)
        return :ok
      end

      found_products = scan_products(expanded_url, url)
      newSources = []

      enter_again = false

      # more products on the medium, let the user choose the products to install
      # this code is not used in AutoYaST, but rather be on the safe side...
      if !Mode.auto && found_products.size > 1
        require "y2packager/dialogs/addon_selector"
        dialog = Y2Packager::Dialogs::AddonSelector.new(found_products)

        ui = dialog.run
        found_products = dialog.selected_products

        # pressed abort/cancel/close/back/...
        return ui if ui != :next

        # nothing selected, just skip adding the repos and continue in the workflow
        return :next if found_products.empty?
      end

      found_products.each do |product|
        next if enter_again
        name = !preffered_name.nil? && preffered_name != "" ? preffered_name : product.name
        # probe repository type (do not probe plaindir repo)
        repo_type = plaindir ? PLAINDIR_TYPE : Pkg.RepositoryProbe(expanded_url, product.dir)
        log.info("Repository type (#{URL.HidePassword(url)},#{product.dir}): #{repo_type}")

        # the probing has failed
        if repo_type.nil? || repo_type == "NONE"
          if scheme == "dir"
            if !confirm_plain_repo
              enter_again = true
              next
            end

            repo_type = PLAINDIR_TYPE
            log.info("Probing has failed, using Plaindir repository type.")
          end

          next
        end

        alias_name = (force_alias == "") ? propose_alias(product.name) : force_alias

        # map with repository parameters: $[ "enabled" : boolean,
        # "autorefresh" : boolean, "name" : string, "alias" : string,
        # "base_urls" : list<string>, "prod_dir" : string, "type" : string ]
        repo_prop = {
          "enabled"     => true,
          "autorefresh" => autorefresh_for?(url),
          "name"        => name,
          "prod_dir"    => product.dir,
          "alias"       => alias_name,
          "base_urls"   => [url],
          "type"        => repo_type
        }
        if force_alias != ""
          # don't check uniqueness of the alias, force the alias
          repo_prop["check_alias"] = false
        end
        Progress.NextStage
        new_repo_id = Pkg.RepositoryAdd(repo_prop)

        # hide the URL password in the log
        repo_prop_log = deep_copy(repo_prop)
        repo_prop_log["base_urls"] = [URL.HidePassword(url)]
        log.info("Added repository: #{new_repo_id}: #{repo_prop_log}")

        newSources << new_repo_id

        # for local repositories (e.g. CD/DVD) which have autorefresh disabled
        # download the metadata immediately, the medium is in the drive right
        # now, it can be changed later and accidentally added a different repository
        if !autorefresh_for?(url)
          log.info "Adding a local repository, refreshing it now..."
          Pkg.SourceRefreshNow(new_repo_id)
        end
      end

      # broken repository or wrong URL - enter the URL again
      return :again if enter_again

      log.info("New sources: #{newSources}")

      if newSources.empty?
        log.error("Cannot add the repository")
        try_again(url, scheme) ? :again : :cancel
      else
        Progress.NextStage
        license_accepted = true
        Builtins.foreach(newSources) do |id|
          if !LicenseAccepted(id)
            log.info("License NOT accepted, removing the source")
            Pkg.SourceDelete(id)
            license_accepted = false
          else
            src_data = Pkg.SourceGeneralData(id)
            log.info("Addded repository: #{src_data}")

            sourceState = {
              "SrcId"       => id,
              "enabled"     => src_data["enabled"],
              "autorefresh" => src_data["autorefresh"],
              "name"        => src_data["name"],
              "do_refresh"  => download
            }
            @sourceStatesOut << sourceState
          end
        end

        license_accepted ? :ok : :abort
      end
    ensure
      # relese (unmount) the medium
      Pkg.SourceReleaseAll
    end

    # start createSource() function in extra wizard dialog
    def createSource(url, plaindir, download, preffered_name)
      createSourceWithAlias(url, plaindir, download, preffered_name, "")
    end

    # create source with alias
    # *IMPORTANT*: make sure the alias is unique!! Otherwise the repo will be overwritten!!
    def createSourceWithAlias(url, plaindir, download, preffered_name, alias_name)
      Wizard.CreateDialog
      ret = createSourceImpl(url, plaindir, download, preffered_name, alias_name)
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

        if service.nil?
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
        end

        return :next
      elsif url == "sccrepos://"
        sccrepos = WFM.call("inst_scc", ["select_extensions"])
        Builtins.y2milestone("Registration Repositories returned: %1", sccrepos)

        return sccrepos == :abort || sccrepos == :cancel ? :back : :next
      end

      ret = createSource(url, plaindir, @download_meta, name)

      case ret
      when :again
        :back
      when :abort, :cancel
        :abort
      when :next
        :next
      else
        log.warn "Received unknown result: #{ret}, using :next instead"
        :next
      end
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
      SourceDialogs.EditDialog
    end

    # Evaluate the default autorefresh flag for the given repository URL.
    # @param url [String] Repository URL
    # @return [Boolean] The default autorefresh flag for the URL
    def autorefresh_for?(url)
      protocol = URL.Parse(url)["scheme"].downcase

      # disable autorefresh for local repositories ,
      autorefresh = !Pkg.UrlSchemeIsLocal(protocol)

      log.info "Autorefresh flag for '#{protocol}' URL protocol: #{autorefresh}"
      autorefresh
    end

  private

    # scan the repository URL and return the available products
    # @return [Array<Y2Packager::ProductLocation>] Found products
    def scan_products(expanded_url, original_url)
      new_repos = Pkg.RepositoryScan(expanded_url)
      found_products = new_repos.map { |(name, dir)| Y2Packager::ProductLocation.new(name, dir) }
      log.info("Found products: #{found_products}")

      # add at least one product if the scan result is empty (no product info available)
      # to try adding the repository at the root (/) of the medium
      if found_products.empty?
        url_path = URL.Parse(original_url)["path"]
        p_elems = url_path.split("/")

        fallback = _("Repository")

        if p_elems.size > 1
          url_path = Ops.get(
            p_elems,
            Ops.subtract(Builtins.size(p_elems), 1),
            fallback
          )

          if url_path.nil? || url_path == ""
            url_path = Ops.get(
              p_elems,
              Ops.subtract(Builtins.size(p_elems), 2),
              fallback
            )

            url_path = fallback if url_path.nil? || url_path == ""
          end
        elsif url_path == "/"
          url_path = fallback
        end

        found_products << Y2Packager::ProductLocation.new(url_path, "/")
      end

      found_products
    end

    # propose the repository alias (based on the product name)
    # @return [String] an unique alias
    def propose_alias(product_name)
      # replace " " -> "_" (avoid spaces in .repo file name) and remove shell unfriendly chars
      alias_name = product_name.tr(" ", "_").delete(SHELL_UNFRIENDLY)
      alias_orig = alias_name

      # all current aliases
      aliases = Pkg.SourceGetCurrent(false).map do |i|
        Pkg.SourceGeneralData(i)["alias"]
      end

      # repository alias must be unique
      # if it already exists add "_<number>" suffix to it
      idx = 1
      while aliases.include?(alias_name)
        alias_name = "#{alias_orig}_#{idx}"
        idx += 1
      end

      alias_name
    end

    # initialize the progress for adding new add-on repository
    def initialize_progress
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
    end

    # Add a new repository service.
    # @param url [String] service URL
    # @param type [String] probed service type
    # @param preffered_name [String] service name, empty string means generate it
    def add_service(url, preffered_name)
      # all current aliases
      aliases = @serviceStatesOut.map { |s| s["alias"] }

      # service alias must be unique
      # if it already exists add "_<number>" suffix to it
      idx = 1
      alias_name = "service"
      while aliases.include?(alias_name)
        alias_name = "service_#{idx}"
        idx += 1
      end

      # use alias as the name if it's missing
      preffered_name = alias_name if preffered_name.nil? || preffered_name == ""

      new_service = {
        "alias"       => alias_name,
        "autorefresh" => autorefresh_for?(url),
        "enabled"     => true,
        "name"        => preffered_name,
        "url"         => url
      }

      log.info("Added new service: #{new_service}")

      @serviceStatesOut << new_service
    end

    # Ask user whether to use plaindir repository type when no repository
    # metadata has been found at the specified URL.
    # @return [Boolean] true to use plaindir repository
    def confirm_plain_repo
      Popup.AnyQuestion(
        Popup.NoHeadline,
        # continue-back popup
        _(
          "There is no product information available at the given location.\n" \
            "If you expected to to point a product, go back and enter\n" \
            "the correct location.\n" \
            "To make rpm packages located at the specified location available\n" \
            "in the packages selection, continue.\n"
        ),
        Label.ContinueButton,
        Label.BackButton,
        :focus_no
      )
    end

    # Check and install the packages needed for accessing the URL scheme.
    # @param scheme [String] URL scheme of the new repository
    def install_mount_package(scheme)
      if scheme == "smb" && !File.exist?("/sbin/mount.cifs")
        log.info("Installing missing 'cifs-mount' package...")
        # install cifs-mount package
        PackageSystem.CheckAndInstallPackages(["cifs-mount"])
      end
    end

    # Ask user whether to change the entered URL and try again
    # @param url [String] repository URL
    # @param scheme [String] scheme part of the URL
    # @return [Boolean] true to try again
    def try_again(url, scheme)
      # TRANSLATORS: error message (1/3), %1 is repository URL
      msgs = [Builtins.sformat(
        _("Unable to create repository\nfrom URL '%1'."),
        URL.HidePassword(url)
      )]

      if url.end_with?(".iso") && ["ftp", "sftp", "http", "https"].include?(scheme)
        # TRANSLATORS: error message (2/3)
        msgs << _(
          "Using an ISO image over ftp or http protocol is not possible.\n" \
              "Change the protocol or unpack the ISO image on the server side."
        )
      end

      # TRANSLATORS: error message (3/3)
      msgs << _("Change the URL and try again?")

      Popup.YesNo(msgs.join("\n\n"))
    end
  end
end
