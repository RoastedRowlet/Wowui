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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Unknown-Unknown','Warrior-Fury','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Druid-Guardian','Paladin-Protection','Hunter-Marksmanship','Paladin-Holy','Mage-Frost','Rogue-Subtlety','Warrior-Protection','Evoker-Augmentation','Monk-Brewmaster','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Hunter-Survival','DeathKnight-Unholy','Evoker-Devastation','Evoker-Preservation','Monk-Windwalker','Warrior-Arms','Druid-Feral','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Holy','Shaman-Restoration','Shaman-Enhancement','Druid-Restoration','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Blood','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=46,date='2026-05-30',data={Ai='Aisling:BAAALgADCgYJBgAAAA==.',
Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAABLgAECn8UAAIBAAkJKQwxYACpAQABAAkJKQwxYACpAQAAAA==.Allinaa:BAABLgAECn8cAAICAAkJwQ5GRgC3AQACAAkJwQ5GRgC3AQAAAA==.Alya:BAAALgADCgkJEAAAAA==.',
Am='Amorvea:BAAALgADCgUJBQABLgAECgIJAgADAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAACLgAFFH8IAAIEAAMJUQPKMwCyAAAEAAMJUQPKMwCyAAAuAAQKfzMAAgQACQnrDOgpAJsBAAQACQnrDOgpAJsBAAAA.Antilight:BAAALgAECgcJAQAAAA==.',
Ar='Arcade:BAAALgAECgEJAgAAAA==.Arlyx:BAACLgAFFH8QAAMBAAUJRR5+SwAdAQABAAQJBSB+SwAdAQAFAAIJzxPuGgBWAAAuAAQKfygABAEACAkTH+oqACECAAEABwlCG+oqACECAAUAAwnzFohHAJgAAAYAAgnoBzQfAHcAAAAA.Arnwaz:BAAALgAECggJEwAAAA==.Arthuria:BAAALgAECggJDAAAAA==.',
As='Aslan:BAAALgADCgQJBwAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Av='Avelyn:BAAALgAFFAIJAwAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAACLgAFFH8MAAIHAAQJaxc4NQApAQAHAAQJaxc4NQApAQAuAAQKfxoAAgcABwl3HYY+ACsCAAcABwl3HYY+ACsCAAAA.Bayside:BAAALgAECgYJEQAAAA==.',
Be='Bearfomat:BAABLgAFFH8FAAIIAAMJFh5ECwAOAQAIAAMJFh5ECwAOAQAAAA==.Beefis:BAAALgAECgUJCwAAAA==.Beenjuicin:BAAALgAFFAEJAgABLgAFFAIJAgADAAAAAA==.Berfomat:BAABLgAECn8rAAIJAAkJ1CGzAgDoAgAJAAkJ1CGzAgDoAgAAAA==.',
Bi='Bingchilling:BAACLgAFFH8TAAIKAAUJyRLpCgBrAQAKAAUJyRLpCgBrAQAuAAQKfzAAAgoACQnqHAgMAOoCAAoACQnqHAgMAOoCAAAA.',
Bj='Bjorn:BAAALgAFFAIJAwAAAA==.',
Bl='Bloodyfupa:BAAALgAECgIJAQAAAA==.Bloomyvfd:BAABLgAECn8vAAILAAgJmB4EDQCrAgALAAgJmB4EDQCrAgAAAA==.',
Bo='Bombuur:BAAALgAECgQJCAAAAA==.Bonniebadass:BAABLgAECn8VAAIHAAgJRApjkAA2AQAHAAgJRApjkAA2AQAAAA==.Bottle:BAABLgAECn8WAAIEAAgJrxv1GQAKAgAEAAgJrxv1GQAKAgAAAA==.Boxxylove:BAAALgAECgQJBwAAAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAABLgAECn8eAAIHAAgJuyL6GACXAgAHAAgJuyL6GACXAgAAAA==.',
Ca='Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8tAAIMAAcJ/xvVZgAJAgAMAAcJ/xvVZgAJAgAAAA==.Capybubger:BAAALgAECggJDwABLgAFFAcJFAANAJAjAA==.Cavalis:BAACLgAFFH8JAAMBAAMJuhJ1ZgDdAAABAAMJcg91ZgDdAAAGAAEJSg5gIABIAAAuAAQKfzMABAEACQmTG1gxAAcCAAEACAm3GVgxAAcCAAYABQmyF7ESAAEBAAUABAlsHE8UAO8AAAAA.',
Ce='Ceedh:BAAALgAFFAMJBAAAAA==.Ceejr:BAACLgAFFH8ZAAMEAAgJhCKlAQDoAQAEAAUJ5iKlAQDoAQAOAAUJuCA7BwCZAQAuAAQKfyoAAwQACQlpJSQBAMQDAAQACQlpJSQBAMQDAA4ABgmLIm4OAOsBAAAA.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgADAAAAAA==.Chillum:BAAALgAECgIJAgABLgAFFAUJEgAPAKMWAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgUJCwAAAA==.',
Cr='Creativez:BAACLgAFFH8IAAIQAAIJxRmzGACoAAAQAAIJxRmzGACoAAAuAAQKfxYAAhAABwkIJK8OAKsCABAABwkIJK8OAKsCAAEuAAUUBAkJAAgAPhsA.Creativezd:BAABLgAFFH8JAAIIAAQJPhvJBwBDAQAIAAQJPhvJBwBDAQAAAA==.',
Da='Dadgoo:BAAALgAECgMJBQAAAA==.Damnskippy:BAAALgAECgcJDQAAAA==.Dannÿ:BAABLgAECn8lAAMRAAgJmRRhIgCXAQARAAcJnhVhIgCXAQASAAMJow5IVQCTAAAAAA==.Dantè:BAAALgAECgIJAgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAACLgAFFH8LAAICAAUJPhBPMwAvAQACAAUJPhBPMwAvAQAuAAQKfyoAAgIACAkhHLAvAAcCAAIACAkhHLAvAAcCAAAA.Darkstar:BAAALgADCgUJBQAAAA==.Darkwarriorx:BAAALgADCgQJBAAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathroll:BAABLgAECn8oAAITAAkJNhkgEACCAgATAAkJNhkgEACCAgAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJCAABLgAECgcJCAADAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Dontah:BAAALgADCgcJBwABLgAFFAMJCQAUAK0eAA==.Doomward:BAABLgAECn8lAAIVAAcJMBMrfABWAQAVAAcJMBMrfABWAQAAAA==.Dorien:BAACLgAFFH8JAAIUAAMJrR42FQASAQAUAAMJrR42FQASAQAuAAQKfysAAxQACQmoIagEANYCABQACQmoIagEANYCAAIABAk6HdFnAFsBAAAA.',
Dr='Drachilly:BAACLgAFFH8SAAIPAAUJoxa/IQAiAQAPAAUJoxa/IQAiAQAuAAQKfyIABA8ACAkoHv4VACkCAA8ACAmSHf4VACkCABYABgknHj0QANgBABcAAQkPAglAABsAAAAA.Dragnar:BAABLgAECn8jAAICAAkJlwzuPQC3AQACAAkJlwzuPQC3AQAAAA==.Drakbonespur:BAAALgAECggJEwAAAA==.Drhealzgood:BAAALgADCgYJBgAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Ey='Eysia:BAAALgADCgUJCAAAAA==.',
Fa='Faemi:BAAALgAECgEJAQAAAA==.Faewryn:BAABLgAECn8YAAILAAkJlxH8HgD1AQALAAkJlxH8HgD1AQAAAA==.Faeya:BAAALgADCgEJAQABLgADCgUJCAADAAAAAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAACLgAFFH8TAAIQAAUJOxqyFwBEAQAQAAUJOxqyFwBEAQAuAAQKfyAAAhAACAlUIuwSAHoCABAACAlUIuwSAHoCAAAA.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Firstblood:BAAALgAECgYJCQAAAA==.Fishnchimps:BAABLgAFFH8NAAMTAAMJyRf2KADWAAATAAMJyRf2KADWAAAYAAIJ9AU2LwBoAAAAAA==.',
Fr='Frostyfupa:BAAALgADCgIJAgAAAA==.',
Fu='Fupalicious:BAAALgAECgYJCwABLgAECgUJCwADAAAAAA==.Furrburger:BAAALgADCgIJAgAAAA==.',
Ga='Gaiserik:BAABLgAECn8rAAIZAAkJRCFNAwDoAgAZAAkJRCFNAwDoAgAAAA==.Galenda:BAAALgADCgQJBQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgADAAAAAA==.Garlictoast:BAAALgAECgQJBwAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.Genga:BAAALgADCgYJBgAAAA==.',
Go='Goldenorder:BAAALgAECggJCgAAAA==.Gome:BAAALgADCgcJGwABLgAFFAMJDQATAMkXAA==.Goodvbes:BAAALgAECgQJBAAAAA==.',
Gr='Gracile:BAAALgADCgEJAQAAAA==.Gragolf:BAABLgAECn8dAAICAAkJPRP8PADVAQACAAkJPRP8PADVAQAAAA==.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBwAAAA==.',
Gu='Gustabo:BAABLgAECn8bAAIaAAYJGyIRDADWAQAaAAYJGyIRDADWAQAAAA==.',
Ha='Haslin:BAAALgADCgEJAgAAAA==.Havibonespur:BAABLgAECn8XAAMQAAYJXQuURQDUAAAQAAYJXQuURQDUAAAYAAEJyQRhpgAfAAABLgAECggJEwADAAAAAA==.',
He='Healir:BAABLgAECn8TAAMRAAgJZiKLFgABAgARAAgJZiKLFgABAgASAAQJnh/ULAB3AQABLgAFFAIJAgADAAAAAA==.Healmepls:BAAALgADCgYJCgABLgAFFAUJDAAbAHcPAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAABLgAECn8XAAMcAAkJcRYeOwDEAQAcAAkJcRYeOwDEAQAdAAUJ3RXDLgBXAQAAAA==.',
Hi='Hiéi:BAAALgAECgEJAQAAAA==.',
Ho='Holydeath:BAABLgAECn8YAAIeAAcJwB3bEQA6AgAeAAcJwB3bEQA6AgAAAA==.Hotboydragon:BAAALgAFFAIJAgAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwAEACoXAA==.',
Hu='Hunterish:BAAALgADCgEJAQAAAA==.',
Ia='Iadrithe:BAAALgADCgYJBgAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Invisus:BAABLgAECn8WAAIEAAcJZxnhIgDIAQAEAAcJZxnhIgDIAQAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAABLgAECn8nAAIHAAkJCiZfBQB3AwAHAAkJCiZfBQB3AwAAAA==.Jarlan:BAACLgAFFH8ZAAIZAAUJbyK1CgBqAQAZAAUJbyK1CgBqAQAuAAQKfygAAhkACAmRI7sBACMDABkACAmRI7sBACMDAAAA.Jarlhun:BAABLgAECn8dAAIKAAcJjh0BCADsAQAKAAcJjh0BCADsAQABLgAFFAUJGQAZAG8iAA==.',
Je='Jellous:BAACLgAFFH8GAAMcAAIJpQZdegBqAAAcAAIJBgVdegBqAAAdAAEJZwv7DQBOAAAuAAQKfyoAAx0ACQmCF5MTADgCAB0ACAl5GJMTADgCABwACQllFN4zACoCAAAA.Jethereal:BAAALgADCgcJBwABLgAFFAIJBgAcAKUGAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.Justin:BAAALgAECgYJBgAAAA==.',
Ke='Ketharion:BAABLgAECn8rAAMLAAkJ5RWWGQAjAgALAAkJ5RWWGQAjAgAHAAEJiguwgQEsAAAAAA==.Kevamin:BAABLgAECn8WAAIHAAcJ8hEqjAA9AQAHAAcJ8hEqjAA9AQAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAAALgAECggJDwAAAA==.',
Ki='Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kulfa:BAAALgADCgcJCgAAAA==.Kurailos:BAAALgADCggJCAAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAABLgAECn8fAAQUAAkJ+BMRJABtAQAUAAcJIA0RJABtAQAKAAYJ8A2mRgA6AQACAAUJexSZiwAOAQAAAA==.Lake:BAAALgAECgcJDAAAAA==.Laîlyne:BAAALgAECgYJBgABLgAECgkJHwAUAPgTAA==.',
Le='Learned:BAABLgAECn8UAAIVAAgJzAp3fwBPAQAVAAgJzAp3fwBPAQAAAA==.Leo:BAABLgAECn8ZAAIOAAgJSRxiDAAPAgAOAAgJSRxiDAAPAgAAAA==.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAACLgAFFH8IAAIfAAMJWQ+0RAC6AAAfAAMJWQ+0RAC6AAAuAAQKfxUAAh8ACQlPFjo3ALgBAB8ACQlPFjo3ALgBAAAA.Lillymeii:BAAALgAECgEJAQAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8wAAIgAAkJ0B8rBADfAgAgAAkJ0B8rBADfAgAAAA==.',
Lo='Logical:BAAALgAECgYJBgAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgAECgYJBwABLgAFFAUJEAABAEUeAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAFFAUJEwAQADsaAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIhAAcJsxT8PgCEAQAhAAcJsxT8PgCEAQAAAA==.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Manon:BAACLgAFFH8TAAIfAAUJTRkTFQCNAQAfAAUJTRkTFQCNAQAuAAQKfx0AAx8ACAnPFhEtANYBAB8ACAnPFhEtANYBABsAAQm+B4KiACUAAAAA.',
Mc='Mcchungus:BAABLgAECn8XAAMCAAcJxxZMXwBvAQACAAcJlRVMXwBvAQAUAAUJgBL8MQALAQAAAA==.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAABLgAECn8ZAAMMAAcJ4gXKwADqAAAMAAcJ4gXKwADqAAAiAAIJ3AFqGgBEAAAAAA==.Meowmixx:BAAALgAECgcJAwAAAA==.',
Mi='Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAACLgAFFH8SAAIGAAUJohGVAwBCAQAGAAUJohGVAwBCAQAuAAQKfz8AAgYACQkiHo0CAIsCAAYACQkiHo0CAIsCAAAA.',
Mk='Mk:BAEALgAECgQJCQABLgAECggJPQAYAGsjAA==.',
Mo='Mooage:BAACLgAFFH8GAAIMAAIJYiDBMwDLAAAMAAIJYiDBMwDLAAAuAAQKfzMAAgwACQmcJBcMAGQDAAwACQmcJBcMAGQDAAAA.Morewyn:BAABLgAECn8nAAICAAkJVBKcMwD3AQACAAkJVBKcMwD3AQAAAA==.Mozoh:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Na='Nalock:BAAALgAECgUJBQAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAABLgAECn8hAAQYAAgJkxrwEAApAgAYAAgJkxrwEAApAgATAAQJLBElRwC+AAAQAAUJswbFVgCcAAABLgAFFAMJCAAZABYXAA==.Nidhogg:BAAALgADCgcJBwABLgAECgkJIQAfANcaAA==.Nisara:BAABLgAECn8YAAIBAAkJIAkyWQCGAQABAAkJIAkyWQCGAQAAAA==.',
No='Noellie:BAAALgAFFAEJAgAAAA==.Noobdestroya:BAAALgAECgQJDwAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.Oldicy:BAAALgAECgQJBAAAAA==.',
Om='Omantul:BAABLgAECn8hAAMfAAkJ1xqGIgAQAgAfAAgJDRqGIgAQAgAbAAYJUBnrSQDxAAAAAA==.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgADCgYJCwABLgAFFAUJEgANALkQAA==.',
Pa='Painfull:BAABLgAECn8jAAIcAAgJpB1ALAABAgAcAAgJpB1ALAABAgAAAA==.Pants:BAAALgAECgEJAQAAAA==.Pantzor:BAAALgADCgEJAQAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.',
Ph='Phakes:BAAALgAECgUJCAAAAA==.Phengzera:BAABLgAECn8WAAIMAAcJMBX3dADoAQAMAAcJMBX3dADoAQAAAA==.Phizz:BAABLgAFFH8JAAIcAAQJKxNAPAAXAQAcAAQJKxNAPAAXAQAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAUJDgAcACARAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDgADAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAABLgAECn8xAAIjAAkJ+CR/AABRAwAjAAkJ+CR/AABRAwAAAA==.Pumpkinspice:BAAALgADCgYJCQAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDgAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECggJEwADAAAAAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwABLgAFFAQJBgABAMAHAA==.',
Ro='Rotdaddy:BAABLgAECn8aAAINAAgJ4BGHLQCVAQANAAgJ4BGHLQCVAQAAAA==.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAABLgAECn8jAAMhAAkJsgdkWwBAAQAhAAkJsgdkWwBAAQAIAAgJ3AgfLADYAAAAAA==.',
Sa='Saintrandy:BAAALgADCgMJAwAAAA==.Saphiel:BAAALgAECgEJAQAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shaviji:BAAALgAECgcJBwAAAA==.Shinra:BAAALgADCgEJAQAAAA==.Shore:BAABLgAECn8eAAMUAAkJ8xtQCwBgAgAUAAkJ8xtQCwBgAgAKAAYJQRJ1EgAfAQAAAA==.Shrekw:BAAALgAECgcJEwAAAA==.Shuralya:BAACLgAFFH8UAAMHAAQJfxuUJwBKAQAHAAQJfxuUJwBKAQALAAMJURIQKwC5AAAuAAQKf0MAAwcACQkhJCAFAD0DAAcACQkhJCAFAD0DAAsACQk9GH0gABcCAAAA.',
Si='Silverhorn:BAABLgAECn8UAAIPAAgJ0A7sLABrAQAPAAgJ0A7sLABrAQAAAA==.Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8fAAMkAAkJCQ5uGgB+AQAkAAkJCQ5uGgB+AQAVAAEJMgHwOwEbAAAAAA==.Souliel:BAAALgAECgEJAQAAAA==.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAABLgAECn8UAAMgAAcJpxyKCwDeAQAgAAcJpxyKCwDeAQAfAAQJsAVNfwCWAAAAAA==.Stradynia:BAAALgAECggJEAAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.Stócky:BAAALgAECgcJEwAAAA==.',
Su='Sui:BAAALgADCgUJCAAAAA==.Survas:BAACLgAFFH8LAAINAAUJZA4TGQAwAQANAAUJZA4TGQAwAQAuAAQKfx8AAg0ACAmqGfocABcCAA0ACAmqGfocABcCAAAA.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgYJDAAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgYJEAABLgAECgcJDQADAAAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgAFFAIJAgABLgAFFAMJDQATAMkXAA==.Tawna:BAAALgAECgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8VAAQPAAgJuRZGKAB7AQAPAAcJSxVGKAB7AQAXAAYJmhTVJwA1AQAWAAEJOQjJQAAvAAAAAA==.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgAECgQJBQABLgAECgcJDQADAAAAAA==.',
To='Toospooky:BAAALgAECgYJDgAAAA==.Tovlacar:BAAALgAECgUJBgABLgAECgkJMAARAO0PAA==.Toyboy:BAAALgAECgQJBAAAAA==.',
Tr='Triage:BAABLgAECn8VAAQiAAgJjhxsBAAFAgAiAAUJCSRsBAAFAgAMAAUJOhW6ywDYAAAlAAEJTRayDwA8AAAAAA==.Trolladin:BAAALgAECgEJAgAAAA==.Tronarn:BAAALgAECgcJDQAAAA==.',
Ty='Tyrias:BAAALgAECggJAwAAAA==.',
Ug='Ugin:BAACLgAFFH8IAAMmAAMJegVnEwCxAAAmAAMJbQVnEwCxAAAVAAMJPQNtoACrAAAuAAQKfyoAAyYACQk+F2EIANkBACYACQkXFmEIANkBABUACAnsEFp4AF4BAAAA.',
Um='Umaydie:BAAALgAECgIJAwAAAA==.Umbrasyl:BAAALgAECgUJCgAAAA==.',
Un='Unclecharlie:BAAALgAECgUJDAABLgAFFAQJCgAmALsbAA==.Unholylukers:BAAALgAECgIJAwAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAACLgAFFH8FAAIgAAIJ9x1uDADAAAAgAAIJ9x1uDADAAAAuAAQKfzMAAiAACQnmIckCANUCACAACQnmIckCANUCAAAA.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgYJDAADAAAAAA==.Venitaurus:BAAALgAECgEJAQAAAA==.Veon:BAAALgADCgYJBgAAAA==.Verlehn:BAAALgADCgcJBgAAAA==.',
Vo='Voidomo:BAAALgAFFAIJAwAAAA==.Vonbearback:BAAALgAECgEJAgAAAA==.',
Wa='Walden:BAABLgAECn8XAAIIAAcJJhZJGwBOAQAIAAcJJhZJGwBOAQAAAA==.Waterlance:BAAALgAECgEJBAAAAA==.',
We='Weeniefuyu:BAAALgAECgMJBAAAAA==.',
Wi='Wildfupa:BAAALgAECgQJBAAAAA==.Wisecraic:BAAALgAECgUJBQAAAA==.Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8SAAINAAUJuRCPFgA/AQANAAUJuRCPFgA/AQAuAAQKfycAAg0ACQlIHbUGACQDAA0ACQlIHbUGACQDAAAA.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAAALgAECggJEgAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgAECgIJAgAAAA==.',
Za='Zabaniya:BAAALgAECgEJAQAAAA==.Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAABLgAECn8VAAIiAAcJWBSCCQBRAQAiAAcJWBSCCQBRAQAAAA==.Zaida:BAAALgADCgUJBQABLgAECgIJAgADAAAAAA==.',
Ze='Zeale:BAACLgAFFH8GAAIBAAQJwAc3VwACAQABAAQJwAc3VwACAQAuAAQKfy0AAgEACQmmGLMdAGQCAAEACQmmGLMdAGQCAAAA.Zenedict:BAABLgAECn8WAAMfAAkJJBr7FgB5AgAfAAkJJBr7FgB5AgAbAAIJygnVewBbAAAAAA==.',
Zh='Zharsha:BAAALgADCgkJCQAAAA==.',
Zu='Zulubonespur:BAAALgAECgEJAQABLgAECggJEwADAAAAAA==.',
['Áç']='Áçe:BAAALgADCgMJAwAAAA==.',
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
