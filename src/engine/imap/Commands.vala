/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.CapabilityCommand : Command {
    public const string NAME = "capability";
    
    public CapabilityCommand(ClientSession session) {
        base (new Tag.generated(session), NAME);
    }
}

public class Geary.Imap.NoopCommand : Command {
    public const string NAME = "noop";
    
    public NoopCommand(ClientSession session) {
        base (new Tag.generated(session), NAME);
    }
}

public class Geary.Imap.LoginCommand : Command {
    public const string NAME = "login";
    
    public LoginCommand(ClientSession session, string user, string pass) {
        base (new Tag.generated(session), NAME, { user, pass });
    }
    
    public override string to_string() {
        return "%s %s <user> <pass>".printf(tag.to_string(), name);
    }
}

public class Geary.Imap.LogoutCommand : Command {
    public const string NAME = "logout";
    
    public LogoutCommand(ClientSession session) {
        base (new Tag.generated(session), NAME);
    }
}

public class Geary.Imap.ListCommand : Command {
    public const string NAME = "list";
    
    public ListCommand(ClientSession session, string mailbox) {
        base (new Tag.generated(session), NAME, { "", mailbox });
    }
    
    public ListCommand.wildcarded(ClientSession session, string reference, string mailbox) {
        base (new Tag.generated(session), NAME, { reference, mailbox });
    }
}

public class Geary.Imap.ExamineCommand : Command {
    public const string NAME = "examine";
    
    public ExamineCommand(ClientSession session, string mailbox) {
        base (new Tag.generated(session), NAME, { mailbox });
    }
}

