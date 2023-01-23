var acdir = getprop('/sim/aircraft-dir');
var path = acdir ~ '/Nasal/cpdlc/parser-combinators.nas';
io.load_nasal(path, 'cpdlc');

# These are not in ICAO Doc 4444; we use these to inject system events into the
# message log, but we never send or receive these.
var hoppie_uplink_messages = {
    "HPPU-1": { txt: "LOGON ACCEPTED", args: [] },
    "HPPU-2": { txt: "HANDOVER $1", args: [ARG_FACILITY] },
    "HPPU-3": { txt: "LOGOFF", args: [] },
};

var hoppie_downlink_messages = {
    "HPPD-1": { txt: "REQUEST LOGON", args: [] },
};

var argParsers = {};

argParsers[ARG_TEXT] = func (delimiter=nil) {
    if (delimiter == nil)
        delimiter = eof;
    return pMap(
            unwords,
            manyTill(anyToken, delimiter));
};

var unwords = func (words) {
    return string.join(' ', words);
};

var isCallsign = func (str) {
    return isstr(str) and size(str) and string.isalpha(str[0]);
};

var isNumber = func (str) {
    return num(str) != nil;
};

var isSpeed = func (str) {
    if (startswith(str, 'MACH') and isNumber(substr(str, 4))) {
        return 1;
    }
    elsif (startswith(str, 'M') and isNumber(substr(str, 1))) {
        return 1;
    }
    else {
        return 0;
    }
};

argParsers[ARG_FACILITY] = func (delimiter=nil) {
    return satisfy(isCallsign);
};

argParsers[ARG_CALLSIGN] = func (delimiter=nil) {
    return pMap(unwords, many(satisfy(isCallsign)));
};

argParsers[ARG_NAVPOS] = func (delimiter=nil) {
    return anyToken;
};

argParsers[ARG_FL_ALT] = func (delimiter=nil) {
    return satisfy(func (val) {
        if (startswith(val, 'FL') and isNumber(substr(val, 2))) {
            return 1;
        }
        elsif (endswith(val, 'FT') and isNumber(substr(val, 0, size(val) - 2))) {
            return 1;
        }
        elsif (endswith(val, 'M') and isNumber(substr(val, 0, size(val) - 1))) {
            return 1;
        }
        else {
            return 0;
        }
    });
};

argParsers[ARG_SPEED] = func (delimiter=nil) {
    return choice(
        [
            satisfy(isSpeed),
            pBind(satisfy(isNumber), func (val) {
                return pBind(oneOf(['KTS', 'KNOTS', 'MACH', 'KMH', 'KPH']), func (unit) {
                        return pOK(val ~ ' ' ~ unit);
                    });
                }),
        ]);
};

var getArgParser = func (type, delimiter=nil) {
    var elemType = type & ARG_TYPE_MASK;
    var optionalType = type & ARG_OPTIONAL;

    var p = nil;
    if (contains(argParsers, elemType)) {
        p = argParsers[elemType](delimiter);
    }
    else {
        p = argParsers[ARG_TEXT](delimiter);
    }

    if (optionalType) {
        p = optionally(p);
    }

    return p;
};

var matchMessageText = func (msg, tokens) {
    var ts = TokenStream.new(tokens);
    var words = split(' ', msg.txt);
    var ps = TokenStream.new(words);

    var args = [];

    while (!ps.eof()) {
        var pspec = runP(ps, anyToken);
        var delimiter = runP(ps, optionally(peekToken, nil));
        if (delimiter != nil and startswith(delimiter, '$'))
            delimiter = nil;
        if (delimiter != nil)
            delimiter = exactly(delimiter);

        # printf("Parsing: %s (next %s)", pspec, delimiter);

        if (startswith(pspec, '$')) {
            var index = num(substr(pspec, 1)) - 1;
            var type = ARG_TEXT;
            if (index < size(msg.args))
                type = msg.args[index];
            var p = getArgParser(type, delimiter);
            var r = p(ts);
            if (r.failed)
                return r;
            else
                append(args, r.val);
        }
        else {
            var r = exactly(pspec)(ts);
            if (r.failed)
                return r;
        }
    }

    return rOK([args, ts.unconsumed()]);
};

