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

local lookup = {'DemonHunter-Havoc','Hunter-BeastMastery','Monk-Brewmaster','Druid-Balance','DeathKnight-Blood','Paladin-Holy','Unknown-Unknown','Warlock-Demonology','DemonHunter-Devourer','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Warlock-Destruction','Mage-Arcane','Mage-Fire','Warrior-Arms','Warrior-Protection','Monk-Mistweaver','Hunter-Survival','Shaman-Restoration','Priest-Discipline','Druid-Feral','Paladin-Protection','Shaman-Elemental','Druid-Guardian','Shaman-Enhancement','Monk-Windwalker','Paladin-Retribution','Warrior-Fury','Mage-Frost','Hunter-Marksmanship',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=53,date='2026-10-20',data={Al='Althenara:BAAANQAECgUICgAAAA==.Alysard:BAABNQAECn8ZAAIBAAoKzxCcEABmAQABAAoKzxCcEABmAQAAAA==.',
Am='Amaurine:BAAANQAECgIIBAAAAA==.',
An='Anoras:BAAANQADCgcIEAAAAA==.',
Ar='Aratfu:BAAANQAECgcIDAABNQAECgkJIgACAG0VAA==.Araycadia:BAAANQAECggICAAAAA==.Archivus:BAAANQADCgYIBgAAAA==.Arteymis:BAAANQAECgEIAQABNQAECgkJKwADAMEhAA==.Arui:BAABNQAECn8YAAIEAAYKRRqKGAAcAQAEAAYKRRqKGAAcAQAAAA==.',
At='Athania:BAAANQAECgYICwABNQAECggIFQAFALANAA==.Athornia:BAAANQADCgUIBQAAAA==.',
Au='Aumery:BAABNQAECn8oAAIFAAcKMRUdVQCgAQAFAAcKMRUdVQCgAQAAAA==.Autoflick:BAAANQADCgYJBgAAAA==.',
Aw='Awwee:BAAANQAECgEIAQAAAA==.',
Az='Azinozl:BAAANQAFFAEIAQAAAA==.Azipaly:BAABNQAECn8YAAIGAAoK5RkwJQDWAgAGAAoK5RkwJQDWAgABNQAFFAEIAQAHAAAAAA==.Azurite:BAABNQAECn8WAAIIAAgKlAqWnACfAQAIAAgKlAqWnACfAQAAAA==.',
Ba='Baelthos:BAABNQAECn8YAAMJAAYKtxQ+FgD9AAABAAYKwQ9qSgB6AQAJAAYKVxQ+FgD9AAAAAA==.Barebut:BAAANQADCgEIAQAAAA==.',
Be='Belleslock:BAAANQADCgYIBgABNQAECgcIFwAKANgZAA==.Bermon:BAAANQADCgYIDAABNQAECgcIKAAFADEVAA==.Berrypunch:BAAANQADCgcIFQAAAA==.',
Bi='Bingo:BAAANQAECgQICAAAAA==.',
Bl='Bluebyyou:BAABNQAECn8UAAILAAYKfAp5QgAfAQALAAYKfAp5QgAfAQAAAA==.',
Bo='Borgor:BAAANQADCgEIAQAAAA==.',
Bu='Bubblé:BAABNQAECn8ZAAMKAAgK5xfQSgBFAgAKAAgK5xfQSgBFAgALAAUKZwu6RwD/AAAAAA==.Bustei:BAAANQAECgEIAQAAAA==.',
Ca='Caelion:BAABNQAECn8dAAIGAAgKkyLNGAAWAwAGAAgKkyLNGAAWAwAAAA==.Cannex:BAABNQAECn8WAAIMAAYKYhuyGgARAQAMAAYKYhuyGgARAQAAAA==.',
Ce='Celestia:BAAANQAECgUIDQAAAA==.',
Cl='Clarinet:BAAANQAECgEIAQABNQAECggIDQAHAAAAAA==.Clarinetbdk:BAAANQAECggIDQAAAA==.',
Co='Coomerlord:BAAANQAECgEIAQAAAA==.',
Da='Daki:BAAANQADCgUICgABNQAECgkJIgAMAGUKAA==.',
De='Deathhunter:BAAANQABCgQIBAAAAA==.Deekon:BAABNQAECn8dAAMIAAgKrBfNdgD+AQAIAAgKrBfNdgD+AQANAAEKugbAfwAsAAAAAA==.Delryn:BAAANQAECgQIBgAAAA==.Deshand:BAAANQABCgEIAQAAAA==.Deyvian:BAAANQADCgQIBAAAAA==.',
Do='Dooplikit:BAAANQADCgYIBwAAAA==.',
Dp='Dpn:BAABNQAECn8nAAMOAAkKwyHhHQBgAwAOAAkKwyHhHQBgAwAPAAEK1AtlDAA/AAABNQAECgQICQAHAAAAAA==.',
Dr='Draxil:BAAANQAECgEIAQAAAA==.Druish:BAAANQAECgEIAQAAAA==.',
Du='Durpp:BAABNQAECn8YAAIQAAYK4hkPPQArAQAQAAYK4hkPPQArAQAAAA==.Dusyk:BAAANQAECgIIBAAAAA==.',
['Dä']='Däisymäy:BAAANQADCgEIAQABNQAECgcIJQACAIMdAA==.',
Eg='Egud:BAABNQAECn8mAAIRAAgK6hdDBwBFAQARAAgK6hdDBwBFAQAAAA==.',
El='Elipse:BAAANQADCgUIBgAAAA==.Elipsis:BAAANQAECgEIAgAAAA==.Eliri:BAABNQAECn8WAAISAAgKexsUEgBbAgASAAgKexsUEgBbAgABNQAFFAIIAgAHAAAAAA==.Ellenad:BAAANQAECgIIAwAAAA==.',
En='Enemy:BAAANQAECgUICwABNQAECggIFQATAA8TAA==.',
Es='Estia:BAAANQABCgEIAQAAAA==.',
Ev='Everflux:BAABNQAECn8iAAIKAAcK/iGYHACXAQAKAAcK/iGYHACXAQAAAA==.Everhunt:BAAANQAECgEIAQAAAA==.Evo:BAABNQAECn8VAAITAAgKDxPqBQBNAgATAAgKDxPqBQBNAgAAAA==.',
Ey='Ey:BAAANQAECgIIAgAAAA==.',
Fa='Farisu:BAACNQAFFH8QAAMMAAYKdhLXCQB2AQAMAAUKdhLXCQB2AQAFAAEKAABuLQA+AAA1AAQKfyIAAwwACgprGo0zAF0CAAwACgpaGo0zAF0CAAUABQq+GoCBAPUAAAAA.',
Fe='Feoran:BAAANQADCgIIAgAAAA==.',
Fj='Fjara:BAAANQADCgYIBgAAAA==.',
Fl='Flick:BAAANQAECgQIBAAAAA==.',
Fr='Frontallover:BAAANQADCgEIAQABNQAFFAIIAgAHAAAAAA==.',
Ge='Georish:BAAANQAECgUIBwAAAA==.',
Gi='Gilgamësh:BAAANQADCgIIAgAAAA==.Ginseng:BAABNQAECn8bAAIUAAgKwBUnVAAWAgAUAAgKwBUnVAAWAgAAAA==.Giritos:BAAANQADCgYIBgABNQAECggIEgAHAAAAAA==.Girthquake:BAABNQAECn8mAAIUAAkKTCS9EAA/AwAUAAkKTCS9EAA/AwAAAA==.',
Go='Gorg:BAAANQADCgMIAwAAAA==.',
['Gé']='Gémini:BAAANQAECgUICAAAAA==.',
Ha='Haavoc:BAAANQAECgEIAQABNQAECggIJAAQAO8HAA==.Hagul:BAAANQAECgIIAgAAAA==.Hakuad:BAAANQADCgIIAgAAAA==.Halanhar:BAAANQADCgcICgAAAA==.Hashi:BAAANQAECgEIAQAAAA==.',
He='Hellrocker:BAAANQAECgQIDwAAAA==.Hermione:BAAANQAECgQICwABNQAECgIIAwAHAAAAAA==.Hestia:BAAANQABCgQIBAAAAA==.',
Ho='Holyvader:BAAANQADCggICAAAAA==.Hotnspicy:BAAANQADCgUIBQAAAA==.',
Hu='Hukhan:BAAANQAECgEIAQAAAA==.Huraaki:BAAANQAECgIIAgAAAA==.',
In='Innis:BAABNQAECn8aAAMKAAgKNRvURgBSAgAKAAgKNRvURgBSAgAVAAEKVwcELQAqAAAAAA==.',
Ir='Irine:BAAANQAECgYIEgAAAA==.Irore:BAAANQAECgUIEQAAAA==.',
It='Itszoi:BAAANQADCgIIAgAAAA==.',
Je='Jenjyandi:BAAANQADCgYICwABNQAECgYIGAAUAPIKAA==.Jetahnna:BAABNQAECn8UAAICAAYK/QUQegC5AAACAAYK/QUQegC5AAAAAA==.',
Ji='Jibbs:BAAANQAECgEIAQAAAA==.',
Jo='Jozlinn:BAABNQAECn8tAAILAAcKAgVYQwAaAQALAAcKAgVYQwAaAQAAAA==.',
Ka='Kaeldar:BAAANQAECgIIBQAAAA==.Kajadin:BAABNQAECn8YAAIUAAYK8gpPSwDKAAAUAAYK8gpPSwDKAAAAAA==.Karatedonkey:BAABNQAECn8XAAIWAAYKLQ2NDADWAAAWAAYKLQ2NDADWAAAAAA==.Kardai:BAEBNQAECn8YAAIFAAYKaRW7IwDoAAAFAAYKaRW7IwDoAAAAAA==.Katreia:BAAANQAFFAEIAQABNQAFFAYIGAAFAAEZAA==.Kazimas:BAAANQADCgcJFQAAAA==.',
Kh='Khalcite:BAABNQAECn8YAAIXAAYKUR38HgDvAQAXAAYKUR38HgDvAQAAAA==.',
Ki='Kittyshaman:BAABNQAECn8oAAIYAAkKeQZ5JQAmAQAYAAkKeQZ5JQAmAQAAAA==.',
Kr='Kristyleigh:BAAANQABCgQIBAAAAA==.',
Ku='Kurono:BAABNQAECn8YAAICAAYKUguIXQDxAAACAAYKUguIXQDxAAAAAA==.Kuross:BAAANQAECgQICwAAAA==.',
La='Laermeluion:BAABNQAECn8WAAIZAAoKXx4EBwAaAwAZAAoKXx4EBwAaAwABNQAFFAYIGAAFAAEZAA==.Larra:BAABNQAECn8lAAICAAcKgx0GKQB2AQACAAcKgx0GKQB2AQAAAA==.',
Le='Leen:BAAANQAECgEIAgAAAA==.Lefthian:BAAANQAECgQIDwAAAA==.Leonidas:BAAANQADCggICAAAAA==.',
Lf='Lftwentyones:BAAANQADCgYICwABNQAFFAIIAgAHAAAAAA==.',
Li='Limptriscuit:BAAANQADCgYIBgAAAA==.',
Lo='Loshing:BAAANQAECgMICQAAAA==.',
Lu='Lunakae:BAAANQADCgIIAgAAAA==.',
Ma='Macumba:BAAANQADCggIDwAAAA==.Madeline:BAABNQAECn8aAAILAAgKMSD9FgCiAgALAAgKMSD9FgCiAgAAAA==.Malafar:BAAANQAECgcIEQAAAA==.Maranwae:BAABNQAECn8mAAMUAAgKWB3gCAA1AgAUAAgKWB3gCAA1AgAYAAIKpAiPEwFmAAAAAA==.Masochist:BAAANQAECgcIEgABNQAECgIIAwAHAAAAAA==.',
Me='Melokoi:BAAANQAECgEIAwAAAA==.Merlose:BAAANQAECgIJBAAAAA==.',
Mi='Mieditos:BAAANQAECgQICgABNQAECggIEgAHAAAAAA==.Minirocks:BAABNQAECn8oAAMUAAkKhRjddACtAQAUAAcKPBXddACtAQAaAAkKGxYQCAB0AQAAAA==.',
Mo='Moondivine:BAAANQAECgEIAgABNQAECgcICQAHAAAAAA==.Moonfaith:BAAANQAECgcICQAAAA==.Moosader:BAAANQAECgEIAQAAAA==.',
Na='Naleana:BAAANQADCgcIIgAAAA==.Narzwaz:BAABNQAECn8YAAIbAAYKwhsIKQDXAQAbAAYKwhsIKQDXAQAAAA==.Nataly:BAABNQAECn8cAAIKAAYKyCBWIQB9AQAKAAYKyCBWIQB9AQAAAA==.',
Ne='Neytri:BAABNQAECn8mAAICAAgKDA73JQCBAQACAAgKDA73JQCBAQAAAA==.',
Ni='Nightmoon:BAAANQADCgYIBQAAAA==.',
No='Nommo:BAAANQAECgYICgABNQAECgYIFAALAHwKAA==.Nophica:BAABNQAECn8YAAIRAAcKHwfICwDyAAARAAcKHwfICwDyAAAAAA==.Novaxian:BAAANQAECgUIBgAAAA==.Noxicous:BAAANQADCggIEAAAAA==.',
Nz='Nzoth:BAAANQAECgcIDgABNQAECggIEwAHAAAAAA==.',
On='Oneeyedwilly:BAAANQADCgcIBwAAAA==.',
Os='Osaka:BAABNQAECn8YAAIUAAYK6CMzBwBWAgAUAAYK6CMzBwBWAgAAAA==.',
Pa='Pantheain:BAAANQADCgMIAwAAAA==.Patches:BAAANQAECgYIEgAAAA==.',
Pe='Peänuts:BAAANQAECgEIAgAAAA==.',
Pl='Plagos:BAAANQAECgEIAQAAAA==.',
Po='Pouncival:BAAANQADCgEIAQAAAA==.',
Pr='Prahumn:BAABNQAECn8vAAMKAAkKpR87GQAQAwAKAAkKpR87GQAQAwALAAEKAABOiwAfAAAAAA==.',
Pu='Purplicious:BAAANQAECgIIAgAAAA==.',
Py='Pymilocs:BAABNQAECn8gAAIYAAgKdyDUKQDZAgAYAAgKdyDUKQDZAgAAAA==.',
Qi='Qixx:BAABNQAECn8WAAIYAAYK5wnFOQDdAAAYAAYK5wnFOQDdAAAAAA==.',
Qu='Quint:BAAANQADCgYIDgAAAA==.',
Ra='Rabore:BAAANQAECgMIAwAAAA==.Raktal:BAAANQABCgIIAgAAAA==.Ralee:BAABNQAECn8iAAIMAAkKZQp6YwCCAQAMAAkKZQp6YwCCAQAAAA==.Ralienne:BAAANQAECgIIBAABNQAECgkJIgAMAGUKAA==.Ravinia:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.',
Re='Rennai:BAAANQAECgYICgAAAA==.',
Rh='Rhaemira:BAAANQAECgUIBQAAAA==.',
Ri='Richter:BAAANQADCggIIAAAAA==.Rigoletta:BAAANQAECgEIAQAAAA==.Rin:BAEBNQAECn8bAAISAAgKyRs0CgAzAQASAAgKyRs0CgAzAQAAAA==.',
Ro='Rogelink:BAAANQADCgYIBgAAAA==.Rosan:BAAANQAECgMIBQAAAA==.Royakan:BAAANQAECgEIAQAAAA==.',
Ru='Rumtumtugger:BAAANQADCgUIBQAAAA==.',
Sa='Samoset:BAAANQAECgUIEwAAAA==.Sasten:BAAANQADCgMIAwAAAA==.',
Se='Serosion:BAAANQADCgcIBwAAAA==.',
Sh='Shaile:BAABNQAECn8VAAIFAAgKsA0NWgCLAQAFAAgKsA0NWgCLAQAAAA==.Shalu:BAAANQAECgEIAgAAAA==.Shammysham:BAAANQAECgEIBAAAAA==.Shaymis:BAAANQABCggICwAAAA==.Shifthappons:BAAANQADCgUIBQAAAA==.Shockisha:BAAANQAECgQIBAAAAA==.Shogoth:BAAANQADCgEIAQAAAA==.Shortnstormy:BAAANQAECgQIBAAAAA==.',
Si='Sightseer:BAABNQAECn8YAAICAAgK4gYxqwCuAQACAAgK4gYxqwCuAQAAAA==.Silverthorn:BAABNQAECn8eAAIcAAgKOgwzXgAIAQAcAAgKOgwzXgAIAQAAAA==.',
Sk='Skrom:BAAANQADCgIIAgAAAA==.',
Sn='Sney:BAAANQADCgUICgABNQAECgkJIgAMAGUKAA==.',
Su='Suotokahn:BAAANQADCgUIBQAAAA==.',
Sw='Sweetti:BAAANQADCgcIBwABNQAECgcIJQACAIMdAA==.',
Sy='Sybbil:BAAANQADCgQIBAAAAA==.',
Ta='Tad:BAAANQAECgYIEQAAAA==.Taeltaa:BAAANQAECgUICwAAAA==.Takara:BAAANQABCggIHAAAAA==.Taken:BAABNQAECn8WAAIOAAYKdwTtlACeAAAOAAYKdwTtlACeAAAAAA==.Tazra:BAABNQAECn8xAAIcAAoKZSG5KAAkAwAcAAoKZSG5KAAkAwAAAA==.',
Th='Theshammslam:BAAANQADCgMIAwAAAA==.Thomaz:BAABNQAECn8kAAMdAAoKBAmvGQAIAQAQAAkKtQjyswCbAQAdAAYK2QivGQAIAQAAAA==.Thx:BAAANQAECgIIAgAAAA==.',
Ti='Tiarini:BAAANQADCggIMAAAAA==.Tilee:BAAANQADCgUICQAAAA==.',
To='Tondri:BAABNQAECn8tAAIGAAkK+xcDUgAkAgAGAAkK+xcDUgAkAgAAAA==.Tonkatruck:BAAANQAECgQIDQAAAA==.',
Tr='Traice:BAAANQABCgYICQAAAA==.',
Tu='Tuyenlotus:BAABNQAECn8pAAIaAAoKGBwpBQCuAQAaAAoKGBwpBQCuAQAAAA==.',
['Tò']='Tòkkí:BAAANQAECgUIBwAAAA==.',
Va='Vahnya:BAABNQAECn8fAAIYAAgK5hOVXgAGAgAYAAgK5hOVXgAGAgAAAA==.',
Ve='Venekor:BAAANQADCggICQAAAA==.',
Vi='Vicarrion:BAABNQAECn8VAAIcAAcKDgX0EgH/AAAcAAcKDgX0EgH/AAAAAA==.Viscera:BAAANQADCgIIAwAAAA==.Vitesse:BAAANQADCgcIBwAAAA==.',
Vl='Vlane:BAAANQADCgEIAQAAAA==.',
Vr='Vrat:BAABNQAECn8iAAICAAkKbRXPbwAyAgACAAkKbRXPbwAyAgAAAA==.',
['Ví']='Ví:BAAANQAECgUICgAAAA==.',
Wa='Warfare:BAABNQAECn8kAAIQAAgK7we9vgCAAQAQAAgK7we9vgCAAQAAAA==.Warxie:BAAANQADCggIDgABNQAECgUIDQAHAAAAAA==.',
We='Wendrix:BAAANQADCggICAAAAA==.',
Wi='Winxie:BAAANQAECgMIBQABNQAECgUIDQAHAAAAAA==.',
Wt='Wtfoxtrot:BAAANQADCggICAAAAA==.',
Yo='Yourmageisty:BAABNQAECn8gAAMOAAgKexhJkABfAgAOAAgKLhhJkABfAgAeAAMKVhl4IgDXAAAAAA==.',
Yu='Yulíana:BAABNQAECn8aAAMKAAkKux5PCwAwAgAKAAkKux5PCwAwAgALAAEKAABoPwAAAAAAAA==.',
Za='Zanot:BAAANQADCgQIBAAAAA==.',
Zc='Zcart:BAABNQAECn8gAAMCAAgKyg4lgAAMAgACAAgKyg4lgAAMAgAfAAIKAABjfABSAAAAAA==.',
Ze='Zelara:BAAANQAECgYIBgAAAA==.Zeluxum:BAAANQAECgEJAgABNQAECgYIFgAMAGIbAA==.Zerkio:BAABNQAECn8eAAIUAAkKpxMKRQBNAgAUAAkKpxMKRQBNAgAAAA==.Zertloc:BAACNQAFFH8HAAIYAAQKRgt7DACVAAAYAAQKRgt7DACVAAA1AAQKf0MAAxgACgoOIEkDAGgCABgACgoOIEkDAGgCABQAAQr2BBAdATMAAAAA.',
Zi='Zieda:BAAANQAFFAEIAQAAAA==.',
Zo='Zoids:BAAANQADCgEIAQAAAA==.',
Zu='Zulix:BAAANQAECgEIAQAAAA==.Zulixx:BAAANQADCgQIBAAAAA==.',
Zy='Zyriatchi:BAAANQAECgMIBAAAAA==.',
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
