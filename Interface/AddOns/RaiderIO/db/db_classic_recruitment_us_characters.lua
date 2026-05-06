--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="us",date="2026-05-05T08:07:12Z",numCharacters=15,db={}}
local F

F = function() provider.db["Pagle"]={0,"Airbrake","Dragonsage","Firebrake","Healbrake","Holybrake","Ineedwhat","Kelthara","Sajara","Scarletwind","Teramedic","Treebrake","Wulfwÿnn"} end F()
F = function() provider.db["Galakras"]={24,"Styggzfu","Styggztoo","Varltok"} end F()

F = nil
RaiderIO.AddProvider(provider)
