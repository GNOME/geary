/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Describes a error that the engine encountered, for reporting to the client.
 */
public class Geary.ProblemReport : Object {


    /** The exception caused the problem, if any. */
    public ErrorContext? error { get; private set; default = null; }

    /** The oldest log record when the report was first created. */
    public Logging.Record? earliest_log { get; private set; default = null; }

    /** The newest log record when the report was first created. */
    public Logging.Record? latest_log { get; private set; default = null; }


    public ProblemReport(GLib.Error? error) {
        if (error != null) {
            this.error = new ErrorContext(error);
        }
        Logging.Record next_original = Logging.get_earliest_record();
        Logging.Record last_original = Logging.get_latest_record();
        if (next_original != null) {
            Logging.Record copy = this.earliest_log = new Logging.Record.copy(
                next_original
            );
            next_original = next_original.next;
            while (next_original != null &&
                   next_original != last_original) {
                copy.next = new Logging.Record.copy(next_original);
                copy = copy.next;
                next_original = next_original.next;
            }
            this.latest_log = copy;
        }
    }

    ~ProblemReport() {
        // Manually clear each log record in a loop if we have the
        // only reference to it so that finalisation of each is an
        // iterative process. If we just nulled out the record,
        // finalising the first would cause second to be finalised,
        // which would finalise the third, etc., and the recursion
        // could cause the stack to blow right out for large log
        // buffers.
        Logging.Record? earliest = this.earliest_log;
        this.earliest_log = null;
        this.latest_log = null;
        while (earliest != null) {
            earliest = earliest.next;
        }
    }

    /** Returns a string representation of the report, for debugging only. */
    public string to_string() {
        return "%s".printf(
            this.error != null
                ? this.error.format_full_error()
                : "no error reported"
        );
    }

}

/**
 * Describes an account-related error that the engine encountered.
 */
public class Geary.AccountProblemReport : ProblemReport {


    /** The account related to the problem report. */
    public AccountInformation account { get; private set; }


    public AccountProblemReport(AccountInformation account, Error? error) {
        base(error);
        this.account = account;
    }

    /** Returns a string representation of the report, for debugging only. */
    public new string to_string() {
        return "%s: %s".printf(this.account.id, base.to_string());
    }

}

/**
 * Describes a service-related error that the engine encountered.
 */
public class Geary.ServiceProblemReport : AccountProblemReport {


    /** The service related to the problem report. */
    public ServiceInformation service { get; private set; }


    public ServiceProblemReport(AccountInformation account,
                                ServiceInformation service,
                                Error? error) {
        base(account, error);
        this.service = service;
    }

    /** Returns a string representation of the report, for debugging only. */
    public new string to_string() {
        return "%s: %s: %s".printf(
            this.account.id,
            this.service.protocol.to_string(),
            this.error != null
                ? this.error.format_full_error()
                : "no error reported"
        );
    }

}
