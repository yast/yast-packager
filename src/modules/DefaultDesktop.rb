# encoding: utf-8

# File:	DefaultDesktop.rb
# Package:	Handling of default desktop selection
# Authors:	Jiri Srain <jsrain@suse.cz>
#		Lukas Ocilka <locilka@suse.cz>

require "yast"

module Yast
  class DefaultDesktopClass < Module
    def main
      Yast.import "Pkg"

      textdomain "packager"

      Yast.import "ProductFeatures"
      Yast.import "ProductControl"
      Yast.import "Installation"
      Yast.import "PackagesProposal"
      Yast.import "Mode"

      # All desktop definitions are taken from control file
      # @see GetAllDesktopsMap
      @all_desktops = nil

      # Desktop which was selected in the desktop selection dialog.
      # Must be defined in control file in section software->supported_desktops.
      @desktop = nil

      @initialized = false

      @packages_proposal_ID_patterns = "DefaultDesktopPatterns"
    end

    def MissingKey(desktop_def, key)
      ret = nil

      Builtins.y2warning(
        "Wrong desktop def, missing '%1' key: %2",
        key,
        desktop_def.value
      )

      case key
        when "order"
          ret = 99
        when "desktop"
          ret = "unknown"
        else
          ret = ""
      end

      deep_copy(ret)
    end

    # Initialize default desktop from control file if specified there
    def Init
      if @initialized == true
        Builtins.y2debug("Already initialized")
        return
      end

      @initialized = true

      # See BNC #424678
      if @all_desktops == nil
        Builtins.y2milestone("Getting supported desktops from control file")

        desktops_from_cf = []
        # supported_desktops migh be undefined
        any_desktops_from_cf = ProductFeatures.GetFeature(
          "software",
          "supported_desktops"
        )

        if any_desktops_from_cf != "" && any_desktops_from_cf != ""
          desktops_from_cf = Convert.convert(
            any_desktops_from_cf,
            :from => "any",
            :to   => "list <map>"
          )
        end

        @all_desktops = {}
        one_desktop = {}
        desktop_name = ""

        Builtins.foreach(desktops_from_cf) do |one_desktop_cf|
          desktop_name = Ops.get_string(one_desktop_cf, "name", "")
          if desktop_name == ""
            Builtins.y2error("Missing 'name' in %1", one_desktop_cf)
            next
          end
          desktop_label = Ops.get_string(one_desktop_cf, "label_id") do
            (
              one_desktop_cf_ref = arg_ref(one_desktop_cf);
              _MissingKey_result = MissingKey(one_desktop_cf_ref, "label_id");
              one_desktop_cf = one_desktop_cf_ref.value;
              _MissingKey_result
            )
          end
          # required keys
          one_desktop = {
            "desktop"  => Ops.get(one_desktop_cf, "desktop") do
              (
                one_desktop_cf_ref = arg_ref(one_desktop_cf);
                _MissingKey_result = MissingKey(one_desktop_cf_ref, "desktop");
                one_desktop_cf = one_desktop_cf_ref.value;
                _MissingKey_result
              )
            end,
            "logon"    => Ops.get(one_desktop_cf, "logon") do
              (
                one_desktop_cf_ref = arg_ref(one_desktop_cf);
                _MissingKey_result = MissingKey(one_desktop_cf_ref, "logon");
                one_desktop_cf = one_desktop_cf_ref.value;
                _MissingKey_result
              )
            end,
            "cursor"   => Ops.get(one_desktop_cf, "cursor") do
              (
                one_desktop_cf_ref = arg_ref(one_desktop_cf);
                _MissingKey_result = MissingKey(one_desktop_cf_ref, "logon");
                one_desktop_cf = one_desktop_cf_ref.value;
                _MissingKey_result
              )
            end,
            "packages" => Builtins.splitstring(
              Ops.get_string(one_desktop_cf, "packages", ""),
              " \t\n"
            ),
            "patterns" => Builtins.splitstring(
              Ops.get_string(one_desktop_cf, "patterns", ""),
              " \t\n"
            ),
            "order"    => Ops.get(one_desktop_cf, "order") do
              (
                one_desktop_cf_ref = arg_ref(one_desktop_cf);
                _MissingKey_result = MissingKey(one_desktop_cf_ref, "order");
                one_desktop_cf = one_desktop_cf_ref.value;
                _MissingKey_result
              )
            end,
            # BNC #449818, after switching the language name should change too
            "label_id" => desktop_label,
            "label"    => ProductControl.GetTranslatedText(desktop_label)
          }
          # 'icon' in optional
          if Builtins.haskey(one_desktop_cf, "icon")
            Ops.set(
              one_desktop,
              "icon",
              Ops.get_string(one_desktop_cf, "icon", "")
            )
          end
          # 'description' is optional
          if Builtins.haskey(one_desktop_cf, "description_id")
            description_id = Ops.get_string(
              one_desktop_cf,
              "description_id",
              ""
            )

            Ops.set(
              one_desktop,
              "description",
              ProductControl.GetTranslatedText(description_id)
            )
            # BNC #449818, after switching the language description should change too
            Ops.set(one_desktop, "description_id", description_id)
          end
          # bnc #431251
          # If this desktop is selected, do not deselect patterns
          if Builtins.haskey(one_desktop_cf, "do_not_deselect_patterns")
            Ops.set(
              one_desktop,
              "do_not_deselect_patterns",
              Ops.get_boolean(one_desktop_cf, "do_not_deselect_patterns", false)
            )
          end
          Ops.set(@all_desktops, desktop_name, one_desktop)
        end
      end

      default_desktop = ProductFeatures.GetStringFeature(
        "software",
        "default_desktop"
      )
      default_desktop = nil if default_desktop == ""

      Builtins.y2milestone("Default desktop: '%1'", default_desktop)
      SetDesktop(default_desktop)

      nil
    end

    # Forces new initialization...
    def ForceReinit
      @initialized = false
      Init()

      nil
    end

    # Returns map of pre-defined default system tasks
    #
    # @return [Hash{String => map}] all_system_tasks
    #
    #
    # **Structure:**
    #
    #     $[
    #          "desktop ID" : $[
    #              "desktop" : "desktop to start", // DEFAULT_WM
    #              "order" : integer,
    #              "label" : _("Desktop Name Visible in Dialog (localized - initial localization)"),
    #              "label_id" : _("Desktop Name Visible in Dialog (original)"),
    #              "description" : _("Description text of the desktop (localized - initial localization)"),
    #              "description_id" : _("Description text of the desktop (originale)"),
    #              "patterns" : ["list", "of", "required", "patterns"],
    #              "packages" : ["list", "of", "packages", "to", "identify", "selected", "desktop"],
    #              "icon" : "some-icon", // filename from the 64x64 directory of the current theme (without .png suffix)
    #          ],
    #      ]
    def GetAllDesktopsMap
      Init()

      deep_copy(@all_desktops)
    end

    # Return list installed desktops or desktop selected for installation.
    #
    # @see #GetAllDesktopsMap
    def SelectedDesktops
      Init()

      Pkg.TargetInit(Installation.destdir, true)
      Pkg.SourceStartManager(true)
      Pkg.PkgSolve(true)

      all_sel_or_inst_patterns = Builtins.maplist(
        Pkg.ResolvableProperties("", :pattern, "")
      ) do |one_pattern|
        if Ops.get_symbol(one_pattern, "status", :unknown) == :selected ||
            Ops.get_symbol(one_pattern, "status", :unknown) == :installed
          next Ops.get_string(one_pattern, "name", "")
        end
      end

      # all selected or installed patterns
      all_sel_or_inst_patterns = Builtins.filter(all_sel_or_inst_patterns) do |one_pattern|
        one_pattern != nil
      end

      selected_desktops = []
      selected = true

      Builtins.foreach(GetAllDesktopsMap()) do |desktop_name, desktop_def|
        selected = true
        Builtins.foreach(Ops.get_list(desktop_def, "patterns", [])) do |one_pattern|
          if !Builtins.contains(all_sel_or_inst_patterns, one_pattern)
            selected = false
            next
          end
        end
        if selected
          selected_desktops = Builtins.add(selected_desktops, desktop_name)
        end
      end

      deep_copy(selected_desktops)
    end

    # Get the currently set default desktop, nil if none set
    # @return [String] desktop or nil
    def Desktop
      Init()

      @desktop
    end

    # Set the default desktop
    # @param [String,nil] new_desktop one of those desktops defined in control file or nil for no desktop selected
    def SetDesktop(new_desktop)
      Init()

      if new_desktop == nil
        # Reset the selected patterns
        Builtins.y2milestone("Reseting DefaultDesktop")
        @desktop = nil

        # Do not overwrite the autoyast pattern selection by
        # the default desktop pattern selection (bnc#888981)
        unless Mode.autoinst
          PackagesProposal.SetResolvables(
            @packages_proposal_ID_patterns,
            :pattern,
            [],
            optional: true
          )
        end
      elsif !Builtins.haskey(@all_desktops, new_desktop)
        Builtins.y2error("Attempting to set desktop to unknown %1", new_desktop)
      else
        @desktop = new_desktop

        Builtins.y2milestone("New desktop has been set: %1", @desktop)

        # Do not overwrite the autoyast pattern selection by
        # the default desktop pattern selection (bnc#888981)
        if @desktop != nil && @desktop != "" && !Mode.autoinst
          # Require new patterns and packages
          PackagesProposal.SetResolvables(
            @packages_proposal_ID_patterns,
            :pattern,
            Ops.get_list(@all_desktops, [@desktop, "patterns"], []),
            optional: true
          )
        end
      end

      nil
    end

    def SelectedPatterns
      PackagesProposal.GetResolvables(@packages_proposal_ID_patterns, :pattern, optional: true)
    end

    # Deprecated: Packages are not selected by a desktop selection only patterns
    # bnc#866724
    def SelectedPackages
      []
    end

    # Get preffered window/desktop manager for the selected desktop
    # @return [String] preffered window/desktop manager, empty if no one
    def PrefferedWindowManager
      Init()

      Ops.get_string(@all_desktops, [@desktop, "desktop"], "")
    end

    # Get patterns which should be selected for currently selected desktop
    # @return a list of patterns
    def PatternsToSelect
      Init()

      Ops.get_list(@all_desktops, [@desktop, "patterns"], [])
    end

    # Get patterns which should be NOT selected for currently selected desktop
    # @return a list of patterns
    def PatternsToDeselect
      Init()

      # patterns which must be selected
      patterns_to_select = PatternsToSelect()

      patterns_to_deselect = []

      # bnc #431251
      # A dummy desktop is selected, do not deselect already selected patterns
      if Ops.get_boolean(
          @all_desktops,
          [@desktop, "do_not_deselect_patterns"],
          false
        ) == true
        Builtins.y2milestone(
          "Desktop %1 has 'do_not_deselect_patterns' set",
          @desktop
        )
      else
        # go through all known system task definitions
        Builtins.foreach(GetAllDesktopsMap()) do |one_desktop, desktop_descr|
          # all patterns required by a system type
          Builtins.foreach(Ops.get_list(desktop_descr, "patterns", [])) do |one_pattern|
            # if not required, add it to 'to deselect'
            if one_pattern != nil &&
                !Builtins.contains(patterns_to_select, one_pattern)
              patterns_to_deselect = Builtins.add(
                patterns_to_deselect,
                one_pattern
              )
            end
          end
        end
      end

      Builtins.y2milestone(
        "Patterns to deselect '%1' -> %2",
        @desktop,
        patterns_to_deselect
      )

      deep_copy(patterns_to_deselect)
    end

    # Get the description of the currently selected desktop for the summary
    # @return [String] the description of the desktop
    def Description
      Init()

      return "" unless @desktop

      ProductControl.GetTranslatedText(
        Ops.get_string(@all_desktops, [@desktop, "label_id"], "")
      )
    end

    publish :function => :SetDesktop, :type => "void (string)"
    publish :function => :Init, :type => "void ()"
    publish :function => :ForceReinit, :type => "void ()"
    publish :function => :GetAllDesktopsMap, :type => "map <string, map> ()"
    publish :function => :SelectedDesktops, :type => "list <string> ()"
    publish :function => :Desktop, :type => "string ()"
    publish :function => :SelectedPatterns, :type => "list <string> ()"
    publish :function => :SelectedPackages, :type => "list <string> ()"
    publish :function => :PrefferedWindowManager, :type => "string ()"
    publish :function => :PatternsToSelect, :type => "list <string> ()"
    publish :function => :PatternsToDeselect, :type => "list <string> ()"
    publish :function => :Description, :type => "string ()"
  end

  DefaultDesktop = DefaultDesktopClass.new
  DefaultDesktop.main
end
