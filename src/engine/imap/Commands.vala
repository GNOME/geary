/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.CapabilityCommand : Command {
    public const string NAME = "capability";
    
    public CapabilityCommand(Tag tag) {
        base (tag, NAME);
    }
}

public class Geary.Imap.NoopCommand : Command {
    public const string NAME = "noop";
    
    public NoopCommand(Tag tag) {
        base (tag, NAME);
    }
}

public class Geary.Imap.LoginCommand : Command {
    public const string NAME = "login";
    
    public LoginCommand(Tag tag, string user, string pass) {
        base (tag, NAME, { user, pass });
    }
    
    public override string to_string() {
        return "%s %s <user> <pass>".printf(tag.to_string(), name);
    }
}

public class Geary.Imap.LogoutCommand : Command {
    public const string NAME = "logout";
    
    public LogoutCommand(Tag tag) {
        base (tag, NAME);
    }
}

public class Geary.Imap.ListCommand : Command {
    public const string NAME = "list";
    
    public ListCommand(Tag tag, string mailbox) {
        base (tag, NAME, { "", mailbox });
    }
    
    public ListCommand.wildcarded(Tag tag, string reference, string mailbox) {
        base (tag, NAME, { reference, mailbox });
    }
}

public class Geary.Imap.XListCommand : Command {
    public const string NAME = "xlist";
    
    public XListCommand(Tag tag, string mailbox) {
        base (tag, NAME, { "", mailbox });
    }
    
    public XListCommand.wildcarded(Tag tag, string reference, string mailbox) {
        base (tag, NAME, { reference, mailbox });
    }
}

public class Geary.Imap.ExamineCommand : Command {
    public const string NAME = "examine";
    
    public ExamineCommand(Tag tag, string mailbox) {
        base (tag, NAME, { mailbox });
    }
}

public class Geary.Imap.SelectCommand : Command {
    public const string NAME = "select";
    
    public SelectCommand(Tag tag, string mailbox) {
        base (tag, NAME, { mailbox });
    }
}

public class Geary.Imap.CloseCommand : Command {
    public const string NAME = "close";
    
    public CloseCommand(Tag tag) {
        base (tag, NAME);
    }
}

public class Geary.Imap.FetchCommand : Command {
    public const string NAME = "fetch";
    
    public FetchCommand(Tag tag, string msg_span, FetchDataType[] data_items) {
        base (tag, NAME);
        
        add(new StringParameter(msg_span));
        
        assert(data_items.length > 0);
        if (data_items.length == 1) {
            add(data_items[0].to_parameter());
        } else {
            ListParameter data_item_list = new ListParameter(this);
            foreach (FetchDataType data_item in data_items)
                data_item_list.add(data_item.to_parameter());
            
            add(data_item_list);
        }
    }
}

public class Geary.Imap.StatusCommand : Command {
    public const string NAME = "status";
    
    public StatusCommand(Tag tag, string mailbox, StatusDataType[] data_items) {
        base (tag, NAME);
        
        add (new StringParameter(mailbox));
        
        assert(data_items.length > 0);
        ListParameter data_item_list = new ListParameter(this);
        foreach (StatusDataType data_item in data_items)
            data_item_list.add(data_item.to_parameter());
        
        add(data_item_list);
    }
}

