/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Util.Date {

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

public enum CoarseDate {
    NOW,
    MINUTES,
    HOURS,
    TODAY,
    YESTERDAY,
    THIS_WEEK,
    THIS_YEAR,
    YEARS,
    FUTURE;
}

private int init_count = 0;
private string[]? xlat_pretty_clocks = null;
private string[]? xlat_pretty_verbose_dates = null;
private string? xlat_same_year = null;
/// Date format for dates within a different year, i.e. 02/04/10
private const string xlat_diff_year = "%x";

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

    xlat_pretty_clocks = new string[ClockFormat.TOTAL];
    /// Datetime format for 12-hour time, i.e. 8:31 am
    /// See https://docs.gtk.org/glib/method.DateTime.format.html
    // xgettext: no-c-format
    xlat_pretty_clocks[ClockFormat.TWELVE_HOURS] = _("%l:%M %P");
    /// Datetime format for 24-hour time, i.e. 16:35
    /// See https://docs.gtk.org/glib/method.DateTime.format.html
    // xgettext: no-c-format
    xlat_pretty_clocks[ClockFormat.TWENTY_FOUR_HOURS] = _("%H:%M");
    /// Datetime format for the locale default, i.e. 8:31 am or 16:35,
    /// See https://docs.gtk.org/glib/method.DateTime.format.html
    xlat_pretty_clocks[ClockFormat.LOCALE_DEFAULT] = "%X";

    /// Date format for dates within the current year, i.e. Nov 8
    /// See https://docs.gtk.org/glib/method.DateTime.format.html
    // xgettext: no-c-format
    xlat_same_year = _("%b %-e");

    xlat_pretty_verbose_dates = new string[ClockFormat.TOTAL];
    /// Verbose datetime format for 12-hour time, i.e. November 8, 2010 8:42 am
    /// See https://docs.gtk.org/glib/method.DateTime.format.html
    // xgettext: no-c-format
    xlat_pretty_verbose_dates[ClockFormat.TWELVE_HOURS] = _("%B %-e, %Y %-l:%M %P");
    /// Verbose datetime format for 24-hour time, i.e. November 8, 2010 16:35
    /// See https://docs.gtk.org/glib/method.DateTime.format.html
    // xgettext: no-c-format
    xlat_pretty_verbose_dates[ClockFormat.TWENTY_FOUR_HOURS] = _("%B %-e, %Y %-H:%M");
    /// Verbose datetime format for the locale default (full month, day and time)
    /// See https://docs.gtk.org/glib/method.DateTime.format.html
    // xgettext: no-c-format
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

    xlat_pretty_clocks = null;
    xlat_same_year = null;
    xlat_pretty_verbose_dates = null;
}

private bool same_day(DateTime a, DateTime b) {
    int year1, month1, day1;
    a.get_ymd(out year1, out month1, out day1);

    int year2, month2, day2;
    b.get_ymd(out year2, out month2, out day2);

    return year1 == year2 && month1 == month2 && day1 == day2;
}

// Computes the CoarseDate corresponding to the given datetime
// The CoarseDate is a rough description of the date, to be used by the pretty printer
public CoarseDate as_coarse_date(DateTime datetime, DateTime now, TimeSpan diff) {
    if (same_day(datetime, now)) {
        if (diff < TimeSpan.MINUTE) {
            return CoarseDate.NOW;
        }
        if (diff < TimeSpan.HOUR) {
            return CoarseDate.MINUTES;
        }
        if (diff < 12 * TimeSpan.HOUR) {
            return CoarseDate.HOURS;
        }
        return CoarseDate.TODAY;
    } else {
        if (datetime.compare(now) > 0) {
            return CoarseDate.FUTURE;
        }
        DateTime temp;
        temp = datetime.add_days(1);
        if (same_day(temp, now)) {
            return CoarseDate.YESTERDAY;
        }
        temp = datetime.add_days(6);
        if (same_day(temp, now) || temp.compare(now) >= 0) {
            return CoarseDate.THIS_WEEK;
        }
        if (datetime.get_year() == now.get_year()) {
            return CoarseDate.THIS_YEAR;
        } else {
            return CoarseDate.YEARS;
        }
    }
}

// Private because it's just a helper method for pretty_print, which is the "public api"
private string pretty_print_coarse(CoarseDate coarse_date, ClockFormat clock_format, DateTime datetime, TimeSpan diff) {
    string fmt;
    switch (coarse_date) {
        case CoarseDate.NOW:
            return _("Now");

        case CoarseDate.MINUTES:
            return ngettext("%dm ago", "%dm ago", (ulong) (diff / TimeSpan.MINUTE)).printf((int) (diff / TimeSpan.MINUTE));

        case CoarseDate.HOURS:
            int rounded = (int) Math.round((double) diff / TimeSpan.HOUR);
            return ngettext("%dh ago", "%dh ago", (ulong) rounded).printf(rounded);

        case CoarseDate.TODAY:
            fmt = get_clock_format(clock_format);
        break;

        case CoarseDate.YESTERDAY:
            return _("Yesterday");

        case CoarseDate.THIS_WEEK:
            /// Date format that shows the weekday (Monday, Tuesday, ...)
            /// See https://docs.gtk.org/glib/method.DateTime.format.html
            // xgettext: no-c-format
            fmt = _("%A");
        break;

        case CoarseDate.THIS_YEAR:
            fmt = xlat_same_year;
        break;

        case CoarseDate.YEARS:
        case CoarseDate.FUTURE:
        default:
            fmt = xlat_diff_year;
        break;
    }

    return datetime.format(fmt);
}

public string pretty_print(DateTime datetime, ClockFormat clock_format) {
    DateTime to_local = datetime.to_local();
    DateTime now = new DateTime.now_local();
    TimeSpan diff = now.difference(to_local);

    return pretty_print_coarse(as_coarse_date(to_local, now, diff), clock_format, to_local, diff);
}

public string pretty_print_verbose(DateTime datetime, ClockFormat clock_format) {
    return datetime.format(xlat_pretty_verbose_dates[clock_format.to_index()]);
}

public string get_clock_format(ClockFormat clock_format) {
    return xlat_pretty_clocks[clock_format.to_index()];
}

}
