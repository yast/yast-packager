# encoding: utf-8
require "yast"

# Yast namespace
module Yast
  # Handling of default desktop selection
  class DefaultDesktopClass < Module
    def main
      textdomain "packager"

      Yast.import "ProductFeatures"
      Yast.import "ProductControl"
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
      Builtins.y2warning(
        "Wrong desktop def, missing '%1' key: %2",
        key,
        desktop_def.value
      )

      case key
      when "order"
        99
      when "desktop"
        "unknown"
      else
        ""
      end
    end

    # Initialize default desktop from control file if specified there
    def Init
      if @initialized == true
        Builtins.y2debug("Already initialized")
        return
      end

      @initialized = true

      # See BNC #424678
      if @all_desktops.nil?
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
            from: "any",
            to:   "list <map>"
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
              one_desktop_cf_ref = arg_ref(one_desktop_cf)
              result = MissingKey(one_desktop_cf_ref, "label_id")
              one_desktop_cf = one_desktop_cf_ref.value
              result
            )
          end
          # required keys
          one_desktop = {
            "desktop"  => Ops.get(one_desktop_cf, "desktop") do
              (
                one_desktop_cf_ref = arg_ref(one_desktop_cf)
                result = MissingKey(one_desktop_cf_ref, "desktop")
                one_desktop_cf = one_desktop_cf_ref.value
                result
              )
            end,
            "logon"    => Ops.get(one_desktop_cf, "logon") do
              (
                one_desktop_cf_ref = arg_ref(one_desktop_cf)
                result = MissingKey(one_desktop_cf_ref, "logon")
                one_desktop_cf = one_desktop_cf_ref.value
                result
              )
            end,
            "cursor"   => Ops.get(one_desktop_cf, "cursor") do
              (
                one_desktop_cf_ref = arg_ref(one_desktop_cf)
                result = MissingKey(one_desktop_cf_ref, "logon")
                one_desktop_cf = one_desktop_cf_ref.value
                result
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
                one_desktop_cf_ref = arg_ref(one_desktop_cf)
                result = MissingKey(one_desktop_cf_ref, "order")
                one_desktop_cf = one_desktop_cf_ref.value
                result
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
    #  @example
    #     $[
    #          "desktop ID" : $[
    #              "desktop" : "desktop to start", // DEFAULT_WM
    #              "order" : integer,
    #              "label" : _("Desktop Name Visible in Dialog (localized - initial localization)"),
    #              "label_id" : _("Desktop Name Visible in Dialog (original)"),
    #              "description" : _("Desktop description text (localized - initial localization)"),
    #              "description_id" : _("Description text of the desktop (originale)"),
    #              "patterns" : ["list", "of", "required", "patterns"],
    #              "packages" : ["list", "of", "packages", "to", "identify", "selected", "desktop"],
    #              // filename from the 64x64 directory of the current theme (without .png suffix)
    #              "icon" : "some-icon",
    #          ],
    #      ]
    def GetAllDesktopsMap
      Init()

      deep_copy(@all_desktops)
    end

    # Get the currently set default desktop, nil if none set
    # @return [String] desktop or nil
    def Desktop
      Init()

      @desktop
    end

    # Set the default desktop
    # @param [String,nil] new_desktop one of those desktops defined in control file
    #   or nil for no desktop selected
    def SetDesktop(new_desktop)
      Init()

      if new_desktop.nil?
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
        if !@desktop.nil? && @desktop != "" && !Mode.autoinst
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

    # Get the description of the currently selected desktop for the summary
    # @return [String] the description of the desktop
    def Description
      Init()

      return "" unless @desktop

      ProductControl.GetTranslatedText(
        Ops.get_string(@all_desktops, [@desktop, "label_id"], "")
      )
    end

    publish function: :SetDesktop, type: "void (string)"
    publish function: :Init, type: "void ()"
    publish function: :ForceReinit, type: "void ()"
    publish function: :GetAllDesktopsMap, type: "map <string, map> ()"
    publish function: :Desktop, type: "string ()"
    publish function: :Description, type: "string ()"
  end

  DefaultDesktop = DefaultDesktopClass.new
  DefaultDesktop.main
end
