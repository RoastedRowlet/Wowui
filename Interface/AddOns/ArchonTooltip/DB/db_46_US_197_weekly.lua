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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Druid-Balance','DemonHunter-Vengeance','Warrior-Fury','Warlock-Demonology','DemonHunter-Devourer','Paladin-Retribution','Hunter-Survival','Druid-Restoration','Evoker-Preservation','Unknown-Unknown','Priest-Shadow','Priest-Holy','Paladin-Holy','Warlock-Destruction','Warlock-Affliction','DeathKnight-Unholy','Evoker-Augmentation','DeathKnight-Blood','Warrior-Protection','Hunter-BeastMastery','Druid-Guardian','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Druid-Feral','Evoker-Devastation','Mage-Fire','Paladin-Protection','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Shaman-Enhancement','Priest-Discipline','Mage-Arcane',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aachooshaman:BAAALgAECgEJAwAAAA==.',
Al='Althenara:BAAALgAECgYJDQAAAA==.',
Am='Amaurine:BAAALgAECgQJBQAAAA==.Amethorn:BAAALgADCgcJBwAAAA==.',
An='Anoramang:BAAALgADCgYJBgAAAA==.Anugunrama:BAAALgAECgUJBgAAAA==.Anzul:BAAALgAECgIJAgAAAA==.',
Aq='Aquarius:BAAALgAECggJDwAAAA==.Aquessaria:BAAALgADCgEJAQAAAA==.Aquå:BAAALgAECgMJCgAAAA==.',
Ar='Aratfu:BAABLgAECn9PAAMBAAkJ+BmpDwCpAgABAAkJ+BmpDwCpAgACAAgJbB/bDQBpAgAAAA==.Araycadia:BAAALgAECgkJBAAAAA==.Arcanita:BAABLgAFFH8JAAIDAAMJDRfXmACaAAADAAMJDRfXmACaAAAAAA==.Arcee:BAAALgAECgcJDQAAAA==.Archivus:BAAALgADCgEJAQAAAA==.Argelmach:BAAALgAECgEJBAAAAA==.Arui:BAABLgAECn8nAAIEAAkJVCB0BwDfAgAEAAkJVCB0BwDfAgAAAA==.',
At='Athania:BAABLgAECn8nAAIFAAkJHxrvBQA+AgAFAAkJHxrvBQA+AgAAAA==.Athornia:BAAALgAECgEJAwAAAA==.',
Av='Avrass:BAAALgAECgEJAQAAAA==.',
Az='Azai:BAAALgADCgcJBwAAAA==.Azrannoth:BAACLgAFFH8IAAIGAAMJEhB2OADRAAAGAAMJEhB2OADRAAAuAAQKfxYAAgYACQlqFdohAOMBAAYACQlqFdohAOMBAAAA.Azurite:BAABLgAECn80AAIHAAkJEhNvTAC1AQAHAAkJEhNvTAC1AQAAAA==.Azzael:BAAALgAECgIJAgAAAA==.',
Ba='Baelthos:BAABLgAECn8kAAIIAAkJSxPmRwCvAQAIAAkJSxPmRwCvAQAAAA==.Balthamøs:BAABLgAECn8vAAIJAAkJ7hHXYgCqAQAJAAkJ7hHXYgCqAQAAAA==.Barebut:BAAALgAECgcJBwAAAA==.Baz:BAABLgAECn8WAAIKAAcJwR7KCABbAgAKAAcJwR7KCABbAgAAAA==.',
Be='Beautiful:BAABLgAFFH8HAAILAAQJrRJBMQDqAAALAAQJrRJBMQDqAAABLgAFFAYJGwAMAPMWAA==.Belak:BAAALgAECgEJAwAAAA==.Belathel:BAAALgAECgEJAQAAAA==.Bermon:BAABLgAECn8WAAILAAgJhwp4UwBCAQALAAgJhwp4UwBCAQABLgAECgkJCgANAAAAAA==.Beyond:BAAALgAECgQJBAAAAA==.',
Bl='Bloodmojo:BAAALgADCgYJCAAAAA==.Bloodtotems:BAAALgAECgcJEQAAAA==.Bloomumz:BAABLgAECn8pAAIEAAgJQx4dAQBVAgAEAAgJQx4dAQBVAgAAAA==.Bluebyyou:BAABLgAECn8sAAMOAAgJigsVNABIAQAOAAgJigsVNABIAQAPAAYJBQZnSgC6AAAAAA==.Blur:BAAALgAECgEJAQABLgAFFAkJRQAIAAgbAA==.',
Bo='Borgor:BAAALgADCggJCAAAAA==.Boseph:BAAALgAECgEJBAAAAA==.Bowlicious:BAAALgADCgYJCgAAAA==.',
Br='Bryman:BAAALgADCgQJBwAAAA==.Brystle:BAABLgAECn8dAAIDAAYJ+gcA3wDcAAADAAYJ+gcA3wDcAAAAAA==.',
Bu='Bustei:BAAALgADCgMJAwAAAA==.',
Ca='Caelion:BAACLgAFFH8IAAIQAAMJzxtAKgDWAAAQAAMJzxtAKgDWAAAuAAQKf1oAAhAACQlkJh8AAP0DABAACQlkJh8AAP0DAAAA.Callaf:BAABLgAECn8eAAMRAAkJWw7XDgBQAQARAAgJzA/XDgBQAQASAAMJ4QKNOABEAAAAAA==.Cannex:BAABLgAECn8oAAITAAkJzB4yHwCNAgATAAkJzB4yHwCNAgAAAA==.Cavell:BAAALgAECgYJCQAAAA==.',
Ce='Celas:BAABLgAECn8WAAILAAUJ6xEKagD2AAALAAUJ6xEKagD2AAAAAA==.Cemmos:BAAALgAECgkJCgAAAA==.',
Ch='Chromex:BAAALgADCgEJAQAAAA==.',
Ci='Ciasteczka:BAAALgADCgUJBQAAAA==.Cindro:BAABLgAECn88AAMMAAkJuQ2WEQCxAQAMAAkJuQ2WEQCxAQAUAAcJ5wKraQCeAAAAAA==.',
Cl='Clam:BAAALgAECgIJAgAAAA==.Clarinets:BAAALgAECgEJAQAAAA==.',
Co='Coheed:BAAALgADCgUJBQAAAA==.Command:BAAALgADCgEJAQAAAA==.Cottonwood:BAAALgADCgYJCwAAAA==.',
Cr='Cryomyst:BAAALgADCgMJAwAAAA==.Crystaleyes:BAAALgADCgYJBgAAAA==.',
De='Deathmage:BAAALgAECgkJDwAAAA==.Deekon:BAABLgAECn8WAAMHAAcJHRitaABsAQAHAAcJHRitaABsAQASAAEJAADtSAAAAAAAAA==.Deni:BAAALgAECgEJAgAAAA==.Derrick:BAAALgADCgEJAQAAAA==.Devourer:BAAALgADCgEJAQAAAA==.Deyvian:BAAALgAECgUJBgAAAA==.Dezrick:BAAALgAECgcJAQAAAA==.',
Do='Dooplikit:BAAALgAECgEJAQAAAA==.Dovathresh:BAAALgAECgkJEAABLgAFFAkJJQAVAJkaAA==.',
Ec='Ectorius:BAAALgAECgEJAwAAAA==.',
Ed='Edwardkenway:BAAALgAECgYJBgAAAA==.',
Eg='Egud:BAABLgAECn9CAAIWAAkJPRsTCQBlAgAWAAkJPRsTCQBlAgAAAA==.',
El='Elegean:BAAALgADCgIJAgAAAA==.Elipsis:BAAALgADCgcJBwAAAA==.Eliri:BAACLgAFFH8XAAIBAAQJth5UJQBDAQABAAQJth5UJQBDAQAuAAQKfxkAAgEACAmlHJ0gAK4BAAEACAmlHJ0gAK4BAAAA.Ellenad:BAABLgAECn8YAAIJAAcJmRbaCABfAQAJAAcJmRbaCABfAQAAAA==.Elsadormu:BAAALgAECgIJAgAAAA==.Elsà:BAAALgAECgYJBgABLgAECgkJVwAXACciAA==.',
Ev='Evayn:BAABLgAECn8nAAIOAAkJugaNOAAzAQAOAAkJugaNOAAzAQAAAA==.Everflux:BAAALgAECgUJBQAAAA==.Everhunt:BAAALgAECggJCQAAAA==.Evo:BAABLgAECn82AAIKAAkJRiAwBADtAgAKAAkJRiAwBADtAgAAAA==.Evolves:BAAALgADCgEJAQAAAA==.',
Ey='Ey:BAABLgAECn8dAAIEAAYJRQUfDQBpAAAEAAYJRQUfDQBpAAAAAA==.',
Fa='Fanguloo:BAAALgADCgYJBgAAAA==.Fantasmo:BAAALgAECgEJAQAAAA==.Fantoria:BAAALgADCgcJBAAAAA==.Farisu:BAACLgAFFH8LAAITAAUJ5BEHKQD2AAATAAUJ5BEHKQD2AAAuAAQKfxYAAxUACQmxGKgeAGEBABMACQlmEgtwAKgBABUABgmzGqgeAGEBAAAA.',
Fe='Feasting:BAAALgADCgEJAQABLgAECggJSwAYAPoeAA==.Fendria:BAAALgAECgQJDAAAAA==.Feval:BAAALgADCgMJAwAAAA==.',
Fj='Fjara:BAAALgAECgEJAQAAAA==.',
Fl='Flavortown:BAABLgAECn8WAAIIAAYJwRWSegArAQAIAAYJwRWSegArAQAAAA==.Fletch:BAAALgADCgMJAwAAAA==.Flick:BAABLgAECn8aAAIXAAcJmQh2oAABAQAXAAcJmQh2oAABAQAAAA==.Fluffyfury:BAAALgAECgQJCQAAAA==.',
Fo='Foggy:BAAALgADCgEJAQAAAA==.',
Fr='Frenchfries:BAAALgAECgEJAQAAAA==.Frontallover:BAAALgAECgEJAQABLgAFFAQJFwABALYeAA==.',
Ga='Gaba:BAABLgAFFH8XAAIBAAYJ1BnbFQDSAQABAAYJ1BnbFQDSAQAAAA==.Galndrel:BAAALgADCgEJAQAAAA==.Garden:BAAALgAECgEJAQABLgAECgMJAwANAAAAAA==.',
Ge='Georish:BAABLgAECn8hAAIZAAkJSw+cHwDBAQAZAAkJSw+cHwDBAQAAAA==.',
Gi='Ginseng:BAABLgAECn81AAIaAAkJFh/pDgDcAgAaAAkJFh/pDgDcAgAAAA==.Girthquake:BAABLgAECn8gAAMaAAkJnR9tBwA5AwAaAAkJnR9tBwA5AwAbAAEJ7BSBFgA/AAAAAA==.',
Gl='Glucian:BAAALgAECgEJAQAAAA==.',
Go='Gorg:BAABLgAECn9CAAMRAAkJ9RX9BgDrAQARAAkJ9RX9BgDrAQASAAIJrQanIgBnAAAAAA==.',
Gr='Grease:BAAALgAECgUJBgAAAA==.',
Gu='Gunkshot:BAACLgAFFH8FAAIKAAMJ9x6/GAAMAQAKAAMJ9x6/GAAMAQAuAAQKfxUAAhwABwnvJU4JAA0DABwABwnvJU4JAA0DAAAA.',
['Gé']='Gémini:BAAALgAECgIJAwAAAA==.',
Ha='Haavoc:BAABLgAECn8rAAIdAAkJmAhpHQAfAQAdAAkJmAhpHQAfAQABLgAFFAIJAgANAAAAAA==.Hagul:BAAALgAECggJCgAAAA==.Handsomeman:BAAALgAECgEJAQAAAA==.Haniki:BAAALgADCgMJAwAAAA==.Harandoll:BAAALgADCgkJCQAAAA==.',
He='Hexadecimal:BAAALgAECgcJEAAAAA==.',
Hi='Hiasinth:BAABLgAECn8WAAMBAAgJZxALIgCjAQABAAgJZxALIgCjAQACAAMJxRZrUwDEAAAAAA==.',
Ho='Holytroller:BAAALgADCgUJBQAAAA==.Hornhub:BAAALgAFFAEJAQAAAA==.',
Ik='Ikhdea:BAAALgADCgUJBQAAAA==.Ikhdin:BAAALgAECgQJBAAAAA==.Ikhlock:BAAALgADCgMJAwAAAA==.Ikthalon:BAAALgADCggJCAAAAA==.',
Im='Imnotafurry:BAAALgAECgYJBwAAAA==.',
In='Invictorian:BAAALgADCgUJBQAAAA==.',
Ir='Irine:BAABLgAECn8bAAITAAkJfgt4hQBZAQATAAkJfgt4hQBZAQAAAA==.Irore:BAAALgAECggJDAAAAA==.',
Is='Isoldé:BAAALgADCgcJBwAAAA==.',
Ja='Jagen:BAAALgADCgYJBgAAAA==.Jamarie:BAAALgADCgYJBgAAAA==.Jarrah:BAABLgAECn8UAAMLAAcJAg2FWwAlAQALAAcJAg2FWwAlAQAEAAIJRwaFnAAlAAAAAA==.Jaxr:BAACLgAFFH8XAAIXAAQJ1gqGJgDQAAAXAAQJ1gqGJgDQAAAuAAQKf0EAAhcACQntGH0iAFoCABcACQntGH0iAFoCAAAA.',
Je='Jenjyandi:BAAALgAECgQJBwABLgAECgkJLQAaACUQAA==.Jetahnna:BAABLgAECn8gAAIXAAkJ+gdJWgCWAQAXAAkJ+gdJWgCWAQAAAA==.',
Jh='Jhata:BAABLgAECn8VAAQMAAYJlAxJIADyAAAMAAYJlAxJIADyAAAUAAYJZRE+WADSAAAeAAEJTgsuPgA2AAAAAA==.',
Jo='Johnnysins:BAAALgAECgUJBwABLgAFFAkJIwAfALsdAA==.Jontarr:BAAALgAECgIJBAAAAA==.',
Ka='Kaelanna:BAAALgAECgcJEAAAAA==.Kajadin:BAABLgAECn8tAAIaAAkJJRBxBwBEAQAaAAkJJRBxBwBEAQAAAA==.Karatedonkey:BAABLgAECn8kAAIdAAkJBA9ZEgCWAQAdAAkJBA9ZEgCWAQAAAA==.Kardai:BAEBLgAECn8oAAIVAAkJ2gqiBQDKAAAVAAkJ2gqiBQDKAAAAAA==.Katamai:BAABLgAECn9AAAIDAAkJMgo0eQCGAQADAAkJMgo0eQCGAQAAAA==.Katreia:BAAALgAECgMJAwABLgAFFAkJJQAVAJkaAA==.Kazimas:BAAALgAECgUJCgAAAA==.',
Ke='Kelisande:BAAALgADCgEJAQAAAA==.',
Kh='Khalcite:BAABLgAECn8oAAIgAAkJ2hMUDwDSAQAgAAkJ2hMUDwDSAQAAAA==.',
Ki='Kik:BAAALgADCgEJAQAAAA==.Kittylock:BAAALgAECgEJAQAAAA==.Kittyshaman:BAABLgAECn87AAMbAAkJmRS4HQD0AQAbAAkJmRS4HQD0AQAaAAIJBQXi2wAsAAAAAA==.',
Ko='Kode:BAAALgAECgYJCQAAAA==.Kozalos:BAAALgADCgUJBQAAAA==.',
Kr='Kristyleigh:BAAALgADCgEJAgAAAA==.',
Ku='Kurono:BAAALgAECggJDQABLgAECgkJHAAJAFMGAA==.Kuross:BAAALgAECgQJBQAAAA==.',
Ky='Kyko:BAAALgAFFAIJAgAAAA==.Kyraltas:BAABLgAECn8cAAIJAAkJUwZSngA6AQAJAAkJUwZSngA6AQAAAA==.Kyrexis:BAAALgAECgEJAQAAAA==.',
La='Laermeluion:BAABLgAECn8aAAIYAAkJPxkLCgBHAgAYAAkJPxkLCgBHAgABLgAFFAkJJQAVAJkaAA==.Larra:BAABLgAECn9XAAIXAAkJJyLdAgBOAgAXAAkJJyLdAgBOAgAAAA==.',
Le='Lefthian:BAAALgAECgQJEAAAAA==.Lemixa:BAAALgADCgEJAQAAAA==.',
Li='Listwhorior:BAABLgAECn87AAIWAAkJTyNKAwADAwAWAAkJTyNKAwADAwAAAA==.Listwindwalk:BAAALgAECgQJBAAAAA==.',
Lo='Logen:BAAALgADCgcJCAAAAA==.Lokita:BAAALgADCgUJBQAAAA==.Loshing:BAAALgAECgIJAgAAAA==.Lothorine:BAAALgAECgEJAQAAAA==.',
Lu='Lunakae:BAABLgAECn8ZAAILAAgJcw+QQgCHAQALAAgJcw+QQgCHAQAAAA==.Lunariella:BAAALgADCgcJBwAAAA==.',
Ly='Lysandrra:BAAALgAECgMJBAAAAA==.',
Ma='Madeline:BAAALgAECgYJCQAAAA==.Malafar:BAAALgAFFAIJBAAAAA==.Malfuriion:BAAALgAECgUJBwAAAA==.Maranwae:BAABLgAECn8+AAMaAAkJkCB4CAApAwAaAAkJkCB4CAApAwAbAAEJHhtvkgBOAAAAAA==.Mastakwaa:BAAALgAECgEJAQAAAA==.Maybemo:BAAALgAECggJCgAAAA==.Maylata:BAAALgAECgYJBgAAAA==.',
Me='Mebumsir:BAAALgADCgUJBgAAAA==.Melokoi:BAABLgAECn83AAMWAAkJSiNGAwAEAwAWAAkJSiNGAwAEAwAhAAUJ4gSTKwCYAAAAAA==.Merlose:BAABLgAECn84AAIgAAkJvhqhBwBiAgAgAAkJvhqhBwBiAgAAAA==.',
Mi='Minidrake:BAABLgAECn8ZAAMMAAgJ3wxKGABNAQAMAAgJ3wxKGABNAQAeAAMJQwVKMwB7AAAAAA==.',
Mo='Moana:BAAALgAFFAEJAQABLgAFFAUJEAAOAD4hAA==.Mogrun:BAABLgAECn8WAAMRAAcJShlpFwCOAQAHAAYJJRqVWAC+AQARAAYJlRVpFwCOAQAAAA==.Monahci:BAAALgADCgcJEwAAAA==.Monocho:BAAALgAECgEJAQAAAA==.Monrroe:BAABLgAECn8WAAMgAAYJSBLbIQAGAQAgAAYJSBLbIQAGAQAQAAYJ3gvdYgCqAAAAAA==.Mooasaurus:BAAALgAFFAIJAgAAAA==.Moonfaith:BAAALgAECgIJAgABLgAFFAQJFwALAHsPAA==.Moonveil:BAAALgAECggJDQABLgAFFAQJFwALAHsPAA==.Moosader:BAAALgAECgEJAQABLgAECgQJCwANAAAAAA==.Moshamie:BAABLgAECn8tAAIbAAkJxghuQAAyAQAbAAkJxghuQAAyAQAAAA==.',
Na='Naeryns:BAAALgAECgUJCQAAAA==.Naleana:BAAALgAECgQJCwAAAA==.Narzwaz:BAABLgAECn8rAAICAAkJpR/gBwDKAgACAAkJpR/gBwDKAgAAAA==.Natallia:BAAALgADCgUJBQABLgAECgkJVwAXACciAA==.',
Ne='Nehemiia:BAAALgADCgMJAwAAAA==.Neytri:BAABLgAECn8/AAIXAAkJpRTNMwANAgAXAAkJpRTNMwANAgAAAA==.',
Ni='Nivale:BAABLgAECn8WAAIDAAYJWht0jABeAQADAAYJWht0jABeAQAAAA==.',
No='Noc:BAAALgADCgIJAgAAAA==.Noel:BAACLgAFFH8SAAIDAAkJCw36HwACAgADAAkJCw36HwACAgAuAAQKfyAAAgMACAmyGZJYAC8CAAMACAmyGZJYAC8CAAAA.Nosotras:BAABLgAECn8oAAIHAAkJXxBeSgC7AQAHAAkJXxBeSgC7AQAAAA==.Noxicous:BAAALgAECgYJEQAAAA==.',
Nz='Nzoth:BAAALgAFFAMJAwAAAA==.',
Ol='Olitas:BAAALgAFFAEJAQAAAA==.',
Pa='Pahudesh:BAAALgADCgUJBQABLgAECgkJKAABAPwgAA==.Patches:BAABLgAECn8dAAMiAAkJ6hGwFwDdAQAiAAkJ6hGwFwDdAQAjAAEJEgT4LAAlAAAAAA==.',
Pe='Pelonia:BAAALgAECgYJBQAAAA==.Perse:BAAALgAECgQJBQAAAA==.',
Ph='Phaera:BAAALgAECgIJAgABLgAECgYJFQAMAJQMAA==.Phau:BAABLgAECn8oAAIBAAkJ/CCKBgA6AwABAAkJ/CCKBgA6AwAAAA==.',
Pi='Pinklemonade:BAAALgAECgQJCgAAAA==.',
Pl='Plagos:BAAALgADCgcJEAAAAA==.Playmate:BAACLgAFFH8XAAILAAQJew/7MgDiAAALAAQJew/7MgDiAAAuAAQKfyMAAgsACAlXHwscAGYCAAsACAlXHwscAGYCAAAA.',
Po='Pointbreak:BAAALgADCgQJBAAAAA==.Potatoe:BAAALgADCgQJBAAAAA==.',
Pr='Prahumn:BAAALgAECgQJDwAAAA==.Prozac:BAAALgADCgMJAwAAAA==.Prïnçess:BAAALgAECgUJDAAAAA==.',
Pu='Purplicious:BAAALgAECgUJBQAAAA==.',
Py='Pymilocs:BAABLgAECn86AAIbAAkJPCKmBgDyAgAbAAkJPCKmBgDyAgAAAA==.',
Qu='Qualison:BAAALgAECgYJEgAAAA==.Quint:BAAALgAECgMJAwAAAA==.Quleiry:BAAALgAFFAMJAwAAAA==.',
Ra='Rabare:BAAALgAECgcJDgAAAA==.Rabore:BAAALgAECgQJBAAAAA==.Rahumn:BAACLgAFFH8KAAIGAAMJyAhMPgCxAAAGAAMJyAhMPgCxAAAuAAQKfycAAgYACAn5FYUmAMQBAAYACAn5FYUmAMQBAAAA.Raktal:BAAALgAECgMJAgAAAA==.Ralee:BAABLgAECn9FAAITAAkJTRTmBgBuAQATAAkJTRTmBgBuAQAAAA==.Ranebowz:BAACLgAFFH8GAAIJAAMJQQaBngCAAAAJAAMJQQaBngCAAAAuAAQKfy4AAgkACQl+H/0hAH4CAAkACQl+H/0hAH4CAAAA.Ravenmohr:BAAALgADCgUJBQAAAA==.Ravinia:BAAALgAECgEJAQAAAA==.Razleaf:BAAALgAECgQJBQABLgAECgkJCgANAAAAAA==.',
Re='Rennai:BAAALgAECgcJDAAAAA==.',
Rh='Rhebeqa:BAAALgAECgUJBAABLgAECggJFgADAPAFAA==.',
Ri='Richter:BAAALgADCgkJIAAAAA==.Rin:BAEBLgAECn82AAIBAAkJbiIDBQBcAwABAAkJbiIDBQBcAwAAAA==.Rist:BAABLgAECn8gAAIWAAkJAxDnGgBhAQAWAAkJAxDnGgBhAQAAAA==.',
Ro='Rogelink:BAAALgAECggJDgAAAA==.Rosan:BAAALgAFFAIJBAAAAA==.Royakan:BAAALgAECgEJBAAAAA==.',
Sa='Samoset:BAABLgAECn8nAAIPAAkJDBS0HADhAQAPAAkJDBS0HADhAQAAAA==.',
Sc='Scarhide:BAABLgAECn8cAAQhAAkJkhIuGQCRAQAhAAkJuQ4uGQCRAQAWAAgJqRDXGQBsAQAGAAMJjhD6CgC3AAAAAA==.',
Se='Setsuna:BAABLgAECn8eAAMeAAkJESP5BwBoAgAeAAYJBCX5BwBoAgAUAAUJZx5+KwCQAQABLgAECgYJCQANAAAAAA==.',
Sh='Shadaloo:BAABLgAFFH8HAAITAAMJIBC2mwDZAAATAAMJIBC2mwDZAAAAAA==.Shaori:BAAALgADCgkJCQAAAA==.Shava:BAAALgAECgYJBgAAAA==.Sheepstealer:BAABLgAECn8eAAIeAAkJwRMWBwDUAQAeAAkJwRMWBwDUAQAAAA==.Shippo:BAAALgAECgIJAgAAAA==.Shire:BAAALgAECgUJBQAAAA==.Shockisha:BAAALgAECgQJBAAAAA==.Showgirl:BAAALgADCgcJBwABLgAFFAYJGwAMAPMWAA==.',
Si='Silvanthos:BAAALgAECgQJBwAAAA==.Silvers:BAAALgAECgUJCwAAAA==.Silverthorn:BAAALgAECgIJAgAAAA==.',
Sk='Skrom:BAABLgAECn8UAAIkAAkJewr4AQBfAQAkAAkJewr4AQBfAQAAAA==.',
Sl='Sliccie:BAABLgAECn8sAAIHAAgJIBKFXgCEAQAHAAgJIBKFXgCEAQAAAA==.',
Sm='Smashypants:BAAALgADCgIJAgAAAA==.Smitegoat:BAACLgAFFH8QAAMlAAUJCQnxIgA4AQAlAAUJ1wjxIgA4AQAPAAEJ/gxMOQAvAAAuAAQKfygAAw8ACQleHJ8UADkCAA8ACAnzGZ8UADkCACUAAwmFHWhDAPsAAAAA.',
Sn='Sney:BAABLgAECn8sAAIbAAYJgQ56CQC8AAAbAAYJgQ56CQC8AAABLgAECgkJRQATAE0UAA==.',
So='Solaia:BAABLgAECn8YAAIWAAgJ8xRxEgDEAQAWAAgJ8xRxEgDEAQABLgAFFAkJJQAVAJkaAA==.Solar:BAAALgAECgkJAQAAAA==.Solomon:BAAALgAFFAEJAQAAAA==.Sorlzul:BAAALgAECgMJBwAAAA==.Sound:BAAALgAECgIJBQABLgAECgMJAwANAAAAAA==.',
Sp='Specialbarz:BAAALgADCgEJAQAAAA==.',
St='Stellaluna:BAAALgAECgQJBAAAAA==.Stranger:BAAALgAECgcJBwAAAA==.',
Su='Suotokahn:BAAALgADCgQJBAAAAA==.',
Sv='Svanalock:BAAALgADCgcJDwAAAA==.',
Ta='Tad:BAABLgAECn8eAAIXAAkJNQ0iUQCvAQAXAAkJNQ0iUQCvAQAAAA==.Taini:BAAALgADCgYJBgABLgAFFAkJJQAVAJkaAA==.Taiurag:BAAALgAECgUJEwAAAA==.Taken:BAABLgAECn8jAAIDAAkJWwYLmgBFAQADAAkJWwYLmgBFAQAAAA==.Tazra:BAACLgAFFH8PAAIJAAQJfBxLDwA4AQAJAAQJfBxLDwA4AQAuAAQKfzoAAgkACQlsH5YmAGoCAAkACQlsH5YmAGoCAAAA.Tazzy:BAAALgAECgMJAwAAAA==.Tazzyy:BAAALgAECgQJBAAAAA==.',
Te='Terrylabonte:BAAALgAECgcJEgAAAA==.',
Th='Thomaz:BAABLgAECn8pAAIGAAkJIxPuIgDbAQAGAAkJIxPuIgDbAQAAAA==.Thorninii:BAAALgADCgQJBAAAAA==.Thundergoose:BAAALgAECgMJAwAAAA==.',
Ti='Tirel:BAAALgADCgUJBQAAAA==.',
To='Tondri:BAAALgAFFAIJAgAAAA==.Tonkatruck:BAABLgAECn8gAAIJAAkJFhjDNQApAgAJAAkJFhjDNQApAgAAAA==.',
Tt='Ttvnazboo:BAAALgADCgMJBAAAAA==.',
Tu='Tulany:BAABLgAECn8VAAMPAAgJYwjVOgAMAQAlAAYJYwcJMQAYAQAPAAgJCwfVOgAMAQABLgAECgkJCgANAAAAAA==.Tuyenlotus:BAABLgAECn8nAAIkAAkJtxwmCABEAgAkAAkJtxwmCABEAgAAAA==.',
Un='Unholypriest:BAAALgAECgYJCwAAAA==.',
Ut='Utloc:BAAALgAECgYJEwAAAA==.',
Va='Vahnya:BAABLgAECn84AAIbAAkJoRs5DwB9AgAbAAkJoRs5DwB9AgAAAA==.Vardren:BAAALgADCgQJBAAAAA==.',
Ve='Venekor:BAABLgAECn8wAAMUAAkJLQuYMgBqAQAUAAkJ6wqYMgBqAQAeAAEJgwgpJwAvAAAAAA==.Vesia:BAABLgAECn8YAAMPAAYJZRiWMQBGAQAPAAYJZRiWMQBGAQAOAAQJYBPZPwD4AAAAAA==.',
Vi='Viainfinita:BAAALgADCgYJBgAAAA==.Viannaironcl:BAAALgADCgIJAgAAAA==.Vicarrion:BAAALgAECggJDQAAAA==.Viscera:BAAALgADCgMJAwAAAA==.',
Vo='Voidrat:BAABLgAECn8VAAMBAAcJOxs3NwCXAQABAAYJxho3NwCXAQACAAYJMRGvOgAXAQABLgAECgkJTwABAPgZAA==.Voidweaver:BAAALgADCgYJBgAAAA==.',
Vr='Vrat:BAAALgAECgYJCAABLgAECgkJTwABAPgZAA==.',
Vy='Vyndenfox:BAAALgADCgkJCQAAAA==.',
['Ví']='Ví:BAABLgAECn83AAQDAAkJgAuwFgC+AAAmAAUJHAwKDAC+AAADAAkJjgiwFgC+AAAfAAEJAAAoGQAAAAAAAA==.',
Wa='Warfare:BAAALgAFFAIJAgAAAA==.',
Wh='Whistler:BAAALgADCgEJAQAAAA==.Whitezi:BAAALgAECgYJBwAAAA==.',
Wi='Wildpally:BAABLgAECn8XAAIgAAUJYA2hLgCuAAAgAAUJYA2hLgCuAAAAAA==.',
['Wí']='Wíldhide:BAAALgADCgMJAwAAAA==.',
Xo='Xonon:BAAALgAECgYJEAAAAA==.',
Xw='Xweithel:BAAALgAECgQJBwAAAA==.',
Yo='Yourmageisty:BAABLgAECn89AAMDAAkJGRpyPwAeAgADAAkJCxZyPwAeAgAmAAYJzhgKBQCUAQAAAA==.',
Yu='Yulíana:BAAALgAECgYJCgAAAA==.',
Za='Zakýe:BAAALgAECgQJBAAAAA==.Zanot:BAAALgADCgYJBgAAAA==.Zariara:BAAALgADCgUJBQAAAA==.',
Zc='Zcart:BAABLgAECn9CAAMXAAkJeRgFKAA/AgAXAAkJeRgFKAA/AgAcAAEJ4QFKmgAZAAAAAA==.',
Ze='Zelara:BAABLgAFFH8GAAIYAAIJUBGCLgBhAAAYAAIJUBGCLgBhAAAAAA==.Zeluxum:BAAALgAECgYJBQABLgAECgkJKAATAMweAA==.Zertloc:BAABLgAECn9MAAIbAAkJOiJrBAAcAwAbAAkJOiJrBAAcAwAAAA==.',
Zh='Zhaan:BAAALgAECgYJBgAAAA==.',
Zi='Zieda:BAACLgAFFH8VAAIEAAQJGRJBIgAQAQAEAAQJGRJBIgAQAQAuAAQKfyoAAgQACAmHGYUZAAACAAQACAmHGYUZAAACAAAA.Ziti:BAAALgADCgIJAgAAAA==.',
Zo='Zombini:BAAALgAECgQJBAAAAA==.',
Zu='Zubiria:BAAALgADCgcJCwAAAA==.Zulaaj:BAAALgAECgMJAwAAAA==.',
Zy='Zydratie:BAAALgAECgMJAwAAAA==.',
['Év']='Évania:BAAALgADCgYJBgAAAA==.Éver:BAAALgADCgUJBQAAAA==.',
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
