/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.CapabilityCommand : Command {
    public const string NAME = "capability";
    
    public CapabilityCommand() {
        base (NAME);
    }
}

public class Geary.Imap.CompressCommand : Command {
    public const string NAME = "compress";
    
    public const string ALGORITHM_DEFLATE = "deflate";
    
    public CompressCommand(string algorithm) {
        base (NAME, { algorithm });
    }
}

public class Geary.Imap.StarttlsCommand : Command {
    public const string NAME = "starttls";
    
    public StarttlsCommand() {
        base (NAME);
    }
}

public class Geary.Imap.NoopCommand : Command {
    public const string NAME = "noop";
    
    public NoopCommand() {
        base (NAME);
    }
}

public class Geary.Imap.LoginCommand : Command {
    public const string NAME = "login";
    
    public LoginCommand(string user, string pass) {
        base (NAME, { user, pass });
    }
    
    public override string to_string() {
        return "%s %s <user> <pass>".printf(tag.to_string(), name);
    }
}

public class Geary.Imap.LogoutCommand : Command {
    public const string NAME = "logout";
    
    public LogoutCommand() {
        base (NAME);
    }
}

public class Geary.Imap.ListCommand : Command {
    public const string NAME = "list";
    public const string XLIST_NAME = "xlist";
    
    public ListCommand(Geary.Imap.MailboxParameter mailbox, bool use_xlist) {
        base (use_xlist ? XLIST_NAME : NAME, { "", mailbox.value });
    }
    
    public ListCommand.wildcarded(string reference, Geary.Imap.MailboxParameter mailbox, bool use_xlist) {
        base (use_xlist ? XLIST_NAME : NAME, { reference, mailbox.value });
    }
}

public class Geary.Imap.ExamineCommand : Command {
    public const string NAME = "examine";
    
    public ExamineCommand(Geary.Imap.MailboxParameter mailbox) {
        base (NAME, { mailbox.value });
    }
}

public class Geary.Imap.SelectCommand : Command {
    public const string NAME = "select";
    
    public SelectCommand(Geary.Imap.MailboxParameter mailbox) {
        base (NAME, { mailbox.value });
    }
}

public class Geary.Imap.CloseCommand : Command {
    public const string NAME = "close";
    
    public CloseCommand() {
        base (NAME);
    }
}

public class Geary.Imap.StatusCommand : Command {
    public const string NAME = "status";
    
    public StatusCommand(Geary.Imap.MailboxParameter mailbox, StatusDataType[] data_items) {
        base (NAME);
        
        add(mailbox);
        
        assert(data_items.length > 0);
        ListParameter data_item_list = new ListParameter(this);
        foreach (StatusDataType data_item in data_items)
            data_item_list.add(data_item.to_parameter());
        
        add(data_item_list);
    }
}

public class Geary.Imap.StoreCommand : Command {
    public const string NAME = "store";
    public const string UID_NAME = "uid store";
    
    public StoreCommand(MessageSet message_set, Gee.List<MessageFlag> flag_list, bool add_flag, 
        bool silent) {
        base (message_set.is_uid ? UID_NAME : NAME);
        
        add(message_set.to_parameter());
        add(new StringParameter("%sflags%s".printf(add_flag ? "+" : "-", silent ? ".silent" : "")));
        
        ListParameter list = new ListParameter(this);
        foreach(MessageFlag flag in flag_list)
            list.add(new StringParameter(flag.value));
        
        add(list);
    }
}

// Results of this command automatically handled by Geary.Imap.UnsolicitedServerData
public class Geary.Imap.ExpungeCommand : Command {
    public const string NAME = "expunge";
    public const string UID_NAME = "uid expunge";
    
    public ExpungeCommand() {
        base (NAME);
    }
    
    public ExpungeCommand.uid(MessageSet message_set) {
        base (UID_NAME);
        
        assert(message_set.is_uid);
        
        add(message_set.to_parameter());
    }
}

public class Geary.Imap.IdleCommand : Command {
    public const string NAME = "idle";
    
    public IdleCommand() {
        base (NAME);
    }
}

public class Geary.Imap.CopyCommand : Command {
    public const string NAME = "copy";
    public const string UID_NAME = "uid copy";

    public CopyCommand(MessageSet message_set, Geary.Imap.MailboxParameter destination) {
        base (message_set.is_uid ? UID_NAME : NAME);

        add(message_set.to_parameter());
        add(destination);
    }
}

public class Geary.Imap.IdCommand : Command {
    public const string NAME = "id";
    
    public IdCommand(Gee.HashMap<string, string> fields) {
        base (NAME);
        
        ListParameter list = new ListParameter(this);
        foreach (string key in fields.keys) {
            list.add(new QuotedStringParameter(key));
            list.add(new QuotedStringParameter(fields.get(key)));
        }
        
        add(list);
    }
    
    public IdCommand.nil() {
        base (NAME);
        
        add(NilParameter.instance);
    }
}

