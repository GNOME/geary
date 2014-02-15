/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Time {

/**
 * Converts a DateTime object into the nearest approximation of time_t.
 *
 * Since DateTime can store down to the microsecond and dates before UNIX epoch, there's some
 * truncating going on here.
 */
public time_t datetime_to_time_t(DateTime datetime) {
    GLib.Time tm = GLib.Time();
    tm.second = datetime.get_second();
    tm.minute = datetime.get_minute();
    tm.hour = datetime.get_hour();
    tm.day = datetime.get_day_of_month();
    // month is 1-based in DateTime
    tm.month = Numeric.int_floor(datetime.get_month() - 1, 0);
    // Time's year is number of years after 1900
    tm.year = Numeric.int_floor(datetime.get_year() - 1900, 0);
    tm.isdst = datetime.is_daylight_savings() ? 1 : 0;
    
    return tm.mktime();
}

}
