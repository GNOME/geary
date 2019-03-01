/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public enum Geary.Db.SynchronousMode {
    OFF = 0,
    NORMAL = 1,
    FULL = 2;

    public unowned string sql() {
        switch (this) {
            case OFF:
                return "off";

            case NORMAL:
                return "normal";

            case FULL:
            default:
                return "full";
        }
    }

    public static SynchronousMode parse(string str) {
        switch (str.down()) {
            case "off":
                return OFF;

            case "normal":
                return NORMAL;

            case "full":
            default:
                return FULL;
        }
    }
}

