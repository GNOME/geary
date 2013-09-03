/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of the IMAP FETCH command.
 *
 * FETCH is easily the most complicated IMAP command.  It has a large number of parameters, some of
 * which have a number of variants, others defined as macros combining other fields, and the
 * returned {@link ServerData} requires involved decoding patterns.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.5]]
 *
 * @see FetchedData
 * @see StoreCommand
 */

public class Geary.Imap.FetchCommand : Command {
    public const string NAME = "fetch";
    public const string UID_NAME = "uid fetch";
    
    public FetchCommand(MessageSet msg_set, Gee.List<FetchDataSpecifier>? data_items,
        Gee.List<FetchBodyDataSpecifier>? body_data_items) {
        base (msg_set.is_uid ? UID_NAME : NAME);
        
        add(msg_set.to_parameter());
        
        int data_items_length = (data_items != null) ? data_items.size : 0;
        int body_items_length = (body_data_items != null) ? body_data_items.size : 0;
        
        // see note in unadorned ctor for reasoning here
        if (data_items_length == 1 && body_items_length == 0) {
            add(data_items[0].to_parameter());
        } else if (data_items_length == 0 && body_items_length == 1) {
            add(body_data_items[0].to_request_parameter());
        } else {
            ListParameter list = new ListParameter();
            
            if (data_items_length > 0) {
                foreach (FetchDataSpecifier data_item in data_items)
                    list.add(data_item.to_parameter());
            }
            
            if (body_items_length > 0) {
                foreach (FetchBodyDataSpecifier body_item in body_data_items)
                    list.add(body_item.to_request_parameter());
            }
            
            add(list);
        }
    }
    
    public FetchCommand.data_type(MessageSet msg_set, FetchDataSpecifier data_type) {
        base (msg_set.is_uid ? UID_NAME : NAME);
        
        add(msg_set.to_parameter());
        add(data_type.to_parameter());
    }
    
    public FetchCommand.body_data_type(MessageSet msg_set, FetchBodyDataSpecifier body_data_specifier) {
        base (msg_set.is_uid ? UID_NAME : NAME);
        
        add(msg_set.to_parameter());
        add(body_data_specifier.to_request_parameter());
    }
}

