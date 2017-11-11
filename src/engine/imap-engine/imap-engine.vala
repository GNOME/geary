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

}
