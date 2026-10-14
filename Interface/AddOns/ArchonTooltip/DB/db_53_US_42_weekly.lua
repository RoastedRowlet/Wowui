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

local lookup = {'Unknown-Unknown','Warrior-Arms','DemonHunter-Havoc','Paladin-Holy','Mage-Arcane','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Priest-Shadow','Paladin-Protection','DeathKnight-Unholy','Shaman-Enhancement','Priest-Discipline','Druid-Balance','Druid-Feral','DeathKnight-Blood','Warlock-Affliction','Mage-Fire','Paladin-Retribution','Shaman-Elemental','Evoker-Preservation','Warrior-Fury','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','DemonHunter-Devourer','Mage-Frost','DeathKnight-Frost','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Guardian','Hunter-Survival','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Bonechewer',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aandras:BAAANQAECgcIEwAAAA==.',
Ab='Abbey:BAAANQADCgYIBgAAAA==.Abhayah:BAAANQAECgMIBwAAAA==.Absdots:BAAANQAECgQIBAABNQAECgUIDwABAAAAAA==.Absportls:BAAANQAECgUIDwAAAA==.',
Ac='Acelliste:BAAANQAECggIEwAAAA==.Acrylix:BAAANQADCgYICAAAAA==.',
Ad='Adventurerr:BAAANQAECgMIAQAAAA==.',
Af='Affgrezz:BAEANQADCgQIBAABNQAECgcIEwABAAAAAA==.',
Ai='Aidlef:BAAANQAECgMIBAABNQAECgkJGQACAGUhAA==.Aikenbranwen:BAAANQAECgQIBQAAAA==.Aillannia:BAAANQAECgYIDAAAAA==.Airwalkin:BAAANQADCgUIBQAAAA==.',
Al='Alandor:BAAANQADCgUICgAAAA==.Aleathris:BAAANQAECgYIDQAAAA==.Allfire:BAEBNQAECn85AAIDAAkK8CInBwCEAwADAAkK8CInBwCEAwAAAA==.Alutier:BAAANQAECgEIAQAAAA==.Aluunix:BAAANQAECgYICwAAAA==.Alyse:BAABNQAECn8oAAIEAAkKdhxTJQDTAgAEAAkKdhxTJQDTAgABNQAFFAEIAQABAAAAAA==.Alyta:BAAANQADCggIGgAAAA==.Alzulra:BAAANQADCgYIBgAAAA==.',
Am='Amayla:BAAANQADCgcIBwAAAA==.Amoracon:BAAANQADCgUIBQAAAA==.Amushroom:BAAANQAECgIIAgAAAA==.',
An='Anilfizzur:BAAANQADCgMIAwAAAA==.Anthanka:BAAANQADCggICAAAAA==.Anubiá:BAAANQADCgYIBwAAAA==.Anulstorm:BAAANQADCgYIEAAAAA==.Anundir:BAABNQAECn8XAAIEAAcKygijmABUAQAEAAcKygijmABUAQAAAA==.',
Ao='Aoiue:BAAANQAECgUIEAAAAA==.Aondor:BAABNQAECn8kAAIFAAgKYxe2mgBKAgAFAAgKYxe2mgBKAgAAAA==.',
Ap='Applepi:BAAANQADCgEIAQAAAA==.',
Ar='Araenna:BAAANQADCgUIBQAAAA==.Arcanical:BAAANQADCgYIDAAAAA==.Arday:BAABNQAECn8gAAIDAAkKUB2OHACxAgADAAkKUB2OHACxAgAAAA==.Areala:BAAANQAECggICAAAAA==.Arksos:BAAANQADCgEIAQAAAA==.Aroldo:BAAANQAECgEIAQAAAA==.Aroromunroe:BAABNQAECn8fAAIGAAkKUxEmVwAJAgAGAAkKUxEmVwAJAgABNQADCggIDgABAAAAAA==.Arrancateta:BAAANQAECgQIDwAAAA==.Arthredemis:BAAANQADCgQIBAAAAA==.',
As='Asena:BAAANQADCgQIBAABNQAFFAQIBwAHAA4QAA==.Ashblast:BAAANQAECgcICwAAAA==.Ashira:BAAANQAECgUICQABNQAFFAMIBwAIAIsWAA==.Askleppius:BAAANQADCgIIAgAAAA==.Astarouge:BAABNQAECn8kAAIJAAkKXiDcCQA9AwAJAAkKXiDcCQA9AwAAAA==.Astrafury:BAAANQADCgcIBwAAAA==.Astrasneaky:BAABNQAECn8eAAQKAAkKhBNXCAAZAgAKAAgKhBNXCAAZAgALAAcK5QYmLgBLAQAJAAQK+QtXdQDTAAAAAA==.',
At='Atchafalaya:BAABNQAECn8iAAIMAAcKVRNhLQCsAQAMAAcKVRNhLQCsAQABNQAECggIJQAMAKIMAA==.',
Av='Avatarstate:BAAANQADCgYICAAAAA==.Avonleâ:BAAANQAECgEIAQAAAA==.',
Aw='Awrina:BAABNQAECn8dAAIHAAcKACGaWQBkAgAHAAcKACGaWQBkAgAAAA==.',
Az='Azylrog:BAAANQADCggIEwAAAA==.',
Ba='Baalrin:BAAANQADCgUIBQAAAA==.Babymiko:BAAANQAECgIIAwAAAA==.Babypeech:BAAANQADCgcIEgAAAA==.Bakudo:BAAANQABCgYICAAAAA==.Bakulu:BAAANQAECgcIDwAAAA==.Bantoou:BAAANQAECgUIDQAAAA==.Batcat:BAAANQADCgMIAwAAAA==.Bathoryz:BAABNQAECn8gAAMNAAgKABMYbwAOAgANAAgKABMYbwAOAgAOAAEKAADhiAAWAAAAAA==.Battlescars:BAAANQAECgIIAgAAAA==.Bauhaus:BAAANQADCgYIDwAAAA==.Bauld:BAAANQAECgUIEgAAAA==.',
Bd='Bdbypaladin:BAAANQABCgQIBAAAAA==.',
Be='Beacong:BAAANQAECggICAAAAA==.Beardybear:BAAANQAECgQIBgAAAA==.Bearface:BAAANQADCgYIBgAAAA==.Bearicaide:BAAANQAECggIDwAAAA==.Bearnorgas:BAAANQADCggICAAAAA==.Beautiful:BAAANQADCgYIBgAAAA==.Beefygee:BAAANQADCgMIAwAAAA==.Belldrak:BAAANQADCgUIBQAAAA==.Belldren:BAAANQAECgEIAQAAAA==.Belldrin:BAAANQAECgQIBQAAAA==.Bepaulie:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Bergidum:BAAANQADCgcJDAAAAA==.Beriamilbinc:BAAANQADCgYICAAAAA==.Berladilana:BAAANQAECgIIAgAAAA==.Besota:BAAANQADCgcIBgAAAA==.Bewmy:BAAANQAECgcIEgAAAA==.',
Bh='Bhucket:BAAANQADCgEIAQAAAA==.',
Bi='Biglett:BAABNQAECn8iAAMHAAgKjCBkSgCMAgAHAAcKTyJkSgCMAgAIAAYK7B4OJAAqAgAAAA==.Bignagos:BAAANQAECgEIAQAAAA==.Bigolboi:BAAANQAECgIIAwAAAA==.Bigthickheal:BAAANQADCgEIAQAAAA==.',
Bl='Blackk:BAACNQAFFH8HAAIGAAMK/xgoFAAOAQAGAAMK/xgoFAAOAQA1AAQKfygAAgYACQoNH5IgAOUCAAYACQoNH5IgAOUCAAAA.Blackxcoffee:BAAANQADCgIIAgAAAA==.Bladesong:BAAANQAECgQIAgAAAA==.Blood:BAAANQAECgYICAAAAA==.Bloodietraks:BAAANQAECgYIBwAAAA==.Blorglock:BAACNQAFFH8FAAMNAAIKrRD4LwCaAAANAAIKvA/4LwCaAAAOAAEKvwxCHgBLAAA1AAQKfzAAAw0ACQrUHEY/AJECAA0ACAqXG0Y/AJECAA4ABAplGicnAD0BAAAA.Blorgonp:BAAANQAECgYIBgABNQAFFAIIBQANAK0QAA==.Blorgonw:BAAANQAECggIEgABNQAFFAIIBQANAK0QAA==.Blowaegis:BAABNQAECn8gAAIHAAgKkhYqZABKAgAHAAgKkhYqZABKAgAAAA==.Blownoutshax:BAAANQADCgEIAQAAAA==.Bluntnfortys:BAAANQADCgYICwAAAA==.Blupenguiny:BAABNQAECn8oAAMPAAkKZwoVbQDSAQAPAAkKZwoVbQDSAQAQAAEKAADvkAAWAAAAAA==.Blóódý:BAAANQADCgIIAgAAAA==.',
Bm='Bmfsleeps:BAAANQADCgUICAAAAA==.',
Bn='Bnortwarrior:BAAANQAECgQICQABNQAECgEIAQABAAAAAA==.',
Bo='Boanz:BAABNQAECn8YAAINAAcKLhJpkQC2AQANAAcKLhJpkQC2AQAAAA==.Bobasaurus:BAABNQAECn8lAAICAAkKPR1eKAAWAwACAAkKPR1eKAAWAwAAAA==.Bombastik:BAAANQAECgYICAAAAA==.Bondi:BAAANQADCgQIBAABNQAECgYICAABAAAAAA==.Bonesnapp:BAAANQAECgQIAwABNQAECgkJKgARADQiAA==.Booperry:BAAANQADCggICAAAAA==.Bosskün:BAAANQAECgUICwABNQAECgUIEAABAAAAAA==.Bossticles:BAAANQAECgEIAQAAAA==.Bountie:BAABNQAECn8hAAIHAAgKGhgzYABUAgAHAAgKGhgzYABUAgAAAA==.Bountiè:BAAANQADCgEIAQABNQAECggIIQAHABoYAA==.Boyoyong:BAAANQADCgQIBAABNQAECgYIBgABAAAAAA==.',
Br='Brainmatter:BAAANQADCgUICgAAAA==.Brandedsoul:BAAANQADCgIIAgAAAA==.Brewztler:BAAANQAECgIIAQAAAA==.Brickaroni:BAAANQAECgEIAQAAAA==.Brightscale:BAAANQADCggIDgAAAA==.Brogak:BAAANQAECgQIBAAAAA==.Broham:BAAANQAECgEIAQAAAA==.Bromeheal:BAAANQADCgIIAgAAAA==.Bronik:BAABNQAECn8kAAICAAgKjBIgjgD0AQACAAgKjBIgjgD0AQAAAA==.Brujaja:BAAANQAECgMIAwAAAA==.',
Bu='Bubblebitc:BAAANQADCgYIBgAAAA==.Buckk:BAAANQADCgcIBwAAAA==.Buffmage:BAABNQAECn8qAAIFAAkK4R4SUADhAgAFAAkK4R4SUADhAgAAAA==.Bullman:BAAANQAECgQIBgABNQAFFAIIBQASAPkVAA==.Bullrûsh:BAAANQAECgYJCQAAAA==.Bullviper:BAAANQADCgYIDwAAAA==.Bumblbeetuna:BAAANQABCgIIAgAAAA==.Burnbrand:BAAANQAECgMIBAAAAA==.',
['Bä']='Bärok:BAAANQAECgQIBAAAAA==.',
['Bè']='Bèrsèrk:BAAANQADCgcIBwABNQAECgkJLQATALUaAA==.',
['Bì']='Bìgdaddy:BAAANQADCgYICwAAAA==.',
['Bø']='Bønestørm:BAABNQAECn8tAAITAAkKtRqTCgDHAgATAAkKtRqTCgDHAgAAAA==.',
['Bù']='Bùndee:BAABNQAECn8aAAIFAAgKeBKmxQD3AQAFAAgKeBKmxQD3AQAAAA==.',
Ca='Cabbâge:BAAANQADCgYIBgAAAA==.Cacapants:BAAANQADCgQIBQAAAA==.Cadencegs:BAAANQAECgYIDQAAAA==.Caliex:BAAANQAECgQIBAAAAA==.Califax:BAACNQAFFH8HAAIIAAMKixYuFQDlAAAIAAMKixYuFQDlAAA1AAQKfyYAAwgACQrpIkMdAGUCAAgABwqLIUMdAGUCAAcAAwpWJg3sACQBAAAA.Caller:BAAANQADCgIIAgAAAA==.Callsignwiz:BAAANQAECgcIEwAAAA==.Cannedbeans:BAAANQADCgMIBQAAAA==.Canuckcow:BAAANQADCggIDwAAAA==.Captantrips:BAAANQAECgIIAgAAAA==.Carltonswag:BAAANQADCgcIBwAAAA==.Catazhanir:BAAANQAECgMJAwAAAA==.Catbear:BAAANQAECgEIAQAAAA==.Catclown:BAABNQAECn8rAAMPAAgKGx3fOgB7AgAPAAgKGx3fOgB7AgAQAAYKiRGOOABdAQAAAA==.Cavonesee:BAAANQADCgcJCAAAAA==.Caylaramose:BAAANQADCggICAAAAA==.Cazsandra:BAABNQAECn8sAAMPAAkKPx6FHgD0AgAPAAkKPx6FHgD0AgAUAAQKABQYEQAUAQAAAA==.',
Cc='Ccs:BAAANQADCgcIFAAAAA==.',
Ce='Ceeque:BAAANQABCgIIAgAAAA==.Centos:BAAANQABCgIIAgAAAA==.Cethlenn:BAAANQADCgQIBAAAAA==.',
Ch='Chadsoss:BAAANQADCgYIBgAAAA==.Chamlio:BAAANQAECgEIAQAAAA==.Channis:BAAANQAECgEIAQAAAA==.Cheesepizza:BAAANQAECgEIAgAAAA==.Chenaccles:BAAANQAECgEIAQAAAA==.Chickenrally:BAABNQAECn8dAAICAAkKRiLoFABlAwACAAkKRiLoFABlAwAAAA==.Chicogel:BAAANQAECgYIBwABNQAECggIHQAEAAEPAA==.Chinobear:BAAANQAECgYICgAAAA==.Chixilog:BAAANQAECgUIBgAAAA==.Choda:BAAANQADCgIIAgAAAA==.Chodyboy:BAAANQABCgYIBgAAAA==.Cholmondeley:BAAANQADCggIDQAAAA==.Chublie:BAAANQAECgUIBQAAAA==.Chuchix:BAACNQAFFH8HAAMVAAQKexDLHwCRAAAVAAIKYAzLHwCRAAAMAAIK5AXzEACHAAA1AAQKfzYABBUACQoXG9QXAAcDABUACQoXG9QXAAcDAAwABwqDE5gpAM8BABYAAgr0GCIuAJsAAAAA.Chuckler:BAABNQAECn8VAAINAAgK6hKlbQARAgANAAgK6hKlbQARAgAAAA==.Chupacabris:BAAANQAECgEIAQABNQAECggIHQAEAAEPAA==.',
Cl='Cladtu:BAABNQAECn8aAAIXAAcKjwMFfQABAQAXAAcKjwMFfQABAQAAAA==.Cleiah:BAAANQADCgUIBQAAAA==.Cloudfisto:BAAANQADCggJEwAAAA==.',
Co='Colacolaz:BAACNQAFFH8WAAQOAAUKuSSpBQDDAAANAAMK2h6OGAA1AQAOAAIK8iOpBQDDAAAYAAEKAABVCgBUAAA1AAQKfzAAAw0ACQrYJQsIAIsDAA0ACQobJQsIAIsDAA4ABgq5JRQMADUCAAAA.Colasham:BAABNQAECn8iAAITAAkKFCW2AADOAwATAAkKFCW2AADOAwABNQAFFAUIFgAOALkkAA==.Coldhands:BAAANQADCgEIAQABNQAECgkJNAAJAMgiAA==.Coldplunge:BAAANQAECgEIAQAAAA==.Colombiano:BAAANQAECgQIDgABNQAECggIHQAEAAEPAA==.Coltoff:BAACNQAFFH8LAAIPAAUK2w7wEQB6AQAPAAUK2w7wEQB6AQA1AAQKfygAAw8ACQoHGa47AHgCAA8ACQoHGa47AHgCABQAAQogASQyABwAAAAA.Conker:BAAANQADCgUIBQAAAA==.Coolebra:BAAANQADCgMIBgAAAA==.Coprates:BAAANQAECgUIEQAAAA==.Corgiquester:BAAANQAECgQIBgAAAA==.Corpserot:BAAANQADCgEIAQAAAA==.Corsin:BAAANQAECgQICAAAAA==.Cowbustion:BAABNQAECn8fAAMFAAgKxxqlagCpAgAFAAgKxxqlagCpAgAZAAEKLQQxDgAvAAAAAA==.',
Cp='Cptxcrunch:BAAANQADCgYICQAAAA==.',
Cr='Cracken:BAAANQADCggICgABNQAECggIGAAGAPAcAA==.Crankshot:BAAANQADCgYICgABNQAECgMIAwABAAAAAA==.Crimsonrayne:BAAANQAECgQIBQAAAA==.Cruciatus:BAAANQAECgYIDAAAAA==.Crusherlol:BAAANQAECgcIEgAAAA==.Crusherlul:BAAANQAECgIJAgABNQAECgcIEgABAAAAAA==.',
Cu='Curfew:BAAANQAECgcIEgAAAA==.',
Cy='Cyrathis:BAAANQAECggIEQAAAA==.',
['Cà']='Càt:BAAANQADCgEIAQAAAA==.',
Da='Dabigoldk:BAAANQAECgUIBQAAAA==.Daenen:BAAANQAECgIIAgAAAA==.Dahlya:BAAANQADCgEIAQABNQADCggICQABAAAAAA==.Dannzig:BAAANQADCgIJAgAAAA==.Daragon:BAAANQADCgEIAQABNQAFFAUICwAQAAggAA==.Dargran:BAAANQABCgIIAgAAAA==.Darkravèn:BAABNQAECn8jAAIMAAgKPAeGOQBNAQAMAAgKPAeGOQBNAQAAAA==.Darthevader:BAAANQAECgQIBAABNQAECgEIAgABAAAAAA==.Darthkitsune:BAAANQAECgMIAwAAAA==.Datbubblelol:BAABNQAECn8hAAIaAAkK2SKzEACFAwAaAAkK2SKzEACFAwAAAA==.Datchick:BAAANQADCggIHQAAAA==.Dawnkeeper:BAAANQADCgIIAgAAAA==.Dawnlily:BAAANQABCgcIDwAAAA==.Daxy:BAAANQADCgIIAgAAAA==.Daymandeuces:BAAANQAECggIAwAAAA==.Dazbek:BAACNQAFFH8LAAIFAAUKMRmEGQCpAQAFAAUKMRmEGQCpAQA1AAQKfzQAAgUACQopIMspAD0DAAUACQopIMspAD0DAAAA.',
De='Decày:BAAANQADCgUIBgABNQAECgkJKAANADokAA==.Dederedar:BAAANQADCgEIAQAAAA==.Deepdutch:BAABNQAECn8YAAIbAAgKvxOtYQD5AQAbAAgKvxOtYQD5AQAAAA==.Deezzeezz:BAAANQAECgYIEgABNQAECgkJPAAHAJ0fAA==.Degeneffe:BAAANQAECgUIDQAAAA==.Demonrey:BAAANQADCgMIAwAAAA==.Demoreknight:BAABNQAECn8pAAIXAAkKqRoQIQCpAgAXAAkKqRoQIQCpAgAAAA==.Devilboy:BAABNQAECn8mAAISAAkKwSTABQCdAwASAAkKwSTABQCdAwAAAA==.Dextrey:BAAANQADCggICAABNQAECgUJDgABAAAAAA==.',
Di='Dialuptacos:BAAANQABCgYIBgAAAA==.Diddycombs:BAAANQADCgYIBgAAAA==.Diplo:BAAANQADCgcIBwAAAA==.Dirtydaggers:BAAANQAECgcIAQAAAA==.Discbrown:BAABNQAECn8eAAMQAAkKFx5qFQCyAgAQAAkKFx5qFQCyAgAPAAEKeQIK9gA5AAAAAA==.Dischanges:BAAANQAECgQIBAAAAA==.Discmemommy:BAAANQAECgcIEgABNQAECgkJKAANADokAA==.Discontent:BAAANQAECgUICwAAAA==.Divinesmoke:BAAANQAECgQIBAAAAA==.',
Dj='Djblink:BAAANQAECgQICAABNQAECgQIDAABAAAAAA==.',
Dk='Dkgaming:BAAANQAECgQJCQABNQAECgkJHAAbAC8dAA==.',
Do='Dogeared:BAABNQAECn8lAAIMAAgKogzcMACPAQAMAAgKogzcMACPAQAAAA==.Doloc:BAEANQAECgQIBQABNQAECggIJgAcAIQUAA==.Domore:BAAANQAECgcIDQAAAA==.Donniedrako:BAAANQADCgQIBAAAAA==.Donson:BAABNQAECn8oAAIaAAkKaB9AQADRAgAaAAkKaB9AQADRAgAAAA==.Donsun:BAAANQADCgUIBQAAAA==.Doodlebobb:BAAANQAECgMIBAABNQAECgUIDgABAAAAAA==.Doomlakalaka:BAAANQAECgEIAQAAAA==.Doomshamalam:BAAANQADCgUICgAAAA==.Dorgh:BAAANQADCgIIAgAAAA==.Doskya:BAABNQAFFH8IAAMNAAQKowdbJgDTAAANAAMKRgtbJgDTAAAOAAEKXwCnJQAyAAAAAA==.Doubleclap:BAAANQADCggIEwAAAA==.',
Dp='Dpzofdoom:BAABNQAECn8aAAIdAAcKJQSaHADeAAAdAAcKJQSaHADeAAAAAA==.',
Dr='Dracthwnd:BAACNQAFFH8MAAMeAAUK2BC6BAB9AQAeAAUK2BC6BAB9AQAfAAIKYQgyDQB1AAA1AAQKfy8AAx4ACQqvJBMBAJ4DAB4ACQqvJBMBAJ4DAB8ACApwG3ESACcCAAAA.Dragbrown:BAAANQADCgYIBgAAAA==.Dragonsins:BAACNQAFFH8HAAINAAQKEx8FEwBnAQANAAQKEx8FEwBnAQA1AAQKfyUAAg0ACQq1IsAXACcDAA0ACQq1IsAXACcDAAAA.Drahron:BAAANQADCggIAgAAAA==.Drdiksmasher:BAAANQAECgUIEwAAAA==.Drekka:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Drogmax:BAAANQAECgQIDgAAAA==.Droptopp:BAABNQAECn8bAAIQAAkKMCQMBgB2AwAQAAkKMCQMBgB2AwAAAA==.Drusys:BAAANQAECgUICwAAAA==.Dryrod:BAAANQADCgYIDgAAAA==.',
Du='Duckelf:BAABNQAECn8rAAIMAAkKRiSYAwCMAwAMAAkKRiSYAwCMAwAAAA==.Dunranger:BAAANQAECgEIAQAAAA==.Durrga:BAACNQAFFH8HAAICAAIKoBohKgChAAACAAIKoBohKgChAAA1AAQKfzUAAgIACQrMI1ILAJoDAAIACQrMI1ILAJoDAAAA.',
['Dà']='Dàb:BAAANQAECgUIDgAAAA==.',
['Dã']='Dãftmõnk:BAABNQAECn8aAAIgAAgKVBH5KQDKAQAgAAgKVBH5KQDKAQAAAA==.',
['Dë']='Dëvildog:BAAANQADCggIDgAAAA==.',
Ed='Edgecrusherr:BAAANQAECgMJBAAAAA==.',
Eg='Egwenalmere:BAABNQAECn8fAAIDAAkKfgjdRgCLAQADAAkKfgjdRgCLAQAAAA==.',
El='Elainia:BAAANQADCgYIDgAAAA==.Elandae:BAAANQAECgEIAQAAAA==.Elinoosh:BAAANQADCgEIAQAAAA==.Elisaveta:BAAANQAECgMJAwAAAA==.Elliaa:BAAANQAECgQICgAAAA==.Elliard:BAAANQADCgUICAAAAA==.Elmahikera:BAAANQADCggJCAABNQAECgkJJgAQAFIWAA==.Elodi:BAAANQADCgYIBgAAAA==.',
Em='Emanx:BAAANQABCgIIAgABNQAECggIJgAaAF0XAA==.Embér:BAAANQAECggICQAAAA==.',
En='Enheduanna:BAAANQADCgUICAAAAA==.',
Eo='Eowyen:BAAANQADCgUIBQAAAA==.',
Ep='Epiiphany:BAAANQADCgcICAAAAA==.',
Er='Eriaedria:BAAANQAECgUIBgAAAA==.Erinsister:BAABNQAECn8cAAMbAAkKLx3vTQA8AgAbAAcKmR3vTQA8AgAGAAcKQweqowAoAQAAAA==.Erydius:BAAANQAECgQIBwAAAA==.',
Es='Esdeath:BAAANQABCgIIAgAAAA==.',
Ev='Evilpalz:BAAANQADCgMIAwAAAA==.Evodry:BAAANQADCgQIBAABNQAECgcIIAAHAPkiAA==.',
['Eì']='Eìrì:BAAANQAECgUICwAAAA==.',
['Eô']='Eôwyn:BAAANQADCgcIGwAAAA==.',
Fa='Faclion:BAAANQAECgUJCQAAAA==.Faketurkey:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Falkhor:BAAANQAECgYIDwAAAA==.Fancyhorse:BAAANQABCgIIAgAAAA==.Fari:BAAANQAECgUIEQAAAA==.Farstryder:BAAANQADCgYIBgAAAA==.Fatlootz:BAABNQAECn8oAAINAAkKOiT9BwCLAwANAAkKOiT9BwCLAwAAAA==.',
Fe='Fellwarden:BAAANQADCgMIAwAAAA==.Feltyah:BAAANQAECgIIAgAAAA==.',
Fi='Finnajuggyou:BAAANQAECgIIAgAAAA==.Finniker:BAAANQAECgcIEAAAAA==.Fiorina:BAABNQAECn8mAAIFAAgKvwe08wChAQAFAAgKvwe08wChAQAAAA==.Firefóx:BAAANQADCggICAAAAA==.Fishnet:BAAANQAECgUICwAAAA==.Fishthicc:BAAANQADCgYIEAAAAA==.',
Fl='Flexkin:BAABNQAECn8tAAMVAAkKGyTLBwCRAwAVAAkKGyTLBwCRAwAMAAkKtyG7BQBlAwAAAA==.Flicks:BAAANQAECgMIAwAAAA==.',
Fo='Foe:BAACNQAFFH8SAAIPAAYKOxWICAD9AQAPAAYKOxWICAD9AQA1AAQKfyIAAw8ACQqaHzAxAKACAA8ACQqaHzAxAKACABQAAQpqFi0pADAAAAAA.Fornor:BAACNQAFFH8FAAISAAIK+RVHFgClAAASAAIK+RVHFgClAAA1AAQKfyUAAhIACQrEHpkgAMYCABIACQrEHpkgAMYCAAAA.Foxfù:BAAANQADCgYIDAAAAA==.Foxkníght:BAACNQAFFH8HAAISAAIKWiICFADFAAASAAIKWiICFADFAAA1AAQKfzoAAhIACQpVJsIBAOIDABIACQpVJsIBAOIDAAAA.Foxxalot:BAAANQADCgQIBAAAAA==.Foxxpachi:BAAANQAECgQIBwAAAA==.',
Fr='Franký:BAAANQAECgQIBAAAAA==.Franzia:BAAANQADCgIIAgAAAA==.Frebaen:BAAANQAECgQIBQAAAA==.Freezenikko:BAAANQADCgEIAQAAAA==.Frogus:BAAANQAECgUICgAAAA==.Frostednight:BAAANQADCgUICgAAAA==.',
Fu='Fullgrim:BAAANQADCgQIBAAAAA==.Fungbuck:BAAANQADCgYIDgAAAA==.Fungbucko:BAAANQADCggIDgAAAA==.Fuule:BAABNQAECn8WAAIFAAgKkQbI+QCWAQAFAAgKkQbI+QCWAQAAAA==.Fuusei:BAABNQAECn8cAAMVAAcKexJaQwDjAQAVAAcKexJaQwDjAQAMAAEKKAuQewAjAAAAAA==.',
Fy='Fyrdrakon:BAABNQAECn8oAAIfAAgKSh6CCQDXAgAfAAgKSh6CCQDXAgAAAA==.',
Ga='Gabeitch:BAAANQADCgMIAwAAAA==.Gahero:BAAANQADCgQIBAAAAA==.Galapagós:BAAANQADCgYIEwAAAA==.Galaxus:BAABNQAECn8iAAIhAAkKGBqvFQC0AgAhAAkKGBqvFQC0AgAAAA==.Gammastorm:BAABNQAECn8vAAIiAAgKOQo7EQCQAQAiAAgKOQo7EQCQAQAAAA==.Gandallfin:BAAANQADCggICwAAAA==.Garokk:BAAANQAECgEIAgAAAA==.',
Ge='Gemmastone:BAAANQADCgcIBwAAAA==.',
Gh='Ghall:BAAANQADCgIIAgAAAA==.Ghrell:BAEBNQAECn8kAAIWAAgK8x6aCADGAgAWAAgK8x6aCADGAgAAAA==.',
Gi='Gickygackers:BAAANQAECgQIBQAAAA==.Gigglepeak:BAABNQAECn8bAAIRAAgKGAzYKwB7AQARAAgKGAzYKwB7AQAAAA==.Girlhands:BAAANQADCgIIAgAAAA==.',
Gl='Glekimage:BAAANQAECgQIAwAAAA==.',
Gn='Gnormage:BAAANQABCgEIAQAAAA==.',
Go='Goatmylk:BAAANQAECgUICgAAAA==.Goattote:BAAANQAECggIBAABNQAECgkJKAANADokAA==.Gobblr:BAAANQADCgUJCAAAAA==.Goldensorbet:BAAANQADCgYIBgAAAA==.Golokis:BAAANQADCggICAABNQAECggIHAACAP8bAA==.Gonuhreeuh:BAAANQAECgYICgABNQAECggILgAFAHEQAA==.Gotz:BAAANQADCggIEwAAAA==.',
Gr='Grattick:BAAANQAECgUIDAAAAA==.Greenlightt:BAAANQAECgEIAQAAAA==.Greenxll:BAABNQAECn8hAAIbAAkKgCMlDgB2AwAbAAkKgCMlDgB2AwAAAA==.Greypa:BAAANQAECgUIBwAAAA==.Grezulock:BAEANQAECgcIEwAAAA==.Griggles:BAAANQAECgQICAAAAA==.Grizzbane:BAAANQADCgEIAQAAAA==.Grizzleygrez:BAEANQADCgYIDwABNQAECgcIEwABAAAAAA==.Grolk:BAAANQAECgQIBwAAAA==.',
Gu='Guerita:BAAANQADCgUICQAAAA==.Gumptruck:BAABNQAECn8eAAISAAgKsCPpHgDQAgASAAgKsCPpHgDQAgAAAA==.',
Gw='Gwenevere:BAAANQADCgMIAwAAAA==.',
Ha='Habibii:BAAANQAECgcICwAAAA==.Hakana:BAAANQADCgUJBwABNQAECgcIEgABAAAAAA==.Hardendaire:BAAANQADCgYIDQAAAA==.Harryballzac:BAAANQADCgMIAwAAAA==.Hashycasty:BAAANQADCgcIBwAAAA==.Hashypally:BAAANQAECggIEQAAAA==.Hathern:BAAANQADCgIIAgAAAA==.Hawkmees:BAABNQAECn8qAAMVAAgKPhPGOAAlAgAVAAgKPhPGOAAlAgAMAAEKSQ67dAAyAAAAAA==.Hazbretzul:BAAANQAECgYICgAAAA==.',
He='Headyy:BAAANQAECggIBwAAAA==.Hediff:BAAANQADCggIDQAAAA==.Heelza:BAAANQAECgYIDAAAAA==.Hellskitchën:BAAANQAECgIIAgAAAA==.Hellxan:BAEANQAECgQIBAABNQAECggIJgAjAEIaAA==.Help:BAAANQAECgUIDgAAAA==.Hephs:BAAANQAECgQIBgABNQAECgYIEwABAAAAAA==.Herlo:BAAANQAECgUIDwAAAA==.Hermionejean:BAAANQADCgUJBQAAAA==.Hexuz:BAAANQAECgQIBAAAAA==.',
Hi='Hilas:BAAANQADCggICgAAAA==.Hipster:BAAANQAECgIIAwABNQABCgIIAgABAAAAAA==.',
Ho='Holeekow:BAAANQADCgEIAgAAAA==.Hollymollie:BAAANQAECgYICAAAAA==.Holoey:BAAANQABCgIIAgAAAA==.Holychicken:BAAANQAECgMIAwABNQAECgkJHQACAEYiAA==.Holymobeus:BAAANQAECgQICwAAAA==.Holypower:BAAANQADCgYICQAAAA==.Holythot:BAABNQAECn8kAAIQAAkKlBujEwDIAgAQAAkKlBujEwDIAgAAAA==.Hoofanhammer:BAAANQAECgEIAQAAAA==.Hornzart:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.Howoriginal:BAABNQAECn8VAAIaAAcKOBO4uACmAQAaAAcKOBO4uACmAQABNQAECggIFwAhAL8PAA==.Hozrozlok:BAABNQAECn8eAAMGAAkK/g5dZQDZAQAGAAkK/g5dZQDZAQAbAAUKQwi4zwDvAAAAAA==.Hozzula:BAAANQADCgcIBwAAAA==.',
Hu='Huntdry:BAABNQAECn8gAAMHAAcK+SJyRgCWAgAHAAcK+SJyRgCWAgAIAAEKAADghgA2AAAAAA==.Hurkoh:BAAANQAECgQIBQAAAA==.Hurrikin:BAAANQADCggJCAAAAA==.Hushpuppié:BAAANQAECgYIDwAAAA==.',
Hy='Hypereon:BAABNQAECn8oAAIRAAgKYyCMDADQAgARAAgKYyCMDADQAgAAAA==.',
Ib='Ibox:BAAANQAECgUICQAAAA==.',
Ic='Iceden:BAAANQAECgQIDgAAAA==.Icyweenor:BAAANQAECgIIAgAAAA==.',
Id='Idkdude:BAABNQAECn8UAAIFAAkKKB4/WQDNAgAFAAkKKB4/WQDNAgAAAA==.',
Ie='Ielarth:BAAANQADCgEIAQAAAA==.',
If='Ifhediehedie:BAAANQADCgcIBwAAAA==.',
Ig='Ignateus:BAAANQADCgIIAgAAAA==.',
Ih='Ihrasx:BAAANQAECggIDAAAAA==.',
Ik='Ikeepdying:BAAANQAECgEIAQAAAA==.Ikevzl:BAAANQAECgMIAwAAAA==.',
Il='Illadarina:BAABNQAECn8hAAIkAAgKIBAmEACsAQAkAAgKIBAmEACsAQAAAA==.Illys:BAAANQADCgEIAQAAAA==.Illí:BAAANQADCgcICAAAAA==.',
In='Incetardis:BAAANQADCgcIGgAAAA==.Indiriel:BAAANQAECgcIBgAAAA==.',
Ir='Iradoria:BAACNQAFFH8HAAIQAAMK6RcXDQABAQAQAAMK6RcXDQABAQA1AAQKfygAAxAACQpYHTIQAPECABAACQpYHTIQAPECAA8ABAqIF1KZAEQBAAAA.Ironplay:BAAANQAECgMIAwAAAA==.',
Is='Isoldè:BAAANQADCgcIBwAAAA==.Istabu:BAAANQAECggIEQAAAA==.',
It='Itachi:BAACNQAFFH8RAAMSAAYKlBp+BQDLAQASAAYKlBp+BQDLAQAjAAMKSRLhDgDmAAA1AAQKfyYAAyMACQp1JkoGAHsDACMACQoFJkoGAHsDABIACQoGJj0SACQDAAAA.Itamï:BAABNQAECn8iAAIXAAkKOBZ/KQB1AgAXAAkKOBZ/KQB1AgAAAA==.',
Iv='Ivannacream:BAAANQAECgIIAgAAAA==.',
Ja='Jaagren:BAAANQAECgQIBAAAAA==.Jadawin:BAABNQAECn8dAAIEAAkKshHASwA3AgAEAAkKshHASwA3AgAAAA==.Jaketta:BAAANQAECgEIAQAAAA==.Jaquemehof:BAAANQAECgEIAQAAAA==.Jasnah:BAACNQAFFH8NAAIFAAQKuw2kKwApAQAFAAQKuw2kKwApAQA1AAQKfyoAAgUACQoxGAp0AJUCAAUACQoxGAp0AJUCAAAA.Jayrel:BAACNQAFFH8HAAIPAAIK7xGlJgCXAAAPAAIK7xGlJgCXAAA1AAQKfzoAAxQACQppGb0JALUBAA8ACQr6FtY6AHsCABQACAprEL0JALUBAAAA.Jaytheg:BAAANQAECggIDAAAAA==.Jaythep:BAAANQADCgQIBAAAAA==.',
Je='Jerrik:BAABNQAECn8lAAIaAAgK2hGolgDyAQAaAAgK2hGolgDyAQAAAA==.',
Ji='Jillean:BAAANQAECggICAAAAA==.',
Jo='Joedky:BAAANQADCgcIBwAAAA==.Joeyexotic:BAAANQAECgUICwAAAA==.Jokem:BAAANQADCgUIBQAAAA==.Jozelyn:BAAANQADCgEJAQAAAA==.',
Ju='Juankkii:BAAANQADCggICgABNQAECgQICgABAAAAAA==.Juggerbear:BAAANQAECgEJAQAAAA==.Juiçy:BAAANQAECgUICwAAAA==.Juls:BAAANQAECgcIDwAAAA==.Julìette:BAAANQADCgEIAQAAAA==.Justhetip:BAAANQADCgEIAQAAAA==.Justjason:BAAANQAECgQICQAAAA==.',
['Jä']='Jäger:BAAANQAECgQIBQAAAA==.',
Ka='Kagama:BAAANQAECgQIBQAAAA==.Kaladora:BAAANQAECgUIEwAAAA==.Kalatabi:BAAANQADCggICAABNQAECgkJKgARADQiAA==.Kalatai:BAABNQAECn8qAAIRAAkKNCLABgA5AwARAAkKNCLABgA5AwAAAA==.Kamisenshi:BAAANQADCgIIAgAAAA==.Kamkanzakur:BAAANQAECgEIAQAAAA==.Kaosforged:BAAANQAECgQIBgAAAA==.Kaosstorm:BAAANQAECgQICAAAAA==.Kaostheory:BAAANQAECgMIAwAAAA==.Karayna:BAAANQAECggIEQAAAA==.Kareemcheese:BAAANQAECgQJBgAAAA==.Kauko:BAAANQAECggIEwAAAA==.',
Ke='Keadron:BAAANQADCgIIAgAAAA==.Kellanash:BAAANQADCgUICAAAAA==.Kevz:BAAANQAECgIIAgAAAA==.Kezwik:BAAANQAECgUICwAAAA==.',
Kh='Khaotick:BAAANQAECgEIAQAAAA==.Kheetz:BAAANQAECgEIAgAAAA==.Kháris:BAAANQADCgUIBQAAAA==.',
Ki='Kiilg:BAAANQADCgcIFwAAAA==.Kikomo:BAAANQAECgEIAQAAAA==.Kikosho:BAABNQAECn8tAAMlAAgK4hnVHAC1AQAlAAgK4hnVHAC1AQAgAAEKAAAzaQA1AAAAAA==.Kilaaj:BAAANQADCgIIAgAAAA==.Killerbane:BAAANQAECgUIBQAAAA==.Killgoro:BAAANQADCggIFgAAAA==.Kinclakis:BAAANQADCgQIBAAAAA==.Kinthor:BAAANQABCgIIAgAAAA==.Kirrin:BAABNQAECn8XAAIVAAkKixkaLQBxAgAVAAkKixkaLQBxAgAAAA==.Kisaragi:BAAANQAECgQIBAAAAA==.',
Kn='Kneecap:BAABNQAECn8pAAIEAAgKcyZzCACEAwAEAAgKcyZzCACEAwAAAA==.Kneepad:BAAANQADCgcIBwABNQAECggIKQAEAHMmAA==.Knetikara:BAABNQAECn82AAMiAAkKuQkeEQCSAQAFAAkK6gQD8gCkAQAiAAgKwwkeEQCSAQAAAA==.',
Ko='Kokokrantz:BAAANQAECgMIAwAAAA==.Korthix:BAAANQAECgUJDgAAAA==.Kosi:BAABNQAECn8oAAMhAAkK8g0MLwDFAQAhAAgK/gwMLwDFAQADAAgKmwquRQCTAQAAAA==.',
Kr='Kraanan:BAAANQADCgUIBQAAAA==.Krabs:BAAANQAECgQIBAAAAA==.Kraves:BAAANQAECgYICwAAAA==.Kreiedril:BAAANQADCggIJwAAAA==.Krispyish:BAABNQAECn8eAAMPAAkKmCDnDgBMAwAPAAkKmCDnDgBMAwAQAAYKlQ0UPgA4AQAAAA==.Krompir:BAAANQADCgcJBwAAAA==.',
Ku='Kulltena:BAAANQADCggICAAAAA==.Kulltina:BAAANQADCggICAAAAA==.Kurnous:BAAANQADCgUIBQAAAA==.',
Ky='Kyokaii:BAABNQAECn8YAAMCAAYK4QrL0wBDAQACAAYK4QrL0wBDAQAdAAEK0gYVNwAoAAAAAA==.',
['Kí']='Kíngcoyote:BAAANQAECggIBAAAAA==.',
La='Laarken:BAAANQAECgEIAQAAAA==.Lacedtotems:BAACNQAFFH8EAAIbAAMKDBv2FgAIAQAbAAMKDBv2FgAIAQA1AAQKfxcAAhsACQraJGQNAHwDABsACQraJGQNAHwDAAAA.Ladiluxanna:BAAANQAECgEIAQAAAA==.Lagexe:BAAANQAECgUICAAAAA==.Lakihaki:BAAANQAECgEIAQAAAA==.Laybia:BAAANQADCgEIAQAAAA==.Lazlo:BAAANQAECgQIAwAAAA==.',
Le='Lenrela:BAABNQAECn8bAAIWAAcKwRYgEAAHAgAWAAcKwRYgEAAHAgAAAA==.Leroenus:BAAANQADCgEIAQAAAA==.Lestealth:BAAANQAECgQIDAAAAA==.Letena:BAABNQAECn8oAAMVAAkKdg0hQQDxAQAVAAkKdg0hQQDxAQAmAAEKmQ0cXAA4AAAAAA==.Levyymage:BAAANQAECgYIEwAAAA==.',
Li='Lialyndra:BAAANQADCgYICgAAAA==.Licelia:BAAANQAECgcIEQAAAA==.Lilballohate:BAAANQADCgEIAQAAAA==.Liligayle:BAAANQADCgMIAwAAAA==.Lilsxe:BAAANQAECgcIBgAAAA==.Lilypadz:BAAANQAECgQIBAAAAA==.Linane:BAABNQAECn8yAAIDAAgK9x7BHACwAgADAAgK9x7BHACwAgAAAA==.Lite:BAAANQADCggICQABNQAECggIEAABAAAAAA==.Liveevil:BAAANQAFFAEIAQAAAA==.',
Ll='Llama:BAAANQADCgYIBgAAAA==.',
Lo='Loathsome:BAAANQADCgEIAQABNQAECgQICgABAAAAAA==.Locksummnplz:BAAANQAECgQIBAAAAA==.Lolmagician:BAAANQABCgIJAgABNQADCggJCAABAAAAAA==.Loquail:BAAANQADCgUIBQAAAA==.Lorgrith:BAAANQAECgQICgAAAA==.Lorike:BAAANQAECggICgAAAA==.Losthobo:BAAANQADCgEIAQAAAA==.',
Lu='Lucifoor:BAAANQAECgQIBgAAAA==.Luftim:BAAANQAECgEIAQAAAA==.Lunastellara:BAAANQAECgcIDAAAAA==.Lunoxx:BAAANQAECgIIAwAAAA==.Lurang:BAAANQAECgUIEgAAAA==.',
Ma='Macacbre:BAAANQADCgcICwAAAA==.Macdotnalds:BAAANQADCgMIAwAAAA==.Madetolock:BAAANQAECgEIAQAAAA==.Maerlyna:BAAANQABCgIIAwAAAA==.Magebrew:BAAANQAECgUIDAAAAA==.Mageycat:BAAANQADCgYICAABNQAECggIKwAPABsdAA==.Magicma:BAAANQAECgQIBAABNQAECgUICgABAAAAAA==.Magiks:BAAANQAECgMIBAAAAA==.Mahlah:BAAANQABCgQIBgAAAA==.Makarov:BAAANQADCgEIAQAAAA==.Maladen:BAAANQADCgUIBwAAAA==.Malevir:BAAANQABCgUIBQAAAA==.Maliun:BAABNQAECn8cAAIbAAcKLRxYUQAwAgAbAAcKLRxYUQAwAgAAAA==.Malusdemon:BAAANQAECgQIBQAAAA==.Mamasota:BAAANQAECgUIDAAAAA==.Markfunk:BAABNQAECn8xAAIFAAkK8iVPCgCuAwAFAAkK8iVPCgCuAwAAAA==.Markiepoo:BAAANQAECgcICwABNQAECgkJMQAFAPIlAA==.Markyboom:BAAANQADCgIIAgABNQAECgkJMQAFAPIlAA==.Markybowner:BAABNQAECn8ZAAIHAAgK+R1CQgCiAgAHAAgK+R1CQgCiAgABNQAECgkJMQAFAPIlAA==.Markykhan:BAAANQAECggIDAABNQAECgkJMQAFAPIlAA==.Markykong:BAAANQAECggIDQABNQAECgkJMQAFAPIlAA==.Martimusmagi:BAAANQADCgIIAgAAAA==.Maryjaiyne:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Mawmatz:BAAANQADCgEIAQAAAA==.',
Me='Mebashum:BAAANQAECgYICAAAAA==.Mechavexi:BAAANQAECgYIDAAAAA==.Medihunter:BAAANQAECgEIAQABNQAECgcIHAAaAMwRAA==.Meditations:BAABNQAECn8cAAIaAAcKzBFusAC5AQAaAAcKzBFusAC5AQAAAA==.Megumi:BAAANQAECgQIBAAAAA==.Meleath:BAAANQADCgEIAQAAAA==.Melibeth:BAAANQABCgEIAQAAAA==.Melledris:BAAANQAECgQIBAAAAA==.Metrakatanke:BAAANQADCgYICgAAAA==.Mexiflip:BAAANQADCgYICQAAAA==.',
Mi='Miamin:BAAANQAECgQIBwAAAA==.Michaaelvick:BAAANQADCgEIAQABNQAECgUICgABAAAAAA==.Midoriya:BAAANQAECgMIAQAAAA==.Mikeshifter:BAAANQAECgYIDQABNQAECgEIAgABAAAAAA==.Milgan:BAABNQAECn8jAAIGAAkKHCB6HQD1AgAGAAkKHCB6HQD1AgAAAA==.Minimochi:BAABNQAECn9QAAIPAAkK2h3oGwABAwAPAAkK2h3oGwABAwAAAA==.Missblackk:BAAANQADCgIIAgAAAA==.Mithyr:BAAANQADCgcIBwABNQAECgUIDQABAAAAAA==.',
Mn='Mneme:BAACNQAFFH8VAAIMAAUK2STxAgAgAgAMAAUK2STxAgAgAgA1AAQKfyUAAgwACQpZJH8FAGgDAAwACQpZJH8FAGgDAAAA.',
Mo='Mogani:BAAANQAECgcIDAAAAA==.Mohrdren:BAAANQADCgYICgAAAA==.Momoland:BAAANQAECgUICgAAAA==.Monkeypiglet:BAABNQAECn8cAAICAAgKvyFEMAD7AgACAAgKvyFEMAD7AgAAAA==.Moobiwan:BAAANQAECgIIBAABNQAECgEIAgABAAAAAA==.Moogies:BAAANQAECgEIAQABNQAECgUICgABAAAAAA==.Moogpal:BAAANQAECgMIBQABNQAECgUICgABAAAAAA==.Moogul:BAAANQAECgUICgAAAA==.Moovoe:BAAANQAECgUICwAAAA==.Morcarth:BAAANQAECgQIBQAAAA==.Mortal:BAAANQADCgEIAQAAAA==.Mortemer:BAAANQADCgIIAgAAAA==.Morts:BAAANQADCgYJBgAAAA==.',
Mu='Mulks:BAABNQAECn8XAAIGAAcKkww/mABGAQAGAAcKkww/mABGAQAAAA==.Multiblox:BAABNQAECn8sAAImAAkKgSCUBQA+AwAmAAkKgSCUBQA+AwAAAA==.Murgruuk:BAAANQADCggICQAAAA==.',
My='Myling:BAAANQADCggIAgAAAA==.',
['Mà']='Màrkham:BAAANQAFFAEIAQAAAA==.',
['Má']='Mágé:BAAANQAECgYICwABNQAECggIEQABAAAAAA==.',
['Må']='Måjïñßûüü:BAAANQAECgIIAgAAAA==.',
Na='Naam:BAAANQAECgYIEwAAAA==.Nadrin:BAAANQADCggIHQAAAA==.Naedora:BAABNQAECn8jAAMUAAgKkRzAAwCkAgAUAAgKkRzAAwCkAgAPAAEKVAuM/gAqAAAAAA==.Namixx:BAABNQAECn8qAAIUAAgKqR0JAwDQAgAUAAgKqR0JAwDQAgAAAA==.Naruwnd:BAAANQADCggICAABNQAFFAUIDAAeANgQAA==.Nassaela:BAAANQAECgcICwABNQAECgkJFAAFACgeAA==.Nathaanis:BAABNQAECn8fAAIaAAkKPhbQfwAlAgAaAAkKPhbQfwAlAgAAAA==.',
Ne='Necrodamus:BAAANQAECgEIAQAAAA==.Neliera:BAAANQABCgUIBQAAAA==.Neopolitangs:BAAANQAECgcIEQAAAA==.Nevs:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Nevsy:BAAANQADCgYICAAAAA==.Nezdispenser:BAAANQAECgMIBAAAAA==.',
Ni='Niduash:BAAANQADCgMIAwAAAA==.Nightchill:BAAANQAECgUICQAAAA==.Nim:BAAANQAECgEIAQAAAA==.Nimbletoes:BAABNQAECn8YAAIhAAcKuxymJgANAgAhAAcKuxymJgANAgAAAA==.Ninabudhu:BAAANQAECgQIBAAAAA==.Nirza:BAAANQAECgQIBwAAAA==.Nixara:BAAANQADCggICAAAAA==.Niziel:BAABNQAECn8uAAMjAAkKdxtbFgDVAgAjAAkKdxtbFgDVAgAXAAEK3wcsyAA1AAAAAA==.',
No='Nofurrys:BAAANQADCggICQAAAA==.Nokorin:BAAANQAECgEIAwAAAA==.Nolo:BAAANQADCgUIBQABNQAFFAQIBgAJAKQiAA==.Nomamesrko:BAAANQADCgEIAQAAAA==.Noranis:BAAANQAECgEIAQAAAA==.Noros:BAACNQAFFH8GAAIJAAQKpCLjCAB1AQAJAAQKpCLjCAB1AQA1AAQKfykAAgkACQqpI8gHAFYDAAkACQqpI8gHAFYDAAAA.',
Nu='Nuggalicious:BAAANQAECgQIBQAAAA==.Nuggss:BAAANQABCgEIAQAAAA==.Nursjoy:BAAANQADCggICQAAAA==.Nuumm:BAAANQADCgIIAgAAAA==.',
Nv='Nveturkey:BAAANQAECgIIAgAAAA==.',
Ok='Oko:BAABNQAECn8cAAMSAAcKZRwiRwD4AQASAAcKZRwiRwD4AQAjAAcKbBDZTgByAQAAAA==.',
Ol='Oldmanpeanut:BAAANQADCggICQABNQAECgkJHAAbAC8dAA==.Olopa:BAAANQABCgQIBQAAAA==.',
Om='Omenwar:BAAANQADCggJIAAAAA==.Omni:BAAANQADCggICwAAAA==.',
Or='Orcazum:BAAANQAECggIEAAAAA==.Orelia:BAAANQAECgMIAwAAAA==.Orfnanu:BAAANQADCggIDQABNQAECgQIBgABAAAAAA==.Ornarl:BAAANQAECgMIBgAAAA==.Orranhar:BAAANQADCgYIBgAAAA==.',
Ot='Ottawa:BAAANQADCggIDQAAAA==.',
Ox='Oxsana:BAAANQAECgUJBgAAAA==.',
Pa='Packtastic:BAABNQAECn8jAAMNAAcKoBZaswBkAQANAAUK7BdaswBkAQAOAAIKrhQ1VACBAAAAAA==.Padthang:BAAANQAECgcIEwAAAA==.Pakipot:BAAANQAECgQIBAAAAA==.Palazyn:BAAANQADCggIHQABNQAECggIIQAkACAQAA==.Pallymar:BAAANQAECgcICQABNQAFFAQIBwAnAFYWAA==.Pandorax:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Panhexual:BAAANQADCgQIBAAAAA==.Papadude:BAAANQAECggIEAAAAA==.Parketor:BAABNQAECn8WAAIFAAcK8RvKngBCAgAFAAcK8RvKngBCAgAAAA==.Pathyx:BAAANQAECgUICAAAAA==.',
Pe='Peacefulguy:BAAANQABCgQIBgAAAA==.Peachjars:BAABNQAECn8zAAMNAAkK0iPtBQCfAwANAAkK0iPtBQCfAwAOAAQKYRM7NgDnAAAAAA==.Pelvis:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.Perixi:BAAANQADCgYICgAAAA==.Perpekto:BAAANQADCgUIBQAAAA==.Peterpewpew:BAAANQAECgIIAgAAAA==.',
Ph='Phedragon:BAAANQAECgQIBQAAAA==.Phedrah:BAACNQAFFH8GAAIbAAMKWgmyGwDfAAAbAAMKWgmyGwDfAAA1AAQKfxwAAhsACQrQFJhHAFUCABsACQrQFJhHAFUCAAAA.Philipx:BAAANQADCgQIBAAAAA==.Phookie:BAAANQADCgcIBwAAAA==.',
Pi='Picklenator:BAAANQAECgUIEAAAAA==.Pierreplays:BAAANQADCgUIBQAAAA==.Pillowhands:BAAANQADCgQIBAAAAA==.Pilto:BAABNQAECn8cAAIPAAkKjBNfUAAvAgAPAAkKjBNfUAAvAgAAAA==.Pingo:BAAANQAECgUIDgAAAA==.Pinkmj:BAAANQADCgMIBgAAAA==.Pitchief:BAAANQAECgYIEwAAAA==.',
Po='Pokiplate:BAAANQADCgUIBQAAAA==.Polendina:BAABNQAECn8gAAMSAAkKlSRwHwDMAgASAAgKBiRwHwDMAgAXAAgKNCM4HwC2AgAAAA==.Pooginator:BAAANQADCgYICAAAAA==.Porcelinà:BAAANQAECgcIEwABNQAECgkJKgAEAIcZAA==.',
Pr='Prada:BAAANQAECgEIAQAAAA==.Premmish:BAAANQADCggJCAAAAA==.Primeork:BAAANQADCgUIBQAAAA==.Pritasth:BAAANQAECgEIAQAAAA==.Prodigÿ:BAAANQAECggIBwAAAA==.Prometheuss:BAAANQADCgQIBAAAAA==.',
Ps='Psammophile:BAABNQAECn8nAAIFAAkKryBuKQA+AwAFAAkKryBuKQA+AwAAAA==.Psymmer:BAAANQADCgYICAABNQAECgUIEgABAAAAAA==.Psynge:BAAANQADCgYICgABNQAECgUIEgABAAAAAA==.Psynnergy:BAAANQAECgUIEgAAAA==.Psytellar:BAAANQAECgEIAQABNQAECgUIEgABAAAAAA==.',
Pt='Ptsd:BAAANQAECgEIAQAAAA==.',
Pu='Pumprstltskn:BAAANQAECgYIDgAAAA==.Purplepally:BAAANQADCgEIAQAAAA==.Purpleshroom:BAAANQAECgMIAwABNQAECgQICAABAAAAAA==.Put:BAAANQADCgYJDwAAAA==.',
Py='Pyrat:BAAANQAECgcIEwAAAA==.Pyroangel:BAAANQAECgYIDQAAAA==.Pyrom:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Pyrotwopnto:BAAANQAECgEIAwAAAA==.',
['Pë']='Pëstilëncë:BAAANQADCggIDwAAAA==.',
['Pí']='Píneapple:BAAANQAECgIIAwAAAA==.',
Qa='Qannasa:BAAANQAECgIIAgAAAA==.',
Qe='Qertinya:BAAANQADCgYIEQAAAA==.',
Qu='Quadman:BAABNQAECn8ZAAICAAkKZSFWSgCnAgACAAkKZSFWSgCnAgAAAA==.Quaxly:BAAANQADCgQIBAAAAA==.Quinexorable:BAACNQAFFH8HAAIoAAIKbyDzBAC+AAAoAAIKbyDzBAC+AAA1AAQKfzoAAigACQoTJpQAAOYDACgACQoTJpQAAOYDAAAA.',
Qy='Qyl:BAAANQADCgMIAwAAAA==.',
Ra='Ragedaddy:BAABNQAECn8cAAICAAgK/xtXewAjAgACAAgK/xtXewAjAgAAAA==.Raglashar:BAAANQADCgQJBAAAAA==.Rahkar:BAAANQAECgYJDgAAAA==.Rainndance:BAAANQAECgcIEgAAAA==.Rainnhell:BAAANQAECgEIAQAAAA==.Raitan:BAAANQADCggIEQAAAA==.Raitazzak:BAAANQAECgQIBAAAAA==.Rallet:BAAANQADCgIIAgAAAA==.Rambojoe:BAAANQADCgEIAQAAAA==.Ramrodveazy:BAABNQAECn8gAAIHAAcKfxtpawA5AgAHAAcKfxtpawA5AgAAAA==.Ranaklos:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.Ranato:BAAANQAECgQIBAAAAA==.Rancimus:BAAANQAECgQICAAAAA==.Rangore:BAAANQADCgQIBAAAAA==.Ranocthan:BAAANQAECgUIEwAAAA==.Rarcher:BAAANQAECgUJCgAAAA==.Rasmuz:BAAANQAECgEIAQAAAA==.Rauthar:BAAANQAECgYIDwAAAA==.Rayyven:BAABNQAECn8aAAINAAkK2wvxdwD2AQANAAkK2wvxdwD2AQAAAA==.Razorken:BAAANQAECgQIBAAAAA==.Razorsharp:BAABNQAECn8oAAIXAAkKARaaIwCZAgAXAAkKARaaIwCZAgAAAA==.',
Re='Recon:BAABNQAECn8iAAMeAAgK3w4qCwCtAQAeAAgK3w4qCwCtAQAfAAQK2wJwMgB5AAAAAA==.Reedeemer:BAAANQAECgEIAQAAAA==.Reefermadnes:BAABNQAECn8wAAMCAAgKahjFcwA2AgACAAgKahjFcwA2AgAoAAgKEw8MGQCcAQAAAA==.Reelsteel:BAAANQADCgcIFgAAAA==.Relnamah:BAAANQAECgQIBgAAAA==.Reoloc:BAEANQADCgYICQABNQAECggIJgAcAIQUAA==.Retandspank:BAAANQABCgQIBAAAAA==.Revdev:BAABNQAECn9ZAAIaAAkKJR8RKwAZAwAaAAkKJR8RKwAZAwAAAA==.Revils:BAAANQAECgMIBgAAAA==.Revoke:BAAANQADCgEIAQABNQAECgQICgABAAAAAA==.Reyn:BAAANQAECgQIBAAAAA==.Rezowulf:BAABNQAECn8bAAIGAAcKnw/yggCAAQAGAAcKnw/yggCAAQAAAA==.',
Rh='Rhapsydee:BAAANQADCgUIBQAAAA==.Rhododendron:BAAANQADCggICQAAAA==.Rhoñin:BAAANQABCgEIAQAAAA==.Rhuney:BAAANQAECgcIEAAAAA==.Rhunie:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.Rhyllii:BAABNQAECn8cAAIaAAcK4xUmmwDoAQAaAAcK4xUmmwDoAQAAAA==.Rhäenyra:BAAANQADCgQIBAABNQAECgUIEAABAAAAAA==.',
Ri='Rickrmortis:BAAANQADCgIIAgAAAA==.Riftmaker:BAAANQABCgIIAgAAAA==.Rivermage:BAAANQADCggICAAAAA==.',
Ro='Roadburner:BAAANQAECggIDgAAAA==.Roccotaco:BAAANQADCgYICgAAAA==.Roloc:BAEANQAECgQIBgABNQAECggIJgAcAIQUAA==.Roloch:BAAANQAECgQIBAAAAA==.Romenhoff:BAABNQAECn8tAAMMAAkK/RWMGgBhAgAMAAkK/RWMGgBhAgAVAAgKAAt+TACtAQAAAA==.Rootbeer:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Roshambu:BAAANQAECgMIBAAAAA==.Roxinator:BAAANQAECgQICAAAAA==.Roxorath:BAAANQADCggIDAAAAA==.Roxyrocko:BAAANQADCggIDgAAAA==.',
Ru='Ruikiea:BAAANQAECgYICwABNQAECgkJOAAbAAIYAA==.Runahdan:BAAANQAECgUICQABNQAECgcIEAABAAAAAA==.',
Ry='Ryomage:BAAANQABCgcIBwAAAA==.Ryushin:BAAANQADCggICAAAAA==.',
['Rà']='Ràggà:BAABNQAECn8aAAIaAAgKQgkgzQB7AQAaAAgKQgkgzQB7AQAAAA==.',
['Rí']='Rían:BAAANQAECgYIDgAAAA==.',
Sa='Sacerdota:BAAANQADCgUICQAAAA==.Saelenei:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Saevra:BAAANQADCgMIAwAAAA==.Sairadoka:BAAANQAECgUIEgAAAA==.Samzori:BAAANQAECgcIEwAAAA==.Sanatizer:BAABNQAECn8lAAIVAAgKWBzLKwB5AgAVAAgKWBzLKwB5AgAAAA==.Sandret:BAAANQAECgYIDgAAAA==.Sarris:BAAANQAECgUIDwAAAA==.Sathriel:BAABNQAECn8lAAISAAgKsxSZQQASAgASAAgKsxSZQQASAgAAAA==.Savagebleedz:BAAANQAECgUIBQAAAA==.Savagehealz:BAAANQADCgYJBgAAAA==.Savagetotemz:BAABNQAECn8rAAIbAAkKph5IGQAvAwAbAAkKph5IGQAvAwAAAA==.',
Sc='Scalelujah:BAAANQAECgUIDgABNQAECgUIBQABAAAAAA==.Scottadin:BAABNQAECn8iAAMEAAkKDxZWOwB0AgAEAAkKDxZWOwB0AgAaAAQKFQoaPwG0AAAAAA==.',
Se='Seanasy:BAAANQABCgIIAgAAAA==.Secondenvoy:BAAANQAECgQIDQAAAA==.Seerawh:BAAANQAECgYICgAAAA==.Sehetep:BAAANQAECgEIAQAAAA==.Sellithe:BAAANQAECgIIAgAAAA==.Sephyrea:BAAANQADCgYIBgAAAA==.Serigon:BAAANQAECgQIBAAAAA==.',
Sh='Shadownd:BAACNQAFFH8PAAIPAAUKZBrBDAC5AQAPAAUKZBrBDAC5AQA1AAQKfyEAAw8ACQodITgvAKkCAA8ACApGIDgvAKkCABQAAwonHVsVANIAAAE1AAUUBQgMAB4A2BAA.Shadowsloth:BAAANQADCgYICQAAAA==.Shadymcgee:BAAANQAECgUICgAAAA==.Shaevra:BAAANQADCgQIBAABNQAFFAMIBwAIAIsWAA==.Shahli:BAAANQADCgIIAgAAAA==.Shakiro:BAABNQAECn8dAAIEAAgKAQ86eACsAQAEAAgKAQ86eACsAQAAAA==.Shaloendril:BAAANQAECgIIAQABNQAFFAQIBgAaAG8NAA==.Shalzind:BAAANQAECggIAQAAAA==.Shamchan:BAAANQAECgYIDgAAAA==.Shamergency:BAAANQADCggIGQAAAA==.Shammyrock:BAABNQAECn8aAAITAAgKPx6ADQCSAgATAAgKPx6ADQCSAgAAAA==.Shamtony:BAAANQABCgQIBgAAAA==.Sharkk:BAAANQAECgQICgAAAA==.Shasham:BAAANQAECgYIDAAAAA==.Shaylar:BAAANQAECgMJBAAAAA==.Sheisunholy:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Shiherlis:BAAANQAECgQICAAAAA==.Shmacken:BAABNQAECn8YAAMGAAgK8Bx9PgBjAgAGAAgK8Bx9PgBjAgAbAAEKAADETgEkAAAAAA==.Shockinglee:BAAANQAECgQJBQABNQAECgQICgABAAAAAA==.Shoryuken:BAAANQAECgQIBAAAAA==.Shosannaa:BAAANQAECgYIEQAAAA==.Shuriken:BAACNQAFFH8HAAIIAAIKRyAxGQCuAAAIAAIKRyAxGQCuAAA1AAQKfz0AAwgACQreJa8BANADAAgACQreJa8BANADAAcAAQoAAHVWATgAAAAA.',
Si='Siete:BAAANQADCggIFgAAAA==.Sikblitz:BAAANQAECgQICQAAAA==.Sikbubblez:BAABNQAECn8rAAIaAAkKABcQWQCIAgAaAAkKABcQWQCIAgAAAA==.Sikdemonz:BAAANQADCggICAAAAA==.Sikhealz:BAAANQAECgUIBwAAAA==.Sikshockz:BAABNQAECn8ZAAIbAAcKEBI2cgDGAQAbAAcKEBI2cgDGAQAAAA==.Silentblades:BAAANQAECgIIAgAAAA==.Sindazia:BAAANQAECgQIBwAAAA==.Sinistry:BAAANQADCgUIBgAAAA==.Siopau:BAAANQADCgQIBAAAAA==.Sip:BAAANQADCgUIBQAAAA==.Sixunder:BAAANQADCgcIBwAAAA==.',
Sk='Skrinkles:BAAANQAECgcICQAAAA==.Skullwhisper:BAAANQAECgcIEQAAAA==.',
Sl='Slaught:BAAANQAECgYIBgAAAA==.Slomar:BAAANQAECgQIBwAAAA==.Slowar:BAAANQADCggICAAAAA==.Slowpallh:BAAANQADCgYICAABNQADCggICAABAAAAAA==.Slowrog:BAAANQADCgUIAwABNQADCggICAABAAAAAA==.Slowsh:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.',
Sm='Smashlo:BAAANQAECgEIAQAAAA==.Smoggely:BAAANQAECgYICQAAAA==.Smoketotem:BAAANQAECgUIDQAAAA==.',
Sn='Sneakzalot:BAAANQAECgEIAQAAAA==.Sneevle:BAAANQAECgIIAgABNQAECggIHwAFAMcaAA==.Snowbreeze:BAAANQAECgUIDgAAAA==.Snowfláme:BAABNQAECn8mAAIaAAgKXRedfgAnAgAaAAgKXRedfgAnAgAAAA==.Snubz:BAAANQADCgYIBgAAAA==.',
So='Solarity:BAAANQABCgUIBQAAAA==.Solfyr:BAAANQADCgYIBgABNQAECggIKAAfAEoeAA==.Solie:BAAANQADCgQIBAABNQAECgYICAABAAAAAA==.Solki:BAAANQAECgEIAgAAAA==.Solrak:BAAANQAECgYIEwAAAA==.Soobatai:BAAANQADCgYIBgAAAA==.Soot:BAAANQAECgYIBwABNQAECggIEAABAAAAAA==.Soots:BAAANQAECggIEAAAAA==.Sootzy:BAAANQAECgQIBgABNQAFFAgIHgAOAI8eAA==.Sophiane:BAAANQAECgcIEwAAAA==.Soulcaller:BAAANQADCggICAAAAA==.Soulkhan:BAAANQADCgUIBQAAAA==.Soulkrusher:BAAANQAECgMIBQAAAA==.',
Sp='Spadeii:BAABNQAECn81AAISAAkK4RyXJQCmAgASAAkK4RyXJQCmAgAAAA==.Spadex:BAAANQADCggIEAABNQAECgkJNQASAOEcAA==.Spagheddy:BAAANQADCggIDQAAAA==.Spankky:BAAANQAECgQIBAAAAA==.Spellzy:BAABNQAECn8uAAIFAAgKcRDHwAABAgAFAAgKcRDHwAABAgAAAA==.Spicylatina:BAAANQADCgYIBgAAAA==.',
Sq='Squachy:BAAANQADCgYIBgABNQAFFAIIBwAPAO8RAA==.',
Ss='Sseoyoon:BAABNQAECn8UAAIMAAcKswnfPwAhAQAMAAcKswnfPwAhAQAAAA==.Ssnneezzyy:BAABNQAECn8XAAICAAcKCwuSvgB7AQACAAcKCwuSvgB7AQAAAA==.',
St='Starwnd:BAAANQAECgUIBQABNQAFFAUIDAAeANgQAA==.Steadchi:BAAANQAECgcIGgAAAQ==.Stolibear:BAABNQAECn8tAAImAAkKUCJAAwCFAwAmAAkKUCJAAwCFAwAAAA==.Stolidh:BAAANQAECgUICgABNQAECgkJLQAmAFAiAA==.Stolidk:BAAANQAECgEIAQABNQAECgkJLQAmAFAiAA==.Stolip:BAAANQAECgQIBgABNQAECgkJLQAmAFAiAA==.Stonedtothe:BAAANQAECgQIEQAAAA==.Stoneycrusty:BAABNQAECn81AAIbAAkKXRW6PQB8AgAbAAkKXRW6PQB8AgAAAA==.Straywalker:BAAANQADCgEIAQAAAA==.Strongside:BAAANQAECgQIBAAAAA==.Stublimë:BAABNQAECn8WAAIEAAYK/xbHegClAQAEAAYK/xbHegClAQAAAA==.Studdie:BAAANQADCgYICQAAAA==.',
Su='Succeeds:BAAANQAECggIDwAAAA==.Sungjinwooz:BAABNQAECn8cAAIaAAgKjAw+uQClAQAaAAgKjAw+uQClAQAAAA==.Suntitan:BAAANQADCgIIAgABNQAECggIHwAGAG0aAA==.Surrloc:BAAANQADCgYIBgAAAA==.Suuhdude:BAABNQAECn8lAAITAAgKMxnyDQCLAgATAAgKMxnyDQCLAgABNQAECgkJPAAhAAEjAA==.Suzue:BAAANQAECgEIAQAAAA==.',
Sw='Swd:BAABNQAECn8cAAIPAAgK+BgmQABnAgAPAAgK+BgmQABnAgAAAA==.Swudge:BAAANQAECgYIDwAAAA==.',
Sy='Syladeith:BAAANQAECgYIDgAAAA==.Sylandrus:BAAANQADCgYJBgAAAA==.Sylbanas:BAAANQADCgQICgABNQAECgkJHAAbAC8dAA==.Syldrunk:BAAANQADCgcIDgAAAA==.Sylvashaman:BAAANQAECgUICQAAAA==.',
Sz='Szolkarr:BAAANQAECgYIBgAAAA==.',
['Sé']='Séii:BAAANQADCgYIBgAAAA==.',
['Sÿ']='Sÿdney:BAAANQADCggICwAAAA==.',
Ta='Tabarnaka:BAAANQAECgUICwAAAA==.Tairnock:BAAANQAECgcIDgAAAA==.Takabaka:BAAANQAECgYIBgAAAA==.Tamira:BAAANQAECgEIAQAAAA==.Tankadina:BAAANQADCgEIAQAAAA==.Tanzee:BAACNQAFFH8HAAIPAAIK8gp7KwCFAAAPAAIK8gp7KwCFAAA1AAQKfzoAAw8ACQrIFJVDAFoCAA8ACQrIFJVDAFoCABAAAQoAADeCACUAAAAA.Tarmarion:BAAANQAECgYIEgABNQAECgkJKAAfAH0hAA==.Tarmesan:BAABNQAECn8oAAIfAAkKfSGwBABMAwAfAAkKfSGwBABMAwAAAA==.Tastytooth:BAABNQAECn8XAAMDAAgKiQb8TgBZAQADAAgKiQb8TgBZAQAhAAMK6QC4ZwA9AAAAAA==.Taytaytyrone:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQAECgUICQAAAA==.',
Te='Tegadin:BAAANQAECgEIAQAAAA==.Telemanus:BAAANQAECgYIBgAAAA==.Telhani:BAAANQAECgQICAAAAA==.Tesse:BAAANQAECgEIAgAAAA==.',
Th='Thadude:BAAANQAECgQICAABNQAECggIEAABAAAAAA==.Thannos:BAACNQAFFH8GAAIEAAMKxx9SEgA1AQAEAAMKxx9SEgA1AQA1AAQKfyYAAgQACQo5IxAJAH8DAAQACQo5IxAJAH8DAAAA.Thanos:BAABNQAECn8YAAIbAAkKLBuCLADJAgAbAAkKLBuCLADJAgAAAA==.Thanozul:BAABNQAECn8YAAIGAAcKUiB8NQCHAgAGAAcKUiB8NQCHAgAAAA==.Thark:BAAANQAECgcIEwAAAA==.Thatonebear:BAAANQAECggIBwAAAA==.Thawnn:BAAANQADCgQIBQAAAA==.Theberos:BAAANQADCggIDAAAAA==.Thebigd:BAAANQADCgQIBAAAAA==.Thebighoss:BAAANQAECgIIAgAAAA==.Thedùde:BAAANQAECgQIBAABNQAECggIEAABAAAAAA==.Thelgrus:BAAANQADCggIIAAAAA==.Thesharr:BAAANQAECggICAAAAA==.Thesmanmeta:BAAANQADCgUIBQAAAA==.Thoern:BAAANQAECgEIAQAAAA==.Thorane:BAAANQADCgYJBgAAAA==.Thrashcan:BAAANQAECgQIBwABNQAECgcIEwABAAAAAA==.Threem:BAAANQAECgEIAQAAAA==.Threepercent:BAABNQAECn8kAAMHAAgKDRveWABmAgAHAAgKDRveWABmAgAIAAEK9wGLmQAkAAAAAA==.Threesteps:BAAANQADCgIIAgAAAA==.Throad:BAAANQADCgcJCAAAAA==.Throatzilla:BAAANQAECgUICAAAAA==.Throwbackhlz:BAABNQAECn8eAAITAAgK1AhlGQDJAQATAAgK1AhlGQDJAQAAAA==.Throwinshåde:BAAANQAECgUJBQAAAA==.Thudmuffin:BAAANQAECgQICAABNQAECgQICgABAAAAAA==.Thundersfury:BAAANQADCgEIAQAAAA==.Thyrealest:BAAANQADCgEJAQAAAA==.Thysania:BAAANQABCgYICQABNQABCgIIAgABAAAAAA==.',
Ti='Tides:BAABNQAECn8qAAMGAAkK+xVmQQBYAgAGAAkK+xVmQQBYAgAbAAEKtQExUgEiAAAAAA==.Tilyne:BAAANQABCgIIAgAAAA==.Tinarii:BAACNQAFFH8NAAIpAAQK/SZEAgDQAQApAAQK/SZEAgDQAQA1AAQKfx8AAikACQrnJrgAANcDACkACQrnJrgAANcDAAAA.Tinyshadow:BAAANQAECgMIBQAAAA==.Tinytit:BAAANQAECgQIBAAAAA==.Tinytusk:BAAANQABCgIIAgAAAA==.Titdruid:BAAANQADCgUIBQAAAA==.Titpoosy:BAAANQADCgYICQAAAA==.Tiusele:BAAANQABCgEIAQAAAA==.Tizali:BAAANQADCgUIBQABNQAFFAMIBwAIAIsWAA==.',
To='Tonystonk:BAAANQAECgUIDwAAAA==.Toombz:BAAANQADCgYIBgAAAA==.Toreto:BAAANQADCgEIAgAAAA==.Totemkoff:BAAANQABCgMIAwAAAA==.Toureg:BAAANQAECgUICAAAAA==.',
Tr='Tragha:BAAANQADCggIEQAAAA==.Trayker:BAAANQADCgQIBAAAAA==.Traynisa:BAAANQADCgUICAAAAA==.Treykor:BAAANQADCgQIBAAAAA==.Tria:BAAANQAECgEIAwAAAA==.Trixrforkids:BAAANQAECgEIAQAAAA==.Trlight:BAAANQAECgcICQAAAA==.Trollsicle:BAAANQAECgQICgAAAA==.Trotah:BAAANQADCgYICQAAAA==.Tryzz:BAAANQAECgUICwAAAA==.',
Tu='Tubhead:BAAANQAECgQIDAAAAA==.Tumamaesmia:BAAANQAECgQICgABNQAECggIHQAEAAEPAA==.Tunare:BAAANQAECgUIDQAAAA==.Tusknflamer:BAAANQADCgUIBwAAAA==.Tuunn:BAAANQAECgEIAQAAAA==.',
Tw='Twentyrats:BAAANQAECgYIBwAAAA==.Twoman:BAAANQAECgUIBQABNQAECgkJGQACAGUhAA==.Twylla:BAAANQAECgUIBgAAAA==.',
Ty='Tynak:BAAANQADCgQIBAAAAA==.',
Ub='Ubemilktea:BAAANQADCgIIAgAAAA==.',
Ug='Ugroto:BAABNQAECn8gAAIdAAgKsAT8GgDzAAAdAAgKsAT8GgDzAAAAAA==.',
Uh='Uhrstaria:BAAANQAECggICQAAAA==.',
Ul='Uldred:BAAANQADCgUIBQABNQAFFAMIBwAIAIsWAA==.',
Un='Unclesnottyp:BAAANQAECgEIAwAAAA==.Unmortal:BAAANQAECgUJDAAAAA==.',
Ur='Urotherdaddy:BAAANQAECgEIAQAAAA==.Uruker:BAAANQADCgIIAgAAAA==.',
Us='Useurblinker:BAAANQADCgcIBwAAAA==.',
Va='Valglacius:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Valkrin:BAAANQAECgQIBAAAAA==.Valonthir:BAAANQADCggIEwAAAA==.Valstone:BAAANQAECgEIAQAAAA==.Vancleave:BAAANQAECgMJAwAAAA==.Vandreck:BAAANQAECggICAAAAA==.Vandril:BAAANQAECggIBAAAAA==.Vandrip:BAAANQAECggICAAAAA==.Vanellope:BAAANQADCggICAAAAA==.Vargruf:BAAANQAECgQIBAABNQAECggIKAAfAEoeAA==.Vasati:BAABNQAECn8ZAAIFAAkKjR2NLwAtAwAFAAkKjR2NLwAtAwABNQAFFAMIBwAIAIsWAA==.Vaylethrayne:BAAANQABCgQIBQAAAA==.',
Ve='Vend:BAAANQAECgUIBQAAAA==.Verguetta:BAAANQAECgQICgAAAA==.Verinsedai:BAABNQAECn8fAAIVAAkKOgSFYQBFAQAVAAkKOgSFYQBFAQAAAA==.Vesimer:BAAANQADCggIFQAAAA==.',
Vh='Vharka:BAAANQADCgUIBQAAAA==.',
Vi='Viber:BAAANQADCgcIBwAAAA==.Vicvondik:BAAANQADCgQIBAAAAA==.Vildri:BAAANQAECgUIEQAAAA==.Violetknight:BAAANQADCgIIAgAAAA==.',
Vo='Voidrey:BAAANQAECgMJBgABNQAECgQIBAABAAAAAA==.Voikullten:BAAANQADCgUIBQAAAA==.Vornash:BAAANQAECgQIBgAAAA==.',
Vy='Vylax:BAAANQAECgEIAQAAAA==.Vylent:BAAANQADCggIEwAAAA==.',
Wa='Waddleweaver:BAAANQADCggICAAAAA==.Wardogfour:BAAANQAECgEIAQAAAA==.Wardogsix:BAABNQAECn8ZAAIaAAkKhAupxgCIAQAaAAkKhAupxgCIAQAAAA==.Warkraz:BAAANQAECgIIAQAAAA==.Warrush:BAAANQAECgcIEwAAAA==.Watchmedps:BAAANQAECgIJAgAAAA==.',
We='Wevv:BAAANQADCgMIAwAAAA==.Weyds:BAAANQAECgUICgAAAA==.',
Wi='Wildthang:BAAANQAECgEIAQAAAA==.Willgate:BAAANQADCgMIAwAAAA==.Willhelt:BAAANQAECgUIEgAAAA==.Willpray:BAAANQAECgUIDQAAAA==.Windle:BAAANQAECgYIBwAAAA==.Windrunnér:BAABNQAECn8ZAAIHAAkKixk/JgD9AgAHAAkKixk/JgD9AgAAAA==.Winterwølf:BAAANQADCgIJAgAAAA==.',
Wo='Wobblepot:BAAANQAECggIEgAAAA==.Wontondesire:BAABNQAECn8nAAIpAAkKhw0uEgC/AQApAAkKhw0uEgC/AQAAAA==.',
Wu='Wulfdin:BAAANQAECgYICAABNQAECgcIGwAGAJ8PAA==.Wulfpriest:BAAANQAECggIBwABNQAECgcIGwAGAJ8PAA==.',
Xa='Xantry:BAEBNQAECn8mAAMjAAgKQhrBJgBbAgAjAAgKxBnBJgBbAgAXAAcKXQ9YXAB+AQAAAA==.',
Xb='Xbambs:BAAANQADCgQIBAAAAA==.',
Xe='Xerovladej:BAABNQAECn8ZAAMRAAcKoxh6KQCOAQARAAYKJhx6KQCOAQAaAAUKbAgWFwHyAAAAAA==.',
Xo='Xonares:BAAANQAECgYIBgAAAA==.Xoog:BAAANQAECgUIDQAAAA==.Xozo:BAAANQADCgIIAgAAAA==.',
Xu='Xualene:BAABNQAECn8YAAIVAAcKhBJFRwDLAQAVAAcKhBJFRwDLAQABNQAECgcIIAAHAH8bAA==.Xurk:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Xw='Xwarrior:BAABNQAECn8fAAICAAgKMxNDigD+AQACAAgKMxNDigD+AQAAAA==.',
Ya='Yaaz:BAABNQAECn8hAAMCAAgKgxz9WgB4AgACAAgKgxz9WgB4AgAoAAEKfxejQAA5AAAAAA==.Yamata:BAAANQADCgQIBAAAAA==.',
Ye='Yetistorm:BAAANQADCgMIAwAAAA==.',
Yo='Yoz:BAAANQAECgEIAQAAAA==.',
Yu='Yuee:BAAANQAECgMIAwAAAA==.Yukonicüs:BAAANQAECgYIEQABNQAFFAMIBgADALQNAA==.Yungsoo:BAAANQAECgIIBgAAAQ==.',
['Yü']='Yükonicus:BAAANQAECgYICAABNQAFFAMIBgADALQNAA==.',
Za='Zaehara:BAAANQAECgMIBAAAAA==.Zanarian:BAAANQAECgEIAgAAAA==.Zappinboi:BAAANQAECgUIBwABNQAFFAUIEQAlAKwRAA==.Zatkiel:BAAANQAECgQICQAAAA==.',
Ze='Zealot:BAAANQAECgMIBQAAAA==.Zedar:BAABNQAECn8aAAMFAAcKaRJt7ACuAQAFAAcKwBBt7ACuAQAiAAMK2xJmLQCOAAABNQAECgkJIQAaANkiAA==.Zeju:BAAANQAECgEIAgAAAA==.Zekinett:BAAANQADCgUIBQAAAA==.Zekker:BAAANQADCgcICgAAAA==.Zenolinwæ:BAAANQAECgUIEAAAAA==.Zeohavoc:BAAANQADCggICgAAAA==.',
Zh='Zhondari:BAAANQAECgEIAgAAAA==.',
Zi='Zivanya:BAAANQAECgUICgAAAA==.',
Zu='Zuljek:BAAANQABCgIIAgAAAA==.Zupaï:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Zupäi:BAAANQAECgQIBQAAAA==.Zurprise:BAAANQADCgYICAAAAA==.',
Zx='Zxz:BAAANQAECggIEgAAAA==.',
Zy='Zyrgarran:BAAANQAECgEIAQAAAA==.',
['Zá']='Záraya:BAABNQAECn8qAAMEAAkKhxkIKQDCAgAEAAkKhxkIKQDCAgAaAAEKfAbkswErAAAAAA==.',
['Zú']='Zúpái:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
['Àz']='Àzæs:BAAANQAECgUICgAAAA==.',
['Ät']='Ätreo:BAAANQAECgcIEgAAAA==.',
['Åi']='Åirå:BAAANQADCgEIAQAAAA==.',
['Æl']='Ælusive:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
['Ço']='Çondemned:BAAANQADCgQIBAABNQAECgIIAwABAAAAAA==.',
['Ém']='Émperor:BAAANQADCgUIBQABNQADCgYIEwABAAAAAA==.',
['Îc']='Îcyhot:BAAANQAECgIIAwAAAA==.',
['Ða']='Ðaunta:BAAANQADCgIIAgABNQAECggIBwABAAAAAA==.',
['Ðr']='Ðräx:BAABNQAECn8lAAQGAAgK0hqsQABbAgAGAAgK0hqsQABbAgATAAUKhwPfJwDeAAAbAAMKpA3r8wCmAAAAAA==.',
['Óh']='Óhelgur:BAAANQADCgIIAgAAAA==.',
['Öh']='Öhgr:BAAANQAECgMIBwAAAA==.',
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
