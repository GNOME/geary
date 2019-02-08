/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.ImapEngine {

    /**
     * Determines if retrying an operation might succeed or not.
     *
     * A recoverable failure is defined as one that may not occur
     * again if the operation that caused it is retried, without
     * needing to make some change in the mean time. For example,
     * recoverable failures may occur due to transient network
     * connectivity issues or server rate limiting. On the other hand,
     * an unrecoverable failure is due to some problem that will not
     * succeed if tried again unless some action is taken, such as
     * authentication failures, protocol parsing errors, and so on.
     */
    private static bool is_recoverable_failure(GLib.Error err) {
        return (
            err is EngineError.SERVER_UNAVAILABLE ||
            err is IOError.BROKEN_PIPE ||
            err is IOError.BUSY ||
            err is IOError.CONNECTION_CLOSED ||
            err is IOError.NOT_CONNECTED ||
            err is IOError.TIMED_OUT ||
            err is ImapError.NOT_CONNECTED ||
            err is ImapError.TIMED_OUT ||
            err is ImapError.UNAVAILABLE
        );
    }

    /**
     * Determines if an error was caused by the remote host or not.
     */
    private static bool is_remote_error(GLib.Error err) {
        return (
            err is EngineError.NOT_FOUND ||
            err is EngineError.SERVER_UNAVAILABLE ||
            err is IOError.CONNECTION_CLOSED ||
            err is IOError.CONNECTION_REFUSED ||
            err is IOError.HOST_UNREACHABLE ||
            err is IOError.MESSAGE_TOO_LARGE ||
            err is IOError.NETWORK_UNREACHABLE ||
            err is IOError.NOT_CONNECTED ||
            err is IOError.PROXY_AUTH_FAILED ||
            err is IOError.PROXY_FAILED ||
            err is IOError.PROXY_NEED_AUTH ||
            err is IOError.PROXY_NOT_ALLOWED ||
            err is ImapError
        );
    }

}
