/* Copyright 2009-2012 Yorba Foundation
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

private string get_langpack_dir_path(string program_path) {
    File local_langpack_dir =
        File.new_for_path(Environment.find_program_in_path(program_path)).get_parent().get_child("locale");
    
    return (local_langpack_dir.query_exists(null)) ? local_langpack_dir.get_path() :
        LANGUAGE_SUPPORT_DIRECTORY;
}

}

