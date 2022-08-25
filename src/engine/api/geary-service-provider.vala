/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of the various built-in email service providers Geary supports.
 */

public enum Geary.ServiceProvider {
    GMAIL,
    OUTLOOK,
    OTHER;

    public static ServiceProvider for_value(string value)
        throws EngineError {
        return ObjectUtils.from_enum_nick<ServiceProvider>(
            typeof(ServiceProvider), value.ascii_down()
        );
    }

    public string to_value() {
        return ObjectUtils.to_enum_nick<ServiceProvider>(
            typeof(ServiceProvider), this
        );
    }

    public void set_account_defaults(AccountInformation service) {
        switch (this) {
        case GMAIL:
            ImapEngine.GmailAccount.setup_account(service);
            break;
        case OUTLOOK:
            ImapEngine.OutlookAccount.setup_account(service);
            break;
        case OTHER:
            // no-op
            break;
        }
    }

    public void set_service_defaults(ServiceInformation service) {
        switch (this) {
        case GMAIL:
            ImapEngine.GmailAccount.setup_service(service);
            break;
        case OUTLOOK:
            ImapEngine.OutlookAccount.setup_service(service);
            break;
        case OTHER:
            // no-op
            break;
        }
    }

}
