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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Druid-Balance','DemonHunter-Vengeance','DeathKnight-Unholy','Warrior-Fury','Warlock-Demonology','DemonHunter-Devourer','Paladin-Retribution','Hunter-Survival','Druid-Restoration','Evoker-Preservation','Unknown-Unknown','Priest-Shadow','Priest-Holy','Paladin-Holy','Warlock-Destruction','Warlock-Affliction','Evoker-Augmentation','DeathKnight-Blood','Warrior-Protection','Hunter-BeastMastery','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Druid-Feral','Evoker-Devastation','Mage-Fire','Paladin-Protection','Druid-Guardian','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Shaman-Enhancement','Priest-Discipline','Mage-Arcane',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aachooshaman:BAAALgAECgEJAwAAAA==.',
Al='Althenara:BAAALgAECgYJDQAAAA==.',
Am='Amaurine:BAAALgAECgQJBQAAAA==.Amethorn:BAAALgADCgcJBwAAAA==.',
An='Anoramang:BAAALgADCgYJBgAAAA==.Anugunrama:BAAALgAECgUJBgAAAA==.Anzul:BAAALgAECgMJAgAAAA==.',
Aq='Aquarius:BAAALgAECggJDwAAAA==.Aquessaria:BAAALgADCgEJAQAAAA==.Aquå:BAAALgAECgMJCgAAAA==.',
Ar='Aratfu:BAABLgAECn9PAAMBAAkJ+BmpDwCpAgABAAkJ+BmpDwCpAgACAAgJbB/bDQBpAgAAAA==.Araycadia:BAAALgAECgkJBAAAAA==.Arcanita:BAABLgAFFH8KAAIDAAMJDRfXmACaAAADAAMJDRfXmACaAAAAAA==.Arcee:BAAALgAECgcJDQAAAA==.Archivus:BAAALgADCgEJAQAAAA==.Argelmach:BAAALgAECgEJBQAAAA==.Arui:BAABLgAECn8nAAIEAAkJVCB0BwDfAgAEAAkJVCB0BwDfAgAAAA==.',
At='Athania:BAABLgAECn8rAAIFAAkJrhrvBQA+AgAFAAkJrhrvBQA+AgAAAA==.Athornia:BAAALgAECgEJAwAAAA==.',
Av='Avrass:BAAALgAECgEJAQAAAA==.',
Az='Azai:BAAALgADCgcJBwABLgAECgkJGwAGAH4LAA==.Azrannoth:BAACLgAFFH8IAAIHAAMJEhB2OADRAAAHAAMJEhB2OADRAAAuAAQKfxYAAgcACQlqFdohAOMBAAcACQlqFdohAOMBAAAA.Azurite:BAABLgAECn80AAIIAAkJEhNvTAC1AQAIAAkJEhNvTAC1AQAAAA==.Azzael:BAAALgAECgIJAgAAAA==.',
Ba='Baelthos:BAABLgAECn8kAAIJAAkJSxPmRwCvAQAJAAkJSxPmRwCvAQAAAA==.Balthamøs:BAABLgAECn8vAAIKAAkJ7hHXYgCqAQAKAAkJ7hHXYgCqAQAAAA==.Barebut:BAAALgAECgcJBwAAAA==.Baz:BAABLgAECn8WAAILAAcJwR7KCABbAgALAAcJwR7KCABbAgAAAA==.',
Be='Beautiful:BAABLgAFFH8HAAIMAAQJrRJBMQDqAAAMAAQJrRJBMQDqAAABLgAFFAYJHAANAPMWAA==.Belak:BAAALgAECgEJAwAAAA==.Belathel:BAAALgAECgEJAQAAAA==.Bermon:BAABLgAECn8WAAIMAAgJhwp4UwBCAQAMAAgJhwp4UwBCAQABLgAECgkJCgAOAAAAAA==.Beyond:BAAALgAECgQJBwAAAA==.',
Bl='Bloodmojo:BAAALgADCgYJCAAAAA==.Bloodtotems:BAAALgAECgcJEQAAAA==.Bloomumz:BAABLgAECn81AAIEAAgJrSB1AQB/AgAEAAgJrSB1AQB/AgAAAA==.Bluebyyou:BAABLgAECn8tAAMPAAkJSgsVNABIAQAPAAkJSgsVNABIAQAQAAYJBQZnSgC6AAAAAA==.Blur:BAAALgAECgEJAQABLgAFFAkJVQAJAFAcAA==.',
Bo='Borgor:BAAALgADCggJCAAAAA==.Boseph:BAAALgAECgEJBAAAAA==.Bowlicious:BAAALgADCgYJCgAAAA==.',
Br='Bryman:BAAALgADCgQJBwAAAA==.Brystle:BAABLgAECn8dAAIDAAYJ+gcA3wDcAAADAAYJ+gcA3wDcAAAAAA==.',
Bu='Bustei:BAAALgADCgMJAwAAAA==.',
Ca='Caelion:BAACLgAFFH8IAAIRAAMJzxtAKgDWAAARAAMJzxtAKgDWAAAuAAQKf1oAAhEACQlkJh8AAP0DABEACQlkJh8AAP0DAAAA.Callaf:BAABLgAECn8eAAMSAAkJWw7XDgBQAQASAAgJzA/XDgBQAQATAAMJ4QKNOABEAAAAAA==.Cannex:BAABLgAECn8oAAIGAAkJzB4yHwCNAgAGAAkJzB4yHwCNAgAAAA==.Cavell:BAAALgAECgYJCQAAAA==.',
Ce='Celas:BAABLgAECn8WAAIMAAUJ6xEKagD2AAAMAAUJ6xEKagD2AAAAAA==.Celinna:BAAALgAECgQJBAAAAA==.Cemmos:BAAALgAECgkJCgAAAA==.',
Ch='Chromex:BAAALgADCgEJAQAAAA==.',
Ci='Ciasteczka:BAAALgADCgUJBgAAAA==.Cindro:BAABLgAECn88AAMNAAkJuQ2WEQCxAQANAAkJuQ2WEQCxAQAUAAcJ5wKraQCeAAAAAA==.',
Cl='Clam:BAAALgAECgIJAgAAAA==.Clarinets:BAAALgAECgEJAQAAAA==.',
Co='Coheed:BAAALgADCgUJBQAAAA==.Command:BAAALgADCgEJAQAAAA==.Cottonwood:BAAALgADCgYJCwAAAA==.',
Cr='Cryomyst:BAAALgADCgMJAwAAAA==.Crystaleyes:BAAALgADCgYJBgAAAA==.',
De='Deathmage:BAAALgAECgkJDwAAAA==.Deekon:BAABLgAECn8WAAMIAAcJHRitaABsAQAIAAcJHRitaABsAQATAAEJAADtSAAAAAAAAA==.Deni:BAAALgAECgEJAgAAAA==.Derrick:BAAALgADCgEJAQAAAA==.Devourer:BAAALgADCgEJAQAAAA==.Deyvian:BAAALgAECgUJBgAAAA==.Dezrick:BAAALgAECgcJAQAAAA==.',
Do='Dooplikit:BAAALgAECgEJAQAAAA==.Dovathresh:BAAALgAECgkJEAABLgAFFAkJKQAVACgdAA==.',
Ec='Ectorius:BAAALgAECgEJAwAAAA==.',
Ed='Edwardkenway:BAAALgAECgYJBgAAAA==.',
Eg='Egud:BAABLgAECn9OAAIWAAkJPRsTCQBlAgAWAAkJPRsTCQBlAgAAAA==.',
El='Elegean:BAAALgADCgIJAgAAAA==.Elipsis:BAAALgADCgcJBwAAAA==.Eliri:BAACLgAFFH8YAAIBAAQJth5UJQBDAQABAAQJth5UJQBDAQAuAAQKfxkAAgEACAmlHJ0gAK4BAAEACAmlHJ0gAK4BAAAA.Ellenad:BAABLgAECn8bAAIKAAkJsBSaBwDGAQAKAAkJsBSaBwDGAQAAAA==.Elsadormu:BAAALgAECgIJAgAAAA==.Elsà:BAAALgAECgYJBgABLgAECgkJVwAXACciAA==.',
Ev='Evayn:BAABLgAECn8nAAIPAAkJugaNOAAzAQAPAAkJugaNOAAzAQAAAA==.Everflux:BAAALgAECgYJBgAAAA==.Everhunt:BAAALgAECggJCQAAAA==.Evo:BAABLgAECn82AAILAAkJRiAwBADtAgALAAkJRiAwBADtAgAAAA==.Evolves:BAAALgADCgEJAQAAAA==.',
Ey='Ey:BAABLgAECn8dAAIEAAYJRQW1EgBkAAAEAAYJRQW1EgBkAAAAAA==.',
Fa='Fanguloo:BAAALgADCgYJBgAAAA==.Fantasmo:BAAALgAECgEJAQAAAA==.Fantoria:BAAALgADCgcJBAAAAA==.Farisu:BAACLgAFFH8NAAIGAAYJrBSfFwCIAQAGAAYJrBSfFwCIAQAuAAQKfxYAAxUACQmxGKgeAGEBAAYACQlmEgtwAKgBABUABgmzGqgeAGEBAAAA.',
Fe='Feasting:BAAALgADCgEJAQABLgAFFAIJBQAEAIAVAA==.Fendria:BAAALgAECgUJDwAAAA==.Feval:BAAALgADCgMJAwAAAA==.',
Fj='Fjara:BAAALgAECgEJAQAAAA==.',
Fl='Flavortown:BAABLgAECn8WAAIJAAYJwRWSegArAQAJAAYJwRWSegArAQAAAA==.Fletch:BAAALgADCgMJAwAAAA==.Flick:BAABLgAECn8aAAIXAAcJmQh2oAABAQAXAAcJmQh2oAABAQAAAA==.Fluffyfury:BAAALgAECgQJCQAAAA==.',
Fo='Foggy:BAAALgADCgEJAQAAAA==.',
Fr='Frenchfries:BAAALgAECgEJAQAAAA==.Frontallover:BAAALgAECgEJAQABLgAFFAQJGAABALYeAA==.',
Ga='Gaba:BAABLgAFFH8XAAIBAAYJ1BnbFQDSAQABAAYJ1BnbFQDSAQAAAA==.Galndrel:BAAALgADCgEJAQAAAA==.Garden:BAAALgAECgEJAQABLgAECgMJAwAOAAAAAA==.',
Ge='Georish:BAABLgAECn8iAAIYAAkJWxCcHwDBAQAYAAkJWxCcHwDBAQAAAA==.',
Gi='Ginseng:BAABLgAECn83AAIZAAkJRx/pDgDcAgAZAAkJRx/pDgDcAgAAAA==.Girthquake:BAABLgAECn8hAAMZAAkJnR9tBwA5AwAZAAkJnR9tBwA5AwAaAAEJ7BS8HgA+AAAAAA==.',
Gl='Glucian:BAAALgAECgEJAQAAAA==.',
Go='Gorg:BAABLgAECn9GAAMSAAkJZRf9BgDrAQASAAkJZRf9BgDrAQATAAIJrQanIgBnAAAAAA==.',
Gr='Grease:BAAALgAECgUJBgAAAA==.',
Gu='Gunkshot:BAACLgAFFH8FAAILAAMJ9x6/GAAMAQALAAMJ9x6/GAAMAQAuAAQKfxUAAhsABwnvJU4JAA0DABsABwnvJU4JAA0DAAAA.',
['Gé']='Gémini:BAAALgAECgIJAwAAAA==.',
Ha='Haavoc:BAABLgAECn8rAAIcAAkJmAhpHQAfAQAcAAkJmAhpHQAfAQABLgAFFAIJAwAOAAAAAA==.Hagul:BAAALgAECggJCgAAAA==.Handsomeman:BAAALgAECgEJAQAAAA==.Haniki:BAAALgADCgMJAwAAAA==.Harandoll:BAAALgADCgkJCQAAAA==.',
He='Hexadecimal:BAAALgAECgcJEAAAAA==.',
Hi='Hiasinth:BAABLgAECn8WAAMBAAgJZxALIgCjAQABAAgJZxALIgCjAQACAAMJxRZrUwDEAAAAAA==.',
Ho='Holytroller:BAAALgADCgUJBQAAAA==.Hornhub:BAAALgAFFAEJAQAAAA==.',
Ik='Ikhdea:BAAALgADCgUJBQAAAA==.Ikhdin:BAAALgAECgQJBAAAAA==.Ikhlock:BAAALgADCgMJAwAAAA==.Ikthalon:BAAALgADCggJCAAAAA==.',
Im='Imnotafurry:BAAALgAECgYJBwAAAA==.',
In='Invictorian:BAAALgADCgUJBQAAAA==.',
Ir='Irine:BAABLgAECn8bAAIGAAkJfgt4hQBZAQAGAAkJfgt4hQBZAQAAAA==.Irore:BAAALgAECgkJDQAAAA==.',
Is='Isoldé:BAAALgADCgcJBwAAAA==.',
Ja='Jagen:BAAALgADCgYJBgAAAA==.Jamarie:BAAALgADCgYJBgAAAA==.Jarrah:BAABLgAECn8UAAMMAAcJAg2FWwAlAQAMAAcJAg2FWwAlAQAEAAIJRwaFnAAlAAAAAA==.Jaxr:BAACLgAFFH8XAAIXAAQJ1grdMwDCAAAXAAQJ1grdMwDCAAAuAAQKf0EAAhcACQntGH0iAFoCABcACQntGH0iAFoCAAAA.',
Je='Jenjyandi:BAAALgAECgQJBwABLgAECgkJMAAZACUQAA==.Jetahnna:BAABLgAECn8gAAIXAAkJ+gdJWgCWAQAXAAkJ+gdJWgCWAQAAAA==.',
Jh='Jhata:BAABLgAECn8VAAQNAAYJlAxJIADyAAANAAYJlAxJIADyAAAUAAYJZRE+WADSAAAdAAEJTgsuPgA2AAAAAA==.',
Jo='Johnnysins:BAAALgAECgUJBwABLgAFFAkJKwAeABwfAA==.Jontarr:BAAALgAECgIJBAAAAA==.',
Ka='Kaelanna:BAAALgAECgcJEAAAAA==.Kajadin:BAABLgAECn8wAAIZAAkJJRD+CABxAQAZAAkJJRD+CABxAQAAAA==.Karatedonkey:BAABLgAECn8kAAIcAAkJBA9ZEgCWAQAcAAkJBA9ZEgCWAQAAAA==.Kardai:BAEBLgAECn8oAAIVAAkJ2gqjBwDRAAAVAAkJ2gqjBwDRAAAAAA==.Katamai:BAABLgAECn9AAAIDAAkJMgo0eQCGAQADAAkJMgo0eQCGAQAAAA==.Katreia:BAAALgAECgYJCQABLgAFFAkJKQAVACgdAA==.Kazimas:BAAALgAECgYJCwAAAA==.',
Ke='Kelisande:BAAALgADCgEJAQAAAA==.Kerrmieryon:BAAALgADCgEJAQAAAA==.',
Kh='Khalcite:BAABLgAECn8oAAIfAAkJ2hMUDwDSAQAfAAkJ2hMUDwDSAQAAAA==.',
Ki='Kik:BAAALgADCgEJAQAAAA==.Kittylock:BAAALgAECgEJAQAAAA==.Kittyshaman:BAABLgAECn87AAMaAAkJmRS4HQD0AQAaAAkJmRS4HQD0AQAZAAIJBQXi2wAsAAAAAA==.',
Ko='Kode:BAAALgAECgYJCQAAAA==.Kozalos:BAAALgADCgUJBQAAAA==.',
Kr='Kristyleigh:BAAALgADCgEJAgAAAA==.',
Ku='Kurono:BAAALgAECggJDQABLgAECgkJHAAKAFMGAA==.Kuross:BAAALgAECgQJBQAAAA==.',
Ky='Kyko:BAAALgAFFAIJAgAAAA==.Kyraltas:BAABLgAECn8cAAIKAAkJUwZSngA6AQAKAAkJUwZSngA6AQAAAA==.Kyrash:BAAALgADCgEJAQAAAA==.Kyrexis:BAAALgAECgEJAQAAAA==.',
La='Laermeluion:BAABLgAECn8aAAIgAAkJPxkLCgBHAgAgAAkJPxkLCgBHAgABLgAFFAkJKQAVACgdAA==.Larra:BAABLgAECn9XAAIXAAkJJyITEADQAgAXAAkJJyITEADQAgAAAA==.',
Le='Lefthian:BAAALgAECgQJEAAAAA==.Lemixa:BAAALgADCgEJAQAAAA==.',
Li='Listwhorior:BAABLgAECn87AAIWAAkJTyNKAwADAwAWAAkJTyNKAwADAwAAAA==.Listwindwalk:BAAALgAECgQJBAAAAA==.',
Lo='Logen:BAAALgADCgcJCAAAAA==.Lokita:BAAALgADCgUJBQAAAA==.Loshing:BAAALgAECgIJAgAAAA==.Lothorine:BAAALgAECgQJBAAAAA==.',
Lu='Lunakae:BAABLgAECn8ZAAIMAAgJcw+QQgCHAQAMAAgJcw+QQgCHAQAAAA==.Lunariella:BAAALgADCgkJGAAAAA==.',
Ly='Lysandrra:BAAALgAECgMJBAAAAA==.',
Ma='Madeline:BAAALgAECgYJCQAAAA==.Malafar:BAAALgAFFAIJBAAAAA==.Malfuriion:BAAALgAECgUJBwAAAA==.Maranwae:BAABLgAECn9OAAMZAAkJoiBOAQAHAwAZAAkJoiBOAQAHAwAaAAEJHhtvkgBOAAAAAA==.Mastakwaa:BAAALgAECgEJAQAAAA==.Maybemo:BAAALgAECggJCgAAAA==.Maylata:BAAALgAECgYJBgAAAA==.',
Me='Mebumsir:BAAALgADCgUJBgAAAA==.Melokoi:BAABLgAECn86AAMWAAkJSiNGAwAEAwAWAAkJSiNGAwAEAwAhAAUJ4gSTKwCYAAAAAA==.Menxwolf:BAAALgADCgQJBAAAAA==.Merlose:BAABLgAECn84AAIfAAkJvhqhBwBiAgAfAAkJvhqhBwBiAgAAAA==.',
Mi='Minidrake:BAABLgAECn8ZAAMNAAgJ3wxKGABNAQANAAgJ3wxKGABNAQAdAAMJQwVKMwB7AAAAAA==.',
Mo='Moana:BAAALgAFFAMJAwABLgAFFAUJEgAPAD4hAA==.Mogrun:BAABLgAECn8WAAMSAAcJShlpFwCOAQAIAAYJJRqVWAC+AQASAAYJlRVpFwCOAQAAAA==.Monahci:BAAALgADCgcJEwAAAA==.Monocho:BAAALgAECgEJAQAAAA==.Monrroe:BAABLgAECn8WAAMfAAYJSBLbIQAGAQAfAAYJSBLbIQAGAQARAAYJ3gvdYgCqAAAAAA==.Mooasaurus:BAAALgAFFAIJAgAAAA==.Moonfaith:BAAALgAECgIJAgABLgAFFAQJFwAMAHsPAA==.Moonveil:BAAALgAECggJDQABLgAFFAQJFwAMAHsPAA==.Moosader:BAAALgAECgEJAQABLgAECgUJDgAOAAAAAA==.Moshamie:BAABLgAECn8tAAIaAAkJxghuQAAyAQAaAAkJxghuQAAyAQAAAA==.',
Na='Naeryns:BAAALgAECgUJCQAAAA==.Naleana:BAAALgAECgUJDgAAAA==.Narzwaz:BAABLgAECn8rAAICAAkJpR/gBwDKAgACAAkJpR/gBwDKAgAAAA==.Natallia:BAAALgADCgUJBQABLgAECgkJVwAXACciAA==.',
Ne='Nehemiia:BAAALgADCgMJAwAAAA==.Neytri:BAABLgAECn8/AAIXAAkJpRTNMwANAgAXAAkJpRTNMwANAgAAAA==.',
Ni='Nivale:BAABLgAECn8WAAIDAAYJWht0jABeAQADAAYJWht0jABeAQAAAA==.',
No='Noc:BAAALgADCgIJAgAAAA==.Noel:BAACLgAFFH8XAAIDAAkJjA/6HwACAgADAAkJjA/6HwACAgAuAAQKfyAAAgMACAmyGZJYAC8CAAMACAmyGZJYAC8CAAAA.Nosotras:BAABLgAECn8oAAIIAAkJXxBeSgC7AQAIAAkJXxBeSgC7AQAAAA==.Noxicous:BAAALgAECgYJEQABLgAECgcJCgAOAAAAAA==.',
Nz='Nzoth:BAAALgAFFAMJAwABLgAFFAQJCgALAIwOAA==.',
Ol='Olitas:BAAALgAFFAEJAgAAAA==.',
Pa='Pahudesh:BAAALgADCgUJBQABLgAECgkJKAABAPwgAA==.Pahukupua:BAAALgAECgIJAgAAAA==.Patches:BAABLgAECn8dAAMiAAkJ6hGwFwDdAQAiAAkJ6hGwFwDdAQAjAAEJEgT4LAAlAAAAAA==.',
Pe='Pelonia:BAAALgAECgYJBQAAAA==.Perse:BAAALgAECgQJBQAAAA==.',
Ph='Phaera:BAAALgAECgIJAgABLgAECgYJFQANAJQMAA==.Phau:BAABLgAECn8oAAIBAAkJ/CCKBgA6AwABAAkJ/CCKBgA6AwAAAA==.',
Pi='Pinklemonade:BAAALgAECgQJCgAAAA==.',
Pl='Plagos:BAAALgADCgcJEAAAAA==.Playmate:BAACLgAFFH8XAAIMAAQJew/7MgDiAAAMAAQJew/7MgDiAAAuAAQKfyMAAgwACAlXHwscAGYCAAwACAlXHwscAGYCAAAA.',
Po='Pointbreak:BAAALgADCgQJBAAAAA==.Potatoe:BAAALgADCgQJBAAAAA==.',
Pr='Prahumn:BAAALgAECgQJDwAAAA==.Prozac:BAAALgADCgMJAwAAAA==.Prïnçess:BAAALgAECgUJDAAAAA==.',
Pu='Purplicious:BAAALgAECgYJDAAAAA==.',
Py='Pymilocs:BAABLgAECn86AAIaAAkJPCKmBgDyAgAaAAkJPCKmBgDyAgAAAA==.',
Qu='Qualison:BAAALgAECgYJEgAAAA==.Quint:BAAALgAECgMJBAAAAA==.Quleiry:BAAALgAFFAMJAwAAAA==.',
Ra='Rabare:BAAALgAECgcJDgAAAA==.Rabore:BAAALgAECgQJBAAAAA==.Rahumn:BAACLgAFFH8KAAIHAAMJyAhMPgCxAAAHAAMJyAhMPgCxAAAuAAQKfycAAgcACAn5FYUmAMQBAAcACAn5FYUmAMQBAAAA.Raktal:BAAALgAECgMJAgAAAA==.Ralee:BAACLgAFFH8FAAIGAAIJvAwSXACQAAAGAAIJvAwSXACQAAAuAAQKf0kAAgYACQnVFJIJAHMBAAYACQnVFJIJAHMBAAAA.Ralienne:BAAALgADCgcJBwABLgAFFAIJBQAGALwMAA==.Ranebowz:BAACLgAFFH8GAAIKAAMJQQaBngCAAAAKAAMJQQaBngCAAAAuAAQKfy4AAgoACQl+H/0hAH4CAAoACQl+H/0hAH4CAAAA.Ravenmohr:BAAALgADCgUJBQAAAA==.Ravinia:BAAALgAECgEJAQAAAA==.Razleaf:BAAALgAECgQJBQABLgAECgkJCgAOAAAAAA==.',
Re='Rennai:BAAALgAECgcJDAAAAA==.',
Rh='Rhebeqa:BAAALgAECgUJBAABLgAECggJFgADAPAFAA==.',
Ri='Richter:BAAALgADCgkJIAAAAA==.Rin:BAEBLgAECn82AAIBAAkJbiIDBQBcAwABAAkJbiIDBQBcAwAAAA==.Rist:BAABLgAECn8gAAIWAAkJAxDnGgBhAQAWAAkJAxDnGgBhAQAAAA==.',
Ro='Rogelink:BAAALgAECggJDgAAAA==.Rosan:BAABLgAFFH8GAAIDAAIJYwfVUgBmAAADAAIJYwfVUgBmAAAAAA==.Royakan:BAAALgAECgEJBAAAAA==.',
Sa='Samoset:BAABLgAECn8nAAIQAAkJDBS0HADhAQAQAAkJDBS0HADhAQAAAA==.',
Sc='Scarhide:BAABLgAECn8gAAQhAAkJWhMuGQCRAQAhAAkJuQ4uGQCRAQAWAAgJqRDXGQBsAQAHAAYJMw9sCQAJAQAAAA==.',
Se='Setsuna:BAABLgAECn8eAAMdAAkJESP5BwBoAgAdAAYJBCX5BwBoAgAUAAUJZx5+KwCQAQABLgAECgYJCQAOAAAAAA==.',
Sh='Shadaloo:BAABLgAFFH8HAAIGAAMJIBC2mwDZAAAGAAMJIBC2mwDZAAAAAA==.Shahumn:BAAALgAECgEJAQAAAA==.Shaori:BAAALgADCgkJCQAAAA==.Shava:BAAALgAECgYJBgAAAA==.Sheepstealer:BAABLgAECn8eAAIdAAkJwRMWBwDUAQAdAAkJwRMWBwDUAQAAAA==.Shippo:BAAALgAECgIJAgAAAA==.Shire:BAAALgAECgUJBQAAAA==.Shockisha:BAAALgAECgQJBAAAAA==.Showgirl:BAAALgADCgcJBwABLgAFFAYJHAANAPMWAA==.',
Si='Silvanthos:BAAALgAECgQJBwAAAA==.Silvers:BAAALgAECgUJCwAAAA==.Silverthorn:BAAALgAECgIJAgAAAA==.',
Sk='Skrom:BAABLgAECn8UAAIkAAkJewosAwBLAQAkAAkJewosAwBLAQAAAA==.',
Sl='Sliccie:BAABLgAECn8sAAIIAAgJIBKFXgCEAQAIAAgJIBKFXgCEAQAAAA==.',
Sm='Smashypants:BAAALgADCgIJAgAAAA==.Smitegoat:BAACLgAFFH8QAAMlAAUJCQnxIgA4AQAlAAUJ1wjxIgA4AQAQAAEJ/gxMOQAvAAAuAAQKfygAAxAACQleHJ8UADkCABAACAnzGZ8UADkCACUAAwmFHWhDAPsAAAAA.',
Sn='Sney:BAABLgAECn80AAIaAAYJuhJvCQD5AAAaAAYJuhJvCQD5AAABLgAFFAIJBQAGALwMAA==.',
So='Solaia:BAABLgAECn8YAAIWAAgJ8xRxEgDEAQAWAAgJ8xRxEgDEAQABLgAFFAkJKQAVACgdAA==.Solar:BAAALgAECgkJAQAAAA==.Solomon:BAAALgAFFAEJAQAAAA==.Sorlzul:BAAALgAECgMJBwAAAA==.Sound:BAAALgAECgIJBQABLgAECgMJAwAOAAAAAA==.',
Sp='Specialbarz:BAAALgADCgEJAQAAAA==.',
St='Stellaluna:BAAALgAECgQJBAAAAA==.Stranger:BAAALgAECgcJBwAAAA==.',
Su='Suotokahn:BAAALgADCgQJCQAAAA==.',
Sv='Svanalock:BAAALgADCgcJDwAAAA==.',
Sy='Sybbil:BAAALgADCgUJBQAAAA==.',
Ta='Tad:BAABLgAECn8eAAIXAAkJNQ0iUQCvAQAXAAkJNQ0iUQCvAQAAAA==.Taini:BAAALgADCgYJBgABLgAFFAkJKQAVACgdAA==.Taiurag:BAAALgAECgUJEwAAAA==.Taken:BAABLgAECn8jAAIDAAkJWwYLmgBFAQADAAkJWwYLmgBFAQAAAA==.Tazra:BAACLgAFFH8SAAIKAAQJjxyDFgApAQAKAAQJjxyDFgApAQAuAAQKfzoAAgoACQlsH5YmAGoCAAoACQlsH5YmAGoCAAAA.Tazzy:BAAALgAECgMJAwAAAA==.Tazzyy:BAAALgAECgQJBAAAAA==.',
Te='Terrylabonte:BAAALgAECgcJEgAAAA==.',
Th='Thomaz:BAABLgAECn8pAAIHAAkJIxPuIgDbAQAHAAkJIxPuIgDbAQAAAA==.Thorninii:BAAALgADCgQJBAAAAA==.Thundergoose:BAAALgAECgMJAwAAAA==.',
Ti='Tirel:BAAALgADCgkJDgAAAA==.',
To='Tondri:BAAALgAFFAIJAwAAAA==.Tonkatruck:BAABLgAECn8gAAIKAAkJFhjDNQApAgAKAAkJFhjDNQApAgAAAA==.',
Tt='Ttvnazboo:BAAALgADCgMJBAAAAA==.',
Tu='Tulany:BAABLgAECn8VAAMQAAgJYwjVOgAMAQAlAAYJYwcJMQAYAQAQAAgJCwfVOgAMAQABLgAECgkJCgAOAAAAAA==.Tuyenlotus:BAABLgAECn8nAAIkAAkJtxwmCABEAgAkAAkJtxwmCABEAgAAAA==.',
Un='Unholypriest:BAAALgAECgYJCwAAAA==.',
Ut='Utloc:BAAALgAECgYJEwAAAA==.',
Va='Vahnya:BAABLgAECn87AAIaAAkJ5Rs5DwB9AgAaAAkJ5Rs5DwB9AgAAAA==.Vardren:BAAALgADCgQJBAAAAA==.',
Ve='Venekor:BAABLgAECn8wAAMUAAkJLQuYMgBqAQAUAAkJ6wqYMgBqAQAdAAEJgwgpJwAvAAAAAA==.Vesia:BAABLgAECn8YAAMQAAYJZRiWMQBGAQAQAAYJZRiWMQBGAQAPAAQJYBPZPwD4AAAAAA==.',
Vi='Viainfinita:BAAALgADCgYJBgAAAA==.Viannaironcl:BAAALgADCgIJAgAAAA==.Vicarrion:BAAALgAECggJEwAAAA==.Viscera:BAAALgADCgMJAwAAAA==.',
Vo='Voidrat:BAABLgAECn8ZAAMBAAcJGBwOCwBHAQABAAYJyBsOCwBHAQACAAYJcxSvOgAXAQABLgAECgkJTwABAPgZAA==.Voidweaver:BAAALgADCgYJBgAAAA==.',
Vr='Vrat:BAAALgAECgYJCAABLgAECgkJTwABAPgZAA==.',
Vy='Vyndenfox:BAAALgADCgkJCQAAAA==.',
['Ví']='Ví:BAABLgAECn83AAQDAAkJgAtlHQDEAAADAAkJjghlHQDEAAAmAAUJHAwKDAC+AAAeAAEJAAAoGQAAAAAAAA==.',
Wa='Warfare:BAAALgAFFAIJAwAAAA==.',
Wh='Whistler:BAAALgADCgEJAQAAAA==.Whitezi:BAAALgAECgYJBwAAAA==.',
Wi='Wildpally:BAABLgAECn8XAAIfAAUJYA2hLgCuAAAfAAUJYA2hLgCuAAAAAA==.',
['Wí']='Wíldhide:BAAALgADCgMJAwAAAA==.',
Xo='Xonon:BAAALgAECgYJEAAAAA==.',
Xw='Xweithel:BAAALgAECgQJBwAAAA==.',
Yo='Yourmageisty:BAABLgAECn89AAMDAAkJGRpyPwAeAgADAAkJCxZyPwAeAgAmAAYJzhgKBQCUAQAAAA==.',
Yu='Yulíana:BAAALgAFFAIJAgAAAA==.',
Za='Zakýe:BAAALgAECgQJBAAAAA==.Zanot:BAAALgADCgYJBgAAAA==.Zariara:BAAALgADCgUJBQAAAA==.',
Zc='Zcart:BAABLgAECn9GAAMXAAkJeRgFKAA/AgAXAAkJeRgFKAA/AgAbAAEJ4QFKmgAZAAAAAA==.',
Ze='Zelara:BAABLgAFFH8GAAIgAAIJUBGCLgBhAAAgAAIJUBGCLgBhAAAAAA==.Zeluxum:BAAALgAECgYJBwABLgAECgkJKAAGAMweAA==.Zertloc:BAACLgAFFH8FAAIaAAIJmxFFIQB8AAAaAAIJmxFFIQB8AAAuAAQKf1IAAhoACQk6ImsEABwDABoACQk6ImsEABwDAAAA.',
Zh='Zhaan:BAAALgAECgYJBgAAAA==.',
Zi='Zieda:BAACLgAFFH8XAAIEAAQJGRJBIgAQAQAEAAQJGRJBIgAQAQAuAAQKfyoAAgQACAmHGYUZAAACAAQACAmHGYUZAAACAAAA.Ziti:BAAALgADCgIJAgAAAA==.',
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
