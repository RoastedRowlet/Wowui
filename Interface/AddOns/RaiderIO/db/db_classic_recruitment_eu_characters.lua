--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="eu",date="2026-06-15T08:13:34Z",numCharacters=3,db={}}
local F

F = function() provider.db["MirageRaceway"]={0,"Magopok"} end F()
F = function() provider.db["Norushen"]={2,"Xentare"} end F()
F = function() provider.db["Everlook"]={4,"Captntobi"} end F()

F = nil
RaiderIO.AddProvider(provider)
