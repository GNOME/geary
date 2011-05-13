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

public class Geary.Imap.FetchResults {
    public int msg_num { get; private set; }
    
    private Gee.Map<FetchDataItem, MessageData> map = new Gee.HashMap<FetchDataItem, MessageData>();
    
    public FetchResults(int msg_num) {
        this.msg_num = msg_num;
    }
    
    public static FetchResults decode(ServerData data) throws ImapError {
        StringParameter msg_num = (StringParameter) data.get_as(1, typeof(StringParameter));
        StringParameter cmd = (StringParameter) data.get_as(2, typeof(StringParameter));
        ListParameter list = (ListParameter) data.get_as(3, typeof(ListParameter));
        
        // verify this is a FETCH response
        if (!cmd.equals_ci("fetch")) {
            throw new ImapError.TYPE_ERROR("Unable to decode fetch response \"%s\": Not marked as fetch response",
                data.to_string());
        }
        
        FetchResults results = new FetchResults(msg_num.as_int());
        
        // walk the list for each returned fetch data item, which is paired by its data item name
        // and the structured data itself
        for (int ctr = 0; ctr < list.get_count(); ctr += 2) {
            StringParameter data_item_param = (StringParameter) list.get_as(ctr, typeof(StringParameter));
            FetchDataItem data_item = FetchDataItem.decode(data_item_param.value);
            FetchDataDecoder? decoder = data_item.get_decoder();
            if (decoder == null) {
                debug("Unable to decode fetch response for \"%s\": No decoder available",
                    data_item.to_string());
                
                continue;
            }
            
            results.set_data(data_item, decoder.decode(list.get_required(ctr + 1)));
        }
        
        return results;
    }
    
    public static FetchResults[] decode_command_response(CommandResponse response) throws ImapError {
        FetchResults[] array = new FetchResults[0];
        foreach (ServerData data in response.server_data)
            array += decode(data);
        
        return array;
    }
    
    public void set_data(FetchDataItem data_item, MessageData primitive) {
        map.set(data_item, primitive);
    }
    
    public MessageData? get_data(FetchDataItem data_item) {
        return map.get(data_item);
    }
    
    public int get_count() {
        return map.size;
    }
}

