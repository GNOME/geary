/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Files {

public const int64 KILOBYTE = 1024;
public const int64 MEGABYTE = KILOBYTE * 1024;
public const int64 GIGABYTE = MEGABYTE * 1024;
public const int64 TERABYTE = GIGABYTE * 1024;

public string get_filesize_as_string(int64 filesize) {
    int64 scale = 1;
    string units = _("bytes");
    if (filesize > TERABYTE) {
        scale = TERABYTE;
        units = C_("Abbreviation for terabyte", "TB");
    } else if (filesize > GIGABYTE) {
        scale = GIGABYTE;
        units = C_("Abbreviation for gigabyte", "GB");
    } else if (filesize > MEGABYTE) {
        scale = MEGABYTE;
        units = C_("Abbreviation for megabyte", "MB");
    } else if (filesize > KILOBYTE) {
        scale = KILOBYTE;
        units = C_("Abbreviation for kilobyte", "KB");
    }

    if (scale == 1) {
        return "%s %s".printf(filesize.to_string(), units);
    } else {
        return "%.2f %s".printf((float) filesize / (float) scale, units);
    }
}

}

