# encoding: utf-8

# Module:	OneClickInstallStandard.pm
# Authors:	Lukas Ocilka <locilka@suse.cz>
# Summary:	Module for parsing One Click Install Standard
#		http://en.opensuse.org/Standards/One_Click_Install
require "yast"

module Yast
  class OneClickInstallStandardClass < Module
    def main

      textdomain "packager"

      Yast.import "FileUtils"
    end

    # Converts XML file to a list of maps with all repositories described in the XML content.
    #
    # @param [String] filename XML file
    # @return [Array<Hash, <String, Object> >]
    #
    #
    # **Structure:**
    #
    #     $[
    #              "distversion" : "openSUSE Factory",
    #              "url" : "full url of the repository (http://.../)",
    #              "format" : "yast",
    #              "recommended" : true,
    #              "description" : "repository description",
    #              "localized_description" : $[
    #                  "en_GB" : "repository description (localized to en_GB)",
    #                  ...
    #              ],
    #              "summary" : "repository summary",
    #              "localized_summary" : $[
    #                  "en_GB" : "repository summary (localized to en_GB)",
    #                  ...
    #              ],
    #              "name" : "repository name",
    #              "localized_name" : $[
    #                  "en_GB" : "repository name (localized to en_GB)",
    #                  ...
    #              ],
    #      ]
    def GetRepositoriesFromXML(filename)
      ret = []

      if !FileUtils.Exists(filename)
        Builtins.y2error("File doesn't exist: %1", filename)
        return deep_copy(ret)
      end

      read_result = Convert.to_map(SCR.Read(path(".anyxml"), filename))

      if read_result == nil
        Builtins.y2error("Cannot read file: %1", filename)
        return deep_copy(ret)
      elsif read_result == {}
        Builtins.y2warning("File %1 is empty", filename)
        return deep_copy(ret)
      end

      distversion = ""

      one_repo_out = {}

      # starting with <metapackage>-><group>
      Builtins.foreach(
        Ops.get_list(read_result, ["metapackage", 0, "group"], [])
      ) do |one_group|
        distversion = Ops.get_string(one_group, "distversion", "")
        Builtins.foreach(
          Ops.get_list(one_group, ["repositories", 0, "repository"], [])
        ) do |repository|
          # One repository (requierd keys)
          one_repo_out = {
            "distversion" => distversion,
            "url"         => Ops.get_string(
              repository,
              ["url", 0, "content"],
              ""
            ),
            "format"      => Ops.get_string(repository, "format", ""),
            "recommended" => Ops.get_string(repository, "recommended", "false") == "true"
          }
          # Required + dynamic (localized) keys
          Builtins.foreach(["name", "description", "summary"]) do |one_key|
            loc_key = Ops.add("localized_", one_key)
            Ops.set(one_repo_out, loc_key, {})
            Builtins.foreach(Ops.get_list(repository, one_key, [])) do |one_item|
              if Ops.get_string(one_item, "content", "") != ""
                if Builtins.haskey(one_item, "xml:lang")
                  Ops.set(
                    one_repo_out,
                    [loc_key, Ops.get_string(one_item, "xml:lang", "")],
                    Ops.get_string(one_item, "content", "")
                  )
                else
                  Ops.set(
                    one_repo_out,
                    one_key,
                    Ops.get_string(one_item, "content", "")
                  )
                end
              end
            end
          end
          # Fallback
          Builtins.foreach(["name", "description", "summary"]) do |one_key|
            if Ops.is_map?(Ops.get(repository, one_key)) &&
                Ops.get_string(repository, [one_key, "content"], "") != ""
              Ops.set(
                one_repo_out,
                one_key,
                Ops.get_string(repository, [one_key, "content"], "")
              )
            end
          end
          ret = Builtins.add(ret, one_repo_out)
        end
      end

      deep_copy(ret)
    end

    publish :function => :GetRepositoriesFromXML, :type => "list <map <string, any>> (string)"
  end

  OneClickInstallStandard = OneClickInstallStandardClass.new
  OneClickInstallStandard.main
end
