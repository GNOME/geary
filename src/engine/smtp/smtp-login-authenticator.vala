/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Smtp.LoginAuthenticator : Geary.Smtp.AbstractAuthenticator {
    public LoginAuthenticator(Credentials credentials) {
        base (credentials);
    }
    
    public override string get_name() {
        return "LOGIN";
    }
    
    public override Request initiate() {
        return new Request(Command.AUTH, { "login" });
    }
    
    public override Memory.Buffer? challenge(int step, Response response) throws SmtpError {
        switch (step) {
            case 0:
                return new Memory.StringBuffer(Base64.encode(credentials.user.data));
            
            case 1:
                return new Memory.StringBuffer(Base64.encode((credentials.pass ?? "").data));
            
            default:
                return null;
        }
    }
}

