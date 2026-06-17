--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="eu",date="2026-06-16T08:06:50Z",numCharacters=3,lookup={},recordSizeInBytes=2,encodingOrder={0,1,3}}
local F

-- chunk size: 6
F = function() provider.lookup[1] = "\4\4\4\4\4\8" end F()

F = nil
RaiderIO.AddProvider(provider)
