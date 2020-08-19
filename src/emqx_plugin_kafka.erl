%%--------------------------------------------------------------------
%% Copyright (c) 2015-2017 Feng Lee <feng@emqtt.io>.
%%
%% Modified by Ramez Hanna <rhanna@iotblue.net>
%% 
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_plugin_kafka).

% -include("emqx_plugin_kafka.hrl").

-include_lib("emqx/include/emqx.hrl").

-export([load/1, unload/0]).

%% Client Lifecircle Hooks
-export([ on_client_connect/3
        , on_client_connack/4
        , on_client_connected/3
        , on_client_disconnected/4
        , on_client_authenticate/3
        , on_client_check_acl/5
        , on_client_subscribe/4
        , on_client_unsubscribe/4
        ]).

%% Session Lifecircle Hooks
-export([ on_session_created/3
        , on_session_subscribed/4
        , on_session_unsubscribed/4
        , on_session_resumed/3
        , on_session_discarded/3
        , on_session_takeovered/3
        , on_session_terminated/4
        ]).

%% Message Pubsub Hooks
-export([ on_message_publish/2
        , on_message_delivered/3
        , on_message_acked/3
        , on_message_dropped/4
        ]).



%% Called when the plugin application start
load(Env) ->
    ekaf_init([Env]), 
    emqx:hook('client.connect',      {?MODULE, on_client_connect, [Env]}),
    emqx:hook('client.connack',      {?MODULE, on_client_connack, [Env]}),
    emqx:hook('client.connected',    {?MODULE, on_client_connected, [Env]}),
    emqx:hook('client.disconnected', {?MODULE, on_client_disconnected, [Env]}),
    emqx:hook('client.authenticate', {?MODULE, on_client_authenticate, [Env]}),
    emqx:hook('client.check_acl',    {?MODULE, on_client_check_acl, [Env]}),
    emqx:hook('client.subscribe',    {?MODULE, on_client_subscribe, [Env]}),
    emqx:hook('client.unsubscribe',  {?MODULE, on_client_unsubscribe, [Env]}),
    emqx:hook('session.created',     {?MODULE, on_session_created, [Env]}),
    emqx:hook('session.subscribed',  {?MODULE, on_session_subscribed, [Env]}),
    emqx:hook('session.unsubscribed',{?MODULE, on_session_unsubscribed, [Env]}),
    emqx:hook('session.resumed',     {?MODULE, on_session_resumed, [Env]}),
    emqx:hook('session.discarded',   {?MODULE, on_session_discarded, [Env]}),
    emqx:hook('session.takeovered',  {?MODULE, on_session_takeovered, [Env]}),
    emqx:hook('session.terminated',  {?MODULE, on_session_terminated, [Env]}),
    emqx:hook('message.publish',     {?MODULE, on_message_publish, [Env]}),
    emqx:hook('message.delivered',   {?MODULE, on_message_delivered, [Env]}),
    emqx:hook('message.acked',       {?MODULE, on_message_acked, [Env]}),
    emqx:hook('message.dropped',     {?MODULE, on_message_dropped, [Env]}).
	
