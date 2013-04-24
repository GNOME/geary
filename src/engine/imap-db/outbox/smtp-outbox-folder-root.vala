/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.SmtpOutboxFolderRoot : Geary.FolderRoot {
    public const string MAGIC_BASENAME = "$GearyOutbox$";
    
    public SmtpOutboxFolderRoot() {
        base(MAGIC_BASENAME, null, false);
    }
}

