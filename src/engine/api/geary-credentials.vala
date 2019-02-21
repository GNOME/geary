/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Credentials provide a user's access details for authentication.
 *
 * The {@link user} property specifies the user's log in name, and the
 * {@link token} property is a shared secret between the user and a
 * service. For password-based schemes, this would be a password.

 * The token property may be null. This indicates the Credentials are
 * incomplete and need further information (i.e. prompt user for
 * username, fetch password from keyring, etc.). The token may be a
 * non-null zero-length string; this is considered valid and
 * is_complete() will return true in this case.
 *
 * Note that Geary will hold Credentials in memory for the long-term,
 * usually the duration of the application.  This is because network
 * resources often have to be connected (or reconnected) to in the
 * background and asking the user to reauthenticate each time is
 * deemed inconvenient.
 */
public class Geary.Credentials : BaseObject, Gee.Hashable<Geary.Credentials> {


    /**
     * Authentication methods supported by the Engine.
     */
    public enum Method {

        /** Password-based authentication, such as SASL PLAIN. */
        PASSWORD,

        /** OAuth2-based authentication. */
        OAUTH2;


        public string to_string() {
            switch (this) {
            case PASSWORD:
                return "password";

            case OAUTH2:
                return "oauth2";

            default:
                assert_not_reached();
            }
        }

        public static Method from_string(string str) throws Error {
            switch (str) {
            case "password":
                return PASSWORD;

            case "oauth2":
                return OAUTH2;

            default:
                throw new KeyFileError.INVALID_VALUE(
                    "Unknown credentials method type: %s", str
                );
            }
        }
    }


    /** The requirements for a service's credentials. */
    public enum Requirement {
        /** No credentials are required. */
        NONE,

        /** The incoming service's credentials should be used. */
        USE_INCOMING,

        /** Custom credentials are required. */
        CUSTOM;

        public static Requirement for_value(string value)
            throws EngineError {
            return ObjectUtils.from_enum_nick<Requirement>(
                typeof(Requirement), value.ascii_down()
            );
        }

        public string to_value() {
            return ObjectUtils.to_enum_nick<Requirement>(
                typeof(Requirement), this
            );
        }

    }


    public Method supported_method { get; private set; }
    public string user { get; private set; }
    public string? token { get; private set; }

    public Credentials(Method supported_method, string user, string? token = null) {
        this.supported_method = supported_method;
        this.user = user;
        this.token = token;
    }

    /** Determines if a token has been provided. */
    public bool is_complete() {
        return this.token != null;
    }

    public Credentials copy_with_user(string user) {
        return new Credentials(this.supported_method, user, this.token);
    }

    public Credentials copy_with_token(string? token) {
        return new Credentials(this.supported_method, this.user, token);
    }

    public Credentials copy() {
        return new Credentials(this.supported_method, this.user, this.token);
    }

    public string to_string() {
        return "%s:%s".printf(this.user, this.supported_method.to_string());
    }

    public bool equal_to(Geary.Credentials c) {
        if (this == c)
            return true;

        return (
            this.supported_method == c.supported_method &&
            this.user == c.user &&
            this.token == c.token
        );
    }

    public uint hash() {
        return "%d%s%s".printf(
            this.supported_method, this.user, this.token ?? ""
        ).hash();
    }
}
