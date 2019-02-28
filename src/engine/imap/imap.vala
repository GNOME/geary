/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Imap {

private int init_count = 0;

internal void init() {
    if (init_count++ != 0)
        return;

    MessageFlag.init();
    MailboxAttribute.init();
    Tag.init();
}

}
