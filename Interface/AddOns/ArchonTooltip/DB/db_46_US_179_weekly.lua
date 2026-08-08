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

local lookup = {'Paladin-Protection','Shaman-Restoration','Warlock-Affliction','Priest-Shadow','Shaman-Elemental','Hunter-BeastMastery','DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Devourer','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Mage-Frost','Paladin-Retribution','Mage-Fire','Warrior-Fury','Warlock-Destruction','Monk-Brewmaster','Warrior-Protection','Priest-Discipline','Evoker-Devastation','Warlock-Demonology','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Priest-Holy','Paladin-Holy','Unknown-Unknown','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Enhancement','Evoker-Preservation','Hunter-Marksmanship','Monk-Windwalker','Druid-Guardian','Evoker-Augmentation','Mage-Arcane','Warrior-Arms','Rogue-Assassination',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abcdeath:BAAALgAECgQJBQAAAA==.',
Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Addalyne:BAAALgAECgYJDQAAAA==.Adhenar:BAAALgAECgQJBAAAAA==.Adow:BAAALgAECggJCQAAAA==.Adynne:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.',
Ae='Aered:BAAALgAECggJDwAAAA==.Aerev:BAAALgAECgEJBgAAAA==.Aerylith:BAAALgAECgYJCgAAAA==.',
Af='Aften:BAAALgAECgYJCAAAAA==.',
Ah='Ahira:BAABLgAECn9DAAICAAkJqSNaBwA6AwACAAkJqSNaBwA6AwAAAA==.',
Ai='Aiel:BAAALgADCgEJAQAAAA==.Ailov:BAAALgAECgMJAwAAAA==.Ains:BAAALgAECgEJAQAAAA==.Airro:BAAALgAECgUJBQAAAA==.Aitruin:BAAALgAECgEJAQABLgAECgkJWAADAOwgAA==.',
Ak='Akuria:BAABLgAECn9oAAIEAAkJbCPCAAApAwAEAAkJbCPCAAApAwAAAA==.',
Al='Alacía:BAABLgAFFH8FAAMCAAMJrBHBSABEAAACAAIJiQnBSABEAAAFAAEJ4wG2QAAmAAAAAA==.Alahna:BAABLgAECn8oAAIGAAkJHQz+HQDlAAAGAAkJHQz+HQDlAAAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAACLgAFFH8iAAIHAAQJZAh6FQCsAAAHAAQJZAh6FQCsAAAuAAQKf1IAAwcACQl/GLgCAA8CAAcACQl/GLgCAA8CAAgABglGA2dQAVEAAAAA.Annicution:BAABLgAECn8dAAMHAAgJCR65AwC6AQAHAAgJCR65AwC6AQAIAAUJiwwyIQCxAAAAAA==.Antamoon:BAABLgAECn8YAAIJAAkJyg6VTQCdAQAJAAkJyg6VTQCdAQAAAA==.',
Ao='Aox:BAABLgAECn82AAIKAAkJmhxdCgB+AgAKAAkJmhxdCgB+AgAAAA==.',
Aq='Aquarian:BAAALgAECgYJDAAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgkJGAAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgAECgMJAwAAAA==.Asseroth:BAAALgAECgEJAQAAAA==.',
At='Atriux:BAAALgAECgkJCAAAAA==.',
Au='Aureline:BAABLgAECn80AAMLAAkJXRMhNQDGAQALAAkJXRMhNQDGAQAMAAQJpAUnZgCFAAAAAA==.Aurna:BAACLgAFFH8GAAINAAQJLQmEMgD9AAANAAQJLQmEMgD9AAAuAAQKfyIAAg0ACQlvG3sFAE0CAA0ACQlvG3sFAE0CAAAA.',
Av='Avianddrela:BAAALgADCgIJAgAAAA==.',
Az='Azuresky:BAABLgAECn8ZAAIOAAYJkgMUQgBbAAAOAAYJkgMUQgBbAAAAAA==.',
Ba='Babegnome:BAAALgAECgEJAgAAAA==.Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgcJEQAAAA==.',
Be='Beanfliker:BAAALgADCgIJAgAAAA==.Bearlysimple:BAAALgAECgYJEAAAAA==.Beartank:BAAALgADCgYJBgAAAA==.Beastiam:BAAALgAECgEJAwAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgAECgEJAQAAAA==.Belserion:BAACLgAFFH8QAAINAAQJwRjWGABnAQANAAQJwRjWGABnAQAuAAQKf2IAAw0ACQnoJT8EAGYDAA0ACQnoJT8EAGYDAA8AAQndIeUQAFQAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECgkJIQANANEfAA==.Bernir:BAAALgAECgIJAgAAAA==.Berol:BAABLgAECn8YAAIQAAgJTBtcGgAbAgAQAAgJTBtcGgAbAgAAAA==.Beroldin:BAAALgAECgQJAwABLgAECggJGAAQAEwbAA==.Bevar:BAAALgAECgYJDQABLgAECgcJGwARAAULAA==.Bevell:BAAALgAECgQJCgABLgAECgcJGwARAAULAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAISAAYJoB7QJQDVAQASAAYJoB7QJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAABLgAECn8aAAIHAAkJjh+hBgC1AgAHAAkJjh+hBgC1AgAAAA==.Biggieshan:BAAALgAECggJDQAAAA==.',
Bj='Bjøørn:BAAALgAECgQJBAAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAwAAAA==.Blair:BAAALgAECgEJBAAAAA==.Blindmafaka:BAAALgAECgYJEAAAAA==.Blkrend:BAACLgAFFH8HAAIHAAMJ3CDRGQAYAQAHAAMJ3CDRGQAYAQAuAAQKf00AAgcACQkrJkABAFIDAAcACQkrJkABAFIDAAAA.Bloodhound:BAAALgAECgYJBgAAAA==.Bluntz:BAAALgAECgQJBQAAAA==.Blurtaxes:BAAALgAECgcJAgABLgAFFAIJBQAIAJ4VAA==.',
Bo='Bonko:BAAALgAECgMJAwAAAA==.',
Br='Bradycam:BAABLgAECn9LAAIOAAkJkiKgCQAbAwAOAAkJkiKgCQAbAwAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brewmaster:BAAALgAECgcJCAAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruceelee:BAAALgADCgMJAwAAAA==.Brucegoon:BAAALgAECgQJBwAAAA==.Bruddah:BAAALgAFFAIJAwABLgAFFAMJDAATAPMKAA==.Brycefotm:BAAALgAECgcJCwABLgAFFAQJFQACAA0gAA==.',
Bu='Bubblebutt:BAAALgAECgUJBQAAAA==.Bulloo:BAAALgAECgIJBQAAAA==.Busterblader:BAAALgAECgcJEQAAAA==.',
['Bó']='Bóbafett:BAAALgADCgEJAQAAAA==.',
Ca='Cadovenia:BAAALgAECgEJBAAAAA==.Camdencer:BAAALgADCgQJBAAAAA==.Camillerose:BAAALgAECgQJBAAAAA==.Cantpalyhard:BAAALgAECgYJCgABLgAFFAQJGAACAIERAA==.Carebeär:BAABLgAECn8gAAILAAcJ6hcYNgDPAQALAAcJ6hcYNgDPAQAAAA==.Carpediems:BAAALgADCgIJAQAAAA==.Casella:BAABLgAECn8/AAISAAkJkSC5BgDOAgASAAkJkSC5BgDOAgAAAA==.',
Ce='Celerrime:BAAALgAECgEJAQAAAA==.Celissara:BAABLgAECn8YAAIUAAYJVBZ/MgBQAQAUAAYJVBZ/MgBQAQABLgAFFAQJBgANAC0JAA==.',
Ch='Chamoo:BAAALgADCgIJBAAAAA==.Chimken:BAAALgADCgMJAwAAAA==.Chocospells:BAAALgAECgIJAwAAAA==.Chogori:BAAALgAECgUJDQAAAA==.Chôsenône:BAAALgAECgUJBgAAAA==.',
Ci='Cid:BAAALgADCgEJAQAAAA==.Cierdwyn:BAABLgAECn8qAAIMAAcJDQXMFAB+AAAMAAcJDQXMFAB+AAAAAA==.Cinnaßon:BAAALgAECgQJBAAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAABLgAECn83AAIOAAkJwSBNDQD6AgAOAAkJwSBNDQD6AgAAAA==.Clouzot:BAAALgADCgkJFwAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAABLgAECn9tAAIVAAkJBhIYAQC/AQAVAAkJBhIYAQC/AQAAAA==.',
Cp='Cptbarnacles:BAABLgAECn8lAAQDAAcJhBKiIQC1AAAWAAQJGhHxqQDuAAADAAQJshCiIQC1AAARAAMJzwwjKgBsAAAAAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBwAJACEdAA==.Crunchylock:BAAALgAECggJDAAAAA==.Crèmeßrûlée:BAAALgAECgUJCQAAAA==.',
Cu='Cunumi:BAAALgAECgQJBAAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Dainichi:BAAALgAECgEJAgAAAA==.Dakyne:BAAALgAECgYJBgAAAA==.Damachi:BAABLgAECn81AAMXAAkJ1xhWBgBDAgAXAAkJgRhWBgBDAgAIAAgJ5xBtegBuAQAAAA==.Danskan:BAABLgAECn8aAAIYAAYJFBt3FgBjAQAYAAYJFBt3FgBjAQAAAA==.Darkvale:BAAALgAFFAEJAwAAAA==.Darkñess:BAAALgAECggJDQAAAA==.Darmorae:BAABLgAECn8jAAIZAAkJsRV4FQD3AQAZAAkJsRV4FQD3AQAAAA==.Dashii:BAAALgAECgQJCAABLgAECggJJgAaAPwXAA==.Datewoo:BAABLgAECn8oAAIOAAgJ6BKUZQCkAQAOAAgJ6BKUZQCkAQAAAA==.Datsuo:BAAALgAECgcJEQABLgAECgkJWAADAOwgAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deathfaxiss:BAEALgAECggJEgABLgAECgkJNwAbAAgkAA==.Deathris:BAAALgAECggJCgAAAA==.Deef:BAAALgAECgYJDgAAAA==.Demilia:BAAALgAECgQJBAAAAA==.Demontotem:BAAALgAECgkJEAAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desadeness:BAAALgADCgUJEAABLgADCgkJNwAcAAAAAA==.Desertpunk:BAAALgAECgEJAQAAAA==.Destrolock:BAAALgAECgYJCwABLgAFFAMJDQAOADkgAA==.Devinos:BAAALgADCgMJAwAAAA==.Dez:BAAALgAECgYJBwABLgAECgkJJQAIAKUHAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECgkJEwAAAA==.',
Do='Donkaßutts:BAAALgAECgQJDgAAAA==.Dooda:BAAALgAECgcJDQAAAA==.Doodooboi:BAAALgAECgQJBQAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECgkJEQAAAA==.Dooretos:BAAALgADCgEJAQAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracbow:BAACLgAFFH8JAAIGAAMJLA+yMwDUAAAGAAMJLA+yMwDUAAAuAAQKfxcAAgYACAkUE69MALwBAAYACAkUE69MALwBAAEuAAUUBAkNAAgAmgcA.Dracdemonica:BAAALgAFFAIJAgABLgAFFAQJDQAIAJoHAA==.Dracfu:BAABLgAECn8YAAIdAAgJpgi5XgD8AAAdAAgJpgi5XgD8AAABLgAFFAQJDQAIAJoHAA==.Dracklock:BAAALgADCgMJAwABLgAECgcJBQAcAAAAAA==.Drackpally:BAAALgAECgcJBQAAAA==.Dracserion:BAAALgAFFAEJAgABLgAFFAQJEAANAMEYAA==.Dracsham:BAAALgADCgEJAQABLgAFFAQJDQAIAJoHAA==.Dracsknight:BAACLgAFFH8NAAIIAAQJmgcYWwCiAAAIAAQJmgcYWwCiAAAuAAQKfyIAAggACQmAEilCAPwBAAgACQmAEilCAPwBAAAA.Dracslana:BAAALgAECgYJEQABLgAFFAQJDQAIAJoHAA==.Dracstone:BAAALgAECgEJAQABLgAFFAQJDQAIAJoHAA==.Draffel:BAABLgAECn8hAAMCAAkJuxt4EwCwAgACAAkJuxt4EwCwAgAFAAEJxQElxQAVAAAAAA==.Dramamine:BAAALgAECgQJBAAAAA==.Drathi:BAABLgAECn8jAAMIAAgJCxrCNgAkAgAIAAcJCxrCNgAkAgAHAAgJMBB7IwA3AQAAAA==.Drestla:BAAALgAECgcJCwAAAA==.Drothikus:BAAALgAECgMJAwAAAA==.Drowgon:BAABLgAECn8YAAMQAAgJEhc4MwB+AQAQAAcJORg4MwB+AQATAAcJ8g0qLADYAAAAAA==.Drtot:BAAALgAECgEJAwAAAA==.Druidfaxxis:BAEALgAECggJDwABLgAECgkJNwAbAAgkAA==.Druwgon:BAAALgAECgIJAgAAAA==.Drác:BAAALgAECgIJBAABLgAFFAQJDQAIAJoHAA==.',
Du='Duartor:BAAALgAECgIJAgAAAA==.Dukalune:BAAALgAECgUJCQAAAA==.Dukaos:BAACLgAFFH8VAAIJAAUJjhEISwAJAQAJAAUJjhEISwAJAQAuAAQKfzoABAkACAmgHTQjAEMCAAkACAmgHTQjAEMCAB4ABAlCDWQaAMEAAB8AAgmDFBVoAD0AAAAA.Dukazil:BAAALgADCgYJBgAAAA==.Dukorpse:BAAALgAECgYJBgAAAA==.Dunzer:BAACLgAFFH8YAAIOAAQJMxCsJgDwAAAOAAQJMxCsJgDwAAAuAAQKf0sAAw4ACQksG8oiAHsCAA4ACQksG8oiAHsCAAEAAglDCSdHAEkAAAAA.Dunzerblaze:BAAALgAECgQJCQAAAA==.',
['Dæ']='Dæmonia:BAAALgAECgIJBAAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAABLgAECn8hAAILAAgJJBuTHQBZAgALAAgJJBuTHQBZAgABLgAECgkJHwAIACAcAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgAECgEJAQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8hAAINAAgJ0R/wOgCLAgANAAgJ0R/wOgCLAgAAAA==.',
Eh='Ehonda:BAAALgAECgUJBQABLgAECgkJGQAHAJQPAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAABLgAECn8ZAAIgAAkJrB8PBQC6AgAgAAkJrB8PBQC6AgAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAABLgAECn8hAAIUAAgJUxOmBADWAQAUAAgJUxOmBADWAQAAAA==.Emolock:BAAALgAECgUJBQAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgAECgIJAgAAAA==.',
Eo='Eon:BAAALgAECgUJDwAAAA==.',
Ep='Epiphaný:BAAALgAECgYJCwABLgAECggJJgAaAPwXAA==.',
Er='Eradoria:BAABLgAECn8WAAIfAAgJPgfmRADiAAAfAAgJPgfmRADiAAAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgAECgQJBAAAAA==.',
Es='Essylt:BAAALgAECgQJCgAAAA==.Este:BAAALgADCgQJBAAAAA==.',
Ev='Evadne:BAABLgAECn8VAAMCAAgJsQ1jFwDJAAACAAYJRQxjFwDJAAAFAAYJ7gKRdgCJAAAAAA==.Evagrius:BAAALgAECgUJBQAAAA==.Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAABLgAECn8cAAIhAAkJ0wmKFQB0AQAhAAkJ0wmKFQB0AQAAAA==.',
Ex='Exidore:BAAALgAECgcJDAAAAA==.Extremespeed:BAAALgAECgYJDAABLgAECgkJHwAIACAcAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAAcAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Fafnix:BAAALgAECgUJBQABLgAECgkJGQAgAKwfAA==.Falchionx:BAAALgAECgUJDAABLgAECgkJHwAIACAcAA==.Falfogan:BAAALgAECgEJAgAAAA==.Fangy:BAAALgAECgQJCgAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felindra:BAAALgADCgYJBgAAAA==.Felserion:BAAALgAECgUJBgABLgAFFAQJEAANAMEYAA==.Fenn:BAABLgAECn9KAAIFAAkJFh2SCgC2AgAFAAkJFh2SCgC2AgAAAA==.Fenrirstorm:BAAALgADCgIJAgAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Firechicken:BAAALgAECgcJBwAAAA==.Fistantillus:BAAALgAECgcJCwAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flnx:BAAALgAECggJCwABLgAECgkJHwAIACAcAA==.Float:BAAALgADCgQJBAAAAA==.Flopper:BAAALgAECgYJCwAAAA==.',
Fo='Fo:BAAALgADCgEJAQAAAA==.Fonddle:BAAALgADCgUJCQAAAA==.Forthelight:BAAALgAFFAEJAQAAAA==.Foxyboo:BAACLgAFFH8YAAICAAQJgRHWJQCzAAACAAQJgRHWJQCzAAAuAAQKf00AAwIACQmNIIEGAEgDAAIACQmNIIEGAEgDAAUAAQnzBcu7ACEAAAAA.',
Fr='Freak:BAABLgAECn8YAAMLAAgJHhIiQwCEAQALAAgJHhIiQwCEAQAMAAYJsgk6TQD1AAAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.Frorly:BAAALgAECgEJAQAAAA==.',
Fu='Fulv:BAAALgAECgUJEAAAAA==.',
['Fâ']='Fâith:BAAALgAECgUJEAAAAA==.',
Ga='Gaezßuleaux:BAAALgAECgUJCgAAAA==.Galerodra:BAAALgADCgEJAQAAAA==.Galorani:BAAALgADCgIJAgAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAABLgAECn8VAAIJAAgJXhT7YABnAQAJAAgJXhT7YABnAQAAAA==.',
Ge='Gertroz:BAAALgAECgUJCAABLgAFFAQJBgANAC0JAA==.',
Gi='Gimic:BAAALgAECgkJEwAAAA==.',
Gn='Gnomatic:BAAALgAECgIJCwABLgAECgkJJQAIAKUHAA==.Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn88AAIGAAkJLSVBBQA+AwAGAAkJLSVBBQA+AwAAAA==.Gope:BAABLgAECn8lAAMCAAkJRBepIQBFAgACAAkJRBepIQBFAgAFAAQJ3gZMdgBpAAAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Graazer:BAAALgAECgIJAgAAAA==.Green:BAABLgAECn8WAAIZAAgJSxcbCQBUAgAZAAgJSxcbCQBUAgAAAA==.Grewsome:BAAALgAECgQJBAAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn9HAAMZAAkJUSRvAQBPAwAZAAkJLSRvAQBPAwAiAAgJ3R0MEgCoAgAAAA==.Gromyr:BAAALgAECgEJAQABLgAECgkJRwAZAFEkAA==.Grr:BAABLgAECn8rAAIJAAkJZiEjDADlAgAJAAkJZiEjDADlAgAAAA==.Gruxxle:BAAALgADCgUJBQAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gä']='Gärrus:BAAALgAECgQJBAAAAA==.',
['Gó']='Gójira:BAABLgAECn8bAAIOAAkJFgcmtwAVAQAOAAkJFgcmtwAVAQAAAA==.',
Ha='Hafgan:BAEBLgAECn8ZAAMCAAcJ7h5jAwBwAgACAAcJ7h5jAwBwAgAgAAMJMxLdCQClAAABLgAECgkJNwAbAAgkAA==.Hartis:BAABLgAECn8sAAQGAAkJERDKLgD2AQAGAAkJERDKLgD2AQAZAAIJqwTDVQBWAAAiAAQJ5wBdewBWAAAAAA==.Hashmal:BAAALgAECgUJCAAAAA==.Hazo:BAABLgAECn8iAAMSAAYJbgnpYACOAAASAAUJcQrpYACOAAAjAAMJqAQbbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Hectabali:BAAALgADCgYJBQAAAA==.Heizou:BAAALgAECgYJBwABLgAFFAQJFwAMAP8dAA==.Hellkat:BAAALgAECgcJDAAAAA==.',
Hi='Higarosa:BAAALgAECgEJAQAAAA==.Highbull:BAAALgAECgcJCgABLgAECggJJgAaAPwXAA==.Hild:BAAALgAECgkJAQAAAA==.',
Ho='Hogfather:BAAALgAECgkJDwAAAA==.Holiblade:BAABLgAECn87AAIOAAkJ5QlRqwAmAQAOAAkJ5QlRqwAmAQAAAA==.Holyfaxiss:BAEBLgAECn83AAIbAAkJCCR3AABWAwAbAAkJCCR3AABWAwAAAA==.Holyhannah:BAAALgAECgUJBgAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJCgAAAA==.Holywhiskers:BAABLgAECn8fAAIbAAgJNRIoBADMAQAbAAgJNRIoBADMAQABLgAECgkJUgAOAHkhAA==.Hooligun:BAABLgAECn8wAAIFAAkJPRDyMAB7AQAFAAkJPRDyMAB7AQAAAA==.Hoppered:BAAALgAECgUJBgABLgAECgkJQQADADQkAA==.Howlapeno:BAAALgAECgUJBAABLgAFFAcJFwASAKgcAA==.',
Hu='Huntinpowerz:BAAALgAECgEJAQAAAA==.Huntlord:BAAALgADCgcJBwAAAA==.',
Hy='Hypérian:BAAALgAECgQJBgAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAABLgAECn8TAAIGAAkJSBt1PgC1AQAGAAkJSBt1PgC1AQAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAABLgAECn8qAAIBAAkJihVXBABfAQABAAkJihVXBABfAQAAAA==.',
Ih='Ihatereports:BAAALgAECgQJCAABLgAFFAMJCQAZAKsMAA==.',
Ij='Ijustshotyou:BAACLgAFFH8JAAMZAAMJqwx6IADUAAAZAAMJqwx6IADUAAAGAAIJzAfrjACGAAAuAAQKfxYABCIACAnQEc8RAD4BACIABwl3Es8RAD4BABkAAglBDr1OAHYAAAYAAgm+Don3AGgAAAAA.',
Il='Ilithid:BAEALgAECgIJAgABLgAECgkJNwAbAAgkAA==.Illyría:BAAALgADCgcJBwAAAA==.Ilovetouka:BAAALgAECgMJBQAAAA==.',
Im='Imascaleymon:BAAALgAECgQJBAAAAA==.',
In='Indigoaura:BAAALgAECgMJAwAAAA==.',
Ir='Ironlotss:BAAALgADCgkJDQAAAA==.',
Iz='Izumo:BAABLgAECn8WAAIeAAcJ4RY3AgB6AQAeAAcJ4RY3AgB6AQAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAFFAUJCAAWAJwSAA==.Jakob:BAAALgAECgEJBAAAAA==.Jaks:BAAALgADCgEJAQAAAA==.Jamaris:BAAALgAECgYJCQABLgAECgkJWAADAOwgAA==.Jardal:BAAALgADCgkJHAAAAA==.Jatswamdi:BAABLgAFFH8FAAMBAAMJpBWvBgC0AAABAAMJpBWvBgC0AAAOAAIJYgLItQBJAAAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAABLgAECn8jAAIGAAkJ8w4VZAB9AQAGAAkJ8w4VZAB9AQAAAA==.Jenanila:BAAALgAECgMJBAAAAA==.',
Jh='Jhenna:BAAALgAECgQJBgABLgAECgkJLwALAB8WAA==.',
Ji='Jibbs:BAABLgAECn8lAAMIAAkJpQfImQA2AQAIAAgJXQjImQA2AQAHAAEJmAKbaAAZAAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwAcAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJEAAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jolah:BAAALgAECgIJAgAAAA==.Jollakeratu:BAABLgAECn9tAAIkAAkJaBm1AQA/AgAkAAkJaBm1AQA/AgAAAA==.Jonnygordo:BAABLgAECn8bAAIOAAYJBxT2GAAIAQAOAAYJBxT2GAAIAQAAAA==.Jorahh:BAABLgAECn8XAAMFAAcJHRY/NQBlAQAFAAYJHRY/NQBlAQACAAcJ2QysYAAJAQAAAA==.',
Ju='Jugernawt:BAAALgAECgEJAQABLgAECgkJQAABAIYdAA==.Jugram:BAAALgAECgQJCQAAAA==.Jungolv:BAAALgADCgMJAwAAAA==.Jusmissiner:BAABLgAECn8iAAIGAAkJxx5yFgCEAgAGAAkJxx5yFgCEAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAABLgAECn8eAAIHAAkJKRtzEQD1AQAHAAkJKRtzEQD1AQAAAA==.',
['Jø']='Jønty:BAAALgADCgkJFgAAAA==.',
Ka='Kaelyra:BAAALgADCgkJHAAAAA==.Kaitenn:BAAALgAECgYJBgAAAA==.Kamehame:BAAALgAECggJEgAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECgkJRAACAFciAA==.',
Ke='Keelhorn:BAABLgAECn8lAAMCAAkJGRRVMwDlAQACAAkJGRRVMwDlAQAFAAMJgwdyewB9AAAAAA==.Kenneth:BAABLgAECn8cAAIOAAcJshJJgwBpAQAOAAcJshJJgwBpAQAAAA==.Kerubiel:BAAALgAECggJCwABLgAECgkJWAADAOwgAA==.Kessarah:BAAALgAECgkJAgAAAA==.Kevin:BAAALgAECgYJDAABLgAFFAUJDwAMAIgcAA==.Keyadorath:BAAALgADCgIJAgAAAA==.',
Ki='Kibon:BAABLgAECn8ZAAMRAAYJsga7KABzAAAWAAYJ9AXxxQDDAAARAAQJfgS7KABzAAAAAA==.Kindabored:BAAALgADCggJCAABLgAFFAUJIAALAOwLAA==.Kinkyhawt:BAEBLgAECn8YAAMlAAYJAB8KKwCSAQAVAAUJchuiFQCUAQAlAAYJZx4KKwCSAQAAAA==.Kirio:BAAALgADCgcJCgAAAA==.Kitsunenohi:BAABLgAECn9fAAIfAAkJ5QxRBgBTAQAfAAkJ5QxRBgBTAQAAAA==.',
Ko='Kodiakk:BAABLgAECn8nAAIZAAkJNRQ7HAC7AQAZAAkJNRQ7HAC7AQAAAA==.Kornbread:BAAALgAECgQJBAAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Krattos:BAAALgAFFAEJAQAAAA==.Krechon:BAAALgADCgQJBAAAAA==.Krimzin:BAAALgAECgEJAgABLgAFFAUJGwAGADAhAA==.',
Ks='Ksares:BAAALgAECgIJAgABLgAECgkJUAAGANwhAA==.',
Ku='Kuddles:BAAALgADCgEJBwAAAA==.Kumei:BAAALgAECgEJAQABLgAECgkJLAAGABEQAA==.Kural:BAAALgAECgUJBgABLgAECggJKAABAJsjAA==.',
Kw='Kwazii:BAABLgAECn8mAAQaAAgJ/BeiHgDQAQAaAAgJ/BeiHgDQAQAEAAYJ+wUiVADCAAAUAAIJJAWVbABTAAAAAA==.',
Ky='Kyantzmi:BAABLgAECn8fAAIKAAYJkxEgJwBeAQAKAAYJkxEgJwBeAQAAAA==.Kyogre:BAABLgAECn8cAAIMAAcJ4RMAMgBTAQAMAAcJ4RMAMgBTAQAAAA==.',
La='Laefnia:BAACLgAFFH8XAAQMAAQJ/x3gEAAGAQAMAAQJ/x3gEAAGAQALAAMJgRH2GgCWAAAkAAEJAwocPwAwAAAuAAQKfzQABQwACQnUGkIRAFECAAwACQmYGUIRAFECAAsACAnUGbswAN8BACQABQmfGJkeAFgBABgAAQk0Bn01AC4AAAAA.Lapisal:BAAALgADCgEJAQAAAA==.Laraydra:BAAALgAECgcJEwABLgAFFAQJBgANAC0JAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJGQAjAD4QAA==.Lavaburstya:BAAALgAECgcJDAAAAA==.',
Le='Leelui:BAAALgAECgEJAwAAAA==.Leomist:BAABLgAECn8gAAMdAAkJ8A+XMQCyAQAdAAkJ8A+XMQCyAQAjAAEJKwotJAAkAAAAAA==.Leviosä:BAABLgAECn8+AAMNAAkJOxj5MABVAgANAAkJOxj5MABVAgAPAAEJ2wbmFgAiAAAAAA==.Leylan:BAAALgADCgQJBAAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgAECgcJDAAAAA==.Lilis:BAAALgAECgMJAwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8uAAIIAAkJZCRxDAAJAwAIAAkJZCRxDAAJAwAAAA==.Liten:BAAALgADCgkJGwAAAA==.Littlebev:BAABLgAECn8bAAIRAAcJBQsEFwDrAAARAAcJBQsEFwDrAAAAAA==.',
Lo='Lockins:BAAALgAECgcJCQAAAA==.Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJCgAAAA==.Lohruken:BAAALgADCgQJBAAAAA==.Longshankss:BAAALgAECgcJDwAAAA==.',
Lu='Luahn:BAAALgAECggJCwAAAA==.',
Ly='Lynaiya:BAAALgADCgMJAwAAAA==.',
['Lé']='Léxí:BAAALgAECgkJCQAAAA==.',
['Lí']='Lírii:BAAALgAECggJEgAAAA==.',
['Lô']='Lôôbmeup:BAAALgADCgEJAQAAAA==.',
Ma='Maachen:BAAALgAECgYJDgAAAA==.Maalik:BAABLgAECn9YAAQDAAkJ7CCiAQDeAgADAAkJpSCiAQDeAgARAAcJfxoiCgCkAQAWAAMJgw6Y/gBqAAAAAA==.Magejackky:BAAALgAECgQJCAAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Maivorkeru:BAAALgAECgQJBgAAAA==.Malaurray:BAABLgAECn8jAAIWAAgJbQxDcgBVAQAWAAgJbQxDcgBVAQABLgABCgQJBgAcAAAAAA==.Maluin:BAAALgAECgEJAgABLgAECgkJUAAeAHccAA==.Mammoth:BAAALgAECgEJAQAAAA==.Mavanta:BAAALgAECgMJBAAAAA==.Mayonæse:BAABLgAECn8fAAIJAAUJuAxCmgDsAAAJAAUJuAxCmgDsAAAAAA==.',
Mc='Mcchong:BAABLgAECn8cAAIGAAcJjR7gBgAaAgAGAAcJjR7gBgAaAgAAAA==.Mckennah:BAABLgAECn8eAAMBAAgJbiGdBgB6AgABAAgJbiGdBgB6AgAOAAEJDgwgpgEsAAAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAFFAQJEQANACwTAA==.Mereidith:BAACLgAFFH8RAAMNAAQJLBMtOADiAAANAAQJLBMtOADiAAAmAAEJXAYWCAA1AAAuAAQKfywAAw0ABwmCHPdPAOwBAA0ABwmCHPdPAOwBACYAAQlyGhMZAE8AAAAA.Meshulk:BAAALgAECgEJAQAAAA==.Mesohungry:BAABLgAECn8uAAMbAAkJiQkkOwBcAQAbAAkJiQkkOwBcAQAOAAIJzAGPtwEnAAAAAA==.Metasploit:BAAALgAECgkJAQAAAA==.',
Mi='Mikehunte:BAAALgAECgYJBgABLgAECgkJIQANANEfAA==.Miriya:BAABLgAECn8jAAISAAkJyCR+AgA1AwASAAkJyCR+AgA1AwAAAA==.Missnoms:BAAALgAECgEJAQAAAA==.',
Mn='Mnemnoc:BAAALgAECgUJBQAAAA==.',
Mo='Monkeycheese:BAABLgAECn8ZAAIjAAcJPhAKPAARAQAjAAcJPhAKPAARAQAAAA==.Moobáca:BAAALgAECgUJBwABLgAECggJJgAaAPwXAA==.Moostradamas:BAABLgAECn8oAAMXAAkJBQfqFgAgAQAXAAkJBQfqFgAgAQAIAAIJsgAWogEeAAAAAA==.Morcilla:BAABLgAECn8UAAMHAAkJngv3IwAzAQAHAAkJngv3IwAzAQAXAAMJ/gTKLgBlAAAAAA==.Morticyde:BAAALgAECgMJBAAAAA==.',
Ms='Msg:BAABLgAECn8lAAILAAkJrBveFACjAgALAAkJrBveFACjAgAAAA==.',
Mu='Munassa:BAAALgADCgcJBwAAAA==.Muppets:BAAALgAECgUJCQAAAA==.',
My='Myssidia:BAAALgADCgkJGwAAAA==.',
['Mâ']='Mânô:BAAALgAECgQJBAAAAA==.',
['Mí']='Mínervä:BAAALgAECgkJEAAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgIJAwAAAA==.Nasdaralth:BAAALgAECgMJBgABLgAFFAQJBgANAC0JAA==.Nastrodamus:BAAALgAECgIJAgAAAA==.Naturegoob:BAABLgAECn8hAAQLAAkJyRogNADYAQALAAgJphogNADYAQAkAAMJFiA5DAC0AAAMAAUJnxYgEQCoAAAAAA==.Naughtynurse:BAABLgAECn9HAAILAAkJixLVKwD7AQALAAkJixLVKwD7AQAAAA==.Nayee:BAAALgAECgMJAwAAAA==.',
Ne='Nemrak:BAAALgAFFAIJAgAAAA==.Neuma:BAABLgAECn8UAAIOAAQJBAvfBQGxAAAOAAQJBAvfBQGxAAAAAA==.',
Ni='Nicfurry:BAAALgADCgMJAwAAAA==.Nightflower:BAABLgAECn8kAAMmAAkJUwUhDwDRAAANAAcJGQVEyQD8AAAmAAYJAwQhDwDRAAAAAA==.',
No='Noided:BAAALgAECgYJCgAAAA==.Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgYJDwABLgAECgYJEAAcAAAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
['Nö']='Növä:BAAALgAECgYJCwABLgAECgkJTQARAPEeAA==.',
Ob='Obiejuan:BAACLgAFFH8HAAIOAAMJ2g2tdgDHAAAOAAMJ2g2tdgDHAAAuAAQKf1MAAw4ACQngIq8NAPgCAA4ACQngIq8NAPgCAAEABQlnHeMhAAUBAAAA.Obietide:BAAALgAECgkJEQABLgAFFAMJBwAOANoNAA==.',
Od='Oddball:BAABLgAECn8eAAIFAAkJBhxMGQAYAgAFAAkJBhxMGQAYAgAAAA==.',
Of='Ofthecircle:BAAALgAECggJEwAAAA==.',
Ok='Okamiblooded:BAABLgAECn8dAAQZAAkJexWmAgCpAQAZAAkJexWmAgCpAQAiAAEJBAvGQAApAAAGAAEJ7AJ8TgEiAAAAAA==.',
Ol='Olly:BAAALgAECgYJDQAAAA==.',
On='Ontala:BAAALgADCgYJBgAAAA==.',
Oo='Oodles:BAABLgAECn8UAAINAAcJYRxwdwDjAQANAAcJYRxwdwDjAQAAAA==.',
Op='Ophiron:BAAALgAECgUJCQAAAA==.',
Or='Orangecrush:BAABLgAECn8oAAIGAAcJsgqrGQAHAQAGAAcJsgqrGQAHAQAAAA==.Orangekeg:BAAALgAECgUJEQABLgAFFAMJBQAFAAkhAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAABLgAECn8aAAIGAAkJkA1dJgC2AAAGAAkJkA1dJgC2AAAAAA==.',
Pa='Paduma:BAAALgADCgEJAQAAAA==.Paintrain:BAAALgAECgUJBQABLgAECgYJBgAcAAAAAA==.Palelite:BAAALgAECgEJAgABLgAFFAMJBgAHADoWAA==.Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn88AAIHAAkJ2R1eCgBsAgAHAAkJ2R1eCgBsAgABLgAECggJKAABAJsjAA==.Perkyßits:BAAALgAECgEJAQAAAA==.Persíkutor:BAAALgAECgQJBAAAAA==.Peso:BAAALgAECgQJBwABLgAECggJJgAaAPwXAA==.Pez:BAAALgAECgYJEQABLgAECgkJLwALAB8WAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAABLgAFFH8cAAIdAAgJJRauEgD0AQAdAAgJJRauEgD0AQABLgAFFAUJDAAbAEsTAA==.Pomater:BAAALgAECgYJDgABLgAFFAQJBgANAC0JAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAABLgAECn8YAAINAAgJOQkLngA+AQANAAgJOQkLngA+AQAAAA==.Powerzone:BAAALgAECgEJAQAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECgkJLAACALQgAA==.',
Pr='Primafox:BAAALgAECgYJDAAAAA==.Prkchopxpres:BAAALgAECgYJDwAAAA==.Protoheal:BAAALgAECgEJAgAAAA==.',
Ps='Psychoman:BAAALgAECgUJBQAAAA==.',
Pu='Punchandkick:BAAALgAECgMJBgAAAA==.Punkweight:BAAALgAECgEJAQAAAA==.Purpleeater:BAAALgAECgIJBQAAAA==.',
Py='Pyrabanks:BAABLgAFFH8MAAIlAAQJFwo3OgDdAAAlAAQJFwo3OgDdAAAAAA==.',
['Pä']='Päw:BAACLgAFFH8NAAMIAAMJThAzqgDKAAAIAAMJThAzqgDKAAAXAAIJMAWgIgB1AAAuAAQKfy4ABAgACQniHWFTAMoBAAgACAmhF2FTAMoBAAcABQnEHN0gAEsBABcAAwnjHz8aAP8AAAEuAAUUBAkXAAwA/x0A.',
Qu='Quetzalcóatl:BAAALgAECgQJBAAAAA==.Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJBQAAAA==.',
Qx='Qx:BAAALgAECgYJBwAAAA==.',
Ra='Raakoth:BAAALgAECgYJEwABLgAECgkJWAADAOwgAA==.Radge:BAABLgAECn87AAMnAAkJriUVAQBlAwAnAAkJriUVAQBlAwAQAAMJKR0rdgDiAAAAAA==.Rainjar:BAACLgAFFH8iAAMZAAYJUBxIAwCVAQAZAAYJDRhIAwCVAQAGAAIJkBv/eACmAAAuAAQKfzwAAxkACQkAIl4CAB8DABkACQlcH14CAB8DAAYACAk3JCQTALkCAAAA.Rainne:BAAALgADCgcJCAAAAA==.Raistyn:BAABLgAECn8pAAMBAAkJwRzUCwAIAgABAAkJwRzUCwAIAgAOAAEJigwNqAErAAAAAA==.Ralanar:BAAALgAFFAMJBAABLgAFFAQJBgANAC0JAA==.Raljah:BAABLgAECn9BAAQDAAkJNCQNAQAFAwADAAkJKSQNAQAFAwAWAAcJBB8zKgAyAgARAAUJXh19FACnAQAAAA==.Ramasus:BAAALgAECgUJBQAAAA==.Rampart:BAABLgAECn9AAAMBAAkJhh1xBwBnAgABAAkJhh1xBwBnAgAOAAEJ5w4EnAEvAAAAAA==.Rasaltghul:BAAALgAECgEJAQABLgAECgMJBgAcAAAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.Raxxer:BAAALgAECgEJBAAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAABLgAECn8UAAMBAAcJtw3YJwDYAAAOAAcJ9gej0ADyAAABAAYJbg7YJwDYAAAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Rem:BAAALgAECgUJBQAAAA==.Renm:BAAALgAECgYJEgAAAA==.Renpriest:BAACLgAFFH8UAAIUAAMJfx4QKgD+AAAUAAMJfx4QKgD+AAAuAAQKfxUAAxQACAmMGVIRAC4CABQACAmMGVIRAC4CAAQAAQk4FUmBADoAAAAA.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgkJFwAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.Royaldüh:BAACLgAFFH8GAAIJAAIJ7wXRjABpAAAJAAIJ7wXRjABpAAAuAAQKfxcAAgkABwlCFZpfAGoBAAkABwlCFZpfAGoBAAAA.',
Ru='Rubyraeven:BAABLgAECn8UAAIGAAcJlQbrIQDMAAAGAAcJlQbrIQDMAAAAAA==.',
Ry='Ryobi:BAABLgAECn9DAAMiAAkJJBqgCADyAQAGAAkJWBYAMwAQAgAiAAgJrhmgCADyAQAAAA==.Ryptyde:BAABLgAECn8WAAICAAkJ7h7YBwAyAwACAAkJ7h7YBwAyAwAAAA==.',
['Ræ']='Rævena:BAABLgAECn8dAAIIAAYJzBG9GQDbAAAIAAYJzBG9GQDbAAAAAA==.',
Sa='Sachaann:BAAALgAECgIJAwAAAA==.Salinan:BAACLgAFFH8GAAMDAAMJDRI5DgCiAAAWAAMJewsNfgDIAAADAAIJ1BU5DgCiAAAuAAQKf1EAAwMACQncJL8AACIDAAMACQm3JL8AACIDABYABgntGshVAJsBAAAA.Saltymon:BAAALgADCgYJBgABLgAECgIJAwAcAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgkJNgAKAJocAA==.Saradia:BAAALgADCgIJAgAAAA==.Saric:BAAALgAECgMJBwAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Scanor:BAAALgAECgYJDAABLgAFFAMJDgAlAM4CAA==.Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.Scrim:BAAALgAECgEJAQAAAA==.',
Se='Seaßass:BAAALgAECgIJAgAAAA==.Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAABLgAECn8qAAIOAAkJBB0HIACIAgAOAAkJBB0HIACIAgAAAA==.Selky:BAAALgADCgcJCgAAAA==.Sevenbeers:BAAALgAFFAEJAQABLgAFFAgJHQAgAE8RAA==.',
Sf='Sfodin:BAABLgAECn8eAAIQAAgJKQk9QQBAAQAQAAgJKQk9QQBAAQAAAA==.',
Sh='Shadowkings:BAAALgAFFAEJAwAAAA==.Shak:BAABLgAECn8jAAIFAAYJoRFATQAAAQAFAAYJoRFATQAAAQAAAA==.Shalai:BAAALgADCgMJAwAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shastix:BAAALgAECgYJEwABLgAECgkJWAADAOwgAA==.Shelinaria:BAAALgADCgQJBAABLgAECgkJPAAOAC0bAA==.Shellingtun:BAABLgAECn8UAAMbAAgJ+xOQBAC8AQAbAAcJgRWQBAC8AQAOAAUJ2wV2VQA/AAABLgAECggJJgAaAPwXAA==.Shiggylloway:BAAALgAECgEJAgAAAA==.Shyandrial:BAAALgAECgUJCQAAAA==.Shyness:BAAALgAECgQJBAAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAABLgAECn8yAAMEAAgJNA/VCgAHAQAEAAgJNA/VCgAHAQAaAAQJtgieVACKAAAAAA==.',
Sk='Skilltotem:BAAALgAECgkJEAAAAA==.Skitch:BAAALgAECgEJAgAAAA==.Skk:BAAALgADCggJCQAAAA==.Sksteve:BAAALgAECgUJDwAAAA==.Skullyy:BAAALgAECgYJDgABLgAECgYJEAAcAAAAAA==.Skychades:BAABLgAECn8ZAAIGAAkJARgoQwDZAQAGAAkJARgoQwDZAQAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAABLgAECn8cAAIMAAcJohD2OAAvAQAMAAcJohD2OAAvAQABLgAECgkJDwAcAAAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECgkJDwAAAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgAECgcJDwAAAA==.Soulsreaver:BAAALgADCgcJBwAAAA==.Soulsrequiem:BAABLgAECn9IAAIoAAgJeQihAgAFAQAoAAgJeQihAgAFAQAAAA==.',
Sp='Spiceynoodle:BAABLgAFFH8dAAMNAAYJ1xu4GwCNAQANAAYJ1xu4GwCNAQAmAAEJpBW7BgBEAAAAAA==.Spookydeath:BAACLgAFFH8gAAINAAUJCxZCKwAhAQANAAUJCxZCKwAhAQAuAAQKfy4AAg0ACQmrEnpJAP8BAA0ACQmrEnpJAP8BAAAA.',
Sr='Srsnacksalot:BAACLgAFFH8FAAIOAAMJdgjPPACqAAAOAAMJdgjPPACqAAAuAAQKfysAAg4ACAn2GPVKAOUBAA4ACAn2GPVKAOUBAAAA.',
St='Stileto:BAAALgAECgcJEAABLgAECggJJgAaAPwXAA==.Stonedhuntar:BAAALgAECgcJDAAAAA==.Stoneydracco:BAABLgAECn8hAAINAAgJIBPtgAB1AQANAAgJIBPtgAB1AQAAAA==.Stoneydragon:BAAALgADCgYJBgAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECgkJEwAAAA==.',
Su='Sukiliana:BAAALgAECgQJBQAAAA==.Sumtinwng:BAABLgAECn85AAIOAAkJsBKjRwDvAQAOAAkJsBKjRwDvAQAAAA==.Supervicious:BAABLgAECn8ZAAITAAkJuxUeFACuAQATAAkJuxUeFACuAQAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgkJHAAAAA==.Sylenne:BAABLgAECn8vAAILAAkJHxaOHwBKAgALAAkJHxaOHwBKAgAAAA==.Sylur:BAABLgAECn8fAAQIAAkJIBwMBQA5AgAIAAkJfRkMBQA5AgAXAAYJJiD9AQDcAQAHAAEJlAxiSQAlAAAAAA==.Syrayvianda:BAAALgADCgYJBgAAAA==.',
['Sÿ']='Sÿlvanah:BAAALgAECgQJBAAAAA==.',
Ta='Taemea:BAAALgAECggJEgAAAA==.Tahran:BAAALgAFFAIJAgABLgAFFAgJKAAUAJQUAA==.Tahren:BAACLgAFFH8oAAQUAAgJlBS9CwCdAQAUAAgJFxG9CwCdAQAaAAQJBRU4EwAvAQAEAAIJlhUnIABTAAAuAAQKfyoABBoACQmIIHMQAGECABoABwn0IHMQAGECABQACQlvExMzAEwBAAQABwllEJZKAOUAAAAA.Talanima:BAAALgADCgcJBwAAAA==.Taler:BAAALgAFFAEJAQAAAA==.Talerion:BAAALgAECgcJEgAAAA==.Talyaine:BAAALgAECgUJBQABLgAFFAQJFwAMAP8dAA==.Tanzanitia:BAAALgAECgYJBgABLgAECgcJFAAGAJUGAA==.',
Tc='Tcdots:BAAALgAECgEJAwAAAA==.',
Te='Telline:BAAALgADCgYJBwAAAA==.Tens:BAABLgAECn8bAAIQAAgJJiNXDAD1AgAQAAgJJiNXDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECgkJEwAAAA==.Theafflictor:BAAALgAECgcJCgAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECgkJEwAcAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thisfelbear:BAABLgAECn8UAAIfAAkJMhPVAwDGAQAfAAkJMhPVAwDGAQAAAA==.Thistelbear:BAABLgAECn9RAAIjAAkJ9Q/eAwCOAQAjAAkJ9Q/eAwCOAQAAAA==.Thrallsux:BAAALgAECgEJAgAAAA==.Thraun:BAABLgAECn8UAAIWAAYJ/Q+hhwBKAQAWAAYJ/Q+hhwBKAQAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn80AAMOAAkJsBKiagCpAQAOAAkJsBKiagCpAQABAAcJaAspJgDkAAAAAA==.',
Ti='Titszilla:BAAALgAECggJBQABLgAECggJJgAaAPwXAA==.',
To='Toki:BAABLgAECn8bAAMdAAYJxxuSLgDCAQAdAAYJxxuSLgDCAQAjAAQJqg+ZTQDbAAABLgAECgkJPAAhACEgAA==.Tokidormi:BAABLgAECn88AAMhAAkJISBvAADoAgAhAAkJISBvAADoAgAVAAUJPxPKEQDuAAAAAA==.Tokihots:BAABLgAECn8WAAMMAAgJiSCjAQCVAgAMAAgJiSCjAQCVAgALAAYJbxqsBADMAQABLgAECgkJPAAhACEgAA==.Toralus:BAAALgADCgYJCQAAAA==.Totumm:BAAALgADCgcJCAAAAA==.',
Tr='Tralku:BAAALgAECgcJDAAAAA==.Tremmørs:BAABLgAECn8aAAIFAAcJUQy0UQDxAAAFAAcJUQy0UQDxAAAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAABLgAECn8UAAIOAAkJghZTYACwAQAOAAkJghZTYACwAQAAAA==.',
Tu='Turnip:BAAALgAECgIJAgABLgAECggJJgAaAPwXAA==.',
Tw='Tweak:BAAALgAECgIJAgABLgAECggJJgAaAPwXAA==.Tweis:BAAALgADCgkJFwAAAA==.',
Ty='Tyllinor:BAAALgADCgUJBQAAAA==.',
Um='Umbrarogue:BAABLgAECn8eAAMKAAkJOBxtEQAdAgAKAAkJ0RptEQAdAgAoAAEJPh2vIQBVAAAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEwAAAA==.',
Va='Vaara:BAAALgAECgMJBAAAAA==.Valaa:BAAALgAECggJCQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAABLgAECn8WAAIOAAkJyA4CcgCYAQAOAAkJyA4CcgCYAQAAAA==.Veliya:BAAALgAECgYJEwABLgAECgkJLwALAB8WAA==.Vellestrix:BAAALgAECgQJBAAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Veriity:BAAALgAECgUJCwAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Vicotr:BAAALgAFFAEJAQAAAA==.Viddysouls:BAABLgAECn8iAAIgAAkJMhKeEQCaAQAgAAkJMhKeEQCaAQAAAA==.Vienaa:BAAALgAECgEJAQAAAA==.Viscerai:BAABLgAECn85AAIaAAkJiSVIAQCyAwAaAAkJiSVIAQCyAwAAAA==.Vite:BAAALgAECgYJDwAAAA==.Vitta:BAAALgAECgMJAwAAAA==.',
Vo='Vonmiller:BAACLgAFFH8FAAIDAAIJLhXQEACLAAADAAIJLhXQEACLAAAuAAQKfxsAAwMACAn9FkAGAPkBAAMACAn9FkAGAPkBABYAAgkSDPf7AGIAAAAA.Vozluz:BAAALgAECgEJAQABLgAECgkJWAADAOwgAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECgkJDwAcAAAAAA==.',
['Væ']='Væda:BAAALgAECgMJAwAAAA==.',
Wa='Warfaxis:BAEBLgAECn86AAIQAAgJISRqBwDoAgAQAAgJISRqBwDoAgABLgAECgkJNwAbAAgkAA==.',
We='Weird:BAAALgAECgIJAgABLgAECgkJGAALAB4SAA==.Wereßearßirb:BAAALgADCgUJBQAAAA==.',
Wh='Who:BAAALgAECgkJCAAAAA==.',
Wi='Winnower:BAAALgAECgIJAgAAAA==.Wiseoldgoob:BAABLgAECn8dAAQUAAkJmxliCwC4AgAUAAkJmxliCwC4AgAEAAIJERifFACLAAAaAAEJkw4dbwAyAAAAAA==.',
Wo='Woodwildin:BAAALgAECgUJBgAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAFFAIJBAAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAFFAMJAwAAAA==.',
Xu='Xugos:BAAALgAECgEJAQAAAA==.',
Yu='Yurie:BAAALgAECgMJAwABLgAECgQJBwAcAAAAAA==.',
Za='Zarash:BAAALgAECgQJCAABLgAECgkJHwAIACAcAA==.',
Ze='Zenclaw:BAABLgAECn9BAAIdAAkJzhCJLQDIAQAdAAkJzhCJLQDIAQAAAA==.Zencore:BAABLgAECn8VAAINAAgJeA99iABmAQANAAgJeA99iABmAQAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECggJFQANAHgPAA==.Zenlock:BAAALgADCgIJAgABLgAECggJFQANAHgPAA==.',
Zi='Ziel:BAAALgAECgkJCwABLgAECgkJIwASAMgkAA==.Ziya:BAAALgADCgIJAgAAAA==.',
Zo='Zolßane:BAAALgAECgQJBAAAAA==.Zoramite:BAAALgAECgUJBQAAAA==.',
['Äl']='Älexa:BAAALgAECgkJAQAAAA==.',
['Ñö']='Ñövä:BAAALgAECgUJCwAAAA==.',
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
