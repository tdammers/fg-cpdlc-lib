var rOK = func (val) {
    return {
        failed: 0,
        ok: 1,
        val: val,
    };
};

var rFail = func (msg) {
    return {
        failed: 1,
        ok: 0,
        error: msg,
    };
};

var rBind = func (r, f) {
    if (r.failed)
        return r;
    else
        return f(r.val);
};

var rFailToDie = func (r) {
    if (r.failed)
        die(r.error);
    else
        return r.val;
};

var rMap = func (f, r) {
    if (r.ok)
        return rOK(f(r.val));
    else
        return r;
};

var pBind = func (p, f) {
    return func (s) {
        var r = p(s);
        if (r.failed)
            return r;
        else
            return f(r.val)(s);
    };
};

var pOK = func (val) {
    return func (s) {
        return rOK(val);
    };
};

var pFail = func (msg) {
    return func (s) {
        return rFail(msg);
    };
};

var pMap = func (f, p) {
    return func (s) {
        rMap(f, p(s));
    };
};

var runP = func (s, p) {
    return rFailToDie(p(s));
};

var TokenStream = {
    new: func (tokens) {
        var m = {
            parents: [TokenStream],
            tokens: tokens,
            numTokens: size(tokens),
            readpos: 0,
        };
        return m;
    },

    eof: func {
        return (me.readpos >= me.numTokens);
    },

    peek: func (n=0) {
        if (me.readpos + n >= me.numTokens)
            return rFail('Unexpected end of input');
        else
            return rOK(me.tokens[me.readpos + n]);
    },

    consume: func {
        if (me.eof())
            return rFail('Unexpected end of input');
        me.readpos += 1;
        return rOK(me.tokens[me.readpos - 1]);
    },

    consumeAll: func {
        var result = subvec(me.tokens, me.readpos);
        me.readpos = me.numTokens;
        return rOK(result);
    },

    unconsumed: func {
        return subvec(me.tokens, me.readpos);
    },

};

anyToken = func (s) {
    return s.consume();
};

peekToken = func (s) {
    return s.peek();
};

var eof = func (s) {
    if (s.eof())
        return rOK(nil);
    else
        return rFail('Expected EOF');
};

var satisfy = func (cond, expected=nil) {
    return
        pBind(peekToken, func (token) {
            if (cond(token)) {
                return anyToken;
            }
            elsif (expected == nil)
                return pFail(sprintf('Unexpected %s', token));
            else
                return pFail(sprintf('Unexpected %s, expected %s', token, expected));
        });
};

var oneOf = func (items) {
    return satisfy(func (token) { return contains(items, token); });
};

var exactly = func (item) {
    return satisfy(func (token) { return token == item; }, item);
};

var tryParse = func (p, catch=nil) {
    return func (s) {
        var readposBuf = s.readpos;
        var result = p(s);
        if (result.failed) {
            # parse failed: roll back
            s.readpos = readposBuf;
            if (catch == nil)
                return result;
            else
                return catch(s);
        }
        else {
            return result;
        }
    }
};

var optionally = func (p, def=nil) {
    return tryParse(p, pOK(def));
};


var manyTill = func (p, stop) {
    return func (s) {
        var result = [];
        var val = nil;
        while (1) {
            var r = tryParse(stop)(s);
            if (r.ok) {
                return rOK(result);
            }
            var inner = p(s);
            if (inner.failed) {
                return inner;
            }
            else {
                append(result, inner.val);
            }
        }
        return rFail('This point cannot be reached');
    }
};

var many = func (p) {
    return func (s) {
        var result = [];
        var val = nil;
        while (!s.eof()) {
            var inner = tryParse(p)(s);
            if (inner.failed)
                return rOK(result);
            else
                append(result, inner.val);
        }
        return rOK(result);
    }
};

var choice = func (ps, expected=nil) {
    return func (s) {
        foreach (var p; ps) {
            var r = tryParse(p)(s);
            if (r.ok)
                return r;
        }
        return pFail('Choice failed');
    }
};
