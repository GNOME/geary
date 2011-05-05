/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

MainLoop? main_loop = null;

void print(int depth, Gee.List<Geary.Imap.Parameter> params) {
    string pad = string.nfill(depth * 4, ' ');
    
    int index = 0;
    foreach (Geary.Imap.Parameter param in params) {
        Geary.Imap.ListParameter? list = param as Geary.Imap.ListParameter;
        if (list == null) {
            stdout.printf("%s#%02d >%s<\n", pad, index++, param.to_string());
            
            continue;
        }
        
        print(depth + 1, list.get_all());
    }
}

void on_params_ready(Geary.Imap.RootParameters root) {
    print(0, root.get_all());
}

void on_eos() {
    main_loop.quit();
}

int main(string[] args) {
    if (args.length < 2) {
        stderr.printf("usage: syntax <imap command>\n");
        
        return 1;
    }
    
    main_loop = new MainLoop();
    
    // turn argument into single line for deserializer
    string line = "";
    for (int ctr = 1; ctr < args.length; ctr++) {
        line += args[ctr];
        if (ctr < (args.length - 1))
            line += " ";
    }
    line += "\r\n";
    
    MemoryInputStream mins = new MemoryInputStream();
    mins.add_data(line.data, null);
    
    Geary.Imap.Deserializer des = new Geary.Imap.Deserializer(mins);
    des.parameters_ready.connect(on_params_ready);
    des.eos.connect(on_eos);
    
    stdout.printf("INPUT: >%s<\n", line);
    des.xon();
    
    main_loop.run();
    
    return 0;
}

