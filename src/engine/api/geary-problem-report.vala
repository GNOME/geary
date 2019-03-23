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


    public ProblemReport(Error? error) {
        if (error != null) {
            this.error = new ErrorContext(error);
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
