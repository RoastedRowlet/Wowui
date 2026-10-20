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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Warlock-Demonology','DemonHunter-Devourer','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','Priest-Holy','DeathKnight-Blood','Paladin-Protection','Warlock-Destruction','Druid-Balance','Monk-Windwalker','Priest-Discipline','Druid-Restoration','Druid-Feral','Paladin-Holy','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Havoc','Mage-Frost','Shaman-Restoration','Priest-Shadow','Monk-Mistweaver','Monk-Brewmaster','Warlock-Affliction','Paladin-Retribution','Mage-Fire','Evoker-Preservation','Warrior-Fury','Evoker-Devastation',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abednego:BAABNQAECn8vAAMBAAkKZRdVDgCSAgABAAkKZRdVDgCSAgACAAQK9As1NAB4AAAAAA==.',
Ac='Acidrain:BAABNQAECn8oAAIDAAkKqBmJBQAbAgADAAkKqBmJBQAbAgAAAA==.Acmiax:BAAANQAECgQICAABNQAECgoKKAAEAMAVAA==.',
Ad='Adar:BAAANQAECgUIDwAAAA==.Adonsinn:BAABNQAECn8bAAIFAAgKhR8oBgCuAQAFAAgKhR8oBgCuAQAAAA==.',
Ae='Aegos:BAAANQAECgQIBgAAAA==.Aep:BAAANQAECgMJBAABNQAECgQICAAGAAAAAA==.',
Ah='Ahu:BAABNQAECn81AAMHAAkK3hbUSACSAgAHAAkK3hbUSACSAgAIAAEKKgZMlQArAAAAAA==.',
Ai='Airotciv:BAAANQAECgEIAQAAAA==.',
Al='Alakazam:BAAANQADCgUIBgAAAA==.Alanath:BAAANQADCgQIBAAAAA==.Alandramun:BAAANQAECgIIAgAAAA==.Aleroderp:BAABNQAECn8XAAIIAAkKMwM0GwC1AAAIAAkKMwM0GwC1AAAAAA==.Allaria:BAAANQAECgIIBQAAAA==.Alucard:BAAANQAECgIIAgAAAA==.',
Am='Amaging:BAABNQAECn8lAAIJAAkKqgqmxAD7AQAJAAkKqgqmxAD7AQAAAA==.Ambassador:BAAANQAECgUIBQAAAA==.Amoondai:BAACNQAFFH8IAAIKAAMKWQ/FFACBAAAKAAMKWQ/FFACBAAA1AAQKfz4AAgoACgr9ImcGAI0CAAoACgr9ImcGAI0CAAAA.',
An='Analytics:BAAANQAECgcIEQAAAA==.Angusdei:BAAANQADCgIIAgAAAA==.Anyr:BAAANQADCgMIAwAAAA==.',
Ap='Apochryphal:BAABNQAECn8qAAILAAkKwhuwBAAMAgALAAkKwhuwBAAMAgAAAA==.',
Ar='Aranadar:BAAANQADCgEIAQAAAA==.Araylva:BAAANQADCgcIBwAAAA==.Arrtemiss:BAAANQADCgMIBAABNQAECgUIDgAGAAAAAA==.Artium:BAAANQADCgEIAwAAAA==.',
As='Asheraah:BAAANQADCgEIAQAAAA==.Ashogg:BAAANQAECgYIEgAAAA==.',
At='Atorious:BAAANQADCgEIAQAAAA==.Atriuage:BAAANQADCgEIAQAAAA==.',
Au='Aurén:BAAANQADCggIEwAAAA==.',
Az='Azenethera:BAAANQADCgEIAQAAAA==.Azuree:BAAANQAECgMIBQAAAA==.',
Ba='Bacstabath:BAABNQAECn88AAMCAAoKjCIODwAJAwACAAgKKCMODwAJAwABAAkKchzTDwB/AgAAAA==.Ballista:BAAANQADCgEIAQAAAA==.',
Be='Becca:BAABNQAECn8wAAIMAAoKQh2UAQBwAgAMAAoKQh2UAQBwAgAAAA==.Bequin:BAAANQADCgUIBQAAAA==.',
Bi='Bigdaddys:BAAANQAECgMIAgAAAA==.Bigduh:BAAANQADCgQIBQAAAA==.Birblock:BAABNQAECn81AAMEAAoKryAuAgDeAgAEAAoKryAuAgDeAgANAAQK8A9YNgDoAAABNQAFFAYIFgAOAAgTAA==.',
Bl='Blaizee:BAAANQADCgIIAgAAAA==.Blasphemar:BAAANQADCgYJBwAAAA==.Bloodios:BAABNQAECn80AAILAAoKAhjHAgBkAgALAAoKAhjHAgBkAgAAAA==.Bluechewgold:BAABNQAECn8lAAILAAkKgCLJCgBeAwALAAkKgCLJCgBeAwAAAA==.',
Bo='Bobbardment:BAAANQADCgQIBAABNQAECgQIBAAGAAAAAA==.Bobin:BAABNQAECn8dAAIPAAgKDhJKKQDUAQAPAAgKDhJKKQDUAQAAAA==.Bombadil:BAABNQAECn8jAAIQAAkKag7gAADmAQAQAAkKag7gAADmAQAAAA==.Boshek:BAAANQABCgUJCQAAAA==.',
Br='Bribage:BAACNQAFFH8WAAMOAAYKCBPKDwBtAQAOAAYKCBPKDwBtAQARAAEKowkQFQBKAAA1AAQKfyIAAw4ACgowH7UcAOMCAA4ACgowH7UcAOMCABIAAQozH+k4AFkAAAAA.Brightest:BAAANQAECgIIAQAAAA==.Brolaf:BAAANQADCgIIAwABNQAFFAUIFAATAJkkAA==.Brolavski:BAACNQAFFH8UAAITAAUKmSQvBgANAgATAAUKmSQvBgANAgA1AAQKfxUAAhMACQpcHnYuAK0CABMACQpcHnYuAK0CAAAA.',
Bu='Budderwar:BAABNQAECn8vAAMUAAkKhiUJAQDKAwAUAAkKhiUJAQDKAwAVAAQK9RGs9QDzAAAAAA==.Buster:BAABNQAECn8aAAMWAAgKEAvLFQBPAQAWAAgKEAvLFQBPAQAFAAQKhQMZYQBpAAAAAA==.Buzkills:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàdmofos:BAAANQADCgcJCQAAAA==.',
['Bë']='Bëëfy:BAAANQADCgEIAQAAAA==.',
Ca='Carébéar:BAAANQADCgEIAQAAAA==.',
Ce='Celerydk:BAABNQAECn8vAAIXAAoKSBorGADJAgAXAAoKSBorGADJAgAAAA==.',
Ch='Chaosgaara:BAAANQADCgEIAgAAAA==.Chikñ:BAAANQAECgQIAQAAAA==.',
Co='Colossus:BAABNQAECn8eAAMYAAgKpR6QJQCoAgAYAAgKpR6QJQCoAgALAAMKUgtDqQB+AAAAAA==.Connor:BAAANQAECgIIBAAAAA==.Correin:BAABNQAECn8rAAIZAAoKpw8aDwB0AQAZAAoKpw8aDwB0AQAAAA==.',
Cr='Craszhin:BAABNQAECn8oAAIOAAkKlgwfCwCNAQAOAAkKlgwfCwCNAQAAAA==.Crime:BAAANQAECgMIAwAAAA==.',
['Cè']='Cèl:BAABNQAECn8rAAMaAAoKsA2xBABgAQAaAAoKsA2xBABgAQAJAAQKoQGUogF9AAAAAA==.',
Da='Daddio:BAEANQAECgQIBwAAAA==.Daenarea:BAAANQADCgYIBgAAAA==.Dangpup:BAABNQAECn8tAAIIAAoKrxd6BwBuAQAIAAoKrxd6BwBuAQAAAA==.Danru:BAAANQADCgQICwAAAA==.Darkdelight:BAABNQAECn82AAIHAAoKtRTOUQB7AgAHAAoKtRTOUQB7AgAAAA==.',
De='Deathlylazy:BAAANQAECgcICgAAAA==.Deets:BAABNQAECn8iAAIHAAkKHB67CAA6AgAHAAkKHB67CAA6AgAAAA==.Demona:BAABNQAECn8pAAMNAAkKlwyRAQB7AQANAAkKlwyRAQB7AQAEAAEKEwE7WgEcAAAAAA==.Derfhurnturr:BAAANQAECgUIBgAAAA==.Descalabrada:BAAANQAECgcICwAAAA==.',
Di='Distol:BAAANQADCgIIAgAAAA==.',
Dr='Draeamorjan:BAAANQADCgEIAQAAAA==.Driver:BAEANQAECggIBwAAAA==.Drpeppers:BAABNQAECn8iAAIRAAkK8RAcEgA1AQARAAkK8RAcEgA1AQAAAA==.',
['Dé']='Déathsavage:BAAANQADCggIIAAAAA==.',
Ea='Eatmorchikin:BAAANQADCgMJAwAAAA==.',
Ec='Eclair:BAABNQAECn8qAAIbAAkK/CAFAwDzAgAbAAkK/CAFAwDzAgAAAA==.',
El='Elfkr:BAABNQAECn8eAAMbAAgKJiEDIwDbAgAbAAgKJiEDIwDbAgADAAIK+hif+wCbAAAAAA==.Elhayn:BAABNQAECn8mAAIcAAkKESKdAwDZAQAcAAkKESKdAwDZAQAAAA==.Elmos:BAABNQAECn82AAIPAAoKMh/tBwBQAwAPAAoKMh/tBwBQAwAAAA==.',
Er='Erethidian:BAAANQADCgQIBAAAAA==.Eris:BAAANQADCgYIBwAAAA==.',
Ev='Evilmonkeydr:BAAANQAECgQIBAABNQAECgoKHwAJAD0eAA==.Evilmonkeymg:BAABNQAECn8fAAIJAAoKPR45HQCbAQAJAAoKPR45HQCbAQAAAA==.Evilmonkeysh:BAAANQADCgUIBQABNQAECgoKHwAJAD0eAA==.',
Ez='Ezaylia:BAABNQAECn8iAAIZAAgKEg/2FABEAQAZAAgKEg/2FABEAQAAAA==.',
Fa='Fatehunter:BAABNQAECn8cAAIHAAcKuhI6VQAFAQAHAAcKuhI6VQAFAQAAAA==.',
Fe='Feim:BAAANQADCggICgAAAA==.Fenrisulfr:BAAANQADCgEIAQABNQADCgYIBgAGAAAAAA==.Fergis:BAABNQAECn8nAAMaAAkKbxoMAQA4AgAaAAgKbxoMAQA4AgAJAAYKGxSc+wCWAQAAAA==.',
Fi='Firefox:BAABNQAECn8dAAILAAkKORlONgAyAgALAAkKORlONgAyAgAAAA==.',
Fl='Flypig:BAAANQADCggIBwAAAA==.',
Fr='Frostybeary:BAAANQADCgEIAQAAAA==.Frostymonk:BAABNQAECn8aAAMdAAkKFQtTDgDyAAAdAAcKbw1TDgDyAAAeAAIKlATyEQBTAAAAAA==.Frostypally:BAAANQAECggIDwAAAA==.',
Fu='Fuel:BAAANQADCgYIBgABNQAECgYIDQAGAAAAAA==.Furrybear:BAAANQAECgEIAgAAAA==.',
Ga='Gala:BAAANQAECggIEwAAAA==.',
Ge='Genorian:BAABNQAECn8cAAIOAAoKFBKhBAALAgAOAAoKFBKhBAALAgAAAA==.',
Gi='Gigem:BAABNQAECn8ZAAIHAAcKjhqsiwDzAQAHAAcKjhqsiwDzAQAAAA==.Girlshoon:BAAANQAECgEIAwAAAA==.Githan:BAAANQAECgYIDAABNQAECgkJJwARAK0bAA==.',
Gl='Glarious:BAABNQAECn8tAAIBAAoKlw/3FAA/AgABAAoKlw/3FAA/AgAAAA==.',
Go='Gobbozap:BAAANQADCggIDgABNQAECgoKLgAQAC8fAA==.',
Gr='Grandpa:BAAANQADCgEIAQAAAA==.Gredan:BAABNQAECn8WAAILAAcKqxZREwBIAQALAAcKqxZREwBIAQAAAA==.Greymoor:BAAANQABCgQIBAAAAA==.Gruhm:BAAANQADCgUIBgAAAA==.Grôg:BAAANQAECggICgAAAA==.',
Gu='Guldaniel:BAABNQAECn8oAAIEAAoKwBX/PQCZAgAEAAoKwBX/PQCZAgAAAA==.Guthuzad:BAAANQADCgUIBgAAAA==.Guthx:BAABNQAECn8cAAMOAAgK6hcYRADjAQAOAAcK7BcYRADjAQARAAMKKA+0WAClAAAAAA==.',
Ha='Halfaman:BAAANQAECgUIBwABNQAFFAIIAgAGAAAAAA==.Hantzel:BAAANQADCgUIBgAAAA==.',
He='Healyeah:BAAANQAECgEIAQAAAA==.Hellen:BAABNQAECn8YAAIEAAgKziHuLADSAgAEAAgKziHuLADSAgAAAA==.',
Hw='Hwat:BAAANQAECgYIDwAAAA==.',
Ic='Ictus:BAABNQAECn8XAAIJAAgKtBzjcACcAgAJAAgKtBzjcACcAgAAAA==.',
In='Incredabull:BAAANQAECgIIAgAAAA==.',
Is='Isabelle:BAACNQAFFH8HAAIIAAIKHwolCgBxAAAIAAIKHwolCgBxAAA1AAQKfywAAggACQr7Ew0MADABAAgACQr7Ew0MADABAAAA.Isharded:BAABNQAECn8uAAIfAAoKiw0pAQDHAQAfAAoKiw0pAQDHAQAAAA==.Istayblunted:BAAANQAECgUIBwAAAA==.',
Ja='Jacqualyn:BAAANQAFFAIIAgAAAA==.Jaylon:BAAANQADCgUIBQAAAA==.',
Ji='Jiayerah:BAAANQADCggIEAABNQAECgcIEwAGAAAAAA==.Jinkuzo:BAABNQAECn8mAAIeAAkKrhhxAgCiAQAeAAkKrhhxAgCiAQAAAA==.Jinmu:BAABNQAECn8qAAMBAAkKChGjEABRAQACAAcKJwjeVgBfAQABAAkKChGjEABRAQAAAA==.',
Jo='Joaquin:BAAANQADCgEIAQABNQAECgQIBwAGAAAAAA==.',
Ju='Juanaloopa:BAAANQAECgcIDQAAAA==.Juggie:BAABNQAECn8bAAMKAAcKVwWCnQA9AQAKAAcKVwWCnQA9AQAcAAUKXwSwVAC7AAAAAA==.Julienned:BAABNQAECn8tAAICAAoK5ww2BQDOAQACAAoK5ww2BQDOAQAAAA==.',
['Jè']='Jèsse:BAAANQADCgcJCQAAAA==.',
Ka='Kainen:BAABNQAECn8qAAQgAAkK8xhpEgDoAQAgAAkK8xhpEgDoAQATAAQKGQOP8QCdAAAMAAQK4QNSWgBzAAAAAA==.Kattlock:BAAANQADCgEIAQAAAA==.',
Ki='Kinkybunny:BAAANQADCgYJBgAAAA==.',
Kl='Klodar:BAABNQAECn8ZAAIcAAYK9hGHFADmAAAcAAYK9hGHFADmAAAAAA==.Klum:BAAANQADCgEIAQAAAA==.',
Kr='Krazee:BAAANQABCgMIBQAAAA==.',
La='Lafey:BAAANQADCgIJAgAAAA==.Lamedout:BAAANQADCgcIBwABNQAECgYIDQAGAAAAAA==.Lanfear:BAAANQADCgQIBQAAAA==.Laurenya:BAAANQADCgMIAwABNQAECgUIDgAGAAAAAA==.',
Le='Leida:BAAANQADCgcICwAAAA==.Leinen:BAAANQADCgYICAAAAA==.',
Lo='Logi:BAAANQAECgQICAAAAA==.Lostrage:BAAANQADCgcICgAAAA==.',
Lu='Lumiyer:BAABNQAECn8hAAIKAAoKjxrhAgAkAwAKAAoKjxrhAgAkAwABNQAFFAcIGQAdAHgcAA==.',
Ly='Lygra:BAAANQAECgUIEAAAAA==.Lykana:BAAANQAECgQIBQAAAA==.Lyrasong:BAAANQADCgMIAwAAAA==.Lytharielis:BAAANQADCgEIAQAAAA==.',
Ma='Majellan:BAABNQAECn80AAMMAAoKBxUSBADQAQAMAAoKBxUSBADQAQAgAAgKzw2NuACtAQAAAA==.Marsawn:BAABNQAECn8zAAMKAAoKrhdiDAAhAgAKAAoKrhdiDAAhAgAcAAIKbh8/VQC4AAAAAA==.Mass:BAACNQAFFH8aAAIUAAcKiyUWAADzAgAUAAcKiyUWAADzAgA1AAQKfycAAhQACgoIJRQCAJ0DABQACgoIJRQCAJ0DAAAA.',
Me='Meatbatticus:BAAANQAECgcICwAAAA==.Meqi:BAABNQAECn8WAAMJAAcKPx/iEgDPAQAJAAcKPx/iEgDPAQAhAAEK7R29CgBVAAAAAA==.',
Mi='Mindlessness:BAABNQAECn8pAAIVAAoKERtiFAC5AQAVAAoKERtiFAC5AQAAAA==.Mineralelf:BAABNQAECn80AAIHAAoKngreKgBwAQAHAAoKngreKgBwAQAAAA==.Minichaos:BAABNQAECn8jAAMNAAgKdRaLDAAuAgANAAgKxBOLDAAuAgAEAAYKsQ2SRwD7AAAAAA==.Miriam:BAABNQAECn84AAIJAAoKPApUGACuAQAJAAoKPApUGACuAQAAAA==.',
Mo='Mojosavage:BAABNQAECn8YAAIEAAcKWgPxhQB3AAAEAAcKWgPxhQB3AAAAAA==.Moonblade:BAAANQAECgEIAQAAAA==.',
My='Mylas:BAAANQADCgcIBwAAAA==.Mysticalfox:BAAANQADCgEIAQAAAA==.',
Na='Nalfilas:BAABNQAECn8VAAIJAAYKpwaVNgExAQAJAAYKpwaVNgExAQAAAA==.',
Ne='Nephaleos:BAABNQAECn8mAAIiAAkKnR+UCwDqAgAiAAkKnR+UCwDqAgAAAA==.Nessie:BAAANQAECgIIAgAAAA==.',
Ni='Nihlus:BAAANQAECgYICgAAAA==.',
No='Nocturnous:BAAANQAECgMIBAAAAA==.',
Nu='Nurzul:BAAANQADCggICgABNQAECggICgAGAAAAAA==.',
Ny='Nyrvana:BAAANQAECgYICQAAAA==.',
['Nà']='Nàtureswrath:BAAANQAECgYIDQAAAA==.',
Og='Ogre:BAAANQADCggIGgAAAA==.',
Ol='Olblunty:BAAANQADCgEIAQAAAA==.',
Or='Orceo:BAABNQAECn8oAAIHAAoKvyIsGgAwAwAHAAoKvyIsGgAwAwAAAA==.Orkeo:BAAANQADCgcICwAAAA==.Orkreghar:BAABNQAECn8mAAIHAAkKdBrxQACoAgAHAAkKdBrxQACoAgAAAA==.',
Pa='Padawon:BAAANQAECgQICgAAAA==.Pallon:BAAANQAECgcJCwAAAA==.',
Ph='Phazma:BAAANQADCgUIBQAAAA==.',
Pi='Pindapin:BAAANQAECgMIBQAAAA==.',
Po='Pompompower:BAABNQAECn8uAAIDAAoK4AfkdwC6AQADAAoK4AfkdwC6AQAAAA==.Popashammy:BAAANQAECgIIAgAAAA==.Poplock:BAAANQADCgcIFwAAAA==.Popple:BAABNQAECn8WAAIjAAkKyAsPDwC8AQAjAAkKyAsPDwC8AQAAAA==.Potential:BAAANQAECgQIBAAAAA==.',
Pu='Puggsly:BAAANQAECgQIBAABNQAECgoKKAAEAMAVAA==.',
Qa='Qaccy:BAAANQADCgEIAQAAAA==.',
Qu='Quixotical:BAAANQADCgYIDAAAAA==.',
Ra='Radaghast:BAAANQAECgIIAgAAAA==.Raoul:BAAANQADCgEIAQABNQAFFAIIAgAGAAAAAA==.',
Re='Rectumraker:BAAANQAECgMIBQAAAA==.Reishirome:BAAANQADCggIFQAAAA==.Revenmar:BAAANQADCgQIBAAAAA==.',
Rh='Rhaelin:BAABNQAECn8mAAIbAAoK+RpIHgDyAgAbAAoK+RpIHgDyAgAAAA==.Rhaellia:BAAANQADCggICAAAAA==.Rhoke:BAABNQAECn8vAAIgAAgKIhBcrgDCAQAgAAgKIhBcrgDCAQAAAA==.',
Ro='Romeoz:BAAANQADCgMIBAABNQAFFAIIAgAGAAAAAA==.Rona:BAAANQAECgQIDAAAAA==.Roofhouse:BAAANQADCgMIAwAAAA==.Rosary:BAABNQAECn8dAAIKAAgKeyAsJQDXAgAKAAgKeyAsJQDXAgAAAA==.Rotiserychic:BAAANQAECgIIAwAAAA==.Roukia:BAAANQADCgEIAQAAAA==.',
Ru='Rusticfinger:BAABNQAECn8cAAIbAAgK0RcSUwAaAgAbAAgK0RcSUwAaAgAAAA==.',
Sa='Sacerdote:BAAANQAECgMIBAAAAA==.Sansa:BAAANQAECgcIEwAAAA==.Saruma:BAAANQADCggIDwABNQAECggICgAGAAAAAA==.',
Sc='Scalygrob:BAABNQAECn8VAAIkAAgKMBESFgDqAQAkAAgKMBESFgDqAQAAAA==.Scarytery:BAAANQAECgYIEAAAAA==.Scrügemcmonk:BAAANQAECgQIBAAAAA==.',
Sh='Shamaya:BAAANQABCgMIAwABNQADCgIIAgAGAAAAAA==.Shamfox:BAABNQAECn8YAAMDAAcKDw3gNgDmAAADAAcKDw3gNgDmAAAbAAEKNwJTKQElAAAAAA==.Shatrium:BAAANQADCgEIAQAAAA==.',
Si='Sidewinder:BAAANQAECgYIBgAAAA==.',
Sm='Smogcheck:BAACNQAFFH8GAAIiAAIKcRPPCACKAAAiAAIKcRPPCACKAAA1AAQKfykAAyIACgrBFnITAHYCACIACgrBFnITAHYCACQAAgpQC+Q1AF8AAAAA.',
Sn='Snowsz:BAAANQAECgcIDgAAAA==.Snowws:BAABNQAECn8pAAIZAAoKtx5lEQAUAwAZAAoKtx5lEQAUAwAAAA==.Snowzz:BAAANQADCgQIBAAAAA==.',
So='Sonektot:BAAANQAECgEIAQAAAA==.Sortis:BAABNQAECn8iAAMJAAkKGRx/ZAC1AgAJAAkKGRx/ZAC1AgAaAAEK/wNQUAAnAAAAAA==.',
Sp='Spicebreff:BAAANQAECgEIAQABNQAECgcIGwAVAOsYAA==.',
St='Steck:BAAANQAECgUIEAAAAA==.Strigg:BAAANQADCgMIAwABNQADCggIEQAGAAAAAA==.Strigöi:BAAANQADCggIEQAAAA==.',
Su='Suprahunts:BAABNQAECn8dAAMHAAcKcCLRUgB4AgAHAAcKcCLRUgB4AgAIAAQKeA3tVQDOAAAAAA==.',
['Sà']='Sàlís:BAAANQADCgcIEAAAAA==.',
Ta='Talander:BAAANQADCgUIBQABNQAFFAIIAgAGAAAAAA==.Talas:BAABNQAECn82AAMHAAoKxxp3MQDYAgAHAAoKxxp3MQDYAgAIAAYK1w+JRQAtAQAAAA==.Tarshaa:BAAANQADCgEIAQAAAA==.',
Te='Teaka:BAAANQAECgEIAQAAAA==.',
Th='Thaeker:BAAANQADCggIDwAAAA==.Thaelink:BAAANQAECgEIAQABNQAECgkJIAAJAE8XAA==.Thickthighs:BAAANQAECgYICQABNQAFFAIIAgAGAAAAAA==.Thorss:BAAANQAECgIIAwABNQAECgYIEAAGAAAAAA==.Thrann:BAABNQAECn8oAAIYAAoKKyL0AgAvAgAYAAoKKyL0AgAvAgAAAA==.',
Ti='Tirium:BAABNQAECn8bAAIVAAcK6xjenADUAQAVAAcK6xjenADUAQAAAA==.',
To='Tolkien:BAABNQAECn8bAAIXAAYKABCCKgD0AAAXAAYKABCCKgD0AAAAAA==.',
Tu='Tubbytotem:BAAANQADCgYIDAAAAA==.',
Un='Unduril:BAAANQADCgYIBgAAAA==.',
Ur='Ursae:BAAANQADCgIIAgAAAA==.',
Va='Vanargandr:BAAANQADCgYIBgAAAA==.Vartlek:BAAANQADCgYIBgAAAA==.',
Ve='Velarys:BAAANQADCgEIAQABNQAECgoKLgAQAC8fAA==.Velinlock:BAAANQADCgEIAgAAAA==.Velinthil:BAAANQADCgcIBwAAAA==.Verðandi:BAAANQADCgMJBAAAAA==.',
Vi='Vigilante:BAAANQAECgUIBQAAAA==.',
Vo='Volvox:BAAANQADCggIDAAAAA==.',
Vy='Vyxenn:BAABNQAECn80AAMbAAoK2BrABwBKAgAbAAoK2BrABwBKAgADAAIK1wbXFwFfAAAAAA==.',
Wa='Wanders:BAAANQAECgQIAQABNQAECgQIBAAGAAAAAA==.Wartrium:BAAANQADCgEIAQAAAA==.Washim:BAAANQADCggICQAAAA==.',
Wo='Wonkybits:BAAANQAECgQIBAAAAA==.',
Wu='Wurm:BAAANQADCgQIBAABNQAECggICgAGAAAAAA==.',
Ye='Yejena:BAAANQAECgIIAwAAAA==.',
Za='Zaleras:BAAANQADCggIDwAAAA==.',
Ze='Zerkium:BAAANQAECgcIEgAAAA==.',
Zi='Zillaamiri:BAAANQAECgcICgAAAA==.',
Zu='Zugzugdaboo:BAAANQADCggJGQAAAA==.',
Zy='Zyrinx:BAAANQADCgEIAQAAAA==.Zywol:BAABNQAECn80AAMOAAoKmBe3AwAwAgAOAAoKmBe3AwAwAgARAAMKDg0mWQCjAAAAAA==.',
['Ër']='Ëresta:BAAANQADCgYIFQABNQAECgkJKQAHAOUZAA==.',
['Ðe']='Ðespair:BAABNQAECn8cAAMKAAoK1htbTABAAgAKAAcKgRxbTABAAgAcAAgKohjZLQC3AQAAAA==.',
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
