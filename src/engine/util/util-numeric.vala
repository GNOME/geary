/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.Numeric {

public inline int int_floor(int value, int floor) {
    return (value >= floor) ? value : floor;
}

public inline int64 int64_floor(int64 value, int64 floor) {
    return (value >= floor) ? value : floor;
}

public inline int int_ceiling(int value, int ceiling) {
    return (value <= ceiling) ? value : ceiling;
}

public inline int64 int64_ceiling(int64 value, int64 ceiling) {
    return (value <= ceiling) ? value : ceiling;
}

public inline uint uint_ceiling(uint value, uint ceiling) {
    return (value <= ceiling) ? value : ceiling;
}

public inline bool int_in_range_inclusive(int value, int min, int max) {
    return (value >= min) && (value <= max);
}

public inline bool int64_in_range_inclusive(int64 value, int64 min, int64 max) {
    return (value >= min) && (value <= max);
}

public inline bool int_in_range_exclusive(int value, int min, int max) {
    return (value > min) && (value < max);
}

public inline bool int64_in_range_exclusive(int64 value, int64 min, int64 max) {
    return (value > min) && (value < max);
}

}

