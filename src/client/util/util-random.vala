/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private string random_string(int length) {
    // No upper case letters, since request gets lower-cased.
    string chars = "abcdefghijklmnopqrstuvwxyz";
    char[] random = new char[length];
    for (int i = 0; i < length; i++)
        random[i] = chars[Random.int_range(0, chars.length)];
    return (string) random;
}

