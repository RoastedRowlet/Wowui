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

local lookup = {'Unknown-Unknown','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Druid-Guardian','Evoker-Preservation','Rogue-Subtlety','Warlock-Demonology','Priest-Shadow','Priest-Holy','Priest-Discipline','Rogue-Assassination','Mage-Arcane','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Blood','DeathKnight-Unholy','Hunter-Survival','Warrior-Protection','Hunter-BeastMastery','Mage-Frost','Druid-Feral','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Destruction','Warlock-Affliction','Monk-Mistweaver','Evoker-Augmentation','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Shaman-Enhancement','DeathKnight-Frost','Evoker-Devastation','Druid-Balance',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aamara:BAAANQAECgUIDQABNQAECgYICwABAAAAAA==.',
Ab='Aboyton:BAAANQADCgYIEAAAAA==.',
Ad='Adarksoul:BAAANQADCggICQAAAA==.Adhpally:BAAANQADCgIIAgABNQAECgkJHQACAHIeAA==.Adorara:BAAANQADCgEIAQAAAA==.',
Ae='Aefarshammy:BAABNQAECoEfAAMDAAkK3yM+NQBdAgADAAYKQyM+NQBdAgAEAAkKxhPCOQAwAgAAAA==.Aelistiah:BAAANQABCggIEwAAAA==.Aerithorn:BAABNQAECoEaAAIFAAgKCCFNBQDxAgAFAAgKCCFNBQDxAgAAAA==.',
Ah='Aheck:BAAANQADCgMJAwABNQAECgcIEwABAAAAAA==.Ahleya:BAAANQAECgQIBAAAAA==.Ahlonaa:BAAANQADCggJDQAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgQICgABAAAAAA==.',
Ak='Akoris:BAAANQADCgcICgABNQAECggIEgABAAAAAA==.Akorys:BAAANQAECggIEgAAAA==.',
Al='Albyno:BAACNQAFFIEGAAIGAAMKfgzdCwDuAAAGAAMKfgzdCwDuAAA1AAQKgRwAAgYACQobGEwNAKkCAAYACQobGEwNAKkCAAAA.Algebrah:BAAANQADCgYIBgAAAA==.',
Am='Amara:BAAANQADCgYIFgAAAA==.Ambitionz:BAAANQADCgEIAQAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAAANQAECgQIEAAAAA==.Ancksunamun:BAAANQADCgUIBwAAAA==.Andromedia:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Anicarcia:BAAANQADCgQIBAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAACNQAFFIENAAIHAAUKpxN+BAC1AQAHAAUKpxN+BAC1AQA1AAQKgRoAAgcACQrfHn4FAB4DAAcACQrfHn4FAB4DAAAA.',
Ap='Aperture:BAAANQADCgcIBwAAAA==.',
Aq='Aquua:BAABNQAECoEaAAIDAAgK8hdFOQBJAgADAAgK8hdFOQBJAgAAAA==.',
Ar='Araelen:BAAANQAECgUJBQAAAA==.Arcticdps:BAABNQAECoEdAAIIAAkKdxR/OABtAgAIAAkKdxR/OABtAgAAAA==.Ariastel:BAAANQABCgIIAgAAAA==.Ariell:BAABNQAECoEXAAQJAAgK2RYDLAB0AQAJAAYK9BIDLAB0AQAKAAUK5Au5gQAhAQALAAUKkQz9DgAHAQAAAA==.Ariestar:BAAANQAECgUIBQAAAA==.Ariiel:BAAANQADCggICQABNQAECggIFwAJANkWAA==.Arthimas:BAAANQAECgIJAgAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQAECggJBwAAAA==.Ashelash:BAAANQAECgQIBgAAAA==.Asidize:BAAANQAECgQIBAAAAA==.Aslor:BAAANQAECgYIEgAAAA==.Aspenoa:BAAANQADCggICAAAAA==.Asralia:BAAANQADCgMIAwAAAA==.',
At='Athalia:BAABNQAECoEnAAIMAAkKbSBdBgBCAwAMAAkKbSBdBgBCAwAAAA==.',
Au='Audi:BAAANQADCgMIBAAAAA==.Aug:BAAANQAECgUIDAAAAA==.Autofellate:BAAANQADCgIIAgAAAA==.',
Av='Avaldra:BAAANQABCgEIAQAAAA==.Avex:BAAANQAECgcIEwAAAA==.',
Ax='Axemage:BAABNQAECoEiAAINAAgKAhZvfQBKAgANAAgKAhZvfQBKAgAAAA==.Axeom:BAABNQAECoEiAAIEAAgKshlKLABxAgAEAAgKshlKLABxAgAAAA==.Axeshammy:BAAANQAECgIIAgABNQAECggIIgANAAIWAA==.',
Az='Azmodan:BAAANQAECgEIAQAAAA==.Azzith:BAAANQAECgYIDwAAAA==.',
Ba='Bahgeye:BAAANQADCgUIBQAAAA==.Bajaladin:BAAANQAECgYIDwAAAA==.Barometer:BAAANQAECgUIDAAAAA==.Bast:BAAANQADCggICwABNQAECgYIDAABAAAAAA==.Baxa:BAAANQADCgYJDAAAAA==.Baylee:BAAANQAECgQIDwAAAA==.',
Bb='Bbartemis:BAAANQAECgQIBgAAAA==.',
Be='Bearaqobama:BAAANQADCgYIBgAAAA==.Bearlyalivee:BAAANQADCgUICQABNQAECgMIBAABAAAAAA==.Bearvul:BAAANQABCgEIAQAAAA==.Beekerr:BAAANQADCgMIAwABNQAECgcIGQAHAP4bAA==.Belbroon:BAAANQADCgQIBAAAAA==.Beliele:BAAANQAECgQIBQAAAA==.Benjohnbo:BAAANQABCgEIAQAAAA==.Benwins:BAAANQAECgEIAgAAAA==.Bergamö:BAAANQADCgcICQABNQAECgIIAwABAAAAAA==.Bernecessity:BAAANQAECgYIBwAAAA==.',
Bh='Bho:BAAANQADCgUICgAAAA==.',
Bi='Biffedit:BAAANQADCgcIBwAAAA==.Biom:BAABNQAECoEUAAQOAAYKuReAlgCKAQAOAAYKcRSAlgCKAQAPAAQKZRt3KgAwAQAQAAMKISCZmQABAQAAAA==.Bis:BAAANQADCgEJAgAAAA==.Biscuitbabe:BAAANQAECgYIEgAAAA==.Bisholoyd:BAAANQAECgMIAwAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blastoise:BAABNQAECoEcAAMRAAgKQh4ZHACbAgARAAcKmCEZHACbAgASAAYKgRA6YAAoAQAAAA==.Blinktwice:BAAANQABCgcIBwAAAA==.Blizfishleg:BAAANQADCgcIFAAAAA==.Bllur:BAAANQADCgIIAgAAAA==.Bloodroots:BAAANQAECgMIBwAAAA==.Bluur:BAAANQADCgYIBgAAAA==.',
Bo='Bonehacker:BAAANQABCgYICAAAAA==.Boombóx:BAAANQADCgUIBQABNQAECggIHwAIAK8hAA==.Boostia:BAAANQADCgEIAQAAAA==.Borthos:BAAANQAECgcIEwAAAA==.Bowsback:BAAANQADCgcIGAAAAA==.Bowyohead:BAAANQAECgcIDQABNQAECgkJHgAQAG8XAA==.',
Br='Brandoe:BAAANQAECgQIBgAAAA==.Breece:BAAANQADCgcIDAAAAA==.Brickinkeys:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Brightmare:BAAANQADCgYIDwAAAA==.Brusa:BAAANQADCgEJAQAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAAANQAECgcIDwAAAA==.',
Ca='Caadra:BAAANQADCgIIAgAAAA==.Caimie:BAAANQAECgIJAgAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQAECgQICQAAAA==.Cassiaan:BAAANQAECgEIAQAAAA==.Caylavibes:BAABNQAECoEdAAIKAAkKeBCSOwAzAgAKAAkKeBCSOwAzAgAAAA==.',
Ch='Chaviel:BAAANQAECggICgAAAA==.Cheetasista:BAAANQADCgQJBAAAAA==.Cherry:BAAANQAECgEIAgAAAA==.Chironn:BAABNQAECoEZAAITAAgKzhhQAwCdAgATAAgKzhhQAwCdAgAAAA==.Chudlord:BAAANQADCgYICAAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQAECgMIAwAAAA==.',
Ci='Cinderburn:BAAANQAECgIIAwAAAA==.Cinderkai:BAAANQAECgEIAgAAAA==.',
Cl='Clayshaper:BAAANQADCgYIDAAAAA==.Clohhe:BAAANQAECgEIAgAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQADCgEIAQAAAA==.Comfychair:BAAANQAECgYIBwAAAA==.Conclaved:BAAANQADCgMIAwAAAA==.Coowmoo:BAAANQAECgQICgAAAA==.Cosmochopper:BAAANQAECgEIAQABNQAECggIDQABAAAAAA==.Cosmoshotter:BAAANQAECggIDQAAAA==.',
Cr='Craterstab:BAAANQADCgEIAQAAAA==.Cremebrule:BAAANQADCggIHwAAAA==.Critnyspears:BAAANQAECgIIBgAAAA==.Crushleaf:BAAANQADCggICwAAAA==.',
Cu='Cucubau:BAAANQADCgcIBwAAAA==.',
Cy='Cyndra:BAAANQADCgIIAgAAAA==.',
Da='Dallthyrian:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.Dalthyrian:BAAANQAECgYICgABNQAECgUIBwABAAAAAA==.Dalthyriian:BAAANQAECgUIBwAAAA==.Dalthyrrian:BAAANQAECgEJAQABNQAECgUIBwABAAAAAA==.Dalthyyrian:BAAANQAECgQIBAABNQAECgUIBwABAAAAAA==.Damii:BAAANQADCgUICQAAAA==.Danfarm:BAAANQADCgEIAQAAAA==.Dargonbref:BAAANQADCgUIAQABNQAECgYICwABAAAAAA==.Darjen:BAAANQAECgMIAwAAAA==.Darkjestêr:BAAANQADCgUIBQAAAA==.Darksky:BAAANQABCgMIAwAAAA==.Daysfox:BAAANQAECgcIEAAAAA==.Daysmonk:BAAANQADCgYIBgAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deadenside:BAAANQADCgMIAwAAAA==.Deadmountain:BAAANQADCgIIBAAAAA==.Deahtlyx:BAAANQADCgQIBAABNQAECgkJHgAMAPUZAA==.Deathfang:BAAANQADCgUICgAAAA==.Deathlyy:BAABNQAECoEeAAMMAAkK9RkzEwCbAgAMAAgKNxszEwCbAgAHAAQKOwqEMgDqAAAAAA==.Deathmatch:BAAANQAECgIIAwAAAA==.Deathstone:BAAANQAECgcIDQABNQAECgkJMgAOANkjAA==.Deathtress:BAAANQAECgQICAAAAA==.Debbydowner:BAAANQAECgUIDQAAAA==.Decado:BAAANQAECgYIDAAAAA==.Deemwins:BAAANQADCgYIBwAAAA==.Deezenuts:BAAANQAECggIAwAAAA==.Degen:BAAANQAECgMIAwAAAA==.Dejevoid:BAAANQAECgcICwAAAA==.Delidyr:BAAANQAECgEIAQAAAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEBNQAECoEaAAMUAAcKjxj2DgDgAQAUAAcKjxj2DgDgAQACAAMKnwbm8QCPAAAAAA==.Denwere:BAAANQADCgUICAAAAA==.Deww:BAAANQAECgcIEAAAAA==.',
Dh='Dhawk:BAAANQADCggIFAAAAA==.Dhelilha:BAABNQAECoEcAAIPAAgKLgmYJgBOAQAPAAgKLgmYJgBOAQAAAA==.',
Di='Distance:BAAANQADCgIIAgAAAA==.',
Dk='Dkalliru:BAABNQAECoEaAAIRAAgKqxsDIQB2AgARAAgKqxsDIQB2AgAAAA==.',
Do='Docdolittle:BAABNQAECoEkAAIVAAkKMCEtDQBTAwAVAAkKMCEtDQBTAwAAAA==.Docfreez:BAABNQAECoEgAAMNAAgKMiCAcABpAgANAAcKUB+AcABpAgAWAAIKHx+5IQCeAAAAAA==.Docragosa:BAAANQAECgMIBAABNQAECgcICAABAAAAAA==.Doctermoo:BAAANQAECgEIAQAAAA==.Doomhamer:BAAANQADCggICAABNQAECgcIEwABAAAAAA==.Doraemee:BAAANQAECgIIAgAAAA==.',
Dr='Drbaconbrgr:BAAANQAECgYICwABNQAECggIFwAVAHUgAA==.Drbakedziti:BAAANQADCgYIBgABNQAECggIFwAVAHUgAA==.Drbaobuns:BAAANQAECgYICwABNQAECggIFwAVAHUgAA==.Drcarrotcake:BAAANQADCggIDgABNQAECggIFwAVAHUgAA==.Drcheeseball:BAAANQAECgUICAABNQAECggIFwAVAHUgAA==.Dreggsalad:BAAANQAECgUICgABNQAECggIFwAVAHUgAA==.Dreima:BAAANQAECgMJAwAAAA==.Dreist:BAAANQADCgIIAgAAAA==.Drfriedrice:BAAANQADCgEJAQABNQAECggIFwAVAHUgAA==.Drgatorwine:BAAANQAECgUICAABNQAECggIFwAVAHUgAA==.Drhashbrowns:BAAANQAECgQIBgABNQAECggIFwAVAHUgAA==.Drkimchirice:BAABNQAECoEYAAIXAAgKZiPVAwAaAwAXAAgKZiPVAwAaAwABNQAECggIFwAVAHUgAA==.Drmacncheese:BAAANQAECgQIDwABNQAECggIFwAVAHUgAA==.Drpumpkinpie:BAAANQAECgYIDAABNQAECggIFwAVAHUgAA==.Drshephardpi:BAAANQADCggICgABNQAECggIFwAVAHUgAA==.Drshortbread:BAAANQAECgQIBAABNQAECggIFwAVAHUgAA==.Druiddres:BAAANQAECgQIBAAAAA==.Druidussy:BAAANQADCggICAAAAA==.Drwontonsoup:BAABNQAECoEXAAIVAAgKdSALHwDlAgAVAAgKdSALHwDlAgAAAA==.',
Du='Dummythicc:BAAANQADCgQIBAAAAA==.',
['Dö']='Dööku:BAAANQADCgYIBgAAAA==.',
Ei='Eighteen:BAABNQAECoEgAAIHAAkKsRtMBwDyAgAHAAkKsRtMBwDyAgAAAA==.',
Ek='Eksi:BAAANQAECgcIEwAAAA==.',
El='Elethe:BAAANQAECgIIAgABNQAFFAUIDQAHAKcTAA==.Elianx:BAAANQAECggIAQAAAA==.Ellebush:BAAANQADCgIIAgAAAA==.Elzaine:BAAANQAECgMIBAAAAA==.',
Em='Embedded:BAAANQAECgYICwAAAA==.Eme:BAAANQADCggIFAAAAA==.Emearq:BAAANQABCggICgAAAA==.Empress:BAAANQAECgYIDgAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQAECggICQAAAA==.Enhanceme:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Entrophi:BAAANQADCgMIAwAAAA==.',
Er='Erikaa:BAAANQAECgIIAgAAAA==.Erisnyx:BAAANQADCgIIAgAAAA==.',
Es='Escoez:BAAANQADCgQIBAABNQADCggICQABAAAAAA==.Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAQABNQAECggICQABAAAAAA==.',
Ex='Excruciator:BAAANQAECgYIEwAAAA==.Exhumedraven:BAAANQAECgIIBAAAAA==.',
Fa='Falloutz:BAAANQADCggIJQAAAA==.Farahcanle:BAABNQAECoEgAAIFAAgKdAqBGQBVAQAFAAgKdAqBGQBVAQAAAA==.Farrock:BAAANQAECgYIDwAAAA==.Fawxette:BAAANQADCggICAABNQAECgkJLQAYAF4ZAA==.',
Fe='Felanish:BAAANQAECgEIAQAAAA==.Felystia:BAAANQAECgMIBQAAAA==.Fenra:BAAANQADCgcICQAAAA==.Feorblarir:BAAANQAECgMIBQAAAA==.Fernmister:BAAANQAECgIIAwAAAA==.',
Fi='Fieryfrost:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Filledegel:BAAANQAECgQICQABNQAECgYIBgABAAAAAA==.Finowscath:BAAANQAECgIJAgAAAA==.Firequencher:BAAANQAECgYIEgAAAA==.Fistacuffs:BAAANQADCgcIFQAAAA==.Fistdoc:BAAANQAECgYICAABNQAECgcICAABAAAAAA==.Fistícuffs:BAAANQADCggIGgAAAA==.Fizzroll:BAAANQADCgcIGgAAAA==.Fié:BAAANQADCgYIEgABNQAECgkJLQAYAF4ZAA==.',
Fl='Flais:BAAANQAECgIIAgAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAABNQAECoEnAAIZAAgKhRKYJwAQAgAZAAgKhRKYJwAQAgABNQAECgkJLQAYAF4ZAA==.Foxknight:BAAANQADCgQIBAABNQAECgkJLQAYAF4ZAA==.Foxybag:BAAANQADCggICAAAAA==.Foxytotes:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.',
Fr='Fredo:BAAANQADCgIIAgAAAA==.Friendlypal:BAAANQAECgYIEQAAAA==.Friendofbear:BAABNQAECoEjAAIVAAkKoBngKAC4AgAVAAkKoBngKAC4AgAAAA==.Fromabove:BAAANQADCgMIAwAAAA==.',
Fu='Furryfeet:BAAANQAECgUICAAAAA==.Fuzywuzzy:BAAANQAECgcIDwAAAA==.Fuzzykuntz:BAAANQAECgUIDgAAAA==.',
Fy='Fynsdood:BAAANQAECgUICQAAAA==.Fynslane:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.',
Ga='Gabelock:BAACNQAFFIEKAAMIAAYKNBlHBADZAQAIAAUK3B1HBADZAQAaAAEK6wGvGgBJAAA1AAQKgSwABAgACQoAIxwUAA8DAAgACAoyIxwUAA8DABoABAouGX4qABMBABsAAQrmHG8kAD0AAAAA.Gabemage:BAAANQAECgYIDAAAAA==.Gala:BAAANQAECgMIBAAAAA==.Gasback:BAAANQADCgYICwAAAA==.',
Gh='Gherkins:BAAANQADCgYICgAAAA==.Ghostreveri:BAAANQAECgUIBwAAAA==.',
Gi='Gigah:BAAANQAECgcICwAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQAECgQJBgAAAA==.Glutebruiser:BAAANQAECgEIAgABNQAECgUICwABAAAAAA==.',
Gn='Gnomedguerre:BAAANQADCgYIDQAAAA==.',
Go='Gooseshift:BAAANQAECgEIAQAAAA==.Gouchh:BAAANQAECgEIAQAAAA==.',
Gr='Gravithel:BAAANQADCgYIDwAAAA==.Graybøw:BAAANQADCgcIBwAAAA==.Grayseer:BAABNQAECoEXAAIcAAgKVyKOBwDtAgAcAAgKVyKOBwDtAgAAAA==.Grimspark:BAAANQABCgUIBQAAAA==.Grimtree:BAAANQAECgYIEwAAAA==.Grindor:BAAANQADCggIDAAAAA==.Grommel:BAAANQADCgYICAAAAA==.Grumblecane:BAAANQADCgIIAgAAAA==.Grumpstraza:BAAANQAECgEIAQAAAA==.Grumpydemon:BAABNQAECoEhAAIYAAgKEBT4HgAdAgAYAAgKEBT4HgAdAgAAAA==.Grymshot:BAAANQAECgIJAgAAAA==.',
Gw='Gwong:BAAANQADCgcIBwAAAA==.',
Ha='Haldril:BAEANQAECgUIBQABNQAECgkJKwAOAK4gAA==.Halfskul:BAABNQAECoEYAAISAAgK4gwgSwCCAQASAAgK4gwgSwCCAQAAAA==.Halotic:BAAANQADCggJCAAAAA==.Hashah:BAABNQAECoEVAAIJAAcKUxxIGABMAgAJAAcKUxxIGABMAgAAAA==.Hatefel:BAAANQAECgQJBAABNQAECgUIBwABAAAAAA==.',
He='Healsgobrr:BAAANQADCgYICwABNQAECgkJJwAdAD0YAA==.Healyaass:BAAANQADCggIEwAAAA==.Hecate:BAAANQADCgIIAgAAAA==.Helenfeller:BAAANQADCgEIBAAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgcIFQAJAFMcAA==.Hexlexxia:BAAANQADCggIDwABNQAECgYICwABAAAAAA==.Heyyboyy:BAABNQAECoEcAAMVAAkKsR0rGAAKAwAVAAkKsR0rGAAKAwAeAAEK8g1kaAA7AAAAAA==.',
Ho='Holyaefar:BAAANQADCgQIBAABNQAECgkJHwADAN8jAA==.Holysab:BAAANQAECgQICQAAAA==.Holysock:BAAANQAECgMIAwAAAA==.Holyyaii:BAAANQAECgcICAAAAA==.Holz:BAAANQAECgEIAQAAAA==.Horsetowater:BAAANQADCgYIBgABNQAECgkJHgAQAG8XAA==.',
Hu='Hugoman:BAAANQADCggIIwABNQAECgYIEQABAAAAAA==.Huni:BAABNQAECoEcAAIEAAkKsx6NGADgAgAEAAkKsx6NGADgAgAAAA==.Hunterj:BAAANQADCgcIBwAAAA==.Huupa:BAAANQADCgYIBgAAAA==.',
Hy='Hydealyn:BAAANQADCgQIBAAAAA==.Hystaric:BAAANQADCgYIDAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ia='Iamyu:BAAANQAECgMIAwABNQAECggICgABAAAAAA==.',
Ib='Ibun:BAAANQAECgIIAwAAAA==.',
Ic='Iceblow:BAAANQADCgcIBwAAAA==.Icentheveins:BAABNQAECoEeAAIQAAkKbxeqJQCgAgAQAAkKbxeqJQCgAgAAAA==.',
Ig='Igneus:BAACNQAFFIEHAAINAAQKCiHUEgCPAQANAAQKCiHUEgCPAQA1AAQKgSAAAg0ACQquI/sPAIUDAA0ACQquI/sPAIUDAAAA.Igriz:BAAANQADCggIHAAAAA==.',
Ii='Iillil:BAABNQAECoEZAAIYAAgKbgpMKADDAQAYAAgKbgpMKADDAQAAAA==.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Imakeuflased:BAAANQADCgIIAgAAAA==.Immamoonchix:BAAANQADCgUICwAAAA==.Imthatguy:BAAANQADCgQIBAAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
In='Inkyraven:BAAANQADCgIIAgAAAA==.Insidedoubt:BAAANQAECgIIAgAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.Ironorchid:BAAANQADCgUJBQAAAA==.',
It='Itsjeff:BAAANQAECgUIDAAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jambonjay:BAABNQAECoEVAAICAAQK9AmZ2wDHAAACAAQK9AmZ2wDHAAABNQAECgYIGAAVAGEVAA==.Jananda:BAAANQAECgUICgAAAA==.Jarnirdimli:BAAANQABCgYIDAAAAA==.Jaywaz:BAAANQAECgUIBQAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgAAAA==.Jckjckjck:BAAANQADCgUIBQAAAA==.Jckjckjckjck:BAAANQADCgQIBAAAAA==.',
Je='Jermagedupri:BAACNQAFFIEKAAINAAMKkhMKJADwAAANAAMKkhMKJADwAAA1AAQKgS4AAg0ACQr2Ia0iADwDAA0ACQr2Ia0iADwDAAAA.Jessupy:BAAANQAECgcIDQAAAA==.Jezashi:BAAANQADCgUIBQAAAA==.Jezina:BAAANQADCgYIBgAAAA==.',
Jh='Jhene:BAAANQAECgUIBQABNQAECggICgABAAAAAA==.',
Jo='Johkneesinz:BAAANQADCgYICwAAAA==.Johntapper:BAAANQADCgQIBgAAAA==.Joshuå:BAAANQAECgUICQAAAA==.',
Ju='Julieteshade:BAAANQADCgMJBAAAAA==.Junkbot:BAAANQADCgYIEAAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
['Jø']='Jøsh:BAAANQADCgQIBQAAAA==.',
Ka='Kaimingxiona:BAAANQAECgQIBAAAAA==.Kalrendion:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Kalru:BAAANQAECgEIAQAAAA==.Karaillyonna:BAAANQAECgYIBgAAAA==.Karasu:BAAANQAECgEIAQAAAA==.Karliechirky:BAAANQADCgYIBgAAAA==.Kasher:BAAANQAECgQIBAAAAA==.Kayho:BAAANQAECgUJBwAAAA==.',
Ke='Kelltrax:BAAANQAECgMIBAAAAA==.Kelsier:BAABNQAECoEeAAMcAAkK9yJpAwBdAwAcAAkK9yJpAwBdAwAfAAUKqQQpPwCwAAAAAA==.Kelzorn:BAAANQADCgEIAQAAAA==.Keruilin:BAAANQADCgQIAgAAAA==.Kesk:BAAANQADCgUICAAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khela:BAAANQAECgIIAgAAAA==.Khendra:BAAANQAECgQIAwAAAA==.',
Ki='Kiezo:BAAANQAECgQICQAAAA==.Killachefd:BAAANQAECgYICgAAAA==.Killamanjoro:BAABNQAECoEcAAICAAgKWxx2VgBEAgACAAgKWxx2VgBEAgAAAA==.Kimchiwar:BAAANQAECgUICgAAAA==.Kirasha:BAAANQADCggIHQAAAA==.Kitak:BAAANQAECgYIDQAAAA==.Kitchenbound:BAAANQAECgYIDwAAAA==.Kittychan:BAAANQAECgYIEQAAAA==.',
Kl='Klaacus:BAABNQAECoEiAAMYAAkKPhU5GwBHAgAYAAgKshU5GwBHAgAZAAEKnhF/bgBBAAAAAA==.Kloex:BAAANQABCgIIAgAAAA==.',
Kn='Knosk:BAAANQAECgUIBQAAAA==.',
Ko='Kodomo:BAAANQADCgYIBgAAAA==.Kokk:BAAANQAECgMIAwAAAA==.Koudelka:BAAANQAECgQJBAAAAA==.',
Kr='Kralok:BAAANQADCgYICwAAAA==.Krazm:BAAANQAECgYIDAAAAA==.Kreleril:BAAANQADCgEIAQAAAA==.Kriticál:BAABNQAECoEYAAMJAAkK8Q2AJAC7AQAJAAkK8Q2AJAC7AQALAAEKXxL2HwA5AAAAAA==.Krustyg:BAAANQADCgcIDAAAAA==.Krustym:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEANQAECggIDQABNQAECgkJKwAOAK4gAA==.',
La='Lakshmi:BAAANQAECgYICwAAAA==.Laradin:BAAANQADCgEJAQAAAA==.Larasimus:BAAANQADCgMJAwAAAA==.Larndorn:BAAANQADCgMIAwAAAA==.Lavagrip:BAAANQAECgQIDgAAAA==.',
Le='Lelou:BAACNQAFFIELAAMVAAUKxyTWAQAXAgAVAAUKxyTWAQAXAgAeAAEKvh0xGABYAAA1AAQKgS4AAxUACQqdJpoBAOEDABUACQqdJpoBAOEDAB4AAwqOIOw6ABIBAAAA.Letmehealu:BAAANQADCgEIAQAAAA==.Lewsky:BAAANQAECgIIBAABNQAECgkJGwAOAOgiAA==.',
Li='Lichtghost:BAAANQADCgEIAQAAAA==.Lilathiaa:BAAANQADCgYIFwAAAA==.Lilru:BAAANQAECgEIAQAAAA==.Linddria:BAABNQAECoEcAAIMAAgKDxMlIQAcAgAMAAgKDxMlIQAcAgAAAA==.Liondori:BAAANQADCgYJBgAAAA==.Lipspire:BAAANQABCggICAAAAA==.Lissarael:BAAANQAECgcICwAAAA==.',
Lm='Lmj:BAAANQAECgIIBQAAAA==.',
Lo='Lockbox:BAABNQAECoEfAAMIAAgKryGAIQDLAgAIAAgKLR6AIQDLAgAaAAMKFSHaKQAWAQAAAA==.Lokmar:BAAANQADCgQIBAAAAA==.Loomin:BAABNQAECoEmAAMNAAkKbh7bRQDVAgANAAkKzBrbRQDVAgAWAAUKGRGpFAAeAQAAAA==.',
Lu='Lucatia:BAABNQAECoEcAAIYAAgKDB7bEADDAgAYAAgKDB7bEADDAgAAAA==.Luciaa:BAAANQADCgQIAgAAAA==.Lumièrevide:BAAANQADCgIIAgABNQAECgYIBgABAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgUICAAAAA==.',
['Lä']='Lädyæk:BAAANQAECgYIDgAAAA==.',
['Lí']='Líz:BAAANQAECgYIAQABNQAECgkJFwEgAAonAA==.',
Ma='Maekyss:BAAANQAECgcIDQAAAA==.Magezu:BAAANQAECgYIDgAAAA==.Maggarak:BAAANQAECgUIBgAAAA==.Magixstraza:BAABNQAECoEcAAINAAgK6hNIiAAwAgANAAgK6hNIiAAwAgAAAA==.Magwilddued:BAAANQADCgQIBQAAAA==.Mahmba:BAAANQAECgUIBQAAAA==.Malzel:BAAANQAECgcICwAAAA==.Mamasan:BAAANQAECgUIBQAAAA==.Mamor:BAAANQAECgIIAgAAAA==.Maphra:BAAANQAECgIJAgAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.Mastatracka:BAAANQAECgEIAQAAAA==.Mazethak:BAAANQADCgYIBgAAAA==.',
Md='Mdeow:BAAANQADCgUIBQAAAA==.',
Me='Mechabull:BAAANQABCgIIAgAAAA==.Meladys:BAAANQADCgUIBQAAAA==.Meleemeal:BAAANQAECgUIBQAAAA==.Melianthal:BAAANQADCgEIAQAAAA==.Melorac:BAAANQAECgIJAgAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQAECgYIDAAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQAECgIIAgAAAA==.',
Mi='Miakoda:BAAANQADCgQJBAABNQADCgYIBwABAAAAAA==.Micromortis:BAAANQAECgQJBAABNQAECgcICAABAAAAAA==.Mikuu:BAAANQAECgQICAAAAA==.Minouetoile:BAAANQADCgYIBgAAAA==.Misamane:BAAANQADCggIDAAAAA==.Mistdru:BAAANQADCgUIBQAAAA==.Mistical:BAAANQAECgcIEwAAAA==.Mitufu:BAAANQAECgEJAQAAAA==.',
Mm='Mmeow:BAAANQADCgUJBQAAAA==.',
Mo='Mogonn:BAAANQABCgEIAQAAAA==.Moonpiie:BAAANQADCgUIBQAAAA==.Morganya:BAABNQAECoEtAAMYAAkKXhnJEQC4AgAYAAkKXhnJEQC4AgAZAAEKAg6AcQA5AAAAAA==.Morgul:BAAANQAECgcICwAAAA==.Moriru:BAAANQAECgMIAwAAAA==.Morrtis:BAAANQADCgYIEwAAAA==.Morticas:BAAANQAECgMIAwAAAA==.Movechill:BAAANQADCggICAAAAA==.',
Ms='Mseow:BAAANQADCggIFgAAAA==.',
Mu='Mudbutbrooks:BAAANQAECgQIEQAAAA==.Muddbut:BAAANQADCgQIBAABNQAECgkJHgAQAG8XAA==.Muller:BAAANQAECgUIEAAAAA==.',
Mw='Mweow:BAAANQADCgYICwAAAA==.',
My='Mynnu:BAAANQAECgQICwAAAA==.Mynthara:BAAANQADCggIAgAAAA==.',
Na='Nautprepared:BAAANQAECgQICAAAAA==.',
Ne='Necrodancer:BAAANQAECggJAgAAAA==.Necrogore:BAAANQADCgcIBwAAAA==.Neeo:BAAANQADCgEJAQAAAA==.Neildasstysn:BAAANQAECgYICQABNQAECggIAwABAAAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neverdruid:BAAANQADCgEIAQAAAA==.Neveya:BAAANQADCgcIFgAAAA==.',
Ni='Nickeld:BAABNQAECoEaAAINAAgK7hvfWACjAgANAAgK7hvfWACjAgAAAA==.Nickhy:BAAANQAECgMIBAAAAA==.Nietherme:BAAANQAECgcIEAAAAA==.Nietheryew:BAAANQADCgIIAgAAAA==.Nihildicits:BAAANQADCgIIAgAAAA==.Nikkeld:BAAANQADCgIIAgAAAA==.Nitesblade:BAAANQAECgEIAQABNQAECgYIEgABAAAAAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Nofoamlatte:BAAANQADCgYIBgABNQAECgYIEQABAAAAAA==.Nolife:BAAANQADCgQIBAAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.',
Ny='Nyagosa:BAAANQAECgcJDAAAAA==.Nyalore:BAAANQAECgYIDwAAAA==.Nymesys:BAAANQADCgYIBgAAAA==.',
Ob='Obiwinonly:BAAANQAECgEIAQAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIAQAAAA==.',
Or='Oraedia:BAABNQAECoEpAAIQAAkKRRvmGQDkAgAQAAkKRRvmGQDkAgAAAA==.Oralen:BAABNQAECoEiAAMQAAkKySLhBQCHAwAQAAkKySLhBQCHAwAOAAIKbQ8aIAFtAAAAAA==.Orilitha:BAAANQADCgYIDAAAAA==.Orlandris:BAAANQADCgcIGAAAAA==.Orndaith:BAAANQAECggIDwAAAA==.',
Ov='Overloader:BAABNQAECoEWAAIZAAgKKh7nFAC4AgAZAAgKKh7nFAC4AgAAAA==.',
Ox='Oxkenpachixo:BAAANQADCgMIAwAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Pa='Pairodeez:BAAANQADCgMIAQAAAA==.Pallyaxe:BAAANQAECgQIBAABNQAECggIIgANAAIWAA==.Pandawannabe:BAAANQAECgEIAQAAAA==.Pandussi:BAABNQAECoEaAAIfAAkKXRO2GAAtAgAfAAkKXRO2GAAtAgAAAA==.Paneer:BAAANQAECggIBwAAAA==.Paninus:BAAANQAECgEIAQAAAA==.Papabair:BAAANQAECgcICAAAAA==.Papawheelie:BAAANQADCgcIBwAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Penta:BAAANQAECgIIAQAAAA==.Perfectplex:BAAANQABCgUIBQAAAA==.Peruano:BAABNQAECoEZAAIaAAgK+BKTCwAqAgAaAAgK+BKTCwAqAgAAAA==.Petforheals:BAAANQAECgUICwAAAA==.',
Ph='Phanchom:BAAANQADCgQICAAAAA==.Phyett:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Pi='Pietastegood:BAABNQAECoEeAAICAAgKTiOnHwAWAwACAAgKTiOnHwAWAwAAAA==.Pigbeniz:BAAANQABCgIIAgAAAA==.Pikaboom:BAAANQADCgYJBgABNQAECggICgABAAAAAA==.Pintsizemage:BAAANQADCgUIBQABNQAECgcICAABAAAAAA==.Pitchblack:BAAANQAECgQIBwAAAA==.',
Po='Pocahöntas:BAAANQAECgIIAgAAAA==.Pocketrocket:BAAANQADCgUIBgAAAA==.Ponce:BAABNQAECoEmAAIhAAkKQRvnBgDsAgAhAAkKQRvnBgDsAgAAAA==.Poordemon:BAAANQADCgUIBQABNQAECgcIGwASAH0GAA==.Popehealz:BAAANQADCgYJAQAAAA==.',
Pr='Predatori:BAAANQADCgIIAgAAAA==.Priestofholy:BAAANQADCgYIDQAAAA==.Provolonie:BAAANQADCggIDAAAAA==.Proñto:BAAANQAECggIAQAAAA==.Pryor:BAAANQADCgcICwAAAA==.Pròntò:BAAANQADCgQIBAABNQAECggIAQABAAAAAA==.Prõntõ:BAAANQADCgEIAQABNQAECggIAQABAAAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECggIHwACAJIZAA==.Punchbugman:BAAANQADCggIDAAAAA==.Puritos:BAAANQADCgcIBwAAAA==.Pustain:BAAANQABCggICgAAAA==.',
Py='Pymera:BAAANQAECgMICAAAAA==.Pyrista:BAAANQAECgUIDQAAAA==.',
Qd='Qdonis:BAAANQADCgMIAwABNQAECgkJIgAYAD4VAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAAANQAECggIEQAAAA==.Radilas:BAAANQABCgIIAgAAAA==.Radioatlarge:BAAANQAECgUIBQABNQAECggIHgACAE4jAA==.Raendarth:BAAANQAECgUICgAAAA==.Rageth:BAAANQAECgUICwAAAA==.Ragglefraggl:BAAANQADCgMIAwABNQAECgkJJwAMAG0gAA==.Rakalaag:BAEANQAECgQIBgAAAA==.Rakath:BAAANQAECgIIAgAAAA==.Ramidus:BAAANQAECgQIBgAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgcIDQAAAA==.',
Re='Reck:BAABNQAECoEfAAICAAgKkhlnTQBjAgACAAgKkhlnTQBjAgAAAA==.Redlands:BAAANQADCgQIBAAAAA==.Redredwine:BAAANQADCggICAAAAA==.Rejuve:BAAANQADCgYIBgAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Renwick:BAAANQAECgEIAQABNQAFFAUIDQAHAKcTAA==.Restlece:BAAANQABCgEIAQAAAA==.Reunach:BAAANQAECgYIDAAAAA==.',
Rh='Rhahirn:BAAANQAECgMIAwAAAA==.Rhialto:BAAANQADCgIJAgAAAA==.Rhinopill:BAAANQAECgUIBQABNQAECgkJJwAMAG0gAA==.Rhyzand:BAAANQADCgQIBwAAAA==.',
Ri='Riasg:BAAANQADCgIIAgAAAA==.Rickilake:BAAANQADCggIIAAAAA==.Ricksanchez:BAAANQAECgYIDQAAAA==.Rinik:BAAANQAECgYIDwAAAA==.Riptiide:BAAANQADCgcIBwABNQADCggIDgABAAAAAA==.Rivendra:BAAANQADCggJGAAAAA==.Riverpixie:BAAANQADCgQIBAAAAA==.',
Ro='Rockabye:BAAANQAECgYIEAAAAA==.Rokar:BAAANQADCgEIAQAAAA==.Rosannas:BAAANQADCgYIDAABNQAECgkJJwAMAG0gAA==.Rosi:BAAANQADCggICAAAAA==.Royallz:BAAANQAECgIIAgAAAA==.',
Ru='Rudeknees:BAACNQAFFIEGAAIDAAMKnBBaEADxAAADAAMKnBBaEADxAAA1AAQKgSwAAwMACQqfFv0wAHQCAAMACQqfFv0wAHQCACEABQp8AnsiALMAAAAA.Ruibash:BAEBNQAECoErAAIOAAkKriA4FwBDAwAOAAkKriA4FwBDAwAAAA==.Rukie:BAAANQADCgYICAAAAA==.Runebladé:BAAANQAECgYIDwAAAA==.',
Ry='Ryuu:BAAANQADCggIDAAAAA==.Ryuuzen:BAAANQAECgEIAQABNQAECgMICAABAAAAAA==.',
Sa='Sabitha:BAAANQAECgEIAQAAAA==.Sableanne:BAAANQADCgEIAQAAAA==.Sacklunch:BAAANQADCgEIAQAAAA==.Sacredkhaos:BAAANQADCgQJBAABNQADCgQIBQABAAAAAA==.Sacredknight:BAAANQADCgQIBQAAAA==.Saikoumaster:BAAANQAECgEIAQAAAA==.Saintkhaos:BAAANQADCgIIAgABNQADCgQIBQABAAAAAA==.Sakuraa:BAAANQAECggIEAAAAA==.Samisra:BAAANQADCgYJBgAAAA==.Sarajean:BAAANQAECgEIAQAAAA==.Savaged:BAAANQADCgcIDAABNQAECggIKAASAHYYAA==.Savajed:BAABNQAECoEoAAMSAAgKdhgQKABHAgASAAgKdhgQKABHAgAiAAYKwArTRQApAQAAAA==.Savaragon:BAAANQADCgYIDgABNQAECggIKAASAHYYAA==.Sazbena:BAAANQADCgQIBAAAAA==.',
Sc='Scallywagg:BAAANQADCggICQAAAA==.Scarletmatch:BAAANQAECgIIAgAAAA==.Scroto:BAAANQAECgEIAQAAAA==.',
Se='Searcomic:BAAANQAECgYIDgAAAA==.Secondwall:BAAANQADCgMIAwAAAA==.Seldav:BAABNQAECoEnAAMdAAkKPRhQBACJAgAdAAkKPRhQBACJAgAjAAMKWQpmKACgAAAAAA==.Selendas:BAAANQADCgcICwAAAA==.Selessa:BAAANQADCggICgAAAA==.Selinathra:BAAANQAECgIIAgAAAA==.Selm:BAABNQAECoEcAAIFAAgKySLdAwAsAwAFAAgKySLdAwAsAwAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBQAAAA==.Shaleka:BAAANQADCgUICAABNQADCgYIEAABAAAAAA==.Shaluesta:BAAANQADCgcICgAAAA==.Shamanism:BAAANQAECgQJBwAAAA==.Shameless:BAAANQAECgYICgAAAA==.Shamwów:BAAANQAECgcIEQAAAA==.Sharco:BAABNQAECoEVAAIWAAYKlR9aCQDtAQAWAAYKlR9aCQDtAQAAAA==.Sharkbites:BAAANQAECgUICQAAAA==.Shawarmafury:BAABNQAECoEnAAIVAAkK4CYIAQDwAwAVAAkK4CYIAQDwAwAAAA==.Shaydens:BAAANQADCgEIAQAAAA==.Shettani:BAAANQABCgYJCQAAAA==.Shiirou:BAAANQADCgQIBAAAAA==.Shockrasta:BAAANQADCgUJBQABNQAECggIIAANADIgAA==.Shooshmael:BAABNQAECoEbAAIDAAgKJRWGPgAxAgADAAgKJRWGPgAxAgAAAA==.Shozo:BAAANQADCgUICAABNQAECggIHAAFAMkiAA==.Shujáa:BAAANQAECgYIBwAAAA==.Shælynne:BAAANQABCgIIAgABNQAECgkJLQAYAF4ZAA==.Shékinah:BAABNQAECoElAAIkAAkKfw49MQARAgAkAAkKfw49MQARAgAAAA==.',
Si='Sidesteppin:BAAANQADCgUICAAAAA==.Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQAECgMIAwAAAA==.Sinthein:BAAANQAECgMIBQABNQAFFAUIDQAHAKcTAA==.Sixséven:BAAANQADCgIIAQABNQADCgYIBgABAAAAAA==.',
Sk='Skadgrip:BAAANQADCgUIBQABNQAECgcICwABAAAAAA==.Skorpekh:BAABNQAECoEZAAIVAAgK4wYhfgCxAQAVAAgK4wYhfgCxAQAAAA==.Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgQICgAAAA==.',
Sl='Sleepingsun:BAAANQAECgcIEgAAAA==.Sloppyspikes:BAAANQAECgYIDwAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smashdocta:BAABNQAECoEVAAICAAcK1xXZbgD5AQACAAcK1xXZbgD5AQABNQAECgkJJAAVADAhAA==.Smidgenn:BAAANQADCgcIDAAAAA==.Smokyblast:BAAANQAECgUICQAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCgcIEAAAAA==.Sneakgooner:BAAANQADCgcIBwAAAA==.Snowball:BAABNQAECoEsAAINAAcKGAXF8wBRAQANAAcKGAXF8wBRAQAAAA==.',
So='Sohtan:BAAANQADCgQIBAAAAA==.Sonbrandt:BAAANQAECgYIDQAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgQIDAAAAA==.',
Sp='Sparowprince:BAABNQAECoEyAAIOAAkK2SOgCQCZAwAOAAkK2SOgCQCZAwAAAA==.Speccurious:BAAANQADCgYIBwABNQADCgcIBwABAAAAAA==.Spectraleye:BAAANQAECgcIDgAAAA==.Sproocherlou:BAABNQAECoEaAAIOAAkKRRU0UwBKAgAOAAkKRRU0UwBKAgAAAA==.Sprour:BAAANQAECgYJCAAAAA==.',
St='Stankbolt:BAAANQAECgUICwAAAA==.Steezya:BAAANQAECgUIDgAAAA==.Stegulos:BAAANQABCgEJAQABNQABCgIIAwABAAAAAA==.Stellarum:BAAANQAECgMIAwAAAA==.Stormsy:BAAANQAECgQIBAABNQAECgcIEwABAAAAAA==.Stormykitty:BAAANQAECgcIEwAAAA==.Strauch:BAAANQADCgcIDgAAAA==.Striderdh:BAAANQABCggIDgAAAA==.Strongwoman:BAAANQAECgQICQAAAA==.Sturtza:BAABNQAECoEqAAIVAAkKoB+MEwAnAwAVAAkKoB+MEwAnAwAAAA==.Sturtzam:BAAANQADCgUJBQABNQAECgkJKgAVAKAfAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Sunbear:BAAANQADCgYICAAAAA==.Suun:BAABNQAECoEgAAIOAAgKExv5SgBlAgAOAAgKExv5SgBlAgAAAA==.',
Sw='Swampassuti:BAAANQAECgEIAQAAAA==.Swoley:BAAANQAECgYIEAAAAA==.',
Sy='Sybelada:BAAANQABCgcJCQAAAA==.Sylphia:BAAANQADCgYIBgAAAA==.Syrina:BAAANQADCgQIBAAAAA==.',
Ta='Taanua:BAAANQADCgYIBgAAAA==.Taelandas:BAAANQADCgQIEAAAAA==.Tagobeets:BAABNQAECoEbAAIWAAgKJgynCgDJAQAWAAgKJgynCgDJAQAAAA==.Tailyn:BAAANQADCgUIBQAAAA==.Taleiya:BAAANQAECgIICQAAAA==.Talisaie:BAAANQAECgQIBQABNQAFFAQIBwAZAPoYAA==.Tanisatharae:BAAANQADCgYIDgABNQAECgMICAABAAAAAA==.Tarahly:BAAANQAECgYIBgAAAA==.Tarahse:BAAANQADCgIIAgABNQAECgYIBgABAAAAAA==.Taron:BAAANQAECgUICgAAAA==.Tart:BAABNQAECoEXAAIDAAkKOxDdQAAnAgADAAkKOxDdQAAnAgABNQAFFAMIBgANAA4QAA==.',
Te='Tedjones:BAAANQAECgQJBgAAAA==.Temupeggy:BAAANQADCgEIAQAAAA==.',
Tg='Tgbird:BAAANQADCgQIBAAAAA==.',
Th='Thehumanatee:BAABNQAECoEYAAIkAAcKtBbSNgDoAQAkAAcKtBbSNgDoAQAAAA==.Thersh:BAAANQADCgMJAwAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thiccims:BAAANQADCgIIAgABNQAECggICgABAAAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingytoo:BAAANQAECgIIAgAAAA==.Thiqq:BAAANQADCggICAAAAA==.Thrallsballs:BAAANQADCgMIAwABNQAECggIFgAZACoeAA==.Threlindrier:BAAANQADCgYICAAAAA==.Throbinggimp:BAAANQADCggICAAAAA==.Thunderzelly:BAAANQADCgcIBwAAAA==.Thurien:BAAANQAECgUIBQAAAA==.Thyphlo:BAAANQAECgMIBQAAAA==.',
Ti='Tiltawhirl:BAAANQAECggICAAAAA==.Tiltedup:BAABNQAECoEZAAINAAgKRBDVogDzAQANAAgKRBDVogDzAQAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Tinkerßell:BAAANQADCgUIBQABNQAECgcIEwABAAAAAA==.Tirich:BAAANQADCggICAABNQAFFAUIDQAHAKcTAA==.Titaintium:BAAANQAECgQIBAABNQAECggIFgAZACoeAA==.',
To='Toshi:BAAANQAECgcIDQAAAA==.Totemtree:BAAANQADCgMIAwABNQAECgYIEwABAAAAAA==.',
Tr='Trustmei:BAAANQAECggICgAAAA==.Trystin:BAAANQAECgIIAgAAAA==.',
Tu='Tullydin:BAAANQAECgYIDwAAAA==.Tullyy:BAAANQAECgMIAwAAAA==.Tums:BAABNQAECoEZAAMHAAcK/ht6EgA7AgAHAAcK/ht6EgA7AgAMAAEKbhHgcABBAAAAAA==.',
Tw='Twirls:BAABNQAECoEXAAIgAAcKKxrBDADxAQAgAAcKKxrBDADxAQAAAA==.Twistoffate:BAAANQAECgIIBgAAAA==.',
Ty='Tyerant:BAAANQADCgMIAgAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Un='Uncanny:BAAANQABCgIIAwAAAA==.',
Ur='Urtle:BAAANQADCggIFAAAAA==.',
Us='Uselece:BAABNQAECoEaAAMOAAgKsh1LSABvAgAOAAgKsh1LSABvAgAPAAMKMwvmQwCIAAAAAA==.',
Ut='Uthadandewey:BAAANQADCgcIBwAAAA==.',
Uz='Uzainbolt:BAAANQAECgYICwAAAA==.',
Va='Valgorr:BAAANQAECgMIAgAAAA==.Valvalon:BAAANQAECgcIEgAAAA==.Vandil:BAAANQADCgYIBgAAAA==.',
Ve='Veelaria:BAAANQAECgcIEwAAAA==.Vegetablue:BAAANQAECgEIAQAAAA==.Verahardyr:BAAANQADCgIIAgAAAA==.Veravulp:BAAANQAECgEIAQAAAA==.Vet:BAAANQAECgQIBwAAAA==.',
Vh='Vhelithiana:BAAANQADCgYIFwAAAA==.',
Vi='Viathun:BAAANQADCggICAABNQAECggIKAASAHYYAA==.Vicalaus:BAABNQAECoEcAAIiAAcKMxxKIAA6AgAiAAcKMxxKIAA6AgABNQAECgkJIgAYAD4VAA==.View:BAABNQAECoEXAAIEAAkK+hJ2PgAcAgAEAAkK+hJ2PgAcAgAAAA==.Vikcy:BAAANQAECgIIAgAAAA==.Vilified:BAAANQADCggIEwAAAA==.Vitros:BAAANQADCgcIBwABNQAECggIFwAJANkWAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQAECgcIDwABAAAAAA==.Voidwitch:BAAANQAECgUIBwAAAA==.Volstagg:BAAANQADCgMIAwAAAA==.',
Vr='Vrakken:BAAANQAECgQICQAAAA==.',
Vy='Vyndenus:BAABNQAECoEhAAIKAAkKrRRmLwBpAgAKAAkKrRRmLwBpAgAAAA==.',
Wa='Warriorluv:BAAANQADCgEIAQAAAA==.Warrwing:BAAANQADCgcJBwAAAA==.',
We='Webbfury:BAAANQAECgcICAAAAA==.Wespoo:BAAANQAECgQIBQAAAA==.Wetpug:BAAANQADCggIDAAAAA==.',
Wh='Wheremytotem:BAAANQADCgcIBwABNQAECgkJHgAQAG8XAA==.Wholephister:BAAANQAECgEIAQABNQAECgQICgABAAAAAA==.Whupsmarse:BAAANQADCgcIDQAAAA==.',
Wi='Wickin:BAAANQADCggIDAAAAA==.Wifeyaggroed:BAAANQAECgMIAwAAAA==.Wiggles:BAAANQABCgEIAQAAAA==.Wiglock:BAAANQADCgQIBAAAAA==.Wigpetval:BAABNQAECoEYAAIVAAYKYRW0gQCoAQAVAAYKYRW0gQCoAQAAAA==.Wiidge:BAAANQAECgUICgAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQAECgMIBQAAAA==.Winterbane:BAAANQAECgQIBAAAAA==.',
Wo='Wocky:BAAANQAECgUIDwAAAA==.Wolfchan:BAAANQADCggIDQAAAA==.Wolfmeow:BAAANQADCgMIAwABNQAECgkJIgAYAD4VAA==.Worldcrafter:BAAANQAECgUIBwAAAA==.Worldender:BAAANQAECgQJCQAAAA==.',
Wr='Wrathofdawn:BAAANQAECgEIAQAAAA==.Wreckross:BAAANQABCgUIBQAAAA==.',
Xa='Xantry:BAABNQAECoEbAAIOAAkK6CLrHAAkAwAOAAkK6CLrHAAkAwAAAA==.',
Xm='Xmen:BAAANQAECggIAwAAAA==.',
Xu='Xurkitree:BAAANQADCgQIBAAAAA==.',
Xy='Xymm:BAAANQADCgcIEAAAAA==.',
Ye='Yeastybush:BAABNQAECoEfAAIEAAkKNx1TFwDoAgAEAAkKNx1TFwDoAgAAAA==.',
Ys='Yseeraa:BAAANQAECgEIAQAAAA==.',
Za='Zalatoes:BAAANQADCggIIQAAAA==.Zarathea:BAAANQADCggICAABNQAECgQIAwABAAAAAA==.',
Zi='Zilphah:BAAANQADCgMIAwAAAA==.Zimmerwitch:BAAANQADCggJDgAAAA==.Zimms:BAABNQAECoEaAAIfAAkK3xyECgD/AgAfAAkK3xyECgD/AgAAAA==.',
Zo='Zoeyredbird:BAAANQAECgcICwAAAA==.Zongo:BAAANQADCgcIBwAAAA==.',
Zw='Zwhitty:BAAANQADCgcJCQAAAA==.',
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
