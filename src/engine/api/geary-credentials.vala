/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Credentials represent a username and a password authenticating a user for access to a resource.
 * More sophisticated schemes exist; this suffices for now.
 *
 * Either property (user, pass) may be null.  This indicates the Credentials are incomplete and
 * need further information (i.e. prompt user for username, fetch password from keyring, etc.)
 * Either field may be a non-null zero-length string; this is considered valid and is_complete()
 * will return true in this case.
 *
 * Note that Geary will hold Credentials in memory for the long-term, usually the duration of the
 * application.  This is because network resources often have to be connected (or reconnected) to
 * in the background and asking the user to reauthenticate each time is deemed inconvenient.
 */

public class Geary.Credentials : BaseObject, Gee.Hashable<Geary.Credentials> {


    /**
     * Authentication methods supported by the Engine.
     */
    public enum Method {
        /** Password-based authentication, such as SASL PLAIN. */
        PASSWORD;

        public string to_string() {
            switch (this) {
            case PASSWORD:
                return "password";

            default:
                assert_not_reached();
            }
        }

        public static Method from_string(string str) throws Error {
            switch (str) {
            case "password":
                return PASSWORD;

            default:
                throw new KeyFileError.INVALID_VALUE(
                    "Unknown credentials method type: %s", str
                );
            }
        }
    }


    public Method supported_method { get; private set; }
    public string user { get; private set; }
    public string? pass { get; private set; }

    public Credentials(Method supported_method, string user, string? pass = null) {
        this.supported_method = supported_method;
        this.user = user;
        this.pass = pass;
    }

    public bool is_complete() {
        return (this.user != null) && (this.pass != null);
    }

    public Credentials copy_with_password(string? password) {
        return new Credentials(this.supported_method, this.user, password);
    }

    public Credentials copy() {
        return new Credentials(this.supported_method, this.user, this.pass);
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
            this.pass == c.pass
        );
    }

    public uint hash() {
        return "%d%s%s".printf(
            this.supported_method, this.user ?? "", this.pass ?? ""
        ).hash();
    }
}
