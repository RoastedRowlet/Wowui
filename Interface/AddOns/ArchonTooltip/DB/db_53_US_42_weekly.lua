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

local lookup = {'Unknown-Unknown','Warrior-Arms','DemonHunter-Havoc','Paladin-Holy','Mage-Arcane','Shaman-Restoration','Hunter-Marksmanship','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Druid-Restoration','Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Paladin-Protection','DeathKnight-Unholy','Shaman-Enhancement','Priest-Shadow','Priest-Discipline','Druid-Balance','Druid-Feral','Warlock-Affliction','Mage-Fire','Paladin-Retribution','Shaman-Elemental','DeathKnight-Blood','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','DemonHunter-Devourer','Mage-Frost','DemonHunter-Vengeance','DeathKnight-Frost','Monk-Mistweaver','Warrior-Fury','Druid-Guardian','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Bonechewer',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aandras:BAAANQAECgUIDQAAAA==.',
Ab='Abbey:BAAANQADCgYIBgAAAA==.Abhayah:BAAANQAECgMIBwAAAA==.Absportls:BAAANQAECgUIDAAAAA==.',
Ac='Acelliste:BAAANQAECgcIEQAAAA==.Acrylix:BAAANQADCgYICAAAAA==.',
Ad='Adventurerr:BAAANQADCgMIBQAAAA==.',
Af='Affgrezz:BAEANQADCgQIBAABNQAECgUIDwABAAAAAA==.',
Ai='Aidlef:BAAANQAECgMIBAABNQAECgkJGQACABIfAA==.Aikenbranwen:BAAANQAECgEIAQAAAA==.Aillannia:BAAANQAECgYIBgAAAA==.',
Al='Alandor:BAAANQADCgUICgAAAA==.Aleathris:BAAANQAECgYICQAAAA==.Allfire:BAEBNQAECoEuAAIDAAkK9iCmCQBUAwADAAkK9iCmCQBUAwAAAA==.Alutier:BAAANQAECgEIAQAAAA==.Aluunix:BAAANQAECgYICwAAAA==.Alyse:BAABNQAECoEoAAIEAAkKdhyuHQDmAgAEAAkKdhyuHQDmAgAAAA==.Alyta:BAAANQADCggIGgAAAA==.Alzulra:BAAANQADCgYIBgAAAA==.',
Am='Amayla:BAAANQADCgcIBwAAAA==.Amoracon:BAAANQADCgUIBQAAAA==.',
An='Anilfizzur:BAAANQADCgMIAwAAAA==.Anubiá:BAAANQADCgYIBgAAAA==.Anulstorm:BAAANQADCgYIDgAAAA==.Anundir:BAABNQAECoEXAAIEAAcKyghShwBbAQAEAAcKyghShwBbAQAAAA==.',
Ao='Aoiue:BAAANQAECgMIBgAAAA==.Aondor:BAABNQAECoEiAAIFAAgKyhevhABcAgAFAAgKyhevhABcAgAAAA==.',
Ap='Applepi:BAAANQADCgEIAQAAAA==.',
Ar='Araenna:BAAANQADCgUIBQAAAA==.Arcanical:BAAANQADCgYIDAAAAA==.Arday:BAABNQAECoEfAAIDAAkKmh1SFgDKAgADAAkKmh1SFgDKAgAAAA==.Areala:BAAANQAECggICAAAAA==.Arksos:BAAANQADCgEIAQAAAA==.Aroldo:BAAANQAECgEIAQAAAA==.Aroromunroe:BAABNQAECoEYAAIGAAgK7BLDVgDfAQAGAAgK7BLDVgDfAQABNQADCggIDgABAAAAAA==.Arrancateta:BAAANQAECgQIDwAAAA==.',
As='Asena:BAAANQADCgQIBAABNQAFFAMIAwABAAAAAA==.Ashblast:BAAANQAECgQIBAAAAA==.Ashira:BAAANQAECgUICQABNQAECgkJIwAHAOMhAA==.Astarouge:BAABNQAECoEfAAIIAAkKECAACABAAwAIAAkKECAACABAAwAAAA==.Astrafury:BAAANQADCgcIBwAAAA==.Astrasneaky:BAABNQAECoEWAAQJAAkKwwqhDQBQAQAKAAcK4Qc6KgBXAQAJAAYK+wuhDQBQAQAIAAQK+QvjYgDYAAAAAA==.',
At='Atchafalaya:BAABNQAECoEbAAILAAcKuAcROAAnAQALAAcKuAcROAAnAQABNQAECggIIAALAMQGAA==.',
Av='Avatarstate:BAAANQADCgYICAAAAA==.Avonleâ:BAAANQAECgEIAQAAAA==.',
Aw='Awrina:BAABNQAECoEWAAIMAAcKaxpSWABBAgAMAAcKaxpSWABBAgAAAA==.',
Az='Azylrog:BAAANQADCggIEwAAAA==.',
Ba='Babymiko:BAAANQADCgQIBQAAAA==.Babypeech:BAAANQADCgYICwAAAA==.Bakudo:BAAANQABCgYICAAAAA==.Bakulu:BAAANQAECgQICAAAAA==.Bantoou:BAAANQAECgQICAAAAA==.Batcat:BAAANQADCgMIAwAAAA==.Bathoryz:BAABNQAECoEcAAMNAAgKORJGagD3AQANAAgKORJGagD3AQAOAAEKIwFWggAWAAAAAA==.Battlescars:BAAANQAECgIIAgAAAA==.Bauhaus:BAAANQADCgYIDwAAAA==.Bauld:BAAANQAECgUIDgAAAA==.',
Bd='Bdbypaladin:BAAANQABCgQIBAAAAA==.',
Be='Beacong:BAAANQAECggICAAAAA==.Beardybear:BAAANQAECgQIBgAAAA==.Bearface:BAAANQADCgYIBgAAAA==.Bearicaide:BAAANQAECgYIDAAAAA==.Bearnorgas:BAAANQADCggICAAAAA==.Beautiful:BAAANQADCgYIBgAAAA==.Beefygee:BAAANQADCgMIAwAAAA==.Belldrak:BAAANQADCgUIBQAAAA==.Belldren:BAAANQAECgEJAQAAAA==.Belldrin:BAAANQAECgQIBQAAAA==.Bepaulie:BAAANQADCgIIAgABNQAECgcICwABAAAAAA==.Bergidum:BAAANQADCgcJDAAAAA==.Beriamilbinc:BAAANQADCgYICAAAAA==.Bewmy:BAAANQAECgcICwAAAA==.',
Bh='Bhucket:BAAANQADCgEIAQAAAA==.',
Bi='Biglett:BAABNQAECoEbAAMMAAgKVSFOOwCVAgAMAAcK3iJOOwCVAgAHAAUKBRztNgBqAQAAAA==.Bignagos:BAAANQADCgYIFgAAAA==.Bigolboi:BAAANQAECgIIAwAAAA==.Bigthickheal:BAAANQADCgEIAQAAAA==.',
Bl='Blackk:BAABNQAECoEjAAIGAAkKLR7jGwDjAgAGAAkKLR7jGwDjAgAAAA==.Blackxcoffee:BAAANQADCgIIAgAAAA==.Bladesong:BAAANQAECgQIAQAAAA==.Blood:BAAANQAECgYICAAAAA==.Bloodietraks:BAAANQAECgQIBAAAAA==.Blorglock:BAABNQAECoEpAAMNAAkKfx2wPgB7AgANAAgKpxywPgB7AgAOAAQKZRrzJABBAQAAAA==.Blorgonp:BAAANQAECgUIBQABNQAECgkJKQANAH8dAA==.Blorgonw:BAAANQAECggIEAABNQAECgkJKQANAH8dAA==.Blowaegis:BAABNQAECoEbAAIMAAcKSRXUdgD0AQAMAAcKSRXUdgD0AQAAAA==.Blownoutshax:BAAANQADCgEIAQAAAA==.Bluntnfortys:BAAANQADCgYICwAAAA==.Blupenguiny:BAABNQAECoEjAAIPAAcK1wufdwB7AQAPAAcK1wufdwB7AQAAAA==.',
Bm='Bmfsleeps:BAAANQADCgUICAAAAA==.',
Bn='Bnortwarrior:BAAANQAECgQICQABNQAECgEIAQABAAAAAA==.',
Bo='Boanz:BAAANQAECgYIDwAAAA==.Bobasaurus:BAABNQAECoEgAAICAAkKiRw3NQDXAgACAAkKiRw3NQDXAgAAAA==.Bombastik:BAAANQAECgYICAAAAA==.Bonesnapp:BAAANQAECgMIAwABNQAECgkJKAAQAOohAA==.Booperry:BAAANQADCggICAAAAA==.Bosskün:BAAANQAECgUICwAAAA==.Bossticles:BAAANQAECgEIAQAAAA==.Bountie:BAABNQAECoEZAAIMAAgKhhW8VQBIAgAMAAgKhhW8VQBIAgAAAA==.Bountiè:BAAANQADCgEIAQABNQAECggIGQAMAIYVAA==.Boyoyong:BAAANQADCgQIBAABNQAECgUIBQABAAAAAA==.',
Br='Brainmatter:BAAANQADCgUICgAAAA==.Brandedsoul:BAAANQADCgIIAgAAAA==.Brewztler:BAAANQADCgcIHQAAAA==.Brightscale:BAAANQADCggIDgAAAA==.Brogak:BAAANQADCggIDQAAAA==.Broham:BAAANQAECgEIAQAAAA==.Bromeheal:BAAANQADCgIIAgAAAA==.Bronik:BAABNQAECoEiAAICAAgKlhNRfAACAgACAAgKlhNRfAACAgAAAA==.Brujaja:BAAANQADCggIEAAAAA==.',
Bu='Bubblebitc:BAAANQADCgYIBgAAAA==.Buffmage:BAABNQAECoElAAIFAAkKkRw2TwDTAgAFAAkKkRw2TwDTAgAAAA==.Bullman:BAAANQAECgQIBgABNQAECgkJIwARAJ8eAA==.Bullrûsh:BAAANQAECgYJCQAAAA==.Bullviper:BAAANQADCgYIDwAAAA==.Bumblbeetuna:BAAANQABCgIIAgAAAA==.Burnbrand:BAAANQAECgIIAgAAAA==.',
['Bè']='Bèrsèrk:BAAANQADCgcIBwABNQAECgkJKQASAE0cAA==.',
['Bì']='Bìgdaddy:BAAANQADCgYICwAAAA==.',
['Bø']='Bønestørm:BAABNQAECoEpAAISAAkKTRyzCADcAgASAAkKTRyzCADcAgAAAA==.',
['Bù']='Bùndee:BAAANQAECgUIEgAAAA==.',
Ca='Cabbâge:BAAANQADCgYIBgAAAA==.Cacapants:BAAANQADCgQIBQAAAA==.Cadencegs:BAAANQAECgYIDQAAAA==.Caliex:BAAANQAECgQIBAAAAA==.Califax:BAABNQAECoEjAAMHAAkK4yEJHABXAgAHAAcKVyAJHABXAgAMAAMKoiLL3gASAQAAAA==.Caller:BAAANQADCgIIAgAAAA==.Callsignwiz:BAAANQAECgYIDgAAAA==.Cannedbeans:BAAANQADCgMIAwAAAA==.Canuckcow:BAAANQADCgUICAAAAA==.Captantrips:BAAANQAECgIIAgAAAA==.Carltonswag:BAAANQADCgcIBwAAAA==.Catazhanir:BAAANQAECgMJAwAAAA==.Catclown:BAABNQAECoElAAMPAAgKmxsYMwB6AgAPAAgKmxsYMwB6AgATAAUKlhCcPAAcAQAAAA==.Cavonesee:BAAANQADCgcJCAAAAA==.Caylaramose:BAAANQADCggICAAAAA==.Cazsandra:BAABNQAECoElAAMPAAkK/x3iGwDrAgAPAAkK/x3iGwDrAgAUAAQKABRYDwAeAQAAAA==.',
Cc='Ccs:BAAANQADCgcIFAAAAA==.',
Ce='Ceeque:BAAANQABCgIIAgAAAA==.Centos:BAAANQABCgIIAgAAAA==.',
Ch='Chadsoss:BAAANQADCgYIBgAAAA==.Chamlio:BAAANQADCgYIHAAAAA==.Channis:BAAANQADCgQIAwAAAA==.Chenaccles:BAAANQAECgEIAQAAAA==.Chickenrally:BAABNQAECoEaAAICAAkKziEeFgBXAwACAAkKziEeFgBXAwAAAA==.Chicogel:BAAANQAECgYIBwABNQAECgYIFgAEAL0OAA==.Chinobear:BAAANQAECgQIBAAAAA==.Chixilog:BAAANQAECgUIBgAAAA==.Chodyboy:BAAANQABCgYIBgAAAA==.Cholmondeley:BAAANQADCgQIBAAAAA==.Chublie:BAAANQAECgUIBQAAAA==.Chuchix:BAABNQAECoEwAAQVAAkK2xskGQDkAgAVAAkKzBskGQDkAgALAAcKgxOnIwDbAQAWAAIK9BgSJwCdAAAAAA==.Chuckler:BAAANQAECggIEgAAAA==.',
Cl='Cladtu:BAAANQAECgUIEQAAAA==.Cleiah:BAAANQADCgUIBQAAAA==.Cloudfisto:BAAANQADCggJEwAAAA==.',
Co='Colacolaz:BAACNQAFFIETAAQOAAUKnCNpBADKAAANAAIKbSb7GwDmAAAOAAIK8iNpBADKAAAXAAEKTB0CCABWAAA1AAQKgTAAAw0ACQoPJgUFAJ8DAA0ACQp9JQUFAJ8DAA4ABgq5IwoLADsCAAAA.Colasham:BAABNQAECoEbAAISAAgK3yTOAwBWAwASAAgK3yTOAwBWAwABNQAFFAUIEwAOAJwjAA==.Coldhands:BAAANQADCgEIAQABNQAECgkJKgAIADUhAA==.Coldplunge:BAAANQAECgEIAQAAAA==.Colombiano:BAAANQAECgQICgABNQAECgYIFgAEAL0OAA==.Coltoff:BAACNQAFFIEJAAIPAAUKzgw+DgCHAQAPAAUKzgw+DgCHAQA1AAQKgScAAw8ACQrEGEgxAIICAA8ACQrEGEgxAIICABQAAQogAYwtABwAAAAA.Conker:BAAANQADCgUIBQAAAA==.Coolebra:BAAANQADCgIIAwAAAA==.Coprates:BAAANQAECgUIDgAAAA==.Corgiquester:BAAANQAECgQIBgAAAA==.Corpserot:BAAANQADCgEIAQAAAA==.Corsin:BAAANQAECgQIBAAAAA==.Cowbustion:BAABNQAECoEYAAMFAAYKMxxVuADwAQAFAAYKMxxVuADwAQAYAAEKLQSZDAAvAAAAAA==.',
Cp='Cptxcrunch:BAAANQADCgYICQAAAA==.',
Cr='Cracken:BAAANQADCggICgABNQAECggIFwAGAIYaAA==.Crankshot:BAAANQADCgYICgABNQAECgMIAwABAAAAAA==.Crimsonrayne:BAAANQAECgQIBQAAAA==.Cruciatus:BAAANQAECgUICQAAAA==.Crusherlol:BAAANQAECgYIDgAAAA==.Crusherlul:BAAANQAECgIJAgABNQAECgYIDgABAAAAAA==.',
Cu='Curfew:BAAANQAECgcIEgAAAA==.',
Cy='Cyrathis:BAAANQAECgcICQAAAA==.',
['Cà']='Càt:BAAANQADCgEIAQAAAA==.',
Da='Dabigoldk:BAAANQAECgUIBQAAAA==.Dahlya:BAAANQADCgEIAQABNQADCggICQABAAAAAA==.Dannzig:BAAANQADCgIJAgAAAA==.Daragon:BAAANQADCgEIAQABNQAFFAUICAATANMVAA==.Dargran:BAAANQABCgIIAgAAAA==.Darkravèn:BAABNQAECoEhAAILAAgKPAe6MQBYAQALAAgKPAe6MQBYAQAAAA==.Darthkitsune:BAAANQAECgMIAwAAAA==.Datbubblelol:BAABNQAECoEZAAIZAAkKpCDmGABNAwAZAAkKpCDmGABNAwAAAA==.Datchick:BAAANQADCggIHQAAAA==.Dawnkeeper:BAAANQADCgIIAgAAAA==.Dawnlily:BAAANQABCgcIDwAAAA==.Daxy:BAAANQADCgIIAgAAAA==.Daymandeuces:BAAANQAECggIAwAAAA==.Dazbek:BAABNQAECoEwAAIFAAkKvyDXJQA+AwAFAAkKvyDXJQA+AwAAAA==.',
De='Decày:BAAANQADCgUIBgABNQAECggIJAANABQkAA==.Deepdutch:BAABNQAECoEXAAIaAAcKBRVQZQDAAQAaAAcKBRVQZQDAAQAAAA==.Deezzeezz:BAAANQAECgUIDgABNQAECgkJNgAMANMfAA==.Degeneffe:BAAANQAECgUIDQAAAA==.Demoreknight:BAABNQAECoEmAAIbAAkKCRpVIgCJAgAbAAkKCRpVIgCJAgAAAA==.Devilboy:BAABNQAECoEfAAIRAAkKMyQNCABxAwARAAkKMyQNCABxAwAAAA==.Dextrey:BAAANQADCggICAABNQAECgUJDgABAAAAAA==.',
Di='Dialuptacos:BAAANQABCgYIBgAAAA==.Diddycombs:BAAANQADCgYIBgAAAA==.Discbrown:BAABNQAECoEeAAMTAAkKfR7QEQDCAgATAAkKfR7QEQDCAgAPAAEKeQJD3gA7AAAAAA==.Discmemommy:BAAANQAECgcIEAABNQAECggIJAANABQkAA==.Discontent:BAAANQAECgUICwAAAA==.Divinesmoke:BAAANQAECgEIAQAAAA==.',
Dj='Djblink:BAAANQAECgQIBAAAAA==.',
Dk='Dkgaming:BAAANQAECgQJCQABNQAECgcIEwABAAAAAA==.',
Do='Dogeared:BAABNQAECoEgAAILAAgKxAZWMwBLAQALAAgKxAZWMwBLAQAAAA==.Doloc:BAEANQAECgQIBQABNQAECgcIHgAcAJsSAA==.Domore:BAAANQAECgcIDQAAAA==.Donniedrako:BAAANQADCgQIBAAAAA==.Donson:BAABNQAECoEoAAIZAAkKeR7nLgDvAgAZAAkKeR7nLgDvAgAAAA==.Donsun:BAAANQADCgUIBQAAAA==.Doodlebobb:BAAANQAECgMIBAABNQAECgUICgABAAAAAA==.Doomlakalaka:BAAANQADCgcIHgAAAA==.Doomshamalam:BAAANQADCgQIBQAAAA==.Dorgh:BAAANQADCgIIAgAAAA==.Doskya:BAAANQAFFAIIBAAAAA==.Doubleclap:BAAANQADCggIEwAAAA==.',
Dp='Dpzofdoom:BAAANQAECgUIDwAAAA==.',
Dr='Dracthwnd:BAACNQAFFIEMAAMdAAUKQBGoAwCIAQAdAAUKQBGoAwCIAQAeAAIKYQjLCwB7AAA1AAQKgS8AAx0ACQqFJMgAAKkDAB0ACQqFJMgAAKkDAB4ACApNHG0QADECAAAA.Dragbrown:BAAANQADCgYIBgAAAA==.Dragonsins:BAABNQAECoEkAAINAAkKBSKiEgAvAwANAAkKBSKiEgAvAwAAAA==.Drahron:BAAANQADCggIAgAAAA==.Drdiksmasher:BAAANQAECgUIDgAAAA==.Drekka:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Drogmax:BAAANQAECgQIDQAAAA==.Droptopp:BAABNQAECoEbAAITAAkKOiM8BACIAwATAAkKOiM8BACIAwAAAA==.Drusys:BAAANQAECgUICgAAAA==.Dryrod:BAAANQADCgYIDAAAAA==.',
Du='Duckelf:BAABNQAECoEoAAILAAkKASRLAwCHAwALAAkKASRLAwCHAwAAAA==.Dunranger:BAAANQAECgEIAQAAAA==.Durrga:BAACNQAFFIEFAAICAAIK5hatJACaAAACAAIK5hatJACaAAA1AAQKgS0AAgIACQqnI8IKAJkDAAIACQqnI8IKAJkDAAAA.',
['Dà']='Dàb:BAAANQAECgUICgAAAA==.',
['Dã']='Dãftmõnk:BAABNQAECoEaAAIfAAgKxxHTIwDZAQAfAAgKxxHTIwDZAQAAAA==.',
['Dë']='Dëvildog:BAAANQADCggIDQAAAA==.',
Ed='Edgecrusherr:BAAANQAECgMJBAAAAA==.',
Eg='Egwenalmere:BAABNQAECoEdAAIDAAkKwAicPgCQAQADAAkKwAicPgCQAQAAAA==.',
El='Elainia:BAAANQADCgYIDgAAAA==.Elandae:BAAANQAECgEIAQAAAA==.Elinoosh:BAAANQADCgEIAQAAAA==.Elisaveta:BAAANQAECgMJAwAAAA==.Elliaa:BAAANQAECgQIBgAAAA==.Elliard:BAAANQADCgUICAAAAA==.Elmahikera:BAAANQADCggJCAABNQAECgkJHgATAPgWAA==.Elodi:BAAANQADCgYIBgAAAA==.',
Em='Emanx:BAAANQABCgIIAgABNQAECggIIAAZADwXAA==.Embér:BAAANQAECggICQAAAA==.',
En='Enheduanna:BAAANQADCgUICAAAAA==.',
Eo='Eowyen:BAAANQADCgUIBQAAAA==.',
Ep='Epiiphany:BAAANQADCgcICAAAAA==.',
Er='Eriaedria:BAAANQAECgMIAwAAAA==.Erinsister:BAAANQAECgcIEwAAAA==.Erydius:BAAANQAECgQIBwAAAA==.',
Es='Esdeath:BAAANQABCgIIAgAAAA==.',
Ev='Evilpalz:BAAANQADCgMIAwAAAA==.',
['Eì']='Eìrì:BAAANQAECgMIBwAAAA==.',
['Eô']='Eôwyn:BAAANQADCgcIFAAAAA==.',
Fa='Faclion:BAAANQAECgUJCQAAAA==.Faketurkey:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Falkhor:BAAANQAECgUIDAAAAA==.Fancyhorse:BAAANQABCgIIAgAAAA==.Fari:BAAANQAECgUIDAAAAA==.Farstryder:BAAANQADCgYIBgAAAA==.Fatlootz:BAABNQAECoEkAAINAAgKFCSVEgAvAwANAAgKFCSVEgAvAwAAAA==.',
Fe='Fellwarden:BAAANQADCgMIAwAAAA==.Feltyah:BAAANQADCgcIHQAAAA==.',
Fi='Finnajuggyou:BAAANQAECgIIAgAAAA==.Finniker:BAAANQAECgcICQAAAA==.Fiorina:BAABNQAECoEkAAIFAAgKrwdq3wCjAQAFAAgKrwdq3wCjAQAAAA==.Firefóx:BAAANQADCggICAAAAA==.Fishnet:BAAANQAECgUICgAAAA==.Fishthicc:BAAANQADCgYIEAAAAA==.',
Fl='Flashnikko:BAAANQADCgIIAgAAAA==.Flexkin:BAABNQAECoEoAAMVAAkKHSS2BQCfAwAVAAkKHSS2BQCfAwALAAkKtSEkBAB0AwAAAA==.Flicks:BAAANQAECgMIAwAAAA==.',
Fo='Foe:BAACNQAFFIEMAAIPAAUK0BacCgC4AQAPAAUK0BacCgC4AQA1AAQKgSAAAw8ACQpwH3EoAKoCAA8ACQpwH3EoAKoCABQAAQpqFi0nADAAAAAA.Fornor:BAABNQAECoEjAAIRAAkKnx4eHgC5AgARAAkKnx4eHgC5AgAAAA==.Foxfù:BAAANQADCgYIDAAAAA==.Foxkníght:BAACNQAFFIEFAAIRAAIKWiLyEADFAAARAAIKWiLyEADFAAA1AAQKgTIAAhEACQpHJnUBAOQDABEACQpHJnUBAOQDAAAA.Foxxalot:BAAANQADCgQIBAAAAA==.Foxxpachi:BAAANQAECgQIBwAAAA==.',
Fr='Franký:BAAANQAECgQIBAAAAA==.Franzia:BAAANQADCgIIAgAAAA==.Frebaen:BAAANQAECgQIBQAAAA==.Freezenikko:BAAANQADCgEIAQAAAA==.Frogus:BAAANQAECgUICgAAAA==.Frostednight:BAAANQADCgUICAAAAA==.',
Fu='Fungbuck:BAAANQADCgYIDgAAAA==.Fungbucko:BAAANQADCggIDgAAAA==.Fuule:BAAANQAECgYIDwAAAA==.Fuusei:BAABNQAECoEYAAMVAAcK5xSpPQDfAQAVAAcK5xSpPQDfAQALAAEKKAvybQAjAAAAAA==.',
Fy='Fyrdrakon:BAABNQAECoEhAAIeAAgKiRodDACMAgAeAAgKiRodDACMAgAAAA==.',
Ga='Gabeitch:BAAANQADCgMIAwAAAA==.Gahero:BAAANQADCgQIBAAAAA==.Galapagós:BAAANQADCgYIDQAAAA==.Galaxus:BAABNQAECoEiAAIgAAkKpRt1EADcAgAgAAkKpRt1EADcAgAAAA==.Gammastorm:BAABNQAECoEoAAIhAAgKiwpmDwCHAQAhAAgKiwpmDwCHAQAAAA==.Gandallfin:BAAANQADCgQIBAAAAA==.Garokk:BAAANQADCgYICAAAAA==.',
Gh='Ghall:BAAANQADCgIIAgAAAA==.Ghrell:BAEBNQAECoEiAAIWAAgKvR7WBgDQAgAWAAgKvR7WBgDQAgAAAA==.',
Gi='Gickygackers:BAAANQAECgQIBAAAAA==.Gigglepeak:BAABNQAECoEZAAIQAAgKSg0WJgCBAQAQAAgKSg0WJgCBAQAAAA==.Girlhands:BAAANQADCgIIAgAAAA==.',
Gl='Glekimage:BAAANQAECgMIAwAAAA==.',
Gn='Gnormage:BAAANQABCgEIAQAAAA==.',
Go='Goatmylk:BAAANQAECgQIBgAAAA==.Gobblr:BAAANQADCgUJCAAAAA==.Goldensorbet:BAAANQADCgYIBgAAAA==.Golokis:BAAANQADCggICAABNQAECggIHAACAP8aAA==.Gonuhreeuh:BAAANQAECgYICgABNQAECggIJwAFACEPAA==.Gotz:BAAANQADCggIEwAAAA==.',
Gr='Grattick:BAAANQAECgQIBwAAAA==.Greenlightt:BAAANQADCgYIHAAAAA==.Greenxll:BAABNQAECoEdAAIaAAkK7SFOEgBKAwAaAAkK7SFOEgBKAwAAAA==.Greypa:BAAANQAECgUIBwAAAA==.Grezulock:BAEANQAECgUIDwAAAA==.Griggles:BAAANQAECgQICAAAAA==.Grizzbane:BAAANQADCgEIAQAAAA==.Grizzleygrez:BAEANQADCgYICQABNQAECgUIDwABAAAAAA==.Grolk:BAAANQAECgIIAwAAAA==.',
Gu='Guerita:BAAANQADCgUICQAAAA==.Gumptruck:BAABNQAECoEeAAIRAAgKOCT6GADdAgARAAgKOCT6GADdAgAAAA==.',
Gw='Gwenevere:BAAANQADCgMIAwAAAA==.',
Ha='Habibii:BAAANQAECgQIBAAAAA==.Hakana:BAAANQADCgUJBwABNQAECgYIDAABAAAAAA==.Hardendaire:BAAANQADCgYIDQAAAA==.Hashypally:BAAANQAECgYICQAAAA==.Hathern:BAAANQADCgIIAgAAAA==.Hawkmees:BAABNQAECoEnAAMVAAgKphXGMQAvAgAVAAgKphXGMQAvAgALAAEKSQ4XaAAyAAAAAA==.Hazbretzul:BAAANQAECgYICgAAAA==.',
He='Hediff:BAAANQADCggIDQAAAA==.Heelza:BAAANQAECgYICwAAAA==.Hellskitchën:BAAANQADCgQIBQAAAA==.Hellxan:BAEANQAECgQIBAABNQAECggIHwAbALYRAA==.Help:BAAANQAECgUIDgAAAA==.Hephs:BAAANQAECgQIBgABNQAECgYIDgABAAAAAA==.Herlo:BAAANQAECgQICgAAAA==.Hermionejean:BAAANQADCgUJBQAAAA==.Hexuz:BAAANQAECgQIBAAAAA==.',
Hi='Hipster:BAAANQAECgIIAwABNQABCgIIAgABAAAAAA==.',
Ho='Holeekow:BAAANQADCgEIAgAAAA==.Hollymollie:BAAANQAECgYICAAAAA==.Holoey:BAAANQABCgIIAgAAAA==.Holymobeus:BAAANQAECgQIBwAAAA==.Holypower:BAAANQADCgYICQAAAA==.Holythot:BAABNQAECoEcAAITAAgKTxwpFgCJAgATAAgKTxwpFgCJAgAAAA==.Hoofanhammer:BAAANQADCgIIAwAAAA==.Hornzart:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.Howoriginal:BAABNQAECoEVAAIZAAcK7RKHmgC3AQAZAAcK7RKHmgC3AQABNQAECggIFwAgANEQAA==.Hozrozlok:BAABNQAECoEYAAMGAAkKfAzGYwCzAQAGAAkKfAzGYwCzAQAaAAUKHwniuQDwAAAAAA==.',
Hu='Huntdry:BAABNQAECoEaAAMMAAcKXCFrOwCUAgAMAAcKXCFrOwCUAgAHAAEK0Q7/eQA2AAAAAA==.Hurkoh:BAAANQAECgQIBQAAAA==.Hurrikin:BAAANQADCggJCAAAAA==.Hushpuppié:BAAANQAECgYIDQAAAA==.',
Hy='Hypereon:BAABNQAECoEhAAIQAAgKCiBlCgDWAgAQAAgKCiBlCgDWAgAAAA==.',
Ic='Iceden:BAAANQAECgQICgAAAA==.Ichirosuzuki:BAAANQABCgYICAAAAA==.Icyweenor:BAAANQAECgIIAgAAAA==.',
Id='Idkdude:BAAANQAECggIEQAAAA==.',
Ie='Ielarth:BAAANQADCgEIAQAAAA==.',
If='Ifhediehedie:BAAANQADCgcIBwAAAA==.',
Ig='Ignateus:BAAANQADCgIIAgAAAA==.',
Ih='Ihrasx:BAAANQAECggIDAAAAA==.',
Ik='Ikeepdying:BAAANQAECgEIAQAAAA==.Ikevzl:BAAANQAECgEIAQAAAA==.',
Il='Illadarina:BAABNQAECoEbAAIiAAgKYhDpDQCtAQAiAAgKYhDpDQCtAQAAAA==.Illys:BAAANQADCgEIAQAAAA==.Illí:BAAANQADCgcICAAAAA==.',
In='Incetardis:BAAANQADCgcIGgAAAA==.Indiriel:BAAANQAECgcIBgAAAA==.',
Ir='Iradoria:BAABNQAECoEkAAMTAAkKxhmSEwCtAgATAAkKxhmSEwCtAgAPAAQKiBcqhgBKAQAAAA==.Ironplay:BAAANQAECgMIAwAAAA==.',
Is='Isoldè:BAAANQADCgcIBwAAAA==.Istabu:BAAANQAECgcIDgAAAA==.',
It='Itachi:BAACNQAFFIERAAMRAAYKyBxPBADLAQARAAYKCBxPBADLAQAjAAMK0xc6CgD0AAA1AAQKgSYAAyMACQpcJnYDAJ4DACMACQrVJXYDAJ4DABEACQrmJWgOADADAAAA.Itamï:BAABNQAECoEdAAIbAAkKYRAFOwD3AQAbAAkKYRAFOwD3AQAAAA==.',
Iv='Ivannacream:BAAANQAECgIIAgAAAA==.',
Ja='Jaagren:BAAANQAECgQJBAAAAA==.Jadawin:BAABNQAECoEXAAIEAAgKqQrgbQCmAQAEAAgKqQrgbQCmAQAAAA==.Jaketta:BAAANQAECgEIAQAAAA==.Jaquemehof:BAAANQAECgEIAQAAAA==.Jasnah:BAACNQAFFIEJAAIFAAMKuw2eLQDmAAAFAAMKuw2eLQDmAAA1AAQKgSkAAgUACQqZGKFtAI0CAAUACQqZGKFtAI0CAAAA.Jayrel:BAACNQAFFIEFAAIPAAIKixEdIQChAAAPAAIKixEdIQChAAA1AAQKgTIAAxQACQofGYMIAMIBAA8ACQqwFlAzAHkCABQACAprEIMIAMIBAAAA.Jaytheg:BAAANQAECgQIBQAAAA==.',
Je='Jerrik:BAABNQAECoEeAAIZAAgKXxJMhgDoAQAZAAgKXxJMhgDoAQAAAA==.',
Ji='Jillean:BAAANQAECggICAAAAA==.',
Jo='Joedky:BAAANQADCgcIBwAAAA==.Joeyexotic:BAAANQAECgUICgAAAA==.Jokem:BAAANQADCgUIBQAAAA==.Jozelyn:BAAANQADCgEJAQAAAA==.',
Ju='Juankkii:BAAANQADCggICgABNQAECgQIBwABAAAAAA==.Juggerbear:BAAANQAECgEJAQAAAA==.Juiçy:BAAANQAECgUICwAAAA==.Juls:BAAANQAECgcIDwAAAA==.Julìette:BAAANQADCgEIAQAAAA==.Justhetip:BAAANQADCgEIAQAAAA==.Justjason:BAAANQAECgIIAwAAAA==.',
['Jä']='Jäger:BAAANQAECgQIBQAAAA==.',
Ka='Kagama:BAAANQAECgQIBQAAAA==.Kaladora:BAAANQAECgUIEwAAAA==.Kalatabi:BAAANQADCggICAABNQAECgkJKAAQAOohAA==.Kalatai:BAABNQAECoEoAAIQAAkK6iFHBQBFAwAQAAkK6iFHBQBFAwAAAA==.Kamisenshi:BAAANQADCgIIAgAAAA==.Kamkanzakur:BAAANQAECgEIAQAAAA==.Kaosforged:BAAANQAECgIIAgAAAA==.Kaosstorm:BAAANQAECgQIBQAAAA==.Karayna:BAAANQAECgcIDgAAAA==.Kareemcheese:BAAANQAECgQJBgAAAA==.Kauko:BAAANQAECggIEgAAAA==.',
Ke='Keadron:BAAANQADCgIIAgAAAA==.Kellanash:BAAANQADCgUICAAAAA==.Kezwik:BAAANQAECgUICwAAAA==.',
Kh='Khaotick:BAAANQADCgYIHAAAAA==.Kheetz:BAAANQAECgEIAgAAAA==.',
Ki='Kiilg:BAAANQADCgYIEQAAAA==.Kikomo:BAAANQAECgEIAQAAAA==.Kikosho:BAABNQAECoEfAAMkAAYK1BmxGQC3AQAkAAYK1BmxGQC3AQAfAAEK1RE9XgA1AAAAAA==.Kilaaj:BAAANQADCgIIAgAAAA==.Killerbane:BAAANQADCgcJEAAAAA==.Killgoro:BAAANQADCggIEAAAAA==.Kinclakis:BAAANQADCgQIBAAAAA==.Kinthor:BAAANQABCgIIAgAAAA==.Kirrin:BAABNQAECoEVAAIVAAgKjxnkMAA1AgAVAAgKjxnkMAA1AgAAAA==.Kisaragi:BAAANQAECgQIBAAAAA==.',
Kn='Kneecap:BAABNQAECoEhAAIEAAgKYSSMDABWAwAEAAgKYSSMDABWAwAAAA==.Kneepad:BAAANQADCgcIBwAAAA==.Knetikara:BAABNQAECoEvAAMhAAgK1AxNDgCaAQAhAAgKlgxNDgCaAQAFAAgKOgM0DQFQAQAAAA==.',
Ko='Kokokrantz:BAAANQAECgMIAwAAAA==.Korthix:BAAANQAECgUJDgAAAA==.Kosi:BAABNQAECoEeAAIgAAgKjw14KADgAQAgAAgKjw14KADgAQAAAA==.',
Kr='Kraanan:BAAANQADCgUIBQAAAA==.Krabs:BAAANQADCgMIAwAAAA==.Kraves:BAAANQAECgUICwAAAA==.Kreiedril:BAAANQADCggIJwAAAA==.Krispytoo:BAABNQAECoEVAAMPAAkKZRzlFwAAAwAPAAkKZRzlFwAAAwATAAIKAxVcVQCGAAAAAA==.Krompir:BAAANQADCgcJBwAAAA==.',
Ku='Kulltena:BAAANQADCggICAAAAA==.Kulltina:BAAANQADCggICAAAAA==.Kurnous:BAAANQADCgUIBQAAAA==.',
Ky='Kyokaii:BAABNQAECoEWAAMCAAYKGAvPvgBNAQACAAYKGAvPvgBNAQAlAAEK0gYHMAAtAAAAAA==.Kyrasala:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíngcoyote:BAAANQAECggIAgAAAA==.',
La='Laarken:BAAANQAECgEIAQAAAA==.Lacedtotems:BAACNQAFFIEEAAIaAAMKDBs8EgAMAQAaAAMKDBs8EgAMAQA1AAQKgRcAAhoACQoEJdIJAI0DABoACQoEJdIJAI0DAAAA.Lagexe:BAAANQAECgMIAwAAAA==.Laybia:BAAANQADCgEIAQAAAA==.Lazlo:BAAANQAECgQIAwAAAA==.',
Le='Lenrela:BAABNQAECoEbAAIWAAcKSBhhDQAQAgAWAAcKSBhhDQAQAgAAAA==.Leroenus:BAAANQADCgEIAQAAAA==.Lestealth:BAAANQAECgMICAABNQAECgQIBAABAAAAAA==.Letena:BAABNQAECoElAAIVAAkKFA34PQDdAQAVAAkKFA34PQDdAQAAAA==.Levyymage:BAAANQAECgYIEwAAAA==.',
Li='Lialyndra:BAAANQADCgYICgAAAA==.Licelia:BAAANQAECgcIEQAAAA==.Lilballohate:BAAANQADCgEIAQAAAA==.Liligayle:BAAANQADCgMIAwAAAA==.Lilsxe:BAAANQADCgUJBQAAAA==.Lilypadz:BAAANQADCggICAAAAA==.Linane:BAABNQAECoEvAAIDAAgKuh58FgDIAgADAAgKuh58FgDIAgAAAA==.Lite:BAAANQADCggICQABNQAECgcIBwABAAAAAA==.Liveevil:BAAANQAFFAEIAQAAAA==.',
Ll='Llama:BAAANQADCgYIBgAAAA==.',
Lo='Loathsome:BAAANQADCgEIAQABNQAECgQICgABAAAAAA==.Locksummnplz:BAAANQAECgQIBAAAAA==.Lolmagician:BAAANQABCgIJAgABNQADCggJCAABAAAAAA==.Loquail:BAAANQADCgUIBQAAAA==.Lorgrith:BAAANQAECgQIBwAAAA==.Lorike:BAAANQAECggICgAAAA==.Losthobo:BAAANQADCgEIAQAAAA==.',
Lu='Lucifoor:BAAANQAECgIIAgAAAA==.Luftim:BAAANQAECgEIAQAAAA==.Lunastellara:BAAANQAECgcIDAAAAA==.Lunoxx:BAAANQAECgIIAwAAAA==.Lurang:BAAANQAECgUIDgAAAA==.',
Ma='Macacbre:BAAANQADCgcICwAAAA==.Macdotnalds:BAAANQADCgMIAwAAAA==.Madetolock:BAAANQADCgYIFgAAAA==.Maerlyna:BAAANQABCgIIAwAAAA==.Magebrew:BAAANQAECgQIBQAAAA==.Mageycat:BAAANQADCgYICAABNQAECggIJQAPAJsbAA==.Magicma:BAAANQAECgQIBAABNQAECgUICgABAAAAAA==.Magiks:BAAANQAECgEIAQAAAA==.Mahlah:BAAANQABCgQIBgAAAA==.Makarov:BAAANQADCgEIAQAAAA==.Maladen:BAAANQADCgQIBAAAAA==.Malevir:BAAANQABCgUIBQAAAA==.Maliun:BAABNQAECoEYAAIaAAcK8Rk0TAAZAgAaAAcK8Rk0TAAZAgAAAA==.Malusdemon:BAAANQAECgQIBQAAAA==.Mamasota:BAAANQAECgUIDAAAAA==.Marisol:BAAANQADCgYIGQAAAA==.Markfunk:BAABNQAECoEsAAIFAAkKqyMfEwCAAwAFAAkKqyMfEwCAAwAAAA==.Markiepoo:BAAANQAECgYICgABNQAECgkJLAAFAKsjAA==.Markyboom:BAAANQADCgIIAgABNQAECgkJLAAFAKsjAA==.Markybowner:BAABNQAECoEYAAIMAAgKqxxuOQCbAgAMAAgKqxxuOQCbAgABNQAECgkJLAAFAKsjAA==.Markykong:BAAANQAECgcIBwABNQAECgkJLAAFAKsjAA==.Martimusmagi:BAAANQADCgIIAgAAAA==.Maryjaiyne:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Mawmatz:BAAANQADCgEIAQAAAA==.',
Me='Mebashum:BAAANQAECgYIBAAAAA==.Mechavexi:BAAANQAECgYIBgAAAA==.Medihunter:BAAANQAECgEIAQABNQAECgcIFwAZADUSAA==.Meditations:BAABNQAECoEXAAIZAAcKNRIAnwCsAQAZAAcKNRIAnwCsAQAAAA==.Megumi:BAAANQAECgQIBAAAAA==.Meleath:BAAANQADCgEIAQAAAA==.Melibeth:BAAANQABCgEIAQAAAA==.Metrakatanke:BAAANQADCgYICgAAAA==.Mexiflip:BAAANQADCgYICQAAAA==.',
Mi='Miamin:BAAANQAECgQIBAAAAA==.Midoriya:BAAANQAECgMIAQAAAA==.Mikeshifter:BAAANQAECgMIBwABNQADCgIIAgABAAAAAA==.Milgan:BAABNQAECoEiAAIGAAkKHCCxFgABAwAGAAkKHCCxFgABAwAAAA==.Minimochi:BAABNQAECoFFAAIPAAkKRB3uFgAGAwAPAAkKRB3uFgAGAwAAAA==.Missblackk:BAAANQADCgIIAgAAAA==.Mithyr:BAAANQADCgcIBwABNQAECgUICAABAAAAAA==.',
Mn='Mneme:BAACNQAFFIEQAAILAAUKlyQpAgAiAgALAAUKlyQpAgAiAgA1AAQKgSQAAgsACQpZJC0EAHMDAAsACQpZJC0EAHMDAAAA.',
Mo='Mogani:BAAANQAECgcIDAAAAA==.Mohrdren:BAAANQADCgYIBgAAAA==.Momoland:BAAANQAECgUICgAAAA==.Monkeypiglet:BAABNQAECoEUAAICAAcKUhtvdgARAgACAAcKUhtvdgARAgAAAA==.Moobiwan:BAAANQAECgIIAgABNQADCgIIAgABAAAAAA==.Moogpal:BAAANQAECgMIBQABNQAECgUICgABAAAAAA==.Moogul:BAAANQAECgUICgAAAA==.Moovoe:BAAANQAECgUICgAAAA==.Morcarth:BAAANQAECgQIBQAAAA==.Mortal:BAAANQADCgEIAQAAAA==.Morts:BAAANQADCgYJBgAAAA==.',
Mu='Mulks:BAABNQAECoEXAAIGAAcKkww+hwBKAQAGAAcKkww+hwBKAQAAAA==.Multiblox:BAABNQAECoEnAAImAAkK6h7mBAAtAwAmAAkK6h7mBAAtAwAAAA==.Murgruuk:BAAANQADCggICQAAAA==.',
My='Myling:BAAANQADCggIAgAAAA==.',
['Mà']='Màrkham:BAAANQABCgYJCAAAAA==.',
['Má']='Mágé:BAAANQAECgYICAABNQAECgkJHwAVAFAZAA==.',
['Må']='Måjïñßûüü:BAAANQAECgIIAgAAAA==.',
Na='Naam:BAAANQAECgYIDgAAAA==.Nadrin:BAAANQADCggIHQAAAA==.Naedora:BAABNQAECoEeAAMUAAgKSRodBAB9AgAUAAgKSRodBAB9AgAPAAEKVAvw5gAqAAAAAA==.Namixx:BAABNQAECoEiAAIUAAgKsBzIAgDLAgAUAAgKsBzIAgDLAgAAAA==.Naruwnd:BAAANQADCggICAABNQAFFAUIDAAdAEARAA==.Nassaela:BAAANQAECgYIBgABNQAECggIEQABAAAAAA==.Nathaanis:BAABNQAECoEZAAIZAAgKsRl5fgD8AQAZAAgKsRl5fgD8AQAAAA==.',
Ne='Necrodamus:BAAANQAECgEIAQAAAA==.Neliera:BAAANQABCgUIBQAAAA==.Neopolitangs:BAAANQAECgcIDQAAAA==.Nevs:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Nevsy:BAAANQADCgYICAAAAA==.Nezdispenser:BAAANQAECgMIBAAAAA==.',
Ni='Niduash:BAAANQADCgMIAwAAAA==.Nightchill:BAAANQAECgUICQAAAA==.Nim:BAAANQAECgEIAQAAAA==.Nimbletoes:BAABNQAECoEYAAIgAAcKwBxVIAAtAgAgAAcKwBxVIAAtAgAAAA==.Ninabudhu:BAAANQADCggJEAAAAA==.Nirza:BAAANQAECgIIAwAAAA==.Nixara:BAAANQADCggICAAAAA==.Niziel:BAABNQAECoEoAAMjAAkKORudGwCHAgAjAAkKORudGwCHAgAbAAEK3we+uAA4AAAAAA==.',
No='Nofurrys:BAAANQADCggICQAAAA==.Nokorin:BAAANQAECgEIAgAAAA==.Nolo:BAAANQADCgUIBQABNQAFFAQIBgAIAJcgAA==.Nomamesrko:BAAANQADCgEIAQAAAA==.Noranis:BAAANQAECgEIAQAAAA==.Noros:BAACNQAFFIEGAAIIAAQKlyAHBgCIAQAIAAQKlyAHBgCIAQA1AAQKgScAAggACQo0JP8EAG4DAAgACQo0JP8EAG4DAAAA.',
Nu='Nuggalicious:BAAANQAECgQIBQAAAA==.Nuggss:BAAANQABCgEIAQAAAA==.Nursjoy:BAAANQADCggICQAAAA==.Nuumm:BAAANQADCgIIAgAAAA==.',
Nv='Nveturkey:BAAANQAECgIIAgAAAA==.',
Ok='Oko:BAABNQAECoEYAAMRAAcKZhwJPgABAgARAAcKZhwJPgABAgAjAAcKEhCPQACBAQAAAA==.',
Ol='Oldmanpeanut:BAAANQADCggICQABNQAECgcIEwABAAAAAA==.Olopa:BAAANQABCgQIBQAAAA==.',
Om='Omenwar:BAAANQADCggJIAAAAA==.Omni:BAAANQADCggICwAAAA==.',
Or='Orcazum:BAAANQAECgUICQAAAA==.Orelia:BAAANQAECgMJAwAAAA==.Orfnanu:BAAANQADCggIDQABNQAECgQIBgABAAAAAA==.Ornarl:BAAANQAECgMJBgAAAA==.',
Ot='Ottawa:BAAANQADCgYIBgAAAA==.',
Ox='Oxsana:BAAANQAECgUJBgAAAA==.',
Pa='Packtastic:BAABNQAECoEdAAMNAAcKQBYEoQBkAQANAAUKHxcEoQBkAQAOAAIKFBRgUQB/AAAAAA==.Padthang:BAAANQAECgcIEwAAAA==.Pakipot:BAAANQAECgQIBAAAAA==.Palazyn:BAAANQADCggIHQABNQAECggIGwAiAGIQAA==.Pallymar:BAAANQAECgIIAgAAAA==.Panhexual:BAAANQADCgQIBAAAAA==.Papadude:BAAANQAECgcIBwAAAA==.Parketor:BAABNQAECoEWAAIFAAcKzRzwhgBXAgAFAAcKzRzwhgBXAgAAAA==.Pathyx:BAAANQAECgMIBAAAAA==.',
Pe='Peacefulguy:BAAANQABCgQIBgAAAA==.Peachjars:BAABNQAECoEtAAMNAAkKzCNTBwCDAwANAAkKzCNTBwCDAwAOAAQKExFGMwDrAAAAAA==.Pelvis:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.Perixi:BAAANQADCgYICgAAAA==.Perpekto:BAAANQADCgUIBQAAAA==.Peterpewpew:BAAANQAECgIIAgAAAA==.',
Ph='Phedragon:BAAANQAECgMIBAAAAA==.Phedrah:BAABNQAECoEZAAIaAAkKAxWaPABaAgAaAAkKAxWaPABaAgAAAA==.Philipx:BAAANQADCgQIBAAAAA==.Phookie:BAAANQADCgcIBwAAAA==.',
Pi='Picklenator:BAAANQAECgQICwAAAA==.Pickléz:BAAANQADCgEIAgAAAA==.Pierreplays:BAAANQADCgUIBQAAAA==.Pillowhands:BAAANQADCgQIBAAAAA==.Pilto:BAAANQAECgcIEgAAAA==.Pingo:BAAANQAECgUIDgAAAA==.Pinkmj:BAAANQADCgMIBgAAAA==.Pitchief:BAAANQAECgUIDgAAAA==.',
Po='Pokiplate:BAAANQADCgUIBQAAAA==.Polendina:BAABNQAECoEdAAMbAAkKCiS6GQDJAgAbAAgK0CK6GQDJAgARAAgKRCR/HADFAgAAAA==.Pooginator:BAAANQADCgYICAAAAA==.Porcelinà:BAAANQAECgcIDwABNQAECggIIAAEADUWAA==.',
Pr='Prada:BAAANQAECgEIAQAAAA==.Premmish:BAAANQADCggJCAAAAA==.Primeork:BAAANQADCgUIBQAAAA==.Prisca:BAAANQABCggIDgAAAA==.Pritasth:BAAANQAECgEIAQAAAA==.Prometheuss:BAAANQADCgQIBAAAAA==.',
Ps='Psammophile:BAABNQAECoEiAAIFAAkKjx/KLgAkAwAFAAkKjx/KLgAkAwAAAA==.Psymmer:BAAANQADCgYICAABNQAECgUIDQABAAAAAA==.Psynge:BAAANQADCgYICgABNQAECgUIDQABAAAAAA==.Psynnergy:BAAANQAECgUIDQAAAA==.Psytellar:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.',
Pt='Ptsd:BAAANQAECgEIAQAAAA==.',
Pu='Pumprstltskn:BAAANQAECgUIDgAAAA==.Puppyflower:BAAANQADCggIDQAAAA==.Purplepally:BAAANQADCgEIAQAAAA==.Purpleshroom:BAAANQAECgMIAwABNQAECgQICAABAAAAAA==.Put:BAAANQADCgYJDwAAAA==.',
Py='Pyrat:BAAANQAECgUIDwAAAA==.Pyroangel:BAAANQAECgQICAAAAA==.Pyrom:BAAANQADCgUIBQABNQADCgIIAgABAAAAAA==.Pyrotwopnto:BAAANQAECgEIAgAAAA==.',
['Pë']='Pëstilëncë:BAAANQADCgcIBwAAAA==.',
['Pí']='Píneapple:BAAANQAECgIIAwAAAA==.',
Qe='Qertinya:BAAANQADCgYIEQAAAA==.',
Qu='Quadman:BAABNQAECoEZAAICAAkKEh/9OQDGAgACAAkKEh/9OQDGAgAAAA==.Quaxly:BAAANQADCgQIBAAAAA==.Quinexorable:BAACNQAFFIEFAAInAAIKYx1GBACsAAAnAAIKYx1GBACsAAA1AAQKgTIAAicACQq5JY4AAN4DACcACQq5JY4AAN4DAAAA.',
Qy='Qyl:BAAANQADCgMIAwAAAA==.',
Ra='Ragedaddy:BAABNQAECoEcAAICAAgK/xo8ZQBAAgACAAgK/xo8ZQBAAgAAAA==.Raglashar:BAAANQADCgQJBAAAAA==.Rahkar:BAAANQAECgYJDgAAAA==.Rainndance:BAAANQAECgYIDgAAAA==.Rainnhell:BAAANQADCgEIAQAAAA==.Raitan:BAAANQADCggIEQAAAA==.Raitazzak:BAAANQAECgQIBAAAAA==.Rallet:BAAANQADCgIIAgAAAA==.Ramrodveazy:BAAANQAECgYIEwAAAA==.Ranaklos:BAAANQADCgQIBAABNQADCgIIAgABAAAAAA==.Rancimus:BAAANQAECgQICAAAAA==.Rangore:BAAANQADCgQIBAAAAA==.Ranocthan:BAAANQAECgUIDgAAAA==.Rarcher:BAAANQAECgUJCgAAAA==.Rasmuz:BAAANQADCgYIFgAAAA==.Rauthar:BAAANQAECgYIDgAAAA==.Rayyven:BAABNQAECoEZAAINAAkKGg0TagD4AQANAAkKGg0TagD4AQAAAA==.Razorken:BAAANQADCgYIBgAAAA==.Razorsharp:BAABNQAECoEhAAIbAAgKaxk4JwBqAgAbAAgKaxk4JwBqAgAAAA==.',
Re='Recon:BAABNQAECoEiAAMdAAgKPhC4CQCzAQAdAAgKPhC4CQCzAQAeAAQKoQK6LgB9AAAAAA==.Reefermadnes:BAABNQAECoEpAAMCAAgKqBc2dgARAgACAAgKAhY2dgARAgAnAAcKPA+YGAB4AQAAAA==.Reelsteel:BAAANQADCgcIFgAAAA==.Relnamah:BAAANQAECgQIBgAAAA==.Reoloc:BAEANQADCgYICQABNQAECgcIHgAcAJsSAA==.Retandspank:BAAANQABCgQIBAAAAA==.Revdev:BAABNQAECoFPAAIZAAkK1h71JQATAwAZAAkK1h71JQATAwAAAA==.Revils:BAAANQAECgMIAwAAAA==.Revoke:BAAANQADCgEIAQABNQAECgQICgABAAAAAA==.Reyn:BAAANQAECgQIBAAAAA==.Rezowulf:BAAANQAECgYIDwAAAA==.',
Rh='Rhapsydee:BAAANQADCgUIBQAAAA==.Rhododendron:BAAANQADCggICAAAAA==.Rhoñin:BAAANQABCgEIAQAAAA==.Rhuney:BAAANQAECgcIEAAAAA==.Rhunie:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.Rhyllii:BAAANQAECgYIEgAAAA==.Rhäenyra:BAAANQADCgQIBAAAAA==.',
Ri='Riftmaker:BAAANQABCgIIAgAAAA==.Rivermage:BAAANQABCgIIAgAAAA==.',
Ro='Roadburner:BAAANQAECggICwAAAA==.Roccotaco:BAAANQADCgYICgAAAA==.Roloc:BAEANQAECgQIBgABNQAECgcIHgAcAJsSAA==.Roloch:BAAANQAECgMIAwABNQAECggIGgAhAN8SAA==.Romenhoff:BAABNQAECoEmAAMLAAkK/RXXFQByAgALAAkK/RXXFQByAgAVAAYK4gpoXwApAQAAAA==.Rootbeer:BAAANQAECgEIAgABNQAECgQIBQABAAAAAA==.Roshambu:BAAANQAECgIIAwAAAA==.Roxinator:BAAANQAECgQICAAAAA==.Roxorath:BAAANQADCgQIBAAAAA==.Roxyrocko:BAAANQADCggIDgAAAA==.',
Ru='Ruikiea:BAAANQAECgYIBgABNQAECgkJMwAaACMWAA==.Runahdan:BAAANQAECgUIBQABNQAECgcIEAABAAAAAA==.',
Ry='Ryomage:BAAANQABCgcJBwAAAA==.',
['Rà']='Ràggà:BAABNQAECoEYAAIZAAgKrQjzrwCGAQAZAAgKrQjzrwCGAQAAAA==.',
['Rí']='Rían:BAAANQAECgYICAAAAA==.',
Sa='Sacerdota:BAAANQADCgUICQAAAA==.Saelenei:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Saevra:BAAANQADCgMIAwAAAA==.Sairadoka:BAAANQAECgUIDgAAAA==.Samzori:BAAANQAECgcIEwAAAA==.Sanatizer:BAABNQAECoEiAAIVAAgKwBuQJQCFAgAVAAgKwBuQJQCFAgAAAA==.Sandret:BAAANQAECgYIDgAAAA==.Sarris:BAAANQAECgUICwAAAA==.Sathriel:BAABNQAECoEfAAIRAAgKZhbWOQAXAgARAAgKZhbWOQAXAgAAAA==.Savagebleedz:BAAANQAECgUIBQAAAA==.Savagehealz:BAAANQADCgYJBgAAAA==.Savagetotemz:BAABNQAECoEoAAIaAAgKwSCPHgD4AgAaAAgKwSCPHgD4AgAAAA==.',
Sc='Scalelujah:BAAANQAECgUICwABNQAECgQIBQABAAAAAA==.Scottadin:BAABNQAECoEeAAMEAAkKDxY6MACKAgAEAAkKDxY6MACKAgAZAAQKnQiQGgG7AAAAAA==.',
Se='Seanasy:BAAANQABCgIIAgAAAA==.Secondenvoy:BAAANQAECgQIDQAAAA==.Seerawh:BAAANQAECgYICgAAAA==.Sehetep:BAAANQAECgEIAQAAAA==.Sellithe:BAAANQAECgIIAgAAAA==.Sephyrea:BAAANQADCgYIBgAAAA==.Serigon:BAAANQAECgQIBAAAAA==.',
Sh='Shadownd:BAACNQAFFIEKAAIPAAMKhR7tFAAhAQAPAAMKhR7tFAAhAQA1AAQKgSEAAw8ACQodIbMlALcCAA8ACApGILMlALcCABQAAwonHXITANYAAAE1AAUUBQgMAB0AQBEA.Shadowsloth:BAAANQADCgYICQAAAA==.Shadymcgee:BAAANQAECgUICAAAAA==.Shaevra:BAAANQADCgQIBAABNQAECgkJIwAHAOMhAA==.Shahli:BAAANQADCgIIAgAAAA==.Shakiro:BAABNQAECoEWAAIEAAYKvQ6zkwA7AQAEAAYKvQ6zkwA7AQAAAA==.Shaloendril:BAAANQAECgIIAQABNQAECgkJJwAZAHEbAA==.Shalzind:BAAANQAECgEIAQAAAA==.Shamchan:BAAANQAECgYIDgAAAA==.Shamergency:BAAANQADCggIGAAAAA==.Shammyrock:BAABNQAECoEaAAISAAgKVx/fCQDDAgASAAgKVx/fCQDDAgAAAA==.Shamtony:BAAANQABCgQIBgAAAA==.Sharkk:BAAANQAECgQICgAAAA==.Shaylar:BAAANQAECgMJBAAAAA==.Sheisunholy:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Shiherlis:BAAANQAECgQICAAAAA==.Shmacken:BAABNQAECoEXAAMGAAgKhhqcOABVAgAGAAgKhhqcOABVAgAaAAEK2AObMAEkAAAAAA==.Shockinglee:BAAANQAECgQJBQABNQAECgQICgABAAAAAA==.Shoryuken:BAAANQAECgIIAgAAAA==.Shosannaa:BAAANQAECgYIDQAAAA==.Shuriken:BAACNQAFFIEFAAIHAAIKRyAcFQC3AAAHAAIKRyAcFQC3AAA1AAQKgTUAAwcACQoLJYYCALEDAAcACQoLJYYCALEDAAwAAQrpFVA5ATkAAAAA.',
Si='Siete:BAAANQADCggIFgAAAA==.Sikblitz:BAAANQAECgQICQAAAA==.Sikbubblez:BAABNQAECoEkAAIZAAgKahrFVABuAgAZAAgKahrFVABuAgAAAA==.Sikdemonz:BAAANQADCggICAAAAA==.Sikshockz:BAAANQAECgYIEAAAAA==.Silentblades:BAAANQAECgIIAgAAAA==.Sindazia:BAAANQAECgQIBwAAAA==.Sinistry:BAAANQADCgUIBgAAAA==.Siopau:BAAANQADCgQIBAAAAA==.Sixunder:BAAANQADCgcIBwAAAA==.',
Sk='Skrinkles:BAAANQAECgYIBgAAAA==.Skullwhisper:BAAANQAECgYIEAAAAA==.',
Sl='Slomar:BAAANQAECgIIAwAAAA==.Slowar:BAAANQADCggICAAAAA==.Slowpallh:BAAANQADCgYICAABNQADCggICAABAAAAAA==.Slowrog:BAAANQADCgUIAwABNQADCggICAABAAAAAA==.Slowsh:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.',
Sm='Smashlo:BAAANQAECgEIAQAAAA==.Smoggely:BAAANQAECgUICQAAAA==.Smoketotem:BAAANQAECgUIDQAAAA==.',
Sn='Sneakzalot:BAAANQAECgEIAQAAAA==.Sneevle:BAAANQAECgIIAgABNQAECgYIGAAFADMcAA==.Snowbreeze:BAAANQAECgUIDgAAAA==.Snowfláme:BAABNQAECoEgAAIZAAgKPBdEagAwAgAZAAgKPBdEagAwAgAAAA==.Snubz:BAAANQADCgYIBgAAAA==.',
So='Solarity:BAAANQABCgUIBQAAAA==.Solfyr:BAAANQADCgYIBgABNQAECggIIQAeAIkaAA==.Solie:BAAANQADCgQIBAABNQAECgYICAABAAAAAA==.Solki:BAAANQADCgIIAgAAAA==.Solrak:BAAANQAECgYIEwAAAA==.Soobatai:BAAANQADCgYIBgAAAA==.Soot:BAAANQAECgYIBwABNQAECgcIDgABAAAAAA==.Soots:BAAANQAECgcIDgAAAA==.Sootzy:BAAANQAECgQIBgABNQAFFAcIHAAOAAchAA==.Sophiane:BAAANQAECgcIDwAAAA==.Soulcaller:BAAANQADCggICAAAAA==.Soulkhan:BAAANQADCgUIBQAAAA==.Soulkrusher:BAAANQAECgMIBQAAAA==.',
Sp='Spadeii:BAABNQAECoEtAAIRAAkKHxybJQCIAgARAAkKHxybJQCIAgAAAA==.Spadex:BAAANQADCggIEAABNQAECgkJLQARAB8cAA==.Spagheddy:BAAANQADCggIDQAAAA==.Spankky:BAAANQAECgQIBAAAAA==.Spellzy:BAABNQAECoEnAAIFAAcKIQ+73QCmAQAFAAcKIQ+73QCmAQAAAA==.Spicylatina:BAAANQADCgYIBgAAAA==.',
Sq='Squachy:BAAANQADCgYIBgABNQAFFAIIBQAPAIsRAA==.',
Ss='Sseoyoon:BAABNQAECoEUAAILAAcKswknOAAmAQALAAcKswknOAAmAQAAAA==.Ssnneezzyy:BAABNQAECoEXAAICAAcKSQ27qACLAQACAAcKSQ27qACLAQAAAA==.',
St='Starwnd:BAAANQAECgUIBQABNQAFFAUIDAAdAEARAA==.Steadchi:BAAANQAECgcIGAAAAQ==.Stolibear:BAABNQAECoEmAAImAAkKsyFEAwBuAwAmAAkKsyFEAwBuAwAAAA==.Stolidh:BAAANQAECgUICQABNQAECgkJJgAmALMhAA==.Stolidk:BAAANQADCgUIBQABNQAECgkJJgAmALMhAA==.Stolip:BAAANQAECgMIBAABNQAECgkJJgAmALMhAA==.Stonedtothe:BAAANQAECgQIDAAAAA==.Stoneycrusty:BAABNQAECoEuAAIaAAgKkhb/QgA+AgAaAAgKkhb/QgA+AgAAAA==.Straywalker:BAAANQADCgEIAQAAAA==.Strongside:BAAANQAECgQIBAAAAA==.Stublimë:BAAANQAECgUIEAAAAA==.Studdie:BAAANQADCgYICQAAAA==.',
Su='Succeeds:BAAANQAECggICwAAAA==.Sungjinwooz:BAAANQAECgYIEQAAAA==.Suntitan:BAAANQADCgIIAgABNQAECgcIGAAGAGUZAA==.Suuhdude:BAABNQAECoEdAAISAAcKixjKDwBSAgASAAcKixjKDwBSAgABNQAECgkJKQAgAOMhAA==.Suzue:BAAANQAECgEIAQAAAA==.',
Sw='Swd:BAABNQAECoEWAAIPAAgK+BiKNAB0AgAPAAgK+BiKNAB0AgAAAA==.Swiffty:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Swudge:BAAANQAECgQICgAAAA==.',
Sy='Syladeith:BAAANQAECgUIDAAAAA==.Sylandrus:BAAANQADCgYJBgAAAA==.Sylbanas:BAAANQADCgQICgABNQAECgcIEwABAAAAAA==.Syldrunk:BAAANQADCgcIDgAAAA==.Sylvashaman:BAAANQAECgUICQAAAA==.',
Sz='Szolkarr:BAAANQAECgYIBgAAAA==.',
['Sé']='Séii:BAAANQADCgYIBgAAAA==.',
['Sÿ']='Sÿdney:BAAANQADCggICwAAAA==.',
Ta='Tabarnaka:BAAANQAECgQICQAAAA==.Tairnock:BAAANQAECgcIDAAAAA==.Takabaka:BAAANQAECgUIBQAAAA==.Tamira:BAAANQAECgEIAQAAAA==.Tankadina:BAAANQADCgEIAQAAAA==.Tanzee:BAACNQAFFIEFAAIPAAIKDQhaJgCJAAAPAAIKDQhaJgCJAAA1AAQKgTIAAw8ACQrrEtY+AEoCAA8ACQrrEtY+AEoCABMAAQqkC5t0ACgAAAAA.Tarmarion:BAAANQAECgYIDAABNQAECgkJJAAeAAQiAA==.Tarmesan:BAABNQAECoEkAAIeAAkKBCIDBABQAwAeAAkKBCIDBABQAwAAAA==.Tastytooth:BAABNQAECoEXAAMDAAgK8QW+RQBgAQADAAgK8QW+RQBgAQAgAAMKuwBYXAA/AAAAAA==.Taytaytyrone:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQAECgUICQAAAA==.',
Te='Tegadin:BAAANQADCgYIHAAAAA==.Telemanus:BAAANQADCgUIBQAAAA==.Telhani:BAAANQAECgQICAAAAA==.Tesse:BAAANQAECgEIAQAAAA==.',
Th='Thadude:BAAANQAECgQIBAABNQAECgcIBwABAAAAAA==.Thannos:BAABNQAECoEjAAIEAAkKOSPQBgCJAwAEAAkKOSPQBgCJAwAAAA==.Thanos:BAAANQAFFAEIAQAAAA==.Thanozul:BAAANQAECgYIDwAAAA==.Thark:BAAANQAECgcIEQAAAA==.Thatonebear:BAAANQAECgYIBgAAAA==.Thawnn:BAAANQADCgQIBQAAAA==.Theberos:BAAANQADCggIDAAAAA==.Thebigd:BAAANQADCgQIBAAAAA==.Thebighoss:BAAANQAECgIIAgAAAA==.Thedùde:BAAANQAECgQIBAABNQAECgcIBwABAAAAAA==.Thelgrus:BAAANQADCggIIAAAAA==.Thesmanmeta:BAAANQADCgUIBQAAAA==.Thoern:BAAANQAECgEIAQAAAA==.Thorane:BAAANQADCgYJBgAAAA==.Thrashcan:BAAANQAECgQIBwABNQAECgYIDgABAAAAAA==.Threem:BAAANQAECgEIAQAAAA==.Threepercent:BAABNQAECoEdAAMMAAgKlRmGSQBqAgAMAAgKlRmGSQBqAgAHAAEK9wHVhwAlAAAAAA==.Threesteps:BAAANQADCgIIAgAAAA==.Throad:BAAANQADCgcJCAAAAA==.Throatzilla:BAAANQAECgUICAAAAA==.Throwbackhlz:BAAANQAECgYIEwAAAA==.Throwinshåde:BAAANQAECgUJBQAAAA==.Thudmuffin:BAAANQAECgQICAABNQAECgQICgABAAAAAA==.Thundersfury:BAAANQADCgEIAQAAAA==.Thyrealest:BAAANQADCgEJAQAAAA==.Thysania:BAAANQABCgYICQABNQABCgIIAgABAAAAAA==.',
Ti='Tides:BAABNQAECoEnAAMGAAkK+xWJNwBZAgAGAAkK+xWJNwBZAgAaAAEKtQHEMwEiAAAAAA==.Tilyne:BAAANQABCgIIAgAAAA==.Tinarii:BAACNQAFFIEJAAIoAAQKWSa5AQDQAQAoAAQKWSa5AQDQAQA1AAQKgR4AAigACQqqJowAAN4DACgACQqqJowAAN4DAAAA.Tinyshadow:BAAANQAECgMIBQAAAA==.Tinytit:BAAANQAECgQIBAAAAA==.Tinytusk:BAAANQABCgIIAgAAAA==.Titdruid:BAAANQADCgUIBQAAAA==.Titpoosy:BAAANQADCgYICQAAAA==.Tiusele:BAAANQABCgEIAQAAAA==.Tizali:BAAANQADCgUIBQABNQAECgkJIwAHAOMhAA==.',
To='Tonystonk:BAAANQAECgUIDAAAAA==.Toombz:BAAANQADCgYIBgAAAA==.Toreto:BAAANQADCgEIAgAAAA==.Totemkoff:BAAANQABCgMIAwAAAA==.Toureg:BAAANQAECgUICAAAAA==.',
Tr='Tragha:BAAANQADCggIEQAAAA==.Trayker:BAAANQADCgQIBAAAAA==.Traynisa:BAAANQADCgUICAAAAA==.Treykor:BAAANQADCgQIBAAAAA==.Tria:BAAANQAECgEIAwAAAA==.Trixrforkids:BAAANQAECgEIAQAAAA==.Trlight:BAAANQAECgcICQAAAA==.Trollsicle:BAAANQAECgQICgAAAA==.Trotah:BAAANQADCgYICQAAAA==.Tryzz:BAAANQAECgUICwAAAA==.',
Tu='Tubhead:BAAANQAECgQIDAAAAA==.Tumamaesmia:BAAANQAECgQIBgABNQAECgYIFgAEAL0OAA==.Tunare:BAAANQAECgUICAAAAA==.Tusknflamer:BAAANQADCgUIBwAAAA==.',
Tw='Twentyrats:BAAANQAECgEIAQAAAA==.Twoman:BAAANQAECgUIBQABNQAECgkJGQACABIfAA==.Twylla:BAAANQAECgUIBgAAAA==.',
Ty='Tynak:BAAANQADCgQIBAAAAA==.',
Ug='Ugroto:BAABNQAECoEYAAIlAAgK8AQeGQDsAAAlAAgK8AQeGQDsAAAAAA==.',
Uh='Uhrstaria:BAAANQAECggIBwAAAA==.',
Ul='Uldred:BAAANQADCgUIBQABNQAECgkJIwAHAOMhAA==.',
Un='Unclesnottyp:BAAANQAECgEIAwAAAA==.Unmortal:BAAANQAECgUJDAAAAA==.',
Ur='Urotherdaddy:BAAANQAECgEIAQAAAA==.Uruker:BAAANQADCgIIAgAAAA==.',
Us='Useurblinker:BAAANQADCgcIBwAAAA==.',
Va='Valglacius:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Valkrin:BAAANQAECgQIBAAAAA==.Valonthir:BAAANQADCggIEwAAAA==.Valstone:BAAANQAECgEIAQAAAA==.Vancleave:BAAANQAECgMJAwAAAA==.Vanellope:BAAANQADCggICAAAAA==.Vargruf:BAAANQADCggIEAABNQAECggIIQAeAIkaAA==.Vasati:BAAANQAFFAEIAQABNQAECgkJIwAHAOMhAA==.Vaylethrayne:BAAANQABCgQIBQAAAA==.',
Ve='Vend:BAAANQAECgUIBQAAAA==.Verguetta:BAAANQAECgQIBwAAAA==.Verinsedai:BAABNQAECoEdAAIVAAkKugR0WABJAQAVAAkKugR0WABJAQAAAA==.Vesimer:BAAANQADCggIFQAAAA==.',
Vi='Viber:BAAANQADCgcIBwAAAA==.Vicvondik:BAAANQADCgQIBAAAAA==.Vildri:BAAANQAECgUIDgAAAA==.Violetknight:BAAANQADCgIIAgAAAA==.',
Vo='Voidrey:BAAANQAECgMJBgABNQAECgQIBAABAAAAAA==.Voikullten:BAAANQADCgUIBQAAAA==.Vornash:BAAANQAECgQIBgAAAA==.',
Vy='Vylax:BAAANQAECgEIAQAAAA==.Vylent:BAAANQADCggIDgAAAA==.',
Wa='Waddleweaver:BAAANQADCggICAAAAA==.Wardogsix:BAAANQAECggIEAAAAA==.Warrush:BAAANQAECgcIEwAAAA==.Watchmedps:BAAANQAECgIJAgAAAA==.',
We='Wevv:BAAANQADCgMIAwAAAA==.Weyds:BAAANQAECgUIBgAAAA==.',
Wi='Wildthang:BAAANQAECgEIAQAAAA==.Willgate:BAAANQADCgMIAwAAAA==.Willhelt:BAAANQAECgUIDgAAAA==.Willpray:BAAANQAECgUIDQAAAA==.Windle:BAAANQAECgYIBwAAAA==.Windrunnér:BAAANQAECggIDgAAAA==.Winterwølf:BAAANQADCgIJAgAAAA==.',
Wo='Wobblepot:BAAANQAECggIDAAAAA==.Wontondesire:BAABNQAECoEeAAIoAAgKTgvLFAB2AQAoAAgKTgvLFAB2AQAAAA==.',
Wu='Wulfdin:BAAANQAECgYIAwABNQAECgYIDwABAAAAAA==.Wulfpriest:BAAANQAECggIBwABNQAECgYIDwABAAAAAA==.',
Xa='Xantry:BAEBNQAECoEfAAMbAAgKthGXUQCNAQAbAAcKVBCXUQCNAQAjAAYKKQ+GTAA6AQAAAA==.',
Xb='Xbambs:BAAANQADCgQIBAAAAA==.',
Xe='Xerovladej:BAABNQAECoEVAAMQAAcK/xVHIwCaAQAQAAYK5RdHIwCaAQAZAAMKVAiEKQGfAAAAAA==.',
Xo='Xoog:BAAANQAECgQICAAAAA==.Xozo:BAAANQADCgIIAgAAAA==.',
Xu='Xualene:BAAANQAECgYIEAABNQAECgYIEwABAAAAAA==.Xurk:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Xw='Xwarrior:BAABNQAECoEeAAICAAgKzhKFdwAOAgACAAgKzhKFdwAOAgAAAA==.',
Ya='Yaaz:BAABNQAECoEaAAMCAAgKoxq/YwBEAgACAAgK/xm/YwBEAgAnAAEKfxeFOAA9AAAAAA==.Yamata:BAAANQADCgQIBAAAAA==.',
Ye='Yetistorm:BAAANQADCgMIAwAAAA==.',
Yo='Yoz:BAAANQAECgEIAQAAAA==.',
Yu='Yuee:BAAANQAECgMIAwAAAA==.Yukonicüs:BAAANQAECgYIEQABNQAECgkJOgADAF0jAA==.Yungsoo:BAAANQAECgIIBAAAAQ==.',
['Yü']='Yükonicus:BAAANQADCgUIBQABNQAECgkJOgADAF0jAA==.',
Za='Zaehara:BAAANQAECgMIBAAAAA==.Zanarian:BAAANQAECgEIAQAAAA==.Zappinboi:BAAANQAECgUIBwABNQAFFAUIEQAkAKwRAA==.Zatkiel:BAAANQAECgQIBQAAAA==.',
Ze='Zealot:BAAANQAECgMIBQAAAA==.Zedar:BAABNQAECoEaAAMFAAcKoRD/0wC5AQAFAAcKcg//0wC5AQAhAAMK2A6oJwCSAAABNQAECgkJGQAZAKQgAA==.Zeju:BAAANQAECgEIAgAAAA==.Zekinett:BAAANQADCgUIBQAAAA==.Zekker:BAAANQADCgcICgAAAA==.Zenolinwæ:BAAANQAECgUICwAAAA==.Zeohavoc:BAAANQADCgIIAgAAAA==.',
Zh='Zhondari:BAAANQAECgEIAgAAAA==.',
Zi='Zivanya:BAAANQAECgUICgAAAA==.',
Zu='Zuljek:BAAANQABCgIIAgAAAA==.Zupäi:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Zurprise:BAAANQADCgYICAAAAA==.',
Zx='Zxz:BAAANQAECggIEgAAAA==.',
Zy='Zyrgarran:BAAANQAECgEIAQAAAA==.',
['Zá']='Záraya:BAABNQAECoEgAAMEAAgKNRbgSQAhAgAEAAgKNRbgSQAhAgAZAAEKfAYChwErAAAAAA==.',
['Zú']='Zúpái:BAAANQAECgEIAQAAAA==.',
['Àz']='Àzæs:BAAANQAECgUICgAAAA==.',
['Ät']='Ätreo:BAAANQAECgYIDAAAAA==.',
['Åi']='Åirå:BAAANQADCgEIAQAAAA==.',
['Æl']='Ælusive:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
['Ço']='Çondemned:BAAANQADCgQIBAABNQADCggIGgABAAAAAA==.',
['Ém']='Émperor:BAAANQADCgUIBQABNQADCgYIDQABAAAAAA==.',
['Îc']='Îcyhot:BAAANQADCggIGgAAAA==.',
['Ðr']='Ðräx:BAABNQAECoEfAAQGAAcK/xrGYAC9AQAGAAYKGRnGYAC9AQASAAUKWgMqIwDuAAAaAAMKDQ6g3QCiAAAAAA==.',
['Óh']='Óhelgur:BAAANQADCgIIAgAAAA==.',
['Öh']='Öhgr:BAAANQAECgMIBQAAAA==.',
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