var matchMessage = func (tokens) {
    foreach (var msgTypeList; [hoppie_uplink_messages, hoppie_downlink_messages, uplink_messages, downlink_messages]) {
        foreach (var msgTypeKey; sort(keys(msgTypeList), cmp)) {
            # printf("Trying %s", msgTypeKey);

            var msgType = msgTypeList[msgTypeKey];

            # Skip the message types that just have a single catch-all pattern.
            if (msgType.txt == '$1') continue;

            var result = matchMessageText(msgType, tokens);
            if (result.ok) {
                (args, remainder) = result.val;
                return [msgTypeKey, msgType, args, remainder];
            }
        }
    }
    return nil;
};

var tokenSplit = func (str) {
    str = string.replace(str, '@_@', ' ');
    str = string.replace(str, '@', ' ');
    var words = split(' ', str);
    var tokens = [];
    foreach (var word; words) {
        if (word != '')
            append(tokens, word);
    }
    return tokens;
};

var matchMessages = func (str) {
    var tokens = tokenSplit(str);
    var parts = [];
    while (size(tokens) > 0) {
        var result = matchMessage(tokens);
        if (result == nil)
            return nil;
        (msgTypeKey, msgType, args, tokens) = result;
        append(parts, [msgTypeKey, msgType, args]);
    }
    return parts;
};

