# encoding: utf-8
require "yast"
require "uri"

# Yast namespace
module Yast
  # Provide access / dialog for product license
  class ProductLicenseClass < Module
    attr_accessor :license_patterns, :license_file_print

    include Yast::Logger

    DOWNLOAD_URL_SCHEMA = ["http", "https", "ftp"].freeze
    INFO_FILE = "/README.BETA".freeze

    def main
      Yast.import "Pkg"
      Yast.import "UI"

      Yast.import "Directory"
      Yast.import "InstShowInfo"
      Yast.import "Language"
      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "Stage"
      Yast.import "Wizard"
      Yast.import "Mode"
      Yast.import "FileUtils"
      Yast.import "ProductFeatures"
      Yast.import "String"
      Yast.import "WorkflowManager"
      Yast.import "Progress"

      # IMPORTANT: maintainer of yast2-installation is responsible for this module

      textdomain "packager"

      @license_patterns = [
        "license\\.html",
        "license\\.%1\\.html",
        "license\\.htm",
        "license\\.%1\\.htm",
        "license\\.txt",
        "license\\.%1\\.txt"
      ]
      # no more wildcard patterns here, UI can display only html and txt anyway

      initialize_default_values
    end

    # (Re)Initializes all internal caches
    def initialize_default_values
      # All licenses have their own unique ID
      @license_ids = []

      # License files by their eula_ID
      #
      # **Structure:**
      #
      #     $["ID":$[licenses]]
      @all_licenses = {}

      # filename printed in the license dialog
      @license_file_print = nil
      # license file is on installed system
      @license_on_installed_system = false

      # BNC #448598
      # no-acceptance-needed file in license.tar.gz means the license
      # doesn't have to be accepted by user, just displayed
      @license_acceptance_needed = {}

      @tmpdir = nil
      @license_dir = nil
      @info_file = nil

      @lic_lang = ""

      # FIXME: map <string, boolean> ...
      @info_file_already_seen = {}
    end

    # Returns whether accepting the license manually is requied.
    #
    # @see BNC #448598
    # @param [Any] id unique ID
    # @return [Boolean] if required
    def AcceptanceNeeded(id)
      # FIXME: lazy loading of the info about licenses, bigger refactoring needed
      # @see bsc#993285
      #
      # In the initial installation, for base product, acceptance_needed needs
      # to be known before showing the license dialog (inst_complex_welcome).
      # Loading the info is handled internally in other cases.
      #
      # id can be a string (currently is) when called from inst_complex_welcome
      if !@license_acceptance_needed.key?(id) &&
          Stage.initial &&
          id.to_s == base_product_id.to_s
        # Although we know the base product ID, the function below expects
        # id to be nil for base product in inital installation
        GetSourceLicenseDirectory(nil, "/")
        cache_license_acceptance_needed(id, @license_dir)
      end

      if @license_acceptance_needed.key?(id)
        @license_acceptance_needed[id]
      else
        log.warn "SetAcceptanceNeeded(#{id}) should be called first, using default 'true'"
        true
      end
    end

    # Sets whether explicit acceptance of a license is needed
    #
    # @param [Any] id unique ID (often a source ID)
    # @param [Boolean] new_value if needed
    def SetAcceptanceNeeded(id, new_value)
      if new_value.nil?
        Builtins.y2error(
          "Undefined behavior (License ID %1), AcceptanceNeeded: %2",
          id,
          new_value
        )
        return
      end

      @license_acceptance_needed[id] = new_value

      if new_value == true
        log.info "License agreement (ID #{id}) WILL be required"
      else
        log.info "License agreement (ID #{id}) will NOT be required"
      end

      nil
    end

    # Generic cleanup
    def CleanUp
      # BNC #581933: All license IDs are cached while the module is in memory.
      # Removing them when leaving the license dialog.
      @license_ids = []

      nil
    end

    # Ask user to confirm license agreement
    # @param [Fixnum,nil] src_id integer repository to get the license from.
    #   If set to 'nil', the license is considered to belong to a base product
    # @param [String] dir string directory to look for the license in if src_id is nil
    #   and not 1st stage installation
    # @param [Array<String>] _patterns a list of patterns for the files, regular expressions
    #   with %1 for the language
    # @param [Boolean] enable_back sets the back_button status
    # @param [Boolean] base_product defines whether it is a base or add-on product
    #   true means base product, false add-on product
    # @param [Boolean] require_agreement means that even if the license (or the very same license)
    #   has been already accepetd, ask user to accept it again (because of 'going back'
    #   in the installation proposal).
    # @param [String] id usually source id but it can be any unique id in UI
    def AskLicenseAgreement(src_id, dir, _patterns, action,
      enable_back, base_product, require_agreement, id)
      @lic_lang = ""
      licenses = {}
      available_langs = []
      license_ident = ""

      init_ret = (
        licenses_ref = arg_ref(licenses)
        available_langs_ref = arg_ref(available_langs)
        license_ident_ref = arg_ref(license_ident)
        result = InitLicenseData(
          src_id,
          dir,
          licenses_ref,
          available_langs_ref,
          require_agreement,
          license_ident_ref,
          id
        )
        licenses = licenses_ref.value
        available_langs = available_langs_ref.value
        license_ident = license_ident_ref.value
        result
      )

      if init_ret == :auto || init_ret == :accepted
        Builtins.y2milestone("Returning %1", init_ret)
        return init_ret
      end

      created_new_dialog = false

      # #459391
      # If a progress is running open another dialog
      if Progress.IsRunning
        Builtins.y2milestone(
          "Some progress is running, opening new dialog for license..."
        )
        Wizard.OpenLeftTitleNextBackDialog
        created_new_dialog = true
      end

      licenses_ref = arg_ref(licenses)

      title = _("License Agreement")

      if src_id
        repo_data = Pkg::SourceGeneralData(src_id)

        if repo_data
          label = repo_data["name"]
          # TRANSLATORS: %s is an extension name
          # e.g. "SUSE Linux Enterprise Software Development Kit"
          title = _("%s License Agreement") % label unless label.empty?
        end
      end

      DisplayLicenseDialogWithTitle(
        available_langs, # license id
        enable_back,
        @lic_lang,
        licenses_ref,
        id,
        title
      )
      licenses = licenses_ref.value

      update_license_archive_location(src_id) if src_id

      # Display info as a popup if exists
      InstShowInfo.show_info_txt(@info_file) if !@info_file.nil?

      # initial loop
      licenses_ref = arg_ref(licenses)
      ret = HandleLicenseDialogRet(
        licenses_ref,
        base_product,
        action
      )

      if ret == :accepted && !license_ident.nil?
        # store already accepted license ID
        LicenseHasBeenAccepted(license_ident)
      end

      CleanUpLicense(@tmpdir)

      # bugzilla #303922
      Wizard.CloseDialog if created_new_dialog || !Stage.initial && !src_id.nil?

      CleanUp()

      ret
    end

    # Ask user to confirm license agreement
    # @param [Array<String>] dirs - directories to look for the licenses
    # @param [Array<String>] patterns a list of patterns for the files, regular expressions
    #   with %1 for the language
    # @param [String] action what to do if the license is declined,
    #   can be "continue", "abort" or "halt"
    # @param [Boolean] enable_back sets the back_button status
    # @param [Boolean] base_product defines whether it is a base or add-on product
    #   true means base product, false add-on product
    # @param [Boolean] require_agreement means that even if the license (or the very same license)
    #   has been already accepetd, ask user to accept it again (because of 'going back'
    #   in the installation proposal).
    def AskLicensesAgreement(dirs, patterns, action, enable_back, base_product, require_agreement)
      # dialog caption
      caption = _("License Agreement")
      heading = nil

      AskLicensesAgreementWithHeading(dirs, patterns, action, enable_back,
        base_product, require_agreement, caption, heading)
    end

    # @see {AskLicensesAgreement} for details
    # @param caption [String] custom dialog title
    # @param heading [String] optional heading displayed above the license text
    def AskLicensesAgreementWithHeading(dirs, _patterns, action, enable_back,
      base_product, require_agreement, caption, heading)
      dirs = deep_copy(dirs)
      if dirs.nil? || dirs == []
        Builtins.y2error("No directories: %1", dirs)
        # error message
        Report.Error("Internal Error: No license to show")
        return :auto
      end

      created_new_dialog = false

      # #459391
      # If a progress is running open another dialog
      if Progress.IsRunning
        Builtins.y2milestone(
          "Some progress is running, opening new dialog for license..."
        )
        Wizard.OpenNextBackDialog
        created_new_dialog = true
      end

      license_idents = []

      licenses = []
      counter = -1
      contents = VBox(
        if heading
          VBox(
            VSpacing(0.5),
            Left(Heading(heading)),
            VSpacing(0.5)
          )
        else
          Empty()
        end
      )

      Builtins.foreach(dirs) do |dir|
        counter = Ops.add(counter, 1)
        Ops.set(licenses, counter, {})
        @lic_lang = ""
        available_langs = []
        license_ident = ""
        tmp_licenses = {}
        tmp_licenses_ref = arg_ref(tmp_licenses)
        available_langs_ref = arg_ref(available_langs)
        license_ident_ref = arg_ref(license_ident)
        InitLicenseData(
          nil,
          dir,
          tmp_licenses_ref,
          available_langs_ref,
          require_agreement,
          license_ident_ref,
          dir
        )
        tmp_licenses = tmp_licenses_ref.value
        available_langs = available_langs_ref.value
        license_ident = license_ident_ref.value
        if !license_ident.nil?
          license_idents = Builtins.add(license_idents, license_ident)
        end
        license_term = (
          tmp_licenses_ref = arg_ref(tmp_licenses)
          result = GetLicenseDialog(
            available_langs,
            @lic_lang,
            tmp_licenses_ref,
            dir,
            true
          )
          tmp_licenses = tmp_licenses_ref.value
          result
        )
        if license_term.nil?
          Builtins.y2error("Oops, license term is: %1", license_term)
        else
          contents = Builtins.add(contents, license_term)
        end
        # Display info as a popup if exists
        InstShowInfo.show_info_txt(@info_file) if !@info_file.nil?
        Ops.set(licenses, counter, tmp_licenses)
      end

      Wizard.SetContents(
        caption,
        contents,
        GetLicenseDialogHelp(),
        enable_back,
        true # always enable next, as popup is raised if not accepted (bnc#993530)
      )

      Wizard.SetTitleIcon("yast-license")
      Wizard.SetFocusToNextButton

      tmp_licenses = {}
      ret = (
        tmp_licenses_ref = arg_ref(tmp_licenses)
        result = HandleLicenseDialogRet(
          tmp_licenses_ref,
          base_product,
          action
        )
        result
      )
      Builtins.y2milestone("Dialog ret: %1", ret)

      # store already accepted license IDs
      Builtins.foreach(license_idents) do |license_ident|
        LicenseHasBeenAccepted(license_ident)
      end if ret == :accepted

      CleanUpLicense(@tmpdir)

      # bugzilla #303922
      Wizard.CloseDialog if created_new_dialog

      CleanUp()

      ret
    end

    def AskAddOnLicenseAgreement(src_id)
      AskLicenseAgreement(
        src_id,
        "",
        @license_patterns,
        "abort",
        # back button is disabled
        false,
        false,
        false,
        Builtins.tostring(src_id)
      )
    end

    def AskFirstStageLicenseAgreement(src_id, action)
      # bug #223258
      # disabling back button when the select-language dialog is skipped
      #
      enable_back = true
      enable_back = false if Language.selection_skipped

      AskLicenseAgreement(
        nil,
        "",
        @license_patterns,
        action,
        # back button is enabled
        enable_back,
        true,
        true,
        # unique id
        Builtins.tostring(src_id)
      )
    end

    # Called from the first stage Welcome dialog by clicking on a button
    def ShowFullScreenLicenseInInstallation(replace_point_ID, src_id)
      replace_point_ID = deep_copy(replace_point_ID)
      @lic_lang = ""
      licenses = {}
      available_langs = []
      license_ident = ""

      licenses_ref = arg_ref(licenses)
      available_langs_ref = arg_ref(available_langs)
      license_ident_ref = arg_ref(license_ident)
      InitLicenseData(
        nil,
        "",
        licenses_ref,
        available_langs_ref,
        true,
        license_ident_ref,
        Builtins.tostring(src_id)
      )
      licenses = licenses_ref.value
      available_langs = available_langs_ref.value

      # Replaces the dialog content with Languages combo-box
      # and the current license text (richtext)
      UI.ReplaceWidget(
        Id(replace_point_ID),
        (
          licenses_ref = arg_ref(licenses)
          result = GetLicenseDialogTerm(
            available_langs,
            @lic_lang,
            licenses_ref,
            Builtins.tostring(src_id)
          )
          licenses = licenses_ref.value
          result
        )
      )

      ret = nil

      loop do
        ret = UI.UserInput

        if Ops.is_string?(ret) &&
            Builtins.regexpmatch(
              Builtins.tostring(ret),
              "^license_language_[[:digit:]]+"
            )
          licenses_ref = arg_ref(licenses)
          UpdateLicenseContent(licenses_ref, GetId(Builtins.tostring(ret)))
          licenses = licenses_ref.value
        else
          break
        end
      end

      CleanUp()

      true
    end

    # Used in the first-stage Welcome dialog
    def ShowLicenseInInstallation(replace_point_ID, src_id)
      replace_point_ID = deep_copy(replace_point_ID)
      @lic_lang = ""
      licenses = {}
      available_langs = []
      license_ident = ""

      licenses_ref = arg_ref(licenses)
      available_langs_ref = arg_ref(available_langs)
      license_ident_ref = arg_ref(license_ident)
      InitLicenseData(
        nil,
        "",
        licenses_ref,
        available_langs_ref,
        true,
        license_ident_ref,
        Builtins.tostring(src_id)
      )
      licenses = licenses_ref.value

      licenses_ref = arg_ref(licenses)
      rt = GetLicenseContent(
        @lic_lang,
        licenses_ref,
        Builtins.tostring(src_id)
      )
      UI.ReplaceWidget(Id(replace_point_ID), rt)

      display_info(src_id) if @info_file && !info_seen?(src_id)

      CleanUp()

      true
    end

    def AskInstalledLicenseAgreement(directory, action)
      # patterns are hard-coded
      AskLicenseAgreement(
        nil,
        directory,
        [],
        action,
        false,
        true,
        false,
        directory
      )
    end

    # FATE #306295: More licenses in one dialog
    def AskInstalledLicensesAgreement(directories, action)
      directories = deep_copy(directories)
      # patterns are hard-coded
      AskLicensesAgreement(directories, [], action, false, true, false)
    end

    publish function: :AcceptanceNeeded, type: "boolean (string)"
    publish function: :AskLicenseAgreement,
            type:     "symbol (integer, string, list <string>, string, " \
             "boolean, boolean, boolean, string)"
    publish function: :AskAddOnLicenseAgreement, type: "symbol (integer)"
    publish function: :AskFirstStageLicenseAgreement, type: "symbol (integer, string)"
    publish function: :ShowFullScreenLicenseInInstallation, type: "boolean (any, integer)"
    publish function: :ShowLicenseInInstallation, type: "boolean (any, integer)"
    publish function: :AskInstalledLicenseAgreement, type: "symbol (string, string)"
    publish function: :AskInstalledLicensesAgreement, type: "symbol (list <string>, string)"

  private

    # check if the license location is an URL for download
    # @param [String] location
    # @return [Boolean] true if it is a HTTP, HTTPS or an FTP URL
    def location_is_url?(location)
      return false unless location.is_a?(::String)
      DOWNLOAD_URL_SCHEMA.include?(URI(location).scheme)
    rescue URI::InvalidURIError => e
      log.error "Error while parsing URL #{location.inspect}: #{e.message}"
      false
    end

    # split a long URL to multiple lines
    # @param [String] url URL
    # @return [String] URL split to multiple lines if too long
    def format_url(url)
      url.scan(/.{1,57}/).join("\n")
    end

    # crate a label describing the license URL location
    # @param [String] display_url URL to display
    # return [String] translated label
    def license_download_label(display_url)
      # TRANSLATORS: %{license_url} is an URL where the displayed license can be found
      (_("If you want to print this EULA, you can download it from\n%{license_url}") %
        { license_url: display_url })
    end

    # update license location displayed in the dialog (e.g. after license translation
    # is changed)
    # @param [String] lang language of the currently displayed license
    # @param [Yast::ArgRef] licenses reference to the list of licenses
    def update_license_location(lang, licenses)
      return if !location_is_url?(license_file_print) || !UI.WidgetExists(:printing_hint)

      # name of the license file
      file = File.basename(WhichLicenceFile(lang, licenses))

      url = URI(license_file_print)
      url.path = File.join(url.path, file)
      log.info "Updating license URL: #{url}"

      display_url = format_url(url.to_s)

      UI.ReplaceWidget(:printing_hint, Label(license_download_label(display_url)))
    end

    # update license location displayed in the dialog
    # @param [Fixnum] src_id integer repository to get the license from.
    def update_license_archive_location(src_id)
      repo_data = Pkg::SourceGeneralData(src_id)
      return unless repo_data

      src_url = repo_data["url"]
      if location_is_url?(src_url) && UI.WidgetExists(:printing_hint)
        lic_url = File.join(src_url, @license_file_print)
        UI.ReplaceWidget(:printing_hint, Label(license_download_label(lic_url)))
      end

      nil
    end

    # Display info as a popup if exists
    def display_info(id)
      if Mode.autoinst
        Builtins.y2milestone("Autoinstallation: Skipping info file...")
      else
        InstShowInfo.show_info_txt(@info_file)
        info_seen!(id)
      end
    end

    def GetLicenseContent(lic_lang, licenses, id)
      license_file = (
        licenses_ref = arg_ref(licenses.value)
        result = WhichLicenceFile(lic_lang, licenses_ref)
        licenses.value = licenses_ref.value
        result
      )

      license_text = Convert.to_string(
        SCR.Read(path(".target.string"), license_file)
      )
      if license_text.nil?
        if Mode.live_installation
          license_text = Builtins.sformat(
            "<b>%1</b><br>%2",
            Builtins.sformat(_("Cannot read license file %1"), license_file),
            _(
              "To show the product license properly, put the license.tar.gz file to " \
                "the root of the live media when building the image."
            )
          )
        else
          Report.Error(
            Builtins.sformat(_("Cannot read license file %1"), license_file)
          )
          license_text = ""
        end
      end
      rt = Empty()

      # License is HTML (or RichText)
      if Builtins.regexpmatch(license_text, "</.*>")
        rt = MinWidth(
          80,
          RichText(Id(Builtins.sformat("welcome_text_%1", id)), license_text)
        )
      else
        # License is plain text
        # details in BNC #449188
        rt = MinWidth(
          80,
          RichText(
            Id(Builtins.sformat("welcome_text_%1", id)),
            Ops.add(Ops.add("<pre>", String.EscapeTags(license_text)), "</pre>")
          )
        )
      end

      deep_copy(rt)
    end

    # Checks the string that might contain ID of a license and
    # eventually returns that id.
    # See also GetIdPlease for a better ratio of successful stories.
    def GetId(id_text)
      id = nil

      if Builtins.regexpmatch(id_text, "^license_language_.+")
        id = Builtins.regexpsub(id_text, "^license_language_(.+)", "\\1")
      else
        Builtins.y2error("Cannot get ID from %1", id_text)
      end

      id
    end

    # Helper func. Cuts encoding suffix off the LANG
    # env. variable i.e. foo_BAR.UTF-8 => foo_BAR
    def EnvLangToLangCode(env_lang)
      tmp = []
      tmp = Builtins.splitstring(env_lang, ".@") if !env_lang.nil?

      Ops.get(tmp, 0, "")
    end

    # Sets that the license (file) has been already accepted
    #
    # @param [String] license_ident file name
    def LicenseHasBeenAccepted(license_ident)
      if license_ident.nil? || license_ident == ""
        Builtins.y2error("Wrong license ID '%1'", license_ident)
        return
      end

      nil
    end

    def WhichLicenceFile(license_language, licenses)
      license_file = Ops.get(licenses.value, license_language, "")

      if license_file.nil? || license_file == ""
        Builtins.y2error(
          "No license file defined for language '%1' in %2",
          license_language,
          licenses.value
        )
      else
        Builtins.y2milestone("Using license file: %1", license_file)
      end

      license_file
    end

    def GetLicenseDialogTerm(languages, license_language, licenses, id)
      languages = deep_copy(languages)
      rt = (
        licenses_ref = arg_ref(licenses.value)
        result = GetLicenseContent(
          license_language,
          licenses_ref,
          id
        )
        licenses.value = licenses_ref.value
        result
      )

      # bug #204791, no more "languages.ycp" client
      lang_names_orig = Language.GetLanguagesMap(false)
      if lang_names_orig.nil?
        Builtins.y2error("Wrong definition of languages")
        lang_names_orig = {}
      end

      lang_names = {}

      # $[ "en" : "English (US)", "de" : "Deutsch" ]
      lang_names = Builtins.mapmap(lang_names_orig) do |code, descr|
        { code => Ops.get_string(descr, 4, "") }
      end

      # for the default fallback
      if Ops.get(lang_names, "").nil?
        # language name
        Ops.set(
          lang_names,
          "",
          Ops.get_string(lang_names_orig, ["en_US", 4], "")
        )
      end

      if Ops.get(lang_names, "en").nil?
        # language name
        Ops.set(
          lang_names,
          "en",
          Ops.get_string(lang_names_orig, ["en_US", 4], "")
        )
      end

      lang_pairs = Builtins.maplist(languages) do |l|
        name_print = Ops.get(lang_names, l, "")
        if name_print == ""
          # TODO: FIXME: the language code might be longer than 2 characters,
          # e.g. "ast_ES"
          l_short = Builtins.substring(l, 0, 2)

          Builtins.foreach(lang_names) do |k, v|
            if Builtins.substring(k, 0, 2) == l_short
              name_print = v
              next true
            end
            false
          end
        end
        [l, name_print]
      end

      # filter-out languages that don't have any name
      lang_pairs = Builtins.filter(lang_pairs) do |lang_pair|
        if Ops.get(lang_pair, 1, "") == ""
          Builtins.y2warning(
            "Unknown license language '%1', filtering out...",
            lang_pair
          )
          false
        else
          true
        end
      end

      lang_pairs = Builtins.sort(lang_pairs) do |a, b|
        # bnc#385172: must use < instead of <=, the following means:
        # strcoll(x) <= strcoll(y) && strcoll(x) != strcoll(y)
        lsorted = Builtins.lsort([Ops.get(a, 1, ""), Ops.get(b, 1, "")])
        lsorted_r = Builtins.lsort([Ops.get(b, 1, ""), Ops.get(a, 1, "")])
        Ops.get_string(lsorted, 0, "") == Ops.get(a, 1, "") &&
          lsorted == lsorted_r
      end
      langs = Builtins.maplist(lang_pairs) do |descr|
        Item(
          Id(Ops.get(descr, 0, "")),
          Ops.get(descr, 1, ""),
          Ops.get(descr, 0, "") == license_language
        )
      end

      lang_selector_options = Opt(:notify)
      # Disable in case there is no language to select
      # bugzilla #203543
      if Ops.less_or_equal(Builtins.size(langs), 1)
        lang_selector_options = Builtins.add(lang_selector_options, :disabled)
      end

      @license_ids = Builtins.toset(Builtins.add(@license_ids, id))

      VBox(
        # combo box
        Left(
          ComboBox(
            Id(Builtins.sformat("license_language_%1", id)),
            lang_selector_options,
            _("&Language"),
            langs
          )
        ),
        ReplacePoint(Id(Builtins.sformat("license_contents_rp_%1", id)), rt)
      )
    end

    # Returns source ID of the base product - initial installation only!
    # If no sources are found, returns 0.
    # FIXME: Connected to bsc#993285, refactoring needed
    #
    # return [Integer] base_product_id or 0
    def base_product_id
      raise "Base product can be only found in installation" unless Stage.initial

      # The first product in the list of known products
      # 0 is the backward-compatible default value, first installation repo always
      # gets this ID later
      current_sources = Pkg.SourceGetCurrent(true)
      current_sources.any? ? current_sources.first : 0
    end

    def GetLicenseDialog(languages, license_language, licenses, id, spare_space)
      space = UI.TextMode ? 1 : 3

      license_buttons = VBox(
        VSpacing(spare_space ? 0 : 0.5),
        Left(
          CheckBox(
            Id("eula_#{id}"),
            Opt(:notify),
            # check box label
            _("I &Agree to the License Terms.")
          )
        )
      )

      VBox(
        VSpacing(spare_space ? 0 : 1),
        HBox(
          HSpacing(2 * space),
          VBox(
            GetLicenseDialogTerm(
              languages,
              license_language,
              arg_ref(licenses.value),
              id
            ),
            if !@license_file_print.nil?
              Left(
                # FATE #302018
                ReplacePoint(
                  Id(:printing_hint),
                  Label(
                    if @license_on_installed_system
                      # TRANSLATORS: addition license information
                      # %s is replaced with the directory name
                      _("This EULA can be found in the directory\n%s") % @license_file_print
                    else
                      # TRANSLATORS: addition license information
                      # %s is replaced with the filename
                      _("If you want to print this EULA, you can find it\n" \
                        "on the first media in the file %s") %
                      @license_file_print
                    end
                  )
                )
              )
            else
              Empty()
            end,
            # BNC #448598
            # yes/no buttons exist only if needed
            # if they don't exist, user is not asked to accept the license later
            AcceptanceNeeded(id) ? license_buttons : Empty()
          ),
          HSpacing(2 * space)
        )
      )
    end

    def GetLicenseDialogHelp
      # help text
      _(
        "<p>Read the license agreement carefully and select\n" \
          "one of the available options. If you do not agree to the license agreement,\n" \
          "the configuration will be aborted.</p>\n"
      )
    end

    # Displays License dialog
    def DisplayLicenseDialog(languages, back, license_language, licenses, id)
      # dialog title
      DisplayLicenseDialogWithTitle(languages, back, license_language, licenses, id,
        _("License Agreement"))
    end

    # Displays License with Help and ( ) Yes / ( ) No radio buttons
    # @param [Array<String>] languages list of license translations
    # @param [Boolean] back enable "Back" button
    # @param [String] license_language default license language
    # @param [Hash<String,String>] licenses licenses (mapping "langugage_code" => "license")
    # @param [String] id unique license ID
    # @param [String] caption dialog title
    def DisplayLicenseDialogWithTitle(languages, back, license_language, licenses, id, caption)
      languages = deep_copy(languages)

      contents = (
        licenses_ref = arg_ref(licenses.value)
        result = GetLicenseDialog(
          languages,
          license_language,
          licenses_ref,
          id,
          false
        )
        licenses.value = licenses_ref.value
        result
      )

      Wizard.SetContents(
        caption,
        contents,
        GetLicenseDialogHelp(),
        back,
        # always allow next button, as if not accepted, it will raise popup (bnc#993530)
        true
      )

      # set the initial license download URL
      update_license_location(license_language, licenses)

      Wizard.SetTitleIcon("yast-license")
      Wizard.SetFocusToNextButton

      nil
    end

    # Removes the temporary directory for licenses
    # @param [String] tmpdir temporary directory path
    def CleanUpLicense(tmpdir)
      if !tmpdir.nil? && tmpdir != "/"
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat("rm -rf '%1'", String.Quote(tmpdir))
        )
      end

      nil
    end

    # Get all files with license existing in specified directory
    # @param [String] dir string directory to look into
    # @param [Array<String>] patterns a list of patterns for the files, regular expressions
    #   with %1 for the language
    # @return a map $[ lang_code : filename ]
    def LicenseFiles(dir, patterns)
      patterns = deep_copy(patterns)
      ret = {}

      return deep_copy(ret) if dir.nil?

      files = Convert.convert(
        SCR.Read(path(".target.dir"), dir),
        from: "any",
        to:   "list <string>"
      )
      Builtins.y2milestone("All files in license directory: %1", files)

      # no license
      return {} if files.nil?

      Builtins.foreach(patterns) do |p|
        if !Builtins.issubstring(p, "%")
          Builtins.foreach(files) do |file|
            # Possible license file names are regexp patterns
            # (see list <string> license_patterns)
            # so we should treat them as such (bnc#533026)
            if Builtins.regexpmatch(file, p)
              Ops.set(ret, "", Ops.add(Ops.add(dir, "/"), file))
            end
          end
        else
          regpat = Builtins.sformat(p, "(.+)")
          Builtins.foreach(files) do |file|
            if Builtins.regexpmatch(file, regpat)
              key = Builtins.regexpsub(file, regpat, "\\1")
              Ops.set(ret, key, Ops.add(Ops.add(dir, "/"), file))
            end
          end
        end
      end
      Builtins.y2milestone("Files containing license: %1", ret)
      deep_copy(ret)
    end

    def UnpackLicenseTgzFileToDirectory(unpack_file, to_directory)
      # License file exists
      if FileUtils.Exists(unpack_file)
        out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat(
              "\nrm -rf '%1' && mkdir -p '%1' && cd '%1' && tar -xzf '%2'\n",
              String.Quote(to_directory),
              String.Quote(unpack_file)
            )
          )
        )

        # Extracting license failed, cannot accept the license
        if Ops.get_integer(out, "exit", 0).nonzero?
          Builtins.y2error("Cannot untar license -> %1", out)
          # popup error
          Report.Error(
            _("An error occurred while preparing the installation system.")
          )
          CleanUpLicense(to_directory)
          return false
        end

        # Success
        return true

        # Nothing to unpack
      else
        Builtins.y2error("No such file: %1", unpack_file)
        return false
      end
    end

    def SearchForLicense_FirstStageBaseProduct(_src_id, _fallback_dir)
      Builtins.y2milestone("Getting license from installation product")

      license_file = "/license.tar.gz"

      if FileUtils.Exists(license_file)
        Builtins.y2milestone("Installation Product has a license")

        @tmpdir = Builtins.sformat(
          "%1/product-license/base-product/",
          Convert.to_string(SCR.Read(path(".target.tmpdir")))
        )

        if UnpackLicenseTgzFileToDirectory(license_file, @tmpdir)
          @license_dir = @tmpdir
          @license_file_print = "license.tar.gz"
        end
      else
        Builtins.y2milestone("Installation Product doesn't have a license")
      end

      @info_file = INFO_FILE if FileUtils.Exists(INFO_FILE)

      nil
    end

    def SearchForLicense_LiveCDInstallation(_src_id, _fallback_dir)
      Builtins.y2milestone("LiveCD License")

      # BNC #594042: Multiple license locations
      license_locations = ["/usr/share/doc/licenses/", "/"]

      @license_dir = nil
      @info_file = nil

      Builtins.foreach(license_locations) do |license_location|
        license_location = Builtins.sformat(
          "%1/license.tar.gz",
          license_location
        )
        if FileUtils.Exists(license_location)
          Builtins.y2milestone("Using license: %1", license_location)
          @tmpdir = Builtins.sformat(
            "%1/product-license/LiveCD/",
            Convert.to_string(SCR.Read(path(".target.tmpdir")))
          )

          if UnpackLicenseTgzFileToDirectory(license_location, @tmpdir)
            @license_dir = @tmpdir
            @license_file_print = "license.tar.gz"
          else
            CleanUpLicense(@tmpdir)
          end
          raise Break
        end
      end

      if @license_dir.nil?
        Builtins.y2milestone("No license found in: %1", license_locations)
      end

      Builtins.foreach(license_locations) do |info_location|
        info_location += INFO_FILE
        if FileUtils.Exists(info_location)
          Builtins.y2milestone("Using info file: %1", info_location)
          @info_file = info_location
          raise Break
        end
      end

      if @info_file.nil?
        Builtins.y2milestone("No info file found in: %1", license_locations)
      end

      nil
    end

    def SearchForLicense_NormalRunBaseProduct(_src_id, fallback_dir)
      Builtins.y2milestone("Using default license directory %1", fallback_dir)

      if FileUtils.Exists(fallback_dir)
        @license_dir = fallback_dir
        @license_file_print = fallback_dir
        @license_on_installed_system = true
      else
        Builtins.y2warning("Fallback dir doesn't exist %1", fallback_dir)
        @license_dir = nil
      end

      @info_file = INFO_FILE if FileUtils.Exists(INFO_FILE)

      nil
    end

    def SearchForLicense_AddOnProduct(src_id, _fallback_dir)
      Builtins.y2milestone("Getting license info from repository %1", src_id)

      @info_file = Pkg.SourceProvideDigestedFile(
        src_id, # optional
        1,
        "/media.1" + INFO_FILE,
        true
      )

      # using a separate license directory for all products
      @tmpdir = Builtins.sformat(
        "%1/product-license/%2/",
        Convert.to_string(SCR.Read(path(".target.tmpdir"))),
        src_id
      )

      # FATE #302018 comment #54
      license_file_location = "/license.tar.gz"
      license_file = Pkg.SourceProvideDigestedFile(
        src_id, # optional
        1,
        license_file_location,
        true
      )

      if !license_file.nil?
        Builtins.y2milestone("Using file %1 with licenses", license_file)

        if UnpackLicenseTgzFileToDirectory(license_file, @tmpdir)
          @license_dir = @tmpdir
          @license_file_print = "license.tar.gz"
        else
          @license_dir = nil
        end

        return
      end

      Builtins.y2milestone(
        "Licenses in %1... not supported",
        license_file_location
      )

      # New format didn't work, try the old one 1stMedia:/media.1/license.zip
      @license_dir = @tmpdir
      license_file = Pkg.SourceProvideDigestedFile(
        src_id, # optional
        1,
        "/media.1/license.zip",
        true
      )

      # no license present
      if license_file.nil?
        Builtins.y2milestone("No license present")
        @license_dir = nil
        @tmpdir = nil
        # return from the function
        return
      end

      Builtins.y2milestone("Product has a license")
      out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat(
            "\nrm -rf '%1' && mkdir -p '%1' && cd '%1' && unzip -qqo '%2'\n",
            String.Quote(@tmpdir),
            String.Quote(license_file)
          )
        )
      )

      # Extracting license failed, cannot accept the license
      if Ops.get_integer(out, "exit", 0).nonzero?
        Builtins.y2error("Cannot unzip license -> %1", out)
        # popup error
        Report.Error(
          _("An error occurred while preparing the installation system.")
        )
        CleanUpLicense(@tmpdir)
        @license_dir = nil
      else
        @license_dir = @tmpdir
        @license_file_print = "/media.1/license.zip"
      end

      nil
    end

    def GetSourceLicenseDirectory(src_id, fallback_dir)
      Builtins.y2milestone(
        "Searching for licenses... (src_id: %1, fallback_dir: %2, mode: %3, stage: %4)",
        src_id,
        fallback_dir,
        Mode.mode,
        Stage.stage
      )

      @license_file_print = nil

      # Bugzilla #299732
      # Base Product - LiveCD installation
      if Mode.live_installation
        log.info "LiveCD Installation"
        SearchForLicense_LiveCDInstallation(src_id, fallback_dir)

        # Base-product - license not in installation
        #   * Stage is not initial
        #   * source ID is not defined
      elsif !Stage.initial && src_id.nil?
        log.info "Base product, not in initial stage"
        SearchForLicense_NormalRunBaseProduct(src_id, fallback_dir)

        # Base-product - first-stage installation
        #   * Stage is initial
        #   * Source ID is not set
        # bugzilla #298342
      elsif Stage.initial && src_id.nil?
        log.info "Base product, initial stage"
        SearchForLicense_FirstStageBaseProduct(base_product_id, fallback_dir)

        # Add-on-product license
        #   * Source ID is set
      elsif !src_id.nil? && Ops.greater_than(src_id, -1)
        log.info "Add-On product"
        SearchForLicense_AddOnProduct(src_id, fallback_dir)

        # Fallback
      else
        Builtins.y2warning(
          "Source ID not defined, using fallback dir '%1'",
          fallback_dir
        )
        @license_dir = fallback_dir
      end

      Builtins.y2milestone(
        "ProductLicense settings: license_dir: %1, tmpdir: %2, info_file: %3",
        @license_dir,
        @tmpdir,
        @info_file
      )

      nil
    end

    # Finds out whether user needs to 'Agree to the license coming from a given source_id'
    #
    # @param [Any] id unique ID
    # @param [String,nil] license_dir path to directory with unpacked licenses
    def cache_license_acceptance_needed(id, license_dir)
      # license_dir can be nil if there is no license present (e.g. DUDs)
      return if license_dir.nil?

      license_acceptance_needed = !FileUtils.Exists("#{license_dir}/no-acceptance-needed")
      SetAcceptanceNeeded(id, license_acceptance_needed)
    end

    def InitLicenseData(src_id, dir, licenses, available_langs,
      _require_agreement, _license_ident, id)
      # Downloads and unpacks all licenses for a given source ID
      GetSourceLicenseDirectory(src_id, dir)
      cache_license_acceptance_needed(id, @license_dir)

      licenses.value = LicenseFiles(@license_dir, @license_patterns)

      # all other 'licenses' could be replaced by this one
      Ops.set(@all_licenses, id, licenses.value)

      return :auto if @info_file.nil? && Builtins.size(licenses.value).zero?

      # Let's do getenv here. Language::language may not be initialized
      # by now (see bnc#504803, c#28). Language::Language does only
      # sysconfig reading, which is not too useful in cases like
      # 'LANG=foo_BAR yast repositories'
      language = EnvLangToLangCode(Builtins.getenv("LANG"))

      # Preferencies how the client selects from available languages
      langs = [
        language,
        Builtins.substring(language, 0, 2), # "it_IT" -> "it"
        "en_US",
        "en_GB",
        "en",
        ""
      ] # license.txt fallback
      available_langs.value = Builtins.maplist(licenses.value) do |lang, _fn|
        lang
      end

      # "en" is the same as "", we don't need to have them both
      if Builtins.contains(available_langs.value, "en") &&
          Builtins.contains(available_langs.value, "")
        Builtins.y2milestone(
          "Removing license fallback '' as we already have 'en'..."
        )
        available_langs.value = Builtins.filter(available_langs.value) do |one_lang|
          one_lang != "en"
        end
      end

      Builtins.y2milestone("Preffered lang: %1", language)
      return :auto if Builtins.size(available_langs.value).zero? # no license available
      @lic_lang = Builtins.find(langs) { |l| Builtins.haskey(licenses.value, l) }
      @lic_lang = Ops.get(available_langs.value, 0, "") if @lic_lang.nil?

      Builtins.y2milestone("Preselected language: '%1'", @lic_lang)

      if @lic_lang.nil?
        CleanUpLicense(@tmpdir) if !@tmpdir.nil?
        return :auto
      end

      # Check whether such license hasn't been already accepted
      # Bugzilla #305503
      license_ident_lang = nil

      # We need to store the original -- not localized license ID (if possible)
      Builtins.foreach(["", "en", @lic_lang]) do |check_this|
        if Builtins.contains(available_langs.value, check_this)
          license_ident_lang = check_this
          Builtins.y2milestone(
            "Using localization '%1' (for license ID)",
            license_ident_lang
          )
          raise Break
        end
      end

      # fallback
      license_ident_lang = @lic_lang if license_ident_lang.nil?

      licenses_ref = arg_ref(licenses.value)
      WhichLicenceFile(
        license_ident_lang,
        licenses_ref
      )
      licenses.value = licenses_ref.value
      log.info "License needs to be shown"

      # bugzilla #303922
      # src_id == nil (the initial product license)
      if !src_id.nil?
        # use wizard with steps
        if Stage.initial
          # Wizard::OpenNextBackStepsDialog();
          # WorkflowManager::RedrawWizardSteps();
          Builtins.y2milestone("Initial stage, not opening any window...")
          # use normal wizard
        else
          Wizard.OpenNextBackDialog
        end
      end

      :cont
    end

    # Should have been named 'UpdateLicenseContentBasedOnSelectedLanguage' :->
    def UpdateLicenseContent(licenses, id)
      # read the selected language
      @lic_lang = Convert.to_string(
        UI.QueryWidget(Id(Builtins.sformat("license_language_%1", id)), :Value)
      )
      rp_id = Id(Builtins.sformat("license_contents_rp_%1", id))

      licenses.value = Ops.get(@all_licenses, id, {}) if licenses.value == {}

      if UI.WidgetExists(rp_id)
        UI.ReplaceWidget(
          rp_id,
          (
            licenses_ref = arg_ref(licenses.value)
            result = GetLicenseContent(
              @lic_lang,
              licenses_ref,
              id
            )
            licenses.value = licenses_ref.value
            result
          )
        )
      else
        Builtins.y2error("No such widget: %1", rp_id)
      end

      # update displayed license URL after changing the license translation
      update_license_location(@lic_lang, licenses)

      nil
    end

    def AllLicensesAccepted
      # BNC #448598
      # If buttons don't exist, eula is automatically accepted
      accepted = true
      eula_id = nil

      Builtins.foreach(@license_ids) do |one_license_id|
        if AcceptanceNeeded(one_license_id) != true
          Builtins.y2milestone(
            "License %1 does not need to be accepted",
            one_license_id
          )
          next
        end
        eula_id = Builtins.sformat("eula_%1", one_license_id)
        if UI.WidgetExists(Id(eula_id)) != true
          Builtins.y2error("Widget %1 does not exist", eula_id)
          next
        end

        # All licenses have to be accepted
        license_accepted = UI.QueryWidget(Id(eula_id), :Value)

        Builtins.y2milestone(
          "License %1 accepted: %2",
          eula_id,
          license_accepted
        )

        if !license_accepted
          accepted = false
          raise Break
        end
      end

      accepted
    end

    def AllLicensesAcceptedOrDeclined
      ret = true

      eula_id = nil
      Builtins.foreach(@license_ids) do |one_license_id|
        next if AcceptanceNeeded(one_license_id) != true
        eula_id = Builtins.sformat("eula_%1", one_license_id)
        if UI.WidgetExists(Id(eula_id)) != true
          Builtins.y2error("Widget %1 does not exist", eula_id)
        end
      end

      ret
    end

    def HandleLicenseDialogRet(licenses, base_product, action)
      ret = nil

      loop do
        ret = UI.UserInput
        log.info "User ret: #{ret}"

        if ret.is_a?(::String) && ret.start_with?("license_language_")
          licenses_ref = arg_ref(licenses.value)
          UpdateLicenseContent(licenses_ref, GetId(ret))
          licenses.value = licenses_ref.value
          ret = :language
        # bugzilla #303828
        # disabled next button unless yes/no is selected
        elsif ret.is_a?(::String) && ret.start_with?("eula_")
          Wizard.EnableNextButton if AllLicensesAcceptedOrDeclined()
        # Aborting the license dialog
        elsif ret == :abort
          # bnc#886662
          if Stage.initial
            next unless Popup.ConfirmAbort(:painless)
          else
            # popup question
            next unless Popup.YesNo(_("Really abort the add-on product installation?"))
          end

          log.warn "Aborting..."
          break
        elsif ret == :next
          if AllLicensesAccepted()
            log.info "All licenses have been accepted."
            ret = :accepted
            break
          end

          # License declined

          # message is void in case not accepting license doesn't stop the installation
          if action == "continue"
            log.info "action in case of license refusal is continue, not asking user"
            ret = :accepted
            break
          end

          if base_product
            # TODO: refactor to use same widget as in inst_complex_welcome
            # NOTE: keep in sync with inst_compex_welcome client, for grabing its translation
            # mimic inst_complex_welcome behavior see bnc#993530
            refuse_popup_text = Builtins.dgettext(
              "installation",
              "You must accept the license to install this product"
            )
            Popup.Message(refuse_popup_text)
            next
          else
            # text changed due to bug #162499
            # TRANSLATORS: text asking whether to refuse a license (Yes-No popup)
            refuse_popup_text = _("Refusing the license agreement cancels the add-on\n" \
              "product installation. Really refuse the agreement?")
            next unless Popup.YesNo(refuse_popup_text)
          end

          log.info "License has been declined."

          case action
          when "abort"
            ret = :abort
          when "halt"
            # timed ok/cancel popup
            next unless Popup.TimedOKCancel(_("The system is shutting down..."), 10)
            ret = :halt
          else
            log.error "Unknown action #{action}"
            ret = :abort
          end

          break
        elsif ret == :back
          ret = :back
          break
        else
          log.error "Unhandled input: #{ret}"
        end
      end

      log.info "Returning #{ret}"
      ret
    end

    # Check if installation info had been seen to given ID
    def info_seen?(id)
      @info_file_already_seen.fetch(id, false)
    end

    # Mark given id as seen
    def info_seen!(id)
      @info_file_already_seen[id] = true
    end
  end

  ProductLicense = ProductLicenseClass.new
  ProductLicense.main
end
