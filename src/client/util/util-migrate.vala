/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
n */

namespace Util.Migrate {
    private const string GROUP = "AccountInformation";
    private const string PRIMARY_EMAIL_KEY = "primary_email";
    private const string SETTINGS_FILENAME = Accounts.Manager.SETTINGS_FILENAME;
    private const string MIGRATED_FILENAME = ".config_migrated";

    /**
     * Migrates geary.ini to the XDG configuration directory with the account's email address
     *
     * This function iterates through all the account directories in $XDG_DATA_DIR and copies over
     * geary.ini to ~/.config/geary/<account>/geary.ini. Note that it leaves the
     * original file untouched.
     * It also appends a "primary_email" key to the new configuration file to reliaby keep
     * track of the user's email address.
     */
    public static void xdg_config_dir(GLib.File user_config_dir,
                                      GLib.File user_data_dir)
        throws GLib.Error {
        File new_config_dir;
        File old_data_dir;
        File new_config_file;
        File old_config_file;

        // Return if Geary has never been run (~/.local/share/geary does not exist).
        if (!user_data_dir.query_exists())
            return;

        FileEnumerator enumerator;
        enumerator = user_data_dir.enumerate_children ("standard::*",
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);

        FileInfo? info;
        string email;
        File is_migrated;
        while ((info = enumerator.next_file(null)) != null) {
            if (info.get_file_type() != FileType.DIRECTORY)
                continue;

            email = info.get_name();

            // Skip the directory if its name is not a valid email address.
            if (!Geary.RFC822.MailboxAddress.is_valid_address(email))
                continue;

            old_data_dir = user_data_dir.get_child(email);
            new_config_dir = user_config_dir.get_child(email);

            // Skip the directory if ~/.local/share/geary/<account>/geary.ini does not exist.
            old_config_file = old_data_dir.get_child(SETTINGS_FILENAME);
            if (!old_config_file.query_exists())
                continue;

            // Skip the directory if ~/.local/share/geary/<account>/.config_migrated exists.
            is_migrated = old_data_dir.get_child(MIGRATED_FILENAME);
            if (is_migrated.query_exists())
                continue;

            if (!new_config_dir.query_exists()) {
                try {
                    new_config_dir.make_directory_with_parents();
                } catch (Error e) {
                    debug("Cannot make directory, %s", e.message);
                    continue;
                }
            }

            new_config_file = new_config_dir.get_child(SETTINGS_FILENAME);
            if (new_config_file.query_exists())
                continue;

            try {
                old_config_file.copy(new_config_file, FileCopyFlags.NONE);
            } catch (Error err) {
                debug("Error copying over to %s", new_config_dir.get_path());
                continue;
            }
            KeyFile key_file = new KeyFile();
            try {
                key_file.load_from_file(new_config_file.get_path(), KeyFileFlags.NONE);
            } catch (Error err) {
                debug("Error opening %s", new_config_file.get_path());
                continue;
            }

            // Write the primary email key in the new config file.
            key_file.set_value(GROUP, PRIMARY_EMAIL_KEY, email);
            string data = key_file.to_data();
            try {
                new_config_file.replace_contents(data.data, null, false, FileCreateFlags.NONE,
                null);
            } catch (Error e) {
                debug("Error writing email %s to config file", email);
                continue;
            }
            is_migrated.create(FileCreateFlags.PRIVATE);
        }
    }

