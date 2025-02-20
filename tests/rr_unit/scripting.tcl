start_server {tags {"scripting"}} {
    test {EVAL - Does Lua interpreter replies to our requests?} {
        r eval {return 'hello'} 0
    } {hello}

    test {EVAL - Lua integer -> Redis protocol type conversion} {
        r eval {return 100.5} 0
    } {100}

    test {EVAL - Lua string -> Redis protocol type conversion} {
        r eval {return 'hello world'} 0
    } {hello world}

    test {EVAL - Lua true boolean -> Redis protocol type conversion} {
        r eval {return true} 0
    } {1}

    test {EVAL - Lua false boolean -> Redis protocol type conversion} {
        r eval {return false} 0
    } {}

    test {EVAL - Lua status code reply -> Redis protocol type conversion} {
        r eval {return {ok='fine'}} 0
    } {fine}

    test {EVAL - Lua error reply -> Redis protocol type conversion} {
        catch {
            r eval {return {err='this is an error'}} 0
        } e
        set _ $e
    } {this is an error}

    test {EVAL - Lua table -> Redis protocol type conversion} {
        r eval {return {1,2,3,'ciao',{1,2}}} 0
    } {1 2 3 ciao {1 2}}

    test {EVAL - Are the KEYS and ARGV arrays populated correctly?} {
        r eval {return {KEYS[1],KEYS[2],ARGV[1],ARGV[2]}} 2 a b c d
    } {a b c d}

    test {EVAL - is Lua able to call Redis API?} {
        r set mykey myval
        after 200
        r eval {return redis.call('get',KEYS[1])} 1 mykey
    } {myval}

    test {SCRIPT LOAD - Tendis won't save script came from eval cmd} {
        r script load {return redis.call('get',KEYS[1])}
    } {fd758d1589d044dd850a6f05d52f2eefd27f033f}

    test {EVALSHA - Can we call a SHA1 if already defined?} {
        r evalsha fd758d1589d044dd850a6f05d52f2eefd27f033f 1 mykey
    } {myval}

    test {EVALSHA - Can we call a SHA1 in uppercase?} {
        r evalsha FD758D1589D044DD850A6F05D52F2EEFD27F033F 1 mykey
    } {myval}

    test {EVALSHA - Do we get an error on invalid SHA1?} {
        catch {r evalsha NotValidShaSUM 0} e
        set _ $e
    } {NOSCRIPT*}

    test {EVALSHA - Do we get an error on non defined SHA1?} {
        catch {r evalsha ffd632c7d33e571e9f24556ebed26c3479a87130 0} e
        set _ $e
    } {NOSCRIPT*}

    test {EVAL - Redis integer -> Lua type conversion} {
        r eval {
            local foo = redis.pcall('incr','x')
            return {type(foo),foo}
        } 0
    } {number 1}

    test {EVAL - Redis bulk -> Lua type conversion} {
        r set mykey myval
        r eval {
            local foo = redis.pcall('get','mykey')
            return {type(foo),foo}
        } 0
    } {string myval}

    test {EVAL - Redis multi bulk -> Lua type conversion} {
        r del mylist
        r rpush mylist a
        r rpush mylist b
        r rpush mylist c
        r eval {
            local foo = redis.pcall('lrange','mylist',0,-1)
            return {type(foo),foo[1],foo[2],foo[3],# foo}
        } 0
    } {table a b c 3}

    test {EVAL - Redis status reply -> Lua type conversion} {
        r eval {
            local foo = redis.pcall('set','mykey','myval')
            return {type(foo),foo['ok']}
        } 0
    } {table OK}

    test {EVAL - Redis error reply -> Lua type conversion} {
        r set mykey myval
        r eval {
            local foo = redis.pcall('incr','mykey')
            return {type(foo),foo['err']}
        } 0
    } {table {ERR:7,msg:value is not an integer or out of range}};

    test {EVAL - Redis stop when error -> Lua commands atomic} {
        r set mykey myval
        catch {
            r eval "redis.call('set','mykey', 'value1'); redis.call('incr','mykey'); redis.call('set','mykey', 'value2')" 0
        } e
        r get mykey
    } {value1};

    test {EVAL - Redis continue when error -> Lua commands atomic} {
        r set mykey myval
        catch {
            r eval "redis.pcall('set','mykey', 'value1'); redis.pcall('incr','mykey'); redis.pcall('set','mykey', 'value2')" 0
        } e
        r get mykey
    } {value2};

    test {EVAL - Redis nil bulk reply -> Lua type conversion} {
        r del mykey
        r eval {
            local foo = redis.pcall('get','mykey')
            return {type(foo),foo == false}
        } 0
    } {boolean 1}

    test {EVAL - Is the Lua client using the currently selected DB?} {
        r set mykey "this is DB 9"
        r select 10
        r set mykey "this is DB 10"
        r eval {return redis.pcall('get','mykey')} 0
    } {this is DB 10}

    test {EVAL - SELECT inside Lua should not affect the caller} {
        # here we DB 10 is selected
        r set mykey "original value"
        r eval {return redis.pcall('select','9')} 0
        set res [r get mykey]
        r select 9
        set res
    } {original value}

    if 0 {
        test {EVAL - Script can't run more than configured time limit} {
            r config set lua-time-limit 1
            catch {
                r eval {
                    local i = 0
                    while true do i=i+1 end
                } 0
            } e
            set _ $e
        } {*execution time*}
    }

    test {EVAL - Scripts can't run certain commands} {
        set e {}
        catch {r eval {return redis.pcall('spop','x')} 0} e
        set e
    } {*not allowed*}

    test {EVAL - Scripts can't run certain commands} {
        set e {}
        catch {
            r eval "redis.pcall('scan','0'); return redis.pcall('set','x','ciao')" 0
        } e
        set e
    } {*not allowed after*}

    test {EVAL - No arguments to redis.call/pcall is considered an error} {
        set e {}
        catch {r eval {return redis.call()} 0} e
        set e
    } {*one argument*}

    test {EVAL - redis.call variant raises a Lua error on Redis cmd error (1)} {
        set e {}
        catch {
            r eval "redis.call('nosuchcommand')" 0
        } e
        set e
    } {*unknown command*}

    test {EVAL - redis.call variant raises a Lua error on Redis cmd error (1)} {
        set e {}
        catch {
            r eval "redis.call('get','a','b','c')" 0
        } e
        set e
    } {*wrong number of arguments*}

    test {EVAL - redis.call variant raises a Lua error on Redis cmd error (1)} {
        set e {}
        r set foo bar
        catch {
            r eval {redis.call('lpush',KEYS[1],'val')} 1 foo
        } e
        set e
    } {*against a key*}

    test {SCRIPTING FLUSH - is able to clear the scripts cache?} {
        r set mykey myval
        set v [r evalsha fd758d1589d044dd850a6f05d52f2eefd27f033f 1 mykey]
        assert_equal $v myval
        set e ""
        r script flush
        catch {r evalsha fd758d1589d044dd850a6f05d52f2eefd27f033f 1 mykey} e
        set e
    } {NOSCRIPT*}

    test {SCRIPT EXISTS - can detect already defined scripts?} {
        r eval "return 1+1" 0
        r script load "return 1+1"
        r script exists a27e7e8a43702b7046d4f6a7ccf5b60cef6b9bd9 a27e7e8a43702b7046d4f6a7ccf5b60cef6b9bda
    } {1 0}

    test {SCRIPT LOAD - is able to register scripts in the scripting cache} {
        list \
            [r script load "return 'loaded'"] \
            [r evalsha b534286061d4b9e4026607613b95c06c06015ae8 0]
    } {b534286061d4b9e4026607613b95c06c06015ae8 loaded}

    test "In the context of Lua the output of random commands gets ordered" {
        r del myset
        r sadd myset a b c d e f g h i l m n o p q r s t u v z aa aaa azz
        r eval {return redis.call('smembers',KEYS[1])} 1 myset
    } {a aa aaa azz b c d e f g h i l m n o p q r s t u v z}

    test "SORT is normally not alpha re-ordered for the scripting engine" {
        r del myset
        r sadd myset 1 2 3 4 10
        r eval {return redis.call('sort',KEYS[1],'desc')} 1 myset
    } {10 4 3 2 1}

    test "SORT BY <constant> output gets ordered for scripting" {
        r del myset
        r sadd myset a b c d e f g h i l m n o p q r s t u v z aa aaa azz
        r eval {return redis.call('sort',KEYS[1],'by','_')} 1 myset
    } {a aa aaa azz b c d e f g h i l m n o p q r s t u v z}

    #test "SORT BY <constant> with GET gets ordered for scripting" {
    #    r del myset
    #    r sadd myset a b c
    #    r eval {return redis.call('sort',KEYS[1],'by','_','get','#','get','_:*')} 1 myset
    #} {a {} b {} c {}}

    test "redis.sha1hex() implementation" {
        list [r eval {return redis.sha1hex('')} 0] \
             [r eval {return redis.sha1hex('Pizza & Mandolino')} 0]
    } {da39a3ee5e6b4b0d3255bfef95601890afd80709 74822d82031af7493c20eefa13bd07ec4fada82f}

    test {Globals protection reading an undeclared global variable} {
        catch {r eval {return a} 0} e
        set e
    } {*ERR*attempted to access nonexistent global*}

    test {Globals protection setting an undeclared global*} {
        catch {r eval {a=10} 0} e
        set e
    } {*ERR*attempted to create global*}

    test {Test an example script DECR_IF_GT} {
        set decr_if_gt {
            local current

            current = redis.call('get',KEYS[1])
            if not current then return nil end
            if current > ARGV[1] then
                return redis.call('decr',KEYS[1])
            else
                return redis.call('get',KEYS[1])
            end
        }
        r set foo 5
        set res {}
        lappend res [r eval $decr_if_gt 1 foo 2]
        lappend res [r eval $decr_if_gt 1 foo 2]
        lappend res [r eval $decr_if_gt 1 foo 2]
        lappend res [r eval $decr_if_gt 1 foo 2]
        lappend res [r eval $decr_if_gt 1 foo 2]
        set res
    } {4 3 2 2 2}

    test {Scripting engine resets PRNG at every script execution} {
        set rand1 [r eval {return tostring(math.random())} 0]
        set rand2 [r eval {return tostring(math.random())} 0]
        assert_equal $rand1 $rand2
    }

    test {Scripting engine PRNG can be seeded correctly} {
        set rand1 [r eval {
            math.randomseed(ARGV[1]); return tostring(math.random())
        } 0 10]
        set rand2 [r eval {
            math.randomseed(ARGV[1]); return tostring(math.random())
        } 0 10]
        set rand3 [r eval {
            math.randomseed(ARGV[1]); return tostring(math.random())
        } 0 20]
        assert_equal $rand1 $rand2
        assert {$rand2 ne $rand3}
    }

    test {EVAL does not leak in the Lua stack} {
        r set x 0
        # Use a non blocking client to speedup the loop.
        set rd [redis_deferring_client]
        for {set j 0} {$j < 10000} {incr j} {
            $rd eval {return redis.call("incr",KEYS[1])} 1 x
        }
        for {set j 0} {$j < 10000} {incr j} {
            $rd read
        }
        assert {[s used_memory_lua] < 1024*100}
        $rd close
        r get x
    } {10000}

    #test {EVAL processes writes from AOF in read-only slaves} {
    #    r flushall
    #    r config set appendonly yes
    #    r eval {redis.call("set",KEYS[1],"100")} 1 foo
    #    r eval {redis.call("incr",KEYS[1])} 1 foo
    #    r eval {redis.call("incr",KEYS[1])} 1 foo
    #    wait_for_condition 50 100 {
    #        [s aof_rewrite_in_progress] == 0
    #    } else {
    #        fail "AOF rewrite can't complete after CONFIG SET appendonly yes."
    #    }
    #    r config set slave-read-only yes
    #    r slaveof 127.0.0.1 0
    #    r debug loadaof
    #    set res [r get foo]
    #    r slaveof no one
    #    set res
    #} {102}

    test {We can call scripts rewriting client->argv from Lua} {
        r del myset
        r sadd myset a b c
        r mset a 1 b 2 c 3 d 4
        assert {[r spop myset] ne {}}
        assert {[r spop myset] ne {}}
        assert {[r spop myset] ne {}}
        assert {[r mget a b c d] eq {1 2 3 4}}
        assert {[r spop myset] eq {}}
    }

    test {Call Redis command with many args from Lua (issue #1764)} {
        r eval {
            local i
            local x={}
            redis.call('del','mylist')
            for i=1,100 do
                table.insert(x,i)
            end
            redis.call('rpush','mylist',unpack(x))
            return redis.call('lrange','mylist',0,-1)
        } 0
    } {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100}

    test {Number conversion precision test (issue #1118)} {
        r eval {
              local value = 9007199254740991
              redis.call("set","foo",value)
              return redis.call("get","foo")
        } 0
    } {9007199254740991}

    test {String containing number precision test (regression of issue #1118)} {
        r eval {
            redis.call("set", "key", "12039611435714932082")
            return redis.call("get", "key")
        } 0
    } {12039611435714932082}

    test {Verify negative arg count is error instead of crash (issue #1842)} {
        catch { r eval { return "hello" } -12 } e
        set e
    } {ERR Number of keys can't be negative}

    test {Correct handling of reused argv (issue #1939)} {
        r eval {
              for i = 0, 10 do
                  redis.call('SET', 'a', '1')
                  redis.call('MGET', 'a', 'b', 'c')
                  redis.call('EXPIRE', 'a', 0)
                  redis.call('GET', 'a')
                  redis.call('MGET', 'a', 'b', 'c')
              end
        } 0
    }

    test {cjson encode} {
        r eval {return cjson.encode({1, 2})} 0
    } {[1,2]}

    test {cjson decode} {
        r eval {return cjson.decode("[1,2]")} 0
    } {1 2}

    test {cmsgpack} {
        r eval {local p=cmsgpack.pack({2,3}); local d=cmsgpack.unpack(p); return d} 0
    } {2 3}

    test {struct} {
        r eval {local p=struct.pack("ii",2,4); local d1,d2=struct.unpack("ii",p); return {d1,d2}} 0
    } {2 4}
}

# Start a new server since the last test in this stanza will kill the
# instance at all.
start_server {tags {"scripting"}} {
    test {Timedout read-only scripts can be killed by SCRIPT KILL} {
        set rd [redis_deferring_client]
        r config set lua-time-limit 10
        $rd eval {while true do end} 0
        after 200
        catch {r ping} e
        assert_match {PONG} $e
        r script kill
        after 200 ; # Give some time to Lua to call the hook again...
        assert_equal [r ping] "PONG"
    }

    test {Timedout script link is still usable after Lua returns} {
        r config set lua-time-limit 10
        r eval {for i=1,100000 do redis.call('ping') end return 'ok'} 0
        r ping
    } {PONG}

    test {Timedout scripts that modified data can't be killed by SCRIPT KILL} {
        set rd [redis_deferring_client]
        r config set lua-time-limit 10
        $rd eval {redis.call('set',KEYS[1],'y'); while true do end} 1 x
        after 200
        catch {r ping} e
        assert_match {PONG} $e
        catch {r script kill} e
        #assert_match {UNKILLABLE*} $e
        assert_match {OK} $e
        catch {r ping} e
        assert_match {PONG} $e
    }

    # Note: keep this test at the end of this server stanza because it
    # kills the server.
    test {SHUTDOWN NOSAVE can kill a timedout script anyway} {
        # The server sould be still unresponding to normal commands.
        catch {r ping} e
        assert_match {PONG} $e
        catch {r shutdown nosave}
        after 15000
        # Make sure the server was killed
        catch {set rd [redis_deferring_client]} e
        assert_match {*connection refused*} $e
    }
}

start_server {tags {"scripting repl"}} {
    start_server {} {
        test {Before the slave connects we issue two EVAL commands} {
            # One with an error, but still executing a command.
            # SHA is: 67164fc43fa971f76fd1aaeeaf60c1c178d25876
            catch {
                r script load {redis.call('incr',KEYS[1]); redis.call('nonexisting')}
                r eval {redis.call('incr',KEYS[1]); redis.call('nonexisting')} 1 x
            }
            # One command is correct:
            # SHA is: 6f5ade10a69975e903c6d07b10ea44c6382381a5
            r script load {return redis.call('incr',KEYS[1])}
            r eval {return redis.call('incr',KEYS[1])} 1 x
        } {2}

        test {Connect a slave to the main instance} {
            r -1 slaveof [srv 0 host] [srv 0 port]
            wait_for_condition 50 100 {
                [s -1 role] eq {slave} &&
                [string match {*master_link_status:up*} [r -1 info replication]]
            } else {
                fail "Can't turn the instance into a slave"
            }
        }

        test {Now use EVALSHA against the master, with both SHAs} {
            # The server should replicate successful and unsuccessful
            # commands as EVAL instead of EVALSHA.
            catch {
                r evalsha 67164fc43fa971f76fd1aaeeaf60c1c178d25876 1 x
            }
            r evalsha 6f5ade10a69975e903c6d07b10ea44c6382381a5 1 x
        } {4}

        test {If EVALSHA was replicated as EVAL, 'x' should be '4'} {
            wait_for_condition 50 100 {
                [r -1 get x] eq {4}
            } else {
                fail "Expected 4 in x, but value is '[r -1 get x]'"
            }
        }

        # brpop not supported!
        #test {Replication of script multiple pushes to list with BLPOP} {
        #    set rd [redis_deferring_client]
        #    $rd brpop a 0
        #    r eval {
        #        redis.call("lpush",KEYS[1],"1");
        #        redis.call("lpush",KEYS[1],"2");
        #    } 1 a
        #    set res [$rd read]
        #    $rd close
        #    wait_for_condition 50 100 {
        #        [r -1 lrange a 0 -1] eq [r lrange a 0 -1]
        #    } else {
        #        fail "Expected list 'a' in slave and master to be the same, but they are respectively '[r -1 lrange a 0 -1]' and '[r lrange a 0 -1]'"
        #    }
        #    set res
        #} {a 1}

        #test {EVALSHA replication when first call is readonly} {
        #    r del x
        #    r eval {if tonumber(ARGV[1]) > 0 then redis.call('incr', KEYS[1]) end} 1 x 0
        #    r evalsha 6e0e2745aa546d0b50b801a20983b70710aef3ce 1 x 0
        #    r evalsha 6e0e2745aa546d0b50b801a20983b70710aef3ce 1 x 1
        #    wait_for_condition 50 100 {
        #        [r -1 get x] eq {1}
        #    } else {
        #        fail "Expected 1 in x, but value is '[r -1 get x]'"
        #    }
        #}

        test {Lua scripts using SELECT are replicated correctly} {
            r eval {
                redis.call("set","foo1","bar1")
                redis.call("select","10")
                redis.call("incr","x")
                redis.call("select","11")
                redis.call("incr","z")
            } 0
            r eval {
                redis.call("set","foo1","bar1")
                redis.call("select","10")
                redis.call("incr","x")
                redis.call("select","11")
                redis.call("incr","z")
            } 0
            wait_for_condition 50 100 {
                [r -1 debug digest] eq [r debug digest]
            } else {
                fail "Master-Slave desync after Lua script using SELECT."
            }
        }
    }
}
