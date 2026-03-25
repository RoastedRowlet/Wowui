--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="eu",date="2026-03-24T06:06:08Z",numCharacters=17,db={}}
local F

F = function() provider.db["Hoptallus"]={0,"Arizara","Eruveena","Feronya","Ludidoktor","Ludidoktorr","Ludidokttor","Nacugivara","Nikotako","Noshecant","Psyvise","Rualan"} end F()
F = function() provider.db["Norushen"]={22,"Doybear","Dythu","Synomnomnom","Taibalt"} end F()
F = function() provider.db["Everlook"]={30,"Chugganaut","Imperatvs"} end F()

F = nil
RaiderIO.AddProvider(provider)
