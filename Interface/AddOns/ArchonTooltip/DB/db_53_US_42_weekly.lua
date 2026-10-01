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

local lookup = {'Unknown-Unknown','Warrior-Arms','DemonHunter-Havoc','Paladin-Holy','Mage-Arcane','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Hunter-BeastMastery','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Paladin-Protection','DeathKnight-Unholy','Shaman-Enhancement','Priest-Shadow','Priest-Discipline','Druid-Balance','Druid-Feral','Warlock-Affliction','DeathKnight-Blood','Evoker-Preservation','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','Mage-Frost','Shaman-Elemental','DemonHunter-Vengeance','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Hunter-Survival','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Bonechewer',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aandras:BAAANQAECgQICAAAAA==.',
Ab='Abbey:BAAANQADCgYIBgAAAA==.Abhayah:BAAANQAECgMIBwAAAA==.Absportls:BAAANQAECgUIBQAAAA==.',
Ac='Acelliste:BAAANQAECgYIDwAAAA==.Acrylix:BAAANQADCgYIBgAAAA==.',
Ad='Adventurerr:BAAANQADCgMIBQAAAA==.',
Af='Affgrezz:BAEANQADCgQIBAABNQAECgUICgABAAAAAA==.',
Ai='Aidlef:BAAANQAECgMIBAABNQAECgkJGQACABIfAA==.Aikenbranwen:BAAANQADCggIMQAAAA==.Aillannia:BAAANQADCggIDAAAAA==.',
Al='Alandor:BAAANQADCgUICgAAAA==.Aleathris:BAAANQAECgYIBgAAAA==.Allfire:BAEBNQAECoEiAAIDAAkKsR4qDgADAwADAAkKsR4qDgADAwAAAA==.Alutier:BAAANQAECgEIAQAAAA==.Aluunix:BAAANQAECgUJCgAAAA==.Alyse:BAABNQAECoEkAAIEAAkKihveGADqAgAEAAkKihveGADqAgAAAA==.Alyta:BAAANQADCggIGgAAAA==.Alzulra:BAAANQADCgYIBgAAAA==.',
Am='Amayla:BAAANQADCgcIBwAAAA==.Amoracon:BAAANQADCgUIBQAAAA==.',
An='Anubiá:BAAANQADCgYIBgAAAA==.Anulstorm:BAAANQADCgYIDAAAAA==.Anundir:BAAANQAECgYJDwAAAA==.',
Ao='Aondor:BAABNQAECoEaAAIFAAgKABQvhgA1AgAFAAgKABQvhgA1AgAAAA==.',
Ap='Applepi:BAAANQADCgEIAQAAAA==.',
Ar='Arcanical:BAAANQADCgYIDAAAAA==.Arday:BAABNQAECoEbAAIDAAkK0RyCEwDHAgADAAkK0RyCEwDHAgAAAA==.Areala:BAAANQAECggICAAAAA==.Arksos:BAAANQADCgEIAQAAAA==.Aroldo:BAAANQAECgEIAQAAAA==.Aroromunroe:BAAANQAFFAEIAQABNQADCggIDgABAAAAAA==.Arrancateta:BAAANQAECgQICwAAAA==.',
As='Asena:BAAANQADCgQIBAABNQAECggIDAABAAAAAA==.Ashblast:BAAANQADCgQIBAAAAA==.Ashira:BAAANQAECgYICQABNQAECgkJIQAGAAUgAA==.Astarouge:BAABNQAECoEXAAIHAAgKhB/cDADnAgAHAAgKhB/cDADnAgAAAA==.Astrafury:BAAANQADCgcIBwAAAA==.Astrasneaky:BAABNQAECoEPAAQIAAgKHAkZJwBdAQAIAAcK4QcZJwBdAQAHAAQK+QvGUgDZAAAJAAEKeAutFwA4AAAAAA==.',
At='Atchafalaya:BAAANQAECgYIEAABNQAECgcIGQAKAKkFAA==.',
Av='Avatarstate:BAAANQADCgQIBAAAAA==.Avonleâ:BAAANQADCgUIBQAAAA==.',
Aw='Awrina:BAAANQAECgUIDgAAAA==.',
Az='Azylrog:BAAANQADCggIEwAAAA==.',
Ba='Babymiko:BAAANQADCgQIBQAAAA==.Babypeech:BAAANQADCgYICwAAAA==.Bakudo:BAAANQABCgIIAgAAAA==.Bakulu:BAAANQAECgIIBAAAAA==.Bantoou:BAAANQAECgIIBAAAAA==.Batcat:BAAANQADCgMIAwAAAA==.Bathoryz:BAAANQAECgcIEwAAAA==.Battlescars:BAAANQADCgYIEgAAAA==.Bauhaus:BAAANQADCgUICQAAAA==.Bauld:BAAANQAECgUICgAAAA==.',
Bd='Bdbypaladin:BAAANQABCgQIBAAAAA==.',
Be='Beacong:BAAANQAECggICAAAAA==.Beardybear:BAAANQAECgQIBgAAAA==.Bearface:BAAANQADCgYIBgAAAA==.Bearicaide:BAAANQAECgQIBgAAAA==.Bearnorgas:BAAANQADCggICAAAAA==.Beautiful:BAAANQADCgYIBgAAAA==.Beefygee:BAAANQADCgMIAwAAAA==.Belldrak:BAAANQADCgUIBQAAAA==.Belldren:BAAANQAECgEJAQAAAA==.Belldrin:BAAANQAECgEIAQAAAA==.Bepaulie:BAAANQADCgIIAgABNQAECgcICgABAAAAAA==.Bergidum:BAAANQADCgcJDAAAAA==.Beriamilbinc:BAAANQADCgYICAAAAA==.Bewmy:BAAANQAECgIIAgAAAA==.',
Bh='Bhucket:BAAANQADCgEIAQAAAA==.',
Bi='Biglett:BAABNQAECoEYAAMLAAgKmx9SPgBoAgALAAcK5CBSPgBoAgAGAAUKBRxbLwB4AQAAAA==.Bignagos:BAAANQADCgYIFgAAAA==.Bigolboi:BAAANQAECgIJAwAAAA==.Bigthickheal:BAAANQADCgEIAQAAAA==.',
Bl='Blackk:BAABNQAECoEhAAIMAAkKLR5WFAD8AgAMAAkKLR5WFAD8AgAAAA==.Blackxcoffee:BAAANQADCgIIAgAAAA==.Bladesong:BAAANQAECgEIAQAAAA==.Blood:BAAANQAECgYICAAAAA==.Bloodietraks:BAAANQADCgUIBQAAAA==.Blorglock:BAABNQAECoEjAAMNAAkKfx1bMACNAgANAAgKpxxbMACNAgAOAAQKZRrWIwA+AQAAAA==.Blorgonp:BAAANQADCgYIBgABNQAECgkJIwANAH8dAA==.Blorgonw:BAAANQAECgYICQABNQAECgkJIwANAH8dAA==.Blowaegis:BAAANQAFFAEIAQAAAA==.Blownoutshax:BAAANQADCgEIAQAAAA==.Bluntnfortys:BAAANQADCgYICwAAAA==.Blupenguiny:BAABNQAECoEcAAIPAAcKVAnFawBwAQAPAAcKVAnFawBwAQAAAA==.',
Bm='Bmfsleeps:BAAANQADCgUICAAAAA==.',
Bn='Bnortwarrior:BAAANQAECgQICQABNQAECgEIAQABAAAAAA==.',
Bo='Boanz:BAAANQAECgUICQAAAA==.Bobasaurus:BAABNQAECoEYAAICAAgKoRrySQBuAgACAAgKoRrySQBuAgAAAA==.Bombastik:BAAANQAECgUIBwAAAA==.Bonesnapp:BAAANQAECgMIAwABNQAECggIIQAQAKohAA==.Booperry:BAAANQADCggICAAAAA==.Bosskün:BAAANQAECgQIBwAAAA==.Bountie:BAAANQAECggIEwAAAA==.Bountiè:BAAANQADCgEIAQABNQAECggIEwABAAAAAA==.Boyoyong:BAAANQADCgQIBAAAAA==.',
Br='Brainmatter:BAAANQADCgUICgAAAA==.Brandedsoul:BAAANQADCgIIAgAAAA==.Brewztler:BAAANQADCgcIHQAAAA==.Brightscale:BAAANQADCggIDgAAAA==.Brogak:BAAANQADCgUIBQAAAA==.Broham:BAAANQAECgEIAQAAAA==.Bromeheal:BAAANQADCgIIAgAAAA==.Bronik:BAABNQAECoEaAAICAAgKuRHdcgDtAQACAAgKuRHdcgDtAQAAAA==.Brujaja:BAAANQADCgQICAAAAA==.',
Bu='Buffmage:BAABNQAECoEdAAIFAAgK6xvwZgCAAgAFAAgK6xvwZgCAAgAAAA==.Bullman:BAAANQAECgQIBgABNQAECgkJIAARAIodAA==.Bullrûsh:BAAANQAECgYJCQAAAA==.Bullviper:BAAANQADCgYIDwAAAA==.Bumblbeetuna:BAAANQABCgIIAgAAAA==.',
['Bè']='Bèrsèrk:BAAANQADCgcIBwABNQAECggIIgASADEcAA==.',
['Bì']='Bìgdaddy:BAAANQADCgYICwAAAA==.',
['Bø']='Bønestørm:BAABNQAECoEiAAISAAgKMRw9CgCaAgASAAgKMRw9CgCaAgAAAA==.',
['Bù']='Bùndee:BAAANQAECgQIDQAAAA==.',
Ca='Cabbâge:BAAANQADCgYIBgAAAA==.Cacapants:BAAANQADCgQIBQAAAA==.Cadencegs:BAAANQAECgYIDQAAAA==.Caliex:BAAANQAECgQIBAAAAA==.Califax:BAABNQAECoEhAAMGAAkKBSAAGwBGAgAGAAcK8B0AGwBGAgALAAMKoiLbvQAaAQAAAA==.Caller:BAAANQADCgIIAgAAAA==.Callsignwiz:BAAANQAECgYICAAAAA==.Cannedbeans:BAAANQADCgMIAwAAAA==.Canuckcow:BAAANQADCgUICAAAAA==.Captantrips:BAAANQAECgIJAgAAAA==.Carizi:BAAANQAECgEIAgAAAA==.Carltonswag:BAAANQADCgcJBwAAAA==.Catazhanir:BAAANQAECgMJAwAAAA==.Catclown:BAABNQAECoEfAAMPAAgK+RlIMgBcAgAPAAgK+RlIMgBcAgATAAMKZAlBSwCMAAAAAA==.Cavonesee:BAAANQADCgcJCAAAAA==.Caylaramose:BAAANQADCggICAAAAA==.Cazsandra:BAABNQAECoEdAAMPAAgKdB03LQB0AgAPAAgKsBw3LQB0AgAUAAQKABSZDQAkAQAAAA==.',
Cc='Ccs:BAAANQADCgcIFAAAAA==.',
Ce='Centos:BAAANQABCgIIAgAAAA==.',
Ch='Chadsoss:BAAANQADCgYIBgAAAA==.Chamlio:BAAANQADCgYIHAAAAA==.Channis:BAAANQADCgQIAwAAAA==.Chenaccles:BAAANQADCgQIBAAAAA==.Chickenrally:BAABNQAECoEUAAICAAgKmBzrRwB1AgACAAgKmBzrRwB1AgAAAA==.Chicogel:BAAANQAECgQIBQABNQAECgQIEAABAAAAAA==.Chinobear:BAAANQADCggIGwAAAA==.Chixilog:BAAANQAECgIIAgAAAA==.Chodyboy:BAAANQABCgYIBgAAAA==.Cholmondeley:BAAANQADCgQIBAAAAA==.Chublie:BAAANQAECgUIBQAAAA==.Chuchix:BAABNQAECoEoAAQVAAkKLRt4FwDhAgAVAAkKHht4FwDhAgAWAAIK9BhwIACiAAAKAAMKagNXTAB5AAAAAA==.Chuckler:BAAANQAECggICQAAAA==.',
Cl='Cladtu:BAAANQAECgUIDAAAAA==.Cleiah:BAAANQADCgUIBQAAAA==.Cloudfisto:BAAANQADCggJEwAAAA==.',
Co='Colacolaz:BAACNQAFFIEPAAQOAAUKZSHGAwDOAAAOAAIKqiPGAwDOAAANAAIKLCH6GADEAAAXAAEKTB38BQBZAAA1AAQKgS0AAw0ACQoPJgIDALIDAA0ACQp9JQIDALIDAA4ABgq5Ix8KAEQCAAAA.Colasham:BAABNQAECoEZAAISAAgK3yTBAgBnAwASAAgK3yTBAgBnAwABNQAFFAUIDwAOAGUhAA==.Coldhands:BAAANQADCgEIAQABNQAECgUIBQABAAAAAA==.Colombiano:BAAANQAECgQIBgABNQAECgQIEAABAAAAAA==.Coltoff:BAABNQAECoEkAAMPAAkKRhfxKwB6AgAPAAkKRhfxKwB6AgAUAAEKIAEsKAAeAAAAAA==.Conker:BAAANQADCgUIBQAAAA==.Coolebra:BAAANQADCgIIAgAAAA==.Coprates:BAAANQAECgUICgAAAA==.Corgiquester:BAAANQAECgMIBQAAAA==.Corpserot:BAAANQADCgEIAQAAAA==.Corsin:BAAANQADCgQICQAAAA==.Cowbustion:BAAANQAECgUIEQAAAA==.',
Cp='Cptxcrunch:BAAANQADCgYICQAAAA==.',
Cr='Cracken:BAAANQADCggICgABNQAECggIFwAMAIYaAA==.Crankshot:BAAANQADCgYICgABNQAECgMIAwABAAAAAA==.Crimsonrayne:BAAANQAECgQIBQAAAA==.Cruciatus:BAAANQAECgQIBAAAAA==.Crusherlol:BAAANQAECgYICwAAAA==.Crusherlul:BAAANQAECgIJAgABNQAECgYICwABAAAAAA==.',
Cu='Curfew:BAAANQAECgcIEgAAAA==.',
['Cà']='Càt:BAAANQADCgEIAQAAAA==.',
Da='Dabigoldk:BAAANQAECgUIBQAAAA==.Dahlya:BAAANQADCgEIAQABNQADCggICQABAAAAAA==.Dannzig:BAAANQADCgIJAgAAAA==.Daragon:BAAANQADCgEIAQABNQAECggIHgAQAEElAA==.Darkravèn:BAABNQAECoEaAAIKAAgKEQfSKgBhAQAKAAgKEQfSKgBhAQAAAA==.Darthkitsune:BAAANQAECgMIAwAAAA==.Datbubblelol:BAAANQAECgcIDgAAAA==.Datchick:BAAANQADCggIHQAAAA==.Datlilpriest:BAAANQADCggICAAAAA==.Dawnkeeper:BAAANQADCgIIAgAAAA==.Dawnlily:BAAANQABCgcIDwAAAA==.Daxy:BAAANQADCgIIAgAAAA==.Daymandeuces:BAAANQAECggIAwAAAA==.Dazbek:BAABNQAECoErAAIFAAkK9x6DPADuAgAFAAkK9x6DPADuAgAAAA==.',
De='Decày:BAAANQADCgUIBgABNQAECggIHgANAHAjAA==.Deepdutch:BAAANQAECgYJDwAAAA==.Deezzeezz:BAAANQAECgUIDQABNQAECggIKQALAFQfAA==.Degeneffe:BAAANQAECgUICQAAAA==.Demoreknight:BAABNQAECoEjAAIYAAgKRBq6JQBWAgAYAAgKRBq6JQBWAgAAAA==.Devilboy:BAABNQAECoEcAAIRAAgKRSQsDAAxAwARAAgKRSQsDAAxAwAAAA==.Dextrey:BAAANQADCggICAABNQAECgUJDgABAAAAAA==.',
Di='Dialuptacos:BAAANQABCgYIBgAAAA==.Diddycombs:BAAANQADCgYIBgAAAA==.Discbrown:BAABNQAECoEeAAMTAAkKfR4EDgDfAgATAAkKfR4EDgDfAgAPAAEKeQIxxQA7AAAAAA==.Discmemommy:BAAANQAECgQIDAABNQAECggIHgANAHAjAA==.Discontent:BAAANQAECgQIBgAAAA==.Divinesmoke:BAAANQADCgUIBQAAAA==.',
Dj='Djblink:BAAANQADCgIIAgABNQAECgIIBQABAAAAAA==.',
Dk='Dkgaming:BAAANQAECgQJCQABNQAECgUIBwABAAAAAA==.',
Do='Dogeared:BAABNQAECoEZAAIKAAcKqQVzMgAdAQAKAAcKqQVzMgAdAQAAAA==.Doloc:BAEANQADCgIIAgABNQAECgcIGAAZAJsSAA==.Domore:BAAANQAECgcJCgAAAA==.Donniedrako:BAAANQADCgQIBAAAAA==.Donson:BAABNQAECoEjAAIaAAkKBxzBOgCfAgAaAAkKBxzBOgCfAgAAAA==.Donsun:BAAANQADCgUIBQAAAA==.Doodlebobb:BAAANQAECgMIBAABNQAECgUIBQABAAAAAA==.Doomlakalaka:BAAANQADCgcIHgAAAA==.Doomshamalam:BAAANQADCgQIBAAAAA==.Dorgh:BAAANQADCgIIAgAAAA==.Doskya:BAAANQAFFAIIAgAAAA==.Doubleclap:BAAANQADCggIEwAAAA==.',
Dp='Dpzofdoom:BAAANQAECgUICgAAAA==.',
Dr='Dracthwnd:BAACNQAFFIEIAAMbAAUK+QjdAwAcAQAbAAQKCQvdAwAcAQAcAAIKYQhACgB/AAA1AAQKgSwAAxsACQo1I9wAAJcDABsACQo1I9wAAJcDABwACApNHDoOAEICAAAA.Dragbrown:BAAANQADCgYIBgAAAA==.Dragonsins:BAABNQAECoEhAAINAAkKBSLxCwBIAwANAAkKBSLxCwBIAwAAAA==.Drahron:BAAANQADCggIAgAAAA==.Drdiksmasher:BAAANQAECgQICQAAAA==.Drekka:BAAANQADCgEIAQABNQAECgIJAwABAAAAAA==.Drogmax:BAAANQAECgQICwAAAA==.Droptopp:BAABNQAECoEaAAITAAkKcyCoBQBkAwATAAkKcyCoBQBkAwAAAA==.Drusys:BAAANQAECgUICgAAAA==.Dryrod:BAAANQADCgYIDAAAAA==.',
Du='Duckelf:BAABNQAECoEiAAIKAAgKXCShBgAyAwAKAAgKXCShBgAyAwAAAA==.Dunranger:BAAANQAECgEIAQAAAA==.Durrga:BAABNQAECoElAAICAAkKhiO6CQCVAwACAAkKhiO6CQCVAwAAAA==.',
['Dà']='Dàb:BAAANQAECgUIBQAAAA==.',
['Dã']='Dãftmõnk:BAAANQAECgcIEgAAAA==.',
['Dë']='Dëvildog:BAAANQADCggICAAAAA==.',
Ed='Edgecrusherr:BAAANQAECgMJBAAAAA==.',
Eg='Egwenalmere:BAABNQAECoEZAAIDAAkKwAhYNQCgAQADAAkKwAhYNQCgAQAAAA==.',
El='Elainia:BAAANQADCgYIDgAAAA==.Elandae:BAAANQAECgEIAQAAAA==.Elinoosh:BAAANQADCgEIAQAAAA==.Elisaveta:BAAANQAECgMJAwAAAA==.Elliaa:BAAANQAECgEIAQAAAA==.Elliard:BAAANQADCgUICAAAAA==.Elmahikera:BAAANQADCggJCAABNQAECgkJGAATAAkWAA==.Elodi:BAAANQADCgYIBgAAAA==.',
Em='Emanx:BAAANQABCgIIAgABNQAECgcIGAAaAD4VAA==.Embér:BAAANQAECggICAAAAA==.',
En='Enheduanna:BAAANQADCgUICAAAAA==.',
Eo='Eowyen:BAAANQADCgUIBQAAAA==.',
Ep='Epiiphany:BAAANQADCgcICAAAAA==.',
Er='Eriaedria:BAAANQAECgIIAgAAAA==.Erinsister:BAAANQAECgUIBwAAAA==.Erydius:BAAANQAECgQIBwAAAA==.',
Es='Esdeath:BAAANQABCgIIAgAAAA==.',
['Eì']='Eìrì:BAAANQAECgIIBAAAAA==.',
['Eô']='Eôwyn:BAAANQADCgcIFAAAAA==.',
Fa='Faclion:BAAANQAECgUJCQAAAA==.Faketurkey:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Falkhor:BAAANQAECgUICAAAAA==.Fari:BAAANQAECgQIBwAAAA==.Farstryder:BAAANQADCgYIBgAAAA==.Fatlootz:BAABNQAECoEeAAINAAgKcCNxEQAhAwANAAgKcCNxEQAhAwAAAA==.',
Fe='Fellwarden:BAAANQADCgMIAwAAAA==.Feltyah:BAAANQADCgcIGQAAAA==.',
Fi='Finnajuggyou:BAAANQAECgIIAgAAAA==.Finniker:BAAANQAECgIIAgAAAA==.Fiorina:BAABNQAECoEcAAIFAAgKqAT04AB0AQAFAAgKqAT04AB0AQAAAA==.Firefóx:BAAANQADCggICAAAAA==.Fishnet:BAAANQAECgUICgAAAA==.Fishthicc:BAAANQADCgYIEAAAAA==.',
Fl='Flashnikko:BAAANQADCgIIAgAAAA==.Flexkin:BAABNQAECoEfAAMVAAkK5CPxBACiAwAVAAkK5CPxBACiAwAKAAgKOCNWBgA4AwAAAA==.Flicks:BAAANQAECgMIAwAAAA==.',
Fo='Foe:BAACNQAFFIELAAIPAAUK0BapBwDIAQAPAAUK0BapBwDIAQA1AAQKgR4AAw8ACQpwHz0fAL0CAA8ACQpwHz0fAL0CABQAAQpqFsIhADUAAAAA.Fornor:BAABNQAECoEgAAIRAAkKih2QFgDOAgARAAkKih2QFgDOAgAAAA==.Foxfù:BAAANQADCgYIDAAAAA==.Foxkníght:BAABNQAECoEqAAIRAAkKRybEAADxAwARAAkKRybEAADxAwAAAA==.Foxxalot:BAAANQADCgQIBAAAAA==.Foxxpachi:BAAANQAECgQIBgAAAA==.',
Fr='Franký:BAAANQADCgUIBgAAAA==.Frebaen:BAAANQAECgQIBQAAAA==.Freezenikko:BAAANQADCgEIAQAAAA==.Frogus:BAAANQAECgUJCgAAAA==.Frostednight:BAAANQABCgYICQAAAA==.',
Fu='Fungbuck:BAAANQADCgYICgAAAA==.Fungbucko:BAAANQADCggIDgAAAA==.Fuule:BAAANQAECgUICQAAAA==.Fuusei:BAAANQAECgYIEAAAAA==.',
Fy='Fyrdrakon:BAABNQAECoEbAAIcAAcKMxwIDgBHAgAcAAcKMxwIDgBHAgAAAA==.',
Ga='Gabeitch:BAAANQADCgMIAwAAAA==.Gahero:BAAANQADCgQIBAAAAA==.Galapagós:BAAANQADCgYIDQAAAA==.Galaxus:BAABNQAECoEiAAIdAAkKpRtEDQDxAgAdAAkKpRtEDQDxAgAAAA==.Gammastorm:BAABNQAECoEdAAIeAAgKnwmBDACgAQAeAAgKnwmBDACgAQAAAA==.Garokk:BAAANQADCgYICAAAAA==.',
Gh='Ghall:BAAANQADCgIIAgAAAA==.Ghrell:BAEBNQAECoEaAAIWAAgK4R05BgC1AgAWAAgK4R05BgC1AgAAAA==.',
Gi='Gickygackers:BAAANQADCgYIDgAAAA==.Gigglepeak:BAAANQAECgYIDwAAAA==.Girlhands:BAAANQADCgIIAgAAAA==.',
Gl='Glekimage:BAAANQAECgMIAwAAAA==.',
Go='Goatmylk:BAAANQAECgIIAgAAAA==.Gobblr:BAAANQADCgUJCAAAAA==.Goldensorbet:BAAANQADCgYIBgAAAA==.Golokis:BAAANQADCggICAABNQAECggIHAACAP8aAA==.Gonuhreeuh:BAAANQAECgYICgABNQAECgcIIAAFAB0PAA==.Gotz:BAAANQADCggIEwAAAA==.',
Gr='Grattick:BAAANQAECgIIAwAAAA==.Greenlightt:BAAANQADCgYIHAAAAA==.Greenxll:BAABNQAECoEbAAIfAAkK9R9oEgA6AwAfAAkK9R9oEgA6AwAAAA==.Greypa:BAAANQAECgUIBwAAAA==.Grezulock:BAEANQAECgUICgAAAA==.Griggles:BAAANQAECgQICAAAAA==.Grikol:BAAANQADCgIIAgAAAA==.Grizzbane:BAAANQADCgEIAQAAAA==.Grizzleygrez:BAEANQADCgYIBgABNQAECgUICgABAAAAAA==.Grolk:BAAANQAECgEIAQAAAA==.',
Gu='Guerita:BAAANQADCgUICQAAAA==.Gumptruck:BAAANQAECgcIEgAAAA==.',
Gw='Gwenevere:BAAANQADCgMIAwAAAA==.',
Ha='Habibii:BAAANQADCgQIBAAAAA==.Hakana:BAAANQADCgUJBwABNQAECgQJBgABAAAAAA==.Hardendaire:BAAANQADCgYIDQAAAA==.Hashypally:BAAANQAECgQIBAAAAA==.Hathern:BAAANQADCgIIAgAAAA==.Hawkmees:BAABNQAECoEfAAMVAAgKYRKbMwD/AQAVAAgKYRKbMwD/AQAKAAEKSQ47WwAyAAAAAA==.Hazbretzul:BAAANQAECgYICgAAAA==.',
He='Hediff:BAAANQADCggICAAAAA==.Heelza:BAAANQAECgUIBQAAAA==.Hellskitchën:BAAANQADCgQIBQAAAA==.Help:BAAANQAECgUICgAAAA==.Hephs:BAAANQAECgIIAgABNQAECgUIDQABAAAAAA==.Herlo:BAAANQAECgQIBAAAAA==.Hermionejean:BAAANQADCgUJBQAAAA==.Hexuz:BAAANQAECgQIBAAAAA==.',
Hi='Hipster:BAAANQAECgIIAwABNQABCgIIAgABAAAAAA==.',
Ho='Holeekow:BAAANQADCgEIAgAAAA==.Hollymollie:BAAANQAECgYICAAAAA==.Holoey:BAAANQABCgIIAgAAAA==.Holymobeus:BAAANQAECgIIAgAAAA==.Holypower:BAAANQADCgYICQAAAA==.Holythot:BAAANQAECgcIEQAAAA==.Hoofanhammer:BAAANQADCgIJAwAAAA==.Howoriginal:BAAANQAECgcIDgAAAA==.Hozrozlok:BAAANQAECgYIDgAAAA==.',
Hu='Huntdry:BAAANQAECgUIEQAAAA==.Hurkoh:BAAANQAECgQIBQAAAA==.Hurrikin:BAAANQADCggJCAAAAA==.Hushpuppié:BAAANQAECgQJBwAAAA==.',
Hy='Hypereon:BAABNQAECoEaAAIQAAgKWRz0DACFAgAQAAgKWRz0DACFAgAAAA==.',
Ic='Iceden:BAAANQAECgQIBgAAAA==.Ichirosuzuki:BAAANQABCgYJCAAAAA==.Icyweenor:BAAANQAECgIIAgAAAA==.',
Id='Idkdude:BAAANQAECggIEQAAAA==.',
Ie='Ielarth:BAAANQADCgEIAQAAAA==.',
If='Ifhediehedie:BAAANQADCgcIBwAAAA==.',
Ih='Ihrasx:BAAANQAECggIBAAAAA==.',
Ik='Ikeepdying:BAAANQAECgEIAQAAAA==.Ikevzl:BAAANQADCgYIBwAAAA==.',
Il='Illadarina:BAABNQAECoEVAAIgAAgKeQ5TDACgAQAgAAgKeQ5TDACgAQAAAA==.Illys:BAAANQADCgEIAQAAAA==.Illí:BAAANQADCgcICAAAAA==.',
In='Incetardis:BAAANQADCgcIGgAAAA==.Indiriel:BAAANQAECgcJBgAAAA==.',
Ir='Iradoria:BAABNQAECoEiAAMTAAkKvhe7FwBTAgATAAgKpRe7FwBTAgAPAAQKiBcEdQBOAQAAAA==.Ironplay:BAAANQAECgEIAQAAAA==.',
Is='Isoldè:BAAANQADCgcIBwAAAA==.Istabu:BAAANQAECgYIBwAAAA==.',
It='Itachi:BAACNQAFFIERAAMRAAYKyBz4AQDiAQARAAYKCBz4AQDiAQAhAAMK0xe5BwD/AAA1AAQKgSYAAyEACQpcJiECALYDACEACQrVJSECALYDABEACQrmJR4HAG4DAAAA.Itamï:BAABNQAECoEbAAIYAAgKOg5uQwCrAQAYAAgKOg5uQwCrAQAAAA==.',
Iv='Ivannacream:BAAANQADCggIEAAAAA==.',
Ja='Jaagren:BAAANQAECgQJBAAAAA==.Jadawin:BAABNQAECoEVAAIEAAgK0AnjYwCdAQAEAAgK0AnjYwCdAQAAAA==.Jaketta:BAAANQAECgEIAQAAAA==.Jaquemehof:BAAANQAECgEIAQAAAA==.Jasnah:BAACNQAFFIEGAAIFAAIKnQ5YMwCfAAAFAAIKnQ5YMwCfAAA1AAQKgSYAAgUACQr6Fm1kAIYCAAUACQr6Fm1kAIYCAAAA.Jayrel:BAABNQAECoEqAAMUAAkK4hc5BwDQAQAPAAkKgxRGLwBqAgAUAAgKaxA5BwDQAQAAAA==.',
Je='Jerrik:BAAANQAECgYIEgAAAA==.',
Jo='Joedky:BAAANQADCgcIBwAAAA==.Joeyexotic:BAAANQAECgUICgAAAA==.Jokem:BAAANQADCgUIBQAAAA==.Jozelyn:BAAANQADCgEJAQAAAA==.',
Ju='Juankkii:BAAANQADCggICgABNQAECgQIBwABAAAAAA==.Juggerbear:BAAANQAECgEJAQAAAA==.Juiçy:BAAANQAECgQIBgAAAA==.Juls:BAAANQAECgYJDgAAAA==.Justhetip:BAAANQADCgEIAQAAAA==.Justjason:BAAANQAECgIIAgAAAA==.',
['Jä']='Jäger:BAAANQAECgQIBQAAAA==.',
Ka='Kagama:BAAANQAECgQIBQAAAA==.Kaladora:BAAANQAECgUIEAAAAA==.Kalatabi:BAAANQADCggICAABNQAECggIIQAQAKohAA==.Kalatai:BAABNQAECoEhAAIQAAgKqiFFCQDOAgAQAAgKqiFFCQDOAgAAAA==.Kamisenshi:BAAANQADCgIIAgAAAA==.Kaosstorm:BAAANQAECgQIBAAAAA==.Karayna:BAAANQAECgcICQAAAA==.Kareemcheese:BAAANQAECgQJBgAAAA==.Kauko:BAAANQAECgYIEgAAAA==.',
Ke='Keadron:BAAANQADCgIIAgAAAA==.Kellanash:BAAANQADCgUICAAAAA==.Kezwik:BAAANQAECgUICwAAAA==.',
Kh='Khaotick:BAAANQADCgYIHAAAAA==.Kheetz:BAAANQAECgEIAgAAAA==.',
Ki='Kiilg:BAAANQADCgYIDAAAAA==.Kikomo:BAAANQAECgEIAQAAAA==.Kikosho:BAABNQAECoEaAAMiAAYK1BlwFgC+AQAiAAYK1BlwFgC+AQAjAAEK1RHRUgA1AAAAAA==.Kilaaj:BAAANQADCgIIAgAAAA==.Killerbane:BAAANQADCgcJEAAAAA==.Killgoro:BAAANQADCgYICgAAAA==.Kinclakis:BAAANQADCgQIBAAAAA==.Kinthor:BAAANQABCgIIAgAAAA==.Kirrin:BAAANQAECgcIEwAAAA==.Kisaragi:BAAANQAECgQIBAAAAA==.',
Kn='Kneecap:BAABNQAECoEaAAIEAAgK4CHWEAAiAwAEAAgK4CHWEAAiAwAAAA==.Kneepad:BAAANQADCgcIBwAAAA==.Knetikara:BAABNQAECoEoAAMeAAgKLggWGADxAAAFAAgKOgMT8gBUAQAeAAUKugoWGADxAAAAAA==.',
Ko='Kokokrantz:BAAANQAECgMIAwAAAA==.Korthix:BAAANQAECgUJDgAAAA==.Kosi:BAABNQAECoEXAAIdAAgKvQj0LACZAQAdAAgKvQj0LACZAQAAAA==.',
Kr='Kraanan:BAAANQADCgUIBQAAAA==.Kraves:BAAANQAECgUICgAAAA==.Kreiedril:BAAANQADCggIJwAAAA==.Krispytoo:BAAANQAECggIEgAAAA==.Krompir:BAAANQADCgcJBwAAAA==.',
Ku='Kulltena:BAAANQADCggICAAAAA==.Kulltina:BAAANQADCggICAAAAA==.Kurnous:BAAANQADCgUIBQAAAA==.',
Ky='Kyokaii:BAAANQAECgYIEAAAAA==.Kyrasala:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíngcoyote:BAAANQAECggIAQAAAA==.',
La='Laarken:BAAANQADCggIIQAAAA==.Lacedtotems:BAABNQAECoEVAAIfAAkKtSQbCACVAwAfAAkKtSQbCACVAwAAAA==.Lagexe:BAAANQADCggIEQAAAA==.Laybia:BAAANQADCgEIAQAAAA==.Lazlo:BAAANQAECgQIAwAAAA==.',
Le='Lenrela:BAAANQAECgYIEgAAAA==.Leroenus:BAAANQADCgEIAQAAAA==.Lestealth:BAAANQAECgIIBQAAAA==.Letena:BAABNQAECoEcAAIVAAgKLwzyPwCrAQAVAAgKLwzyPwCrAQAAAA==.Levyymage:BAAANQAECgYIDgAAAA==.',
Li='Lialyndra:BAAANQADCgYICgAAAA==.Licelia:BAAANQAECgcIEQAAAA==.Lilballohate:BAAANQADCgEIAQAAAA==.Liligayle:BAAANQADCgMIAwAAAA==.Lilsxe:BAAANQADCgUJBQAAAA==.Linane:BAABNQAECoEmAAIDAAgKzhpWGwB4AgADAAgKzhpWGwB4AgAAAA==.Lite:BAAANQADCggICQABNQAECggIIQAYALIcAA==.Liveevil:BAAANQAFFAEIAQAAAA==.',
Ll='Llama:BAAANQADCgYIBgAAAA==.',
Lo='Loathsome:BAAANQADCgEIAQABNQAECgQICgABAAAAAA==.Locksummnplz:BAAANQAECgQIBAAAAA==.Lolmagician:BAAANQABCgIJAgABNQADCggJCAABAAAAAA==.Loquail:BAAANQADCgUIBQAAAA==.Lorgrith:BAAANQAECgIIAgAAAA==.Lorike:BAAANQAECggICgAAAA==.Losthobo:BAAANQADCgEIAQAAAA==.',
Lu='Lucifoor:BAAANQAECgEIAQAAAA==.Luftim:BAAANQAECgEIAQAAAA==.Lunastellara:BAAANQAECgQIBQAAAA==.Lunoxx:BAAANQAECgIIAwAAAA==.Lurang:BAAANQAECgUICgAAAA==.',
Ma='Macacbre:BAAANQADCgYICgAAAA==.Macdotnalds:BAAANQADCgMIAwAAAA==.Madetolock:BAAANQADCgYIFgAAAA==.Maerlyna:BAAANQABCgIIAwAAAA==.Magebrew:BAAANQAECgEJAQAAAA==.Mageycat:BAAANQADCgYICAABNQAECggIHwAPAPkZAA==.Magicma:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.Magiks:BAAANQADCgIIAgAAAA==.Mahlah:BAAANQABCgQIBgAAAA==.Makarov:BAAANQADCgEIAQAAAA==.Malevir:BAAANQABCgUIBQAAAA==.Maliun:BAAANQAECgYIEAAAAA==.Malusdemon:BAAANQAECgQIBQAAAA==.Mamasota:BAAANQAECgUIBwAAAA==.Marisol:BAAANQADCgYIGQAAAA==.Markfunk:BAABNQAECoEmAAIFAAkKeiNaEACDAwAFAAkKeiNaEACDAwAAAA==.Markiepoo:BAAANQAECgQIBAABNQAECgkJJgAFAHojAA==.Markyboom:BAAANQADCgIIAgABNQAECgkJJgAFAHojAA==.Markybowner:BAABNQAECoEVAAILAAgKlhynKwCtAgALAAgKlhynKwCtAgABNQAECgkJJgAFAHojAA==.Markykong:BAAANQADCggIEgABNQAECgkJJgAFAHojAA==.Martimusmagi:BAAANQADCgIIAgAAAA==.Maryjaiyne:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Mawmatz:BAAANQADCgEIAQAAAA==.',
Me='Mebashum:BAAANQAECgYIBAAAAA==.Mechavexi:BAAANQADCggICAAAAA==.Medihunter:BAAANQADCgIIAgABNQAECgYIDgABAAAAAA==.Meditations:BAAANQAECgYIDgAAAA==.Megumi:BAAANQAECgQIBAAAAA==.Meleath:BAAANQADCgEIAQAAAA==.Melibeth:BAAANQABCgEIAQAAAA==.Metrakatanke:BAAANQADCgYICgAAAA==.Mexiflip:BAAANQADCgYICQAAAA==.',
Mi='Midoriya:BAAANQAECgMIAQAAAA==.Mikeshifter:BAAANQAECgMIAwABNQADCgIIAgABAAAAAA==.Milgan:BAABNQAECoEcAAIMAAgKDCC7JQCTAgAMAAgKDCC7JQCTAgAAAA==.Minimochi:BAABNQAECoE7AAIPAAkKpBe5IQCvAgAPAAkKpBe5IQCvAgAAAA==.Missblackk:BAAANQADCgIIAgAAAA==.Mithyr:BAAANQADCgcIBwABNQAECgIIAwABAAAAAA==.',
Mn='Mneme:BAACNQAFFIELAAIKAAUKcySPAQAZAgAKAAUKcySPAQAZAgA1AAQKgSIAAgoACQpZJBcDAIADAAoACQpZJBcDAIADAAAA.',
Mo='Mogani:BAAANQAECgUIBQAAAA==.Monkeypiglet:BAABNQAECoETAAICAAcKUhuxYwAaAgACAAcKUhuxYwAaAgAAAA==.Moogpal:BAAANQAECgMIBQABNQAECgUICQABAAAAAA==.Moogul:BAAANQAECgUICQAAAA==.Moovoe:BAAANQAECgUICgAAAA==.Morcarth:BAAANQAECgQIBQAAAA==.Mortal:BAAANQADCgEIAQAAAA==.Morts:BAAANQADCgYJBgAAAA==.',
Mu='Mulks:BAAANQAECgYIEQAAAA==.Multiblox:BAABNQAECoEfAAIkAAkKlBsRBgDVAgAkAAkKlBsRBgDVAgAAAA==.Murgruuk:BAAANQADCggICQAAAA==.',
My='Myling:BAAANQADCggIAgAAAA==.',
['Mà']='Màrkham:BAAANQABCgYJCAAAAA==.',
['Má']='Mágé:BAAANQAECgUIBgABNQAECggIHAAVAH8ZAA==.',
['Må']='Måjïñßûüü:BAAANQAECgIIAgAAAA==.',
Na='Naam:BAAANQAECgUIDQAAAA==.Nadrin:BAAANQADCggIHQAAAA==.Naedora:BAAANQAECgYIEQAAAA==.Namixx:BAABNQAECoEdAAIUAAgK9RuiAgC6AgAUAAgK9RuiAgC6AgAAAA==.Naruwnd:BAAANQADCggICAABNQAFFAUICAAbAPkIAA==.Nassaela:BAAANQAECgYIBgABNQAECggIEQABAAAAAA==.Nathaanis:BAABNQAECoEZAAIaAAgKsRnZZQAQAgAaAAgKsRnZZQAQAgAAAA==.',
Ne='Necrodamus:BAAANQAECgEIAQAAAA==.Neliera:BAAANQABCgUIBQAAAA==.Neopolitangs:BAAANQAECgYICwAAAA==.Nevs:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Nevsy:BAAANQADCgYICAAAAA==.Nezdispenser:BAAANQAECgEIAQAAAA==.',
Ni='Niduash:BAAANQADCgMIAwAAAA==.Nightchill:BAAANQAECgUICQAAAA==.Nim:BAAANQADCgQIBAAAAA==.Nimbletoes:BAABNQAECoEYAAIdAAcKwBwHHAA+AgAdAAcKwBwHHAA+AgAAAA==.Ninabudhu:BAAANQADCggJEAAAAA==.Nirza:BAAANQAECgEIAQAAAA==.Niziel:BAABNQAECoElAAMhAAkK7hrhFQCYAgAhAAkK7hrhFQCYAgAYAAEK3wecqQA4AAAAAA==.',
No='Nofurrys:BAAANQADCggICQAAAA==.Nokorin:BAAANQAECgEIAgAAAA==.Nolo:BAAANQADCgUIBQABNQAECgkJJAAHAGojAA==.Nomamesrko:BAAANQADCgEIAQAAAA==.Noranis:BAAANQAECgEIAQAAAA==.Noros:BAABNQAECoEkAAIHAAkKaiPtAwB0AwAHAAkKaiPtAwB0AwAAAA==.',
Nu='Nuggalicious:BAAANQAECgQIBQAAAA==.Nuggss:BAAANQABCgEIAQAAAA==.Nursjoy:BAAANQADCggICQAAAA==.',
Nv='Nveturkey:BAAANQAECgIIAgAAAA==.',
Ok='Oko:BAAANQAECgcIEgAAAA==.',
Ol='Oldmanpeanut:BAAANQADCggICQABNQAECgUIBwABAAAAAA==.Olopa:BAAANQABCgIIAgAAAA==.',
Om='Omenwar:BAAANQADCggJIAAAAA==.Omni:BAAANQADCggICwAAAA==.',
Or='Orcazum:BAAANQAECgUIBQAAAA==.Orelia:BAAANQAECgMJAwAAAA==.Orfnanu:BAAANQADCggIDQABNQAECgQIBgABAAAAAA==.Ornarl:BAAANQAECgMJBgAAAA==.',
Ot='Ottawa:BAAANQADCgYIBgAAAA==.',
Ox='Oxsana:BAAANQAECgUJBgAAAA==.',
Pa='Packtastic:BAABNQAECoEXAAMNAAcKEhaKiwBlAQANAAUKCheKiwBlAQAOAAIKpRPUTgB9AAAAAA==.Padthang:BAAANQAECgcIEwAAAA==.Pakipot:BAAANQAECgMIAwAAAA==.Palazyn:BAAANQADCggIHQABNQAECggIFQAgAHkOAA==.Pallymar:BAAANQAECgIIAgABNQAECgkJGgAlAIckAA==.Panhexual:BAAANQADCgQIBAAAAA==.Parketor:BAAANQAECgcIDwAAAA==.Pathyx:BAAANQAECgMIAwAAAA==.',
Pe='Peacefulguy:BAAANQABCgQIBgAAAA==.Peachjars:BAABNQAECoEpAAMNAAkKVyNjBgB8AwANAAkKVyNjBgB8AwAOAAQKExEUMADzAAAAAA==.Pelvis:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Perixi:BAAANQADCgYICgAAAA==.Perpekto:BAAANQADCgUIBQAAAA==.Peterpewpew:BAAANQAECgIIAgAAAA==.',
Ph='Phedragon:BAAANQAECgMIBAAAAA==.Phedrah:BAABNQAECoEWAAIfAAkKkBO4NQBbAgAfAAkKkBO4NQBbAgAAAA==.Philipx:BAAANQADCgQIBAAAAA==.Phookie:BAAANQADCgcJBwAAAA==.',
Pi='Picklenator:BAAANQAECgQIBwAAAA==.Pickléz:BAAANQADCgEIAQAAAA==.Pierreplays:BAAANQADCgUIBQAAAA==.Pillowhands:BAAANQADCgQIBAAAAA==.Pilto:BAAANQAECgYIEAAAAA==.Pingo:BAAANQAECgUICQAAAA==.Pinkmj:BAAANQADCgMIBgAAAA==.Pitchief:BAAANQAECgUICgAAAA==.',
Po='Polendina:BAABNQAECoEaAAMRAAkKwiOJEgDwAgARAAgK8iOJEgDwAgAYAAgK0CLCFADaAgAAAA==.Pooginator:BAAANQADCgYICAAAAA==.Porcelinà:BAAANQAECgQICAABNQAECggIHwAEADUWAA==.',
Pr='Prada:BAAANQAECgEIAQAAAA==.Premmish:BAAANQADCggJCAAAAA==.Primeork:BAAANQADCgUIBQAAAA==.Prisca:BAAANQABCgcICwAAAA==.Pritasth:BAAANQAECgEIAQAAAA==.Prometheuss:BAAANQADCgQJBAAAAA==.',
Ps='Psammophile:BAABNQAECoEfAAIFAAgKEyHiPgDnAgAFAAgKEyHiPgDnAgAAAA==.Psymmer:BAAANQADCgYICAABNQAECgQICAABAAAAAA==.Psynge:BAAANQADCgYICgABNQAECgQICAABAAAAAA==.Psynnergy:BAAANQAECgQICAAAAA==.Psytellar:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.',
Pt='Ptsd:BAAANQAECgEIAQAAAA==.',
Pu='Pumprstltskn:BAAANQAECgUIDgAAAA==.Puppyflower:BAAANQADCggIDQAAAA==.Purplepally:BAAANQADCgEIAQAAAA==.Purpleshroom:BAAANQAECgIJAgABNQAECgQIBAABAAAAAA==.Put:BAAANQADCgYJDwAAAA==.',
Py='Pyrat:BAAANQAECgUICgAAAA==.Pyroangel:BAAANQAECgIIBAAAAA==.Pyrom:BAAANQADCgUIBQABNQADCgIIAgABAAAAAA==.Pyrotwopnto:BAAANQAECgEIAQAAAA==.',
['Pí']='Píneapple:BAAANQAECgIIAwAAAA==.',
Qe='Qertinya:BAAANQADCgYIEQAAAA==.',
Qu='Quadman:BAABNQAECoEZAAICAAkKEh9ALADeAgACAAkKEh9ALADeAgAAAA==.Quaxly:BAAANQADCgQIBAAAAA==.Quinexorable:BAABNQAECoEqAAImAAkKPiWVAADUAwAmAAkKPiWVAADUAwAAAA==.',
Qy='Qyl:BAAANQADCgMIAwAAAA==.',
Ra='Ragedaddy:BAABNQAECoEcAAICAAgK/xqjUgBRAgACAAgK/xqjUgBRAgAAAA==.Raglashar:BAAANQADCgQJBAAAAA==.Rahkar:BAAANQAECgYJDgAAAA==.Rainndance:BAAANQAECgUICgAAAA==.Rainnhell:BAAANQADCgEIAQAAAA==.Raitan:BAAANQADCggIEQAAAA==.Raitazzak:BAAANQADCgEIAQAAAA==.Rallet:BAAANQADCgIIAgAAAA==.Ramrodveazy:BAAANQAECgYIDgAAAA==.Ranaklos:BAAANQADCgQIBAABNQADCgIIAgABAAAAAA==.Rancimus:BAAANQAECgQICAAAAA==.Rangore:BAAANQADCgQIBAAAAA==.Ranocthan:BAAANQAECgUICQAAAA==.Rarcher:BAAANQAECgUJCgAAAA==.Rasmuz:BAAANQADCgYIFgAAAA==.Rauthar:BAAANQAECgUIDQAAAA==.Rayyven:BAAANQAECggIDwAAAA==.Razorken:BAAANQADCgYIBgAAAA==.Razorsharp:BAABNQAECoEaAAIYAAgKNxYRLAAsAgAYAAgKNxYRLAAsAgAAAA==.',
Re='Recon:BAABNQAECoEiAAMbAAgKPhAOCAC+AQAbAAgKPhAOCAC+AQAcAAQKoQKuKgCBAAAAAA==.Reefermadnes:BAABNQAECoEhAAMCAAgKqBeVZAAYAgACAAgKAhaVZAAYAgAmAAQK8gnFIwDAAAAAAA==.Reelsteel:BAAANQADCgcIFgAAAA==.Relnamah:BAAANQAECgIIAwAAAA==.Reoloc:BAEANQADCgYICQABNQAECgcIGAAZAJsSAA==.Retandspank:BAAANQABCgQIBAAAAA==.Revdev:BAABNQAECoFFAAIaAAkKnBxDKgDkAgAaAAkKnBxDKgDkAgAAAA==.Revoke:BAAANQADCgEIAQABNQAECgQICgABAAAAAA==.Rezowulf:BAAANQAECgYICgAAAA==.',
Rh='Rhapsydee:BAAANQADCgUIBQAAAA==.Rhododendron:BAAANQADCgcIBwAAAA==.Rhoñin:BAAANQABCgEIAQAAAA==.Rhuney:BAAANQAECgcIDwAAAA==.Rhunie:BAAANQADCgcIBwABNQAECgcIDwABAAAAAA==.Rhyllii:BAAANQAECgUIDAAAAA==.',
Ri='Riftmaker:BAAANQABCgIIAgAAAA==.Rivermage:BAAANQABCgIIAgAAAA==.',
Ro='Roadburner:BAAANQAECggICwAAAA==.Roccotaco:BAAANQADCgYICgAAAA==.Roloc:BAEANQAECgQIBAABNQAECgcIGAAZAJsSAA==.Roloch:BAAANQADCgcIBwAAAA==.Romenhoff:BAABNQAECoEfAAMKAAkKKhW/EgB1AgAKAAkKKhW/EgB1AgAVAAYK4gpqVQAxAQAAAA==.Rootbeer:BAAANQAECgEIAgABNQAECgEIAQABAAAAAA==.Roshambu:BAAANQAECgIIAwAAAA==.Roxinator:BAAANQAECgQIBAAAAA==.Roxorath:BAAANQADCgQIBAAAAA==.Roxyrocko:BAAANQADCggIDgAAAA==.',
Ru='Ruikiea:BAAANQAECgQIBgABNQAECggILgAfAPoWAA==.Runahdan:BAAANQADCgcIBwABNQAECgcIDwABAAAAAA==.',
Ry='Ryomage:BAAANQABCgcJBwAAAA==.',
['Rà']='Ràggà:BAAANQAECgcIDgAAAA==.',
['Rí']='Rían:BAAANQAECgIIAgAAAA==.',
Sa='Sacerdota:BAAANQADCgQIBAAAAA==.Saelenei:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Saevra:BAAANQADCgMIAwAAAA==.Sairadoka:BAAANQAECgUICgAAAA==.Samzori:BAAANQAECgcIEgAAAA==.Sanatizer:BAABNQAECoEbAAIVAAcKUBu0LwAdAgAVAAcKUBu0LwAdAgAAAA==.Sandret:BAAANQAECgYIDgAAAA==.Sarris:BAAANQAECgUIBQAAAA==.Sathriel:BAABNQAECoEbAAIRAAgKtBT2MgACAgARAAgKtBT2MgACAgAAAA==.Savagebleedz:BAAANQAECgUIBQAAAA==.Savagehealz:BAAANQADCgYJBgAAAA==.Savagetotemz:BAABNQAECoEhAAIfAAgKKB/uHgDfAgAfAAgKKB/uHgDfAgAAAA==.',
Sc='Scalelujah:BAAANQAECgUICgABNQAECgEIAQABAAAAAA==.Scottadin:BAAANQAECgcIEQAAAA==.',
Se='Seanasy:BAAANQABCgIIAgAAAA==.Secondenvoy:BAAANQAECgQIDQAAAA==.Seerawh:BAAANQAECgYICgAAAA==.Sehetep:BAAANQAECgEIAQAAAA==.Sephyrea:BAAANQADCgYIBgAAAA==.Serigon:BAAANQADCgYIDQAAAA==.',
Sh='Shadownd:BAACNQAFFIEHAAIPAAMKhR5IEAAkAQAPAAMKhR5IEAAkAQA1AAQKgR4AAw8ACQocIVohALECAA8ACAoYIFohALECABQAAwonHUcRANsAAAE1AAUUBQgIABsA+QgA.Shadowsloth:BAAANQADCgYICQAAAA==.Shadymcgee:BAAANQAECgMIAwAAAA==.Shaevra:BAAANQADCgQIBAABNQAECgkJIQAGAAUgAA==.Shahli:BAAANQADCgIIAgAAAA==.Shakiro:BAAANQAECgQIEAAAAA==.Shaloendril:BAAANQAECgEIAQABNQAECgkJJAAaAH8ZAA==.Shalzind:BAAANQADCgIIAgAAAA==.Shamchan:BAAANQAECgYIDgAAAA==.Shamergency:BAAANQADCgYIFgAAAA==.Shammyrock:BAABNQAECoEYAAISAAgKAR1tCADEAgASAAgKAR1tCADEAgAAAA==.Shamtony:BAAANQABCgQIBgAAAA==.Sharkk:BAAANQAECgIIAwAAAA==.Shaylar:BAAANQAECgMJBAAAAA==.Sheisunholy:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Shiherlis:BAAANQAECgQIBAAAAA==.Shmacken:BAABNQAECoEXAAMMAAgKhhqwLwBgAgAMAAgKhhqwLwBgAgAfAAEK2APjEgEmAAAAAA==.Shockinglee:BAAANQAECgQJBQABNQAECgQICgABAAAAAA==.Shoryuken:BAAANQADCgMIBAAAAA==.Shosannaa:BAAANQAECgUJBwAAAA==.Shuriken:BAABNQAECoEsAAMGAAkK0STVAgCfAwAGAAkK0STVAgCfAwALAAEK6RVTFwE7AAAAAA==.',
Si='Siete:BAAANQADCggIFgAAAA==.Sikblitz:BAAANQAECgMIBQAAAA==.Sikbubblez:BAABNQAECoEeAAIaAAgKnBgyTQBeAgAaAAgKnBgyTQBeAgAAAA==.Sikshockz:BAAANQAECgUICgAAAA==.Silentblades:BAAANQAECgIIAgAAAA==.Sindazia:BAAANQAECgQIBAAAAA==.Sinistry:BAAANQADCgUIBgAAAA==.Siopau:BAAANQADCgQIBAAAAA==.Sixunder:BAAANQADCgcIBwAAAA==.',
Sk='Skrinkles:BAAANQAECgQIBAAAAA==.Skullwhisper:BAAANQAECgYIDQAAAA==.',
Sl='Slomar:BAAANQAECgEIAQAAAA==.Slowar:BAAANQADCggICAAAAA==.Slowpallh:BAAANQADCgYICAABNQADCggICAABAAAAAA==.Slowrog:BAAANQADCgUIAwABNQADCggICAABAAAAAA==.Slowsh:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.',
Sm='Smoggely:BAAANQAECgUICQAAAA==.Smoketotem:BAAANQAECgUICQAAAA==.',
Sn='Sneakzalot:BAAANQAECgEIAQAAAA==.Sneevle:BAAANQADCgMIAwABNQAECgUIEQABAAAAAA==.Snowbreeze:BAAANQAECgUICgAAAA==.Snowfláme:BAABNQAECoEYAAIaAAcKPhWmfgDJAQAaAAcKPhWmfgDJAQAAAA==.Snubz:BAAANQADCgYIBgAAAA==.',
So='Solarity:BAAANQABCgUIBQAAAA==.Solfyr:BAAANQADCgYIBgABNQAECgcIGwAcADMcAA==.Solie:BAAANQADCgQIBAABNQAECgUIBwABAAAAAA==.Solki:BAAANQADCgIIAgAAAA==.Solrak:BAAANQAECgQIDAAAAA==.Soobatai:BAAANQADCgYIBgAAAA==.Soot:BAAANQAECgYIBwABNQAECgcIDQABAAAAAA==.Soots:BAAANQAECgcIDQAAAA==.Sootzy:BAAANQAECgQIBgABNQAFFAcIFwAOAIcgAA==.Sophiane:BAAANQAECgYICAAAAA==.Soulcaller:BAAANQADCggICAAAAA==.Soulkhan:BAAANQADCgUIBQAAAA==.Soulkrusher:BAAANQAECgMIBQAAAA==.',
Sp='Spadeii:BAABNQAECoEmAAIRAAkKAByCGwCkAgARAAkKAByCGwCkAgAAAA==.Spadex:BAAANQADCggIEAABNQAECgkJJgARAAAcAA==.Spagheddy:BAAANQADCggIDQAAAA==.Spankky:BAAANQAECgQJBAAAAA==.Spellzy:BAABNQAECoEgAAIFAAcKHQ/JxgCnAQAFAAcKHQ/JxgCnAQAAAA==.Spicylatina:BAAANQADCgYIBgAAAA==.',
Sq='Squachy:BAAANQADCgYIBgABNQAECgkJKgAUAOIXAA==.',
Ss='Sseoyoon:BAAANQAECgUIDQAAAA==.Ssnneezzyy:BAAANQAECgUIEAAAAA==.',
St='Starwnd:BAAANQAECgUIBQABNQAFFAUICAAbAPkIAA==.Steadchi:BAAANQAECgcIEQAAAQ==.Stolibear:BAABNQAECoEdAAIkAAgKcR/QBQDdAgAkAAgKcR/QBQDdAgAAAA==.Stolidh:BAAANQAECgUICQABNQAECggIHQAkAHEfAA==.Stolidk:BAAANQADCgUIBQABNQAECggIHQAkAHEfAA==.Stolip:BAAANQAECgMIBAABNQAECggIHQAkAHEfAA==.Stonedtothe:BAAANQAECgQIBQAAAA==.Stoneycrusty:BAABNQAECoEkAAIfAAgKvhVJPwAuAgAfAAgKvhVJPwAuAgAAAA==.Straywalker:BAAANQADCgEIAQAAAA==.Strongside:BAAANQAECgQIBAAAAA==.Stublimë:BAAANQAECgUICwAAAA==.Studdie:BAAANQADCgYICQAAAA==.',
Su='Succeeds:BAAANQAECggICAAAAA==.Sungjinwooz:BAAANQAECgQICwAAAA==.Suntitan:BAAANQADCgIIAgABNQAECgYIDgABAAAAAA==.Suuhdude:BAABNQAECoEWAAISAAYKLRYqEwDjAQASAAYKLRYqEwDjAQABNQAECgkJHwAdANYdAA==.Suzue:BAAANQAECgEIAQAAAA==.',
Sw='Swd:BAAANQAECggIDwAAAA==.Swiffty:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Swudge:BAAANQAECgMIBgAAAA==.',
Sy='Syladeith:BAAANQAECgUICwAAAA==.Sylandrus:BAAANQADCgYJBgAAAA==.Sylbanas:BAAANQADCgQICgABNQAECgUIBwABAAAAAA==.Syldrunk:BAAANQADCgcIDgAAAA==.Sylvashaman:BAAANQAECgUICQAAAA==.',
Sz='Szolkarr:BAAANQADCgQIBAAAAA==.',
['Sé']='Séii:BAAANQADCgYIBgAAAA==.',
['Sÿ']='Sÿdney:BAAANQADCggICwAAAA==.',
Ta='Tabarnaka:BAAANQAECgQICQAAAA==.Tairnock:BAAANQAECgYICwAAAA==.Takabaka:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Tamira:BAAANQAECgEIAQAAAA==.Tankadina:BAAANQADCgEIAQAAAA==.Tanzee:BAABNQAECoEqAAMPAAkK9Q/UQwAQAgAPAAkK9Q/UQwAQAgATAAEKpAuRZwAoAAAAAA==.Tarmarion:BAAANQAECgYIBgABNQAECgkJHgAcAOIgAA==.Tarmesan:BAABNQAECoEeAAIcAAkK4iDHBAArAwAcAAkK4iDHBAArAwAAAA==.Tastytooth:BAABNQAECoEXAAMDAAgK8QVwOwBxAQADAAgK8QVwOwBxAQAdAAMKuwC4VABBAAAAAA==.Taytaytyrone:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQAECgUICQAAAA==.',
Te='Tegadin:BAAANQADCgYIHAAAAA==.Telemanus:BAAANQADCgUIBQAAAA==.Telhani:BAAANQAECgQICAAAAA==.Tesse:BAAANQAECgEIAQAAAA==.',
Th='Thadude:BAAANQAECgQIBAABNQAECggIIQAYALIcAA==.Thannos:BAABNQAECoEhAAIEAAkKOSMVBQCSAwAEAAkKOSMVBQCSAwAAAA==.Thanos:BAAANQAECgYICgAAAA==.Thanozul:BAAANQAECgUICQAAAA==.Thark:BAAANQAECgUJDAAAAA==.Thatonebear:BAAANQAECgUIBQAAAA==.Thawnn:BAAANQADCgQIBQAAAA==.Theberos:BAAANQADCggICgAAAA==.Thebigd:BAAANQADCgQIBAAAAA==.Thebighoss:BAAANQAECgEIAQAAAA==.Thedùde:BAAANQAECgQIBAABNQAECggIIQAYALIcAA==.Thelgrus:BAAANQADCggIIAAAAA==.Thesmanmeta:BAAANQADCgUIBQAAAA==.Thoern:BAAANQADCggIEgAAAA==.Thorane:BAAANQADCgYJBgAAAA==.Thrashcan:BAAANQAECgQIBwABNQAECgYICAABAAAAAA==.Threem:BAAANQAECgEIAQAAAA==.Threepercent:BAAANQAECgcIEwAAAA==.Threesteps:BAAANQADCgIIAgAAAA==.Throad:BAAANQADCgcJCAAAAA==.Throatzilla:BAAANQAECgUICAAAAA==.Throwbackhlz:BAAANQAECgYIDQAAAA==.Throwinshåde:BAAANQAECgUJBQAAAA==.Thudmuffin:BAAANQAECgQICAABNQAECgQICgABAAAAAA==.Thyrealest:BAAANQADCgEJAQAAAA==.Thysania:BAAANQABCgYICQABNQABCgIIAgABAAAAAA==.',
Ti='Tides:BAABNQAECoEfAAMMAAkK/BLqPQAeAgAMAAkK/BLqPQAeAgAfAAEKtQEaFQEkAAAAAA==.Tilyne:BAAANQABCgIJAgAAAA==.Tinarii:BAACNQAFFIEFAAInAAQKICZFAQDMAQAnAAQKICZFAQDMAQA1AAQKgR0AAicACQqqJm4AAOUDACcACQqqJm4AAOUDAAAA.Tinyshadow:BAAANQAECgEIAgAAAA==.Tinytit:BAAANQAECgQIBAAAAA==.Tinytusk:BAAANQABCgIIAgAAAA==.Titdruid:BAAANQADCgUIBQAAAA==.Titpoosy:BAAANQADCgYICQAAAA==.Tiusele:BAAANQABCgEIAQAAAA==.Tizali:BAAANQADCgUIBQABNQAECgkJIQAGAAUgAA==.',
To='Tonystonk:BAAANQAECgQIBwAAAA==.Toombz:BAAANQADCgYIBgAAAA==.Toreto:BAAANQADCgEIAgAAAA==.Totemkoff:BAAANQABCgMIAwAAAA==.Toureg:BAAANQAECgUIBQAAAA==.',
Tr='Tragha:BAAANQADCgcIEAAAAA==.Trayker:BAAANQADCgQIBAAAAA==.Traynisa:BAAANQADCgUICAAAAA==.Treykor:BAAANQADCgQIBAAAAA==.Tria:BAAANQAECgEIAwAAAA==.Trixrforkids:BAAANQADCgYIBgAAAA==.Trlight:BAAANQAECgcICQAAAA==.Trollsicle:BAAANQAECgQICgAAAA==.Trotah:BAAANQADCgYICQAAAA==.Tryzz:BAAANQAECgUICwAAAA==.',
Tu='Tubhead:BAAANQAECgQICQAAAA==.Tumamaesmia:BAAANQAECgIIAgABNQAECgQIEAABAAAAAA==.Tunare:BAAANQAECgIIAwAAAA==.Tusknflamer:BAAANQADCgUIBwAAAA==.',
Tw='Twoman:BAAANQAECgUIBQABNQAECgkJGQACABIfAA==.Twylla:BAAANQAECgUIBgAAAA==.',
Ty='Tynak:BAAANQADCgQIBAAAAA==.',
Ug='Ugroto:BAAANQAECggIEAAAAA==.',
Ul='Uldred:BAAANQADCgUIBQABNQAECgkJIQAGAAUgAA==.',
Un='Unclesnottyp:BAAANQAECgEIAwAAAA==.Unmortal:BAAANQAECgUJDAAAAA==.',
Ur='Urotherdaddy:BAAANQAECgEIAQAAAA==.Uruker:BAAANQADCgIIAgAAAA==.',
Us='Useurblinker:BAAANQADCgcIBwAAAA==.',
Va='Valglacius:BAAANQADCgYICwAAAA==.Valkrin:BAAANQADCgYIBgAAAA==.Valonthir:BAAANQADCggIEwAAAA==.Valstone:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.Vancleave:BAAANQAECgMJAwAAAA==.Vargruf:BAAANQADCggICAABNQAECgcIGwAcADMcAA==.Vasati:BAAANQAECgIIAgABNQAECgkJIQAGAAUgAA==.Vaylethrayne:BAAANQABCgQIBQAAAA==.',
Ve='Vend:BAAANQAECgUIBQAAAA==.Verguetta:BAAANQAECgQIBwAAAA==.Verinsedai:BAABNQAECoEZAAIVAAkKUARtUABKAQAVAAkKUARtUABKAQAAAA==.Vesimer:BAAANQADCggIFQAAAA==.',
Vi='Viber:BAAANQADCgcIBwAAAA==.Vicvondik:BAAANQADCgQIBAAAAA==.Vildri:BAAANQAECgUICgAAAA==.Violetknight:BAAANQADCgIIAgAAAA==.',
Vo='Voidrey:BAAANQAECgMJBgAAAA==.Voikullten:BAAANQADCgUIBQAAAA==.Vornash:BAAANQAECgQIBgAAAA==.',
Vy='Vylax:BAAANQAECgEIAQAAAA==.Vylent:BAAANQADCgYIBgAAAA==.',
Wa='Waddleweaver:BAAANQADCggICAAAAA==.Wardogsix:BAAANQAECgYICAAAAA==.Warkraz:BAAANQADCgMIAwAAAA==.Warrush:BAAANQAECgcIEwAAAA==.Watchmedps:BAAANQAECgIJAgAAAA==.',
We='Wevv:BAAANQADCgMIAwAAAA==.Weyds:BAAANQADCgUIBQAAAA==.',
Wi='Wildthang:BAAANQADCgQIBAAAAA==.Willhelt:BAAANQAECgUICgAAAA==.Willpray:BAAANQAECgUICwAAAA==.Windle:BAAANQAECgYIBwAAAA==.Windrunnér:BAAANQAECgQICAAAAA==.Winterwølf:BAAANQADCgIJAgAAAA==.',
Wo='Wobblepot:BAAANQAECgcIBwAAAA==.Wontondesire:BAABNQAECoEYAAInAAcKlwv8EwBaAQAnAAcKlwv8EwBaAQAAAA==.Wowii:BAAANQAFFAEIAQABNQAFFAIIAgABAAAAAA==.',
Wu='Wulfpriest:BAAANQAECggJBwABNQAECgYICgABAAAAAA==.',
Xa='Xantry:BAEBNQAECoEYAAMhAAcKQhDXQgA9AQAhAAYKKQ/XQgA9AQAYAAYKNAwlXgAxAQAAAA==.',
Xb='Xbambs:BAAANQADCgQIBAAAAA==.',
Xe='Xerovladej:BAAANQAECgYIDgAAAA==.',
Xo='Xoog:BAAANQAECgIIBAAAAA==.Xozo:BAAANQADCgIIAgAAAA==.',
Xu='Xualene:BAAANQAECgUICgABNQAECgYIDgABAAAAAA==.Xurk:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Xw='Xwarrior:BAABNQAECoEYAAICAAgKCRD8dwDeAQACAAgKCRD8dwDeAQAAAA==.',
Ya='Yaaz:BAAANQAECgYIEAAAAA==.Yamata:BAAANQADCgQIBAAAAA==.',
Ye='Yetistorm:BAAANQADCgMIAwAAAA==.',
Yo='Yoz:BAAANQAECgEIAQAAAA==.',
Yu='Yuee:BAAANQAECgMIAwAAAA==.Yukonicüs:BAAANQAECgYIEAABNQAECgkJKwADAJghAA==.',
Za='Zaehara:BAAANQAECgEIAQAAAA==.Zanarian:BAAANQAECgEIAQAAAA==.Zappinboi:BAAANQAECgUIBwABNQAFFAUIEQAiAKwRAA==.Zatkiel:BAAANQAECgEJAQAAAA==.',
Ze='Zealot:BAAANQAECgMIAwAAAA==.Zedar:BAAANQAECgYIEAABNQAECgcIDgABAAAAAA==.Zeju:BAAANQAECgEIAgAAAA==.Zekinett:BAAANQADCgUIBQAAAA==.Zekker:BAAANQADCgcICgAAAA==.Zenolinwæ:BAAANQAECgUICAAAAA==.Zeohavoc:BAAANQADCgIIAgAAAA==.',
Zh='Zhondari:BAAANQAECgEIAgAAAA==.',
Zi='Zivanya:BAAANQAECgQIBQAAAA==.',
Zu='Zurprise:BAAANQADCgYICAAAAA==.',
Zx='Zxz:BAAANQAECggIDgAAAA==.',
Zy='Zyrgarran:BAAANQAECgEIAQAAAA==.',
['Zá']='Záraya:BAABNQAECoEfAAMEAAgKNRZKPgArAgAEAAgKNRZKPgArAgAaAAEKfAapWAEtAAAAAA==.',
['Zú']='Zúpái:BAAANQAECgEIAQAAAA==.',
['Àz']='Àzæs:BAAANQAECgUIBgAAAA==.',
['Ät']='Ätreo:BAAANQAECgQJBgAAAA==.',
['Åi']='Åirå:BAAANQADCgEIAQAAAA==.',
['Æl']='Ælusive:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
['Ço']='Çondemned:BAAANQADCgQIBAABNQADCggIEgABAAAAAA==.',
['Ém']='Émperor:BAAANQADCgUIBQABNQADCgYIDQABAAAAAA==.',
['Îc']='Îcyhot:BAAANQADCggIEgAAAA==.',
['Ðr']='Ðräx:BAAANQAECgUIEAAAAA==.',
['Óh']='Óhelgur:BAAANQADCgIIAgAAAA==.',
['Öh']='Öhgr:BAAANQAECgMIBAAAAA==.',
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
