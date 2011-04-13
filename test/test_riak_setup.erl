%%% @doc Setup for testing modules in Riak.

-module (test_riak_setup).

-export ([setup/1,
          tear_down/1]).

setup (DepsToInclude) ->
  {ok, [Cfg]} = file:consult(filename:join([filename:dirname(code:which(?MODULE)),
                                            "..", "test", "test_riak.config"])),
  RiakCookie  = proplists:get_value(riak_cookie, Cfg, riak),
  RiakNode    = proplists:get_value(riak_node, Cfg, 'dev1@127.0.0.1'),
  RiakInstall = proplists:get_value(riak_install, Cfg),
  true        = is_list(RiakInstall),  
  % inhale the Riak instance code paths to have an access to the Riak's' modules
  lists:foreach(fun (Path) ->
                  code:add_pathz(filename:join([Path, "ebin"]))
                end, filelib:wildcard(filename:join([RiakInstall, "lib", "*"]))),  
  {ok, _} = net_kernel:start(['riak_tests@127.0.0.1', longnames]),
  erlang:set_cookie(node(), RiakCookie),
  pong = net_adm:ping(RiakNode),
  % inform the Riak instance about gardens code path 
  MyCodePath   = filename:dirname(code:which(?MODULE)),
  DepsDir      = filename:join([MyCodePath, "..", "deps"]),
  DepsCodePath = [filename:join([DepsDir, I, "ebin"]) || I <- DepsToInclude],
  lists:foreach(fun (Path) ->
                    case lists:member(Path, rpc:call(RiakNode, code, get_path, [])) of
                      true  -> ok;
                      false -> true = rpc:call(RiakNode, code, add_pathz, [Path])
                    end
                end, [MyCodePath] ++ DepsCodePath),
  % reload my modules on the Riak node
  lists:foreach(fun (BeamFile) ->
                    Beam = list_to_atom(filename:rootname(filename:basename(BeamFile))),
                    true = rpc:call(RiakNode, code, soft_purge, [Beam]),
                    {module, Beam} = rpc:call(RiakNode, code, load_file, [Beam])
                end, filelib:wildcard(filename:join([MyCodePath, "*.beam"]))),
  RiakNode.

tear_down (_RiakNode) ->
  net_kernel:stop().


