/* Copyright 2011 Yorba Foundation
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

public string pretty_print(DateTime datetime) {
    DateTime now = new DateTime.now_local();
    string fmt;
    if (equals(datetime, now)) {
        // 8:31 am
        fmt = "%l:%M %P";
    } else if (datetime.get_year() == now.get_year()) {
        // Nov 8
        fmt = "%b %-e";
    } else {
        // 02/04/10
        fmt = "%m/%e/%y";
    }
    
    return datetime.format(fmt);
}

public string pretty_print_verbose(DateTime datetime) {
    // November 8, 2010 8:42 am
    return datetime.format("%B %-e, %Y %-l:%M %P");
}

}