var HoppieDriver = {
    new: func (system) {
        var m = BaseDriver.new(system);
        m.parents = [HoppieDriver] ~ m.parents;

        var hoppieNode = props.globals.getNode('/hoppie', 1);

        m.props = {
            downlink: hoppieNode.getNode('downlink', 1),
            uplink: hoppieNode.getNode('uplink', 1),
            status: hoppieNode.getNode('status-text', 1),
            uplinkStatus: hoppieNode.getNode('uplink/status', 1),
        };
        m.listeners = {
            uplink: nil,
            running: nil,
        };
        return m;
    },

    getDriverName: func () { return 'HOPPIE'; },

    isAvailable: func () {
        return
            contains(globals, 'hoppieAcars') and
            (me.props.status.getValue() == 'running');
    },

    start: func () {
        if (me.listeners.uplink != nil) {
            removelistener(me.listeners.status);
            me.listeners.uplink = nil;
        }
        var self = me;
        me.listeners.uplink = setlistener(me.props.uplinkStatus, func { self.receive(); });
    },

    stop: func () {
        if (me.listeners.uplink != nil) {
            removelistener(me.listeners.uplink);
            me.listeners.uplink = nil;
        }
    },

    connect: func (logonStation) {
        var min = me.system.genMIN();
        var packed = me._pack(min, '', 'Y', 'REQUEST LOGON');
        me._send(logonStation, packed);
    },

    disconnect: func () {
        var to = me.system.getCurrentStation();
        if (to == nil or to == '') return; # Not connected
        var min = me.system.genMIN();
        var packed = me._pack(min, '', 'N', 'LOGOFF');
        me._send(me.system.getCurrentStation(), packed);
    },

    send: func (msg) {
        var body = [];
        var to = msg.to or me.system.getCurrentStation();
        foreach (var part; msg.parts) {
            append(body, formatMessagePart(part.type, part.args));
        }
        var ra = msg.getRA();
        var packed = me._pack(msg.min or '', msg.mrn or '', ra or 'N', body);
        var self = me;
        # debug.dump('ABOUT TO SEND:', packed);
        me._send(to, packed, func {
            self.system.markMessageSent(msg.getMID());
        });
    },

    receive: func () {
        var raw = me._rawMessageFromNode(me.props.uplink);
        # ignore non-CPDLC
        if (raw.type != 'cpdlc')
            return;
        var cpdlc = me._parseCPDLC(raw.packet);
        # bail on CPDLC parser error (_parseCPDLC will dump error)
        if (cpdlc == nil)
            return;
        
        # ignore empty messages
        if (typeof(cpdlc.message) != 'vector' or size(cpdlc.message) == 0)
            return;

        # Now handle the actual message.
        var m = cpdlc.message[0];
        var vars = [];

        # debug.dump('CPDLC', raw, cpdlc);
        var msg = Message.new();
        msg.dir = 'up';
        msg.min = cpdlc.min;
        msg.mrn = cpdlc.mrn;
        msg.parts = [];
        msg.from = raw.from;
        msg.to = raw.to;
        msg.dir = 'up';
        msg.valid = 1;
        foreach (var m; cpdlc.message) {
            var rawPart = me._parseCPDLCPart(m);
            var type = me._matchCPDLCMessageType(rawPart[0], rawPart[1]);
            var args = rawPart[1];
            if (type == nil) {
                args = [string.replace(m, "@", " ")];
                if (cpdlc.ra == 'WU')
                    type = 'TXTU-4';
                elsif (cpdlc.ra == 'AN')
                    type = 'TXTU-5';
                elsif (cpdlc.ra == 'R')
                    type = 'TXTU-1';
                else
                    type = 'TXTU-2';
            }
            append(msg.parts, {type: type, args: args});
        }
        # debug.dump('RECEIVED', msg);

        if (size(msg.parts) == 0)
            return nil;

        if (msg.parts[0].type == 'HPPU-1') {
            # LOGON ACCEPTED
            me.system.setLogonAccepted(raw.from);
        }
        elsif (msg.parts[0].type == 'HPPU-3') {
            # LOGOFF
            me.system.setCurrentStation('');
        }
        elsif (msg.parts[0].type == 'HPPU-2') {
            me.system.setNextStation(vars[0]);
            me.system.connect(vars[0]);
        }
        elsif (msg.parts[0].type == 'COMU-9') {
            # CURRENT ATC UNIT
            me.system.setCurrentStation(vars[0]);
        }
        else {
            me.system.receive(msg);
        }
    },

    _parseCPDLCPart: func (txt, dir='up') {
        var words = split(' ', string.replace(txt, '@_@', ' '));
        var parsed = [];
        var i = 0;
        var args = [];
        var a = [];
        var argmode = 0;
        var argnum = 1;
        forindex (var i; words) {
            var word = words[i];
            if (word == '') continue;
            if (argmode) {
                if (substr(word, -1) == '@') {
                    # found terminating '@'
                    append(a, string.replace(word, '@', ''));
                    if (size(a)) {
                        append(args, unwords(a));
                    }
                    a = [];
                    argmode = 0;
                }
                else {
                    append(a, word);
                }
            }
            else {
                if (substr(word, 0, 1) == '@') {
                    # found opening '@'
                    append(parsed, '$' ~ argnum);
                    argnum += 1;
                    if (substr(word, -1) == '@') {
                        # found terminating '@'
                        append(args, substr(word, 1, size(word) - 2));
                    }
                    else {
                        append(a, substr(word, 1));
                        argmode = 1;
                    }
                }
                else {
                    append(parsed, word);
                }
            }
        }
        if (size(a)) {
            append(args, unwords(a));
        }
        var txt = unwords(parsed);
        return [txt, args];
    },

    _matchCPDLCMessageType: func (txt, args, dir='up') {
        var messageLists = ((dir == 'up') ? [hoppie_uplink_messages, uplink_messages] : [hoppie_downlink_messages, downlink_messages]);
        foreach (var messages; messageLists) {
            foreach (var msgKey; keys(messages)) {
                var message = messages[msgKey];
                if (message.txt != txt) {
                    continue;
                }
                var valid = 1;
                forindex (var i; message.args) {
                    var argTy = message.args[i];
                    var argVal = args[i] or '';
                    if (!me._validateArg(argTy, argVal)) {
                        valid = 0;
                        break;
                    }
                }
                if (valid) {
                    return msgKey;
                }
            }
        }
        return nil;
    },

    _validateArg: func (argTy, argVal) {
        var spacesRemoved = string.replace(argVal, ' ', '');
        if (argTy == ARG_FL_ALT) {
            return string.match(spacesRemoved, 'FL[0-9][0-9][0-9]') or
                   string.match(spacesRemoved, 'FL[0-9][0-9]') or

                   string.match(spacesRemoved, '[0-9][0-9][0-9][0-9]FT');
                   string.match(spacesRemoved, '[0-9][0-9][0-9][0-9][0-9]FT') or

                   string.match(spacesRemoved, '[0-9][0-9][0-9][0-9]FEET') or
                   string.match(spacesRemoved, '[0-9][0-9][0-9][0-9][0-9]FEET') or

                   string.match(spacesRemoved, '[0-9][0-9][0-9][0-9]') or
                   string.match(spacesRemoved, '[0-9][0-9][0-9][0-9][0-9]') or

                   string.match(spacesRemoved, '[0-9][0-9][0-9]M');
                   string.match(spacesRemoved, '[0-9][0-9][0-9][0-9]M');
                   string.match(spacesRemoved, '[0-9][0-9][0-9][0-9][0-9]M') or

                   string.match(spacesRemoved, '[0-9][0-9][0-9]METERS') or
                   string.match(spacesRemoved, '[0-9][0-9][0-9][0-9]METERS') or
                   string.match(spacesRemoved, '[0-9][0-9][0-9][0-9][0-9]METERS');
        }
        elsif (argTy == ARG_SPEED) {
            return string.match(spacesRemoved, '[0-9][0-9][0-9]KTS') or
                   string.match(spacesRemoved, '[0-9][0-9]KTS') or
                   string.match(spacesRemoved, '[0-9][0-9][0-9]KNOTS') or
                   string.match(spacesRemoved, '[0-9][0-9]KNOTS') or
                   string.match(spacesRemoved, '[0-9][0-9][0-9]KMH') or
                   string.match(spacesRemoved, '[0-9][0-9]KMH') or
                   string.match(spacesRemoved, '[0-9][0-9][0-9]KPH') or
                   string.match(spacesRemoved, '[0-9][0-9]KPH') or
                   string.match(spacesRemoved, 'MACH.[0-9][0-9]') or
                   string.match(spacesRemoved, 'MACH.[0-9]') or
                   string.match(spacesRemoved, 'M.[0-9][0-9]') or
                   string.match(spacesRemoved, 'M.[0-9]') or
                   string.match(spacesRemoved, 'MACH0[0-9][0-9]') or
                   string.match(spacesRemoved, 'MACH[0-9][0-9]') or
                   string.match(spacesRemoved, 'MACH[0-9]') or
                   string.match(spacesRemoved, 'M0[0-9][0-9]') or
                   string.match(spacesRemoved, 'M[0-9][0-9]') or
                   string.match(spacesRemoved, 'M[0-9]');
        }
        else {
            # We skip validating any other argument types; the only messages
            # that are potentially ambiguous are those that can take either a
            # speed or an altitude/flight level, so these are the only types
            # we need to distinguish here.
            return 1;
        }
    },

    _send: func (to, packed, then=nil) {
        # debug.dump('SENDING', to, packed);
        globals.hoppieAcars.send(to, 'cpdlc', packed, then);
    },

    _pack: func (min, mrn, ra, message) {
        if (typeof(message) == 'vector') {
            message = string.join('/', message);
        }
        if (ra == '')
            ra = 'N';
        return string.join('/', ['', 'data2', min, mrn, ra, message]);
    },

    _rawMessageFromNode: func(node) {
        var msg = {
                from: node.getValue('from'),
                to: node.getValue('to'),
                type: node.getValue('type'),
                packet: node.getValue('packet'),
                status: node.getValue('status'),
                serial: node.getValue('serial'),
                timestamp: node.getValue('timestamp'),
                timestamp4: substr(node.getValue('timestamp') or '?????????T??????', 9, 4),
            };
        return msg;
    },


    _parseCPDLC: func (str) {
        # /data2/654/3/NE/LOGON ACCEPTED
        var result = split('/', string.uc(str));
        if (result[0] != '') {
            debug.dump('CPDLC PARSER ERROR 10: expected leading slash in ' ~ str);
            return nil;
        }
        if (result[1] != 'DATA2') {
            debug.dump('CPDLC PARSER ERROR 11: expected `data2` in ' ~ str);
            return nil;
        }
        var min = result[2];
        var mrn = result[3];
        var ra = result[4];
        var message = subvec(result, 5);
        return {
            min: min,
            mrn: mrn,
            ra: ra,
            message: message,
        }
    },

};

