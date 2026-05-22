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

local lookup = {'Mage-Frost','Mage-Arcane','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Druid-Restoration','Mage-Fire','DemonHunter-Devourer','Druid-Balance','Unknown-Unknown','Hunter-BeastMastery','DemonHunter-Havoc','DeathKnight-Blood','DemonHunter-Vengeance','Priest-Discipline','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Feral','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Paladin-Protection','Paladin-Holy','Hunter-Survival','Rogue-Subtlety','Warrior-Fury','DeathKnight-Frost','Warlock-Affliction',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaletaa:BAAALgADCgUJBQABLgAFFAMJCwABANMXAA==.',
Al='Alalange:BAAALgADCgQJBAAAAA==.Alendrael:BAAALgADCgEJAQAAAA==.Allice:BAABLgAECn8aAAMCAAcJ5BtfAwA8AgACAAcJkBtfAwA8AgABAAQJoQyO0gCmAAAAAA==.Alterion:BAAALgAECgMJBAAAAA==.Altimusprime:BAAALgAECgkJEQAAAA==.',
An='Antitww:BAAALgADCgkJCQAAAA==.Anxious:BAAALgADCgYJCgAAAA==.',
Au='Augnyxia:BAABLgAECn8sAAQDAAcJnxOuJACYAQADAAcJuxGuJACYAQAEAAQJIASqIwCCAAAFAAQJ8Q41FQBvAAAAAA==.Augtism:BAABLgAECn8hAAMGAAgJsSDtJwByAgAGAAgJsSDtJwByAgAHAAEJAADXXQBVAAAAAA==.',
Av='Avengedfoldz:BAAALgAECgMJBAAAAA==.Avengedmunk:BAAALgADCgUJBQAAAA==.Avengedx:BAAALgAECgMJBAAAAA==.Avengeseven:BAAALgADCgYJBgAAAA==.',
Ay='Aylaa:BAAALgADCgMJAwAAAA==.',
Ba='Balsamicvinn:BAAALgAECgMJAwAAAA==.Bamfp:BAAALgAECgEJAgAAAA==.Bandobras:BAAALgAECgUJCgAAAA==.Bangtwinkdh:BAAALgAFFAMJAwABLgAFFAgJHQAFACAgAA==.',
Be='Beefquake:BAAALgAECgcJCwAAAA==.Belfdelphine:BAAALgAECgYJCwAAAA==.Bersh:BAABLgAECn8rAAQIAAkJEh1NBwB4AgAIAAkJBhpNBwB4AgAJAAYJuhcaLQA1AQAKAAEJAQiMngAyAAAAAA==.',
Bi='Bigstankyy:BAAALgADCgQJCAAAAA==.',
Bl='Blarn:BAAALgAECgQJBAAAAA==.Bloodjury:BAABLgAECn8aAAILAAcJVhq1TwCPAQALAAcJVhq1TwCPAQAAAA==.Bloom:BAAALgADCgYJBgAAAA==.Blossom:BAABLgAECn8UAAIMAAgJpxgzIAD/AQAMAAgJpxgzIAD/AQAAAA==.Bluespirit:BAAALgADCgEJAQAAAA==.',
Bo='Boonktown:BAABLgAECn8iAAMNAAkJpAn5BAB9AQANAAcJuQn5BAB9AQABAAgJdgkHagBoAQAAAA==.Booschlock:BAAALgAECgMJAwAAAA==.',
Br='Brambles:BAAALgAECgYJDgAAAA==.Bruceleela:BAAALgADCggJCAABLgAECgcJGwAOANkUAA==.Brunarr:BAAALgAECgQJEQAAAA==.',
Bu='Bushetti:BAABLgAECn8dAAMMAAgJCRXhOgBhAQAMAAgJCRXhOgBhAQAPAAMJmxgjTQB/AAABLgAFFAIJAwAQAAAAAA==.',
Ca='Candlemass:BAAALgAECgQJBQAAAA==.Canelor:BAAALgADCgEJAQAAAA==.Casperface:BAABLgAECn8dAAMJAAkJYBElJQDoAQAJAAkJYBElJQDoAQAKAAYJDxWhOwBfAQAAAA==.Catawampus:BAAALgADCgQJBAAAAA==.Caylo:BAAALgAECgUJCAAAAA==.Cazisham:BAABLgAECn8VAAIIAAcJIQQpFwDRAAAIAAcJIQQpFwDRAAAAAA==.',
Ce='Cevianne:BAABLgAECn8jAAIRAAgJjRMsOADNAQARAAgJjRMsOADNAQAAAA==.',
Ch='Chama:BAAALgADCgEJAQAAAA==.Chaoticsaint:BAABLgAECn8XAAISAAgJEBG8HgAbAQASAAgJEBG8HgAbAQAAAA==.Chronoblade:BAAALgAECgMJBAAAAA==.',
Cl='Claros:BAAALgAECgEJAgAAAA==.',
Co='Coal:BAABLgAECn8mAAIOAAgJDCPMDgCNAgAOAAgJDCPMDgCNAgAAAA==.Coalesce:BAAALgADCgQJBAABLgAECggJJgAOAAwjAA==.Coltonater:BAABLgAECn87AAIBAAgJZR8bHwBnAgABAAgJZR8bHwBnAgAAAA==.Corlieb:BAAALgAECgQJBAAAAA==.',
Cu='Cuh:BAAALgAECgcJBwAAAA==.Curlyfrys:BAAALgADCgQJBAAAAA==.',
['Cá']='Cáséy:BAACLgAFFH8HAAIBAAMJehRqUAAFAQABAAMJehRqUAAFAQAuAAQKfxkAAgEACAkXGmM8AIYCAAEACAkXGmM8AIYCAAAA.',
['Cä']='Cäsey:BAAALgAECgQJBAABLgAFFAMJBwABAHoUAA==.',
Da='Dampening:BAAALgAECgMJAwAAAA==.Danbi:BAABLgAECn8uAAQDAAkJ9hODFADsAQADAAkJ9hODFADsAQAEAAgJpRacCgDoAQAFAAQJtg9CEQCuAAAAAA==.',
De='Deathdylan:BAACLgAFFH8FAAITAAIJ0g19HgB6AAATAAIJ0g19HgB6AAAuAAQKfyQAAhMACAnXHKELAP8BABMACAnXHKELAP8BAAAA.Deathra:BAAALgADCgYJBgAAAA==.Deathseer:BAABLgAECn8bAAIOAAcJ2RSqUABDAQAOAAcJ2RSqUABDAQAAAA==.Deathshaq:BAAALgADCggJGQAAAA==.Delice:BAAALgAECgEJAQAAAA==.Demi:BAAALgADCgYJBgAAAA==.Demítríus:BAAALgADCgYJDQAAAA==.Dethh:BAAALgADCgYJBgAAAA==.Dethpally:BAAALgADCgYJBgAAAA==.',
Do='Dourwolf:BAAALgADCgUJBAAAAA==.',
Dr='Dragman:BAAALgAECgUJBQAAAA==.Dragonlord:BAAALgAECgYJBgAAAA==.Draugr:BAAALgADCgUJBQAAAA==.Dravyn:BAABLgAECn8iAAIBAAgJLAs1agBoAQABAAgJLAs1agBoAQAAAA==.Drfiredumper:BAABLgAECn8iAAIBAAgJmhxNNQCeAgABAAgJmhxNNQCeAgAAAA==.Druqz:BAACLgAFFH8FAAIBAAMJRQMAZwC/AAABAAMJRQMAZwC/AAAuAAQKfxkAAgEACAmdCsN1AE8BAAEACAmdCsN1AE8BAAAA.Drævn:BAABLgAECn8hAAMBAAYJyxHahQAwAQABAAYJwBHahQAwAQANAAMJYw/wBwCtAAAAAA==.',
Du='Ducky:BAAALgADCgEJAQAAAA==.Dum:BAACLgAFFH8WAAMOAAUJnCCFFwByAQAOAAUJnCCFFwByAQAUAAIJQgtQBwB4AAAuAAQKfyUAAg4ACAmlIhoOAJUCAA4ACAmlIhoOAJUCAAAA.',
Dw='Dwimbear:BAAALgADCgEJAQAAAA==.Dwimhoof:BAAALgADCgcJCQAAAA==.',
Ed='Ediconegoen:BAAALgAECgEJAgAAAA==.',
Ei='Eiir:BAAALgADCgQJAwAAAA==.',
El='Eldin:BAABLgAECn8ZAAIVAAgJ6R77DwA/AgAVAAgJ6R77DwA/AgAAAA==.Elunadorei:BAAALgAECgMJBAAAAA==.',
Em='Emancipation:BAAALgAECgYJDgAAAA==.',
En='Enchantress:BAABLgAECn8hAAMBAAkJ0gt2TQCwAQABAAkJ0gt2TQCwAQACAAIJOgZTGQBNAAAAAA==.Endofdays:BAAALgAECggJDQAAAA==.Enro:BAABLgAECn8qAAMSAAgJ4hgFEgBLAgASAAgJ4hgFEgBLAgAOAAQJqgd+tQCdAAAAAA==.',
Er='Erovia:BAABLgAECn8fAAIRAAkJVwmPUgBQAQARAAkJVwmPUgBQAQAAAA==.',
Es='Esclipse:BAAALgAECgcJCAAAAA==.',
Et='Etc:BAAALgADCgIJAgAAAA==.',
Fa='Farruq:BAAALgAECgMJAwAAAA==.',
Fe='Felony:BAABLgAECn8wAAISAAgJaCSqAwDQAgASAAgJaCSqAwDQAgAAAA==.Feyri:BAAALgADCgMJAwAAAA==.',
Fl='Flavah:BAABLgAECn8WAAIPAAgJMB2YHAAdAgAPAAgJMB2YHAAdAgAAAA==.Flavahflav:BAAALgAECgYJCgAAAA==.Floormatt:BAABLgAECn8qAAMWAAkJKRO4VwDqAQAWAAkJKRO4VwDqAQATAAcJDQRIKgCwAAAAAA==.Flower:BAAALgAECgcJEQAAAA==.',
Fo='Foodex:BAAALgAECgcJEQAAAA==.Fourleaf:BAABLgAECn8qAAIXAAgJVxufCQCNAQAXAAgJVxufCQCNAQAAAA==.',
Fr='Frydayx:BAAALgAECgMJAwAAAA==.',
Fu='Furral:BAABLgAECn8VAAIYAAgJcBsVBgArAgAYAAgJcBsVBgArAgAAAA==.',
Ga='Gaeth:BAABLgAECn8jAAIMAAkJUBAIQgCZAQAMAAkJUBAIQgCZAQAAAA==.',
Gh='Gheal:BAAALgAECgUJBQAAAA==.',
Gl='Gleg:BAAALgAFFAIJAwAAAA==.',
Go='Goopdawg:BAAALgAECgQJDAAAAA==.Goregon:BAAALgAECgYJBwAAAA==.',
Gr='Grimthebrave:BAAALgAECgEJAQAAAA==.Grimthecruel:BAABLgAECn8UAAIOAAYJmhjFUwA6AQAOAAYJmhjFUwA6AQAAAA==.Grimvess:BAAALgAECggJCQAAAA==.Grungle:BAAALgADCgIJAgAAAA==.',
Ha='Hamburgler:BAAALgADCgYJBgABLgAECgkJIAARAKchAA==.Handlebar:BAAALgAECgEJAQABLgAECgcJGwAOANkUAA==.Hannsollo:BAAALgADCgEJAQAAAA==.',
He='Heavenfall:BAAALgADCgMJAwAAAA==.Hellomon:BAAALgAECgMJBAABLgAECgUJCgAQAAAAAA==.Hellspawn:BAAALgADCgUJBQAAAA==.',
Ho='Holycowherd:BAABLgAECn8dAAILAAgJLhF8VgB+AQALAAgJLhF8VgB+AQAAAA==.Holycrem:BAAALgADCgEJAQAAAA==.',
Hy='Hyournmaru:BAAALgAECgYJBAAAAA==.',
['Hâ']='Hâmburger:BAAALgADCgQJAwAAAA==.',
Ia='Iamapally:BAAALgAECgEJAQAAAA==.',
Il='Ilkkarid:BAAALgAECgUJBQAAAA==.',
In='Incarcerated:BAAALgADCgQJBAAAAA==.Infêstus:BAAALgAECgQJBAAAAA==.',
Ir='Iridessa:BAABLgAECn8VAAIZAAkJKARtPADKAAAZAAkJKARtPADKAAAAAA==.',
Is='Ishpoo:BAABLgAECn8kAAILAAkJuAxGSgCfAQALAAkJuAxGSgCfAQAAAA==.',
Ja='Jaellen:BAAALgAECgQJBgABLgAECggJIgABAJocAA==.Janasong:BAAALgAECgMJBAAAAA==.',
Je='Jecht:BAAALgADCgEJAQAAAA==.Jelqer:BAABLgAECn8VAAMFAAYJsCCaEgC4AQAFAAYJsCCaEgC4AQADAAUJZBQXMABFAQAAAA==.Jennybunbun:BAAALgADCgcJBwAAAA==.',
Ji='Jimmycooks:BAAALgADCgMJAwAAAA==.',
Jl='Jlaworz:BAABLgAECn8oAAIMAAkJOR3/DQCoAgAMAAkJOR3/DQCoAgAAAA==.',
Jo='Job:BAACLgAFFH8UAAIOAAUJcCLvFQB7AQAOAAUJcCLvFQB7AQAuAAQKfzkAAw4ACQmCJP4CADUDAA4ACQmCJP4CADUDABIABgnFINgjAJ4BAAAA.',
Ju='Juanweasley:BAAALgAECgMJBAAAAA==.Judoriel:BAAALgAECgYJCAAAAA==.Junkyard:BAAALgAECgQJCgAAAA==.',
Ka='Kahsindre:BAABLgAECn8nAAIRAAgJkhwUGABKAgARAAgJkhwUGABKAgAAAA==.Kaimin:BAABLgAECn8pAAIWAAgJUh71KAAWAgAWAAgJUh71KAAWAgAAAA==.Karthas:BAAALgAECgIJBQAAAA==.',
Ke='Kellenved:BAAALgADCgEJAQABLgAECgcJAQAQAAAAAA==.Kennypowers:BAAALgAECgQJCAAAAA==.Kezeshi:BAABLgAECn8xAAMVAAkJdhiwCQCEAgAVAAkJdhiwCQCEAgAZAAMJFAPIVQBqAAAAAA==.',
Kh='Khaidralulz:BAABLgAECn8nAAIKAAkJvBB9LQCmAQAKAAkJvBB9LQCmAQAAAA==.Khonsu:BAAALgAECgcJDAAAAA==.',
Ki='Kiba:BAABLgAECn8fAAMaAAcJBw+OKwBFAQAaAAcJBw+OKwBFAQAbAAMJTQh6TQB+AAAAAA==.Kiliko:BAAALgADCgEJAQAAAA==.Killershammy:BAABLgAECn8WAAIKAAYJ/hqPJwDJAQAKAAYJ/hqPJwDJAQAAAA==.',
Kn='Knubboi:BAAALgADCgcJBwAAAA==.',
Ko='Koy:BAAALgADCgIJAwAAAA==.',
Kr='Kraegen:BAABLgAECn8lAAIcAAkJkQtOEgBJAQAcAAkJkQtOEgBJAQAAAA==.',
Ku='Kushiea:BAAALgADCgIJAgAAAA==.',
Ky='Kyofu:BAABLgAECn82AAMaAAkJEiGOAwA4AwAaAAkJEiGOAwA4AwAbAAMJdA5cRgCaAAAAAA==.',
La='Larethiana:BAABLgAECn8UAAMMAAgJ6RSiTABxAQAMAAcJjBWiTABxAQAPAAYJ9RYANQBqAQAAAA==.',
Le='Leafmochi:BAAALgAECgYJBwAAAA==.Lennytwotoes:BAAALgAECgYJBQAAAA==.Leorick:BAAALgADCgMJAwAAAA==.Lexibelle:BAABLgAECn8UAAMdAAYJXQMfagDSAAAdAAYJXQMfagDSAAALAAQJRQGAIQFbAAAAAA==.',
Li='Lightbright:BAABLgAECn8YAAILAAgJ7ySXBwBaAwALAAgJ7ySXBwBaAwAAAA==.Lilbeefcake:BAAALgAECgMJAwAAAA==.Lildab:BAAALgAECgYJEwAAAA==.Linnasha:BAABLgAECn8rAAIMAAgJwBjAIwDmAQAMAAgJwBjAIwDmAQAAAA==.Litlefoot:BAAALgAECgIJAgAAAA==.',
Lo='Lornzap:BAABLgAFFH8GAAIJAAMJpRYdHQDnAAAJAAMJpRYdHQDnAAAAAA==.Lostwanderer:BAAALgAECggJDQAAAA==.Lot:BAAALgAECgUJBQABLgAFFAUJFAAOAHAiAA==.Lowcowlorie:BAAALgAECgEJAQAAAA==.',
Ma='Machine:BAAALgAECggJEgAAAA==.Magoo:BAAALgAECgIJAgAAAA==.Magtharas:BAAALgAECgYJDAAAAA==.Magzul:BAAALgADCggJCAAAAA==.Maki:BAAALgAECgUJCgAAAA==.Malacoda:BAABLgAECn8mAAISAAgJIBYmGwDoAQASAAgJIBYmGwDoAQAAAA==.Manawurm:BAAALgAECgEJAQAAAA==.Marble:BAAALgAECgUJCAAAAA==.Marshboa:BAAALgAECgUJBQAAAA==.Marymo:BAAALgADCgUJBQAAAA==.',
Me='Meddicare:BAAALgADCgUJBQAAAA==.',
Mi='Mindra:BAABLgAECn8xAAQRAAkJziDTBwDhAgARAAkJziDTBwDhAgAeAAIJPRCiOwB4AAAXAAEJhwy+LQA0AAAAAA==.Minymoney:BAAALgADCgcJBwAAAA==.Mirañda:BAAALgADCgEJAQAAAA==.Miridian:BAAALgAECgUJBgAAAA==.Mitsuri:BAAALgAECggJDgAAAA==.',
Mo='Moatie:BAAALgAECgMJAwAAAA==.Moogician:BAAALgAECgIJBQABLgAECgkJIAARAKchAA==.Moolasses:BAAALgAECgEJAgAAAA==.Moonsïnd:BAABLgAECn8lAAIMAAgJuAxfQwA5AQAMAAgJuAxfQwA5AQAAAA==.Moonwren:BAAALgAECgkJAQAAAA==.Mooradin:BAAALgADCgQJAwAAAA==.Morgrin:BAAALgAECgMJAwAAAA==.Morguen:BAAALgAECgYJCwAAAA==.',
Mu='Mustachiopaw:BAABLgAECn8iAAIfAAgJAhOvFgCQAQAfAAgJAhOvFgCQAQAAAA==.',
My='Mydira:BAAALgAECgkJDAAAAA==.Mysha:BAAALgAECgMJAwAAAA==.',
['Mò']='Mòomòo:BAAALgAECgEJAQAAAA==.',
Na='Nalth:BAAALgAFFAMJAwAAAA==.Nalthexon:BAAALgAECgYJBgABLgAFFAMJAwAQAAAAAA==.Navysis:BAAALgAECgMJAQAAAA==.Nazra:BAAALgAECgEJAQAAAA==.',
Ne='Negativeone:BAAALgADCgYJAgAAAA==.Neverender:BAAALgAECgUJBwAAAA==.Nexxus:BAAALgADCgcJDAAAAA==.Nezan:BAAALgADCgQJBAAAAA==.Nezin:BAAALgADCgUJBQABLgAECgkJGAAdANscAA==.',
Ni='Niavanith:BAAALgAECgYJEQAAAA==.Nights:BAAALgAECgUJBQABLgAECggJEgAQAAAAAA==.Nike:BAAALgAECgEJAQAAAA==.Nitwp:BAACLgAFFH8FAAIFAAIJfg89BgCdAAAFAAIJfg89BgCdAAAuAAQKfywAAgUACAkcInsBAKMCAAUACAkcInsBAKMCAAAA.Nizo:BAABLgAECn8lAAIMAAgJIh1jDwCWAgAMAAgJIh1jDwCWAgAAAA==.',
No='Noblitz:BAAALgAECgcJBwAAAA==.Novastrike:BAABLgAECn8lAAMKAAgJohf6LACpAQAKAAgJohf6LACpAQAJAAgJ3wuGPwDcAAAAAA==.',
Ny='Nyrif:BAABLgAECn8gAAITAAgJfho8DgDQAQATAAgJfho8DgDQAQAAAA==.',
Oj='Ojoon:BAAALgADCgkJFgAAAA==.',
Om='Omnisllash:BAAALgAFFAEJAQAAAA==.',
Or='Orisana:BAACLgAFFH8MAAMeAAQJDxKVCwBGAQAeAAQJDxKVCwBGAQARAAIJNxXFTQCaAAAuAAQKf0MABB4ACQnQHxkEALsCABcACQnAGnkMAOUCAB4ACQnEHRkEALsCABEABQmMGThUAEsBAAAA.',
Pa='Pallamb:BAAALgADCgYJBwAAAA==.Palleberry:BAAALgADCgEJAQAAAA==.Panzerfaust:BAAALgADCgQJBAAAAA==.',
Pe='Penjamin:BAAALgADCgEJAQAAAA==.Petal:BAABLgAFFH8SAAMEAAUJSguwDgBIAQAEAAUJSguwDgBIAQADAAEJlwgDRQBEAAAAAA==.',
Ph='Phyter:BAAALgAECgIJAwAAAA==.',
Pi='Pillin:BAAALgAECgcJDgAAAA==.Pillroller:BAAALgADCgYJBgAAAA==.',
Po='Pock:BAAALgADCgIJAgAAAA==.Poochew:BAABLgAECn8ZAAIgAAcJHB9uHQC0AQAgAAcJHB9uHQC0AQAAAA==.Powerwordmoo:BAAALgADCgYJBwABLgAECgkJIAARAKchAA==.',
Pr='Prilo:BAAALgADCgcJBwAAAA==.Provi:BAAALgAECgcJCwAAAA==.',
Ps='Psyffe:BAAALgAECgUJBgAAAA==.Psyrge:BAAALgAECgQJBAAAAA==.',
Qu='Queue:BAABLgAECn8kAAITAAgJXA5xGQA7AQATAAgJXA5xGQA7AQAAAA==.',
Re='Rebeccayaros:BAAALgAECgQJCAAAAA==.Redle:BAAALgAECggJEAAAAA==.Rendarc:BAAALgADCgIJAgAAAA==.',
Rh='Rhordric:BAECLgAFFH8FAAQeAAMJDwy9GgCkAAAeAAIJjBC9GgCkAAAXAAEJtgcQKgBIAAARAAEJFANuaABAAAAuAAQKfyEAAxcACAlGHAAeADYCABcACAkSFgAeADYCAB4ABwk4G3YSANABAAAA.',
Ro='Rokkitok:BAAALgAECgcJEAAAAA==.Ronindots:BAAALgADCgMJAwAAAA==.',
['Rå']='Råwrshåk:BAABLgAECn8gAAIRAAgJWRupJgD1AQARAAgJWRupJgD1AQAAAA==.',
['Rú']='Rúmi:BAAALgAECgUJCgAAAA==.',
Se='Sea:BAACLgAFFH8VAAIKAAYJextrAwAhAgAKAAYJextrAwAhAgAuAAQKfyEAAgoACQmSIOYBAG4DAAoACQmSIOYBAG4DAAAA.Seniri:BAAALgAECgMJCAAAAA==.',
Sh='Shadowaurora:BAAALgAECgYJCgAAAA==.Shadowrose:BAABLgAECn8nAAMYAAgJQhYpCQDVAQAYAAgJQhYpCQDVAQAMAAIJGQiGlwBMAAAAAA==.Shaide:BAAALgADCgIJAgAAAA==.Shaihulud:BAABLgAECn8XAAIGAAgJvhXTMQDSAQAGAAgJvhXTMQDSAQAAAA==.Shamanic:BAAALgADCgQJBAAAAA==.Shamanistix:BAAALgAECgEJAwAAAA==.Shane:BAAALgADCgcJBwABLgAECgQJBAAQAAAAAA==.Shiemi:BAAALgAECgIJAgAAAA==.Shunsui:BAABLgAECn8iAAMGAAgJ5xgfOgCyAQAGAAgJ5xgfOgCyAQAHAAEJAAAkbwA3AAAAAA==.',
Si='Silchas:BAAALgAECgcJAQAAAA==.Siley:BAABLgAECn8YAAIdAAkJ2xzDFABrAgAdAAkJ2xzDFABrAgAAAA==.Sinnister:BAAALgAECgcJDQAAAA==.Sixsixsicks:BAAALgAECgcJCwAAAA==.Sizurp:BAAALgAECgYJCwAAAA==.',
Sl='Sleepytree:BAAALgAECgcJDwAAAA==.Slugo:BAAALgADCgcJCAAAAA==.',
Sn='Snail:BAAALgAECgMJAwAAAA==.Sneakytrix:BAAALgAFFAEJAQAAAA==.',
So='Sooner:BAACLgAFFH8LAAMhAAMJDh84CADtAAAWAAMJDh/DWQD8AAAhAAMJXRQ4CADtAAAuAAQKfxkAAyEABwl7HfEEAPwBACEABgl0IPEEAPwBABYABQkMHPiCAHwBAAAA.Sorcerix:BAAALgADCgQJBAAAAA==.Soror:BAAALgAECgEJAQAAAA==.',
Sq='Squeaky:BAAALgAECgQJAQAAAA==.',
St='Starar:BAAALgADCgkJDwAAAA==.Stickylicky:BAAALgADCgIJAgAAAA==.',
Su='Suina:BAAALgAECgYJEAAAAA==.Sungodess:BAAALgAECgEJAQAAAA==.',
Sy='Syrupp:BAAALgAECgkJCgAAAA==.',
Ta='Tanya:BAAALgAECgYJCgAAAA==.Tayn:BAAALgADCgEJAgAAAA==.',
Te='Temporary:BAAALgADCgcJFgAAAA==.Tenka:BAAALgADCgMJAwAAAA==.',
Th='Theblackdk:BAAALgADCgQJAwAAAA==.',
Ti='Tisiphone:BAAALgADCgYJBgAAAA==.',
Tr='Triplenine:BAAALgAECgIJAgABLgAFFAcJFwABAOMbAA==.',
Ts='Tsavò:BAAALgADCgQJBgAAAA==.Tsavø:BAAALgAECgMJBAAAAA==.',
Tu='Tucktoo:BAAALgAECgIJAwAAAA==.',
Ty='Tyundric:BAAALgADCgYJCgAAAA==.',
Un='Unholysage:BAABLgAECn8tAAMZAAkJRhbEDgAdAgAZAAkJRhbEDgAdAgAVAAQJRQjtNwDIAAAAAA==.',
Uw='Uwurailme:BAABLgAECn8VAAQHAAcJNg8KMgDwAAAGAAYJcQxriwBCAQAHAAUJHAoKMgDwAAAiAAIJrRN5HQCGAAAAAA==.',
Va='Valenix:BAACLgAFFH8GAAMbAAMJNAg4GAC7AAAbAAMJNAg4GAC7AAAaAAMJXwaxIgCkAAAuAAQKfx4AAxsACAkTEXgsAAoBABsABwlDEHgsAAoBABoABwnQEu8/AOIAAAAA.Valkryi:BAAALgADCgMJAwAAAA==.Vaxis:BAAALgADCgcJDgAAAA==.',
Ve='Velagosa:BAAALgADCgMJAwAAAA==.Venetrazat:BAAALgAECgUJBgAAAA==.',
Vo='Vo:BAAALgAECgYJEgAAAA==.',
Wa='Warder:BAAALgAECgYJEgAAAA==.Warp:BAAALgAECgcJEwAAAA==.',
Wh='Whiteshaq:BAAALgAECgYJCwAAAA==.Whiteypingus:BAAALgADCgYJBgAAAA==.',
Wi='Wincks:BAABLgAECn8VAAMHAAYJIB6tBwCHAQAHAAYJIB6tBwCHAQAGAAQJSxXkfwD8AAAAAA==.',
Xe='Xenosaga:BAAALgAECgIJAgAAAA==.',
Ya='Yaltar:BAAALgAECgUJCgAAAA==.',
Za='Zachthemage:BAABLgAECn8XAAICAAgJ/xBZAwCvAQACAAgJ/xBZAwCvAQAAAA==.Zackman:BAACLgAFFH8FAAIdAAIJ2gizLQBwAAAdAAIJ2gizLQBwAAAuAAQKfy4AAh0ACAkGDCYnAIQBAB0ACAkGDCYnAIQBAAAA.',
Zh='Zhimer:BAAALgADCgIJAgAAAA==.',
Zi='Zinagos:BAAALgAECggJDgABLgAFFAMJBgAbADQIAA==.',
Zo='Zolttor:BAAALgAECgYJCQAAAA==.Zombie:BAAALgAECgQJBQAAAA==.',
Zu='Zulrea:BAAALgAECgIJAwAAAA==.Zuri:BAAALgAECgUJCgAAAA==.Zushi:BAAALgADCgYJCwAAAA==.',
['Ùn']='Ùncleíroh:BAAALgADCgcJBwABLgAECgUJCgAQAAAAAA==.',
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
