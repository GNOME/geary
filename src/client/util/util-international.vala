/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern const string LANGUAGE_SUPPORT_DIRECTORY;
public const string TRANSLATABLE = "translatable";

namespace International {

public const string SYSTEM_LOCALE = "";

void init(string package_name, string program_path, string locale = SYSTEM_LOCALE) {
    Intl.setlocale(LocaleCategory.ALL, locale);
    Intl.bindtextdomain(package_name, get_langpack_dir_path(program_path));
    Intl.bind_textdomain_codeset(package_name, "UTF-8");
    Intl.textdomain(package_name);
}

// TODO: Geary should be able to use langpacks from the build directory
private string get_langpack_dir_path(string program_path) {
    return LANGUAGE_SUPPORT_DIRECTORY;
}

}

