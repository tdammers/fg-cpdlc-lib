# CPDLC System class

var LOGON_NO_LINK = -4; # Transport is not available, cannot logon
var LOGON_NO_LOGON_STATION = -5; # No logon station selected, can't logon
var LOGON_FAILED = -2; # Last logon attempt did not succeed
var LOGON_NOT_CONNECTED = -1; # Currently disconnected, connecting possible
var LOGON_OK = 0; # Logged on successfully
var LOGON_ACCEPTED = 2; # Logon accepted, wait for CURRENT DATA AUTHORITY
var LOGON_SENT = 1; # Logon request sent, no reply received

var System = {
    new: func () {
        var m = {
            parents: [System],
            props: {
                base: nil,
                logonStatus: nil,
                connected: nil,
                currentStation: nil,
                logonStation: nil,
                nextStation: nil,
                history: nil,
                unread: nil,
                newestUnread: nil,
                incoming: nil,
                driver: nil,
            },
            driver: nil,
            drivers: {},
            nextMIN: 1,
        };
        return m;
    },

    attach: func (propBase=nil) {
        if (propBase == nil) {
            propBase = 'cpdlc';
        }
        if (typeof(propBase) == 'scalar') {
            me.props.base = props.globals.getNode(propBase, 1);
        }
        elsif (typeof(propBase) == 'ghost') {
            # Assume it's a property node already
            me.props.base = propBase;
        }
        me.props.datalinkStatus = me.props.base.getNode('datalink-status', 1);
        me.props.datalinkStatus.setValue(0);
        me.props.logonStatus = me.props.base.getNode('logon-status', 1);
        me.props.logonStatus.setValue(0);
        me.props.connected = me.props.base.getNode('connected', 1);
        me.props.connected.setValue(0);
        me.props.currentStation = me.props.base.getNode('current-station', 1);
        me.props.currentStation.setValue('');
        me.props.logonStation = me.props.base.getNode('logon-station', 1);
        me.props.nextStation = me.props.base.getNode('next-station', 1);
        me.props.nextStation.setValue('');
        me.props.history = me.props.base.getNode('history', 1);
        me.props.messages = me.props.base.getNode('messages', 1);
        me.props.unread = me.props.base.getNode('unread', 1);
        me.props.unread.setValue(0);
        me.props.newestUnread = me.props.base.getNode('newest-unread', 1);
        me.props.newestUnread.setValue('');
        me.props.incoming = me.props.base.getNode('incoming', 1);
        me.props.incoming.setValue(0);
        me.props.driver = me.props.base.getNode('driver', 1);
        me.setDriver(me.props.driver.getValue() or '');
        me.updateUnread();
    },

    registerDriver: func (driver) {
        var name = driver.getDriverName();
        me.drivers[name] = driver;
    },

    setDriver: func (driver) {
        if (typeof(driver) == 'scalar')
            driver = me.drivers[driver];
        if (me.driver != nil) {
            me.driver.stop();
            me.props.driver.setValue('');
        }
        me.props.datalinkStatus.setValue(0);
        me.driver = driver;
        if (me.driver != nil) {
            driver.start();
            me.props.driver.setValue(me.driver.getDriverName());
        }
        if (me.driver != nil and me.driver.isAvailable()) {
            if ((me.props.logonStation.getValue() or '') == '')
                me.setLogonStatus(LOGON_NO_LOGON_STATION);
            else
                me.setLogonStatus(LOGON_NOT_CONNECTED);
            me.props.datalinkStatus.setValue(1);
        }
        else {
            me.setLogonStatus(LOGON_NO_LINK);
        }
    },

    updateDatalinkStatus: func () {
        var oldStatus = me.props.datalinkStatus.getBoolValue();
        me.props.datalinkStatus.setBoolValue(me.driver != nil and me.driver.isAvailable());
        var newStatus = me.props.datalinkStatus.getBoolValue();
        if (oldStatus != newStatus) {
            var msg = Message.new();
            msg.dir = 'pseudo';
            if (newStatus) {
                # datalink up
                msg.parts = [{type: 'CONX-4', args: [me.driver.getDriverName()]}];
            }
            else {
                # datalink down
                msg.parts = [{type: 'CONX-5', args: [me.driver.getDriverName()]}];
            }
            msg.from = 'SYSTEM';
            msg.min = me.genMIN();
            msg.status = '';
            me.logMessage(msg);
        }
    },

    getDriver: func () {
        if (me.driver != nil)
            return me.driver.getDriverName();
        else
            return '';
    },

    listDrivers: func () {
        return sort(keys(me.drivers), func (a, b) { return string.icmp(a, b); });
    },

    setNextStation: func (station) {
        me.props.nextStation.setValue(station or '');
    },

    setLogonAccepted: func (station) {
        if (station == '') {
            me.setLogonStatus(LOGON_NOT_CONNECTED);
        }
        else {
            me.setLogonStatus(LOGON_ACCEPTED);
        }
    },

    setCurrentStation: func (station) {
        var prevStation = me.props.currentStation.getValue() or '';
        if (station == '') {
            me.setLogonStatus(LOGON_NOT_CONNECTED);
        }
        else {
            me.setLogonStatus(LOGON_OK);
        }
        me.props.currentStation.setValue(station or '');
        me.props.nextStation.setValue('');
        me.props.logonStation.setValue('');

        var msg = Message.new();
        msg.dir = 'pseudo';
        if (prevStation == '') {
            if (station == '') {
                # invalid situation
                msg.parts = [{type: 'CONX-6', args: ['NO LOGON STATION'] }];
            }
            else {
                # logon
                msg.parts = [{type: 'CONX-1', args: [station]}];
            }
        }
        else {
            if (station == '') {
                # logoff
                msg.parts = [{type: 'CONX-2', args: [] }];
            }
            else {
                # handover
                msg.parts = [{type: 'CONX-3', args: [station, prevStation]}];
            }
        }
        msg.from = 'SYSTEM';
        msg.min = me.genMIN();
        msg.status = '';
        me.logMessage(msg);
    },

    getCurrentStation: func {
        return me.props.currentStation.getValue() or '';
    },

    getNextStation: func {
        return me.props.nextStation.getValue() or '';
    },

    getLogonStation: func {
        return me.props.logonStation.getValue() or '';
    },

    setLogonStatus: func (status) {
        if (status == LOGON_FAILED) {
            var msg = Message.new();
            msg.dir = 'pseudo';
            msg.parts = [{type: 'CONX-6', args: ['LOGON FAILED']}];
            msg.from = 'SYSTEM';
            msg.min = me.genMIN();
            msg.status = '';
            me.logMessage(msg);
        }
        me.props.logonStatus.setValue(status);
        me.props.connected.setBoolValue(status == LOGON_OK);
    },


    connect: func (logonStation='') {
        if (logonStation == '') {
            logonStation = me.props.logonStation.getValue();
        }
        if (logonStation == '') {
            logonStation = me.props.nextStation.getValue();
        }
        if (logonStation == '') return;
        if (me.driver == nil) return;
        if (!me.driver.isAvailable()) return;
        me.setLogonStatus(LOGON_SENT);
        me.driver.connect(logonStation);
    },

    disconnect: func {
        if (!me.driver.isAvailable()) return;
        me.driver.disconnect();
    },

    genMIN: func {
        var min = me.nextMIN;
        me.nextMIN += 1;
        return min;
    },

    send: func(msg) {
        msg.min = me.genMIN();
        if (msg.to == nil or msg.to == '') {
            msg.to = me.getCurrentStation();
        }
        var mid = me.logMessage(msg);
        me.driver.send(msg);
        return mid;
    },

    receive: func(msg) {
        foreach (var part; msg.parts) {
            if (part.type == 'SYSU-2') {
                me.setNextStation(part.args[0]);
            }
        }
        return me.logMessage(msg);
    },

    markMessageSent: func(mid) {
        var msgNode = me.props.messages.getNode(mid, 0);
        if (msgNode != nil) {
            msgNode.setValue('status', 'SENT');
        }
    },

    logMessage: func(msg) {
        if (size(msg.parts) == 0) return nil;
        msg.timestamp = sprintf('%02i%02i', getprop('/sim/time/utc/hour'), getprop('/sim/time/utc/minute'));
        var mid = msg.getMID();
        var otherDir = (msg.dir == 'up') ? 'down' : 'up';

        var msgNode = me.props.messages.getNode(mid, 1);
        msgNode.removeAllChildren();
        msg.toNode(msgNode);

        var self = me;
        if (msg.dir == 'up') {
            me.props.incoming.setValue(1);
            settimer(func { self.props.incoming.setValue(0); }, 0.1, 1);
        }

        msgNode.setValues(msg);

        var ra = msg.getRA();
        if (ra == '' or ra == 'N') {
            msgNode.setValue('response-status', '');
            if (msg.dir == 'down')
                msgNode.setValue('status', 'SENDING');
            else
                msgNode.setValue('status', '');
        }
        else {
            msgNode.setValue('response-status', 'OPEN');
            if (msg.dir == 'down')
                msgNode.setValue('status', 'SENDING');
            else
                msgNode.setValue('status', 'NEW');
        }
        if (msg.mrn != nil) {
            # establish parent-child relationship
            var otherID = otherDir ~ msg.mrn;
            var parentNode = me.props.messages.getNode(otherID);
            if (parentNode != nil) {
                msgNode.setValue('parent', otherID);
                parentNode.setValue('reply', mid);
                if (msg.dir == 'up') {
                    # This is an uplink, so whatever it references must be a
                    # downlink request, and all we care about here is that
                    # a response has been received.
                    parentNode.setValue('status', 'RESPONSE RCVD');
                    parentNode.setValue('response-status', 'RESPONSE RCVD');
                }
                else {
                    # This is a downlink, so the original request came from
                    # ATC. We want to keep track not just of whether we
                    # responded, but, in the case of clearances (WU), also whether
                    # we have accepted or rejected it.
                    if (parentNode.getValue('ra') == 'Y') {
                        # "Y" response type means any response other than
                        # STAND BY closes the dialog
                        if (msg.parts[0].type != 'RSPD-3') {
                            parentNode.setValue('status', 'RESPONDED');
                            parentNode.setValue('response-status', 'RESPONDED');
                        }
                    }
                    elsif (msg.parts[0].type == 'RSPD-1' or msg.parts[0].type == 'RSPD-4') {
                        # WILCO / ROGER
                        parentNode.setValue('status', 'ACCEPTED');
                        parentNode.setValue('response-status', 'ACCEPTED');
                    }
                    elsif (msg.parts[0].type == 'RSPD-2') {
                        # UNABLE
                        parentNode.setValue('status', 'REJECTED');
                        parentNode.setValue('response-status', 'REJECTED');
                    }
                    elsif (msg.parts[0].type == 'RSPD-5' or msg.parts[0].type == 'RSPD-6') {
                        # AFFIRM / NEGATIVE
                        parentNode.setValue('status', 'RESPONDED');
                        parentNode.setValue('response-status', 'RESPONDED');
                    }
                }
            }
        }
        me.props.history.addChild('item').setValue(mid);
        me.updateUnread();
        return mid;
    },

    markMessageRead: func(mid) {
        var msgNode = me.props.messages.getNode(mid, 1);
        var msg = messageFromNode(msgNode);
        if (msg.status != 'NEW') return;
        msgNode.setValue('status', msgNode.getValue('response-status'));
        me.updateUnread();
    },

    updateUnread: func () {
        var msgNodes = me.props.messages.getChildren();
        var numUnread = 0;
        var newest = '';
        foreach (var msgNode; msgNodes) {
            if (msgNode.getValue('status') == 'NEW') {
                var msg = Message.fromNode(msgNode);
                newest = msg.getMID();
                numUnread += 1;
            }
        }
        me.props.unread.setValue(numUnread);
        me.props.newestUnread.setValue(newest);
    },


    clearHistory: func () {
        me.props.history.removeAllChildren();
        me.props.messages.removeAllChildren();
        me.updateUnread();
    },
};
