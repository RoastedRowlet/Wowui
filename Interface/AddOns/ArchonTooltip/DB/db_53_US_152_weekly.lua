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

local lookup = {'DemonHunter-Havoc','Warlock-Destruction','DeathKnight-Blood','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Rogue-Subtlety','Priest-Shadow','Priest-Holy','DemonHunter-Vengeance','Warrior-Arms','Warrior-Fury','Mage-Arcane','Paladin-Retribution','Monk-Brewmaster','Hunter-BeastMastery','Monk-Windwalker','Monk-Mistweaver','Evoker-Devastation','Warlock-Demonology','Shaman-Enhancement','Hunter-Marksmanship','Mage-Frost','Warrior-Protection','Paladin-Protection','Paladin-Holy','Unknown-Unknown','Druid-Restoration','Rogue-Outlaw','Rogue-Assassination','Druid-Guardian','DemonHunter-Devourer','Priest-Discipline','Druid-Feral','Druid-Balance','Warlock-Affliction','Hunter-Survival','DeathKnight-Unholy',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaylasecura:BAABNQAECn8yAAIBAAkKaiGZCABxAwABAAkKaiGZCABxAwAAAA==.',
Ab='Abelladanger:BAAANQADCgQJBAAAAA==.Abracadavar:BAAANQADCgEIAQABNQAFFAgIGwACAO8YAA==.Absinth:BAABNQAECn8YAAMDAAgKow07YQBqAQADAAgKow07YQBqAQAEAAEKAAD7tAAmAAAAAA==.',
Ai='Aidaric:BAAANQADCgUIBQAAAA==.Airfriend:BAABNQAECn82AAMFAAkKkhQJSgA3AgAFAAkKkhQJSgA3AgAGAAUKZRoKmgBgAQAAAA==.',
Al='Alder:BAAANQAECgUIDQAAAA==.Alphard:BAABNQAECn8oAAIHAAgKtR7iCwC2AgAHAAgKtR7iCwC2AgAAAA==.',
An='Anelowyn:BAABNQAECn8oAAMIAAgK+hI3JgD4AQAIAAgK+hI3JgD4AQAJAAcKtwY0lwBLAQAAAA==.Angrychicken:BAAANQAECgYIBgAAAA==.',
Ap='Apocal:BAACNQAFFH8JAAIKAAYKeRgWAQCxAQAKAAYKeRgWAQCxAQA1AAQKfykAAgoACQpcI+gBAHoDAAoACQpcI+gBAHoDAAAA.',
Ar='Arete:BAAANQADCgcIBwAAAA==.Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAAANQAECgYIDgAAAA==.Asmozaps:BAABNQAECn8hAAIGAAkK1w8qVQAhAgAGAAkK1w8qVQAhAgAAAA==.',
At='Ataraxya:BAAANQAECgQIBAAAAA==.',
Az='Aziel:BAABNQAECn8ZAAMLAAkKlguzngDLAQALAAkKNwuzngDLAQAMAAEKcw01MAA8AAAAAA==.Azmodeaus:BAAANQADCgcIBwAAAA==.',
Ba='Baraden:BAABNQAECn8cAAIGAAcKpBDfeQCxAQAGAAcKpBDfeQCxAQAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQAECgIIAgAAAA==.Bih:BAAANQADCgMIAwAAAA==.Bikerm:BAAANQAECgEIAQABNQAFFAcIGgAKAAcgAA==.Billiards:BAAANQADCggICAABNQAECgkJKgANAGcZAA==.Birgetta:BAAANQADCggICAABNQAECggIGwABAC0FAA==.',
Bl='Blitzkrieged:BAAANQAECggICAAAAA==.Blorne:BAAANQAECgQICAAAAA==.',
Bo='Bobodaklown:BAABNQAECn8tAAIOAAgKJSCgOwDhAgAOAAgKJSCgOwDhAgAAAA==.Boombawks:BAAANQADCgUICQAAAA==.Boomnbrew:BAABNQAECn8mAAIPAAkKCA7UEQDGAQAPAAkKCA7UEQDGAQAAAA==.Bownir:BAABNQAECn8WAAIQAAcKmQ3SoADAAQAQAAcKmQ3SoADAAQAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAABNQAECn8kAAMRAAkKCRUpHwAzAgARAAkKCRUpHwAzAgASAAMKKBACOACoAAAAAA==.',
Bu='Bubonic:BAAANQAECgUIDgAAAA==.Buenasalud:BAABNQAECn8WAAIJAAgKZRTEYgD0AQAJAAgKZRTEYgD0AQAAAA==.',
Ca='Catopriest:BAAANQAECgYICgABNQAECggILAATAN0QAA==.Caylea:BAACNQAFFH8QAAILAAUKEBgrEwCPAQALAAUKDxgrEwCPAQA1AAQKfykAAgsACQpbIeMmABwDAAsACQpbIeMmABwDAAAA.',
Ch='Chalis:BAABNQAECn8ZAAMCAAcKwh3EFwCtAQACAAQKfiTEFwCtAQAUAAUKPBfQpACGAQAAAA==.',
Cl='Clamsquirter:BAABNQAECn8XAAMFAAgKhxt2OwBvAgAFAAgKhxt2OwBvAgAVAAIKtQnXLwBqAAAAAA==.Clanis:BAAANQAECgUICAABNQAFFAUIDQAWADUfAA==.',
Co='Coldhwip:BAABNQAECn8rAAMXAAkKZxagDwCrAQANAAgKIhXNvQAHAgAXAAYKbhWgDwCrAQAAAA==.',
Cr='Crtaker:BAAANQAECgcICAAAAA==.Crushfoot:BAAANQADCgUIBQAAAA==.Crysis:BAABNQAECn8rAAIYAAkK1xzVCADBAgAYAAkK1xzVCADBAgAAAA==.',
Cu='Cuahtemoc:BAAANQADCgYIDQAAAA==.',
Da='Dabss:BAAANQAECgEIAQAAAA==.Daelin:BAABNQAECn8oAAMOAAgKQB/xVACTAgAOAAgKQB/xVACTAgAZAAgKqxUrIADgAQAAAA==.Dagda:BAAANQAECgQIBAAAAA==.Danye:BAAANQAECgMIBgAAAA==.Darknasti:BAAANQAECgEIAQAAAA==.Darkscout:BAAANQADCgUJDwAAAA==.',
De='Decease:BAAANQAECgQIBAABNQAECgkJJgAUAOwiAA==.Delium:BAACNQAFFH8RAAINAAYKihE2EgDgAQANAAYKihE2EgDgAQA1AAQKfyYAAg0ACQpnIzAoAEEDAA0ACQpnIzAoAEEDAAAA.Demonmommy:BAAANQAECgUICgAAAA==.Deäthrose:BAABNQAECn8qAAMGAAkK3A/yWAAVAgAGAAkK3A/yWAAVAgAFAAgKCAksjQBkAQAAAA==.',
Di='Die:BAAANQAECgYICgAAAA==.Diegoo:BAAANQADCgUIBQAAAA==.Disc:BAAANQADCgQIBgAAAA==.',
Do='Doadin:BAABNQAECn8tAAIaAAgKJhiJRwBGAgAaAAgKJhiJRwBGAgAAAA==.Dolphus:BAAANQAECggIEAAAAA==.Dolust:BAAANQAECgQIAgABNQAECggILQAaACYYAA==.Doominatrix:BAABNQAECn8oAAIUAAkK/hHaZwAgAgAUAAkK/hHaZwAgAgAAAA==.Dotem:BAAANQAECgIIAgAAAA==.',
Dr='Draggum:BAAANQADCggIFQABNQAECgkJLAAOABggAA==.Dreadlocky:BAABNQAECn8hAAMCAAgKexa0DQAcAgACAAcKRRm0DQAcAgAUAAQKAg3WAgHAAAAAAA==.Dreadmagey:BAAANQADCggICQABNQADCgYIDAAbAAAAAA==.Dreadraven:BAAANQADCgYIDAAAAA==.Dreven:BAAANQADCggIEAABNQAECgcIFwAIANUQAA==.Drip:BAAANQAECgIIAgAAAA==.Druidhams:BAABNQAECn8XAAIcAAkK2h2TDQDzAgAcAAkK2h2TDQDzAgAAAA==.',
Du='Dunktars:BAABNQAECn8jAAILAAkKeR/TQgC+AgALAAkKeR/TQgC+AgAAAA==.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBgAAAA==.',
Ei='Eightball:BAAANQADCggIFwABNQAECgkJKgANAGcZAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBgAbAAAAAA==.Elisha:BAABNQAECn9SAAIOAAgKFxEaoADcAQAOAAgKFxEaoADcAQAAAA==.Eltara:BAAANQADCgEIAQAAAA==.',
Er='Erebostro:BAABNQAECn8oAAIQAAgKOhyGPgCtAgAQAAgKOhyGPgCtAgAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgQICgAAAA==.Fathercow:BAAANQAFFAIIAgAAAA==.Fauxphoe:BAAANQADCgMIAwAAAA==.Fauxtotem:BAABNQAECn8rAAIVAAkKiiFhBQA0AwAVAAkKiiFhBQA0AwAAAA==.',
Fe='Fender:BAAANQAECgEIAQAAAA==.Ferdinand:BAAANQADCgcIBwABNQAECgcIEAAbAAAAAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAABNQAECn82AAMUAAkK1SInMADEAgAUAAcK+SInMADEAgACAAIKeyLnPQDJAAAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.Flush:BAAANQAECggICAAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAECgkJGAAdAAIeAA==.',
Fu='Furina:BAAANQAECgIIAgAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
Ga='Galaxsea:BAABNQAECn8gAAIRAAgKIh18FQCjAgARAAgKIh18FQCjAgAAAA==.Gale:BAAANQADCgYIBwABNQAECggIGgARAEoVAA==.Gamefreak:BAAANQAECgQIBAAAAA==.',
Ge='Gerthquake:BAAANQAECgcIEQAAAA==.',
Gh='Ghostfreak:BAABNQAECn8fAAIeAAgKfhaeLgAkAgAeAAgKfhaeLgAkAgAAAA==.',
Gi='Giren:BAAANQAECggIBwABNQAFFAcIHAAOAG8cAA==.',
Go='Gobø:BAAANQAECgQIBAAAAA==.Gooby:BAAANQAECgYIEwAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAABNQAECn8ZAAMFAAcKSw2WkwBTAQAFAAcKSw2WkwBTAQAGAAUKtwX6zwDvAAAAAA==.Haranjer:BAABNQAECn8eAAIRAAgKJBtRGgBpAgARAAgKJBtRGgBpAgAAAA==.',
He='Hefferhumper:BAABNQAECn8WAAIfAAYKnRJXKQBHAQAfAAYKnRJXKQBHAQAAAA==.',
Ho='Homlock:BAAANQADCgYICwABNQAFFAYIGgANANIgAA==.Homslam:BAAANQAECggIEAABNQAFFAYIGgANANIgAA==.Homsorc:BAACNQAFFH8aAAMNAAYK0iCsCAA2AgANAAYKQyCsCAA2AgAXAAEKDSAADQBXAAA1AAQKfygAAg0ACQpcJlgEANYDAA0ACQpcJlgEANYDAAAA.Homstab:BAABNQAECn8gAAMHAAkKtR+aEwBMAgAHAAcKmR2aEwBMAgAeAAIK+STGdADVAAABNQAFFAYIGgANANIgAA==.Homtard:BAAANQAECgQIBQABNQAFFAYIGgANANIgAA==.Homtotem:BAAANQADCggICAABNQAFFAYIGgANANIgAA==.Homwiz:BAAANQAECgQIBgAAAA==.Hope:BAABNQAECn8iAAIaAAkK3BRrRQBNAgAaAAkK3BRrRQBNAgAAAA==.',
Ic='Iced:BAAANQADCgIIAgABNQAECggIHQAIAJAZAA==.Icons:BAAANQAECggICAAAAA==.Icyshaft:BAAANQADCgMIAwABNQAFFAUIDQAWADUfAA==.',
Il='Illiandray:BAABNQAECn8lAAICAAgKvR3KBQC2AgACAAgKvR3KBQC2AgAAAA==.',
In='Insomniac:BAABNQAECn8nAAIgAAgKQyS+CABHAwAgAAgKQyS+CABHAwAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgYIEgAAAA==.Jagernaut:BAAANQAECgUICwAAAA==.Jake:BAAANQAECgYIDgAAAA==.Jangaballs:BAAANQAECgYIDQAAAA==.Jawndie:BAABNQAECn8kAAMSAAgKRBqCEwBAAgASAAgKRBqCEwBAAgAPAAEKAACTNAAjAAAAAA==.',
Jo='Joker:BAAANQAECgIIAgAAAA==.',
Jy='Jynn:BAAANQAECgQIBwABNQAECgkJJgAhADMhAA==.',
Ka='Kaalg:BAAANQADCgYIBgAAAA==.Kaalgormi:BAAANQABCgcICQAAAA==.Kammo:BAABNQAECn8zAAIEAAkKaiOGBQCGAwAEAAkKaiOGBQCGAwAAAA==.Kassa:BAAANQADCggIEQAAAA==.',
Ke='Keeah:BAAANQAECgYIEwAAAA==.Kestra:BAABNQAECn8rAAISAAkKtAf2IQByAQASAAkKtAf2IQByAQAAAA==.',
Ki='Kittysprigg:BAABNQAECn8cAAMiAAgKFhTLDwANAgAiAAgKFhTLDwANAgAjAAQKgwgciQCrAAAAAA==.',
Kl='Klingnor:BAAANQADCgcJBwAAAA==.',
Kr='Kravensteak:BAACNQAFFH8NAAIWAAUKNR+9CQCjAQAWAAUKNR+9CQCjAQA1AAQKfyUAAhYACArLIskXAJgCABYACArLIskXAJgCAAAA.',
Ku='Kurty:BAAANQADCgUIBQAAAA==.',
Kw='Kwickin:BAAANQAECgYICAABNQAECgkJLAAOABggAA==.',
Ky='Kyreen:BAAANQAECgYIEwAAAA==.',
['Kä']='Kärl:BAAANQADCgYIBwABNQAECggIIAARACIdAA==.',
Le='Leonelda:BAAANQADCgUIBQAAAA==.Leylines:BAABNQAECn8rAAINAAkKrxfMjwBfAgANAAkKrxfMjwBfAgAAAA==.',
Lu='Luciferr:BAAANQAECgEIAQAAAA==.Lukafox:BAAANQAECgUIDAAAAA==.Lunastarvale:BAABNQAECn8eAAIQAAgKLhIjcwAnAgAQAAgKLhIjcwAnAgAAAA==.Lunereclipse:BAAANQAECgQJBAAAAA==.',
Ma='Macha:BAABNQAECn8sAAMFAAkKIiRCBQCcAwAFAAkKIiRCBQCcAwAGAAYKkwcQvgARAQAAAA==.Madith:BAAANQAECgQICgAAAA==.Maintarget:BAABNQAECn8dAAIIAAgKkBnDGgBxAgAIAAgKkBnDGgBxAgAAAA==.Malefisico:BAABNQAECn8aAAICAAgKExg3CgBTAgACAAgKExg3CgBTAgAAAA==.Mardríft:BAABNQAECn8oAAIjAAkK4hvTGgDwAgAjAAkK4hvTGgDwAgAAAA==.Marero:BAAANQADCgYICgAAAA==.Martyr:BAABNQAECn8iAAITAAkKog40FAAJAgATAAkKog40FAAJAgAAAA==.Mazga:BAABNQAECn8nAAIFAAgKQxFGcwCuAQAFAAgKQxFGcwCuAQAAAA==.',
Mc='Mcflury:BAAANQADCgYICwAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.Meteos:BAAANQABCgMIBAAAAA==.Mezoti:BAAANQADCggICgAAAA==.',
Mi='Mick:BAAANQAECgYICQAAAA==.Miraclehwip:BAAANQADCggICQAAAA==.',
Mo='Moaxzy:BAAANQAECgEIAQAAAA==.Moji:BAABNQAECn8yAAISAAkKuBYqEAB5AgASAAkKuBYqEAB5AgAAAA==.Monstermayi:BAABNQAECn8nAAMMAAgKWRYGCgAsAgAMAAgKWRYGCgAsAgALAAIKvxBLLwFuAAAAAA==.Mooknight:BAABNQAECn8hAAIDAAgK9AnKXgBzAQADAAgK9AnKXgBzAQAAAA==.Moreina:BAAANQADCgUIBQABNQAECgkJNAAJAAYZAA==.Morgoth:BAABNQAECn8fAAQUAAcKuB/PPgCTAgAUAAcKxx7PPgCTAgAkAAMK1RmRFwDPAAACAAEKAAAhdAA5AAAAAA==.Morteesha:BAAANQAECgEIAQABNQAECggIJAASAEQaAA==.',
Mu='Muggy:BAABNQAECn8oAAIeAAgK4xDqMwAHAgAeAAgK4xDqMwAHAgAAAA==.',
My='Myrothar:BAAANQAECgUIBQAAAA==.Mytastical:BAAANQAECgMIBwAAAA==.',
['Må']='Måzikeen:BAAANQAECgQIBAABNQAECgkJLAAFACIkAA==.',
Na='Najwah:BAABNQAECn8aAAMJAAkKQB3SFgAcAwAJAAkKQB3SFgAcAwAIAAQKRxFeSgDqAAAAAA==.Namalis:BAABNQAECn8mAAMUAAkK7CJvHQAMAwAUAAgKRiNvHQAMAwACAAMKyRZAPgDIAAAAAA==.Nanielito:BAABNQAECn8bAAINAAkKaxfIgQB6AgANAAkKaxfIgQB6AgAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQIBwAAAA==.Nerra:BAAANQADCggIDgAAAA==.',
Ni='Nineball:BAAANQADCgIIAgABNQAECgkJKgANAGcZAA==.Ninjutsu:BAAANQAECgEIAQABNQAECgkJJgAUAOwiAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAABNQAECn8XAAIQAAgKTRjUagA7AgAQAAgKTRjUagA7AgAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosali:BAABNQAECn8eAAIkAAgKohtoAwDBAgAkAAgKohtoAwDBAgABNQAECgkJNAAJAAYZAA==.Nosliw:BAAANQAECggICAAAAA==.Noxilis:BAAANQAECgQICAABNQAECgkJLAALAPYQAA==.',
Nu='Nuggetz:BAAANQADCggICQAAAA==.',
['Nï']='Nïghtman:BAAANQAECgcIDQABNQAECgcIDgAbAAAAAA==.',
Om='Omegá:BAABNQAECn8UAAMZAAgKPhFJJQCyAQAZAAgKcxBJJQCyAQAOAAEKWBNzjAFCAAABNQAECggIGAADAKMNAA==.',
Op='Optìmusprìme:BAABNQAECn8kAAIYAAgKBheUEQALAgAYAAgKBheUEQALAgAAAA==.',
Or='Ordovic:BAAANQADCgUIBQAAAA==.',
Pa='Pandemic:BAABNQAECn8fAAIQAAkKiRJNTgCBAgAQAAkKiRJNTgCBAgAAAA==.Papa:BAABNQAECn8sAAQkAAkK4BVcEQAzAQAUAAUKbhKMxwA2AQAkAAUKrxFcEQAzAQACAAQKshZELQAXAQAAAA==.Pawfu:BAABNQAECn8oAAQRAAgKxhlpHABSAgARAAgKxhlpHABSAgASAAYKmwz2KgATAQAPAAIKmAmEKgBoAAAAAA==.',
Pe='Penywize:BAABNQAECn8YAAMOAAcKmwTqCwEEAQAOAAcKmwTqCwEEAQAaAAYKuATwugACAQAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgEIBAAAAA==.',
Po='Pockets:BAABNQAECn8qAAINAAkKZxnebACkAgANAAkKZxnebACkAgAAAA==.',
Pr='Prenus:BAAANQAECgUJBwAAAA==.',
Ps='Psychic:BAABNQAECn8mAAIhAAkKMyEBAQBfAwAhAAkKMyEBAQBfAwAAAA==.',
Pu='Purge:BAAANQAECgMIBAAAAA==.',
Qr='Qrazi:BAABNQAECn8aAAIGAAgKwBCQYwDzAQAGAAgKwBCQYwDzAQAAAA==.',
Qu='Quenthil:BAAANQAECgUIBQAAAA==.Quick:BAAANQAECgUIDgABNQAECgkJLAAOABggAA==.',
Ra='Ratha:BAABNQAECn8rAAIZAAkK7CJ6BABvAwAZAAkK7CJ6BABvAwAAAA==.Ravincible:BAAANQAECgMIAwAAAA==.Razeal:BAAANQAECgUIBQAAAA==.',
Ri='Ribbz:BAAANQADCgYICwAAAA==.',
Ro='Roguechin:BAACNQAFFH8XAAMHAAcKjSBVBADlAQAHAAUKpB5VBADlAQAeAAQKayNsCQBpAQA1AAQKfykAAwcACQq4JeoGAA4DAAcACArGJeoGAA4DAB4ABwqEI6gVAMsCAAAA.Rokkgar:BAABNQAECn8fAAIGAAgKOhjiQABvAgAGAAgKOhjiQABvAgAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAAANQAECggIEQAAAA==.',
Sa='Sageara:BAAANQAECgQIBAAAAA==.Samirath:BAABNQAECn8aAAIJAAgKJBewVAAhAgAJAAgKJBewVAAhAgAAAA==.',
Sc='Scared:BAACNQAFFH8KAAIJAAUK0Qm6EwBlAQAJAAUK0Qm6EwBlAQA1AAQKfz0AAgkACQoAIi8MAF8DAAkACQoAIi8MAF8DAAAA.',
Se='Secarious:BAAANQAECgIIAgAAAA==.Sehnsucht:BAABNQAECn8eAAQiAAcKvxmUEAD9AQAiAAYKuR2UEAD9AQAcAAcKQBW5LACyAQAfAAIKHQvdUwBOAAAAAA==.',
Sh='Shakti:BAAANQAECgUIBQAAAA==.Shieldcow:BAAANQAECgIIBAABNQAFFAIIAgAbAAAAAA==.Shmadu:BAABNQAECn8kAAIQAAkK8SUnAQD2AwAQAAkK8SUnAQD2AwAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.Shockk:BAAANQAECgQICAAAAA==.',
So='Soola:BAAANQADCggICAABNQAECgkJKwAZAOwiAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stonedpriest:BAAANQAECgUICwAAAA==.',
Su='Surrëal:BAABNQAECn8bAAIBAAgKLQVGXAALAQABAAgKLQVGXAALAQAAAA==.',
Sw='Sweetmask:BAAANQAECgUICQAAAA==.',
Sy='Sybela:BAAANQABCgYIDAABNQAECgkJJwAJAIUeAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAABNQAECn8oAAIXAAgKRCAlBQDGAgAXAAgKRCAlBQDGAgAAAA==.Tanidge:BAAANQADCgQIBAABNQAECgkJMAAGAA4hAA==.Tanidgemage:BAAANQADCgQIBAABNQAECgkJMAAGAA4hAA==.Tanidgetotem:BAABNQAECn8wAAIGAAkKDiEoFgBBAwAGAAkKDiEoFgBBAwAAAA==.',
Te='Teias:BAABNQAECn80AAMJAAkKBhkqOACFAgAJAAkKBhkqOACFAgAIAAQKzhc1QAApAQAAAA==.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
Ti='Tirael:BAAANQAECgUIBgABNQAECgkJNAAJAAYZAA==.',
To='Torvald:BAAANQAECggICAABNQAECggICAAbAAAAAA==.',
Tr='Tricko:BAABNQAECn8nAAIQAAgKmyH7IwAFAwAQAAgKmyH7IwAFAwAAAA==.Trickshots:BAAANQADCgMIAwABNQAECgkJKgANAGcZAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollbi:BAAANQADCgQIAgAAAA==.Trollfacion:BAAANQADCgYIBgAAAA==.Trollskingx:BAABNQAECn8iAAINAAgKahccowA6AgANAAgKahccowA6AgAAAA==.Trollzy:BAABNQAECn8oAAMVAAgKKBzoDQCMAgAVAAgKKBzoDQCMAgAFAAIKIAPhCgFMAAAAAA==.Trunkmonkey:BAABNQAECn8fAAIUAAkKwhWlTABrAgAUAAkKwhWlTABrAgAAAA==.Trunky:BAAANQAECgYIBgAAAA==.',
Ts='Tsaagan:BAABNQAECn8oAAIUAAkKsCCVIwDzAgAUAAkKsCCVIwDzAgAAAA==.',
Um='Umbrosa:BAAANQADCgcIBwABNQAECgkJKwAYANccAA==.',
Ur='Urthalos:BAAANQAECgcIBwAAAA==.',
Va='Valica:BAAANQADCgUIBQAAAA==.Valiithria:BAAANQAECgQIBQAAAA==.Valkyruid:BAABNQAECn8ZAAMcAAkKBx08EQDGAgAcAAkKBx08EQDGAgAjAAEKAADrvAAiAAAAAA==.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQAECgEIAgAAAA==.',
Vu='Vulgan:BAAANQADCgcICAAAAA==.',
Wa='Warriorchin:BAAANQAFFAIIAgABNQAFFAcIFwAHAI0gAA==.Waywatcher:BAAANQAECgQICAAAAA==.',
Wh='Whiilow:BAABNQAECn8bAAMFAAkKuxYUOwBwAgAFAAkKuxYUOwBwAgAGAAEKGASeRgEoAAAAAA==.',
Wu='Wullgan:BAABNQAECn8XAAIJAAcKKRoLWAAWAgAJAAcKKRoLWAAWAgAAAA==.',
Xe='Xencure:BAAANQAFFAIIAwAAAA==.Xerk:BAAANQAECgcIDgAAAA==.',
Xy='Xyrna:BAABNQAECn8mAAIlAAkKGRvPAgD7AgAlAAkKGRvPAgD7AgABNQAECgkJKwAZAOwiAA==.',
Ya='Yareli:BAABNQAECn8lAAIKAAgKcQZAGAApAQAKAAgKcQZAGAApAQAAAA==.',
Yo='Youngdoug:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAABNQAECn8YAAMmAAgKzhN0ZAB7AQAmAAYKVhh0ZAB7AQAEAAYK4wzRWgA2AQAAAA==.',
Ze='Zeleck:BAABNQAECn8XAAMIAAcK1RD8KwDDAQAIAAcK1RD8KwDDAQAJAAQK3gU+zwCwAAAAAA==.Zeno:BAACNQAFFH8cAAIOAAcKbxz6AADHAgAOAAcKbxz6AADHAgA1AAQKfysAAg4ACQoyJsQUAHEDAA4ACQoyJsQUAHEDAAAA.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAABNQAECn8fAAIeAAgKfBLpMAAYAgAeAAgKfBLpMAAYAgABNQAECggIHwAGADoYAA==.',
Zi='Zinbar:BAAANQAECgYIDQAAAA==.',
Zo='Zoroark:BAAANQADCggIEAABNQAECgkJKwANAK8XAA==.',
Zu='Zuggzugg:BAAANQADCgYIBgAAAA==.Zune:BAABNQAECn8aAAMRAAgKShV1LQCpAQARAAcKyxR1LQCpAQAPAAYKaBM5HgD+AAAAAA==.',
['Çl']='Çloud:BAAANQAECgIIAwAAAA==.',
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
