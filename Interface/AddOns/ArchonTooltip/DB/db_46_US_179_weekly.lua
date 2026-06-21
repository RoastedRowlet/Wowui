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

local lookup = {'Paladin-Protection','Shaman-Restoration','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Devourer','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Mage-Frost','Mage-Fire','Warrior-Fury','Warlock-Destruction','Monk-Brewmaster','Paladin-Retribution','Warrior-Protection','Priest-Discipline','Unknown-Unknown','Evoker-Devastation','Warlock-Demonology','Warlock-Affliction','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Monk-Mistweaver','Shaman-Elemental','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Enhancement','Evoker-Preservation','Hunter-Marksmanship','Monk-Windwalker','Paladin-Holy','Druid-Guardian','Evoker-Augmentation','Priest-Holy','Mage-Arcane','Warrior-Arms','Rogue-Assassination',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-06-20',data={Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Adhenar:BAAALgAECgMJAwAAAA==.Adow:BAAALgAECggJCQAAAA==.Adynne:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.',
Ae='Aered:BAAALgAECgcJDgAAAA==.Aerev:BAAALgAECgEJBQAAAA==.Aerylith:BAAALgAECgYJCgAAAA==.',
Af='Aften:BAAALgAECgYJCAAAAA==.',
Ah='Ahira:BAABLgAECn89AAICAAkJqiJcBwA6AwACAAkJqiJcBwA6AwAAAA==.',
Ai='Ailov:BAAALgADCgMJAwAAAA==.Ains:BAAALgAECgEJAQAAAA==.',
Ak='Akuria:BAABLgAECn9QAAIDAAkJ6yEzAACdAgADAAkJ6yEzAACdAgAAAA==.',
Al='Alacía:BAAALgAFFAIJAgAAAA==.Alahna:BAABLgAECn8hAAIEAAkJgQrBbABoAQAEAAkJgQrBbABoAQAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAACLgAFFH8NAAIFAAQJLwP1KgCiAAAFAAQJLwP1KgCiAAAuAAQKf0UAAwUACQkZDmYcAHcBAAUACQkZDmYcAHcBAAYABglGA11QAVEAAAAA.Annicution:BAAALgAECgYJDgAAAA==.Antamoon:BAABLgAECn8YAAIHAAkJyg6YTQCdAQAHAAkJyg6YTQCdAQAAAA==.',
Ao='Aox:BAABLgAECn82AAIIAAkJmhxbCgB+AgAIAAkJmhxbCgB+AgAAAA==.',
Aq='Aquarian:BAAALgAECgYJDAAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgkJEgAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgAECgMJAwAAAA==.Asseroth:BAAALgAECgEJAQAAAA==.',
At='Atriux:BAAALgAECgkJCAAAAA==.',
Au='Aureline:BAABLgAECn80AAMJAAkJXRMjNQDGAQAJAAkJXRMjNQDGAQAKAAQJpAUjZgCFAAAAAA==.Aurna:BAAALgAFFAEJAgAAAA==.',
Av='Avianddrela:BAAALgADCgIJAgAAAA==.',
Ba='Babegnome:BAAALgAECgEJAgAAAA==.Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgcJEQAAAA==.',
Be='Beanfliker:BAAALgADCgIJAgAAAA==.Bearlysimple:BAAALgAECgYJBgAAAA==.Beartank:BAAALgADCgYJBgAAAA==.Beastiam:BAAALgAECgEJAwAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgADCgUJCAAAAA==.Belserion:BAACLgAFFH8QAAILAAQJwRjWGABnAQALAAQJwRjWGABnAQAuAAQKf18AAwsACQnoJT8EAGYDAAsACQnoJT8EAGYDAAwAAQndIeUQAFQAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECgkJIQALANEfAA==.Bernir:BAAALgAECgIJAgAAAA==.Berol:BAABLgAECn8YAAINAAgJTBtcGgAbAgANAAgJTBtcGgAbAgAAAA==.Beroldin:BAAALgAECgQJAwABLgAECggJGAANAEwbAA==.Bevar:BAAALgAECgMJBgABLgAECgcJGQAOAPoKAA==.Bevell:BAAALgAECgIJAgABLgAECgcJGQAOAPoKAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAIPAAYJoB7QJQDVAQAPAAYJoB7QJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAABLgAECn8aAAIFAAkJjh+kBgC1AgAFAAkJjh+kBgC1AgAAAA==.Biggieshan:BAAALgAECggJDQAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAwAAAA==.Blair:BAAALgAECgEJBAAAAA==.Blindmafaka:BAAALgAECgYJEAAAAA==.Blkrend:BAACLgAFFH8GAAIFAAMJ3CDYGQAYAQAFAAMJ3CDYGQAYAQAuAAQKf00AAgUACQkrJkABAFIDAAUACQkrJkABAFIDAAAA.Bloodhound:BAAALgAECgYJBgAAAA==.Bluntz:BAAALgAECgEJAQAAAA==.Blurtaxes:BAAALgAECgcJAgABLgAFFAIJBQAGAJ4VAA==.',
Bo='Bonko:BAAALgAECgMJAwAAAA==.',
Br='Bradycam:BAABLgAECn9LAAIQAAkJkiKeCQAbAwAQAAkJkiKeCQAbAwAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brewmaster:BAAALgAECgcJCAAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruceelee:BAAALgADCgMJAwAAAA==.Bruddah:BAAALgAFFAIJAwABLgAFFAMJDAARAPMKAA==.Brycefotm:BAAALgAECgcJBwABLgAFFAQJEgACAIQfAA==.',
Bu='Bubblebutt:BAAALgAECgUJBQAAAA==.Bulloo:BAAALgAECgIJBQAAAA==.Busterblader:BAAALgAECgYJCwAAAA==.',
['Bó']='Bóbafett:BAAALgADCgEJAQAAAA==.',
Ca='Cadovenia:BAAALgAECgEJBAAAAA==.Camillerose:BAAALgAECgQJBAAAAA==.Cantpalyhard:BAAALgAECgYJCgABLgAFFAQJGAACAIERAA==.Carebeär:BAABLgAECn8gAAIJAAcJ6hcYNgDPAQAJAAcJ6hcYNgDPAQAAAA==.Carpediems:BAAALgADCgIJAQAAAA==.Casella:BAABLgAECn8/AAIPAAkJkSC5BgDOAgAPAAkJkSC5BgDOAgAAAA==.',
Ce='Celissara:BAABLgAECn8WAAISAAYJgxN+MgBQAQASAAYJgxN+MgBQAQABLgAFFAEJAgATAAAAAA==.',
Ch='Chamoo:BAAALgADCgIJBAAAAA==.Chimken:BAAALgADCgMJAwAAAA==.Chocospells:BAAALgAECgIJAwAAAA==.Chogori:BAAALgAECgQJCgAAAA==.Chôsenône:BAAALgAECgUJBgAAAA==.',
Ci='Cierdwyn:BAAALgAECgcJDwAAAA==.Cinnaßon:BAAALgAECgQJBAAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAABLgAECn83AAIQAAkJwSBMDQD6AgAQAAkJwSBMDQD6AgAAAA==.Clouzot:BAAALgADCgkJEQAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAABLgAECn9OAAIUAAkJXA43AABlAQAUAAkJXA43AABlAQAAAA==.',
Cp='Cptbarnacles:BAABLgAECn8lAAQVAAcJhBJdBQB0AAAWAAQJshCkIQC1AAAVAAQJGhFdBQB0AAAOAAMJzwwfKgBtAAAAAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBwAHACEdAA==.Crunchylock:BAAALgAECggJDAAAAA==.Crèmeßrûlée:BAAALgAECgUJBQAAAA==.',
Cu='Cunumi:BAAALgAECgQJBAAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Dainichi:BAAALgAECgEJAgAAAA==.Damachi:BAABLgAECn80AAMXAAkJwRhVBgBDAgAXAAkJaxhVBgBDAgAGAAgJ5xBsegBuAQAAAA==.Danskan:BAABLgAECn8ZAAIYAAYJ+hd1FgBkAQAYAAYJ+hd1FgBkAQAAAA==.Darkvale:BAAALgAFFAEJAwAAAA==.Darkñess:BAAALgAECggJDQAAAA==.Darmorae:BAABLgAECn8jAAIZAAkJsRV7FQD3AQAZAAkJsRV7FQD3AQAAAA==.Dashii:BAAALgAECgMJBAAAAA==.Datewoo:BAABLgAECn8nAAIQAAgJ6BKYZQCkAQAQAAgJ6BKYZQCkAQAAAA==.Datsuo:BAAALgAECgIJAgABLgAECgkJVwAWAOwgAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deathris:BAAALgAECggJCgAAAA==.Deef:BAAALgAECgYJDgAAAA==.Demilia:BAAALgAECgQJBAAAAA==.Demontotem:BAAALgAECgkJEAAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desadeness:BAAALgADCgUJCgABLgADCgkJNAATAAAAAA==.Desertpunk:BAAALgAECgEJAQAAAA==.Destrolock:BAAALgAECgYJCwABLgAFFAMJCwAQAIIaAA==.Dez:BAAALgAECgYJBgABLgAECgkJJQAGAKUHAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECggJEgAAAA==.',
Do='Donkaßutts:BAAALgAECgQJDgAAAA==.Dooda:BAAALgAECgYJDAAAAA==.Doodooboi:BAAALgAECgQJBQAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECggJEAAAAA==.Dooretos:BAAALgADCgEJAQAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracbow:BAABLgAECn8XAAIEAAgJFBOuTAC8AQAEAAgJFBOuTAC8AQABLgAFFAMJCQAGAM4IAA==.Dracdemonica:BAAALgAECgIJAgABLgAFFAMJCQAGAM4IAA==.Dracfu:BAABLgAECn8XAAIaAAgJpge3XgD8AAAaAAgJpge3XgD8AAABLgAFFAMJCQAGAM4IAA==.Drackpally:BAAALgAECgcJBQAAAA==.Dracserion:BAAALgAFFAEJAgABLgAFFAQJEAALAMEYAA==.Dracsham:BAAALgADCgEJAQABLgAFFAMJCQAGAM4IAA==.Dracsknight:BAACLgAFFH8JAAIGAAMJzgj9sQDAAAAGAAMJzgj9sQDAAAAuAAQKfyEAAgYACQmAEiZCAPwBAAYACQmAEiZCAPwBAAAA.Dracslana:BAAALgAECgYJEAABLgAFFAMJCQAGAM4IAA==.Draffel:BAABLgAECn8hAAMCAAkJuxt4EwCwAgACAAkJuxt4EwCwAgAbAAEJxQEjxQAVAAAAAA==.Drathi:BAABLgAECn8jAAMGAAgJCxrBNgAkAgAGAAcJCxrBNgAkAgAFAAgJMBB6IwA3AQAAAA==.Drestla:BAAALgAECgcJCwAAAA==.Drothikus:BAAALgAECgMJAwAAAA==.Drowgon:BAABLgAECn8YAAMNAAgJEhc3MwB+AQANAAcJORg3MwB+AQARAAcJ8g0qLADYAAAAAA==.Drtot:BAAALgAECgEJAgAAAA==.Druidfaxxis:BAEALgAECgEJAQABLgAECggJOQANACEkAA==.Druwgon:BAAALgAECgIJAgAAAA==.Drác:BAAALgAECgIJBAABLgAFFAMJCQAGAM4IAA==.',
Du='Duartor:BAAALgAECgIJAgAAAA==.Dukalune:BAAALgAECgUJCQAAAA==.Dukaos:BAACLgAFFH8VAAIHAAUJjhEaSwAIAQAHAAUJjhEaSwAIAQAuAAQKfzoABAcACAmgHTYjAEMCAAcACAmgHTYjAEMCABwABAlCDWQaAMEAAB0AAgmDFBRoAD0AAAAA.Dukazil:BAAALgADCgYJBgAAAA==.Dukorpse:BAAALgAECgYJBgAAAA==.Dunzer:BAACLgAFFH8YAAIQAAQJMxDfAwAYAQAQAAQJMxDfAwAYAQAuAAQKf0sAAxAACQksG8oiAHsCABAACQksG8oiAHsCAAEAAglDCSZHAEkAAAAA.Dunzerblaze:BAAALgAECgQJCQAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAABLgAECn8hAAIJAAgJJBuVHQBZAgAJAAgJJBuVHQBZAgABLgAECgkJEgATAAAAAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgAECgEJAQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8hAAILAAgJ0R/wOgCLAgALAAgJ0R/wOgCLAgAAAA==.',
Eh='Ehonda:BAAALgAECgUJBQABLgAECgkJGQAFAJQPAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAABLgAECn8ZAAIeAAkJrB8PBQC6AgAeAAkJrB8PBQC6AgAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAAALgAECgcJEgAAAA==.Emolock:BAAALgAECgUJBQAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgAECgIJAgAAAA==.',
Eo='Eon:BAAALgAECgUJDwAAAA==.',
Ep='Epiphaný:BAAALgAECgYJCwAAAA==.',
Er='Eradoria:BAABLgAECn8UAAIdAAYJQgXmRADiAAAdAAYJQgXmRADiAAAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgAECgQJBAAAAA==.',
Es='Essylt:BAAALgAECgQJCgAAAA==.Este:BAAALgADCgQJBAAAAA==.',
Ev='Evadne:BAAALgAECggJEgAAAA==.Evagrius:BAAALgAECgUJBQAAAA==.Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAABLgAECn8cAAIfAAkJ0wmKFQB0AQAfAAkJ0wmKFQB0AQAAAA==.',
Ex='Exidore:BAAALgAECgcJDAAAAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAATAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Falchionx:BAAALgAECgUJDAABLgAECgkJEgATAAAAAA==.Falfogan:BAAALgAECgEJAgAAAA==.Fangy:BAAALgAECgQJCQAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felindra:BAAALgADCgYJBgAAAA==.Felserion:BAAALgADCgEJAgABLgAFFAQJEAALAMEYAA==.Fenn:BAABLgAECn9KAAIbAAkJFh2SCgC2AgAbAAkJFh2SCgC2AgAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Firechicken:BAAALgAECgcJBwAAAA==.Fistantillus:BAAALgAECgcJCwAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flnx:BAAALgAECgEJAwABLgAECgkJEgATAAAAAA==.Flopper:BAAALgAECgYJCwAAAA==.',
Fo='Fo:BAAALgADCgEJAQAAAA==.Fonddle:BAAALgADCgUJCQAAAA==.Forthelight:BAAALgAFFAEJAQABLgAFFAUJEgALABQYAA==.Foxyboo:BAACLgAFFH8YAAICAAQJgRHnAwDuAAACAAQJgRHnAwDuAAAuAAQKf00AAwIACQmNIIIGAEgDAAIACQmNIIIGAEgDABsAAQnzBce7ACEAAAAA.',
Fr='Freak:BAABLgAECn8YAAMJAAgJHhImQwCEAQAJAAgJHhImQwCEAQAKAAYJsgk6TQD1AAAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.Frorly:BAAALgAECgEJAQAAAA==.',
Fu='Fulv:BAAALgAECgUJEAAAAA==.',
['Fâ']='Fâith:BAAALgAECgUJDgAAAA==.',
Ga='Gaezßuleaux:BAAALgAECgUJCgAAAA==.Galerodra:BAAALgADCgEJAQAAAA==.Galorani:BAAALgADCgIJAgAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAAALgAECggJEwAAAA==.',
Ge='Gertroz:BAAALgAECgUJCAABLgAFFAEJAgATAAAAAA==.',
Gi='Gimic:BAAALgAECgkJEwAAAA==.',
Gn='Gnomatic:BAAALgAECgIJCAABLgAECgkJJQAGAKUHAA==.Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn83AAIEAAkJLSVDBQA+AwAEAAkJLSVDBQA+AwAAAA==.Gope:BAABLgAECn8lAAMCAAkJRBeoIQBFAgACAAkJRBeoIQBFAgAbAAQJ3gZMdgBpAAAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Graazer:BAAALgAECgIJAgAAAA==.Green:BAABLgAECn8WAAIZAAgJSxcbCQBUAgAZAAgJSxcbCQBUAgAAAA==.Grewsome:BAAALgAECgQJBAAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn9HAAMZAAkJUSRvAQBPAwAZAAkJLSRvAQBPAwAgAAgJ3R0MEgCoAgAAAA==.Gromyr:BAAALgAECgEJAQABLgAECgkJRwAZAFEkAA==.Grr:BAABLgAECn8rAAIHAAkJZiElDADlAgAHAAkJZiElDADlAgAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gä']='Gärrus:BAAALgAECgQJBAAAAA==.',
['Gó']='Gójira:BAABLgAECn8bAAIQAAkJFgcktwAVAQAQAAkJFgcktwAVAQAAAA==.',
Ha='Hartis:BAABLgAECn8sAAQEAAkJERDKLgD2AQAEAAkJERDKLgD2AQAZAAIJqwTBVQBWAAAgAAQJ5wBdewBWAAAAAA==.Hashmal:BAAALgAECgUJBwAAAA==.Hazo:BAABLgAECn8iAAMPAAYJbgnqYACOAAAPAAUJcQrqYACOAAAhAAMJqAQbbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Hectabali:BAAALgADCgYJBQAAAA==.Heizou:BAAALgAECgYJBwABLgAFFAMJDQAGAE4QAA==.Hellkat:BAAALgAECgcJDAAAAA==.',
Hi='Higarosa:BAAALgADCgIJBAAAAA==.Highbull:BAAALgAECgUJBQAAAA==.Hild:BAAALgAECgkJAQAAAA==.',
Ho='Holiblade:BAABLgAECn85AAIQAAgJ7glSqwAmAQAQAAgJ7glSqwAmAQAAAA==.Holyfaxiss:BAEBLgAECn8sAAIiAAgJ3iM8AABdAgAiAAgJ3iM8AABdAgABLgAECggJOQANACEkAA==.Holyhannah:BAAALgAECgUJBgAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJCgAAAA==.Holywhiskers:BAAALgADCgYJBgABLgAECgkJTgAQAHkhAA==.Hooligun:BAABLgAECn8vAAIbAAkJNQ/xMAB7AQAbAAkJNQ/xMAB7AQAAAA==.Hoppered:BAAALgAECgUJBgABLgAECgkJPgAWAOAiAA==.',
Hu='Huntinpowerz:BAAALgAECgEJAQAAAA==.Huntlord:BAAALgADCgcJBwAAAA==.',
Hy='Hypérian:BAAALgAECgQJBgAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAABLgAECn8TAAIEAAkJSBt1PgC1AQAEAAkJSBt1PgC1AQAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAABLgAECn8mAAIBAAgJWBL6GABTAQABAAgJWBL6GABTAQAAAA==.',
Ih='Ihatereports:BAAALgAECgQJCAABLgAFFAMJCQAZAKsMAA==.',
Ij='Ijustshotyou:BAACLgAFFH8JAAMZAAMJqwx5IADUAAAZAAMJqwx5IADUAAAEAAIJzAfsjACGAAAuAAQKfxYABCAACAnQEc8RAD4BACAABwl3Es8RAD4BABkAAglBDrtOAHYAAAQAAgm+Dob3AGgAAAAA.',
Il='Illyría:BAAALgADCgcJBwAAAA==.Ilovetouka:BAAALgAECgMJBQAAAA==.',
Ir='Ironlotss:BAAALgADCgkJDQAAAA==.',
Iz='Izumo:BAAALgAECgYJCwAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAFFAUJCAAVAJwSAA==.Jakob:BAAALgAECgEJBAAAAA==.Jaks:BAAALgADCgEJAQAAAA==.Jardal:BAAALgADCgkJFgAAAA==.Jatswamdi:BAAALgAFFAIJAgAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAABLgAECn8iAAIEAAgJ2w8bZAB9AQAEAAgJ2w8bZAB9AQAAAA==.Jenanila:BAAALgAECgMJBAAAAA==.',
Jh='Jhenna:BAAALgAECgQJBgABLgAECgkJLwAJAB8WAA==.',
Ji='Jibbs:BAABLgAECn8lAAMGAAkJpQfGmQA2AQAGAAgJXQjGmQA2AQAFAAEJmAKbaAAZAAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwATAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJEAAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jolah:BAAALgAECgIJAgAAAA==.Jollakeratu:BAABLgAECn9OAAIjAAkJbRWjAAB+AQAjAAkJbRWjAAB+AQAAAA==.Jonnygordo:BAABLgAECn8VAAIQAAYJBg7LyAD8AAAQAAYJBg7LyAD8AAAAAA==.Jorahh:BAABLgAECn8XAAMbAAcJHRY9NQBlAQAbAAYJHRY9NQBlAQACAAcJ2QysYAAJAQAAAA==.',
Ju='Jugernawt:BAAALgAECgEJAQABLgAECgkJNgABAJkbAA==.Jugram:BAAALgAECgQJBAAAAA==.Jungolv:BAAALgADCgMJAwAAAA==.Jusmissiner:BAABLgAECn8iAAIEAAkJxx5yFgCEAgAEAAkJxx5yFgCEAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAABLgAECn8eAAIFAAkJKRtzEQD1AQAFAAkJKRtzEQD1AQAAAA==.',
['Jø']='Jønty:BAAALgADCgkJFgAAAA==.',
Ka='Kaelyra:BAAALgADCgkJFgAAAA==.Kaitenn:BAAALgAECgYJBgAAAA==.Kamehame:BAAALgAECggJEgAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECgkJRAACAFciAA==.',
Ke='Keelhorn:BAABLgAECn8lAAMCAAkJGRRUMwDlAQACAAkJGRRUMwDlAQAbAAMJgwdwewB9AAAAAA==.Kenneth:BAABLgAECn8cAAIQAAcJshJIgwBpAQAQAAcJshJIgwBpAQAAAA==.Kessarah:BAAALgAECgkJAgAAAA==.Kevin:BAAALgAECgYJDAABLgAFFAUJDwAKAIgcAA==.Keyadorath:BAAALgADCgIJAgAAAA==.',
Ki='Kibon:BAABLgAECn8ZAAMOAAYJsga6KABzAAAVAAYJ9AXzxQDDAAAOAAQJfgS6KABzAAAAAA==.Kindabored:BAAALgADCggJCAABLgAFFAQJEgAJAF4LAA==.Kinkyhawt:BAEBLgAECn8YAAMkAAYJAB8JKwCSAQAUAAUJchuiFQCUAQAkAAYJZx4JKwCSAQAAAA==.Kirio:BAAALgADCgcJCgAAAA==.Kitsunenohi:BAABLgAECn9CAAIdAAkJvgkrAQABAQAdAAkJvgkrAQABAQAAAA==.',
Ko='Kodiakk:BAABLgAECn8nAAIZAAkJNxQ8HAC7AQAZAAkJNxQ8HAC7AQAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Krattos:BAAALgAECgIJBgAAAA==.Krechon:BAAALgADCgQJBAAAAA==.Krimzin:BAAALgAECgEJAgABLgAFFAUJGgAEADAhAA==.',
Ks='Ksares:BAAALgAECgIJAgABLgAECgkJUAAEANwhAA==.',
Ku='Kuddles:BAAALgADCgEJBwAAAA==.Kumei:BAAALgAECgEJAQABLgAECgkJLAAEABEQAA==.Kural:BAAALgAECgUJBgABLgAECggJKAABAJsjAA==.',
Kw='Kwazii:BAABLgAECn8mAAQlAAgJ/BehHgDQAQAlAAgJ/BehHgDQAQADAAYJ+wUfVADCAAASAAIJJAWTbABTAAAAAA==.',
Ky='Kyantzmi:BAABLgAECn8dAAIIAAYJMA8fJwBeAQAIAAYJMA8fJwBeAQAAAA==.Kyogre:BAABLgAECn8bAAIKAAcJ9xL6MQBTAQAKAAcJ9xL6MQBTAQAAAA==.',
La='Laefnia:BAACLgAFFH8MAAQKAAMJ8xEaLwDIAAAKAAMJ8xEaLwDIAAAJAAMJgRFjBAClAAAjAAEJAwoePwAwAAAuAAQKfzQABQoACQnUGkERAFECAAoACQmYGUERAFECAAkACAnUGb0wAN8BACMABQmfGJkeAFgBABgAAQk0Bn01AC4AAAEuAAUUAwkNAAYAThAA.Lapisal:BAAALgADCgEJAQAAAA==.Laraydra:BAAALgAECgUJDAABLgAFFAEJAgATAAAAAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJGQAhAD4QAA==.Lavaburstya:BAAALgAECgcJDAAAAA==.',
Le='Leomist:BAABLgAECn8gAAMaAAkJ8A+TMQCyAQAaAAkJ8A+TMQCyAQAhAAEJKwoGBwAuAAAAAA==.Leviosä:BAABLgAECn8+AAMLAAkJOxj8MABVAgALAAkJOxj8MABVAgAMAAEJ2wblFgAiAAAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgAECgUJBQAAAA==.Lilis:BAAALgAECgMJAwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8uAAIGAAkJZCRwDAAJAwAGAAkJZCRwDAAJAwAAAA==.Liten:BAAALgADCggJFQAAAA==.Littlebev:BAABLgAECn8ZAAIOAAcJ+goCFwDrAAAOAAcJ+goCFwDrAAAAAA==.',
Lo='Lockins:BAAALgAECgYJBwAAAA==.Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJBwAAAA==.Longshankss:BAAALgAECgcJDwAAAA==.',
Ly='Lynaiya:BAAALgADCgMJAwAAAA==.',
['Lé']='Léxí:BAAALgAECgkJCQAAAA==.',
['Lí']='Lírii:BAAALgAECggJEgAAAA==.',
['Lô']='Lôôbmeup:BAAALgADCgEJAQAAAA==.',
Ma='Maachen:BAAALgAECgYJCwAAAA==.Maalik:BAABLgAECn9XAAQWAAkJ7CCiAQDeAgAWAAkJpSCiAQDeAgAOAAcJfxoiCgCkAQAVAAMJgw6X/gBqAAAAAA==.Magejackky:BAAALgAECgQJCAAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Maivorkeru:BAAALgAECgQJBgAAAA==.Malaurray:BAABLgAECn8jAAIVAAgJbQxBcgBVAQAVAAgJbQxBcgBVAQABLgABCgQJBgATAAAAAA==.Maluin:BAAALgAECgEJAgABLgAECgkJQQAcAOMaAA==.Mavanta:BAAALgAECgMJBAAAAA==.Mayonæse:BAABLgAECn8dAAIHAAUJRAxBmgDsAAAHAAUJRAxBmgDsAAAAAA==.',
Mc='Mcchong:BAAALgAECgYJEgAAAA==.Mckennah:BAABLgAECn8eAAMBAAgJbiGdBgB6AgABAAgJbiGdBgB6AgAQAAEJDgwepgEsAAAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAFFAQJDgALAPQQAA==.Mereidith:BAACLgAFFH8OAAMLAAQJ9BDdXQAkAQALAAQJ9BDdXQAkAQAmAAEJXAYZCAA1AAAuAAQKfywAAwsABwmCHPdPAOwBAAsABwmCHPdPAOwBACYAAQlyGhMZAE8AAAAA.Meshulk:BAAALgAECgEJAQAAAA==.Mesohungry:BAABLgAECn8uAAMiAAkJiQkjOwBcAQAiAAkJiQkjOwBcAQAQAAIJzAGMtwEnAAAAAA==.Metasploit:BAAALgAECgkJAQAAAA==.',
Mi='Mikehunte:BAAALgAECgYJBgABLgAECgkJIQALANEfAA==.Miriya:BAABLgAECn8jAAIPAAkJyCR/AgA1AwAPAAkJyCR/AgA1AwAAAA==.Missnoms:BAAALgAECgEJAQAAAA==.',
Mo='Monkeycheese:BAABLgAECn8ZAAIhAAcJPhAKPAARAQAhAAcJPhAKPAARAQAAAA==.Moobáca:BAAALgAECgUJBwAAAA==.Moostradamas:BAABLgAECn8nAAMXAAkJBQfqFgAgAQAXAAkJBQfqFgAgAQAGAAIJsgAQogEeAAAAAA==.Morcilla:BAABLgAECn8UAAMFAAkJngv2IwAzAQAFAAkJngv2IwAzAQAXAAMJ/gTLLgBlAAAAAA==.Morticyde:BAAALgAECgMJBAAAAA==.',
Ms='Msg:BAABLgAECn8lAAIJAAkJrBveFACjAgAJAAkJrBveFACjAgAAAA==.',
Mu='Munassa:BAAALgADCgcJBwAAAA==.Muppets:BAAALgAECgUJCQAAAA==.',
My='Myssidia:BAAALgADCgkJFQAAAA==.',
['Mí']='Mínervä:BAAALgAECgkJEAAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgIJAwAAAA==.Nasdaralth:BAAALgAECgMJAwABLgAFFAEJAgATAAAAAA==.Nastrodamus:BAAALgAECgIJAgAAAA==.Naturegoob:BAABLgAECn8bAAMJAAgJphogNADYAQAJAAgJphogNADYAQAKAAMJ4RGeXQCgAAAAAA==.Naughtynurse:BAABLgAECn9HAAIJAAkJixLWKwD7AQAJAAkJixLWKwD7AQAAAA==.Nayee:BAAALgADCgUJBQAAAA==.',
Ne='Nemrak:BAAALgAFFAIJAgAAAA==.Neuma:BAABLgAECn8UAAIQAAQJBAvbBQGxAAAQAAQJBAvbBQGxAAAAAA==.',
Ni='Nicfurry:BAAALgADCgMJAwAAAA==.Nightflower:BAABLgAECn8kAAMmAAkJUwUhDwDRAAALAAcJGQU8yQD8AAAmAAYJAwQhDwDRAAAAAA==.',
No='Noided:BAAALgAECgYJCgAAAA==.Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgYJDwABLgAECgYJEAATAAAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
Ob='Obiejuan:BAACLgAFFH8GAAIQAAMJBw23dgDHAAAQAAMJBw23dgDHAAAuAAQKf1EAAxAACQngIq0NAPgCABAACQngIq0NAPgCAAEABAmgHuIhAAUBAAAA.Obietide:BAAALgAECgkJEQABLgAFFAMJBgAQAAcNAA==.',
Od='Oddball:BAABLgAECn8eAAIbAAkJBhxNGQAYAgAbAAkJBhxNGQAYAgAAAA==.',
Of='Ofthecircle:BAAALgAECggJEwAAAA==.',
Ok='Okamiblooded:BAAALgAECggJEQAAAA==.',
Ol='Olly:BAAALgAECgYJDQAAAA==.',
On='Ontala:BAAALgADCgYJBgAAAA==.',
Oo='Oodles:BAAALgAECgcJEgAAAA==.',
Op='Ophiron:BAAALgAECgUJBwAAAA==.',
Or='Orangecrush:BAAALgAECgYJEQAAAA==.Orangekeg:BAAALgAECgUJEQABLgAECgkJIQAbANgfAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAAALgAECgcJEwAAAA==.',
Pa='Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn88AAIFAAkJ2R1hCgBsAgAFAAkJ2R1hCgBsAgABLgAECggJKAABAJsjAA==.Peso:BAAALgAECgQJBwAAAA==.Pez:BAAALgAECgYJEQABLgAECgkJLwAJAB8WAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAABLgAFFH8YAAIaAAcJrROvEgD0AQAaAAcJrROvEgD0AQABLgAFFAQJCAAiAGESAA==.Pomater:BAAALgAECgYJDgABLgAFFAEJAgATAAAAAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAABLgAECn8YAAILAAgJOQkKngA+AQALAAgJOQkKngA+AQAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECgkJLAACALQgAA==.',
Pr='Primafox:BAAALgAECgYJDAAAAA==.Prkchopxpres:BAAALgAECgYJDwAAAA==.Protoheal:BAAALgAECgEJAgAAAA==.',
Pu='Punchandkick:BAAALgAECgMJBgAAAA==.Punkweight:BAAALgAECgEJAQAAAA==.Purpleeater:BAAALgAECgIJBQAAAA==.',
Py='Pyrabanks:BAABLgAFFH8IAAIkAAQJFwovOgDdAAAkAAQJFwovOgDdAAAAAA==.',
['Pä']='Päw:BAACLgAFFH8NAAMGAAMJThA5qgDKAAAGAAMJThA5qgDKAAAXAAIJMAWiIgB1AAAuAAQKfy4ABAYACQniHV1TAMoBAAYACAmhF11TAMoBAAUABQnEHNwgAEsBABcAAwnjHz8aAP8AAAAA.',
Qu='Quetzalcóatl:BAAALgAECgQJBAAAAA==.Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJAgAAAA==.',
Qx='Qx:BAAALgAECgYJBgAAAA==.',
Ra='Raakoth:BAAALgAECgUJDQABLgAECgkJVwAWAOwgAA==.Radge:BAABLgAECn83AAMnAAkJoiUVAQBlAwAnAAkJoiUVAQBlAwANAAMJKR0rdgDiAAAAAA==.Rainjar:BAACLgAFFH8XAAMZAAQJiiFQAgC6AAAZAAMJnyFQAgC6AAAEAAIJkBsAeQCmAAAuAAQKfzwAAxkACQkAIl4CAB8DABkACQlcH14CAB8DAAQACAk3JCYTALkCAAAA.Rainne:BAAALgADCgcJCAAAAA==.Raistyn:BAABLgAECn8pAAMBAAkJwRzUCwAIAgABAAkJwRzUCwAIAgAQAAEJigwLqAErAAAAAA==.Ralanar:BAAALgAECgcJDgABLgAFFAEJAgATAAAAAA==.Raljah:BAABLgAECn8+AAQWAAkJ4CINAQAFAwAWAAkJ1CINAQAFAwAVAAcJBB8zKgAyAgAOAAUJXh19FACnAQAAAA==.Ramasus:BAAALgAECgUJBQAAAA==.Rampart:BAABLgAECn82AAMBAAkJmRtyBwBnAgABAAkJmRtyBwBnAgAQAAEJ5w4BnAEvAAAAAA==.Rasaltghul:BAAALgAECgEJAQABLgAECgMJBgATAAAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.Raxxer:BAAALgAECgEJBAAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAABLgAECn8UAAMBAAcJtw3ZJwDYAAAQAAcJ9gei0ADyAAABAAYJbg7ZJwDYAAAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Renm:BAAALgAECgYJEgAAAA==.Renpriest:BAACLgAFFH8UAAISAAMJfx4YKgD+AAASAAMJfx4YKgD+AAAuAAQKfxUAAxIACAmMGVIRAC4CABIACAmMGVIRAC4CAAMAAQk4FUCBADoAAAAA.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgkJEQAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.Royaldüh:BAACLgAFFH8GAAIHAAIJ7wXZjABpAAAHAAIJ7wXZjABpAAAuAAQKfxcAAgcABwlCFZtfAGoBAAcABwlCFZtfAGoBAAAA.Royalüwü:BAAALgAECgUJCQAAAA==.',
Ry='Ryobi:BAABLgAECn8/AAMgAAkJuhigCADyAQAEAAkJ9BQCMwAQAgAgAAgJDRigCADyAQAAAA==.Ryptyde:BAABLgAECn8WAAICAAkJ7h7aBwAyAwACAAkJ7h7aBwAyAwAAAA==.',
['Ræ']='Rævena:BAABLgAECn8VAAIGAAYJOgohygDwAAAGAAYJOgohygDwAAAAAA==.',
Sa='Sachaann:BAAALgAECgIJAwAAAA==.Salinan:BAACLgAFFH8GAAMWAAMJDRI5DgCiAAAVAAMJewsjfgDIAAAWAAIJ1BU5DgCiAAAuAAQKf1EAAxYACQncJL8AACIDABYACQm3JL8AACIDABUABgntGshVAJsBAAAA.Saltymon:BAAALgADCgYJBgABLgAECgIJAwATAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgkJNgAIAJocAA==.Saradia:BAAALgADCgIJAgAAAA==.Saric:BAAALgAECgMJBwAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Scanor:BAAALgAECgYJDAABLgAFFAMJDgAkAM4CAA==.Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.',
Se='Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAABLgAECn8kAAIQAAkJ9hsDIACIAgAQAAkJ9hsDIACIAgAAAA==.Selky:BAAALgADCgcJCgAAAA==.',
Sf='Sfodin:BAABLgAECn8eAAINAAgJKQk7QQBAAQANAAgJKQk7QQBAAQAAAA==.',
Sh='Shadowkings:BAAALgAFFAEJAwAAAA==.Shak:BAABLgAECn8gAAIbAAYJ0A4+TQAAAQAbAAYJ0A4+TQAAAQAAAA==.Shalai:BAAALgADCgMJAwAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shastix:BAAALgAECgYJEgABLgAECgkJVwAWAOwgAA==.Shellingtun:BAAALgAECgYJCwAAAA==.Shiggylloway:BAAALgAECgEJAQAAAA==.Shyandrial:BAAALgAECgQJBQAAAA==.Shyness:BAAALgAECgQJBAAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAABLgAECn8rAAMDAAgJ1gvlMwBJAQADAAgJ1gvlMwBJAQAlAAQJtgiYVACKAAAAAA==.',
Sk='Skilltotem:BAAALgAECgkJEAAAAA==.Skk:BAAALgADCggJCQAAAA==.Sksteve:BAAALgAECgUJDwAAAA==.Skullyy:BAAALgAECgYJDgABLgAECgYJEAATAAAAAA==.Skychades:BAABLgAECn8YAAIEAAkJAhgqQwDZAQAEAAkJAhgqQwDZAQAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAABLgAECn8cAAIKAAcJohDyOAAvAQAKAAcJohDyOAAvAQABLgAECggJCwATAAAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECggJCwAAAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgAECgcJDwAAAA==.Soulsrequiem:BAABLgAECn8tAAIoAAgJ+AEAAQBjAAAoAAgJ+AEAAQBjAAAAAA==.',
Sp='Spicyblaster:BAABLgAFFH8SAAILAAUJFBj7TABFAQALAAUJFBj7TABFAQAAAA==.Spookydeath:BAACLgAFFH8aAAILAAUJ8hCOXwAiAQALAAUJ8hCOXwAiAQAuAAQKfy4AAgsACQmrEn1JAP8BAAsACQmrEn1JAP8BAAAA.',
Sr='Srsnacksalot:BAABLgAECn8qAAIQAAgJ9hj3SgDlAQAQAAgJ9hj3SgDlAQAAAA==.',
St='Stileto:BAAALgAECgcJEAAAAA==.Stonedhuntar:BAAALgAECgcJBwAAAA==.Stoneydracco:BAABLgAECn8gAAILAAcJUBPwgAB1AQALAAcJUBPwgAB1AQAAAA==.Stoneydragon:BAAALgADCgYJBgAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECggJEgAAAA==.',
Su='Sukiliana:BAAALgAECgQJBQAAAA==.Sumtinwng:BAABLgAECn84AAIQAAkJDxKmRwDvAQAQAAkJDxKmRwDvAQAAAA==.Supervicious:BAABLgAECn8ZAAIRAAkJuxUgFACuAQARAAkJuxUgFACuAQAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgkJFgAAAA==.Sylenne:BAABLgAECn8vAAIJAAkJHxaPHwBKAgAJAAkJHxaPHwBKAgAAAA==.Sylur:BAAALgAECgkJEgAAAA==.Syrayvianda:BAAALgADCgYJBgAAAA==.',
['Sÿ']='Sÿlvanah:BAAALgAECgQJBAAAAA==.',
Ta='Taemea:BAAALgAECggJEgAAAA==.Tahran:BAAALgAFFAIJAgABLgAFFAYJIAASALkVAA==.Tahren:BAACLgAFFH8gAAQSAAYJuRVpFwC2AQASAAYJAxFpFwC2AQAlAAQJBRU4EwAvAQADAAIJZgu9MQB/AAAuAAQKfyoABCUACQmIIHMQAGECACUABwn0IHMQAGECABIACQlvExMzAEwBAAMABwllEJJKAOUAAAAA.Talanima:BAAALgADCgcJBwAAAA==.Taler:BAAALgAFFAEJAQAAAA==.Talerion:BAAALgAECgcJEgAAAA==.Talyaine:BAAALgAECgUJBQABLgAFFAMJDQAGAE4QAA==.Tanzanitia:BAAALgAECgYJBgAAAA==.',
Tc='Tcdots:BAAALgAECgEJAgAAAA==.',
Te='Telline:BAAALgADCgYJBwAAAA==.Tens:BAABLgAECn8bAAINAAgJJiNXDAD1AgANAAgJJiNXDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECggJEgAAAA==.Theafflictor:BAAALgAECgYJCQAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECggJEgATAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thistelbear:BAABLgAECn9LAAIhAAkJ/g6qAABlAQAhAAkJ/g6qAABlAQAAAA==.Thrallsux:BAAALgAECgEJAgAAAA==.Thraun:BAAALgAECgYJEgAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn80AAMQAAkJsBKiagCpAQAQAAkJsBKiagCpAQABAAcJaAspJgDkAAAAAA==.',
Ti='Titszilla:BAAALgAECgcJAwAAAA==.',
To='Toki:BAABLgAECn8bAAMaAAYJxxuPLgDCAQAaAAYJxxuPLgDCAQAhAAQJqg+ZTQDbAAAAAA==.Tokidormi:BAABLgAECn8nAAMfAAgJaSAlAAAvAgAfAAgJaSAlAAAvAgAUAAQJrBDKEQDuAAAAAA==.Toralus:BAAALgADCgYJCQAAAA==.Totumm:BAAALgADCgcJCAAAAA==.',
Tr='Tralku:BAAALgAECgcJDAAAAA==.Tremmørs:BAABLgAECn8aAAIbAAcJUQywUQDxAAAbAAcJUQywUQDxAAAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAABLgAECn8UAAIQAAkJghZWYACwAQAQAAkJghZWYACwAQAAAA==.',
Tu='Turnip:BAAALgAECgEJAQAAAA==.',
Tw='Tweak:BAAALgAECgIJAgAAAA==.Tweis:BAAALgADCgYJEQAAAA==.',
Ty='Tyllinor:BAAALgADCgUJBQAAAA==.',
Um='Umbrarogue:BAABLgAECn8eAAMIAAkJOBxsEQAdAgAIAAkJ0RpsEQAdAgAoAAEJPh2sIQBVAAAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEwAAAA==.',
Va='Vaara:BAAALgAECgMJBAAAAA==.Valaa:BAAALgAECggJCQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAABLgAECn8WAAIQAAkJyA4CcgCYAQAQAAkJyA4CcgCYAQAAAA==.Veliya:BAAALgAECgYJEwABLgAECgkJLwAJAB8WAA==.Vellestrix:BAAALgAECgQJBAAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Veriity:BAAALgAECgUJBgAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Vicotr:BAAALgAFFAEJAQAAAA==.Viddysouls:BAABLgAECn8hAAIeAAgJtRKfEQCaAQAeAAgJtRKfEQCaAQAAAA==.Vienaa:BAAALgAECgEJAQAAAA==.Viscerai:BAABLgAECn84AAIlAAkJiSVJAQCyAwAlAAkJiSVJAQCyAwAAAA==.Vite:BAAALgAECgYJDwAAAA==.Vitta:BAAALgAECgMJAwAAAA==.',
Vo='Vonmiller:BAACLgAFFH8FAAIWAAIJLhXPEACLAAAWAAIJLhXPEACLAAAuAAQKfxsAAxYACAn9FkAGAPkBABYACAn9FkAGAPkBABUAAgkSDPf7AGIAAAAA.Vozluz:BAAALgAECgEJAQABLgAECgkJVwAWAOwgAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECggJCwATAAAAAA==.',
['Væ']='Væda:BAAALgAECgMJAwAAAA==.',
Wa='Warfaxis:BAEBLgAECn85AAINAAgJISRpBwDoAgANAAgJISRpBwDoAgAAAA==.',
We='Weird:BAAALgAECgIJAgABLgAECgkJGAAJAB4SAA==.Wereßearßirb:BAAALgADCgUJBQAAAA==.',
Wi='Winnower:BAAALgADCgYJBgAAAA==.Wiseoldgoob:BAABLgAECn8bAAQSAAkJmxljCwC4AgASAAkJmxljCwC4AgAlAAEJkw4ZbwAyAAADAAEJ6wVaZgAsAAAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAFFAIJBAAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAFFAMJAwAAAA==.',
Ze='Zenclaw:BAABLgAECn9BAAIaAAkJzhCILQDIAQAaAAkJzhCILQDIAQAAAA==.Zencore:BAABLgAECn8VAAILAAgJeA97iABmAQALAAgJeA97iABmAQAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECggJFQALAHgPAA==.Zenlock:BAAALgADCgIJAgABLgAECggJFQALAHgPAA==.',
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
