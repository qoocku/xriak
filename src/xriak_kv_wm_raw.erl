%%%-------------------------------------------------------------------
%%% @author Damian T. Dobroczy\\'nski <qoocku@gmail.com>
%%% @copyright (C) 2011, Damian T. Dobroczy\\'nski <qoocku@gmail.com>
%%% @doc Riak Extension to KV resources managing buckets and objects.
%%%      The main purpose of this module is to implement alternative
%%%      of storing objects in Riak. The idea is to store internally
%%%      as Erlang terms BUT allowing translation of this values onto
%%%      client form given in "content-type" and "accept" headers (the
%%%      first is for putting objects and the latter is for retrieving).
%%% @since 2011-04-12
%%% @end
%%%-------------------------------------------------------------------

-module (xriak_kv_wm_raw).
-author ("Damian T. Dobroczy\\'nski <qoocku@gmail.com>").
-include ("vsn").

%%% Extended "inheritance" is used. See `emixins' application.
-compile ([{parse_transform, mixins_pt}]).
-mixins ([{riak_kv_wm_raw, {exclude, [ping/2]}}]).

%%% these functions will replace the standard `riak_kv_wm_raw'
-export ([content_types_accepted/2,
          content_types_provided/2,
          process_post/2]).

%%% internal functions
-export ([translate_to_external_format/2,
          translate_to_erlang_term/2]).

-include_lib ("eunit/include/eunit.hrl").
-include ("webmachine/include/webmachine.hrl").
-include ("webmachine/include/wm_reqstate.hrl").

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Chooses an translator of Erlang term according to "Content-Type"
%%      header. If no such translator can be found the return value
%%      of `riak_kv_wm_raw:content_types_accepted/2' is returned.
%% @end
%%--------------------------------------------------------------------

-type wm_reqdata      () :: #wm_reqdata{}.
-type translator_list () :: [{string(), atom()}].
-spec content_types_accepted (RD::wm_reqdata(), Ctx0::any()) -> 
                                 {translator_list(), wm_reqdata(), any()}.

content_types_accepted (RD, Ctx0) ->
  case riak_kv_wm_raw:content_types_accepted(RD, Ctx0) of
    Bucket = {[_, accept_bucket_body], _, _} -> 
      Bucket;
    Other = {[{Media, accept_doc_body}], RD, Ctx} ->
      case Media of
        "application/json" ->
          {[{Media, translate_to_erlang_term}], RD, Ctx};
        Other ->
          Other
      end;
    Wrong ->
      Wrong
  end.

%%--------------------------------------------------------------------
%% @doc Chooses an translator of Erlang term according to "Accept"
%%      header. If no such translator can be found the return value
%%      of `riak_kv_wm_raw:content_types_provided/2' is returned.
%% @end
%%--------------------------------------------------------------------

-spec content_types_provided (RD::wm_reqdata(), Ctx0::any()) ->
                                 {translator_list(), wm_reqdata(), any()}.

content_types_provided (RD, Ctx0) ->
  Accept = wrq:get_req_header("accept", RD),
  case Accept of
    "application/json" ->
      {_, RD1, DocCtx} = riak_kv_wm_raw:content_types_provided(RD, Ctx0),
      {[{"application/json", translate_to_external_format}], RD, DocCtx};
    _Other -> 
      riak_kv_wm_raw:content_types_provided(RD, Ctx0)
  end.

%%--------------------------------------------------------------------
%% @doc Processes a post translating the body to an Erlang term 
%%      according to "Content-Type" header. If no such translator can 
%%      be found the `riak_kv_wm_raw:process_post/2' is applied.
%% @end
%%--------------------------------------------------------------------

-spec process_post (RD::wm_reqdata(), Ctx0::any()) ->
                       {boolean, wm_reqdata(), any()}.

process_post (RD, Ctx) ->
  case riak_kv_wm_raw:content_types_accepted(RD, Ctx) of
    Bucket = {[_, accept_bucket_body], _, _} -> 
      Bucket;
    Other = {[{Media, accept_doc_body}], RD, Ctx} ->
      case Media of
        "application/json" ->
          translate_to_erlang_term(RD, Ctx);
        Other ->
          riak_kv_wm_raw:process_post(RD, Ctx)
      end;
    Wrong ->
      Wrong
  end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Translates an Erlang expression into a JSON string.
%% @end
%%--------------------------------------------------------------------

-spec translate_to_external_format (wm_reqdata(), any()) -> {binary(), any(), any()}.                      

translate_to_external_format (RD, Ctx) ->
  {Bin, VClock, Ctx} = riak_kv_wm_raw:produce_doc_body(RD, Ctx),
  ErlTerm            = erlang:binary_to_term(Bin),
  External           = to_external(wrq:get_req_header("accept", RD),
                                   ErlTerm),
  {External, VClock, Ctx}.

-spec to_external (string(), term()) -> iolist().

to_external ("application/json", ErlTerm) ->
  mochijson2:encode(to_list(ErlTerm)).

%%--------------------------------------------------------------------
%% @doc Translates from external format into an Erlang expression.
%%      Unfortunately, being a part of `webmachine' state machine
%%      flow it MUST change the request state internal bodu value. To do
%%      so it uses process dictionary according to the source code of
%%      webmachine's `wrq' and `webmachine_request' modules. So far, I do
%%      not know other delicate workaround.
%% @end
%%--------------------------------------------------------------------

-spec translate_to_erlang_term (wm_reqdata(), any()) -> {boolean(), wm_reqdata(), any()}.

translate_to_erlang_term (RD, Ctx) ->
  Headers= mochiweb_headers:enter("content-type",
                                  "application/x-erlang-binary",
                                  wrq:req_headers(RD)),
  Body   = wrq:req_body(RD),
  CT     = wrq:get_req_header("content-type", RD),
  ErlBin = term_to_binary(to_erlang_term(CT, Body)),
  RD1    = RD#wm_reqdata{req_headers = Headers},
  RD2    = RD1#wm_reqdata{req_body    = ErlBin},
  RS     = get(tmp_reqstate),
  put(tmp_reqstate, RS#wm_reqstate{reqbody = ErlBin}),
  put(req_body, ErlBin),
  ?debugFmt("RBody = ~p~n", [wrq:req_body(RD2)]),
  riak_kv_wm_raw:accept_doc_body(RD2, Ctx).

-spec to_erlang_term (string(), binary() | string()) -> term().

to_erlang_term ("application/json", V) ->
  mochijson2:decode(V).

to_list (L) when is_list(L) ->
  L;
to_list ({gb_tree, T}) ->
  {struct, gb_trees:to_list(T)};
to_list ({gb_set, S}) ->
  gb_sets:to_list(S);
to_list (D) when is_tuple(D) andalso element(1, D) =:= dict ->
  {struct, dict:to_list(D)};
to_list (S) when is_tuple(S) andalso element(1, S) =:= set ->
  sets:to_list(S);
to_list (Other) ->
  Other.


