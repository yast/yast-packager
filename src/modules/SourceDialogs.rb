require "yast"

require "uri"
require "cgi"
require "shellwords"

Yast.import "NetworkService"

# Yast namespace
module Yast
  # Displays possibilities to install from NFS, CD or partition
  class SourceDialogsClass < Module
    # to use N_ in the class constant
    extend Yast::I18n
    include Yast::Logger

    # display a global enable/disable checkbox in URL type dialog
    attr_accessor :display_addon_checkbox
    # the status of the global checkbox
    attr_reader :addon_enabled

    # widget ID => translatable label (needs to be translated by _())
    WIDGET_LABELS = {
      # radio button
      slp:               N_("&Scan Using SLP..."),
      # radio button
      comm_repos:        N_("Commun&ity Repositories"),
      # radio button
      sccrepos:          N_("&Extensions and Modules from Registration Server..."),
      # radio button
      specify_url:       N_("Specify &URL..."),
      # radio button
      ftp:               N_("&FTP..."),
      # radio button
      http:              N_("&HTTP..."),
      # radio button
      https:             N_("HTT&PS..."),
      # radio button
      samba:             N_("S&MB/CIFS"),
      # radio button
      nfs:               N_("NF&S..."),
      # radio button
      cd:                N_("&CD..."),
      # radio button
      dvd:               N_("&DVD..."),
      # radio button
      hd:                N_("&Hard Disk..."),
      # radio button
      usb:               N_("&USB Mass Storage (USB Stick, Disk)..."),
      # radio button
      local_dir:         N_("&Local Directory..."),
      # radio button
      local_iso:         N_("&Local ISO Image..."),
      # check box
      download_metadata: N_("&Download repository description files")
    }.freeze

    # @see https://github.com/openSUSE/libzypp/blob/master/zypp/media/MediaManager.h#L163
    VALID_URL_SCHEMES = ["ftp", "tftp", "http", "https", "nfs",
                         "nfs4", "cifs", "smb", "cd", "dvd", "iso", "dir", "file", "hd"].freeze

    # repository types which need special handling
    SPECIAL_TYPES = [:slp, :cd, :dvd, :comm_repos, :sccrepos].freeze

    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "packager"

      Yast.import "Label"
      Yast.import "URL"
      Yast.import "URLRecode"
      Yast.import "Popup"
      Yast.import "CWM"
      Yast.import "SourceManager"
      Yast.import "Message"
      Yast.import "Report"
      Yast.import "NetworkPopup"
      Yast.import "String"
      Yast.import "Hostname"
      Yast.import "IP"
      Yast.import "ProductControl"
      Yast.import "ProductFeatures"
      Yast.import "Stage"
      Yast.import "WFM"

      # common functions / data

      # URL to work with
      @_url = ""

      # The repo at _url is plaindir
      @_plaindir = false

      # Repo name to work with
      @_repo_name = ""

      # value of the "download" check box
      @_download_metadata = true

      # Allow HTTPS for next repository dialog?
      @_allow_https = true

      # display a check box in type selection dialog in the next run
      # use nil to indicate the default value, true/false override the default
      @display_addon_checkbox = nil

      # CD/DVD device name to use (e.g. /dev/sr1) in case of multiple
      # devices in the system. Empty string means use the default.
      @cd_device_name = ""

      # Help text suffix for some types of the media
      @iso_help = _(
        "<p>If the location is a file holding an ISO image\nof the media, set <b>ISO Image</b>.</p>"
      )

      # Help text suffix for some types of the media
      @multi_cd_help = _(
        "<p>If the repository is on multiple media,\n" \
        "set the location of the first media of the set.</p>\n"
      )

      # Belongs to a constant, but can't be there because of `fun_ref`
      @default_cwm_fallback_functions = {
        abort: fun_ref(method(:confirm_abort?), "boolean ()")
      }

      # NFS editation widget

      @nfs_details_content = VBox(
        HBox(
          # text entry
          InputField(Id(:server), Opt(:hstretch), _("&Server Name")),
          VBox(Label(""), PushButton(Id(:nfs_browse), Label.BrowseButton))
        ),
        HBox(
          # text entry
          InputField(
            Id(:dir),
            Opt(:hstretch),
            _("&Path to Directory or ISO Image")
          ),
          VBox(
            Label(""),
            PushButton(Id(:nfs_exports_browse), Label.BrowseButton)
          )
        ),
        # checkbox label
        Left(CheckBox(Id(:ch_iso), _("&ISO Image"))),
        # checkbox label
        Left(CheckBox(Id(:ch_nfs4), _("N&FS v4 Protocol"))),
        VSpacing(0.4),
        Left(
          ComboBox(
            Id(:mount_options),
            Opt(:editable),
            _("Mount Options"),
            [
              # TRANSLATORS: "(default)" - is a combobox value and means default libzypp
              # NFS mount option (users can change it to anything else, the field is editable)
              Item(Id(:default), _("(default)"), true),
              "ro,nolock,soft,timeo=300",
              "ro,nolock,soft,timeo=300,sec=krb5p"
            ]
          )
        )
      )

      @nfs_complete_content = InputField(
        Id(:complete_url),
        Opt(:hstretch),
        _("URL of the Repository")
      )

      # dialog contents for different views

      @details_content = VBox(
        HBox(
          HSpacing(0.5),
          # frame
          Frame(_("P&rotocol"), ReplacePoint(Id(:rb_type_rp), Empty())),
          HSpacing(0.5)
        ),
        ReplacePoint(Id(:server_rp), Empty())
      )

      # input field label
      @complete_content = InputField(
        Id(:complete_url),
        Opt(:hstretch),
        _("&URL of the Repository")
      )

      # use selected editing URL part, remember the value in case the URL is wrong
      # and the dialog needs to displayed again
      @editing_parts = false

      # general data

      # Individual widgets
      @_widgets = {}

      # Captions for individual protocols
      @_caption = {
        # label / dialog caption
        "url"   => _("Repository URL"),
        # label / dialog caption
        "nfs"   => _("NFS Server"),
        # label / dialog caption
        "cd"    => _("CD or DVD Media"),
        # label / dialog caption
        "dvd"   => _("CD or DVD Media"),
        # label / dialog caption
        "hd"    => _("Hard Disk"),
        # label / dialog caption
        "usb"   => _("USB Stick or Disk"),
        # label / dialog caption
        "dir"   => _("Local Directory"),
        # label / dialog caption
        "iso"   => _("Local ISO Image"),
        # label / dialog caption
        "http"  => _("Server and Directory"),
        # label / dialog caption
        "https" => _("Server and Directory"),
        # label / dialog caption
        "ftp"   => _("Server and Directory"),
        # label / dialog caption
        "smb"   => _("Server and Directory"),
        # label / dialog caption
        "cifs"  => _("Server and Directory")
      }
    end

    # Set the URL to work with
    # @param [String] url string URL to run the dialogs with
    def SetURL(url)
      @_url = url

      parsed = URL.Parse(@_url)

      # check if it's HDD or USB
      # convert it to the internal representation
      if Ops.get_string(parsed, "scheme", "") == "hd"
        query = Ops.get_string(parsed, "query", "")

        if Builtins.regexpmatch(query, "device=/dev/disk/by-id/usb-")
          Ops.set(parsed, "scheme", "usb")

          @_url = URL.Build(parsed)
          Builtins.y2milestone(
            "URL %1 is an USB device, changing the scheme to %2",
            URL.HidePassword(url),
            @_url
          )
        end
      end

      # reset the plaindir flag
      @_plaindir = false

      nil
    end

    # Set the URL to work with, set the plaindir flag (type of the repository)
    # @param [String] url string URL to run the dialogs with
    # @param [Boolean] plaindir_type true if the repo type is plaindir
    def SetURLType(url, plaindir_type)
      SetURL(url)
      # set the flag AFTER setting the URL!
      # SetURL() resets the _plaindir flag
      @_plaindir = plaindir_type

      nil
    end

    # Return URL after the run of the dialog
    # @return [String] the URL
    def GetURL
      parsed = URL.Parse(@_url)

      # usb scheme is not valid, it's used only internally
      # convert it for external clients
      if Ops.get_string(parsed, "scheme", "") == "usb"
        Ops.set(parsed, "scheme", "hd")

        Ops.set(parsed, "path", "/") if Ops.get_string(parsed, "path", "") == ""

        URL.Build(parsed)
      else
        @_url
      end
    end

    # Return the configured URL in the dialog, do not do any conversion (return the internal value)
    # @return [String] raw internal URL
    def GetRawURL
      @_url
    end

    def IsPlainDir
      @_plaindir
    end

    # Set the RepoName to work with
    # @param [String] repo_name string RepoName to run the dialogs with
    def SetRepoName(repo_name)
      @_repo_name = repo_name

      nil
    end

    # Return RepoName after the run of the dialog
    # @return [String] the RepoName
    def GetRepoName
      @_repo_name
    end

    # Postprocess URL of an ISO image
    # @param [String] url string URL in the original form
    # @return [String] postprocessed URL
    def PostprocessISOURL(url)
      log.info "Updating ISO URL: #{URL.HidePassword(url)}"

      uri = URI(url)
      query = uri.query || ""
      params = URI.decode_www_form(query).to_h
      path = uri.path || ""
      params["iso"] = File.basename(path)

      new_url = uri.dup
      new_url.path = File.dirname(path)
      new_url.query = nil
      # URL scheme in the "url" option must be set to "dir" (or empty)
      # for a local ISO image (see https://bugzilla.suse.com/show_bug.cgi?id=919138
      # and https://en.opensuse.org/openSUSE:Libzypp_URIs#ISO_Images )
      new_url.scheme = "dir" if uri.scheme.casecmp("iso").zero?
      params["url"] = new_url.to_s
      log.info "unescaped url param #{params["url"].inspect}"

      processed = URI("")
      # libzypp do not use web encoding as in https://www.w3.org/TR/html5/forms.html#url-encoded-form-data
      # but percentage enconding only. For more details see (bsc#954813#c20)
      processed.query = URI.encode_www_form(params).gsub(/\+/, "%20")

      ret = "iso:///" + processed.to_s
      log.info "Updated URL: #{URL.HidePassword(ret)}"
      ret
    end

    # Check if URL is an ISO URL
    # @param [String] url string URL to check
    # @return [Boolean] true if URL is an ISO URL, false otherwise
    def IsISOURL(url)
      begin
        uri = URI(url)
      rescue URI::InvalidURIError
        return false
      end

      # empty or generic uri have nil scheme causing exception below (bnc#934216)
      return false if uri.scheme.nil?

      params = URI.decode_www_form(uri.query || "").to_h

      uri.scheme.casecmp("iso").zero? && params.key?("url")
    end

    # Preprocess the ISO URL to be used in the dialogs
    # @param [String] url string URL to preprocess
    # @return [String] preprocessed URL
    def PreprocessISOURL(url)
      log.info "Preprocessing ISO URL: #{URL.HidePassword(url)}"

      # empty iso is used when we adding new url
      return "" if url == "iso://"

      uri = URI(url)
      query = uri.query || ""

      # libzypp do not use web encoding as in https://www.w3.org/TR/html5/forms.html#url-encoded-form-data
      # but percentage enconding only. For more details see (bsc#954813#c20)
      params = URI.decode_www_form(query.gsub(/%20/, "+")).to_h

      param_url = params.delete("url") || ""
      processed = URI.parse(param_url)
      log.info "processed URI after escaping #{URL.HidePassword(processed.to_s)}"
      processed.scheme = "iso" if processed.scheme.casecmp("dir").zero?
      # we need to construct path from more potential sources, as url can look like
      # `iso:/subdir?iso=test.iso&path=dir%3A%2Finstall` resulting in
      # path "/install/subdir/test.iso"
      processed.path = File.join(processed.path || "", uri.path, params.delete("iso") || "")
      processed.query = URI.encode_www_form(params) unless params.empty?

      ret = processed.to_s

      log.info "Updated URL: #{URL.HidePassword(ret)}"
      ret
    end

    # check if given path points to ISO file
    # @param [String] url string URL to check
    # @return [Boolean] true if URL is ISO image
    def PathIsISO(url)
      return false if Ops.less_than(Builtins.size(url), 4)

      Builtins.substring(url, Ops.subtract(Builtins.size(url), 4), 4) == ".iso"
    end

    # Add a slash to the part of url, if it is not already present
    # @param [String] urlpart string a part of the URL
    # @return [String] urlpart with leading slash
    def Slashed(urlpart)
      return urlpart if Builtins.substring(urlpart, 0, 1) == "/"

      Ops.add("/", urlpart)
    end

    # Remove leading and trailing (and inner) spaces from the host name
    # @param [String] host string original host name
    # @return [String] host without leading and trailing spaces
    def NormalizeHost(host)
      Builtins.deletechars(host, " \t")
    end

    # Return an HBox with ok and cancel buttons for use by other dialogs.
    # @return An HBox term for use in a CreateDialog call.
    def PopupButtons
      HBox(
        PushButton(Id(:ok), Opt(:default), Label.OKButton),
        HSpacing(2),
        PushButton(Id(:cancel), Label.CancelButton)
      )
    end

    # Get scheme of a URL, also for ISO URL get scheme of the access protocol
    # @param [String] url string URL to get scheme for
    # @return [String] URL scheme
    def URLScheme(url)
      if IsISOURL(url)
        tmp_url = PreprocessISOURL(url)
        parsed = URL.Parse(tmp_url)
      else
        parsed = URL.Parse(url)
      end
      scheme = Ops.get_string(parsed, "scheme", "")

      scheme = "url" if scheme == "" || scheme.nil?
      Builtins.y2milestone(
        "URL scheme for URL %1: %2",
        URL.HidePassword(url),
        scheme
      )
      scheme
    end

    # Init function of a widget
    # @param [String] _key string widget key
    def RepoNameInit(_key)
      UI.ChangeWidget(Id(:repo_name), :Value, @_repo_name)

      nil
    end

    # Store function of a widget
    # @param [String] _key string widget key
    # @param [Hash] _event map which caused settings being stored
    def RepoNameStore(_key, _event)
      @_repo_name = Convert.to_string(UI.QueryWidget(Id(:repo_name), :Value))

      nil
    end

    def RepoNameValidate(_key, _event)
      repo_name = Convert.to_string(UI.QueryWidget(Id(:repo_name), :Value))
      if repo_name == "" && @_repo_name != "" # do not fail on new repo creation
        UI.SetFocus(Id(:repo_name))
        # popup message
        Popup.Message(_("The name of the repository cannot be empty."))
        return false
      end
      true
    end

    # Get widget description map
    # @return widget description map
    def RepoNameWidget
      {
        "widget"            => :custom,
        "custom_widget"     => VBox(
          # text entry
          InputField(Id(:repo_name), Opt(:hstretch), _("&Repository Name"))
        ),
        "init"              => fun_ref(method(:RepoNameInit), "void (string)"),
        "store"             => fun_ref(
          method(:RepoNameStore),
          "void (string, map)"
        ),
        "validate_type"     => :function,
        # TODO: FIXME: RepoName can be empty if the URL has been changed,
        # yast will use the product name or the URL in this case (the repository is recreated)
        "validate_function" => fun_ref(
          method(:RepoNameValidate),
          "boolean (string, map)"
        ),
        # help text
        "help"              => _(
          "<p><big><b>Repository Name</b></big><br>\nUse <b>Repository Name</b> " \
          "to specify the name of the repository. If it is empty, " \
          "YaST will use the product name (if available) or the URL as the name.</p>\n"
        )
      }
    end

    def ServiceNameWidget
      ret = RepoNameWidget()

      Ops.set(
        ret,
        "custom_widget",
        VBox(
          # text entry
          InputField(Id(:repo_name), Opt(:hstretch), _("&Service Name"))
        )
      )

      # help text
      Ops.set(
        ret,
        "help",
        _(
          "<p><big><b>Service Name</b></big><br>\n" \
          "Use <b>Service Name</b> to specify the name of the service. " \
          "If it is empty, YaST will use part of the service URL as the name.</p>\n"
        )
      )

      deep_copy(ret)
    end

    # raw URL editation widget

    # Init function of a widget
    # @param [String] _key string widget key
    def PlainURLInit(_key)
      UI.ChangeWidget(Id(:url), :Value, @_url)
      UI.SetFocus(:url)

      nil
    end

    # Store function of a widget
    # @param [String] _key string widget key
    # @param [Hash] _event map which caused settings being stored
    def PlainURLStore(_key, _event)
      @_url = Convert.to_string(UI.QueryWidget(Id(:url), :Value))

      nil
    end

    def PlainURLValidate(_key, _event)
      url = Convert.to_string(UI.QueryWidget(Id(:url), :Value))
      if url == ""
        UI.SetFocus(Id(:url))
        # popup message
        Popup.Message(_("URL cannot be empty."))
        return false
      end

      valid_scheme?(url)
    end

    # Get widget description map
    # @return widget description map
    def PlainURLWidget
      {
        "widget"            => :custom,
        "custom_widget"     => VBox(
          # text entry
          InputField(Id(:url), Opt(:hstretch), _("&URL"))
        ),
        "init"              => fun_ref(method(:PlainURLInit), "void (string)"),
        "store"             => fun_ref(
          method(:PlainURLStore),
          "void (string, map)"
        ),
        "validate_type"     => :function,
        "validate_function" => fun_ref(
          method(:PlainURLValidate),
          "boolean (string, map)"
        ),
        # help text
        "help"              => Ops.add(
          _(
            "<p><big><b>Repository URL</b></big><br>\n" \
            "Use <b>URL</b> to specify the URL of the repository.</p>"
          ),
          @multi_cd_help
        )
      }
    end

    # Init function of a widget
    # @param [String] _key string widget key
    def NFSInit(_key)
      # check the current edit type
      current_type = Convert.to_symbol(UI.QueryWidget(Id(:edit_type), :Value))
      Builtins.y2debug("Current edit type: %1", current_type)

      UI.ReplaceWidget(
        Id(:edit_content),
        (current_type == :edit_url_parts) ? @nfs_details_content : @nfs_complete_content
      )

      if current_type == :edit_url_parts
        iso = IsISOURL(@_url)

        repo_url = @_url

        repo_url = PreprocessISOURL(repo_url) if iso

        parsed = URL.Parse(repo_url)
        UI.ChangeWidget(Id(:server), :Value, Ops.get_string(parsed, "host", ""))
        UI.ChangeWidget(Id(:dir), :Value, Ops.get_string(parsed, "path", ""))
        UI.ChangeWidget(Id(:ch_iso), :Value, iso)
        UI.SetFocus(:server)

        query_map = URL.MakeMapFromParams(Ops.get_string(parsed, "query", ""))

        nfs4 = Builtins.tolower(Ops.get_string(parsed, "scheme", "nfs")) == "nfs4" ||
          Ops.get_string(query_map, "type", "") == "nfs4"

        if Ops.get_string(parsed, "query", "") != ""
          UI.ChangeWidget(
            Id(:mount_options),
            :Value,
            Ops.get_string(query_map, "mountoptions", "")
          )
        end

        Builtins.y2milestone("NFSv4: %1", nfs4)

        UI.ChangeWidget(Id(:ch_nfs4), :Value, nfs4)
      else
        UI.ChangeWidget(Id(:complete_url), :Value, @_url)
      end

      nil
    end

    def NFSStoreParts
      parsed = {
        "scheme" => "nfs",
        "host"   => NormalizeHost(
          Convert.to_string(UI.QueryWidget(Id(:server), :Value))
        ),
        "path"   => Convert.to_string(UI.QueryWidget(Id(:dir), :Value))
      }

      nfs4 = Convert.to_boolean(UI.QueryWidget(Id(:ch_nfs4), :Value))
      if nfs4
        # keep nfs4:// if it is used in the original URL
        if Builtins.tolower(Ops.get_string(URL.Parse(@_url), "scheme", "")) == "nfs4"
          Ops.set(parsed, "scheme", "nfs4")
        else
          Ops.set(parsed, "query", "type=nfs4")
        end
      end

      @_url = URL.Build(parsed)
      iso = Convert.to_boolean(UI.QueryWidget(Id(:ch_iso), :Value))

      # workaround: URL::Build does not accept numbers in scheme,
      # for nfs4 scheme it returns URL with no scheme (like "://foo/bar")
      @_url = Ops.add("nfs4", @_url) if !Builtins.regexpmatch(@_url, "^nfs")

      @_url = PostprocessISOURL(@_url) if iso

      if UI.QueryWidget(Id(:mount_options), :Value) != :default
        mount_opts = Convert.to_string(
          UI.QueryWidget(Id(:mount_options), :Value)
        )
        @_url = Ops.add(
          Ops.add(@_url, "?mountoptions="),
          URL.EscapeString(mount_opts, URL.transform_map_filename)
        )
      end

      nil
    end

    def NFSStoreComplete
      @_url = Convert.to_string(UI.QueryWidget(Id(:complete_url), :Value))

      nil
    end

    # Store function of a widget
    # @param [String] _key string widget key
    # @param [Hash] _event map which caused settings being stored
    def NFSStore(_key, _event)
      current_type = Convert.to_symbol(UI.QueryWidget(Id(:edit_type), :Value))
      Builtins.y2milestone("Current edit type: %1", current_type)

      if current_type == :edit_url_parts
        NFSStoreParts()
      else
        NFSStoreComplete()
      end

      nil
    end

    # Handle function of a widget
    # @param [String] key string widget key
    # @param [Hash] event map which caused settings being stored
    # @return always nil
    def NFSHandle(key, event)
      event = deep_copy(event)
      Builtins.y2debug("NFSHandle: key: %1, event: %2", key, event)

      if Ops.get(event, "ID") == :nfs_browse
        server = Convert.to_string(UI.QueryWidget(Id(:server), :Value))
        # dialog caption
        result = NetworkPopup.NFSServer(server)

        UI.ChangeWidget(Id(:server), :Value, result) if !result.nil?
      elsif Ops.get(event, "ID") == :nfs_exports_browse
        server = Convert.to_string(UI.QueryWidget(Id(:server), :Value))
        nfs_export = Convert.to_string(UI.QueryWidget(Id(:dir), :Value))
        # dialog caption
        result = NetworkPopup.NFSExport(server, nfs_export)

        UI.ChangeWidget(Id(:dir), :Value, result) if !result.nil?
      elsif (Ops.get(event, "ID") == :edit_url_parts ||
          Ops.get(event, "ID") == :edit_complete_url) &&
          Ops.get_string(event, "EventReason", "") == "ValueChanged"
        Builtins.y2milestone("Changing dialog type: %1", Ops.get(event, "ID"))

        # store the current settings
        if Ops.get(event, "ID") == :edit_url_parts
          NFSStoreComplete()
        else
          NFSStoreParts()
        end

        # reinitialize the dialog (set the current values)
        NFSInit(nil)
      end

      nil
    end

    # Get widget description map
    # @return widget description map
    def NFSWidget
      {
        "widget"            => :custom,
        "custom_widget"     => VBox(
          RadioButtonGroup(
            Id(:edit_type),
            HBox(
              RadioButton(
                Id(:edit_url_parts),
                Opt(:notify),
                _("Edit Parts of the URL"),
                true
              ),
              HSpacing(2),
              RadioButton(
                Id(:edit_complete_url),
                Opt(:notify),
                _("Edit Complete URL")
              )
            )
          ),
          ReplacePoint(Id(:edit_content), Empty())
        ),
        "init"              => fun_ref(method(:NFSInit), "void (string)"),
        "store"             => fun_ref(method(:NFSStore), "void (string, map)"),
        "handle"            => fun_ref(method(:NFSHandle), "symbol (string, map)"),
        "validate_type"     => :function,
        "validate_function" => fun_ref(
          method(:ServerValidate),
          "boolean (string, map)"
        ),
        # help text
        "help"              => Ops.add(
          Ops.add(
            _(
              "<p><big><b>NFS Server</b></big><br>\n" \
              "Use <b>Server Name</b> and <b>Path to Directory or ISO Image</b>\n" \
              "to specify the NFS server host name and path on the server.</p>"
            ),
            @multi_cd_help
          ),
          _(
            "<p><big><b>Mount Options</b></big><br>\n" \
            "You can specify extra options used for mounting the NFS volume.\n" \
            "This is an expert option, keeping the default value is recommened. " \
            "See <b>man 5 nfs</b>\n" \
            "for details and the list of supported options."
          )
        )
      }
    end

    # CD/DVD repository widget

    # Init function of a widget
    # @param [String] _key string widget key
    def CDInit(_key)
      parsed = URL.Parse(@_url)
      scheme = Ops.get_string(parsed, "scheme", "")
      if scheme == "dvd"
        UI.ChangeWidget(Id(:dvd), :Value, true)
      else
        UI.ChangeWidget(Id(:cd), :Value, true)
      end

      nil
    end

    # Store function of a widget
    # @param [String] _key string widget key
    # @param [Hash] _event map which caused settings being stored
    def CDStore(_key, _event)
      device = Convert.to_symbol(UI.QueryWidget(Id(:device), :CurrentButton))
      parsed = URL.Parse(@_url)
      scheme = Builtins.tolower(Ops.get_string(parsed, "scheme", ""))

      # preserve other URL options, e.g. ?devices=/dev/sr0
      # change the URL only when necessary
      if device == :cd && scheme != "cd"
        @_url = "cd:///"
      elsif device == :dvd && scheme != "dvd"
        @_url = "dvd:///"
      end

      nil
    end

    # Get widget description map
    # @return widget description map
    def CDWidget
      {
        "widget"        => :custom,
        "custom_widget" => RadioButtonGroup(
          Id(:device),
          VBox(
            # radio button
            Left(RadioButton(Id(:cd), _("&CD-ROM"))),
            # radio button
            Left(RadioButton(Id(:dvd), _("&DVD-ROM")))
          )
        ),
        "init"          => fun_ref(method(:CDInit), "void (string)"),
        "store"         => fun_ref(method(:CDStore), "void (string, map)"),
        "help"          => _(
          "<p><big><b>CD or DVD Media</b></big><br>\n" \
          "Set <b>CD-ROM</b> or <b>DVD-ROM</b> to specify the type of media.</p>"
        )
      }
    end

    # File / Directory repository widget

    # Init function of a widget
    # @param [String] _key string widget key
    def DirInit(_key)
      parsed = URL.Parse(@_url)

      path = parsed["path"]
      path = "/" if path.empty?

      UI.ChangeWidget(Id(:dir), :Value, path)
      UI.SetFocus(:dir)

      # is it a plain directory?
      UI.ChangeWidget(Id(:ch_plain), :Value, @_plaindir)

      nil
    end

    # Init function of a widget
    # @param [String] _key string widget key
    def IsoInit(_key)
      @_url = PreprocessISOURL(@_url)
      parsed = URI.parse(@_url)
      path = CGI.unescape(parsed.path)
      log.info "unescaped path #{path}"

      UI.ChangeWidget(Id(:dir), :Value, path)
      UI.SetFocus(:dir)

      nil
    end

    # Store function of a widget
    # @param [String] _key string widget key
    # @param [Hash] _event map which caused settings being stored
    def DirStore(_key, _event)
      parsed = URL.Parse(@_url)

      # keep file:// scheme if it was used originally
      scheme = parsed["scheme"] || ""
      scheme = "dir" if !scheme.casecmp("file").zero?

      parsed = {
        "scheme" => scheme,
        "path"   => Convert.to_string(UI.QueryWidget(Id(:dir), :Value))
      }

      @_plaindir = true if Convert.to_boolean(UI.QueryWidget(Id(:ch_plain), :Value))

      @_url = URL.Build(parsed)

      nil
    end

    # Store function of a widget
    # @param [String] _key string widget key
    # @param [Hash] _event map which caused settings being stored
    def IsoStore(_key, _event)
      parsed = {
        "scheme" => "iso",
        "path"   => Convert.to_string(UI.QueryWidget(Id(:dir), :Value))
      }

      @_url = URL.Build(parsed)
      @_url = PostprocessISOURL(@_url)

      nil
    end

    # Handle function of a widget
    # @param [String] _key string widget key
    # @param [Hash] _event map which caused settings being stored
    # @return always nil
    def DirHandle(_key, _event)
      dir = Convert.to_string(UI.QueryWidget(Id(:dir), :Value))
      # dialog caption
      result = UI.AskForExistingDirectory(dir, _("Local Directory"))

      UI.ChangeWidget(Id(:dir), :Value, result) if !result.nil?

      nil
    end

    # Handle function of a widget
    # @param [String] _key string widget key
    # @param [Hash] _event map which caused settings being stored
    # @return always nil
    def IsoHandle(_key, _event)
      dir = Convert.to_string(UI.QueryWidget(Id(:dir), :Value))
      # dialog caption
      result = UI.AskForExistingFile(dir, "*", _("ISO Image File"))

      UI.ChangeWidget(Id(:dir), :Value, result) if !result.nil?

      nil
    end

    def DirValidate(_key, _event)
      s = Convert.to_string(UI.QueryWidget(Id(:dir), :Value))
      if s.nil? || s == ""
        # error popup
        Popup.Error(Message.RequiredItem)
        UI.SetFocus(Id(:dir))
        return false
      end

      stat = Convert.to_map(SCR.Read(path(".target.stat"), s))

      Builtins.y2milestone("stat %1: %2", s, stat)

      if !Ops.get_boolean(stat, "isdir", false)
        # error popup - the entered path is not a directory
        Report.Error(
          _(
            "The entered path is not a directory\nor the directory does not exist.\n"
          )
        )
        UI.SetFocus(Id(:dir))

        return false
      end

      true
    end

    FILE_BIN = "/usr/bin/file".freeze

    def IsoValidate(_key, _event)
      s = Convert.to_string(UI.QueryWidget(Id(:dir), :Value))
      if s.nil? || s == ""
        # error popup
        Popup.Error(Message.RequiredItem)
        UI.SetFocus(Id(:dir))
        return false
      end

      stat = Convert.to_map(SCR.Read(path(".target.stat"), s))

      Builtins.y2milestone("stat %1: %2", s, stat)

      if !Ops.get_boolean(stat, "isreg", false)
        # error popup - the entered path is not a regular file
        Report.Error(
          _("The entered path is not a file\nor the file does not exist.\n")
        )
        UI.SetFocus(Id(:dir))

        return false
      end

      # try to detect ISO image by file if it's present
      if SCR.Read(path(".target.size"), FILE_BIN) > 0
        # Use also -k as new images contain at first DOS boot sector for UEFI
        # then iso magic block
        out = SCR.Execute(path(".target.bash_output"), "#{FILE_BIN} -kb -- #{s.shellescape}")

        stdout = out["stdout"] || ""

        if stdout.include? "ISO 9660 CD-ROM filesystem"
          Builtins.y2milestone("ISO 9660 image detected")
        else
          # continue/cancel popup, %1 is a file name
          return Popup.ContinueCancel(
            Builtins.sformat(
              _(
                "File '%1'\n" \
                "does not seem to be an ISO image.\n" \
                "Use it anyway?\n"
              ),
              s
            )
          )
        end
      end

      true
    end

    # Get widget description map
    # @return widget description map
    def DirWidget
      {
        "widget"            => :custom,
        "custom_widget"     => VBox(
          HBox(
            # text entry
            InputField(Id(:dir), Opt(:hstretch), _("&Path to Directory")),
            VBox(
              Label(""),
              # push button
              PushButton(Id(:browse), Label.BrowseButton)
            )
          ),
          # checkbox label
          Left(CheckBox(Id(:ch_plain), _("&Plain RPM Directory")))
        ),
        "init"              => fun_ref(method(:DirInit), "void (string)"),
        "store"             => fun_ref(method(:DirStore), "void (string, map)"),
        "handle"            => fun_ref(
          method(:DirHandle),
          "symbol (string, map)"
        ),
        "handle_events"     => [:browse],
        "validate_type"     => :function,
        "validate_function" => fun_ref(
          method(:DirValidate),
          "boolean (string, map)"
        ),
        "help"              => Ops.add(
          _(
            "<p><big><b>Local Directory</b></big><br>\n" \
            "Use <b>Path to Directory</b> to specify the path to the\n" \
            "directory. If the directory contains only RPM packages without\n" \
            "any metadata (i.e. there is no product information), then check option\n" \
            "<b>Plain RPM Directory</b>.</p>\n"
          ),
          @multi_cd_help
        )
      }
    end

    def DetectPartitions(disk_id)
      # this kills things like /dev/fd0 (that don't have a disk_id)
      return [] if disk_id.empty?

      command = "/usr/bin/ls #{disk_id.shellescape}-part*"

      out = SCR.Execute(path(".target.bash_output"), command)

      if Ops.get_integer(out, "exit", -1).nonzero?
        Builtins.y2milestone("no partitions on %1, using full disk", disk_id)
        return [disk_id]
      end

      ret = Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n")
      ret_size = Builtins.size(ret)

      # remove empty string at the end
      if Ops.greater_than(ret_size, 0) &&
          Ops.get(ret, Ops.subtract(ret_size, 1), "dummy") == ""
        ret = Builtins.remove(ret, Ops.subtract(ret_size, 1))
      end

      deep_copy(ret)
    end

    def GetDeviceID(devices)
      devices = deep_copy(devices)
      ret = ""

      Builtins.foreach(devices) do |dev|
        ret = dev if Builtins.regexpmatch(dev, "^/dev/disk/by-id/")
      end

      ret
    end

    def DetectDisk(usb_only)
      Builtins.y2milestone("Detecting %1USB disks", usb_only ? "" : "non-")
      disks = Convert.convert(
        SCR.Read(path(".probe.disk")),
        from: "any",
        to:   "list <map>"
      )

      Builtins.y2debug("Detected disks: %1", disks)

      disks = Builtins.filter(disks) do |disk|
        (Ops.get_string(disk, "driver", "") == "usb-storage" && usb_only) ||
          (Ops.get_string(disk, "driver", "") != "usb-storage" && !usb_only)
      end

      Builtins.y2milestone("Found disks: %1", disks)

      ret = []

      Builtins.foreach(disks) do |disk|
        dev_id = GetDeviceID(Ops.get_list(disk, "dev_names", []))
        ret = Builtins.add(
          ret,
          "model"      => Ops.get_string(disk, "model", ""),
          # compute the size (number of sectors * size of sector)
          "size"       => Ops.multiply(
            Ops.get_integer(disk, ["resource", "size", 0, "x"], 0),
            Ops.get_integer(disk, ["resource", "size", 0, "y"], 0)
          ),
          "dev"        => Ops.get_string(disk, "dev_name", ""),
          "dev_by_id"  => dev_id,
          "partitions" => DetectPartitions(dev_id)
        )
      end

      Builtins.y2milestone("Disk configuration: %1", ret)

      deep_copy(ret)
    end

    def DetectUSBDisk
      DetectDisk(true)
    end

    def DetectHardDisk
      DetectDisk(false)
    end

    def DiskSelectionList(disks, selected)
      disks = deep_copy(disks)
      ret = []
      found = false

      Builtins.foreach(disks) do |disk|
        label = Ops.get_string(disk, "model", "")
        # add size if it's known and there is just one partition
        # TODO detect size of each partition
        sz = Ops.get_integer(disk, "size", 0)
        if Ops.greater_than(sz, 0) &&
            Builtins.size(Ops.get_list(disk, "partitions", [])) == 1
          label = Ops.add(Ops.add(label, " - "), String.FormatSize(sz))
        end
        dev = Ops.get_string(disk, "dev", "")
        Builtins.foreach(Ops.get_list(disk, "partitions", [])) do |part|
          partnum = Builtins.regexpsub(part, ".*-part([0-9]*)$", "\\1")
          disk_label = "#{label} (#{dev}#{partnum})"
          found ||= part == selected
          ret = Builtins.add(ret, Item(Id(part), disk_label, part == selected))
        end
      end

      if !found && Builtins.regexpmatch(selected, "^/dev/disk/by-id/usb-")
        Builtins.y2milestone(
          "USB disk %1 is not currently attached, adding the raw device to the list",
          selected
        )

        # remove the /dev prefix
        dev_name = Builtins.regexpsub(
          selected,
          "^/dev/disk/by-id/usb-(.*)",
          "\\1"
        )
        ret = Builtins.add(ret, Item(Id(selected), dev_name, true))
      end

      deep_copy(ret)
    end

    def SetFileSystems(selected_fs)
      fs_list = [
        "auto",
        "vfat",
        "ntfs",
        "ntfs-3g",
        "ext2",
        "ext3",
        "ext4",
        "reiserfs",
        "xfs",
        "jfs",
        "iso9660"
      ]

      items = Builtins.maplist(fs_list) do |fs|
        Item(Id(fs), fs, fs == selected_fs)
      end

      UI.ChangeWidget(Id(:fs), :Items, items)

      nil
    end

    # common code for USBInit() and DiskInit()
    def InitDiskWidget(disks)
      disks = deep_copy(disks)
      parsed = URL.Parse(@_url)
      query = URL.MakeMapFromParams(Ops.get_string(parsed, "query", ""))

      UI.ChangeWidget(
        Id(:disk),
        :Items,
        DiskSelectionList(disks, Ops.get(query, "device", ""))
      )

      SetFileSystems(Ops.get(query, "filesystem", "auto"))

      UI.ChangeWidget(Id(:dir), :Value, Ops.get_string(parsed, "path", ""))

      # is it a plain directory?
      UI.ChangeWidget(Id(:ch_plain), :Value, @_plaindir)

      UI.SetFocus(:disk)

      nil
    end

    # Init function of a widget
    # @param [String] _key string widget key
    def USBInit(_key)
      # detect disks
      usb_disks = DetectUSBDisk()
      InitDiskWidget(usb_disks)

      nil
    end

    # Store function of a widget
    # @param [String] _key string widget key
    # @param [Hash] _event map which caused settings being stored
    def USBStore(_key, _event)
      # build URL like this: usb:///openSUSE?device=/dev/sdb8&filesystem=auto
      query = Builtins.sformat(
        "device=%1&filesystem=%2",
        Convert.to_string(UI.QueryWidget(Id(:disk), :Value)),
        Convert.to_string(UI.QueryWidget(Id(:fs), :Value))
      )

      dir = Convert.to_string(UI.QueryWidget(Id(:dir), :Value))

      @_plaindir = Convert.to_boolean(UI.QueryWidget(Id(:ch_plain), :Value))

      parsed = { "scheme" => "usb", "path" => dir, "query" => query }

      @_url = URL.Build(parsed)

      Builtins.y2milestone("New USB url: %1", URL.HidePassword(@_url))

      nil
    end

    # Get widget description map
    # @return widget description map
    def USBWidget
      {
        "widget"        => :custom,
        "custom_widget" => VBox(
          # combobox title
          Left(
            ComboBox(
              Id(:disk),
              # `opt(`hstretch),
              _("&USB Mass Storage Device") +
                # the spacing is added to make the widget wider
                "                                                   "
            )
          ),
          Left(ComboBox(Id(:fs), Opt(:editable), _("&File System"))),
          Left(InputField(Id(:dir), _("Dire&ctory"))),
          Left(CheckBox(Id(:ch_plain), _("&Plain RPM Directory")))
        ),
        "init"          => fun_ref(method(:USBInit), "void (string)"),
        "store"         => fun_ref(method(:USBStore), "void (string, map)"),
        "help"          => _(
          "<p><big><b>USB Stick or Disk</b></big><br>\n" \
          "Select the USB device on which the repository is located.\n" \
          "Use <b>Path to Directory</b> to specify the directory of the repository.\n" \
          "If the path is omitted, the system will use the root directory of the disk.\n" \
          "If the directory contains only RPM packages without\n" \
          "any metadata (i.e. there is no product information), then check option\n" \
          "<b>Plain RPM Directory</b>.</p>\n"
        ) +
          # 'auto' is a value in the combo box widget, do not translate it!
          _(
            "<p>The file system used on the device will be detected automatically\n" \
            "if you select file system 'auto'. If the detection fails or you\n" \
            "want to use a certain file system, select it from the list.</p>\n"
          )
      }
    end

    # Init function of a widget
    # @param [String] _key string widget key
    def DiskInit(_key)
      # refresh the cache
      disks = DetectHardDisk()
      InitDiskWidget(disks)

      nil
    end

    # Store function of a widget
    # @param [String] _key string widget key
    # @param [Hash] _event map which caused settings being stored
    def DiskStore(_key, _event)
      # build URL like this: usb:///openSUSE?device=/dev/sdb8&filesystem=auto
      query = Builtins.sformat(
        "device=%1&filesystem=%2",
        Convert.to_string(UI.QueryWidget(Id(:disk), :Value)),
        Convert.to_string(UI.QueryWidget(Id(:fs), :Value))
      )

      dir = Convert.to_string(UI.QueryWidget(Id(:dir), :Value))

      @_plaindir = Convert.to_boolean(UI.QueryWidget(Id(:ch_plain), :Value))

      parsed = { "scheme" => "hd", "path" => dir, "query" => query }

      @_url = URL.Build(parsed)

      Builtins.y2milestone("New Disk url: %1", URL.HidePassword(@_url))

      nil
    end

    # Get widget description map
    # @return widget description map
    def DiskWidget
      {
        "widget"        => :custom,
        "custom_widget" => VBox(
          # combobox title
          ComboBox(Id(:disk), Opt(:hstretch), _("&Disk Device")),
          ComboBox(Id(:fs), Opt(:editable), _("&File System")),
          InputField(Id(:dir), _("Dire&ctory")),
          Left(CheckBox(Id(:ch_plain), _("&Plain RPM Directory")))
        ),
        "init"          => fun_ref(method(:DiskInit), "void (string)"),
        "store"         => fun_ref(method(:DiskStore), "void (string, map)"),
        "help"          => _(
          "<p><big><b>Disk</b></big><br>\n" \
          "Select the disk on which the repository is located.\n" \
          "Use <b>Path to Directory</b> to specify the directory of the repository.\n" \
          "If the path is omitted, the system will use the root directory of the disk.\n" \
          "If the directory contains only RPM packages without\n" \
          "any metadata (i.e. there is no product information), then check option\n" \
          "<b>Plain RPM Directory</b>.</p>\n"
        ) +
          # 'auto' is a value in the combo box widget, do not translate it!
          _(
            "<p>The file system used on the device will be detected automatically\n" \
            "if you select file system 'auto'. If the detection fails or you\n" \
            "want to use a certain file system, select it from the list.</p>\n"
          )
      }
    end

    # Get widget description map
    # @return widget description map
    def IsoWidget
      {
        "widget"            => :custom,
        "custom_widget"     => VBox(
          HBox(
            # text entry
            InputField(Id(:dir), Opt(:hstretch), _("&Path to ISO Image")),
            VBox(
              Label(""),
              # push button
              PushButton(Id(:browse), Label.BrowseButton)
            )
          )
        ),
        "init"              => fun_ref(method(:IsoInit), "void (string)"),
        "store"             => fun_ref(method(:IsoStore), "void (string, map)"),
        "handle"            => fun_ref(
          method(:IsoHandle),
          "symbol (string, map)"
        ),
        "handle_events"     => [:browse],
        "validate_type"     => :function,
        "validate_function" => fun_ref(
          method(:IsoValidate),
          "boolean (string, map)"
        ),
        "help"              => _(
          "<p><big><b>Local ISO Image</b></big><br>\n" \
          "Use <b>Path to ISO Image</b> to specify the path to the\n" \
          "ISO image file.</p>"
        )
      }
    end

    def InitFocusServerInit(server_type)
      UI.SetFocus(:server) if [:ftp, :http, :https, :samba].include?(server_type)

      nil
    end

    def ServerStoreParts
      type = Convert.to_symbol(UI.QueryWidget(Id(:rb_type), :CurrentButton))

      # initialize keys to empty values so the new and old values can be simply compared
      parsed = {
        "fragment" => "",
        "host"     => "",
        "pass"     => "",
        "path"     => "",
        "port"     => "",
        "query"    => "",
        "scheme"   => "",
        "user"     => ""
      }
      case type
      when :ftp
        Ops.set(parsed, "scheme", "ftp")
      when :http
        Ops.set(parsed, "scheme", "http")
      when :https
        Ops.set(parsed, "scheme", "https")
      when :samba
        Ops.set(parsed, "scheme", "smb")
      end

      anonymous = Convert.to_boolean(UI.QueryWidget(Id(:anonymous), :Value))
      if !anonymous
        user = Convert.to_string(UI.QueryWidget(Id(:username), :Value))
        pass = Convert.to_string(UI.QueryWidget(Id(:password), :Value))
        Ops.set(parsed, "user", user) if Builtins.size(user).nonzero?
        Ops.set(parsed, "pass", pass) if Builtins.size(pass).nonzero?
      end

      host = NormalizeHost(
        Convert.to_string(UI.QueryWidget(Id(:server), :Value))
      )
      directory = Convert.to_string(UI.QueryWidget(Id(:dir), :Value))

      # is / in the host name?
      pos = Builtins.findfirstof(host, "/")
      if !pos.nil?
        # update the hostname and the directory,
        # URL::Build return empty URL when the hostname is not valid
        Builtins.y2milestone("The hostname contains a path: %1", host)
        dir = Builtins.substring(host, pos)

        if Builtins.substring(dir, Ops.subtract(Builtins.size(dir), 1), 1) != "/" &&
            Builtins.substring(directory, 0, 1) != "/"
          dir = Ops.add(dir, "/")
        end

        directory = Ops.add(dir, directory)
        host = Builtins.substring(host, 0, pos)

        Builtins.y2milestone(
          "Updated hostname: %1, directory: %2",
          host,
          directory
        )
      end

      Ops.set(parsed, "host", host)

      if type == :samba
        share = Convert.to_string(UI.QueryWidget(Id(:share), :Value))
        directory = Ops.add(Slashed(share), Slashed(directory))
      elsif type != :ftp
        # FTP needs to distinguish absolute and relative path
        # do not add the slash if host and directory is empty
        # (avoid e.g. http:// -> http:/// when switching from the parts to the complete view)
        directory = Slashed(directory) if host != "" || directory != ""
      end
      if UI.WidgetExists(Id(:workgroup))
        workgroup = Convert.to_string(UI.QueryWidget(Id(:workgroup), :Value))
        if type == :samba && Ops.greater_than(Builtins.size(workgroup), 0)
          Ops.set(parsed, "domain", workgroup)
        end
      end
      Ops.set(parsed, "path", directory)

      # set HTTP/HTTPS port
      if [:http, :https].include?(type)
        Ops.set(
          parsed,
          "port",
          Convert.to_string(UI.QueryWidget(Id(:port), :Value))
        )
      end

      # keep the URL if user haven't changed anything (don't change escaped chars bnc#529944)
      parsed_old = URL.Parse(@_url)
      if parsed == parsed_old
        Builtins.y2milestone("No change, NOT updating the complete URL")
        Builtins.y2debug("Unchanged URL: %1", parsed)
      else
        Builtins.y2milestone("A change detected, updating complete URL")
        Builtins.y2debug("Updating the URL: %1 -> %2", parsed_old, parsed)

        # do not log the entered password
        Builtins.y2milestone("Entered URL: %1", URL.HidePasswordToken(parsed))
        @_url = URL.Build(parsed)
        Builtins.y2milestone("URL::Build: %1", URL.HidePassword(@_url))

        if UI.WidgetExists(Id(:ch_iso))
          iso = Convert.to_boolean(UI.QueryWidget(Id(:ch_iso), :Value))
          @_url = PostprocessISOURL(@_url) if iso
        end
      end

      nil
    end

    def ServerStoreComplete
      @_url = Convert.to_string(UI.QueryWidget(Id(:complete_url), :Value))

      nil
    end

    # Handle function of a widget
    # @param [String] key string widget key
    # @param [Hash] event map which caused settings being stored
    # @return always nil
    def ServerHandle(key, event)
      event = deep_copy(event)
      Builtins.y2milestone("ServerHandle: %1, %2", key, event)

      current_type = Convert.to_symbol(UI.QueryWidget(Id(:edit_type), :Value))
      Builtins.y2debug("Current edit type: %1", current_type)

      id = Ops.get(event, "ID")
      if Ops.is_symbol?(id) &&
          Builtins.contains(
            [:http, :https, :ftp, :samba, :rb_type],
            Convert.to_symbol(id)
          ) &&
          current_type == :edit_url_parts
        type = Convert.to_symbol(UI.QueryWidget(Id(:rb_type), :CurrentButton))
        server = if UI.WidgetExists(Id(:server))
          Convert.to_string(UI.QueryWidget(Id(:server), :Value))
        else
          ""
        end
        dir = if UI.WidgetExists(Id(:dir))
          Convert.to_string(UI.QueryWidget(Id(:dir), :Value))
        else
          ""
        end
        anonymous = if UI.WidgetExists(Id(:anonymous))
          Convert.to_boolean(UI.QueryWidget(Id(:anonymous), :Value))
        else
          false
        end
        username = if UI.WidgetExists(Id(:username))
          Convert.to_string(UI.QueryWidget(Id(:username), :Value))
        else
          ""
        end
        password = if UI.WidgetExists(Id(:password))
          Convert.to_string(UI.QueryWidget(Id(:password), :Value))
        else
          ""
        end
        port = if UI.WidgetExists(Id(:port))
          Convert.to_string(UI.QueryWidget(Id(:port), :Value))
        else
          ""
        end

        widget = VBox(
          HBox(
            # text entry
            InputField(Id(:server), Opt(:hstretch), _("Server &Name"), server),
            if [:http, :https].include?(type)
              HBox(
                HSpacing(1),
                HSquash(InputField(Id(:port), _("&Port"), port))
              )
            else
              Empty()
            end,
            if type == :samba
              # text entry
              InputField(Id(:share), Opt(:hstretch), _("&Share"))
            else
              Empty()
            end
          ),
          if type == :samba
            VBox(
              InputField(
                Id(:dir),
                Opt(:hstretch),
                # text entry
                _("&Path to Directory or ISO Image"),
                dir
              ),
              # checkbox label
              Left(CheckBox(Id(:ch_iso), _("ISO &Image")))
            )
          else
            # text entry
            InputField(Id(:dir), Opt(:hstretch), _("&Directory on Server"), dir)
          end,
          HBox(
            HSpacing(0.5),
            # frame
            Frame(
              _("Au&thentication"),
              VBox(
                Left(
                  CheckBox(
                    Id(:anonymous),
                    Opt(:notify),
                    # check box
                    _("&Anonymous"),
                    anonymous
                  )
                ),
                if type == :samba
                  # text entry
                  InputField(
                    Id(:workgroup),
                    Opt(:hstretch),
                    _("&Workgroup or Domain")
                  )
                else
                  Empty()
                end,
                # text entry
                VSpacing(0.4),
                HBox(
                  InputField(
                    Id(:username),
                    Opt(:hstretch),
                    _("&User Name"),
                    username
                  ),
                  # password entry
                  Password(
                    Id(:password),
                    Opt(:hstretch),
                    _("&Password"),
                    password
                  )
                )
              )
            ),
            HSpacing(0.5)
          )
        )
        UI.ReplaceWidget(Id(:server_rp), widget)

        if UI.WidgetExists(Id(:port))
          # maximum port number is 65535
          UI.ChangeWidget(Id(:port), :InputMaxLength, 5)
          # allow only numbers in the port spec
          UI.ChangeWidget(Id(:port), :ValidChars, String.CDigit)
        end

        # update widget status
        UI.ChangeWidget(Id(:username), :Enabled, !anonymous)
        UI.ChangeWidget(Id(:password), :Enabled, !anonymous)
        UI.ChangeWidget(Id(:workgroup), :Enabled, !anonymous) if UI.WidgetExists(Id(:workgroup))

        InitFocusServerInit(Convert.to_symbol(id))

        return nil
      end

      if Ops.get(event, "ID") == :anonymous && current_type == :edit_url_parts
        anonymous = Convert.to_boolean(UI.QueryWidget(Id(:anonymous), :Value))
        UI.ChangeWidget(Id(:username), :Enabled, !anonymous)
        UI.ChangeWidget(Id(:password), :Enabled, !anonymous)
        UI.ChangeWidget(Id(:workgroup), :Enabled, !anonymous) if UI.WidgetExists(Id(:workgroup))
        return nil
      elsif [:edit_url_parts, :edit_complete_url].include?(id) &&
          Ops.get_string(event, "EventReason", "") == "ValueChanged"
        Builtins.y2milestone("Changing dialog type")

        # store the current values (note: the radio button just has been switched,
        # compare to the opposite value!)
        if id == :edit_url_parts
          ServerStoreComplete()
        else
          ServerStoreParts()
        end

        @editing_parts = id == :edit_url_parts

        # reinitialize the dialog (set the current values)
        ServerInit(nil)
      end

      nil
    end

    def ServerInit(key)
      # check the current edit type
      current_type = @editing_parts ? :edit_url_parts : :edit_complete_url

      # set the stored value
      UI.ChangeWidget(Id(:edit_type), :Value, current_type)

      Builtins.y2debug("Current edit type: %1", current_type)

      UI.ReplaceWidget(
        Id(:edit_content),
        (current_type == :edit_url_parts) ? @details_content : @complete_content
      )

      if current_type == :edit_url_parts
        protocol_box = HBox(
          HStretch(),
          # radio button
          RadioButton(Id(:ftp), Opt(:notify), _("&FTP")),
          HStretch(),
          # radio button
          RadioButton(Id(:http), Opt(:notify), _("H&TTP")),
          HStretch()
        )
        if @_allow_https
          protocol_box = Builtins.add(
            protocol_box,
            # radio button
            RadioButton(Id(:https), Opt(:notify), _("HTT&PS"))
          )
          protocol_box = Builtins.add(protocol_box, HStretch())
        end
        protocol_box = Builtins.add(
          protocol_box,
          # radio button
          RadioButton(Id(:samba), Opt(:notify), _("S&MB/CIFS"))
        )
        protocol_box = Builtins.add(protocol_box, HStretch())
        protocol_box = RadioButtonGroup(
          Id(:rb_type),
          Opt(:notify),
          protocol_box
        )
        UI.ReplaceWidget(Id(:rb_type_rp), protocol_box)

        iso = IsISOURL(@_url)
        @_url = PreprocessISOURL(@_url) if iso
        parsed = URL.Parse(@_url)
        type = :ftp
        case Ops.get_string(parsed, "scheme", "")
        when "http"
          type = :http
        when "https"
          type = :https
        when "smb"
          type = :samba
        end
        UI.ChangeWidget(Id(:rb_type), :CurrentButton, type)

        ServerHandle(key, "ID" => :rb_type)

        UI.ChangeWidget(Id(:server), :Value, Ops.get_string(parsed, "host", ""))
        dir = Ops.get_string(parsed, "path", "")
        if type == :samba
          UI.ChangeWidget(Id(:ch_iso), :Value, iso)
          sharepath = Builtins.regexptokenize(dir, "^/*([^/]+)(/.*)?$")
          share = Ops.get_string(sharepath, 0, "")
          dir = Ops.get_string(sharepath, 1, "")
          dir = "/" if dir.nil?

          query = URI.decode_www_form(parsed["query"] || "").to_h
          # libzypp uses "workgroup" or "domain" parameter, see "man zypper"
          workgroup = query["workgroup"] || query["domain"] || ""

          UI.ChangeWidget(Id(:workgroup), :Value, workgroup)
          UI.ChangeWidget(Id(:share), :Value, share)
        end
        UI.ChangeWidget(Id(:dir), :Value, dir)
        UI.ChangeWidget(
          Id(:username),
          :Value,
          Ops.get_string(parsed, "user", "")
        )
        UI.ChangeWidget(
          Id(:password),
          :Value,
          Ops.get_string(parsed, "pass", "")
        )
        anonymous = !(Ops.get_string(parsed, "user", "") != "" ||
          Ops.get_string(parsed, "pass", "") != "")
        Builtins.y2milestone("Anonymous: %1", anonymous)
        UI.ChangeWidget(Id(:anonymous), :Value, anonymous)
        if anonymous
          UI.ChangeWidget(Id(:username), :Enabled, false)
          UI.ChangeWidget(Id(:password), :Enabled, false)
          UI.ChangeWidget(Id(:workgroup), :Enabled, !anonymous) if UI.WidgetExists(Id(:workgroup))
        end

        # set HTTP/HTTPS port if it's specified
        if [:http, :https].include?(type)
          port_num = Ops.get_string(parsed, "port", "")

          UI.ChangeWidget(Id(:port), :Value, port_num) if !port_num.nil? && port_num != ""
        end

        InitFocusServerInit(type)
      else
        UI.ChangeWidget(Id(:complete_url), :Value, @_url)
      end

      nil
    end

    def ServerValidate(_key, _event)
      current_type = Convert.to_symbol(UI.QueryWidget(Id(:edit_type), :Value))
      Builtins.y2debug("Current edit type: %1", current_type)

      if current_type == :edit_url_parts
        host = NormalizeHost(
          Convert.to_string(UI.QueryWidget(Id(:server), :Value))
        )
        if !Hostname.CheckFQ(host) && !IP.Check(host)
          UI.SetFocus(:server)
          Popup.Error(
            Builtins.sformat("%1\n\n%2", Hostname.ValidFQ, IP.Valid4)
          )
          return false
        end
      else
        url = UI.QueryWidget(Id(:complete_url), :Value)
        return valid_scheme?(url)
      end

      true
    end

    def ServerStore(key, event)
      Builtins.y2debug("Server store: %1, %2", key, event)

      current_type = Convert.to_symbol(UI.QueryWidget(Id(:edit_type), :Value))
      Builtins.y2debug("Current edit type: %1", current_type)

      @editing_parts = current_type == :edit_url_parts

      if @editing_parts
        ServerStoreParts()
      else
        ServerStoreComplete()
      end

      nil
    end

    # Get widget description map
    # @return widget description map
    def ServerWidget
      {
        "widget"            => :custom,
        "custom_widget"     => VBox(
          RadioButtonGroup(
            Id(:edit_type),
            HBox(
              RadioButton(
                Id(:edit_url_parts),
                Opt(:notify),
                _("Edit Parts of the URL"),
                @editing_parts
              ),
              HSpacing(2),
              RadioButton(
                Id(:edit_complete_url),
                Opt(:notify),
                _("Edit Complete URL"),
                !@editing_parts
              )
            )
          ),
          VSpacing(0.3),
          ReplacePoint(Id(:edit_content), Empty())
        ),
        "init"              => fun_ref(method(:ServerInit), "void (string)"),
        "validate_type"     => :function,
        "validate_function" => fun_ref(
          method(:ServerValidate),
          "boolean (string, map)"
        ),
        "store"             => fun_ref(
          method(:ServerStore),
          "void (string, map)"
        ),
        "handle"            => fun_ref(
          method(:ServerHandle),
          "symbol (string, map)"
        ),
        # help text - server dialog
        "help"              => Ops.add(
          _(
            "<p><big><b>Server and Directory</b></big><br>\n" \
            "Use <b>Server Name</b> and <b>Path to Directory or ISO Image</b>\n" \
            "to specify the NFS server host name and path on the server.\n" \
            "To enable authentication, uncheck <b>Anonymous</b> and specify the\n" \
            "<b>User Name</b> and the <b>Password</b>.</p>\n" \
            "<p>\n" \
            "For the SMB/CIFS repository, specify <b>Share</b> name and <b>Path to Directory\n" \
            "or ISO Image</b>. \n" \
            "If the location is a file holding an ISO image\n" \
            "of the media, set <b>ISO Image</b>.</p>\n"
          ) +
            # help text - server dialog, there is a "Port" widget
            _(
              "<p>It is possible to set the <b>Port</b> number for a HTTP/HTTPS repository.\n" \
              "Leave it empty to use the default port.</p>\n"
            ),
          @multi_cd_help
        )
      }
    end

    # Returns whether Community Repositories are defined in the control file.
    #
    # @return [Boolean] whether defined
    def CRURLDefined
      link = ProductFeatures.GetStringFeature(
        "software",
        "external_sources_link"
      )

      Builtins.y2debug("software/external_sources_link -> '%1'", link)

      if link.nil? || link == ""
        Builtins.y2milestone(
          "No software/external_sources_link, community repos will be disabled"
        )
        false
      else
        true
      end
    end

    def addon_checkbox_term
      return Empty() unless @display_addon_checkbox

      VBox(
        Left(CheckBox(Id(:add_addon), Opt(:notify),
          _("I would li&ke to install an additional Add On Product"), false)),
        VSpacing(1)
      )
    end

    def addon_spacing_term
      @display_addon_checkbox ? HSpacing(3) : Empty()
    end

    def scc_repos_widget
      display_scc = WFM.ClientExists("inst_scc") && !Stage.initial
      log.info "Displaying SCC option: #{display_scc}"

      display_scc ? Left(RadioButton(Id(:sccrepos), _(WIDGET_LABELS[:sccrepos]))) : Empty()
    end

    def network_button
      if Mode.installation || Mode.live_installation || Mode.update
        Right(PushButton(Id(:network), _("Net&work Configuration...")))
      else
        Empty()
      end
    end

    # FIXME: two almost same definitions in the same function smell bad
    def SelectRadioWidgetOpt(download_widget)
      contents = HBox(
        HStretch(),
        VBox(
          VStretch(),
          addon_checkbox_term,
          RadioButtonGroup(
            Id(:type),
            VBox(
              HBox(
                addon_spacing_term,
                VBox(
                  # radio button
                  Left(RadioButton(Id(:slp), _(WIDGET_LABELS[:slp]))),
                  # bnc #428370, No need to offer community repositories if not defined
                  if CRURLDefined()
                    # radio button
                    Left(RadioButton(Id(:comm_repos), _(WIDGET_LABELS[:comm_repos])))
                  else
                    Empty()
                  end,
                  scc_repos_widget,
                  VSpacing(0.4),
                  Left(RadioButton(Id(:specify_url), _(WIDGET_LABELS[:specify_url]))),
                  VSpacing(0.4),
                  *[:ftp, :http, :https, :samba, :nfs, :cd, :dvd, :hd, :usb,
                    :local_dir, :local_iso].map do |id|
                    Left(RadioButton(Id(id), _(WIDGET_LABELS[id])))
                  end,
                  if download_widget
                    VBox(
                      VSpacing(2),
                      Left(
                        CheckBox(
                          Id(:download_metadata),
                          _(WIDGET_LABELS[:download_metadata]),
                          @_download_metadata
                        )
                      )
                    )
                  else
                    Empty()
                  end,
                  VStretch()
                )
              )
            )
          )
        ),
        HStretch()
      )
      if NetworkService.isNetworkRunning
        Builtins.y2milestone(
          "Network is available, allowing Network-related options..."
        )
      else
        Builtins.y2milestone(
          "Network is not available, skipping all Network-related options..."
        )

        contents = HBox(
          HStretch(),
          VBox(
            VStretch(),
            addon_checkbox_term,
            RadioButtonGroup(
              Id(:type),
              VBox(
                HBox(
                  addon_spacing_term,
                  VBox(
                    Left(RadioButton(Id(:specify_url),
                      _(WIDGET_LABELS[:specify_url]))),
                    VSpacing(0.4),
                    *[:cd, :dvd, :hd, :usb, :local_dir, :local_iso].map do |id|
                      Left(RadioButton(Id(id), _(WIDGET_LABELS[id])))
                    end,
                    if download_widget
                      VBox(
                        VSpacing(2),
                        Left(
                          CheckBox(
                            Id(:download_metadata),
                            _(WIDGET_LABELS[:download_metadata]),
                            @_download_metadata
                          )
                        )
                      )
                    else
                      Empty()
                    end,
                    VStretch()
                  )
                )
              )
            )
          ),
          HStretch()
        )
      end
      deep_copy(contents)
    end

    def SelectRadioWidget
      SelectRadioWidgetOpt(false)
    end

    def SelectRadioWidgetDL
      SelectRadioWidgetOpt(true)
    end

    def SelectWidgetHelp
      # help text
      _(
        "<p><big><b>Media Type</b></big><br>\n" \
        "The software repository can be located on CD, on a network server,\n" \
        "or on the hard disk.</p>"
      ) +
        _(
          "<p>\n" \
          "To add  <b>CD</b> or <b>DVD</b>,\n" \
          "have the product CD set or the DVD available.</p>"
        ) +
        _(
          "<p>\n" \
          "The product CDs can be copied to the hard disk.\n" \
          "Enter the path to the first CD, for example, /data1/<b>CD1</b>.\n" \
          "Only the base path is required if all CDs are copied\n" \
          "into the same directory.</p>\n"
        ) +
        _(
          "<p>\n" \
          "Network installation requires a working network connection.\n" \
          "Specify the directory in which the packages from\n" \
          "the first CD are located, such as /data1/CD1.</p>\n"
        )
    end

    def SelectValidate(_key, _event)
      # skip validation if disabled by the global checkbox
      return true if global_disable

      selected = Convert.to_symbol(UI.QueryWidget(Id(:type), :CurrentButton))
      if selected.nil?
        # error popup
        Popup.Message(_("Select the media type"))
        return false
      end
      case selected
      when :cd, :dvd
        Pkg.SourceReleaseAll
        msg = if selected == :cd
          _("Insert the add-on product CD")
        else
          _("Insert the add-on product DVD")
        end

        # reset the device name
        @cd_device_name = ""

        # ask for a medium
        ui_result = SourceManager.AskForCD(msg)
        return false if !Ops.get_boolean(ui_result, "continue", false)

        cd_device = Ops.get_string(ui_result, "device", "")
        if !cd_device.nil? && cd_device != ""
          Builtins.y2milestone("Selected CD/DVD device: %1", cd_device)
          @cd_device_name = cd_device
        end
      when :usb
        usb_disks = DetectUSBDisk()

        if Builtins.size(usb_disks).zero?
          Report.Error(_("No USB disk was detected."))
          return false
        end
      end
      true
    end

    # Handles Ui events in New repository type selection dialog
    #
    # @param [String] _key widget key
    # @param [Hash] event event description
    # @return [Symbol]
    def SelectHandle(_key, event)
      case event["ID"]
      when :back
        # reset the preselected URL when going back
        @_url = ""
        return nil
      when :add_addon
        RefreshTypeWidgets()
        return nil
      when :network
        Yast::WFM.CallFunction(
          "inst_lan",
          [{ "skip_detection" => true, "hide_abort_button" => true }]
        )
      end

      return nil if event["ID"] != :next && event["ID"] != :ok

      #  TODO: disable "download" option when CD or DVD source is selected

      selected = UI.QueryWidget(Id(:type), :CurrentButton)
      return :finish if SPECIAL_TYPES.include?(selected) && !global_disable

      nil
    end

    # Get the status of the global checkbox.
    # @return [Boolean] true if the global checkbox is displayed and is unchecked,
    #   false otherwise
    def global_disable
      UI.WidgetExists(:add_addon) && !UI.QueryWidget(:add_addon, :Value)
    end

    def SelectStore(_key, _event)
      @_url = ""
      @_plaindir = false
      @_repo_name = ""
      @addon_enabled = !global_disable

      return nil if global_disable

      selected = Convert.to_symbol(UI.QueryWidget(Id(:type), :CurrentButton))

      if Builtins.contains(
        [
          :ftp,
          :http,
          :https,
          :samba,
          :nfs,
          :cd,
          :dvd,
          :usb,
          :hd,
          :local_dir,
          :specify_url,
          :slp,
          :local_iso,
          :sccrepos,
          :comm_repos
        ],
        selected
      )
        case selected
        when :ftp
          @_url = "ftp://"
        when :http
          @_url = "http://"
        when :https
          @_url = "https://"
        when :samba
          @_url = "smb://"
        when :nfs
          @_url = "nfs://"
        # this case is specific, as it return complete path and not just
        # prefix as others
        when :cd, :dvd
          # use three slashes as third slash means path
          @_url = (selected == :cd) ? "cd:///" : "dvd:///"
          if @cd_device_name != ""
            @_url = Ops.add(
              Ops.add(@_url, "?devices="),
              URLRecode.EscapeQuery(@cd_device_name)
            )
          end
        when :hd
          @_url = "hd://"
        when :usb
          @_url = "usb://"
        when :local_dir
          @_url = "dir://"
        when :local_iso
          @_url = "iso://"
        when :slp
          @_url = "slp://"
        when :comm_repos
          @_url = "commrepos://"
        when :sccrepos
          @_url = "sccrepos://"
        end
      else
        Builtins.y2error("Unexpected repo type %1", selected)
      end

      nil
    end

    def SelectInit(_key)
      current = nil

      case @_url
      when "ftp://"
        current = :ftp
      when "http://"
        current = :http
      when "https://"
        current = :https
      when "smb://"
        current = :samba
      when "nfs://", "nfs4://"
        current = :nfs
      when "cd://"
        current = :cd
      when "dvd://"
        current = :dvd
      when "hd://"
        current = :hd
      when "usb://"
        current = :usb
      when "dir://", "file://"
        current = :local_dir
      when "iso://"
        current = :local_iso
      when "slp://"
        current = :slp
      when "commrepos://"
        current = :comm_repos
      when "sccrepos://"
        current = :sccrepos
      else
        Builtins.y2warning("Unknown URL scheme '%1'", @_url)
        current = :specify_url
      end

      UI.ChangeWidget(Id(:type), :CurrentButton, current) if !current.nil?

      RefreshTypeWidgets()

      nil
    end

    def RefreshTypeWidgets
      return unless UI.WidgetExists(:add_addon)

      enabled = UI.QueryWidget(Id(:add_addon), :Value)

      WIDGET_LABELS.each_key do |widget|
        UI.ChangeWidget(Id(widget), :Enabled, enabled) if UI.WidgetExists(widget)
      end
      UI.ChangeWidget(Id(:type), :Enabled, enabled) if UI.WidgetExists(:type)
    end

    def SelectWidget
      {
        "widget"            => :func,
        "widget_func"       => fun_ref(method(:SelectRadioWidget), "term ()"),
        "init"              => fun_ref(method(:SelectInit), "void (string)"),
        "help"              => SelectWidgetHelp(),
        "validate_type"     => :function,
        "validate_function" => fun_ref(
          method(:SelectValidate),
          "boolean (string, map)"
        ),
        "store"             => fun_ref(
          method(:SelectStore),
          "void (string, map)"
        ),
        "handle"            => fun_ref(
          method(:SelectHandle),
          "symbol (string, map)"
        )
      }
    end

    def GetDownloadOption
      @_download_metadata
    end

    def SetDownloadOption(download)
      @_download_metadata = download

      nil
    end

    def SelectStoreDl(key, event)
      event = deep_copy(event)
      SelectStore(key, event)

      @_download_metadata = Convert.to_boolean(
        UI.QueryWidget(Id(:download_metadata), :Value)
      )

      nil
    end

    def SelectWidgetHelpDl
      _(
        "<p><b>Download Files</b><br>\n" \
        "Each repository has description files which describe the content of the\n" \
        "repository. Check <b>Download repository description files</b> to download the\n" \
        "files when closing this YaST module. If the option is unchecked, YaST will\n" \
        "automatically download the files when it needs them later. </p>\n"
      )
    end

    def SelectWidgetDL
      {
        "widget"            => :func,
        "widget_func"       => fun_ref(method(:SelectRadioWidgetDL), "term ()"),
        "init"              => fun_ref(method(:SelectInit), "void (string)"),
        "help"              => Ops.add(SelectWidgetHelp(), SelectWidgetHelpDl()),
        "validate_type"     => :function,
        "validate_function" => fun_ref(
          method(:SelectValidate),
          "boolean (string, map)"
        ),
        "store"             => fun_ref(
          method(:SelectStoreDl),
          "void (string, map)"
        ),
        "handle"            => fun_ref(
          method(:SelectHandle),
          "symbol (string, map)"
        )
      }
    end

    # Get individual widgets
    # @return individual widgets
    def Widgets
      if Builtins.size(@_widgets).zero?
        @_widgets = {
          "repo_name"    => RepoNameWidget(),
          "service_name" => ServiceNameWidget(),
          "url"          => PlainURLWidget(),
          "nfs"          => NFSWidget(),
          "cd"           => CDWidget(),
          "dvd"          => CDWidget(),
          "hd"           => DiskWidget(),
          "usb"          => USBWidget(),
          "dir"          => DirWidget(),
          "file"         => DirWidget(),
          "iso"          => IsoWidget(),
          "http"         => ServerWidget(),
          "https"        => ServerWidget(),
          "ftp"          => ServerWidget(),
          "smb"          => ServerWidget(),
          "cifs"         => ServerWidget(),
          "select"       => SelectWidget(),
          "select_dl"    => SelectWidgetDL()
        }
      end
      deep_copy(@_widgets)
    end

    # general functions

    # Get contents of a popup for specified protocol
    # @param [String] proto string protocol to display popup for
    # @return [Yast::Term] popup contents
    def PopupContents(proto, repository)
      VBox(
        HSpacing(50),
        # label
        Heading(Ops.get(@_caption, proto, "")),
        repository ? "repo_name" : "service_name",
        VSpacing(0.4),
        proto,
        VSpacing(0.4),
        PopupButtons()
      )
    end

    def EditDisplayInt(repository)
      proto = URLScheme(@_url)

      Builtins.y2milestone(
        "Displaying %1 popup for protocol %2",
        repository ? "repository" : "service",
        proto
      )

      w = CWM.CreateWidgets(
        [repository ? "repo_name" : "service_name", proto],
        Widgets()
      )
      Builtins.y2milestone("w: %1", w)
      contents = PopupContents(proto, repository)
      contents = CWM.PrepareDialog(contents, w)
      UI.OpenDialog(contents)
      ret = CWM.Run(w, {})
      Builtins.y2milestone("Ret: %1", ret)
      UI.CloseDialog
      [:ok, :next].include?(ret) ? GetURL() : ""
    end

    def EditDisplay
      EditDisplayInt(true)
    end

    def EditDisplayService
      EditDisplayInt(false)
    end

    # URL editation popup
    # @param [String] url string url URL to edit
    # @return [String] modified URL or empty string if canceled
    def EditPopup(url)
      SetURL(url)

      EditDisplay()
    end

    # URL editation popup
    # @param [String] url string url URL to edit
    # @return [String] modified URL or empty string if canceled
    def EditPopupService(url)
      SetURL(url)

      EditDisplayService()
    end

    # URL editation popup, allows setting plaindir type
    # @param [String] url string url URL to edit
    # @param [Boolean] plaindir_type set to true if the repository is plaindor
    # @return [String] modified URL or empty string if canceled
    def EditPopupType(url, plaindir_type)
      SetURLType(url, plaindir_type)

      EditDisplay()
    end

    # URL editation popup without the HTTPS option
    # @param [String] url string url URL to edit
    # @return [String] modified URL or empty string if canceled
    def EditPopupNoHTTPS(url)
      @_allow_https = false
      ret = EditPopup(url)
      @_allow_https = true
      ret
    end

    # Sample implementation of URL selection dialog
    # @return [Symbol] for wizard sequencer
    def EditDialogProtocol(proto)
      Builtins.y2milestone("Displaying dialog for protocol %1", proto)
      caption = Ops.get(@_caption, proto, "")

      CWM.ShowAndRun(
        "widget_names"       => ["repo_name", proto],
        "widget_descr"       => Widgets(),
        "contents"           => HVCenter(
          MinWidth(65, VBox("repo_name", proto))
        ),
        "caption"            => caption,
        "back_button"        => Label.BackButton,
        "next_button"        => Label.NextButton,
        "fallback_functions" => @default_cwm_fallback_functions
      )
    end

    # Sample implementation of URL selection dialog
    # @return [Symbol] for wizard sequencer
    def EditDialogProtocolService(proto)
      Builtins.y2milestone("Displaying service dialog for protocol %1", proto)
      caption = Ops.get(@_caption, proto, "")

      CWM.ShowAndRun(
        "widget_names"       => ["service_name", proto],
        "widget_descr"       => Widgets(),
        "contents"           => HVCenter(
          MinWidth(65, VBox("service_name", proto))
        ),
        "caption"            => caption,
        "back_button"        => Label.BackButton,
        "next_button"        => Label.NextButton,
        "fallback_functions" => @default_cwm_fallback_functions
      )
    end

    # Sample implementation of URL selection dialog
    # @return [Symbol] for wizard sequencer
    def EditDialog
      proto = URLScheme(@_url)

      EditDialogProtocol(proto)
    end

    # URL editation popup with the HTTPS option
    # @return [String] modified URL or empty string if canceled
    def TypePopup
      w = CWM.CreateWidgets(["select"], Widgets())
      contents = PopupContents("select", true)
      contents = CWM.PrepareDialog(contents, w)
      UI.OpenDialog(contents)
      ret = CWM.Run(w, {})
      Builtins.y2milestone("Ret: %1", ret)
      UI.CloseDialog
      ""
      #    if (ret == `ok)
      #   return GetURL ();
      #    else
      #   return "";
    end

    # Sample implementation of URL type selection dialog
    # @return [Symbol] for wizard sequencer
    def TypeDialog
      Builtins.y2milestone("Running repository type dialog")
      # dialog caption
      caption = _("Media Type")
      ret = CWM.ShowAndRun(
        "widget_names"       => ["select"],
        "widget_descr"       => Widgets(),
        "contents"           => VBox(network_button, "select"),
        "caption"            => caption,
        "back_button"        => Label.BackButton,
        "next_button"        => Label.NextButton,
        "fallback_functions" => @default_cwm_fallback_functions
      )
      Builtins.y2milestone("Type dialog returned %1", ret)
      ret
    end

    # Sample implementation of URL type selection dialog
    # @return [Symbol] for wizard sequencer
    def TypeDialogDownloadOpt
      Builtins.y2milestone(
        "Running repository type dialog with download option"
      )

      # dialog caption
      caption = _("Add On Product")
      ui = CWM.ShowAndRun(
        "widget_names"       => ["select_dl"],
        "widget_descr"       => Widgets(),
        "contents"           => VBox(network_button, "select_dl"),
        "caption"            => caption,
        "back_button"        => Label.BackButton,
        "next_button"        => Label.NextButton,
        "fallback_functions" => @default_cwm_fallback_functions
      )

      ret = { "ui" => ui, "download" => @_download_metadata }

      Builtins.y2milestone("Type dialog returned %1", ret)
      deep_copy(ret)
    end

    # Returns boolean whether user confirmed to abort the configuration
    #
    # @return [Boolean] whether to abort
    def confirm_abort?
      (Stage.initial ? Popup.ConfirmAbort(:painless) : Popup.ReallyAbort(SourceManager.Modified()))
    end

    def valid_scheme?(url)
      scheme = URL.Parse(url)["scheme"] || ""
      scheme.downcase!
      ret = VALID_URL_SCHEMES.include?(scheme)

      Report.Error(_("URL scheme '%s' is not valid.") % scheme) unless ret

      ret
    end

    publish function: :SetURL, type: "void (string)"
    publish function: :SetURLType, type: "void (string, boolean)"
    publish function: :GetURL, type: "string ()"
    publish function: :GetRawURL, type: "string ()"
    publish function: :IsPlainDir, type: "boolean ()"
    publish function: :SetRepoName, type: "void (string)"
    publish function: :GetRepoName, type: "string ()"
    publish function: :GetDownloadOption, type: "boolean ()"
    publish function: :SetDownloadOption, type: "void (boolean)"
    publish function: :EditPopup, type: "string (string)"
    publish function: :EditPopupService, type: "string (string)"
    publish function: :EditPopupType, type: "string (string, boolean)"
    publish function: :EditPopupNoHTTPS, type: "string (string)"
    publish function: :EditDialogProtocol, type: "symbol (string)"
    publish function: :EditDialogProtocolService, type: "symbol (string)"
    publish function: :EditDialog, type: "symbol ()"
    publish function: :TypePopup, type: "string ()"
    publish function: :TypeDialog, type: "symbol ()"
    publish function: :TypeDialogDownloadOpt, type: "map <string, any> ()"
  end

  SourceDialogs = SourceDialogsClass.new
  SourceDialogs.main
end
