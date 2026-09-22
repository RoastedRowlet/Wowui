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

local lookup = {'Paladin-Protection','Unknown-Unknown','Priest-Discipline','Warrior-Arms','Warrior-Fury','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Priest-Shadow','Mage-Arcane','DeathKnight-Blood','Monk-Mistweaver','Priest-Holy','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Frost','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DemonHunter-Havoc','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=53,date='2026-09-22',data={Ae='Aegrias:BAAANQAECgcIDwAAAA==.Aerodria:BAABNQAECoEcAAIBAAgKKxQoEQAIAgABAAgKKxQoEQAIAgAAAA==.',
Al='Alanril:BAAANQADCgMIAwAAAA==.Alarthevel:BAAANQAECgMIAwAAAA==.Albince:BAAANQADCgQIBAAAAA==.',
Am='Amellis:BAAANQADCgIIAgAAAA==.',
An='Andreaswar:BAAANQAECgMIAwAAAA==.Anniferal:BAAANQAECgMIBAABNQAFFAIIAgACAAAAAA==.Annisseda:BAAANQAFFAIIAgAAAA==.Anzak:BAAANQAECgEIAQAAAA==.',
Ar='Ardrayshock:BAAANQABCgcJCgAAAA==.Arrhythmia:BAAANQAECgIIAgABNQAFFAMIBQACAAAAAQ==.',
As='Astrayn:BAAANQADCgIIAgAAAA==.',
Az='Azala:BAAANQAECgIJAgAAAA==.Azryx:BAAANQADCgcICQABNQAECggIHwADABUTAA==.Azzy:BAACNQAFFIEFAAIEAAMKmQv3EQDVAAAEAAMKmQv3EQDVAAA1AAQKgSkAAwUACQqqIiIBAFoDAAUACQonISIBAFoDAAQACQqJHzwWADMDAAAA.',
Ba='Bananski:BAAANQADCgcIBwAAAA==.',
Be='Bearpong:BAAANQAECggIAQAAAA==.Beefychunks:BAAANQAECgUJDAAAAA==.',
Bi='Bigdraco:BAAANQADCgEIAQAAAA==.Biggums:BAAANQADCgQIBAAAAA==.Billyspikepd:BAAANQAECgIIBwAAAA==.Billyspikepr:BAAANQADCggIDQABNQAECgIIBwACAAAAAA==.Billyspikerg:BAAANQADCggIEwABNQAECgIIBwACAAAAAA==.',
Bl='Black:BAAANQADCgEJAQAAAA==.Blobcat:BAAANQAECgcIDwAAAA==.Blobknight:BAAANQADCggIFwAAAA==.Bloodhase:BAAANQAECgYJDgAAAA==.Bluecard:BAAANQAFFAIJAgAAAA==.',
Bo='Bothenheim:BAAANQAFFAIJAgAAAA==.Bowdaddy:BAAANQADCgQIBAAAAA==.',
Br='Breakdown:BAAANQAECgMJBAAAAA==.Brewsimmons:BAAANQADCggIEAABNQAFFAYIDgAGAJgKAA==.',
Ca='Cailey:BAAANQAECggIAgABNQAECggICAACAAAAAA==.Calcshortfor:BAAANQADCgQIBAAAAA==.Callamdrake:BAAANQADCgQJBQAAAA==.Callamsvoid:BAAANQADCgEIAQAAAA==.Calyrex:BAAANQADCgEJAQAAAA==.Camazotz:BAAANQADCgYIBgAAAA==.Capulse:BAAANQAFFAIJAgAAAA==.',
Ce='Centri:BAAANQAECggIDwAAAA==.',
Cl='Clapdatazz:BAAANQADCgcIBwAAAA==.Cleverlev:BAAANQADCgUIBwABNQAECgcIEgACAAAAAA==.',
Co='Colapse:BAAANQADCgMIAwAAAA==.',
Cr='Crunchrr:BAAANQADCgEIAQAAAA==.',
Cu='Cubensis:BAAANQADCgcJFgAAAA==.',
Cy='Cyiera:BAAANQAECggICAAAAA==.',
Da='Daeland:BAAANQAECgEIAQAAAA==.Daisyshot:BAABNQAECoEdAAMHAAkKwyJqDwAnAwAHAAgKKiRqDwAnAwAIAAYKERweJgCbAQAAAA==.',
De='Deathsgrace:BAAANQADCggICAAAAA==.Decima:BAAANQAECgYJDwAAAA==.Dejustinfox:BAAANQADCgQIBwAAAA==.Demeter:BAAANQAFFAIIAgAAAA==.Demonpunter:BAAANQAECgQICAABNQAFFAMIBQAJAMUkAA==.',
Di='Diabloa:BAAANQADCgQICAAAAA==.Diamba:BAAANQADCgMIAwAAAA==.Dinoscarr:BAAANQADCgYIEAAAAA==.',
Do='Doohickey:BAAANQADCggICAAAAA==.Doohicky:BAAANQADCggIEAAAAA==.Dorgrim:BAAANQADCgMIAwAAAA==.Dotsndash:BAABNQAECoEcAAIKAAgKwRQQFgBBAgAKAAgKwRQQFgBBAgAAAA==.',
Dp='Dpsshaman:BAAANQABCgYIBgABNQAFFAMIBQAIAA4SAA==.',
Du='Dungpoo:BAAANQADCgEIAQAAAA==.',
Ea='Eargox:BAAANQAECgMIBAAAAA==.',
Ee='Eesa:BAAANQAECgYIAgAAAA==.',
El='Elinia:BAAANQADCgMIBAAAAA==.Elmdor:BAAANQAECgEIAQAAAA==.Elyndra:BAAANQAECgMIBAAAAA==.',
En='Eniacoc:BAAANQAECgEIAQAAAA==.',
Ex='Excentric:BAAANQAECgIIAgABNQAECggIDwACAAAAAA==.',
Fa='Falarth:BAAANQAECgUIBgAAAA==.Falloutman:BAAANQAECgIIAgAAAA==.Farther:BAAANQADCgUIBQABNQAECgkJOwALAAMiAA==.Fayne:BAAANQADCgcICQAAAA==.',
Fe='Felfart:BAAANQADCgUIBQAAAA==.',
Fi='Firefox:BAABNQAECoEXAAIMAAkKChdVIgBDAgAMAAkKChdVIgBDAgAAAA==.',
Fl='Flechillas:BAAANQADCgcIDQAAAA==.Flán:BAAANQAECgMJAwAAAA==.',
Fr='Fraternite:BAAANQADCggIFgAAAA==.',
Fu='Furrymoon:BAAANQADCgcIBwAAAA==.',
Ga='Gabriellad:BAAANQAECgEJAQAAAA==.',
Ge='Gerrakha:BAAANQADCgYJBgABNQAECgEJAQACAAAAAA==.',
Gi='Giterdonee:BAABNQAECoEeAAMFAAkK1h7YAQARAwAFAAkKIh7YAQARAwAEAAQKmBIIpgAQAQAAAA==.',
Go='Gotchoo:BAAANQAECgQICgABNQADCgQJBAACAAAAAA==.Gothmommy:BAAANQAECgYIDQAAAA==.',
Gr='Groldin:BAAANQADCgEIAQABNQADCgQIBAACAAAAAA==.Grumble:BAAANQADCggICAAAAA==.',
['Gõ']='Gõtchoo:BAAANQADCgQJBAAAAA==.',
Ha='Hairball:BAAANQAECgUJCQAAAA==.Hammerthumb:BAAANQADCgcICQABNQAECgUJCgACAAAAAA==.Hardawn:BAAANQABCgEIAQABNQAECgkJOwALAAMiAA==.',
Ho='Hotsoup:BAAANQADCgQJBAAAAA==.Hozzluzzak:BAAANQADCggICAAAAA==.',
Hy='Hyara:BAABNQAECoEpAAIHAAkK+iIcBACkAwAHAAkK+iIcBACkAwAAAA==.',
['Hù']='Hùñtarð:BAAANQAECgEIAgAAAA==.',
Im='Imnaked:BAAANQADCgYIBgABNQAECggIAQACAAAAAA==.',
In='Invisimitch:BAAANQADCgEIAQAAAA==.',
Ip='Ips:BAAANQADCgIIAgABNQADCgUIBQACAAAAAA==.',
Jo='Jordi:BAAANQAECgYJEQAAAA==.Jotarcyon:BAAANQABCgIJAgAAAA==.',
Ju='Jukkes:BAAANQADCgcIBwAAAA==.Justinfox:BAAANQADCgEIAQAAAA==.Juukess:BAAANQADCggJCwAAAA==.',
Ka='Kannarri:BAAANQADCggIDwAAAA==.Kanree:BAACNQAFFIEFAAINAAMK0wJTBADOAAANAAMK0wJTBADOAAA1AAQKgSkAAg0ACQplEXsOACACAA0ACQplEXsOACACAAAA.',
Ke='Kea:BAABNQAECoElAAQDAAkK3yR5AAB6AwAOAAkKBCR5BACAAwADAAkK6yF5AAB6AwAKAAMKfRJRPAC2AAAAAA==.',
Kh='Khaalid:BAAANQADCgQIBAABNQAECggIHwADABUTAA==.Kharok:BAAANQAECgYIBgABNQAECggIHwADABUTAA==.',
Ki='Kincane:BAAANQADCgcICQAAAA==.',
Ko='Korxin:BAABNQAECoElAAMHAAkKbCBFFQD7AgAHAAkKbCBFFQD7AgAIAAUKRA48MQAoAQAAAA==.Kota:BAAANQADCgEIAQAAAA==.',
Ku='Kurnhaspios:BAAANQADCgQIBAAAAA==.Kurquaan:BAAANQAECgIJAgAAAA==.',
Ky='Kydraeth:BAAANQADCgcIEgAAAA==.',
La='Lanstyn:BAABNQAECoEfAAIDAAgKFRPxBAANAgADAAgKFRPxBAANAgAAAA==.Laufey:BAAANQAECgQIEQAAAA==.',
Le='Lemone:BAAANQADCgUIBQAAAA==.Lemonsk:BAAANQADCgUICAAAAA==.Lenton:BAAANQAECgEIAQAAAA==.',
Li='Lightfury:BAAANQADCgYIDAAAAA==.Limone:BAAANQADCgYICAAAAA==.Listradra:BAAANQADCgQIBAAAAA==.',
Lo='Loganwater:BAAANQADCgQIBAAAAA==.Lohcolo:BAAANQAECgEJAQAAAA==.Loinari:BAAANQADCgUICQAAAA==.',
Lu='Ludmylha:BAAANQAECgEIAQAAAA==.Luisda:BAAANQADCggIFwAAAA==.Lull:BAAANQADCggICwAAAA==.Lushil:BAAANQAFFAEIAQAAAA==.',
Ma='Man:BAAANQADCgUIBQAAAA==.Maybell:BAAANQAECgEIAQAAAA==.',
Me='Meepmeepmomp:BAAANQADCgUIBQAAAA==.Megumín:BAAANQADCgUIBQAAAA==.Melt:BAACNQAFFIEEAAMPAAMKRw8uCgChAAAPAAIKBQouCgChAAAJAAEKyxn3HwBXAAA1AAQKgScAAwkACQqeIl0QAAoDAAkACAqbIl0QAAoDAA8ABAqhIUgaAIABAAAA.Mepha:BAABNQAECoEZAAMQAAkKBRYdJgAzAgAQAAgK5BcdJgAzAgARAAgKtAyIJgDAAQAAAA==.',
Mi='Mike:BAABNQAECoE7AAMLAAkKAyI7GABXAwALAAkKASI7GABXAwASAAUKxhNVEQAYAQAAAA==.Mikevoker:BAAANQADCgEIAQABNQAECgkJOwALAAMiAA==.Mipz:BAAANQADCgUIBQAAAA==.Mistfox:BAAANQADCgYIDAAAAA==.Mistmommy:BAAANQAECgUJDAAAAA==.',
Mo='Mommon:BAAANQADCgEIAQAAAA==.Morrighan:BAAANQADCgMIAwAAAA==.',
['Mâ']='Mâlus:BAAANQAECgQIBQAAAA==.',
['Mä']='Märs:BAAANQADCgYICgAAAA==.',
Na='Nadra:BAAANQADCgYJBgAAAA==.Naminé:BAAANQADCgQIBAABNQAECgQIEQACAAAAAA==.Nattyrav:BAABNQAECoEeAAMTAAkKwhclJwCAAgATAAkKwhclJwCAAgAUAAEKPRvIxQBLAAAAAA==.',
Ne='Neemesis:BAAANQAECgQIBAAAAA==.Nemonk:BAAANQAECgcIDAAAAA==.Nerfling:BAAANQADCgYICAAAAA==.',
No='Nocter:BAAANQAECgUIBQAAAA==.Noktor:BAAANQADCgYIBgAAAA==.Noktra:BAAANQAECgQJCwAAAA==.',
Ny='Nymura:BAAANQAECgMJBAAAAA==.',
Oa='Oakhugger:BAAANQAECgUJCgAAAA==.',
Ol='Olyvivia:BAAANQADCgUIBQAAAA==.',
Om='Omgega:BAAANQAECgQIDAAAAA==.',
On='Onichan:BAAANQAECgEIAQABNQAFFAYJDAATACoUAA==.Onimeek:BAABNQAECoEcAAIVAAgKZRhiHQA1AgAVAAgKZRhiHQA1AgAAAA==.Onionknightt:BAAANQAECgEIAQAAAA==.',
Or='Oryn:BAAANQAECggJCwAAAA==.Oryx:BAAANQADCgEIAQAAAA==.',
Pa='Palmpower:BAAANQADCgYICQAAAA==.Palpitations:BAAANQAECgEJAQAAAA==.Paper:BAAANQAFFAMIBQAAAQ==.',
Pe='Peacefullev:BAAANQAECgcIEgAAAA==.Pewpewpew:BAAANQADCggIHAAAAA==.',
Ph='Phantomthief:BAAANQADCgYJDgAAAA==.',
Pi='Pipeleto:BAABNQAECoEYAAIEAAcKOBj7XwDyAQAEAAcKOBj7XwDyAQAAAA==.Pizzaroll:BAABNQAECoEcAAIWAAgKXBRQBQAZAgAWAAgKXBRQBQAZAgAAAA==.',
Po='Podvoddonut:BAAANQADCgYIBgAAAA==.',
Pr='Previdius:BAAANQADCgUIBQAAAA==.Priesstess:BAAANQADCgYICQAAAA==.',
['Pé']='Pépega:BAAANQADCgQIBwAAAA==.',
Ri='Riven:BAAANQADCgYIBgAAAA==.Rixin:BAEBNQAECoEdAAIQAAkKnx6eEQDqAgAQAAkKnx6eEQDqAgAAAA==.',
Ro='Rokom:BAABNQAECoEeAAMFAAkK3BsMCADiAQAFAAYKrB0MCADiAQAEAAQKFRfcoAAfAQAAAA==.Roonrano:BAAANQADCggJCAAAAA==.',
Ru='Runed:BAAANQAECgEIAQAAAA==.',
Ry='Ryuk:BAAANQADCgYJCgAAAA==.',
Sa='Salla:BAAANQADCgYICQAAAA==.Sanlennicus:BAAANQADCggICAAAAA==.Saphh:BAAANQAECgEIAQAAAA==.Saudencheek:BAAANQAECgQIBAAAAA==.',
Se='Seanster:BAAANQAECggJDQABNQAECgkJHwAPAEAXAA==.Senecca:BAAANQAECgUICgAAAA==.',
Sh='Shadowms:BAAANQAECgUJCQAAAA==.Shadowxd:BAAANQAECgUIBgAAAA==.Shamanpwnz:BAAANQAECgQIBgAAAA==.Shambassador:BAAANQAECgUJCAAAAA==.Shamwowha:BAAANQADCgQIBAAAAA==.Sharkdancer:BAAANQAFFAIIAgABNQAFFAUJCgANAEEfAA==.Shaulana:BAAANQADCggJDwAAAA==.Shenwu:BAAANQAECgYJDwAAAA==.Shirokuma:BAAANQAFFAIJAgAAAA==.Shocktopuus:BAAANQADCgQIBAAAAA==.Shwizzle:BAAANQADCggIDgAAAA==.',
Si='Sidvicious:BAAANQADCgUIBAAAAA==.',
Sk='Sköllati:BAAANQADCggIDwAAAA==.',
Sn='Sneakylev:BAAANQAECgcIDAABNQAECgcIEgACAAAAAA==.',
So='Solari:BAABNQAECoEiAAMXAAkKXB8WCQAiAwAXAAkKXB8WCQAiAwAYAAQKghF8EQDlAAAAAA==.Soleon:BAAANQAECgQIBAAAAA==.Solune:BAAANQAECgYIBgAAAA==.Souprage:BAAANQAECgIJAgAAAA==.',
Sp='Spypal:BAAANQADCgYIDAAAAA==.',
St='Stabwei:BAAANQADCggICAAAAA==.',
Sw='Swagmastrflx:BAAANQADCgQIBAAAAA==.Swëëtdee:BAAANQADCgMICAAAAA==.',
Ta='Taehausx:BAAANQAFFAEIAQABNQAFFAYIEAAMAIkbAA==.Taraka:BAAANQADCggICAAAAA==.',
Td='Tdolokk:BAAANQADCgYJEAAAAA==.',
Te='Teeward:BAAANQADCgYIBgAAAA==.Tenath:BAAANQAECgEJAgAAAA==.',
Th='Thaleon:BAAANQADCggICAAAAA==.Thauriel:BAAANQAECgEIAQAAAA==.Therella:BAAANQADCgUIBQAAAA==.',
To='Totemtotebag:BAAANQAECgQICwABNQAECgcJEAACAAAAAA==.',
Tr='Trollztoll:BAAANQADCgIIAgAAAA==.',
Tw='Twochain:BAAANQADCggJCAABNQAECggIAQACAAAAAA==.',
Un='Una:BAAANQADCgQIBAAAAA==.',
Ut='Uthok:BAAANQADCgEJAQAAAA==.',
Uz='Uzol:BAAANQADCgEIAQAAAA==.',
Va='Vacalocà:BAAANQAECgIIAgAAAA==.Valerian:BAAANQAECgQIBgAAAA==.',
Ve='Veinke:BAAANQAECgcIEwAAAA==.Velanthir:BAAANQADCggIFAAAAA==.Veronica:BAAANQABCgYICAAAAA==.Versaacee:BAAANQADCgYIBgAAAA==.Vessarind:BAAANQADCgUIBQAAAA==.',
Vi='Vivrian:BAAANQADCgUIBQAAAA==.',
['Vä']='Vänillaicë:BAAANQADCgcIBwAAAA==.',
Wa='Waally:BAAANQAECgEJAQAAAA==.',
We='Weebsora:BAAANQAECgQIBQAAAA==.',
Wo='Worldtree:BAAANQADCgEIAQAAAA==.',
Xa='Xaelthira:BAAANQADCgcIBwAAAA==.',
Yi='Yimomo:BAABNQAECoEXAAIOAAcKZiA7JQBvAgAOAAcKZiA7JQBvAgAAAA==.',
Za='Zalconn:BAABNQAECoEVAAMZAAgKeiNnCADOAgAZAAcK6yNnCADOAgAaAAIKJCKgRQDFAAAAAA==.Zarrona:BAAANQAECgIIAwABNQAECgQIEQACAAAAAA==.Zayah:BAAANQAECggIDwAAAA==.',
Zi='Zikony:BAAANQADCgYIBgAAAA==.',
Zu='Zuber:BAABNQAECoEdAAIaAAgKGyGhCQDwAgAaAAgKGyGhCQDwAgAAAA==.Zuldag:BAAANQABCgEIAgAAAA==.',
['År']='Årtimus:BAAANQADCgYIDAAAAA==.',
['Üw']='Üwü:BAAANQAECgEIAQAAAA==.',
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
