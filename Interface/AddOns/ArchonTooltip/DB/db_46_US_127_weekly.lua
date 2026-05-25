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

local lookup = {'Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DemonHunter-Devourer','Warrior-Protection','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Paladin-Retribution','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Paladin-Holy','Priest-Shadow','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Demonology','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECgUJBQAAAA==.Bazthrax:BAAALgAECgMJAgAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAAALgAECgUJCgAAAA==.',
Bl='Blade:BAACLgAFFH8KAAIBAAMJzh0tIwDyAAABAAMJzh0tIwDyAAAuAAQKfx0AAgEACAnWIpMUACgCAAEACAnWIpMUACgCAAAA.Blarneystone:BAAALgAECgUJDgAAAA==.Bluemoon:BAAALgADCgYJBgAAAA==.',
Bo='Bootybsneaks:BAACLgAFFH8bAAICAAUJCiN1CQCWAQACAAUJCiN1CQCWAQAuAAQKfzUAAwIACQkiI0QDAPsCAAIACQkiI0QDAPsCAAMAAQl8FqMgADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIEAAYJ5AthHQDiAAAEAAYJ5AthHQDiAAAAAA==.',
Bu='Bullfist:BAAALgAECgYJCgABLgAECggJJAAFABocAA==.Bullievit:BAACLgAFFH8FAAIGAAMJFxDDJgDFAAAGAAMJFxDDJgDFAAAuAAQKfyQAAwYACQleHSEWAPUBAAYACQleHSEWAPUBAAcABAktBTyeAI4AAAAA.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn80AAIIAAkJpRAcCADHAQAIAAkJpRAcCADHAQAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgABAM4dAA==.Chaozz:BAABLgAECn8YAAIJAAYJXyIQPwD4AQAJAAYJXyIQPwD4AQAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgUJBgAAAA==.Chunly:BAAALgAECgYJEQAAAA==.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8VAAIKAAgJRw/pFgBkAQAKAAgJRw/pFgBkAQAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQALAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8mAAMMAAgJYhODJwCFAQAMAAgJSxCDJwCFAQANAAYJcBAUDQAfAQAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAAALgAECgYJEwAAAA==.Davik:BAAALgAECgQJEwAAAA==.',
De='Deathcharger:BAAALgADCgYJDwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgMJAgAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8XAAIOAAgJgwzeeABcAQAOAAgJgwzeeABcAQAAAA==.',
Dr='Dracarsynimz:BAAALgAFFAIJAgABLgAFFAQJEwAMAEILAQ==.Dracene:BAAALgAECgUJDgAAAA==.Dragosa:BAAALgADCgMJAwABLgAECgMJBAAPAAAAAA==.',
Du='Duf:BAAALgAECgEJAwAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgEJAQABLgAECgQJCwAPAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMQAAkJvB4OBQAUAwAQAAkJvB4OBQAUAwARAAEJZQrEhQA7AAAAAA==.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgUJCgAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMSAAgJkxSdGQARAgASAAgJkxSdGQARAgAOAAEJ8QQ7dgEpAAAAAA==.',
Gb='Gb:BAACLgAFFH8NAAMTAAQJ8hplGQD4AAATAAMJsBllGQD4AAAUAAMJyQ90JADaAAAuAAQKfygABBQACQlKHRUGAP4CABQACQlKHRUGAP4CABMACAnlHAMOAKMCABUAAgk5CDJxAGIAAAAA.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECggJKAALABQXAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8FAAIWAAMJ3yP3MQAaAQAWAAMJ3yP3MQAaAQAuAAQKfz0AAhYACAmRJRAJAO8CABYACAmRJRAJAO8CAAAA.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Je='Jeffren:BAAALgAECgQJCwAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIgAWAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAILAAcJPiQcEAB+AgALAAcJPiQcEAB+AgAAAA==.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8OAAIHAAQJwBDmIgAUAQAHAAQJwBDmIgAUAQAuAAQKfyoAAgcACQkPHzYLAO0CAAcACQkPHzYLAO0CAAAA.',
Kr='Krazedwolf:BAACLgAFFH8FAAIOAAMJPBNESgDuAAAOAAMJPBNESgDuAAAuAAQKfygAAg4ACQlGIW0QAMoCAA4ACQlGIW0QAMoCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgADCgEJAQAAAA==.Lehran:BAAALgAECgIJAwAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAITAAgJJx19AAC/AgATAAgJJx19AAC/AgAuAAQKfzcAAhMACQklJkABAMADABMACQklJkABAMADAAAA.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8bAAIXAAYJMQ5unQAIAQAXAAYJMQ5unQAIAQAAAA==.Lovelypwr:BAABLgAECn86AAITAAkJdRNxFgDyAQATAAkJdRNxFgDyAQAAAA==.',
Ma='Mannera:BAAALgAFFAMJAwAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAECgMJBAAAAA==.Matheris:BAABLgAECn8YAAIKAAkJZiL+AwDOAgAKAAkJZiL+AwDOAgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAAALgAECgYJEQABLgAFFAMJBQAYAI8OAA==.',
Me='Melarac:BAABLgAECn8VAAQGAAYJjQk+QwDNAAAGAAYJjQk+QwDNAAAHAAUJCAhEegCpAAAFAAUJ1AYzPgBjAAAAAA==.',
Mi='Minibow:BAAALgAECgEJAQAAAA==.Minimagic:BAACLgAFFH8QAAIZAAQJNRzXOABRAQAZAAQJNRzXOABRAQAuAAQKfzoAAhkACQkGJK8IACIDABkACQkGJK8IACIDAAAA.',
Mo='Mogh:BAAALgAECgQJBAAAAA==.Monker:BAABLgAECn8eAAQQAAgJzh6fFAA7AgAQAAcJrh6fFAA7AgALAAYJgBUQPgAjAQARAAMJvBx5UwCaAAAAAA==.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgAPAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgAPAAAAAA==.',
My='Mysteria:BAAALgADCgEJAQAAAA==.',
Na='Nasara:BAABLgAECn82AAIZAAgJXyP7IADwAgAZAAgJXyP7IADwAgAAAA==.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgIJAgAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgADCgEJAQAAAA==.',
Ni='Nikallnight:BAAALgADCgYJBgAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgcJHQAJAL4WAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQALAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAgABLgAECgkJOgATAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgADCgMJAwAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAABLgAECn8bAAIXAAYJERYtjQAlAQAXAAYJERYtjQAlAQAAAA==.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQALAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAAALgAECgUJDgAAAA==.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJDwAAAA==.Revanoc:BAAALgAECgEJAQAAAA==.Revanon:BAAALgADCgYJBgAAAA==.',
Ro='Roidsnmolly:BAAALgAECgYJAQAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAQJDgAHAMAQAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAAALgAECgcJDwAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAEAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECgcJCwAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDgAAAA==.',
Sh='Shammtastiç:BAABLgAECn8zAAIaAAkJIRebGQDpAQAaAAkJIRebGQDpAQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAATACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8lAAMXAAgJog3LZAB6AQAXAAgJog3LZAB6AQAIAAMJJwUxLgAoAAAAAA==.',
Sn='Sncak:BAACLgAFFH8ZAAMCAAYJVhz8BgC7AQACAAYJVhz8BgC7AQADAAEJOQ08BgBcAAAuAAQKfyoAAwIACQkPJCgCAJADAAIACQkPJCgCAJADAAMABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8GAAIEAAMJnQ87CQDrAAAEAAMJnQ87CQDrAAAuAAQKfxsAAgQACQn2ITsEAN0CAAQACQn2ITsEAN0CAAAA.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgADCgUJBQAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgQJBgAAAA==.Syrax:BAABLgAECn8fAAMNAAcJqha7CAB/AQANAAYJCBq7CAB/AQAMAAQJawzKUwC2AAABLgAFFAMJBQAYAI8OAA==.Syrieal:BAACLgAFFH8FAAIYAAMJjw5XHgC1AAAYAAMJjw5XHgC1AAAuAAQKfzAAAxgACQlSG4oLACcCABgACQn3GooLACcCAAgAAglCDgkmAEoAAAAA.',
Ta='Taiyla:BAABLgAECn81AAIZAAkJmxEyQQD9AQAZAAkJmxEyQQD9AQAAAA==.Talithiala:BAAALgAECgYJCQAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMQAAgJExkqEwAzAgAQAAgJExkqEwAzAgALAAcJigpzTACnAAAAAA==.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Thyra:BAAALgAECgUJBQABLgAFFAQJDgAHAMAQAA==.',
Tr='Trip:BAABLgAECn8kAAMbAAkJSgvvVgArAQAbAAkJSgvvVgArAQAcAAcJBw0dFQApAQAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIcAAYJORmQEABtAQAcAAYJORmQEABtAQAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJHQAVABwcAA==.Unilock:BAABLgAECn8fAAIdAAkJORnvIwA2AgAdAAkJORnvIwA2AgABLgAFFAcJHQAVABwcAA==.Unipray:BAACLgAFFH8dAAMVAAcJHBz0AQAvAgAVAAcJHBz0AQAvAgATAAUJXhWuEQA8AQAuAAQKfycAAxUACQmwIlABAG8DABUACQmwIlABAG8DABMABwnrHoYYAN4BAAAA.',
Va='Valaran:BAAALgAECgEJAQAAAA==.Vamperella:BAABLgAECn8XAAIeAAUJcgHaDgBSAAAeAAUJcgHaDgBSAAAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgQJBgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wu='Wumbo:BAAALgAECgIJAgABLgAFFAcJIQAXALgkAA==.',
Ye='Yefercas:BAAALgAECgUJCgAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIfAAkJGRaoAQBMAgAfAAkJGRaoAQBMAgAAAA==.',
Yl='Ylvis:BAABLgAECn8oAAIWAAgJogcGYABZAQAWAAgJogcGYABZAQAAAA==.',
Yo='You:BAABLgAECn8kAAIYAAkJsxe0EADPAQAYAAkJsxe0EADPAQAAAA==.',
Yu='Yulogee:BAAALgAFFAMJBAAAAA==.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAPAAAAAA==.',
Ze='Zemzelett:BAAALgAECgUJCwAAAA==.Zeuz:BAAALgADCgEJAQAAAA==.',
Zu='Zumadin:BAAALgADCgkJBwAAAA==.Zummev:BAAALgADCgYJBAAAAA==.',
['Æs']='Æsham:BAAALgADCgQJBAAAAA==.',
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
