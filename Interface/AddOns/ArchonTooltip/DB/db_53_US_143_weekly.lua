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

local lookup = {'Mage-Arcane','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Paladin-Protection','Priest-Shadow','Warrior-Protection','Unknown-Unknown','DeathKnight-Blood','Priest-Holy','Hunter-Marksmanship','Druid-Guardian','Mage-Frost','Shaman-Enhancement','Warrior-Arms','DeathKnight-Frost','Druid-Feral','Druid-Balance','Druid-Restoration','Priest-Discipline','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Monk-Mistweaver',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abukuma:BAAANQAECgUIBgAAAA==.',
Ad='Adrewid:BAAANQADCgEIAQABNQAFFAUIDAABAOgQAA==.',
Ae='Aenstalash:BAABNQAECn8lAAMCAAkKlB5tBQCBAgACAAkKlB5tBQCBAgADAAMKEwqoUwGaAAAAAA==.Aephium:BAAANQADCgQIBAAAAA==.Aeson:BAABNQAECn8oAAIEAAgKRBIvUADTAQAEAAgKRBIvUADTAQAAAA==.',
Al='Alfonsoo:BAAANQAECgEIAQAAAA==.Alistur:BAAANQAECgYIDgAAAA==.',
Am='Ameena:BAABNQAECn8fAAMFAAgKRhwxTwAoAgAFAAcKBRsxTwAoAgAGAAEKGwhClAA1AAAAAA==.Amuraby:BAAANQADCgEIAQAAAA==.',
An='Anamura:BAAANQADCgMIAwAAAA==.Angus:BAAANQAECgIIBAAAAA==.',
Ar='Arcomedes:BAAANQAECgIIAgAAAA==.Arthrasz:BAABNQAECn8XAAIDAAgK2xOmmQDwAQADAAgK2xOmmQDwAQAAAA==.Arthraz:BAABNQAECn8jAAIHAAgKqxfSDgAGAgAHAAgKqxfSDgAGAgAAAA==.',
As='Asondralyn:BAAANQABCgUIBgAAAA==.Astara:BAABNQAECn8lAAIIAAoKcxPqBgBIAgAIAAoKcxPqBgBIAgAAAA==.Astrex:BAABNQAECn8iAAMJAAcK1RWGAwDSAQAJAAcK1RWGAwDSAQAKAAEKAgKWQwAgAAAAAA==.',
Au='Aurali:BAAANQAECgQIBwAAAA==.Aureliá:BAABNQAECn8XAAILAAYKpQbj5wAxAQALAAYKpQbj5wAxAQAAAA==.',
Az='Azureth:BAAANQAECgcIBwAAAA==.',
['Aü']='Aütobot:BAAANQAECgUICQAAAA==.',
Ba='Babayaga:BAAANQADCgUIBQAAAA==.Badgirl:BAAANQADCgQIBAAAAA==.Balnar:BAAANQAECgQIBgABNQAECgcIIAAMAMgYAA==.',
Be='Bega:BAAANQAECgIIAgABNQAFFAQIBwANAIIEAA==.',
Bl='Bloodlustplz:BAABNQAECn8hAAIOAAgKaRDrGgCJAQAOAAgKaRDrGgCJAQAAAA==.',
Bo='Bobster:BAABNQAECn8eAAIBAAgKMhRRuwANAgABAAgKMhRRuwANAgAAAA==.Bonepaw:BAAANQADCgUICAABNQAECgcIBwAPAAAAAA==.Booyea:BAABNQAECn8uAAIQAAkKphXtCwCKAQAQAAkKphXtCwCKAQAAAA==.',
Br='Brew:BAAANQABCgIJAgAAAA==.Brewwnor:BAAANQAECgcICgAAAA==.Brewwnôr:BAAANQADCgEIAQAAAA==.Brewwtus:BAAANQADCgMIAwAAAA==.Brisfloggnaw:BAAANQADCgcIBwAAAA==.',
Bu='Bubblenoodle:BAAANQADCgQIBAAAAA==.Bubbleplop:BAAANQAECgYICwABNQAECgoKNgARAGEhAA==.',
Ca='Calamuelis:BAACNQAFFH8OAAMLAAcKyxm+BAANAgALAAYKYxm+BAANAgASAAEKbRvlIABdAAA1AAQKfywAAwsACgr6JWkOAG4DAAsACgr6JWkOAG4DABIABQrDIqYMACoBAAAA.Caliope:BAAANQAECgUICQAAAA==.Carnage:BAAANQAECggIAwAAAA==.Cathbad:BAABNQAECn8pAAITAAgKYxGXGgDRAQATAAgKYxGXGgDRAQAAAA==.',
Ce='Celery:BAAANQADCgYIBgABNQAECggIIwAHAKsXAA==.Cerelus:BAABNQAECn8mAAIUAAkKsReNAQD+AQAUAAkKsReNAQD+AQAAAA==.',
Ch='Chaac:BAABNQAECn8eAAIVAAgKEh67CQDZAgAVAAgKEh67CQDZAgAAAA==.Chediah:BAAANQAECgMIBAAAAA==.Cheesûs:BAAANQAECgUICwAAAA==.',
Co='Cocana:BAAANQAECggICgAAAA==.Cowmus:BAAANQAECggIEQABNQAECgoKKwAFAC0fAA==.',
Cr='Crow:BAAANQAECgcIAQABNQAECggIBQAPAAAAAQ==.',
['Cã']='Cãrloy:BAABNQAECn9uAAIWAAoKNxwgBgBsAgAWAAoKNxwgBgBsAgAAAA==.',
Da='Daedalas:BAABNQAECn8ZAAINAAkKQRTAJQABAgANAAkKQRTAJQABAgAAAA==.Daenari:BAAANQADCgYIBgAAAA==.Darkxsoul:BAABNQAECn8gAAIMAAcKyBjUDQApAQAMAAcKyBjUDQApAQAAAA==.Darthgrogu:BAAANQAECgYIDgABNQAFFAUICwADAKUNAA==.Darthknull:BAACNQAFFH8LAAIDAAUKpQ2UDwBTAQADAAUKpQ2UDwBTAQA1AAQKfyQAAgMACgreGaVnAGUCAAMACgreGaVnAGUCAAAA.Darthputska:BAAANQAECgQIBAABNQAFFAUICwADAKUNAA==.Darthreven:BAAANQAECgUIDQABNQAFFAUICwADAKUNAA==.Darthtalon:BAABNQAECn8WAAIXAAkKswnqRQCpAQAXAAkKswnqRQCpAQABNQAFFAUICwADAKUNAA==.Dayla:BAAANQADCgMIAwAAAA==.',
De='Deathwood:BAAANQAECgQIBgAAAA==.Deatthdecay:BAAANQAECggJAQAAAA==.Degloved:BAEANQAECgQIBQABNQAECgoKLQAFAPMWAA==.Deitrichx:BAAANQAECgMIAwAAAA==.Deminestrea:BAAANQADCgcICAAAAA==.',
Di='Discodeitx:BAAANQADCgIIAgAAAA==.Disshammy:BAAANQAECgIIBAABNQAECggIDQAPAAAAAA==.',
Do='Donkform:BAAANQAECgIIAgABNQAECgYIDwAPAAAAAA==.Donkulle:BAAANQAECgYIDwAAAA==.',
Dr='Draconith:BAABNQAECn8qAAIJAAkKSRxrAQCNAgAJAAkKSRxrAQCNAgAAAA==.Draqkmar:BAAANQADCgcICAAAAA==.',
Du='Dunsparrow:BAABNQAECn8rAAIFAAoKLR9LIgDeAgAFAAoKLR9LIgDeAgAAAA==.Durzul:BAAANQADCgcICwAAAA==.',
Ei='Eindraken:BAABNQAECn8sAAMJAAkKiRAPBgBzAQAJAAkKiRAPBgBzAQAKAAEKAACSQgAkAAAAAA==.Eisis:BAABNQAECn8aAAIYAAkKwAkhCAAoAQAYAAkKwAkhCAAoAQAAAA==.',
El='Elanalué:BAAANQADCggIGAABNQAECgUICQAPAAAAAA==.',
Em='Empoleonn:BAABNQAECn8VAAINAAgK7w5NJgD8AQANAAgK7w5NJgD8AQAAAA==.',
En='Engos:BAAANQADCgYIBwAAAA==.',
Ep='Epsolone:BAAANQABCgMIAwAAAA==.',
Er='Erroz:BAAANQADCggIEwAAAA==.Erukani:BAABNQAECn8UAAIZAAcKPAhEXgBXAQAZAAcKPAhEXgBXAQAAAA==.',
Es='Espriesso:BAABNQAECn8jAAMRAAkK1wiugwCMAQARAAkK1wiugwCMAQANAAIK0AOdNAAyAAABNQAECgoKJgACAKUPAA==.',
Ex='Exemplar:BAAANQAECgUIBgAAAA==.',
Fe='Fearwatermac:BAAANQAECgYIDQAAAA==.Feider:BAAANQABCgQJBwAAAA==.Felais:BAABNQAECn8pAAIaAAoK0hlwDgBaAQAaAAoK0hlwDgBaAQAAAA==.Femmefatale:BAABNQAECn80AAQRAAkKVxpjFwC2AQARAAkKVxpjFwC2AQANAAcKiw5aNQB5AQAbAAYKLgqJEQAPAQABNQAECgkJKgAaAGIOAA==.',
Fl='Flamecube:BAAANQADCgMIAwAAAA==.Flashx:BAABNQAECn8WAAICAAYK/iDiCAA2AgACAAYK/iDiCAA2AgAAAA==.Flass:BAAANQADCggIDgAAAA==.',
Fr='Freerin:BAAANQADCgcICAAAAA==.Frevpl:BAAANQAECgIIAgAAAA==.Frofrohunter:BAAANQAECgYIEgAAAA==.Froggie:BAAANQAECgcIBwAAAA==.',
Fu='Fuzywuuzy:BAAANQAECgYICAAAAA==.',
Ga='Gattsu:BAAANQABCgEIAQABNQAECgoKLQACAGoPAA==.Gazdorn:BAABNQAECn8WAAIOAAcKZgzeHgBcAQAOAAcKZgzeHgBcAQAAAA==.',
Gd='Gddmnbigcrit:BAAANQAECgYIDwAAAA==.',
Ge='Genghis:BAAANQADCgQICAAAAA==.',
Gh='Ghost:BAABNQAECn8lAAIcAAoK1hhsDABlAQAcAAoK1hhsDABlAQAAAA==.',
Gi='Gigof:BAAANQADCgUIBQAAAA==.Gil:BAABNQAECn8cAAIGAAgKghY1dgC/AQAGAAgKghY1dgC/AQAAAA==.Gimmighoul:BAAANQAECgMIAwAAAA==.',
Gl='Gleoc:BAABNQAECn8ZAAIdAAkKgQf4TwDkAAAdAAkKgQf4TwDkAAAAAA==.Glissa:BAABNQAECn8kAAQeAAoKMhwAHQCGAQAeAAQKrCEAHQCGAQAfAAUKfhaBDgBqAQAdAAcKrBnjPQATAQAAAA==.',
Go='Gorditt:BAAANQAECgIIAgAAAA==.',
Gt='Gt:BAABNQAECn8tAAMCAAoKag+AaQDbAQACAAkKpxCAaQDbAQAMAAcKQAu+OAAmAQAAAA==.',
Ha='Habanero:BAAANQAECgQIBwABNQAECggIIwAHAKsXAA==.Hadense:BAAANQADCggICAABNQAFFAQIDAAGAH8cAA==.Hadory:BAAANQAECggIDAAAAA==.',
He='Hellzzdemon:BAAANQAECgQICgAAAA==.Hercow:BAAANQAECgUICAAAAA==.Herrvoller:BAAANQADCgEIAQAAAA==.Hexinverter:BAAANQADCggIEgAAAA==.',
Ho='Holycannoli:BAABNQAECn8VAAIDAAgKQxmfqgDKAQADAAgKQxmfqgDKAQAAAA==.Horiffic:BAABNQAECn8bAAIgAAkKNxiDCgAiAgAgAAkKNxiDCgAiAgAAAA==.Hotfuzz:BAABNQAECn8cAAIBAAoKBxwsVwDSAgABAAoKBxwsVwDSAgAAAA==.Hotsforthots:BAABNQAECn8qAAIRAAoKlRneBwBsAgARAAoKlRneBwBsAgAAAA==.',
Hu='Huntyboi:BAAANQADCgUIBwAAAA==.Hurricaneg:BAAANQADCgMIAwAAAA==.',
Hy='Hyena:BAAANQAECgEIAQAAAA==.',
Ic='Ichaerus:BAAANQAECgIIAgABNQAECgkJGQANAEEUAA==.',
Ii='Iilli:BAAANQADCgYIBgAAAA==.',
In='Inari:BAAANQAECgMIAgAAAA==.Inkkubus:BAACNQAFFH8RAAQeAAUKpxM7EQCPAAAdAAMKBBXrJwDIAAAeAAIKNxI7EQCPAAAfAAEKAACZCQBaAAA1AAQKfzQABB0ACgp0Hh1BAI8CAB0ACQp5Hh1BAI8CAB4AAwqgETZDALgAAB8ABAqTF98IAJkAAAAA.',
Ir='Ironfur:BAAANQABCgQICgABNQAFFAUIDwACAEITAA==.',
Je='Jeffpwnros:BAAANQAECgQIBgAAAA==.',
Jh='Jhohn:BAAANQAECgQIBwAAAA==.',
Ji='Jintan:BAAANQAECgQIBwAAAA==.',
Ju='Judgmentjudy:BAACNQAFFH8PAAICAAUKQhOTDACVAQACAAUKQhOTDACVAQA1AAQKf28AAwIACgpnIYQIAIQDAAIACgpnIYQIAIQDAAMAAQqDAGrlAQoAAAAA.',
Ka='Kaing:BAAANQAECgQIBAAAAA==.Kaissa:BAAANQADCgEIAQAAAA==.Kalena:BAABNQAECn8lAAIUAAkKQgrBBABeAQAUAAkKQgrBBABeAQAAAA==.Kariatyda:BAABNQAECn8pAAILAAoKDxRFDAAQAgALAAoKDxRFDAAQAgAAAA==.Kasaí:BAAANQAECgUIDgAAAA==.Kassandra:BAAANQADCggICAAAAA==.',
Ke='Kekio:BAAANQAECgMIBAAAAA==.',
Ki='Kiloton:BAABNQAECn8dAAITAAcK/xJaEAALAQATAAcK/xJaEAALAQAAAA==.Kinari:BAAANQAECgIIAgABNQAECgYIDgAPAAAAAA==.Kitzy:BAAANQAECgUICQAAAA==.',
Kl='Klippertdk:BAABNQAECn8tAAIEAAgKOxVoCQCfAQAEAAgKOxVoCQCfAQAAAA==.Klutz:BAABNQAECn8gAAIaAAkKqxMOJgDyAQAaAAkKqxMOJgDyAQAAAA==.',
Kn='Kniwt:BAAANQABCgQIBAABNQAECgoKLQACAGoPAA==.',
Ku='Kurzo:BAABNQAECn8bAAIWAAgKTxosfQAiAgAWAAgKTxosfQAiAgAAAA==.',
Ky='Kylarian:BAAANQAECgEIAQAAAA==.Kyntara:BAAANQAECgUIBgAAAA==.Kyronian:BAAANQAECgUICQAAAA==.',
La='Lachancea:BAABNQAECn8WAAIFAAgKPRfkEgC+AQAFAAgKPRfkEgC+AQABNQAECgoKHgAdAHUZAA==.Laeleirri:BAAANQAECggIDQAAAA==.Lakshmee:BAABNQAECn8WAAIFAAcKwgW8rgASAQAFAAcKwgW8rgASAQAAAA==.Landwar:BAAANQADCgYIBgAAAA==.Lanre:BAAANQADCgcIBwAAAA==.',
Le='Ledarm:BAABNQAECn8dAAILAAgK5wIO7wAjAQALAAgK5wIO7wAjAQAAAA==.Leonah:BAAANQAECgEIAQABNQAECgUICQAPAAAAAA==.Lexxi:BAAANQAECgMIBQAAAA==.',
Lh='Lhuru:BAAANQADCggIGwABNQAECgkJJgAUALEXAA==.',
Li='Lightbehunt:BAAANQAECgQIEAAAAA==.Lilly:BAAANQADCgYIBgAAAA==.Linestra:BAAANQAECgQICwABNQAECggIGwAWAE8aAA==.Livaless:BAAANQAECgMIAwABNQAECgoKKQAdAEIhAA==.',
Lo='Lorstus:BAAANQABCgYIBgAAAA==.',
Lu='Lucialyn:BAAANQAECgYIBAABNQAECggIEQAPAAAAAA==.Lux:BAAANQAECgEIAQAAAA==.',
Ma='Mahidevran:BAAANQADCggIAgABNQAECgUICQAPAAAAAA==.Maitotoxin:BAAANQADCggIEgAAAA==.Majikarp:BAAANQAECgQIBAAAAA==.Mal:BAAANQADCggIFAABNQAECgYIFAACALYgAA==.Malthaius:BAAANQADCgUIBQAAAA==.Marble:BAAANQADCgYIBgABNQAECgcIBwAPAAAAAA==.Marché:BAAANQAECgEIAQAAAA==.Mastablasta:BAAANQAECgQICgAAAA==.Matfekk:BAAANQADCgEIAQAAAA==.Maursaline:BAABNQAECn8YAAIaAAgKWAtrMwB/AQAaAAgKWAtrMwB/AQAAAA==.Mawks:BAABNQAECn8uAAIhAAoKORtHAACyAgAhAAoKORtHAACyAgAAAA==.',
Me='Meragos:BAAANQADCgEIAQAAAA==.',
Mi='Migzeviltwin:BAAANQAECgEIAQAAAA==.Milk:BAAANQAECgEIAQAAAA==.',
Mo='Moisten:BAAANQADCgMIAwABNQAECgIIAwAPAAAAAA==.Monkent:BAAANQAECgcIBwAAAA==.Monstabull:BAAANQADCgUIBQAAAA==.Morhgana:BAAANQADCgIIAgAAAA==.',
Na='Nallaa:BAAANQAECgYIDgAAAA==.Naranak:BAABNQAECn8cAAIMAAYKMg9DNABCAQAMAAYKMg9DNABCAQAAAA==.',
Ne='Neremian:BAAANQADCgQIBAAAAA==.',
No='Noodles:BAAANQAECgQIBAABNQAECgYIFAADAHUVAA==.',
Ny='Nymara:BAABNQAECn8YAAIMAAgKAhDjKwB+AQAMAAgKAhDjKwB+AQAAAA==.',
Oc='Occan:BAAANQADCgMIAwAAAA==.',
Ol='Oldenglish:BAABNQAECn8cAAIDAAgKKAhZzQCBAQADAAgKKQhZzQCBAQAAAA==.',
On='Ontos:BAABNQAECn8qAAMaAAkKYg6xCgCNAQAaAAkKYg6xCgCNAQAZAAUKzQ6HbwAMAQAAAA==.',
Or='Orrok:BAAANQADCgEIAQAAAA==.',
Os='Osita:BAAANQAECgIIAgAAAA==.',
Pa='Painnkiller:BAABNQAECn8qAAILAAkKRBSEDgD9AQALAAkKRBSEDgD9AQAAAA==.Pallycracker:BAAANQADCgEIAQAAAA==.Parsley:BAABNQAECn8YAAIfAAYK1iCFAgBZAQAfAAYK1iCFAgBZAQABNQAECggIIwAHAKsXAA==.',
Pe='Perriwinkle:BAABNQAECn8tAAIYAAoK8hb1AQDtAQAYAAoK8hb1AQDtAQAAAA==.',
Ph='Phylloxeras:BAABNQAECn8wAAMEAAoKECInAQC1AgAEAAoKECInAQC1AgAXAAEKAAAurAA2AAAAAA==.',
Po='Powders:BAAANQAECgQICQAAAA==.',
Pr='Priopopo:BAAANQABCgIIBAAAAA==.Prophecyrose:BAAANQADCgQIBQAAAA==.Proshot:BAABNQAECn8cAAIhAAcKhRkdAgCSAQAhAAcKhRkdAgCSAQAAAA==.',
Pu='Puddles:BAAANQAECgEIAQAAAA==.',
Py='Pyrasi:BAABNQAECn8iAAILAAgKHROJaQBBAgALAAgKHROJaQBBAgAAAA==.',
Ra='Raccoon:BAABNQAECn8cAAMdAAgKBgomogCRAQAdAAgKBgomogCRAQAfAAEKxw63KwA/AAAAAA==.Ralor:BAAANQADCgQIBAAAAA==.Razza:BAAANQADCggIEgAAAA==.',
Rh='Rhewz:BAAANQADCgYIBgAAAA==.',
Ri='Rivet:BAAANQADCgcIBwABNQAECgoKHQAiAMcYAA==.',
Ro='Roa:BAAANQADCggIFQAAAA==.Rokkuhato:BAAANQAECgEIAQAAAA==.Roronoazoro:BAACNQAFFH8XAAMiAAcKExMeBwDNAQAiAAcKExMeBwDNAQAjAAIKMRHiEQCAAAA1AAQKfy4AAyIACgpEH9sNAH8BACMACQo0G1MfAFQCACIACArKH9sNAH8BAAAA.',
Ry='Ryrin:BAAANQADCgYIBgAAAA==.',
['Rë']='Rëggië:BAAANQAECggICAAAAA==.',
Sa='Saffron:BAAANQAECgIIAwABNQAECggIIwAHAKsXAA==.Samidrac:BAAANQAECgMICgAAAA==.Sammidormu:BAAANQAECgUICwAAAA==.Saphiragosa:BAAANQADCgQIBAAAAA==.Saräha:BAAANQADCggJCwAAAA==.Satoshie:BAAANQAECgYIBgAAAA==.Satòshí:BAAANQADCgQIBAABNQAECgYIBgAPAAAAAA==.Sayang:BAAANQADCgMIAwABNQAECgcIEwAPAAAAAA==.',
Sc='Scerevisiae:BAABNQAECn8eAAMdAAoKdRmmJgDpAgAdAAoKdRmmJgDpAgAeAAEKgBVTbwBAAAAAAA==.',
Se='Sedelis:BAAANQAECgUIDgAAAA==.Selaya:BAAANQAECgMIAwAAAA==.Serafín:BAABNQAECn8uAAIHAAkKbgyGAwBuAQAHAAkKbgyGAwBuAQAAAA==.',
Sh='Shaadra:BAAANQADCgMIAwAAAA==.Shaay:BAAANQAECgEIAQAAAA==.Shadownutt:BAAANQAECgQICAAAAA==.Sharur:BAAANQAECgYICgAAAA==.Shazzam:BAAANQAECggIAwAAAA==.Shieldwall:BAAANQAECgIIAwAAAA==.',
Si='Silanah:BAAANQAECgUICgABNQAECgoKKwAFAC0fAA==.Silveroaks:BAAANQADCgQIBAABNQAECgcIBwAPAAAAAA==.',
So='Somavra:BAAANQAECgYIDAAAAA==.Sopidia:BAAANQAECgQICgAAAA==.Sorvato:BAAANQADCgYICAAAAA==.',
Sp='Spiritholy:BAABNQAECn8ZAAMRAAgKzxT5aADkAQARAAgKzxT5aADkAQAbAAEK8hBMKQAxAAAAAA==.Spiritomb:BAAANQAECgYICgAAAA==.Spúdd:BAABNQAECn8jAAIWAAoK3hMxMwBFAQAWAAoK3hMxMwBFAQAAAA==.',
St='Stamavan:BAABNQAECn8eAAITAAgKqh60CgDEAgATAAgKqh60CgDEAgAAAA==.Strykerius:BAAANQAECgEIAQABNQAECgUICgAPAAAAAA==.',
Su='Sunari:BAAANQADCgcIBwAAAA==.Supermelon:BAAANQAECgYIDQAAAA==.',
Sy='Syena:BAAANQAECgEIAQAAAA==.Sylvanaria:BAABNQAECn8uAAIFAAkKSB/5BwBFAgAFAAkKSB/5BwBFAgAAAA==.Systyx:BAAANQADCgUICQABNQAECgQIBgAPAAAAAA==.',
Ta='Tammirya:BAAANQADCgEIAQAAAA==.',
Te='Television:BAAANQADCgYIBgAAAA==.Teronreborn:BAABNQAECn8qAAIEAAkKzCDTHADfAgAEAAkKzCDTHADfAgAAAA==.',
Th='Thaneer:BAAANQADCgQICAAAAA==.Throstmok:BAABNQAECn8aAAIQAAoK6hf+LQBdAgAQAAoK6hf+LQBdAgAAAA==.Thumbalina:BAAANQADCgYIBgABNQAECgkJIgACAF8RAA==.',
Ti='Tiantu:BAAANQADCggIEgAAAA==.Tideus:BAAANQADCgcIBwAAAA==.Tilingo:BAAANQAECgUIBgAAAA==.',
To='Tongra:BAAANQADCggIHwABNQAECgkJJgAUALEXAA==.Torg:BAABNQAECn8VAAIQAAgKew1oXgB4AQAQAAgKew1oXgB4AQAAAA==.Torgin:BAAANQAECgQICQAAAA==.',
Tr='Trinitea:BAAANQADCgcICAAAAA==.',
Tu='Turgies:BAABNQAECn8nAAMBAAgKGhIyAAGOAQABAAcKahMyAAGOAQAUAAIKqQ6AMwBtAAAAAA==.Turgroka:BAAANQAECgYICAAAAA==.',
['Tí']='Tíffanny:BAAANQAECgQIBQAAAA==.',
Ub='Ubaubadead:BAAANQADCggICgAAAA==.Ubaubajuana:BAABNQAECn8oAAIFAAgKsxnHSAA/AgAFAAgKsxnHSAA/AgAAAA==.',
Ul='Ulfast:BAABNQAECn8qAAIGAAgKYByoDgCeAQAGAAgKYByoDgCeAQAAAA==.',
Va='Vannhellsing:BAABNQAECn8cAAMEAAgKrga2dABFAQAEAAgKrga2dABFAQAXAAMKrAHfnQBVAAAAAA==.Vanyel:BAABNQAECn81AAIUAAoKHBbFAQDpAQAUAAoKHBbFAQDpAQAAAA==.Vardant:BAAANQADCgMIAwABNQAECgYIBgAPAAAAAA==.',
Ve='Vemal:BAABNQAECn8sAAILAAgKFBJEcwAqAgALAAgKFBJEcwAqAgAAAA==.',
Vi='Vidula:BAAANQADCgcICAAAAA==.Vigorous:BAABNQAECn8YAAIOAAgKhQiJIgA1AQAOAAgKhQiJIgA1AQAAAA==.',
Vo='Vociferoy:BAABNQAECn8vAAMLAAoKghjYCgAfAgALAAoKghjYCgAfAgASAAEKpAG1RQArAAAAAA==.Voidsteffan:BAABNQAECn8jAAIeAAgKFQ9PAgBIAQAeAAgKFQ9PAgBIAQAAAA==.',
Vv='Vv:BAACNQAFFH8tAAMjAAgKWyYIAAB3AwAjAAgKWyYIAAB3AwAiAAUKnBnTCgB2AQA1AAQKfysAAyMACgp+JnYFAHsDACMACQqLJnYFAHsDACIABwppJCsKAKYBAAAA.',
Wa='Waterworks:BAAANQAECgQIBQABNQAECgoKLQACAGoPAA==.',
Wi='Willowmoon:BAAANQADCgIIAgAAAA==.',
Wo='Worgenlina:BAAANQAECgEIAQAAAA==.',
Wu='Wushiilock:BAAANQADCgQIBAABNQAFFAcIFwAZAPUWAA==.',
['Wá']='Wárranpeace:BAAANQADCgIIAgAAAA==.',
Xa='Xalmo:BAAANQADCgQIBAABNQAECgcIIgAIAFMVAA==.Xalzi:BAAANQADCgEIAQABNQAECgcIBwAPAAAAAA==.',
Xu='Xul:BAAANQABCggICgAAAA==.',
Xy='Xyphër:BAAANQADCgQIBAABNQAECgUICgAPAAAAAA==.',
Za='Zannytoes:BAABNQAECn8ZAAMkAAgKaAxiMQCNAQAkAAgKaAxiMQCNAQAlAAYKHwvELAAGAQAAAA==.',
Zi='Zie:BAABNQAECn8uAAINAAkKTBLWCwA/AQANAAkKTBLWCwA/AQAAAA==.',
['Ñi']='Ñice:BAACNQAFFH8HAAMgAAQKaRyUAQAYAQAgAAMKqxuUAQAYAQAWAAEK5R0XOgBQAAA1AAQKfzUAAyAACQoXJVYFANACABYACAqhJFMpABUDACAACArjIFYFANACAAAA.',
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
