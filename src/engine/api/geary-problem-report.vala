/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/** Describes available problem types. */
public enum Geary.ProblemType {


    /** Indicates an engine problem not covered by another type. */
    GENERIC_ERROR;

}

/**
 * Describes a error that the engine encountered, for reporting to the client.
 */
public class Geary.ProblemReport : Object {


    /** Describes the type of being reported. */
    public ProblemType problem_type { get; private set; }

    /** The exception caused the problem, if any. */
    public ErrorContext? error { get; private set; default = null; }


    public ProblemReport(ProblemType type, Error? error) {
        this.problem_type = type;
        if (error != null) {
            this.error = new ErrorContext(error);
        }
    }

    /** Returns a string representation of the report, for debugging only. */
    public string to_string() {
        return "%s: %s".printf(
            this.problem_type.to_string(),
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
            this.error != null
                ? this.error.format_full_error()
                : "no error reported"
        );
    }

}
