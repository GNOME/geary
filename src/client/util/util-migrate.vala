/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Migrate {
    private const string GROUP = "AccountInformation";
    private const string PRIMARY_EMAIL_KEY = "primary_email";
    private const string SETTINGS_FILENAME = Geary.AccountInformation.SETTINGS_FILENAME;
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
    public static void xdg_config_dir(File user_data_dir, File user_config_dir) throws Error {
        File new_config_dir;
        File old_data_dir;
        File new_config_file;
        File old_config_file;

        // Return if Geary has never been run (~/.local/share/geary does not exist).
        if (!user_data_dir.query_exists())
            return;

        // Create ~/.config/geary
        try {
            user_config_dir.make_directory_with_parents();
        } catch (Error err) {
            // The user may have already created the directory, so don't throw EXISTS.
            if (!(err is IOError.EXISTS))
                throw err;
        }

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
}
