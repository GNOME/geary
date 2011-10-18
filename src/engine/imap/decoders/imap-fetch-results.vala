/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * FetchResults represents the data returned from a FETCH response for each message.  Since
 * FETCH allows for multiple FetchDataItems to be requested, this object can hold all of them.
 *
 * decode_command_response() will take a CommandResponse for a FETCH command and return all
 * results for all messages specified.
 */

public class Geary.Imap.FetchResults : Geary.Imap.CommandResults {
    public int msg_num { get; private set; }
    
    private Gee.Map<FetchDataType, MessageData> map = new Gee.HashMap<FetchDataType, MessageData>();
    private Gee.List<Memory.AbstractBuffer> body_data = new Gee.ArrayList<Memory.AbstractBuffer>();
    
    public FetchResults(StatusResponse status_response, int msg_num) {
        base (status_response);
        
        this.msg_num = msg_num;
    }
    
    public static FetchResults decode_data(StatusResponse status_response, ServerData data) throws ImapError {
        StringParameter msg_num = data.get_as_string(1);
        StringParameter cmd = data.get_as_string(2);
        ListParameter list = data.get_as_list(3);
        
        // verify this is a FETCH response
        if (!cmd.equals_ci(FetchCommand.NAME)) {
            throw new ImapError.TYPE_ERROR("Unable to decode fetch response \"%s\": Not marked as fetch response",
                data.to_string());
        }
        
        FetchResults results = new FetchResults(status_response, msg_num.as_int());
        
        // walk the list for each returned fetch data item, which is paired by its data item name
        // and the structured data itself
        for (int ctr = 0; ctr < list.get_count(); ctr += 2) {
            StringParameter data_item_param = list.get_as_string(ctr);
            
            if (FetchBodyDataType.is_fetch_body(data_item_param)) {
                // FETCH body data items are merely a literal of all requested fields formatted
                // in RFC822 header format
                results.body_data.add(list.get_as_literal(ctr + 1).get_buffer());
            } else {
                FetchDataType data_item = FetchDataType.decode(data_item_param.value);
                FetchDataDecoder? decoder = data_item.get_decoder();
                if (decoder == null) {
                    debug("Unable to decode fetch response for \"%s\": No decoder available",
                        data_item.to_string());
                    
                    continue;
                }
                
                results.set_data(data_item, decoder.decode(list.get_required(ctr + 1)));
            }
        }
        
        return results;
    }
    
    public static FetchResults[] decode(CommandResponse response) {
        assert(response.is_sealed());
        
        FetchResults[] array = new FetchResults[0];
        foreach (ServerData data in response.server_data) {
            try {
                array += decode_data(response.status_response, data);
            } catch (ImapError ierr) {
                // drop bad data on the ground
                debug("Dropping FETCH data \"%s\": %s", data.to_string(), ierr.message);
                
                continue;
            }
        }
        
        return array;
    }
    
    public Gee.Set<FetchDataType> get_all_types() {
        return map.keys;
    }
    
    private void set_data(FetchDataType data_item, MessageData primitive) {
        map.set(data_item, primitive);
    }
    
    public MessageData? get_data(FetchDataType data_item) {
        return map.get(data_item);
    }
    
    public Gee.List<Memory.AbstractBuffer> get_body_data() {
        return body_data.read_only_view;
    }
    
    public int get_count() {
        return map.size;
    }
}

