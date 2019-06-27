require "yast"

# Yast namespace
module Yast
  # Handling of default desktop selection
  class DefaultDesktopClass < Module
    include Yast::Logger

    PROPOSAL_ID = "DefaultDesktopPatterns".freeze

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
    end

    # Defaults when something in control file is not defined
    DEFAULT_VALUES = { # rubocop:disable Style/MutableConstant default_proc conflict
      "order"   => 99,
      "desktop" => "unknown"
    }

    # Define default for other keys that are not explicitelly mentioned
    DEFAULT_VALUES.default_proc = proc { "" }
    DEFAULT_VALUES.freeze

    # Initialize default desktop from control file if specified there
    def Init
      return if @initialized

      @initialized = true

      # See BNC #424678
      if @all_desktops.nil?
        log.info "Getting supported desktops from control file"

        # supported_desktops migh be undefined
        desktops_from_cf = ProductFeatures.GetFeature(
          "software",
          "supported_desktops"
        )

        log.info "desktops from control file #{desktops_from_cf.inspect}"
        desktops_from_cf = [] unless desktops_from_cf.is_a?(::Array)

        @all_desktops = {}

        desktops_from_cf.each do |one_desktop_cf|
          one_desktop_cf ||= {}
          desktop_name = one_desktop_cf["name"] || ""
          if desktop_name == ""
            log.error "Missing 'name' in #{one_desktop_cf}"
            next
          end

          @all_desktops[desktop_name] = desktop_entry(one_desktop_cf)
        end
      end

      default_desktop = ProductFeatures.GetStringFeature(
        "software",
        "default_desktop"
      )
      default_desktop = nil if default_desktop == ""

      log.info "Default desktop: '#{default_desktop}'"
      SetDesktop(default_desktop)

      nil
    end

    def desktop_entry(control_file_entry)
      desktop_label = control_file_entry["label_id"] || DEFAULT_VALUES["label_id"]
      # required keys
      one_desktop = {
        # BNC #449818, after switching the language name should change too
        "label_id" => desktop_label,
        "label"    => ProductControl.GetTranslatedText(desktop_label)
      }
      ["desktop", "logon", "cursor", "order"].each do |key|
        one_desktop[key] = control_file_entry[key] || DEFAULT_VALUES[key]
      end
      ["packages", "patterns"].each do |key|
        one_desktop[key] = (control_file_entry[key] || "").split
      end
      # 'description' is optional
      if control_file_entry["description_id"]
        one_desktop["description_id"] = control_file_entry["description_id"]
        one_desktop["description"] =
          ProductControl.GetTranslatedText(one_desktop["description_id"])
      end

      one_desktop
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
            PROPOSAL_ID,
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
            PROPOSAL_ID,
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
