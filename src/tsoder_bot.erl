-module(tsoder_bot).
-behaviour(gen_server).
-export([start_link/0,
         init/1,
         handle_call/3,
         handle_cast/2,
         terminate/2]).

-include("fart_rating.hrl").
-include("quote_database.hrl").

start_link() ->
    gen_server:start_link({local, tsoder_bot}, ?MODULE, [], []).

init([]) ->
    rand:seed(exs1024,
              {erlang:phash2([node()]),
               erlang:monotonic_time(),
               erlang:unique_integer()}),
    {ok, {}}.

terminate(Reason, State) ->
    error_logger:info_report([{reason, Reason},
                              {state, State}]).

handle_call({message, User, Message}, _, State) ->
    option:default(
      { reply, nomessage, State },
      option:map(
        fun ({Command, Arguments}) ->
                case command_table() of
                    #{ Command := { Action, _ } } ->
                        { reply, Action(User, Arguments), State };
                    _ ->
                        { reply, custom_commands:exec_command(Command, Arguments), State }
                end
        end,
        command_parser:from_string(Message)));
handle_call({join, _}, _, State) ->
    {reply, {message, "I came! HyperNyard"}, State};
handle_call(_, _, State) ->
    {reply, unsupported, State}.

handle_cast(_, State) ->
    error_logger:info_report(unsupported),
    {noreply, State}.

%% Internal %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

command_table() ->
    #{
       "hi"   => { fun hi_command/2, "!hi -- says hi to you" }
     , "help" => { fun help_command/2, "!help [command] -- prints the list of supported commands." }
     , "fart" => { fun fart_command/2, "!fart [rating] -- fart" }
     , "addquote" => { command_auth(
                         ["tsoding", "r3x1m", "bpaf", "everx80"],
                         fun addquote_command/2)
                     , "!addquote <quote> -- add a quote to the quote database"
                     }
     , "quote" => { fun quote_command/2, "!quote [id] -- select a quote from the quote database" }
     , "russify" => { fun russify_command/2, "!russify <western-spy-text> -- russify western spy text" }
     , "addcom" => { command_auth(
                       ["tsoding", "r3x1m"],
                       command_args(
                         "^\\s*(\\w*)\\s*(.+)",
                         fun addcom_command/2))
                   , "!addcom <command-name> <text> -- add custom response command"
                   }
     , "delcom" => { command_auth(
                       ["tsoding", "r3x1m"],
                       fun delcom_command/2)
                   , "!delcom <command-name> -- remove an existing response command"
                   }
     , "bttv" => { fun bttv_command/2
                 , "!bttv -- show all of the available BTTV emotes for the channel"
                 }
     %% TODO(#115): Design a more advanced mechanism for disabling/enabling commands
     %% , "ub"   => { fun ub_command/3, "!ub [term] -- Lookup the term in Urban Dictionary" }
     }.

%% TODO(#109): design a more advanced authentication system for commands
command_auth(AuthorizedUsers, Command) ->
    fun (User, Args) ->
            Authorized = lists:member(User, AuthorizedUsers),
            if
                Authorized -> Command(User, Args);
                true -> string_as_user_response(User, "Nope HyperNyard")
            end
    end.

command_args(RegexpString, Command) ->
    {ok, Regexp} = re:compile(RegexpString),
    fun (User, Message) ->
            case re:run(Message, Regexp, [{capture, all, list}]) of
                {match, [_ | Args]} -> Command(User, Args);
                nomatch -> string_as_user_response(User, "Incorrect command syntax")
            end
    end.

ub_command(User, "") ->
    string_as_user_response(User, "Cannot lookup an empty term");
ub_command(User, Term) ->
    %% TODO(#98): response should include the link to the defintion page
    string_as_user_response(
      User,
      option:default(
        "Could not find the term",
        option:map(
          fun (Definition) ->
                  string:substr(Definition, 1, 200)
          end,
          option:flat_map(
            fun ub_definition:from_http_response/1,
            httpc:request(
              "http://api.urbandictionary.com/v0/define?term="
              ++ http_uri:encode(Term)))))).


hi_command(User, _) ->
    {message, "Hello @" ++ User ++ "!"}.

fart_command(User, "rating") ->
    string_as_user_response(User, fart_rating:as_string());
fart_command(User, _) ->
    fart_rating:bump_counter(User),
    string_as_user_response(User,
                            "don't have intestines to perform the operation.").

addquote_command(User, "") ->
    string_as_user_response(User, "Empty quotes are ignored");
addquote_command(User, Quote) ->
    Id = quote_database:add_quote(Quote, User, erlang:timestamp()),
    string_as_user_response(User, "Added the quote under number " ++ integer_to_list(Id)).

quote_command(User, []) ->
    option:default(
      {message, "No quotes are found"},
      option:map(
        fun (Quote) ->
                string_as_user_response(User,
                                        Quote#quote.quote
                                        ++ " ("
                                        ++ integer_to_list(Quote#quote.id)
                                        ++ ")")
        end,
        quote_database:random()));
quote_command(User, Arg) ->
    case string:to_integer(Arg) of
        {Id, []} -> option:default(
                      nomessage,
                      option:map(
                        fun (Quote) ->
                                string_as_user_response(User,
                                                        Quote#quote.quote
                                                        ++ " ("
                                                        ++ integer_to_list(Quote#quote.id)
                                                        ++ ")")
                        end,
                        quote_database:quote(Id)));
        _ -> nomessage
    end.


russify_command(User, Text) ->
    string_as_user_response(User,
                            gen_server:call(russify, binary:list_to_bin(Text))).

addcom_command(User, [Name, Response]) ->
    case custom_commands:add_command(Name, Response) of
        ok -> string_as_user_response(User, ["Command !", Name, " has been added"]);
        updated -> string_as_user_response(User, ["Command !", Name, " has been updated"])
    end.

delcom_command(User, Name) ->
    case custom_commands:del_command(Name) of
        ok -> string_as_user_response(User, ["Command !", Name, " has been removed."]);
        noexists -> string_as_user_response(User, ["Command !", Name, " doesn't exist."])
    end.

bttv_command(User, _) ->
    EmotesResponse =
        option:map(
          fun ({_, _, Body}) ->
                  {BttvResponse} = jiffy:decode(Body),
                  ["Available BTTV emotes: ",
                   lists:join(
                     " ",
                     lists:map(
                       fun ({Emote}) ->
                               proplists:get_value(<<"code">>, Emote)
                       end,
                       proplists:get_value(<<"emotes">>, BttvResponse)))]
          end,
          httpc:request("https://api.betterttv.net/2/channels/tsoding")),
    case EmotesResponse of
        {ok, Response} -> string_as_user_response(User, Response);
        Error -> error_logger:error_report(Error)
    end.

help_command(User, "") ->
    string_as_user_response(User,
                            "supported commands: "
                            ++ string:join(maps:keys(command_table()), ", ")
                            ++ ". Source code: https://github.com/tsoding/tsoder");
help_command(User, Command) ->
    case command_table() of
        #{ Command := {_, Description} } ->
            string_as_user_response(User, Description);
        _ ->
            string_as_user_response(User, "never heard of " ++ Command)
    end.

string_as_user_response(User, String) ->
    {message, ["@", User, ", ", String]}.
