/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Nonblocking.ReportingSemaphore<G> : Geary.Nonblocking.Semaphore {
    public G result { get; private set; }
    public Error? err { get; private set; default = null; }

    private G default_result;

    public ReportingSemaphore(G default_result, Cancellable? cancellable = null) {
        base (cancellable);

        this.default_result = default_result;
        result = default_result;
    }

    public override void reset() {
        result = default_result;
        err = null;

        base.reset();
    }

    public void notify_result(G result, Error? err) throws Error {
        this.result = result;
        this.err = err;

        notify();
    }

    public void throw_if_error() throws Error {
        if (err != null)
            throw err;
    }

    public async G wait_for_result_async(Cancellable? cancellable = null) throws Error {
        // check before waiting
        throw_if_error();

        // wait
        yield base.wait_async(cancellable);

        // if notified of error while waiting, throw that
        throw_if_error();

        return result;
    }
}

