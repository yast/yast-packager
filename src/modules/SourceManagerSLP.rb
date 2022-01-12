require "yast"
require "y2firewall/firewalld"

# YaST Namespace
module Yast
  # This module provides a complete set of functions that allows you to search
  # and select a new SLP repository.
  class SourceManagerSLPClass < Module
    def main
      Yast.import "UI"
      Yast.import "SLP"
      Yast.import "Wizard"
      Yast.import "Directory"
      Yast.import "Stage"
      Yast.import "Report"
      Yast.import "Label"
      #    import "IP";
      #    import "String";
      #    import "FileUtils";

      textdomain "packager"
    end

    def Icon(icon_name)
      ui_info = UI.GetDisplayInfo
      return Empty() if !Ops.get_boolean(ui_info, "HasLocalImageSupport", false)

      Image(icon_name, "[x]")
    end

    def CreateSearchUI
      UI.OpenDialog(
        VBox(
          HBox(
            HSquash(MarginBox(0.5, 0.2, Icon("yast-you_server"))),
            # translators: popup heading (progress popup)
            Left(Heading(Id(:search_heading), _("SLP Search")))
          ),
          Left(
            # progress information
            ReplacePoint(
              Id(:search_rp),
              Label(_("Scanning network for installation services..."))
            )
          )
        )
      )

      nil
    end

    def CloseSearchUI
      UI.CloseDialog

      nil
    end

    def SetSearchUI(content)
      content = deep_copy(content)
      UI.ReplaceWidget(Id(:search_rp), content)

      nil
    end

    def SearchForSLPServices(services)
      # progress information
      SetSearchUI(Label(_("Scanning network for installation services...")))
      Builtins.y2milestone(
        "scanning network: SLP::FindSrvs(\"install.suse\", \"\")"
      )
      services.value = SLP.FindSrvs("install.suse", "")
      Builtins.y2milestone(
        "Done, found %1 repositories",
        Builtins.size(services.value)
      )

      nil
    end

    def CreateSLPListFoundDialog(services)
      filter_dialog = Empty()
      show_filter = false

      # Show filter only for bigger amount of services
      if Ops.greater_than(Builtins.size(services.value), 15)
        show_filter = true
        filter_dialog = MarginBox(
          0.5,
          0.5,
          Frame(
            # frame label
            _("Filter Form"),
            VSquash(
              HBox(
                HSquash(MinWidth(22, TextEntry(Id(:filter_text), ""))),
                # push button
                PushButton(Id(:filter), _("&Filter")),
                HStretch()
              )
            )
          )
        )
      end

      # bugzilla #209426
      # window size (in ncurses) based on currently available space
      display_info = UI.GetDisplayInfo
      min_size_x = 76
      min_size_y = 19
      if Ops.get_boolean(display_info, "TextMode", true)
        min_size_x = Ops.divide(
          Ops.multiply(
            Builtins.tointeger(Ops.get_integer(display_info, "Width", 80)),
            3
          ),
          4
        )
        min_size_y = Ops.subtract(
          Ops.divide(
            Ops.multiply(
              Builtins.tointeger(Ops.get_integer(display_info, "Height", 25)),
              2
            ),
            3
          ),
          5
        )
        min_size_x = 76 if Ops.less_than(min_size_x, 76)
        min_size_y = 18 if Ops.less_than(min_size_y, 18)
        Builtins.y2milestone(
          "X/x Y/y %1/%2 %3/%4",
          Ops.get_integer(display_info, "Width", 80),
          min_size_x,
          Ops.get_integer(display_info, "Height", 25),
          min_size_y
        )
      end

      UI.OpenDialog(
        VBox(
          HBox(
            HSquash(MarginBox(0.5, 0.2, Icon("yast-you_server"))),
            # translators: popup heading
            Left(Heading(Id(:search_heading), _("Choose SLP Repository")))
          ),
          filter_dialog,
          MarginBox(
            0.5,
            0,
            MinSize(
              min_size_x,
              min_size_y,
              Tree(
                Id(:tree_of_services),
                Opt(:notify),
                # tree label (tree of available products)
                _("Available Installation &Products"),
                []
              )
            )
          ),
          PushButton(Id(:details), _("&Details...")),
          VSpacing(1),
          HBox(
            PushButton(Id(:ok), Opt(:default), Label.SelectButton),
            VSpacing(1),
            PushButton(Id(:cancel), Label.CancelButton)
          )
        )
      )

      UI.SetFocus(:filter_text) if show_filter

      nil
    end

    def InitDetailsButton
      current = Convert.to_integer(
        UI.QueryWidget(Id(:tree_of_services), :CurrentItem)
      )
      if current.nil? || Ops.less_than(current, 0)
        UI.ChangeWidget(Id(:details), :Enabled, false)
      else
        UI.ChangeWidget(Id(:details), :Enabled, true)
      end

      nil
    end

    def ShowDetailsDialog(services)
      current = Convert.to_integer(
        UI.QueryWidget(Id(:tree_of_services), :CurrentItem)
      )
      if current.nil? || Ops.less_than(current, 0)
        Builtins.y2error("No service selected, no details")
        # error popup
        Report.Error(_("No details are available."))
      else
        service_details = Ops.get(services.value, current, {})

        if service_details == {}
          # message popup
          Report.Message(_("No details are available."))
        else
          # maximal size allowed by UI (with a fallback)
          display_information = UI.GetDisplayInfo
          max_width = Ops.get_integer(display_information, "Width", 1200)
          max_heigth = Ops.get_integer(display_information, "Height", 500)
          # Graphical UI returns 1280x1024, textmode 80x25
          if !Ops.get_boolean(display_information, "TextMode", false)
            max_width = Ops.divide(max_width, 15)
            max_heigth = Ops.divide(max_heigth, 18)
          end

          # maximal length of key and val found
          max_len_key = 0
          max_len_val = 0

          details = []
          curr_len_key = 0
          curr_len_val = 0

          Builtins.foreach(service_details) do |key, value|
            details = Builtins.add(
              details,
              Item(Id(nil), Builtins.tostring(key), Builtins.tostring(value))
            )
            curr_len_key = Builtins.size(Builtins.tostring(key))
            curr_len_val = Builtins.size(Builtins.tostring(value))
            if !curr_len_key.nil? &&
                Ops.greater_than(curr_len_key, max_len_key)
              max_len_key = curr_len_key
            end
            if !curr_len_val.nil? &&
                Ops.greater_than(curr_len_val, max_len_val)
              max_len_val = curr_len_val
            end
          end
          # maximal key + maximal val (presented in table)
          max_len_total = Ops.add(max_len_key, max_len_val)

          # min X in UI
          min_size_x = max_len_total
          min_size_x = max_width if Ops.greater_than(min_size_x, max_width)
          min_size_x = 60 if Ops.less_than(min_size_x, 60)

          # min Y in UI
          min_size_y = Ops.add(Builtins.size(details), 4)
          min_size_y = max_heigth if Ops.greater_than(min_size_y, max_heigth)
          min_size_y = 14 if Ops.less_than(min_size_y, 14)

          Builtins.y2milestone(
            "Details min size: %1 x %2",
            min_size_x,
            min_size_y
          )

          UI.OpenDialog(
            VBox(
              Left(Heading(Id(:details_heading), _("Repository Details"))),
              MinSize(
                min_size_x,
                min_size_y,
                Table(
                  Header(
                    # table header item
                    _("Key"),
                    # table header item
                    _("Value")
                  ),
                  details
                )
              ),
              VSpacing(1),
              PushButton(Id(:ok), Label.OKButton)
            )
          )
          UI.UserInput
          UI.CloseDialog
        end
      end

      nil
    end

    # Initializes the listed SLP services.
    #
    # @param [Yast::ArgRef] services reference to services (Array<Hash>)
    # @param [String,nil] filter_string regexp for services that should be visible
    #   (nil or "" for all)
    def InitSLPListFoundDialog(services, filter_string)
      filter_string = nil if filter_string == ""

      inst_products = {}
      service_label = nil

      # index in the list of 'services'
      service_counter = -1

      Builtins.foreach(services.value) do |one_service|
        # always increase the service ID, must be consistent for all turns
        service_counter = Ops.add(service_counter, 1)
        service_label = Ops.get_string(one_service, "label", "")
        # bugzilla #219759
        # service label can be empty (not defined)
        if service_label == ""
          if Ops.get_string(one_service, "srvurl", "") == ""
            Builtins.y2error(
              "Wrong service definition: %1, key \"srvurl\" must not be empty.",
              one_service
            )
          else
            service_label = Builtins.sformat(
              "%1: %2",
              _("Repository URL"),
              Builtins.substring(Ops.get_string(one_service, "srvurl", ""), 21)
            )
          end
        end
        # search works in "label" or in "srvurl" as a fallback
        if !filter_string.nil? && !service_label.downcase.include?(filter_string.downcase)
          # filter out all services that don't match the filter
          next
        end

        # define an empty list if it is not defined at all
        Ops.set(inst_products, service_label, []) if Ops.get(inst_products, service_label).nil?
        Ops.set(
          inst_products,
          service_label,
          Builtins.add(
            Ops.get(inst_products, service_label, []),
            service_counter
          )
        )
      end

      tree_of_services = []
      urls_for_product = nil
      product_counter = -1
      service_url = nil

      # "SUSE Linux 10.2 x86_64":[10, 195]
      Builtins.foreach(inst_products) do |one_product, service_ids|
        product_counter = Ops.add(product_counter, 1)
        if Builtins.size(service_ids) == 1
          Ops.set(
            tree_of_services,
            product_counter,
            Item(Id(Ops.get(service_ids, 0)), one_product)
          )
        else
          urls_for_product = []
          Builtins.foreach(service_ids) do |service_id|
            # removing "install.suse..."
            service_url = Builtins.substring(
              Ops.get_string(services.value, [service_id, "srvurl"], ""),
              21
            )
            urls_for_product = Builtins.add(
              urls_for_product,
              Item(Id(service_id), service_url)
            )
          end
          # -1 for a product name without url (URLs are hidden below)
          Ops.set(
            tree_of_services,
            product_counter,
            Item(Id(-1), one_product, urls_for_product)
          )
        end
      end

      UI.ChangeWidget(Id(:tree_of_services), :Items, tree_of_services)
      InitDetailsButton()

      nil
    end

    def GetCurrentlySelectedURL(services)
      current = Convert.to_integer(
        UI.QueryWidget(Id(:tree_of_services), :CurrentItem)
      )

      if current.nil? || Ops.less_than(current, 0)
        # message popup
        Report.Message(
          _(
            "Select one of the offered options.\n" \
            "More repositories are available for this product.\n"
          )
        )

        nil
      else
        service_url = Builtins.substring(
          Ops.get_string(services.value, [current, "srvurl"], ""),
          21
        )

        if service_url.nil? || service_url == ""
          Builtins.y2error(
            "An internal error occurred, service ID %1, %2 has no URL!",
            current,
            Ops.get(services.value, current, {})
          )
          # popup error
          Report.Error(
            _(
              "An internal error occurred.\nThe selected repository has no URL."
            )
          )
          return nil
        end

        service_url
      end
    end

    def HandleSLPListDialog(services)
      services_ref = arg_ref(services.value)
      InitSLPListFoundDialog(services_ref, nil)
      services.value = services_ref.value

      dialog_ret = nil
      ret = nil

      loop do
        ret = UI.UserInput

        case ret
        when :cancel
          dialog_ret = nil
          break
        when :ok
          dialog_ret = (
            services_ref = arg_ref(services.value)
            result = GetCurrentlySelectedURL(
              services_ref
            )
            services.value = services_ref.value
            result
          )
          Builtins.y2milestone("Selected URL: '%1'", dialog_ret)
          break if dialog_ret != "" && !dialog_ret.nil?
        when :tree_of_services
          InitDetailsButton()
        when :filter
          filter_string = UI.QueryWidget(Id(:filter_text), :Value)
          Builtins.y2milestone("filter_string: %1", filter_string)

          services_ref = arg_ref(services.value)
          InitSLPListFoundDialog(services_ref, filter_string)
          services.value = services_ref.value
        when :details
          services_ref = arg_ref(services.value)
          ShowDetailsDialog(services_ref)
          services.value = services_ref.value
        else
          Builtins.y2error("Unknown ret: %1", ret)
        end
      end

      dialog_ret
    end

    def CloseSLPListFoundDialog
      UI.CloseDialog

      nil
    end

    def SearchForSLPServicesInfo(services)
      number_of_services = Builtins.size(services.value)

      SetSearchUI(
        Label(
          Builtins.sformat(
            # progress information, %1 stands for number of services
            _("Collecting information of %1 services found..."),
            number_of_services
          )
        )
      )

      Builtins.y2milestone(
        "Collecting data about %1 services",
        number_of_services
      )

      new_services = []

      counter = -1
      Builtins.foreach(services.value) do |slp_service|
        counter = Ops.add(counter, 1)
        server_ip = Ops.get_string(slp_service, "ip", "")
        service_url = Ops.get_string(slp_service, "srvurl", "")
        # empty server_ip
        if service_url != "" && server_ip != ""
          attrs = SLP.GetUnicastAttrMap(service_url, server_ip)

          slp_service = Builtins.union(slp_service, attrs) if !attrs.nil? && attrs != {}
        end
        Ops.set(new_services, counter, slp_service)
      end

      Builtins.y2milestone("Done")

      services.value = deep_copy(new_services)

      nil
    end

    # Function searches the SLP services on the current network.
    # If there are some SLP services, opens up a dialog containing
    # them and user has to select one or cancel the operation.
    # Selected URL is returned as string, otherwise a nil is returned.
    #
    # @return [String] service_URL
    def SelectOneSLPService
      CreateSearchUI()
      slp_services_found = []
      slp_services_found_ref = arg_ref(slp_services_found)
      SearchForSLPServices(slp_services_found_ref)
      slp_services_found = slp_services_found_ref.value

      if slp_services_found.nil? || Builtins.size(slp_services_found).zero?
        Builtins.y2warning("No SLP repositories found")
      else
        slp_services_found_ref = arg_ref(slp_services_found)
        SearchForSLPServicesInfo(slp_services_found_ref)
        slp_services_found = slp_services_found_ref.value
      end
      CloseSearchUI()

      # no servers found
      if slp_services_found.nil? || Builtins.size(slp_services_found).zero?
        Builtins.y2warning("No SLP repositories were found")
        if !Stage.initial && firewalld.running?
          Report.Message(
            # error popup
            _(
              "No SLP repositories have been found on your network.\n" \
              "This could be caused by a running firewall,\n" \
              "which probably blocks the network scanning."
            )
          )
        else
          Report.Message(
            # error popup
            _("No SLP repositories have been found on your network.")
          )
        end
        return nil
      end

      slp_services_found_ref = arg_ref(slp_services_found)
      CreateSLPListFoundDialog(slp_services_found_ref)
      slp_services_found = slp_services_found_ref.value
      selected_service = (
        slp_services_found_ref = arg_ref(slp_services_found)
        HandleSLPListDialog(slp_services_found_ref)
      )
      CloseSLPListFoundDialog()

      selected_service
    end

    # Function scans for SLP installation servers on the network
    # @return [Symbol] one of `back, `next
    def AddSourceTypeSLP
      url = SelectOneSLPService()
      Builtins.y2milestone("Selected URL: %1", url)

      url
    end

    def firewalld
      Y2Firewall::Firewalld.instance
    end

    publish function: :SelectOneSLPService, type: "string ()"
    publish function: :AddSourceTypeSLP, type: "string ()"
  end

  SourceManagerSLP = SourceManagerSLPClass.new
  SourceManagerSLP.main
end
