local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Unknown-Unknown','Warrior-Arms','DemonHunter-Havoc','Paladin-Holy','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Paladin-Protection','DeathKnight-Unholy','Shaman-Enhancement','Hunter-BeastMastery','Priest-Shadow','Druid-Balance','Druid-Feral','Druid-Restoration','Priest-Discipline','Mage-Arcane','DeathKnight-Blood','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','Shaman-Elemental','DeathKnight-Frost','Mage-Frost','Druid-Guardian','Hunter-Survival','Warrior-Protection','Monk-Brewmaster','Monk-Mistweaver',}
local provider = {region='US',realm='Bonechewer',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aandras:BAAANQAECgQJBQAAAA==.',
Ab='Abbey:BAAANQADCgYIBgAAAA==.Abhayah:BAAANQAECgMJBAAAAA==.Absportls:BAAANQAECgMJAwAAAA==.',
Ac='Acelliste:BAAANQAECgQICQAAAA==.',
Ad='Adventurerr:BAAANQADCgMJBQAAAA==.',
Af='Affgrezz:BAEANQADCgQIBAABNQAECgIJBQABAAAAAA==.',
Ai='Aidlef:BAAANQAECgMIBAABNQAECgkJFgACAPoeAA==.Aikenbranwen:BAAANQADCggJLAAAAA==.Aillannia:BAAANQADCgQIBAAAAA==.',
Al='Alandor:BAAANQADCgUICgAAAA==.Allfire:BAABNQAECoEfAAIDAAgKtR56EgCuAgADAAgKtR56EgCuAgAAAA==.Aluunix:BAAANQAECgUJCgAAAA==.Alyse:BAABNQAECoEcAAIEAAgKcx0jHACyAgAEAAgKcx0jHACyAgAAAA==.Alyta:BAAANQADCggJGgAAAA==.Alzulra:BAAANQADCgYIBgAAAA==.',
Am='Amayla:BAAANQADCgcIBwAAAA==.Amoracon:BAAANQADCgUIBQAAAA==.',
An='Anulstorm:BAAANQADCgYJDAAAAA==.Anundir:BAAANQAECgYJDwAAAA==.',
Ao='Aondor:BAAANQAECgYJDgAAAA==.',
Ap='Applepi:BAAANQADCgEIAQAAAA==.',
Ar='Arcanical:BAAANQADCgYIDAAAAA==.Arday:BAAANQAECgcIEwAAAA==.Aroldo:BAAANQAECgEJAQAAAA==.Aroromunroe:BAAANQAFFAEJAQABNQADCggIDgABAAAAAA==.Arrancateta:BAAANQAECgQICAAAAA==.',
As='Asena:BAAANQADCgQIBAABNQAECgQJBAABAAAAAA==.Ashblast:BAAANQADCgQIBAAAAA==.Ashira:BAAANQAECgMJBAABNQAECgkJHQAFAIIfAA==.Astarouge:BAAANQAECgYIDgAAAA==.Astrafury:BAAANQADCgcIBwAAAA==.Astrasneaky:BAABNQAECoEPAAQGAAgKHAnpIgBpAQAGAAcK4QfpIgBpAQAHAAQK+Qs+QADmAAAIAAEKeQvhFQA4AAAAAA==.',
At='Atchafalaya:BAAANQAECgUJCgABNQAECgYIDwABAAAAAA==.',
Av='Avatarstate:BAAANQADCgQIBAAAAA==.',
Aw='Awrina:BAAANQAECgUJCQAAAA==.',
Az='Azylrog:BAAANQADCgQJDwAAAA==.',
Ba='Babymiko:BAAANQADCgQIBQAAAA==.Babypeech:BAAANQADCgUJBQAAAA==.Bakudo:BAAANQABCgIIAgAAAA==.Bakulu:BAAANQAECgEJAgAAAA==.Bantoou:BAAANQAECgEJAgAAAA==.Bathoryz:BAAANQAECgcJEAAAAA==.Battlescars:BAAANQADCgYIEgAAAA==.Bauhaus:BAAANQADCgUJCQAAAA==.Bauld:BAAANQAECgMJBQAAAA==.',
Bd='Bdbypaladin:BAAANQABCgQIBAAAAA==.',
Be='Beardybear:BAAANQAECgQIBgAAAA==.Bearface:BAAANQADCgYIBgAAAA==.Bearicaide:BAAANQAECgQIBQAAAA==.Beautiful:BAAANQADCgYIBgAAAA==.Beefygee:BAAANQADCgMIAwAAAA==.Belldrak:BAAANQADCgUIBQAAAA==.Belldren:BAAANQAECgEJAQAAAA==.Belldrin:BAAANQAECgEJAQAAAA==.Bepaulie:BAAANQADCgIIAgABNQAECgUICAABAAAAAA==.Bergidum:BAAANQADCgcJDAAAAA==.Beriamilbinc:BAAANQADCgYICAAAAA==.Bewmy:BAAANQADCgIJAgAAAA==.',
Bh='Bhucket:BAAANQADCgEIAQAAAA==.',
Bi='Bignagos:BAAANQADCgYJEAAAAA==.Bigolboi:BAAANQAECgIJAwAAAA==.Bigthickheal:BAAANQADCgEIAQAAAA==.',
Bl='Blackk:BAABNQAECoEdAAIJAAkKLR4oDgAXAwAJAAkKLR4oDgAXAwAAAA==.Blackxcoffee:BAAANQADCgIIAgAAAA==.Bladesong:BAAANQAECgEIAQAAAA==.Blood:BAAANQAECgYICAAAAA==.Blorglock:BAABNQAECoEiAAMKAAkKfx2PIACnAgAKAAgKpxyPIACnAgALAAQKZRqkIABIAQAAAA==.Blorgonp:BAAANQADCgYIBgABNQAECgkJIgAKAH8dAA==.Blorgonw:BAAANQAECgYJCQABNQAECgkJIgAKAH8dAA==.Blowaegis:BAAANQAFFAEJAQAAAA==.Blownoutshax:BAAANQADCgEIAQAAAA==.Bluntnfortys:BAAANQADCgYICwAAAA==.Blupenguiny:BAABNQAECoEVAAIMAAcKLAneWAB1AQAMAAcKLAneWAB1AQAAAA==.',
Bm='Bmfsleeps:BAAANQADCgUICAAAAA==.',
Bn='Bnortwarrior:BAAANQAECgQICQABNQAECgEIAQABAAAAAA==.',
Bo='Boanz:BAAANQAECgMJBAAAAA==.Bobasaurus:BAAANQAECgUIDgAAAA==.Bombastik:BAAANQAECgMIBAAAAA==.Bonesnapp:BAAANQAECgMIAwABNQAECggIHgANAEcfAA==.Booperry:BAAANQADCggICAAAAA==.Bosskün:BAAANQAECgMIAwAAAA==.Bountie:BAAANQAECgYIEAAAAA==.Bountiè:BAAANQADCgEIAQABNQAECgYIEAABAAAAAA==.Boyoyong:BAAANQADCgQIBAAAAA==.',
Br='Brainmatter:BAAANQADCgUJCgAAAA==.Brandedsoul:BAAANQADCgIIAgAAAA==.Brewztler:BAAANQADCgcIFwAAAA==.Brightscale:BAAANQADCggIDgAAAA==.Broham:BAAANQAECgEIAQAAAA==.Bromeheal:BAAANQADCgIIAgAAAA==.Bronik:BAAANQAECgYJDgAAAA==.Brujaja:BAAANQADCgQIBAAAAA==.',
Bu='Buffmage:BAAANQAECgcIEgAAAA==.Bullman:BAAANQAECgQIBgABNQAECggJGgAOAJkdAA==.Bullrûsh:BAAANQAECgYJCQAAAA==.Bullviper:BAAANQADCgYIDwAAAA==.',
['Bè']='Bèrsèrk:BAAANQADCgcIBwABNQAECggIGwAPAKMZAA==.',
['Bì']='Bìgdaddy:BAAANQADCgYICwAAAA==.',
['Bø']='Bønestørm:BAABNQAECoEbAAIPAAgKoxluCACiAgAPAAgKoxluCACiAgAAAA==.',
['Bù']='Bùndee:BAAANQAECgQJCQAAAA==.',
Ca='Cabbâge:BAAANQADCgEIAQAAAA==.Cacapants:BAAANQADCgQIBAAAAA==.Cadencegs:BAAANQAECgQIBwAAAA==.Caliex:BAAANQAECgQIBAAAAA==.Califax:BAABNQAECoEdAAMFAAkKgh+DFwBJAgAFAAcKRx2DFwBJAgAQAAMKoiIOngAkAQAAAA==.Caller:BAAANQADCgIIAgAAAA==.Callsignwiz:BAAANQAECgQJBQABNQAECgQIBwABAAAAAA==.Cannedbeans:BAAANQADCgMIAwAAAA==.Canuckcow:BAAANQADCgUICAAAAA==.Captantrips:BAAANQAECgIJAgAAAA==.Carltonswag:BAAANQADCgcJBwAAAA==.Catazhanir:BAAANQAECgMJAwAAAA==.Catclown:BAABNQAECoEYAAMMAAcKDRxaMgAqAgAMAAcKDRxaMgAqAgARAAMKZAl4QACUAAAAAA==.Cavonesee:BAAANQADCgcJCAAAAA==.Caylaramose:BAAANQADCggICAAAAA==.Cazsandra:BAAANQAECgcJEwAAAA==.',
Cc='Ccs:BAAANQADCgYIEwAAAA==.',
Ch='Chadsoss:BAAANQADCgYIBgAAAA==.Chamlio:BAAANQADCgYJFgAAAA==.Channis:BAAANQADCgQIAwAAAA==.Chenaccles:BAAANQADCgQIBAAAAA==.Chickenrally:BAAANQAECgQIDQAAAA==.Chinobear:BAAANQADCgYIEQAAAA==.Chixilog:BAAANQAECgIJAgAAAA==.Chodyboy:BAAANQABCgYIBgAAAA==.Cholmondeley:BAAANQADCgIIAgAAAA==.Chublie:BAAANQAECgUJBQAAAA==.Chuchix:BAABNQAECoEgAAQSAAkKehqgFgDHAgASAAkKThqgFgDHAgATAAIK9Bj6GQCpAAAUAAMKagMTQAB9AAAAAA==.Chuckler:BAAANQAECgEIAQAAAA==.',
Cl='Cladtu:BAAANQAECgUJBwAAAA==.Cleiah:BAAANQADCgUIBQAAAA==.Cloudfisto:BAAANQADCggJEwAAAA==.',
Co='Colacolaz:BAACNQAFFIEHAAMLAAIKRCXaCwBtAAAKAAEKiyXbHABvAAALAAEK/CTaCwBtAAA1AAQKgSUAAwoACQrjJTMJAEcDAAoACAolJTMJAEcDAAsABgq5IyAJAEwCAAAA.Colasham:BAAANQAECgcIDwABNQAFFAIIBwALAEQlAA==.Coldhands:BAAANQADCgEIAQABNQAECgkJGgAHACgfAA==.Colombiano:BAAANQAECgQIBAABNQAECgQIDgABAAAAAA==.Coltoff:BAABNQAECoEhAAMMAAkKKBbyJgBnAgAMAAkKKBbyJgBnAgAVAAEKIAG8IQAeAAAAAA==.Conker:BAAANQADCgUIBQAAAA==.Coprates:BAAANQAECgMJBQAAAA==.Corgiquester:BAAANQAECgIJAgAAAA==.Corpserot:BAAANQADCgEIAQAAAA==.Corsin:BAAANQADCgQICQAAAA==.Cowbustion:BAAANQAECgQJDAAAAA==.',
Cp='Cptxcrunch:BAAANQADCgUJBgAAAA==.',
Cr='Cracken:BAAANQADCggICgABNQAECgYJEwABAAAAAA==.Crankshot:BAAANQADCgYICgABNQAECgMIAwABAAAAAA==.Crimsonrayne:BAAANQAECgQIBQAAAA==.Crusherlol:BAAANQAECgQICQAAAA==.Crusherlul:BAAANQAECgIJAgABNQAECgQICQABAAAAAA==.',
Cu='Curfew:BAAANQAECgcIEgAAAA==.',
['Cà']='Càt:BAAANQADCgEIAQAAAA==.',
Da='Dabigoldk:BAAANQAECgUIBQAAAA==.Dahlya:BAAANQADCgEIAQABNQADCggICQABAAAAAA==.Dannzig:BAAANQADCgIJAgAAAA==.Daragon:BAAANQADCgEIAQABNQAECggIFwANAKQjAA==.Darkravèn:BAAANQAECgYJEAAAAA==.Darthkitsune:BAAANQAECgMIAwAAAA==.Datbubblelol:BAAANQAECgYIBwAAAA==.Datchick:BAAANQADCgcJGQAAAA==.Datlilpriest:BAAANQADCggICAAAAA==.Dawnkeeper:BAAANQADCgIIAgAAAA==.Dawnlily:BAAANQABCgcIDwAAAA==.Daxy:BAAANQADCgIIAgAAAA==.Daymandeuces:BAAANQAECggJAwAAAA==.Dazbek:BAABNQAECoElAAIWAAkKBB7lOQDeAgAWAAkKBB7lOQDeAgAAAA==.',
De='Decày:BAAANQADCgUIBgABNQAECgcIGgAKADMjAA==.Deepdutch:BAAANQAECgYJDwAAAA==.Deezzeezz:BAAANQAECgUJDAABNQAECggJIQAQAJEZAA==.Degeneffe:BAAANQAECgMJBAAAAA==.Demoreknight:BAABNQAECoEcAAIXAAgKAhojHwBcAgAXAAgKAhojHwBcAgAAAA==.Devilboy:BAABNQAECoEXAAIOAAgKriNoCQBMAwAOAAgKriNoCQBMAwAAAA==.Dextrey:BAAANQADCggICAABNQAECgUJDgABAAAAAA==.',
Di='Dialuptacos:BAAANQABCgYIBgAAAA==.Diddycombs:BAAANQADCgYIBgAAAA==.Discbrown:BAABNQAECoEeAAMRAAkKfR6qCQARAwARAAkKfR6qCQARAwAMAAEKeQIGqAA7AAAAAA==.Discmemommy:BAAANQAECgQJCAABNQAECgcIGgAKADMjAA==.Discontent:BAAANQAECgIJAgAAAA==.Divinesmoke:BAAANQADCgUIBQAAAA==.',
Dj='Djblink:BAAANQADCgIIAgABNQAECgIIBAABAAAAAA==.',
Dk='Dkgaming:BAAANQAECgQJCQAAAA==.',
Do='Dogeared:BAAANQAECgYIDwAAAA==.Doloc:BAEANQADCgIIAgABNQAECgYJEQABAAAAAA==.Domore:BAAANQAECgcJCgAAAA==.Donniedrako:BAAANQADCgQIBAAAAA==.Donson:BAABNQAECoEeAAIYAAkK9hijOQBuAgAYAAkK9hijOQBuAgAAAA==.Donsun:BAAANQADCgUIBQAAAA==.Doodlebobb:BAAANQAECgMIBAAAAA==.Doomlakalaka:BAAANQADCgYIFwAAAA==.Dorgh:BAAANQADCgIIAgAAAA==.Doskya:BAAANQADCgQIBAAAAA==.Doubleclap:BAAANQADCggIEwAAAA==.',
Dp='Dpzofdoom:BAAANQAECgQJBQAAAA==.',
Dr='Dracthwnd:BAACNQAFFIEIAAMZAAUK+QiAAgAxAQAZAAQKCQuAAgAxAQAaAAIKYQhcCACIAAA1AAQKgSQAAxkACQrPIHUBAE0DABkACQrPIHUBAE0DABoACApNHHgLAGcCAAAA.Dragbrown:BAAANQADCgYIBgAAAA==.Dragonsins:BAABNQAECoEcAAIKAAkK8CE9BwBeAwAKAAkK8CE9BwBeAwAAAA==.Drahron:BAAANQADCggIAgAAAA==.Drdiksmasher:BAAANQAECgIIBQAAAA==.Drekka:BAAANQADCgEIAQABNQAECgIJAwABAAAAAA==.Drogmax:BAAANQAECgQJBgAAAA==.Droptopp:BAAANQAECgcIEQAAAA==.Drusys:BAAANQAECgUJBwAAAA==.Dryrod:BAAANQADCgYJBgAAAA==.',
Du='Duckelf:BAABNQAECoEbAAIUAAgKMST3BAA8AwAUAAgKMST3BAA8AwAAAA==.Dunranger:BAAANQAECgEIAQAAAA==.Durrga:BAABNQAECoEdAAICAAkKUCD/EgBGAwACAAkKUCD/EgBGAwAAAA==.',
['Dà']='Dàb:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.',
['Dã']='Dãftmõnk:BAAANQAECgUICwAAAA==.',
['Dë']='Dëvildog:BAAANQADCgYIBgAAAA==.',
Ed='Edgecrusherr:BAAANQAECgMJBAAAAA==.',
Eg='Egwenalmere:BAAANQAECgYJBwAAAA==.',
El='Elainia:BAAANQADCgYIDgAAAA==.Elisaveta:BAAANQAECgMJAwAAAA==.Elliaa:BAAANQADCggIEgAAAA==.Elliard:BAAANQADCgUICAAAAA==.Elmahikera:BAAANQADCggJCAABNQAECgYIDQABAAAAAA==.Elodi:BAAANQADCgYIBgAAAA==.',
Em='Emanx:BAAANQABCgIIAgABNQAECgYJDgABAAAAAA==.Embér:BAAANQAECggIBQAAAA==.',
En='Enheduanna:BAAANQADCgUICAAAAA==.',
Eo='Eowyen:BAAANQADCgUIBQAAAA==.',
Ep='Epiiphany:BAAANQADCgYIBwAAAA==.',
Er='Erinsister:BAAANQADCgEIAgABNQAECgQJCQABAAAAAA==.Erydius:BAAANQAECgIJAwAAAA==.',
Es='Esdeath:BAAANQABCgIIAgAAAA==.',
['Eì']='Eìrì:BAAANQAECgEJAgAAAA==.',
['Eô']='Eôwyn:BAAANQADCgYIDQAAAA==.',
Fa='Faclion:BAAANQAECgUJCQAAAA==.Faketurkey:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Falkhor:BAAANQAECgMIAwAAAA==.Fari:BAAANQAECgMIAwAAAA==.Farstryder:BAAANQADCgYIBgAAAA==.Fatlootz:BAABNQAECoEaAAIKAAcKMyPiGgDHAgAKAAcKMyPiGgDHAgAAAA==.',
Fe='Fellwarden:BAAANQADCgMIAwAAAA==.Feltyah:BAAANQADCgYJEwAAAA==.',
Fi='Finnajuggyou:BAAANQAECgIIAgAAAA==.Finniker:BAAANQAECgIIAgAAAA==.Fiorina:BAAANQAECgYJEAAAAA==.Firefóx:BAAANQADCggICAAAAA==.Fishnet:BAAANQAECgUJBwAAAA==.Fishthicc:BAAANQADCgYIEAAAAA==.',
Fl='Flashnikko:BAAANQADCgIIAgAAAA==.Flexkin:BAABNQAECoEYAAMUAAkKEx/ABQAmAwAUAAgKWCLABQAmAwASAAcKciNnFQDUAgAAAA==.',
Fo='Foe:BAACNQAFFIEGAAIMAAQKfhPuCABhAQAMAAQKfhPuCABhAQA1AAQKgRsAAwwACQpwHyMWAM8CAAwACQpwHyMWAM8CABUAAQpqFrUcADUAAAAA.Fornor:BAABNQAECoEaAAIOAAgKmR0nGACoAgAOAAgKmR0nGACoAgAAAA==.Foxfù:BAAANQADCgYIDAAAAA==.Foxkníght:BAABNQAECoEiAAIOAAkKlSOHBACbAwAOAAkKlSOHBACbAwAAAA==.Foxxalot:BAAANQADCgQIBAAAAA==.Foxxpachi:BAAANQAECgIJAgAAAA==.',
Fr='Franký:BAAANQADCgUIBgAAAA==.Frebaen:BAAANQAECgEJAQAAAA==.Frogus:BAAANQAECgUJCgAAAA==.',
Fu='Fungbuck:BAAANQADCgQIBAAAAA==.Fungbucko:BAAANQADCgcJBwAAAA==.Fuule:BAAANQAECgUJBQAAAA==.Fuusei:BAAANQAECgUICwAAAA==.',
Fy='Fyrdrakon:BAAANQAECgYJEAAAAA==.',
Ga='Gabeitch:BAAANQADCgMIAwAAAA==.Galapagós:BAAANQADCgQIBwABNQADCgUIBQABAAAAAA==.Galaxus:BAABNQAECoEhAAIbAAkKpRswCgAQAwAbAAkKpRswCgAQAwAAAA==.Gammastorm:BAAANQAECgcJEQAAAA==.Garokk:BAAANQADCgMJAwAAAA==.',
Gh='Ghall:BAAANQADCgIIAgAAAA==.Ghrell:BAEANQAECgYJDwAAAA==.',
Gi='Gickygackers:BAAANQADCgYIDgAAAA==.Gigglepeak:BAAANQAECgUICQAAAA==.Girlhands:BAAANQADCgIIAgAAAA==.',
Gl='Glekimage:BAAANQAECgMIAwAAAA==.',
Go='Goatmylk:BAAANQADCggJDwAAAA==.Gobblr:BAAANQADCgUJCAAAAA==.Goldensorbet:BAAANQADCgYIBgAAAA==.Golokis:BAAANQADCggICAABNQAECggIFgACAEAaAA==.Gonuhreeuh:BAAANQAECgYICgABNQAECgYIGgAWAGIQAA==.Gotz:BAAANQADCggIDgAAAA==.',
Gr='Grattick:BAAANQAECgEJAQAAAA==.Greenlightt:BAAANQADCgYJFgAAAA==.Greenxll:BAABNQAECoEZAAIcAAgKUyEQFAAOAwAcAAgKUyEQFAAOAwAAAA==.Greypa:BAAANQAECgUIBwAAAA==.Grezulock:BAEANQAECgIJBQAAAA==.Griggles:BAAANQAECgQICAAAAA==.Grikol:BAAANQADCgIIAgAAAA==.Grizzbane:BAAANQADCgEIAQAAAA==.Grolk:BAAANQAECgEJAQAAAA==.',
Gu='Guerita:BAAANQADCgUICQAAAA==.Gumptruck:BAAANQAECgYJEQAAAA==.',
Gw='Gwenevere:BAAANQADCgMIAwAAAA==.',
Ha='Habibii:BAAANQADCgQIBAAAAA==.Hakana:BAAANQADCgUJBwABNQAECgQJBgABAAAAAA==.Hardendaire:BAAANQADCgYIDQAAAA==.Hashypally:BAAANQAECgQIBAAAAA==.Hathern:BAAANQADCgIIAgAAAA==.Hawkmees:BAAANQAECgYJEwAAAA==.Hazbretzul:BAAANQAECgYICgAAAA==.',
He='Hediff:BAAANQADCgYIBgAAAA==.Heelza:BAAANQAECgUIBQAAAA==.Hellskitchën:BAAANQADCgQIBQAAAA==.Help:BAAANQAECgQIBQAAAA==.Hephs:BAAANQADCggJDwABNQAECgQICAABAAAAAA==.Hermionejean:BAAANQADCgUJBQAAAA==.Hexuz:BAAANQAECgQJBAAAAA==.',
Hi='Hipster:BAAANQAECgIIAwABNQABCgIIAgABAAAAAA==.',
Ho='Holeekow:BAAANQADCgEIAgAAAA==.Hollymollie:BAAANQAECgIJAgAAAA==.Holoey:BAAANQABCgIIAgAAAA==.Holymobeus:BAAANQAECgEIAQAAAA==.Holypower:BAAANQADCgYICQAAAA==.Holythot:BAAANQAECgYIEAAAAA==.Hoofanhammer:BAAANQADCgIJAwAAAA==.Howoriginal:BAAANQAECgcJBwAAAA==.Hozrozlok:BAAANQAECgYJDQAAAA==.',
Hu='Huntdry:BAAANQAECgUIDAAAAA==.Hurkoh:BAAANQAECgQIBQAAAA==.Hurrikin:BAAANQADCggJCAAAAA==.Hushpuppié:BAAANQAECgQJBwAAAA==.',
Hy='Hypereon:BAAANQAECgYIDwAAAA==.',
Ic='Iceden:BAAANQAECgIIAgAAAA==.Ichirosuzuki:BAAANQABCgYJCAAAAA==.Icyweenor:BAAANQAECgIIAgAAAA==.',
Id='Idkdude:BAAANQAECggIDwAAAA==.',
Ie='Ielarth:BAAANQADCgEIAQAAAA==.',
If='Ifhediehedie:BAAANQADCgcIBwAAAA==.',
Ih='Ihrasx:BAAANQAECggJBAAAAA==.',
Ik='Ikevzl:BAAANQADCgMIAwAAAA==.',
Il='Illadarina:BAAANQAECgYIEwAAAA==.Illí:BAAANQADCgcICAAAAA==.',
In='Incetardis:BAAANQADCgYIEwAAAA==.Indiriel:BAAANQAECgcJBgAAAA==.',
Ir='Iradoria:BAABNQAECoEeAAMRAAkK2xYgEwBvAgARAAgKEhcgEwBvAgAMAAMKexxTcAAVAQAAAA==.Ironplay:BAAANQADCgYJBgAAAA==.',
Is='Isoldè:BAAANQADCgcIBwAAAA==.Istabu:BAAANQAECgEIAQAAAA==.',
It='Itachi:BAACNQAFFIEQAAMOAAYKCBxsAABCAgAOAAYKCBxsAABCAgAdAAIKSRKvCQCfAAA1AAQKgSMAAw4ACQpbJpsCAMMDAA4ACQrmJZsCAMMDAB0ABgrNJfUSAIoCAAAA.Itamï:BAAANQAECgcIEQAAAA==.',
Iv='Ivannacream:BAAANQADCggIEAAAAA==.',
Ja='Jaagren:BAAANQAECgQJBAAAAA==.Jadawin:BAAANQAECgcIDgAAAA==.Jaketta:BAAANQAECgEJAQAAAA==.Jaquemehof:BAAANQAECgEIAQAAAA==.Jasnah:BAABNQAECoEgAAIWAAkKURUYUQCYAgAWAAkKURUYUQCYAgAAAA==.Jayrel:BAABNQAECoEiAAMVAAkK4hcFBgDaAQAMAAkKgxTtIwB3AgAVAAgKaxAFBgDaAQAAAA==.',
Je='Jerrik:BAAANQAECgYJDQAAAA==.',
Jo='Joedky:BAAANQADCgcIBwAAAA==.Joeyexotic:BAAANQAECgUJBwAAAA==.Jokem:BAAANQADCgUIBQAAAA==.Jozelyn:BAAANQADCgEJAQAAAA==.',
Ju='Juankkii:BAAANQADCggICgABNQAECgQIBwABAAAAAA==.Juggerbear:BAAANQAECgEJAQAAAA==.Juiçy:BAAANQAECgIJAgAAAA==.Juls:BAAANQAECgYJDgAAAA==.Justhetip:BAAANQADCgEJAQAAAA==.',
['Jä']='Jäger:BAAANQAECgQIBQAAAA==.',
Ka='Kagama:BAAANQAECgQIBQAAAA==.Kaladora:BAAANQAECgQJCgAAAA==.Kalatabi:BAAANQADCggICAABNQAECggIHgANAEcfAA==.Kalatai:BAABNQAECoEeAAINAAgKRx9GCAC/AgANAAgKRx9GCAC/AgAAAA==.Kamisenshi:BAAANQADCgIIAgAAAA==.Karayna:BAAANQAECgEIAQAAAA==.Kareemcheese:BAAANQAECgQJBgAAAA==.Kauko:BAAANQAECgUJDAAAAA==.',
Ke='Keadron:BAAANQADCgIIAgAAAA==.Kellanash:BAAANQADCgQIBAAAAA==.Kezwik:BAAANQAECgUICwAAAA==.',
Kh='Khaotick:BAAANQADCgYJFgAAAA==.Kheetz:BAAANQAECgEIAgAAAA==.',
Ki='Kiilg:BAAANQADCgYJBgAAAA==.Kikomo:BAAANQAECgEIAQAAAA==.Kikosho:BAAANQAECgUJDgAAAA==.Kilaaj:BAAANQADCgIIAgAAAA==.Killerbane:BAAANQADCgcJEAAAAA==.Killgoro:BAAANQADCgQIBAAAAA==.Kinclakis:BAAANQADCgQIBAAAAA==.Kinthor:BAAANQABCgIIAgAAAA==.Kirrin:BAAANQAECgcJEgAAAA==.',
Kn='Kneecap:BAAANQAECgYIDwAAAA==.Kneepad:BAAANQADCgcIBwAAAA==.Knetikara:BAABNQAECoEgAAMeAAgKJwgqEwD7AAAWAAcK9QIL7AAsAQAeAAUKugoqEwD7AAAAAA==.',
Ko='Kokokrantz:BAAANQAECgMIAwAAAA==.Korthix:BAAANQAECgUJDgAAAA==.Kosi:BAAANQAECgUICAAAAA==.',
Kr='Kraanan:BAAANQADCgUIBQAAAA==.Kraves:BAAANQAECgUIBQAAAA==.Kreiedril:BAAANQADCggJJAAAAA==.Krispytoo:BAAANQAECgYJDwAAAA==.Krompir:BAAANQADCgcJBwAAAA==.',
Ku='Kulltena:BAAANQADCggICAAAAA==.Kulltina:BAAANQADCggICAAAAA==.',
Ky='Kyokaii:BAAANQAECgYICgAAAA==.Kyrasala:BAAANQADCgIIAgAAAA==.',
La='Laarken:BAAANQADCggJGwAAAA==.Lacedtotems:BAABNQAECoEVAAIcAAkKtSTbBACtAwAcAAkKtSTbBACtAwAAAA==.Lagexe:BAAANQADCggIEQAAAA==.Laybia:BAAANQADCgEIAQAAAA==.Lazlo:BAAANQAECgQIAwAAAA==.',
Le='Leeleelooloo:BAAANQADCgYIBgAAAA==.Lenrela:BAAANQAECgUIDAAAAA==.Lestealth:BAAANQAECgIIBAAAAA==.Letena:BAABNQAECoEaAAISAAgKFwxcNgC6AQASAAgKFwxcNgC6AQAAAA==.Levyymage:BAAANQAECgYICgAAAA==.',
Li='Lialyndra:BAAANQADCgYICgAAAA==.Licelia:BAAANQAECgcJEQAAAA==.Lilballohate:BAAANQADCgEIAQAAAA==.Liligayle:BAAANQADCgMIAwAAAA==.Lilsxe:BAAANQADCgUJBQAAAA==.Linane:BAABNQAECoEWAAIDAAYK4BbSLACeAQADAAYK4BbSLACeAQAAAA==.Lite:BAAANQADCggICQABNQAECggIGgAXABsbAA==.Liveevil:BAAANQAFFAEIAQAAAA==.',
Ll='Llama:BAAANQADCgYIBgAAAA==.',
Lo='Loathsome:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.Lolmagician:BAAANQABCgIJAgABNQADCggJCAABAAAAAA==.Loquail:BAAANQADCgUIBQAAAA==.Lorgrith:BAAANQADCgcIBwAAAA==.Lorike:BAAANQAECggICgAAAA==.Losthobo:BAAANQADCgEIAQAAAA==.',
Lu='Lucifoor:BAAANQAECgEJAQAAAA==.Luftim:BAAANQAECgEIAQAAAA==.Lunastellara:BAAANQAECgEJAQAAAA==.Lunoxx:BAAANQAECgIJAgAAAA==.Lurang:BAAANQAECgMJBQAAAA==.',
Ma='Macacbre:BAAANQADCgYICQAAAA==.Macdotnalds:BAAANQADCgMIAwAAAA==.Madetolock:BAAANQADCgYJEAAAAA==.Maerlyna:BAAANQABCgIIAwAAAA==.Magebrew:BAAANQAECgEJAQAAAA==.Mageycat:BAAANQADCgYICAABNQAECgcIGAAMAA0cAA==.Magicma:BAAANQAECgQIBAABNQAECgUIBwABAAAAAA==.Mahlah:BAAANQABCgIIBAAAAA==.Makarov:BAAANQADCgEIAQAAAA==.Malevir:BAAANQABCgUIBQAAAA==.Maliun:BAAANQAECgUICgAAAA==.Malusdemon:BAAANQADCggJHgAAAA==.Mamasota:BAAANQAECgIIAgAAAA==.Marisol:BAAANQADCgYIEwAAAA==.Markfunk:BAABNQAECoEdAAIWAAkK7CIUDwCCAwAWAAkK7CIUDwCCAwAAAA==.Markiepoo:BAAANQADCgcIBwABNQAECgkJHQAWAOwiAA==.Markyboom:BAAANQADCgIIAgABNQAECgkJHQAWAOwiAA==.Markybowner:BAAANQAECggICAABNQAECgkJHQAWAOwiAA==.Markykong:BAAANQADCgcICwABNQAECgkJHQAWAOwiAA==.Maryjaiyne:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Mawmatz:BAAANQADCgEIAQAAAA==.',
Me='Mebashum:BAAANQAECgYIBAAAAA==.Medihunter:BAAANQADCgIIAgABNQAECgUJCAABAAAAAA==.Meditations:BAAANQAECgUJCAAAAA==.Meleath:BAAANQADCgEIAQAAAA==.Melibeth:BAAANQABCgEIAQAAAA==.Metrakatanke:BAAANQADCgQIBAAAAA==.Mexiflip:BAAANQADCgYICQAAAA==.',
Mi='Midoriya:BAAANQAECgMIAQAAAA==.Milgan:BAABNQAECoEaAAIJAAgKZh2LIQCLAgAJAAgKZh2LIQCLAgAAAA==.Minimochi:BAABNQAECoExAAIMAAkK9BAmLwA7AgAMAAkK9BAmLwA7AgAAAA==.Missblackk:BAAANQADCgIIAgAAAA==.Mithyr:BAAANQADCgcIBwABNQAECgIJAwABAAAAAA==.',
Mn='Mneme:BAABNQAECoEgAAIUAAkKWSTuAQCTAwAUAAkKWSTuAQCTAwAAAA==.',
Mo='Mogani:BAAANQADCgUIBwAAAA==.Monkeypiglet:BAABNQAECoERAAICAAcK9hoMUgAkAgACAAcK9hoMUgAkAgAAAA==.Moogpal:BAAANQAECgIJAwABNQAECgUIBwABAAAAAA==.Moogul:BAAANQAECgUIBwAAAA==.Moovoe:BAAANQAECgUJBwAAAA==.Morcarth:BAAANQAECgQIBQAAAA==.Mortal:BAAANQADCgEIAQAAAA==.Morts:BAAANQADCgYJBgAAAA==.',
Mu='Mulks:BAAANQAECgYIEQAAAA==.Multiblox:BAABNQAECoEXAAIfAAgKPRaPCQAfAgAfAAgKPRaPCQAfAgAAAA==.Murgruuk:BAAANQADCggJCAAAAA==.',
My='Myling:BAAANQADCggIAgAAAA==.',
['Mà']='Màrkham:BAAANQABCgYJCAAAAA==.',
['Må']='Måjïñßûüü:BAAANQADCggJCgAAAA==.',
Na='Naam:BAAANQAECgQICAAAAA==.Nadrin:BAAANQADCgYJFQAAAA==.Naedora:BAAANQAECgQICwAAAA==.Namixx:BAABNQAECoEXAAIVAAcK5hxpAwBjAgAVAAcK5hxpAwBjAgAAAA==.Naruwnd:BAAANQADCggJCAABNQAFFAUJCAAZAPkIAA==.Nathaanis:BAABNQAECoEZAAIYAAgKsRl/SwAmAgAYAAgKsRl/SwAmAgAAAA==.',
Ne='Necrodamus:BAAANQAECgEIAQAAAA==.Neliera:BAAANQABCgUIBQAAAA==.Neopolitangs:BAAANQAECgYICgAAAA==.Nevs:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Nevsy:BAAANQADCgYICAAAAA==.Nezdispenser:BAAANQAECgEIAQAAAA==.',
Ni='Niduash:BAAANQADCgMIAwAAAA==.Nightchill:BAAANQAECgUICQAAAA==.Nim:BAAANQADCgQIBAAAAA==.Nimbletoes:BAAANQAECgcIEgAAAA==.Ninabudhu:BAAANQADCggJEAAAAA==.Nirza:BAAANQAECgEJAQAAAA==.Niziel:BAABNQAECoEdAAMdAAgKexiNGABIAgAdAAgKexiNGABIAgAXAAEK3wf7lQA4AAAAAA==.',
No='Nofurrys:BAAANQADCggICQAAAA==.Nokorin:BAAANQAECgEIAgAAAA==.Nolo:BAAANQADCgUIBQABNQAECgkJIAAHABIiAA==.Noros:BAABNQAECoEgAAIHAAkKEiKgAwBpAwAHAAkKEiKgAwBpAwAAAA==.',
Nu='Nuggalicious:BAAANQAECgEIAQAAAA==.Nuggss:BAAANQABCgEJAQAAAA==.Nursjoy:BAAANQADCggICAAAAA==.',
Nv='Nveturkey:BAAANQAECgIIAgAAAA==.',
Ok='Oko:BAAANQAECgcICwAAAA==.',
Ol='Oldmanpeanut:BAAANQADCggICQABNQAECgQJCQABAAAAAA==.Olopa:BAAANQABCgIIAgAAAA==.',
Om='Omenwar:BAAANQADCggJIAAAAA==.Omni:BAAANQADCggICwAAAA==.',
Or='Orelia:BAAANQAECgMJAwAAAA==.Orfnanu:BAAANQADCggIDQABNQAECgIIAgABAAAAAA==.Ornarl:BAAANQAECgMJBgAAAA==.',
Ot='Ottawa:BAAANQADCgYIBgAAAA==.',
Ox='Oxsana:BAAANQAECgUJBgAAAA==.',
Pa='Packtastic:BAAANQAECgUJDgAAAA==.Padthang:BAAANQAECgYIDwAAAA==.Pakipot:BAAANQAECgIIAgAAAA==.Palazyn:BAAANQADCggIFQABNQAECgYIEwABAAAAAA==.Pallymar:BAAANQADCggICAABNQAECgkJGQAgAIckAA==.Panhexual:BAAANQADCgQIBAAAAA==.Parketor:BAAANQAECgUICAAAAA==.Pathyx:BAAANQAECgIIAgAAAA==.',
Pe='Peacefulguy:BAAANQABCgQIBgAAAA==.Peachjars:BAABNQAECoEeAAMKAAgKsyKlDwAQAwAKAAgKsyKlDwAQAwALAAQKExFULAD3AAAAAA==.Pelvis:BAAANQADCgQIBAABNQAECgIJAgABAAAAAA==.Perixi:BAAANQADCgYICgAAAA==.Perpekto:BAAANQADCgUIBQAAAA==.Peterpewpew:BAAANQAECgIIAgAAAA==.',
Ph='Phedragon:BAAANQADCgIIAgAAAA==.Phedrah:BAAANQAECgcIEQAAAA==.Philipx:BAAANQADCgQIBAAAAA==.Phookie:BAAANQADCgcJBwAAAA==.',
Pi='Picklenator:BAAANQAECgMIAwAAAA==.Pickléz:BAAANQADCgEJAQAAAA==.Pierreplays:BAAANQADCgUIBQAAAA==.Pillowhands:BAAANQADCgQIBAAAAA==.Pilto:BAAANQAECgUJCgAAAA==.Pingo:BAAANQAECgMJBAAAAA==.Pinkmj:BAAANQADCgMIBgAAAA==.Pitchief:BAAANQAECgUJBgAAAA==.',
Po='Polendina:BAABNQAECoEVAAMXAAgK1SO+DwDuAgAXAAgK0CK+DwDuAgAOAAcKVCIbFwCyAgAAAA==.Pooginator:BAAANQADCgYICAAAAA==.Porcelinà:BAAANQAECgQJBwABNQAECggIGAAEADgSAA==.',
Pr='Prada:BAAANQAECgEIAQAAAA==.Premmish:BAAANQADCggJCAAAAA==.Primeork:BAAANQADCgUIBQAAAA==.Prisca:BAAANQABCgcICwAAAA==.Prometheuss:BAAANQADCgQJBAAAAA==.',
Ps='Psammophile:BAAANQAECgcIEwAAAA==.Psymmer:BAAANQADCgYICAABNQAECgIJBAABAAAAAA==.Psynge:BAAANQADCgYICgABNQAECgIJBAABAAAAAA==.Psynnergy:BAAANQAECgIJBAAAAA==.Psytellar:BAAANQAECgEIAQABNQAECgIJBAABAAAAAA==.',
Pt='Ptsd:BAAANQAECgEIAQAAAA==.',
Pu='Pumprstltskn:BAAANQAECgUJCwAAAA==.Puppyflower:BAAANQADCggIDQAAAA==.Purplepally:BAAANQADCgEIAQAAAA==.Purpleshroom:BAAANQAECgIJAgAAAA==.Put:BAAANQADCgYJDwAAAA==.',
Py='Pyrat:BAAANQAECgQJBQAAAA==.Pyroangel:BAAANQAECgEIAgAAAA==.Pyrom:BAAANQADCgUIBQABNQADCgIIAgABAAAAAA==.Pyrotwopnto:BAAANQAECgEIAQAAAA==.',
['Pí']='Píneapple:BAAANQAECgIIAwAAAA==.',
Qe='Qertinya:BAAANQADCgYIEQAAAA==.',
Qu='Quadman:BAABNQAECoEWAAICAAkK+h4JIQD0AgACAAkK+h4JIQD0AgAAAA==.Quaxly:BAAANQADCgQIBAAAAA==.Quinexorable:BAABNQAECoEiAAIhAAkKqSJtAQCPAwAhAAkKqSJtAQCPAwAAAA==.',
Ra='Ragedaddy:BAABNQAECoEWAAICAAgKQBreQwBYAgACAAgKQBreQwBYAgAAAA==.Raglashar:BAAANQADCgQJBAAAAA==.Rahkar:BAAANQAECgYJDgAAAA==.Rainndance:BAAANQAECgQJCQAAAA==.Rainnhell:BAAANQADCgEIAQAAAA==.Raitan:BAAANQADCgQJDQAAAA==.Rallet:BAAANQADCgIIAgAAAA==.Ramrodveazy:BAAANQAECgQJCAAAAA==.Ranaklos:BAAANQADCgQIBAABNQADCgIIAgABAAAAAA==.Rancimus:BAAANQAECgQICAAAAA==.Rangore:BAAANQADCgQIBAAAAA==.Ranocthan:BAAANQAECgUJBgAAAA==.Rarcher:BAAANQAECgUJCgAAAA==.Rasmuz:BAAANQADCgYJEAAAAA==.Rauthar:BAAANQAECgQICAAAAA==.Rayyven:BAAANQAECggICAAAAA==.Razorken:BAAANQADCgYIBgAAAA==.Razorsharp:BAAANQAECgcJEQAAAA==.',
Re='Recon:BAABNQAECoEiAAMZAAgKPhBjBgDXAQAZAAgKPhBjBgDXAQAaAAQKoQIiJgCGAAAAAA==.Reefermadnes:BAABNQAECoEaAAMCAAgKmxQRYgDrAQACAAcKiBYRYgDrAQAhAAQK0AYUHwCyAAAAAA==.Reelsteel:BAAANQADCgcJFQAAAA==.Relnamah:BAAANQAECgEIAQAAAA==.Reoloc:BAEANQADCgYICQABNQAECgYJEQABAAAAAA==.Retandspank:BAAANQABCgQIBAAAAA==.Revdev:BAABNQAECoE7AAIYAAkKGRkPMQCTAgAYAAkKGRkPMQCTAgAAAA==.Revoke:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.Rezowulf:BAAANQAECgYJBQAAAA==.',
Rh='Rhapsydee:BAAANQADCgUIBQAAAA==.Rhododendron:BAAANQADCgcIBwAAAA==.Rhoñin:BAAANQABCgEIAQAAAA==.Rhuney:BAAANQAECgYJDgAAAA==.Rhunie:BAAANQADCgcIBwABNQAECgYJDgABAAAAAA==.Rhyllii:BAAANQAECgUIBwAAAA==.',
Ri='Riftmaker:BAAANQABCgIIAgAAAA==.Rivermage:BAAANQABCgIIAgAAAA==.',
Ro='Roadburner:BAAANQAECggJCQAAAA==.Roccotaco:BAAANQADCgYICgAAAA==.Roloch:BAAANQADCgYJBgAAAA==.Romenhoff:BAABNQAECoEZAAMUAAgKZRFZGADuAQAUAAgKZRFZGADuAQASAAUKWQedVwDvAAAAAA==.Rootbeer:BAAANQAECgEIAgABNQADCgYJBgABAAAAAA==.Roshambu:BAAANQAECgEJAQAAAA==.Roxinator:BAAANQAECgQJBAAAAA==.Roxorath:BAAANQADCgQJBAAAAA==.Roxyrocko:BAAANQADCgcIBwAAAA==.',
Ru='Ruikiea:BAAANQAECgQIBQABNQAECggJJgAcADkWAA==.Runahdan:BAAANQADCgcIBwABNQAECgYJDgABAAAAAA==.',
Ry='Ryomage:BAAANQABCgcJBwAAAA==.',
['Rà']='Ràggà:BAAANQAECgUICQAAAA==.',
['Rí']='Rían:BAAANQAECgIIAgAAAA==.',
Sa='Sacerdota:BAAANQADCgQIBAAAAA==.Saelenei:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Saevra:BAAANQADCgMIAwAAAA==.Sairadoka:BAAANQAECgMJBQAAAA==.Samzori:BAAANQAECgUJCwAAAA==.Sanatizer:BAAANQAECgYJEQAAAA==.Sandret:BAAANQAECgYICwAAAA==.Sarris:BAAANQAECgUIBQAAAA==.Sathriel:BAABNQAECoEWAAIOAAcKihIQMwDdAQAOAAcKihIQMwDdAQAAAA==.Savagebleedz:BAAANQADCggJCAAAAA==.Savagehealz:BAAANQADCgYJBgAAAA==.Savagetotemz:BAABNQAECoEaAAIcAAgKvRk3JwCAAgAcAAgKvRk3JwCAAgAAAA==.',
Sc='Scalelujah:BAAANQAECgQIBQABNQADCgYJBgABAAAAAA==.Scottadin:BAAANQAECgcIDwAAAA==.',
Se='Seanasy:BAAANQABCgIIAgAAAA==.Secondenvoy:BAAANQAECgQJCQAAAA==.Seerawh:BAAANQAECgYICgAAAA==.Sehetep:BAAANQAECgEIAQAAAA==.Sephyrea:BAAANQADCgYIBgAAAA==.Serigon:BAAANQADCgYJCgAAAA==.',
Sh='Shadownd:BAABNQAECoEcAAMMAAkKBSG3GAC/AgAMAAgK/x+3GAC/AgAVAAMKJx2kDgDeAAABNQAFFAUJCAAZAPkIAA==.Shadowsloth:BAAANQADCgYICQAAAA==.Shaevra:BAAANQADCgQIBAABNQAECgkJHQAFAIIfAA==.Shahli:BAAANQADCgIIAgAAAA==.Shakiro:BAAANQAECgQIDgAAAA==.Shaloendril:BAAANQADCgUICgAAAA==.Shalzind:BAAANQADCgIIAgAAAA==.Shamchan:BAAANQAECgUJCQAAAA==.Shamergency:BAAANQADCgYIEAAAAA==.Shammyrock:BAAANQAECgcIEAAAAA==.Shamtony:BAAANQABCgQIBgAAAA==.Sharkk:BAAANQAECgEIAQAAAA==.Shaylar:BAAANQAECgMJBAAAAA==.Sheisunholy:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Shiherlis:BAAANQADCggICwABNQAECgIJAgABAAAAAA==.Shmacken:BAAANQAECgYJEwAAAA==.Shockinglee:BAAANQAECgQJBQABNQAECgQIBwABAAAAAA==.Shosannaa:BAAANQAECgUJBwAAAA==.Shuriken:BAABNQAECoEkAAMFAAkK7CM9AwCOAwAFAAkK7CM9AwCOAwAQAAEK6RUM8gA9AAAAAA==.',
Si='Siete:BAAANQADCggIFgAAAA==.Sikblitz:BAAANQAECgMJBAAAAA==.Sikbubblez:BAAANQAECgYJEgAAAA==.Sikshockz:BAAANQAECgQJBAAAAA==.Silentblades:BAAANQAECgIIAgAAAA==.Sindazia:BAAANQADCggIDgAAAA==.Sinistry:BAAANQADCgUIBgAAAA==.Siopau:BAAANQADCgQIBAAAAA==.Sixunder:BAAANQADCgcIBwAAAA==.',
Sk='Skrinkles:BAAANQAECgQIBAAAAA==.Skullwhisper:BAAANQAECgUIDAAAAA==.',
Sl='Slomar:BAAANQAECgEJAQAAAA==.Slowar:BAAANQADCggICAAAAA==.Slowpallh:BAAANQADCgYICAABNQADCggICAABAAAAAA==.Slowrog:BAAANQADCgUIAwABNQADCggICAABAAAAAA==.Slowsh:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.',
Sm='Smoggely:BAAANQAECgUICQAAAA==.Smoketotem:BAAANQAECgMIBAAAAA==.',
Sn='Sneakzalot:BAAANQAECgEIAQAAAA==.Snowbreeze:BAAANQAECgMJBQAAAA==.Snowfláme:BAAANQAECgYJDgAAAA==.Snubz:BAAANQADCgYJBgAAAA==.',
So='Solarity:BAAANQABCgUIBQAAAA==.Solfyr:BAAANQADCgYIBgABNQAECgYJEAABAAAAAA==.Solie:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.Solki:BAAANQADCgIIAgAAAA==.Solrak:BAAANQAECgQICAAAAA==.Soobatai:BAAANQADCgYIBgAAAA==.Soot:BAAANQAECgYIBwABNQAECgcJBwABAAAAAA==.Soots:BAAANQAECgcJBwAAAA==.Sootzy:BAAANQAECgQIBgABNQAFFAcIEQALAAMcAA==.Sophiane:BAAANQAECgYIBwAAAA==.Soulcaller:BAAANQADCggICAAAAA==.Soulkhan:BAAANQADCgUIBQAAAA==.Soulkrusher:BAAANQAECgMIBQAAAA==.',
Sp='Spadeii:BAABNQAECoEhAAIOAAgKoRxlGAClAgAOAAgKoRxlGAClAgAAAA==.Spadex:BAAANQADCggIEAABNQAECggIIQAOAKEcAA==.Spagheddy:BAAANQADCggIDQAAAA==.Spankky:BAAANQAECgQJBAAAAA==.Spellzy:BAABNQAECoEaAAIWAAYKYhAtxgB1AQAWAAYKYhAtxgB1AQAAAA==.Spicylatina:BAAANQADCgYIBgAAAA==.',
Sq='Squachy:BAAANQADCgYIBgABNQAECgkJIgAVAOIXAA==.',
Ss='Sseoyoon:BAAANQAECgUICgAAAA==.Ssnneezzyy:BAAANQAECgUIDAAAAA==.',
St='Starwnd:BAAANQAECgUIBQABNQAFFAUJCAAZAPkIAA==.Steadchi:BAAANQAECgYICgAAAQ==.Stolibear:BAABNQAECoEVAAIfAAgKYR2iBQClAgAfAAgKYR2iBQClAgAAAA==.Stolidh:BAAANQAECgUIBgABNQAECggIFQAfAGEdAA==.Stolidk:BAAANQADCgUIBQABNQAECggIFQAfAGEdAA==.Stolip:BAAANQAECgEIAQABNQAECggIFQAfAGEdAA==.Stonedtothe:BAAANQADCgYIBgAAAA==.Stoneycrusty:BAABNQAECoEZAAIcAAcK7hSWSADQAQAcAAcK7hSWSADQAQAAAA==.Straywalker:BAAANQADCgEIAQAAAA==.Strongside:BAAANQAECgQIBAAAAA==.Stublimë:BAAANQAECgQJBgAAAA==.Studdie:BAAANQADCgYICQAAAA==.',
Su='Succeeds:BAAANQAECggJCAAAAA==.Sungjinwooz:BAAANQAECgQJBwAAAA==.Suntitan:BAAANQADCgIIAgABNQAECgUJCAABAAAAAA==.Suuhdude:BAAANQAECgQIDQABNQAECggIFgAbAPodAA==.Suzue:BAAANQAECgEIAQAAAA==.',
Sw='Swd:BAAANQAECggJCQAAAA==.Swiffty:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Swudge:BAAANQAECgIJAwAAAA==.',
Sy='Syladeith:BAAANQAECgUICgAAAA==.Sylandrus:BAAANQADCgYJBgAAAA==.Sylbanas:BAAANQADCgQICgABNQAECgQJCQABAAAAAA==.Syldrunk:BAAANQADCgcIDgAAAA==.Sylvashaman:BAAANQAECgUICQAAAA==.',
['Sé']='Séii:BAAANQADCgYIBgAAAA==.',
['Sÿ']='Sÿdney:BAAANQADCggICwAAAA==.',
Ta='Tabarnaka:BAAANQAECgQIBgAAAA==.Tairnock:BAAANQAECgUIBQAAAA==.Takabaka:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Tankadina:BAAANQADCgEIAQAAAA==.Tanzee:BAABNQAECoEiAAMMAAkK9Q+SNAAfAgAMAAkK9Q+SNAAfAgARAAEKpAsTWQApAAAAAA==.Tarmesan:BAABNQAECoEaAAIaAAkK4iDiAwA9AwAaAAkK4iDiAwA9AwAAAA==.Tastytooth:BAAANQAECgYJDQAAAA==.Taytaytyrone:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQAECgUICQAAAA==.',
Te='Tegadin:BAAANQADCgYIFgAAAA==.Telemanus:BAAANQADCgUIBQAAAA==.Telhani:BAAANQAECgQIBAAAAA==.Tesse:BAAANQAECgEIAQAAAA==.',
Th='Thadude:BAAANQAECgQJBAABNQAECggIGgAXABsbAA==.Thannos:BAABNQAECoEdAAIEAAkKOSODAwCdAwAEAAkKOSODAwCdAwAAAA==.Thanos:BAAANQAECgQIBAAAAA==.Thanozul:BAAANQAECgMJBAAAAA==.Thark:BAAANQAECgUJDAAAAA==.Thatonebear:BAAANQAECgMIAwAAAA==.Thawnn:BAAANQADCgQIBQAAAA==.Theberos:BAAANQADCgYIBgAAAA==.Thebighoss:BAAANQADCgQIBAAAAA==.Thedùde:BAAANQAECgQJBAABNQAECggIGgAXABsbAA==.Thelgrus:BAAANQADCggIIAAAAA==.Thoern:BAAANQADCggJDAAAAA==.Thorane:BAAANQADCgYJBgAAAA==.Thrashcan:BAAANQAECgQIBwAAAA==.Threem:BAAANQAECgEIAQAAAA==.Threepercent:BAAANQAECgcIDQAAAA==.Threesteps:BAAANQADCgIIAgAAAA==.Throad:BAAANQADCgcJCAAAAA==.Throatzilla:BAAANQAECgUJBQAAAA==.Throwbackhlz:BAAANQAECgQJBwAAAA==.Throwinshåde:BAAANQAECgUJBQAAAA==.Thudmuffin:BAAANQAECgQICAABNQAECgQIBwABAAAAAA==.Thyrealest:BAAANQADCgEJAQAAAA==.Thysania:BAAANQABCgYJCQABNQABCgIIAgABAAAAAA==.',
Ti='Tides:BAABNQAECoEXAAIJAAkKYBCIMgAtAgAJAAkKYBCIMgAtAgAAAA==.Tilyne:BAAANQABCgIJAgAAAA==.Tinarii:BAABNQAECoEaAAIiAAkKpiZfAADpAwAiAAkKpiZfAADpAwAAAA==.Tinyshadow:BAAANQAECgEJAQAAAA==.Tinytit:BAAANQAECgQIBAAAAA==.Tinytusk:BAAANQABCgIIAgAAAA==.Titdruid:BAAANQADCgUIBQAAAA==.Titpoosy:BAAANQADCgYICQAAAA==.Tiusele:BAAANQABCgEIAQAAAA==.',
To='Tonystonk:BAAANQAECgIJAwAAAA==.Toombz:BAAANQADCgYIBgAAAA==.Totemkoff:BAAANQABCgMIAwAAAA==.',
Tr='Tragha:BAAANQADCgcJCQAAAA==.Trayker:BAAANQADCgQIBAAAAA==.Traynisa:BAAANQADCgUICAAAAA==.Treykor:BAAANQADCgQIBAAAAA==.Tria:BAAANQAECgEIAwAAAA==.Trixrforkids:BAAANQADCgYIBgAAAA==.Trlight:BAAANQAECgcICQAAAA==.Trollsicle:BAAANQAECgQIBwAAAA==.Trotah:BAAANQADCgYICQAAAA==.Tryzz:BAAANQAECgUICwAAAA==.',
Tu='Tubhead:BAAANQAECgQIBAAAAA==.Tunare:BAAANQAECgIJAwAAAA==.Tusknflamer:BAAANQADCgUIBwAAAA==.',
Tw='Twoman:BAAANQAECgUIBQABNQAECgkJFgACAPoeAA==.Twylla:BAAANQAECgUIBgAAAA==.',
Ty='Tynak:BAAANQADCgQIBAAAAA==.',
Ug='Ugroto:BAAANQAECggJCAAAAA==.',
Ul='Uldred:BAAANQADCgUIBQABNQAECgkJHQAFAIIfAA==.',
Un='Unclesnottyp:BAAANQAECgEJAwAAAA==.Unmortal:BAAANQAECgUJDAAAAA==.',
Ur='Urotherdaddy:BAAANQAECgEIAQAAAA==.Uruker:BAAANQADCgIIAgAAAA==.',
Us='Useurblinker:BAAANQADCgcIBwAAAA==.',
Va='Valglacius:BAAANQADCgYICwAAAA==.Valkrin:BAAANQADCgYIBgAAAA==.Valonthir:BAAANQADCgQJDwAAAA==.Valstone:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.Vancleave:BAAANQAECgMJAwAAAA==.Vaylethrayne:BAAANQABCgQIBQAAAA==.',
Ve='Vend:BAAANQADCgEIAQAAAA==.Verguetta:BAAANQAECgQIBwAAAA==.Verinsedai:BAAANQAECgYJBwAAAA==.Vesimer:BAAANQADCggIFQAAAA==.',
Vi='Vicvondik:BAAANQADCgQIBAAAAA==.Vildri:BAAANQAECgMJBQAAAA==.Violetknight:BAAANQADCgIIAgAAAA==.',
Vo='Voidrey:BAAANQAECgMJBgAAAA==.Voikullten:BAAANQADCgUIBQAAAA==.Vornash:BAAANQAECgIIAgAAAA==.',
Vy='Vylent:BAAANQABCgUICAAAAA==.',
Wa='Waddleweaver:BAAANQADCggICAAAAA==.Wardogsix:BAAANQAECgYIBAAAAA==.Warkraz:BAAANQADCgMIAwAAAA==.Warrush:BAAANQAECgcIDgAAAA==.Watchmedps:BAAANQAECgIJAgAAAA==.',
Wi='Wildthang:BAAANQADCgQIBAAAAA==.Willhelt:BAAANQAECgMJBQAAAA==.Willpray:BAAANQAECgMJBgAAAA==.Windle:BAAANQAECgEJAQAAAA==.Windrunnér:BAAANQAECgQIBAAAAA==.Winterwølf:BAAANQADCgIJAgAAAA==.',
Wo='Wontondesire:BAAANQAECgcJEQAAAA==.Wowii:BAAANQAECggIAwAAAA==.',
Wu='Wulfpriest:BAAANQAECggJBwABNQAECgYJBQABAAAAAA==.',
Xa='Xantry:BAEANQAECgUJDQAAAA==.',
Xb='Xbambs:BAAANQADCgQIBAAAAA==.',
Xe='Xerovladej:BAAANQAECgQICAAAAA==.',
Xo='Xoog:BAAANQAECgEJAgAAAA==.Xozo:BAAANQADCgIIAgAAAA==.',
Xu='Xualene:BAAANQAECgUJBQABNQAECgQJCAABAAAAAA==.Xurk:BAAANQADCggICAAAAA==.',
Xw='Xwarrior:BAAANQAECgYJDwAAAA==.',
Ya='Yaaz:BAAANQAECgYICgAAAA==.Yamata:BAAANQADCgQIBAAAAA==.',
Ye='Yetistorm:BAAANQADCgMIAwAAAA==.',
Yo='Yoz:BAAANQAECgEIAQAAAA==.',
Yu='Yuee:BAAANQAECgMIAwAAAA==.Yukonicüs:BAAANQAECgYICgABNQAECgkJHAADACsgAA==.',
Za='Zaehara:BAAANQAECgEIAQAAAA==.Zanarian:BAAANQAECgEIAQAAAA==.Zappinboi:BAAANQAECgUIBwABNQAFFAUJDAAjACEQAA==.Zatkiel:BAAANQAECgEJAQAAAA==.',
Ze='Zealot:BAAANQAECgMIAwAAAA==.Zedar:BAAANQAECgYJCgABNQAECgYIBwABAAAAAA==.Zeju:BAAANQAECgEIAgAAAA==.Zekinett:BAAANQADCgUIBQAAAA==.Zekker:BAAANQADCgYICAAAAA==.Zenolinwæ:BAAANQAECgUJBQAAAA==.Zeohavoc:BAAANQADCgIIAgAAAA==.',
Zh='Zhondari:BAAANQAECgEJAQAAAA==.',
Zi='Zivanya:BAAANQAECgEIAQAAAA==.',
Zu='Zurprise:BAAANQADCgYICAAAAA==.',
Zx='Zxz:BAAANQAECgUJBwAAAA==.',
Zy='Zyrgarran:BAAANQADCgcJDgAAAA==.',
['Zá']='Záraya:BAABNQAECoEYAAMEAAgKOBI7OQATAgAEAAgKOBI7OQATAgAYAAEKfAZzKwEuAAAAAA==.',
['Zú']='Zúpái:BAAANQAECgEIAQAAAA==.',
['Àz']='Àzæs:BAAANQAECgEIAQAAAA==.',
['Ät']='Ätreo:BAAANQAECgQJBgAAAA==.',
['Æl']='Ælusive:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
['Ço']='Çondemned:BAAANQADCgQIBAABNQADCggIDQABAAAAAA==.',
['Ém']='Émperor:BAAANQADCgUIBQAAAA==.',
['Îc']='Îcyhot:BAAANQADCggIDQAAAA==.',
['Ðr']='Ðräx:BAAANQAECgQICwAAAA==.',
['Óh']='Óhelgur:BAAANQADCgIIAgAAAA==.',
['Öh']='Öhgr:BAAANQAECgMJBAAAAA==.',
['ßí']='ßíll:BAAANQADCggIEwAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
