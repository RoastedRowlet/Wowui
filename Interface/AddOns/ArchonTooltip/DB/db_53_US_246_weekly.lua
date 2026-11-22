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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Mage-Frost','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Druid-Balance','Mage-Arcane','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Rogue-Assassination','Unknown-Unknown','Druid-Feral','Monk-Brewmaster','Hunter-Marksmanship','Priest-Holy','Shaman-Restoration','Hunter-Survival','Paladin-Protection','Shaman-Elemental','Priest-Shadow','DeathKnight-Frost','Mage-Fire','Warrior-Fury','Evoker-Preservation','Priest-Discipline','Warlock-Affliction','Warlock-Destruction','Shaman-Enhancement','Monk-Windwalker',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaron:BAAANQAECgIIAgABNQAECgoKRwABAHUiAA==.Aaronfreeze:BAACNQAFFH8IAAICAAQKqhXLHgCmAAACAAQKqhXLHgCmAAA1AAQKfzYAAgIACgqKIQsfABsDAAIACgqKIQsfABsDAAAA.',
Ab='Abnar:BAABNQAECn8rAAIDAAkKaxXgDADoAQADAAkKaxXgDADoAQAAAA==.',
Ad='Adversaryq:BAAANQADCgYIBwAAAA==.',
Ae='Aecir:BAAANQADCgYIBgAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUICQAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAFFAMIBwAEAAQUAA==.Allformarc:BAAANQAECgUJBgAAAA==.Allmaick:BAAANQADCggIDAAAAA==.Alucard:BAACNQAFFH8FAAIFAAIKAQSOIQBvAAAFAAIKAQSOIQBvAAA1AAQKf0gAAgUACgrhFmc0AEwCAAUACgrhFmc0AEwCAAAA.Alystrasza:BAABNQAECn8uAAMGAAoK3B4gDQD9AgAGAAoK3B4gDQD9AgAHAAcKLg26WABxAQAAAA==.',
Am='Ambivalent:BAABNQAECn8dAAIIAAkKUAkgkQCEAQAIAAkKUAkgkQCEAQAAAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgQICgAAAA==.',
Ar='Arrowsmïth:BAAANQADCgUIBwAAAA==.',
As='Ashenfate:BAAANQAECgYICQABNQAFFAUIFAAJAP0XAA==.',
Au='Auroras:BAAANQAECgIIAgAAAA==.',
Av='Aviaria:BAAANQAECgEIAQAAAA==.',
Ax='Axsenaea:BAAANQADCgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAABNQAECn8zAAMKAAoKLSASDwCNAgAKAAoKLSASDwCNAgALAAEK1QU80AAtAAABNQAFFAMIBwAEAAQUAA==.',
['Aü']='Aütöpsy:BAABNQAECn86AAIMAAoKkhsyEgBgAgAMAAoKkhsyEgBgAgAAAA==.',
Ba='Baarda:BAAANQADCgQIBAABNQAECgkJKQANAHEPAA==.Babylonfive:BAABNQAECn9EAAIOAAoKsCQDBQDSAwAOAAoKsCQDBQDSAwAAAA==.Backstabbath:BAAANQADCgQIBQAAAA==.Banger:BAAANQAECgQIBgAAAA==.',
Be='Beardsy:BAAANQAECgUIAwAAAA==.Belleta:BAAANQAECgEIAgAAAA==.Belligerente:BAABNQAECn80AAIPAAgKUxQbJQByAQAPAAgKUxQbJQByAQABNQAECgkJHQAIAFAJAA==.Berserk:BAEBNQAECn8aAAMQAAgKYRaWdAA3AgAQAAgK5BSWdAA3AgARAAYKIBPAHgBdAQABNQAFFAUIBwASABwDAA==.Bertringer:BAAANQAECgMIAwABNQAECgQIBQATAAAAAA==.',
Bi='Bigthiccboi:BAAANQAECgQIBQAAAA==.Bigwave:BAAANQADCggIHwAAAA==.Bigwilli:BAAANQAECgEIAQAAAA==.Bilefiend:BAAANQADCgMIAwAAAA==.Birds:BAACNQAFFH8UAAIJAAUK/RclAgAhAQAJAAUK/RclAgAhAQA1AAQKfzMABAkACgrcIE0GAC0DAAkACgrcIE0GAC0DABQABwoRExoSAN4BAAcAAQoAANK2ACsAAAAA.Birdweiser:BAABNQAFFH8LAAIVAAYKvgfRAwAmAQAVAAYKvgfRAwAmAQABNQAFFAUIFAAJAP0XAA==.Biscuit:BAACNQAFFH8ZAAMCAAkKShzsCwCRAQACAAcKzxzsCwCRAQAWAAYKeg8nFAD+AAA1AAQKfzwAAwIACQr5JUgSAAUDAAIACQrIJUgSAAUDABYACAoRI4UbAKQBAAAA.Bisha:BAABNQAECn9RAAIQAAoKiiOSFQBkAwAQAAoKiiOSFQBkAwAAAA==.Bizcocho:BAABNQAECn8XAAIXAAkKkBURbQDXAQAXAAkKkBURbQDXAQAAAA==.',
Bl='Bloodfern:BAAANQABCgEIAQAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boogsta:BAAANQAECgMIAwABNQAFFAQIBwAXAEsOAA==.Boomkingobrr:BAAANQAECgYICQAAAA==.Boops:BAABNQAFFH8LAAIYAAMKkQrEGQDNAAAYAAMKkQrEGQDNAAABNQAFFAYIDwAGAAsJAA==.Bootysweatt:BAAANQADCggICAAAAA==.Boss:BAABNQAECn8oAAIRAAkKoR+kCwB/AgARAAkKoR+kCwB/AgAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Bunnycakez:BAAANQADCgIIAgAAAA==.Burnsx:BAAANQADCggIGAABNQAFFAgIGAAPAL0ZAA==.',
Bw='Bwoar:BAABNQAECn8xAAIMAAoKDBu+JgBoAgAMAAoKDBu+JgBoAgAAAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Canderis:BAAANQABCgEIAQABNQABCgUICAATAAAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captinfeo:BAAANQADCggICAAAAA==.Captnmurloc:BAABNQAECn8wAAMZAAoKyBpzBACdAgAZAAoKyBpzBACdAgACAAEKNBYdSwFJAAAAAA==.Carriedomb:BAAANQADCgYICQAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQAECgcICwAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAABNQAECn8pAAICAAgK8BWrhwCpAQACAAgK8BWrhwCpAQAAAA==.Chrinn:BAAANQABCgUIBQAAAA==.Church:BAABNQAECn8rAAIFAAoKMxrpHgDGAgAFAAoKMxrpHgDGAgAAAA==.',
Ci='Cirxe:BAABNQAECn8xAAIIAAoK/gWiDgF0AQAIAAoK/gWiDgF0AQAAAA==.',
Cl='Clarkent:BAAANQAECgUICAAAAA==.',
Co='Coms:BAABNQAECn8UAAIOAAgKVAvnxACSAQAOAAgKVAvnxACSAQAAAA==.Cowmoorem:BAAANQADCgEIAQAAAA==.',
Cr='Crayze:BAAANQAECgIIBgAAAA==.Creatinepowa:BAAANQADCgEIAQAAAA==.',
Cu='Curuni:BAAANQAECgQIBAAAAA==.',
['Cø']='Cønstance:BAABNQAECn80AAIJAAoKIiI4BQAIAwAJAAoKIiI4BQAIAwAAAA==.',
Da='Dabai:BAABNQAECn9IAAIOAAoKjBweaQD+AQAOAAoKjBweaQD+AQAAAA==.Dahliaa:BAAANQADCgMIAwAAAA==.Daipailaotie:BAABNQAECn88AAMOAAoKZAws1ABzAQAOAAoKnwss1ABzAQAaAAgKJAdAOADOAAAAAA==.Dalight:BAAANQAECgUICAAAAA==.Dankins:BAABNQAFFH8PAAIYAAUK4B1eCADNAQAYAAUK4B1eCADNAQAAAA==.Darealfarmer:BAAANQADCgcIBwAAAA==.Darkzoomies:BAAANQAECgMIAwAAAA==.Darthravens:BAAANQABCgQIBAAAAA==.',
De='Deathmager:BAAANQAECgQICQAAAA==.Depar:BAAANQAECgMIAwAAAA==.Dethsent:BAAANQAECgIIAgAAAA==.Dette:BAABNQAECn8hAAICAAkKqA/idADVAQACAAkKqA/idADVAQAAAA==.Devourer:BAABNQAECn9iAAIPAAoKHiUlAwCnAwAPAAoKHiUlAwCnAwAAAA==.',
Dk='Dkboss:BAAANQADCgYIEQABNQAECgkJKAARAKEfAA==.',
Do='Doctrdoom:BAAANQADCggIFQABNQAECgoKRwABAHUiAA==.',
Dr='Drafted:BAAANQAECgYIDQAAAA==.Dragondank:BAAANQAFFAEIAgABNQAFFAUIDwAYAOAdAA==.Drukah:BAAANQAECgQIBQAAAA==.',
Dt='Dtrike:BAAANQAECgIIBAAAAA==.',
Ed='Edstark:BAABNQAECn8gAAIEAAcK0wLqZwDZAAAEAAcK0wLqZwDZAAAAAA==.Edwinranger:BAAANQAECggIAQAAAA==.',
El='Elabernathy:BAABNQAECn82AAICAAoKZQ7mXgAKAgACAAoKZQ7mXgAKAgAAAA==.Elchapö:BAAANQAECgMIAwABNQAECgoKRwABAHUiAA==.Elenay:BAABNQAECn8iAAIHAAoKoCBMFQAdAwAHAAoKoCBMFQAdAwAAAA==.Eliarssande:BAAANQAECgYIDAABNQAECgcIHQAYADkbAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAABNQAECn8uAAIGAAkKEyKABQBqAwAGAAkKEyKABQBqAwAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAABNQAECn8zAAIKAAkKiiIkLgB5AgAKAAkKiiIkLgB5AgABNQAFFAMIBQAOALIhAA==.Emulsifier:BAACNQAFFH8FAAIOAAMKsiGtHACxAAAOAAMKsiGtHACxAAA1AAQKf00AAw4ACgrvJQ0CAPEDAA4ACgrvJQ0CAPEDAAUAAQqAFMDuADwAAAAA.Emulslash:BAAANQADCgYIDAABNQAFFAMIBQAOALIhAA==.',
Ev='Evideia:BAAANQADCgQJBAABNQAECgcIKwACAGAhAA==.',
Ex='Expiatory:BAAANQADCgEIAQAAAA==.Expiredbeef:BAAANQADCgYIBgABNQAECgcIDAATAAAAAA==.',
Fa='Farcha:BAAANQAECgUICQAAAA==.',
Fi='Fidge:BAAANQADCgYIBgAAAA==.Finester:BAABNQAECn8hAAMSAAoKACBaDgAQAwASAAoKMx5aDgAQAwAMAAgKhhhweAA/AQAAAA==.',
Fl='Flatline:BAABNQAECn8jAAIBAAkKPxZvrwByAQABAAkKPxZvrwByAQAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Ga='Gagners:BAABNQAECn8aAAMSAAkKARlDLQAxAgASAAcK+hpDLQAxAgAMAAMKEhO5nADPAAABNQAFFAMIBQAOALIhAA==.Gazingo:BAAANQAECggIDwAAAA==.Gazkaash:BAAANQAECgYIBwABNQAECggIDwATAAAAAA==.',
Go='Gorska:BAABNQAECn8kAAIbAAkKuhtcNgCeAgAbAAkKuhtcNgCeAgAAAA==.',
Gr='Grawm:BAAANQAECgYIDgAAAA==.Gritshaman:BAAANQAECgcICgABNQAECgoKRwABAHUiAA==.',
['Gä']='Gämbit:BAAANQAECgUICAAAAA==.',
Ha='Hangman:BAAANQAECgcIDQAAAA==.Hanni:BAAANQAECgUIBQAAAA==.Harakutoo:BAAANQAECgEIAQAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAACNQAFFH8HAAIXAAQKSw7ZHAAMAQAXAAQKSw7ZHAAMAQA1AAQKfzEAAxcACgqdHUctAJECABcACgqdHUctAJECABwAAgqpBDlmADEAAAAA.',
He='Hellshand:BAAANQAECgUICQAAAA==.Helmhammer:BAAANQAECgEIAQAAAA==.',
Hi='Hinxx:BAAANQAECgMIAwAAAA==.',
Ho='Holychaser:BAAANQAECgMJBwAAAA==.Holycrack:BAABNQAECn8fAAIaAAcKSiXSDABhAgAaAAcKSiXSDABhAgABNQAECgoKPwABAEoiAA==.Holycøw:BAAANQAECgEIAQAAAA==.Holydefender:BAAANQADCgMIAwAAAA==.Holyfyree:BAAANQADCgcICAABNQAECgkJKQANAHEPAA==.Holypawk:BAABNQAECn8aAAIaAAkKdhf1GwANAgAaAAkKdhf1GwANAgAAAA==.Holyrock:BAABNQAECn82AAIOAAoKlhgdVQAuAgAOAAoKlhgdVQAuAgAAAA==.Holyyshi:BAAANQADCgQIBAAAAA==.Honorheart:BAAANQADCgcICwAAAA==.',
['Hó']='Hóly:BAAANQADCgEJAQABNQAECgYICQATAAAAAA==.',
Ih='Ihureciv:BAABNQAECn8tAAIWAAoKwR/DIgA3AgAWAAoKwR/DIgA3AgABNQAFFAUICQAcAIYWAA==.',
Ik='Ikur:BAABNQAECn89AAIFAAoKWCA7KADHAgAFAAoKWCA7KADHAgAAAA==.',
In='Infoxicated:BAAANQAECgYIBgABNQAECgoKQQAaAFEgAA==.',
Ip='Ipopkidneys:BAACNQAFFH8cAAMMAAgKnh++BADdAQAMAAYK3R6+BADdAQASAAIKISG3CwCcAAA1AAQKfzAAAwwACgp/Jb4MAKkCAAwACgpPJb4MAKkCABIABAo3JO1QAHoBAAAA.',
Ir='Iroi:BAAANQAECgIIAgAAAA==.',
Is='Iskur:BAAANQAECgYIEQABNQAECgoKPQAFAFggAA==.Isurr:BAAANQAECgUIDQABNQAECgoKPQAFAFggAA==.',
Iv='Ivanapump:BAAANQAECgQIBAAAAA==.',
Ja='Jadhar:BAAANQAECgUICwAAAA==.Jametrok:BAABNQAECn8aAAIOAAgK4BW+lAD6AQAOAAgK4BW+lAD6AQAAAA==.Jarréth:BAAANQAECgEIAQABNQAECgQIBQATAAAAAA==.Jastra:BAAANQADCgcIDgAAAA==.',
Je='Jennyanydots:BAAANQAECgIIAgABNQAFFAkJGwAcANMPAA==.',
Ji='Jiraîya:BAABNQAECn8hAAIbAAkKGhQtTACmAQAbAAkKGhQtTACmAQAAAA==.',
Jo='Jorbar:BAAANQAECgcIDwAAAA==.Jordak:BAABNQAECn8jAAIGAAkKDhxBEwCzAgAGAAkKDhxBEwCzAgAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Julex:BAAANQAECggICAAAAA==.Jumbok:BAABNQAECn8uAAIIAAoKYxMmkwB/AQAIAAoKYxMmkwB/AQAAAA==.Just:BAABNQAECn8wAAMKAAoKRxK6LQB8AQAKAAoKDBK6LQB8AQAdAAQKFAvJdwDEAAAAAA==.',
Ka='Kaddiya:BAAANQAECgEIAQAAAA==.Kaine:BAAANQADCgUIBQAAAA==.Kalinxer:BAAANQAECgUIBgAAAA==.Kallistos:BAABNQAECn8sAAIYAAkKtBV8TwAnAgAYAAkKtBV8TwAnAgAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQAECgQIBgAAAA==.Katalaana:BAAANQAECgEIAQAAAA==.',
Ke='Kevdogg:BAABNQAECn8qAAMIAAkKIwZorwBGAQAIAAkKnAVorwBGAQAeAAEKlQV/DgAuAAAAAA==.Key:BAACNQAFFH8MAAMOAAUKJh/UDgBfAQAOAAUKJh/UDgBfAQAFAAEKbwusJwBOAAA1AAQKfysAAw4ACgowJTQvAAwDAA4ACgowJTQvAAwDAAUABwr/FOR2ALMBAAAA.',
Kh='Khione:BAAANQADCgcIFQAAAA==.',
Ki='Kindsöul:BAAANQAECgQICAABNQAFFAUIFAAJAP0XAA==.',
Ko='Kobol:BAAANQAECggIDAAAAA==.Koluvan:BAAANQADCggIGQAAAA==.Koopa:BAABNQAECn88AAIfAAoKxyAmBAC5AgAfAAoKxyAmBAC5AgAAAA==.',
Kr='Krianii:BAAANQADCgEIAQAAAA==.Krieg:BAAANQAECgYIBgABNQAFFAcIEwAHAOghAA==.Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAACNQAFFH8JAAIcAAUKhhalCgDpAAAcAAUKhhalCgDpAAA1AAQKf2EAAxwACgoVJdcCAK4DABwACgoVJdcCAK4DABcABQrxFIGoABwBAAAA.',
Li='Lillianna:BAABNQAECn8WAAIMAAcKYw5nIgC3AQAMAAcKYw5nIgC3AQAAAA==.Lilmf:BAAANQADCggIDwAAAA==.Lilsensual:BAABNQAECn8fAAIYAAkK5xIFZADhAQAYAAkK5xIFZADhAQABNQAFFAUICQAaADsGAA==.',
Lo='Loads:BAAANQAECgcICwAAAA==.Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.Lolkurtone:BAAANQAECgQIBAAAAA==.',
Lu='Luceus:BAABNQAECn8qAAIaAAoKwxBwHwBzAQAaAAoKwxBwHwBzAQAAAA==.Lucário:BAABNQAECn80AAIQAAkKPyWxFwBaAwAQAAkKPyWxFwBaAwAAAA==.Lugia:BAAANQADCgYJCwAAAA==.Lunadawn:BAABNQAECn8jAAIFAAoK8yDSDQBWAwAFAAoK8yDSDQBWAwAAAA==.Lunastorm:BAACNQAFFH8JAAIgAAUKHwoEDAA9AQAgAAUKHwoEDAA9AQA1AAQKf1oAAiAACgo4H1gIAMgCACAACgo4H1gIAMgCAAAA.Luponero:BAACNQAFFH8hAAMWAAgKYhYkCQBjAQAWAAcKBBYkCQBjAQACAAEKNhjPLgBZAAA1AAQKfykAAxYACgrrILsYAJECABYACgqNILsYAJECAAIAAQoCJOhGAVEAAAAA.',
Ma='Macmn:BAACNQAFFH8NAAIbAAYK6Rq/CQDRAQAbAAYK6Rq/CQDRAQA1AAQKfzEAAhsACgr/JfcFALoDABsACgr/JfcFALoDAAAA.Magej:BAAANQADCgQIBAAAAA==.Mageyouacake:BAAANQADCgQIBgAAAA==.Mamaheals:BAABNQAECn87AAIXAAoK0yHvFwAXAwAXAAoK0yHvFwAXAwAAAA==.Mandos:BAABNQAECn9LAAILAAoKISSFCAACAwALAAoKISSFCAACAwAAAA==.Mantistabogn:BAAANQAFFAEIAQAAAA==.Manzoholy:BAAANQADCgMIAwAAAA==.Maor:BAAANQAECgEIAQAAAA==.',
Me='Merlerk:BAAANQAECgIIAgABNQAFFAcIFgAbACAYAA==.Merlini:BAABNQAECn8sAAMcAAoKYA9wJgD6AQAcAAoKYA9wJgD6AQAhAAUKwiD+BADWAQAAAA==.Metrohexual:BAABNQAECn8vAAIYAAoKth3vGADuAgAYAAoKth3vGADuAgAAAA==.Mets:BAABNQAECn8vAAICAAoKah7TIAC8AgACAAoKah7TIAC8AgABNQAECgoKKgABANIeAA==.',
Mi='Mikasa:BAAANQAECgQIBAABNQAECgYICQATAAAAAA==.Mitzis:BAACNQAFFH8IAAICAAMKOBIXIgCYAAACAAMKOBIXIgCYAAA1AAQKfysAAgIACgpFI5ozANECAAIACgpFI5ozANECAAAA.',
Mn='Mnm:BAAANQAECgUICAAAAA==.',
Mo='Moltiy:BAAANQADCgcIDwAAAA==.Moltten:BAAANQAECgUIDgAAAA==.Moondo:BAECNQAFFH8eAAIHAAcKpiIqAwCVAgAHAAcKpiIqAwCVAgA1AAQKfz8AAwcACgpQJRgFAEEDAAcACgpQJRgFAEEDAAYABgqvD2lMAMoAAAE1AAUUAggCABMAAAAA.',
['Mè']='Mètis:BAABNQAECn8rAAICAAcKYCHpUAB9AgACAAcKYCHpUAB9AgAAAA==.',
Na='Naahx:BAAANQAECgcICgABNQAECgoKJgASAG4iAA==.Nall:BAAANQAECgQIBAAAAA==.Narmer:BAAANQABCgMIAwAAAA==.',
Ne='Nefarius:BAACNQAFFH8GAAIcAAIKVxGpEQCGAAAcAAIKVxGpEQCGAAA1AAQKfzAAAhwACgqEH4ILAC0DABwACgqEH4ILAC0DAAAA.Neuropolis:BAAANQADCgYIBgAAAA==.Neurotics:BAABNQAECn87AAQBAAoKFCRRHAAUAwABAAkKbSJRHAAUAwAiAAcKTCOECQC4AQAjAAUKviHmCwADAQAAAA==.',
Ni='Nighthigh:BAAANQAECgEIAQAAAA==.Nineoneone:BAABNQAECn88AAIXAAoKcBolOgBTAgAXAAoKcBolOgBTAgAAAA==.',
No='Noperr:BAAANQAECggICAAAAA==.',
Nu='Nurmally:BAABNQAECn8ZAAMHAAkKORZSLACfAQAHAAkKORZSLACfAQAGAAQKCQ5WTADLAAABNQAFFAUIBgACAAwPAA==.Nutmilk:BAAANQAECgcICQAAAA==.Nuuot:BAAANQAECgcIDQAAAA==.',
Oc='Ocra:BAABNQAECn8qAAIkAAoKgRL+FADFAQAkAAoKgRL+FADFAQABNQAFFAQICAACAMQRAA==.',
Of='Offspeck:BAAANQAECgQIBQABNQAECgoKRwABAHUiAA==.',
Ol='Oldirtycasta:BAAANQAECgEIAgABNQAECgkJHQAIAFAJAA==.',
On='Onayhawe:BAAANQAECgUIBgAAAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgoKRAAOALAkAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAABNQAECn8sAAIOAAoKRAay8gA3AQAOAAoKRAay8gA3AQAAAA==.Pallysmack:BAAANQADCgEIAQAAAA==.Pandapwr:BAAANQADCgcIDwABNQAECgoKMQAMAAwbAA==.Pandemul:BAAANQADCggICAABNQAFFAMIBQAOALIhAA==.Patrio:BAAANQADCgYICwABNQAECgkJLgAGABMiAA==.Pawkler:BAAANQAECgQIBAABNQAECgkJGgAaAHYXAA==.Pawshira:BAAANQADCgUIBQABNQAECgkJGgAaAHYXAA==.',
Pe='Peachaid:BAEANQAECggIDwAAAA==.Peachie:BAAANQADCgcIBwAAAA==.Peetree:BAABNQAECn82AAIYAAoKJSIlFgAfAwAYAAoKJSIlFgAfAwAAAA==.Perfectcell:BAAANQADCgYICwAAAA==.Petures:BAAANQAECgMIAwAAAA==.',
Ph='Phosphorus:BAACNQAFFH8HAAIQAAQKJQmXLQBzAAAQAAQKJQmXLQBzAAA1AAQKf4gAAxAACgrIIMEtAAYDABAACgq+H8EtAAYDABEACgpFGuUKABwCAAAA.',
Pl='Plagüë:BAACNQAFFH8JAAMKAAUKIwkvCgC2AAAKAAQKIwkvCgC2AAALAAIKaQy6MAA1AAA1AAQKf0YAAwoACgoQIw4SACcDAAoACgpUIg4SACcDAAsACQr4Hh0XAPQCAAAA.Pluckedchkn:BAAANQAECgIIBgABNQAFFAUICQAaADsGAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAAANQAECgUIEwAAAA==.Primalistic:BAAANQAECgQIBQAAAA==.',
Pu='Pullnprey:BAAANQADCggIDgAAAA==.Purgedoctor:BAABNQAFFH8IAAIYAAMK8h0nFQAIAQAYAAMK8h0nFQAIAQAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAACNQAFFH8ZAAIBAAgKKCCXAQCTAgABAAgKKCCXAQCTAgA1AAQKfzgAAwEACgpVJpMLAHADAAEACgpVJpMLAHADACIAAgrpGVwdAI0AAAAA.',
Qu='Quietrevenge:BAAANQADCgQIBAAAAA==.',
Ra='Ravenofchaos:BAAANQADCggIDAAAAA==.Ravenoflight:BAAANQAECgIIAwAAAA==.Ravenshatred:BAAANQAECgUIDQAAAA==.Ravenslight:BAAANQABCgQIBAAAAA==.Ravenswrath:BAAANQADCgcIEwAAAA==.Ravenuchiha:BAAANQAECgMIAwAAAA==.Rawrsaur:BAAANQAECgYIDgAAAA==.',
Re='Really:BAAANQAECgcIDAAAAA==.Reallyhpal:BAAANQAECgcIEAAAAA==.Recon:BAAANQADCgMIAwABNQAECgoKGAAHALAFAA==.Redpocket:BAAANQAECgIIAgAAAA==.Rein:BAABNQAECn8dAAIRAAYKbQiHJgDGAAARAAYKbQiHJgDGAAAAAA==.Remin:BAAANQAECgUIBQAAAA==.Retaliator:BAAANQAECgEIAQAAAA==.Reuuín:BAAANQADCggIDAABNQAECgoKIwASAJocAA==.Revan:BAAANQADCggIDgAAAA==.',
Ri='Riitari:BAAANQAECgUIBQABNQAECgoKKgABANIeAA==.Rimooru:BAABNQAECn8cAAIWAAoKxBaRDgBTAgAWAAoKxBaRDgBTAgABNQAFFAMIBwAEAAQUAA==.Risquae:BAAANQAECgEIAQAAAA==.',
Ro='Romulis:BAAANQAECgQIBgAAAA==.Rooms:BAAANQADCgIIAgAAAA==.Rosè:BAABNQAECn81AAIGAAoKCBwcDQD3AgAGAAoKCBwcDQD3AgABNQAECgoKSwALACEkAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.',
Ry='Ryguyro:BAAANQADCgIJAgAAAA==.Ryhia:BAAANQAECgIIAgABNQAECgoKSwALACEkAA==.Ryzee:BAABNQAECn8mAAIIAAoKOhJ3sAAiAgAIAAoKOhJ3sAAiAgABNQAECgoKMwAbANkbAA==.',
['Rí']='Ríco:BAAANQADCgYIDgAAAA==.',
Sa='Sajaboy:BAAANQADCgIIAgAAAA==.Salena:BAAANQAECgQIBwAAAA==.Sans:BAAANQAECggIEQABNQAECgoKWgAbAG0TAA==.Sartha:BAABNQAECn80AAIOAAoKNRcUYgAOAgAOAAoKNRcUYgAOAgAAAA==.Sasuka:BAABNQAECn8dAAMYAAcKORvsQAARAgAYAAcKORvsQAARAgAbAAMKAg8C8AC2AAAAAA==.Savagesoso:BAAANQADCgQJBAAAAA==.',
Sc='Schy:BAAANQAECgIIAgAAAA==.Scratsxd:BAAANQAECggIBQAAAA==.Scrumpheals:BAAANQAECgEIAQABNQAECgIIAQATAAAAAA==.Scrumpvincet:BAAANQAECgIIAQAAAA==.',
Se='Sedda:BAACNQAFFH8JAAIOAAUKDx/BCQCsAQAOAAUKDx/BCQCsAQA1AAQKfygAAg4ACQqCJWIXAGcDAA4ACQqCJWIXAGcDAAAA.Sensual:BAACNQAFFH8JAAIaAAUKOwZWCQCXAAAaAAUKOwZWCQCXAAA1AAQKf0IAAhoACgqIHUEPAKkCABoACgqIHUEPAKkCAAAA.Sesshomaru:BAACNQAFFH8HAAIEAAMKBBSBDwDQAAAEAAMKBBSBDwDQAAA1AAQKf1IAAgQACgrgI7oEAKcDAAQACgrgI7oEAKcDAAAA.',
Sh='Shadoworca:BAAANQADCgQIBAAAAA==.Shampain:BAABNQAECn8hAAMkAAoKXgpZHACeAQAkAAoKXgpZHACeAQAYAAUKug6B3wCqAAABNQAFFAUICAAFAIEaAA==.Shampooh:BAAANQADCggICAAAAA==.Shang:BAACNQAFFH8TAAIHAAcK6CELBwDfAQAHAAcK6CELBwDfAQA1AAQKfzIAAgcACgrtJY4FAKoDAAcACgrtJY4FAKoDAAAA.Shanzo:BAAANQAECggIAwAAAA==.Shiftshot:BAAANQAECgUICAAAAA==.Shiftstab:BAAANQADCgQIBAAAAA==.Shirona:BAABNQAECn80AAMEAAoKWyEpDQDSAgAEAAoKWyEpDQDSAgAPAAcKCgmJOwBqAQAAAA==.Shloomish:BAAANQAECgYIBwAAAA==.Shmized:BAAANQAECgEIAQAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAABNQAECn9KAAIIAAoKHyGgGQDeAgAIAAoKHyGgGQDeAgABNQAFFAMIBwAEAAQUAA==.',
Si='Siare:BAABNQAECn8qAAIBAAoK0h6QGwCqAgABAAoK0h6QGwCqAgAAAA==.',
Sk='Skeeter:BAABNQAECn8rAAQjAAoK7xeGFADLAQABAAgK+RNYhADbAQAjAAYKtBiGFADLAQAiAAUKvw77EwALAQAAAA==.Skroncer:BAAANQADCgYIEgAAAA==.',
Sl='Slyse:BAAANQAECgEIAQAAAA==.',
Sm='Smokinjawn:BAAANQADCgMIAwAAAA==.Smòtts:BAABNQAECn8nAAIJAAoKsBqmDwBnAgAJAAoKsBqmDwBnAgAAAA==.Smótts:BAAANQAECgEIAQAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAABNQAECgQIBAATAAAAAA==.Snizard:BAABNQAECn8XAAICAAYKIRNXswCdAQACAAYKIRNXswCdAQAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQAECgoKQQAaAFEgAA==.',
So='Soawesome:BAABNQAECn8WAAIbAAYKgAnxnwDHAAAbAAYKgAnxnwDHAAABNQAECgkJHQAIAFAJAA==.Solenoid:BAABNQAECn8nAAMXAAoKMRdLTwD8AQAXAAoKMRdLTwD8AQAcAAYKsQwINwDeAAAAAA==.',
Sp='Spicymustard:BAAANQADCgYICgAAAA==.Springrollz:BAAANQAECgEIAQAAAA==.Spàdes:BAAANQAECgQICgAAAA==.',
Sq='Squírtlé:BAAANQADCgEIAQAAAA==.',
St='Stellanoova:BAABNQAECn8WAAMVAAYKTAa5IQDOAAAVAAUK2ga5IQDOAAAlAAEKFgTFdQAjAAABNQAECgkJKQANAHEPAA==.Stonecolld:BAAANQADCgIIAgAAAA==.Stormbeards:BAAANQADCgcIBwAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarcube:BAAANQAECgUICAABNQAFFAUIFAAJAP0XAA==.Sugarhigh:BAAANQABCgQIBAAAAA==.Sunlight:BAAANQADCggICQAAAA==.Sushirollz:BAAANQAECggICwAAAA==.',
Ta='Taazdingo:BAAANQADCggIEwAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAACNQAFFH8OAAQjAAYK2xc2CACxAAAjAAIKEh42CACxAAAiAAEK9BTQFABRAAABAAMKVg5SOQBGAAA1AAQKfzwAAwEACgpZJPo4AKkCAAEACAqDJPo4AKkCACMAAwrPHXMTAL0AAAAA.',
Te='Teabear:BAAANQAECggIBwAAAA==.',
Th='Thisishard:BAABNQAECn9DAAIIAAoKgxduVAAVAgAIAAoKgxduVAAVAgAAAA==.Thorshammer:BAAANQADCgUIBQAAAA==.Thryen:BAAANQAECgQICwAAAA==.Thundergrasp:BAABNQAECn8zAAIbAAoK2Rv2IQBnAgAbAAoK2Rv2IQBnAgAAAA==.',
To='Toe:BAACNQAFFH8IAAIKAAMKjQk+CQDHAAAKAAMKjQk+CQDHAAA1AAQKfxYAAgoACQp8GPhGAPwBAAoACQp8GPhGAPwBAAAA.Toobestake:BAAANQAECgEIAgABNQAFFAgIIQAWAGIWAA==.Topenga:BAACNQAFFH8IAAICAAQKxBEGIQCcAAACAAQKxBEGIQCcAAA1AAQKf1MAAgIACgpRI/8aACwDAAIACgpRI/8aACwDAAAA.',
Tr='Trunnks:BAAANQAECgcIBgAAAA==.',
Ts='Tsargock:BAAANQADCgUIBAAAAA==.',
Tw='Twicelife:BAAANQAECgUICgABNQAFFAQIBwAQACUJAA==.',
Ty='Typhoid:BAAANQAECggIEAAAAA==.',
['Tñ']='Tñt:BAAANQAECgYICwABNQAECgoKRwABAHUiAA==.',
Um='Umei:BAAANQAECgIIAgAAAA==.',
Ur='Urbek:BAABNQAECn8VAAIHAAcKGyDhLgBoAgAHAAcKGyDhLgBoAgAAAA==.Urthstripe:BAABNQAECn8oAAIGAAoKTxeIHAAjAgAGAAoKTxeIHAAjAgAAAA==.',
Us='Usualsuspect:BAAANQAECgIIAgAAAA==.',
Uw='Uwu:BAAANQAECgUIBQABNQAFFAkJGwAcANMPAA==.',
Va='Valle:BAAANQADCggIDgABNQAFFAkJGwAcANMPAA==.Valoria:BAAANQAECggICAABNQAFFAkJGwAcANMPAA==.',
Ve='Velgabrine:BAAANQAECgQICAABNQAFFAMIBQAOALIhAA==.Veraani:BAAANQADCggICAAAAA==.Verlaria:BAAANQADCgEIAQAAAA==.',
Vi='Viserion:BAABNQAECn8pAAMNAAkKcQ/eDACEAQANAAgK9BDeDACEAQAgAAUKkApxMwD7AAAAAA==.',
Vu='Vue:BAACNQAFFH8IAAIFAAUKgRpSCgCzAQAFAAUKgRpSCgCzAQA1AAQKf10AAgUACgrGH6sbAAYDAAUACgrGH6sbAAYDAAAA.Vulkun:BAAANQAECgMIAwAAAA==.',
Wa='Wakasham:BAACNQAFFH8XAAIkAAYKWSUbAQCmAQAkAAYKWSUbAQCmAQA1AAQKfy4AAiQACgqrJqcAANQDACQACgqrJqcAANQDAAAA.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAABNQAECn8ZAAMEAAkKtSAiFAD9AgAEAAkKtSAiFAD9AgAPAAIKUgjsYwBbAAABNQAFFAgIGAAPAL0ZAA==.',
Wi='Wickedmisery:BAAANQADCgYIBgAAAA==.Witherly:BAAANQAECgIIAwAAAA==.',
Wo='Wolfpacked:BAABNQAECn8bAAIYAAYKFhnpdgCnAQAYAAYKFhnpdgCnAQABNQAECgoKPwABAEoiAA==.Wolfzbåin:BAAANQAECgQIAwAAAA==.',
Wr='Wrbringer:BAAANQADCgEIAQAAAA==.',
Wu='Wunderlust:BAACNQAFFH8IAAIIAAUKhQ1vKgDOAAAIAAUKhQ1vKgDOAAA1AAQKf0cAAggACgqnImAnAEQDAAgACgqnImAnAEQDAAAA.',
Xe='Xeroidz:BAAANQADCgcICgAAAA==.',
Xs='Xscrats:BAAANQAECggIBQAAAA==.',
Ye='Yellowshaman:BAACNQAFFH8JAAIbAAMKpA20GwDkAAAbAAMKpA20GwDkAAA1AAQKfywAAxsACQrpHs0mAOgCABsACQrpHs0mAOgCABgAAQoTDv0AAS0AAAAA.Yerac:BAABNQAFFH8PAAMGAAYKCwlXBwB7AQAGAAYKCwlXBwB7AQAHAAEK4QGNJQA0AAAAAA==.',
Za='Zandelussy:BAABNQAECn9BAAMaAAoKUSCBBgDuAgAaAAkKUSCBBgDuAgAFAAoKkx7tLABxAgAAAA==.Zapper:BAAANQAECgIIBAAAAA==.',
Zu='Zugg:BAAANQAECgYIBgABNQAFFAkJGwAcANMPAA==.Zuriznikov:BAABNQAECn8eAAUGAAgK8w17LACMAQAGAAgK8w17LACMAQAHAAQKCQXAjQCfAAAJAAQKqgc+RgCZAAAUAAEKhAm3RQAuAAABNQAECgkJKQANAHEPAA==.',
['Øf']='Øffspeck:BAABNQAECn9HAAQBAAoKdSIMFwAsAwABAAoKTSAMFwAsAwAiAAoKHhwABQB+AgAjAAcKrCKbDwADAgAAAA==.',
['ßo']='ßoss:BAAANQADCgQIBAABNQAECgkJKAARAKEfAA==.',
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
