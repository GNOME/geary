/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.Outbox.FolderProperties : Geary.FolderProperties {

    public FolderProperties(int total, int unread) {
        base(
            total, unread,
            Trillian.FALSE, Trillian.FALSE, Trillian.TRUE,
            true, false, false
        );
    }

    public void set_total(int total) {
        this.email_total = total;
    }

}
