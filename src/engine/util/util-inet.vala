/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Inet {

public string address_to_string(InetSocketAddress addr) {
    return "%s:%u".printf(addr.address.to_string(), addr.port);
}

}

