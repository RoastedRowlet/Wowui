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

local lookup = {'Paladin-Protection','Shaman-Restoration','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Blood','DeathKnight-Unholy','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Mage-Frost','Mage-Fire','Unknown-Unknown','Monk-Brewmaster','Paladin-Retribution','Warrior-Protection','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Frost','Hunter-Survival','Monk-Mistweaver','Shaman-Elemental','Warrior-Fury','DemonHunter-Vengeance','Shaman-Enhancement','DemonHunter-Havoc','Evoker-Preservation','Hunter-Marksmanship','Monk-Windwalker','Druid-Guardian','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Druid-Feral','Mage-Arcane','Paladin-Holy','Warrior-Arms','Rogue-Assassination',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Adhenar:BAAALgAECgMJAwAAAA==.Adow:BAAALgAECgUJBQAAAA==.Adynne:BAAALgAECgYJBgABLgAECgcJGgABADsfAA==.',
Ae='Aered:BAAALgAECgUJCwAAAA==.Aerylith:BAAALgAECgYJCgAAAA==.',
Af='Aften:BAAALgAECgYJCAAAAA==.',
Ah='Ahira:BAABLgAECn80AAICAAkJqiLIBABDAwACAAkJqiLIBABDAwAAAA==.',
Ai='Ailov:BAAALgADCgMJAwAAAA==.',
Ak='Akuria:BAABLgAECn8qAAIDAAkJWhobDABtAgADAAkJWhobDABtAgAAAA==.',
Al='Alacía:BAAALgADCgcJBwAAAA==.Alahna:BAABLgAECn8UAAIEAAgJVgUxeAAgAQAEAAgJVgUxeAAgAQAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAABLgAECn88AAMFAAkJKA0qGQBmAQAFAAkJKA0qGQBmAQAGAAUJvwJa+gCHAAAAAA==.Antamoon:BAAALgAECgUJCwAAAA==.',
Ao='Aox:BAABLgAECn8mAAIHAAkJfRr2CgBSAgAHAAkJfRr2CgBSAgAAAA==.',
Aq='Aquarian:BAAALgAECgYJCwAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgUJCwAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgAECgMJAwAAAA==.Asseroth:BAAALgAECgEJAQAAAA==.',
At='Atriux:BAAALgAECgkJCAAAAA==.',
Au='Aureline:BAABLgAECn80AAMIAAkJXRN3LgDIAQAIAAkJXRN3LgDIAQAJAAQJpAU1VgCFAAAAAA==.Aurna:BAAALgAFFAEJAQAAAA==.',
Ba='Babegnome:BAAALgAECgEJAgAAAA==.Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgcJEQAAAA==.',
Be='Beartank:BAAALgADCgYJBgAAAA==.Beastiam:BAAALgAECgEJAQAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgADCgUJCAAAAA==.Belserion:BAACLgAFFH8OAAIKAAQJVhjWGABnAQAKAAQJVhjWGABnAQAuAAQKf1cAAwoACQnoJVgCAHQDAAoACQnoJVgCAHQDAAsAAQndITMMAFoAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECgkJHwAKABofAA==.Bernir:BAAALgAECgIJAgAAAA==.Berol:BAAALgAECgYJDgAAAA==.Beroldin:BAAALgADCgIJAgABLgAECgYJDgAMAAAAAA==.Bevar:BAAALgADCgkJDQABLgAECgUJDAAMAAAAAA==.Bevell:BAAALgADCgQJBAABLgAECgUJDAAMAAAAAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAINAAYJoB7QJQDVAQANAAYJoB7QJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAABLgAECn8WAAIFAAkJjh/KBADCAgAFAAkJjh/KBADCAgAAAA==.Biggieshan:BAAALgAECgUJBQAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAwAAAA==.Blindmafaka:BAAALgAECgYJCwAAAA==.Blkrend:BAABLgAECn9EAAIFAAkJKybmAABQAwAFAAkJKybmAABQAwAAAA==.Blurtaxes:BAAALgAECgcJAgAAAA==.',
Bo='Bonko:BAAALgAECgMJAwAAAA==.',
Br='Bradycam:BAABLgAECn8yAAIOAAkJYRvsFgCbAgAOAAkJYRvsFgCbAgAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brewmaster:BAAALgAECgcJCAAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruceelee:BAAALgADCgMJAwAAAA==.Bruddah:BAAALgAFFAIJAwABLgAFFAMJDAAPAPMKAA==.',
Bu='Bulloo:BAAALgAECgEJAgAAAA==.',
['Bó']='Bóbafett:BAAALgADCgEJAQAAAA==.',
Ca='Cadovenia:BAAALgAECgEJBAAAAA==.Camillerose:BAAALgAECgQJBAAAAA==.Cantpalyhard:BAAALgAECgQJBAABLgAECgkJPAACAHQcAA==.Carebeär:BAABLgAECn8aAAIIAAcJ6hcYNgDPAQAIAAcJ6hcYNgDPAQAAAA==.Casella:BAABLgAECn8/AAINAAkJkSD4BADZAgANAAkJkSD4BADZAgAAAA==.',
Ce='Celissara:BAAALgAECgUJDwABLgAFFAEJAQAMAAAAAA==.',
Ch='Chimken:BAAALgADCgMJAwAAAA==.Chogori:BAAALgAECgMJCQAAAA==.Chôsenône:BAAALgAECgUJBgAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAABLgAECn8jAAIOAAgJfh3jIQBfAgAOAAgJfh3jIQBfAgAAAA==.Clouzot:BAAALgADCgUJBwAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAABLgAECn8oAAIQAAgJUAmnCgBPAQAQAAgJUAmnCgBPAQAAAA==.',
Cp='Cptbarnacles:BAABLgAECn8ZAAQRAAYJ1Q6dIgBxAAASAAQJRQ2DqgDVAAARAAMJzwydIgBxAAATAAMJ5QxlIwBlAAAAAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBwAUACEdAA==.Crunchylock:BAAALgAECggJDAAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Damachi:BAABLgAECn8rAAMVAAgJ7BhVBgAAAgAVAAgJihhVBgAAAgAGAAgJ5xC9YwB8AQAAAA==.Danskan:BAAALgAECgYJDQAAAA==.Darkvale:BAAALgAECgYJCQAAAA==.Darkñess:BAAALgAECggJDQAAAA==.Darmorae:BAABLgAECn8jAAIWAAkJsRUBEQALAgAWAAkJsRUBEQALAgAAAA==.Dashii:BAAALgAECgEJAgAAAA==.Datewoo:BAABLgAECn8ZAAIOAAYJLQ94qwAEAQAOAAYJLQ94qwAEAQAAAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deef:BAAALgAECgUJBQAAAA==.Demilia:BAAALgAECgQJBAAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desadeness:BAAALgADCgMJBQABLgADCgkJMAAMAAAAAA==.Desertpunk:BAAALgAECgEJAQAAAA==.Destrolock:BAAALgAECgYJCwAAAA==.Devoroyal:BAAALgAECgcJEQAAAA==.Dez:BAAALgAECgUJBQABLgAECgkJJQAGAKUHAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECgUJCwAAAA==.',
Do='Donkaßutts:BAAALgAECgQJCQAAAA==.Dooda:BAAALgAECgQJCgAAAA==.Doodooboi:BAAALgADCgMJAwAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECgUJCQAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECgcJGgABADsfAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracbow:BAAALgAECggJDgABLgAECgkJFQAGACgPAA==.Dracfu:BAABLgAECn8XAAIXAAgJpgdjRQD9AAAXAAgJpgdjRQD9AAABLgAECgkJFQAGACgPAA==.Drackpally:BAAALgAECgcJAgAAAA==.Dracserion:BAAALgAECgYJBwABLgAFFAQJDgAKAFYYAA==.Dracsknight:BAABLgAECn8VAAIGAAkJKA8iRADUAQAGAAkJKA8iRADUAQAAAA==.Dracslana:BAAALgAECgUJCwABLgAECgkJFQAGACgPAA==.Draffel:BAABLgAECn8hAAMCAAkJuxtYDgC5AgACAAkJuxtYDgC5AgAYAAEJxQG2nwAVAAAAAA==.Drathi:BAABLgAECn8WAAIFAAcJ4g+hIgAPAQAFAAcJ4g+hIgAPAQAAAA==.Drestla:BAAALgAECgcJCwAAAA==.Drowgon:BAABLgAECn8WAAMZAAcJXxf9LAB4AQAZAAcJXxf9LAB4AQAPAAYJgA1iLACvAAAAAA==.Druwgon:BAAALgAECgEJAQAAAA==.',
Du='Duartor:BAAALgAECgIJAgAAAA==.Dukalune:BAAALgAECgUJCQAAAA==.Dukaos:BAACLgAFFH8NAAIUAAQJNQ36PgABAQAUAAQJNQ36PgABAQAuAAQKfzUAAxQACAmgHegfADcCABQACAmgHegfADcCABoABAlCDWQaAMEAAAAA.Dunzer:BAABLgAECn8+AAMOAAkJFhnwJABQAgAOAAkJFhnwJABQAgABAAIJQwlYOwBJAAAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAABLgAECn8cAAIIAAgJ1xmKHAA+AgAIAAgJ1xmKHAA+AgAAAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgAECgEJAQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8fAAIKAAgJGh/wOgCLAgAKAAgJGh/wOgCLAgAAAA==.',
Eh='Ehonda:BAAALgAECgUJBQABLgAECgcJFgAFAAYPAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAABLgAECn8YAAIbAAkJqh8PBQC6AgAbAAkJqh8PBQC6AgAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAAALgAECgQJCQAAAA==.Emolock:BAAALgAECgUJBQAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgADCgcJBwAAAA==.',
Eo='Eon:BAAALgAECgUJDwAAAA==.',
Ep='Epiphaný:BAAALgAECgYJCwAAAA==.',
Er='Eradoria:BAABLgAECn8UAAIcAAYJQgXmRADiAAAcAAYJQgXmRADiAAAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgAECgQJBAAAAA==.',
Es='Essylt:BAAALgAECgEJAwAAAA==.Este:BAAALgADCgQJBAAAAA==.',
Ev='Evadne:BAAALgAECgcJCAAAAA==.Evagrius:BAAALgAECgUJBQAAAA==.Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAABLgAECn8aAAIdAAkJzgkVEgCEAQAdAAkJzgkVEgCEAQAAAA==.',
Ex='Exidore:BAAALgAECgcJDAAAAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAAMAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Falchionx:BAAALgAECgUJCwABLgAECggJHAAIANcZAA==.Falfogan:BAAALgAECgEJAgAAAA==.Fangy:BAAALgAECgIJAwAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felserion:BAAALgADCgEJAgABLgAFFAQJDgAKAFYYAA==.Fenn:BAABLgAECn8xAAIYAAkJLBk6DwBXAgAYAAkJLBk6DwBXAgAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Fistantillus:BAAALgAECgcJCgAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flopper:BAAALgAECgYJCwAAAA==.',
Fo='Fonddle:BAAALgADCgUJCQAAAA==.Foxyboo:BAABLgAECn88AAMCAAkJdBzyCQDtAgACAAkJdBzyCQDtAgAYAAEJ8wUvmQAiAAAAAA==.',
Fr='Freak:BAABLgAECn8YAAMIAAgJHhL5OgCGAQAIAAgJHhL5OgCGAQAJAAYJsgk6TQD1AAAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.Frorly:BAAALgAECgEJAQAAAA==.',
Fu='Fulv:BAAALgAECgUJEAAAAA==.',
['Fâ']='Fâith:BAAALgAECgQJCQAAAA==.',
Ga='Gaezßuleaux:BAAALgAECgEJAQAAAA==.Galerodra:BAAALgADCgEJAQAAAA==.Galorani:BAAALgADCgIJAgAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAAALgAECgcJDQAAAA==.',
Ge='Gertroz:BAAALgAECgQJBgABLgAFFAEJAQAMAAAAAA==.',
Gi='Gimic:BAAALgAECggJCAAAAA==.',
Gn='Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn8uAAIEAAkJLSXHAgBOAwAEAAkJLSXHAgBOAwAAAA==.Gope:BAABLgAECn8lAAMCAAkJRBdPGgBLAgACAAkJRBdPGgBLAgAYAAQJ3gZMdgBpAAAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Green:BAABLgAECn8WAAIWAAgJSxcbCQBUAgAWAAgJSxcbCQBUAgAAAA==.Grewsome:BAAALgADCgcJBwAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn8uAAMWAAkJSyKfAwDmAgAWAAkJdCGfAwDmAgAeAAgJ3R0MEgCoAgAAAA==.Gromyr:BAAALgAECgEJAQABLgAECgkJLgAWAEsiAA==.Grr:BAABLgAECn8rAAIUAAkJZiGoCADyAgAUAAkJZiGoCADyAgAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gó']='Gójira:BAAALgAECgYJCgAAAA==.',
Ha='Hartis:BAABLgAECn8sAAQEAAkJERDKLgD2AQAEAAkJERDKLgD2AQAWAAIJqwQUSQBcAAAeAAQJ5wBdewBWAAAAAA==.Hashmal:BAAALgAECgQJBAAAAA==.Hazo:BAABLgAECn8eAAMNAAYJOwnOVgCPAAANAAUJMQrOVgCPAAAfAAMJqAQbbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Hectabali:BAAALgADCgYJBQAAAA==.Heizou:BAAALgAECgYJBgAAAA==.Hellkat:BAAALgAECgUJBwAAAA==.',
Hi='Higarosa:BAAALgADCgIJAwAAAA==.Highbull:BAAALgAECgUJBQAAAA==.Hild:BAAALgAECgkJAQAAAA==.',
Ho='Holiblade:BAABLgAECn83AAIOAAgJ7gmQhwBAAQAOAAgJ7gmQhwBAAQAAAA==.Holyfaxiss:BAEALgAECgcJCgABLgAECgcJGwAZAEsiAA==.Holyhannah:BAAALgAECgUJBgAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJCgAAAA==.Hooligun:BAABLgAECn8qAAIYAAgJRRAvMABRAQAYAAgJRRAvMABRAQAAAA==.Hoppered:BAAALgAECgEJAQABLgAECgkJOwATAOAiAA==.',
Hu='Huntinpowerz:BAAALgAECgEJAQAAAA==.Huntlord:BAAALgADCgcJBwAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAABLgAECn8TAAIEAAkJSBt1PgC1AQAEAAkJSBt1PgC1AQAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAABLgAECn8iAAIBAAcJ9RAmFgBEAQABAAcJ9RAmFgBEAQAAAA==.',
Ih='Ihatereports:BAAALgAECgQJCAABLgAFFAMJBQAEAHgHAA==.',
Ij='Ijustshotyou:BAACLgAFFH8FAAMEAAMJeAelYQCPAAAEAAIJzAelYQCPAAAWAAIJiwSLIgCKAAAuAAQKfxUABB4ACAl4D5oSAAwBAB4ABwnNDpoSAAwBABYAAglBDlVEAHoAAAQAAgm+DhrKAG0AAAAA.',
Il='Illyría:BAAALgADCgcJBwAAAA==.Ilovetouka:BAAALgAECgMJBAAAAA==.',
Ir='Ironlotss:BAAALgADCgkJDQAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAECggJJgASAMQeAA==.Jakob:BAAALgAECgEJAgAAAA==.Jaks:BAAALgADCgEJAQAAAA==.Jardal:BAAALgADCgUJDAAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAABLgAECn8fAAIEAAYJmxGqegAbAQAEAAYJmxGqegAbAQAAAA==.Jenanila:BAAALgAECgMJBAAAAA==.',
Ji='Jibbs:BAABLgAECn8lAAMGAAkJpQfhfgA/AQAGAAgJXQjhfgA/AQAFAAEJmAKOVgAZAAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwAMAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJEAAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jolah:BAAALgAECgIJAgAAAA==.Jollakeratu:BAABLgAECn8oAAIgAAgJ9BLbEwB8AQAgAAgJ9BLbEwB8AQAAAA==.Jonnygordo:BAAALgAECgYJEwAAAA==.Jorahh:BAABLgAECn8XAAMYAAcJHRYLKwBuAQAYAAYJHRYLKwBuAQACAAcJ2QysYAAJAQAAAA==.',
Ju='Jugram:BAAALgAECgMJAwAAAA==.Jungolv:BAAALgADCgMJAwAAAA==.Jusmissiner:BAABLgAECn8eAAIEAAgJ8h5yFgCEAgAEAAgJ8h5yFgCEAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAABLgAECn8cAAIFAAgJzBu9EQDBAQAFAAgJzBu9EQDBAQAAAA==.',
['Jø']='Jønty:BAAALgADCgUJDAAAAA==.',
Ka='Kaelyra:BAAALgADCgUJDAAAAA==.Kaitenn:BAAALgAECgYJBgAAAA==.Kamehame:BAAALgAECggJEgAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECgkJMwACANUhAA==.',
Ke='Keelhorn:BAABLgAECn8kAAMCAAkJGRSDKQDoAQACAAkJGRSDKQDoAQAYAAIJDQeTeABPAAAAAA==.Kenneth:BAAALgAECgIJBAAAAA==.Kevin:BAAALgAECgYJDAABLgAFFAUJCAAJAJQUAA==.Keyadorath:BAAALgADCgIJAgAAAA==.',
Ki='Kibon:BAABLgAECn8ZAAMRAAYJsgZXIQB7AAASAAYJ9AXNrQDPAAARAAQJfgRXIQB7AAAAAA==.Kinkyhawt:BAEBLgAECn8WAAMhAAYJkh2vJACWAQAhAAYJ+RyvJACWAQAQAAUJchuiFQCUAQAAAA==.Kirio:BAAALgADCgcJCgAAAA==.Kitsunenohi:BAABLgAECn8cAAIcAAgJCAR4LgDUAAAcAAgJCAR4LgDUAAAAAA==.',
Ko='Kodiakk:BAABLgAECn8cAAIWAAYJwRXeJgBFAQAWAAYJwRXeJgBFAQAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Kramden:BAAALgADCgkJEwAAAA==.Krattos:BAAALgAECgIJAwAAAA==.Krimzin:BAAALgAECgEJAQABLgAFFAUJFAAEAF8fAA==.',
Ks='Ksares:BAAALgAECgIJAgABLgAECgkJRwAEAMohAA==.',
Ku='Kuddles:BAAALgADCgEJBgAAAA==.Kumei:BAAALgAECgEJAQABLgAECgkJLAAEABEQAA==.Kural:BAAALgAECgUJBgABLgAECggJKAABAJsjAA==.',
Kw='Kwazii:BAABLgAECn8mAAQiAAgJ/BdSGADjAQAiAAgJ/BdSGADjAQADAAYJ+wXQRADQAAAjAAIJJAVfVwBWAAAAAA==.',
Ky='Kyantzmi:BAAALgAECgYJDQAAAA==.Kyogre:BAAALgAECgYJEwAAAA==.',
La='Laefnia:BAABLgAECn8kAAUJAAkJKxZqGgDJAQAJAAgJshZqGgDJAQAIAAYJ2hK0ZQAhAQAgAAEJ8hLwUgAzAAAkAAEJNAZ9NQAuAAAAAA==.Laraydra:BAAALgAECgUJDAABLgAFFAEJAQAMAAAAAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJGQAfAD4QAA==.Lavaburstya:BAAALgAECgcJDAAAAA==.',
Le='Leomist:BAABLgAECn8WAAIXAAgJyg1oMQBhAQAXAAgJyg1oMQBhAQAAAA==.Leviosä:BAABLgAECn81AAIKAAkJTxbSKwBNAgAKAAkJTxbSKwBNAgAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgADCgkJHQAAAA==.Lilis:BAAALgADCgcJCwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8uAAIGAAkJZCQ5CAAVAwAGAAkJZCQ5CAAVAwAAAA==.Liten:BAAALgADCgUJDAAAAA==.Littlebev:BAAALgAECgUJDAAAAA==.',
Lo='Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJBwAAAA==.Longshankss:BAAALgAECgUJDAAAAA==.',
Ly='Lynaiya:BAAALgADCgMJAwAAAA==.',
['Lí']='Lírii:BAAALgAECgcJEQAAAA==.',
['Lô']='Lôôbmeup:BAAALgADCgEJAQAAAA==.',
Ma='Maachen:BAAALgAECgYJCwAAAA==.Maalik:BAABLgAECn9DAAQTAAgJYSBiAwBQAgATAAgJESBiAwBQAgARAAcJfxpyBwCuAQASAAMJgw543gByAAAAAA==.Magejackky:BAAALgAECgQJCAAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Maivorkeru:BAAALgAECgMJAwAAAA==.Malaurray:BAABLgAECn8fAAISAAgJ+AotZwBYAQASAAgJ+AotZwBYAQABLgABCgQJBgAMAAAAAA==.Maluin:BAAALgAECgEJAQAAAA==.Mavanta:BAAALgAECgMJBAAAAA==.Mayonæse:BAAALgAECgkJDwAAAA==.',
Mc='Mcchong:BAAALgAECgMJAwAAAA==.Mckennah:BAABLgAECn8aAAMBAAcJOx83CgD6AQABAAcJOx83CgD6AQAOAAEJDgzhXwEyAAAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAECgcJIwAKAIEVAA==.Mereidith:BAABLgAECn8jAAMKAAcJgRXziQBHAQAKAAcJcRTziQBHAQAlAAEJchoTGQBPAAAAAA==.Meshulk:BAAALgAECgEJAQAAAA==.Mesohungry:BAABLgAECn8pAAMmAAgJrgeWQQATAQAmAAgJrgeWQQATAQAOAAIJzAFPdwEoAAAAAA==.Metasploit:BAAALgAECgkJAQAAAA==.',
Mi='Mikehunte:BAAALgAECgYJBgABLgAECgkJHwAKABofAA==.Miriya:BAABLgAECn8jAAINAAkJyCSkAQA/AwANAAkJyCSkAQA/AwAAAA==.Missnoms:BAAALgAECgEJAQAAAA==.',
Mo='Monkeycheese:BAABLgAECn8ZAAIfAAcJPhAcLwAiAQAfAAcJPhAcLwAiAQAAAA==.Moobáca:BAAALgAECgUJBwAAAA==.Moostradamas:BAABLgAECn8cAAMVAAgJ7wWoFQDjAAAVAAgJ7wWoFQDjAAAGAAIJsgB1VwEgAAAAAA==.Morcilla:BAAALgAECggJEAAAAA==.Morticyde:BAAALgAECgMJAwAAAA==.',
Ms='Msg:BAABLgAECn8kAAIIAAkJrBsrEQCnAgAIAAkJrBsrEQCnAgAAAA==.',
Mu='Munassa:BAAALgADCgcJBwAAAA==.Muppets:BAAALgAECgUJCQAAAA==.',
My='Myssidia:BAAALgADCgUJCwAAAA==.',
['Mí']='Mínervä:BAAALgAECgkJCQAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgIJAwAAAA==.Nastrodamus:BAAALgAECgEJAQAAAA==.Naturegoob:BAABLgAECn8bAAMIAAgJphogNADYAQAIAAgJphogNADYAQAJAAMJ4RHrTgCgAAAAAA==.Naughtynurse:BAABLgAECn8vAAIIAAkJyxBKLADVAQAIAAkJyxBKLADVAQAAAA==.',
Ne='Nemrak:BAAALgAFFAIJAgAAAA==.Neuma:BAABLgAECn8UAAIOAAQJBAvP2ADBAAAOAAQJBAvP2ADBAAAAAA==.',
Ni='Nicfurry:BAAALgADCgMJAwAAAA==.Nightflower:BAABLgAECn8kAAMlAAkJUwUhDwDRAAAKAAcJGQWYrwAHAQAlAAYJAwQhDwDRAAAAAA==.',
No='Noided:BAAALgAECgYJCgAAAA==.Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgYJDgABLgAECgYJEAAMAAAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
Ob='Obiejuan:BAABLgAECn9IAAMOAAkJ2SJ3CQADAwAOAAkJ2SJ3CQADAwABAAQJoB79GwAJAQAAAA==.Obietide:BAAALgAECgYJCAABLgAECgkJSAAOANkiAA==.',
Od='Oddball:BAABLgAECn8eAAIYAAkJBhx0EwAlAgAYAAkJBhx0EwAlAgAAAA==.',
Of='Ofthecircle:BAAALgAECggJEwAAAA==.',
Ok='Okamiblooded:BAAALgAECgYJCgAAAA==.',
Ol='Olly:BAAALgAECgUJBQAAAA==.',
On='Ontala:BAAALgADCgYJBgAAAA==.',
Oo='Oodles:BAAALgAECgYJEQAAAA==.',
Or='Orangecrush:BAAALgADCgMJAwAAAA==.Orangekeg:BAAALgAECgUJEQABLgAECgkJIAAYANgfAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAAALgAECgQJCwAAAA==.',
Pa='Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn82AAIFAAkJXh1DCABsAgAFAAkJXh1DCABsAgABLgAECggJKAABAJsjAA==.Peso:BAAALgAECgQJBwAAAA==.Pez:BAAALgAECgEJAQABLgAECgkJLgAIAA0WAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAABLgAFFH8RAAIXAAYJfRGNEACTAQAXAAYJfRGNEACTAQABLgAFFAQJCAAmAGESAA==.Pomater:BAAALgAECgQJBgABLgAFFAEJAQAMAAAAAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAABLgAECn8YAAIKAAgJOQlZhQBQAQAKAAgJOQlZhQBQAQAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECgkJLAACALQgAA==.',
Pr='Primafox:BAAALgAECgQJCgAAAA==.Prkchopxpres:BAAALgAECgYJDgAAAA==.Protoheal:BAAALgAECgEJAQAAAA==.',
Pu='Punchandkick:BAAALgAECgMJBgAAAA==.',
Py='Pyrabanks:BAAALgAECgUJBQAAAA==.',
['Pä']='Päw:BAACLgAFFH8FAAMGAAMJbwtVfwDVAAAGAAMJbwtVfwDVAAAVAAEJ8QLbGgA8AAAuAAQKfyQAAwYACAk+GL9EANIBAAYACAlOF79EANIBABUAAQmTHHgkAFMAAAAA.',
Qu='Quetzalcóatl:BAAALgAECgQJBAAAAA==.Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJAgAAAA==.',
Qx='Qx:BAAALgADCggJDgAAAA==.',
Ra='Radge:BAABLgAECn8uAAMnAAkJtSNmAQA3AwAnAAkJsyNmAQA3AwAZAAMJKR0rdgDiAAAAAA==.Rainjar:BAACLgAFFH8JAAMWAAMJrR9zGwC+AAAWAAIJ3x5zGwC+AAAEAAEJSiFobABgAAAuAAQKfzwAAwQACQkAIogMAMkCABYACQlcH14CAB8DAAQACAk3JIgMAMkCAAAA.Rainne:BAAALgADCgcJCAAAAA==.Raistyn:BAABLgAECn8nAAMBAAgJFB4kCwAaAgABAAgJFB4kCwAaAgAOAAEJigwtXAE0AAAAAA==.Ralanar:BAAALgAECgcJDQABLgAFFAEJAQAMAAAAAA==.Raljah:BAABLgAECn87AAQTAAkJ4CKTAAAYAwATAAkJ1CKTAAAYAwASAAcJ7B5mIgA/AgARAAUJXh19FACnAQAAAA==.Ramasus:BAAALgAECgUJBQAAAA==.Rampart:BAABLgAECn8gAAIBAAgJRRfCDADLAQABAAgJRRfCDADLAQAAAA==.Rasaltghul:BAAALgAECgEJAQABLgAECgMJBgAMAAAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.Raxxer:BAAALgAECgEJBAAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAAALgAECgcJEQAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Renm:BAAALgAECgYJEgAAAA==.Renpriest:BAACLgAFFH8RAAIjAAMJfx7ZHgASAQAjAAMJfx7ZHgASAQAuAAQKfxUAAyMACAmMGVIRAC4CACMACAmMGVIRAC4CAAMAAQk4FdVpADsAAAAA.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgUJDAAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.',
Ry='Ryobi:BAABLgAECn8vAAMEAAkJmhQMJwAZAgAEAAkJmhQMJwAZAgAeAAcJdglaFQDrAAAAAA==.Ryptyde:BAAALgAECgkJDQAAAA==.',
['Ræ']='Rævena:BAAALgAECgcJDwAAAA==.',
Sa='Sachaann:BAAALgAECgEJAQAAAA==.Salinan:BAABLgAECn9IAAMTAAkJtyRpAAA0AwATAAkJtyRpAAA0AwASAAQJtRe4rADRAAAAAA==.Saltymon:BAAALgADCgYJBgABLgAECgEJAQAMAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgkJJgAHAH0aAA==.Saric:BAAALgAECgEJAQAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Scanor:BAAALgADCgUJBgABLgAFFAMJCAAhAD8CAA==.Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.',
Se='Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAABLgAECn8eAAIOAAgJIRtAJwBEAgAOAAgJIRtAJwBEAgAAAA==.Selky:BAAALgADCgcJCgAAAA==.',
Sf='Sfodin:BAABLgAECn8WAAIZAAcJgwg4QQAXAQAZAAcJgwg4QQAXAQAAAA==.',
Sh='Shadowkings:BAAALgAECgMJBAAAAA==.Shak:BAAALgAECgYJDQAAAA==.Shalai:BAAALgADCgMJAwAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shastix:BAAALgAECgYJCwABLgAECggJQwATAGEgAA==.Shellingtun:BAAALgAECgYJCwAAAA==.Shyandrial:BAAALgADCgkJIQAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAABLgAECn8fAAIDAAgJ4QkdLABMAQADAAgJ4QkdLABMAQAAAA==.',
Sk='Skilltotem:BAAALgAECgkJEAAAAA==.Skk:BAAALgADCggJCQAAAA==.Sksteve:BAAALgAECgUJDwAAAA==.Skullyy:BAAALgAECgYJDAABLgAECgYJEAAMAAAAAA==.Skychades:BAAALgAECgYJDgAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAABLgAECn8cAAIJAAcJohCxLwAwAQAJAAcJohCxLwAwAQAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECgYJBwABLgAECgcJHAAJAKIQAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgAECgcJDQAAAA==.Soulsrequiem:BAABLgAECn8dAAIoAAgJdwGiFwCHAAAoAAgJdwGiFwCHAAAAAA==.',
Sp='Spicyblaster:BAABLgAFFH8FAAIKAAMJdAQGcwDIAAAKAAMJdAQGcwDIAAAAAA==.Spookydeath:BAACLgAFFH8LAAIKAAMJSgrPbQDZAAAKAAMJSgrPbQDZAAAuAAQKfy0AAgoACQlUEi09AAoCAAoACQlUEi09AAoCAAAA.',
Sr='Srsnacksalot:BAABLgAECn8jAAIOAAgJTRaCSQDLAQAOAAgJTRaCSQDLAQAAAA==.',
St='Stileto:BAAALgAECgcJDgAAAA==.Stoneydracco:BAABLgAECn8WAAIKAAYJDBImkwA3AQAKAAYJDBImkwA3AQAAAA==.Stoneydragon:BAAALgADCgYJBgAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECgUJCwAAAA==.',
Su='Sukiliana:BAAALgAECgMJBAAAAA==.Sumtinwng:BAABLgAECn8tAAIOAAgJdRDxYwCIAQAOAAgJdRDxYwCIAQAAAA==.Supervicious:BAABLgAECn8YAAIPAAgJZBXOFAB9AQAPAAgJZBXOFAB9AQAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgUJDAAAAA==.Sylenne:BAABLgAECn8uAAIIAAkJDRZCGwBIAgAIAAkJDRZCGwBIAgAAAA==.Sylur:BAAALgAECgcJDQABLgAECggJHAAIANcZAA==.',
Ta='Taemea:BAAALgAECggJEgAAAA==.Tahran:BAAALgAECgEJAQABLgAFFAUJFQAjAMkUAA==.Tahren:BAACLgAFFH8VAAQjAAUJyRSUFAB6AQAjAAUJmRGUFAB6AQADAAIJZgsCJACYAAAiAAEJvCXAJABpAAAuAAQKfycABCIACQmIIHMQAGECACIABwn0IHMQAGECACMACQlvE5UoAF4BAAMABgklD51PAJ8AAAAA.Talanima:BAAALgADCgcJBwAAAA==.Taler:BAAALgAECgUJBQAAAA==.Talerion:BAAALgAECgYJEQAAAA==.Tanzanitia:BAAALgAECgYJBgAAAA==.',
Tc='Tcdots:BAAALgAECgEJAQAAAA==.',
Te='Tens:BAABLgAECn8bAAIZAAgJJiNXDAD1AgAZAAgJJiNXDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECgUJCwAAAA==.Theafflictor:BAAALgAECgUJBwAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECgUJCwAMAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thistelbear:BAABLgAECn8nAAIfAAgJqwfLMgAPAQAfAAgJqwfLMgAPAQAAAA==.Thrallsux:BAAALgAECgEJAgAAAA==.Thraun:BAAALgAECgYJEgAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn8vAAMOAAgJBBOiagCpAQAOAAgJBBOiagCpAQABAAcJaAuBHwDoAAAAAA==.',
Ti='Titszilla:BAAALgAECgcJAwAAAA==.',
To='Toki:BAABLgAECn8bAAMXAAYJxxvAIgDBAQAXAAYJxxvAIgDBAQAfAAQJqg+ZTQDbAAAAAA==.Tokidormi:BAAALgAECgcJDgAAAA==.Toralus:BAAALgADCgYJCQAAAA==.Totumm:BAAALgADCgcJCAAAAA==.',
Tr='Tralku:BAAALgAECgcJDAAAAA==.Tremmørs:BAABLgAECn8YAAIYAAcJ0wvyRQDsAAAYAAcJ0wvyRQDsAAAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAAALgAECgkJEQAAAA==.',
Tu='Turnip:BAAALgAECgEJAQAAAA==.',
Tw='Tweak:BAAALgAECgIJAgAAAA==.Tweis:BAAALgADCgUJDAAAAA==.',
Ty='Tyllinor:BAAALgADCgUJBQAAAA==.',
Um='Umbrarogue:BAABLgAECn8dAAMHAAkJCRtdDwASAgAHAAkJoxldDwASAgAoAAEJPh18HABXAAAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEwAAAA==.',
Va='Vaara:BAAALgAECgEJAQAAAA==.Valaa:BAAALgAECgUJBQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAABLgAECn8WAAIOAAkJyA4CcgCYAQAOAAkJyA4CcgCYAQAAAA==.Veliya:BAAALgAECgYJBgABLgAECgkJLgAIAA0WAA==.Vellestrix:BAAALgAECgMJAwAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Vicotr:BAAALgAECgYJBgAAAA==.Viddysouls:BAABLgAECn8dAAIbAAYJnRU2FAA2AQAbAAYJnRU2FAA2AQAAAA==.Viscerai:BAABLgAECn84AAIiAAkJiSWyAADEAwAiAAkJiSWyAADEAwAAAA==.Vite:BAAALgAECgYJDwAAAA==.Vitta:BAAALgAECgMJAwAAAA==.',
Vo='Vonmiller:BAACLgAFFH8FAAITAAIJLhURCQCdAAATAAIJLhURCQCdAAAuAAQKfxoAAxMABwkiFkAGAPkBABMABwkiFkAGAPkBABIAAgkSDPf7AGIAAAAA.Vozluz:BAAALgAECgEJAQABLgAECggJQwATAGEgAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECgcJHAAJAKIQAA==.',
['Væ']='Væda:BAAALgAECgMJAwAAAA==.',
Wa='Warfaxis:BAEBLgAECn8bAAIZAAcJSyLIEABPAgAZAAcJSyLIEABPAgAAAA==.',
We='Weird:BAAALgAECgIJAgABLgAECgkJGAAIAB4SAA==.',
Wi='Winnower:BAAALgADCgYJBgAAAA==.Wiseoldgoob:BAAALgAECgkJEgAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAFFAIJBAAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAFFAEJAQAAAA==.',
Ze='Zenclaw:BAABLgAECn8oAAIXAAkJSQ3CKQCQAQAXAAkJSQ3CKQCQAQAAAA==.Zencore:BAABLgAECn8VAAIKAAgJeA8ScgB5AQAKAAgJeA8ScgB5AQAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECggJFQAKAHgPAA==.Zenlock:BAAALgADCgIJAgABLgAECggJFQAKAHgPAA==.',
Zi='Ziel:BAAALgAECgkJCwABLgAECgkJIwANAMgkAA==.',
['Äl']='Älexa:BAAALgAECgkJAQAAAA==.',
['Ñö']='Ñövä:BAAALgADCgMJBAAAAA==.',
['ßu']='ßubba:BAAALgAECgQJCQAAAA==.',
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
