--
-- Copyright (c) 2026 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="kr",date="2026-03-30T07:00:44Z",numCharacters=29658,db={}}
local F

F = function() provider.db["아즈샤라"]={0,"마스트리안","아스리엘문레이"} end F()

F = nil
RaiderIO.AddProvider(provider)
