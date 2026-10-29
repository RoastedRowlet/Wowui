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

local lookup = {'Warrior-Arms','Hunter-BeastMastery','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','Priest-Holy','DemonHunter-Vengeance','Warlock-Affliction','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','Druid-Balance','Shaman-Elemental','Druid-Restoration','Paladin-Protection','DeathKnight-Blood','Mage-Frost','Hunter-Survival','Rogue-Subtlety','Priest-Discipline','Priest-Shadow','Druid-Guardian','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Paladin-Holy','Monk-Windwalker','Hunter-Marksmanship','Warrior-Protection','Monk-Mistweaver','Monk-Brewmaster','Warrior-Fury',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aakier:BAABNQAECn9AAAIBAAkKIR2FMgD2AgABAAkKIR2FMgD2AgABNQAECgoKHQACAIEfAA==.',
Ac='Acanda:BAAANQAFFAIIAgAAAA==.',
Ad='Aderai:BAAANQADCggICAAAAA==.Adolina:BAABNQAECn83AAIDAAkKfRxTMQCbAgADAAkKfRxTMQCbAgAAAA==.',
Ak='Akier:BAAANQAECgMIBAABNQAECgoKHQACAIEfAA==.Akkier:BAABNQAECn8dAAICAAoKgR+tDgDZAgACAAoKgR+tDgDZAgAAAA==.',
Ap='Applebutter:BAAANQAECgEIBwAAAA==.',
As='Asmodeus:BAABNQAECn8ZAAMEAAkK0hpyGgCFAgAEAAkK0hpyGgCFAgAFAAEK7AZUmwAoAAABNQAFFAQIBwAGAEsMAA==.Asuna:BAABNQAECn8VAAIHAAcKvR0ASwBEAgAHAAcKvR0ASwBEAgAAAA==.',
At='Atilia:BAAANQADCgQIBAABNQAECggIJAAIAOAhAA==.Atmosfear:BAAANQADCgQIBAAAAA==.',
Ax='Axeldar:BAAANQAECgYIBwAAAA==.',
Az='Azucena:BAAANQAECgEIAQAAAA==.',
Ba='Bananos:BAACNQAFFH8IAAIJAAQKGAzzAADbAAAJAAQKGAzzAADbAAA1AAQKfzEAAgkACgoMHCACAA8DAAkACgoMHCACAA8DAAAA.',
Be='Berrako:BAAANQADCgQIBAAAAA==.',
Bi='Billie:BAABNQAECn8kAAIKAAYKYAYrLgC2AAAKAAYKYAYrLgC2AAAAAA==.',
Bl='Blooddk:BAABNQAECn8rAAQJAAoKXyKSAACjAwAJAAoKJCKSAACjAwALAAkKuR2DAwAKAwAMAAMKIgoLDAG0AAABNQAFFAYIEQANAEwdAA==.',
Bo='Boojum:BAAANQAECgcIEQAAAA==.Booze:BAAANQAECgcICgAAAA==.',
Ca='Callwin:BAAANQAECggICAABNQAECgkJKAAOAFQYAA==.',
Ch='Chachisimo:BAABNQAECn8bAAINAAkKHySIGQBvAwANAAkKHySIGQBvAwAAAA==.Chivasaurus:BAAANQAECgIIAgABNQAFFAYIEQAPAE4GAA==.',
Co='Covenant:BAAANQAECgUIDAAAAA==.',
Cr='Crunksmash:BAABNQAECn8dAAIQAAkKPQ5HKQDVAQAQAAkKPQ5HKQDVAQAAAA==.',
Da='Dashcookin:BAAANQAECgEIAQAAAA==.',
De='Demonbaked:BAAANQAECgIIAwABNQAFFAQICQARAOoYAA==.Derpybômb:BAAANQADCgQIBAAAAA==.Dezyre:BAAANQAECggIEgAAAA==.',
Di='Dillon:BAAANQAECgMIBQAAAA==.',
Do='Donlobö:BAAANQADCggIDQAAAA==.Doodlebob:BAAANQAECgEIAgAAAA==.Dora:BAABNQAECn8pAAISAAkKsRtSGADXAQASAAkKsRtSGADXAQAAAA==.Dorim:BAAANQAECgEIAgAAAA==.',
El='Elmono:BAACNQAFFH8TAAMTAAcKhgsWBQCRAAANAAUKiQ1kLgAeAQATAAIKgQgWBQCRAAA1AAQKf0QAAw0ACgqPG3srAEUCAA0ACgpWGnsrAEUCABMABQodFwUeAP0AAAAA.Elohan:BAAANQAECgUIBgABNQAECgoKHQACAIEfAA==.',
Er='Erther:BAABNQAECn8XAAICAAgKDCEOWwBjAgACAAgKDCEOWwBjAgAAAA==.',
Fa='Far:BAACNQAFFH8LAAICAAYKQQpmBwAgAQACAAYKQQpmBwAgAQA1AAQKfzgAAwIACgp6Hx8yANYCAAIACgpSHB8yANYCABQACQpJGjoEALsBAAAA.',
Fe='Feral:BAAANQAECggICQAAAA==.Feralscale:BAAANQAECgIIAwAAAA==.',
Fl='Flaman:BAAANQADCgEIAQAAAA==.Flashstep:BAABNQAECn8eAAIVAAcKVxILIADOAQAVAAcKVxILIADOAQAAAA==.',
Fo='Foofiqt:BAABNQAECn8kAAQHAAoKZhxTHgD4AgAHAAoKZhxTHgD4AgAWAAMK+gzcGgCSAAAXAAEKoQEzTgAhAAAAAA==.Foxinahat:BAAANQADCgQIAgAAAA==.',
Fr='Frostshock:BAAANQADCgEIAQAAAA==.',
Fu='Fuddytotem:BAABNQAECn8ZAAIDAAgK4R2ZNgCEAgADAAgK4R2ZNgCEAgAAAA==.',
Fz='Fzy:BAAANQAECgEIAgABNQAECggIGQADAOEdAA==.Fzydin:BAAANQAECgEIAgABNQAECggIGQADAOEdAA==.',
Ge='Geus:BAAANQAECgQIDAAAAA==.',
Go='Goosejewce:BAABNQAECn89AAMPAAoKDR3QGAA0AwAPAAkKYh7QGAA0AwADAAQK8hrhWQAyAQAAAA==.',
Gr='Gremmil:BAAANQADCgQIBAAAAA==.Grimscar:BAAANQAECgYIBwAAAA==.Grow:BAAANQAECggICAAAAA==.',
Gw='Gweg:BAACNQAFFH8LAAICAAMKABsdCwD6AAACAAMKABsdCwD6AAA1AAQKfy4AAgIACgobIkEtAOYCAAIACgobIkEtAOYCAAAA.',
Ha='Hades:BAACNQAFFH8IAAICAAYK0RI5CgCnAQACAAYK0RI5CgCnAQA1AAQKf0sAAgIACgpYJOMFADIDAAIACgpYJOMFADIDAAAA.Halarda:BAACNQAFFH8VAAICAAUKGxr1CQCqAQACAAUKGxr1CQCqAQA1AAQKfzQAAgIACgq9IIUpAPICAAIACgq9IIUpAPICAAAA.',
Ho='Hooves:BAACNQAFFH8bAAIYAAcKBwWqAQAHAQAYAAcKBwWqAQAHAQA1AAQKf0UAAhgACgqZF1sMAO8BABgACgqZF1sMAO8BAAAA.',
Ic='Icphunter:BAAANQAECgEIAQAAAA==.',
Il='Ilythya:BAAANQADCgcIFQAAAA==.',
In='Infinus:BAAANQAECgEIAwAAAA==.',
Is='Issolde:BAABNQAECn8YAAMZAAgKgRhoPwDMAQAZAAcKJBloPwDMAQAaAAcK2BazWwChAQABNQADCgcICAAbAAAAAA==.',
Iz='Izthefoofi:BAAANQAECgEIAQABNQAECgoKJAAHAGYcAA==.',
Ja='Jaelana:BAABNQAECn9FAAMcAAkKUgk7EQBzAQAcAAkKUgk7EQBzAQADAAcKFA+piwBsAQAAAA==.Jazigor:BAAANQADCggIGQAAAA==.',
Jo='Josuboxxu:BAABNQAECn84AAMdAAoKJyFwAwBxAwAdAAoKJyFwAwBxAwAeAAEKuQQkMAAqAAAAAA==.',
Ju='Judgyslap:BAAANQADCgUIBQAAAA==.',
Ka='Kamikozy:BAACNQAFFH8FAAINAAMKGiFMHQDEAAANAAMKGiFMHQDEAAA1AAQKf08AAw0ACgrIJMALAKcDAA0ACgrIJMALAKcDABMAAQrCGRQnAEwAAAAA.Kasharas:BAABNQAECn8lAAIDAAgK7BHddQCqAQADAAgK7BHddQCqAQAAAA==.Kassandruh:BAAANQAECgcICgAAAA==.Kazden:BAAANQAECggICQABNQAECgkJKAAOAFQYAA==.',
Kh='Khain:BAAANQADCggICAAAAA==.Khealer:BAABNQAECn8eAAIHAAgKbhrbVgAeAgAHAAgKbhrbVgAeAgAAAA==.',
Ki='Kindi:BAABNQAECn8mAAMfAAgKHiGlJAAmAgAfAAcKpSClJAAmAgAGAAcKzBwsaQCEAQAAAA==.Kitymeowmeow:BAACNQAFFH8aAAIgAAcKiSE3AwA6AgAgAAcKiSE3AwA6AgA1AAQKf0EAAiAACgqrJEkCALsDACAACgqrJEkCALsDAAAA.',
Kl='Klausnomi:BAACNQAFFH8RAAIPAAYKTgasBwAIAQAPAAYKTgasBwAIAQA1AAQKf0QAAg8ACgqxF68iAOoBAA8ACgqxF68iAOoBAAAA.',
Ko='Korlo:BAAANQAECgEIAgABNQAECgYIDgAbAAAAAA==.Kowalzky:BAAANQADCgcIDQAAAA==.',
Kr='Krixer:BAAANQAECgQIBQAAAA==.',
['Kà']='Kàndin:BAABNQAECn8oAAIOAAkKVBgKGADZAQAOAAkKVBgKGADZAQAAAA==.',
La='Lamorak:BAABNQAECn8bAAIBAAkKMhmtTgCdAgABAAkKMhmtTgCdAgAAAA==.Lastdance:BAAANQAECgcIEQAAAA==.',
Li='Lilpsycho:BAAANQADCgQIBAAAAA==.',
Lo='Lokie:BAAANQAECgQIBQAAAA==.Loldroodood:BAAANQADCgYIDwAAAA==.',
Lu='Lucia:BAABNQAECn8VAAIGAAYKEAsQ9QAzAQAGAAYKEAsQ9QAzAQAAAA==.',
Ma='Mafesto:BAABNQAECn8cAAIMAAoKPQ1uXABOAQAMAAoKPQ1uXABOAQAAAA==.Magnusbane:BAAANQADCgIIAgABNQAECgIIAwAbAAAAAQ==.Malaqor:BAABNQAECn8kAAIIAAgK4CGjBQDRAgAIAAgK4CGjBQDRAgAAAA==.Manwe:BAAANQADCgQIBQAAAA==.Maylida:BAAANQADCgEIAQABNQAFFAYIEQANAEwdAA==.',
Mi='Mind:BAAANQAECgEIAQAAAA==.',
Mo='Monado:BAACNQAFFH8PAAMCAAUKDxiyCAC/AQACAAUKDxiyCAC/AQAhAAEK9AXQJQA+AAA1AAQKfxUAAwIACQpEHJo1AMoCAAIACApMHZo1AMoCACEABArkEztNAPwAAAAA.Monkbluhd:BAAANQADCgQIBAAAAA==.Montedk:BAABNQAECn8iAAIaAAcKrRrBPAAtAgAaAAcKrRrBPAAtAgAAAA==.Moonjuice:BAABNQAECn8ZAAIQAAgKoBPFJwDiAQAQAAgKoBPFJwDiAQAAAA==.Moonlightt:BAAANQAECgIIAwAAAA==.Moosetameatu:BAABNQAECn8yAAIiAAoKFCEDBQAsAwAiAAoKFCEDBQAsAwAAAA==.Moscco:BAAANQADCgMIAwABNQAECgcIHgAVAFcSAA==.',
Na='Nahaii:BAAANQAECgUIBAABNQAFFAYICwACAEEKAA==.Nakskao:BAAANQAECggIDwABNQAFFAYIEQANAEwdAA==.',
Ne='Necrogenesis:BAABNQAECn89AAQSAAoKzBpeLABmAgASAAkKKhheLABmAgAaAAcKAhpjOQA/AgAZAAgK7xbEKwB+AQAAAA==.Nelos:BAABNQAECn89AAIjAAoK7Rp0BwBuAgAjAAoK7Rp0BwBuAgAAAA==.Neovisus:BAAANQADCgMIAwABNQAECgoKPQASAMwaAA==.',
Ni='Nineline:BAAANQADCgQIBAABNQAECgkJGQAkANYhAA==.Nitroglycern:BAAANQAECgEIAQAAAA==.Nixhar:BAAANQAECgQIBAABNQAECgIIAwAbAAAAAQ==.',
No='Nothelping:BAAANQADCgUIBQAAAA==.',
Od='Odjinn:BAAANQABCgYIBgAAAA==.',
Pa='Parrudo:BAAANQAECgEIAQAAAA==.',
Pi='Pinkember:BAAANQADCgQIBAAAAA==.',
Po='Poisontips:BAAANQADCgUIBQAAAA==.Powersource:BAAANQAECgEIAQAAAA==.',
Pr='Prettymu:BAAANQADCgEIAQAAAA==.',
Sa='Sadler:BAAANQADCgMIAwAAAA==.Sake:BAABNQAECn8kAAMaAAkKtRp1NQBSAgAaAAgKGh11NQBSAgAZAAQKig3YbQB2AAABNQAECgcICgAbAAAAAA==.Sakurá:BAAANQAECgEIAQABNQAECgYIDgAbAAAAAA==.Sanctu:BAACNQAFFH8HAAIGAAQKSwy3EQCzAAAGAAQKSwy3EQCzAAA1AAQKfy8AAwYACgonIB4sABcDAAYACgonIB4sABcDAB8AAwrvC1oIAWcAAAAA.',
Se='Servusnape:BAAANQABCgEIAQAAAA==.Setchyshock:BAAANQAECgQIBAAAAA==.',
Sh='Shulgin:BAABNQAECn8mAAIOAAkKaRuVIADIAgAOAAkKaRuVIADIAgAAAA==.',
Si='Silvia:BAAANQAECgYIBwAAAA==.Sinndh:BAAANQAECgEIAQAAAA==.',
Sk='Skankie:BAAANQAECgQICAAAAA==.',
So='Sonari:BAAANQAECgcIDAAAAA==.',
Su='Superspike:BAACNQAFFH8cAAITAAcKIRV7AAD3AQATAAcKIRV7AAD3AQA1AAQKf0AAAhMACgp7I0ABAIsDABMACgp7I0ABAIsDAAAA.Superspikee:BAAANQAECggICgABNQAFFAcIHAATACEVAA==.Surlockedin:BAABNQAECn8fAAQJAAkKmBSbFQDxAAAMAAcKlRH/mwCgAQAJAAQKIBSbFQDxAAALAAMKww+rRwCpAAAAAA==.',
Ta='Taekay:BAACNQAFFH8VAAISAAYKTByABwDtAQASAAYKTByABwDtAQA1AAQKfyEAAxIACgrqIuwIAMECABIACgrqIuwIAMECABoABQq1Dc+cAMQAAAAA.Takamine:BAAANQAECgQIBQAAAA==.Talokan:BAAANQAECgIIAwABNQAECgYIDgAbAAAAAA==.',
Te='Teletubi:BAAANQAFFAIIAgAAAA==.',
Th='Thehunter:BAAANQADCgEIAQAAAA==.Thezoolander:BAAANQABCgIIBAAAAA==.Thronn:BAAANQAECgEIAQAAAA==.Thunk:BAAANQAECgEIAQAAAA==.',
Tu='Tullkas:BAAANQADCgEIAQAAAA==.',
Va='Vanillarista:BAACNQAFFH8NAAIXAAQKehl2BQAEAQAXAAQKehl2BQAEAQA1AAQKfyUAAhcACgqLIboPAPkCABcACgqLIboPAPkCAAAA.',
Ve='Vellara:BAAANQAECgEIAQAAAA==.',
Wa='Warmongering:BAAANQAECggIAgAAAA==.',
We='Wesdarian:BAAANQAECgIIAgAAAA==.',
Xi='Xirious:BAAANQAECgMIAwABNQAECgoKLQAlADUcAA==.',
Ze='Zero:BAACNQAFFH8LAAIEAAcK4Ql7AgBLAQAEAAcK4Ql7AgBLAQA1AAQKf0MAAgQACgomIAAGALkCAAQACgomIAAGALkCAAAA.',
['Ís']='Ísolde:BAAANQADCgcICAAAAA==.',
['Îs']='Îsolde:BAAANQAFFAEIAQABNQADCgcICAAbAAAAAA==.',
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
