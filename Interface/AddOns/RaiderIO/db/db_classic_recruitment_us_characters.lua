--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="us",date="2026-06-03T08:07:08Z",numCharacters=3,db={}}
local F

F = function() provider.db["Raden"]={0,"Snuf","Snuff"} end F()
F = function() provider.db["Galakras"]={4,"Hàney"} end F()

F = nil
RaiderIO.AddProvider(provider)
