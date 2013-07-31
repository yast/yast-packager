# encoding: utf-8

# File:
#	WebpinPackageSearch.ycp
#
# Module:
#	WebpinPackageSearch
#
# Summary:
#	YaST API to api.opensuse-community.org
#
# Authors:
#	Lukas Ocilka <locilka@suse.cz>
#	Katarina Machalkova <kmachalkova@suse.cz>
require "yast"

module Yast
  class WebpinPackageSearchClass < Module
    def main

      textdomain "packager"

      Yast.import "HTTP"
      Yast.import "SuSERelease"
      Yast.import "Directory"
      Yast.import "FileUtils"
      Yast.import "URL"
      Yast.import "Arch"
      Yast.import "Report"

      @temporary_file = Ops.add(Directory.tmpdir, "/package_search_webpin.xml")

      # Base search URL, default is "http://api.opensuse-community.org/searchservice/"
      @base_url = "http://api.opensuse-community.org/searchservice/"

      # List of architecture dependencies. Every row contains one list
      # of dependencies sortred from left (the newest) to right (the oldest).
      # Architectures are backward-compatible.
      @deps = [
        # i386 and x86
        ["x86_64", "i686", "i586", "i486", "i386", "noarch", "src"],
        # PPC
        ["ppc64", "ppc", "noarch", "src"],
        # s390
        ["s390_64", "s390_32", "noarch", "src"],
        # IA-64
        ["ia64", "noarch", "src"],
        # Alpha
        [
          "alphaev67",
          "alphaev6",
          "alphapca56",
          "alphaev56",
          "alphaev5",
          "alpha",
          "noarch",
          "src"
        ],
        # SPARC
        ["sparc64", "sparcv9", "sparcv8", "sparc", "noarch", "src"],
        # MIPS
        ["mips64", "mips", "noarch", "src"]
      ]

      @already_guessed = nil
    end

    # Sets base search URL
    # WARNING: Use this only if you know what you are doing!
    #
    # @param string new base_url
    def SetBaseSearchURL(new_base_url)
      if new_base_url == "" || new_base_url == nil
        Builtins.y2error("Wrong base URL: '%1'", new_base_url)
        return
      end

      @base_url = new_base_url
      Builtins.y2milestone("New base URL has been set: %1", @base_url)

      nil
    end

    # Returns base search URL
    #
    # @string current base_url
    def GetBaseSearchURL
      @base_url
    end

    # Returns whether the current architecture matches the list of architectures
    # got as a parameter. The current architecture is backward compatible, so
    # also dependencies are taken into account.
    #
    # @param list <string> list of architectures to check
    # @return [Boolean] whether they match the current architecture
    #
    # @example
    #	// current architecture is "i386"
    #	MatchesCurrentArchitecture (["noarch", "ppc", "i386"]) -> true
    #	MatchesCurrentArchitecture (["noarch"]) -> true
    #	MatchesCurrentArchitecture (["x86_64"]) -> false
    #	MatchesCurrentArchitecture (["ppc"]) -> false
    def MatchesCurrentArchitecture(archs_to_check)
      archs_to_check = deep_copy(archs_to_check)
      current_arch = Arch.architecture

      matches = false

      # one or more archs supported by source
      Builtins.foreach(archs_to_check) do |one_arch_to_check|
        # check all arch dependencies
        Builtins.foreach(@deps) do |one_archlist|
          # both current and checked architectures are in the same list
          if Builtins.contains(one_archlist, current_arch) &&
              Builtins.contains(one_archlist, one_arch_to_check)
            cur_arch_row = nil
            match_arch_row = nil

            str_offset = -1

            # find current_architecture in deps
            Builtins.foreach(one_archlist) do |one_arch|
              str_offset = Ops.add(str_offset, 1)
              if one_arch == current_arch
                cur_arch_row = str_offset
                raise Break
              end
            end

            str_offset = -1

            # find architecture_to_check in deps
            Builtins.foreach(one_archlist) do |one_arch|
              str_offset = Ops.add(str_offset, 1)
              if one_arch == one_arch_to_check
                match_arch_row = str_offset
                raise Break
              end
            end

            # compare
            if Ops.greater_or_equal(match_arch_row, cur_arch_row)
              matches = true
              raise Break
            end
          end
        end
        raise Break if matches
      end

      matches
    end

    # Guesses the current distribution installed
    #
    # @return [String] distribution (Webpin format)
    #
    # @examle
    #   // Installed openSUSE 11.0
    #   GuessCurrentDistribution() -> "openSUSE_110"
    def GuessCurrentDistribution
      return @already_guessed if @already_guessed != nil

      rel_name = SuSERelease.ReleaseName
      rel_version = SuSERelease.ReleaseVersion

      if Builtins.regexpmatch(rel_version, ".")
        rel_version = Builtins.mergestring(
          Builtins.splitstring(rel_version, "."),
          ""
        )
      end

      @already_guessed = Builtins.sformat("%1_%2", rel_name, rel_version)
      @already_guessed
    end

    # Changes the Webpin distro format to OneClickInstall format.
    #
    # @param [String] distro
    # @return [String] modified distro
    #
    # @example
    #   ModifyDistro ("openSUSE_110") -> "openSUSE 11.0"
    def ModifyDistro(distro)
      if Builtins.regexpmatch(distro, "^.*_[0123456789]+[0123456789]$")
        distro = Builtins.regexpsub(
          distro,
          "^(.*)_([0123456789]+)([0123456789])$",
          "\\1 \\2.\\3"
        )
      elsif Builtins.regexpmatch(distro, "^.*_[0123456789]+")
        distro = Builtins.regexpsub(distro, "^(.*)_([0123456789]+)$", "\\1 \\2")
      else
        Builtins.y2warning("'%1' doesn't match any known regexp", distro)
      end

      distro
    end

    # Writes XML configuration file for OnleClickInstall client.
    #
    # @param [Array<Hash>] packages_to_install (in the same format as got from SearchForPackages function)
    # @param [String] save_to_file
    # @return [Boolean] if successful
    #
    # @see SearchForPackages() for the format of <map> package_to_install
    def PrepareOneClickInstallDescription(packages_to_install, save_to_file)
      packages_to_install = deep_copy(packages_to_install)
      if FileUtils.Exists(save_to_file)
        Builtins.y2warning("File %1 already exists, removing", save_to_file)
        SCR.Execute(path(".target.remove"), save_to_file)
      end

      distro = ""
      repoURL = ""

      write_xml = {
        "metapackage" => {
          "xmlns" => "http://opensuse.org/Standards/One_Click_Install"
        }
      }

      repositories = {}
      packages = {}

      Builtins.foreach(packages_to_install) do |one_package|
        distro = Ops.get_string(one_package, "distro") do
          GuessCurrentDistribution()
        end
        repoURL = Ops.get_string(one_package, "repoURL", "")
        # all repositories
        Ops.set(
          repositories,
          distro,
          Builtins.add(Ops.get_list(repositories, distro, []), repoURL)
        )
        # all packages
        Ops.set(
          packages,
          distro,
          Builtins.add(
            Ops.get_list(packages, distro, []),
            {
              "item" => [
                {
                  "name"        => [
                    { "content" => Ops.get_string(one_package, "name", "") }
                  ],
                  "summary"     => [
                    { "content" => Ops.get_string(one_package, "summary", "") }
                  ],
                  "description" => [
                    {
                      "content" => Ops.get_locale(
                        # TRANSLATORS: package description item
                        one_package,
                        "description",
                        Ops.get_locale(
                          one_package,
                          "summary",
                          _("No further information available.")
                        )
                      )
                    }
                  ]
                }
              ]
            }
          )
        )
      end

      Builtins.foreach(
        Convert.convert(
          repositories,
          :from => "map",
          :to   => "map <string, list <string>>"
        )
      ) do |distro2, distro_repos|
        group = {
          "distversion"      => ModifyDistro(distro2),
          "remainSubscribed" => { "content" => "true" },
          "repositories"     => Builtins.toset(Builtins.maplist(distro_repos) do |one_repo|
            {
              "repository" => [
                {
                  "name"        => [{ "content" => one_repo }],
                  "url"         => [{ "content" => one_repo }],
                  # TRANSLATORS: repository summary
                  "summary"     => [
                    { "content" => _("Unknown repository") }
                  ],
                  # TRANSLATORS: repositry description
                  "description" => [
                    {
                      "content" => _(
                        "No further information available, use at your own risk."
                      )
                    }
                  ]
                }
              ]
            }
          end),
          "software"         => Builtins.toset(
            Ops.get_list(packages, distro2, [])
          )
        }
        Ops.set(write_xml, ["metapackage", "group"], group)
      end

      Builtins.y2debug("Writing: %1", write_xml)

      success = SCR.Write(
        path(".anyxml"),
        {
          "xml"  => write_xml,
          "file" => save_to_file,
          "args" => {
            "RootName" => "metapackage",
            "KeepRoot" => true,
            "XMLDecl"  => "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
          }
        }
      )

      if success != true
        Builtins.y2error("Unable to write XML to %1", save_to_file)
      end

      success
    end

    # Searches for packages using Webpin XML API.
    #
    # @param [String] search_for text
    # @param [String] distribution, e.g., openSUSE_10.3, it is guessed from the system if set to nil
    # @param [Hash{String => Boolean}] search_in which defines in which sources it searches,
    #	possible keys: name, description, contents
    #
    # @example
    #   SearchForPackages (
    #	"desktop",
    #	nil,
    #	$[
    #	    "name" : true,
    #	    "description" : true,
    #	    "contents" : false,
    #   	]
    #   )
    #   ->
    #   [
    #     ...
    #     $[
    #        "archs":[
    #            "ppc"
    #        ],
    #        "checksum":"e0cbdbf03ce47dfd5c5f885b86706ddfa023d8dc",
    #        "distro":"openSUSE_110",
    #        "name":"xfce4-desktop",
    #        "priority":"5",
    #        "repoURL":"http://download.opensuse.org/distribution/11.0/repo/oss/suse",
    #        "summary":"Desktop manager for the Xfce Desktop Environment",
    #        "version":"4.4.2"
    #     ],
    #     ...
    #   ]
    def SearchForPackages(search_for, distribution, search_in)
      search_in = deep_copy(search_in)
      Builtins.y2milestone("Searching for %1 in %2", search_for, search_in)

      if search_for == nil || search_for == ""
        Builtins.y2error("empty search string")
        return []
      end

      # search URL is the same for both
      name_or_descr = Ops.get(search_in, "name", false) ||
        Ops.get(search_in, "description", false)

      search_path = nil

      if Ops.get(search_in, "contents", false) && name_or_descr
        search_path = "Search/Simple/"
      elsif name_or_descr
        search_path = "Search/ByName/"
      elsif Ops.get(search_in, "contents", false)
        search_path = "Search/ByContents/"
      else
        Builtins.y2warning("empty search result")
        return []
      end

      # if distro string is nil, try to guess the current one
      if distribution == nil
        distribution = GuessCurrentDistribution()
        Builtins.y2milestone(
          "Distribution not set, guessing '%1'",
          distribution
        )
      end

      url = Ops.add(
        Ops.add(
          Ops.add(Ops.add(GetBaseSearchURL(), search_path), distribution),
          "/"
        ),
        URL.EscapeString(search_for, URL.transform_map_passwd)
      )

      Builtins.y2milestone("HTTP::Get (%1, %2)", url, @temporary_file)
      response = HTTP.Get(url, @temporary_file)
      Builtins.y2milestone("Server response: %1", response)

      ret_list = []

      # something's screwed up on server side - this usually means that tmp file
      # is full of error messages - we should not let anyxml agent parse those
      if Ops.get_integer(response, "code", 0) != 200
        Builtins.y2error("Cannot retrieve search results from the server")
        # %1 is HTTP error code like 404 or 503
        Report.Error(
          Builtins.sformat(
            _("Search failed.\nRemote server returned error code %1"),
            Ops.get_integer(response, "code", 0)
          )
        )
        return nil
      end

      if !FileUtils.Exists(@temporary_file)
        Builtins.y2error("Cannot read file: %1", @temporary_file)
        return nil
      end

      if Ops.less_or_equal(FileUtils.GetSize(@temporary_file), 0)
        Builtins.y2milestone("Empty file: %1", @temporary_file)
        return nil
      end

      search_result = Convert.to_map(SCR.Read(path(".anyxml"), @temporary_file))

      Builtins.y2debug("Search result: %1", search_result)

      counter = -1
      one_entry = {}

      Builtins.foreach(
        Ops.get_list(search_result, ["ns2:packages", 0, "package"], [])
      ) do |one_package|
        one_entry = {}
        Builtins.foreach(one_package) do |key, value|
          if Builtins.haskey(Ops.get_map(value, 0, {}), "content")
            Ops.set(
              one_entry,
              key,
              Builtins.tostring(Ops.get(value, [0, "content"]))
            )
          elsif key == "archs"
            Builtins.foreach(
              Convert.convert(value, :from => "list", :to => "list <map>")
            ) { |one_arch| Builtins.foreach(Ops.get_list(one_arch, "arch", [])) do |xone_arch|
              Ops.set(
                one_entry,
                "archs",
                Builtins.add(
                  Ops.get_list(one_entry, "archs", []),
                  Ops.get_string(xone_arch, "content", "")
                )
              )
            end }
          else
            Builtins.y2error("Unknown key: %1", key)
          end
        end
        counter = Ops.add(counter, 1)
        Ops.set(ret_list, counter, one_entry)
      end

      nr_packages_found = Builtins.size(ret_list)

      if nr_packages_found == nil || nr_packages_found == 0
        Builtins.y2warning("Nothing found")
      else
        Builtins.y2milestone("%1 packages found", nr_packages_found)
      end

      deep_copy(ret_list)
    end

    publish :function => :SetBaseSearchURL, :type => "void (string)"
    publish :function => :GetBaseSearchURL, :type => "string ()"
    publish :function => :MatchesCurrentArchitecture, :type => "boolean (list <string>)"
    publish :function => :PrepareOneClickInstallDescription, :type => "boolean (list <map>, string)"
    publish :function => :SearchForPackages, :type => "list <map> (string, string, map <string, boolean>)"
  end

  WebpinPackageSearch = WebpinPackageSearchClass.new
  WebpinPackageSearch.main
end
