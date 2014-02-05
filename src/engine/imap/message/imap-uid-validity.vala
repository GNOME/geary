/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/*
 * A representation of IMAP's UIDVALIDITY.
 *
 * See [[tools.ietf.org/html/rfc3501#section-2.3.1.1]]
 *
 * @see UID
 */

public class Geary.Imap.UIDValidity : Geary.MessageData.Int64MessageData, Geary.Imap.MessageData {
    // Using statics because int32.MAX is static, not const (??)
    public static int64 MIN = 1;
    public static int64 MAX = int32.MAX;
    public static int64 INVALID = -1;
    
    public UIDValidity(int64 value) {
        base (value);
    }
}

