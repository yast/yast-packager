require "cfa/base_model"
require "cfa/augeas_parser"
require "cfa/matcher"

module Yast
  module Packager
    module CFA
      # Represents a Zypper configuration file.
      class ZyppConf < ::CFA::BaseModel
        # Configuration parser
        PARSER = ::CFA::AugeasParser.new("puppet.lns")
        # Path to configuration file
        PATH = "/etc/zypp/zypp.conf".freeze

        def initialize(file_handler: nil)
          super(PARSER, PATH, file_handler: file_handler)
        end

        def set_minimalistic!
          data["main"]["solver.onlyRequires"] = "true"
          data["main"]["rpm.install.excludedocs"] = "yes"
          data["main"]["multiversion"] = nil
        end
      end
    end
  end
end
