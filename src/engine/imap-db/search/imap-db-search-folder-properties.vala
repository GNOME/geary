/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.SearchFolderProperties : Geary.FolderProperties {
    public SearchFolderProperties(int total, int unread) {
        base(total, unread, Trillian.FALSE, Trillian.FALSE, Trillian.TRUE, true, true, false);
    }
    
    public void set_total(int total) {
        this.email_total = total;
    }
}

