-module(node_integration_test).

-include("../src/chef_req.hrl").
-include_lib("eunit/include/eunit.hrl").

basic_node_create_test_() ->
    {setup,
     fun() ->
             ok = chef_req:start_apps(),
             KeyPath = "/tmp/opscode-platform-test/clownco-org-admin.pem",
             ReqConfig = chef_req:make_config("http://localhost",
                                              "clownco-org-admin", KeyPath),
             {_, ClientConfig} = chef_req:make_client("clownco", "client01", ReqConfig),
             {_, WeakClientConfig} = chef_req:make_client("clownco", "client02", ReqConfig),
             chef_req:remove_client_from_group("clownco", "client02", "clients", ReqConfig),
             {ReqConfig, ClientConfig, WeakClientConfig}
     end,
     fun({ReqConfig, _, _}) ->
             "200" = chef_req:delete_client("clownco", "client01", ReqConfig),
             "200" = chef_req:delete_client("clownco", "client02", ReqConfig),
             test_utils:test_cleanup(ignore)
     end,
     fun({UserConfig, ClientConfig, WeakClientConfig}) ->
             [basic_node_create_tests_for_config(UserConfig),
              basic_node_create_tests_for_config(ClientConfig),
              basic_node_list_tests_for_config(UserConfig),
              node_permissions_tests(UserConfig, WeakClientConfig)]
     end}.

basic_node_list_tests_for_config(#req_config{name = Name}=ReqConfig) ->
    Label = " (" ++ Name ++ ")",
    {NodeName, NodeJson} = sample_node(),
    [
     {"list nodes" ++ Label,
      fun() ->
              Path = "/organizations/clownco/nodes",
              {ok, Code, _H, Body} = chef_req:request(get, Path, ReqConfig),
              ?assertEqual("200", Code),
              NodeList = ejson:decode(Body),
              ?assert(is_list(NodeList)),
              ?assert(is_binary(hd(NodeList)))
              %% FIXME: we need to instrument the db so that we have a
              %% known node table state and then test for nodes.
      end}
    ].

node_permissions_tests(UserConfig, WeakClientConfig) ->              
    [
     {"POST without create on nodes container",
       fun() ->
               Path = "/organizations/clownco/nodes",
               {_, Node403} = sample_node(),
               {ok, Code, _H, Body} = chef_req:request(post, Path, Node403,
                                                        WeakClientConfig),
               ?assertEqual("403", Code),
               ?assertEqual(<<"missing create permission">>, Body)
       end}

    ].

basic_node_create_tests_for_config(#req_config{name = Name}=ReqConfig) ->
    Label = " (" ++ Name ++ ")",
    {NodeName, NodeJson} = sample_node(),
    [
     {"create a new node" ++ Label,
      fun() ->
              Path = "/organizations/clownco/nodes",
              {ok, Code, _H, Body} = chef_req:request(post, Path, NodeJson, ReqConfig),
              ?assertEqual("201", Code),
              NodeUrl = <<"http://localhost/organizations/clownco/nodes/", NodeName/binary>>,
              Expect = ejson:encode({[{<<"uri">>, NodeUrl}]}),
              ?assertEqual(Expect, Body)
      end},

     {"conflict when node name already exists" ++ Label,
      fun() ->
              Path = "/organizations/clownco/nodes",
              {ok, Code, _H, Body} = chef_req:request(post, Path, NodeJson, ReqConfig),
              ?assertEqual("409", Code),
              ?assertEqual(<<"{\"error\":[\"Node already exists\"]}">>, Body)
      end},

     {"org 'no-such-org' does not exist" ++ Label,
      fun() ->
              Path = "/organizations/no-such-org/nodes",
              {ok, Code, _H, Body} = chef_req:request(post, Path, NodeJson, ReqConfig),
              ?assertEqual("404", Code),
              ?assertEqual(<<"{\"error\":[\"organization no-such-org does not exist.\"]}">>,
                           Body)
      end},

     {"POST of invalid JSON is a 400" ++ Label,
      fun() ->
              Path = "/organizations/clownco/nodes",
              InvalidJson = <<"{not:json}">>,
              {ok, Code, _H, _Body} = chef_req:request(post, Path, InvalidJson, ReqConfig),
              ?assertEqual("400", Code)
      end}
    ].

sample_node() ->
    sample_node(make_node_name(<<"node-">>)).

sample_node(Name) ->
    {Name,
     <<"{\"normal\":{\"is_anyone\":\"no\"},\"name\":\"", Name/binary,
       "\",\"override\":{},"
       "\"default\":{},\"json_class\":\"Chef::Node\",\"automatic\":{},"
       "\"chef_environment\":\"_default\",\"run_list\":[],\"chef_type\":\"node\"}">>}.

make_node_name(Prefix) when is_binary(Prefix) ->
    Rand = bin_to_hex(crypto:rand_bytes(3)),
    <<Prefix/binary, Rand/binary>>;
make_node_name(Prefix) when is_list(Prefix) ->
    make_node_name(list_to_binary(Prefix)).

bin_to_hex(Bin) ->
    iolist_to_binary([io_lib:format("~2.16.0b", [X])
                      || X <- binary_to_list(Bin)]).
