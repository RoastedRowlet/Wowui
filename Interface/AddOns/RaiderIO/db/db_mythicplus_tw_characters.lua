--
-- Copyright (c) 2026 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=1,region="tw",date="2026-03-24T06:44:24Z",currentSeasonId=0,numCharacters=7894,keystoneMilestoneLevels={15,12,10,7,4,2},db={}}
local F

F = function() provider.db["眾星之子"]={0,"夜嵐緋雪","龍蝦小魚卵"} end F()
F = function() provider.db["暗影之月"]={60,"緋鳳輓歌"} end F()
F = function() provider.db["銀翼要塞"]={90,"Magicstar","天嵐彗星"} end F()
F = function() provider.db["日落沼澤"]={150,"凝川"} end F()
F = function() provider.db["語風"]={180,"Snowynight"} end F()
F = function() provider.db["水晶之刺"]={210,"憨豆大媽","被強煎的蛋","麥能爺"} end F()
F = function() provider.db["夜空之歌"]={300,"Montblanc","Mythicat","Pinkwarrior","一萬年的雪","床邊目擊者","烽煙肆起","版築雉堞之殷","牛郎店男模","舒服嗎"} end F()
F = function() provider.db["冰霜之刺"]={570,"橘子班長"} end F()

F = nil
RaiderIO.AddProvider(provider)
