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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Mage-Frost','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Druid-Balance','Mage-Arcane','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Rogue-Assassination','Unknown-Unknown','Druid-Feral','Monk-Brewmaster','Hunter-Marksmanship','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Hunter-Survival','Paladin-Protection','Priest-Shadow','DeathKnight-Frost','Mage-Fire','Warrior-Fury','Evoker-Preservation','Priest-Discipline','Warlock-Affliction','Warlock-Destruction','Shaman-Enhancement','Monk-Mistweaver','Monk-Windwalker',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaron:BAAANQAECgIIAgABNQAECgoKRwABAHUiAA==.Aaronfreeze:BAACNQAFFH8IAAICAAQKqhWZGwCpAAACAAQKqhWZGwCpAAA1AAQKfzYAAgIACgqKIQsfABsDAAIACgqKIQsfABsDAAAA.',
Ab='Abnar:BAABNQAECn8qAAIDAAkKaxXgDADoAQADAAkKaxXgDADoAQAAAA==.',
Ad='Adversaryq:BAAANQADCgYIBwAAAA==.',
Ae='Aecir:BAAANQADCgYIBgAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUICgAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAFFAMIBwAEAAQUAA==.Allformarc:BAAANQAECgUJBgAAAA==.Allmaick:BAAANQADCggIDAAAAA==.Alucard:BAABNQAECn9DAAIFAAoK4RbNNwAoAgAFAAoK4RbNNwAoAgAAAA==.Alystrasza:BAABNQAECn8uAAMGAAoK3B4gDQD9AgAGAAoK3B4gDQD9AgAHAAcKLg26WABxAQAAAA==.',
Am='Ambivalent:BAABNQAECn8dAAIIAAkKUAkpiACEAQAIAAkKUAkpiACEAQAAAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgQIDwAAAA==.',
Ap='Aphroditê:BAAANQAECgEIAgABNQAECgcIKwACAGAhAA==.',
Ar='Arrowsmïth:BAAANQADCgUIBwAAAA==.',
As='Ashenfate:BAAANQAECgYICQABNQAFFAUIFAAJAP0XAA==.',
Au='Auroras:BAAANQAECgIIAgAAAA==.',
Av='Aviaria:BAAANQAECgEIAQAAAA==.',
Ax='Axsenaea:BAAANQAECgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAABNQAECn8sAAMKAAoK7B87IADKAgAKAAoK7B87IADKAgALAAEK1QU80AAtAAABNQAFFAMIBwAEAAQUAA==.',
['Aü']='Aütöpsy:BAABNQAECn86AAIMAAoKkhu8LQA0AgAMAAoKkhu8LQA0AgAAAA==.',
Ba='Baarda:BAAANQADCgQIBAABNQAECgkJKQANAHEPAA==.Babylonfive:BAABNQAECn9EAAIOAAoKsCQDBQDSAwAOAAoKsCQDBQDSAwAAAA==.Backstabbath:BAAANQADCgQIBQAAAA==.Banger:BAAANQAECgQICQAAAA==.',
Be='Beardsy:BAAANQABCggICgAAAA==.Belleta:BAAANQAECgEIAwAAAA==.Belligerente:BAABNQAECn80AAIPAAgKUxTSIQB7AQAPAAgKUxTSIQB7AQABNQAECgkJHQAIAFAJAA==.Berserk:BAEBNQAECn8aAAMQAAgKYRaWdAA3AgAQAAgK5BSWdAA3AgARAAYKIBPAHgBdAQABNQAFFAUIBwASABwDAA==.Bertringer:BAAANQAECgMIBQABNQAECgQIBwATAAAAAA==.',
Bi='Bigthiccboi:BAAANQAECgQIBQAAAA==.Bigwave:BAAANQADCggIHwAAAA==.Bigwilli:BAAANQAECgEIAQAAAA==.Bilefiend:BAAANQADCgMIAwAAAA==.Birds:BAACNQAFFH8UAAIJAAUK/RfaAQAoAQAJAAUK/RfaAQAoAQA1AAQKfzMABAkACgrcIE0GAC0DAAkACgrcIE0GAC0DABQABwoRExoSAN4BAAcAAQoAANK2ACsAAAAA.Birdweiser:BAABNQAFFH8KAAIVAAUKNQhBBADxAAAVAAUKNQhBBADxAAABNQAFFAUIFAAJAP0XAA==.Biscuit:BAACNQAFFH8XAAMCAAgKBB/sCwCRAQACAAcKzxzsCwCRAQAWAAUKXhAnFAD+AAA1AAQKfzsAAwIACQr5JWsPAA4DAAIACQrIJWsPAA4DABYACAoRI5YZAKYBAAAA.Bisha:BAABNQAECn9RAAIQAAoKiiOSFQBkAwAQAAoKiiOSFQBkAwAAAA==.Bizcocho:BAABNQAECn8XAAIXAAkKkBURbQDXAQAXAAkKkBURbQDXAQAAAA==.',
Bl='Bloodfern:BAAANQABCgEIAQAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boogsta:BAAANQAECgMIAwABNQAECgoKMQAXAJ0dAA==.Boomkingobrr:BAAANQAECgYICwAAAA==.Boops:BAACNQAFFH8LAAIYAAMKkQrEGQDNAAAYAAMKkQrEGQDNAAA1AAQKfxYAAxgACgpsEfZXAAkCABgACgpsEfZXAAkCABkAAQoAAHtGASsAAAE1AAUUBQgOAAYARwoA.Bootysweatt:BAAANQADCggICAAAAA==.Boss:BAABNQAECn8oAAIRAAkKoR9uCwD4AQARAAkKoR9uCwD4AQAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Bunnycakez:BAAANQADCgIIAgAAAA==.Burnsx:BAAANQADCggIGAABNQAFFAgIGAAPAL0ZAA==.',
Bw='Bwoar:BAABNQAECn8xAAIMAAoKDBtJIwBrAgAMAAoKDBtJIwBrAgAAAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captinfeo:BAAANQADCggICAAAAA==.Captnmurloc:BAABNQAECn8pAAMaAAoKhBpzBACdAgAaAAoKhBpzBACdAgACAAEKNBYdSwFJAAAAAA==.Carriedomb:BAAANQADCgYICQAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQAECgcIDAAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAABNQAECn8pAAICAAgK8BXzegCqAQACAAgK8BXzegCqAQAAAA==.Chrinn:BAAANQAECgEIAQAAAA==.Church:BAABNQAECn8rAAIFAAoKMxrXGgDSAgAFAAoKMxrXGgDSAgAAAA==.',
Ci='Cirxe:BAABNQAECn8tAAIIAAkKSAWiDgF0AQAIAAkKSAWiDgF0AQAAAA==.',
Cl='Clarkent:BAAANQAECgUICQAAAA==.',
Co='Coms:BAABNQAECn8UAAIOAAgKVAvnxACSAQAOAAgKVAvnxACSAQAAAA==.Cowmoorem:BAAANQADCgEIAQAAAA==.',
Cr='Crayze:BAAANQAECgIIBgAAAA==.Creatinepowa:BAAANQADCgEIAQAAAA==.',
Cu='Curuni:BAAANQAECgQIBAAAAA==.',
['Cø']='Cønstance:BAABNQAECn80AAIJAAoKIiLIBAALAwAJAAoKIiLIBAALAwAAAA==.',
Da='Dabai:BAABNQAECn9EAAIOAAoKdRyHXwADAgAOAAoKdRyHXwADAgAAAA==.Dahliaa:BAAANQADCgMIAwAAAA==.Daipailaotie:BAABNQAECn84AAMOAAoKZAws1ABzAQAOAAoKnwss1ABzAQAbAAcKmAefOwCrAAAAAA==.Dalight:BAAANQAECgUICwAAAA==.Dankins:BAABNQAFFH8PAAIYAAUK4B1eCADNAQAYAAUK4B1eCADNAQAAAA==.Darealfarmer:BAAANQADCgcIBwAAAA==.Darkzoomies:BAAANQAECgMIBAAAAA==.Darthravens:BAAANQABCgQIBAAAAA==.',
De='Deathmager:BAAANQAECgQICQAAAA==.Depar:BAAANQAECgMIAwAAAA==.Dethsent:BAAANQAECgIIAwAAAA==.Dette:BAABNQAECn8hAAICAAkKqA8QaQDXAQACAAkKqA8QaQDXAQAAAA==.Devourer:BAABNQAECn9iAAIPAAoKHiUlAwCnAwAPAAoKHiUlAwCnAwAAAA==.',
Dk='Dkboss:BAAANQADCgYIEQABNQAECgkJKAARAKEfAA==.',
Do='Doctrdoom:BAAANQADCggIFQABNQAECgoKRwABAHUiAA==.',
Dr='Drafted:BAAANQAECgYIEQAAAA==.Dragondank:BAAANQAFFAEIAgABNQAFFAUIDwAYAOAdAA==.Drukah:BAAANQAECgMIAwAAAA==.',
Dt='Dtrike:BAAANQAECgIIBAAAAA==.',
Ed='Edstark:BAABNQAECn8gAAIEAAcK0wLqZwDZAAAEAAcK0wLqZwDZAAAAAA==.Edwinranger:BAAANQAECggIAQAAAA==.',
El='Elabernathy:BAABNQAECn8xAAICAAkKrw6qaQDWAQACAAkKrw6qaQDWAQAAAA==.Elchapö:BAAANQAECgMIAwABNQAECgoKRwABAHUiAA==.Elenay:BAABNQAECn8iAAIHAAoKoCBMFQAdAwAHAAoKoCBMFQAdAwAAAA==.Eliarssande:BAAANQAECgYIDAABNQAECgYIHAAYAFIdAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAABNQAECn8uAAIGAAkKEyKABQBqAwAGAAkKEyKABQBqAwAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAABNQAECn8zAAIKAAkKiiIkLgB5AgAKAAkKiiIkLgB5AgABNQAFFAMIBQAOALIhAA==.Emulsifier:BAACNQAFFH8FAAIOAAMKsiFPGQC2AAAOAAMKsiFPGQC2AAA1AAQKf00AAw4ACgrvJQ0CAPEDAA4ACgrvJQ0CAPEDAAUAAQqAFDrlAD0AAAAA.Emulslash:BAAANQADCgYIDAABNQAFFAMIBQAOALIhAA==.',
Ev='Evideia:BAAANQADCgQJBAABNQAECgcIKwACAGAhAA==.',
Ex='Expiatory:BAAANQADCgEIAQAAAA==.Expiredbeef:BAAANQADCgYIBgABNQAECgcIBwATAAAAAA==.',
Fa='Farcha:BAAANQAECgUICQAAAA==.',
Fi='Fidge:BAAANQADCgYIBgAAAA==.Finester:BAABNQAECn8hAAMSAAoKACBaDgAQAwASAAoKMx5aDgAQAwAMAAgKhhh1bQBBAQAAAA==.',
Fl='Flatline:BAABNQAECn8gAAIBAAkK+BRvrwByAQABAAkK+BRvrwByAQAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Ga='Gagners:BAABNQAECn8aAAMSAAkKARlDLQAxAgASAAcK+hpDLQAxAgAMAAMKEhNAkQDPAAABNQAFFAMIBQAOALIhAA==.Gazingo:BAAANQAECggIDwAAAA==.Gazkaash:BAAANQAECgYIBwABNQAECggIDwATAAAAAA==.',
Go='Gorska:BAABNQAECn8kAAIZAAkKuhtcNgCeAgAZAAkKuhtcNgCeAgAAAA==.',
Gr='Grawm:BAAANQAECgYIEQAAAA==.Gritshaman:BAAANQAECgcIDAABNQAECgoKRwABAHUiAA==.',
['Gä']='Gämbit:BAAANQAECgUIDQAAAA==.',
Ha='Hangman:BAAANQAECgcIEAAAAA==.Hanni:BAAANQAECgUIBQAAAA==.Harakutoo:BAAANQAECgEIAQAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAABNQAECn8xAAMXAAoKnR1QJwCfAgAXAAoKnR1QJwCfAgAcAAIKqQRMYAAxAAAAAA==.',
He='Hellshand:BAAANQAECgUICwAAAA==.Helmhammer:BAAANQAECgEIAgAAAA==.',
Hi='Hinxx:BAAANQAECgMIAwAAAA==.',
Ho='Holychaser:BAAANQAECgMJCAAAAA==.Holycrack:BAABNQAECn8fAAIbAAcKSiXECwBkAgAbAAcKSiXECwBkAgABNQAECgoKOAABADciAA==.Holycøw:BAAANQAECgEIAwAAAA==.Holydefender:BAAANQADCgMIAwAAAA==.Holyfyree:BAAANQADCgcICAABNQAECgkJKQANAHEPAA==.Holypawk:BAABNQAECn8aAAIbAAkKdhf1GwANAgAbAAkKdhf1GwANAgAAAA==.Holyrock:BAABNQAECn8yAAIOAAkK9xYXbwDeAQAOAAkK9xYXbwDeAQAAAA==.Holyyshi:BAAANQADCgQIBAAAAA==.Honorheart:BAAANQADCgcICwAAAA==.',
['Hó']='Hóly:BAAANQADCgEJAQABNQAECgYICwATAAAAAA==.',
Ih='Ihureciv:BAABNQAECn8pAAIWAAoKLhzDIgA3AgAWAAoKLhzDIgA3AgABNQAFFAUICQAcAIYWAA==.',
Ik='Ikur:BAABNQAECn89AAIFAAoKWCA7KADHAgAFAAoKWCA7KADHAgAAAA==.',
In='Infoxicated:BAAANQAECgYIBgABNQAECgoKOAAbAFEgAA==.',
Ip='Ipopkidneys:BAACNQAFFH8bAAMMAAcK0SK+BADdAQAMAAUK8CO+BADdAQASAAIKISHXCQCiAAA1AAQKfzAAAwwACgp/Jb4MAKkCAAwACgpPJb4MAKkCABIABAo3JO1QAHoBAAAA.',
Ir='Iroi:BAAANQAECgIJAwAAAA==.',
Is='Iskur:BAABNQAECn8UAAIYAAcKZhRhcQC3AQAYAAcKZhRhcQC3AQABNQAECgoKPQAFAFggAA==.Isurr:BAAANQAECgUIDgABNQAECgoKPQAFAFggAA==.',
Iv='Ivanapump:BAAANQAECgQIBAAAAA==.',
Ja='Jadhar:BAAANQAECgYIDAAAAA==.Jametrok:BAABNQAECn8aAAIOAAgK4BW+lAD6AQAOAAgK4BW+lAD6AQAAAA==.Jastra:BAAANQADCgcIDgAAAA==.',
Je='Jennyanydots:BAAANQAECgIIAgABNQAFFAgIGQAcALoQAA==.',
Ji='Jiraîya:BAABNQAECn8hAAIZAAkKGhSoRQCnAQAZAAkKGhSoRQCnAQAAAA==.',
Jo='Jorbar:BAAANQAECgYICQAAAA==.Jordak:BAABNQAECn8jAAIGAAkKDhxBEwCzAgAGAAkKDhxBEwCzAgAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Julex:BAAANQAECggICAAAAA==.Jumbok:BAABNQAECn8qAAIIAAoKWBJ2jwB0AQAIAAoKWBJ2jwB0AQAAAA==.Just:BAABNQAECn8sAAMKAAoKRxLSKgB7AQAKAAoKDBLSKgB7AQAdAAQKFAvJdwDEAAAAAA==.',
Ka='Kaddiya:BAAANQAECgEIAQAAAA==.Kaine:BAAANQADCgUIBQAAAA==.Kallistos:BAABNQAECn8sAAIYAAkKtBV8TwAnAgAYAAkKtBV8TwAnAgAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQAECgQIBgAAAA==.Katalaana:BAAANQAECgEIAQAAAA==.',
Ke='Kevdogg:BAABNQAECn8qAAMIAAkKIwbWpQBGAQAIAAkKnAXWpQBGAQAeAAEKlQV/DgAuAAAAAA==.Key:BAACNQAFFH8MAAMOAAUKJh/UDgBfAQAOAAUKJh/UDgBfAQAFAAEKbwusJwBOAAA1AAQKfysAAw4ACgowJTQvAAwDAA4ACgowJTQvAAwDAAUABwr/FOR2ALMBAAAA.',
Kh='Khione:BAAANQADCgcIFQAAAA==.',
Ki='Kindsöul:BAAANQAECgQICQABNQAFFAUIFAAJAP0XAA==.',
Ko='Kobol:BAAANQAECggIDgAAAA==.Koluvan:BAAANQAECgEIAQAAAA==.Koopa:BAABNQAECn88AAIfAAoKxyCjAwDCAgAfAAoKxyCjAwDCAgAAAA==.',
Kr='Krianii:BAAANQADCgEIAQAAAA==.Krieg:BAAANQAECgYIBgABNQAFFAcIEwAHAOghAA==.Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAACNQAFFH8JAAIcAAUKhhZXCQDpAAAcAAUKhhZXCQDpAAA1AAQKf2EAAxwACgoVJdcCAK4DABwACgoVJdcCAK4DABcABQrxFIGoABwBAAAA.',
Li='Lillianna:BAABNQAECn8WAAIMAAcKYw5nIgC3AQAMAAcKYw5nIgC3AQAAAA==.Lilsensual:BAABNQAECn8fAAIYAAkK5xIFZADhAQAYAAkK5xIFZADhAQABNQAFFAUICQAbADsGAA==.',
Lo='Loads:BAAANQAECgcIDAAAAA==.Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.Lolkurtone:BAAANQAECgQIBAAAAA==.',
Lu='Luceus:BAABNQAECn8qAAIbAAoKwxDKHAB0AQAbAAoKwxDKHAB0AQAAAA==.Lucário:BAABNQAECn80AAIQAAkKPyWxFwBaAwAQAAkKPyWxFwBaAwAAAA==.Lugia:BAAANQADCgYJCwAAAA==.Lunadawn:BAABNQAECn8gAAIFAAoK8yDxCwBfAwAFAAoK8yDxCwBfAwAAAA==.Lunastorm:BAACNQAFFH8JAAIgAAUKHwqkCgA/AQAgAAUKHwqkCgA/AQA1AAQKf1YAAiAACgqXHnQJAJQCACAACgqXHnQJAJQCAAAA.Luponero:BAACNQAFFH8gAAMWAAcKqRgHCwCPAQAWAAYKxhgHCwCPAQACAAEKNhhAKwBZAAA1AAQKfykAAxYACgrrILsYAJECABYACgqNILsYAJECAAIAAQoCJOhGAVEAAAAA.',
Ma='Macmn:BAACNQAFFH8LAAIZAAUKmB2/CQDRAQAZAAUKmB2/CQDRAQA1AAQKfzEAAhkACgr/JfcFALoDABkACgr/JfcFALoDAAAA.Maethoron:BAAANQAECgEIAQABNQAECgoKSwALACEkAA==.Magej:BAAANQADCgQIBAAAAA==.Mageyouacake:BAAANQADCgQIBgAAAA==.Mamaheals:BAABNQAECn84AAIXAAoK0yHvFwAXAwAXAAoK0yHvFwAXAwAAAA==.Mandos:BAABNQAECn9LAAILAAoKISS2BwAIAwALAAoKISS2BwAIAwAAAA==.Mantistabogn:BAAANQAFFAEIAQAAAA==.Manzoholy:BAAANQADCgMIAwAAAA==.Maor:BAAANQAECgEIAgAAAA==.',
Me='Merlerk:BAAANQAECgIIAgABNQAFFAYIFAAZALUXAA==.Merlini:BAABNQAECn8sAAMcAAoKYA9wJgD6AQAcAAoKYA9wJgD6AQAhAAUKwiCYBADYAQAAAA==.Metrohexual:BAABNQAECn8vAAIYAAoKth3DFQD1AgAYAAoKth3DFQD1AgAAAA==.Mets:BAABNQAECn8pAAICAAoK7h2qHwC0AgACAAoK7h2qHwC0AgABNQAECgoKKQABAA8eAA==.',
Mi='Mikasa:BAAANQAECgQIBAABNQAECgYICwATAAAAAA==.Mitzis:BAACNQAFFH8IAAICAAMKOBKNHgCbAAACAAMKOBKNHgCbAAA1AAQKfysAAgIACgpFI5ozANECAAIACgpFI5ozANECAAAA.',
Mn='Mnm:BAAANQAECgUICAAAAA==.',
Mo='Moltiy:BAAANQADCgcICQAAAA==.Moltten:BAAANQAECgUICgAAAA==.Moondo:BAECNQAFFH8eAAIHAAcKpiIqAwCVAgAHAAcKpiIqAwCVAgA1AAQKfz8AAwcACgpQJYAEAEQDAAcACgpQJYAEAEQDAAYABgqvD3NHAMsAAAE1AAUUAggCABMAAAAA.',
['Mè']='Mètis:BAABNQAECn8rAAICAAcKYCHpUAB9AgACAAcKYCHpUAB9AgAAAA==.',
Na='Naahx:BAAANQAECgcICgABNQAECgoKJgASAG4iAA==.Nall:BAAANQAECgQIBAAAAA==.Narmer:BAAANQABCgMIAwAAAA==.',
Ne='Nefarius:BAACNQAFFH8GAAIcAAIKVxH6DwCGAAAcAAIKVxH6DwCGAAA1AAQKfzAAAhwACgqEH4ILAC0DABwACgqEH4ILAC0DAAAA.Neuropolis:BAAANQADCgYIBgAAAA==.Neurotics:BAABNQAECn83AAQBAAoKFCRRHAAUAwABAAkKbSJRHAAUAwAiAAcKTCOcCAC5AQAjAAUKviG+CgAEAQAAAA==.',
Ni='Nighthigh:BAAANQAECgEIAQAAAA==.Nineoneone:BAABNQAECn84AAIXAAoKcBrdMgBgAgAXAAoKcBrdMgBgAgAAAA==.',
No='Noperr:BAAANQAECggICAAAAA==.Notacop:BAAANQAECgEIAgAAAA==.',
Nu='Nurmally:BAABNQAECn8ZAAMHAAkKORbfKACiAQAHAAkKORbfKACiAQAGAAQKCQ6jRwDKAAABNQAFFAUIBgACAAwPAA==.Nutmilk:BAAANQAECgcICQAAAA==.Nuuot:BAAANQAECgcIDgAAAA==.',
Oc='Ocra:BAABNQAECn8nAAIkAAoKfg/0FACsAQAkAAoKfg/0FACsAQABNQAFFAQICAACAMQRAA==.',
Of='Offspeck:BAAANQAECgQIBgABNQAECgoKRwABAHUiAA==.',
Ol='Oldirtycasta:BAAANQAECgEIBQABNQAECgkJHQAIAFAJAA==.',
On='Onayhawe:BAAANQAECgUICAAAAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgoKRAAOALAkAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAABNQAECn8sAAIOAAoKRAay8gA3AQAOAAoKRAay8gA3AQAAAA==.Pallysmack:BAAANQADCgEIAQAAAA==.Pandapwr:BAAANQADCgcIDwABNQAECgoKMQAMAAwbAA==.Pandemul:BAAANQADCggICAABNQAFFAMIBQAOALIhAA==.Patrio:BAAANQADCgYICwABNQAECgkJLgAGABMiAA==.Pawkler:BAAANQAECgQIBQABNQAECgkJGgAbAHYXAA==.Pawshira:BAAANQADCgUIBQABNQAECgkJGgAbAHYXAA==.',
Pe='Peachaid:BAEANQAECgcICAAAAA==.Peachie:BAAANQADCgcIBwAAAA==.Peetree:BAABNQAECn82AAIYAAoKJSIlFgAfAwAYAAoKJSIlFgAfAwAAAA==.Perfectcell:BAAANQADCgYICwAAAA==.Petures:BAAANQAECgMIAwAAAA==.',
Ph='Phosphorus:BAACNQAFFH8HAAIQAAQKJQmFKQBzAAAQAAQKJQmFKQBzAAA1AAQKf4QAAxAACgrIIMEtAAYDABAACgq+H8EtAAYDABEACQooGQEQACkCAAAA.',
Pl='Plagüë:BAACNQAFFH8JAAMKAAUKIwkNCQC9AAAKAAQKIwkNCQC9AAALAAIKaQy6MAA1AAA1AAQKf0UAAwoACgoQIw4SACcDAAoACgpUIg4SACcDAAsACQr4Hh0XAPQCAAAA.Pluckedchkn:BAAANQAECgIIBgABNQAFFAUICQAbADsGAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAABNQAECn8YAAIlAAYKPA+WHQAfAQAlAAYKPA+WHQAfAQAAAA==.Primalistic:BAAANQAECgQIBQAAAA==.',
Pu='Pullnprey:BAAANQADCgYICAAAAA==.Purgedoctor:BAABNQAFFH8IAAIYAAMK8h0nFQAIAQAYAAMK8h0nFQAIAQAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAACNQAFFH8YAAIBAAcKNiCXAQCTAgABAAcKNiCXAQCTAgA1AAQKfzQAAwEACgpNJpMLAHADAAEACgpNJpMLAHADACIAAQp8HLQlAEcAAAAA.',
Ra='Ravenofchaos:BAAANQADCggIDAAAAA==.Ravenoflight:BAAANQAECgIIBAAAAA==.Ravenshatred:BAAANQAECgUIDgAAAA==.Ravenslight:BAAANQABCgQIBAAAAA==.Ravenswrath:BAAANQADCgcIEwAAAA==.Ravenuchiha:BAAANQAECgMIAwAAAA==.Rawrsaur:BAAANQAECgYIEQAAAA==.',
Re='Really:BAAANQAECgcIBwAAAA==.Reallyhpal:BAAANQAECgcIEgAAAA==.Recon:BAAANQADCgMIAwABNQAECgoKGAAHALAFAA==.Redo:BAAANQAECgEIAQAAAA==.Redpocket:BAAANQAECgIIBAAAAA==.Rein:BAABNQAECn8dAAIRAAYKbQimIwDHAAARAAYKbQimIwDHAAAAAA==.Remin:BAAANQAECgUIBgAAAA==.Retaliator:BAAANQAECgEIAQAAAA==.Reuuín:BAAANQADCggIDAABNQAECgoKIwASAJocAA==.Revan:BAAANQAECgEIAQAAAA==.',
Ri='Rimooru:BAABNQAECn8XAAIWAAoKBxTWEAAjAgAWAAoKBxTWEAAjAgABNQAFFAMIBwAEAAQUAA==.Risquae:BAAANQAECgEIAgAAAA==.',
Ro='Romulis:BAAANQAECgUIBwAAAA==.Rooms:BAAANQADCgIIAgAAAA==.Rosè:BAABNQAECn81AAIGAAoKCBykCwD6AgAGAAoKCBykCwD6AgABNQAECgoKSwALACEkAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.Rus:BAAANQAECgEIAQAAAA==.',
Ry='Ryguyro:BAAANQADCgIJAgAAAA==.Ryhia:BAAANQAECgIIAwABNQAECgoKSwALACEkAA==.Ryzee:BAABNQAECn8kAAIIAAoKSRF3sAAiAgAIAAoKSRF3sAAiAgABNQAECgoKMgAZANkbAA==.',
['Rí']='Ríco:BAAANQADCgYIDgAAAA==.',
Sa='Sajaboy:BAAANQADCgIIAgAAAA==.Salena:BAAANQAECgQICQAAAA==.Sans:BAAANQAECggIEQABNQAECgoKUgAZAG0TAA==.Sartha:BAABNQAECn80AAIOAAoKNRdXWAAVAgAOAAoKNRdXWAAVAgAAAA==.Sasuka:BAABNQAECn8cAAMYAAYKUh2fRgDhAQAYAAYKUh2fRgDhAQAZAAMKAg8C8AC2AAAAAA==.Savagesoso:BAAANQADCgQJBAAAAA==.',
Sc='Schy:BAAANQAECgIIAgAAAA==.Scratsxd:BAAANQAECggIBQAAAA==.Scrumpheals:BAAANQAECgEIAQABNQAECgIIAQATAAAAAA==.Scrumpvincet:BAAANQAECgIIAQAAAA==.',
Se='Sedda:BAACNQAFFH8JAAIOAAUKDx/BCQCsAQAOAAUKDx/BCQCsAQA1AAQKfygAAg4ACQqCJWIXAGcDAA4ACQqCJWIXAGcDAAAA.Sensual:BAACNQAFFH8JAAIbAAUKOwZxCACXAAAbAAUKOwZxCACXAAA1AAQKf0IAAhsACgqIHUEPAKkCABsACgqIHUEPAKkCAAAA.Sesshomaru:BAACNQAFFH8HAAIEAAMKBBSnDQDRAAAEAAMKBBSnDQDRAAA1AAQKf04AAgQACgrgI7oEAKcDAAQACgrgI7oEAKcDAAAA.',
Sh='Shadoworca:BAAANQADCgQIBAAAAA==.Shampain:BAABNQAECn8hAAMkAAoKXgpZHACeAQAkAAoKXgpZHACeAQAYAAUKug6B3wCqAAABNQAFFAUICAAFAIEaAA==.Shampooh:BAAANQADCggICAAAAA==.Shang:BAACNQAFFH8TAAIHAAcK6CEkBQDnAQAHAAcK6CEkBQDnAQA1AAQKfzEAAgcACgrtJY4FAKoDAAcACgrtJY4FAKoDAAAA.Shanzo:BAAANQAECggIBAAAAA==.Shiftshot:BAAANQAECgUICAAAAA==.Shiftstab:BAAANQADCgQIBAAAAA==.Shirona:BAABNQAECn80AAMEAAoKWyG8CwDXAgAEAAoKWyG8CwDXAgAPAAcKCgmJOwBqAQAAAA==.Shloomish:BAAANQAECgYIBwAAAA==.Shmized:BAAANQAECgEIAQAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAABNQAECn9DAAIIAAoKLyA7KACSAgAIAAoKLyA7KACSAgABNQAFFAMIBwAEAAQUAA==.',
Si='Siare:BAABNQAECn8pAAIBAAoKDx44HACaAgABAAoKDx44HACaAgAAAA==.',
Sk='Skeeter:BAABNQAECn8rAAQjAAoK7xeGFADLAQABAAgK+RNYhADbAQAjAAYKtBiGFADLAQAiAAUKvw77EwALAQAAAA==.Skroncer:BAAANQADCgYIEgAAAA==.',
Sl='Slyse:BAAANQAECgEIAQAAAA==.',
Sm='Smokinjawn:BAAANQADCgMIAwAAAA==.Smòtts:BAABNQAECn8jAAIJAAoKYhqmDwBnAgAJAAoKYhqmDwBnAgAAAA==.Smótts:BAAANQAECgEIAQAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAABNQAECgQIBAATAAAAAA==.Snizard:BAABNQAECn8XAAICAAYKIRNXswCdAQACAAYKIRNXswCdAQAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQAECgoKOAAbAFEgAA==.',
So='Soawesome:BAABNQAECn8WAAIZAAYKgAnUlQDHAAAZAAYKgAnUlQDHAAABNQAECgkJHQAIAFAJAA==.Solenoid:BAABNQAECn8iAAMXAAoKBRcOXwAEAgAXAAoKBRcOXwAEAgAcAAYKsQxLMwDeAAAAAA==.',
Sp='Spicymustard:BAAANQADCgYICgAAAA==.Springrollz:BAAANQAECgEIAQAAAA==.Spàdes:BAAANQAECgQICgAAAA==.',
Sq='Squírtlé:BAAANQADCgEIAQAAAA==.',
St='Stellanoova:BAABNQAECn8WAAMVAAYKTAa5IQDOAAAVAAUK2ga5IQDOAAAmAAEKFgTFdQAjAAABNQAECgkJKQANAHEPAA==.Stonecolld:BAAANQADCgIIAgAAAA==.Stormbeards:BAAANQADCgcIBwAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarcube:BAAANQAECgUICAABNQAFFAUIFAAJAP0XAA==.Sugarhigh:BAAANQABCgQIBAAAAA==.Sunlight:BAAANQADCggICQAAAA==.Sushirollz:BAAANQAECggICwAAAA==.',
Ta='Taazdingo:BAAANQADCggIEwAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAACNQAFFH8OAAQjAAYK2xc2CACxAAAjAAIKEh42CACxAAAiAAEK9BSIDgBXAAABAAMKVg4BNQBIAAA1AAQKfzsAAwEACgpZJPo4AKkCAAEACAqDJPo4AKkCACMAAwrPHcYRAL4AAAAA.',
Te='Teabear:BAAANQAECggIBwAAAA==.',
Th='Thisishard:BAABNQAECn9BAAIIAAoKgxdZTgAWAgAIAAoKgxdZTgAWAgAAAA==.Thorshammer:BAAANQADCgUIBQAAAA==.Thryen:BAAANQAECgQIDAAAAA==.Thundergrasp:BAABNQAECn8yAAIZAAoK2RuhHgBsAgAZAAoK2RuhHgBsAgAAAA==.',
To='Toe:BAACNQAFFH8IAAIKAAMKjQkxCADOAAAKAAMKjQkxCADOAAA1AAQKfxYAAgoACQp8GPhGAPwBAAoACQp8GPhGAPwBAAAA.Toobestake:BAAANQAECgEIBgABNQAFFAcIIAAWAKkYAA==.Topenga:BAACNQAFFH8IAAICAAQKxBGpHQCfAAACAAQKxBGpHQCfAAA1AAQKf1IAAgIACgpRI/kWAOACAAIACgpRI/kWAOACAAAA.',
Tr='Trunnks:BAAANQAECgcICAAAAA==.',
Ts='Tsargock:BAAANQADCgUIBAAAAA==.',
Tu='Tuoldforthis:BAAANQAECgIIAwAAAA==.',
Tw='Twicelife:BAAANQAECgUICwABNQAFFAQIBwAQACUJAA==.',
Ty='Typhoid:BAAANQAECggIEAAAAA==.',
['Tñ']='Tñt:BAAANQAECgYICwABNQAECgoKRwABAHUiAA==.',
Um='Umei:BAAANQAECgIIAgAAAA==.',
Ur='Urbek:BAABNQAECn8VAAIHAAcKGyDhLgBoAgAHAAcKGyDhLgBoAgAAAA==.Urthstripe:BAABNQAECn8oAAIGAAoKTxfdGQAkAgAGAAoKTxfdGQAkAgAAAA==.',
Us='Usualsuspect:BAAANQAECgIIAgAAAA==.',
Uw='Uwu:BAAANQAECgUIBQABNQAFFAgIGQAcALoQAA==.',
Va='Valle:BAAANQADCggIDgABNQAFFAgIGQAcALoQAA==.Valoria:BAAANQAECggICAABNQAFFAgIGQAcALoQAA==.',
Ve='Velgabrine:BAAANQAECgQICAABNQAFFAMIBQAOALIhAA==.Veraani:BAAANQADCggICAAAAA==.Verlaria:BAAANQADCgEIAQAAAA==.',
Vi='Viserion:BAABNQAECn8pAAMNAAkKcQ/eDACEAQANAAgK9BDeDACEAQAgAAUKkApxMwD7AAAAAA==.',
Vu='Vue:BAACNQAFFH8IAAIFAAUKgRrZCAC3AQAFAAUKgRrZCAC3AQA1AAQKf1kAAgUACgrGH6sbAAYDAAUACgrGH6sbAAYDAAAA.Vulkun:BAAANQAECgMIBAAAAA==.',
Wa='Wakasham:BAACNQAFFH8XAAIkAAYKWSXWAACuAQAkAAYKWSXWAACuAQA1AAQKfy4AAiQACgqrJqcAANQDACQACgqrJqcAANQDAAAA.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAABNQAECn8ZAAMEAAkKtSAiFAD9AgAEAAkKtSAiFAD9AgAPAAIKUgjsYwBbAAABNQAFFAgIGAAPAL0ZAA==.',
Wi='Wickedmisery:BAAANQADCgYIBgAAAA==.',
Wo='Wolfpacked:BAABNQAECn8bAAIYAAYKFhnpdgCnAQAYAAYKFhnpdgCnAQABNQAECgoKOAABADciAA==.Wolfzbåin:BAAANQAECgQIAwAAAA==.',
Wr='Wrbringer:BAAANQADCgEIAQAAAA==.',
Wu='Wunderlust:BAACNQAFFH8IAAIIAAUKhQ2LJQDXAAAIAAUKhQ2LJQDXAAA1AAQKf0QAAggACgqnImAnAEQDAAgACgqnImAnAEQDAAAA.',
Xe='Xeroidz:BAAANQADCgcICgAAAA==.',
Xs='Xscrats:BAAANQAECggIBQAAAA==.',
Ye='Yellowshaman:BAACNQAFFH8JAAIZAAMKpA20GwDkAAAZAAMKpA20GwDkAAA1AAQKfywAAxkACQrpHs0mAOgCABkACQrpHs0mAOgCABgAAQoTDhP4AC0AAAAA.Yerac:BAABNQAFFH8OAAMGAAUKRwqCCAAzAQAGAAUKRwqCCAAzAQAHAAEK4QEjIwA0AAAAAA==.',
Za='Zandelussy:BAABNQAECn84AAMbAAoKUSDbBQDyAgAbAAkKUSDbBQDyAgAFAAoKkx4yKAB6AgAAAA==.Zapper:BAAANQAECgIIBAAAAA==.',
Zu='Zugg:BAAANQAECgYIBwABNQAFFAgIGQAcALoQAA==.Zuriznikov:BAABNQAECn8eAAUGAAgK8w2WKACOAQAGAAgK8w2WKACOAQAHAAQKCQXAjQCfAAAJAAQKqgc+RgCZAAAUAAEKhAm3RQAuAAABNQAECgkJKQANAHEPAA==.',
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
