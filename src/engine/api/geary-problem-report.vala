/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/** Describes available problem types. */
public enum Geary.ProblemType {


    /** Indicates an engine problem not covered by one of the other types. */
    GENERIC_ERROR,

    /** Indicates an error opening, using or closing the account database. */
    DATABASE_FAILURE,

    /** Indicates a problem establishing a connection. */
    CONNECTION_ERROR,

    /** Indicates a problem caused by a network operation. */
    NETWORK_ERROR,

    /** Indicates a non-network related server error. */
    SERVER_ERROR,

    /** Indicates credentials supplied for authentication were rejected. */
    LOGIN_FAILED,

    /** Indicates an outgoing message was sent, but not saved. */
    SEND_EMAIL_SAVE_FAILED;


    /** Determines the appropriate problem type for an IOError. */
    public static ProblemType for_ioerror(IOError error) {
        if (error is IOError.CONNECTION_REFUSED ||
            error is IOError.HOST_NOT_FOUND ||
            error is IOError.HOST_UNREACHABLE ||
            error is IOError.NETWORK_UNREACHABLE) {
            return ProblemType.CONNECTION_ERROR;
        }

        if (error is IOError.CONNECTION_CLOSED ||
            error is IOError.NOT_CONNECTED) {
            return ProblemType.NETWORK_ERROR;
        }

        return ProblemType.GENERIC_ERROR;
    }

}

/**
 * Describes a error that the engine encountered, for reporting to the client.
 */
public class Geary.ProblemReport : Object {


    /**
     * Represents an individual stack frame in a call back-trace.
     */
    public class StackFrame {


        /** Name of the function being called. */
        public string name = "unknown";


        internal StackFrame(Unwind.Cursor frame) {
            uint8 proc_name[256];
            int ret = -frame.get_proc_name(proc_name);
			if (ret == Unwind.Error.SUCCESS ||
                ret == Unwind.Error.NOMEM) {
                this.name = (string) proc_name;
            }
        }

        public string to_string() {
            return this.name;
        }

    }


    /** Describes the type of being reported. */
    public ProblemType problem_type { get; private set; }

    /** The exception caused the problem, if any. */
    public Error? error { get; private set; default = null; }

    /** A back trace from when the problem report was constructed. */
    public Gee.List<StackFrame>? backtrace = null;


    public ProblemReport(ProblemType type, Error? error) {
        this.problem_type = type;
        this.error = error;

        if (error != null) {
            // Some kind of exception occurred, so build a trace. This
            // is far from perfect, but at least we will know where it
            // was getting caught.
            this.backtrace = new Gee.LinkedList<StackFrame>();
            Unwind.Context trace = Unwind.Context();
            Unwind.Cursor cursor = Unwind.Cursor.local(trace);

            // This misses the first frame, but that's this
            // constructor call, so we don't really care.
            while (cursor.step() != 0) {
                this.backtrace.add(new StackFrame(cursor));
            }
        }
    }

    /** Returns a string representation of the report, for debugging only. */
    public string to_string() {
        return "%s: %s".printf(
            this.problem_type.to_string(),
            format_full_error() ?? "no error reported"
        );
    }

    /** Returns a string representation of the error type, for debugging. */
    public string? format_error_type() {
        string type = null;
        if (this.error != null) {
            const string QUARK_SUFFIX = "-quark";
            string ugly_domain = this.error.domain.to_string();
            if (ugly_domain.has_suffix(QUARK_SUFFIX)) {
                ugly_domain = ugly_domain.substring(
                    0, ugly_domain.length - QUARK_SUFFIX.length
                );
            }
            StringBuilder nice_domain = new StringBuilder();
            string separator = (ugly_domain.index_of("_") != -1) ? "_" : "-";
            foreach (string part in ugly_domain.split(separator)) {
                if (part.length > 0) {
                    if (part == "io") {
                        nice_domain.append("IO");
                    } else {
                        nice_domain.append(part.up(1));
                        nice_domain.append(part.substring(1));
                    }
                }
            }

            type = "%s %i".printf(nice_domain.str, this.error.code);
        }
        return type;
    }

    /** Returns a string representation of the complete error, for debugging. */
    public string? format_full_error() {
        string error = null;
        if (this.error != null) {
            error = String.is_empty(this.error.message)
                ? "%s: no message specified".printf(format_error_type())
                : "%s: \"%s\"".printf(format_error_type(), this.error.message);
        }
        return error;
    }

}

/**
 * Describes an account-related error that the engine encountered.
 */
public class Geary.AccountProblemReport : ProblemReport {


    /** The account related to the problem report. */
    public AccountInformation account { get; private set; }


    public AccountProblemReport(ProblemType type, AccountInformation account, Error? error) {
        base(type, error);
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


    public ServiceProblemReport(ProblemType type,
                                AccountInformation account,
                                ServiceInformation service,
                                Error? error) {
        base(type, account, error);
        this.service = service;
    }

    /** Returns a string representation of the report, for debugging only. */
    public new string to_string() {
        return "%s: %s: %s: %s".printf(
            this.account.id,
            this.service.protocol.to_string(),
            this.problem_type.to_string(),
            format_full_error() ?? "no error reported"
        );
    }

}
