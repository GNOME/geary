/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.ImapEngine {

/**
 * A hard failure is defined as one due to hardware or connectivity issues, where a soft failure
 * is due to software reasons, like credential failure or protocol violation.
 */
private static bool is_hard_failure(Error err) {
    // CANCELLED is not a hard error
    if (err is IOError.CANCELLED)
        return false;

    // Treat other errors -- most likely IOErrors -- as hard failures
    if (!(err is ImapError) && !(err is EngineError))
        return true;

    return err is ImapError.NOT_CONNECTED
        || err is ImapError.TIMED_OUT
        || err is ImapError.SERVER_ERROR
        || err is EngineError.SERVER_UNAVAILABLE;
}

/**
 * Determines if this IOError related to a remote host or not.
 */
private static bool is_remote_error(GLib.Error err) {
    return err is ImapError
        || err is IOError.CONNECTION_CLOSED
        || err is IOError.CONNECTION_REFUSED
        || err is IOError.HOST_UNREACHABLE
        || err is IOError.MESSAGE_TOO_LARGE
        || err is IOError.NETWORK_UNREACHABLE
        || err is IOError.NOT_CONNECTED
        || err is IOError.PROXY_AUTH_FAILED
        || err is IOError.PROXY_FAILED
        || err is IOError.PROXY_NEED_AUTH
        || err is IOError.PROXY_NOT_ALLOWED;
}

}
