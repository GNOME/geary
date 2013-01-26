/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Smtp.PlainAuthenticator : Geary.Smtp.AbstractAuthenticator {
    private static uint8[] nul = { '\0' };
    
    public PlainAuthenticator(Credentials credentials) {
        base (credentials);
    }
    
    public override string get_name() {
        return "PLAIN";
    }
    
    public override Request initiate() {
        return new Request(Command.AUTH, { "plain" });
    }
    
    public override uint8[]? challenge(int step, Response response) throws SmtpError {
        // only a single challenge is issued in PLAIN
        if (step > 0)
            return null;
        
        Memory.GrowableBuffer growable = new Memory.GrowableBuffer();
        // skip the "authorize" field, which we don't support
        growable.append(nul);
        growable.append(credentials.user.data);
        growable.append(nul);
        growable.append((credentials.pass ?? "").data);
        
        return Base64.encode(growable.get_array()).data;
    }
}

