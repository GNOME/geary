/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Date {

public enum ClockFormat {
    TWELVE_HOURS,
    TWENTY_FOUR_HOURS,
    LOCALE_DEFAULT,
    
    TOTAL;
    
    internal int to_index() {
        // clamp to array boundaries
        return ((int) this).clamp(0, ClockFormat.TOTAL - 1);
    }
}

private int init_count = 0;
private string[]? xlat_pretty_dates = null;
private string[]? xlat_pretty_verbose_dates = null;
private string? xlat_same_year = null;
private string? xlat_diff_year = null;

// Must be called before any threads are started
public void init() {
    if (init_count++ != 0)
        return;
    
    // Ripped from Shotwell proposed patch for localizing time (http://redmine.yorba.org/issues/2462)
    // courtesy Marcel Stimberg.  Another example may be found here:
    // http://bazaar.launchpad.net/~indicator-applet-developers/indicator-datetime/trunk.12.10/view/head:/src/utils.c
    
    // Because setlocale() is a process-wide setting, need to cache strings at startup, otherwise
    // risk problems with threading
    
    string? messages_locale = Intl.setlocale(LocaleCategory.MESSAGES, null);
    string? time_locale = Intl.setlocale(LocaleCategory.TIME, null);
    
    // LANGUAGE must be unset before changing locales, as it trumps all the LC_* variables
    string? language_env = Environment.get_variable("LANGUAGE");
    if (language_env != null)
        Environment.unset_variable("LANGUAGE");
    
    // Swap LC_TIME's setting into LC_MESSAGE's.  This allows performinglookups of time-based values
    // from a different translation file, useful in mixed-locale settings
    if (time_locale != null)
        Intl.setlocale(LocaleCategory.MESSAGES, time_locale);
    
    xlat_pretty_dates = new string[ClockFormat.TOTAL];
    /// Datetime format for 12-hour time, i.e. 8:31 am
    /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
    xlat_pretty_dates[ClockFormat.TWELVE_HOURS] = _("%l:%M %P");
    /// Datetime format for 24-hour time, i.e. 16:35
    /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
    xlat_pretty_dates[ClockFormat.TWENTY_FOUR_HOURS] = _("%H:%M");
    /// Datetime format for the locale default, i.e. 8:31 am or 16:35,
    /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
    xlat_pretty_dates[ClockFormat.LOCALE_DEFAULT] = C_("Default clock format", "%l:%M %P");
    
    /// Date format for dates within the current year, i.e. Nov 8
    /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
    xlat_same_year = _("%b %-e");
    
    /// Date format for dates within a different year, i.e. 02/04/10
    /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
    /* xgettext:no-c-format */
    xlat_diff_year = _("%x");
    
    xlat_pretty_verbose_dates = new string[ClockFormat.TOTAL];
    /// Verbose datetime format for 12-hour time, i.e. November 8, 2010 8:42 am
    /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
    xlat_pretty_verbose_dates[ClockFormat.TWELVE_HOURS] = _("%B %-e, %Y %-l:%M %P");
    /// Verbose datetime format for 24-hour time, i.e. November 8, 2010 16:35
    /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
    xlat_pretty_verbose_dates[ClockFormat.TWENTY_FOUR_HOURS] = _("%B %-e, %Y %-H:%M");
    /// Verbose datetime format for the locale default (full month, day and time)
    /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
    xlat_pretty_verbose_dates[ClockFormat.LOCALE_DEFAULT] = C_("Default full date", "%B %-e, %Y %-l:%M %P");
    
    // return LC_MESSAGES back to proper locale and return LANGUAGE environment variable
    if (messages_locale != null)
        Intl.setlocale(LocaleCategory.MESSAGES, messages_locale);
    if (language_env != null)
        Environment.set_variable("LANGUAGE", language_env, true);
}

// Must be called before exiting, after all threads have closed or gone idle
private void terminate() {
    if (--init_count != 0)
        return;
    
    xlat_pretty_dates = null;
    xlat_same_year = null;
    xlat_diff_year = null;
    xlat_pretty_verbose_dates = null;
}

private bool same_day(DateTime a, DateTime b) {
    int year1, month1, day1;
    a.get_ymd(out year1, out month1, out day1);
    
    int year2, month2, day2;
    b.get_ymd(out year2, out month2, out day2);
    
    return year1 == year2 && month1 == month2 && day1 == day2;
}

public string pretty_print(DateTime datetime, ClockFormat clock_format) {
    DateTime now = new DateTime.now_local();
    
    string fmt;
    if (same_day(datetime, now))
        fmt = xlat_pretty_dates[clock_format.to_index()];
    else if (datetime.get_year() == now.get_year())
        fmt = xlat_same_year;
    else
        fmt = xlat_diff_year;
    
    return datetime.format(fmt);
}

public string pretty_print_verbose(DateTime datetime, ClockFormat clock_format) {
    return datetime.format(xlat_pretty_verbose_dates[clock_format.to_index()]);
}

}

