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

local lookup = {'Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Druid-Guardian','Unknown-Unknown','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Demonology','Paladin-Holy','Priest-Holy','Paladin-Retribution','Hunter-BeastMastery','Mage-Frost','Druid-Feral','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Destruction','Warlock-Affliction','Monk-Mistweaver','Evoker-Augmentation','Monk-Windwalker','Hunter-Marksmanship','Shaman-Enhancement','DeathKnight-Frost','Evoker-Devastation','Druid-Balance',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aamara:BAAANQAECgQJCAAAAA==.',
Ab='Aboyton:BAAANQADCgUJCgAAAA==.',
Ad='Adhpally:BAAANQADCgIIAgABNQAECgkJGwABAHIeAA==.',
Ae='Aefarshammy:BAABNQAECoEcAAMCAAgKvCTuOQAUAgACAAUKhSTuOQAUAgADAAgKLxR4OwACAgAAAA==.Aelistiah:BAAANQABCggJEgAAAA==.Aerithorn:BAABNQAECoEYAAIEAAcKyR90BgCDAgAEAAcKyR90BgCDAgAAAA==.',
Ah='Aheck:BAAANQADCgMJAwABNQAECgYJDAAFAAAAAA==.Ahleya:BAAANQAECgQIBAAAAA==.Ahlonaa:BAAANQADCggJDQAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgQJCgAFAAAAAA==.',
Ak='Akoris:BAAANQADCgcICQABNQAECgYICgAFAAAAAA==.Akorys:BAAANQAECgYICgAAAA==.',
Al='Albyno:BAABNQAECoEXAAIGAAkKuBT4DwBZAgAGAAkKuBT4DwBZAgAAAA==.',
Am='Amara:BAAANQADCgUIEAAAAA==.Ambitionz:BAAANQADCgEIAQAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAAANQAECgQIBwAAAA==.Ancksunamun:BAAANQADCgQJBAAAAA==.Andromedia:BAAANQADCgYIBgABNQAECgQJCAAFAAAAAA==.Anicarcia:BAAANQADCgQIBAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAACNQAFFIEIAAIHAAQK1hDvBABjAQAHAAQK1hDvBABjAQA1AAQKgRcAAgcACQqLHqQEACwDAAcACQqLHqQEACwDAAAA.',
Aq='Aquua:BAAANQAECgYIDwAAAA==.',
Ar='Araelen:BAAANQAECgUJBQAAAA==.Arcticdps:BAAANQAECggIEQAAAA==.Ariastel:BAAANQABCgIIAgAAAA==.Ariell:BAAANQAECgcIDQAAAA==.Ariestar:BAAANQAECgUIBQAAAA==.Ariiel:BAAANQADCggICQABNQAECgcIDQAFAAAAAA==.Arthimas:BAAANQAECgIJAgAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQAECggJBwAAAA==.Ashelash:BAAANQAECgIJBAAAAA==.Asidize:BAAANQADCggIEQAAAA==.Aslor:BAAANQAECgUIDAAAAA==.Aspenoa:BAAANQADCggICAAAAA==.Asralia:BAAANQADCgMJAwAAAA==.',
At='Athalia:BAABNQAECoEfAAIIAAkKdx9PBQA/AwAIAAkKdx9PBQA/AwAAAA==.',
Au='Aug:BAAANQAECgQIBwAAAA==.',
Av='Avaldra:BAAANQABCgEIAQAAAA==.Avex:BAAANQAECgYJDAAAAA==.',
Ax='Axemage:BAABNQAECoEbAAIJAAgKkxPQcQA+AgAJAAgKkxPQcQA+AgAAAA==.Axeom:BAABNQAECoEeAAIDAAcKOhomNQAgAgADAAcKOhomNQAgAgAAAA==.Axeshammy:BAAANQADCggICwABNQAECggJGwAJAJMTAA==.',
Az='Azmodan:BAAANQAECgEIAQAAAA==.Azzith:BAAANQAECgYICQAAAA==.',
Ba='Bahgeye:BAAANQADCgUIBQAAAA==.Bajaladin:BAAANQAECgQJCQAAAA==.Barometer:BAAANQAECgUICQAAAA==.Bast:BAAANQADCggICwABNQAECgMJBgAFAAAAAA==.Baxa:BAAANQADCgYJDAAAAA==.Baylee:BAAANQAECgQIDgAAAA==.',
Bb='Bbartemis:BAAANQADCggICgAAAA==.',
Be='Bearaqobama:BAAANQADCgYIBgAAAA==.Bearlyalivee:BAAANQADCgUJCQABNQAECgIJAwAFAAAAAA==.Bearvul:BAAANQABCgEIAQAAAA==.Beekerr:BAAANQADCgMIAwABNQAECgYIEwAFAAAAAA==.Belbroon:BAAANQADCgQIBAAAAA==.Beliele:BAAANQAECgQJBAAAAA==.Benjohnbo:BAAANQABCgEIAQAAAA==.Benwins:BAAANQAECgEJAgAAAA==.Bergamö:BAAANQADCgcICQABNQAECgIIAwAFAAAAAA==.Bernecessity:BAAANQADCggJGwAAAA==.',
Bh='Bho:BAAANQADCgUIBQAAAA==.',
Bi='Biffedit:BAAANQADCgcIBwAAAA==.Bis:BAAANQADCgEJAgAAAA==.Biscuitbabe:BAAANQAECgYIDQAAAA==.Bisholoyd:BAAANQAECgIIAgAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blastoise:BAABNQAECoEVAAMKAAgK2B0OGgCHAgAKAAcK3CAOGgCHAgALAAYKgRAZTQBOAQAAAA==.Blinktwice:BAAANQABCgcIBwAAAA==.Blizfishleg:BAAANQADCgcICAAAAA==.Bllur:BAAANQADCgIIAgAAAA==.Bloodroots:BAAANQAECgMIBwAAAA==.Bluur:BAAANQADCgYIBgAAAA==.',
Bo='Bonehacker:BAAANQABCgUIBwAAAA==.Boombóx:BAAANQADCgUJBQABNQAECggIGQAMAIQhAA==.Boostia:BAAANQADCgEIAQAAAA==.Borthos:BAAANQAECgYIDgAAAA==.Bowsback:BAAANQADCgYIEQAAAA==.Bowyohead:BAAANQAECgcJBwABNQAECgkJHAANAG8XAA==.',
Br='Brandoe:BAAANQAECgQIBQAAAA==.Breece:BAAANQADCgUIBQAAAA==.Brickinkeys:BAAANQADCgYIBgABNQAECgQJCAAFAAAAAA==.Brightmare:BAAANQADCgYICwAAAA==.Brusa:BAAANQADCgEJAQAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAAANQAECgYICgAAAA==.',
Ca='Caadra:BAAANQADCgIIAgAAAA==.Caimie:BAAANQAECgIJAgAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQAECgQJBgAAAA==.Cassiaan:BAAANQADCggIDgAAAA==.Caylavibes:BAABNQAECoEXAAIOAAkKdhB/LwA5AgAOAAkKdhB/LwA5AgAAAA==.',
Ch='Chaviel:BAAANQAECgcJBwAAAA==.Cheetasista:BAAANQADCgQJBAAAAA==.Cherry:BAAANQAECgEIAQAAAA==.Chironn:BAAANQAECgYJEQAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQAECgMIAwAAAA==.',
Ci='Cinderburn:BAAANQAECgEIAQAAAA==.Cinderkai:BAAANQADCgEIAQAAAA==.',
Cl='Clayshaper:BAAANQADCgYIDAAAAA==.Clohhe:BAAANQAECgEJAQAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQADCgEIAQAAAA==.Comfychair:BAAANQAECgEJAQAAAA==.Conclaved:BAAANQADCgMIAwAAAA==.Coowmoo:BAAANQAECgQIBwAAAA==.Cosmochopper:BAAANQAECgEIAQABNQAECgcJCgAFAAAAAA==.Cosmoshotter:BAAANQAECgcJCgAAAA==.',
Cr='Craterstab:BAAANQADCgEIAQAAAA==.Cremebrule:BAAANQADCggIFgAAAA==.Critnyspears:BAAANQAECgIIBgAAAA==.Crushleaf:BAAANQADCggICwAAAA==.',
Cu='Cucubau:BAAANQADCgcIBwAAAA==.',
Cy='Cyndra:BAAANQADCgIIAgAAAA==.',
Da='Dallthyrian:BAAANQADCgYIBgABNQAECgUIBwAFAAAAAA==.Dalthyrian:BAAANQAECgQIBAABNQAECgUIBwAFAAAAAA==.Dalthyriian:BAAANQAECgUIBwAAAA==.Dalthyrrian:BAAANQAECgEJAQABNQAECgUIBwAFAAAAAA==.Dalthyyrian:BAAANQAECgQIBAABNQAECgUIBwAFAAAAAA==.Damii:BAAANQADCgMIBAAAAA==.Danfarm:BAAANQADCgEIAQAAAA==.Dargonbref:BAAANQADCgUIAQABNQAECgQICQAFAAAAAA==.Darjen:BAAANQAECgIJAgAAAA==.Darkjestêr:BAAANQADCgUIBQAAAA==.Daysfox:BAAANQAECgYICQAAAA==.Daysmonk:BAAANQADCgYIBgAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deahtlyx:BAAANQADCgQIBAABNQAECggIGAAIAPkXAA==.Deathfang:BAAANQADCgUICgAAAA==.Deathlyy:BAABNQAECoEYAAMIAAgK+RdDGQAjAgAIAAcKIBlDGQAjAgAHAAQKOwqELQDyAAAAAA==.Deathmatch:BAAANQAECgEIAQAAAA==.Deathstone:BAAANQAECgYICAABNQAECgkJKgAPAEUiAA==.Deathtress:BAAANQAECgMJAwAAAA==.Debbydowner:BAAANQAECgUICwAAAA==.Decado:BAAANQAECgMJBgAAAA==.Deemwins:BAAANQADCgYIBwAAAA==.Dejevoid:BAAANQAECgYJCQAAAA==.Delidyr:BAAANQADCgcJCAAAAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEANQAECgUIDwAAAA==.Denwere:BAAANQADCgMIAwAAAA==.Deww:BAAANQAECgYICgAAAA==.',
Dh='Dhawk:BAAANQADCggIFAAAAA==.Dhelilha:BAAANQAECgcIEwAAAA==.',
Dk='Dkalliru:BAAANQAECgYIDwAAAA==.',
Do='Docdolittle:BAABNQAECoEbAAIQAAgKOCJjEgAQAwAQAAgKOCJjEgAQAwAAAA==.Docfreez:BAABNQAECoEZAAMJAAgKAR2IbQBKAgAJAAcKcxuIbQBKAgARAAIKHx+dGgCsAAAAAA==.Docragosa:BAAANQAECgMIBAABNQAECgYJBwAFAAAAAA==.Doctafury:BAAANQAECgYIDAABNQAECggIGwAQADgiAA==.Doctermoo:BAAANQAECgEJAQAAAA==.Doomhamer:BAAANQADCggICAABNQAECgYIDgAFAAAAAA==.Doraemee:BAAANQAECgIIAgAAAA==.',
Dr='Drbaconbrgr:BAAANQAECgUICgABNQAECgYIDgAFAAAAAA==.Drbakedziti:BAAANQADCgYIBgABNQAECgYIDgAFAAAAAA==.Drbaobuns:BAAANQAECgUIBQABNQAECgYIDgAFAAAAAA==.Drcarrotcake:BAAANQADCggIDgABNQAECgYIDgAFAAAAAA==.Drcheeseball:BAAANQAECgUIBQABNQAECgYIDgAFAAAAAA==.Dreggsalad:BAAANQAECgUJBQABNQAECgYIDgAFAAAAAA==.Dreima:BAAANQAECgMJAwAAAA==.Drfriedrice:BAAANQADCgEJAQABNQAECgYIDgAFAAAAAA==.Drgatorwine:BAAANQAECgQJBgABNQAECgYIDgAFAAAAAA==.Drhashbrowns:BAAANQAECgIIAgABNQAECgYIDgAFAAAAAA==.Drkimchirice:BAABNQAECoEWAAISAAcKACRVBADQAgASAAcKACRVBADQAgABNQAECgYIDgAFAAAAAA==.Drmacncheese:BAAANQAECgQICwABNQAECgYIDgAFAAAAAA==.Drpumpkinpie:BAAANQAECgYIBgABNQAECgYIDgAFAAAAAA==.Drshephardpi:BAAANQADCggICgABNQAECgYIDgAFAAAAAA==.Druiddres:BAAANQAECgQIBAAAAA==.Druidussy:BAAANQADCggICAAAAA==.Drwontonsoup:BAAANQAECgYIDgAAAA==.',
Du='Dummythicc:BAAANQADCgQIBAAAAA==.',
['Dö']='Dööku:BAAANQADCgYIBgAAAA==.',
Ei='Eighteen:BAABNQAECoEXAAIHAAgK6BhaDACBAgAHAAgK6BhaDACBAgAAAA==.',
Ek='Eksi:BAAANQAECgcIEQAAAA==.',
El='Elethe:BAAANQAECgIIAgABNQAFFAQICAAHANYQAA==.Elianx:BAAANQAECgIIAQAAAA==.Elzaine:BAAANQAECgMIBAAAAA==.',
Em='Embedded:BAAANQAECgQICQAAAA==.Eme:BAAANQADCgYJEgAAAA==.Emearq:BAAANQABCggICgAAAA==.Empress:BAAANQAECgYICQAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQADCgUICAABNQAECgcIEgAFAAAAAA==.Entrophi:BAAANQADCgMIAwAAAA==.',
Er='Erikaa:BAAANQADCgMIAwAAAA==.Erisnyx:BAAANQADCgIIAgAAAA==.',
Es='Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAQABNQAECgcIEgAFAAAAAA==.',
Ex='Excruciator:BAAANQAECgUJDQAAAA==.Exhumedraven:BAAANQADCgUJBQAAAA==.',
Fa='Falloutz:BAAANQADCggIHgAAAA==.Farahcanle:BAABNQAECoEaAAIEAAgK1wehFQAzAQAEAAgK1wehFQAzAQAAAA==.Farrock:BAAANQAECgUICQAAAA==.Fawxette:BAAANQADCggICAABNQAECgkJJAATAKYYAA==.',
Fe='Felanish:BAAANQAECgEIAQAAAA==.Felystia:BAAANQAECgEJAwAAAA==.Fenra:BAAANQADCgQIBAAAAA==.Feorblarir:BAAANQAECgEJAgAAAA==.Fernmister:BAAANQAECgIIAwAAAA==.',
Fi='Fieryfrost:BAAANQABCgQIBgABNQAECgMJBAAFAAAAAA==.Filledegel:BAAANQAECgQICQAAAA==.Finowscath:BAAANQAECgIJAgAAAA==.Firequencher:BAAANQAECgYIEgAAAA==.Fistacuffs:BAAANQADCgcJDwAAAA==.Fistdoc:BAAANQAECgYJBwAAAA==.Fistícuffs:BAAANQADCggIGgAAAA==.Fizzroll:BAAANQADCgYIEwAAAA==.Fié:BAAANQADCgYJDgABNQAECgkJJAATAKYYAA==.',
Fl='Flais:BAAANQAECgEIAQAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAABNQAECoEdAAIUAAgKLhDAIQAKAgAUAAgKLhDAIQAKAgABNQAECgkJJAATAKYYAA==.Foxybag:BAAANQADCgYIBgAAAA==.',
Fr='Friendlypal:BAAANQAECgYJCwAAAA==.Friendofbear:BAABNQAECoEaAAIQAAkKXBlqIQC1AgAQAAkKXBlqIQC1AgAAAA==.Fromabove:BAAANQADCgMIAwAAAA==.',
Fu='Furryfeet:BAAANQAECgMJBAAAAA==.Fuzywuzzy:BAAANQAECgYJDQAAAA==.Fuzzykuntz:BAAANQAECgUJCQAAAA==.',
Fy='Fynsdood:BAAANQAECgMJBAAAAA==.Fynslane:BAAANQADCgQIBAABNQAECgMJBAAFAAAAAA==.',
Ga='Gabelock:BAABNQAECoEjAAQMAAkKlCLiFQDmAgAMAAgKuSLiFQDmAgAVAAQKLhndJwATAQAWAAEK5hxUHwA/AAAAAA==.Gabemage:BAAANQAECgUICAAAAA==.Gala:BAAANQAECgIJAwAAAA==.Gasback:BAAANQADCgYJCwAAAA==.',
Gh='Gherkins:BAAANQADCgYICgAAAA==.Ghostreveri:BAAANQAECgUIBwAAAA==.',
Gi='Gigah:BAAANQAECgYJCQAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQAECgQJBgAAAA==.Glutebruiser:BAAANQAECgEJAQABNQAECgUJBwAFAAAAAA==.',
Gn='Gnomedguerre:BAAANQADCgYIDQAAAA==.',
Go='Gooseshift:BAAANQAECgEIAQAAAA==.Gouchh:BAAANQAECgEIAQAAAA==.',
Gr='Gravithel:BAAANQADCgYJDQAAAA==.Grayseer:BAABNQAECoEXAAIXAAgKVyJfBQAIAwAXAAgKVyJfBQAIAwAAAA==.Grimtree:BAAANQAECgUIDQAAAA==.Grindor:BAAANQADCgQIBAAAAA==.Grommel:BAAANQADCgUIBwAAAA==.Grumpstraza:BAAANQADCgcJDgAAAA==.Grumpydemon:BAABNQAECoEZAAITAAgKogxIIQDrAQATAAgKogxIIQDrAQAAAA==.Grymshot:BAAANQAECgIJAgAAAA==.',
Gw='Gwong:BAAANQADCgcIBwAAAA==.',
Ha='Haldril:BAEANQADCgYIBgABNQAECggIIgAPALsfAA==.Halfskul:BAABNQAECoEYAAILAAgK4gyANgDJAQALAAgK4gyANgDJAQAAAA==.Halotic:BAAANQADCggJCAAAAA==.Hashah:BAAANQAECgYIDwAAAA==.Hatefel:BAAANQAECgQJBAABNQAECgEIAgAFAAAAAA==.',
He='Healsgobrr:BAAANQADCgYICwABNQAECgkJHwAYADYXAA==.Healyaass:BAAANQADCgYICQAAAA==.Hecate:BAAANQADCgIIAgAAAA==.Helenfeller:BAAANQADCgEIBAAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgYIDwAFAAAAAA==.Hexlexxia:BAAANQADCggIDwABNQAECgQJCAAFAAAAAA==.Heyyboyy:BAAANQAECggJEQAAAA==.',
Ho='Holyaefar:BAAANQADCgQIBAABNQAECggIHAACALwkAA==.Holysab:BAAANQAECgIIBQAAAA==.Holysock:BAAANQADCggICAAAAA==.Holyyaii:BAAANQAECgEJAQAAAA==.Holz:BAAANQADCgcJEQAAAA==.',
Hu='Hugoman:BAAANQADCggJHgABNQAECgUJCwAFAAAAAA==.Huni:BAABNQAECoEbAAIDAAgKuB6PHgCdAgADAAgKuB6PHgCdAgAAAA==.Huupa:BAAANQADCgYIBgAAAA==.',
Hy='Hystaric:BAAANQADCgYIDAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ia='Iamyu:BAAANQAECgMIAgABNQAECgcICQAFAAAAAA==.',
Ib='Ibun:BAAANQAECgIIAwAAAA==.',
Ic='Icentheveins:BAABNQAECoEcAAINAAkKbxceHQCrAgANAAkKbxceHQCrAgAAAA==.',
Ig='Igneus:BAABNQAECoEaAAIJAAkKVSKrFwBaAwAJAAkKVSKrFwBaAwAAAA==.Igriz:BAAANQADCggJGwAAAA==.',
Ii='Iillil:BAABNQAECoEXAAITAAgKXgm6IwDTAQATAAgKXgm6IwDTAQAAAA==.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Imakeuflased:BAAANQADCgIIAgAAAA==.Immamoonchix:BAAANQADCgUICwAAAA==.Imthatguy:BAAANQADCgEIAQAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.Ironorchid:BAAANQADCgUJBQAAAA==.',
It='Itsjeff:BAAANQAECgUJBwAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jaeyk:BAAANQADCggIFwAAAA==.Jambonjay:BAAANQAECgQJEAAAAA==.Jananda:BAAANQADCgMIAwAAAA==.Jarnirdimli:BAAANQABCgQICgAAAA==.Jaywaz:BAAANQAECgUIBQAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgAAAA==.Jckjckjck:BAAANQADCgUIBQAAAA==.',
Je='Jermagedupri:BAACNQAFFIEHAAIJAAMKDA41GwDsAAAJAAMKDA41GwDsAAA1AAQKgSkAAgkACQr2ISgXAFwDAAkACQr2ISgXAFwDAAAA.Jessupy:BAAANQAECgUIBwAAAA==.Jezashi:BAAANQADCgUIBQAAAA==.',
Jh='Jhene:BAAANQAECgQIBAABNQAECgcJBwAFAAAAAA==.',
Jo='Johkneesinz:BAAANQADCgYICwAAAA==.Johntapper:BAAANQADCgIJAgAAAA==.Joshuå:BAAANQAECgQIBwAAAA==.',
Ju='Julieteshade:BAAANQADCgMJBAAAAA==.Junkbot:BAAANQADCgYIEAAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
['Jø']='Jøsh:BAAANQADCgQIBQAAAA==.',
Ka='Kaimingxiona:BAAANQADCggICAAAAA==.Kalrendion:BAAANQADCgMIAwABNQAECgQIBwAFAAAAAA==.Karaillyonna:BAAANQADCgIIAgABNQAECgQICQAFAAAAAA==.Karasu:BAAANQADCgcJGAAAAA==.Karliechirky:BAAANQADCgYIBgAAAA==.Kasher:BAAANQADCgYJCAAAAA==.Kayho:BAAANQAECgUJBwAAAA==.',
Ke='Kelltrax:BAAANQAECgIIAgAAAA==.Kelsier:BAABNQAECoEdAAMXAAgKvCOfBAAgAwAXAAgKvCOfBAAgAwAZAAUKqQRfNADAAAAAAA==.Keruilin:BAAANQADCgQIAgAAAA==.Kesk:BAAANQADCgUICAAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khela:BAAANQAECgIIAgAAAA==.Khendra:BAAANQAECgMJAgAAAA==.',
Ki='Kiezo:BAAANQAECgQICQAAAA==.Killachefd:BAAANQAECgYJCgAAAA==.Killamanjoro:BAABNQAECoEcAAIBAAgKWxzdQQBfAgABAAgKWxzdQQBfAgAAAA==.Kimchiwar:BAAANQAECgQJBAAAAA==.Kirasha:BAAANQADCgYJGwAAAA==.Kitak:BAAANQAECgQIBwAAAA==.Kitchenbound:BAAANQAECgUICQAAAA==.Kittychan:BAAANQAECgUJCwAAAA==.',
Kl='Klaacus:BAABNQAECoEbAAITAAgKCBO7GgAwAgATAAgKCBO7GgAwAgAAAA==.Kloex:BAAANQABCgIIAgAAAA==.',
Ko='Kokk:BAAANQADCgUIBQAAAA==.Koudelka:BAAANQAECgQJBAAAAA==.',
Kr='Kralok:BAAANQADCgYICwAAAA==.Krazm:BAAANQADCgMIAwAAAA==.Kriticál:BAAANQAECggJEQAAAA==.Krustyg:BAAANQADCgcIDAAAAA==.Krustym:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEANQAECgcJBgABNQAECggIIgAPALsfAA==.',
La='Lakshmi:BAAANQAECgQIBQABNQAECgQJCAAFAAAAAA==.Laradin:BAAANQADCgEJAQAAAA==.Larasimus:BAAANQADCgMJAwAAAA==.Larndorn:BAAANQADCgMIAwAAAA==.Lavagrip:BAAANQAECgQJCgAAAA==.',
Le='Lelou:BAACNQAFFIEGAAIQAAIKKySqCwDHAAAQAAIKKySqCwDHAAA1AAQKgScAAxAACQqdJggCAM4DABAACQqdJggCAM4DABoAAgo0FF5GAIsAAAAA.Letmehealu:BAAANQADCgEIAQAAAA==.Lewsky:BAAANQAECgEIAwABNQAECgkJGQAPANciAA==.',
Li='Lilathiaa:BAAANQADCgYIEQAAAA==.Lilru:BAAANQAECgEIAQAAAA==.Linddria:BAABNQAECoEVAAIIAAcKwBJrIADZAQAIAAcKwBJrIADZAQAAAA==.Liondori:BAAANQADCgYJBgAAAA==.Lipspire:BAAANQABCggICAAAAA==.Lissarael:BAAANQAECgYJCQAAAA==.',
Lm='Lmj:BAAANQAECgIIBQAAAA==.',
Lo='Lockbox:BAABNQAECoEZAAMMAAgKhCFBNABNAgAMAAYKUyFBNABNAgAVAAMKFSEZJgAeAQAAAA==.Loomin:BAABNQAECoEhAAMJAAkKoR3KNADvAgAJAAkK/xnKNADvAgARAAUKGRECEAAuAQAAAA==.',
Lu='Lucatia:BAAANQAECgcJEgAAAA==.Luciaa:BAAANQADCgQIAgAAAA==.Lumièrevide:BAAANQADCgIIAgABNQAECgQICQAFAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgUICAAAAA==.',
['Lä']='Lädyæk:BAAANQAECgUJCAAAAA==.',
['Lí']='Líz:BAAANQAECgYIAQAAAA==.',
Ma='Maekyss:BAAANQAECgcJDAAAAA==.Magezu:BAAANQAECgYIDgAAAA==.Maggarak:BAAANQAECgEJAQAAAA==.Magixstraza:BAABNQAECoEWAAIJAAgK3BHFeAAqAgAJAAgK3BHFeAAqAgAAAA==.Magwilddued:BAAANQADCgQIBQAAAA==.Mahmba:BAAANQAECgUIBQAAAA==.Malzel:BAAANQAECgYJCQAAAA==.Mamasan:BAAANQADCgcIDAAAAA==.Maphra:BAAANQAECgIJAgAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.Mastatracka:BAAANQADCgMIBQAAAA==.Mazethak:BAAANQADCgYIBgAAAA==.',
Md='Mdeow:BAAANQADCgUIBQAAAA==.',
Me='Mechabull:BAAANQABCgIIAgAAAA==.Meladys:BAAANQADCgUIBQAAAA==.Meleemeal:BAAANQADCgYIDAAAAA==.Melorac:BAAANQAECgIJAgAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQAECgUICAAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQAECgIIAgAAAA==.',
Mi='Miakoda:BAAANQADCgQJBAABNQADCgYIBwAFAAAAAA==.Micromortis:BAAANQAECgQJBAABNQAECgYJBwAFAAAAAA==.Mikuu:BAAANQAECgIJBAAAAA==.Minouetoile:BAAANQADCgYIBgAAAA==.Misamane:BAAANQADCggICgAAAA==.Mistdru:BAAANQADCgUIBQAAAA==.Mistical:BAAANQAECgYIDAAAAA==.Mitufu:BAAANQAECgEJAQAAAA==.',
Mm='Mmeow:BAAANQADCgUJBQAAAA==.',
Mo='Mogonn:BAAANQABCgEIAQAAAA==.Moonpiie:BAAANQADCgUIBQAAAA==.Morganya:BAABNQAECoEkAAMTAAkKphjZDgDJAgATAAkKphjZDgDJAgAUAAEKAg5OXwA7AAAAAA==.Morgul:BAAANQAECgYJCQAAAA==.Moriru:BAAANQAECgMIAwAAAA==.Morrtis:BAAANQADCgYIEwAAAA==.Morticas:BAAANQAECgMIAwAAAA==.',
Ms='Mseow:BAAANQADCggJFAAAAA==.',
Mu='Mudbutbrooks:BAAANQAECgQJDQAAAA==.Muddbut:BAAANQADCgQIBAABNQAECgkJHAANAG8XAA==.Muller:BAAANQAECgMICwAAAA==.',
Mw='Mweow:BAAANQADCgUJBQAAAA==.',
My='Mynnu:BAAANQAECgIJBwAAAA==.Mynthara:BAAANQADCggIAgAAAA==.',
Na='Nautprepared:BAAANQAECgQICAAAAA==.',
Ne='Necrodancer:BAAANQAECggJAgAAAA==.Necrogore:BAAANQADCgcIBwAAAA==.Neeo:BAAANQADCgEJAQAAAA==.Neildasstysn:BAAANQAECgYJCQAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neverdruid:BAAANQADCgEIAQAAAA==.Neveya:BAAANQADCgYIDwAAAA==.',
Ni='Nickeld:BAAANQAECgYIEAAAAA==.Nickhy:BAAANQAECgIIAgAAAA==.Nietherme:BAAANQAECgUJCgAAAA==.Nietheryew:BAAANQADCgIIAgAAAA==.Nikkeld:BAAANQADCgIIAgAAAA==.Nitesblade:BAAANQADCgEIAQABNQAECgYJDQAFAAAAAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Nolife:BAAANQADCgQIBAAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.',
Ny='Nyagosa:BAAANQAECgcJDAAAAA==.Nyalore:BAAANQAECgUJCQAAAA==.',
Ob='Obiwinonly:BAAANQADCgIIAgAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIAQAAAA==.',
Or='Oraedia:BAABNQAECoEZAAINAAkKARkGGADOAgANAAkKARkGGADOAgAAAA==.Oralen:BAABNQAECoEfAAMNAAkK0CFZBgBxAwANAAkK0CFZBgBxAwAPAAIKbQ+h8wBxAAAAAA==.Orilitha:BAAANQADCgYIDAAAAA==.Orlandris:BAAANQADCgUIDQAAAA==.Orndaith:BAAANQAECggJDAAAAA==.',
Ov='Overloader:BAAANQAECgcJDQAAAA==.',
Ox='Oxkenpachixo:BAAANQADCgMIAwAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Pa='Pairodeez:BAAANQADCgMIAQAAAA==.Pallyaxe:BAAANQADCggICQABNQAECggJGwAJAJMTAA==.Pandawannabe:BAAANQAECgEIAQAAAA==.Pandussi:BAABNQAECoEWAAIZAAkKQxApFgAXAgAZAAkKQxApFgAXAgAAAA==.Paneer:BAAANQADCggJCAABNQAECgYICAAFAAAAAA==.Paninus:BAAANQAECgEJAQAAAA==.Papabair:BAAANQAECgIIAgABNQAECgYJBwAFAAAAAA==.Papawheelie:BAAANQADCgcIBwAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Perfectplex:BAAANQABCgUIBQAAAA==.Peruano:BAAANQAECgcIEAAAAA==.Petforheals:BAAANQAECgUJCwAAAA==.',
Ph='Phanchom:BAAANQADCgQJBAAAAA==.Phyett:BAAANQADCgEIAQABNQAECgEIAQAFAAAAAA==.',
Pi='Pietastegood:BAABNQAECoEZAAIBAAgKkyACJgDZAgABAAgKkyACJgDZAgAAAA==.Pigbeniz:BAAANQABCgIIAgAAAA==.Pikaboom:BAAANQADCgYJBgABNQAECgcJBwAFAAAAAA==.Pintsizemage:BAAANQADCgUIBQABNQAECgYJBwAFAAAAAA==.Pitchblack:BAAANQAECgQJAwAAAA==.',
Po='Pocahöntas:BAAANQADCgUIBQAAAA==.Pocketrocket:BAAANQADCgUIBgAAAA==.Ponce:BAABNQAECoEeAAIbAAgKXhygBwC2AgAbAAgKXhygBwC2AgAAAA==.Poordemon:BAAANQADCgUIBQAAAA==.Popehealz:BAAANQADCgYJAQAAAA==.',
Pr='Predatori:BAAANQADCgIIAgAAAA==.Priestofholy:BAAANQADCgYIDQAAAA==.Provolonie:BAAANQADCggIDAAAAA==.Proñto:BAAANQAECgEIAQABNQAECgYJEgAFAAAAAA==.Pryor:BAAANQADCgcIBwAAAA==.Pròntò:BAAANQADCgQIBAABNQAECgYJEgAFAAAAAA==.Prõntõ:BAAANQADCgEIAQABNQAECgYJEgAFAAAAAA==.Prøntø:BAAANQAECgYJEgAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECggIGAABAC4XAA==.Punchbugman:BAAANQADCggIDAAAAA==.Puritos:BAAANQADCgcIBwAAAA==.Pustain:BAAANQABCggICgAAAA==.',
Py='Pymera:BAAANQAECgMJBQAAAA==.Pyrista:BAAANQAECgUJCAAAAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAAANQAECgYIBwAAAA==.Radilas:BAAANQABCgIIAgAAAA==.Radioatlarge:BAAANQADCgUIBQABNQAECggIGQABAJMgAA==.Raendarth:BAAANQAECgMJBQAAAA==.Rageth:BAAANQAECgUICwAAAA==.Rakalaag:BAEANQAECgQIBAAAAA==.Rakath:BAAANQAECgEIAQAAAA==.Ramidus:BAAANQAECgQIBgAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgcIDQAAAA==.',
Re='Reck:BAABNQAECoEYAAIBAAgKLhfRSABFAgABAAgKLhfRSABFAgAAAA==.Redlands:BAAANQABCgQJAgAAAA==.Rejuve:BAAANQADCgYIBgAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Renwick:BAAANQAECgEIAQABNQAFFAQICAAHANYQAA==.Restlece:BAAANQABCgEIAQAAAA==.Reunach:BAAANQAECgUICwAAAA==.',
Rh='Rhahirn:BAAANQAECgMJAwAAAA==.Rhialto:BAAANQADCgIJAgAAAA==.Rhinopill:BAAANQAECgUIBQABNQAECgkJHwAIAHcfAA==.Rhyzand:BAAANQADCgQJBwAAAA==.',
Ri='Riasg:BAAANQADCgIIAgAAAA==.Rickilake:BAAANQADCggJGAAAAA==.Ricksanchez:BAAANQAECgYICAAAAA==.Rinik:BAAANQAECgYIDwAAAA==.Riptiide:BAAANQADCgcIBwABNQADCggIDgAFAAAAAA==.Rivendra:BAAANQADCggJGAAAAA==.Riverpixie:BAAANQADCgQJBAAAAA==.',
Ro='Rockabye:BAAANQAECgYJDwAAAA==.Rosannas:BAAANQADCgUIAgABNQAECgkJHwAIAHcfAA==.Rosi:BAAANQADCggICAAAAA==.Royallz:BAAANQAECgIIAgAAAA==.',
Ru='Rudeknees:BAABNQAECoEoAAMCAAkKDRUlKQBzAgACAAkKDRUlKQBzAgAbAAUKfAI1HgC5AAAAAA==.Ruibash:BAEBNQAECoEiAAIPAAgKux8IJwDFAgAPAAgKux8IJwDFAgAAAA==.Runebladé:BAAANQAECgUJCQAAAA==.',
Ry='Ryuu:BAAANQADCggIDAAAAA==.Ryuuzen:BAAANQADCgUIBQABNQAECgMJBQAFAAAAAA==.',
Sa='Sableanne:BAAANQADCgEJAQAAAA==.Sacredkhaos:BAAANQADCgQJBAABNQADCgQIBQAFAAAAAA==.Sacredknight:BAAANQADCgQIBQAAAA==.Saikoumaster:BAAANQAECgEIAQAAAA==.Saintkhaos:BAAANQADCgIIAgABNQADCgQIBQAFAAAAAA==.Sakuraa:BAAANQAECgYICAAAAA==.Samisra:BAAANQADCgYJBgAAAA==.Sarajean:BAAANQADCgQIBAAAAA==.Savaged:BAAANQADCgcIDAABNQAECggIHQALADsSAA==.Savajed:BAABNQAECoEdAAMLAAgKOxKnKwAOAgALAAgKOxKnKwAOAgAcAAUKfwkzPwACAQAAAA==.Savaragon:BAAANQADCgQJBAABNQAECggIHQALADsSAA==.',
Sc='Scallywagg:BAAANQADCggICQAAAA==.Scarletmatch:BAAANQAECgIIAgAAAA==.Scroto:BAAANQAECgEJAQAAAA==.',
Se='Searcomic:BAAANQAECgYIDgAAAA==.Secondwall:BAAANQADCgMIAwAAAA==.Seldav:BAABNQAECoEfAAMYAAkKNhevAwCLAgAYAAkKNhevAwCLAgAdAAMKWQp4IwCwAAAAAA==.Selendas:BAAANQADCgUIBAAAAA==.Selessa:BAAANQADCggICgAAAA==.Selm:BAAANQAECgcJEgAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBQAAAA==.Shaleka:BAAANQADCgUICAABNQADCgUJCgAFAAAAAA==.Shaluesta:BAAANQADCgcICgAAAA==.Shamanism:BAAANQAECgQJBwAAAA==.Shameless:BAAANQAECgYICgAAAA==.Shamwów:BAAANQAECgUJDQAAAA==.Sharco:BAABNQAECoEVAAIRAAYKlR+bBgAJAgARAAYKlR+bBgAJAgAAAA==.Sharkbites:BAAANQAECgQJBQAAAA==.Shawarmafury:BAABNQAECoElAAIQAAkKvSaxAAD2AwAQAAkKvSaxAAD2AwAAAA==.Shettani:BAAANQABCgYJCQAAAA==.Shiirou:BAAANQADCgQIBAAAAA==.Shockrasta:BAAANQADCgUJBQABNQAECggIGQAJAAEdAA==.Shooshmael:BAAANQAECgYJDwAAAA==.Shozo:BAAANQADCgUICAABNQAECgcJEgAFAAAAAA==.Shujáa:BAAANQAECgEIAQAAAA==.Shékinah:BAABNQAECoEfAAIeAAkKYA3qKgAOAgAeAAkKYA3qKgAOAgAAAA==.',
Si='Sidesteppin:BAAANQADCgUICAAAAA==.Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQAECgMIAwAAAA==.Sinthein:BAAANQAECgMIBQABNQAFFAQICAAHANYQAA==.Sixséven:BAAANQADCgIIAQABNQADCgYIBgAFAAAAAA==.',
Sk='Skadgrip:BAAANQADCgUIBQABNQAECgYJCQAFAAAAAA==.Skorpekh:BAAANQAECgYJDgAAAA==.Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgQJCgAAAA==.',
Sl='Sleepingsun:BAAANQAECgYIEAAAAA==.Sloppyspikes:BAAANQAECgUJCQAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smidgenn:BAAANQADCgcIDAAAAA==.Smokyblast:BAAANQAECgMIBAAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCgcIEAAAAA==.Sneakgooner:BAAANQADCgcIBwAAAA==.Snowball:BAABNQAECoElAAIJAAcKgARp1QBWAQAJAAcKgARp1QBWAQAAAA==.',
So='Sohtan:BAAANQADCgQIBAAAAA==.Sonbrandt:BAAANQAECgUJBwAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgQICgAAAA==.',
Sp='Sparowprince:BAABNQAECoEqAAIPAAkKRSLVDgBdAwAPAAkKRSLVDgBdAwAAAA==.Speccurious:BAAANQADCgYIBwAAAA==.Spectraleye:BAAANQAECgYICwAAAA==.Sproocherlou:BAAANQAECggIEgAAAA==.Sprour:BAAANQAECgYJCAAAAA==.',
St='Stankbolt:BAAANQAECgUJBwAAAA==.Steezya:BAAANQAECgUICgAAAA==.Stegulos:BAAANQABCgEJAQABNQABCgIIAwAFAAAAAA==.Stellarum:BAAANQAECgMIAwAAAA==.Stormsy:BAAANQADCgcICAABNQAECgcIDwAFAAAAAA==.Stormykitty:BAAANQAECgcIDwAAAA==.Strauch:BAAANQADCgcJBwAAAA==.Striderdh:BAAANQABCgYIBgAAAA==.Strongwoman:BAAANQAECgQJBQAAAA==.Sturtza:BAABNQAECoEiAAIQAAkKQxskGQDjAgAQAAkKQxskGQDjAgAAAA==.Sturtzam:BAAANQADCgUJBQABNQAECgkJIgAQAEMbAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Sunbear:BAAANQADCgYICAAAAA==.Suun:BAABNQAECoEaAAIPAAgKrhr0OQBsAgAPAAgKrhr0OQBsAgAAAA==.',
Sw='Swampassuti:BAAANQAECgEIAQAAAA==.Swoley:BAAANQAECgYIDgAAAA==.',
Sy='Sybelada:BAAANQABCgcJCQAAAA==.Sylphia:BAAANQADCgYIBgAAAA==.Syrina:BAAANQADCgQIBAAAAA==.',
Ta='Taelandas:BAAANQADCgQJDQAAAA==.Tagobeets:BAAANQAECgcJEAAAAA==.Tailyn:BAAANQADCgUIBQAAAA==.Taleiya:BAAANQAECgIJBQAAAA==.Talisaie:BAAANQAECgEJAQABNQAECgkJHQAUAIclAA==.Tanisatharae:BAAANQADCgYIDgABNQAECgMJBQAFAAAAAA==.Tarahse:BAAANQADCgIIAgABNQAECgUIDgAFAAAAAA==.Taraleaanna:BAAANQADCgMJAwAAAA==.Taron:BAAANQAECgMJBQAAAA==.Tart:BAABNQAECoEVAAICAAkKfg9pNAAwAgACAAkKfg9pNAAwAgABNQAECgkJHAAJAKgeAA==.',
Te='Tedjones:BAAANQAECgQJBgAAAA==.Temupeggy:BAAANQADCgEIAQAAAA==.',
Tg='Tgbird:BAAANQADCgQIBAAAAA==.',
Th='Thegirth:BAAANQAFFAEIAQAAAA==.Thehumanatee:BAAANQAECgYJDwAAAA==.Thersh:BAAANQADCgMJAwAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingytoo:BAAANQAECgIJAgAAAA==.Thiqq:BAAANQADCggICAAAAA==.Threlindrier:BAAANQADCgQIBAAAAA==.Throbinggimp:BAAANQADCggICAAAAA==.Thurien:BAAANQADCgcJEwAAAA==.Thyphlo:BAAANQAECgMIBQAAAA==.',
Ti='Tiltedup:BAABNQAECoEWAAIJAAgKTA5ZpAC+AQAJAAgKTA5ZpAC+AQAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Tinkerßell:BAAANQADCgEIAQABNQAECgcIDwAFAAAAAA==.Tirich:BAAANQADCggICAABNQAFFAQICAAHANYQAA==.Titaintium:BAAANQAECgQIBAABNQAECgcJDQAFAAAAAA==.',
To='Toshi:BAAANQAECgUJBgAAAA==.Totemtree:BAAANQADCgMIAwABNQAECgUIDQAFAAAAAA==.',
Tr='Trustmei:BAAANQAECgcICQAAAA==.Trystin:BAAANQAECgIIAgAAAA==.',
Tu='Tullydin:BAAANQAECgYJDwAAAA==.Tullyy:BAAANQADCgMIAgAAAA==.Tums:BAAANQAECgYIEwAAAA==.',
Tw='Twirls:BAAANQAECgYJEAAAAA==.Twistoffate:BAAANQAECgIJBAAAAA==.',
Ty='Tyerant:BAAANQADCgMIAgAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Ur='Urtle:BAAANQADCggIFAAAAA==.',
Us='Uselece:BAABNQAECoEWAAIPAAgKsh11MACWAgAPAAgKsh11MACWAgAAAA==.',
Ut='Uthadandewey:BAAANQADCgcIBwAAAA==.',
Uz='Uzainbolt:BAAANQAECgUJBQAAAA==.',
Va='Valgorr:BAAANQAECgIIAQAAAA==.Valvalon:BAAANQAECgYJCwAAAA==.Vandil:BAAANQADCgYIBgAAAA==.',
Ve='Veelaria:BAAANQAECgYIDAAAAA==.Vegetablue:BAAANQAECgEIAQAAAA==.Vet:BAAANQAECgQIBwAAAA==.',
Vh='Vhelithiana:BAAANQADCgYJEQAAAA==.',
Vi='Viathun:BAAANQADCggICAABNQAECggIHQALADsSAA==.Vicalaus:BAABNQAECoEVAAIcAAcKnBPZIwDYAQAcAAcKnBPZIwDYAQABNQAECggIGwATAAgTAA==.View:BAABNQAECoEXAAIDAAkK+hI9LwA9AgADAAkK+hI9LwA9AgAAAA==.Vikcy:BAAANQAECgIIAgAAAA==.Vilified:BAAANQADCgQJDwAAAA==.Vitros:BAAANQADCgcIBwABNQAECgcIDQAFAAAAAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQAECgYJDQAFAAAAAA==.Voidwitch:BAAANQAECgEIAgAAAA==.Volstagg:BAAANQADCgMIAwAAAA==.',
Vr='Vrakken:BAAANQAECgQIBQAAAA==.',
Vy='Vyndenus:BAABNQAECoEYAAIOAAkKaBDfLwA3AgAOAAkKaBDfLwA3AgAAAA==.',
Wa='Warriorluv:BAAANQADCgEIAQAAAA==.Warrwing:BAAANQADCgcJBwAAAA==.',
We='Webbfury:BAAANQAECgYJBgAAAA==.Wespoo:BAAANQAECgQIBQAAAA==.Wetpug:BAAANQADCgUIBQAAAA==.',
Wh='Wholephister:BAAANQAECgEIAQABNQAECgQIBwAFAAAAAA==.Whupsmarse:BAAANQADCgcIDQAAAA==.',
Wi='Wickin:BAAANQADCgQJBAAAAA==.Wifeyaggroed:BAAANQADCgIIBAAAAA==.Wiggles:BAAANQABCgEIAQAAAA==.Wiglock:BAAANQADCgQIBAAAAA==.Wigpetval:BAAANQAECgYIEwAAAA==.Wiidge:BAAANQAECgQJBQAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQAECgMIBQAAAA==.Winterbane:BAAANQAECgQIBAAAAA==.',
Wo='Wocky:BAAANQAECgQJCgAAAA==.Wolfchan:BAAANQADCgUJBQAAAA==.Worldcrafter:BAAANQAECgQIAwAAAA==.Worldender:BAAANQAECgQJCQAAAA==.',
Wr='Wreckross:BAAANQABCgUJBQAAAA==.',
Xa='Xantry:BAABNQAECoEZAAIPAAkK1yJsEgBDAwAPAAkK1yJsEgBDAwAAAA==.',
Xm='Xmen:BAAANQAECggJAgAAAA==.',
Xy='Xymm:BAAANQADCgcICgAAAA==.',
Ye='Yeastybush:BAABNQAECoEYAAIDAAgK7xuTJAB5AgADAAgK7xuTJAB5AgAAAA==.',
Ys='Yseeraa:BAAANQAECgEJAQAAAA==.',
Za='Zalatoes:BAAANQADCggJGQAAAA==.Zarathea:BAAANQADCggICAABNQAECgMJAgAFAAAAAA==.',
Zi='Zilphah:BAAANQADCgMIAwAAAA==.Zimmerwitch:BAAANQADCggJDgAAAA==.Zimms:BAAANQAECgcJDgAAAA==.',
Zo='Zoeyredbird:BAAANQAECgYJCQAAAA==.Zongo:BAAANQADCgcIBwAAAA==.',
Zw='Zwhitty:BAAANQADCgcJCQAAAA==.',
['Ña']='Ñazary:BAAANQADCggICAAAAA==.',
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
