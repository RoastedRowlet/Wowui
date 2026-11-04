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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Mage-Frost','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Druid-Balance','Mage-Arcane','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Rogue-Assassination','Unknown-Unknown','Druid-Feral','Hunter-Marksmanship','Priest-Holy','Shaman-Restoration','Hunter-Survival','Paladin-Protection','Shaman-Elemental','Priest-Shadow','DeathKnight-Frost','Mage-Fire','Warrior-Fury','Evoker-Preservation','Priest-Discipline','Warlock-Affliction','Warlock-Destruction','Shaman-Enhancement','Monk-Brewmaster','Monk-Windwalker',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aaron:BAAANQAECgIIAgABNQAECgoKRQABAHUiAA==.Aaronfreeze:BAACNQAFFH8IAAICAAQKqhXjFwCsAAACAAQKqhXjFwCsAAA1AAQKfzYAAgIACgqKIQsfABsDAAIACgqKIQsfABsDAAAA.',
Ab='Abnar:BAABNQAECn8hAAIDAAgKqRXgDADoAQADAAgKqRXgDADoAQAAAA==.',
Ad='Adversaryq:BAAANQADCgYIBwAAAA==.',
Ae='Aecir:BAAANQADCgYIBgAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUICQAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAFFAMIBwAEAAQUAA==.Allformarc:BAAANQAECgUJBgAAAA==.Allmaick:BAAANQADCggIDAAAAA==.Alucard:BAABNQAECn86AAIFAAoKzRX6NAAVAgAFAAoKzRX6NAAVAgAAAA==.Alystrasza:BAABNQAECn8uAAMGAAoK3B4gDQD9AgAGAAoK3B4gDQD9AgAHAAcKLg26WABxAQAAAA==.',
Am='Ambivalent:BAABNQAECn8cAAIIAAkKHgngewCEAQAIAAkKHgngewCEAQAAAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgQICgAAAA==.',
Ar='Arrowsmïth:BAAANQADCgUIBwAAAA==.',
As='Ashenfate:BAAANQAECgUIBgABNQAFFAUIFAAJAP0XAA==.',
Au='Auroras:BAAANQAECgIIAgAAAA==.',
Av='Aviaria:BAAANQAECgEIAQAAAA==.',
Ax='Axsenaea:BAAANQADCgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAABNQAECn8oAAMKAAoK7B87IADKAgAKAAoK7B87IADKAgALAAEK1QU80AAtAAABNQAFFAMIBwAEAAQUAA==.',
['Aü']='Aütöpsy:BAABNQAECn86AAIMAAoKkhvMKAApAgAMAAoKkhvMKAApAgAAAA==.',
Ba='Baarda:BAAANQADCgQIBAABNQAECgkJJwANAHEPAA==.Babylonfive:BAABNQAECn9EAAIOAAoKsCQDBQDSAwAOAAoKsCQDBQDSAwAAAA==.Backstabbath:BAAANQADCgQIBQAAAA==.Banger:BAAANQAECgQIBgAAAA==.',
Be='Belleta:BAAANQAECgEIAgAAAA==.Belligerente:BAABNQAECn80AAIPAAgKUxRFHQCFAQAPAAgKUxRFHQCFAQABNQAECgkJHAAIAB4JAA==.Berserk:BAEBNQAECn8aAAMQAAgKYRaWdAA3AgAQAAgK5BSWdAA3AgARAAYKIBPAHgBdAQABNQAFFAUIBwASABwDAA==.Bertringer:BAAANQAECgMIAwABNQAECgQIBQATAAAAAA==.',
Bi='Bigthiccboi:BAAANQAECgQIBQAAAA==.Bigwave:BAAANQADCggIGAAAAA==.Bigwilli:BAAANQADCgcIDwAAAA==.Bilefiend:BAAANQADCgMIAwAAAA==.Birds:BAACNQAFFH8UAAIJAAUK/ReOAQArAQAJAAUK/ReOAQArAQA1AAQKfzMABAkACgrcIAUGANMCAAkACgrcIAUGANMCABQABwoRExoSAN4BAAcAAQoAANK2ACsAAAAA.Birdweiser:BAAANQAFFAUIBAABNQAFFAUIFAAJAP0XAA==.Biscuit:BAACNQAFFH8XAAMCAAgKBB/sCwCRAQACAAcKzxzsCwCRAQAVAAUKXhAnFAD+AAA1AAQKfzcAAwIACQrIJTYLABsDAAIACQrIJTYLABsDABUACAoCITwnABECAAAA.Bisha:BAABNQAECn9OAAIQAAoKIyOSFQBkAwAQAAoKIyOSFQBkAwAAAA==.Bizcocho:BAAANQAECgYIEgAAAA==.',
Bl='Bloodfern:BAAANQABCgEIAQAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boogsta:BAAANQAECgMIAwABNQAECgoKMQAWAJ0dAA==.Boomkingobrr:BAAANQAECgYICQAAAA==.Boops:BAABNQAFFH8LAAIXAAMKkQrEGQDNAAAXAAMKkQrEGQDNAAABNQAFFAUIDgAGAEcKAA==.Bootysweatt:BAAANQADCggICAAAAA==.Boss:BAABNQAECn8nAAIRAAgKHx+kCwB/AgARAAgKHx+kCwB/AgAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Bunnycakez:BAAANQADCgIIAgAAAA==.Burnsx:BAAANQADCggIGAABNQAFFAgIGAAPAL0ZAA==.',
Bw='Bwoar:BAABNQAECn8sAAIMAAoKDBvkHgBmAgAMAAoKDBvkHgBmAgAAAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captinfeo:BAAANQADCggICAAAAA==.Captnmurloc:BAABNQAECn8iAAMYAAoKwhlzBACdAgAYAAoKwhlzBACdAgACAAEKNBYdSwFJAAAAAA==.Carriedomb:BAAANQADCgYICQAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQAECgcICwAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAABNQAECn8pAAICAAgK9xVAZQCyAQACAAgK9xVAZQCyAQAAAA==.Chrinn:BAAANQABCgUIBQAAAA==.Church:BAABNQAECn8rAAIFAAoKMxp0FQDgAgAFAAoKMxp0FQDgAgAAAA==.',
Ci='Cirxe:BAABNQAECn8qAAIIAAkKQwWiDgF0AQAIAAkKQwWiDgF0AQAAAA==.',
Cl='Clarkent:BAAANQAECgUICAAAAA==.',
Co='Coms:BAABNQAECn8UAAIOAAgKVAvnxACSAQAOAAgKVAvnxACSAQAAAA==.Cowmoorem:BAAANQADCgEIAQAAAA==.',
Cr='Crayze:BAAANQAECgIIBgAAAA==.Creatinepowa:BAAANQADCgEIAQAAAA==.',
Cu='Curuni:BAAANQAECgQIBAAAAA==.',
['Cø']='Cønstance:BAABNQAECn8zAAIJAAoKJyKnBAD8AgAJAAoKJyKnBAD8AgAAAA==.',
Da='Dabai:BAABNQAECn89AAIOAAoKQBsPbABZAgAOAAoKQBsPbABZAgAAAA==.Dahliaa:BAAANQADCgMIAwAAAA==.Daipailaotie:BAABNQAECn8wAAMOAAoKDAss1ABzAQAOAAoKoAos1ABzAQAZAAUKVQZQVgCIAAAAAA==.Dalight:BAAANQAECgUICAAAAA==.Dankins:BAABNQAFFH8PAAIXAAUK4B1eCADNAQAXAAUK4B1eCADNAQAAAA==.Darealfarmer:BAAANQADCgcIBwAAAA==.Darkzoomies:BAAANQAECgMIAwAAAA==.Darthravens:BAAANQABCgQIBAAAAA==.',
De='Deathmager:BAAANQAECgQICAAAAA==.Depar:BAAANQAECgMIAwAAAA==.Dethsent:BAAANQAECgIIAgAAAA==.Dette:BAABNQAECn8aAAICAAcK1wvA0wBZAQACAAcK1wvA0wBZAQAAAA==.Devourer:BAABNQAECn9iAAIPAAoKHiUxAgBOAwAPAAoKHiUxAgBOAwAAAA==.',
Dk='Dkboss:BAAANQADCgYIEQABNQAECggIJwARAB8fAA==.',
Do='Doctrdoom:BAAANQADCggIFQABNQAECgoKRQABAHUiAA==.',
Dr='Drafted:BAAANQAECgYIDQAAAA==.Dragondank:BAAANQAFFAEIAgABNQAFFAUIDwAXAOAdAA==.Drukah:BAAANQAECgIIAgAAAA==.',
Dt='Dtrike:BAAANQAECgIIBAAAAA==.',
Ed='Edstark:BAABNQAECn8gAAIEAAcK0wLqZwDZAAAEAAcK0wLqZwDZAAAAAA==.Edwinranger:BAAANQAECggIAQAAAA==.',
El='Elabernathy:BAABNQAECn8pAAICAAkK6Q1NZAC1AQACAAkK6Q1NZAC1AQAAAA==.Elchapö:BAAANQAECgMIAwABNQAECgoKRQABAHUiAA==.Elenay:BAABNQAECn8iAAIHAAoKoCBMFQAdAwAHAAoKoCBMFQAdAwAAAA==.Eliarssande:BAAANQAECgYIDAABNQAECgYIFgAXAEoXAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAABNQAECn8uAAIGAAkKEyKABQBqAwAGAAkKEyKABQBqAwAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAABNQAECn8zAAIKAAkKiiIkLgB5AgAKAAkKiiIkLgB5AgABNQAFFAMIBQAOALIhAA==.Emulsifier:BAACNQAFFH8FAAIOAAMKsiFCFQC8AAAOAAMKsiFCFQC8AAA1AAQKf0wAAg4ACgrvJQ0CAPEDAA4ACgrvJQ0CAPEDAAAA.Emulslash:BAAANQADCgYIDAABNQAFFAMIBQAOALIhAA==.',
Ev='Evideia:BAAANQADCgQJBAABNQAECgcIKwACAGAhAA==.',
Ex='Expiatory:BAAANQADCgEIAQAAAA==.Expiredbeef:BAAANQADCgYIBgAAAA==.',
Fa='Farcha:BAAANQAECgUICQAAAA==.',
Fi='Fidge:BAAANQADCgYIBgAAAA==.Finester:BAABNQAECn8hAAMSAAoKACBaDgAQAwASAAoKMx5aDgAQAwAMAAgKhhhFXgBAAQAAAA==.',
Fl='Flatline:BAABNQAECn8dAAIBAAkKAhNvrwByAQABAAkKAhNvrwByAQAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Ga='Gagners:BAABNQAECn8aAAMSAAkKARlDLQAxAgASAAcK+hpDLQAxAgAMAAMKEhOBggDGAAABNQAFFAMIBQAOALIhAA==.Gazingo:BAAANQAECggICAAAAA==.Gazkaash:BAAANQAECgUIBQABNQAECggICAATAAAAAA==.',
Go='Gorska:BAABNQAECn8kAAIaAAkKuhtcNgCeAgAaAAkKuhtcNgCeAgAAAA==.',
Gr='Grawm:BAAANQAECgYIDgAAAA==.Gritshaman:BAAANQAECggICAABNQAECgoKRQABAHUiAA==.',
['Gä']='Gämbit:BAAANQAECgYICAAAAA==.',
Ha='Hangman:BAAANQAECgcIDQAAAA==.Hanni:BAAANQAECgUIBQAAAA==.Harakutoo:BAAANQAECgEIAQAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAABNQAECn8xAAMWAAoKnR0WIACsAgAWAAoKnR0WIACsAgAbAAIKqQThVwAxAAAAAA==.',
He='Hellshand:BAAANQAECgUICQAAAA==.Helmhammer:BAAANQAECgEIAQAAAA==.',
Hi='Hinxx:BAAANQAECgMIAwAAAA==.',
Ho='Holychaser:BAAANQAECgMJBwAAAA==.Holycrack:BAABNQAECn8fAAIZAAcKSiUMCgBpAgAZAAcKSiUMCgBpAgABNQAECgoKOAABADciAA==.Holycøw:BAAANQAECgEIAQAAAA==.Holydefender:BAAANQADCgMIAwAAAA==.Holyfyree:BAAANQADCgcICAABNQAECgkJJwANAHEPAA==.Holypawk:BAABNQAECn8aAAIZAAkKdhf1GwANAgAZAAkKdhf1GwANAgAAAA==.Holyrock:BAABNQAECn8qAAIOAAkK9xY1YADYAQAOAAkK9xY1YADYAQAAAA==.Holyyshi:BAAANQADCgQIBAAAAA==.Honorheart:BAAANQADCgMIBgAAAA==.',
['Hó']='Hóly:BAAANQADCgEJAQABNQAECgYICQATAAAAAA==.',
Ih='Ihureciv:BAABNQAECn8nAAIVAAoK9BnDIgA3AgAVAAoK9BnDIgA3AgABNQAFFAQICAAbAIYWAA==.',
Ik='Ikur:BAABNQAECn83AAIFAAoKnxw7KADHAgAFAAoKnxw7KADHAgAAAA==.',
In='Infoxicated:BAAANQAECgYIBgABNQAECgoKLwAFAJMeAA==.',
Ip='Ipopkidneys:BAACNQAFFH8bAAMMAAcK0SK+BADdAQAMAAUK8CO+BADdAQASAAIKISHYBwCkAAA1AAQKfy8AAwwACgp/JUweAGkCAAwACgpPJUweAGkCABIABAo3JO1QAHoBAAAA.',
Ir='Iroi:BAAANQAECgIJAgAAAA==.',
Is='Iskur:BAAANQAECgYIEQABNQAECgoKNwAFAJ8cAA==.Isurr:BAAANQAECgUIDQABNQAECgoKNwAFAJ8cAA==.',
Iv='Ivanapump:BAAANQAECgQIBAAAAA==.',
Ja='Jadhar:BAAANQAECgYICgAAAA==.Jametrok:BAABNQAECn8aAAIOAAgK4BW+lAD6AQAOAAgK4BW+lAD6AQAAAA==.Jastra:BAAANQADCgcIDgAAAA==.',
Je='Jennyanydots:BAAANQADCggIDAABNQAFFAgIGQAbALoQAA==.',
Ji='Jiraîya:BAABNQAECn8hAAIaAAkKGhT0OwCqAQAaAAkKGhT0OwCqAQAAAA==.',
Jo='Jorbar:BAAANQAECgQIBAAAAA==.Jordak:BAABNQAECn8jAAIGAAkKDhxBEwCzAgAGAAkKDhxBEwCzAgAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Julex:BAAANQAECggICAAAAA==.Jumbok:BAABNQAECn8iAAIIAAoKMRHv4wDBAQAIAAoKMRHv4wDBAQAAAA==.Just:BAABNQAECn8nAAMKAAoKRxJ+JgB8AQAKAAoKDBJ+JgB8AQAcAAQKFAvJdwDEAAAAAA==.',
Ka='Kaddiya:BAAANQAECgEIAQAAAA==.Kaine:BAAANQADCgUIBQAAAA==.Kallistos:BAABNQAECn8sAAIXAAkKtBV8TwAnAgAXAAkKtBV8TwAnAgAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQAECgQIBgAAAA==.Katalaana:BAAANQAECgEIAQAAAA==.',
Ke='Kevdogg:BAABNQAECn8qAAMIAAkKIwbRlwBIAQAIAAkKnAXRlwBIAQAdAAEKlQV/DgAuAAAAAA==.Key:BAACNQAFFH8MAAMOAAUKJh/UDgBfAQAOAAUKJh/UDgBfAQAFAAEKbwusJwBOAAA1AAQKfysAAw4ACgowJTQvAAwDAA4ACgowJTQvAAwDAAUABwr/FOR2ALMBAAAA.',
Kh='Khione:BAAANQADCgcIFQAAAA==.',
Ki='Kindsöul:BAAANQAECgQICAABNQAFFAUIFAAJAP0XAA==.',
Ko='Kobol:BAAANQAECggIDAAAAA==.Koluvan:BAAANQADCggIGQAAAA==.Koopa:BAABNQAECn81AAIeAAoKnCBsAwCqAgAeAAoKnCBsAwCqAgAAAA==.',
Kr='Krianii:BAAANQADCgEIAQAAAA==.Krieg:BAAANQAECgYIBgABNQAFFAYIEgAHAH0hAA==.Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAACNQAFFH8IAAIbAAQKhhbXBwDvAAAbAAQKhhbXBwDvAAA1AAQKf2AAAxsACgq9JNcCAK4DABsACgq9JNcCAK4DABYABQrxFIGoABwBAAAA.',
Li='Lillianna:BAABNQAECn8WAAIMAAcKYw5nIgC3AQAMAAcKYw5nIgC3AQAAAA==.Lilsensual:BAABNQAECn8fAAIXAAkK5xIFZADhAQAXAAkK5xIFZADhAQABNQAFFAQICAAZADsGAA==.',
Lo='Loads:BAAANQAECgcICwAAAA==.Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.Lolkurtone:BAAANQAECgQIBAAAAA==.',
Lu='Luceus:BAABNQAECn8qAAIZAAoKwxA8GAB/AQAZAAoKwxA8GAB/AQAAAA==.Lucário:BAABNQAECn80AAIQAAkKPyUmEgD6AgAQAAkKPyUmEgD6AgAAAA==.Lugia:BAAANQADCgYJCwAAAA==.Lunadawn:BAABNQAECn8cAAIFAAkKZCElEAAVAwAFAAkKZCElEAAVAwAAAA==.Lunastorm:BAACNQAFFH8IAAIfAAQKnAlHCwD8AAAfAAQKnAlHCwD8AAA1AAQKf1UAAh8ACgqXHkQIAJYCAB8ACgqXHkQIAJYCAAAA.Luponero:BAACNQAFFH8gAAMVAAcKqRjoBwAeAQAVAAYKxhjoBwAeAQACAAEKNhgiJwBZAAA1AAQKfygAAxUACgrrILsYAJECABUACgqNILsYAJECAAIAAQoCJOhGAVEAAAAA.',
Ma='Macmn:BAACNQAFFH8LAAIaAAUKmB2/CQDRAQAaAAUKmB2/CQDRAQA1AAQKfzEAAhoACgr/JfcFALoDABoACgr/JfcFALoDAAAA.Magej:BAAANQADCgQIBAAAAA==.Mageyouacake:BAAANQADCgQIBgAAAA==.Mamaheals:BAABNQAECn8zAAIWAAoK0yHvFwAXAwAWAAoK0yHvFwAXAwAAAA==.Mandos:BAABNQAECn9EAAILAAoKFiTSBgALAwALAAoKFiTSBgALAwAAAA==.Mantistabogn:BAAANQAFFAEIAQAAAA==.Manzoholy:BAAANQADCgMIAwAAAA==.Maor:BAAANQAECgEIAQAAAA==.',
Me='Merlerk:BAAANQAECgIIAgABNQAFFAYIFAAaALUXAA==.Merlini:BAABNQAECn8pAAMbAAoKYA9wJgD6AQAbAAoKYA9wJgD6AQAgAAUKkhtDBgBOAQAAAA==.Metrohexual:BAABNQAECn8vAAIXAAoKth2IEQAEAwAXAAoKth2IEQAEAwAAAA==.Mets:BAABNQAECn8jAAICAAoKmR2hGwCwAgACAAoKmR2hGwCwAgABNQAECgoKKAABAA8eAA==.',
Mi='Mikasa:BAAANQAECgQIBAABNQAECgYICQATAAAAAA==.Mitzis:BAACNQAFFH8GAAICAAIKqBeWKwCGAAACAAIKqBeWKwCGAAA1AAQKfygAAgIACgrsIpozANECAAIACgrsIpozANECAAAA.',
Mn='Mnm:BAAANQAECgUIBwAAAA==.',
Mo='Moltiy:BAAANQADCgcICQAAAA==.Moltten:BAAANQAECgUICgAAAA==.Moondo:BAECNQAFFH8eAAIHAAcKpiIqAwCVAgAHAAcKpiIqAwCVAgA1AAQKfz8AAwcACgpQJZ8DAEoDAAcACgpQJZ8DAEoDAAYABgqvD7k/AMwAAAE1AAUUAggCABMAAAAA.',
['Mè']='Mètis:BAABNQAECn8rAAICAAcKYCHpUAB9AgACAAcKYCHpUAB9AgAAAA==.',
Na='Naahx:BAAANQAECgcICgABNQAECgoKJgASAG4iAA==.Nall:BAAANQAECgQIBAAAAA==.Narmer:BAAANQABCgMIAwAAAA==.',
Ne='Nefarius:BAACNQAFFH8GAAIbAAIKVxHQDQCLAAAbAAIKVxHQDQCLAAA1AAQKfzAAAhsACgqEH4ILAC0DABsACgqEH4ILAC0DAAAA.Neuropolis:BAAANQADCgYIBgAAAA==.Neurotics:BAABNQAECn80AAQBAAoKLiJRHAAUAwABAAkKPCJRHAAUAwAhAAYKyyHBDQB7AQAiAAUKviE4CQAIAQAAAA==.',
Ni='Nighthigh:BAAANQAECgEIAQAAAA==.Nineoneone:BAABNQAECn81AAIWAAgKRxuURQBWAgAWAAgKRxuURQBWAgAAAA==.',
No='Noperr:BAAANQAECggICAAAAA==.',
Nu='Nurmally:BAAANQAECggIEwABNQAFFAUIBgACAAwPAA==.Nutmilk:BAAANQAECgcICQAAAA==.Nuuot:BAAANQAECgcIDQAAAA==.',
Oc='Ocra:BAABNQAECn8nAAIjAAoKfg9uEgCsAQAjAAoKfg9uEgCsAQABNQAFFAMIBwACAMQRAA==.',
Of='Offspeck:BAAANQAECgQIBQABNQAECgoKRQABAHUiAA==.',
Ol='Oldirtycasta:BAAANQAECgEIAgABNQAECgkJHAAIAB4JAA==.',
On='Onayhawe:BAAANQAECgUIBgAAAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgoKRAAOALAkAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAABNQAECn8sAAIOAAoKRAYw1ADzAAAOAAoKRAYw1ADzAAAAAA==.Pallysmack:BAAANQADCgEIAQAAAA==.Pandapwr:BAAANQADCgcIDwABNQAECgoKLAAMAAwbAA==.Pandemul:BAAANQADCggICAABNQAFFAMIBQAOALIhAA==.Patrio:BAAANQADCgYICwABNQAECgkJLgAGABMiAA==.Pawkler:BAAANQAECgQIBAABNQAECgkJGgAZAHYXAA==.Pawshira:BAAANQADCgUIBQABNQAECgkJGgAZAHYXAA==.',
Pe='Peachaid:BAEANQAECgcIBwAAAA==.Peachie:BAAANQADCgcIBwAAAA==.Peetree:BAABNQAECn8yAAIXAAoKCyIlFgAfAwAXAAoKCyIlFgAfAwAAAA==.Perfectcell:BAAANQADCgYICwAAAA==.Petures:BAAANQAECgMIAwAAAA==.',
Ph='Phosphorus:BAACNQAFFH8GAAIQAAMKJQluJAB4AAAQAAMKJQluJAB4AAA1AAQKf4AAAxAACgpZH8EtAAYDABAACgpPHsEtAAYDABEACQooGQEQACkCAAAA.',
Pl='Plagüë:BAACNQAFFH8IAAMKAAQKIwndBwDBAAAKAAMKIwndBwDBAAALAAIKaQy6MAA1AAA1AAQKf0UAAwoACgoQIw4SACcDAAoACgpUIg4SACcDAAsACQr4Hh0XAPQCAAAA.Pluckedchkn:BAAANQAECgMIBAABNQAFFAQICAAZADsGAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAAANQAECgUIEgAAAA==.Primalistic:BAAANQAECgQIBQAAAA==.',
Pu='Pullnprey:BAAANQADCgYICAAAAA==.Purgedoctor:BAABNQAFFH8IAAIXAAMK8h0nFQAIAQAXAAMK8h0nFQAIAQAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAACNQAFFH8YAAIBAAcKNiCXAQCTAgABAAcKNiCXAQCTAgA1AAQKfzMAAwEACgpNJpMLAHADAAEACgpNJpMLAHADACEAAQp8HBIgAEoAAAAA.',
Ra='Ravenofchaos:BAAANQADCggICAAAAA==.Ravenoflight:BAAANQAECgIIAwAAAA==.Ravenshatred:BAAANQAECgQICAAAAA==.Ravenslight:BAAANQABCgQIBAAAAA==.Ravenswrath:BAAANQADCgcICAAAAA==.Ravenuchiha:BAAANQADCggIEAAAAA==.Rawrsaur:BAAANQAECgYIDgAAAA==.',
Re='Reallyhpal:BAAANQAECgcIEAAAAA==.Recon:BAAANQADCgMIAwABNQAECgoKGAAHALAFAA==.Redpocket:BAAANQAECgIIAgAAAA==.Rein:BAABNQAECn8dAAIRAAYKbQgEHwDNAAARAAYKbQgEHwDNAAAAAA==.Remin:BAAANQAECgUIBQAAAA==.Retaliator:BAAANQAECgEIAQAAAA==.Reuuín:BAAANQADCggIDAABNQAECgoKIgASAAccAA==.Revan:BAAANQADCggIDgAAAA==.',
Ri='Rimooru:BAAANQAECggIEQABNQAFFAMIBwAEAAQUAA==.Risquae:BAAANQAECgEIAQAAAA==.',
Ro='Romulis:BAAANQAECgUIBgAAAA==.Rooms:BAAANQADCgIIAgAAAA==.Rosè:BAABNQAECn81AAIGAAoKCByGCQD+AgAGAAoKCByGCQD+AgABNQAECgoKRAALABYkAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.',
Ry='Ryguyro:BAAANQADCgIJAgAAAA==.Ryhia:BAAANQAECgIIAgABNQAECgoKRAALABYkAA==.Ryzee:BAABNQAECn8dAAIIAAkKIhN3sAAiAgAIAAkKIhN3sAAiAgABNQAECgoKMgAaANkbAA==.',
['Rí']='Ríco:BAAANQADCgYIDgAAAA==.',
Sa='Sajaboy:BAAANQADCgIIAgAAAA==.Salena:BAAANQAECgQIBwAAAA==.Sans:BAAANQAECggIDgAAAA==.Sartha:BAABNQAECn8yAAIOAAoKYxVpVAD5AQAOAAoKYxVpVAD5AQAAAA==.Sasuka:BAABNQAECn8WAAMXAAYKShcJYABlAQAXAAYKShcJYABlAQAaAAMKAg8C8AC2AAAAAA==.Savagesoso:BAAANQADCgQJBAAAAA==.',
Sc='Schy:BAAANQAECgIIAgAAAA==.Scratsxd:BAAANQAECggIBQAAAA==.Scrumpheals:BAAANQAECgEIAQAAAA==.',
Se='Sedda:BAACNQAFFH8JAAIOAAUKDx/BCQCsAQAOAAUKDx/BCQCsAQA1AAQKfygAAg4ACQqCJWIXAGcDAA4ACQqCJWIXAGcDAAAA.Sensual:BAACNQAFFH8IAAIZAAQKOwZLBwCXAAAZAAQKOwZLBwCXAAA1AAQKf0EAAhkACgowHUEPAKkCABkACgowHUEPAKkCAAAA.Sesshomaru:BAACNQAFFH8HAAIEAAMKBBReCwDdAAAEAAMKBBReCwDdAAA1AAQKf0UAAgQACgogI7oEAKcDAAQACgogI7oEAKcDAAAA.',
Sh='Shadoworca:BAAANQADCgQIBAAAAA==.Shampain:BAABNQAECn8hAAMjAAoKXgpZHACeAQAjAAoKXgpZHACeAQAXAAUKug6B3wCqAAABNQAFFAQIBwAFACQfAA==.Shampooh:BAAANQADCggICAAAAA==.Shang:BAACNQAFFH8SAAIHAAYKfSElBgCMAQAHAAYKfSElBgCMAQA1AAQKfzAAAgcACgrtJY4FAKoDAAcACgrtJY4FAKoDAAAA.Shanzo:BAAANQAECggIAwAAAA==.Shiftshot:BAAANQAECgUICAAAAA==.Shiftstab:BAAANQADCgQIBAAAAA==.Shirona:BAABNQAECn80AAMEAAoKWyHTCQDfAgAEAAoKWyHTCQDfAgAPAAcKCgmJOwBqAQAAAA==.Shloomish:BAAANQAECgYIBwAAAA==.Shmized:BAAANQAECgEIAQAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAABNQAECn9DAAIIAAoKLyDMIACiAgAIAAoKLyDMIACiAgABNQAFFAMIBwAEAAQUAA==.',
Si='Siare:BAABNQAECn8oAAIBAAoKDx57FgClAgABAAoKDx57FgClAgAAAA==.',
Sk='Skeeter:BAABNQAECn8rAAQiAAoK7xeGFADLAQABAAgK+RNYhADbAQAiAAYKtBiGFADLAQAhAAUKvw77EwALAQAAAA==.Skroncer:BAAANQADCgYIEgAAAA==.',
Sm='Smokinjawn:BAAANQADCgMIAwAAAA==.Smòtts:BAABNQAECn8hAAIJAAgKtxymDwBnAgAJAAgKtxymDwBnAgAAAA==.Smótts:BAAANQADCggJEwAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAABNQAECgQIBAATAAAAAA==.Snizard:BAABNQAECn8XAAICAAYKIRNXswCdAQACAAYKIRNXswCdAQAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQAECgoKLwAFAJMeAA==.',
So='Soawesome:BAABNQAECn8VAAIaAAYKgAnIhgDHAAAaAAYKgAnIhgDHAAABNQAECgkJHAAIAB4JAA==.Solenoid:BAABNQAECn8iAAMWAAoKBReMTgDFAQAWAAoKBReMTgDFAQAbAAYKsQzwLQDeAAAAAA==.',
Sp='Spicymustard:BAAANQADCgYICgAAAA==.Springrollz:BAAANQAECgEIAQAAAA==.Spàdes:BAAANQAECgQICgAAAA==.',
Sq='Squírtlé:BAAANQADCgEIAQAAAA==.',
St='Stellanoova:BAABNQAECn8WAAMkAAYKTAa5IQDOAAAkAAUK2ga5IQDOAAAlAAEKFgTFdQAjAAABNQAECgkJJwANAHEPAA==.Stonecolld:BAAANQADCgIIAgAAAA==.Stormbeards:BAAANQADCgcIBwAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarcube:BAAANQAECgUICAABNQAFFAUIFAAJAP0XAA==.Sugarhigh:BAAANQABCgQIBAAAAA==.Sunlight:BAAANQADCggICQAAAA==.Sushirollz:BAAANQAECggICwAAAA==.',
Ta='Taazdingo:BAAANQADCggIEwAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAACNQAFFH8MAAMiAAUK0xg2CACxAAAiAAIKEh42CACxAAABAAMKVg4MMABIAAA1AAQKfzoAAwEACgpQJPo4AKkCAAEACAp3JPo4AKkCACIAAwrPHWMPAMEAAAAA.',
Te='Teabear:BAAANQAECggIBwAAAA==.',
Th='Thisishard:BAABNQAECn89AAIIAAoKgxciRQAZAgAIAAoKgxciRQAZAgAAAA==.Thorshammer:BAAANQADCgUIBQAAAA==.Thryen:BAAANQAECgQICwAAAA==.Thundergrasp:BAABNQAECn8yAAIaAAoK2Rv3GQB1AgAaAAoK2Rv3GQB1AgAAAA==.',
To='Toe:BAACNQAFFH8GAAIKAAIKhQqjCgCKAAAKAAIKhQqjCgCKAAA1AAQKfxUAAgoACQobGPhGAPwBAAoACQobGPhGAPwBAAAA.Toobestake:BAAANQAECgEIAgABNQAFFAcIIAAVAKkYAA==.Topenga:BAACNQAFFH8HAAICAAMKxBEvGgChAAACAAMKxBEvGgChAAA1AAQKf08AAgIACgoAI0ETAOECAAIACgoAI0ETAOECAAAA.',
Tr='Trunnks:BAAANQAECgcIBgAAAA==.',
Ts='Tsargock:BAAANQADCgUIBAAAAA==.',
Tw='Twicelife:BAAANQAECgUICgABNQAFFAMIBgAQACUJAA==.',
Ty='Typhoid:BAAANQAECggIDwAAAA==.',
['Tñ']='Tñt:BAAANQAECgYICQABNQAECgoKRQABAHUiAA==.',
Um='Umei:BAAANQAECgIIAgAAAA==.',
Ur='Urbek:BAABNQAECn8VAAIHAAcKGyDhLgBoAgAHAAcKGyDhLgBoAgAAAA==.Urthstripe:BAABNQAECn8oAAIGAAoKTxfMFQAmAgAGAAoKTxfMFQAmAgAAAA==.',
Us='Usualsuspect:BAAANQAECgIIAgAAAA==.',
Uw='Uwu:BAAANQAECgUIBQABNQAFFAgIGQAbALoQAA==.',
Va='Valle:BAAANQADCggIDgABNQAFFAgIGQAbALoQAA==.Valoria:BAAANQAECggICAABNQAFFAgIGQAbALoQAA==.',
Ve='Velgabrine:BAAANQAECgQICAABNQAFFAMIBQAOALIhAA==.Veraani:BAAANQADCggICAAAAA==.Verlaria:BAAANQADCgEIAQAAAA==.',
Vi='Viserion:BAABNQAECn8nAAMNAAkKcQ/eDACEAQANAAgK9BDeDACEAQAfAAUKkApxMwD7AAAAAA==.',
Vu='Vue:BAACNQAFFH8HAAIFAAQKJB/lCQB6AQAFAAQKJB/lCQB6AQA1AAQKf1YAAgUACgrGH6sbAAYDAAUACgrGH6sbAAYDAAAA.Vulkun:BAAANQAECgMIAwAAAA==.',
Wa='Wakasham:BAACNQAFFH8TAAIjAAUK3iV5AQA+AQAjAAUK3iV5AQA+AQA1AAQKfy4AAiMACgqrJqcAANQDACMACgqrJqcAANQDAAAA.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAABNQAECn8ZAAMEAAkKtSAiFAD9AgAEAAkKtSAiFAD9AgAPAAIKUgjsYwBbAAABNQAFFAgIGAAPAL0ZAA==.',
Wi='Wickedmisery:BAAANQADCgYIBgAAAA==.',
Wo='Wolfpacked:BAABNQAECn8bAAIXAAYKFhnpdgCnAQAXAAYKFhnpdgCnAQABNQAECgoKOAABADciAA==.Wolfzbåin:BAAANQAECgQIAwAAAA==.',
Wr='Wrbringer:BAAANQADCgEIAQAAAA==.',
Wu='Wunderlust:BAACNQAFFH8HAAIIAAQKhQ0kIADdAAAIAAQKhQ0kIADdAAA1AAQKf0EAAggACgoQImAnAEQDAAgACgoQImAnAEQDAAAA.',
Xe='Xeroidz:BAAANQADCgcICgAAAA==.',
Xs='Xscrats:BAAANQAECggIBQAAAA==.',
Ye='Yellowshaman:BAACNQAFFH8JAAIaAAMKpA20GwDkAAAaAAMKpA20GwDkAAA1AAQKfywAAxoACQrpHs0mAOgCABoACQrpHs0mAOgCABcAAQoTDsbgADQAAAAA.Yerac:BAABNQAFFH8OAAMGAAUKRwobBwBHAQAGAAUKRwobBwBHAQAHAAEK4QGtHwA1AAAAAA==.',
Za='Zandelussy:BAABNQAECn8vAAMFAAoKkx5cIACMAgAFAAoKkx5cIACMAgAZAAUKHxw8HgBHAQAAAA==.Zapper:BAAANQAECgIIBAAAAA==.',
Zu='Zugg:BAAANQAECgYIBgABNQAFFAgIGQAbALoQAA==.Zuriznikov:BAABNQAECn8bAAUGAAgK8w1pIwCMAQAGAAgK8w1pIwCMAQAHAAQKCQXAjQCfAAAJAAQKqgc+RgCZAAAUAAEKhAm3RQAuAAABNQAECgkJJwANAHEPAA==.',
['Øf']='Øffspeck:BAABNQAECn9FAAQBAAoKdSIMFwAsAwABAAoKTSAMFwAsAwAhAAoKUxsABQB+AgAiAAcKrCIxBgBPAQAAAA==.',
['ßo']='ßoss:BAAANQADCgQIBAABNQAECggIJwARAB8fAA==.',
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
