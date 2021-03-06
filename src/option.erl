-module(option).
-export([map/2,
         flat_map/2,
         defined/1,
         filter/2,
         foreach/2,
         default/2,
         custom/2]).

map(F, {ok, Value}) ->
    {ok, F(Value)};
map(_, None) ->
    None.

flat_map(F, {ok, Value}) ->
    F(Value);
flat_map(_, None) ->
    None.

defined({ok, _}) ->
    true;
defined(_) ->
    false.

filter(P, {ok, Value}) ->
    case P(Value) of
        true -> {ok, Value};
        _ -> empty
    end;
filter(_, None) -> None.

foreach(F, {ok, Value}) ->
    F(Value),
    {ok, Value};
foreach(_, None) ->
    None.

default(_, {ok, Value}) ->
    Value;
default(Default, _) ->
    Default.

custom(CustomOk, {CustomOk, Value}) ->
    {ok, Value};
custom(_, X) -> X.
