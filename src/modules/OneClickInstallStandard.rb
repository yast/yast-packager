require "yast"

require "nokogiri"

# Yast namespace
module Yast
  # Module for parsing One Click Install Standard
  # http://en.opensuse.org/Standards/One_Click_Install
  class OneClickInstallStandardClass < Module
    include Yast::Logger

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
    #              "alias" : "factory",
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

      if !FileUtils.Exists(filename)
        log.error "File doesn't exist: #{filename}"
        return []
      end

      doc = Nokogiri::XML(File.read(filename), &:strict)
      doc.remove_namespaces! # avoid fancy namespaces as it is not needed for this xml

      ret = []
      groups = doc.root.xpath("/metapackage/group")

      # starting with <metapackage>-><group>
      groups.each do |group|
        distversion = group["distversion"] || ""
        repositories = group.xpath("./repositories/repository")
        repositories.each do |repository|
          url = repository.xpath("./url")
          url = url ? url.text : ""
          # One repository (required keys)
          repo_out = {
            "distversion" => distversion,
            "url"         => url,
            "format"      => repository["format"] || "",
            "alias"       => repository["alias"],
            "recommended" => repository["recommended"] == "true"
          }
          # Required + dynamic (localized) keys
          ["name", "description", "summary"].each do |key|
            loc_key = "localized_" + key
            repo_out[loc_key] = {}
            elements = repository.xpath("./#{key}")
            elements.each do |item|
              if item["lang"]
                repo_out[loc_key][item["lang"]] = item.text
              else
                repo_out[key] = item.text
              end
            end
          end

          ret << repo_out
        end
      end

      ret
    rescue Nokogiri::XML::SyntaxError => e
      log.error "syntax error in file #{filename}: #{e.message}"
      return []
    end

    publish function: :GetRepositoriesFromXML, type: "list <map <string, any>> (string)"
  end

  OneClickInstallStandard = OneClickInstallStandardClass.new
  OneClickInstallStandard.main
end
