-module(riaql).
-export([q/1,q/2,q/3]).
-export([bucket/1,index/3,index/4]).

q(<<_/bitstring>>=Query) ->
    case riaql_parser:parse(Query) of
        {From, Select} ->
            q(From, Select);
        {From, Select, Where} ->
            q(From, Select, Where)
    end;
q(From) ->
    q(From, <<"*">>).
q(From, Select) ->
    q(From, Select, none).
q(From, Select, Where) ->
    {ok, Client} = riak:local_client(),
    case riaql_mapreduce:mapred(
                                From,
                                [{
                                  map,
                                  {qfun, fun map_key_value/3},
                                  [{select, Select}, {where, Where}],
                                  true
                                 }],
                                 60000
                                ) of
        {ok, Result} -> Result;
        {error, Reason} -> throw(Reason)
    end.

map_key_value({error, notfound}, _, _) ->
    [];
map_key_value(RObj, _KD, [{select, Select}, {where, Where}]) ->
    case (catch mochijson2:decode(riak_object:get_value(RObj))) of
        {'EXIT', _} ->
            [];
        DJson={struct, _} ->
            case Where of
                [{_,_}|_] ->
                    case lists:all(fun({Key, Pred}) ->
                                       where_key(Key, Pred, DJson)
                                   end, Where) of
                        false -> [];
                        true -> make_key_value(RObj, DJson, Select)
                    end;
                _ ->
                    make_key_value(RObj, DJson, Select)
            end;
        _ ->
            []
    end.

make_key_value(RObj, DJson, Select) ->
    [{
      <<
        (riak_object:bucket(RObj))/bitstring,
        <<"/">>/bitstring,
        (riak_object:key(RObj))/bitstring
      >>,
      select_keys(
                  Select,
                  DJson
                 )
     }].

where_key(Key, Pred, {struct, PList}) ->
    case lists:keyfind(Key, 1, PList) of
        false -> false;
        {Key, Value} -> Pred(Value)
    end.

select_keys(<<"*">>, DJson) ->
    DJson;
select_keys(Keys=[{_,_}|_], {struct, PList}) ->
    {struct, lists:foldl(fun({Key, Val}, Acc) ->
        case lists:keyfind(Key, 2, Keys) of
            false -> Acc;
            {NewKey, Key} -> [{NewKey, Val}|Acc]
        end
    end, [], PList)}.

bucket(Bucket) ->
    Bucket.

index(Bucket, Index, Key) ->
    {index, Bucket, Index, Key}.
index(Bucket, Index, StartKey, EndKey) ->
    {index, Bucket, Index, StartKey, EndKey}.
