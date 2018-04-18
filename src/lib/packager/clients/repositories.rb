# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# ------------------------------------------------------------------------------

Yast.import "Pkg"
Yast.import "UI"

Yast.import "Confirm"
Yast.import "Mode"
Yast.import "PackageCallbacks"
Yast.import "PackageLock"
Yast.import "Report"
# SourceManager overlaps quite a bit with inst_source,
# so far we only use it for ZMD sync, TODO refactor better
Yast.import "SourceManager"
Yast.import "SourceDialogs"
Yast.import "Wizard"

Yast.import "Label"
Yast.import "Popup"
Yast.import "Sequencer"
Yast.import "CommandLine"
Yast.import "Progress"
Yast.import "Directory"
Yast.import "URL"

module Yast
  # Interface for repository management
  class RepositoriesClient < Client
    include Yast::Logger

    NO_SERVICE = :no_service
    NO_SERVICE_ITEM = :no_service_item

    def import_modules
      Yast.import "Pkg"
      Yast.import "UI"

      Yast.include self, "packager/inst_source_dialogs.rb"
      Yast.include self, "packager/key_manager_dialogs.rb"
      Yast.include self, "packager/repositories_include.rb"
    end

    def initialize
      textdomain "packager"

      @full_mode = false

      # cache for textmode value
      @text_mode = nil

      @sourcesToDelete = []
      @reposFromDeletedServices = []

      # default (minimal) priority of a repository
      @default_priority = 99

      @priority_label = _("&Priority")

      @keeppackages_label = _("Keep Downloaded Packages")

      # current view:
      # selected service (or empty) if all services are selected
      @displayed_service = ""
      # service/repository view flag
      @repository_view = true

      # remember the original selected URL scheme
      @selected_url_scheme = ""

      @cmdline_description = {
        "id"         => "inst_source",
        # Command line help text for the repository module, %1 is "zypper"
        "help"       => Builtins.sformat(
          _(
            "Installation Repositories - This module does not support the command line " \
              "interface, use '%1' instead."
          ),
          "zypper"
        ),
        "guihandler" => fun_ref(method(:StartInstSource), "symbol ()")
      }

      # list of repositories that was already informed to the user that they are
      # managed by service
      @services_repos = []
    end

    def main
      import_modules

      if WFM.Args == [:sw_single_mode]
        Builtins.y2milestone("Started from sw_single, switching the mode")

        @full_mode = true
        @ret = StartInstSource()

        # load objects from the new repositories
        Pkg.SourceLoad if @ret != :abort

        return deep_copy(@ret)
      end

      if WFM.Args == ["refresh-enabled"]
        Builtins.y2milestone("Refresh enabled option set")
        return StartInstSource()
      end

      CommandLine.Run(@cmdline_description)
    end

    def textmode
      if @text_mode.nil?
        @text_mode = if Mode.commandline
          true
        else
          Ops.get_boolean(UI.GetDisplayInfo, "TextMode", false)
        end
      end

      @text_mode
    end

    def RemoveDeletedAddNewRepos
      ret = []

      current_sources = Pkg.SourceGetCurrent(false)
      known_repos = []
      deleted_repos = []

      # sources deleted during this script run
      Builtins.foreach(@sourceStatesIn) do |one_source|
        src_id = Builtins.tointeger(Ops.get(one_source, "SrcId"))
        deleted_repos = Builtins.add(deleted_repos, src_id) if !src_id.nil?
      end

      # sources is a copy of sourceStatesOut
      Builtins.foreach(@sourceStatesOut) do |one_source|
        src_id = Builtins.tointeger(Ops.get(one_source, "SrcId"))
        if Builtins.contains(current_sources, src_id)
          known_repos = Builtins.add(known_repos, src_id) if !src_id.nil?
          ret = Builtins.add(ret, one_source)
        else
          Builtins.y2milestone("Source %1 has been removed already", one_source)
        end
      end

      Builtins.foreach(current_sources) do |one_srcid|
        # already known repository
        next if Builtins.contains(known_repos, one_srcid)
        # already deleted repository
        next if Builtins.contains(deleted_repos, one_srcid)
        # already deleted repository
        next if Builtins.contains(SourceManager.just_removed_sources, one_srcid)
        # repository has been added recently (by some external functionality
        # that doesn't use these internal variables)
        generalData = Pkg.SourceGeneralData(one_srcid)
        Ops.set(generalData, "enabled", true)
        Ops.set(generalData, "SrcId", one_srcid)
        Builtins.y2milestone("New repository found: %1", generalData)
        ret = Builtins.add(ret, generalData)
      end

      @sourceStatesOut = deep_copy(ret)

      nil
    end

    def PriorityToString(priority)
      ret = Builtins.tostring(priority)

      # pad to 3 characters
      rest = Ops.subtract(3, Builtins.size(ret))
      while Ops.greater_than(rest, 0)
        ret = Ops.add(" ", ret)
        rest = Ops.subtract(rest, 1)
      end

      if priority == @default_priority
        ret = Ops.add(Ops.add(Ops.add(ret, " ("), _("Default")), ")")
      end

      ret
    end

    def ReposFromService(service, input)
      input = deep_copy(input)
      service = "" if service == NO_SERVICE
      Builtins.filter(input) do |repo|
        Ops.get_string(repo, "service", "") == service
      end
    end

    #     Create a table item from a map as returned by the InstSrcManager agent.
    #     @param [Hash] source The map describing the source as returned form the agent.
    #     @return An item suitable for addition to a Table.
    def createItem(index, source, repository_mode)
      source = deep_copy(source)
      id = Ops.get_integer(source, "SrcId", 0)
      generalData = Pkg.SourceGeneralData(id)
      Builtins.y2milestone("generalData(%1): %2", id, generalData)

      name = if repository_mode
        if Builtins.haskey(source, "name")
          Ops.get_string(source, "name", "")
        else
          Ops.get_locale(
            # unkown name (alias) of the source
            generalData,
            "alias",
            Ops.get_locale(generalData, "type", _("Unknown Name"))
          )
        end
      else
        Ops.get_string(source, "name", "")
      end

      priority = Ops.get_integer(source, "priority", @default_priority)
      url = if repository_mode
        Ops.get_string(generalData, "url", "")
      else
        Ops.get_string(source, "url", "")
      end
      if ![nil, "", "/"].include?(generalData["product_dir"])
        url += " (#{generalData["product_dir"]})"
      end
      service_alias = Ops.get_string(source, "service", "")
      service_name = if service_alias != ""
        Ops.get_string(Pkg.ServiceGet(service_alias), "name", "")
      else
        ""
      end

      item = if repository_mode
        Item(
          Id(index),
          PriorityToString(priority),
          if Ops.get_boolean(
            # corresponds to the "Enable/Disable" button
            source,
            "enabled",
            true
          )
            UI.Glyph(:CheckMark)
          else
            ""
          end,
          Ops.get_boolean(source, "autorefresh", true) ? UI.Glyph(:CheckMark) : "",
          # translators: unknown name for a given source
          name,
          service_name,
          url
        )
      else
        Item(
          Id(index),
          if Ops.get_boolean(
            # corresponds to the "Enable/Disable" button
            source,
            "enabled",
            true
          )
            UI.Glyph(:CheckMark)
          else
            ""
          end,
          Ops.get_boolean(source, "autorefresh", true) ? UI.Glyph(:CheckMark) : "",
          # translators: unknown name for a given source
          name,
          url
        )
      end

      deep_copy(item)
    end

    def getSourceInfo(_index, source)
      source = deep_copy(source)
      id = Ops.get_integer(source, "SrcId", 0)
      generalData = Pkg.SourceGeneralData(id)
      Builtins.y2milestone("generalData(%1): %2", id, generalData)

      # get the editable propertis from 'source' parameter,
      # get the fixed propertis from the package manager
      out = {
        "enabled"      => Ops.get_boolean(source, "enabled", true),
        "autorefresh"  => Ops.get_boolean(source, "autorefresh", true),
        "name"         => Ops.get_locale(source, "name", _("Unknown Name")),
        "url"          => Ops.get_string(generalData, "url", ""),
        "raw_url"      => Ops.get_string(generalData, "raw_url", ""),
        "type"         => Ops.get_string(generalData, "type", ""),
        "priority"     => Ops.get_integer(source, "priority", @default_priority),
        "service"      => Ops.get_string(source, "service", ""),
        "keeppackages" => Ops.get_boolean(source, "keeppackages", false)
      }
      deep_copy(out)
    end

    # Fill sources table with entries from the InstSrcManager agent.
    def fillTable(repo_mode, service_name)
      Builtins.y2milestone(
        "Filling repository table: repository mode: %1, service: %2",
        repo_mode,
        service_name
      )
      items = []

      if repo_mode
        # because Online Repositories / Community Repositories don't use
        # these internal data maps
        RemoveDeletedAddNewRepos()
      end

      itemList = repo_mode ? deep_copy(@sourceStatesOut) : deep_copy(@serviceStatesOut)

      # displaye only repositories from the selected service
      if repo_mode && service_name != ""
        itemList = ReposFromService(service_name, itemList)
      end

      numItems = Builtins.size(itemList)

      i = 0
      while Ops.less_than(i, numItems)
        items = Builtins.add(
          items,
          createItem(i, Ops.get(itemList, i, {}), repo_mode)
        )
        i = Ops.add(i, 1)
      end

      Builtins.y2milestone("New table content: %1", items)

      UI.ChangeWidget(Id(:table), :Items, items)

      nil
    end

    def repoInfoRichText(name, category, info)
      url = info["url"]
      raw_url = info["raw_url"]

      schema = Builtins.tolower(
        Ops.get_string(URL.Parse(url), "scheme", "")
      )
      icon_tag = Ops.add(
        Ops.add(
          Ops.add(Ops.add("<IMG SRC=\"", Directory.icondir), "/22x22/apps/"),
          ["cd", "dvd", "iso"].include?(schema) ? "yast-cd_update.png" : "yast-http-server.png"
        ),
        "\">&nbsp;&nbsp;&nbsp;"
      )

      url = _("Unknown") if url == ""
      raw_url = _("Unknown") if raw_url == ""

      url_string = Builtins.sformat(_("URL: %1"), url)
      if url != raw_url
        url_string += "<BR>"
        # TRANSLATORS: Raw URL is the address without expanding repo variables
        # e.g. Raw URL = http://something/$arch -> URL = http://something/x86_64
        url_string += _("Raw URL: %s") % raw_url
      end

      Builtins.sformat(
        "<P>%1<B><BIG>%2</BIG></B></P><P>%3<BR>%4</P>",
        icon_tag,
        name,
        url_string,
        category
      )
    end

    def repoInfoTerm
      if textmode
        VBox(
          Left(Heading(Id(:name), Opt(:hstretch), "")),
          Left(Label(Id(:url), Opt(:hstretch), "")),
          Left(Label(Id(:category), Opt(:hstretch), ""))
        )
      else
        VSquash(MinHeight(4, RichText(Id(:repo_info), "")))
      end
    end

    def fillRepoInfo(index, source, repo_mode, _service_name)
      source = deep_copy(source)
      info = repo_mode ? getSourceInfo(index, source) : deep_copy(source)
      if repo_mode
        Builtins.y2milestone("getSourceInfo(%1, %2): %3", index, source, info)
      end

      # heading - in case repo name not found
      name = Ops.get_locale(info, "name", _("Unknown Repository Name"))

      # label to be used instead of URL if not found
      url = Builtins.sformat(
        _("URL: %1"),
        Ops.get_locale(info, "url", _("Unknown"))
      )

      # label, %1 is repo category (eg. YUM)
      category = Builtins.sformat(
        _("Category: %1"),
        Ops.get_locale(info, "type", _("Unknown"))
      )

      # don't display category for services
      category = "" if !repo_mode

      if textmode
        UI.ChangeWidget(Id(:name), :Label, name)
        UI.ChangeWidget(Id(:url), :Label, url)
        UI.ChangeWidget(Id(:category), :Label, category)
      else
        UI.ChangeWidget(
          Id(:repo_info),
          :Value,
          repoInfoRichText(name, category, info)
        )
      end

      UI.ChangeWidget(
        Id(:enable),
        :Value,
        Ops.get_boolean(info, "enabled", true)
      )
      UI.ChangeWidget(
        Id(:autorefresh),
        :Value,
        Ops.get_boolean(info, "autorefresh", true)
      )

      if repo_mode
        # priority and keeppackages are displayed only for repositories
        UI.ChangeWidget(
          Id(:priority),
          :Value,
          Ops.get_integer(info, "priority", @default_priority)
        )
        UI.ChangeWidget(
          Id(:keeppackages),
          :Value,
          Ops.get_boolean(info, "keeppackages", false)
        )
      end

      nil
    end

    def clearRepoInfo
      if textmode
        UI.ChangeWidget(Id(:name), :Label, "")
        UI.ChangeWidget(Id(:url), :Label, "")
        UI.ChangeWidget(Id(:category), :Label, "")
      else
        UI.ChangeWidget(Id(:repo_info), :Value, "")
      end

      UI.ChangeWidget(Id(:enable), :Value, false)
      UI.ChangeWidget(Id(:autorefresh), :Value, false)

      if UI.WidgetExists(Id(:priority))
        # priority is displayed only for repositories
        UI.ChangeWidget(Id(:priority), :Value, @default_priority)
      end

      nil
    end

    def fillCurrentRepoInfo
      selected = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
      if selected.nil?
        clearRepoInfo
        return
      end

      data = if @repository_view
        if @displayed_service == ""
          Ops.get(@sourceStatesOut, selected, {})
        else
          Ops.get(
            ReposFromService(@displayed_service, @sourceStatesOut),
            selected,
            {}
          )
        end
      else
        Ops.get(@serviceStatesOut, selected, {})
      end

      fillRepoInfo(selected, data, @repository_view, @displayed_service)

      nil
    end

    # Find which repositories have to be added or deleted to ZENworks.
    # #182992: formerly we did not consider the enabled attribute.
    # But ZENworks cannot completely disable a repository (unsubscribing a
    # repository merely decreases its priority) so we consider a disabled repository
    # like a deleted one.
    # @param [Array<Hash{String => Object>}] statesOld sourceStates - In or Out
    # @param [Array<Hash{String => Object>}] statesNew sourceStates - In or Out
    # @return the list of SrcId's that are enabled in statesNew
    #  but are not enabled in statesOld
    def newSources(statesOld, statesNew)
      statesOld = deep_copy(statesOld)
      statesNew = deep_copy(statesNew)
      Builtins.y2milestone("From %1 To %2", statesOld, statesNew)
      ret = []
      seen = Builtins.listmap(statesOld) do |src|
        {
          Ops.get_integer(src, "SrcId", -1) => Ops.get_boolean(
            src,
            "enabled",
            true
          )
        }
      end
      Builtins.foreach(statesNew) do |src|
        newid = Ops.get_integer(src, "SrcId", -1)
        newena = Ops.get_boolean(src, "enabled", true)
        ret = Builtins.add(ret, newid) if newena && !Ops.get(seen, newid, false)
      end
      Builtins.y2milestone("Difference %1", ret)
      deep_copy(ret)
    end

    def newServices(statesOld, statesNew)
      statesOld = deep_copy(statesOld)
      statesNew = deep_copy(statesNew)
      Builtins.y2milestone("Services from %1 To %2", statesOld, statesNew)
      ret = []

      seen = Builtins.maplist(statesOld) do |srv|
        Ops.get_string(srv, "alias", "")
      end

      Builtins.foreach(statesNew) do |srv|
        alias_name = Ops.get_string(srv, "alias", "")
        Builtins.y2milestone("Checking %1", alias_name)
        ret = Builtins.add(ret, alias_name) if !Builtins.contains(seen, alias_name)
      end
      Builtins.y2milestone("Difference %1", ret)
      deep_copy(ret)
    end

    def deleteSource(index)
      srcid = Ops.get_integer(@sourceStatesOut, [index, "SrcId"], -1)

      if srcid != -1
        @sourcesToDelete = Builtins.add(@sourcesToDelete, srcid)
        SourceManager.just_removed_sources = Builtins.add(
          SourceManager.just_removed_sources,
          srcid
        )
      end

      @sourceStatesOut = Builtins.remove(@sourceStatesOut, index)

      nil
    end

    def deleteService(index)
      Builtins.y2milestone("Removing service: %1", index)
      @serviceStatesOut = Builtins.remove(@serviceStatesOut, index)

      nil
    end

    def Write
      success = true

      # evaluate removed and new services
      deleted_services = newServices(@serviceStatesOut, @serviceStatesIn)
      Builtins.y2milestone("Deleted services: %1", deleted_services)
      added_services = newServices(@serviceStatesIn, @serviceStatesOut)
      Builtins.y2milestone("Added services: %1", added_services)

      Builtins.foreach(deleted_services) do |alias_name|
        Builtins.y2milestone("Removing service %1", alias_name)
        success &&= Pkg.ServiceDelete(alias_name)
      end

      Builtins.y2milestone("New service config: %1", @serviceStatesOut)
      Builtins.foreach(@serviceStatesOut) do |s|
        alias_name = Ops.get_string(s, "alias", "")
        if Builtins.contains(added_services, alias_name)
          Builtins.y2milestone("Adding service %1", alias_name)
          new_url = Ops.get_string(s, "url", "")

          if new_url != ""
            Builtins.y2milestone("aliases: %1", Pkg.ServiceAliases)
            success &&= Pkg.ServiceAdd(alias_name, new_url)
            # set enabled and autorefresh flags
            success &&= Pkg.ServiceSet(alias_name, s)
          else
            Builtins.y2error("Empty URL for service %1", alias_name)
          end
        else
          Builtins.y2milestone("Modifying service %1", alias_name)
          success &&= Pkg.ServiceSet(alias_name, s)
        end
      end

      # if started from the package manager we need to call these extra
      # pkg-bindings to sync the pool state
      if @full_mode
        @sourceStatesOut.each do |src|
          srcid = src["SrcId"]
          next unless Pkg.SourceGetCurrent(false).include?(srcid)

          Pkg.SourceSetEnabled(srcid, src["enabled"])
          Pkg.SourceSetPriority(srcid, src["priority"])
        end
      end

      Builtins.y2milestone("New repo config: %1", @sourceStatesOut)
      success &&= Pkg.SourceEditSet(@sourceStatesOut)

      # we must sync before the repositories are deleted from zypp
      # otherwise we will not get their details
      added = newSources(@sourceStatesIn, @sourceStatesOut)

      Builtins.foreach(@sourcesToDelete) do |id|
        if Builtins.contains(@reposFromDeletedServices, id)
          Builtins.y2milestone(
            "Repository %1 has been already removed (belongs to a deleted service)",
            id
          )
        else
          success &&= Pkg.SourceDelete(id)
        end
      end

      refresh_enabled = Builtins.contains(WFM.Args, "refresh-enabled")

      Builtins.foreach(@sourceStatesOut) do |src_state|
        srcid = Ops.get_integer(src_state, "SrcId", -1)
        if refresh_enabled && Builtins.contains(added, srcid)
          Builtins.y2milestone("Refreshing enabled repository: %1", srcid)
          Ops.set(src_state, "do_refresh", true)
        end
        if Ops.get_boolean(src_state, "do_refresh", false)
          Builtins.y2milestone("Downloading metadata for source %1", srcid)

          success &&= Pkg.SourceRefreshNow(srcid)
        end
      end

      success &&= KeyManager.Write

      # store repositories and services in the persistent libzypp storage
      success &&= Pkg.SourceSaveAll # #176013

      success
    end

    def buildList
      ret = [
        Item(Id(:all_repositories), _("All repositories"), @repository_view),
        Item(
          Id(:all_services),
          _("All services"),
          !@repository_view && @displayed_service == ""
        )
      ]

      Builtins.foreach(@serviceStatesOut) do |srv_state|
        t = Item(
          Id(Ops.get_string(srv_state, "alias", "")),
          Builtins.sformat(
            _("Service '%1'"),
            Ops.get_string(srv_state, "name", "")
          ),
          @repository_view &&
            @displayed_service == Ops.get_string(srv_state, "alias", "")
        )
        ret = Builtins.add(ret, t)
      end

      # there is some service, so allow to filter repos without service (bnc#944504)
      if ret.size > 2
        t = Item(
          Id(NO_SERVICE_ITEM),
          # TRANSLATORS: Item in selection box that allow user to see only
          # repositories not associated with service. Sometimes called also
          # third party as they are usually repositories not provided by SUSE
          # within product subscription.
          _("Only repositories not provided by a service"),
          @repository_view &&
            @displayed_service == NO_SERVICE
        )
        ret = Builtins.add(ret, t)
      end

      ret
    end

    def RepoFilterWidget
      # combobox label
      ComboBox(Id(:service_filter), Opt(:notify), _("View"), buildList)
    end

    def UpdateCombobox
      UI.ReplaceWidget(Id(:filter_rp), RepoFilterWidget())

      nil
    end

    # return table widget definition
    # layout of the table depends on the current mode (services do not have priorities)
    def TableWidget(repository_mode)
      tabheader = if repository_mode
        Header(
          # table header - priority of the repository - keep the translation as short as possible!
          _("Priority"),
          # table header - is the repo enabled? - keep the translation as short as possible!
          Center(_("Enabled")),
          # table header - is autorefresh enabled for the repo?
          # keep the translation as short as possible!
          Center(_("Autorefresh")),
          # table header - name of the repo
          _("Name"),
          # table header - service to which the repo belongs
          _("Service"),
          # table header - URL of the repo
          _("URL")
        )
      else
        Header(
          # table header - is the repo enabled? - keep the translation as short as possible!
          Center(_("Enabled")),
          # table header - is autorefresh enabled for the repo?
          # keep the translation as short as possible!
          Center(_("Autorefresh")),
          # table header - name of the repo
          _("Name"),
          # table header - URL of the repo
          _("URL")
        )
      end

      Table(Id(:table), Opt(:notify, :immediate), tabheader, [])
    end

    def ReplaceWidgets(repo_mode)
      Builtins.y2milestone("Replacing the table widget")
      UI.ReplaceWidget(Id(:tabrp), TableWidget(repo_mode))

      UI.ReplaceWidget(
        Id(:priorp),
        if repo_mode
          IntField(
            Id(:priority),
            Opt(:notify),
            @priority_label,
            0,
            200,
            @default_priority
          )
        else
          Empty()
        end
      )
      UI.ReplaceWidget(
        Id(:keeppkg_rp),
        if repo_mode
          CheckBox(Id(:keeppackages), Opt(:notify), @keeppackages_label)
        else
          Empty()
        end
      )

      nil
    end

    def RemoveReposFromService(service_alias)
      # delete the repositories belonging to the service
      repos = ReposFromService(service_alias, @sourceStatesOut)
      Builtins.y2milestone(
        "Removing repos from service alias=%1: %2",
        service_alias,
        repos
      )

      Builtins.foreach(repos) do |repo|
        srcid = Ops.get_integer(repo, "SrcId", -1)
        if srcid != -1
          @sourcesToDelete = Builtins.add(@sourcesToDelete, srcid)
          SourceManager.just_removed_sources = Builtins.add(
            SourceManager.just_removed_sources,
            srcid
          )
        end
        @sourceStatesOut = Builtins.filter(@sourceStatesOut) do |srcstate|
          if Ops.get_integer(srcstate, "SrcId", -1) == srcid
            Builtins.y2milestone("Removing repository %1", srcstate)
            @reposFromDeletedServices = Builtins.add(
              @reposFromDeletedServices,
              srcid
            )
            next false
          end
          true
        end
      end

      nil
    end

    def SetReposStatusFromService(service_alias, enable)
      # delete the repositories belonging to the service
      repos = ReposFromService(service_alias, @sourceStatesOut)
      Builtins.y2milestone(
        "%1 repos from service alias=%2: %3",
        enable ? "Enabling" : "Disabling",
        service_alias,
        repos
      )

      Builtins.foreach(repos) do |repo|
        srcid = Ops.get_integer(repo, "SrcId", -1)
        @sourceStatesOut = Builtins.maplist(@sourceStatesOut) do |srcstate|
          if Ops.get_integer(srcstate, "SrcId", -1) == srcid
            Builtins.y2milestone(
              "%1 repository %2",
              enable ? "Enabling" : "Disabling",
              srcstate
            )
            Ops.set(srcstate, "enabled", enable)
          end
          deep_copy(srcstate)
        end
      end

      nil
    end

    def SummaryDialog
      Builtins.y2milestone("Running Summary dialog")

      # push button - refresh the selected repository now
      refreshButtonLabel = _("Re&fresh Selected")

      contents = VBox(
        Right(ReplacePoint(Id(:filter_rp), RepoFilterWidget())),
        VWeight(1, ReplacePoint(Id(:tabrp), TableWidget(@repository_view))),
        repoInfoTerm,
        # label
        Left(Label(_("Properties"))),
        HBox(
          HSquash(
            VBox(
              # check box
              Left(CheckBox(Id(:enable), Opt(:notify), _("&Enabled"))),
              # check box
              Left(
                CheckBox(
                  Id(:autorefresh),
                  Opt(:notify),
                  _("Automatically &Refresh")
                )
              )
            )
          ),
          HSpacing(1),
          HSquash(
            Bottom(
              # check box
              ReplacePoint(
                Id(:keeppkg_rp),
                CheckBox(Id(:keeppackages), Opt(:notify), @keeppackages_label)
              )
            )
          ),
          HSpacing(1),
          HSquash(
            ReplacePoint(
              Id(:priorp),
              IntField(
                Id(:priority),
                Opt(:notify),
                @priority_label,
                0,
                200,
                @default_priority
              )
            )
          ),
          HStretch()
        ),
        VSpacing(0.4),
        HBox(
          PushButton(Id(:add), Opt(:key_F3), Label.AddButton),
          PushButton(Id(:replace), Opt(:key_F4), Label.EditButton),
          PushButton(Id(:delete), Opt(:key_F5), Label.DeleteButton),
          HStretch(),
          # push button label
          PushButton(Id(:key_mgr), _("&GPG Keys...")),
          # menu button label
          MenuButton(
            Id(:menu_button),
            Opt(:key_F6),
            _("Refresh"),
            [
              Item(Id(:refresh), refreshButtonLabel),
              # menu button label
              Item(Id(:autorefresh_all), _("Refresh all Autor&efreshed")),
              # menu button label
              Item(Id(:refresh_enabled), _("Refresh all &Enabled"))
            ]
          )
        )
      )

      # dialog caption
      title = _("Configured Software Repositories")

      # help
      help_text = _(
        "<p>\nManage configured software repositories and services.</p>\n"
      )

      help_text = Ops.add(
        help_text,
        _(
          "<P>A <B>service</B> or <B>Repository Index Service (RIS) </B> is a protocol for " \
            "package repository management. A service can offer one or more software " \
            "repositories which can be dynamically changed by the service administrator.</P>"
        )
      )

      help_text = Ops.add(
        help_text,
        _(
          "<p>\n" \
            "<b>Adding a new Repository or a Service</b><br>\n" \
            "To add a new repository, use <b>Add</b> and specify the software repository or " \
            "service.\n YaST will automatically detect whether a service or a repository is " \
            "available at the entered location.\n</p>\n"
        )
      )

      # help, continued
      help_text = Ops.add(
        help_text,
        _(
          "<p>\n" \
            "To install packages from <b>CD</b>,\n" \
            "have the CD set or the DVD available.\n" \
            "</p>\n"
        )
      )

      # help, continued
      help_text = Ops.add(
        help_text,
        _(
          "<p>\n" \
            "The CDs can be copied to <b>hard disk</b>\n" \
            "and then used as a repository.\n" \
            "Insert the path name where the first\n" \
            "CD is located, for example, /data1/<b>CD1</b>.\n" \
            "Only the base path is required if all CDs are copied\n" \
            "into one directory.\n" \
            "</p>\n"
        )
      )

      # help, continued
      help_text = Ops.add(
        help_text,
        _(
          "<p>\n" \
            "<b>Modifying Status of a Repository or a Service</b><br>\n" \
            "To change a repository location, use <b>Edit</b>. To remove a repository, use\n" \
            "<b>Delete</b>. To enable or disable the repository or to change the refresh status " \
            "at initialization time, select the repository in the table and use the check boxes " \
            "below.\n</p>\n"
        )
      )

      # help text, continued
      help_text = Ops.add(
        help_text,
        _(
          "<P><B>Priority of a Repository</B><BR>\nPriority of a repository is " \
            "an integer value between 0 (the highest priority) and 200 (the lowest priority). " \
            "Default is 99. If a package is available in more repositories, " \
            "the repository with the highest priority is used.</P>\n"
        )
      )

      # help text, continued
      help_text = Ops.add(
        help_text,
        _(
          "<P>Select the appropriate option on top of the window for navigation in " \
            "repositories and services.</P>"
        )
      )
      # help text, continued
      help_text = Ops.add(
        Ops.add(
          help_text,
          _(
            "<P><B>Keep Downloaded Packages</B><BR>Check this option to keep downloaded\n" \
              "packages in a local cache so they can be reused later when the packages are\n" \
              "reinstalled. If not checked, the downloaded packages are deleted after " \
              "installation.</P>"
          )
        ),
        _(
          "<P>The default local cache is located in directory <B>/var/cache/zypp/packages</B>. " \
            "Change the location in <B>/etc/zypp/zypp.conf</B> file.</P>"
        )
      )

      Wizard.SetNextButton(:next, Label.OKButton)
      Wizard.SetAbortButton(:abort, Label.CancelButton)

      Wizard.SetContents(title, contents, help_text, false, true)
      Wizard.HideBackButton

      fillTable(@repository_view, @displayed_service)
      fillCurrentRepoInfo

      input = nil

      current = -1

      exit = false
      begin
        if !current.nil? && Ops.greater_or_equal(current, 0)
          UI.ChangeWidget(Id(:table), :CurrentItem, current)
          fillCurrentRepoInfo
        end

        current = -1

        event = UI.WaitForEvent
        input = Ops.get_symbol(event, "ID", :nothing)
        Builtins.y2debug("Input: %1", input)
        if input == :table &&
            Ops.get_string(event, "EventReason", "") == "Activated"
          input = :enable
        end

        return :add if input == :add
        if input == :next
          # store the new state
          success = Write()
          if !success
            # popup message part 1
            message1 = _(
              "Unable to save changes to the repository\nconfiguration."
            )
            details = Pkg.LastError
            Builtins.y2milestone("LastError: %1", details)
            # popup message part 2 followed by other info
            message2 = details != "" ? Ops.add(_("Details:") + "\n", details) : ""
            # popup message part 3
            message2 = Ops.add(Ops.add(message2, "\n"), _("Try again?"))

            tryagain = Popup.YesNo(Ops.add(Ops.add(message1, "\n"), message2))
            exit = true if !tryagain
          else
            exit = true
          end
        # Wizard::UserInput returns `back instead of `cancel when window is closed by WM
        elsif input == :abort || input == :cancel
          # handle cancel as abort
          input = :abort

          # no change, do not confirm exit
          if @sourceStatesOut == @sourceStatesIn
            exit = true
          else
            # popup headline
            headline = _("Abort Repository Configuration")
            # popup message
            msg = _(
              "Abort the repository configuration?\nAll changes will be lost."
            )
            exit = true if Popup.YesNoHeadline(headline, msg)
          end
        elsif input == :key_mgr
          exit = true
          # return `key_mgr;
          # start the GPG key manager
          # RunGPGKeyMgmt();
        elsif input == :service_filter
          # handle the combobox events here...
          current_item = UI.QueryWidget(Id(:service_filter), :Value)

          # rebuild the dialog if needed
          Builtins.y2milestone("Current combobox item: %1", current_item)
          update_table_widget = false

          if current_item == :all_repositories
            update_table_widget = !@repository_view || @displayed_service != ""
            Builtins.y2milestone("Switching to repository view")
            @repository_view = true
            @displayed_service = ""
          elsif current_item == :all_services
            update_table_widget = @repository_view
            Builtins.y2milestone("Switching to service view")
            @repository_view = false
            # display all services
            @displayed_service = ""
          elsif current_item == NO_SERVICE_ITEM
            update_table_widget = @repository_view
            Builtins.y2milestone("Switching to without service view")
            @repository_view = true
            # display repositories without service
            @displayed_service = NO_SERVICE
          elsif Ops.is_string?(current_item)
            # switch to the selected repository
            Builtins.y2milestone("Switching to service %1", current_item)
            @repository_view = true
            # display the selected service
            @displayed_service = Convert.to_string(current_item)

            # FIXME: always update the table?
            update_table_widget = true
          end

          # update table widget
          ReplaceWidgets(@repository_view) if update_table_widget

          # update table content
          fillTable(@repository_view, @displayed_service)
          fillCurrentRepoInfo

          # update the current item
          current = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
        else
          current = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))

          Builtins.y2debug("Current item: %1", current)

          sourceState = {}

          # global_current - 'current' that points to global sourceStatesOut
          global_current = -1

          if @repository_view
            if @displayed_service == ""
              sourceState = Ops.get(@sourceStatesOut, current, {})
              global_current = current
            elsif !current.nil?
              sources_from_service = ReposFromService(
                @displayed_service,
                @sourceStatesOut
              )
              sourceState = Ops.get(sources_from_service, current, {})

              Builtins.find(@sourceStatesOut) do |s|
                global_current = Ops.add(global_current, 1)
                Ops.get(s, "SrcId") ==
                  Ops.get_integer(sourceState, "SrcId", -1)
              end

              Builtins.y2milestone("global_current: %1", global_current)
            end
          end

          id = Ops.get_integer(sourceState, "SrcId", -1)

          if Ops.less_than(id, 0) && @repository_view &&
              @displayed_service == ""
            Builtins.y2error(
              "Unable to determine repository id, broken repository?"
            )
            next
          end

          if input == :replace
            if @repository_view
              repo_replace_handler(sourceState, global_current)
            else
              service_replace_handler(current)
            end
          elsif input == :refresh
            if @repository_view
              Pkg.SourceRefreshNow(id)

              if @full_mode && Ops.get_boolean(sourceState, "enabled", false)
                # force loading of the resolvables
                Pkg.SourceSetEnabled(id, false)
                Pkg.SourceSetEnabled(id, true)
              end
            else
              # refresh a service
              service_alias = Ops.get_string(
                Ops.get(@serviceStatesOut, current, {}),
                "alias",
                ""
              )

              Builtins.y2milestone("Refreshing service %1...", service_alias)
              Pkg.ServiceRefresh(service_alias)
            end
          elsif input == :autorefresh_all || input == :refresh_enabled
            Builtins.y2milestone(
              "Refreshing all %1 %2%3...",
              input == :refresh_enabled ? "enabled" : "autorefreshed",
              @repository_view ? "repositories" : "services",
              if @repository_view && @displayed_service != ""
                Ops.add(" from service ", @displayed_service)
              else
                ""
              end
            )

            refresh_autorefresh_only = input == :autorefresh_all
            to_refresh = 0

            data = if @repository_view
              if @displayed_service == ""
                deep_copy(@sourceStatesOut)
              else
                ReposFromService(@displayed_service, @sourceStatesOut)
              end
            else
              deep_copy(@serviceStatesOut)
            end

            Builtins.y2milestone("data: %1", data)

            Builtins.foreach(data) do |src_state|
              if Ops.get_boolean(src_state, "enabled", false) &&
                  (!refresh_autorefresh_only ||
                    Ops.get_boolean(src_state, "autorefresh", false))
                url2 = if @repository_view
                  Ops.get_string(
                    Pkg.SourceGeneralData(
                      Ops.get_integer(src_state, "SrcId", -1)
                    ),
                    "url",
                    ""
                  )
                else
                  Ops.get_string(src_state, "url", "")
                end
                schema = Builtins.tolower(Builtins.substring(url2, 0, 3))

                if schema != "cd:" && schema != "dvd"
                  to_refresh = Ops.add(to_refresh, 1)
                end
              end
            end

            Builtins.y2milestone(
              "%1 %2 will be refreshed",
              to_refresh,
              @repository_view ? "repositories" : "services"
            )

            if Ops.greater_than(to_refresh, 0)
              Wizard.CreateDialog
              # TODO: add help text
              Progress.New(
                @repository_view ? _("Refreshing Repositories") : _("Refreshing Services"),
                "",
                Ops.add(to_refresh, 1),
                [
                  @repository_view ? _("Refresh Repositories") : _("Refresh Services")
                ],
                [],
                ""
              )

              Builtins.foreach(data) do |src_state|
                if Ops.get_boolean(src_state, "enabled", false) &&
                    (!refresh_autorefresh_only ||
                      Ops.get_boolean(src_state, "autorefresh", false))
                  name = Ops.get_string(src_state, "name", "")
                  if @repository_view
                    srcid = Ops.get_integer(src_state, "SrcId", -1)

                    url2 = Ops.get_string(
                      Pkg.SourceGeneralData(
                        Ops.get_integer(src_state, "SrcId", -1)
                      ),
                      "url",
                      ""
                    )
                    schema = Builtins.tolower(Builtins.substring(url2, 0, 3))

                    if schema != "cd:" && schema != "dvd"
                      Builtins.y2milestone(
                        "Autorefreshing repository %1 (%2)",
                        srcid,
                        name
                      )

                      # progress bar label
                      Progress.Title(
                        Builtins.sformat(_("Refreshing Repository %1..."), name)
                      )

                      Pkg.SourceRefreshNow(srcid)

                      if @full_mode &&
                          Ops.get_boolean(src_state, "enabled", false)
                        # force loading of the resolvables
                        Pkg.SourceSetEnabled(srcid, false)
                        Pkg.SourceSetEnabled(srcid, true)
                      end

                      Progress.NextStep
                    else
                      Builtins.y2milestone(
                        "Skipping a CD/DVD repository %1 (%2)",
                        srcid,
                        name
                      )
                    end
                  else
                    service_alias = Ops.get_string(src_state, "alias", "")

                    # refreshing services
                    # progress bar label
                    Progress.Title(
                      Builtins.sformat(_("Refreshing Service %1..."), name)
                    )
                    Builtins.y2milestone(
                      "Refreshing service %1 (alias: %2)...",
                      name,
                      service_alias
                    )
                    Pkg.ServiceRefresh(service_alias)
                  end
                end
              end

              Progress.Finish
              Wizard.CloseDialog
            end
          elsif input == :delete
            if @repository_view
              repo_delete_handler(global_current)
            else
              service_delete_handler(current)
            end
          elsif input == :enable
            if @repository_view
              repo_enable_handler(sourceState, global_current, current)
            else
              service_enable_handler(current)
            end
          elsif input == :autorefresh
            if @repository_view
              repo_autorefresh_handler(sourceState, global_current, current)
            else
              service_autorefresh_handler(current)
            end
          elsif input == :priority
            if @repository_view
              repo_priority_handler(sourceState, global_current, current)
            else
              Builtins.y2error(
                "Ignoring event `priority: the widget should NOT be displayed in service mode!"
              )
            end
          elsif input == :keeppackages
            if @repository_view
              repo_keeppackages_handler(sourceState, global_current)
            else
              Builtins.y2error(
                "Ignoring event `keeppackages: the widget should NOT be displayed in service mode!"
              )
            end
          elsif input != :table
            Builtins.y2warning("Unknown user input: %1", input)
          end
        end
      end until exit

      Builtins.y2debug("Return: %1", input)

      input
    end

    def SortReposByPriority(repos)
      repos = deep_copy(repos)
      # check the input
      return deep_copy(repos) if repos.nil?

      # sort the maps by "repos" key (in ascending order)
      ret = Builtins.sort(repos) do |repo1, repo2|
        Ops.less_than(
          Ops.get_integer(repo1, "priority", @default_priority),
          Ops.get_integer(repo2, "priority", @default_priority)
        )
      end

      Builtins.y2milestone("SortReposByPriority: %1 -> %2", repos, ret)

      deep_copy(ret)
    end

    def StartTypeDialog
      seturl = @selected_url_scheme

      if !seturl.nil? && seturl != ""
        seturl = Ops.add(@selected_url_scheme, "://")
      end

      ret = TypeDialogOpts(true, seturl)

      if ret == :back
        @selected_url_scheme = ""
      else
        @selected_url_scheme = Ops.get_string(
          URL.Parse(SourceDialogs.GetRawURL),
          "scheme",
          ""
        )
        Builtins.y2milestone("Selected URL scheme: %1", @selected_url_scheme)

        if @selected_url_scheme.nil? || @selected_url_scheme == ""
          @selected_url_scheme = "url"
        end
      end

      ret
    end

    def url_occupied?(url)
      scheme = Builtins.tolower(Ops.get_string(URL.Parse(url), "scheme", ""))

      # alway create CD/DVD repository
      return false if scheme == "cd" || scheme == "dvd"

      ret = false

      Builtins.foreach(@sourceStatesOut) do |src|
        src_id = Builtins.tointeger(Ops.get(src, "SrcId"))
        generalData = Pkg.SourceGeneralData(src_id)
        src_url = Ops.get_string(generalData, "url", "")
        multi_modules = ![nil, "", "/"].include?(generalData["product_dir"])
        # for multi modules single url can be used for multi repositories, so
        # so it is not occupied
        if (src_url == url) && !multi_modules
          ret = true
          break
        end
      end

      Builtins.y2milestone("URL exists: %1", ret)

      ret
    end

    def StartEditDialog
      Builtins.y2milestone("Edit URL with protocol %1", @selected_url_scheme)
      ret = nil
      begin
        ret = SourceDialogs.EditDialogProtocol(@selected_url_scheme)

        if ret == :next
          url = SourceDialogs.GetURL
          occupied = url_occupied?(url)

          if occupied
            # popup question, %1 is repository URL
            if !Popup.AnyQuestion(
              "",
              Builtins.sformat(
                _(
                  "Repository %1\n" \
                    "has been already added. Each repository should be added only once.\n" \
                    "\n" \
                    "Really add the repository again?"
                ),
                URL.HidePassword(url)
              ),
              Label.YesButton,
              Label.NoButton,
              :focus_no
            )
              # ask again
              ret = nil
            end
          end
        end
      end while ret.nil?

      Builtins.y2milestone("Result: %1", ret)

      ret
    end

    def StartStoreSource
      ret = StoreSource()

      if ret == :next || ret == :abort || ret == :close
        Builtins.y2milestone("Resetting selected URL scheme")
        @selected_url_scheme = ""
      end

      ret
    end

    # main function - start the workflow
    def StartInstSource
      Wizard.CreateDialog
      Wizard.SetDesktopIcon("sw_source")

      if !@full_mode
        # dialog caption
        Wizard.SetContents(_("Initializing..."), Empty(), "", false, true)
        Pkg.TargetInit("/", true)
      end

      Wizard.SetDesktopTitleAndIcon("sw_source")

      # check whether running as root
      if !Confirm.MustBeRoot ||
          !Ops.get_boolean(PackageLock.Connect(false), "connected", false)
        UI.CloseDialog
        return :abort
      end

      PackageCallbacks.InitPackageCallbacks if !@full_mode

      # read repositories & services
      restore = !@full_mode ? Pkg.SourceRestore : true

      Builtins.y2milestone("Known services: %1", Pkg.ServiceAliases)

      if !restore
        cont = Popup.AnyQuestionRichText(
          Label.ErrorMsg,
          Ops.add(
            Ops.add(
              # Error popup
              _(
                "<p>Errors occurred while restoring the repository configuration.</p>\n"
              ) + "<p>",
              Pkg.LastError
            ),
            "</p>"
          ),
          50,
          15,
          Label.ContinueButton,
          Label.CancelButton,
          :focus_no
        )

        # really continue?
        if !cont
          Wizard.CloseDialog
          return :abort
        end
      end

      # read known GPG keys
      KeyManager.Read

      @sourceStatesIn = SortReposByPriority(Pkg.SourceEditGet)
      Builtins.y2milestone("Found repositories: %1", @sourceStatesIn)
      @sourceStatesOut = deep_copy(@sourceStatesIn)

      srv_aliases = Pkg.ServiceAliases
      # get the current services
      Builtins.foreach(srv_aliases) do |srv_alias|
        @serviceStatesIn = Builtins.add(
          @serviceStatesIn,
          Pkg.ServiceGet(srv_alias)
        )
      end

      Builtins.y2milestone("Loaded services: %1", @serviceStatesIn)

      @serviceStatesOut = deep_copy(@serviceStatesIn)

      aliases = {
        "summary" => -> { SummaryDialog() },
        "type"    => -> { StartTypeDialog() },
        "edit"    => -> { StartEditDialog() },
        "store"   => -> { StartStoreSource() },
        "keymgr"  => [-> { RunGPGKeyMgmt(false) }, true]
      }

      sequence = {
        "ws_start" => "summary",
        "summary"  => {
          add:     "type",
          edit:    "edit",
          key_mgr: "keymgr",
          abort:   :abort,
          next:    :next
        },
        "keymgr"   => { next: "summary", abort: "summary" },
        "type"     => { next: "edit", finish: "store", abort: :abort },
        "edit"     => { next: "store", abort: :abort },
        "store"    => { next: "summary", abort: "summary" }
      }

      Builtins.y2milestone("Starting repository sequence")
      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      ret
    end

    # Handle the "Delete" button in the service view
    # @param [Integer] current index of the selected item in the table
    def service_delete_handler(current)
      selected_service = @serviceStatesOut[current] || {}

      service_alias = selected_service["alias"]
      msg = _("The services of type 'plugin' cannot be removed.")
      return if !plugin_service_check(service_alias, msg)

      # yes-no popup
      return if !Popup.YesNo(
        Builtins.sformat(
          _("Delete service %1\nand its repositories?"),
          selected_service["name"]
        )
      )

      RemoveReposFromService(service_alias)

      deleteService(current)
      fillTable(@repository_view, @displayed_service)
      fillCurrentRepoInfo

      # refresh also the combobox widget
      UpdateCombobox()
    end

    # Handle the "Delete" button in the repository view
    # @param [Integer] global_current index of the repository in the @sourceStatesOut
    def repo_delete_handler(global_current)
      repo = @sourceStatesOut[global_current] || {}

      msg = _("The repositories belonging to a service of type 'plugin' cannot be removed.")
      return if !repo["service"].to_s.empty? && !plugin_service_check(repo["service"], msg)

      # yes-no popup
      return if !Popup.YesNo(_("Delete the selected repository from the list?"))

      deleteSource(global_current)
      fillTable(@repository_view, @displayed_service)
      fillCurrentRepoInfo
    end

    # Handle the "Enable" checkbox in the repository view
    # @param [Hash] sourceState the current state of the repository or service
    # @param [Integer] global_current index of the repository in the @sourceStatesOut
    # @param [Integer] current index of the selected item in the table
    def repo_enable_handler(sourceState, global_current, current)
      repo = @sourceStatesOut[global_current] || {}
      if !repo["service"].to_s.empty? && !plugin_service_check(repo["service"], repo_change_msg)
        return
      end

      warn_service_repository(sourceState)
      state = !sourceState["enabled"]
      # corresponds to the "Enable/Disable" button
      state_symbol = state ? UI.Glyph(:CheckMark) : ""
      UI.ChangeWidget(Id(:table), term(:Item, current, 1), state_symbol)
      sourceState["enabled"] = state
      @sourceStatesOut[global_current] = sourceState
    end

    # Handle the "Enable" checkbox in the service view
    # @param [Integer] current index of the selected item in the table
    def service_enable_handler(current)
      srv = @serviceStatesOut[current]
      return if !srv

      log.info("Selected service: #{srv}")
      state = !srv["enabled"]

      # disable/enable the repositories belonging to the service
      service_alias = srv["alias"]
      return if !plugin_service_check(service_alias, plugin_change_msg)

      SetReposStatusFromService(service_alias, state)

      # update the table
      state_symbol = state ? UI.Glyph(:CheckMark) : ""
      UI.ChangeWidget(Id(:table), term(:Item, current, 0), state_symbol)

      # store the change
      srv["enabled"] = state
      @serviceStatesOut[current] = srv
    end

    # Handle the "Autorefresh" checkbox in the repository view
    # @param [Hash] sourceState the current state of the repository or service
    # @param [Integer] global_current index of the repository in the @sourceStatesOut
    # @param [Integer] current index of the selected item in the table
    def repo_autorefresh_handler(sourceState, global_current, current)
      source_id = sourceState["SrcId"]
      src_data = Pkg.SourceGeneralData(source_id)
      return if !plugin_service_check(sourceState["service"], repo_change_msg)

      warn_service_repository(sourceState)

      type = src_data["type"]
      state = !sourceState["autorefresh"]

      if type == "PlainDir" && state
        # popup message
        Popup.Message(_("For the selected repository, refresh\ncannot be set."))
        return
      end

      new_symbol = state ? UI.Glyph(:CheckMark) : ""
      UI.ChangeWidget(Id(:table), term(:Item, current, 2), new_symbol)

      sourceState["autorefresh"] = state
      @sourceStatesOut[global_current] = sourceState
    end

    # Handle the "Autorefresh" checkbox in the service view
    # @param [Integer] current index of the selected item in the table
    def service_autorefresh_handler(current)
      srv = @serviceStatesOut[current]
      log.info("Selected service: #{srv}")

      service_alias = srv["alias"]
      return if !plugin_service_check(service_alias, plugin_change_msg)

      state = !srv["autorefresh"]
      # update the table
      new_symbol = state ? UI.Glyph(:CheckMark) : ""
      UI.ChangeWidget(Id(:table), term(:Item, current, 1), new_symbol)

      # store the change
      srv["autorefresh"] = state
      @serviceStatesOut[current] = srv
    end

    # Handle the "Priority" field in the repository view
    # @param [Hash] sourceState the current state of the repository or service
    # @param [Integer] global_current index of the repository in the @sourceStatesOut
    # @param [Integer] current index of the selected item in the table
    def repo_priority_handler(sourceState, global_current, current)
      return if !plugin_service_check(sourceState["service"], repo_change_msg)

      warn_service_repository(sourceState)
      # refresh the value in the table
      new_priority = UI.QueryWidget(Id(:priority), :Value)
      log.debug("New priority: #{new_priority}")

      UI.ChangeWidget(
        Id(:table),
        term(:Item, current, 0),
        PriorityToString(new_priority)
      )
      sourceState["priority"] = new_priority
      @sourceStatesOut[global_current] = sourceState
    end

    # Handle the "Keep packages" check box in the repository view
    # @param [Hash] sourceState the current state of the repository or service
    # @param [Integer] global_current index of the repository in the @sourceStatesOut
    def repo_keeppackages_handler(sourceState, global_current)
      return if !plugin_service_check(sourceState["service"], repo_change_msg)

      warn_service_repository(sourceState)

      # refresh the value in the table
      new_keep = UI.QueryWidget(Id(:keeppackages), :Value)
      log.info("New keep packages option: #{new_keep}")

      sourceState["keeppackages"] = new_keep
      @sourceStatesOut[global_current] = sourceState
    end

    # Handle the "Edit" button in the repository view
    # @param [Hash] sourceState the current state of the repository or service
    # @param [Integer] global_current index of the repository in the @sourceStatesOut
    def repo_replace_handler(sourceState, global_current)
      id = sourceState["SrcId"]
      generalData = Pkg.SourceGeneralData(id)

      return if !plugin_service_check(generalData["service"], repo_change_msg)

      # use the full URL (incl. the password) when editing it
      url2 = Pkg.SourceRawURL(id)
      old_url = url2
      plaindir = Ops.get_string(generalData, "type", "YaST") == @plaindir_type

      SourceDialogs.SetRepoName(Ops.get_string(sourceState, "name", ""))
      begin
        url2 = SourceDialogs.EditPopupType(url2, plaindir)

        break if Builtins.size(url2).zero?

        same_url = url2 == old_url

        Builtins.y2debug(
          "same_url: %1 (old: %2, new: %3)",
          same_url,
          old_url,
          url2
        )

        # special check for cd:// and dvd:// repositories
        if !same_url
          new_url_parsed = URL.Parse(url2)
          old_url_parsed = URL.Parse(old_url)

          new_url_scheme = Builtins.tolower(
            Ops.get_string(new_url_parsed, "scheme", "")
          )
          old_url_scheme = Builtins.tolower(
            Ops.get_string(old_url_parsed, "scheme", "")
          )

          # ignore cd:// <-> dvd:// changes if the path is not changed
          if (new_url_scheme == "cd" || new_url_scheme == "dvd") &&
              (old_url_scheme == "cd" || old_url_scheme == "dvd")
            # compare only directories, ignore e.g. ?device=/dev/sr0 options
            if Ops.get_string(new_url_parsed, "path", "") ==
                Ops.get_string(old_url_parsed, "path", "")
              Pkg.SourceChangeUrl(
                Ops.get_integer(sourceState, "SrcId", -1),
                url2
              )
              same_url = true
            end
          end
        end

        if !same_url || plaindir != SourceDialogs.IsPlainDir
          Builtins.y2milestone(
            "URL or plaindir flag changed, recreating the source"
          )
          # copy the refresh flag

          # get current alias
          alias_name = Ops.get_string(generalData, "alias", "alias")
          Builtins.y2milestone("Reusing alias: %1", alias_name)

          createResult = createSourceWithAlias(
            url2,
            SourceDialogs.IsPlainDir,
            Ops.get_boolean(sourceState, "do_refresh", false),
            SourceDialogs.GetRepoName,
            alias_name
          )
          if createResult == :ok
            # restore the origonal properties (enabled, autorefresh, keeppackages)
            # the added repository is at the end of the list
            idx = Ops.subtract(Builtins.size(@sourceStatesOut), 1)
            addedSource = Ops.get(@sourceStatesOut, idx, {})

            Builtins.y2milestone("Orig repo: %1", sourceState)
            Builtins.y2milestone("Added repo: %1", addedSource)

            if addedSource != {}
              auto_refresh = Ops.get_boolean(
                sourceState,
                "autorefresh",
                true
              )
              keeppackages = Ops.get_boolean(
                sourceState,
                "keeppackages",
                false
              )
              enabled = Ops.get_boolean(sourceState, "enabled", true)
              priority = Ops.get_integer(
                sourceState,
                "priority",
                @default_priority
              )
              Builtins.y2milestone(
                "Restoring the original properties: enabled: %1, autorefresh: %2, " \
                  "keeppackages: %3, priority: %4",
                enabled,
                auto_refresh,
                keeppackages,
                priority
              )

              # set the original properties
              Ops.set(addedSource, "autorefresh", auto_refresh)
              Ops.set(addedSource, "keeppackages", keeppackages)
              Ops.set(addedSource, "enabled", enabled)
              Ops.set(addedSource, "priority", priority)

              # get the ID of the old repo and mark it for removal
              srcid = Ops.get_integer(
                @sourceStatesOut,
                [global_current, "SrcId"],
                -1
              )
              if srcid != -1
                @sourcesToDelete = Builtins.add(@sourcesToDelete, srcid)
                SourceManager.just_removed_sources = Builtins.add(
                  SourceManager.just_removed_sources,
                  srcid
                )
              end

              # replace the data
              Ops.set(@sourceStatesOut, global_current, addedSource)
              # remove the duplicate at the end
              @sourceStatesOut = Builtins.remove(@sourceStatesOut, idx)

              # refresh only the name and URL in the table
              UI.ChangeWidget(
                Id(:table),
                Cell(global_current, 3),
                Ops.get_string(addedSource, "name", "")
              )
              UI.ChangeWidget(Id(:table), Cell(global_current, 5), url2)

              fillCurrentRepoInfo
            end
          end
        else
          Builtins.y2milestone(
            "URL is the same, not recreating the source"
          )

          new_name = SourceDialogs.GetRepoName
          if new_name != Ops.get_string(sourceState, "name", "")
            warn_service_repository(sourceState)

            Ops.set(sourceState, "name", new_name)
            Ops.set(@sourceStatesOut, global_current, sourceState)

            # update only the name cell in the table
            UI.ChangeWidget(
              Id(:table),
              Cell(global_current, 3),
              new_name
            )

            fillCurrentRepoInfo
          else
            Builtins.y2milestone(
              "The repository name has not been changed"
            )
          end

          createResult = :ok
        end
      end while createResult == :again # service view
    end

    # Handle the "Edit" button in the service view
    # @param [Integer] current index of the selected item in the table
    def service_replace_handler(current)
      service_info = Ops.get(@serviceStatesOut, current, {})

      service_alias = service_info["alias"]
      return if !plugin_service_check(service_alias, plugin_change_msg)

      Builtins.y2milestone("Editing service %1...", current)
      url2 = Ops.get_string(service_info, "raw_url", "")
      old_url = url2

      SourceDialogs.SetRepoName(
        Ops.get_string(service_info, "name", "")
      )
      begin
        url2 = SourceDialogs.EditPopupService(url2)

        break if Builtins.size(url2).zero?
        if url2 != old_url
          Builtins.y2milestone(
            "URL of the service has been changed, recreating the service"
          )
          # createSource() can potentially create a repository instead of a service
          # Probe for a service first must be done before creating a new service
          service_type = Pkg.ServiceProbe(url2)
          Builtins.y2milestone("Probed service type: %1", service_type)

          if !service_type.nil? && service_type != "NONE"
            createResult = createSource(
              url2,
              false,
              false,
              SourceDialogs.GetRepoName
            )
            if createResult == :ok
              deleteService(current)
              fillTable(@repository_view, @displayed_service)
              fillCurrentRepoInfo

              # refresh also the combobox widget
              UpdateCombobox()
            end
          else
            Report.Error(
              Builtins.sformat(
                _("There is no service at URL:\n%1"),
                url2
              )
            )
          end
        else
          Builtins.y2milestone(
            "URL is the same, not recreating the service"
          )
          entered_service_name = SourceDialogs.GetRepoName
          old_service_name = Ops.get_string(service_info, "name", "")

          if old_service_name != entered_service_name
            Builtins.y2milestone(
              "Updating name of the service to '%1'",
              entered_service_name
            )
            Ops.set(service_info, "name", entered_service_name)
            Ops.set(@serviceStatesOut, current, service_info)
            fillTable(@repository_view, @displayed_service)
            fillCurrentRepoInfo
            createResult = :ok

            # update the reference
            @sourceStatesOut = Builtins.maplist(@sourceStatesOut) do |src_state|
              if Ops.get_string(src_state, "service", "") == old_service_name
                Ops.set(src_state, "service", entered_service_name)
              end
              deep_copy(src_state)
            end

            # refresh also the combobox widget
            UpdateCombobox()
          end
        end
      end while createResult == :again
    end

    # The message displayed when trying to change a plugin service
    def plugin_change_msg
      # TRANSLATORS: An error message
      _("The services of type 'plugin' cannot be changed.")
    end

    # The message displayed when trying to change a repository belonging
    # to a plugin service
    def repo_change_msg
      # TRANSLATORS: An error message
      _("The repositories belonging to a service of type 'plugin' cannot be changed.")
    end

    # Check whether the service is of type "plugin", if yes display the message
    # @see https://doc.opensuse.org/projects/libzypp/SLE12SP2/zypp-plugins.html#plugin-services
    # @see https://doc.opensuse.org/projects/libzypp/SLE12SP2/zypp-services.html
    # @param [String] service_alias Alias of the service
    # @param [String] msg Error message displayed
    # @return [Boolean] true if type of service is not "plugin" or service does not exist,
    #                   false otherwise
    def plugin_service_check(service_alias, msg)
      # check whether this is a repo from a plugin based service
      serv_info = Pkg.ServiceGet(service_alias) || {}

      return true if serv_info["type"] != "plugin"

      Popup.Message(msg)
      false
    end

    # Shows a warning message when repository managed by a service
    # @param [Hash] sourceState the current state of the repository or service
    def warn_service_repository(source_state)
      msg = _("Repository '%{name}' is managed by service '%{service}'.\n"\
        "Your manual changes might be reset by the next service refresh!") % {name: source_state["name"],
        service: source_state["service"]}
      if source_state["service"] != "" && !@services_repos.include?(source_state["SrcId"])
        Popup.Warning(msg)
        @services_repos.push(source_state["SrcId"])
      end
    end
  end
end
