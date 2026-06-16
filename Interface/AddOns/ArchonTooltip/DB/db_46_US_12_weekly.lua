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

local lookup = {'Mage-Frost','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Warrior-Fury','Shaman-Elemental','Rogue-Subtlety','Evoker-Preservation','DemonHunter-Vengeance','Druid-Guardian','Hunter-Survival','Warlock-Demonology','Paladin-Holy','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','DemonHunter-Devourer','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Paladin-Protection','Monk-Brewmaster','Hunter-Marksmanship','Shaman-Enhancement',}
local provider = {region='US',realm='Anetheron',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abcmico:BAABLgAECn8XAAIBAAkJ3RwvGgC6AgABAAkJ3RwvGgC6AgAAAA==.',
Ar='Aragarne:BAAALgAECgEJAQAAAA==.Arsha:BAAALgAECgQJBAAAAA==.Arskii:BAAALgADCggJCAAAAA==.',
As='Askii:BAABLgAECn8mAAMCAAgJlhysCQDEAQACAAgJlhysCQDEAQADAAQJpBFcNADlAAAAAA==.',
At='Atulock:BAAALgAECgcJBwAAAA==.',
Az='Azuth:BAAALgADCgYJAQABLgAECgkJLgAEAF8PAA==.',
Ba='Badaspen:BAAALgAECgYJBgAAAA==.Banshee:BAAALgAECgQJCAAAAA==.Batlad:BAAALgAECgEJAgAAAA==.',
Be='Beefcake:BAACLgAFFH8FAAIFAAMJCR4qKAAPAQAFAAMJCR4qKAAPAQAuAAQKf1QAAgUACQnMJeUAAH0DAAUACQnMJeUAAH0DAAAA.',
Bi='Bigsneak:BAAALgAECgEJAQAAAA==.',
Bj='Bjorn:BAAALgAECgMJAwABLgAFFAUJDgAGAKIIAA==.',
Bo='Bojtit:BAAALgADCgUJBQABLgAECgkJIgAHAH0YAA==.Borgor:BAAALgAECgYJDgAAAA==.',
Br='Brachroy:BAAALgADCgcJDAAAAA==.',
Bu='Bullvar:BAAALgAECgUJBQAAAA==.Bunnie:BAAALgAECgUJDAABLgAECgYJGAAIAOUMAA==.Bus:BAABLgAFFH8GAAIJAAYJOiPoAAAKAgAJAAYJOiPoAAAKAgABLgAFFAkJHAAKAP8jAA==.',
Ca='Canttoucthis:BAAALgADCggJDAAAAA==.Casaran:BAAALgAECgkJEgAAAA==.',
Ce='Cesio:BAABLgAFFH8GAAILAAMJFxZkHADoAAALAAMJFxZkHADoAAAAAA==.',
Ch='Chen:BAAALgAECgkJEwAAAA==.',
Co='Cotilliôn:BAACLgAFFH8RAAIHAAQJnhWXGQBCAQAHAAQJnhWXGQBCAQAuAAQKfzUAAgcACAlVIDwKAH0CAAcACAlVIDwKAH0CAAAA.',
Cr='Criticaltuna:BAACLgAFFH8aAAMMAAUJpB17QgBBAQAMAAUJCB17QgBBAQACAAEJ+x86GABaAAAuAAQKfygABAMACAloHukZAH0BAAwABgkkGPNkAJwBAAMABQlgGukZAH0BAAIAAQmXHzElAF0AAAAA.',
Da='Dadadin:BAAALgAECgQJBAAAAA==.Dalanaar:BAAALgADCgQJBAAAAA==.Danimal:BAAALgAFFAIJAgAAAA==.',
De='Deadmens:BAAALgAECgYJCwABLgAFFAQJDgACAHETAA==.Deathblooms:BAACLgAFFH8QAAIJAAUJkR1SAACgAQAJAAUJkR1SAACgAQAuAAQKfyoAAgkACAkwIrYBAP8CAAkACAkwIrYBAP8CAAAA.Destinie:BAACLgAFFH8XAAINAAUJ3yVyCQAVAgANAAUJ3yVyCQAVAgAuAAQKfzgAAg0ACQn4IvUEAEQDAA0ACQn4IvUEAEQDAAAA.Destiniedrud:BAAALgAECgUJCgABLgAFFAUJFwANAN8lAA==.Destiniepves:BAAALgAECgQJBAABLgAFFAUJFwANAN8lAA==.',
Di='Dimlock:BAAALgAECgkJDAAAAA==.Disbearleaf:BAAALgAECgYJCAAAAA==.Disc:BAAALgADCgQJBAABLgADCgYJCwAOAAAAAA==.',
Dr='Dragooning:BAACLgAFFH8MAAIPAAQJ9BB8MQD6AAAPAAQJ9BB8MQD6AAAuAAQKfzQAAw8ACQmFG3ANAIYCAA8ACQmFG3ANAIYCABAAAgl6EnAaAHYAAAAA.',
Du='Duriniknight:BAAALgAFFAIJAwAAAA==.',
['Dé']='Déllenna:BAABLgAECn8jAAIPAAgJNgXQTAD2AAAPAAgJNgXQTAD2AAAAAA==.',
Ea='Earthen:BAABLgAFFH8GAAIRAAQJsQ9zNQAEAQARAAQJsQ9zNQAEAQABLgAFFAUJCgASAGMaAA==.',
El='Elfisto:BAAALgAECgEJAQAAAA==.Ellaa:BAAALgADCgEJAQAAAA==.Ellin:BAAALgAECgIJAgAAAA==.Elokyria:BAAALgAECgYJBgAAAA==.Elorom:BAAALgAECgQJBgAAAA==.Elrentha:BAAALgADCgEJAQAAAA==.',
Em='Emiira:BAAALgAECgMJAwAAAA==.',
Eo='Eos:BAAALgADCgEJAgAAAA==.',
Ep='Ephana:BAAALgAECgEJAQAAAA==.Ephemeral:BAAALgAECgQJCAABLgAECgkJNQATAOgjAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Ex='Excalibes:BAEALgAECgkJAwABLgAECgkJYAAIAJIZAA==.',
Fa='Falkion:BAACLgAFFH8ZAAIFAAUJJh54EwBpAQAFAAUJJh54EwBpAQAuAAQKfzgAAgUACQmvIMwHAOECAAUACQmvIMwHAOECAAAA.',
Fi='Fistingpower:BAAALgAECggJEgABLgAFFAQJDAAPAPQQAA==.',
Fo='Folus:BAAALgAECgEJAQAAAA==.Foluspriest:BAAALgADCgQJBAABLgAECgEJAQAOAAAAAA==.',
Fr='Frozarak:BAAALgADCgQJBAAAAA==.',
Fu='Fuzzy:BAABLgAECn8gAAIUAAkJihs9CwA2AgAUAAkJihs9CwA2AgAAAA==.',
Ge='Gemini:BAAALgAECgUJCgAAAA==.Gewch:BAAALgAECgEJAQAAAA==.',
Gi='Gimlii:BAABLgAECn82AAMVAAkJ6B0rBQC4AgAVAAkJ6B0rBQC4AgAFAAYJHhYYRwCIAQAAAA==.',
Go='Goybeam:BAAALgADCgIJAgAAAA==.',
['Gû']='Gûst:BAAALgAECgQJBAAAAA==.',
Ha='Hachi:BAAALgADCgIJAgAAAA==.Hans:BAAALgAECgIJAgAAAA==.Hanui:BAAALgAECgEJAwAAAA==.Harvoldold:BAAALgAECgEJBAABLgAECgMJBgAOAAAAAA==.',
He='Healuminati:BAAALgAECgkJBQAAAA==.',
Hi='Hib:BAAALgAECgMJAwAAAA==.',
Ho='Hokage:BAAALgAECgIJAgAAAA==.',
Hu='Hunterbidens:BAABLgAECn8zAAIWAAkJkSObBAAMAwAWAAkJkSObBAAMAwAAAA==.',
Ig='Igorz:BAAALgAECgIJAgAAAA==.',
Im='Important:BAAALgAFFAEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAOAAAAAA==.',
Ir='Ironhawk:BAAALgAECgUJCAAAAA==.Irønhåwk:BAAALgADCgEJAgAAAA==.',
It='Itchytasty:BAAALgAECgEJAQAAAA==.',
Iu='Iu:BAABLgAECn8dAAMFAAgJoQw6OABlAQAFAAgJyAs6OABlAQAVAAUJKgmZJADIAAAAAA==.',
Ja='Jada:BAAALgADCgYJBgAAAA==.Jazzy:BAAALgADCgEJAQAAAA==.',
Jo='Johnblizard:BAAALgAECgcJBwAAAA==.Jolly:BAABLgAECn88AAITAAkJ0w/AbgCOAQATAAkJ0w/AbgCOAQAAAA==.Jollymage:BAAALgAECgcJCQAAAA==.',
Ka='Kamia:BAAALgADCgEJAQAAAA==.Karina:BAABLgAECn8dAAITAAkJJA0JTQD7AQATAAkJJA0JTQD7AQAAAA==.Kathadin:BAAALgADCgcJCgAAAA==.Kayd:BAAALgADCgcJBwAAAA==.Kazuha:BAAALgAFFAIJAgAAAA==.',
Ki='Kimari:BAACLgAFFH8IAAIWAAMJPhjcHADkAAAWAAMJPhjcHADkAAAuAAQKfxoAAhYACQmHGwkNAHICABYACQmHGwkNAHICAAAA.Kimìltonze:BAABLgAECn8eAAIUAAkJJgxeHQBHAQAUAAkJJgxeHQBHAQAAAA==.Kite:BAAALgAECgIJAgAAAA==.',
La='Lambpie:BAAALgAECgQJCAABLgAFFAMJBQAFAAkeAA==.',
Li='Lillith:BAAALgAECgYJEgAAAA==.Lilyanna:BAAALgAECgIJAwAAAA==.Limeaid:BAACLgAFFH8PAAMQAAQJ6h1HAgBoAQAQAAQJ6h1HAgBoAQAPAAEJuBRJYQBEAAAuAAQKfzUABBAACQnxItIAAG8DABAACQnxItIAAG8DAA8ACAnfGJE2AFMBAAgAAglABOxAAGQAAAEuAAUUCAkaABcApxIA.Limelight:BAAALgAECgkJEQABLgAFFAgJGgAXAKcSAA==.Limeylady:BAACLgAFFH8aAAMXAAgJpxIwDwAcAgAXAAcJkBIwDwAcAgAYAAUJNBRAEABjAQAuAAQKfzgAAxgACQnVIvgDAB0DABgACQnVIvgDAB0DABcABwmYHr8QADYCAAAA.Liridra:BAAALgAECgYJCAAAAA==.',
Ma='Madwilliam:BAAALgAECgkJBgAAAA==.Magicaltuna:BAAALgAECgUJDgABLgAFFAUJGgAMAKQdAA==.Malvado:BAACLgAFFH8OAAMCAAQJcRMXBQAzAQACAAQJcRMXBQAzAQAMAAIJJATArwByAAAuAAQKfzQABAIACQlZGDoGABkCAAIACQlZGDoGABkCAAwABQlxEdGVAC0BAAMABAnDELAhAJ0AAAAA.Matheney:BAEALgAFFAEJAQABLgAFFAYJCwAPAAYPAA==.Mazikeen:BAAALgADCgcJDgAAAA==.',
Mi='Milktruk:BAACLgAFFH8XAAMZAAUJdh78RQBiAQAZAAUJdh78RQBiAQAaAAQJZR49EgD2AAAuAAQKfysAAxkACQm8JDQHADsDABkACQm8JDQHADsDABoAAwl4GoMfAM0AAAAA.Minji:BAABLgAECn8ZAAIbAAkJMBbKCQAiAgAbAAkJMBbKCQAiAgAAAA==.',
Mo='Mook:BAAALgADCgQJBAAAAA==.Morzrac:BAAALgADCgMJAwAAAA==.',
Ne='Nemosum:BAABLgAECn8YAAQNAAcJsAhFXAAMAQANAAcJsAhFXAAMAQATAAQJjgiXKAGEAAAcAAUJcwMsQABbAAAAAA==.',
Ni='Nightingale:BAAALgADCgcJBwAAAA==.Ningning:BAAALgAECgkJEAAAAA==.Nizyr:BAAALgAECgEJBgAAAA==.',
No='Nottahealer:BAAALgADCgcJDQAAAA==.',
Ny='Nyra:BAAALgAECgMJAwAAAA==.',
Og='Ogma:BAAALgADCgUJBQAAAA==.',
On='One:BAAALgAECgcJBwAAAA==.',
Os='Osiris:BAAALgADCgcJBwAAAA==.',
Pa='Padfoot:BAAALgAECgUJBQABLgAECgUJBgAOAAAAAA==.',
Pr='Prey:BAABLgAECn8fAAMKAAkJvxdZDAAXAgAKAAkJvxdZDAAXAgAbAAQJNQLbLABfAAAAAA==.',
Pu='Purpp:BAAALgAFFAMJAQAAAA==.',
Py='Pyreyn:BAACLgAFFH8LAAMNAAMJdxj8KADYAAANAAMJdxj8KADYAAATAAIJ1gjZKgB/AAAuAAQKfzMAAw0ACAkSHsQcABsCAA0ABwkJHsQcABsCABMACAmnF6lJAOcBAAAA.',
Ra='Radley:BAAALgAECgYJDwABLgAFFAkJDQAaAKEVAA==.Raelilah:BAABLgAECn8iAAIHAAkJfRiiDQBKAgAHAAkJfRiiDQBKAgAAAA==.Raenia:BAAALgAECgEJAQAAAA==.Rakuma:BAAALgADCgEJAQAAAA==.Rawr:BAAALgAECgcJBwAAAA==.',
Re='Reptar:BAACLgAFFH8dAAIdAAcJfhQ5EQCTAQAdAAcJfhQ5EQCTAQAuAAQKfxgAAh0ACAkHHA4bACwCAB0ACAkHHA4bACwCAAAA.',
Rh='Rhaegar:BAAALgAECgMJAwABLgAECgQJBAAOAAAAAA==.Rheolette:BAAALgAECgEJAQAAAA==.Rheolin:BAAALgAECgYJEgAAAA==.Rheolynx:BAABLgAECn8WAAINAAYJESNVFQBgAgANAAYJESNVFQBgAgAAAA==.Rheomei:BAAALgAECgMJAwAAAA==.Rheomoon:BAABLgAECn8ZAAIRAAcJ3xuQJAAvAgARAAcJ3xuQJAAvAgAAAA==.',
Ri='Ricki:BAAALgAECgQJAwAAAA==.',
Ro='Rookhrux:BAAALgAECgUJBgAAAA==.Rookrollux:BAAALgAECgUJCQAAAA==.Rosenya:BAAALgADCgMJAwAAAA==.',
['Rø']='Røsenrøt:BAABLgAECn8UAAIWAAcJvxQTLQBVAQAWAAcJvxQTLQBVAQAAAA==.',
Sa='Saelydera:BAAALgAECgQJBQAAAA==.Saizan:BAAALgAECgcJEQAAAA==.Samsara:BAAALgAECgYJCAAAAA==.',
Sc='Scourgeknigh:BAAALgADCgUJBAAAAA==.',
Se='Seolen:BAAALgAECgEJAQAAAA==.Seppuku:BAAALgAECgEJBAAAAA==.Serie:BAAALgAECgQJCQAAAA==.Severus:BAAALgAECgMJAgAAAA==.',
Sh='Shìfty:BAAALgADCgcJDgAAAA==.',
Si='Silverthorn:BAAALgAECgYJEAAAAA==.Sindrei:BAAALgADCgYJBgAAAA==.Sixxpack:BAAALgADCgcJAQAAAA==.',
Sm='Smokabull:BAAALgAECgEJAQAAAA==.',
St='Stamina:BAAALgADCgYJCwAAAA==.Stathome:BAAALgAECgEJAQAAAA==.Stormm:BAAALgAECgEJAQABLgAECgkJEQAOAAAAAA==.',
Su='Suicidalone:BAAALgAECgEJAQAAAA==.',
Sy='Sylveon:BAABLgAFFH8OAAIbAAYJbyb7AAAnAgAbAAYJbyb7AAAnAgABLgAFFAMJBgAbAMccAA==.Syndara:BAAALgAECgUJCQAAAA==.',
Ta='Tab:BAAALgAECgkJAQAAAA==.',
Ti='Tiamatt:BAAALgAECgkJEQAAAA==.',
To='Tornheart:BAABLgAECn8uAAICAAkJCRV6BQASAgACAAkJCRV6BQASAgAAAA==.',
Tr='Treyni:BAAALgADCgYJBgAAAA==.',
Tu='Tubby:BAAALgAECgYJDQAAAA==.Tubbycoin:BAABLgAECn8fAAMeAAkJmx/RCgC7AQAeAAgJPSDRCgC7AQALAAIJ3xosSACXAAAAAA==.Tulkas:BAACLgAFFH8PAAIfAAQJlh6dBgBMAQAfAAQJlh6dBgBMAQAuAAQKfxcAAh8ACAl7Gx8IAEECAB8ACAl7Gx8IAEECAAAA.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAZAIkhAA==.Vandel:BAAALgAECgYJBgAAAA==.',
Vr='Vrazten:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Wh='Whisper:BAAALgADCgYJBgAAAA==.',
Wy='Wyburn:BAAALgAECgUJCgAAAA==.Wyrm:BAAALgAECgUJBgAAAA==.',
['Yø']='Yøriçk:BAAALgAECgYJEwAAAA==.',
Za='Zane:BAAALgAECgYJBwAAAA==.Zaraelina:BAAALgAECgYJCQAAAA==.',
['Çl']='Çleadon:BAAALgAECgcJDgAAAA==.',
['ßê']='ßêästÿßöÿ:BAAALgAECgcJDAAAAA==.',
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
