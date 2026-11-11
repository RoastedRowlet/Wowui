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

local lookup = {'Warrior-Arms','Hunter-BeastMastery','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','DemonHunter-Vengeance','Warlock-Affliction','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','Druid-Balance','Shaman-Elemental','Druid-Restoration','Paladin-Protection','DeathKnight-Blood','Mage-Frost','Hunter-Survival','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Priest-Discipline','Druid-Guardian','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Paladin-Holy','Monk-Windwalker','Hunter-Marksmanship','Warrior-Protection','Monk-Mistweaver','Monk-Brewmaster','Warrior-Fury',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aakier:BAABNQAECn9AAAIBAAkKIR2FMgD2AgABAAkKIR2FMgD2AgABNQAECgoKNwACAOIkAA==.',
Ac='Acanda:BAAANQAFFAIIAgAAAA==.',
Ad='Aderai:BAAANQADCggICAAAAA==.Adolina:BAABNQAECn84AAIDAAkKfRxTMQCbAgADAAkKfRxTMQCbAgAAAA==.',
Ak='Akier:BAAANQAECgMIAwABNQAECgoKNwACAOIkAA==.Akkier:BAABNQAECn83AAICAAoK4iTUBABkAwACAAoK4iTUBABkAwAAAA==.',
Ap='Applebutter:BAAANQAECgIIBQAAAA==.',
Ar='Arylia:BAAANQAECgQIBQAAAA==.',
As='Asmodeus:BAABNQAECn8ZAAMEAAkK0hpyGgCFAgAEAAkK0hpyGgCFAgAFAAEK7AZUmwAoAAABNQAFFAQIBwAGAEsMAA==.Asuna:BAAANQAECgYIEwAAAA==.',
At='Atilia:BAAANQADCgQIBAABNQAECggIJAAHAOAhAA==.Atmosfear:BAAANQADCgQIBAAAAA==.',
Ax='Axeldar:BAAANQAECgYIBgAAAA==.',
Az='Azucena:BAAANQAECgEIAQAAAA==.',
Ba='Bananos:BAACNQAFFH8NAAIIAAUKWBF2AQAwAQAIAAUKWBF2AQAwAQA1AAQKfzMAAggACgqCHCACAA8DAAgACgqCHCACAA8DAAAA.',
Be='Berrako:BAAANQADCgQIBAAAAA==.',
Bi='Billie:BAABNQAECn8wAAIJAAcK4QYVLADZAAAJAAcK4QYVLADZAAAAAA==.',
Bl='Blooddk:BAABNQAECn8rAAQIAAoKXyKSAACjAwAIAAoKJCKSAACjAwAKAAkKuR2DAwAKAwALAAMKIgoLDAG0AAABNQAFFAcIEgAMAIcaAA==.',
Bo='Boojum:BAAANQAECgcIEAAAAA==.Booze:BAAANQAECggICwAAAA==.',
Ca='Callwin:BAAANQAECggICwABNQAECgkJKAANAFQYAA==.',
Ch='Chachisimo:BAABNQAECn8bAAIMAAkKHySIGQBvAwAMAAkKHySIGQBvAwAAAA==.Chivasaurus:BAAANQAECgIIAgABNQAFFAYIEgAOAE4GAA==.',
Co='Covenant:BAAANQAECgYICAAAAA==.',
Cr='Crunksmash:BAABNQAECn8dAAIPAAkKPQ5HKQDVAQAPAAkKPQ5HKQDVAQAAAA==.',
Da='Dashcookin:BAAANQAECgEIAQAAAA==.',
De='Demonbaked:BAAANQAECgIIAgABNQAFFAQIDQAQAHgbAA==.Derpybômb:BAAANQADCgQIBAAAAA==.Dezyre:BAAANQAECggIEAAAAA==.',
Di='Dillon:BAAANQAECgcIEQAAAA==.',
Do='Donlobö:BAAANQADCggIDQAAAA==.Dora:BAABNQAECn8uAAIRAAoKchuCGAAwAgARAAoKchuCGAAwAgAAAA==.Dorim:BAAANQAECgEIAQAAAA==.',
El='Elmono:BAACNQAFFH8UAAMSAAcKhgt8CACGAAAMAAUKiQ1kLgAeAQASAAIKgQh8CACGAAA1AAQKf1YAAwwACgqPHtc2AF4CAAwACgp7G9c2AF4CABIABwoKGgUeAP0AAAAA.Elohan:BAAANQAECgUIBQABNQAECgoKNwACAOIkAA==.',
Er='Erther:BAABNQAECn8XAAICAAgKDCEOWwBjAgACAAgKDCEOWwBjAgAAAA==.',
Fa='Far:BAACNQAFFH8LAAICAAYKQQr7DAASAQACAAYKQQr7DAASAQA1AAQKfzoAAwIACgp/Hx8yANYCAAIACgpXHB8yANYCABMACQpJGuoGAKYBAAAA.',
Fe='Feral:BAAANQAECggICQAAAA==.Feralscale:BAAANQAECgIIAgAAAA==.',
Fl='Flaman:BAAANQADCgEIAQAAAA==.Flashstep:BAABNQAECn8kAAMUAAkKVRL1UACjAQAUAAkKVRL1UACjAQAJAAEKrwnCYgA0AAAAAA==.',
Fo='Foofiqt:BAACNQAFFH8GAAIVAAQK+xL6FwAiAQAVAAQK+xL6FwAiAQA1AAQKfy0ABBUACgqsHFMeAPgCABUACgqsHFMeAPgCABYABAq1F8AnAC8BABcAAwr6DNwaAJIAAAAA.Foxinahat:BAAANQADCgQIAgAAAA==.',
Fr='Frostshock:BAAANQADCgEIAQAAAA==.',
Fu='Fuddytotem:BAABNQAECn8ZAAIDAAgK4R2ZNgCEAgADAAgK4R2ZNgCEAgAAAA==.',
Fz='Fzy:BAAANQAECgEIAQABNQAECggIGQADAOEdAA==.Fzydin:BAAANQAECgEIAgABNQAECggIGQADAOEdAA==.',
Ge='Geus:BAAANQAECggIEwAAAA==.',
Go='Goosejewce:BAABNQAECn9GAAMOAAoKfR3QGAA0AwAOAAkK4h7QGAA0AwADAAQK1x5hawBbAQAAAA==.',
Gr='Gremmil:BAAANQADCgQIBAAAAA==.Grimscar:BAAANQAECgYIBgAAAA==.Grow:BAAANQAECggICAAAAA==.',
Gw='Gweg:BAACNQAFFH8MAAICAAQKABvaEQDuAAACAAQKABvaEQDuAAA1AAQKfy4AAgIACgobIkEtAOYCAAIACgobIkEtAOYCAAAA.',
Ha='Hades:BAACNQAFFH8IAAICAAYK0RI5CgCnAQACAAYK0RI5CgCnAQA1AAQKf14AAgIACgrYJOMIAD0DAAIACgrYJOMIAD0DAAAA.Halarda:BAACNQAFFH8WAAICAAYKBBU2CQBFAQACAAYKBBU2CQBFAQA1AAQKfzcAAgIACgr7IIUpAPICAAIACgr7IIUpAPICAAAA.',
Ho='Hooves:BAACNQAFFH8cAAIYAAcKBwWzAgD9AAAYAAcKBwWzAgD9AAA1AAQKf1cAAhgACgoqGEwPAG4CABgACgoqGEwPAG4CAAAA.',
Ic='Icphunter:BAAANQADCggIBwAAAA==.',
Il='Ilythya:BAAANQADCgcIFQAAAA==.',
Is='Issolde:BAABNQAECn8YAAMZAAgKgRhoPwDMAQAZAAcKJBloPwDMAQAaAAcK2BazWwChAQABNQADCgcICAAbAAAAAA==.',
Iz='Izthefoofi:BAAANQAECgEIAQABNQAFFAQIBgAVAPsSAA==.',
Ja='Jaelana:BAABNQAECn9WAAMcAAoK/wpzEgDXAQAcAAoK/wpzEgDXAQADAAgK3Q6piwBsAQAAAA==.Jazigor:BAAANQADCggIGQAAAA==.',
Jo='Josuboxxu:BAABNQAECn9CAAMdAAoKtCFwAwBxAwAdAAoKtCFwAwBxAwAeAAIK5RJTLgB0AAAAAA==.',
Ju='Judgyslap:BAAANQADCgUIBQAAAA==.',
Ka='Kamikozy:BAACNQAFFH8FAAIMAAMKGiHlKwCyAAAMAAMKGiHlKwCyAAA1AAQKf10AAwwACgqxJcALAKcDAAwACgqxJcALAKcDABIAAQrCGek0AEwAAAAA.Kanden:BAAANQAECggICAABNQAECgkJKAANAFQYAA==.Kasharas:BAABNQAECn8sAAIDAAoKKg/ddQCqAQADAAoKKg/ddQCqAQAAAA==.Kassandruh:BAAANQAECgcICQAAAA==.Kazden:BAAANQAECggICQABNQAECgkJKAANAFQYAA==.',
Kh='Khain:BAAANQADCggICAAAAA==.Khealer:BAABNQAECn8eAAIVAAgKbhrbVgAeAgAVAAgKbhrbVgAeAgAAAA==.',
Ki='Kindi:BAABNQAECn8uAAMfAAkKNyG0KgBsAgAfAAgK0CC0KgBsAgAGAAkKWh5CTAA2AgAAAA==.Kitymeowmeow:BAACNQAFFH8aAAIgAAcKiSE3AwA6AgAgAAcKiSE3AwA6AgA1AAQKf1MAAiAACgqUJsMAAIIDACAACgqUJsMAAIIDAAAA.',
Kl='Klausnomi:BAACNQAFFH8SAAIOAAYKTgY7DAACAQAOAAYKTgY7DAACAQA1AAQKf1YAAg4ACgoUHa0YAJgCAA4ACgoUHa0YAJgCAAAA.',
Ko='Korlo:BAAANQAECgEIAQABNQAECgQIBQAbAAAAAA==.Kowalzky:BAAANQADCgcIDQAAAA==.',
Kr='Krixer:BAAANQAECgQIBgAAAA==.',
['Kà']='Kàndin:BAABNQAECn8oAAINAAkKVBiaJADDAQANAAkKVBiaJADDAQAAAA==.',
La='Lamorak:BAABNQAECn8bAAIBAAkKMhmtTgCdAgABAAkKMhmtTgCdAgAAAA==.Lastdance:BAAANQAECgcIEQAAAA==.',
Li='Lilpsycho:BAAANQADCgQIBAAAAA==.',
Lo='Lokie:BAAANQAECgYIBwAAAA==.Loldroodood:BAAANQADCgYIDwAAAA==.',
Lu='Lucia:BAABNQAECn8VAAIGAAYKEAsQ9QAzAQAGAAYKEAsQ9QAzAQAAAA==.',
Ma='Mafesto:BAABNQAECn8uAAILAAoKaRQROgAaAgALAAoKaRQROgAaAgAAAA==.Magnusbane:BAAANQADCgIIAgABNQAECgIIAwAbAAAAAQ==.Malaqor:BAABNQAECn8kAAIHAAgK4CGjBQDRAgAHAAgK4CGjBQDRAgAAAA==.Manwe:BAAANQADCgQIBQAAAA==.Maylida:BAAANQADCgEIAQABNQAFFAcIEgAMAIcaAA==.',
Mo='Monado:BAACNQAFFH8PAAMCAAUKDxiyCAC/AQACAAUKDxiyCAC/AQAhAAEK9AXQJQA+AAA1AAQKfxUAAwIACQpEHJo1AMoCAAIACApMHZo1AMoCACEABArkEztNAPwAAAAA.Monkbluhd:BAAANQADCgQIBAAAAA==.Montedk:BAABNQAECn8qAAIaAAkKHhngHgDXAQAaAAkKHhngHgDXAQAAAA==.Moonjuice:BAABNQAECn8ZAAIPAAgKoBPFJwDiAQAPAAgKoBPFJwDiAQAAAA==.Moonlightt:BAAANQAECgIIAgAAAA==.Moosetameatu:BAABNQAECn9AAAIiAAoKMyNnAwD6AgAiAAoKMyNnAwD6AgAAAA==.Moscco:BAAANQADCgMIAwABNQAECgkJJAAUAFUSAA==.',
My='Myppburns:BAAANQAECgMIAwAAAA==.',
Na='Nahaii:BAAANQAECgUIBgABNQAFFAYICwACAEEKAA==.Nakskao:BAAANQAECggIEQABNQAFFAcIEgAMAIcaAA==.',
Ne='Necrogenesis:BAABNQAECn8/AAQRAAoKehxeLABmAgARAAkKKhheLABmAgAaAAcKAhpjOQA/AgAZAAgKmBlvPACVAQAAAA==.Nelos:BAABNQAECn89AAIjAAoK7Ro/DgCfAgAjAAoK7Ro/DgCfAgAAAA==.Neovisus:BAAANQAECgQIBAABNQAECgoKPwARAHocAA==.',
Ni='Nineline:BAAANQADCgUICAABNQAECgkJGQAkANYhAA==.Nitroglycern:BAAANQAECgEIAQAAAA==.Nixhar:BAAANQAECgQIBAABNQAECgIIAwAbAAAAAQ==.',
No='Nothelping:BAAANQADCgUIBQAAAA==.',
Od='Odjinn:BAAANQABCgYIBgAAAA==.',
On='Onym:BAAANQAECgMIBQABNQAECgkJKAANAFQYAA==.',
Pa='Parrudo:BAAANQAECgEIAQAAAA==.',
Pi='Pinkember:BAAANQADCgQIBAAAAA==.',
Po='Poisontips:BAAANQADCgUIBQAAAA==.',
Pr='Prettymu:BAAANQADCgIIAQAAAA==.',
Sa='Sadler:BAAANQADCgMIAwAAAA==.Sake:BAABNQAECn8nAAMaAAoK/Rp1NQBSAgAaAAkKlBt1NQBSAgAZAAUKdRBGcwC/AAABNQAECggICwAbAAAAAA==.Sakurá:BAAANQABCgMIAwABNQAECgQIBQAbAAAAAA==.Sanctu:BAACNQAFFH8HAAIGAAQKSwysGgCsAAAGAAQKSwysGgCsAAA1AAQKfzMAAwYACgpEIR4sABcDAAYACgpEIR4sABcDAB8AAwrvC1oIAWcAAAAA.',
Se='Servusnape:BAAANQABCgEIAQAAAA==.Setchyshock:BAAANQAECgQIBAAAAA==.',
Sh='Shulgin:BAABNQAECn8mAAINAAkKaRuVIADIAgANAAkKaRuVIADIAgAAAA==.',
Si='Silvia:BAAANQAECgYIBQAAAA==.',
Sk='Skankie:BAAANQAECgUIBQAAAA==.',
So='Sonari:BAAANQAECgcICgAAAA==.',
Su='Superspike:BAACNQAFFH8cAAISAAcKIRV7AAD3AQASAAcKIRV7AAD3AQA1AAQKf08AAhIACgplJdAAAFIDABIACgplJdAAAFIDAAAA.Superspikee:BAABNQAECn8aAAIGAAoKSBjWQgBSAgAGAAoKSBjWQgBSAgABNQAFFAcIHAASACEVAA==.Surlockedin:BAABNQAECn8fAAQIAAkKmBSbFQDxAAALAAcKlRH/mwCgAQAIAAQKIBSbFQDxAAAKAAMKww+rRwCpAAAAAA==.',
Ta='Taekay:BAACNQAFFH8YAAIRAAcKThuABwDtAQARAAcKThuABwDtAQA1AAQKfyIAAxEACgqKI0INALsCABEACgqKI0INALsCABoABQq1Dc+cAMQAAAAA.Takamine:BAAANQAECgQIBQAAAA==.Talokan:BAAANQAECgIIAgABNQAECgQIBQAbAAAAAA==.',
Te='Teletubi:BAAANQAFFAIIAwAAAA==.',
Th='Thehunter:BAAANQAECggIDwAAAA==.Thezoolander:BAAANQABCgIIBAAAAA==.Thronn:BAAANQAECgEIAgABNQAECggICwAbAAAAAA==.',
To='Tocafogo:BAAANQAECgEIAQAAAA==.',
Tu='Tullkas:BAAANQADCgEIAQAAAA==.',
Va='Vanillarista:BAACNQAFFH8PAAIWAAYKrxlQBQBOAQAWAAYKrxlQBQBOAQA1AAQKfycAAhYACgoaIroPAPkCABYACgoaIroPAPkCAAAA.',
Ve='Vellara:BAAANQABCgIIAgAAAA==.',
Wa='Warmongering:BAAANQAECggIAQAAAA==.',
We='Wesdarian:BAAANQAECgIIAgAAAA==.',
Xi='Xirious:BAAANQAECgMIAwABNQAECgoKMAAlALocAA==.',
Ze='Zero:BAACNQAFFH8MAAIEAAcK4QlWBAA3AQAEAAcK4QlWBAA3AQA1AAQKf1cAAgQACgpxIRQIAM8CAAQACgpxIRQIAM8CAAAA.',
['Ís']='Ísolde:BAAANQADCgcICAAAAA==.',
['Îs']='Îsolde:BAABNQAECn8ZAAIUAAkKOA40QgDcAQAUAAkKOA40QgDcAQABNQADCgcICAAbAAAAAA==.',
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
