# encoding: utf-8

# File:	webpin_package_search.ycp
# Package:	YaST packager - Client using Webpin XML API
# Authors:	Katarina Machalkova <kmachalkova@suse.cz>
#		Lukas Ocilka <locilka@suse.cz>
#
# $Id$
#
# This client provides UI for searching for packages
# via Webpin XML.
# See http://en.opensuse.org/Package_Search/Design for the API.
module Yast
  class WebpinPackageSearchClient < Client
    def main
      Yast.import "UI"
      textdomain "packager"

      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "Progress"
      Yast.import "Sequencer"
      Yast.import "WebpinPackageSearch"
      Yast.import "Wizard"
      Yast.import "Directory"
      Yast.import "Map"
      Yast.import "Report"

      @search_results = {}
      @all_selected = {}


      Wizard.CreateDialog

      @client_ret = MainSequence()

      Wizard.CloseDialog

      @client_ret
    end

    def SomethingSelected
      @all_selected != {}
    end

    def AbortDialog
      if SomethingSelected()
        return Popup.YesNo(_("All changes will be lost. Really exit?"))
      else
        return true
      end
    end

    def Abort
      ret = UI.PollInput

      if ret == :abort
        return AbortDialog()
      else
        return false
      end
    end

    def SearchExpression
      ret = Convert.to_string(UI.QueryWidget(Id("search_text"), :Value))

      if ret == ""
        Popup.Message(_("Search expression must not be empty!"))
        UI.SetFocus(Id("search_text"))
      end
      ret
    end

    def SearchParameters
      p = Convert.to_list(UI.QueryWidget(Id("search_in"), :SelectedItems))

      ret = Builtins.listmap(["name", "description", "contents"]) do |key|
        { key => Builtins.contains(p, key) }
      end
      #y2internal("%1", ret);
      deep_copy(ret)
    end

    def CurrentTable
      ctable = UI.WidgetExists(Id("results")) ? "results" : "all"

      ctable
    end

    def CreatePackageDescription
      ctable = CurrentTable()
      checksum = Convert.to_string(UI.QueryWidget(Id(ctable), :CurrentItem))

      citem = ctable == "results" ?
        Ops.get(@search_results, checksum, {}) :
        Ops.get(@all_selected, checksum, {})
      ret = ""

      if citem != {}
        descr = Builtins.sformat(
          _("<b>Repository URL:</b> %1<br>"),
          Ops.get_string(citem, "repoURL", "")
        )
        version = Builtins.sformat(
          _("<b>Version:</b> %1<br>"),
          Ops.get_string(citem, "version", "")
        )

        archs = Builtins.sformat(
          _("<b>Architecture:</b> %1<br>"),
          Builtins.mergestring(Ops.get_list(citem, "archs", []), ",")
        )
        ret = Ops.add(
          Ops.add(Ops.add(Ops.add("<p>", descr), version), archs),
          "</p>"
        )
      end

      UI.ChangeWidget(Id("description"), :Value, ret)

      nil
    end

    def CreatePackageListItems(results)
      results = deep_copy(results)
      pkg_items = []

      Builtins.foreach(results) do |iD, pkg_line|
        # Webpin seems to return "ppc" arch even for some i386 packages (e.g., "joe")
        # doesn't match the architecture
        #	if (! WebpinPackageSearch::MatchesCurrentArchitecture (it["archs"]:["noarch"])) {
        #	    y2milestone ("Doesn't match the current arch: %1", it);
        #	    return;
        #	}
        pkg_items = Builtins.add(
          pkg_items,
          Item(
            Id(iD),
            Ops.add(
              Ops.add(Ops.get_string(pkg_line, "name", ""), " - "),
              Ops.get_string(pkg_line, "summary", "")
            )
          )
        )
      end
      deep_copy(pkg_items)
    end

    def PopulatePackageList(results)
      results = deep_copy(results)
      items = CreatePackageListItems(results)
      ctable = CurrentTable()

      _IDs = Convert.convert(
        Builtins.toset(Map.Keys(results)),
        :from => "list",
        :to   => "list <string>"
      )
      wantedIDs = Convert.convert(
        Builtins.toset(Map.Keys(@all_selected)),
        :from => "list",
        :to   => "list <string>"
      )
      Builtins.y2milestone(
        "Package IDs: %1, previously selected: %2",
        _IDs,
        wantedIDs
      )

      if results != nil
        UI.ChangeWidget(Id(ctable), :Items, items)

        if ctable == "all"
          UI.ChangeWidget(Id(ctable), :SelectedItems, wantedIDs)
        else
          UI.ChangeWidget(
            Id(ctable),
            :SelectedItems,
            Builtins::Multiset.intersection(_IDs, wantedIDs)
          )
        end

        UI.SetFocus(Id(ctable))
      else
        UI.SetFocus(Id("search_text"))
      end

      nil
    end

    def SelectedPackages
      result = []

      Builtins.foreach(@all_selected) { |s, m| result = Builtins.add(result, m) }

      Builtins.y2milestone("Passing these data to WebPin %1", result)
      deep_copy(result)
    end

    def AddItemIfNotExists(checksum, data)
      data = deep_copy(data)
      if !Builtins.haskey(@all_selected, checksum)
        Ops.set(@all_selected, checksum, data)
      end

      nil
    end

    def RemoveItemIfExists(checksum)
      if Builtins.haskey(@all_selected, checksum)
        @all_selected = Builtins.remove(@all_selected, checksum)
      end

      nil
    end

    def UpdateSelectedPkgs
      ctable = CurrentTable()
      selected_items = Builtins.toset(
        Convert.convert(
          UI.QueryWidget(Id(ctable), :SelectedItems),
          :from => "any",
          :to   => "list <string>"
        )
      )
      other_items = []

      tt = Convert.convert(
        UI.QueryWidget(Id(ctable), :Items),
        :from => "any",
        :to   => "list <term>"
      )
      Builtins.foreach(tt) do |t|
        tmp = Ops.get_string(
          Builtins.argsof(Ops.get_term(Builtins.argsof(t), 0, term(:none))),
          0,
          ""
        )
        if !Builtins.contains(selected_items, tmp)
          other_items = Builtins.add(other_items, tmp)
        end
      end

      other_items = Builtins.toset(other_items)

      Builtins.foreach(selected_items) do |it|
        AddItemIfNotExists(it, Ops.get(@search_results, it, {}))
      end if ctable == "results"
      Builtins.foreach(other_items) { |it| RemoveItemIfExists(it) }


      Builtins.y2milestone("Selecting these packages: %1", @all_selected)

      nil
    end

    def ReadDialog
      steps = [
        _("Check Network Configuration"),
        _("Initialize Software Manager")
      ]

      actions = [
        _("Checking Network Configuration ..."),
        _("Initializing Software Manager ... ")
      ]

      Progress.New(
        _("Reading Package Search Setup..."),
        " ",
        Builtins.size(steps),
        steps,
        actions,
        _("<p>Packager is initializing...</p>")
      )

      Progress.NextStage
      return :abort if Abort()
      Builtins.sleep(100)

      Progress.NextStage
      return :abort if Abort()
      Builtins.sleep(100)

      Progress.Finish
      :next
    end

    def MainDialog
      current_search_box = MultiSelectionBox(
        Id("results"),
        Opt(:notify, :hstretch),
        "",
        []
      )
      all_pkgs_box = MultiSelectionBox(
        Id("all"),
        Opt(:notify, :hstretch),
        "",
        []
      )

      Wizard.SetContents(
        # TRANSLATORS: dialog caption
        _("Package Search"),
        VBox(
          HBox(
            VBox(
              HBox(
                Bottom(
                  InputField(
                    Id("search_text"),
                    Opt(:hstretch),
                    _("Search &Expression")
                  )
                ),
                # TRANSLATORS: push button
                HSpacing(1),
                Bottom(PushButton(Id("search"), Opt(:default), _("&Search")))
              ),
              VStretch()
            ), #,
            MultiSelectionBox(
              Id("search_in"),
              _("Search &in"),
              [
                Item(Id("name"), _("Name"), true),
                Item(Id("description"), _("Description"), true),
                Item(Id("contents"), _("Contents"))
              ]
            )
          ),
          #`RadioButtonGroup(
          #    `id(`rb),
          #    `VBox(
          #        `Left(`Label( _("Search Repositories"))),
          #        `Frame( "",
          #	    `VBox(
          #                `Left(`RadioButton(`id("current_product"),_("Current product") ) ),
          #                `Left(`RadioButton(`id("factory"),_("Factory") ) ),
          #                `VStretch()
          #	    )
          #         )
          #    )
          #)
          #)
          #),
          VWeight(
            2,
            DumbTab(
              Id("tab_bar"),
              [
                Item(Id("search_tab"), _("&Found Packages"), true),
                Item(Id("all_tab"), _("&All Selected Packages"))
              ],
              ReplacePoint(Id(:rp), current_search_box)
            )
          ),
          #`HBox(
          Left(Label(_("Package Description"))),
          #`HStretch(),
          #`CheckBox(_("Keep Package Repositories Subscribed"), true)
          #),
          VWeight(1, RichText(Id("description"), ""))
        ),
        _(
          "<p><big><b>Package Search</b></big><br>\nUse the functionality of <i>Webpin package search</i> to search in all known openSUSE build-service and openSUSE community repositories.</p>\n"
        ) +
          _(
            "<p><big><b>Security</b></big><br> The software found is often not part of the\n" +
              "distribution itself. You need to decide whether to trust the source of a\n" +
              "package. We do not take any responsibility for installing such software.</p>\n"
          ),
        #We don't need back button
        false,
        true
      )

      Wizard.SetDesktopTitleAndIcon("webpin")
      Wizard.SetAbortButton(:cancel, Label.CancelButton)

      UI.SetFocus(Id("search_text"))


      dialog_ret = nil
      while true
        dialog_ret = UI.UserInput

        UpdateSelectedPkgs() if dialog_ret != "results" && dialog_ret != "all"

        if dialog_ret == :next
          temporary_xml = Ops.add(
            Directory.tmpdir,
            "/one_click_install_temporary_file.xml"
          )

          selected_packages = SelectedPackages()

          if selected_packages == nil || Builtins.size(selected_packages) == 0
            Report.Message(_("Select packages to install."))
            UI.SetFocus(Id("results"))
            next
          end

          WebpinPackageSearch.PrepareOneClickInstallDescription(
            selected_packages,
            temporary_xml
          )

          oci = WFM.CallFunction("OneClickInstallUI", [temporary_xml])
          Builtins.y2milestone("OneClickInstallUI returned: %1", oci)
          break
        elsif dialog_ret == "search"
          UI.ChangeWidget(Id("tab_bar"), :CurrentItem, "search_tab")
          UI.ReplaceWidget(Id(:rp), current_search_box)
          search_expr = SearchExpression()

          if search_expr != ""
            search_params = SearchParameters()
            Popup.ShowFeedback("", _("Searching for packages..."))
            tmp_results = WebpinPackageSearch.SearchForPackages(
              search_expr,
              nil,
              search_params
            )
            @search_results = Builtins.listmap(tmp_results) do |m|
              { Ops.get_string(m, "checksum", "") => m }
            end
            Popup.ClearFeedback
            PopulatePackageList(@search_results)

            if @search_results == nil
              # error message
              UI.ChangeWidget(
                Id("description"),
                :Value,
                _("<p><b>Search failed</b></p>")
              )
            elsif @search_results == {}
              UI.ChangeWidget(
                Id("description"),
                :Value,
                _(
                  "<p><b>No packages matching entered criteria were found.</b></p>"
                )
              )
            else
              CreatePackageDescription()
            end
          end
          next
        elsif dialog_ret == "search_tab"
          UI.ReplaceWidget(Id(:rp), current_search_box)
          PopulatePackageList(@search_results)
          CreatePackageDescription()
        elsif dialog_ret == "all_tab"
          UI.ReplaceWidget(Id(:rp), all_pkgs_box)
          PopulatePackageList(@all_selected)
          CreatePackageDescription()
        elsif dialog_ret == "results" || dialog_ret == "all"
          CreatePackageDescription()
        elsif dialog_ret == :abort || dialog_ret == :cancel
          if AbortDialog()
            dialog_ret = :abort
            Builtins.y2milestone("Aborting...")
            break
          end
        else
          Builtins.y2error("Unknown ret: %1", dialog_ret)
        end
      end
      Convert.to_symbol(dialog_ret)
    end

    def MainSequence
      aliases =
        #	    "write"   : ``(WriteDialog())
        { "read" => lambda { ReadDialog() }, "main" => lambda { MainDialog() } }

      sequence =
        #	    "write" : $[
        #		`abort : `abort,
        #		`next  : `next
        #	    ],
        {
          "ws_start" => "read",
          "read"     => { :next => "main", :abort => :abort },
          "main"     => { :abort => :abort, :next => :next }
        }

      seq_ret = Sequencer.Run(aliases, sequence)

      Convert.to_symbol(seq_ret)
    end
  end
end

Yast::WebpinPackageSearchClient.new.main
