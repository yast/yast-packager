require "yast/rake"

Yast::Tasks.submit_to :sle15sp2

Yast::Tasks.configuration do |conf|
  # lets ignore license check for now
  conf.skip_license_check << /.*/
  conf.install_locations["desktop/*.desktop"] = Packaging::Configuration::DESTDIR +
    "/usr/share/applications"
end
