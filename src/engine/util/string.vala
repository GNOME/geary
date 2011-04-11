/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public inline bool is_empty_string(string? str) {
    return (str == null || str[0] == 0);
}

