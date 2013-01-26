/* Copyright 2011-2012 Yorba Foundation
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
    
    public override uint8[]? challenge(int step, Response response) throws SmtpError {
        switch (step) {
            case 0:
                return Base64.encode(credentials.user.data).data;
            
            case 1:
                return Base64.encode((credentials.pass ?? "").data).data;
            
            default:
                return null;
        }
    }
}