    /**
     * Migrates configuration from release build locations.
     *
     * This will migrate configuration from release build locations to
     * the current config directory, if and only if the current config
     * directory is empty. For example, from the standard
     * distro-package config location to the current Flatpak location,
     * or from either to a development config location.
     */
    public static void release_config(GLib.File[] search_path,
                                      GLib.File config_dir)
        throws GLib.Error {
        if (is_directory_empty(config_dir)) {
            GLib.File? most_recent = null;
            GLib.DateTime most_recent_modified = null;
            foreach (var source in search_path) {
                if (!source.equal(config_dir)) {
                    GLib.DateTime? src_modified = null;
                    try {
                        GLib.FileInfo? src_info = source.query_info(
                            GLib.FileAttribute.TIME_MODIFIED, 0
                        );
                        if (src_info != null) {
                            src_modified =
                                src_info.get_modification_date_time();
                        }
                    } catch (GLib.IOError.NOT_FOUND err) {
                        // fine
                    } catch (GLib.Error err) {
                        debug(
                            "Error querying release config dir %s: %s",
                            source.get_path(),
                            err.message
                        );
                    }
                    if (most_recent_modified == null ||
                        (src_modified != null &&
                         most_recent_modified.compare(src_modified) < 0)) {
                        most_recent = source;
                        most_recent_modified = src_modified;
                    }
                }
            }

            if (most_recent != null) {
                try {
                    debug(
                        "Migrating release config from %s to %s",
                        most_recent.get_path(),
                        config_dir.get_path()
                    );
                    recursive_copy(most_recent, config_dir);
                } catch (GLib.Error err) {
                    debug("Error migrating release config: %s", err.message);
                }
            }
        }
    }

    private bool is_directory_empty(GLib.File dir) {
        bool is_empty = true;
        GLib.FileEnumerator? existing = null;
        try {
            existing = dir.enumerate_children(
                GLib.FileAttribute.STANDARD_TYPE, 0
            );
        } catch (GLib.IOError.NOT_FOUND err) {
            // fine
        } catch (GLib.Error err) {
            debug(
                "Error enumerating directory %s: %s",
                dir.get_path(),
                err.message
            );
        }

        if (existing != null) {
            try {
                is_empty = existing.next_file() == null;
            } catch (GLib.Error err) {
                debug(
                    "Error getting next child in directory %s: %s",
                    dir.get_path(),
                    err.message
                );
            }

            try {
                existing.close();
            } catch (GLib.Error err) {
                debug(
                    "Error closing directory enumeration %s: %s",
                    dir.get_path(),
                    err.message
                );
            }
        }

        return is_empty;
    }

    private static void recursive_copy(GLib.File src,
                                       GLib.File dest,
                                       GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        switch (src.query_file_type(NONE, cancellable)) {
        case DIRECTORY:
            try {
                dest.make_directory(cancellable);
            } catch (GLib.IOError.EXISTS err) {
                // fine
            }
            src.copy_attributes(dest, NONE, cancellable);

            GLib.FileEnumerator children = src.enumerate_children(
                GLib.FileAttribute.STANDARD_NAME,
                NONE,
                cancellable
            );
            GLib.FileInfo? child = children.next_file(cancellable);
            while (child != null) {
                recursive_copy(
                    src.get_child(child.get_name()),
                    dest.get_child(child.get_name())
                );
                child = children.next_file(cancellable);
            }
            break;

        case REGULAR:
            src.copy(dest, NONE, cancellable);
            break;

        default:
            // no-op
            break;
        }
    }

    public const string OLD_APP_ID = "org.yorba.geary";
    private const string MIGRATED_CONFIG_KEY = "migrated-config";

    public static void old_app_config(Settings newSettings, string old_app_id = OLD_APP_ID) {
        SettingsSchemaSource schemaSource = SettingsSchemaSource.get_default();
        if (Application.Client.GSETTINGS_DIR != null) {
            try {
                schemaSource = new SettingsSchemaSource.from_directory(Application.Client.GSETTINGS_DIR, null, false);
            } catch (Error e) {
                // If it didn't work, do nothing (i.e. use the default GSettings dir)
            }
        }
        SettingsSchema oldSettingsSchema = schemaSource.lookup(old_app_id, false);

        if (newSettings.get_boolean(MIGRATED_CONFIG_KEY))
            return;

        if (oldSettingsSchema != null) {
            Settings oldSettings = new Settings.full(oldSettingsSchema, null, null);
            foreach (string key in newSettings.settings_schema.list_keys()) {
                if (oldSettingsSchema.has_key(key)) {
                    newSettings.set_value(key, oldSettings.get_value(key));
                }
            }
        }

        newSettings.set_boolean(MIGRATED_CONFIG_KEY, true);
    }


}
