// Real SuperCalc2, using its installer-generated P2000M terminal profile.
static void sc_send(P2000Machine &m,const std::string &text) {
    for(char c:text) {
        unsigned row=0,bit=0;
        if(c=='+') { row=8;bit=4; }
        else if(c=='(') { row=6;bit=6; }
        else if(c==')') { row=5;bit=1; }
        else { type(m,std::string(1,c));continue; }
        m.setKey(9,0,true);frames(m,2);
        m.setKey(row,bit,true);frames(m,3);
        m.setKey(row,bit,false);frames(m,3);
        m.setKey(9,0,false);frames(m,2);
    }
    // Overlay changes discard type-ahead. Let each command reach its prompt.
    frames(m,1000);
}
static void sc_active(P2000Machine &m,const std::string &cell) {
    require(screen(m).substr(21*80+2,cell.size()+1)==cell+" ","SuperCalc active cell: "+cell);
}
static void sc_arrow(P2000Machine &m,unsigned row,unsigned bit) {
    m.setKey(row,bit,true);frames(m,3);
    m.setKey(row,bit,false);frames(m,100);
}
static void sc_start(P2000Machine &m,bool help=false) {
    sc_send(m,"D:\nSC2\n");
    wait_text(m,"P2000M VT52");
    if(help) {
        // Physical Shift + '?' key, exercising the keyboard and SC2.HLP overlay.
        m.setKey(9,0,true);frames(m,2);m.setKey(7,5,true);frames(m,3);
        m.setKey(7,5,false);frames(m,3);m.setKey(9,0,false);frames(m,3000);
        wait_text(m,"Welcome to SuperCalc2!");wait_text(m,"Press any key to continue");
        sc_send(m," ");wait_text(m,"If you have questions");
        sc_send(m," ");
    } else sc_send(m,"\n");
    sc_active(m,"A1");
}
static void supercalc_test(P2000Machine &m,bool reload=false) {
    sc_start(m,!reload);
    if(!reload) {
        sc_send(m,"6\n7\nA1*B1\n");sc_active(m,"D1");
        require(screen(m).substr(80+22,9)=="       42","SuperCalc formula 6*7");
        sc_send(m,"=A1\n9\n");sc_active(m,"B1");
        require(screen(m).substr(80+22,9)=="       63","SuperCalc automatic recalculation");
        sc_arrow(m,0,0);sc_active(m,"A1");
        sc_arrow(m,2,7);sc_active(m,"B1");
        sc_arrow(m,2,7);sc_active(m,"C1");
        require(m.attributes()[80+22]==8 && m.attributes()[80+13]==0,"SuperCalc inverse selection");
        require(screen(m).substr(80+22,9)=="       63","Selection clipped cell value");
        sc_arrow(m,2,5);sc_active(m,"C2");
        sc_arrow(m,0,2);sc_active(m,"C1");
        sc_arrow(m,0,0);sc_active(m,"B1");
        sc_send(m,"=J25\n");sc_active(m,"J25");
        require(screen(m).substr(0,80).find("J")!=std::string::npos &&
                screen(m).substr(80,4).find("25")!=std::string::npos,"SuperCalc viewport scroll");
        sc_arrow(m,0,0);sc_active(m,"I25");
        sc_send(m,"=A1\n");sc_active(m,"A1");
        sc_send(m,"/S");wait_text(m,"Enter File Name");
        sc_send(m,"SCTEST\n");wait_text(m,"A(ll)");
        sc_send(m,"A");wait_text(m,"Width:");
    } else {
        sc_send(m,"/L");wait_text(m,"Enter File Name");
        sc_send(m,"SCTEST\n");wait_text(m,"A(ll)");
        sc_send(m,"A");wait_text(m,"Width:");
        sc_send(m,"=A1\n");
        require(screen(m).substr(80+4,9)=="        9" &&
                screen(m).substr(80+13,9)=="        7" &&
                screen(m).substr(80+22,9)=="       63","SuperCalc saved worksheet reload");
        sc_send(m,"8\n");
        require(screen(m).substr(80+22,9)=="       56","Reload lost formula dependencies");
    }
    sc_send(m,"/QY");prompt(m); // This edition deliberately returns to A:.
    sc_send(m,"HELLO\n");prompt(m);wait_text(m,"Hello from an original Z80");
}

