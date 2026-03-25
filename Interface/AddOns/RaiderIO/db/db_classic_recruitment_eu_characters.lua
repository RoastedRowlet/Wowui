--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="eu",date="2026-03-25T06:06:23Z",numCharacters=9,db={}}
local F

F = function() provider.db["Hoptallus"]={0,"Arizara","Eruveena","Feronya","Ludidoktor","Nikotako","Psyvise","Rualan"} end F()
F = function() provider.db["Everlook"]={14,"Chugganaut","Imperatvs"} end F()

F = nil
RaiderIO.AddProvider(provider)
