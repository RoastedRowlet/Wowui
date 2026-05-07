--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="us",date="2026-05-06T08:08:15Z",numCharacters=13,db={}}
local F

F = function() provider.db["Pagle"]={0,"Airbrake","Dragonsage","Firebrake","Holybrake","Kelthara","Sajara","Scarletwind","Teramedic","Treebrake","Wulfwÿnn"} end F()
F = function() provider.db["Galakras"]={20,"Styggzfu","Styggztoo","Varltok"} end F()

F = nil
RaiderIO.AddProvider(provider)