// GoTo scrolls only when necessary; locate the selected cell by its attributes.
static void sc_goto(P2000Machine &m,const std::string &cell) {
    sc_send(m,"="+cell+"\n");sc_active(m,cell);
}
static void sc_put(P2000Machine &m,const std::string &cell,const std::string &value) {
    sc_goto(m,cell);sc_send(m,value+"\n");
}
static void sc_number(P2000Machine &m,const std::string &cell,double expected) {
    sc_goto(m,cell);
    size_t selected=0,count=0;
    for(size_t i=80;i<21*80;++i) {
        if(m.attributes()[i]==8) { if(!count)selected=i;++count; }
    }
    require(count==9,"Expected one nine-column inverse numeric cell: "+cell);
    auto split=cell.find_first_of("0123456789");
    std::string display=screen(m);
    require(display.substr(selected%80,9).find(cell.substr(0,split))!=std::string::npos,
            "Selected column heading: "+cell);
    require(std::stoi(display.substr(selected/80*80,3))==std::stoi(cell.substr(split)),
            "Selected row heading: "+cell);
    std::string shown=display.substr(selected,9);
    auto first=shown.find_first_not_of(' '),last=shown.find_last_not_of(' ');
    require(first!=std::string::npos,"Empty numeric cell "+cell);
    shown=shown.substr(first,last-first+1);
    size_t consumed=0;
    double actual=std::stod(shown,&consumed);
    require(consumed==shown.size() && actual==expected,
            cell+" expected "+std::to_string(expected)+" displayed "+shown);
}
static void sc_file(P2000Machine &m,char command,const std::string &name,bool overwrite=false) {
    sc_send(m,std::string("/")+command);wait_text(m,"Enter File Name");
    sc_send(m,name+"\n");
    if(overwrite) { wait_text(m,"O(verwrite)");sc_send(m,"O"); }
    wait_text(m,"A(ll)");sc_send(m,"A");wait_text(m,"Width:");
}
static void sc_finish(P2000Machine &m) {
    sc_send(m,"/QY");prompt(m);
    sc_send(m,"HELLO\n");prompt(m);wait_text(m,"Hello from an original Z80");
}
static void supercalc_scenario(P2000Machine &m,const std::string &name) {
    sc_start(m);
    if(name=="SCCALC") {
        sc_put(m,"A1","12");sc_put(m,"B1","4");
        sc_put(m,"C1","A1+B1");sc_number(m,"C1",16);
        sc_put(m,"D1","A1-B1");sc_number(m,"D1",8);
        sc_put(m,"E1","A1*B1");sc_number(m,"E1",48);
        sc_put(m,"F1","A1/B1");sc_number(m,"F1",3);
        sc_put(m,"G1","(A1+B1)*2");sc_number(m,"G1",32);
        sc_put(m,"H1","A1+B1*2");sc_number(m,"H1",20);
        sc_put(m,"A2","1.25");sc_put(m,"B2","-2.5");
        sc_put(m,"C2","A2*B2");sc_number(m,"C2",-3.125);
        sc_put(m,"I1","SUM(A1:B1)");sc_number(m,"I1",16);
        sc_put(m,"J1","C1*2");sc_number(m,"J1",32);
        sc_put(m,"A1","20");
        sc_number(m,"C1",24);sc_number(m,"D1",16);sc_number(m,"E1",80);
        sc_number(m,"F1",5);sc_number(m,"G1",48);sc_number(m,"H1",28);
        sc_number(m,"I1",24);sc_number(m,"J1",48);
    } else if(name=="SCNAV") {
        sc_put(m,"A1","12345678");sc_number(m,"A1",12345678);
        sc_arrow(m,0,0);sc_active(m,"A1");
        sc_arrow(m,0,2);sc_active(m,"A1");
        for(int i=0;i<9;++i)sc_arrow(m,2,7);
        sc_active(m,"J1");
        for(int i=0;i<24;++i)sc_arrow(m,2,5);
        sc_active(m,"J25");sc_send(m,"925\n");
        sc_put(m,"Z100","2600");sc_number(m,"Z100",2600);
        sc_arrow(m,0,0);sc_active(m,"Y100");
        sc_arrow(m,0,2);sc_active(m,"Y99");
        sc_number(m,"J25",925);sc_number(m,"A1",12345678);
        sc_number(m,"Z100",2600);
    } else if(name=="SCMISSING") {
        sc_put(m,"A1","42");
        sc_send(m,"/L");wait_text(m,"Enter File Name");
        sc_send(m,"MISSING\n");wait_text(m,"File NOT on Disk");
        // P2000 Escape+C generates Ctrl-C, SuperCalc's command cancellation.
        sc_send(m,"\x1b" "C");wait_text(m,"Width:");
        sc_number(m,"A1",42);
        sc_file(m,'L',"SAMPLE");sc_number(m,"B4",1000);
    } else if(name=="SCFILES") {
        sc_put(m,"A1","12");sc_put(m,"B1","A1*2");
        sc_file(m,'S',"ORIGINAL");
        sc_put(m,"A1","21");sc_file(m,'S',"CHANGED");
        sc_put(m,"A1","30");sc_file(m,'S',"CHANGED",true);
        sc_number(m,"B1",60);
    } else if(name=="SCFILELOAD") {
        sc_file(m,'L',"CHANGED");sc_number(m,"A1",30);sc_number(m,"B1",60);
        sc_put(m,"A1","7");sc_number(m,"B1",14);
        sc_file(m,'L',"ORIGINAL");sc_number(m,"A1",12);sc_number(m,"B1",24);
        sc_put(m,"A1","8");sc_number(m,"B1",16);
    } else if(name=="SCSAMPLE") {
        sc_file(m,'L',"SAMPLE");
        sc_number(m,"B4",1000);sc_number(m,"B6",300);sc_number(m,"B8",700);
        sc_number(m,"B14",500);sc_number(m,"B16",200);
        sc_number(m,"B18",80);sc_number(m,"B20",120);
        sc_file(m,'S',"SAMPCOPY");
    } else if(name=="SCSAMPLOAD") {
        sc_file(m,'L',"SAMPCOPY");sc_number(m,"B4",1000);sc_number(m,"B20",120);
        sc_put(m,"B4","2000");sc_number(m,"B8",1700);
    } else require(false,"Unknown SuperCalc scenario "+name);
    sc_finish(m);
}
