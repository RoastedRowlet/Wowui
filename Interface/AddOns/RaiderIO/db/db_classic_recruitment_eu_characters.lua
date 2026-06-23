--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="eu",date="2026-06-22T08:07:03Z",numCharacters=4,db={}}
local F

F = function() provider.db["Norushen"]={0,"Xentare"} end F()
F = function() provider.db["Everlook"]={2,"Captntobi"} end F()
F = function() provider.db["PyrewoodVillage"]={4,"Lanaes","Shaymary"} end F()

F = nil
RaiderIO.AddProvider(provider)
