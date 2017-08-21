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

        # Set options to keep a minimalistic package selection
        def set_minimalistic!
          tree = data["main"]
          if !tree
            tree = ::CFA::AugeasTree.new
            data["main"] = tree
          end
          generic_set("solver.onlyRequires", "true", tree)
          generic_set("rpm.install.excludedocs", "yes", tree)
          generic_set("multiversion", nil, tree)
        end

        def section(name)
          data[name]
        end
      end
    end
  end
end
