# encoding: utf-8
require "yast"

# Yast namespace
module Yast
  # GPG Key Management
  class KeyManagerClass < Module
    def main
      Yast.import "Pkg"

      textdomain "packager"

      Yast.import "Report"
      Yast.import "Directory"
      Yast.import "String"

      # the current state
      @known_keys = []

      # keys to delete
      @deleted_keys = []

      # keys to import from a file (file name => trusted flag)
      @import_from_file = []

      @modified = false
    end

    # ////////////////////////////////////////////////////////////////////////////

    # Reset the internal state of the module. The current configuration and all
    # changes are deleted.
    def Reset
      @known_keys = []
      @deleted_keys = []
      @import_from_file = []
      @modified = false

      nil
    end

    # Read the current configuration from the package manager
    # @return [Array] the current configuration, nil when an error occurr
    def ReadCurrentKeys
      # read trusted keys
      ret = Pkg.GPGKeys(true)

      Builtins.y2milestone("Read configuration: %1", ret)

      deep_copy(ret)
    end

    # Read the current configuration from the package manager.
    # The previous changes are lost (@see Reset).
    # The target system of the package manager must be initialized before reading GPG keys!
    # @return [Boolean] true on success
    def Read
      if Ops.greater_than(Builtins.size(@known_keys), 0)
        Builtins.y2warning("Rereading GPG keys from the package manager")
        Reset()
      end

      @known_keys = ReadCurrentKeys()

      if @known_keys.nil?
        @known_keys = []
        return false
      end

      true
    end

    # Search a GPG key in the known keys
    # @param [String] key_id ID of the key
    # @return [Hash] Data about the key or nil if the key was not found
    def SearchGPGKey(key_id)
      ret = nil

      # search the properties of the key
      Builtins.foreach(@known_keys) do |key|
        if Ops.get_string(key, "id", "") == key_id
          ret = deep_copy(key)
          raise Break
        end
      end

      deep_copy(ret)
    end

    # Apply the changes, update the current status
    # @return [Boolean] true on success
    def Write
      if !@modified
        Builtins.y2milestone("No change, nothing to write")
        return true
      end

      Builtins.y2milestone("Writing key management configuration")

      ret = true

      # delete the keys marked for removal
      Builtins.foreach(@deleted_keys) do |deleted_key|
        Builtins.y2milestone(
          "Deleting key %1 ('%2')",
          Ops.get_string(deleted_key, "id", ""),
          Ops.get_string(deleted_key, "name", "")
        )
        ret = Pkg.DeleteGPGKey(
          Ops.get_string(deleted_key, "id", ""),
          Ops.get_boolean(deleted_key, "trusted", false)
        ) && ret
      end

      # import the new keys
      Builtins.foreach(@import_from_file) do |new_key|
        Builtins.y2milestone(
          "Importing key %1 from '%2', trusted: %3",
          Ops.get_string(new_key, "id", ""),
          Ops.get_string(new_key, "file", ""),
          Ops.get_boolean(new_key, "trusted", false)
        )
        ret = Pkg.ImportGPGKey(
          Ops.get_string(new_key, "file", ""),
          Ops.get_boolean(new_key, "trusted", false)
        ) && ret
      end

      # all changes are saved, reset them
      @deleted_keys = []
      @import_from_file = []
      @modified = false

      ret
    end

    # Has been something changed?
    # @return [Boolean] true if something has been changed
    def Modified
      @modified
    end

    # Return the current keys.
    # @return [Array] list of known GPG keys
    #   ($[ "id" : string, "name" : string, "trusted" : boolean ])
    def GetKeys
      deep_copy(@known_keys)
    end

    # Delete the key from the package manager
    # @param [String] key_id ID of the key to delete
    # @return [Boolean] true on success
    def DeleteKey(key_id)
      if key_id.nil? || key_id == ""
        Builtins.y2error("Invalid key ID: %1", key_id)
        return false
      end

      # index of the key
      found = nil
      i = 0

      # copy the key from known keys to the deleted list
      Builtins.foreach(@known_keys) do |key|
        if Ops.get_string(key, "id", "") == key_id
          @deleted_keys = Builtins.add(@deleted_keys, key)
          found = i
        end
        i = Ops.add(i, 1)
      end

      # remove from known keys when found
      @known_keys = Builtins.remove(@known_keys, found) if !found.nil?

      found_in_imported = false

      # remove from imported keys (deleting a key scheduled for import)
      @import_from_file = Builtins.filter(@import_from_file) do |new_key|
        found_key = Ops.get_string(new_key, "id", "") == key_id
        found_in_imported ||= found_key
        found_key
      end

      @modified = true

      !found.nil?
    end

    # Import key from a file
    # @param [String] file path to the file
    # @param [Boolean] trusted true if the key is trusted
    # @return [Hash] map with the key, nil when import fails
    # (invalid key, not existing file, already imported key...)
    def ImportFromFile(file, trusted)
      # check whether the file is valid, copy the file to the tmpdir
      key = Pkg.CheckGPGKeyFile(file)
      Builtins.y2milestone("File content: %1", key)

      if !key.nil? && Ops.greater_than(Builtins.size(key), 0)
        # update the trusted flag
        Ops.set(key, "trusted", trusted)
      else
        Report.Error(
          Builtins.sformat(
            _("File '%1'\ndoes not contain a valid GPG key.\n"),
            file
          )
        )
        return nil
      end

      known = false

      # check whether the key is already known
      Builtins.foreach(@known_keys) do |k|
        if Ops.get_string(k, "id", "") == Ops.get_string(key, "id", "")
          known = true
        end
      end

      if known
        # %1 is key ID (e.g. A84EDAE89C800ACA), %2 is key name
        # (e.g. "SuSE Package Signing Key <build@suse.de>")
        Report.Error(
          Builtins.sformat(
            _(
              "Key '%1'\n" \
                "'%2'\n" \
                "is already known, it cannot be added again."
            ),
            Ops.get_string(key, "id", ""),
            Ops.get_string(key, "name", "")
          )
        )
        return nil
      end

      found_in_deleted = false
      # check if the key is scheduled for removal
      @deleted_keys = Builtins.filter(@deleted_keys) do |deleted_key|
        key_found = Ops.get_string(deleted_key, "id", "") ==
          Ops.get_string(key, "id", "")
        found_in_deleted ||= key_found
        !key_found
      end

      # the key was known, move it to the known list
      if found_in_deleted
        @known_keys = Builtins.add(@known_keys, key)
        return deep_copy(key)
      end

      # copy the key to the temporary directory (in fact the keys are imported in Write())
      tmpfile = Builtins.sformat(
        "%1/tmp_gpg_key.%2",
        Directory.tmpdir,
        Builtins.size(@known_keys)
      )
      command = Builtins.sformat(
        "/bin/cp -- '%1' '%2'",
        String.Quote(file),
        String.Quote(tmpfile)
      )

      Builtins.y2milestone("Copying the key: %1", command)

      out = Convert.to_integer(SCR.Execute(path(".target.bash"), command))

      if out.nonzero?
        Report.Error(_("Cannot copy the key to the temporary directory."))
        return nil
      end

      # store the import request
      @import_from_file = Builtins.add(
        @import_from_file,
        "file"    => tmpfile,
        "trusted" => trusted,
        "id"      => Ops.get_string(key, "id", "")
      )

      # add the new key to the current config
      @known_keys = Builtins.add(@known_keys, key)

      @modified = true

      deep_copy(key)
    end

    publish function: :Reset, type: "void ()"
    publish function: :Read, type: "boolean ()"
    publish function: :SearchGPGKey, type: "map <string, any> (string)"
    publish function: :Write, type: "boolean ()"
    publish function: :Modified, type: "boolean ()"
    publish function: :GetKeys, type: "list <map <string, any>> ()"
    publish function: :DeleteKey, type: "boolean (string)"
    publish function: :ImportFromFile, type: "map <string, any> (string, boolean)"
  end

  KeyManager = KeyManagerClass.new
  KeyManager.main
end
