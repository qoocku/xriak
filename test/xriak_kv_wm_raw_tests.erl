-module (xriak_kv_wm_raw_tests).
-author ("Damian T. Dobroczy\\'nski <qoocku@gmail.com>").

-compile (export_all).

-include_lib ("eunit/include/eunit.hrl").

-record (ctx, {riak_setup, riak}).

setup () ->
  RS = test_riak_setup:setup([]),
  %% install xriak_kv_wm_raw at the specific url
  DT = [{["xriak"], xriak_kv_wm_raw, [{prefix, "xriak"}, {riak, local}]},
        {["xriak", bucket], xriak_kv_wm_raw, [{prefix, "xriak"}, {riak, local}]},
        {["xriak", bucket, key], xriak_kv_wm_raw, [{prefix, "xriak"}, {riak, local}]},
        {["xriak", bucket, key, "*"], xriak_kv_wm_raw, [{prefix, "xriak"}, {riak, local}]}],
  [begin
     ok = rpc:call(RS, webmachine_router, remove_route, [Route]),
     ok = rpc:call(RS, webmachine_router, add_route, [Route])
   end || Route <- DT],
  {ok, LC} = riak:client_connect(RS),
  #ctx{riak_setup = RS, riak = LC}.

tear_down (#ctx{riak_setup = S}) ->
  test_riak_setup:tear_down(S).

-define (TESTS, [test_get, test_put]).

all_test_ () ->
  {foreach,
   fun setup/0, fun tear_down/1,
   [fun (Ctx) ->        
        {atom_to_list(Fun),
         fun () -> ?MODULE:Fun(Ctx) end}          
    end || Fun <- ?TESTS]}.

%%% ================== unit tests ============================

test_get (Ctx) ->
  %% http client
  ok = inets:start(),
  lists:foldl(fun (Erl, N) ->
                  test_get_one_object(Ctx, Erl, 
                                      lists:flatten(mochijson2:encode(Erl)),
                                      list_to_binary(integer_to_list(N))),
                  N+1
              end,
              0,
              [[1,2,3],
               {struct, [{a, 1}, {b, 2}, {c, 3}]},
               [1,2,3,4,5,6,7,8,9]]),
  inets:stop().

test_get_one_object(#ctx{riak = Riak}, Obj, JSON, Id) ->
  O        = riak_object:new(<<"xriak_tests">>, Id, Obj),
  ok       = Riak:put(O),
  {ok, {Status, Headers, Body}} = 
    httpc:request(get, {"http://localhost:8091/xriak/xriak_tests/" ++ 
                          binary_to_list(Id),
                        [{"accept", "application/json"}]}, [], []),
  ?assertMatch({_, 200, "OK"}, Status),
  ?assert(lists:member({"content-type", "application/json"}, Headers)),
  ?assertEqual(Body, JSON).

test_put (Ctx) ->
  %% http client
  ok = inets:start(),
  lists:foldl(fun (Erl, N) ->
                  test_put_one_object(Ctx, 
                                      lists:flatten(mochijson2:encode(Erl)),
                                      list_to_binary(integer_to_list(N))),
                  N+1
              end,
              0,
              [[1,2,3],
               {struct, [{a, 1}, {b, 2}, {c, 3}]},
               [1,2,3,4,5,6,7,8,9]]),
  inets:stop().
  

test_put_one_object(#ctx{riak = _Riak}, JSON, Id) ->
  {ok, {Status, _Headers, _Body}} = 
    httpc:request(put, {"http://localhost:8091/xriak/xriak_tests/" ++ 
                          binary_to_list(Id),
                        [],
                        "application/json",
                        JSON}, [], []),
  ?assertMatch({_, 204, _}, Status),
  %% read the object
  {ok, {RStatus, Headers, Body}} = 
    httpc:request(get, {"http://localhost:8091/xriak/xriak_tests/" ++ 
                          binary_to_list(Id),
                        [{"accept", "application/json"}]}, [], []),
  ?assertMatch({_, 200, "OK"}, RStatus),
  ?assert(lists:member({"content-type", "application/json"}, Headers)),
  ?assertEqual(Body, JSON).
