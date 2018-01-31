/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Smtp.Request {
    public Command cmd { get; private set; }
    public string[]? args { get; private set; }
    
    public Request(Command cmd, string[]? args = null) {
        this.cmd = cmd;
        this.args = args;
    }
    
    public string serialize() {
        // fast-path
        if (args == null || args.length == 0)
            return cmd.serialize();
        
        StringBuilder builder = new StringBuilder();
        
        builder.append(cmd.serialize());
        
        foreach (string arg in args) {
            builder.append_c(' ');
            builder.append(arg);
        }
        
        return builder.str;
    }
    
    public string to_string() {
        return serialize();
    }
}

public class Geary.Smtp.HeloRequest : Geary.Smtp.Request {
    public HeloRequest(string domain) {
        base (Command.HELO, { domain });
    }
    
    public HeloRequest.for_local_address(InetAddress local_addr) {
        this ("[%s]".printf(local_addr.to_string()));
    }
}

public class Geary.Smtp.EhloRequest : Geary.Smtp.Request {
    public EhloRequest(string domain) {
        base (Command.EHLO, { domain });
    }
    
    public EhloRequest.for_local_address(InetAddress local_addr) {
        string prefix = (local_addr.family == SocketFamily.IPV6) ? "IPv6:" : "";
        this ("[%s%s]".printf(prefix, local_addr.to_string()));
    }
}

public class Geary.Smtp.MailRequest : Geary.Smtp.Request {
    public MailRequest(Geary.RFC822.MailboxAddress from) {
        base (Command.MAIL, { "from:%s".printf(from.to_address_display("<", ">")) });
    }

    public MailRequest.plain(string addr) {
        base (Command.MAIL, { "from:<%s>".printf(addr) });
    }
}

public class Geary.Smtp.RcptRequest : Geary.Smtp.Request {
    public RcptRequest(Geary.RFC822.MailboxAddress to) {
        base (Command.RCPT, { "to:%s".printf(to.to_address_display("<", ">")) });
    }
    
    public RcptRequest.plain(string addr) {
        base (Command.RCPT, { "to:<%s>".printf(addr) });
    }
}