var startswith = func (haystack, needle) {
    return (left(haystack, size(needle)) == needle);
};

var endswith = func (haystack, needle) {
    return (right(haystack, size(needle)) == needle);
};

var testMessages = [
    "CURRENT ATC UNIT@_@EGPX",
    "LOGON ACCEPTED",
    "REQUEST LOGON",
    "HANDOVER @EGPX",
    "MAINTAIN @210 KTS",
    "MAINTAIN @FL100",
    "MAINTAIN @M.75",
    "CONTACT @LONDON CONTROL@ @127.100",
    "ROGER",
    "CLIMB TO @FL360",
    "DESCEND TO @FL110",
    "PROCEED DIRECT TO @HELEN@ DESCEND TO @FL200",
    "PROCEED DIRECT TO @BUB",
    "SQUAWK @1000",
    "FLIGHT PLAN NOT HELD",
    "INCREASE SPEED TO @250 KTS",

    "CURRENT ATC UNIT@_@EGPX@_@SCOTTISH CONTROL",
];

foreach (var msg; testMessages) {
    printf("%s", msg);
    var result = matchMessages(msg);
    if (result == nil) {
        debug.dump(nil);
    }
    else {
        foreach (var part; result) {
            debug.dump(part[0], part[2]);
        }
    }
}
