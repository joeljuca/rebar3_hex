-module(rebar3_hex_docs).

-export([init/1,
         do/1,
         format_error/1]).

-include("rebar3_hex.hrl").

-define(PROVIDER, docs).
-define(DEPS, [{default, edoc}]).

-define(ENDPOINT, "packages").

%% ===================================================================
%% Public API
%% ===================================================================

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
                                {name, ?PROVIDER},
                                {module, ?MODULE},
                                {namespace, hex},
                                {bare, true},
                                {deps, ?DEPS},
                                {example, "rebar3 hex docs"},
                                {short_desc, "Publish documentation for the current project and version"},
                                {desc, ""},
                                {opts, [{revert, undefined, "revert", string, "Revert given version."}]}
                                ]),
    State1 = rebar_state:add_provider(State, Provider),
    {ok, State1}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    Apps = rebar3_hex_utils:select_apps(rebar_state:project_apps(State)),
    lists:foldl(fun(App, {ok, StateAcc}) ->
                        do_(App, StateAcc)
                end, {ok, State}, Apps).

-spec format_error(any()) -> iolist().
format_error({error, Name, Vsn, Message}) ->
    io_lib:format("Failed to publish docs for ~s ~s. Error: ~s.", [Name, Vsn, Message]).

do_(App, State) ->
    AppDir = rebar_app_info:dir(App),
    Files = rebar3_hex_utils:expand_paths(["doc"], AppDir),

    Name = binary_to_list(rebar_app_info:name(App)),
    {Args, _} = rebar_state:command_parsed_args(State),
    Revert = proplists:get_value(revert, Args, undefined),
    case Revert of
        undefined ->
            Vsn = rebar_app_info:original_vsn(App),

            Tarball = Name++"-"++Vsn++"-docs.tar.gz",

            ok = erl_tar:create(Tarball, file_list(Files)),
            {ok, Tar} = file:read_file(Tarball),

            file:delete(Tarball),

            {ok, Auth} = rebar3_hex_config:auth(),
            case rebar3_hex_http:post(filename:join([?ENDPOINT, Name, "releases", Vsn, "docs"])
                                     ,Auth
                                     ,Tar
                                     ,integer_to_list(byte_size(Tar))) of
                ok ->
                    rebar_api:info("Published docs for ~s ~s", [Name, Vsn]),
                    {ok, State};
                {error, _, Error} ->
                    Message = proplists:get_value(<<"message">>, Error, <<"">>),
                    ?PRV_ERROR({error, Name, Vsn, Message})
            end;
        Version ->
            case delete(Name, Version) of
                ok ->
                    {ok, State};
                Error ->
                    Error
            end
    end.

delete(Name, Version) ->
    {ok, Auth} = rebar3_hex_config:auth(),
    case rebar3_hex_http:delete(filename:join([?ENDPOINT, Name, "releases", Version, "docs"]), Auth) of
        ok ->
            rebar_api:info("Successfully deleted docs for ~s ~s", [Name, Version]),
            ok;
        {error, Status, _} ->
            rebar_api:error("Unable to delete docs ~s ~s (~p)", [Name, Version, Status])
    end.

file_list(Files) ->
    [{drop_path(File, ["doc"]), File} || File <- Files].

drop_path(File, Path) ->
    filename:join(filename:split(File) -- Path).
