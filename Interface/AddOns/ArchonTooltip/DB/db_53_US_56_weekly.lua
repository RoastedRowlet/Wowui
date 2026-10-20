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

local lookup = {'Paladin-Holy','Hunter-BeastMastery','Warrior-Arms','Shaman-Restoration','Shaman-Elemental','Druid-Guardian','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Rogue-Subtlety','Mage-Arcane','Warlock-Destruction','Priest-Discipline','Priest-Holy','Priest-Shadow','Rogue-Assassination','DeathKnight-Blood','DeathKnight-Unholy','Mage-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Outlaw','Hunter-Survival','Paladin-Retribution','Shaman-Enhancement','Hunter-Marksmanship','Monk-Windwalker','DeathKnight-Frost','Warrior-Protection','Paladin-Protection','Druid-Feral','Druid-Balance','Druid-Restoration','Warlock-Affliction','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Fury',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aamara:BAABNQAECn8lAAIBAAcKyx3xQQBdAgABAAcKyx3xQQBdAgABNQAECggIGQACAJYfAA==.',
Ab='Aboyton:BAAANQAECgEIAgAAAA==.',
Ad='Adarksoul:BAAANQAECgEIAQAAAA==.Adhpally:BAAANQADCgIIAgABNQAFFAUIBwADAPkTAA==.Adorara:BAAANQADCgEIAQAAAA==.',
Ae='Aefarshammy:BAACNQAFFH8HAAMEAAMK6Q8MCwDMAAAEAAMK6Q8MCwDMAAAFAAEK9yaFKgB3AAA1AAQKfy4AAwUACgqPJNoWAD8DAAUACApaJNoWAD8DAAQACgpzFFtNAC4CAAAA.Aelistiah:BAAANQAECgMIAgAAAA==.Aerithorn:BAABNQAECn8cAAIGAAgKciCzCQDYAgAGAAgKciCzCQDYAgAAAA==.',
Ah='Aheck:BAAANQADCgMJAwABNQAECgkJJwACAA8YAA==.Ahleya:BAAANQAECgYIBgAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgQICgAHAAAAAA==.',
Ak='Akazza:BAAANQADCgIIAgAAAA==.Akoris:BAAANQAECgQIBQABNQAECgoKJAAIAAMSAA==.Akorys:BAABNQAECn8kAAMIAAoKAxLuCgAlAQAIAAoKAxLuCgAlAQAJAAEKAAB9NQAiAAAAAA==.',
Al='Albyno:BAACNQAFFH8OAAMKAAUKcw71CwBeAQAKAAUKcw71CwBeAQALAAEK8wYCEAA/AAA1AAQKfygAAgoACgrwHpADAM8BAAoACgrwHpADAM8BAAAA.Algebrah:BAAANQAECgMIAwAAAA==.',
Am='Amara:BAAANQADCgYIIQAAAA==.Ambitionz:BAAANQADCgEIAQAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAABNQAECn8sAAIMAAYKEAOghQB4AAAMAAYKEAOghQB4AAAAAA==.Ancksunamun:BAAANQADCggIDQAAAA==.Andromedia:BAAANQADCgYIBgABNQAECggIGQACAJYfAA==.Anicarcia:BAAANQADCgQIBAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAACNQAFFH8WAAINAAUK2R3wBQC9AQANAAUK2R3wBQC9AQA1AAQKfyAAAg0ACQrLH90FACgDAA0ACQrLH90FACgDAAAA.',
Ap='Aperture:BAAANQADCgcIEwAAAA==.',
Aq='Aquua:BAABNQAECn8sAAIFAAoKhRp4NQCiAgAFAAoKhRp4NQCiAgAAAA==.',
Ar='Araelen:BAABNQAECn8UAAIOAAgKTwUDHAFdAQAOAAgKTwUDHAFdAQAAAA==.Arcticdps:BAABNQAECn8tAAMMAAoKpha+RACEAgAMAAoKpha+RACEAgAPAAEKVxYCbgBDAAAAAA==.Ariastel:BAAANQABCgIIAgAAAA==.Ariell:BAABNQAECn8tAAQQAAoKZBOGDABwAQAQAAcKUQ6GDABwAQARAAgKWBLxOAAfAQASAAYKeRo3EQAGAQAAAA==.Ariestar:BAAANQAECgcIDQAAAA==.Ariiel:BAAANQADCggICQABNQAECgoKLQAQAGQTAA==.Arthimas:BAAANQAECgIIAgAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQAECggJBwAAAA==.Ashelash:BAABNQAECn8aAAISAAYK3wsnGADGAAASAAYK3wsnGADGAAAAAA==.Asidize:BAAANQAECgUICgAAAA==.Aslor:BAABNQAECn8hAAIMAAgK4hmiZgAnAgAMAAgK4hmiZgAnAgAAAA==.Aspenoa:BAAANQADCggICAAAAA==.Asralia:BAAANQADCgYIDwAAAA==.',
At='Athalia:BAACNQAFFH8HAAITAAIKqRjWBAChAAATAAIKqRjWBAChAAA1AAQKfzQAAxMACgqTIjoFAIADABMACQqjIzoFAIADAA0AAQoiG3dDAFQAAAAA.Atlaswolfe:BAAANQAECgcIBwAAAA==.',
Au='Audi:BAAANQADCgQIDAAAAA==.Aug:BAAANQAECgcIDgAAAA==.',
Av='Avaldra:BAAANQABCgEIAQAAAA==.Avex:BAABNQAECn8nAAICAAkKDxibXgBaAgACAAkKDxibXgBaAgAAAA==.',
Ax='Axemage:BAABNQAECn8yAAIOAAoKKRV+OABMAQAOAAoKKRV+OABMAQAAAA==.Axeom:BAABNQAECn82AAIEAAoK6hpyJwDGAgAEAAoK6hpyJwDGAgAAAA==.Axeshammy:BAAANQAECgMIAwABNQAECgoKMgAOACkVAA==.',
Az='Azmodan:BAAANQAECgEIAQAAAA==.Azzith:BAABNQAECn8VAAIOAAkKoRokowA7AgAOAAkKoRokowA7AgAAAA==.',
Ba='Bahgeye:BAAANQADCgUIBQAAAA==.Bajaladin:BAAANQAECggIEQAAAA==.Baldie:BAAANQAECgEIAQAAAA==.Bamboolan:BAAANQAECgIIAgAAAA==.Barcliah:BAAANQADCgIIAgAAAA==.Barometer:BAAANQAECgcIDQAAAA==.Bast:BAAANQAECgEIAQABNQAECggIDwAHAAAAAA==.Baxa:BAAANQAECggICAAAAA==.Baylee:BAABNQAECn8kAAIOAAgKiQSCeADNAAAOAAgKiQSCeADNAAAAAA==.',
Bb='Bbartemis:BAABNQAECn8bAAINAAcKFAM0OwBrAAANAAcKFAM0OwBrAAAAAA==.',
Bc='Bchamp:BAAANQADCgQIBAAAAA==.',
Be='Bearaqobama:BAAANQADCgYIBgAAAA==.Bearlyalivee:BAAANQAECgQIBAABNQAECgYIBwAHAAAAAA==.Bearvul:BAAANQABCgEIAQAAAA==.Beekerr:BAAANQADCgMIBAABNQAECgoKJgATAHUbAA==.Begonemist:BAAANQADCgEIAQAAAA==.Belbroon:BAAANQADCgQIBAAAAA==.Beliele:BAAANQAECgUIBgAAAA==.Belzenlok:BAAANQAECgIIAQAAAA==.Benjohnbo:BAAANQABCgEIAQAAAA==.Benwins:BAAANQAECgYIDQAAAA==.Bergamö:BAAANQADCgcIFAABNQAECgMIBgAHAAAAAA==.Bernecessity:BAAANQAECgYIDAAAAA==.',
Bh='Bho:BAAANQADCgUICgAAAA==.',
Bi='Biffedit:BAAANQADCgcICgAAAA==.Bigangus:BAAANQAECgIIBQAAAA==.Bigdj:BAAANQAECgEIAQAAAA==.Bigmerch:BAAANQADCgcIDgAAAA==.Bis:BAAANQADCgEJAgAAAA==.Biscuitbabe:BAABNQAECn8TAAIOAAcKXQL4XwHzAAAOAAcKXQL4XwHzAAAAAA==.Bisholoyd:BAABNQAECn8VAAIPAAcK1gmjHwByAQAPAAcK1gmjHwByAQAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blakely:BAAANQADCgQIAwAAAA==.Blastoise:BAABNQAECn80AAMUAAoK3COhBACnAwAUAAoKmSOhBACnAwAVAAcKuRi3OwAyAgAAAA==.Blinktwice:BAAANQAECgEIAQAAAA==.Blizfishleg:BAABNQAECn8WAAIWAAYKFg+1FABfAQAWAAYKFg+1FABfAQAAAA==.Bllur:BAAANQADCgIIAgAAAA==.Bloodroots:BAAANQAECgMIBwAAAA==.Bloodybren:BAAANQAECgQIBAAAAA==.Bluur:BAAANQADCgYIBgAAAA==.',
Bo='Bonehacker:BAAANQABCgYICAAAAA==.Bongwater:BAAANQADCgEIAQABNQAECgoKKgAXALMeAA==.Bonkyo:BAAANQADCgYIBgAAAA==.Boombóx:BAAANQAECgUICAABNQAECgoKNgAMACcjAA==.Boostia:BAAANQADCgEIAQAAAA==.Borthos:BAABNQAECn8oAAIYAAoKsB/9EgDTAgAYAAoKsB/9EgDTAgAAAA==.Bowsback:BAAANQADCggIKAAAAA==.Bowyohead:BAABNQAECn8gAAIRAAoKlhxLBQCwAgARAAoKlhxLBQCwAgAAAA==.',
Br='Bracydaboss:BAAANQAECgEIAgAAAA==.Bradroybboi:BAAANQAECgQICgAAAA==.Braingap:BAAANQAECgYICgABNQAECggIDAAHAAAAAA==.Brandoe:BAAANQAECgQIBgAAAA==.Breece:BAAANQAECgQIBAAAAA==.Brickinkeys:BAAANQAECgEIAgABNQAECggIGQACAJYfAA==.Brightmare:BAAANQADCgYIDwAAAA==.Brusa:BAAANQADCgEJAQAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAABNQAECn8hAAIZAAcKBQehDgBLAQAZAAcKBQehDgBLAQAAAA==.',
Ca='Caadra:BAAANQADCgIIAgAAAA==.Caenarigos:BAAANQAECgIIAQAAAA==.Caenarius:BAAANQADCgMIAwABNQAECgIIAQAHAAAAAA==.Caimie:BAAANQAECgQIBgAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQAECgQICQAAAA==.Capnmorgan:BAAANQABCgEIAQAAAA==.Cassiaan:BAAANQAECgMIAwAAAA==.Caylavibes:BAABNQAECn8iAAIRAAoKEBD0VAAkAgARAAoKEBD0VAAkAgAAAA==.',
Ch='Chaviel:BAAANQAECggICgAAAA==.Cheetasista:BAAANQADCggIDgAAAA==.Cherry:BAAANQAECggIEgAAAA==.Chironn:BAABNQAECn8vAAIaAAoK1RcYAQDqAQAaAAoK1RcYAQDqAQAAAA==.Chudlord:BAAANQADCggICwAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQAECgMIAwAAAA==.',
Ci='Cinderburn:BAAANQAECgQICgAAAA==.Cinderkai:BAAANQAECgEIAgAAAA==.',
Cl='Clayshaper:BAAANQADCgYIDAAAAA==.Clohhe:BAAANQAECgQIBQAAAA==.Clohordyo:BAAANQAECgQIBAAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQAECgEIAQAAAA==.Comfychair:BAABNQAECn8dAAIbAAkKeh+VDgAIAgAbAAkKeh+VDgAIAgAAAA==.Coowmoo:BAABNQAECn8UAAIcAAcKrhJrHQCLAQAcAAcKrhJrHQCLAQAAAA==.Cosmochopper:BAAANQAECgEIAQABNQAFFAUICQAdAI0WAA==.Cosmonodder:BAAANQAECggIDwABNQAFFAUICQAdAI0WAA==.Cosmoshotter:BAACNQAFFH8JAAMdAAUKjRbeFADyAAAdAAQKjRbeFADyAAACAAIKAAD6NwBLAAA1AAQKfx0AAx0ACgqGF6UbAHYCAB0ACgqGF6UbAHYCAAIAAQrvIbw/AWMAAAAA.',
Cr='Craterstab:BAAANQADCgEIAQAAAA==.Cremebrule:BAAANQAECgEIAQAAAA==.Critnyspears:BAAANQAECgIIBwAAAA==.Crushleaf:BAAANQADCggICwAAAA==.',
Cu='Cuchulainn:BAAANQADCgMIAwAAAA==.Cucubau:BAAANQADCggIEwAAAA==.',
Cy='Cyndra:BAABNQAECn8VAAIOAAkKQgmnSAAqAQAOAAkKQgmnSAAqAQAAAA==.',
Da='Dakai:BAAANQADCgIIAgAAAA==.Dallthyrian:BAAANQADCgYIBgABNQAECgUICAAHAAAAAA==.Dalthyrian:BAAANQAECgYIDgABNQAECgUICAAHAAAAAA==.Dalthyriian:BAAANQAECgUICAAAAA==.Dalthyrrian:BAAANQAECgEIAQABNQAECgUICAAHAAAAAA==.Dalthyyrian:BAAANQAECgcIDQABNQAECgUICAAHAAAAAA==.Damii:BAAANQADCgUIDAAAAA==.Danarand:BAAANQADCgMIAwABNQAECgcIHQAGAPcSAA==.Danfarm:BAAANQADCgEIAQAAAA==.Dargonbref:BAAANQADCgUIAQABNQAECgkJFAAFAJsOAA==.Darjen:BAAANQAECgUIDwAAAA==.Darkjestêr:BAAANQADCgUIBQAAAA==.Darkshock:BAAANQADCgQIBgAAAA==.Darksky:BAAANQAECgMICQAAAA==.Darthra:BAAANQAECgEIAQAAAA==.Daysfox:BAABNQAECn8tAAMdAAkKVgzhBAClAQAdAAkKVgzhBAClAQACAAEKugwBTwFDAAAAAA==.Daysmonk:BAABNQAECn8eAAIeAAgKAgz8BwCPAQAeAAgKAgz8BwCPAQAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deadenside:BAAANQADCggIDQAAAA==.Deadmountain:BAAANQADCgIIBAAAAA==.Deadxpool:BAAANQAECgEIAQAAAA==.Deahtlyx:BAAANQADCgQIBAABNQAECgoKNAATAB8dAA==.Deathfang:BAAANQADCgUICgAAAA==.Deathlyy:BAABNQAECn80AAMTAAoKHx39BgCqAQATAAkKHx39BgCqAQANAAQKWAhnOgDkAAAAAA==.Deathmatch:BAAANQAECgIIAwAAAA==.Deathsdawn:BAAANQAECgEIAQABNQAECgoKOwAYAN4aAA==.Deathstone:BAABNQAECn8fAAMfAAgK0RniFwBPAQAfAAgK0RniFwBPAQAVAAMKcA1mqwCeAAABNQAFFAUIEAAbACAZAA==.Deathtress:BAABNQAECn8bAAQfAAkKwhHHMgAVAgAfAAkKwhHHMgAVAgAVAAEKNAN69QAiAAAUAAEKAAAP3QAhAAAAAA==.Debbydowner:BAABNQAECn8iAAIDAAkKAAkrwgB3AQADAAkKAAkrwgB3AQAAAA==.Decado:BAAANQAECggIDwAAAA==.Deemwins:BAAANQAECgUIBQAAAA==.Deezenuts:BAAANQAFFAEIAQAAAA==.Degen:BAAANQAECgQIDwAAAA==.Dejevoid:BAABNQAECn8VAAIYAAoK6wYJHQDGAAAYAAoK6wYJHQDGAAAAAA==.Delidyr:BAAANQAECgIIAwAAAA==.Deliquium:BAAANQABCggICgAAAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEBNQAECn8pAAMgAAgKaxk0DgBMAgAgAAgKaxk0DgBMAgADAAMKuAh9JgGLAAAAAA==.Denwere:BAAANQADCgUICAAAAA==.Dethmoora:BAAANQADCgYIBgAAAA==.Deww:BAABNQAECn8hAAMQAAoK3Br+BABpAgAQAAgKQxj+BABpAgARAAkKhxfpNAAsAQAAAA==.',
Dh='Dhawk:BAAANQADCggIFAAAAA==.Dhelilha:BAABNQAECn8lAAIhAAkKmQrrEQD+AAAhAAkKmQrrEQD+AAAAAA==.',
Di='Diablesse:BAAANQAECgUIBQAAAA==.Distance:BAAANQADCgIIAgAAAA==.',
Dk='Dkalliru:BAABNQAECn8qAAIUAAoKXCAJFAAMAwAUAAoKXCAJFAAMAwAAAA==.',
Do='Docdolittle:BAABNQAECn9BAAMCAAoKmCR3AgDWAgACAAoKmCR3AgDWAgAdAAEKdBHKggA9AAAAAA==.Docfreez:BAABNQAECn82AAMWAAoK+iPEBwBwAgAWAAgKjCLEBwBwAgAOAAkK7SHiHQCZAQAAAA==.Docragosa:BAAANQAECgMIBAABNQAECggIEAAHAAAAAA==.Doctermoo:BAAANQAECgcICwAAAA==.Dogar:BAAANQAECgEIAQAAAA==.Doomhamer:BAAANQADCggICAABNQAECgoKKAAYALAfAA==.Doraemee:BAAANQAECgUICAAAAA==.',
Dr='Drbaconbrgr:BAABNQAECn8cAAIRAAcKWRzYVwAbAgARAAcKWRzYVwAbAgABNQAECgoKLAACALUjAA==.Drbakedziti:BAAANQADCggIDgABNQAECgoKLAACALUjAA==.Drbaobuns:BAAANQAECgYICwABNQAECgoKLAACALUjAA==.Drcarrotcake:BAAANQAECgUICgABNQAECgoKLAACALUjAA==.Drcheeseball:BAAANQAECgYIDgABNQAECgoKLAACALUjAA==.Dreggsalad:BAAANQAECgUIDwABNQAECgoKLAACALUjAA==.Dreim:BAEANQAECgYIBgABNQAECgoKQgAbAMAiAA==.Dreima:BAAANQAECgQIBAAAAA==.Dreist:BAAANQADCgIIAgAAAA==.Drfriedrice:BAAANQADCgEJAQABNQAECgoKLAACALUjAA==.Drgatorwine:BAABNQAECn8UAAIhAAcKWBv2HgDvAQAhAAcKWBv2HgDvAQABNQAECgoKLAACALUjAA==.Drhashbrowns:BAAANQAECgQIBgABNQAECgoKLAACALUjAA==.Drkimchirice:BAABNQAECn8kAAIiAAoKmyP0AQCkAwAiAAoKmyP0AQCkAwABNQAECgoKLAACALUjAA==.Drmacncheese:BAABNQAECn8iAAIPAAgKPh7WAADOAQAPAAgKPh7WAADOAQABNQAECgoKLAACALUjAA==.Drpumpkinpie:BAABNQAECn8aAAIbAAkK4xn2WwCEAgAbAAkK4xn2WwCEAgABNQAECgoKLAACALUjAA==.Drshephardpi:BAAANQADCggICgABNQAECgoKLAACALUjAA==.Drshortbread:BAAANQAECgYIDQABNQAECgoKLAACALUjAA==.Druiddres:BAAANQAECgUIBAAAAA==.Drwontonsoup:BAABNQAECn8sAAICAAoKtSPoBwCeAwACAAoKtSPoBwCeAwAAAA==.',
Du='Dummythicc:BAAANQADCgYICAAAAA==.Dumpstur:BAAANQAECgMIAwAAAA==.',
['Dö']='Dööku:BAAANQADCgYIBgAAAA==.',
Ei='Eighteen:BAABNQAECn8vAAINAAkKcSBiBgAbAwANAAkKcSBiBgAbAwAAAA==.',
Ek='Eksi:BAABNQAECn8YAAIeAAgKhxS+LwCZAQAeAAgKhxS+LwCZAQAAAA==.',
El='Elethe:BAAANQAECgIIAgABNQAFFAUIFgANANkdAA==.Elianx:BAAANQAECggIAQAAAA==.Ellebush:BAAANQADCgQIBgAAAA==.Elyrinna:BAAANQABCgQIBQAAAA==.Elzaine:BAAANQAECgMIBAAAAA==.',
Em='Embedded:BAABNQAECn8UAAMFAAkKmw4rdADFAQAFAAgKfBArdADFAQAcAAEKWAO+IQA0AAAAAA==.Eme:BAAANQAECgUIBwAAAA==.Empress:BAABNQAECn8aAAIfAAgKVQuXTwB2AQAfAAgKVQuXTwB2AQAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQAECggIDAAAAA==.Enhanceme:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Enriq:BAAANQAECgEIAQABNQAECgQICQAHAAAAAA==.Entrophi:BAAANQADCgMIAwAAAA==.',
Er='Erikaa:BAAANQAECgcIDgAAAA==.Erisnyx:BAAANQADCgIIAgAAAA==.',
Es='Escoez:BAAANQADCgUIBQABNQAECgEIAQAHAAAAAA==.Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAQABNQAECggIDAAHAAAAAA==.',
Ex='Excruciator:BAABNQAECn8nAAMjAAgK+hLwRwDLAQAjAAgK+hLwRwDLAQAkAAIKtAfIZgBqAAAAAA==.Exhumedraven:BAAANQAECgYICgAAAA==.',
Fa='Falloutz:BAAANQAECgUIDQAAAA==.Falloutzhunt:BAAANQADCgYIBgABNQAECgUIDQAHAAAAAA==.Fantarada:BAAANQADCgYIBgAAAA==.Farahcanle:BAABNQAECn88AAIGAAoKPxEJBwCRAQAGAAoKPxEJBwCRAQAAAA==.Farrock:BAABNQAECn8fAAIGAAgKsgprFgDQAAAGAAgKsgprFgDQAAAAAA==.Fawxette:BAAANQADCggICAABNQAECgoKSAAYAHMbAA==.',
Fe='Felanish:BAAANQAECgEIAQAAAA==.Felystia:BAAANQAECgYIEQAAAA==.Fenra:BAAANQADCgcIDwAAAA==.Feorblarir:BAAANQAECgcIEAAAAA==.Fernmister:BAAANQAECgIIAwAAAA==.',
Fi='Filledegel:BAAANQAECgQICQABNQAECgcICQAHAAAAAA==.Finowscath:BAAANQAECgMIAwAAAA==.Firequencher:BAABNQAECn8ZAAIjAAkKbxkxNABGAgAjAAkKbxkxNABGAgAAAA==.Fistacuffs:BAAANQAECgEIAQAAAA==.Fistdoc:BAAANQAECggIEAAAAA==.Fistícuffs:BAAANQADCggIGgAAAA==.Fizzroll:BAAANQADCggIGwAAAA==.Fié:BAAANQADCggIIgABNQAECgoKSAAYAHMbAA==.',
Fl='Flais:BAAANQAECgIIAwAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAABNQAECn9AAAIXAAoKohJkBgDpAQAXAAoKohJkBgDpAQABNQAECgoKSAAYAHMbAA==.Foxknight:BAAANQADCgQIBAABNQAECgoKSAAYAHMbAA==.Foxybag:BAAANQADCggICAAAAA==.Foxytotes:BAAANQADCgUICgABNQAECgcIHQAGAPcSAA==.',
Fr='Frederick:BAAANQAECggIBgAAAA==.Fredo:BAAANQADCgIIAgAAAA==.Friendlypal:BAABNQAECn8iAAIBAAgKER84KQDDAgABAAgKER84KQDDAgAAAA==.Friendofbear:BAACNQAFFH8JAAICAAMKvgznCQDHAAACAAMKvgznCQDHAAA1AAQKfy0AAgIACgpuGM44AMACAAIACgpuGM44AMACAAAA.Fromabove:BAAANQADCgYICQAAAA==.',
Fu='Furryfeet:BAAANQAECgYIDAAAAA==.Fuzywuzzy:BAABNQAECn8VAAMGAAkKcyBrBgAqAwAGAAkKcyBrBgAqAwAiAAQK6A0gKQDGAAAAAA==.Fuzzycoochy:BAAANQADCgQIBAAAAA==.Fuzzykuntz:BAABNQAECn8gAAIVAAgKvAnHGgAQAQAVAAgKvAnHGgAQAQAAAA==.Fuzzypus:BAAANQADCgYIBgAAAA==.',
Fw='Fwoom:BAAANQADCgUIBQAAAA==.',
Fy='Fynsdood:BAABNQAECn8dAAIGAAcK9xKgIgCCAQAGAAcK9xKgIgCCAQAAAA==.Fynslane:BAAANQADCgQIBAABNQAECgcIHQAGAPcSAA==.',
Ga='Gabelock:BAACNQAFFH8cAAQMAAcK0hVpAgBzAQAMAAYKcxhpAgBzAQAPAAEKUgvgCQBQAAAlAAEKAADnEgA8AAA1AAQKfzAABAwACgoTIiklAO8CAAwACQorIiklAO8CAA8ABAouGY4wAAYBACUAAQoAALUtADsAAAAA.Gabemage:BAABNQAECn8ZAAIOAAkKkhGfswAcAgAOAAkKkhGfswAcAgAAAA==.Gala:BAAANQAECgYIBwAAAA==.Gasback:BAAANQADCgYICwAAAA==.',
Gh='Gherkins:BAAANQADCgYICgAAAA==.Ghostreveri:BAABNQAECn8bAAIbAAoK8Q+QmgDuAQAbAAoK8Q+QmgDuAQAAAA==.',
Gi='Gigah:BAABNQAECn8VAAINAAoKww54FwAjAgANAAoKww54FwAjAgAAAA==.Gingerbell:BAAANQABCggICgAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQAECgYICwAAAA==.Glutebruiser:BAAANQAECgEIBAABNQAECgkJIAAMAB4kAA==.',
Gn='Gnomedguerre:BAAANQADCgYIDQAAAA==.',
Go='Gooseshift:BAAANQAECgEIAQAAAA==.Gouchh:BAAANQAECgEIAQAAAA==.',
Gr='Gravithel:BAAANQADCggIEQAAAA==.Graybøw:BAAANQADCggIDwAAAA==.Grayseer:BAABNQAECn8XAAIIAAgKVyJuCwDNAgAIAAgKVyJuCwDNAgAAAA==.Grimspark:BAAANQABCgUIBQAAAA==.Grimtree:BAABNQAECn8qAAMlAAgKLRX+BwAVAgAlAAgKLRX+BwAVAgAMAAQKoQlhbwCkAAAAAA==.Grindor:BAAANQADCggIDAAAAA==.Grommel:BAAANQADCgYICAAAAA==.Grumblecane:BAAANQADCgIIAgAAAA==.Grumpstraza:BAAANQAECgYICwAAAA==.Grumpydemon:BAABNQAECn8wAAIYAAoKAhjBGgCCAgAYAAoKAhjBGgCCAgAAAA==.Grymshot:BAAANQAECgQIBgAAAA==.',
Gu='Guglugauthu:BAAANQADCgcICgAAAA==.',
Gw='Gwong:BAAANQADCgcIBwAAAA==.',
Ha='Haldril:BAEANQAECgUIBwABNQAECgoKQgAbAMAiAA==.Halfskul:BAABNQAECn8YAAIVAAgK2guCZgB3AQAVAAgK2guCZgB3AQAAAA==.Halotic:BAAANQAECgMIBAAAAA==.Hashah:BAABNQAECn8aAAISAAcKRyCtGwBqAgASAAcKRyCtGwBqAgAAAA==.Hatefel:BAAANQAECgUIBQABNQAECgcIGwAPAIIkAA==.Havoke:BAAANQADCggIFQAAAA==.',
He='Healsgobrr:BAAANQADCgYICwABNQAECgoKMQAmAHUWAA==.Healyaass:BAAANQADCggIIgAAAA==.Hecate:BAAANQADCgIIAgAAAA==.Helenfeller:BAAANQADCgEIBAAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgcIGgASAEcgAA==.Hexfu:BAAANQADCgMIAwAAAA==.Hexlexxia:BAAANQADCggIDwABNQAECggIGQACAJYfAA==.Heyyboyy:BAABNQAECn85AAMCAAoKsSHcCgCGAwACAAoKsSHcCgCGAwAdAAMKXApqHACvAAAAAA==.',
Ho='Holyaefar:BAAANQAFFAIIAwABNQAFFAMIBwAEAOkPAA==.Holymolydin:BAAANQADCggIBgAAAA==.Holysab:BAAANQAECgcIEgAAAA==.Holysock:BAAANQAECgUICAAAAA==.Holyyaii:BAABNQAECn8aAAMRAAkKYRipSwBCAgARAAkKYRipSwBCAgASAAEK7ALsgwAlAAAAAA==.Holz:BAAANQAECgMIBgAAAA==.Horsetowater:BAAANQAECgUICgABNQAECgoKIAARAJYcAA==.Hotsfordays:BAAANQAECgcIBgAAAA==.',
Hu='Hugoman:BAAANQAECgQIBgABNQAECgkJJwAVAC4UAA==.Huni:BAABNQAECn8cAAIEAAkKsx5ZKADCAgAEAAkKsx5ZKADCAgAAAA==.Hunterj:BAAANQADCggICwAAAA==.Huupa:BAAANQADCgYIBgAAAA==.',
Hy='Hydealyn:BAAANQAECggIEwAAAA==.Hystaric:BAAANQADCgYIDAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ia='Iamyu:BAAANQAECgQIBAABNQAECggICwAHAAAAAA==.',
Ib='Ibun:BAAANQAECgcIDgAAAA==.',
Ic='Iceblow:BAAANQADCgcIBwAAAA==.Icentheveins:BAABNQAECn8oAAIBAAkKYBgCLgCuAgABAAkKYBgCLgCuAgABNQAECgoKIAARAJYcAA==.',
Ig='Igneus:BAACNQAFFH8TAAIOAAUKcyIDEgDnAQAOAAUKcyIDEgDnAQA1AAQKfywAAg4ACgqwI9oYAHEDAA4ACgqwI9oYAHEDAAAA.Igriz:BAAANQADCggIMAAAAA==.',
Ii='Iillil:BAACNQAFFH8HAAIYAAMKdATNDgCxAAAYAAMKdATNDgCxAAA1AAQKfyMAAhgACgpICywsAOABABgACgpICywsAOABAAAA.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Imakeuflased:BAAANQADCgIIAgAAAA==.Immamoonchix:BAAANQADCgUICwAAAA==.Imthatguy:BAAANQAECgIIAgAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
In='Inkyraven:BAAANQADCgMIBQAAAA==.Insidedoubt:BAAANQAECggIDwAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.Ironorchid:BAAANQADCgUIBQAAAA==.',
It='Itsjeff:BAAANQAECgYIDgAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jaeyk:BAAANQAECggICwAAAA==.Jambonjay:BAABNQAECn8gAAIDAAcKuwl+zgBXAQADAAcKuwl+zgBXAQABNQAECggIJQACAJ0RAA==.Jananda:BAABNQAECn8eAAMkAAYKTgEVOABRAAAkAAYKTgEVOABRAAAjAAYK5QAHqABIAAAAAA==.Jarnirdimli:BAAANQABCgYIDAAAAA==.Jaywaz:BAAANQAECgUIBQAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgABNQAECgoKFAAjACkaAA==.Jckjckjck:BAAANQADCgUIBQABNQAECgoKFAAjACkaAA==.Jckjckjckjck:BAABNQAECn8UAAQjAAoKKRpcIwC1AgAjAAgKDB5cIwC1AgAkAAkKShyIHwAwAgAGAAEKAABJUgBaAAAAAA==.',
Je='Jearn:BAAANQADCgEIAQAAAA==.Jermagedupri:BAACNQAFFH8PAAIOAAUKTRUkIACFAQAOAAUKTRUkIACFAQA1AAQKfzEAAg4ACQqzIcI4ABYDAA4ACQqzIcI4ABYDAAAA.Jessupy:BAABNQAECn8pAAIXAAkKKBl8BQADAgAXAAkKKBl8BQADAgAAAA==.Jezashi:BAAANQADCgUIBQAAAA==.Jezina:BAAANQADCgYIBgAAAA==.Jezliu:BAAANQADCgYIBgAAAA==.',
Jh='Jhene:BAAANQAECgYICwABNQAECggICgAHAAAAAA==.',
Jo='Jofroztok:BAAANQADCgEIAQAAAA==.Johkneesinz:BAAANQADCgYICwAAAA==.Johntapper:BAAANQADCgQIBgAAAA==.Joshuå:BAAANQAECgcIDQAAAA==.',
Ju='Julieteshade:BAAANQADCgMJBAAAAA==.Junkbot:BAAANQADCgYIEAAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
['Jø']='Jøsh:BAAANQADCgQIBQAAAA==.',
Ka='Kaimingxiona:BAABNQAECn8UAAIMAAcKCA86mQCoAQAMAAcKCA86mQCoAQAAAA==.Kaiysz:BAAANQAECgIIAgAAAA==.Kalkulus:BAAANQADCgYIBgAAAA==.Kalrendion:BAAANQAECgEIAQABNQAECggIFQAVALcRAA==.Kalru:BAAANQAECgMIAwAAAA==.Kalzok:BAEANQAECgQIBQABNQAECgoKQgAbAMAiAA==.Karaillyonna:BAAANQAECgcICQAAAA==.Karasu:BAAANQAECgQICwAAAA==.Karliechirky:BAAANQADCgYIBgAAAA==.Kasher:BAAANQAECgUIDQAAAA==.Kayho:BAAANQAECgUJBwAAAA==.',
Ke='Kelltrax:BAAANQAECgMIBAAAAA==.Kelsier:BAABNQAECn8tAAMIAAoK+SOMBABdAwAIAAoK+SOMBABdAwAeAAUKuASgUgCnAAAAAA==.Kelzorn:BAAANQADCgEIAQAAAA==.Keruilin:BAAANQADCgQIAgAAAA==.Kesk:BAAANQADCgUICAAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khela:BAAANQAECgIIAgAAAA==.Khendra:BAAANQAECgUIBQAAAA==.',
Ki='Kiezo:BAAANQAECgQICQAAAA==.Killachefd:BAABNQAECn8bAAIVAAgKpAyFYACNAQAVAAgKpAyFYACNAQAAAA==.Killamanjoro:BAABNQAECn8cAAIDAAgKxBlnfAAkAgADAAgKxBlnfAAkAgAAAA==.Kimchiwar:BAAANQAECgYIDQAAAA==.Kirasha:BAAANQAECgIIAwAAAA==.Kitak:BAABNQAECn8VAAMVAAgKtxHSZgB1AQAVAAcKKw/SZgB1AQAUAAYKSxBcZQBdAQAAAA==.Kitchenbound:BAABNQAECn8VAAIGAAgKHRegFgAAAgAGAAgKHRegFgAAAgAAAA==.Kittychan:BAABNQAECn8nAAIVAAkKLhRFPAAvAgAVAAkKLhRFPAAvAgAAAA==.',
Kl='Klaacus:BAABNQAECn87AAQYAAoK3hqpCwAkAwAYAAoK3hqpCwAkAwAnAAMK+wgbFQBLAAAXAAEKnhH6jgA9AAAAAA==.Kloex:BAAANQABCgIIAgAAAA==.',
Kn='Knosk:BAAANQAECgUICwAAAA==.',
Ko='Kodomo:BAAANQADCgYIBgAAAA==.Kokk:BAAANQAECgMIAwAAAA==.Koudelka:BAAANQAECgQJBAAAAA==.',
Kr='Kralok:BAAANQADCgYICwAAAA==.Krazm:BAABNQAECn8XAAICAAoKXh5OKAD3AgACAAoKXh5OKAD3AgAAAA==.Kreleril:BAAANQADCgEIAQAAAA==.Kriticál:BAABNQAECn8fAAMSAAkKpQ7eJQAAAgASAAkKpQ7eJQAAAgAQAAEKXxJFKAA1AAAAAA==.Krustyg:BAAANQADCgcIDAAAAA==.Krustym:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEBNQAECn8eAAIcAAoK5CAbBQA8AwAcAAoK5CAbBQA8AwABNQAECgoKQgAbAMAiAA==.',
La='Lakshmi:BAABNQAECn8ZAAICAAgKlh+9PwCrAgACAAgKlh+9PwCrAgAAAA==.Laradin:BAAANQADCgEIAQAAAA==.Larasimus:BAAANQADCgMIAwAAAA==.Larndorn:BAAANQAECgYIBgAAAA==.Lavagrip:BAABNQAECn8cAAMbAAUKdBP4hQDDAAAbAAUKdBP4hQDDAAAhAAEKAACwcAAvAAAAAA==.Laylea:BAAANQADCgIIAgAAAA==.',
Le='Lelou:BAACNQAFFH8PAAMCAAUKECRmBQD+AQACAAUKECRmBQD+AQAdAAIK1BmcDABRAAA1AAQKf0MAAwIACgqBJo0EAMIDAAIACgqBJo0EAMIDAB0ABwrZI68TAMMCAAAA.Letmehealu:BAABNQAECn8ZAAIRAAgK6g0WQwD+AAARAAgK6g0WQwD+AAAAAA==.Lewsky:BAAANQAECgMIBgABNQAFFAMIBQAbAN4LAA==.',
Li='Lichtghost:BAAANQADCggIDAAAAA==.Lightningzap:BAAANQADCgMIAwAAAA==.Lilathiaa:BAAANQADCgYIFwAAAA==.Lilru:BAAANQAECgEIAQAAAA==.Linddria:BAABNQAECn8wAAITAAkKtBb0EAA9AQATAAkKtBb0EAA9AQAAAA==.Liondori:BAAANQADCgYIBgAAAA==.Lipspire:BAAANQABCggICAAAAA==.Lissarael:BAAANQAECggIEAAAAA==.',
Lm='Lmj:BAAANQAECgIIBgAAAA==.',
Lo='Lockbox:BAABNQAECn82AAMMAAoKJyO2AQD1AgAMAAoKJyO2AQD1AgAPAAMKFSGnLwALAQAAAA==.Lokmar:BAAANQAECgYICgAAAA==.Loomin:BAABNQAECn89AAMOAAoKhyCsEgDRAQAOAAoK9B2sEgDRAQAWAAUK0hA6HQAEAQAAAA==.',
Lu='Lucatia:BAABNQAECn8qAAIYAAoKrBu7DgAAAwAYAAoKrBu7DgAAAwAAAA==.Luciaa:BAAANQADCgQIAgAAAA==.Lumièrevide:BAAANQADCgIIAgABNQAECgcICQAHAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgUICQAAAA==.',
['Lä']='Lädyæk:BAABNQAECn8dAAICAAkKIg1uhQAAAgACAAkKIg1uhQAAAgAAAA==.',
Ma='Madboy:BAAANQAECgEIAQAAAA==.Maekyss:BAAANQAECgcIEgAAAA==.Magezu:BAAANQAECgYIDgAAAA==.Maggarak:BAAANQAECgYIEgAAAA==.Magimagi:BAAANQAECgMIAgAAAA==.Magixstraza:BAABNQAECn8vAAIOAAoKbRjcIwCFAQAOAAoKbRjcIwCFAQAAAA==.Magwilddued:BAAANQADCgQIBQAAAA==.Mahmba:BAAANQAECgUIBQAAAA==.Mallidin:BAAANQAECgIIAgABNQAECgIIAgAHAAAAAA==.Malthoryn:BAAANQAECgMIAwAAAA==.Malzel:BAABNQAECn8UAAMcAAkKeBgMDQAqAQAFAAUK6RnSlwBpAQAcAAUKXBYMDQAqAQAAAA==.Mamasan:BAAANQAECgcIDAAAAA==.Mamor:BAAANQAECgYIEQAAAA==.Maphra:BAAANQAECgcICgAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.Mastatracka:BAAANQAECgQICAAAAA==.Mazethak:BAAANQADCgYIBgAAAA==.',
Md='Mdeow:BAAANQADCgYIEAAAAA==.',
Me='Mechabull:BAAANQAECgEIAQAAAA==.Meladys:BAAANQADCgUIBQAAAA==.Meleemeal:BAAANQAECggICwAAAA==.Melianthal:BAAANQAECgMIAwAAAA==.Melodí:BAAANQADCggICAABNQAECgoKKQAJACAcAA==.Melorac:BAAANQAECgUIBwAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQAECgYIEQAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQAECgUICAAAAA==.',
Mi='Miakoda:BAAANQADCgQIBAABNQAECgUIBQAHAAAAAA==.Micromortis:BAAANQAECgQIBAABNQAECggIEAAHAAAAAA==.Mikuu:BAAANQAECgYIDgAAAA==.Minouetoile:BAAANQADCgYIBgAAAA==.Misamane:BAAANQAECggIEAAAAA==.Mistdru:BAAANQADCgUIBQAAAA==.Mistical:BAAANQAECggIEwABNQAECgoKFAAjACkaAA==.Mitufu:BAAANQAECggIBgAAAA==.',
Mm='Mmeow:BAAANQADCggIDAAAAA==.',
Mo='Moelestyr:BAAANQAECgEIAQAAAA==.Mogonn:BAAANQABCgEIAQAAAA==.Molded:BAAANQAECgEIAQAAAA==.Moonpiie:BAAANQADCgUIBQAAAA==.Morganya:BAABNQAECn9IAAMYAAoKcxscAwAMAgAYAAoKcxscAwAMAgAXAAEKAg4ukgA2AAAAAA==.Morgul:BAABNQAECn8VAAIKAAoKpBGfGgAbAgAKAAoKpBGfGgAbAgAAAA==.Moriru:BAAANQAECgMIAwAAAA==.Moroton:BAAANQADCgQIBAABNQAECgcIEAAHAAAAAA==.Morrtis:BAAANQADCgYIEwAAAA==.Morticas:BAAANQAECgMIAwAAAA==.Movechill:BAAANQAECggIBAAAAA==.',
Ms='Mseow:BAAANQADCggIGAAAAA==.',
Mu='Mudbutbrooks:BAABNQAECn8eAAMdAAcK5g+SFwDKAAAdAAcK5g+SFwDKAAAaAAEKyQO1FAAoAAAAAA==.Muddbut:BAAANQADCgQIBAABNQAECgoKIAARAJYcAA==.Muller:BAABNQAECn8mAAIbAAkKHRIUSAA1AQAbAAkKHRIUSAA1AQAAAA==.',
Mv='Mveow:BAAANQADCgYICQAAAA==.',
Mw='Mweow:BAAANQADCgcIFQAAAA==.',
Mx='Mxeow:BAAANQADCgQICAAAAA==.',
My='Mynnu:BAAANQAECgUIEAAAAA==.Mynthara:BAAANQADCggIAgAAAA==.Mythiand:BAAANQADCgIIAgAAAA==.',
Mz='Mzeow:BAAANQADCgYIBgAAAA==.',
Na='Nahda:BAAANQADCggICAAAAA==.Nautprepared:BAAANQAECgcIEgAAAA==.',
Ne='Necrodancer:BAAANQAECggJAgAAAA==.Necrogore:BAAANQADCgcIBwAAAA==.Neeo:BAAANQADCgEJAQAAAA==.Nefetiree:BAAANQADCgQIBAAAAA==.Neildasstysn:BAAANQAECgYICQABNQAFFAEIAQAHAAAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neverdruid:BAAANQADCgEIAQAAAA==.Neveya:BAAANQADCggIKgAAAA==.',
Ni='Nickeld:BAABNQAECn8fAAIOAAgKBxxCdACVAgAOAAgKBxxCdACVAgAAAA==.Nickhy:BAAANQAECgYIEAAAAA==.Nietherme:BAABNQAECn8oAAIbAAoKTg8yMABwAQAbAAoKTg8yMABwAQAAAA==.Nietheryew:BAAANQADCgIIAgAAAA==.Nihildicits:BAAANQAECgEIAgAAAA==.Nikkeld:BAAANQADCgIIAgAAAA==.Nitesblade:BAAANQAECgEIAQABNQAECgoKGwAFACcaAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Nofoamlatte:BAAANQAECgQICQABNQAECgkJJwAVAC4UAA==.Nolife:BAAANQADCgQIBAAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.',
Ny='Nyagosa:BAABNQAECn8XAAIRAAgKlxG3bgDSAQARAAgKlxG3bgDSAQAAAA==.Nyalore:BAAANQAECgcIEgAAAA==.Nymesys:BAAANQADCgYIBgAAAA==.',
Ob='Obiwinonly:BAAANQAECgEIAQAAAA==.',
Og='Ogyaii:BAAANQAECgEIAQAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIAQAAAA==.',
Op='Optamus:BAAANQAECgEIAQAAAA==.',
Or='Oraedia:BAABNQAECn9VAAIBAAoKjh/+AwCzAgABAAoKjh/+AwCzAgAAAA==.Oralen:BAACNQAFFH8LAAIBAAUKyhouBgBDAQABAAUKyhouBgBDAQA1AAQKfykAAwEACgo4IX8KAHUDAAEACgo4IX8KAHUDABsAAgptD451AWcAAAAA.Orilitha:BAAANQADCgYIDAAAAA==.Orlandris:BAAANQADCgcIGAAAAA==.Orndaith:BAABNQAECn8ZAAIDAAkKKQ7PlgDjAQADAAkKKQ7PlgDjAQAAAA==.',
Ov='Overloader:BAABNQAECn8qAAIXAAoKsx6EFAD5AgAXAAoKsx6EFAD5AgAAAA==.',
Ox='Oxkenpachixo:BAAANQADCgMIAwAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Pa='Pairodeez:BAAANQADCgMIAQAAAA==.Palahang:BAAANQAECgEIAQAAAA==.Pallyaxe:BAAANQAECgUIEQABNQAECgoKMgAOACkVAA==.Pallygank:BAAANQADCgEIAQAAAA==.Pandawannabe:BAABNQAECn8VAAIFAAcKexxFFAB4AQAFAAcKexxFFAB4AQAAAA==.Pandussi:BAABNQAECn8aAAIeAAkKxhNiJAACAgAeAAkKxhNiJAACAgAAAA==.Paneer:BAABNQAECn8jAAICAAoKtR/bCwB+AwACAAoKtR/bCwB+AwAAAA==.Paninus:BAAANQAECgEIAQAAAA==.Papabair:BAAANQAECgcICQABNQAECggIEAAHAAAAAA==.Papawheelie:BAAANQADCgcIBwAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Penta:BAAANQAECgMIAgAAAA==.Perfectplex:BAAANQAECgEIAQAAAA==.Peruano:BAABNQAECn8sAAIPAAoKkRTxCABsAgAPAAoKkRTxCABsAgAAAA==.Petforheals:BAAANQAECgUICwAAAA==.',
Ph='Phanchom:BAAANQAECgEIAQAAAA==.Phouy:BAAANQADCgUIBQAAAA==.Phyett:BAAANQADCgEIAQABNQAECggIFQAFAHscAA==.',
Pi='Pietastegood:BAABNQAECn8tAAIDAAoKHiIdCQCrAwADAAoKHiIdCQCrAwAAAA==.Pigbeniz:BAAANQABCgIIAgAAAA==.Pikaboom:BAAANQADCgYIBgABNQAECggICgAHAAAAAA==.Pintsizemage:BAAANQAECgUIBQABNQAECggIEAAHAAAAAA==.Pitchblack:BAABNQAECn8YAAISAAoKugzYIAAyAgASAAoKugzYIAAyAgAAAA==.',
Po='Pocahöntas:BAAANQAECgUIBQAAAA==.Pocketrocket:BAAANQADCgUIBgAAAA==.Ponce:BAACNQAFFH8FAAIcAAIKqBcXBgCgAAAcAAIKqBcXBgCgAAA1AAQKfzgAAhwACgreHgQFAD8DABwACgreHgQFAD8DAAAA.Poordemon:BAAANQADCgUIBQABNQAECggIJQAVAIcJAA==.Popehealz:BAAANQADCgYIAgAAAA==.Pownds:BAAANQAECgQIBAAAAA==.',
Pr='Predatori:BAAANQADCgIIAgAAAA==.Priestofholy:BAAANQADCgYIDQAAAA==.Privo:BAABNQAFFH8KAAIRAAYKWBpzAwDTAQARAAYKWBpzAwDTAQAAAA==.Procspls:BAAANQADCgIIAgAAAA==.Provolonie:BAAANQADCggIDAAAAA==.Proñto:BAAANQAECggIAQABNQAECgcIGwAGANUOAA==.Pryor:BAAANQAECgYICgAAAA==.Pròntò:BAAANQADCgQIBAABNQAECgcIGwAGANUOAA==.Prõntõ:BAAANQADCgEIAQABNQAECgcIGwAGANUOAA==.Prøntø:BAABNQAECn8bAAMGAAcK1Q4ZJwBdAQAGAAcK1Q4ZJwBdAQAiAAIK3QP8OwBJAAAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECgoKLgADACofAA==.Punchbugman:BAAANQADCggIDAAAAA==.Puritos:BAAANQAECgIIAgAAAA==.Pustain:BAAANQABCggICgAAAA==.',
Py='Pymera:BAAANQAECgMICAABNQAECgcIDAAHAAAAAA==.Pyrista:BAABNQAECn8hAAICAAgKbxh2JQCDAQACAAgKbxh2JQCDAQAAAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quaratus:BAAANQADCgEIAQAAAA==.Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAABNQAECn8nAAIXAAkKmg5uOADvAQAXAAkKmg5uOADvAQAAAA==.Radilas:BAAANQABCgIIAgAAAA==.Radioatlarge:BAAANQAECgUIBQABNQAECgoKLQADAB4iAA==.Raendarth:BAAANQAECgUIDgAAAA==.Rageth:BAABNQAECn8cAAIKAAgK8g9hIADQAQAKAAgK8g9hIADQAQAAAA==.Ragglefraggl:BAAANQADCgMIAwABNQAFFAIIBwATAKkYAA==.Rakalaag:BAEANQAECgQICgAAAA==.Rakath:BAAANQAECgQIDgAAAA==.Ramidus:BAAANQAECgQIBgAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgcIDQAAAA==.Rathorn:BAAANQADCgQIAwAAAA==.',
Re='Reck:BAABNQAECn8uAAIDAAoKKh/aLAAJAwADAAoKKh/aLAAJAwAAAA==.Redlands:BAAANQAECgEIAQAAAA==.Redredwine:BAAANQADCggICAAAAA==.Refractory:BAAANQAECgUIBgAAAA==.Rejuve:BAAANQADCgYIBgAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Renwick:BAAANQAECgEIAQABNQAFFAUIFgANANkdAA==.Restlece:BAAANQABCgEIAQAAAA==.Reunach:BAABNQAECn8hAAIbAAkK3Q/ySQAxAQAbAAkK3Q/ySQAxAQAAAA==.',
Rh='Rhahirn:BAAANQAECgMIAwAAAA==.Rhialto:BAAANQADCgIJAgAAAA==.Rhinopill:BAAANQAECgUIBgABNQAFFAIIBwATAKkYAA==.Rhyzand:BAAANQADCgQIBwAAAA==.',
Ri='Riasg:BAAANQADCgIIAgAAAA==.Rickilake:BAAANQADCggIJwAAAA==.Ricksanchez:BAABNQAECn8nAAIFAAoKzBg9FAB4AQAFAAoKzBg9FAB4AQAAAA==.Rikoe:BAAANQAECgUIBQAAAA==.Rinik:BAAANQAECgYIDwAAAA==.Riptiide:BAAANQADCgcIBwABNQADCggIDgAHAAAAAA==.Rivendra:BAAANQADCggJGAAAAA==.Riverpixie:BAAANQADCgQIBAAAAA==.',
Ro='Rockabye:BAABNQAECn8oAAMSAAkK+hpoFQC1AgASAAkK+hpoFQC1AgARAAEKZwj6kwA7AAAAAA==.Rokar:BAAANQAECgEIAQAAAA==.Roraalionnu:BAAANQADCgUICQABNQAECgEIAgAHAAAAAA==.Rosannas:BAAANQAECgIIAgABNQAFFAIIBwATAKkYAA==.Rosi:BAAANQADCggICAAAAA==.Royallz:BAAANQAECgIIAgAAAA==.',
Ru='Rudeknees:BAACNQAFFH8TAAMcAAYKww2dAABBAQAcAAYKLQudAABBAQAFAAMKshGyGQD0AAA1AAQKfzgAAwUACgqGFiRIAFYCAAUACQqKFSRIAFYCABwACApCD+0MACsBAAAA.Ruibash:BAEBNQAECn9CAAIbAAoKwCLSEACGAwAbAAoKwCLSEACGAwAAAA==.Rukie:BAAANQAECgUIBQAAAA==.Rumproast:BAAANQAECgEIAQAAAA==.Runebladé:BAABNQAECn8YAAIVAAgKXhmUPQApAgAVAAgKXhmUPQApAgAAAA==.',
Ry='Ryuu:BAAANQADCggIDAAAAA==.Ryuuzen:BAAANQAECgcIDAAAAA==.',
Sa='Sabitha:BAAANQAECgEIAQAAAA==.Sableanne:BAAANQAECgQIBwAAAA==.Sacklunch:BAAANQADCgEIAQAAAA==.Sacredkhaos:BAAANQADCgQJBAABNQADCgQIBQAHAAAAAA==.Sacredknight:BAAANQADCgQIBQAAAA==.Saikoumaster:BAAANQAECgEIAQAAAA==.Saintkhaos:BAAANQADCgIIAgABNQADCgQIBQAHAAAAAA==.Sakuraa:BAABNQAECn8uAAMRAAoKvhIzCwAxAgARAAoKvhIzCwAxAgAQAAMKLQEdJABKAAAAAA==.Samisra:BAAANQADCgYJBgAAAA==.Sarajean:BAAANQAECgEIAQAAAA==.Savaged:BAAANQADCgcIDAABNQAECgoKOgAfAG0WAA==.Savajed:BAABNQAECn86AAMfAAoKbRb0DwCFAQAVAAgKLhj/PgAiAgAfAAoKZBH0DwCFAQAAAA==.Savaragon:BAAANQADCggIFgABNQAECgoKOgAfAG0WAA==.Sazbena:BAAANQADCgQIBAAAAA==.',
Sc='Scaledoc:BAAANQAECgMIAwABNQAECggIEAAHAAAAAA==.Scallywagg:BAAANQAECgUICgAAAA==.Scarletmatch:BAAANQAECgIIAgAAAA==.Scroto:BAAANQAECgIIAQAAAA==.',
Se='Searcomic:BAAANQAECgcIDwAAAA==.Secondwall:BAAANQADCgMIAwAAAA==.Seldav:BAABNQAECn8xAAMmAAoKdRYoBgBuAgAmAAoKdRYoBgBuAgALAAMKpQfZLwCbAAAAAA==.Selendas:BAAANQADCgcIDQAAAA==.Selessa:BAAANQADCggICgAAAA==.Selinathra:BAAANQAECgIIAgAAAA==.Selm:BAABNQAECn8zAAMGAAoKuyQ+AgCrAwAGAAoKuyQ+AgCrAwAiAAEKAABfRgAtAAAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBQAAAA==.Shaleka:BAAANQADCgcIEwABNQAECgEIAgAHAAAAAA==.Shaluesta:BAAANQADCgcICgAAAA==.Shamanism:BAAANQAECgcIDAAAAA==.Shameless:BAAANQAECgcICgAAAA==.Shamwów:BAAANQAECgcIEgAAAA==.Sharco:BAABNQAECn8nAAMWAAgKvBgMDgDMAQAWAAYKpR8MDgDMAQAOAAcKrBKSawDlAAAAAA==.Sharkbites:BAAANQAECgUICQAAAA==.Shawarmafury:BAACNQAFFH8MAAICAAUK2CFVCADFAQACAAUK2CFVCADFAQA1AAQKfzEAAgIACgqAJncCAN8DAAIACgqAJncCAN8DAAAA.Shaydens:BAAANQADCgQIBgAAAA==.Sherrizzahh:BAAANQADCgEIAQAAAA==.Shettani:BAAANQABCgYJCQAAAA==.Shiirou:BAAANQADCgQIBAAAAA==.Shinshots:BAAANQAECgEIAQAAAA==.Shockrasta:BAAANQAECgUICAABNQAECgoKNgAWAPojAA==.Shooshmael:BAABNQAECn8cAAIFAAgKKxewWwAPAgAFAAgKKxewWwAPAgAAAA==.Shozo:BAAANQADCgUICAABNQAECgoKMwAGALskAA==.Shujáa:BAAANQAECggIDAAAAA==.Shush:BAAANQAECgEIAQAAAA==.Shælynne:BAAANQABCgIIAgABNQAECgoKSAAYAHMbAA==.Shékinah:BAACNQAFFH8KAAIjAAMK7wFZCwCeAAAjAAMK7wFZCwCeAAA1AAQKfzEAAiMACgoJEFg9AAwCACMACgoJEFg9AAwCAAAA.',
Si='Sidesteppin:BAAANQADCgUICAAAAA==.Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQAECgMIAwAAAA==.Sinthein:BAAANQAECgMIBQABNQAFFAUIFgANANkdAA==.Sixséven:BAAANQADCgIIAQABNQADCgYIBgAHAAAAAA==.',
Sk='Skadgrip:BAAANQADCgUIBQABNQAECgkJFAAcAHgYAA==.Skorpekh:BAABNQAECn8ZAAICAAgKSQZUsQChAQACAAgKSQZUsQChAQAAAA==.Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgQICgAAAA==.',
Sl='Sleepingsun:BAABNQAECn8cAAIkAAgKWR9IEwCyAgAkAAgKWR9IEwCyAgAAAA==.Sloppyspikes:BAABNQAECn8XAAInAAgKUAd1GAAqAQAnAAgKUAd1GAAqAQAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smashdocta:BAABNQAECn9BAAMoAAoKuB4/AADqAgAoAAoKlh0/AADqAgADAAkKxBoLWACDAgABNQAECgoKQQACAJgkAA==.Smidgenn:BAAANQADCgcIEQAAAA==.Smokyblast:BAABNQAECn8VAAIOAAkKawRvJwFKAQAOAAkKawRvJwFKAQAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCggIGAAAAA==.Sneakgooner:BAAANQADCgcIBwAAAA==.Snowball:BAABNQAECn8+AAIOAAkKgwQTVAAUAQAOAAkKgwQTVAAUAQAAAA==.',
So='Sohtan:BAAANQADCgQIBAAAAA==.Sonbrandt:BAABNQAECn8dAAMeAAcKCg8cMgCGAQAeAAcKCg8cMgCGAQAJAAEK7g6AMQAzAAAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgQIDQAAAA==.',
Sp='Sparowprince:BAACNQAFFH8QAAIbAAUKIBmSCgCfAQAbAAUKIBmSCgCfAQA1AAQKf0AAAhsACgrOI7ITAHcDABsACgrOI7ITAHcDAAAA.Spaspanda:BAAANQAECgMIAwABNQAECggIFQAFAHscAA==.Speccurious:BAAANQADCgYIBwABNQAECgMIAwAHAAAAAA==.Spectraleye:BAAANQAECgcIDwAAAA==.Sproocherlou:BAABNQAECn8qAAIbAAoKJRwjNAD8AgAbAAoKJRwjNAD8AgAAAA==.Sprour:BAAANQAECgYJCAAAAA==.',
St='Stankbolt:BAABNQAECn8gAAIMAAkKHiQDBACSAgAMAAkKHiQDBACSAgAAAA==.Steezya:BAAANQAECgUIEwAAAA==.Stegulos:BAAANQAECgEIAQAAAA==.Stellarum:BAAANQAECgMIAwAAAA==.Stonedemon:BAAANQAECggICwABNQAFFAUIEAAbACAZAA==.Stormsy:BAAANQAECgYIDAABNQAECggIGQARAJ0PAA==.Stormykitty:BAABNQAECn8ZAAIRAAgKnQ/ucwDAAQARAAgKnQ/ucwDAAQAAAA==.Strauch:BAAANQADCgcIHAAAAA==.Striderdh:BAAANQABCggIEQAAAA==.Strongwoman:BAAANQAECgUIEAAAAA==.Sturtza:BAACNQAFFH8JAAICAAIKpBHuDQCcAAACAAIKpBHuDQCcAAA1AAQKfzwAAgIACgo4IIQGAKoDAAIACgo4IIQGAKoDAAAA.Sturtzam:BAAANQAECgIIAgABNQAFFAIICQACAKQRAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Sumat:BAAANQADCgIIAgABNQAECgEIAQAHAAAAAA==.Sunbear:BAAANQADCggIDwAAAA==.Susak:BAAANQAECgYIBwABNQAECgkJFgAUAA4cAA==.Suun:BAABNQAECn81AAIbAAoKkR3oBgB5AgAbAAoKkR3oBgB5AgAAAA==.',
Sw='Swampassuti:BAAANQAECgEIAQAAAA==.Sweetysnail:BAAANQAECgQICwAAAA==.Swoley:BAAANQAECggIEgAAAA==.',
Sy='Sybelada:BAAANQABCgcJCQAAAA==.Sylphia:BAAANQADCgYIBgAAAA==.Syrina:BAAANQADCgQIBAAAAA==.',
Ta='Taanua:BAAANQAECgMIBAAAAA==.Taelandas:BAAANQADCgUIFQAAAA==.Tagobeets:BAABNQAECn8oAAIWAAoKpgt8BABoAQAWAAoKpgt8BABoAQAAAA==.Tailyn:BAAANQADCgUIBQAAAA==.Taleiya:BAABNQAECn8XAAIBAAUKPBGgrwAgAQABAAUKPBGgrwAgAQAAAA==.Talisaie:BAAANQAECggIEgABNQAFFAUIEgAXAPAgAA==.Tanisatharae:BAAANQADCgYIDgABNQAECgcIDAAHAAAAAA==.Tarahly:BAAANQAECgYIBgABNQAECggIIAABAG4gAA==.Tarahse:BAAANQADCgIIAgABNQAECggIIAABAG4gAA==.Taron:BAABNQAECn8cAAIDAAcKPRhWLQBWAQADAAcKPRhWLQBWAQAAAA==.Tart:BAACNQAFFH8FAAMFAAMKyw5yJACaAAAFAAIKyw5yJACaAAAEAAEKLwD/NAAXAAA1AAQKfxkAAgUACQp1EL9bAA8CAAUACQp1EL9bAA8CAAAA.',
Te='Techmaestrov:BAAANQAECgQIBAAAAA==.Tedjones:BAABNQAECn8WAAIOAAYKAwXnQQEfAQAOAAYKAwXnQQEfAQAAAA==.Temupeggy:BAAANQADCgEIAQAAAA==.',
Tg='Tgbird:BAAANQADCgQIBAAAAA==.',
Th='Thandana:BAAANQAECgIIAgAAAA==.Thehumanatee:BAABNQAECn8qAAIjAAoKwRWILQBxAgAjAAoKwRWILQBxAgAAAA==.Theroach:BAAANQAECgQIDAAAAA==.Thersh:BAAANQADCgMJAwAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thiccims:BAAANQADCgIIAgABNQAECggICgAHAAAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingstabz:BAAANQAECgEIAQAAAA==.Thingytoo:BAAANQAECgcICAAAAA==.Thiqq:BAAANQAECgMIAQAAAA==.Threlindrier:BAAANQAECgIIAwAAAA==.Throbinggimp:BAAANQADCggICAAAAA==.Thunderzelly:BAAANQADCggIDwAAAA==.Thurien:BAABNQAECn8UAAIDAAcKlASl4gAjAQADAAcKlASl4gAjAQAAAA==.Thyphlo:BAAANQAECgYICgAAAA==.',
Ti='Tiltawhirl:BAAANQAECggICgAAAA==.Tiltedup:BAABNQAECn8fAAIOAAoKCBAAuwAOAgAOAAoKCBAAuwAOAgAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Tinkerßell:BAAANQADCggIEAABNQAECggIGQARAJ0PAA==.Tirich:BAAANQADCggICAABNQAFFAUIFgANANkdAA==.Titaintium:BAAANQAECgQIBAABNQAECgoKKgAXALMeAA==.',
To='Toshi:BAABNQAECn8dAAIMAAkKSAhRpgCHAQAMAAkKSAhRpgCHAQAAAA==.Totemtree:BAAANQADCgMIAwABNQAECggIKgAlAC0VAA==.Touchyouup:BAAANQAECgIIAQAAAA==.',
Tr='Trilguth:BAAANQADCgYIBgAAAA==.Truckkun:BAAANQAECggICgAAAA==.Trustmei:BAAANQAECggICwAAAA==.Trystin:BAAANQAECgIIAgAAAA==.',
Ts='Tstick:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.',
Tu='Tulark:BAAANQABCgYIBgAAAA==.Tullydin:BAABNQAECn8nAAMhAAoKyAj1MgBLAQAbAAgKRQhW3gBeAQAhAAkKewf1MgBLAQAAAA==.Tullyy:BAAANQAECgQICwAAAA==.Tums:BAABNQAECn8mAAMTAAoKdRv4EwAlAQANAAcKUhvUFwAfAgATAAgKOBf4EwAlAQAAAA==.',
Tw='Twirls:BAABNQAECn8YAAIJAAgK7RnGDQAdAgAJAAgK7RnGDQAdAgAAAA==.Twistoffate:BAAANQAECgUIDgAAAA==.',
Ty='Tyerant:BAAANQADCgMIAgAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
['Tä']='Tälos:BAAANQADCgUIBQABNQADCggIDQAHAAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Un='Uncanny:BAABNQAECn8UAAIWAAcKZgkyIADoAAAWAAcKZgkyIADoAAAAAA==.Unpaidintern:BAAANQAECggIEQAAAA==.',
Ur='Urtle:BAAANQADCggIFAAAAA==.',
Us='Uselece:BAABNQAECn8jAAMbAAoKqBoaewA1AgAbAAoKqBoaewA1AgAhAAQKkQ0PTwCrAAAAAA==.',
Ut='Uthadandewey:BAAANQADCgcIBwAAAA==.',
Uz='Uzainbolt:BAAANQAECggIEgAAAA==.',
Va='Valgorr:BAAANQAECgYICwAAAA==.Valvalon:BAABNQAECn8pAAIWAAoKABxwBADlAgAWAAoKABxwBADlAgAAAA==.Vandil:BAAANQADCgYIBgAAAA==.Vanessia:BAAANQADCgQIBAAAAA==.Varhaitof:BAAANQADCggICAAAAA==.',
Ve='Veelaria:BAABNQAECn8iAAIhAAkKBA41KQCTAQAhAAkKBA41KQCTAQAAAA==.Vegetablue:BAAANQAECgEIAQAAAA==.Velinddrel:BAAANQADCgUIBQAAAA==.Verahardyr:BAAANQADCgQIBAAAAA==.Veravulp:BAAANQAECgEIAQAAAA==.Vet:BAAANQAECgQIBwAAAA==.',
Vh='Vhelithiana:BAAANQAECgIIAgAAAA==.',
Vi='Viathun:BAAANQADCggICAABNQAECgoKOgAfAG0WAA==.Vicalaus:BAABNQAECn8vAAIfAAkKnRrdCgCzAQAfAAkKnRrdCgCzAQABNQAECgoKOwAYAN4aAA==.View:BAABNQAECn8aAAIEAAoKaBQ6VgAPAgAEAAoKaBQ6VgAPAgAAAA==.Vikcy:BAAANQAECgQIBgAAAA==.Vikcyholy:BAAANQAECgEIAQAAAA==.Vilified:BAAANQADCggIEwAAAA==.Violete:BAAANQADCgUIBQAAAA==.Vitamind:BAAANQAECgUIBQAAAA==.Vitros:BAAANQADCgcIBwABNQAECgoKLQAQAGQTAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQAECgkJFQAGAHMgAA==.Voidwitch:BAABNQAECn8bAAIPAAcKgiQWBADwAgAPAAcKgiQWBADwAgAAAA==.Volstagg:BAAANQADCgMIAwAAAA==.Vortirtbreni:BAAANQAECgIIAgAAAA==.',
Vr='Vrakken:BAABNQAECn8hAAIfAAkKjRIeCwCwAQAfAAkKjRIeCwCwAQAAAA==.',
Vu='Vududonkey:BAAANQAECgMIAwABNQAECgkJFwAiAOQOAA==.',
Vy='Vyndenus:BAACNQAFFH8GAAIRAAQKfAvzDQDXAAARAAQKfAvzDQDXAAA1AAQKfzwAAhEACgo0HzkCAE8DABEACgo0HzkCAE8DAAAA.',
Wa='Warriorluv:BAAANQADCgEIAQAAAA==.Warrwing:BAAANQADCgcIBwAAAA==.',
We='Webbfury:BAAANQAECggIDQAAAA==.Welor:BAAANQAECgUIBQAAAA==.Wespoo:BAAANQAECgQIBQAAAA==.Wetpug:BAAANQADCggIDQAAAA==.',
Wh='Wheremytotem:BAAANQADCggIDQABNQAECgoKIAARAJYcAA==.Whitbone:BAAANQADCgQIBAAAAA==.Wholephister:BAAANQAECgEIAQABNQAECgcIFAAcAK4SAA==.Whupsmarse:BAAANQADCgcIDQAAAA==.',
Wi='Wickin:BAAANQADCggIDAAAAA==.Wifeyaggroed:BAAANQAECgMIAwAAAA==.Wiggles:BAAANQABCgEIAQAAAA==.Wiglock:BAAANQAECgEIAgAAAA==.Wigpetval:BAABNQAECn8lAAMCAAgKnRGImQDUAQACAAgKURGImQDUAQAdAAIKrRVCaQCIAAAAAA==.Wiidge:BAABNQAECn8iAAIlAAgKiwspBAAXAQAlAAgKiwspBAAXAQAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQAECgMIBQAAAA==.Winterbane:BAAANQAECgQIBAAAAA==.',
Wo='Wocky:BAABNQAECn8XAAIjAAYK+xhMSADJAQAjAAYK+xhMSADJAQAAAA==.Wolfchan:BAAANQAECgQIDgAAAA==.Wolfmeow:BAAANQADCgMIAwABNQAECgoKOwAYAN4aAA==.Worldcrafter:BAABNQAECn8ZAAMQAAgKgRuPCADbAQAQAAYKkRuPCADbAQARAAcKIRw8HACYAQAAAA==.Worldender:BAAANQAECgYIDwAAAA==.Wowretail:BAABNQAECn8hAAQhAAcKphs6IQDaAQAhAAYKnB46IQDaAQAbAAYKZRtNrQDFAQABAAQKSSCQwQD4AAAAAA==.',
Wr='Wrathofdawn:BAAANQAECgYICQAAAA==.Wreckross:BAAANQABCgUIBQAAAA==.',
Wy='Wyldar:BAABNQAECn8YAAIbAAkK1xM5kwD9AQAbAAkK1xM5kwD9AQAAAA==.',
Xa='Xalaria:BAAANQAECggICwAAAA==.Xantry:BAACNQAFFH8FAAIbAAMK3gveGwDJAAAbAAMK3gveGwDJAAA1AAQKfxwAAhsACQr+IoE4AO4CABsACQr+IoE4AO4CAAAA.',
Xe='Xeviscerated:BAAANQADCgEIAQAAAA==.',
Xm='Xmen:BAABNQAECn8YAAIOAAcKbwdhdgDRAAAOAAcKbwdhdgDRAAAAAA==.',
Xs='Xslight:BAAANQAECgcICAABNQADCggIDgAHAAAAAA==.',
Xu='Xurkitree:BAAANQAECgMIAwAAAA==.',
Xy='Xymm:BAAANQAECgUIBAAAAA==.',
Ye='Yeastybush:BAABNQAECn8lAAIEAAoK3B0FJADWAgAEAAoK3B0FJADWAgAAAA==.',
Yi='Yinsen:BAAANQADCggICAAAAA==.',
Ys='Yseera:BAAANQAECgYICQAAAA==.Yseeraa:BAAANQAECgEIAQAAAA==.',
Za='Zarathea:BAAANQAECgEIAQABNQAECgUIBQAHAAAAAA==.',
Zi='Zilphah:BAAANQADCgMIAwAAAA==.Zimmerwitch:BAAANQADCggJDgAAAA==.Zimms:BAABNQAECn8sAAIeAAoKmRwYDwDyAgAeAAoKmRwYDwDyAgAAAA==.',
Zo='Zoeyredbird:BAABNQAECn8UAAQUAAkKOxh+FABAAQAfAAcK1RbmRgCjAQAUAAQKURl+FABAAQAVAAIKDBe+tACGAAAAAA==.Zongo:BAAANQADCgcIBwAAAA==.',
Zw='Zwhitty:BAAANQADCgcJCQAAAA==.Zwhittytv:BAABNQAECn8VAAILAAoK3xA8AwCEAQALAAoK3xA8AwCEAQAAAA==.',
['Ña']='Ñazary:BAAANQADCggIDwAAAA==.',
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
