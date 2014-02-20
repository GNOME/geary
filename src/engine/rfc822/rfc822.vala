/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.RFC822 {

private int init_count = 0;

internal void init() {
    if (init_count++ != 0)
        return;
    
    GMime.init(GMime.ENABLE_RFC2047_WORKAROUNDS);
}

}
