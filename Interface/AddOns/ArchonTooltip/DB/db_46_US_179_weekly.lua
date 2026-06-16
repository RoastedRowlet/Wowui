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

local lookup = {'Paladin-Protection','Shaman-Restoration','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Devourer','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Mage-Frost','Mage-Fire','Warrior-Fury','Warlock-Destruction','Monk-Brewmaster','Paladin-Retribution','Warrior-Protection','Priest-Discipline','Unknown-Unknown','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Monk-Mistweaver','Shaman-Elemental','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Enhancement','Evoker-Preservation','Hunter-Marksmanship','Monk-Windwalker','Paladin-Holy','Druid-Guardian','Evoker-Augmentation','Priest-Holy','Mage-Arcane','Warrior-Arms','Rogue-Assassination',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Adhenar:BAAALgAECgMJAwAAAA==.Adow:BAAALgAECggJCQAAAA==.Adynne:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.',
Ae='Aered:BAAALgAECgcJDgAAAA==.Aerev:BAAALgAECgEJBQAAAA==.Aerylith:BAAALgAECgYJCgAAAA==.',
Af='Aften:BAAALgAECgYJCAAAAA==.',
Ah='Ahira:BAABLgAECn88AAICAAkJqiIrBwA7AwACAAkJqiIrBwA7AwAAAA==.',
Ai='Ailov:BAAALgADCgMJAwAAAA==.Ains:BAAALgAECgEJAQAAAA==.',
Ak='Akuria:BAABLgAECn9HAAIDAAkJ9iAmBQADAwADAAkJ9iAmBQADAwAAAA==.',
Al='Alacía:BAAALgAFFAIJAgAAAA==.Alahna:BAABLgAECn8dAAIEAAgJSghUfABBAQAEAAgJSghUfABBAQAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAACLgAFFH8JAAIFAAQJLwNuKQCnAAAFAAQJLwNuKQCnAAAuAAQKf0IAAwUACQkZDuQbAHkBAAUACQkZDuQbAHkBAAYABQm/Alr6AIcAAAAA.Annicution:BAAALgAECgQJCQAAAA==.Antamoon:BAABLgAECn8WAAIHAAkJ9w2BTACcAQAHAAkJ9w2BTACcAQAAAA==.',
Ao='Aox:BAABLgAECn8zAAIIAAkJmhwQCgCAAgAIAAkJmhwQCgCAAgAAAA==.',
Aq='Aquarian:BAAALgAECgYJDAAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgkJEgAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgAECgMJAwAAAA==.Asseroth:BAAALgAECgEJAQAAAA==.',
At='Atriux:BAAALgAECgkJCAAAAA==.',
Au='Aureline:BAABLgAECn80AAMJAAkJXRPRNADGAQAJAAkJXRPRNADGAQAKAAQJpAV+ZACFAAAAAA==.Aurna:BAAALgAFFAEJAQAAAA==.',
Av='Avianddrela:BAAALgADCgIJAgAAAA==.',
Ba='Babegnome:BAAALgAECgEJAgAAAA==.Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgcJEQAAAA==.',
Be='Beanfliker:BAAALgADCgIJAgAAAA==.Bearlysimple:BAAALgADCgUJBQAAAA==.Beartank:BAAALgADCgYJBgAAAA==.Beastiam:BAAALgAECgEJAwAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgADCgUJCAAAAA==.Belserion:BAACLgAFFH8QAAILAAQJwRjWGABnAQALAAQJwRjWGABnAQAuAAQKf1wAAwsACQnoJfkDAGcDAAsACQnoJfkDAGcDAAwAAQndIWEQAFQAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECgkJIQALANEfAA==.Bernir:BAAALgAECgIJAgAAAA==.Berol:BAABLgAECn8XAAINAAgJTBsEGgAcAgANAAgJTBsEGgAcAgAAAA==.Beroldin:BAAALgAECgMJAgABLgAECggJFwANAEwbAA==.Bevar:BAAALgAECgMJBQABLgAECgcJFwAOAFEKAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAIPAAYJoB7QJQDVAQAPAAYJoB7QJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAABLgAECn8aAAIFAAkJjh9sBgC4AgAFAAkJjh9sBgC4AgAAAA==.Biggieshan:BAAALgAECggJDQAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAwAAAA==.Blair:BAAALgAECgEJBAAAAA==.Blindmafaka:BAAALgAECgYJEAAAAA==.Blkrend:BAACLgAFFH8GAAIFAAMJ3CDLGAAbAQAFAAMJ3CDLGAAbAQAuAAQKf00AAgUACQkrJicBAFUDAAUACQkrJicBAFUDAAAA.Bloodhound:BAAALgAECgYJBgAAAA==.Bluntz:BAAALgAECgEJAQAAAA==.Blurtaxes:BAAALgAECgcJAgABLgAFFAIJBQAGAJ4VAA==.',
Bo='Bonko:BAAALgAECgMJAwAAAA==.',
Br='Bradycam:BAABLgAECn9IAAIQAAkJRyJFCQAcAwAQAAkJRyJFCQAcAwAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brewmaster:BAAALgAECgcJCAAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruceelee:BAAALgADCgMJAwAAAA==.Bruddah:BAAALgAFFAIJAwABLgAFFAMJDAARAPMKAA==.Brycefotm:BAAALgAECgcJBwABLgAFFAQJDgACAKQbAA==.',
Bu='Bubblebutt:BAAALgAECgUJBQAAAA==.Bulloo:BAAALgAECgEJBAAAAA==.Busterblader:BAAALgAECgQJCQAAAA==.',
['Bó']='Bóbafett:BAAALgADCgEJAQAAAA==.',
Ca='Cadovenia:BAAALgAECgEJBAAAAA==.Camillerose:BAAALgAECgQJBAAAAA==.Cantpalyhard:BAAALgAECgYJCQABLgAFFAQJEgACAOoPAA==.Carebeär:BAABLgAECn8gAAIJAAcJ6hcYNgDPAQAJAAcJ6hcYNgDPAQAAAA==.Carpediems:BAAALgADCgIJAQAAAA==.Casella:BAABLgAECn8/AAIPAAkJkSCNBgDPAgAPAAkJkSCNBgDPAgAAAA==.',
Ce='Celissara:BAABLgAECn8WAAISAAYJgxPpMQBRAQASAAYJgxPpMQBRAQABLgAFFAEJAQATAAAAAA==.',
Ch='Chamoo:BAAALgADCgIJBAAAAA==.Chimken:BAAALgADCgMJAwAAAA==.Chocospells:BAAALgAECgIJAgAAAA==.Chogori:BAAALgAECgQJCgAAAA==.Chôsenône:BAAALgAECgUJBgAAAA==.',
Ci='Cierdwyn:BAAALgAECgcJDAAAAA==.Cinnaßon:BAAALgAECgQJBAAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAABLgAECn83AAIQAAkJwSDiDAD8AgAQAAkJwSDiDAD8AgAAAA==.Clouzot:BAAALgADCgkJEQAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAABLgAECn9FAAIUAAkJFg1/CAClAQAUAAkJFg1/CAClAQAAAA==.',
Cp='Cptbarnacles:BAABLgAECn8fAAQVAAcJpRDZIAC1AAAWAAQJSg41vADRAAAVAAQJshDZIAC1AAAOAAMJzwx0KQBsAAAAAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBwAHACEdAA==.Crunchylock:BAAALgAECggJDAAAAA==.',
Cu='Cunumi:BAAALgAECgQJBAAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Damachi:BAABLgAECn8xAAMXAAkJaBgcBgBHAgAXAAkJEhgcBgBHAgAGAAgJ5xC1dwByAQAAAA==.Danskan:BAABLgAECn8ZAAIYAAYJ+hcBFgBjAQAYAAYJ+hcBFgBjAQAAAA==.Darkvale:BAAALgAFFAEJAwAAAA==.Darkñess:BAAALgAECggJDQAAAA==.Darmorae:BAABLgAECn8jAAIZAAkJsRX+FAD8AQAZAAkJsRX+FAD8AQAAAA==.Dashii:BAAALgAECgEJAgAAAA==.Datewoo:BAABLgAECn8mAAIQAAgJ6BLbYgCoAQAQAAgJ6BLbYgCoAQAAAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deathris:BAAALgAECgcJBwAAAA==.Deef:BAAALgAECgYJDgAAAA==.Demilia:BAAALgAECgQJBAAAAA==.Demontotem:BAAALgAECgkJEAAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desadeness:BAAALgADCgUJCgABLgADCgkJNAATAAAAAA==.Desertpunk:BAAALgAECgEJAQAAAA==.Destrolock:BAAALgAECgYJCwABLgAFFAMJCgAQAH4XAA==.Dez:BAAALgAECgYJBgABLgAECgkJJQAGAKUHAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECggJEgAAAA==.',
Do='Donkaßutts:BAAALgAECgQJDgAAAA==.Dooda:BAAALgAECgYJDAAAAA==.Doodooboi:BAAALgAECgQJBQAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECggJEAAAAA==.Dooretos:BAAALgADCgEJAQAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracbow:BAABLgAECn8XAAIEAAgJFBPmSgC8AQAEAAgJFBPmSgC8AQABLgAFFAMJBwAGAM4IAA==.Dracdemonica:BAAALgAECgIJAgABLgAFFAMJBwAGAM4IAA==.Dracfu:BAABLgAECn8XAAIaAAgJpgdOXAD7AAAaAAgJpgdOXAD7AAABLgAFFAMJBwAGAM4IAA==.Drackpally:BAAALgAECgcJBAAAAA==.Dracserion:BAAALgAFFAEJAgABLgAFFAQJEAALAMEYAA==.Dracsham:BAAALgADCgEJAQABLgAFFAMJBwAGAM4IAA==.Dracsknight:BAACLgAFFH8HAAIGAAMJzgh0rADEAAAGAAMJzgh0rADEAAAuAAQKfxwAAgYACQlGEhpBAP0BAAYACQlGEhpBAP0BAAAA.Dracslana:BAAALgAECgYJEAABLgAFFAMJBwAGAM4IAA==.Draffel:BAABLgAECn8hAAMCAAkJuxsUEwCxAgACAAkJuxsUEwCxAgAbAAEJxQEOwQAVAAAAAA==.Drathi:BAABLgAECn8jAAMGAAgJCxrkNQAkAgAGAAcJCxrkNQAkAgAFAAgJMBCgIgA7AQAAAA==.Drestla:BAAALgAECgcJCwAAAA==.Drothikus:BAAALgAECgMJAwAAAA==.Drowgon:BAABLgAECn8YAAMNAAgJEhfLMgB/AQANAAcJORjLMgB/AQARAAcJ8g2DKwDYAAAAAA==.Drtot:BAAALgAECgEJAgAAAA==.Druwgon:BAAALgAECgIJAgAAAA==.',
Du='Duartor:BAAALgAECgIJAgAAAA==.Dukalune:BAAALgAECgUJCQAAAA==.Dukaos:BAACLgAFFH8UAAIHAAUJjhFvSAAJAQAHAAUJjhFvSAAJAQAuAAQKfzoABAcACAmgHaYiAEMCAAcACAmgHaYiAEMCABwABAlCDWQaAMEAAB0AAgmDFFtlAD4AAAAA.Dukazil:BAAALgADCgYJBgAAAA==.Dunzer:BAACLgAFFH8SAAIQAAQJMxCERgAaAQAQAAQJMxCERgAaAQAuAAQKf0sAAxAACQksGxkiAHwCABAACQksGxkiAHwCAAEAAglDCR5GAEkAAAAA.Dunzerblaze:BAAALgAECgQJCQAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAABLgAECn8hAAIJAAgJJBs7HQBZAgAJAAgJJBs7HQBZAgAAAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgAECgEJAQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8hAAILAAgJ0R/wOgCLAgALAAgJ0R/wOgCLAgAAAA==.',
Eh='Ehonda:BAAALgAECgUJBQABLgAECgkJGQAFAJQPAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAABLgAECn8ZAAIeAAkJrB8PBQC6AgAeAAkJrB8PBQC6AgAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAAALgAECgYJEAAAAA==.Emolock:BAAALgAECgUJBQAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgADCgcJBwAAAA==.',
Eo='Eon:BAAALgAECgUJDwAAAA==.',
Ep='Epiphaný:BAAALgAECgYJCwAAAA==.',
Er='Eradoria:BAABLgAECn8UAAIdAAYJQgXmRADiAAAdAAYJQgXmRADiAAAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgAECgQJBAAAAA==.',
Es='Essylt:BAAALgAECgQJCgAAAA==.Este:BAAALgADCgQJBAAAAA==.',
Ev='Evadne:BAAALgAECggJDwAAAA==.Evagrius:BAAALgAECgUJBQAAAA==.Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAABLgAECn8cAAIfAAkJ0wk+FQB0AQAfAAkJ0wk+FQB0AQAAAA==.',
Ex='Exidore:BAAALgAECgcJDAAAAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAATAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Falchionx:BAAALgAECgUJDAABLgAECggJIQAJACQbAA==.Falfogan:BAAALgAECgEJAgAAAA==.Fangy:BAAALgAECgQJCAAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felserion:BAAALgADCgEJAgABLgAFFAQJEAALAMEYAA==.Fenn:BAABLgAECn9HAAIbAAkJ5BxXCgC3AgAbAAkJ5BxXCgC3AgAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Firechicken:BAAALgAECgcJBwAAAA==.Fistantillus:BAAALgAECgcJCwAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flnx:BAAALgAECgEJAgABLgAECggJIQAJACQbAA==.Flopper:BAAALgAECgYJCwAAAA==.',
Fo='Fonddle:BAAALgADCgUJCQAAAA==.Forthelight:BAAALgAFFAEJAQABLgAFFAQJEAALAAwYAA==.Foxyboo:BAACLgAFFH8SAAICAAQJ6g+4PgDiAAACAAQJ6g+4PgDiAAAuAAQKf00AAwIACQmNIFMGAEkDAAIACQmNIFMGAEkDABsAAQnzBQG4ACEAAAAA.',
Fr='Freak:BAABLgAECn8YAAMJAAgJHhI+QgCFAQAJAAgJHhI+QgCFAQAKAAYJsgk6TQD1AAAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.Frorly:BAAALgAECgEJAQAAAA==.',
Fu='Fulv:BAAALgAECgUJEAAAAA==.',
['Fâ']='Fâith:BAAALgAECgUJDgAAAA==.',
Ga='Gaezßuleaux:BAAALgAECgUJCgAAAA==.Galerodra:BAAALgADCgEJAQAAAA==.Galorani:BAAALgADCgIJAgAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAAALgAECgcJEgAAAA==.',
Ge='Gertroz:BAAALgAECgUJCAABLgAFFAEJAQATAAAAAA==.',
Gi='Gimic:BAAALgAECgkJEwAAAA==.',
Gn='Gnomatic:BAAALgAECgIJBgABLgAECgkJJQAGAKUHAA==.Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn82AAIEAAkJLSX/BAA/AwAEAAkJLSX/BAA/AwAAAA==.Gope:BAABLgAECn8lAAMCAAkJRBf9IABFAgACAAkJRBf9IABFAgAbAAQJ3gZMdgBpAAAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Graazer:BAAALgAECgIJAgAAAA==.Green:BAABLgAECn8WAAIZAAgJSxcbCQBUAgAZAAgJSxcbCQBUAgAAAA==.Grewsome:BAAALgAECgQJBAAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn9EAAMZAAkJUSRRAQBSAwAZAAkJLSRRAQBSAwAgAAgJ3R0MEgCoAgAAAA==.Gromyr:BAAALgAECgEJAQABLgAECgkJRAAZAFEkAA==.Grr:BAABLgAECn8rAAIHAAkJZiHnCwDlAgAHAAkJZiHnCwDlAgAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gä']='Gärrus:BAAALgAECgQJBAAAAA==.',
['Gó']='Gójira:BAABLgAECn8bAAIQAAkJFgfZswAXAQAQAAkJFgfZswAXAQAAAA==.',
Ha='Hartis:BAABLgAECn8sAAQEAAkJERDKLgD2AQAEAAkJERDKLgD2AQAZAAIJqwQnVABZAAAgAAQJ5wBdewBWAAAAAA==.Hashmal:BAAALgAECgUJBwAAAA==.Hazo:BAABLgAECn8iAAMPAAYJbgnxXwCOAAAPAAUJcQrxXwCOAAAhAAMJqAQbbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Hectabali:BAAALgADCgYJBQAAAA==.Heizou:BAAALgAECgYJBwABLgAFFAMJDAAGAMkOAA==.Hellkat:BAAALgAECgcJDAAAAA==.',
Hi='Higarosa:BAAALgADCgIJBAAAAA==.Highbull:BAAALgAECgUJBQAAAA==.Hild:BAAALgAECgkJAQAAAA==.',
Ho='Holiblade:BAABLgAECn84AAIQAAgJ7gmCpwApAQAQAAgJ7gmCpwApAQAAAA==.Holyfaxiss:BAEBLgAECn8kAAIiAAgJFCGbCAD/AgAiAAgJFCGbCAD/AgABLgAECggJNQANACIkAA==.Holyhannah:BAAALgAECgUJBgAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJCgAAAA==.Holywhiskers:BAAALgADCgYJBgABLgAECgkJTgAQAHkhAA==.Hooligun:BAABLgAECn8vAAIbAAkJNQ8aMAB8AQAbAAkJNQ8aMAB8AQAAAA==.Hoppered:BAAALgAECgUJBgABLgAECgkJPAAVAOAiAA==.',
Hu='Huntinpowerz:BAAALgAECgEJAQAAAA==.Huntlord:BAAALgADCgcJBwAAAA==.',
Hy='Hypérian:BAAALgAECgQJBgAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAABLgAECn8TAAIEAAkJSBt1PgC1AQAEAAkJSBt1PgC1AQAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAABLgAECn8kAAIBAAcJKROpGABTAQABAAcJKROpGABTAQAAAA==.',
Ih='Ihatereports:BAAALgAECgQJCAABLgAFFAMJCQAZAKsMAA==.',
Ij='Ijustshotyou:BAACLgAFFH8JAAMZAAMJqwyzHwDUAAAZAAMJqwyzHwDUAAAEAAIJzAehhwCGAAAuAAQKfxYABCAACAnQEX4RAD4BACAABwl3En4RAD4BABkAAglBDu1NAHYAAAQAAgm+Dp3yAGgAAAAA.',
Il='Illyría:BAAALgADCgcJBwAAAA==.Ilovetouka:BAAALgAECgMJBQAAAA==.',
Ir='Ironlotss:BAAALgADCgkJDQAAAA==.',
Iz='Izumo:BAAALgAECgQJCQAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAFFAQJBwAWAJwSAA==.Jakob:BAAALgAECgEJAwAAAA==.Jaks:BAAALgADCgEJAQAAAA==.Jardal:BAAALgADCgkJFgAAAA==.Jatswamdi:BAAALgAECgYJBgAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAABLgAECn8iAAIEAAgJ2w8nYgB9AQAEAAgJ2w8nYgB9AQAAAA==.Jenanila:BAAALgAECgMJBAAAAA==.',
Jh='Jhenna:BAAALgAECgQJBgABLgAECgkJLwAJAB8WAA==.',
Ji='Jibbs:BAABLgAECn8lAAMGAAkJpQfulgA4AQAGAAgJXQjulgA4AQAFAAEJmAICZwAZAAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwATAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJEAAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jolah:BAAALgAECgIJAgAAAA==.Jollakeratu:BAABLgAECn9FAAIjAAkJ+hTjDgDxAQAjAAkJ+hTjDgDxAQAAAA==.Jonnygordo:BAABLgAECn8VAAIQAAYJBg57xAD/AAAQAAYJBg57xAD/AAAAAA==.Jorahh:BAABLgAECn8XAAMbAAcJHRZ4NABmAQAbAAYJHRZ4NABmAQACAAcJ2QysYAAJAQAAAA==.',
Ju='Jugernawt:BAAALgAECgEJAQABLgAECgkJMQABAMcaAA==.Jugram:BAAALgAECgQJBAAAAA==.Jungolv:BAAALgADCgMJAwAAAA==.Jusmissiner:BAABLgAECn8iAAIEAAkJxx5yFgCEAgAEAAkJxx5yFgCEAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAABLgAECn8eAAIFAAkJKRsXEQD3AQAFAAkJKRsXEQD3AQAAAA==.',
['Jø']='Jønty:BAAALgADCgkJFgAAAA==.',
Ka='Kaelyra:BAAALgADCgkJFgAAAA==.Kaitenn:BAAALgAECgYJBgAAAA==.Kamehame:BAAALgAECggJEgAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECgkJQQACAFciAA==.',
Ke='Keelhorn:BAABLgAECn8lAAMCAAkJGRSQMgDlAQACAAkJGRSQMgDlAQAbAAMJgwcaeQB+AAAAAA==.Kenneth:BAABLgAECn8bAAIQAAcJshJigQBpAQAQAAcJshJigQBpAQAAAA==.Kessarah:BAAALgAECgkJAgAAAA==.Kevin:BAAALgAECgYJDAABLgAFFAUJDwAKAIgcAA==.Keyadorath:BAAALgADCgIJAgAAAA==.',
Ki='Kibon:BAABLgAECn8ZAAMOAAYJsgbfJwB0AAAWAAYJ9AWcwwDGAAAOAAQJfgTfJwB0AAAAAA==.Kindabored:BAAALgADCggJCAABLgAFFAQJDwAJAPMHAA==.Kinkyhawt:BAEBLgAECn8WAAMkAAYJkh2hKgCSAQAUAAUJchuiFQCUAQAkAAYJ+RyhKgCSAQAAAA==.Kirio:BAAALgADCgcJCgAAAA==.Kitsunenohi:BAABLgAECn85AAIdAAkJJgn9JABMAQAdAAkJJgn9JABMAQAAAA==.',
Ko='Kodiakk:BAABLgAECn8lAAIZAAgJqBSgGwDAAQAZAAgJqBSgGwDAAQAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Krattos:BAAALgAECgIJBgAAAA==.Krechon:BAAALgADCgQJBAAAAA==.Krimzin:BAAALgAECgEJAgABLgAFFAUJGgAEADAhAA==.',
Ks='Ksares:BAAALgAECgIJAgABLgAECgkJUAAEANwhAA==.',
Ku='Kuddles:BAAALgADCgEJBwAAAA==.Kumei:BAAALgAECgEJAQABLgAECgkJLAAEABEQAA==.Kural:BAAALgAECgUJBgABLgAECggJKAABAJsjAA==.',
Kw='Kwazii:BAABLgAECn8mAAQlAAgJ/BcVHgDQAQAlAAgJ/BcVHgDQAQADAAYJ+wU+UgDGAAASAAIJJAWqagBTAAAAAA==.',
Ky='Kyantzmi:BAABLgAECn8aAAIIAAYJMA+NJgBeAQAIAAYJMA+NJgBeAQAAAA==.Kyogre:BAABLgAECn8aAAIKAAcJuhJpMQBSAQAKAAcJuhJpMQBSAQAAAA==.',
La='Laefnia:BAACLgAFFH8JAAQKAAMJ8xG0LQDJAAAKAAMJ8xG0LQDJAAAJAAEJ0w9EbQA3AAAjAAEJAwpWOwAyAAAuAAQKfzQABQoACQnUGgMRAFECAAoACQmYGQMRAFECAAkACAnUGWAwAN4BACMABQmfGOcdAFgBABgAAQk0Bn01AC4AAAEuAAUUAwkMAAYAyQ4A.Lapisal:BAAALgADCgEJAQAAAA==.Laraydra:BAAALgAECgUJDAABLgAFFAEJAQATAAAAAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJGQAhAD4QAA==.Lavaburstya:BAAALgAECgcJDAAAAA==.',
Le='Leomist:BAABLgAECn8ZAAIaAAkJVw+fMACwAQAaAAkJVw+fMACwAQAAAA==.Leviosä:BAABLgAECn8+AAMLAAkJOxgdMABWAgALAAkJOxgdMABWAgAMAAEJ2wYkFgAiAAAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgADCgkJHQAAAA==.Lilis:BAAALgAECgMJAwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8uAAIGAAkJZCQaDAAKAwAGAAkJZCQaDAAKAwAAAA==.Liten:BAAALgADCggJFQAAAA==.Littlebev:BAABLgAECn8XAAIOAAcJUQqHFgDsAAAOAAcJUQqHFgDsAAAAAA==.',
Lo='Lockins:BAAALgAECgYJBwAAAA==.Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJBwAAAA==.Longshankss:BAAALgAECgYJDgAAAA==.',
Ly='Lynaiya:BAAALgADCgMJAwAAAA==.',
['Lé']='Léxí:BAAALgAECgkJCQAAAA==.',
['Lí']='Lírii:BAAALgAECggJEgAAAA==.',
['Lô']='Lôôbmeup:BAAALgADCgEJAQAAAA==.',
Ma='Maachen:BAAALgAECgYJCwAAAA==.Maalik:BAABLgAECn9RAAQVAAkJ7CCQAQDgAgAVAAkJpSCQAQDgAgAOAAcJfxrHCQClAQAWAAMJgw5s+QBuAAAAAA==.Magejackky:BAAALgAECgQJCAAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Maivorkeru:BAAALgAECgQJBgAAAA==.Malaurray:BAABLgAECn8jAAIWAAgJbQwIcABZAQAWAAgJbQwIcABZAQABLgABCgQJBgATAAAAAA==.Maluin:BAAALgAECgEJAgABLgAECgkJQAAcAOMaAA==.Mavanta:BAAALgAECgMJBAAAAA==.Mayonæse:BAABLgAECn8dAAIHAAUJRAwmmADsAAAHAAUJRAwmmADsAAAAAA==.',
Mc='Mcchong:BAAALgAECgYJEgAAAA==.Mckennah:BAABLgAECn8eAAMBAAgJbiF5BgB7AgABAAgJbiF5BgB7AgAQAAEJDgx7nwEsAAAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAFFAQJCwALAPQQAA==.Mereidith:BAACLgAFFH8LAAILAAQJ9BDtWgAzAQALAAQJ9BDtWgAzAQAuAAQKfywAAwsABwmCHKBOAOwBAAsABwmCHKBOAOwBACYAAQlyGhMZAE8AAAAA.Meshulk:BAAALgAECgEJAQAAAA==.Mesohungry:BAABLgAECn8uAAMiAAkJiQk3OgBeAQAiAAkJiQk3OgBeAQAQAAIJzAE0rAEoAAAAAA==.Metasploit:BAAALgAECgkJAQAAAA==.',
Mi='Mikehunte:BAAALgAECgYJBgABLgAECgkJIQALANEfAA==.Miriya:BAABLgAECn8jAAIPAAkJyCRsAgA2AwAPAAkJyCRsAgA2AwAAAA==.Missnoms:BAAALgAECgEJAQAAAA==.',
Mo='Monkeycheese:BAABLgAECn8ZAAIhAAcJPhCXOgATAQAhAAcJPhCXOgATAQAAAA==.Moobáca:BAAALgAECgUJBwAAAA==.Moostradamas:BAABLgAECn8kAAMXAAkJywZvFgAiAQAXAAkJywZvFgAiAQAGAAIJsgDRmAEfAAAAAA==.Morcilla:BAAALgAECggJEwAAAA==.Morticyde:BAAALgAECgMJBAAAAA==.',
Ms='Msg:BAABLgAECn8lAAIJAAkJrBuZFACjAgAJAAkJrBuZFACjAgAAAA==.',
Mu='Munassa:BAAALgADCgcJBwAAAA==.Muppets:BAAALgAECgUJCQAAAA==.',
My='Myssidia:BAAALgADCgkJFQAAAA==.',
['Mí']='Mínervä:BAAALgAECgkJEAAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgIJAwAAAA==.Nasdaralth:BAAALgAECgMJAwABLgAFFAEJAQATAAAAAA==.Nastrodamus:BAAALgAECgEJAQAAAA==.Naturegoob:BAABLgAECn8bAAMJAAgJphogNADYAQAJAAgJphogNADYAQAKAAMJ4REuXACgAAAAAA==.Naughtynurse:BAABLgAECn9EAAIJAAkJixJ8KwD6AQAJAAkJixJ8KwD6AQAAAA==.Nayee:BAAALgADCgUJBQAAAA==.',
Ne='Nemrak:BAAALgAFFAIJAgAAAA==.Neuma:BAABLgAECn8UAAIQAAQJBAt+AgGxAAAQAAQJBAt+AgGxAAAAAA==.',
Ni='Nicfurry:BAAALgADCgMJAwAAAA==.Nightflower:BAABLgAECn8kAAMmAAkJUwUhDwDRAAALAAcJGQWExgD8AAAmAAYJAwQhDwDRAAAAAA==.',
No='Noided:BAAALgAECgYJCgAAAA==.Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgYJDwABLgAECgYJEAATAAAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
Ob='Obiejuan:BAACLgAFFH8GAAIQAAMJBw3rcgDHAAAQAAMJBw3rcgDHAAAuAAQKf1EAAxAACQngIkANAPkCABAACQngIkANAPkCAAEABAmgHm0hAAYBAAAA.Obietide:BAAALgAECgkJEQABLgAFFAMJBgAQAAcNAA==.',
Od='Oddball:BAABLgAECn8eAAIbAAkJBhzfGAAZAgAbAAkJBhzfGAAZAgAAAA==.',
Of='Ofthecircle:BAAALgAECggJEwAAAA==.',
Ok='Okamiblooded:BAAALgAECggJEQAAAA==.',
Ol='Olly:BAAALgAECgYJDQAAAA==.',
On='Ontala:BAAALgADCgYJBgAAAA==.',
Oo='Oodles:BAAALgAECgcJEgAAAA==.',
Op='Ophiron:BAAALgAECgUJBgAAAA==.',
Or='Orangecrush:BAAALgAECgYJEAAAAA==.Orangekeg:BAAALgAECgUJEQABLgAECgkJIQAbANgfAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAAALgAECgcJEwAAAA==.',
Pa='Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn88AAIFAAkJ2R0fCgBvAgAFAAkJ2R0fCgBvAgABLgAECggJKAABAJsjAA==.Peso:BAAALgAECgQJBwAAAA==.Pez:BAAALgAECgYJEQABLgAECgkJLwAJAB8WAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAABLgAFFH8YAAIaAAcJrRNfEQD0AQAaAAcJrRNfEQD0AQABLgAFFAQJCAAiAGESAA==.Pomater:BAAALgAECgYJDgABLgAFFAEJAQATAAAAAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAABLgAECn8YAAILAAgJOQnKmwA/AQALAAgJOQnKmwA/AQAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECgkJLAACALQgAA==.',
Pr='Primafox:BAAALgAECgYJDAAAAA==.Prkchopxpres:BAAALgAECgYJDwAAAA==.Protoheal:BAAALgAECgEJAgAAAA==.',
Pu='Punchandkick:BAAALgAECgMJBgAAAA==.Punkweight:BAAALgAECgEJAQAAAA==.Purpleeater:BAAALgAECgIJBQAAAA==.',
Py='Pyrabanks:BAAALgAFFAQJBAAAAA==.',
['Pä']='Päw:BAACLgAFFH8MAAMGAAMJyQ79pADNAAAGAAMJyQ79pADNAAAXAAIJMAX9IAB1AAAuAAQKfy0ABAYACQm2HOhRAMsBAAYACAmhF+hRAMsBAAUABQnEHGYgAE0BABcAAwnGHL4ZAAABAAAA.',
Qu='Quetzalcóatl:BAAALgAECgQJBAAAAA==.Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJAgAAAA==.',
Qx='Qx:BAAALgADCggJDgAAAA==.',
Ra='Raakoth:BAAALgAECgUJDAABLgAECgkJUQAVAOwgAA==.Radge:BAABLgAECn83AAMnAAkJoiUIAQBmAwAnAAkJoiUIAQBmAwANAAMJKR0rdgDiAAAAAA==.Rainjar:BAACLgAFFH8VAAMZAAQJiiEiEwAuAQAZAAMJnyEiEwAuAQAEAAIJkBvwcwCnAAAuAAQKfzwAAxkACQkAIl4CAB8DABkACQlcH14CAB8DAAQACAk3JHoSALoCAAAA.Rainne:BAAALgADCgcJCAAAAA==.Raistyn:BAABLgAECn8pAAMBAAkJwRyaCwAIAgABAAkJwRyaCwAIAgAQAAEJigxaoQErAAAAAA==.Ralanar:BAAALgAECgcJDgABLgAFFAEJAQATAAAAAA==.Raljah:BAABLgAECn88AAQVAAkJ4CL/AAAHAwAVAAkJ1CL/AAAHAwAWAAcJ7B5yKQAzAgAOAAUJXh19FACnAQAAAA==.Ramasus:BAAALgAECgUJBQAAAA==.Rampart:BAABLgAECn8xAAMBAAkJxxpHBwBnAgABAAkJxxpHBwBnAgAQAAEJ5w55igEyAAAAAA==.Rasaltghul:BAAALgAECgEJAQABLgAECgMJBgATAAAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.Raxxer:BAAALgAECgEJBAAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAABLgAECn8UAAMBAAcJtw1QJwDYAAAQAAcJ9geAzQDzAAABAAYJbg5QJwDYAAAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Renm:BAAALgAECgYJEgAAAA==.Renpriest:BAACLgAFFH8UAAISAAMJfx7JKAD/AAASAAMJfx7JKAD/AAAuAAQKfxUAAxIACAmMGVIRAC4CABIACAmMGVIRAC4CAAMAAQk4Fet+ADoAAAAA.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgkJEQAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.Royaldüh:BAACLgAFFH8GAAIHAAIJ7wVCiQBpAAAHAAIJ7wVCiQBpAAAuAAQKfxcAAgcABwlCFYBeAGkBAAcABwlCFYBeAGkBAAAA.',
Ry='Ryobi:BAABLgAECn8/AAMgAAkJuhhrCADyAQAEAAkJ9BTSMQAQAgAgAAgJDRhrCADyAQAAAA==.Ryptyde:BAABLgAECn8WAAICAAkJ7h6mBwAyAwACAAkJ7h6mBwAyAwAAAA==.',
['Ræ']='Rævena:BAABLgAECn8VAAIGAAYJOgpixgDyAAAGAAYJOgpixgDyAAAAAA==.',
Sa='Sachaann:BAAALgAECgIJAwAAAA==.Salinan:BAACLgAFFH8GAAMVAAMJDRKzDQCiAAAWAAMJewtlewDIAAAVAAIJ1BWzDQCiAAAuAAQKf1EAAxUACQncJLkAACQDABUACQm3JLkAACQDABYABgntGkdVAJsBAAAA.Saltymon:BAAALgADCgYJBgABLgAECgIJAwATAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgkJMwAIAJocAA==.Saradia:BAAALgADCgIJAgAAAA==.Saric:BAAALgAECgMJBwAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Scanor:BAAALgAECgYJDAABLgAFFAMJDQAkAM4CAA==.Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.',
Se='Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAABLgAECn8kAAIQAAkJ9xtrHwCJAgAQAAkJ9xtrHwCJAgAAAA==.Selky:BAAALgADCgcJCgAAAA==.',
Sf='Sfodin:BAABLgAECn8eAAINAAgJKQmAPwBGAQANAAgJKQmAPwBGAQAAAA==.',
Sh='Shadowkings:BAAALgAFFAEJAwAAAA==.Shak:BAABLgAECn8gAAIbAAYJ0A7ySwABAQAbAAYJ0A7ySwABAQAAAA==.Shalai:BAAALgADCgMJAwAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shastix:BAAALgAECgYJEgABLgAECgkJUQAVAOwgAA==.Shellingtun:BAAALgAECgYJCwAAAA==.Shyandrial:BAAALgAECgQJBQAAAA==.Shyness:BAAALgAECgQJBAAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAABLgAECn8rAAMDAAgJ1gvSMgBNAQADAAgJ1gvSMgBNAQAlAAQJtghtUwCKAAAAAA==.',
Sk='Skilltotem:BAAALgAECgkJEAAAAA==.Skk:BAAALgADCggJCQAAAA==.Sksteve:BAAALgAECgUJDwAAAA==.Skullyy:BAAALgAECgYJDgABLgAECgYJEAATAAAAAA==.Skychades:BAABLgAECn8WAAIEAAgJcBeIQQDZAQAEAAgJcBeIQQDZAQAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAABLgAECn8cAAIKAAcJohAvOAAvAQAKAAcJohAvOAAvAQAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECgcJCQABLgAECgcJHAAKAKIQAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgAECgcJDwAAAA==.Soulsrequiem:BAABLgAECn8nAAIoAAgJ9gF5GQCdAAAoAAgJ9gF5GQCdAAAAAA==.',
Sp='Spicyblaster:BAABLgAFFH8QAAILAAQJDBgXSwBQAQALAAQJDBgXSwBQAQAAAA==.Spookydeath:BAACLgAFFH8YAAILAAUJXg3mYwAkAQALAAUJXg3mYwAkAQAuAAQKfy4AAgsACQmrEnxIAP8BAAsACQmrEnxIAP8BAAAA.',
Sr='Srsnacksalot:BAABLgAECn8pAAIQAAgJ9hjVSQDmAQAQAAgJ9hjVSQDmAQAAAA==.',
St='Stileto:BAAALgAECgcJDgAAAA==.Stonedhuntar:BAAALgAECgcJBwAAAA==.Stoneydracco:BAABLgAECn8gAAILAAcJUBNlfwB1AQALAAcJUBNlfwB1AQAAAA==.Stoneydragon:BAAALgADCgYJBgAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECggJEgAAAA==.',
Su='Sukiliana:BAAALgAECgQJBQAAAA==.Sumtinwng:BAABLgAECn84AAIQAAkJDxKJRgDwAQAQAAkJDxKJRgDwAQAAAA==.Supervicious:BAABLgAECn8ZAAIRAAkJuxXPEwCwAQARAAkJuxXPEwCwAQAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgkJFgAAAA==.Sylenne:BAABLgAECn8vAAIJAAkJHxY+HwBJAgAJAAkJHxY+HwBJAgAAAA==.Sylur:BAAALgAECgcJDwABLgAECggJIQAJACQbAA==.Syrayvianda:BAAALgADCgYJBgAAAA==.',
['Sÿ']='Sÿlvanah:BAAALgAECgQJBAAAAA==.',
Ta='Taemea:BAAALgAECggJEgAAAA==.Tahran:BAAALgAECgEJAQABLgAFFAYJHgASAAwVAA==.Tahren:BAACLgAFFH8eAAQSAAYJDBWAFwCsAQASAAYJVhCAFwCsAQAlAAQJBRWcEgAwAQADAAIJZgtAMAB/AAAuAAQKfyoABCUACQmIIHMQAGECACUABwn0IHMQAGECABIACQlvEw8yAFABAAMABwllEFBJAOcAAAAA.Talanima:BAAALgADCgcJBwAAAA==.Taler:BAAALgAFFAEJAQAAAA==.Talerion:BAAALgAECgcJEgAAAA==.Talyaine:BAAALgAECgUJBQABLgAFFAMJDAAGAMkOAA==.Tanzanitia:BAAALgAECgYJBgAAAA==.',
Tc='Tcdots:BAAALgAECgEJAgAAAA==.',
Te='Telline:BAAALgADCgYJBwAAAA==.Tens:BAABLgAECn8bAAINAAgJJiNXDAD1AgANAAgJJiNXDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECggJEgAAAA==.Theafflictor:BAAALgAECgYJCQAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECggJEgATAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thistelbear:BAABLgAECn9CAAIhAAkJmw2vJQCDAQAhAAkJmw2vJQCDAQAAAA==.Thrallsux:BAAALgAECgEJAgAAAA==.Thraun:BAAALgAECgYJEgAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn80AAMQAAkJsBKiagCpAQAQAAkJsBKiagCpAQABAAcJaAupJQDkAAAAAA==.',
Ti='Titszilla:BAAALgAECgcJAwAAAA==.',
To='Toki:BAABLgAECn8bAAMaAAYJxxtkLQDBAQAaAAYJxxtkLQDBAQAhAAQJqg+ZTQDbAAAAAA==.Tokidormi:BAABLgAECn8gAAMfAAgJZx0mBgCkAgAfAAgJZx0mBgCkAgAUAAQJrBB7EQDuAAAAAA==.Toralus:BAAALgADCgYJCQAAAA==.Totumm:BAAALgADCgcJCAAAAA==.',
Tr='Tralku:BAAALgAECgcJDAAAAA==.Tremmørs:BAABLgAECn8aAAIbAAcJUQxcUADxAAAbAAcJUQxcUADxAAAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAABLgAECn8UAAIQAAkJghbgXgCxAQAQAAkJghbgXgCxAQAAAA==.',
Tu='Turnip:BAAALgAECgEJAQAAAA==.',
Tw='Tweak:BAAALgAECgIJAgAAAA==.Tweis:BAAALgADCgYJEQAAAA==.',
Ty='Tyllinor:BAAALgADCgUJBQAAAA==.',
Um='Umbrarogue:BAABLgAECn8eAAMIAAkJOBzmEAAfAgAIAAkJ0RrmEAAfAgAoAAEJPh0pIQBVAAAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEwAAAA==.',
Va='Vaara:BAAALgAECgEJAgAAAA==.Valaa:BAAALgAECggJCQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAABLgAECn8WAAIQAAkJyA4CcgCYAQAQAAkJyA4CcgCYAQAAAA==.Veliya:BAAALgAECgYJEwABLgAECgkJLwAJAB8WAA==.Vellestrix:BAAALgAECgQJBAAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Veriity:BAAALgAECgUJBQAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Vicotr:BAAALgAFFAEJAQAAAA==.Viddysouls:BAABLgAECn8hAAIeAAgJtRI3EQCbAQAeAAgJtRI3EQCbAQAAAA==.Viscerai:BAABLgAECn84AAIlAAkJiSU+AQCzAwAlAAkJiSU+AQCzAwAAAA==.Vite:BAAALgAECgYJDwAAAA==.Vitta:BAAALgAECgMJAwAAAA==.',
Vo='Vonmiller:BAACLgAFFH8FAAIVAAIJLhUYEACNAAAVAAIJLhUYEACNAAAuAAQKfxsAAxUACAn9FkAGAPkBABUACAn9FkAGAPkBABYAAgkSDPf7AGIAAAAA.Vozluz:BAAALgAECgEJAQABLgAECgkJUQAVAOwgAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECgcJHAAKAKIQAA==.',
['Væ']='Væda:BAAALgAECgMJAwAAAA==.',
Wa='Warfaxis:BAEBLgAECn81AAINAAgJIiQvBwDrAgANAAgJIiQvBwDrAgAAAA==.',
We='Weird:BAAALgAECgIJAgABLgAECgkJGAAJAB4SAA==.Wereßearßirb:BAAALgADCgUJBQAAAA==.',
Wi='Winnower:BAAALgADCgYJBgAAAA==.Wiseoldgoob:BAABLgAECn8aAAQSAAkJmxkUCwC8AgASAAkJmxkUCwC8AgAlAAEJkw5jbQAyAAADAAEJ6wVaZgAsAAAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAFFAIJBAAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAFFAMJAwAAAA==.',
Ze='Zenclaw:BAABLgAECn8+AAIaAAkJiRCELADGAQAaAAkJiRCELADGAQAAAA==.Zencore:BAABLgAECn8VAAILAAgJeA9shgBnAQALAAgJeA9shgBnAQAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECggJFQALAHgPAA==.Zenlock:BAAALgADCgIJAgABLgAECggJFQALAHgPAA==.',
Zi='Ziel:BAAALgAECgkJCwABLgAECgkJIwAPAMgkAA==.Ziya:BAAALgADCgIJAgAAAA==.',
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
