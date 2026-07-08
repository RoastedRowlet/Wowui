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

local lookup = {'Paladin-Protection','Shaman-Restoration','Priest-Shadow','Shaman-Elemental','Hunter-BeastMastery','DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Devourer','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Mage-Frost','Mage-Fire','Warrior-Fury','Warlock-Destruction','Monk-Brewmaster','Paladin-Retribution','Warrior-Protection','Priest-Discipline','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','Priest-Holy','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Paladin-Holy','Unknown-Unknown','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Enhancement','Evoker-Preservation','Hunter-Marksmanship','Monk-Windwalker','Druid-Guardian','Evoker-Augmentation','Mage-Arcane','Warrior-Arms','Rogue-Assassination',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-07-05',data={Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Adhenar:BAAALgAECgMJAwAAAA==.Adow:BAAALgAECggJCQAAAA==.Adynne:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.',
Ae='Aered:BAAALgAECggJDwAAAA==.Aerev:BAAALgAECgEJBgAAAA==.Aerylith:BAAALgAECgYJCgAAAA==.',
Af='Aften:BAAALgAECgYJCAAAAA==.',
Ah='Ahira:BAABLgAECn9BAAICAAkJ5iJaBwA6AwACAAkJ5iJaBwA6AwAAAA==.',
Ai='Ailov:BAAALgADCgMJAwAAAA==.Ains:BAAALgAECgEJAQAAAA==.',
Ak='Akuria:BAABLgAECn9QAAIDAAkJ5yHoAACJAgADAAkJ5yHoAACJAgAAAA==.',
Al='Alacía:BAABLgAFFH8FAAMCAAMJrBHvMQBWAAACAAIJiQnvMQBWAAAEAAEJ4wGqLQAsAAAAAA==.Alahna:BAABLgAECn8oAAIFAAkJHQyEEAD9AAAFAAkJHQyEEAD9AAAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAACLgAFFH8UAAIGAAQJwwN3EACaAAAGAAQJwwN3EACaAAAuAAQKf0UAAwYACQkZDmgcAHcBAAYACQkZDmgcAHcBAAcABglGA2dQAVEAAAAA.Annicution:BAABLgAECn8VAAMGAAYJUB9HGgCMAQAGAAYJUB9HGgCMAQAHAAUJUgtmFgCoAAAAAA==.Antamoon:BAABLgAECn8YAAIIAAkJyg6VTQCdAQAIAAkJyg6VTQCdAQAAAA==.',
Ao='Aox:BAABLgAECn82AAIJAAkJmhxdCgB+AgAJAAkJmhxdCgB+AgAAAA==.',
Aq='Aquarian:BAAALgAECgYJDAAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgkJEgAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgAECgMJAwAAAA==.Asseroth:BAAALgAECgEJAQAAAA==.',
At='Atriux:BAAALgAECgkJCAAAAA==.',
Au='Aureline:BAABLgAECn80AAMKAAkJXRMhNQDGAQAKAAkJXRMhNQDGAQALAAQJpAUnZgCFAAAAAA==.Aurna:BAACLgAFFH8FAAIMAAMJpAnCLgDHAAAMAAMJpAnCLgDHAAAuAAQKfxsAAgwACQlTFpQHAIEBAAwACQlTFpQHAIEBAAAA.',
Av='Avianddrela:BAAALgADCgIJAgAAAA==.',
Az='Azuresky:BAAALgAECgUJCAAAAA==.',
Ba='Babegnome:BAAALgAECgEJAgAAAA==.Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgcJEQAAAA==.',
Be='Beanfliker:BAAALgADCgIJAgAAAA==.Bearlysimple:BAAALgAECgYJCwAAAA==.Beartank:BAAALgADCgYJBgAAAA==.Beastiam:BAAALgAECgEJAwAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgADCgUJCAAAAA==.Belserion:BAACLgAFFH8QAAIMAAQJwRjWGABnAQAMAAQJwRjWGABnAQAuAAQKf2AAAwwACQnoJT8EAGYDAAwACQnoJT8EAGYDAA0AAQndIeUQAFQAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECgkJIQAMANEfAA==.Bernir:BAAALgAECgIJAgAAAA==.Berol:BAABLgAECn8YAAIOAAgJTBtcGgAbAgAOAAgJTBtcGgAbAgAAAA==.Beroldin:BAAALgAECgQJAwABLgAECggJGAAOAEwbAA==.Bevar:BAAALgAECgYJDQABLgAECgcJGwAPAAULAA==.Bevell:BAAALgAECgQJCQABLgAECgcJGwAPAAULAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAIQAAYJoB7QJQDVAQAQAAYJoB7QJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAABLgAECn8aAAIGAAkJjh+hBgC1AgAGAAkJjh+hBgC1AgAAAA==.Biggieshan:BAAALgAECggJDQAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAwAAAA==.Blair:BAAALgAECgEJBAAAAA==.Blindmafaka:BAAALgAECgYJEAAAAA==.Blkrend:BAACLgAFFH8HAAIGAAMJ3CDRGQAYAQAGAAMJ3CDRGQAYAQAuAAQKf00AAgYACQkrJkABAFIDAAYACQkrJkABAFIDAAAA.Bloodhound:BAAALgAECgYJBgAAAA==.Bluntz:BAAALgAECgEJAQAAAA==.Blurtaxes:BAAALgAECgcJAgABLgAFFAIJBQAHAJ4VAA==.',
Bo='Bonko:BAAALgAECgMJAwAAAA==.',
Br='Bradycam:BAABLgAECn9LAAIRAAkJkiKgCQAbAwARAAkJkiKgCQAbAwAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brewmaster:BAAALgAECgcJCAAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruceelee:BAAALgADCgMJAwAAAA==.Bruddah:BAAALgAFFAIJAwABLgAFFAMJDAASAPMKAA==.Brycefotm:BAAALgAECgcJCwABLgAFFAQJFQACAA0gAA==.',
Bu='Bubblebutt:BAAALgAECgUJBQAAAA==.Bulloo:BAAALgAECgIJBQAAAA==.Busterblader:BAAALgAECgYJEAAAAA==.',
['Bó']='Bóbafett:BAAALgADCgEJAQAAAA==.',
Ca='Cadovenia:BAAALgAECgEJBAAAAA==.Camillerose:BAAALgAECgQJBAAAAA==.Cantpalyhard:BAAALgAECgYJCgABLgAFFAQJGAACAIERAA==.Carebeär:BAABLgAECn8gAAIKAAcJ6hcYNgDPAQAKAAcJ6hcYNgDPAQAAAA==.Carpediems:BAAALgADCgIJAQAAAA==.Casella:BAABLgAECn8/AAIQAAkJkSC5BgDOAgAQAAkJkSC5BgDOAgAAAA==.',
Ce='Celissara:BAABLgAECn8YAAITAAYJVBZ/MgBQAQATAAYJVBZ/MgBQAQABLgAFFAMJBQAMAKQJAA==.',
Ch='Chamoo:BAAALgADCgIJBAAAAA==.Chimken:BAAALgADCgMJAwAAAA==.Chocospells:BAAALgAECgIJAwAAAA==.Chogori:BAAALgAECgUJDQAAAA==.Chôsenône:BAAALgAECgUJBgAAAA==.',
Ci='Cierdwyn:BAABLgAECn8aAAILAAcJ/QN/CwCBAAALAAcJ/QN/CwCBAAAAAA==.Cinnaßon:BAAALgAECgQJBAAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAABLgAECn83AAIRAAkJwSBNDQD6AgARAAkJwSBNDQD6AgAAAA==.Clouzot:BAAALgADCgkJEQAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAABLgAECn9TAAIUAAkJyg65AAB6AQAUAAkJyg65AAB6AQAAAA==.',
Cp='Cptbarnacles:BAABLgAECn8lAAQVAAcJhBKiIQC1AAAWAAQJGhHxqQDuAAAVAAQJshCiIQC1AAAPAAMJzwwjKgBsAAABLgAECggJJgAXAPwXAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBwAIACEdAA==.Crunchylock:BAAALgAECggJDAAAAA==.Crèmeßrûlée:BAAALgAECgUJCQAAAA==.',
Cu='Cunumi:BAAALgAECgQJBAAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Dainichi:BAAALgAECgEJAgAAAA==.Dakyne:BAAALgAECgEJAQAAAA==.Damachi:BAABLgAECn81AAMYAAkJ1xhWBgBDAgAYAAkJgRhWBgBDAgAHAAgJ5xBtegBuAQAAAA==.Danskan:BAABLgAECn8aAAIZAAYJFBt3FgBjAQAZAAYJFBt3FgBjAQAAAA==.Darkvale:BAAALgAFFAEJAwAAAA==.Darkñess:BAAALgAECggJDQAAAA==.Darmorae:BAABLgAECn8jAAIaAAkJsRV4FQD3AQAaAAkJsRV4FQD3AQAAAA==.Dashii:BAAALgAECgQJCAABLgAECggJJgAXAPwXAA==.Datewoo:BAABLgAECn8nAAIRAAgJ6BKUZQCkAQARAAgJ6BKUZQCkAQAAAA==.Datsuo:BAAALgAECgIJBAABLgAECgkJWAAVAOwgAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deathfaxiss:BAEALgAECggJDgABLgAECgkJNgAbAAgkAA==.Deathris:BAAALgAECggJCgAAAA==.Deef:BAAALgAECgYJDgAAAA==.Demilia:BAAALgAECgQJBAAAAA==.Demontotem:BAAALgAECgkJEAAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desadeness:BAAALgADCgUJCgABLgADCgkJNQAcAAAAAA==.Desertpunk:BAAALgAECgEJAQAAAA==.Destrolock:BAAALgAECgYJCwABLgAFFAMJCwARAIIaAA==.Dez:BAAALgAECgYJBwABLgAECgkJJQAHAKUHAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECgkJEwAAAA==.',
Do='Donkaßutts:BAAALgAECgQJDgAAAA==.Dooda:BAAALgAECgcJDQAAAA==.Doodooboi:BAAALgAECgQJBQAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECgkJEQAAAA==.Dooretos:BAAALgADCgEJAQAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracbow:BAACLgAFFH8GAAIFAAMJkAoSJQDXAAAFAAMJkAoSJQDXAAAuAAQKfxcAAgUACAkUE69MALwBAAUACAkUE69MALwBAAEuAAUUBAkMAAcAmgcA.Dracdemonica:BAAALgAECgIJAgABLgAFFAQJDAAHAJoHAA==.Dracfu:BAABLgAECn8XAAIdAAgJpge5XgD8AAAdAAgJpge5XgD8AAABLgAFFAQJDAAHAJoHAA==.Drackpally:BAAALgAECgcJBQAAAA==.Dracserion:BAAALgAFFAEJAgABLgAFFAQJEAAMAMEYAA==.Dracsham:BAAALgADCgEJAQABLgAFFAQJDAAHAJoHAA==.Dracsknight:BAACLgAFFH8MAAIHAAQJmge4PgCxAAAHAAQJmge4PgCxAAAuAAQKfyIAAgcACQmAEilCAPwBAAcACQmAEilCAPwBAAAA.Dracslana:BAAALgAECgYJEQABLgAFFAQJDAAHAJoHAA==.Draffel:BAABLgAECn8hAAMCAAkJuxt4EwCwAgACAAkJuxt4EwCwAgAEAAEJxQElxQAVAAAAAA==.Dramamine:BAAALgAECgQJBAAAAA==.Drathi:BAABLgAECn8jAAMHAAgJCxrCNgAkAgAHAAcJCxrCNgAkAgAGAAgJMBB7IwA3AQAAAA==.Drestla:BAAALgAECgcJCwAAAA==.Drothikus:BAAALgAECgMJAwAAAA==.Drowgon:BAABLgAECn8YAAMOAAgJEhc4MwB+AQAOAAcJORg4MwB+AQASAAcJ8g0qLADYAAAAAA==.Drtot:BAAALgAECgEJAwAAAA==.Druidfaxxis:BAEALgAECggJDwABLgAECgkJNgAbAAgkAA==.Druwgon:BAAALgAECgIJAgAAAA==.Drác:BAAALgAECgIJBAABLgAFFAQJDAAHAJoHAA==.',
Du='Duartor:BAAALgAECgIJAgAAAA==.Dukalune:BAAALgAECgUJCQAAAA==.Dukaos:BAACLgAFFH8VAAIIAAUJjhEISwAJAQAIAAUJjhEISwAJAQAuAAQKfzoABAgACAmgHTQjAEMCAAgACAmgHTQjAEMCAB4ABAlCDWQaAMEAAB8AAgmDFBVoAD0AAAAA.Dukazil:BAAALgADCgYJBgAAAA==.Dukorpse:BAAALgAECgYJBgAAAA==.Dunzer:BAACLgAFFH8YAAIRAAQJMxA/GAD9AAARAAQJMxA/GAD9AAAuAAQKf0sAAxEACQksG8oiAHsCABEACQksG8oiAHsCAAEAAglDCSdHAEkAAAAA.Dunzerblaze:BAAALgAECgQJCQAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAABLgAECn8hAAIKAAgJJBuTHQBZAgAKAAgJJBuTHQBZAgABLgAECgkJGQAHAH0ZAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgAECgEJAQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8hAAIMAAgJ0R/wOgCLAgAMAAgJ0R/wOgCLAgAAAA==.',
Eh='Ehonda:BAAALgAECgUJBQABLgAECgkJGQAGAJQPAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAABLgAECn8ZAAIgAAkJrB8PBQC6AgAgAAkJrB8PBQC6AgAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAABLgAECn8dAAITAAcJqRMwAwCgAQATAAcJqRMwAwCgAQAAAA==.Emolock:BAAALgAECgUJBQAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgAECgIJAgAAAA==.',
Eo='Eon:BAAALgAECgUJDwAAAA==.',
Ep='Epiphaný:BAAALgAECgYJCwABLgAECggJJgAXAPwXAA==.',
Er='Eradoria:BAABLgAECn8VAAIfAAcJUQbmRADiAAAfAAcJUQbmRADiAAAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgAECgQJBAAAAA==.',
Es='Essylt:BAAALgAECgQJCgAAAA==.Este:BAAALgADCgQJBAAAAA==.',
Ev='Evadne:BAAALgAECggJEwAAAA==.Evagrius:BAAALgAECgUJBQAAAA==.Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAABLgAECn8cAAIhAAkJ0wmKFQB0AQAhAAkJ0wmKFQB0AQAAAA==.',
Ex='Exidore:BAAALgAECgcJDAAAAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAAcAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Falchionx:BAAALgAECgUJDAABLgAECgkJGQAHAH0ZAA==.Falfogan:BAAALgAECgEJAgAAAA==.Fangy:BAAALgAECgQJCQAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felindra:BAAALgADCgYJBgAAAA==.Felserion:BAAALgAECgEJAQABLgAFFAQJEAAMAMEYAA==.Fenn:BAABLgAECn9KAAIEAAkJFh2SCgC2AgAEAAkJFh2SCgC2AgAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Firechicken:BAAALgAECgcJBwAAAA==.Fistantillus:BAAALgAECgcJCwAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flnx:BAAALgAECgEJAwABLgAECgkJGQAHAH0ZAA==.Flopper:BAAALgAECgYJCwAAAA==.',
Fo='Fo:BAAALgADCgEJAQAAAA==.Fonddle:BAAALgADCgUJCQAAAA==.Forthelight:BAAALgAFFAEJAQAAAA==.Foxyboo:BAACLgAFFH8YAAICAAQJgRFWFwDOAAACAAQJgRFWFwDOAAAuAAQKf00AAwIACQmNIIEGAEgDAAIACQmNIIEGAEgDAAQAAQnzBcu7ACEAAAAA.',
Fr='Freak:BAABLgAECn8YAAMKAAgJHhIiQwCEAQAKAAgJHhIiQwCEAQALAAYJsgk6TQD1AAAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.Frorly:BAAALgAECgEJAQAAAA==.',
Fu='Fulv:BAAALgAECgUJEAAAAA==.',
['Fâ']='Fâith:BAAALgAECgUJDgAAAA==.',
Ga='Gaezßuleaux:BAAALgAECgUJCgAAAA==.Galerodra:BAAALgADCgEJAQAAAA==.Galorani:BAAALgADCgIJAgAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAABLgAECn8VAAIIAAgJXhT7YABnAQAIAAgJXhT7YABnAQAAAA==.',
Ge='Gertroz:BAAALgAECgUJCAABLgAFFAMJBQAMAKQJAA==.',
Gi='Gimic:BAAALgAECgkJEwAAAA==.',
Gn='Gnomatic:BAAALgAECgIJCwABLgAECgkJJQAHAKUHAA==.Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn87AAIFAAkJLSVBBQA+AwAFAAkJLSVBBQA+AwAAAA==.Gope:BAABLgAECn8lAAMCAAkJRBepIQBFAgACAAkJRBepIQBFAgAEAAQJ3gZMdgBpAAAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Graazer:BAAALgAECgIJAgAAAA==.Green:BAABLgAECn8WAAIaAAgJSxcbCQBUAgAaAAgJSxcbCQBUAgAAAA==.Grewsome:BAAALgAECgQJBAAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn9HAAMaAAkJUSRvAQBPAwAaAAkJLSRvAQBPAwAiAAgJ3R0MEgCoAgAAAA==.Gromyr:BAAALgAECgEJAQABLgAECgkJRwAaAFEkAA==.Grr:BAABLgAECn8rAAIIAAkJZiEjDADlAgAIAAkJZiEjDADlAgAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gä']='Gärrus:BAAALgAECgQJBAAAAA==.',
['Gó']='Gójira:BAABLgAECn8bAAIRAAkJFgcmtwAVAQARAAkJFgcmtwAVAQAAAA==.',
Ha='Hafgan:BAEALgAECgYJDgABLgAECgkJNgAbAAgkAA==.Hartis:BAABLgAECn8sAAQFAAkJERDKLgD2AQAFAAkJERDKLgD2AQAaAAIJqwTDVQBWAAAiAAQJ5wBdewBWAAAAAA==.Hashmal:BAAALgAECgUJCAAAAA==.Hazo:BAABLgAECn8iAAMQAAYJbgnpYACOAAAQAAUJcQrpYACOAAAjAAMJqAQbbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Hectabali:BAAALgADCgYJBQAAAA==.Heizou:BAAALgAECgYJBwABLgAFFAQJEQALAEwXAA==.Hellkat:BAAALgAECgcJDAAAAA==.',
Hi='Higarosa:BAAALgAECgEJAQAAAA==.Highbull:BAAALgAECgUJBQABLgAECggJJgAXAPwXAA==.Hild:BAAALgAECgkJAQAAAA==.',
Ho='Hogfather:BAAALgAECgUJBQAAAA==.Holiblade:BAABLgAECn85AAIRAAgJ7glRqwAmAQARAAgJ7glRqwAmAQAAAA==.Holyfaxiss:BAEBLgAECn82AAIbAAkJCCQ9AABNAwAbAAkJCCQ9AABNAwAAAA==.Holyhannah:BAAALgAECgUJBgAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJCgAAAA==.Holywhiskers:BAAALgAECgcJDwABLgAECgkJUgARAHkhAA==.Hooligun:BAABLgAECn8vAAIEAAkJNQ/yMAB7AQAEAAkJNQ/yMAB7AQAAAA==.Hoppered:BAAALgAECgUJBgABLgAECgkJPwAVAOAiAA==.Howlapeno:BAAALgAECgEJAQAAAA==.',
Hu='Huntinpowerz:BAAALgAECgEJAQAAAA==.Huntlord:BAAALgADCgcJBwAAAA==.',
Hy='Hypérian:BAAALgAECgQJBgAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAABLgAECn8TAAIFAAkJSBt1PgC1AQAFAAkJSBt1PgC1AQAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAABLgAECn8qAAIBAAkJihVBAgBpAQABAAkJihVBAgBpAQAAAA==.',
Ih='Ihatereports:BAAALgAECgQJCAABLgAFFAMJCQAaAKsMAA==.',
Ij='Ijustshotyou:BAACLgAFFH8JAAMaAAMJqwx6IADUAAAaAAMJqwx6IADUAAAFAAIJzAfrjACGAAAuAAQKfxYABCIACAnQEc8RAD4BACIABwl3Es8RAD4BABoAAglBDr1OAHYAAAUAAgm+Don3AGgAAAAA.',
Il='Illyría:BAAALgADCgcJBwAAAA==.Ilovetouka:BAAALgAECgMJBQAAAA==.',
Ir='Ironlotss:BAAALgADCgkJDQAAAA==.',
Iz='Izumo:BAABLgAECn8VAAIeAAYJnBiNAQBHAQAeAAYJnBiNAQBHAQAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAFFAUJCAAWAJwSAA==.Jakob:BAAALgAECgEJBAAAAA==.Jaks:BAAALgADCgEJAQAAAA==.Jamaris:BAAALgAECgYJCQABLgAECgkJWAAVAOwgAA==.Jardal:BAAALgADCgkJFgAAAA==.Jatswamdi:BAABLgAFFH8FAAMBAAMJpBV8AwDEAAABAAMJpBV8AwDEAAARAAIJYgLItQBJAAAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAABLgAECn8iAAIFAAgJ2w8VZAB9AQAFAAgJ2w8VZAB9AQAAAA==.Jenanila:BAAALgAECgMJBAAAAA==.',
Jh='Jhenna:BAAALgAECgQJBgABLgAECgkJLwAKAB8WAA==.',
Ji='Jibbs:BAABLgAECn8lAAMHAAkJpQfImQA2AQAHAAgJXQjImQA2AQAGAAEJmAKbaAAZAAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwAcAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJEAAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jolah:BAAALgAECgIJAgAAAA==.Jollakeratu:BAABLgAECn9TAAIkAAkJbRXTAQC7AQAkAAkJbRXTAQC7AQAAAA==.Jonnygordo:BAABLgAECn8bAAIRAAYJBxTRDQARAQARAAYJBxTRDQARAQAAAA==.Jorahh:BAABLgAECn8XAAMEAAcJHRY/NQBlAQAEAAYJHRY/NQBlAQACAAcJ2QysYAAJAQAAAA==.',
Ju='Jugernawt:BAAALgAECgEJAQABLgAECgkJOwABABIdAA==.Jugram:BAAALgAECgQJBAAAAA==.Jungolv:BAAALgADCgMJAwAAAA==.Jusmissiner:BAABLgAECn8iAAIFAAkJxx5yFgCEAgAFAAkJxx5yFgCEAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAABLgAECn8eAAIGAAkJKRtzEQD1AQAGAAkJKRtzEQD1AQAAAA==.',
['Jø']='Jønty:BAAALgADCgkJFgAAAA==.',
Ka='Kaelyra:BAAALgADCgkJFgAAAA==.Kaitenn:BAAALgAECgYJBgAAAA==.Kamehame:BAAALgAECggJEgAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECgkJRAACAFciAA==.',
Ke='Keelhorn:BAABLgAECn8lAAMCAAkJGRRVMwDlAQACAAkJGRRVMwDlAQAEAAMJgwdyewB9AAAAAA==.Kenneth:BAABLgAECn8cAAIRAAcJshJJgwBpAQARAAcJshJJgwBpAQAAAA==.Kerubiel:BAAALgAECggJCgABLgAECgkJWAAVAOwgAA==.Kessarah:BAAALgAECgkJAgAAAA==.Kevin:BAAALgAECgYJDAABLgAFFAUJDwALAIgcAA==.Keyadorath:BAAALgADCgIJAgAAAA==.',
Ki='Kibon:BAABLgAECn8ZAAMPAAYJsga7KABzAAAWAAYJ9AXxxQDDAAAPAAQJfgS7KABzAAAAAA==.Kindabored:BAAALgADCggJCAABLgAFFAQJGAAKADsOAA==.Kinkyhawt:BAEBLgAECn8YAAMlAAYJAB8KKwCSAQAUAAUJchuiFQCUAQAlAAYJZx4KKwCSAQAAAA==.Kirio:BAAALgADCgcJCgAAAA==.Kitsunenohi:BAABLgAECn9HAAIfAAkJiAoMBAA0AQAfAAkJiAoMBAA0AQAAAA==.',
Ko='Kodiakk:BAABLgAECn8nAAIaAAkJNRQ7HAC7AQAaAAkJNRQ7HAC7AQAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Krattos:BAAALgAFFAEJAQAAAA==.Krechon:BAAALgADCgQJBAAAAA==.Krimzin:BAAALgAECgEJAgABLgAFFAUJGwAFADAhAA==.',
Ks='Ksares:BAAALgAECgIJAgABLgAECgkJUAAFANwhAA==.',
Ku='Kuddles:BAAALgADCgEJBwAAAA==.Kumei:BAAALgAECgEJAQABLgAECgkJLAAFABEQAA==.Kural:BAAALgAECgUJBgABLgAECggJKAABAJsjAA==.',
Kw='Kwazii:BAABLgAECn8mAAQXAAgJ/BeiHgDQAQAXAAgJ/BeiHgDQAQADAAYJ+wUiVADCAAATAAIJJAWVbABTAAAAAA==.',
Ky='Kyantzmi:BAABLgAECn8fAAIJAAYJkxEgJwBeAQAJAAYJkxEgJwBeAQAAAA==.Kyogre:BAABLgAECn8cAAILAAcJ4RMAMgBTAQALAAcJ4RMAMgBTAQAAAA==.',
La='Laefnia:BAACLgAFFH8RAAQLAAQJTBdaDQDhAAALAAQJTBdaDQDhAAAKAAMJgRHpEgCeAAAkAAEJAwocPwAwAAAuAAQKfzQABQsACQnUGkIRAFECAAsACQmYGUIRAFECAAoACAnUGbswAN8BACQABQmfGJkeAFgBABkAAQk0Bn01AC4AAAAA.Lapisal:BAAALgADCgEJAQAAAA==.Laraydra:BAAALgAECgUJDAABLgAFFAMJBQAMAKQJAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJGQAjAD4QAA==.Lavaburstya:BAAALgAECgcJDAAAAA==.',
Le='Leelui:BAAALgAECgEJAQAAAA==.Leomist:BAABLgAECn8gAAMdAAkJ8A+XMQCyAQAdAAkJ8A+XMQCyAQAjAAEJKwpiFwAqAAAAAA==.Leviosä:BAABLgAECn8+AAMMAAkJOxj5MABVAgAMAAkJOxj5MABVAgANAAEJ2wbmFgAiAAAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgAECgUJBQAAAA==.Lilis:BAAALgAECgMJAwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8uAAIHAAkJZCRxDAAJAwAHAAkJZCRxDAAJAwAAAA==.Liten:BAAALgADCggJFQAAAA==.Littlebev:BAABLgAECn8bAAIPAAcJBQsEFwDrAAAPAAcJBQsEFwDrAAAAAA==.',
Lo='Lockins:BAAALgAECgcJCQAAAA==.Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJBwAAAA==.Longshankss:BAAALgAECgcJDwAAAA==.',
Lu='Luahn:BAAALgAECgcJBwAAAA==.',
Ly='Lynaiya:BAAALgADCgMJAwAAAA==.',
['Lé']='Léxí:BAAALgAECgkJCQAAAA==.',
['Lí']='Lírii:BAAALgAECggJEgAAAA==.',
['Lô']='Lôôbmeup:BAAALgADCgEJAQAAAA==.',
Ma='Maachen:BAAALgAECgYJDgAAAA==.Maalik:BAABLgAECn9YAAQVAAkJ7CCiAQDeAgAVAAkJpSCiAQDeAgAPAAcJfxoiCgCkAQAWAAMJgw6Y/gBqAAAAAA==.Magejackky:BAAALgAECgQJCAAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Maivorkeru:BAAALgAECgQJBgAAAA==.Malaurray:BAABLgAECn8jAAIWAAgJbQxDcgBVAQAWAAgJbQxDcgBVAQABLgABCgQJBgAcAAAAAA==.Maluin:BAAALgAECgEJAgABLgAECgkJTQAeADUcAA==.Mammoth:BAAALgAECgEJAQAAAA==.Mavanta:BAAALgAECgMJBAAAAA==.Mayonæse:BAABLgAECn8dAAIIAAUJRAxCmgDsAAAIAAUJRAxCmgDsAAAAAA==.',
Mc='Mcchong:BAABLgAECn8WAAIFAAcJjBYlEwDfAAAFAAcJjBYlEwDfAAAAAA==.Mckennah:BAABLgAECn8eAAMBAAgJbiGdBgB6AgABAAgJbiGdBgB6AgARAAEJDgwgpgEsAAAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAFFAQJEAAMACwTAA==.Mereidith:BAACLgAFFH8QAAMMAAQJLBPDXQAkAQAMAAQJLBPDXQAkAQAmAAEJXAYWCAA1AAAuAAQKfywAAwwABwmCHPdPAOwBAAwABwmCHPdPAOwBACYAAQlyGhMZAE8AAAAA.Meshulk:BAAALgAECgEJAQAAAA==.Mesohungry:BAABLgAECn8uAAMbAAkJiQkkOwBcAQAbAAkJiQkkOwBcAQARAAIJzAGPtwEnAAAAAA==.Metasploit:BAAALgAECgkJAQAAAA==.',
Mi='Mikehunte:BAAALgAECgYJBgABLgAECgkJIQAMANEfAA==.Miriya:BAABLgAECn8jAAIQAAkJyCR+AgA1AwAQAAkJyCR+AgA1AwAAAA==.Missnoms:BAAALgAECgEJAQAAAA==.',
Mo='Monkeycheese:BAABLgAECn8ZAAIjAAcJPhAKPAARAQAjAAcJPhAKPAARAQAAAA==.Moobáca:BAAALgAECgUJBwABLgAECggJJgAXAPwXAA==.Moostradamas:BAABLgAECn8oAAMYAAkJBQfqFgAgAQAYAAkJBQfqFgAgAQAHAAIJsgAWogEeAAAAAA==.Morcilla:BAABLgAECn8UAAMGAAkJngv3IwAzAQAGAAkJngv3IwAzAQAYAAMJ/gTKLgBlAAAAAA==.Morticyde:BAAALgAECgMJBAAAAA==.',
Ms='Msg:BAABLgAECn8lAAIKAAkJrBveFACjAgAKAAkJrBveFACjAgAAAA==.',
Mu='Munassa:BAAALgADCgcJBwAAAA==.Muppets:BAAALgAECgUJCQAAAA==.',
My='Myssidia:BAAALgADCgkJFQAAAA==.',
['Mí']='Mínervä:BAAALgAECgkJEAAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgIJAwAAAA==.Nasdaralth:BAAALgAECgMJBgABLgAFFAMJBQAMAKQJAA==.Nastrodamus:BAAALgAECgIJAgAAAA==.Naturegoob:BAABLgAECn8dAAMKAAkJjBogNADYAQAKAAgJphogNADYAQALAAUJBBZmCQCoAAAAAA==.Naughtynurse:BAABLgAECn9HAAIKAAkJixLVKwD7AQAKAAkJixLVKwD7AQAAAA==.Nayee:BAAALgAECgMJAwAAAA==.',
Ne='Nemrak:BAAALgAFFAIJAgAAAA==.Neuma:BAABLgAECn8UAAIRAAQJBAvfBQGxAAARAAQJBAvfBQGxAAAAAA==.',
Ni='Nicfurry:BAAALgADCgMJAwAAAA==.Nightflower:BAABLgAECn8kAAMmAAkJUwUhDwDRAAAMAAcJGQVEyQD8AAAmAAYJAwQhDwDRAAAAAA==.',
No='Noided:BAAALgAECgYJCgAAAA==.Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgYJDwABLgAECgYJEAAcAAAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
Ob='Obiejuan:BAACLgAFFH8HAAIRAAMJ2g2tdgDHAAARAAMJ2g2tdgDHAAAuAAQKf1MAAxEACQngIq8NAPgCABEACQngIq8NAPgCAAEABQlnHeMhAAUBAAAA.Obietide:BAAALgAECgkJEQABLgAFFAMJBwARANoNAA==.',
Od='Oddball:BAABLgAECn8eAAIEAAkJBhxMGQAYAgAEAAkJBhxMGQAYAgAAAA==.',
Of='Ofthecircle:BAAALgAECggJEwAAAA==.',
Ok='Okamiblooded:BAAALgAECgkJEgAAAA==.',
Ol='Olly:BAAALgAECgYJDQAAAA==.',
On='Ontala:BAAALgADCgYJBgAAAA==.',
Oo='Oodles:BAABLgAECn8UAAIMAAcJYRxwdwDjAQAMAAcJYRxwdwDjAQAAAA==.',
Op='Ophiron:BAAALgAECgUJBwAAAA==.',
Or='Orangecrush:BAABLgAECn8YAAIFAAcJ8wbMEgDiAAAFAAcJ8wbMEgDiAAAAAA==.Orangekeg:BAAALgAECgUJEQABLgAECgkJIgAEAN4fAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAABLgAECn8VAAIFAAgJsAubhgAxAQAFAAgJsAubhgAxAQAAAA==.',
Pa='Paduma:BAAALgADCgEJAQAAAA==.Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn88AAIGAAkJ2R1eCgBsAgAGAAkJ2R1eCgBsAgABLgAECggJKAABAJsjAA==.Persíkutor:BAAALgAECgQJBAAAAA==.Peso:BAAALgAECgQJBwABLgAECggJJgAXAPwXAA==.Pez:BAAALgAECgYJEQABLgAECgkJLwAKAB8WAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAABLgAFFH8bAAIdAAcJlBeuEgD0AQAdAAcJlBeuEgD0AQABLgAFFAUJDAAbAEsTAA==.Pomater:BAAALgAECgYJDgABLgAFFAMJBQAMAKQJAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAABLgAECn8YAAIMAAgJOQkLngA+AQAMAAgJOQkLngA+AQAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECgkJLAACALQgAA==.',
Pr='Primafox:BAAALgAECgYJDAAAAA==.Prkchopxpres:BAAALgAECgYJDwAAAA==.Protoheal:BAAALgAECgEJAgAAAA==.',
Ps='Psychoman:BAAALgAECgUJBQAAAA==.',
Pu='Punchandkick:BAAALgAECgMJBgAAAA==.Punkweight:BAAALgAECgEJAQAAAA==.Purpleeater:BAAALgAECgIJBQAAAA==.',
Py='Pyrabanks:BAABLgAFFH8KAAIlAAQJFwo3OgDdAAAlAAQJFwo3OgDdAAAAAA==.',
['Pä']='Päw:BAACLgAFFH8NAAMHAAMJThAzqgDKAAAHAAMJThAzqgDKAAAYAAIJMAWgIgB1AAAuAAQKfy4ABAcACQniHWFTAMoBAAcACAmhF2FTAMoBAAYABQnEHN0gAEsBABgAAwnjHz8aAP8AAAEuAAUUBAkRAAsATBcA.',
Qu='Quetzalcóatl:BAAALgAECgQJBAAAAA==.Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJAgAAAA==.',
Qx='Qx:BAAALgAECgYJBwAAAA==.',
Ra='Raakoth:BAAALgAECgYJEAABLgAECgkJWAAVAOwgAA==.Radge:BAABLgAECn87AAMnAAkJriUVAQBlAwAnAAkJriUVAQBlAwAOAAMJKR0rdgDiAAAAAA==.Rainjar:BAACLgAFFH8bAAMaAAUJiiHmBAAhAQAaAAQJnyHmBAAhAQAFAAIJkBv/eACmAAAuAAQKfzwAAxoACQkAIl4CAB8DABoACQlcH14CAB8DAAUACAk3JCQTALkCAAAA.Rainne:BAAALgADCgcJCAAAAA==.Raistyn:BAABLgAECn8pAAMBAAkJwRzUCwAIAgABAAkJwRzUCwAIAgARAAEJigwNqAErAAAAAA==.Ralanar:BAAALgAFFAEJAQABLgAFFAMJBQAMAKQJAA==.Raljah:BAABLgAECn8/AAQVAAkJ4CINAQAFAwAVAAkJ1CINAQAFAwAWAAcJBB8zKgAyAgAPAAUJXh19FACnAQAAAA==.Ramasus:BAAALgAECgUJBQAAAA==.Rampart:BAABLgAECn87AAMBAAkJEh1xBwBnAgABAAkJEh1xBwBnAgARAAEJ5w4EnAEvAAAAAA==.Rasaltghul:BAAALgAECgEJAQABLgAECgMJBgAcAAAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.Raxxer:BAAALgAECgEJBAAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAABLgAECn8UAAMBAAcJtw3YJwDYAAARAAcJ9gej0ADyAAABAAYJbg7YJwDYAAAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Rem:BAAALgAECgUJBQAAAA==.Renm:BAAALgAECgYJEgAAAA==.Renpriest:BAACLgAFFH8UAAITAAMJfx4QKgD+AAATAAMJfx4QKgD+AAAuAAQKfxUAAxMACAmMGVIRAC4CABMACAmMGVIRAC4CAAMAAQk4FUmBADoAAAAA.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgkJEQAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.Royaldüh:BAACLgAFFH8GAAIIAAIJ7wXRjABpAAAIAAIJ7wXRjABpAAAuAAQKfxcAAggABwlCFZpfAGoBAAgABwlCFZpfAGoBAAAA.',
Ru='Rubyraeven:BAAALgAECgcJBwAAAA==.',
Ry='Ryobi:BAABLgAECn9DAAMiAAkJJBqgCADyAQAFAAkJWBYAMwAQAgAiAAgJrhmgCADyAQAAAA==.Ryptyde:BAABLgAECn8WAAICAAkJ7h7YBwAyAwACAAkJ7h7YBwAyAwAAAA==.',
['Ræ']='Rævena:BAABLgAECn8ZAAIHAAYJRg/vEQDLAAAHAAYJRg/vEQDLAAAAAA==.',
Sa='Sachaann:BAAALgAECgIJAwAAAA==.Salinan:BAACLgAFFH8GAAMVAAMJDRI5DgCiAAAWAAMJewsNfgDIAAAVAAIJ1BU5DgCiAAAuAAQKf1EAAxUACQncJL8AACIDABUACQm3JL8AACIDABYABgntGshVAJsBAAAA.Saltymon:BAAALgADCgYJBgABLgAECgIJAwAcAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgkJNgAJAJocAA==.Saradia:BAAALgADCgIJAgAAAA==.Saric:BAAALgAECgMJBwAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Scanor:BAAALgAECgYJDAABLgAFFAMJDgAlAM4CAA==.Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.Scrim:BAAALgAECgEJAQAAAA==.',
Se='Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAABLgAECn8oAAIRAAkJBB0HIACIAgARAAkJBB0HIACIAgAAAA==.Selky:BAAALgADCgcJCgAAAA==.',
Sf='Sfodin:BAABLgAECn8eAAIOAAgJKQk9QQBAAQAOAAgJKQk9QQBAAQAAAA==.',
Sh='Shadowkings:BAAALgAFFAEJAwAAAA==.Shak:BAABLgAECn8gAAIEAAYJ0A5ATQAAAQAEAAYJ0A5ATQAAAQAAAA==.Shalai:BAAALgADCgMJAwAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shastix:BAAALgAECgYJEwABLgAECgkJWAAVAOwgAA==.Shellingtun:BAAALgAECgcJDQABLgAECggJJgAXAPwXAA==.Shiggylloway:BAAALgAECgEJAgAAAA==.Shyandrial:BAAALgAECgQJBQAAAA==.Shyness:BAAALgAECgQJBAAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAABLgAECn8rAAMDAAgJ1gvpMwBJAQADAAgJ1gvpMwBJAQAXAAQJtgieVACKAAAAAA==.',
Sk='Skilltotem:BAAALgAECgkJEAAAAA==.Skitch:BAAALgAECgEJAQAAAA==.Skk:BAAALgADCggJCQAAAA==.Sksteve:BAAALgAECgUJDwAAAA==.Skullyy:BAAALgAECgYJDgABLgAECgYJEAAcAAAAAA==.Skychades:BAABLgAECn8ZAAIFAAkJARgoQwDZAQAFAAkJARgoQwDZAQAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAABLgAECn8cAAILAAcJohD2OAAvAQALAAcJohD2OAAvAQABLgAECgkJDwAcAAAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECgkJDwAAAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgAECgcJDwAAAA==.Soulsrequiem:BAABLgAECn84AAIoAAgJtQUmAgDEAAAoAAgJtQUmAgDEAAAAAA==.',
Sp='Spiceynoodle:BAABLgAFFH8XAAIMAAUJQRkcHAAtAQAMAAUJQRkcHAAtAQAAAA==.Spookydeath:BAACLgAFFH8fAAIMAAUJCxb3HQAiAQAMAAUJCxb3HQAiAQAuAAQKfy4AAgwACQmrEnpJAP8BAAwACQmrEnpJAP8BAAAA.',
Sr='Srsnacksalot:BAABLgAECn8qAAIRAAgJ9hj1SgDlAQARAAgJ9hj1SgDlAQAAAA==.',
St='Stileto:BAAALgAECgcJEAABLgAECggJJgAXAPwXAA==.Stonedhuntar:BAAALgAECgcJCAAAAA==.Stoneydracco:BAABLgAECn8hAAIMAAgJIBPtgAB1AQAMAAgJIBPtgAB1AQAAAA==.Stoneydragon:BAAALgADCgYJBgAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECgkJEwAAAA==.',
Su='Sukiliana:BAAALgAECgQJBQAAAA==.Sumtinwng:BAABLgAECn85AAIRAAkJsBKjRwDvAQARAAkJsBKjRwDvAQAAAA==.Supervicious:BAABLgAECn8ZAAISAAkJuxUeFACuAQASAAkJuxUeFACuAQAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgkJFgAAAA==.Sylenne:BAABLgAECn8vAAIKAAkJHxaOHwBKAgAKAAkJHxaOHwBKAgAAAA==.Sylur:BAABLgAECn8ZAAMHAAkJfRnSAgBEAgAHAAkJfRnSAgBEAgAGAAEJlAxiSQAlAAAAAA==.Syrayvianda:BAAALgADCgYJBgAAAA==.',
['Sÿ']='Sÿlvanah:BAAALgAECgQJBAAAAA==.',
Ta='Taemea:BAAALgAECggJEgAAAA==.Tahran:BAAALgAFFAIJAgABLgAFFAcJIgATABkTAA==.Tahren:BAACLgAFFH8iAAQTAAcJGRNZFwC2AQATAAcJDw9ZFwC2AQAXAAQJBRU4EwAvAQADAAIJZgvAMQB/AAAuAAQKfyoABBcACQmIIHMQAGECABcABwn0IHMQAGECABMACQlvExMzAEwBAAMABwllEJZKAOUAAAAA.Talanima:BAAALgADCgcJBwAAAA==.Taler:BAAALgAFFAEJAQAAAA==.Talerion:BAAALgAECgcJEgAAAA==.Talyaine:BAAALgAECgUJBQABLgAFFAQJEQALAEwXAA==.Tanzanitia:BAAALgAECgYJBgABLgAECgcJBwAcAAAAAA==.',
Tc='Tcdots:BAAALgAECgEJAgAAAA==.',
Te='Telline:BAAALgADCgYJBwAAAA==.Tens:BAABLgAECn8bAAIOAAgJJiNXDAD1AgAOAAgJJiNXDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECgkJEwAAAA==.Theafflictor:BAAALgAECgcJCgAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECgkJEwAcAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thistelbear:BAABLgAECn9LAAIjAAkJ/g7PAgBaAQAjAAkJ/g7PAgBaAQAAAA==.Thrallsux:BAAALgAECgEJAgAAAA==.Thraun:BAABLgAECn8UAAIWAAYJ/Q+hhwBKAQAWAAYJ/Q+hhwBKAQAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn80AAMRAAkJsBKiagCpAQARAAkJsBKiagCpAQABAAcJaAspJgDkAAAAAA==.',
Ti='Titszilla:BAAALgAECgcJAwABLgAECggJJgAXAPwXAA==.',
To='Toki:BAABLgAECn8bAAMdAAYJxxuSLgDCAQAdAAYJxxuSLgDCAQAjAAQJqg+ZTQDbAAABLgAECgkJMgAhAJYfAA==.Tokidormi:BAABLgAECn8yAAMhAAkJlh9GAADPAgAhAAkJlh9GAADPAgAUAAUJPxPKEQDuAAAAAA==.Tokihots:BAAALgADCgkJEgAAAA==.Toralus:BAAALgADCgYJCQAAAA==.Totumm:BAAALgADCgcJCAAAAA==.',
Tr='Tralku:BAAALgAECgcJDAAAAA==.Tremmørs:BAABLgAECn8aAAIEAAcJUQy0UQDxAAAEAAcJUQy0UQDxAAAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAABLgAECn8UAAIRAAkJghZTYACwAQARAAkJghZTYACwAQAAAA==.',
Tu='Turnip:BAAALgAECgIJAgABLgAECggJJgAXAPwXAA==.',
Tw='Tweak:BAAALgAECgIJAgABLgAECggJJgAXAPwXAA==.Tweis:BAAALgADCgYJEQAAAA==.',
Ty='Tyllinor:BAAALgADCgUJBQAAAA==.',
Um='Umbrarogue:BAABLgAECn8eAAMJAAkJOBxtEQAdAgAJAAkJ0RptEQAdAgAoAAEJPh2vIQBVAAAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEwAAAA==.',
Va='Vaara:BAAALgAECgMJBAAAAA==.Valaa:BAAALgAECggJCQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAABLgAECn8WAAIRAAkJyA4CcgCYAQARAAkJyA4CcgCYAQAAAA==.Veliya:BAAALgAECgYJEwABLgAECgkJLwAKAB8WAA==.Vellestrix:BAAALgAECgQJBAAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Veriity:BAAALgAECgUJCwAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Vicotr:BAAALgAFFAEJAQAAAA==.Viddysouls:BAABLgAECn8hAAIgAAgJtRKeEQCaAQAgAAgJtRKeEQCaAQAAAA==.Vienaa:BAAALgAECgEJAQAAAA==.Viscerai:BAABLgAECn85AAIXAAkJiSVIAQCyAwAXAAkJiSVIAQCyAwAAAA==.Vite:BAAALgAECgYJDwAAAA==.Vitta:BAAALgAECgMJAwAAAA==.',
Vo='Vonmiller:BAACLgAFFH8FAAIVAAIJLhXQEACLAAAVAAIJLhXQEACLAAAuAAQKfxsAAxUACAn9FkAGAPkBABUACAn9FkAGAPkBABYAAgkSDPf7AGIAAAAA.Vozluz:BAAALgAECgEJAQABLgAECgkJWAAVAOwgAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECgkJDwAcAAAAAA==.',
['Væ']='Væda:BAAALgAECgMJAwAAAA==.',
Wa='Warfaxis:BAEBLgAECn86AAIOAAgJISRqBwDoAgAOAAgJISRqBwDoAgABLgAECgkJNgAbAAgkAA==.',
We='Weird:BAAALgAECgIJAgABLgAECgkJGAAKAB4SAA==.Wereßearßirb:BAAALgADCgUJBQAAAA==.',
Wi='Winnower:BAAALgADCgkJEwAAAA==.Wiseoldgoob:BAABLgAECn8dAAQTAAkJmxliCwC4AgATAAkJmxliCwC4AgADAAIJERjvCwCQAAAXAAEJkw4dbwAyAAAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAFFAIJBAAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAFFAMJAwAAAA==.',
Xu='Xugos:BAAALgAECgEJAQAAAA==.',
Yu='Yurie:BAAALgAECgMJAwABLgAECgQJBwAcAAAAAA==.',
Ze='Zenclaw:BAABLgAECn9BAAIdAAkJzhCJLQDIAQAdAAkJzhCJLQDIAQAAAA==.Zencore:BAABLgAECn8VAAIMAAgJeA99iABmAQAMAAgJeA99iABmAQAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECggJFQAMAHgPAA==.Zenlock:BAAALgADCgIJAgABLgAECggJFQAMAHgPAA==.',
Zi='Ziel:BAAALgAECgkJCwABLgAECgkJIwAQAMgkAA==.Ziya:BAAALgADCgIJAgAAAA==.',
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