on_client_connect(ConnInfo = #{clientid := ClientId}, Props, _Env) ->
    %io:format("Client(~s) connect, ConnInfo: ~p, Props: ~p~n",
              %[ClientId, ConnInfo, Props]),
    {ok, Props}.

on_client_connack(ConnInfo = #{clientid := ClientId}, Rc, Props, _Env) ->
    %io:format("Client(~s) connack, ConnInfo: ~p, Rc: ~p, Props: ~p~n",
              %[ClientId, ConnInfo, Rc, Props]),
    {ok, Props}.
	
on_client_connected(ClientInfo = #{clientid := ClientId}, ConnInfo, _Env) ->
    io:format("Client(~s) connected, ClientInfo:~n~p~n, ConnInfo:~n~p~n",
              [ClientId, ClientInfo, ConnInfo]),
		{IpAddr, _Port} = maps:get(peername, ConnInfo),
    	Action = <<"connected">>,
    	Now = calendar:datetime_to_gregorian_seconds(calendar:universal_time())-719528*24*3600,
    	Online = 1,
    	Payload = [
		{action, Action}, 
		{device_id, ClientId}, 
		{username, maps:get(username, ClientInfo)},
		{keepalive, maps:get(keepalive, ConnInfo)},
		{ipaddress, iolist_to_binary(ntoa(IpAddr))},
		{proto_name, maps:get(proto_name, ConnInfo)},
		{proto_ver, maps:get(proto_ver, ConnInfo)},
		{timestamp, Now},
		{online, Online}
    ],
   produce_kafka_payload(Payload),
   ok.

on_client_disconnected(ClientInfo = #{clientid := ClientId}, ReasonCode, ConnInfo, _Env) ->
    io:format("Client(~s) disconnected due to ~p, ClientInfo:~n~p~n, ConnInfo:~n~p~n",
              [ClientId, ReasonCode, ClientInfo, ConnInfo]), 
    Action = <<"disconnected">>,
    Now = calendar:datetime_to_gregorian_seconds(calendar:universal_time())-719528*24*3600,
    Online = 0,
    Payload = [
		{action, Action}, 
		{device_id, ClientId}, 
		{username, maps:get(username, ClientInfo)},
 		{reason, ReasonCode},
		{timestamp, Now},
		{online, Online}
	],	
    produce_kafka_payload(Payload),
    ok.

on_client_authenticate(_ClientInfo = #{clientid := ClientId}, Result, _Env) ->
    io:format("Client(~s) authenticate, Result:~n~p~n", [ClientId, Result]),
    {ok, Result}.

on_client_check_acl(_ClientInfo = #{clientid := ClientId}, Topic, PubSub, Result, _Env) ->
    io:format("Client(~s) check_acl, PubSub:~p, Topic:~p, Result:~p~n",
              [ClientId, PubSub, Topic, Result]),
    {ok, Result}.
	
%%---------------------------client subscribe start--------------------------%%
on_client_subscribe(#{clientid := ClientId}, _Properties, TopicFilters, _Env) ->
    io:format("Client(~s) will subscribe: ~p~n", [ClientId, TopicFilters]),  
    Topic=erlang:element(1,erlang:hd(TopicFilters)),
    Qos = erlang:element(2,lists:last(TopicFilters)),
    Action = <<"subscribe">>,
    Now = calendar:datetime_to_gregorian_seconds(calendar:universal_time())-719528*24*3600,
    Payload = [
		{device_id, ClientId},
		{action, Action},  
		{topic, Topic},
		{qos, maps:get(qos, Qos)},
		{timestamp, Now}
	],	
    produce_kafka_payload(Payload),
	{ok, TopicFilters}.
%%---------------------client subscribe stop----------------------%%
on_client_unsubscribe(#{clientid := ClientId}, _Properties, TopicFilters, _Env) ->
    io:format("Client(~s) will unsubscribe ~p~n", [ClientId, TopicFilters]),   
	Topic=erlang:element(1,erlang:hd(TopicFilters)),
    Action = <<"unsubscribe">>,
    Now = calendar:datetime_to_gregorian_seconds(calendar:universal_time())-719528*24*3600,
    Payload = [
		{device_id, ClientId},
		{action, Action},  
		{topic, Topic},
		{timestamp, Now}
	],	
    produce_kafka_payload(Payload),
    {ok, TopicFilters}.

on_message_dropped(#message{topic = <<"$SYS/", _/binary>>}, _By, _Reason, _Env) ->
    ok;
on_message_dropped(Message, _By = #{node := Node}, Reason, _Env) ->
    io:format("Message dropped by node ~s due to ~s: ~s~n",
              [Node, Reason, emqx_message:format(Message)]).

	
%%---------------------------message publish start--------------------------%%
on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};
on_message_publish(Message, _Env) ->
    {ok, Payload} = format_payload(Message),
    produce_kafka_payload(Payload),
    {ok, Message}.	
%%---------------------message publish stop----------------------%%

on_message_delivered(_ClientInfo = #{clientid := ClientId}, Message, _Env) ->
    io:format("Message delivered to client(~s): ~s~n",
              [ClientId, emqx_message:format(Message)]),
    Topic=Message#message.topic,
    Payload=Message#message.payload,
    Qos=Message#message.qos,
    From=Message#message.from,
    Timestamp=Message#message.timestamp,
    Json = jsx:encode([
     		{type,<<"deliver messqge">>},
		{from,From},
		{to,ClientId},
		{topic,Topic},
     	{payload,Payload},
     	{qos,Qos},
     	{cluster_node,node()},
	{ts,now_secs(Timestamp)}
	 ]),
	EkafTopic=ekaf_get_topic(),
	ekaf:produce_sync(EkafTopic,Json),
 	{ok, Message}.

on_message_acked(_ClientInfo = #{clientid := ClientId}, Message, _Env) ->
    io:format("Message acked by client(~s): ~s~n",
              [ClientId, emqx_message:format(Message)]),
    Topic=Message#message.topic,
    Payload=Message#message.payload,
    Qos=Message#message.qos,
    From=Message#message.from,
    Timestamp=Message#message.timestamp,
    Json = jsx:encode([
     	{type,<<"acked messqge">>},
	{from,From},
	{to,ClientId},
	{topic,Topic},
     	{payload,Payload},
     	{qos,Qos},
     	{cluster_node,node()},
	{ts,now_secs(Timestamp)}
	 ]),
	EkafTopic=ekaf_get_topic(),
	ekaf:produce_sync(EkafTopic,Json).
	
%%--------------------------------------------------------------------
%% Session Lifecircle Hooks
%%--------------------------------------------------------------------

on_session_created(#{clientid := ClientId}, SessInfo, _Env) ->
    %io:format("Session(~s) created, Session Info:~n~p~n", [ClientId, SessInfo]).
     ok.
	

on_session_subscribed(#{clientid := ClientId}, Topic, SubOpts, _Env) ->
    io:format("Session(~s) subscribed ~s with subopts: ~p~n", [ClientId, Topic, SubOpts]).

on_session_unsubscribed(#{clientid := ClientId}, Topic, Opts, _Env) ->
    io:format("Session(~s) unsubscribed ~s with opts: ~p~n", [ClientId, Topic, Opts]).

on_session_resumed(#{clientid := ClientId}, SessInfo, _Env) ->
    io:format("Session(~s) resumed, Session Info:~n~p~n", [ClientId, SessInfo]).

on_session_discarded(_ClientInfo = #{clientid := ClientId}, SessInfo, _Env) ->
    io:format("Session(~s) is discarded. Session Info: ~p~n", [ClientId, SessInfo]).

on_session_takeovered(_ClientInfo = #{clientid := ClientId}, SessInfo, _Env) ->
    io:format("Session(~s) is takeovered. Session Info: ~p~n", [ClientId, SessInfo]).

on_session_terminated(_ClientInfo = #{clientid := ClientId}, Reason, SessInfo, _Env) ->
    io:format("Session(~s) is terminated due to ~p~nSession Info: ~p~n",
              [ClientId, Reason, SessInfo]).	
 	
ekaf_init(_Env) ->
    {ok, BrokerValues} = application:get_env(emqx_plugin_kafka, broker),
    KafkaHost = proplists:get_value(host, BrokerValues),
    io:format("KafkaHost = ~s~n",[KafkaHost]),
    KafkaPort = proplists:get_value(port, BrokerValues),
    io:format("KafkaPort = ~s~n",[KafkaPort]),
    KafkaPartitionStrategy = proplists:get_value(partitionstrategy, BrokerValues),
    KafkaPartitionWorkers = proplists:get_value(partitionworkers, BrokerValues),
    KafkaTopic = proplists:get_value(payloadtopic, BrokerValues),
    io:format("KafkaTopic = ~s~n",[KafkaTopic]),
    application:set_env(ekaf, ekaf_bootstrap_broker, {KafkaHost, list_to_integer(KafkaPort)}),
    application:set_env(ekaf, ekaf_partition_strategy, list_to_atom(KafkaPartitionStrategy)),
    application:set_env(ekaf, ekaf_per_partition_workers, KafkaPartitionWorkers),
    application:set_env(ekaf, ekaf_bootstrap_topics, list_to_binary(KafkaTopic)),
    application:set_env(ekaf, ekaf_buffer_ttl, 10),
    application:set_env(ekaf, ekaf_max_downtime_buffer_size, 5),
    % {ok, _} = application:ensure_all_started(kafkamocker),
    {ok, _} = application:ensure_all_started(gproc),
    % {ok, _} = application:ensure_all_started(ranch),
    {ok, _} = application:ensure_all_started(ekaf).

ekaf_get_topic() ->
    {ok, Topic} = application:get_env(ekaf, ekaf_bootstrap_topics),
    Topic.


format_payload(Message) ->
    Username = emqx_message:get_header(username, Message),
    Topic = Message#message.topic,
    Tail = string:right(binary_to_list(Topic), 4),
    RawType = string:equal(Tail, <<"_raw">>),
    % io:format("Tail= ~s , RawType= ~s~n",[Tail,RawType]),

    MsgPayload = Message#message.payload,
    % io:format("MsgPayload : ~s~n", [MsgPayload]),
    if
        RawType == true ->
            MsgPayload64 = list_to_binary(base64:encode_to_string(MsgPayload));
    % io:format("MsgPayload64 : ~s~n", [MsgPayload64]);
        RawType == false ->
            MsgPayload64 = MsgPayload
    end,
    Payload = [{action, message_publish},
        {device_id, Message#message.from},
        {username, Username},
        {topic, Topic},
        {payload, MsgPayload64},
        {ts, emqx_time:now_secs(Message#message.timestamp)}],

    {ok, Payload}.


%% Called when the plugin application stop
unload() ->
    emqx:unhook('client.connect',      {?MODULE, on_client_connect}),
    emqx:unhook('client.connack',      {?MODULE, on_client_connack}),
    emqx:unhook('client.connected',    {?MODULE, on_client_connected}),
    emqx:unhook('client.disconnected', {?MODULE, on_client_disconnected}),
    emqx:unhook('client.authenticate', {?MODULE, on_client_authenticate}),
    emqx:unhook('client.check_acl',    {?MODULE, on_client_check_acl}),
    emqx:unhook('client.subscribe',    {?MODULE, on_client_subscribe}),
    emqx:unhook('client.unsubscribe',  {?MODULE, on_client_unsubscribe}),
    emqx:unhook('session.created',     {?MODULE, on_session_created}),
    emqx:unhook('session.subscribed',  {?MODULE, on_session_subscribed}),
    emqx:unhook('session.unsubscribed',{?MODULE, on_session_unsubscribed}),
    emqx:unhook('session.resumed',     {?MODULE, on_session_resumed}),
    emqx:unhook('session.discarded',   {?MODULE, on_session_discarded}),
    emqx:unhook('session.takeovered',  {?MODULE, on_session_takeovered}),
    emqx:unhook('session.terminated',  {?MODULE, on_session_terminated}),
    emqx:unhook('message.publish',     {?MODULE, on_message_publish}),
    emqx:unhook('message.delivered',   {?MODULE, on_message_delivered}),
    emqx:unhook('message.acked',       {?MODULE, on_message_acked}),
    emqx:unhook('message.dropped',     {?MODULE, on_message_dropped}).

produce_kafka_payload(Message) ->
    Topic = ekaf_get_topic(),
    {ok, MessageBody} = emqx_json:safe_encode(Message),
    % io:format("Message = ~s~n",[MessageBody]),
    Payload = iolist_to_binary(MessageBody),
    ekaf:produce_async_batched(Topic, Payload).

ntoa({0,0,0,0,0,16#ffff,AB,CD}) ->
    inet_parse:ntoa({AB bsr 8, AB rem 256, CD bsr 8, CD rem 256});
ntoa(IP) ->
    inet_parse:ntoa(IP).
now_secs({MegaSecs, Secs, _MicroSecs}) ->
    MegaSecs * 1000000 + Secs.
