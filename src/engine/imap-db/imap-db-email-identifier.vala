/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.EmailIdentifier : Geary.EmailIdentifier {
    public EmailIdentifier(int64 message_id, Geary.FolderPath? folder_path) {
        base (message_id, folder_path);
    }
}
