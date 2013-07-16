/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public abstract class Geary.Smtp.AbstractAuthenticator : BaseObject, Geary.Smtp.Authenticator {
    public Credentials credentials { get; private set; }
    
    public AbstractAuthenticator(Credentials credentials) {
        this.credentials = credentials;
    }
    
    public abstract string get_name();
    
    public abstract Request initiate();
    
    public abstract Memory.Buffer? challenge(int step, Response response) throws SmtpError;
}

