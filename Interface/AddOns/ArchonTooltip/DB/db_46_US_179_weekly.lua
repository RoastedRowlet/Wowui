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

local lookup = {'Paladin-Protection','Shaman-Restoration','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Blood','DeathKnight-Unholy','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Mage-Frost','Mage-Fire','Warrior-Fury','Unknown-Unknown','Monk-Brewmaster','Paladin-Retribution','Warrior-Protection','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Monk-Mistweaver','Shaman-Elemental','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Enhancement','Evoker-Preservation','Hunter-Marksmanship','Monk-Windwalker','Paladin-Holy','Druid-Guardian','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Mage-Arcane','Warrior-Arms','Rogue-Assassination',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Adhenar:BAAALgAECgMJAwAAAA==.Adow:BAAALgAECgUJBQAAAA==.Adynne:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.',
Ae='Aered:BAAALgAECgYJDQAAAA==.Aerev:BAAALgAECgEJBAAAAA==.Aerylith:BAAALgAECgYJCgAAAA==.',
Af='Aften:BAAALgAECgYJCAAAAA==.',
Ah='Ahira:BAABLgAECn80AAICAAkJqiKYBgA8AwACAAkJqiKYBgA8AwAAAA==.',
Ai='Ailov:BAAALgADCgMJAwAAAA==.Ains:BAAALgAECgEJAQAAAA==.',
Ak='Akuria:BAABLgAECn8+AAIDAAkJ6B5ABwDXAgADAAkJ6B5ABwDXAgAAAA==.',
Al='Alacía:BAAALgAECgcJBwAAAA==.Alahna:BAABLgAECn8cAAIEAAgJSgj2dQBHAQAEAAgJSgj2dQBHAQAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAACLgAFFH8JAAIFAAQJLwM1JgCsAAAFAAQJLwM1JgCsAAAuAAQKfzwAAwUACQkoDWUdAGEBAAUACQkoDWUdAGEBAAYABQm/Alr6AIcAAAAA.Annicution:BAAALgAECgQJBwAAAA==.Antamoon:BAAALgAECggJEwAAAA==.',
Ao='Aox:BAABLgAECn8qAAIHAAkJfRpODQBGAgAHAAkJfRpODQBGAgAAAA==.',
Aq='Aquarian:BAAALgAECgYJDAAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgYJDQAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgAECgMJAwAAAA==.Asseroth:BAAALgAECgEJAQAAAA==.',
At='Atriux:BAAALgAECgkJCAAAAA==.',
Au='Aureline:BAABLgAECn80AAMIAAkJXROTMwDFAQAIAAkJXROTMwDFAQAJAAQJpAXYYACFAAAAAA==.Aurna:BAAALgAFFAEJAQAAAA==.',
Av='Avianddrela:BAAALgADCgIJAgAAAA==.',
Ba='Babegnome:BAAALgAECgEJAgAAAA==.Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgcJEQAAAA==.',
Be='Beanfliker:BAAALgADCgIJAgAAAA==.Beartank:BAAALgADCgYJBgAAAA==.Beastiam:BAAALgAECgEJAgAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgADCgUJCAAAAA==.Belserion:BAACLgAFFH8QAAIKAAQJwRjWGABnAQAKAAQJwRjWGABnAQAuAAQKf1wAAwoACQnoJZADAGwDAAoACQnoJZADAGwDAAsAAQndIVAPAFUAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECgkJIQAKANEfAA==.Bernir:BAAALgAECgIJAgAAAA==.Berol:BAABLgAECn8VAAIMAAgJDRmAHgD0AQAMAAgJDRmAHgD0AQAAAA==.Beroldin:BAAALgAECgMJAgABLgAECggJFQAMAA0ZAA==.Bevar:BAAALgAECgMJBAABLgAECgYJEgANAAAAAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAIOAAYJoB7QJQDVAQAOAAYJoB7QJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAABLgAECn8aAAIFAAkJjh/4BQC+AgAFAAkJjh/4BQC+AgAAAA==.Biggieshan:BAAALgAECggJDQAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAwAAAA==.Blair:BAAALgAECgEJAwAAAA==.Blindmafaka:BAAALgAECgYJEAAAAA==.Blkrend:BAABLgAECn9NAAIFAAkJKyYHAQBaAwAFAAkJKyYHAQBaAwAAAA==.Bloodhound:BAAALgAECgYJBgAAAA==.Blurtaxes:BAAALgAECgcJAgAAAA==.',
Bo='Bonko:BAAALgAECgMJAwAAAA==.',
Br='Bradycam:BAABLgAECn8/AAIPAAkJPiFrCwACAwAPAAkJPiFrCwACAwAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brewmaster:BAAALgAECgcJCAAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruceelee:BAAALgADCgMJAwAAAA==.Bruddah:BAAALgAFFAIJAwABLgAFFAMJDAAQAPMKAA==.',
Bu='Bubblebutt:BAAALgAECgUJBQAAAA==.Bulloo:BAAALgAECgEJAwAAAA==.Busterblader:BAAALgAECgQJBwAAAA==.',
['Bó']='Bóbafett:BAAALgADCgEJAQAAAA==.',
Ca='Cadovenia:BAAALgAECgEJBAAAAA==.Camillerose:BAAALgAECgQJBAAAAA==.Cantpalyhard:BAAALgAECgYJCQABLgAFFAMJCgACABsQAA==.Carebeär:BAABLgAECn8gAAIIAAcJ6hcYNgDPAQAIAAcJ6hcYNgDPAQAAAA==.Carpediems:BAAALgADCgIJAQAAAA==.Casella:BAABLgAECn8/AAIOAAkJkSA2BgDRAgAOAAkJkSA2BgDRAgAAAA==.',
Ce='Celissara:BAAALgAECgYJEQABLgAFFAEJAQANAAAAAA==.',
Ch='Chamoo:BAAALgADCgIJBAAAAA==.Chimken:BAAALgADCgMJAwAAAA==.Chogori:BAAALgAECgMJCQAAAA==.Chôsenône:BAAALgAECgUJBgAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAABLgAECn83AAIPAAkJwSC3CwD/AgAPAAkJwSC3CwD/AgAAAA==.Clouzot:BAAALgADCgYJDAAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAABLgAECn88AAIRAAkJfQpyCQCFAQARAAkJfQpyCQCFAQAAAA==.',
Cp='Cptbarnacles:BAABLgAECn8fAAQSAAcJpRD1HgC1AAATAAQJSg5FuADSAAASAAQJshD1HgC1AAAUAAMJzwy8JwBuAAAAAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBwAVACEdAA==.Crunchylock:BAAALgAECggJDAAAAA==.',
Cu='Cunumi:BAAALgAECgQJBAAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Damachi:BAABLgAECn8xAAMWAAkJaBiKBQBMAgAWAAkJEhiKBQBMAgAGAAgJ5xA7cQB5AQAAAA==.Danskan:BAABLgAECn8XAAIXAAYJMBfEFQBYAQAXAAYJMBfEFQBYAQAAAA==.Darkvale:BAAALgAFFAEJAgAAAA==.Darkñess:BAAALgAECggJDQAAAA==.Darmorae:BAABLgAECn8jAAIYAAkJsRXiEwAEAgAYAAkJsRXiEwAEAgAAAA==.Dashii:BAAALgAECgEJAgAAAA==.Datewoo:BAABLgAECn8kAAIPAAgJohIcYACmAQAPAAgJohIcYACmAQAAAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deef:BAAALgAECgYJDgAAAA==.Demilia:BAAALgAECgQJBAAAAA==.Demontotem:BAAALgAECggJDwAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desadeness:BAAALgADCgMJBQABLgADCgkJMAANAAAAAA==.Desertpunk:BAAALgAECgEJAQAAAA==.Destrolock:BAAALgAECgYJCwABLgAFFAIJCAAPAJEdAA==.Devoroyal:BAABLgAECn8XAAIVAAcJQRXIWwBoAQAVAAcJQRXIWwBoAQAAAA==.Dez:BAAALgAECgUJBQABLgAECgkJJQAGAKUHAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECgcJEQAAAA==.',
Do='Donkaßutts:BAAALgAECgQJDQAAAA==.Dooda:BAAALgAECgYJDAAAAA==.Doodooboi:BAAALgAECgQJBQAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECgcJDwAAAA==.Dooretos:BAAALgADCgEJAQAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracbow:BAABLgAECn8XAAIEAAgJFBMRRgDDAQAEAAgJFBMRRgDDAQABLgAECgkJHAAGAEYSAA==.Dracfu:BAABLgAECn8XAAIZAAgJpgduVgD6AAAZAAgJpgduVgD6AAABLgAECgkJHAAGAEYSAA==.Drackpally:BAAALgAECgcJBAAAAA==.Dracserion:BAAALgAFFAEJAQABLgAFFAQJEAAKAMEYAA==.Dracsham:BAAALgADCgEJAQABLgAECgkJHAAGAEYSAA==.Dracsknight:BAABLgAECn8cAAIGAAkJRhKxPgD/AQAGAAkJRhKxPgD/AQAAAA==.Dracslana:BAAALgAECgUJDAABLgAECgkJHAAGAEYSAA==.Draffel:BAABLgAECn8hAAMCAAkJuxsYEgCxAgACAAkJuxsYEgCxAgAaAAEJxQEduAAVAAAAAA==.Drathi:BAABLgAECn8jAAMGAAgJChqvMwAoAgAGAAcJChqvMwAoAgAFAAgJMBAfIQBAAQAAAA==.Drestla:BAAALgAECgcJCwAAAA==.Drothikus:BAAALgAECgMJAwAAAA==.Drowgon:BAABLgAECn8YAAMMAAgJEhcoMQCBAQAMAAcJORgoMQCBAQAQAAcJ8g3YKQDaAAAAAA==.Drtot:BAAALgAECgEJAQAAAA==.Druwgon:BAAALgAECgIJAgAAAA==.',
Du='Duartor:BAAALgAECgIJAgAAAA==.Dukalune:BAAALgAECgUJCQAAAA==.Dukaos:BAACLgAFFH8SAAIVAAUJjhHhQgAQAQAVAAUJjhHhQgAQAQAuAAQKfzoABBUACAmgHTQhAEMCABUACAmgHTQhAEMCABsABAlCDWQaAMEAABwAAgmDFMdfAD4AAAAA.Dunzer:BAACLgAFFH8KAAIPAAMJqg/PYwDUAAAPAAMJqg/PYwDUAAAuAAQKf0sAAw8ACQksG7kfAH8CAA8ACQksG7kfAH8CAAEAAglDCX9DAEkAAAAA.Dunzerblaze:BAAALgAECgQJCQAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAABLgAECn8gAAIIAAgJJBtIHABaAgAIAAgJJBtIHABaAgAAAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgAECgEJAQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8hAAIKAAgJ0R/wOgCLAgAKAAgJ0R/wOgCLAgAAAA==.',
Eh='Ehonda:BAAALgAECgUJBQABLgAECgkJGQAFAJQPAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAABLgAECn8ZAAIdAAkJrB8PBQC6AgAdAAkJrB8PBQC6AgAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAAALgAECgYJDwAAAA==.Emolock:BAAALgAECgUJBQAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgADCgcJBwAAAA==.',
Eo='Eon:BAAALgAECgUJDwAAAA==.',
Ep='Epiphaný:BAAALgAECgYJCwAAAA==.',
Er='Eradoria:BAABLgAECn8UAAIcAAYJQgXmRADiAAAcAAYJQgXmRADiAAAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgAECgQJBAAAAA==.',
Es='Essylt:BAAALgAECgQJCQAAAA==.Este:BAAALgADCgQJBAAAAA==.',
Ev='Evadne:BAAALgAECggJDgAAAA==.Evagrius:BAAALgAECgUJBQAAAA==.Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAABLgAECn8cAAIeAAkJ0wlcFAB9AQAeAAkJ0wlcFAB9AQAAAA==.',
Ex='Exidore:BAAALgAECgcJDAAAAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAANAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Falchionx:BAAALgAECgUJDAABLgAECggJIAAIACQbAA==.Falfogan:BAAALgAECgEJAgAAAA==.Fangy:BAAALgAECgIJBAAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felserion:BAAALgADCgEJAgABLgAFFAQJEAAKAMEYAA==.Fenn:BAABLgAECn8+AAIaAAkJLBxECwCiAgAaAAkJLBxECwCiAgAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Fistantillus:BAAALgAECgcJCwAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flnx:BAAALgAECgEJAQABLgAECggJIAAIACQbAA==.Flopper:BAAALgAECgYJCwAAAA==.',
Fo='Fonddle:BAAALgADCgUJCQAAAA==.Foxyboo:BAACLgAFFH8KAAICAAMJGxCsTACpAAACAAMJGxCsTACpAAAuAAQKf00AAwIACQmNIMgFAEsDAAIACQmNIMgFAEsDABoAAQnzBYWvACEAAAAA.',
Fr='Freak:BAABLgAECn8YAAMIAAgJHhJaQACHAQAIAAgJHhJaQACHAQAJAAYJsgk6TQD1AAAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.Frorly:BAAALgAECgEJAQAAAA==.',
Fu='Fulv:BAAALgAECgUJEAAAAA==.',
['Fâ']='Fâith:BAAALgAECgUJDgAAAA==.',
Ga='Gaezßuleaux:BAAALgAECgQJBwAAAA==.Galerodra:BAAALgADCgEJAQAAAA==.Galorani:BAAALgADCgIJAgAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAAALgAECgcJEQAAAA==.',
Ge='Gertroz:BAAALgAECgUJCAABLgAFFAEJAQANAAAAAA==.',
Gi='Gimic:BAAALgAECggJEAAAAA==.',
Gn='Gnomatic:BAAALgAECgIJAgABLgAECgkJJQAGAKUHAA==.Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn8uAAIEAAkJLSWHBABBAwAEAAkJLSWHBABBAwAAAA==.Gope:BAABLgAECn8lAAMCAAkJRBeCHwBGAgACAAkJRBeCHwBGAgAaAAQJ3gZMdgBpAAAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Green:BAABLgAECn8WAAIYAAgJSxcbCQBUAgAYAAgJSxcbCQBUAgAAAA==.Grewsome:BAAALgAECgQJBAAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn87AAMYAAkJQSNWAwD/AgAYAAkJfCJWAwD/AgAfAAgJ3R0MEgCoAgAAAA==.Gromyr:BAAALgAECgEJAQABLgAECgkJOwAYAEEjAA==.Grr:BAABLgAECn8rAAIVAAkJZiEzCwDmAgAVAAkJZiEzCwDmAgAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gä']='Gärrus:BAAALgAECgQJBAAAAA==.',
['Gó']='Gójira:BAABLgAECn8aAAIPAAgJoQfVuQAEAQAPAAgJoQfVuQAEAQAAAA==.',
Ha='Hartis:BAABLgAECn8sAAQEAAkJERDKLgD2AQAEAAkJERDKLgD2AQAYAAIJqwSiUQBaAAAfAAQJ5wBdewBWAAAAAA==.Hashmal:BAAALgAECgUJBwAAAA==.Hazo:BAABLgAECn8iAAMOAAYJbgnSXQCPAAAOAAUJcQrSXQCPAAAgAAMJqAQbbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Hectabali:BAAALgADCgYJBQAAAA==.Heizou:BAAALgAECgYJBwABLgAFFAMJCQAGAMkOAA==.Hellkat:BAAALgAECgYJCwAAAA==.',
Hi='Higarosa:BAAALgADCgIJBAAAAA==.Highbull:BAAALgAECgUJBQAAAA==.Hild:BAAALgAECgkJAQAAAA==.',
Ho='Holiblade:BAABLgAECn84AAIPAAgJ7gluoAArAQAPAAgJ7gluoAArAQAAAA==.Holyfaxiss:BAEBLgAECn8bAAIhAAgJmR6sCwDIAgAhAAgJmR6sCwDIAgABLgAECggJJAAMAMkeAA==.Holyhannah:BAAALgAECgUJBgAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJCgAAAA==.Hooligun:BAABLgAECn8vAAIaAAkJNQ8TLgB8AQAaAAkJNQ8TLgB8AQAAAA==.Hoppered:BAAALgAECgUJBgABLgAECgkJOwASAOAiAA==.',
Hu='Huntinpowerz:BAAALgAECgEJAQAAAA==.Huntlord:BAAALgADCgcJBwAAAA==.',
Hy='Hypérian:BAAALgAECgQJBQAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAABLgAECn8TAAIEAAkJSBt1PgC1AQAEAAkJSBt1PgC1AQAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAABLgAECn8jAAIBAAcJKROmFwBUAQABAAcJKROmFwBUAQAAAA==.',
Ih='Ihatereports:BAAALgAECgQJCAABLgAFFAMJBwAYAKcKAA==.',
Ij='Ijustshotyou:BAACLgAFFH8HAAMYAAMJpwpSHgDRAAAYAAMJpwpSHgDRAAAEAAIJzAfofACLAAAuAAQKfxUABB8ACAl4D0cVAAQBAB8ABwnNDkcVAAQBABgAAglBDoFLAHoAAAQAAgm+DvjmAGsAAAAA.',
Il='Illyría:BAAALgADCgcJBwAAAA==.Ilovetouka:BAAALgAECgMJBQAAAA==.',
Ir='Ironlotss:BAAALgADCgkJDQAAAA==.',
Iz='Izumo:BAAALgAECgQJBwAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAFFAQJBgATABoQAA==.Jakob:BAAALgAECgEJAwAAAA==.Jaks:BAAALgADCgEJAQAAAA==.Jardal:BAAALgADCgYJEQAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAABLgAECn8iAAIEAAgJ2w8kXACEAQAEAAgJ2w8kXACEAQAAAA==.Jenanila:BAAALgAECgMJBAAAAA==.',
Jh='Jhenna:BAAALgAECgQJBQABLgAECgkJLwAIAB8WAA==.',
Ji='Jibbs:BAABLgAECn8lAAMGAAkJpQfnjwA9AQAGAAgJXQjnjwA9AQAFAAEJmALMYgAZAAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwANAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJEAAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jolah:BAAALgAECgIJAgAAAA==.Jollakeratu:BAABLgAECn88AAIiAAkJ5xQHDgDxAQAiAAkJ5xQHDgDxAQAAAA==.Jonnygordo:BAABLgAECn8VAAIPAAYJBg5NvQAAAQAPAAYJBg5NvQAAAQAAAA==.Jorahh:BAABLgAECn8XAAMaAAcJHRYwMgBmAQAaAAYJHRYwMgBmAQACAAcJ2QysYAAJAQAAAA==.',
Ju='Jugram:BAAALgAECgQJBAAAAA==.Jungolv:BAAALgADCgMJAwAAAA==.Jusmissiner:BAABLgAECn8iAAIEAAkJxx5yFgCEAgAEAAkJxx5yFgCEAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAABLgAECn8eAAIFAAkJKRsQEAD9AQAFAAkJKRsQEAD9AQAAAA==.',
['Jø']='Jønty:BAAALgADCgYJEQAAAA==.',
Ka='Kaelyra:BAAALgADCgYJEQAAAA==.Kaitenn:BAAALgAECgYJBgAAAA==.Kamehame:BAAALgAECggJEgAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECgkJOAACAFciAA==.',
Ke='Keelhorn:BAABLgAECn8lAAMCAAkJGRSAMADlAQACAAkJGRSAMADlAQAaAAMJgwcLdAB+AAAAAA==.Kenneth:BAABLgAECn8UAAIPAAcJAA+ikgBCAQAPAAcJAA+ikgBCAQAAAA==.Kevin:BAAALgAECgYJDAABLgAFFAUJDQAJADUbAA==.Keyadorath:BAAALgADCgIJAgAAAA==.',
Ki='Kibon:BAABLgAECn8ZAAMUAAYJsgblJQB3AAATAAYJ9AWBvgDIAAAUAAQJfgTlJQB3AAAAAA==.Kindabored:BAAALgADCgEJAQABLgAFFAQJDAAIAPMHAA==.Kinkyhawt:BAEBLgAECn8WAAMjAAYJkh1oKQCTAQARAAUJchuiFQCUAQAjAAYJ+RxoKQCTAQAAAA==.Kirio:BAAALgADCgcJCgAAAA==.Kitsunenohi:BAABLgAECn8wAAIcAAkJcwiMJQA6AQAcAAkJcwiMJQA6AQAAAA==.',
Ko='Kodiakk:BAABLgAECn8jAAIYAAgJTBTCGgDDAQAYAAgJTBTCGgDDAQAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Kramden:BAAALgADCgkJEwAAAA==.Krattos:BAAALgAECgIJBQAAAA==.Krechon:BAAALgADCgQJBAAAAA==.Krimzin:BAAALgAECgEJAgABLgAFFAUJGgAEADAhAA==.',
Ks='Ksares:BAAALgAECgIJAgABLgAECgkJUAAEANwhAA==.',
Ku='Kuddles:BAAALgADCgEJBwAAAA==.Kumei:BAAALgAECgEJAQABLgAECgkJLAAEABEQAA==.Kural:BAAALgAECgUJBgABLgAECggJKAABAJsjAA==.',
Kw='Kwazii:BAABLgAECn8mAAQkAAgJ/BfOHADSAQAkAAgJ/BfOHADSAQADAAYJ+wWuTgDLAAAlAAIJJAV+ZQBTAAAAAA==.',
Ky='Kyantzmi:BAABLgAECn8ZAAIHAAYJMA8EJQBeAQAHAAYJMA8EJQBeAQAAAA==.Kyogre:BAABLgAECn8aAAIJAAcJuhKELwBTAQAJAAcJuhKELwBTAQAAAA==.',
La='Laefnia:BAACLgAFFH8IAAQJAAMJQA0SLwCxAAAJAAMJQA0SLwCxAAAIAAEJ0w9OaAA6AAAiAAEJAwqzNAAzAAAuAAQKfy4ABQkACQlVGT8ZAPUBAAkACAnnGD8ZAPUBACIABQmfGD4cAFkBAAgABwmlFZRNAE4BABcAAQk0Bn01AC4AAAEuAAUUAwkJAAYAyQ4A.Laraydra:BAAALgAECgUJDAABLgAFFAEJAQANAAAAAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJGQAgAD4QAA==.Lavaburstya:BAAALgAECgcJDAAAAA==.',
Le='Leomist:BAABLgAECn8ZAAIZAAkJVw8GLgCuAQAZAAkJVw8GLgCuAQAAAA==.Leviosä:BAABLgAECn8+AAMKAAkJOxj7LQBbAgAKAAkJOxj7LQBbAgALAAEJ2wZqFAAlAAAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgADCgkJHQAAAA==.Lilis:BAAALgAECgMJAwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8uAAIGAAkJZCQLCwAOAwAGAAkJZCQLCwAOAwAAAA==.Liten:BAAALgADCgYJEQAAAA==.Littlebev:BAAALgAECgYJEgAAAA==.',
Lo='Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJBwAAAA==.Longshankss:BAAALgAECgYJDgAAAA==.',
Ly='Lynaiya:BAAALgADCgMJAwAAAA==.',
['Lé']='Léxí:BAAALgAECgkJCQAAAA==.',
['Lí']='Lírii:BAAALgAECggJEgAAAA==.',
['Lô']='Lôôbmeup:BAAALgADCgEJAQAAAA==.',
Ma='Maachen:BAAALgAECgYJCwAAAA==.Maalik:BAABLgAECn9QAAQSAAkJ7CBoAQDjAgASAAkJpSBoAQDjAgAUAAcJfxoQCQCoAQATAAMJgw6L8wBuAAAAAA==.Magejackky:BAAALgAECgQJCAAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Maivorkeru:BAAALgAECgQJBgAAAA==.Malaurray:BAABLgAECn8jAAITAAgJbQwbbABfAQATAAgJbQwbbABfAQABLgABCgQJBgANAAAAAA==.Maluin:BAAALgAECgEJAQABLgAECgkJQAAbAOMaAA==.Mavanta:BAAALgAECgMJBAAAAA==.Mayonæse:BAABLgAECn8ZAAIVAAUJXAqQnADbAAAVAAUJXAqQnADbAAAAAA==.',
Mc='Mcchong:BAAALgAECgUJDgAAAA==.Mckennah:BAABLgAECn8eAAMBAAgJbiEHBgB9AgABAAgJbiEHBgB9AgAPAAEJDgwUkQEsAAAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAFFAMJBwAKAJEJAA==.Mereidith:BAACLgAFFH8HAAIKAAMJkQmofwDSAAAKAAMJkQmofwDSAAAuAAQKfycAAwoABwlYFxx4AIIBAAoABwlYFxx4AIIBACYAAQlyGhMZAE8AAAAA.Meshulk:BAAALgAECgEJAQAAAA==.Mesohungry:BAABLgAECn8pAAMhAAgJrgdSSAARAQAhAAgJrgdSSAARAQAPAAIJzAE5nQEoAAAAAA==.Metasploit:BAAALgAECgkJAQAAAA==.',
Mi='Mikehunte:BAAALgAECgYJBgABLgAECgkJIQAKANEfAA==.Miriya:BAABLgAECn8jAAIOAAkJyCQ8AgA4AwAOAAkJyCQ8AgA4AwAAAA==.Missnoms:BAAALgAECgEJAQAAAA==.',
Mo='Monkeycheese:BAABLgAECn8ZAAIgAAcJPhCrNwAXAQAgAAcJPhCrNwAXAQAAAA==.Moobáca:BAAALgAECgUJBwAAAA==.Moostradamas:BAABLgAECn8hAAMWAAkJxQYTFQAkAQAWAAkJxQYTFQAkAQAGAAIJsgAMhgEgAAAAAA==.Morcilla:BAAALgAECggJEwAAAA==.Morticyde:BAAALgAECgMJBAAAAA==.',
Ms='Msg:BAABLgAECn8lAAIIAAkJrBvbEwCjAgAIAAkJrBvbEwCjAgAAAA==.',
Mu='Munassa:BAAALgADCgcJBwAAAA==.Muppets:BAAALgAECgUJCQAAAA==.',
My='Myssidia:BAAALgADCgYJEAAAAA==.',
['Mí']='Mínervä:BAAALgAECgkJCgAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgIJAwAAAA==.Nastrodamus:BAAALgAECgEJAQAAAA==.Naturegoob:BAABLgAECn8bAAMIAAgJphogNADYAQAIAAgJphogNADYAQAJAAMJ4RHjWACgAAAAAA==.Naughtynurse:BAABLgAECn87AAIIAAkJixJgKgD6AQAIAAkJixJgKgD6AQAAAA==.Nayee:BAAALgADCgUJBQAAAA==.',
Ne='Nemrak:BAAALgAFFAIJAgAAAA==.Neuma:BAABLgAECn8UAAIPAAQJBAvF+QCxAAAPAAQJBAvF+QCxAAAAAA==.',
Ni='Nicfurry:BAAALgADCgMJAwAAAA==.Nightflower:BAABLgAECn8kAAMmAAkJUwUhDwDRAAAKAAcJGQWIwgABAQAmAAYJAwQhDwDRAAAAAA==.',
No='Noided:BAAALgAECgYJCgAAAA==.Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgYJDwABLgAECgYJEAANAAAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
Ob='Obiejuan:BAABLgAECn9RAAMPAAkJ4CIADAD9AgAPAAkJ4CIADAD9AgABAAQJoB4lIAAGAQAAAA==.Obietide:BAAALgAECgkJEQABLgAECgkJUQAPAOAiAA==.',
Od='Oddball:BAABLgAECn8eAAIaAAkJBhyOFwAaAgAaAAkJBhyOFwAaAgAAAA==.',
Of='Ofthecircle:BAAALgAECggJEwAAAA==.',
Ok='Okamiblooded:BAAALgAECgcJEAAAAA==.',
Ol='Olly:BAAALgAECgYJDQAAAA==.',
On='Ontala:BAAALgADCgYJBgAAAA==.',
Oo='Oodles:BAAALgAECgcJEgAAAA==.',
Or='Orangecrush:BAAALgAECgQJBQAAAA==.Orangekeg:BAAALgAECgUJEQABLgAECgkJIQAaANgfAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAAALgAECgYJEQAAAA==.',
Pa='Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn88AAIFAAkJ2R1nCQB1AgAFAAkJ2R1nCQB1AgABLgAECggJKAABAJsjAA==.Peso:BAAALgAECgQJBwAAAA==.Pez:BAAALgAECgYJEQABLgAECgkJLwAIAB8WAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAABLgAFFH8WAAIZAAYJJhWMFACvAQAZAAYJJhWMFACvAQABLgAFFAQJCAAhAGESAA==.Pomater:BAAALgAECgQJCQABLgAFFAEJAQANAAAAAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAABLgAECn8YAAIKAAgJOQmWlQBIAQAKAAgJOQmWlQBIAQAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECgkJLAACALQgAA==.',
Pr='Primafox:BAAALgAECgYJDAAAAA==.Prkchopxpres:BAAALgAECgYJDwAAAA==.Protoheal:BAAALgAECgEJAgAAAA==.',
Pu='Punchandkick:BAAALgAECgMJBgAAAA==.Punkweight:BAAALgAECgEJAQAAAA==.Purpleeater:BAAALgAECgEJAQAAAA==.',
Py='Pyrabanks:BAAALgAFFAQJBAAAAA==.',
['Pä']='Päw:BAACLgAFFH8JAAMGAAMJyQ6PmADSAAAGAAMJyQ6PmADSAAAWAAIJSQR1HQByAAAuAAQKfyYAAwYACAlNGVROANEBAAYACAmhF1ROANEBABYAAgmDF+YlAIsAAAAA.',
Qu='Quetzalcóatl:BAAALgAECgQJBAAAAA==.Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJAgAAAA==.',
Qx='Qx:BAAALgADCggJDgAAAA==.',
Ra='Raakoth:BAAALgAECgUJCAABLgAECgkJUAASAOwgAA==.Radge:BAABLgAECn83AAMnAAkJoiXcAABqAwAnAAkJoiXcAABqAwAMAAMJKR0rdgDiAAAAAA==.Rainjar:BAACLgAFFH8RAAMYAAQJhCE9EgArAQAYAAMJlyE9EgArAQAEAAIJkBu0agCrAAAuAAQKfzwAAxgACQkAIl4CAB8DABgACQlcH14CAB8DAAQACAk3JBARAL4CAAAA.Rainne:BAAALgADCgcJCAAAAA==.Raistyn:BAABLgAECn8pAAMBAAkJwRwDCwALAgABAAkJwRwDCwALAgAPAAEJigyMiwEtAAAAAA==.Ralanar:BAAALgAECgcJDQABLgAFFAEJAQANAAAAAA==.Raljah:BAABLgAECn87AAQSAAkJ4CLxAAAEAwASAAkJ1CLxAAAEAwATAAcJ7B4SKAA2AgAUAAUJXh19FACnAQAAAA==.Ramasus:BAAALgAECgUJBQAAAA==.Rampart:BAABLgAECn8tAAMBAAkJWhkpCABKAgABAAkJWhkpCABKAgAPAAEJ5w4mfAEyAAAAAA==.Rasaltghul:BAAALgAECgEJAQABLgAECgMJBgANAAAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.Raxxer:BAAALgAECgEJBAAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAABLgAECn8UAAMBAAcJtw3kJQDYAAAPAAcJ9gcoxgDzAAABAAYJbg7kJQDYAAAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Renm:BAAALgAECgYJEgAAAA==.Renpriest:BAACLgAFFH8UAAIlAAMJfx6BJQACAQAlAAMJfx6BJQACAQAuAAQKfxUAAyUACAmMGVIRAC4CACUACAmMGVIRAC4CAAMAAQk4FZl5ADoAAAAA.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgUJDAAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.',
Ry='Ryobi:BAABLgAECn83AAMEAAkJQhhhLgAYAgAEAAkJ9BRhLgAYAgAfAAgJhxRtCgC6AQAAAA==.Ryptyde:BAABLgAECn8WAAICAAkJ7h4dBwAzAwACAAkJ7h4dBwAzAwAAAA==.',
['Ræ']='Rævena:BAABLgAECn8VAAIGAAYJOgrAvgD2AAAGAAYJOgrAvgD2AAAAAA==.',
Sa='Sachaann:BAAALgAECgIJAwAAAA==.Salinan:BAABLgAECn9RAAMSAAkJ3CShAAAnAwASAAkJtyShAAAnAwATAAYJ7RrnUgCeAQAAAA==.Saltymon:BAAALgADCgYJBgABLgAECgIJAwANAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgkJKgAHAH0aAA==.Saradia:BAAALgADCgIJAgAAAA==.Saric:BAAALgAECgMJBwAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Scanor:BAAALgAECgYJDAABLgAFFAMJDQAjAM4CAA==.Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.',
Se='Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAABLgAECn8iAAIPAAgJdxu4LgA7AgAPAAgJdxu4LgA7AgAAAA==.Selky:BAAALgADCgcJCgAAAA==.',
Sf='Sfodin:BAABLgAECn8eAAIMAAgJKQm7PABKAQAMAAgJKQm7PABKAQAAAA==.',
Sh='Shadowkings:BAAALgAFFAEJAgAAAA==.Shak:BAABLgAECn8aAAIaAAYJ7Qt6UgDdAAAaAAYJ7Qt6UgDdAAAAAA==.Shalai:BAAALgADCgMJAwAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shastix:BAAALgAECgYJEgABLgAECgkJUAASAOwgAA==.Shellingtun:BAAALgAECgYJCwAAAA==.Shyandrial:BAAALgAECgEJAQAAAA==.Shyness:BAAALgAECgQJBAAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAABLgAECn8oAAMDAAgJ1gutLwBZAQADAAgJ1gutLwBZAQAkAAEJkgGveQASAAAAAA==.',
Sk='Skilltotem:BAAALgAECgkJEAAAAA==.Skk:BAAALgADCggJCQAAAA==.Sksteve:BAAALgAECgUJDwAAAA==.Skullyy:BAAALgAECgYJDgABLgAECgYJEAANAAAAAA==.Skychades:BAAALgAECgYJDgAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAABLgAECn8cAAIJAAcJohARNgAvAQAJAAcJohARNgAvAQAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECgcJCAABLgAECgcJHAAJAKIQAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgAECgcJDwAAAA==.Soulsrequiem:BAABLgAECn8hAAIoAAgJoAGWGQCPAAAoAAgJoAGWGQCPAAAAAA==.',
Sp='Spicyblaster:BAABLgAFFH8MAAIKAAQJAg7eWwAoAQAKAAQJAg7eWwAoAQAAAA==.Spookydeath:BAACLgAFFH8TAAIKAAUJGQzLYAAeAQAKAAUJGQzLYAAeAQAuAAQKfy4AAgoACQmrEgJEAAkCAAoACQmrEgJEAAkCAAAA.',
Sr='Srsnacksalot:BAABLgAECn8nAAIPAAgJ9hhORgDoAQAPAAgJ9hhORgDoAQAAAA==.',
St='Stileto:BAAALgAECgcJDgAAAA==.Stoneydracco:BAABLgAECn8dAAIKAAcJUBNTegB9AQAKAAcJUBNTegB9AQAAAA==.Stoneydragon:BAAALgADCgYJBgAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECgcJEQAAAA==.',
Su='Sukiliana:BAAALgAECgQJBQAAAA==.Sumtinwng:BAABLgAECn82AAIPAAkJmxFJRgDoAQAPAAkJmxFJRgDoAQAAAA==.Supervicious:BAABLgAECn8ZAAIQAAkJuxW8EgC0AQAQAAkJuxW8EgC0AQAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgYJEQAAAA==.Sylenne:BAABLgAECn8vAAIIAAkJHxZyHgBJAgAIAAkJHxZyHgBJAgAAAA==.Sylur:BAAALgAECgcJDwABLgAECggJIAAIACQbAA==.',
['Sÿ']='Sÿlvanah:BAAALgAECgQJBAAAAA==.',
Ta='Taemea:BAAALgAECggJEgAAAA==.Tahran:BAAALgAECgEJAQABLgAFFAUJHQAkALAXAA==.Tahren:BAACLgAFFH8dAAQkAAUJsBeJEAA2AQAlAAUJCRJEGwBgAQAkAAQJBRWJEAA2AQADAAIJZgv1LACBAAAuAAQKfycABCQACQmIIHMQAGECACQABwn0IHMQAGECACUACQlvE6UvAFMBAAMABgklDyZbAJwAAAAA.Talanima:BAAALgADCgcJBwAAAA==.Taler:BAAALgAFFAEJAQAAAA==.Talerion:BAAALgAECgcJEgAAAA==.Talyaine:BAAALgAECgEJAQABLgAFFAMJCQAGAMkOAA==.Tanzanitia:BAAALgAECgYJBgAAAA==.',
Tc='Tcdots:BAAALgAECgEJAgAAAA==.',
Te='Tens:BAABLgAECn8bAAIMAAgJJiNXDAD1AgAMAAgJJiNXDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECgcJEQAAAA==.Theafflictor:BAAALgAECgYJCQAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECgcJEQANAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thistelbear:BAABLgAECn85AAIgAAkJFAz2KQBeAQAgAAkJFAz2KQBeAQAAAA==.Thrallsux:BAAALgAECgEJAgAAAA==.Thraun:BAAALgAECgYJEgAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn80AAMPAAkJsBKiagCpAQAPAAkJsBKiagCpAQABAAcJaAtSJADlAAAAAA==.',
Ti='Titszilla:BAAALgAECgcJAwAAAA==.',
To='Toki:BAABLgAECn8bAAMZAAYJxxuqKgDBAQAZAAYJxxuqKgDBAQAgAAQJqg+ZTQDbAAAAAA==.Tokidormi:BAABLgAECn8bAAMeAAgJZx38BQCmAgAeAAgJZx38BQCmAgARAAEJzQWZJwApAAAAAA==.Toralus:BAAALgADCgYJCQAAAA==.Totumm:BAAALgADCgcJCAAAAA==.',
Tr='Tralku:BAAALgAECgcJDAAAAA==.Tremmørs:BAABLgAECn8aAAIaAAcJUQzvTADyAAAaAAcJUQzvTADyAAAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAABLgAECn8UAAIPAAkJghZWWgCzAQAPAAkJghZWWgCzAQAAAA==.',
Tu='Turnip:BAAALgAECgEJAQAAAA==.',
Tw='Tweak:BAAALgAECgIJAgAAAA==.Tweis:BAAALgADCgYJEQAAAA==.',
Ty='Tyllinor:BAAALgADCgUJBQAAAA==.',
Um='Umbrarogue:BAABLgAECn8eAAMHAAkJOBwSEAAhAgAHAAkJ0RoSEAAhAgAoAAEJPh3zHwBVAAAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEwAAAA==.',
Va='Vaara:BAAALgAECgEJAQAAAA==.Valaa:BAAALgAECgUJBQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAABLgAECn8WAAIPAAkJyA4CcgCYAQAPAAkJyA4CcgCYAQAAAA==.Veliya:BAAALgAECgYJEwABLgAECgkJLwAIAB8WAA==.Vellestrix:BAAALgAECgQJBAAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Veriity:BAAALgADCgYJBgAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Vicotr:BAAALgAECgcJDAAAAA==.Viddysouls:BAABLgAECn8hAAIdAAgJtRJYEACeAQAdAAgJtRJYEACeAQAAAA==.Viscerai:BAABLgAECn84AAIkAAkJiSUgAQC1AwAkAAkJiSUgAQC1AwAAAA==.Vite:BAAALgAECgYJDwAAAA==.Vitta:BAAALgAECgMJAwAAAA==.',
Vo='Vonmiller:BAACLgAFFH8FAAISAAIJLhU3DgCXAAASAAIJLhU3DgCXAAAuAAQKfxsAAxIACAn9FkAGAPkBABIACAn9FkAGAPkBABMAAgkSDPf7AGIAAAAA.Vozluz:BAAALgAECgEJAQABLgAECgkJUAASAOwgAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECgcJHAAJAKIQAA==.',
['Væ']='Væda:BAAALgAECgMJAwAAAA==.',
Wa='Warfaxis:BAEBLgAECn8kAAIMAAgJyR4+DwB7AgAMAAgJyR4+DwB7AgAAAA==.',
We='Weird:BAAALgAECgIJAgABLgAECgkJGAAIAB4SAA==.',
Wi='Winnower:BAAALgADCgYJBgAAAA==.Wiseoldgoob:BAAALgAECgkJEgAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAFFAIJBAAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAFFAMJAwAAAA==.',
Ze='Zenclaw:BAABLgAECn81AAIZAAkJTRBWKgDDAQAZAAkJTRBWKgDDAQAAAA==.Zencore:BAABLgAECn8VAAIKAAgJeA8UgQBvAQAKAAgJeA8UgQBvAQAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECggJFQAKAHgPAA==.Zenlock:BAAALgADCgIJAgABLgAECggJFQAKAHgPAA==.',
Zi='Ziel:BAAALgAECgkJCwABLgAECgkJIwAOAMgkAA==.',
Zo='Zoramite:BAAALgAECgUJBQAAAA==.',
['Äl']='Älexa:BAAALgAECgkJAQAAAA==.',
['Ñö']='Ñövä:BAAALgAECgMJBwAAAA==.',
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
