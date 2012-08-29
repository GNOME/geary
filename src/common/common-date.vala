/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Date {

public bool equals(DateTime a, DateTime b) {
    int year1, month1, day1;
    a.get_ymd(out year1, out month1, out day1);
    
    int year2, month2, day2;
    b.get_ymd(out year2, out month2, out day2);
    
    return year1 == year2 && month1 == month2 && day1 == day2;
}

public enum ClockFormat {
    TWELVE_HOURS,
    TWENTY_FOUR_HOURS,
    LOCALE_DEFAULT,
}

public string pretty_print(DateTime datetime, ClockFormat clock_format) {
    DateTime now = new DateTime.now_local();
    string fmt;
    if (equals(datetime, now)) {
        if (clock_format == ClockFormat.TWELVE_HOURS) {
            /// Datetime format for 12-hour time, i.e. 8:31 am
            /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
            fmt = _("%l:%M %P");
        } else if (clock_format == ClockFormat.TWENTY_FOUR_HOURS) {
            /// Datetime format for 24-hour time, i.e. 16:35
            /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
            fmt = _("%H:%M");
        } else {
            /// Datetime format for the locale default, i.e. 8:31 am or 16:35,
            /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
            fmt = C_("Default clock format", "%l:%M %P");
        }
    } else if (datetime.get_year() == now.get_year()) {
        /// Date format for dates within the current year, i.e. Nov 8
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        fmt = _("%b %-e");
    } else {
        /// Date format for dates within a different year, i.e. 02/04/10
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        /* xgettext:no-c-format */
        fmt = _("%x");
    }
    
    return datetime.format(fmt);
}

public string pretty_print_verbose(DateTime datetime, ClockFormat clock_format) {
    if (clock_format == ClockFormat.TWELVE_HOURS) {
        /// Verbose datetime format for 12-hour time, i.e. November 8, 2010 8:42 am
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        return datetime.format(_("%B %-e, %Y %-l:%M %P"));
    } else if (clock_format == ClockFormat.TWENTY_FOUR_HOURS) {
        /// Verbose datetime format for 24-hour time, i.e. November 8, 2010 16:35
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        return datetime.format(_("%B %-e, %Y %-H:%M"));
    } else {
        /// Verbose datetime format for the locale default (full month, day and time)
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        return datetime.format(C_("Default full date", "%B %-e, %Y %-l:%M %P"));
    }
}

}

