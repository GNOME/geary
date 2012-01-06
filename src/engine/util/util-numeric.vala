/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.Numeric {

public inline int int_floor(int value, int floor) {
    return (value >= floor) ? value : floor;
}

public inline int int_ceiling(int value, int ceiling) {
    return (value <= ceiling) ? value : ceiling;
}

}

