--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="us",date="2026-05-05T08:07:12Z",numCharacters=15,lookup={},recordSizeInBytes=2,encodingOrder={0,1,3}}
local F

-- chunk size: 30
F = function() provider.lookup[1] = "\10\29\10\29\10\29\10\29\10\29\10\29\10\29\10\29\10\29\10\29\10\29\10\29\10\5\10\5\10\5" end F()

F = nil
RaiderIO.AddProvider(provider)
