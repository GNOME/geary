/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.6]]
 *
 * @see FetchCommand
 * @see FetchedData
 */

public class Geary.Imap.StoreCommand : Command {
    public const string NAME = "store";
    public const string UID_NAME = "uid store";
    
    public StoreCommand(MessageSet message_set, Gee.List<MessageFlag> flag_list, bool add_flag, 
        bool silent) {
        base (message_set.is_uid ? UID_NAME : NAME);
        
        add(message_set.to_parameter());
        add(new AtomParameter("%sflags%s".printf(add_flag ? "+" : "-", silent ? ".silent" : "")));
        
        ListParameter list = new ListParameter();
        foreach(MessageFlag flag in flag_list)
            list.add(new AtomParameter(flag.value));
        
        add(list);
    }
}

