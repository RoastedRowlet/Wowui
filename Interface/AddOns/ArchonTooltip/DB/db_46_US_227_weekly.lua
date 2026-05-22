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

local lookup = {'Warlock-Demonology','Paladin-Retribution','Warlock-Destruction','Warrior-Protection','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Fury','Rogue-Assassination','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','Paladin-Holy','DeathKnight-Blood','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Holy','Mage-Frost','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Evoker-Devastation','Unknown-Unknown','Druid-Restoration','DeathKnight-Frost','Druid-Balance','Mage-Arcane','Evoker-Augmentation','Evoker-Preservation','Mage-Fire','Priest-Discipline','Shaman-Elemental','Druid-Guardian','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-05-17',data={Ab='Abharn:BAAALgAECgYJDQAAAA==.',
Ak='Akeera:BAABLgAECn8VAAIBAAcJTw6McQApAQABAAcJTw6McQApAQAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAQJCwACAPoSAA==.',
Al='Althtar:BAAALgADCgQJBAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAABLgAECn8bAAMDAAgJngYdFwC6AAADAAcJDAcdFwC6AAABAAIJqgV97wBEAAAAAA==.',
An='Anaesthetize:BAAALgAECgIJAgAAAA==.Aness:BAABLgAECn8aAAIEAAgJwwLOIwDTAAAEAAgJwwLOIwDTAAAAAA==.Angelinalizy:BAAALgADCgkJCQAAAA==.Animagon:BAAALgADCgkJCQAAAA==.Animaker:BAABLgAECn8rAAIFAAkJCRVjMwD4AQAFAAkJCRVjMwD4AQAAAA==.Anngus:BAAALgADCgcJCAAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgADCgcJCAAAAA==.',
As='Ashido:BAAALgAECgYJDgAAAA==.Astreos:BAABLgAFFH8HAAIBAAUJJxomKABGAQABAAUJJxomKABGAQABLgAFFAgJHAAGAOwbAA==.Astrikin:BAAALgAECgYJDwABLgAFFAgJHAAGAOwbAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Baluu:BAAALgAECgQJBAAAAA==.Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn83AAIEAAkJ3CLWAQAUAwAEAAkJ3CLWAQAUAwAAAA==.Beraxes:BAABLgAECn8WAAIHAAcJtArQPQALAQAHAAcJtArQPQALAQAAAA==.',
Bl='Blasser:BAABLgAECn8fAAIIAAkJ6RroAgBeAgAIAAkJ6RroAgBeAgAAAA==.Blizizdumz:BAABLgAECn8uAAMCAAcJzR8yNQDvAQACAAcJ4x4yNQDvAQAJAAYJjyFBDgCTAQAAAA==.',
Bm='Bmcgilicuddy:BAAALgAECgYJCwAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Breadpitt:BAAALgAECgEJAQAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.Brillane:BAAALgADCgUJAwAAAA==.',
Bu='Bulsy:BAACLgAFFH8LAAMKAAQJvRvDFwBUAQAKAAQJvRvDFwBUAQALAAEJcgF/JgAyAAAuAAQKfyQAAwoACQnwHXwJANQCAAoACQnwHXwJANQCAAsABAmQBOtoAJsAAAAA.',
Ca='Calamidade:BAABLgAECn8rAAMMAAkJfAQdEgAtAQAMAAkJfAQdEgAtAQANAAMJdwGqnAA4AAAAAA==.Calashlar:BAAALgAECgIJBQAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAwAAAA==.',
Ce='Cerryan:BAABLgAECn8mAAIOAAgJqA9IJgCXAQAOAAgJqA9IJgCXAQAAAA==.Cexar:BAAALgAECgcJEAAAAA==.',
Ch='Chaoticprime:BAAALgADCgEJAwAAAA==.Charivium:BAAALgADCgQJBAAAAA==.Charo:BAAALgADCgkJEAAAAA==.Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn82AAIPAAkJQCELBQCmAgAPAAkJQCELBQCmAgAAAA==.',
Cl='Clother:BAACLgAFFH8YAAMHAAUJQSRLBACwAQAHAAUJ7RhLBACwAQAQAAUJQST3AQBkAQAuAAQKfxoAAwcACAkEIfYKAAQDAAcACAkEIfYKAAQDABAABgnmIGEHAEkCAAEuAAUUBgkSAAUAjx0A.',
Co='Cokenopepsi:BAABLgAECn8VAAIPAAgJQR3uEQCkAQAPAAgJQR3uEQCkAQAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJCwAAAA==.',
Cu='Curses:BAAALgAECggJEAAAAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn8zAAMRAAgJ1CSdAQDTAgARAAgJ1CSdAQDTAgASAAEJdR2iRABNAAABLgAECgkJNQATAP8hAA==.Damasscus:BAAALgAECgcJDQAAAA==.Darkdesire:BAAALgADCgUJBQAAAA==.',
Di='Disney:BAABLgAECn8WAAIIAAcJsRLOCgCDAQAIAAcJsRLOCgCDAQAAAA==.',
Dj='Djaztech:BAABLgAECn8iAAMHAAkJDSICEAA8AgAHAAgJICECEAA8AgAQAAcJUBp8DQDIAQAAAA==.',
Do='Donkie:BAABLgAECn8eAAIKAAcJ+R8wKwDsAQAKAAcJ+R8wKwDsAQAAAA==.',
Dr='Dracsano:BAAALgAECgQJBwABLgAECggJFAAGANkIAA==.Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAABLgAECn84AAMNAAkJ1x81BAA2AwANAAkJ1x81BAA2AwAMAAgJ9wlxEgAoAQAAAA==.',
Ds='Dsakony:BAABLgAECn8WAAIUAAkJZhRigQBAAQAUAAkJZhRigQBAAQAAAA==.',
Du='Duskdruid:BAAALgAECgUJBQAAAA==.Duthir:BAACLgAFFH8IAAIFAAMJ6gyqbADlAAAFAAMJ6gyqbADlAAAuAAQKfygAAgUACQkfHc8/ADkCAAUACQkfHc8/ADkCAAEuAAQKCQkXABUA0RYA.',
Ea='East:BAAALgAECgYJEwAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAAALgAECgcJEwAAAA==.',
Em='Emaeel:BAABLgAECn8UAAQWAAgJpRCtJACIAQAWAAgJpRCtJACIAQAXAAUJNBATVADBAAAYAAEJpwE7jwAWAAAAAA==.',
En='Envyqt:BAAALgADCgEJAQAAAA==.',
Es='Esso:BAACLgAFFH8LAAIFAAQJmw7ZQwA3AQAFAAQJmw7ZQwA3AQAuAAQKfxgAAgUABwluF9pKAKkBAAUABwluF9pKAKkBAAAA.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8XAAICAAcJiwk8qAAxAQACAAcJiwk8qAAxAQAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJEAAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDgAAAA==.Fizzlewar:BAAALgADCgIJAgABLgAECgcJLgACAM0fAQ==.',
Fo='Foros:BAABLgAECn8cAAIOAAcJbiUsEACSAgAOAAcJbiUsEACSAgAAAA==.',
Fr='Frozone:BAABLgAECn8jAAIUAAgJSRgyPwDnAQAUAAgJSRgyPwDnAQAAAA==.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAABLgAECn8nAAIZAAgJTwnfCQBHAQAZAAgJTwnfCQBHAQAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECggJEAAaAAAAAA==.',
Ge='Gendorosan:BAABLgAECn8nAAIbAAgJRSLRBwAJAwAbAAgJRSLRBwAJAwAAAA==.',
Gn='Gnork:BAAALgAECgcJEQABLgAFFAIJAgAaAAAAAA==.',
Go='Goldwolf:BAAALgADCgYJBgAAAA==.Gotarrnianan:BAAALgAECgEJAwAAAA==.Gothpally:BAAALgAECgQJBAAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Gravewurm:BAAALgAECgEJAQAAAA==.Grayfoxx:BAABLgAECn8lAAIFAAgJyxpILgALAgAFAAgJyxpILgALAgAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgADCgQJBAAAAA==.Grìmmgor:BAACLgAFFH8TAAIcAAQJTSJcAgB7AQAcAAQJTSJcAgB7AQAuAAQKfysAAhwACQmDIkwAAIgDABwACQmDIkwAAIgDAAAA.',
Gu='Guerriera:BAAALgAECgYJBgAAAA==.Gulkenn:BAAALgADCgcJBwAAAA==.',
['Gô']='Gôôdbye:BAAALgAECgYJCgAAAA==.',
['Gö']='Gööse:BAAALgAECggJDAAAAA==.',
Ha='Hado:BAAALgAECgQJBAAAAA==.Halbrand:BAACLgAFFH8GAAIFAAIJKAoVnACVAAAFAAIJKAoVnACVAAAuAAQKfxsAAgUACAm5GRdQAJoBAAUACAm5GRdQAJoBAAEuAAUUBAkJAB0AZhYA.Hamburgmeat:BAAALgADCgYJBQAAAA==.',
He='Healovathyme:BAACLgAFFH8IAAIbAAIJqSCRLgDCAAAbAAIJqSCRLgDCAAAuAAQKfxkAAhsACAlxIugVAIcCABsACAlxIugVAIcCAAAA.Hellstomper:BAAALgAECgQJDQAAAA==.Heygrlhey:BAABLgAECn82AAMKAAkJnyOMBQAKAwAKAAkJnyOMBQAKAwALAAQJRwe0YAC+AAAAAA==.',
Hi='Hidaoushi:BAAALgADCgkJCQAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECgkJNgAPAEAhAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAABLgAECn8dAAIKAAgJxhpeJQAHAgAKAAgJxhpeJQAHAgAAAA==.Hurtzdonit:BAAALgADCgIJAgAAAA==.',
Hv='Hvtn:BAAALgAECgYJEAAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
In='Inebriated:BAABLgAECn8bAAIKAAgJIgv+WgBKAQAKAAgJIgv+WgBKAQAAAA==.',
Io='Iondia:BAAALgAECgQJCgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.',
Iz='Izanami:BAAALgAECgEJAQAAAA==.',
Ja='Jambi:BAAALgAECgUJCQAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Johnconnor:BAAALgADCgQJBAAAAA==.Jolty:BAAALgAECgcJCAABLgAFFAQJDwAFACUeAA==.',
Ka='Kael:BAAALgAECgQJBwAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgQJBAAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAAaAAAAAA==.',
Ke='Kermitted:BAAALgAECgEJAgABLgAECgMJBAAaAAAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJBQAAAA==.Kohnan:BAABLgAECn8UAAIGAAgJ2QjScgD3AAAGAAgJ2QjScgD3AAAAAA==.Kotoko:BAABLgAECn8UAAINAAgJdBkaGgAxAgANAAgJdBkaGgAxAgAAAA==.',
Ks='Ksauce:BAABLgAECn8YAAIeAAgJdwKnCQCxAAAeAAgJdwKnCQCxAAAAAA==.',
Ku='Kungfumama:BAAALgAECgEJAQAAAA==.',
Ky='Kynan:BAACLgAFFH8FAAICAAIJ/A3sXACbAAACAAIJ/A3sXACbAAAuAAQKfxYAAwIABwnCGt5JAK0BAAIABwnCGt5JAK0BAAkAAQmfA8BHABMAAAEuAAQKBAkEABoAAAAA.Kynon:BAABLgAECn8ZAAMXAAYJbRTOMABjAQAXAAYJbRTOMABjAQAWAAEJLgFmdwAUAAABLgAECgQJBAAaAAAAAA==.Kyran:BAAALgAECgQJBAAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lament:BAAALgAECggJEwAAAA==.Lamurun:BAAALgAECgQJBAAAAA==.Lancelöt:BAACLgAFFH8IAAICAAMJKSMlKAAzAQACAAMJKSMlKAAzAQAuAAQKf0UAAgIACQlfJEUEADUDAAIACQlfJEUEADUDAAAA.Lastra:BAAALgAECgkJEgABLgAFFAIJAwAaAAAAAA==.Lathina:BAAALgAECgMJBAAAAA==.Lavendere:BAAALgAECgYJEgABLgAECgkJFwAVANEWAA==.',
Le='Lectra:BAAALgADCgEJAQAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAABLgAECn8WAAIUAAgJaAcqfQBIAQAUAAgJaAcqfQBIAQAAAA==.Linnëa:BAAALgAFFAMJBAAAAA==.Linta:BAAALgADCgcJCQAAAA==.Lizardwizard:BAABLgAECn8XAAIfAAgJQRFzJQBvAQAfAAgJQRFzJQBvAQAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.',
Lo='Lockraum:BAAALgAECgMJAwAAAA==.Lokix:BAABLgAECn8nAAIFAAgJkSCKGwBpAgAFAAgJkSCKGwBpAgAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAABLgAECn8nAAIPAAgJfQyKGwAyAQAPAAgJfQyKGwAyAQAAAA==.',
Ma='Magikishi:BAABLgAECn8cAAIUAAgJYR8xOwCKAgAUAAgJYR8xOwCKAgAAAA==.Magimal:BAAALgAECgYJBgABLgAECggJFAAWAKUQAA==.Mahka:BAABLgAECn89AAMbAAkJwh9nEwB2AgAbAAkJwh9nEwB2AgAdAAMJHyOzLgAZAQABLgADCgEJAQAaAAAAAA==.Maldrakesus:BAAALgADCgEJAQABLgAECggJFAAWAKUQAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAAALgADCgkJPgAAAA==.Masika:BAAALgAECgIJAgAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meganstoon:BAAALgAECgMJBAAAAA==.Meladaris:BAAALgAECgQJBwAAAA==.Mey:BAABLgAECn82AAITAAgJ+hzsEQBSAgATAAgJ+hzsEQBSAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgcJEQAAAA==.Mitenalla:BAACLgAFFH8LAAICAAQJ+hIcJAA9AQACAAQJ+hIcJAA9AQAuAAQKfxYAAgIACAm6Gwc7ANoBAAIACAm6Gwc7ANoBAAAA.',
Mo='Morninbreath:BAAALgAECgUJBQAAAA==.',
Mu='Muatahawa:BAAALgAECgMJAgAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBQAAAA==.Mysticraven:BAABLgAECn8UAAIdAAgJFAQjOwDZAAAdAAgJFAQjOwDZAAAAAA==.Mythbredor:BAAALgAECgYJBgAAAA==.',
Na='Naariah:BAAALgADCgcJCAAAAA==.Nagendra:BAACLgAFFH8HAAIfAAQJDxJuHwAZAQAfAAQJDxJuHwAZAQAuAAQKfxwAAh8ACQkaIOgHAPoCAB8ACQkaIOgHAPoCAAAA.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Neoptolemos:BAAALgAECgEJAgAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAABLgAECn8eAAIZAAgJmAYpCwAsAQAZAAgJmAYpCwAsAQAAAA==.Nitrochrist:BAABLgAECn80AAIBAAkJQxUPNQDQAQABAAkJQxUPNQDQAQAAAA==.Nixxy:BAAALgAECgYJBgABLgAFFAUJFQAgAJ8TAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Nokimi:BAAALgAECgQJBAAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAABLgAECn8XAAIfAAYJ7A6nPQDtAAAfAAYJ7A6nPQDtAAAAAA==.Nori:BAACLgAFFH8iAAIUAAcJqiQAAwCHAgAUAAcJqiQAAwCHAgAuAAQKfyoAAxQACQm9JpoAAPwDABQACQm9JpoAAPwDAB4AAwkSILcPAMcAAAAA.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Or='Original:BAAALgAECggJDwAAAA==.Originals:BAAALgAECgYJCAAAAA==.',
Ot='Otome:BAAALgAECggJDQAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAACLgAFFH8HAAIUAAMJcB3MUQAIAQAUAAMJcB3MUQAIAQAuAAQKfyMAAxQACAm2HW0vALQCABQACAm2HW0vALQCACEAAQkdD64QADEAAAAA.Pastries:BAACLgAFFH8cAAIGAAgJ7BtKAgAyAgAGAAgJ7BtKAgAyAgAuAAQKfzcAAwYACQmrIrkCAKUDAAYACQmrIrkCAKUDABIAAgnMFGU4AIEAAAAA.',
Pb='Pbd:BAAALgAECgIJAgAAAA==.',
Pi='Pitlin:BAABLgAECn8jAAIiAAgJAyLPBQDrAgAiAAgJAyLPBQDrAgAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgAAAA==.',
Po='Polynya:BAAALgAECgQJCQAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH8cAAITAAYJViNZAQAxAgATAAYJViNZAQAxAgAuAAQKfzIAAhMACQkWJVkAANYDABMACQkWJVkAANYDAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAABLgAECn8mAAICAAgJFwmzeQA9AQACAAgJFwmzeQA9AQAAAA==.Ragetatertot:BAAALgAECgYJDgAAAA==.Ragingpoo:BAABLgAECn8ZAAIFAAkJlRR5MAADAgAFAAkJlRR5MAADAgAAAA==.Rakenroll:BAAALgADCggJCAAAAA==.Rawsteak:BAABLgAECn8XAAIPAAgJrBcKGQBLAQAPAAgJrBcKGQBLAQAAAA==.Razdaz:BAABLgAECn8ZAAMiAAcJfx3/FQD0AQAiAAYJxhv/FQD0AQATAAcJ1BYqGwCyAQAAAA==.',
Re='Redcrow:BAABLgAECn8VAAIHAAkJbQamMQBFAQAHAAkJbQamMQBFAQAAAA==.Reheal:BAABLgAECn8UAAITAAgJjR0bCQCYAgATAAgJjR0bCQCYAgAAAA==.Reshocker:BAABLgAECn8lAAIjAAkJ5BnJGgA8AgAjAAkJ5BnJGgA8AgAAAA==.Restosexualz:BAAALgAECgMJBAAAAA==.',
Ri='Rixxy:BAACLgAFFH8VAAMgAAUJnxPHCABdAQAgAAUJnxPHCABdAQAfAAEJsAGDSwA4AAAuAAQKfzIAAyAACAmVIkUCAFEDACAACAmVIkUCAFEDAB8ABwmrC8g+AO8AAAAA.',
Ro='Roastbeefdr:BAABLgAECn8+AAMPAAkJvCRIAQA3AwAPAAkJvCRIAQA3AwAFAAQJwR5AnAD2AAAAAA==.Roderigo:BAABLgAECn8dAAIbAAgJtQ+tNACNAQAbAAgJtQ+tNACNAQAAAA==.Root:BAAALgAECgYJEQAAAA==.',
Ru='Runian:BAAALgAECgUJCAAAAA==.',
Sa='Sadlypink:BAABLgAECn8VAAIUAAcJLBRKhwDDAQAUAAcJLBRKhwDDAQAAAA==.Saisaith:BAABLgAECn8XAAMVAAkJ0RaDDQA5AgAVAAkJ0RaDDQA5AgATAAEJZAVBYgAkAAAAAA==.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAABLgAECn8fAAIFAAcJ9hQ8aAC9AQAFAAcJ9hQ8aAC9AQAAAA==.Sandy:BAAALgAECgcJAwAAAA==.Savadar:BAAALgAECgcJDQAAAA==.Saymourcox:BAAALgAECgYJCgAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJFAAJAM4ZAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Serpeng:BAABLgAECn8UAAMSAAgJHxDpGABfAQASAAgJ5g7pGABfAQARAAYJ9QpjEwDRAAAAAA==.Setareh:BAABLgAECn8WAAIUAAcJzwacpgD/AAAUAAcJzwacpgD/AAAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8yAAIUAAkJyw6zSADIAQAUAAkJyw6zSADIAQAAAA==.Shanta:BAAALgADCgMJAwAAAA==.Shkar:BAABLgAECn9FAAIHAAkJnhlhEgAiAgAHAAkJnhlhEgAiAgAAAA==.Shokan:BAAALgAECgQJBAAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAAALgADCggJDAAAAA==.Sildin:BAAALgAECgUJCAAAAA==.Silverclaws:BAAALgADCgkJDgAAAA==.',
Sj='Sjaridin:BAEALgAECgQJDAAAAA==.',
Sk='Skittle:BAABLgAECn8dAAMkAAcJgggwJADBAAAkAAcJgggwJADBAAAbAAUJdAJwhgBwAAAAAA==.Skullhunter:BAABLgAFFH8HAAQLAAYJKR2nEwC6AAALAAQJXiGnEwC6AAAlAAEJ2RUQIgBSAAAKAAEJ3BewYgBRAAAAAA==.',
Sl='Slenderama:BAAALgADCgYJCQAAAA==.Slenderella:BAAALgADCgUJBQAAAA==.',
Sm='Small:BAAALgADCgEJAQAAAA==.Smawbrawl:BAAALgAECggJCQAAAA==.Smoothroller:BAAALgAECgYJCQAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickyricky:BAAALgADCgUJCgAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn88AAIUAAkJRhY0MwASAgAUAAkJRhY0MwASAgAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAUJFwAYACMcAA==.',
['Sä']='Sämuel:BAAALgAECgEJAQAAAA==.',
Ta='Tanks:BAAALgADCgEJAgAAAA==.',
Th='Thelorax:BAABLgAECn8XAAIGAAkJCww5SABtAQAGAAkJCww5SABtAQAAAA==.Theyeti:BAAALgADCgEJAgABLgADCgcJDQAaAAAAAA==.Thhee:BAABLgAECn8mAAImAAgJ7RfHEQDTAQAmAAgJ7RfHEQDTAQAAAA==.Thumbelyna:BAABLgAECn8jAAMbAAgJtRs0GABIAgAbAAgJtRs0GABIAgAkAAEJMQrzNQAeAAAAAA==.',
Ts='Tsuro:BAAALgAECgYJCAAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAAALgAECgcJEQAAAA==.',
Up='Up:BAABLgAECn8VAAIRAAcJVB/nBABjAgARAAcJVB/nBABjAgAAAA==.',
Va='Valasi:BAAALgAECgEJAwAAAA==.',
Ve='Velocet:BAACLgAFFH8LAAImAAQJ0QlpFAApAQAmAAQJ0QlpFAApAQAuAAQKfzcAAyYACQm0GrgOAPkBACYACQm0GrgOAPkBAAgAAwmICL0WAIsAAAAA.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8pAAICAAkJlCLJCwDZAgACAAkJlCLJCwDZAgAAAA==.Waghiechan:BAAALgAECgcJDQAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAECgYJEAAaAAAAAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAACLgAFFH8LAAIYAAQJ+hgxEwA8AQAYAAQJ+hgxEwA8AQAuAAQKfzwAAxgACQm3HgUFAMQCABgACQm3HgUFAMQCABcAAgmxC8h7AC4AAAAA.',
Wu='Wuji:BAABLgAECn8mAAIiAAgJkwx+HgCNAQAiAAgJkwx+HgCNAQAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgAECgYJBgAAAA==.',
Ye='Yeli:BAAALgAECgYJBwAAAA==.',
Ze='Zenaf:BAAALgAECgUJBwAAAA==.Zeryph:BAAALgADCgYJCwABLgAECgkJIgAEAL8eAA==.',
Zi='Zimbabway:BAAALgAECgYJBwAAAA==.',
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
