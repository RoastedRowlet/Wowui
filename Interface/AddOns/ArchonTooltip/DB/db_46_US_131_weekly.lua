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

local lookup = {'Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Shaman-Restoration','Druid-Feral','Druid-Guardian','Rogue-Assassination','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Warlock-Demonology','Monk-Mistweaver','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','Druid-Balance','Warrior-Protection','Shaman-Enhancement','Shaman-Elemental',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Ader:BAAALgADCgkJDQAAAA==.',
Ae='Aeryhnn:BAAALgADCggJHwABLgAECgYJDwABAAAAAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAABLgAECn8eAAICAAYJhxa5MQBnAQACAAYJhxa5MQBnAQAAAA==.Alexandre:BAABLgAECn8bAAIDAAgJLhJLUgB+AQADAAgJLhJLUgB+AQAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAABLgAECn8XAAIEAAYJuA/3UgAhAQAEAAYJuA/3UgAhAQAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAABLgAECn8jAAQCAAgJOxuBEQBkAgACAAgJOxuBEQBkAgAFAAMJ3QMpOgBOAAAGAAEJ2QY6bgEtAAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJBgAAAA==.',
Ap='Aphroditee:BAAALgAECgIJAwAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgEJAQAAAA==.',
Aq='Aquafresh:BAABLgAECn8xAAIHAAkJiRwdEgCRAgAHAAkJiRwdEgCRAgAAAA==.',
Ar='Archèrdayne:BAAALgAECgEJAQABLgAECgUJCQABAAAAAA==.Arisel:BAABLgAECn8lAAMIAAgJKBQcDQCwAQAIAAgJ8hMcDQCwAQAJAAQJOhIFHwCoAAABLgAECggJJQAKAJwOAA==.Aristia:BAAALgAECgUJCAAAAA==.Artemisiah:BAAALgAECgEJAQAAAA==.Arweni:BAABLgAECn8zAAILAAgJYhlZGQD/AQALAAgJYhlZGQD/AQAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashcheeks:BAAALgAECgEJAQAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8gAAICAAgJECRDCADqAgACAAgJECRDCADqAgAAAA==.',
Av='Avlynn:BAAALgADCgMJAwABLgAFFAQJEQAHAP4MAA==.Avoidme:BAAALgADCgkJEQABLgAECgkJNgACANMdAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAAALgAECgYJBwABLgAECgkJNgACANMdAA==.Baridyn:BAAALgADCgMJBgAAAA==.Bariir:BAAALgAECgQJBAABLgAECgYJEwABAAAAAA==.',
Be='Bearbacked:BAAALgAECgMJAwAAAA==.Bearlytankin:BAAALgADCgkJCQAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Beerus:BAAALgAECgMJAwAAAA==.Belagrip:BAAALgAECgMJBAABLgAECgYJDwABAAAAAA==.Belashar:BAAALgAECgYJDwAAAA==.Belawar:BAAALgADCggJCAABLgAECgYJDwABAAAAAA==.Beleron:BAAALgADCgMJAwAAAA==.Beytuha:BAABLgAECn8ZAAIJAAkJdyKlAQAYAwAJAAkJdyKlAQAYAwAAAA==.',
Bi='Bigtim:BAAALgAECgYJDQAAAA==.Bigworm:BAAALgADCgYJBgAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAABLgAECn8aAAMMAAYJ/hyubQBkAQAMAAYJ/hyubQBkAQANAAQJlhQEKQDeAAAAAA==.Blackknife:BAABLgAECn8uAAMOAAgJih5ODgAfAgAOAAgJih5ODgAfAgAKAAEJGAmyIgAxAAAAAA==.Bladestorm:BAAALgAECgEJAQABLgAECgYJEwABAAAAAA==.Blakylightz:BAACLgAFFH8FAAIFAAEJvxvyDwBPAAAFAAEJvxvyDwBPAAAuAAQKfx8AAwUACAnHGgQJAEYCAAUACAnHGgQJAEYCAAYABglzCXm6ABEBAAEuAAUUCAkfAAkArBkA.Blinker:BAABLgAECn8kAAIPAAgJIg0lfgBeAQAPAAgJIg0lfgBeAQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAQJEQAPAD4YAA==.Blueberriess:BAAALgAECgEJAQAAAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJEwABLgAFFAQJFAAEADsJAA==.Bobbidyboo:BAACLgAFFH8UAAIEAAQJOwnlKQDwAAAEAAQJOwnlKQDwAAAuAAQKfy0AAgQACQlsFao2AM0BAAQACQlsFao2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJCAAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJEgAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAAALgAECgYJDgAAAA==.Brixtia:BAAALgAECgEJAQABLgAECggJHAADAEIbAA==.Brovar:BAACLgAFFH8SAAIGAAQJIh3cIQBQAQAGAAQJIh3cIQBQAQAuAAQKfyoAAwYACAm1I3UaAMoCAAYACAm1I3UaAMoCAAIABQlcCu1zAKwAAAAA.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAACLgAFFH8GAAIQAAMJsQa8NwC0AAAQAAMJsQa8NwC0AAAuAAQKfyEABBAACAm3DuouAFYBABAACAm3DuouAFYBABEABAnxB507AI4AABIAAQnDA31DACgAAAAA.Bubblez:BAAALgAECgUJDAAAAA==.Buddydaelf:BAABLgAECn8mAAIDAAgJVhiQOQDNAQADAAgJVhiQOQDNAQAAAA==.Bueskytter:BAAALgADCgEJAQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
Bw='Bwonshlongdi:BAAALgADCgcJBwAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Calithe:BAAALgAECgYJBgAAAA==.Candyman:BAAALgADCgYJDgAAAA==.Caprisan:BAAALgAECgQJBAABLgAECggJGgAGAD8aAA==.Castro:BAAALgADCgQJBAAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.Ceodochatos:BAAALgAECgEJAQABLgAECgkJFgATALYJAA==.',
Ch='Chals:BAACLgAFFH8NAAMUAAQJ8h8lDgA0AQAUAAMJ4iMlDgA0AQAVAAIJsA1sLwCJAAAuAAQKfxcAAxQACAlIHygOAHkCABQACAk+HygOAHkCABUAAwkVGbA5ANkAAAEuAAUUBAkNABQA8h8A.Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Charfig:BAAALgADCgYJBgAAAA==.Chillfang:BAACLgAFFH8GAAIMAAIJfQ2bSgCKAAAMAAIJfQ2bSgCKAAAuAAQKfykAAgwACQm9Hk4kAFECAAwACQm9Hk4kAFECAAAA.Chune:BAAALgAECgQJEgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAAALgADCgMJAwAAAA==.Clairvoyant:BAAALgAECgEJAQAAAA==.',
Co='Connor:BAABLgAECn8sAAMVAAkJChrjCQCpAgAVAAkJChrjCQCpAgAUAAEJgxcNXQA+AAAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgcJEQAAAA==.',
Cr='Cracken:BAAALgADCgcJCAAAAA==.Crosshair:BAAALgAECgQJCQAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCQAAAA==.',
Da='Daciansniper:BAAALgADCggJCAAAAA==.Dacianwolf:BAAALgAECgUJAgAAAA==.Daemoni:BAAALgAECgYJCQAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJDgAAAA==.Darkerknight:BAAALgAECgQJBAABLgAECggJNAAPAKMfAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgADCgcJDQABLgAECgYJEwABAAAAAA==.Daveah:BAABLgAECn8kAAIHAAcJ7BfBLADWAQAHAAcJ7BfBLADWAQAAAA==.Dazarros:BAABLgAECn8VAAIWAAYJNBCCfwAlAQAWAAYJNBCCfwAlAQAAAA==.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8oAAIWAAgJxRFETACfAQAWAAgJxRFETACfAQAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgAECgUJCwAAAA==.Demoncharge:BAAALgAECgEJAQABLgAECggJDgABAAAAAA==.Demonclaw:BAAALgADCgMJAwABLgAECggJDgABAAAAAA==.Demondrake:BAAALgAECgUJCAABLgAECggJDgABAAAAAA==.Demonflayer:BAAALgAECggJDgAAAA==.Demonicow:BAAALgAECgcJDQAAAA==.Demonikat:BAAALgADCgUJBQAAAA==.Denaeaa:BAABLgAECn8bAAIXAAgJLwySOAA5AQAXAAgJLwySOAA5AQABLgAFFAQJEQAHAP4MAA==.Destroyerman:BAAALgADCgQJBAAAAA==.Devilzkry:BAAALgAECgcJCwAAAA==.Devistaysha:BAAALgAECgYJCgAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgUJBQABLgAECgcJGQADAGMdAA==.',
Dh='Dhodge:BAABLgAECn8ZAAITAAcJGR8KJAAhAgATAAcJGR8KJAAhAgABLgAFFAMJBQAYAJMcAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn82AAICAAkJ0x3KCADZAgACAAkJ0x3KCADZAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJCQAAAA==.',
Do='Doffyy:BAAALgAECgEJAQAAAA==.Dogbreathrlz:BAAALgAECgEJAQAAAA==.Dokash:BAAALgAECgUJCQAAAA==.Dotexe:BAABLgAECn8YAAIKAAUJvB9IDgAiAQAKAAUJvB9IDgAiAQAAAA==.Dotsy:BAACLgAFFH8TAAQZAAQJNxifAgBIAQAZAAQJ0hafAgBIAQAWAAMJFQ10ZADOAAAaAAEJFCBxGQBTAAAuAAQKfy8ABBoACQlNIq4PANMBABoABglDHK4PANMBABYABwnfHsVVAMYBABkABwkhImgHAMQBAAAA.',
Dr='Drackarys:BAAALgADCggJFAAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgAECgUJCQAAAA==.Drakiir:BAAALgAECgQJCQABLgAECgYJEwABAAAAAA==.Dralkish:BAABLgAECn83AAIGAAkJLhNLWQChAQAGAAkJLhNLWQChAQAAAA==.Dramore:BAABLgAECn8YAAIZAAcJ1ArtDwApAQAZAAcJ1ArtDwApAQAAAA==.Drathi:BAAALgADCgcJBwABLgAECggJIwAGAHchAA==.Dravas:BAAALgAECgUJDwAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Drezzo:BAAALgADCgMJAwAAAA==.Droxx:BAAALgAECgUJCgAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drunkash:BAAALgAECgEJAQAAAA==.Dryerbro:BAAALgAECgEJAQAAAA==.Drzark:BAAALgAECgQJBwAAAA==.',
Du='Dundunduns:BAAALgAECgUJBQAAAA==.',
Dw='Dwdog:BAABLgAECn8jAAIZAAkJrxjqBAAQAgAZAAkJrxjqBAAQAgAAAA==.',
['Dà']='Dàthguy:BAACLgAFFH8KAAIMAAMJxiAEWwAYAQAMAAMJxiAEWwAYAQAuAAQKfzEAAgwACQljJXANAC4DAAwACQljJXANAC4DAAAA.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJDwAAAA==.',
El='Elennie:BAAALgAECgQJBQAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elephlock:BAAALgAECgQJBAAAAA==.Elephunch:BAAALgAECgIJAgAAAA==.Elerion:BAABLgAECn8bAAMVAAgJdhVUGQDZAQAVAAgJdhVUGQDZAQAbAAQJDgpuSQC7AAAAAA==.Elista:BAAALgADCgUJBQABLgADCgQJBAABAAAAAA==.Elm:BAAALgADCgUJBQAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgIJAgAAAA==.Emmi:BAABLgAECn8lAAIMAAgJGxrkMgAQAgAMAAgJGxrkMgAQAgAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIGAAcJ/B7jLwBjAgAGAAcJ/B7jLwBjAgAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.',
Fa='Faith:BAAALgADCgYJBgAAAA==.Falcor:BAABLgAECn8eAAMQAAkJDCL+BwD5AgAQAAkJwCH+BwD5AgASAAYJXSF4EQDIAQAAAA==.Faloran:BAAALgAECgEJAQAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgkJAwAAAA==.Fekk:BAAALgADCgIJAgABLgAECgUJBwABAAAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAABLgAECn8lAAINAAgJ7xuSCwAmAgANAAgJ7xuSCwAmAgAAAA==.Fifthelement:BAABLgAECn8gAAIHAAgJ4RzPEwCAAgAHAAgJ4RzPEwCAAgAAAA==.',
Fj='Fjalgeirr:BAABLgAECn8hAAMcAAgJqxNGGQB/AQAcAAgJqxNGGQB/AQAdAAQJKAZWJwBDAAAAAA==.',
Fl='Flockling:BAAALgADCgYJBgAAAA==.',
Fo='Foxymomma:BAABLgAECn8iAAIUAAgJxR8tCADFAgAUAAgJxR8tCADFAgAAAA==.',
Fr='Frey:BAACLgAFFH8TAAIMAAQJICJ1LwBmAQAMAAQJICJ1LwBmAQAuAAQKfzIAAgwACQllJUIDAFsDAAwACQllJUIDAFsDAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8bAAMZAAkJiCBZAQDjAgAZAAcJ7iRZAQDjAgAWAAYJZxqIogDkAAAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fulgar:BAAALgAECgQJBQAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.',
Fw='Fwenwir:BAABLgAECn8aAAQeAAYJFSCWLADKAQAeAAYJfx+WLADKAQAfAAMJvxgHNgDZAAADAAEJ+xhe4wBIAAAAAA==.',
Ga='Galatea:BAAALgAECgYJBgAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAABLgAECn8gAAILAAgJBg4ILQB4AQALAAgJBg4ILQB4AQAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJGgABLgAECggJIwACADsbAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gidgette:BAAALgAECgYJCAAAAA==.Gilalade:BAABLgAECn8kAAIDAAgJXhPBQwCqAQADAAgJXhPBQwCqAQAAAA==.Gingee:BAAALgADCgIJAgAAAA==.',
Gl='Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8iAAIMAAgJZgfvhwAuAQAMAAgJZgfvhwAuAQAAAA==.',
Go='Gobann:BAAALgADCggJEAABLgAECggJHAADAEIbAA==.Gooby:BAAALgAECgQJBAABLgAFFAUJFAACAIMWAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Greencheese:BAAALgAECgIJAgAAAA==.Grimes:BAAALgAECgEJAQABLgAECgMJAwABAAAAAA==.Grlfriend:BAAALgADCgUJAQAAAA==.Grodin:BAAALgAECgEJAgAAAA==.Grofiest:BAABLgAECn8cAAMbAAgJgBSFGgDLAQAbAAgJgBSFGgDLAQAUAAEJjAGgbAAbAAAAAA==.',
Gu='Guggychan:BAACLgAFFH8FAAIYAAMJkxzRFwDbAAAYAAMJkxzRFwDbAAAuAAQKfzgAAhgACQl4JpAAAHQDABgACQl4JpAAAHQDAAAA.',
['Gô']='Gôö:BAAALgAECgQJDAAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAIgAAkJTw9tIgBzAQAgAAkJTw9tIgBzAQAAAA==.Haelwyn:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.Haldor:BAABLgAECn8jAAIGAAgJewwJfABWAQAGAAgJewwJfABWAQAAAA==.Haohmaru:BAABLgAECn8lAAIhAAgJhx8gCwBkAgAhAAgJhx8gCwBkAgAAAA==.',
He='Hecæte:BAAALgADCgYJBgAAAA==.Heella:BAAALgAECgEJAQAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgQJCAAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIWAAUJ+RRjjQA+AQAWAAUJ+RRjjQA+AQAAAA==.',
Hi='Him:BAAALgAECgkJCgAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.Holyshocks:BAAALgAECgEJAQAAAA==.',
Hu='Hugeincanada:BAAALgAFFAEJAQAAAA==.Huneyhunter:BAAALgAECgUJEAAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
Im='Imsocold:BAACLgAFFH8KAAIMAAQJ9g2YUwAmAQAMAAQJ9g2YUwAmAQAuAAQKfxkAAgwACAk9Gp0sACoCAAwACAk9Gp0sACoCAAAA.',
In='Intern:BAABLgAECn8fAAQUAAcJlRYVHQC4AQAUAAcJlRYVHQC4AQAVAAIJ8gpfTQBdAAAbAAEJAACOgQAAAAAAAA==.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgADCgkJIAAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jaks:BAAALgAECgEJAQAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAABLgAECn8eAAISAAgJEQ7uCAB6AQASAAgJEQ7uCAB6AQAAAA==.Javeech:BAAALgAECgEJAgAAAA==.',
Jc='Jchaotic:BAAALgAECgMJAwAAAA==.',
Je='Jeezus:BAAALgADCgYJBgABLgAFFAQJEAAMAGYeAA==.',
Jo='Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwABAAAAAA==.Jongsoo:BAAALgAECgYJBgAAAA==.',
Ju='Jutas:BAAALgAECgcJCwAAAA==.Juudaz:BAACLgAFFH8QAAIMAAQJZh73JgB9AQAMAAQJZh73JgB9AQAuAAQKf0EABAwACQlRJbICAGUDAAwACQnuJLICAGUDAA0ABQkqIPIgADwBACIAAgn8CLQnAEAAAAAA.',
Jv='Jvicious:BAAALgAECgcJCgAAAA==.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAABLgAECn8lAAMCAAgJpB/PCwCsAgACAAgJpB/PCwCsAgAGAAQJCxH3wgDhAAAAAA==.Kallan:BAAALgAECgUJDAAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kapkywa:BAAALgAECgcJEQABLgAECggJIAACABAkAA==.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.Katsumyo:BAAALgADCgUJBQAAAA==.',
Ke='Keggz:BAAALgAECgEJAQAAAA==.Kegpoker:BAAALgAECgcJEgAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgQJBwABAAAAAA==.',
Kh='Khaalzantro:BAAALgAECgIJAgAAAA==.',
Ki='Kilra:BAAALgAECgUJBQAAAA==.Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJEgAAAA==.Kindasmall:BAAALgAECgkJAQAAAA==.Kiyara:BAABLgAECn80AAIDAAgJuBV2PQC/AQADAAgJuBV2PQC/AQAAAA==.Kizaki:BAAALgADCgkJDgABLgAECggJFgACAP8SAA==.',
Kn='Knowoone:BAABLgAECn84AAIEAAkJjhUDHwArAgAEAAkJjhUDHwArAgAAAA==.',
Ko='Komonaut:BAAALgAECgYJCQAAAA==.Koscihardt:BAABLgAECn8VAAIPAAcJcwZltgD8AAAPAAcJcwZltgD8AAAAAA==.Kouelwhip:BAAALgADCgEJAQABLgAECgYJEwABAAAAAA==.',
Kr='Krelliz:BAABLgAECn8cAAIHAAcJTRAXVQAqAQAHAAcJTRAXVQAqAQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAABLgAECn8cAAIPAAcJbgpXlwAvAQAPAAcJbgpXlwAvAQAAAA==.Krystar:BAAALgAECgQJCAAAAA==.',
Ku='Kulfig:BAAALgAECgcJDgAAAA==.Kumen:BAABLgAECn8dAAMjAAgJdx8HEAA5AgAjAAgJjx0HEAA5AgAJAAUJUxaFIgD2AAAAAA==.Kungfuwho:BAACLgAFFH8MAAMgAAMJ4RDhGQDTAAAgAAMJ4RDhGQDTAAAXAAIJLAInOQBWAAAuAAQKfzQAAyAACAkpGf4YAL8BACAACAkpGf4YAL8BABcABglwCo9LAOIAAAAA.Kutyou:BAAALgADCggJCwAAAA==.',
Ky='Kynlailia:BAAALgADCgQJBAAAAA==.',
['Kû']='Kûnei:BAAALgAECgQJBwAAAA==.',
La='Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lenaea:BAACLgAFFH8RAAIHAAQJ/gyBLgDyAAAHAAQJ/gyBLgDyAAAuAAQKfyUAAgcACQnwGHckAAUCAAcACQnwGHckAAUCAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAACLgAFFH8KAAICAAQJKg7lHQABAQACAAQJKg7lHQABAQAuAAQKfycAAgIACAkAFf4gANYBAAIACAkAFf4gANYBAAAA.Liiege:BAAALgAECgYJEgABLgAECgYJEwABAAAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Litesuprmcst:BAAALgAECgEJAQAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJCAAAAA==.',
Lo='Lobø:BAABLgAECn8eAAIDAAgJuRfrMgDnAQADAAgJuRfrMgDnAQAAAA==.Loganx:BAAALgAECgMJAwABLgAECgcJCwABAAAAAA==.Loxen:BAAALgADCgEJAQAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn8jAAIMAAgJMwhrewBGAQAMAAgJMwhrewBGAQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgQJBwAAAA==.Lux:BAAALgAECgQJBAAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgAECgEJAQAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAABLgAECn8dAAIPAAcJ3wjWmQArAQAPAAcJ3wjWmQArAQAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgAECgIJBAAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAAALgAECgYJDwAAAA==.Manatee:BAAALgAECgYJCwAAAA==.Mannan:BAAALgADCgIJAgAAAA==.Marlasinger:BAAALgADCgcJCwAAAA==.Marpesia:BAAALgAECgcJCgAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Maygwyn:BAABLgAECn8UAAIPAAYJLgYgxwDhAAAPAAYJLgYgxwDhAAAAAA==.',
Me='Mediva:BAAALgADCgMJAwAAAA==.Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgYJDwAAAA==.Megaera:BAACLgAFFH8GAAITAAMJwhvOIwCxAAATAAMJwhvOIwCxAAAuAAQKfx4AAxMACQnuIPMOAAcDABMACQnuIPMOAAcDABwAAQkeGBZsADoAAAAA.Melar:BAABLgAECn8lAAMLAAcJoA9SNQBNAQALAAcJoA9SNQBNAQAkAAEJWAC+UQARAAAAAA==.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.',
Mi='Mihawk:BAAALgAECgQJBwAAAA==.Milwaukee:BAAALgAECgEJAQAAAA==.Minjae:BAAALgAECgYJDwABLgAECgkJNgAWAJAVAA==.Minseo:BAAALgAECgEJAgAAAA==.Miserain:BAAALgADCgMJAwAAAA==.Mistbehaving:BAAALgAECgQJBAAAAA==.Mistytouch:BAAALgADCgMJAwAAAA==.',
Mo='Moondemon:BAAALgADCgEJAQAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Moozart:BAAALgADCgEJAQAAAA==.Morphumbra:BAAALgAECgEJAQAAAA==.Morrìgan:BAABLgAECn8ZAAMWAAcJ3QVQmwDwAAAWAAcJ3QVQmwDwAAAaAAIJqwOUYgBJAAAAAA==.Movack:BAABLgAECn8mAAIGAAgJ8Q70ZwB/AQAGAAgJ8Q70ZwB/AQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.',
Mu='Muncha:BAAALgAECgEJAQAAAA==.Murderface:BAABLgAECn8bAAMEAAgJjBaQbAAOAQAEAAcJWxSQbAAOAQAjAAYJ5BWBNwAFAQAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAABLgAECn8YAAIaAAgJswoWEAAVAQAaAAgJswoWEAAVAQAAAA==.Mythunran:BAABLgAECn8pAAIeAAgJXBKqDABwAQAeAAgJXBKqDABwAQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJDwABAAAAAA==.Natash:BAAALgAECgEJAgAAAA==.Nax:BAAALgAECgQJBAAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAgAAAA==.Nerfhammer:BAACLgAFFH8QAAIGAAQJshkFKwA5AQAGAAQJshkFKwA5AQAuAAQKfyoAAgYACQlLIwkcAMICAAYACQlLIwkcAMICAAAA.Nessalove:BAACLgAFFH8VAAIUAAQJoRGTEgAEAQAUAAQJoRGTEgAEAQAuAAQKfysAAhQACQmUHTgMAI8CABQACQmUHTgMAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8eAAQQAAkJjw0YMQBJAQAQAAcJAQ4YMQBJAQARAAYJJxGUGwAAAQASAAEJxANIQgArAAAAAA==.Nipao:BAAALgAECgcJDgAAAA==.Niron:BAAALgAECgUJBwAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAABLgAFFH8JAAIXAAMJpQ0YKQCvAAAXAAMJpQ0YKQCvAAABLgAFFAgJKAAPAFIkAA==.Noriel:BAAALgAECgYJDwAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAAALgAECgYJDQAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Og='Ognyal:BAAALgAECgkJBQAAAA==.',
Oh='Ohtani:BAAALgAECgcJDAAAAA==.',
Ol='Olanali:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.Olectria:BAAALgADCgEJAQAAAA==.',
Oo='Ooblitoon:BAABLgAECn83AAISAAkJaRDJBQDbAQASAAkJaRDJBQDbAQAAAA==.',
Or='Orfantal:BAABLgAECn8hAAIDAAkJExJqOQDOAQADAAkJExJqOQDOAQAAAA==.',
Ov='Oven:BAAALgAECgQJBAABLgAFFAMJCgAMAMYgAA==.Overcast:BAAALgAECgQJBwAAAA==.Overshoot:BAAALgAECgcJDwAAAA==.',
Ox='Oxen:BAAALgAECgUJBQAAAA==.',
Pa='Panterion:BAABLgAECn8ZAAIEAAgJAxaGNQChAQAEAAgJAxaGNQChAQAAAA==.Parvarti:BAABLgAECn8YAAMaAAgJ/gW/FgDMAAAaAAcJZwa/FgDMAAAWAAEJhwNWMwEjAAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECggJEAABAAAAAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Persimmoñ:BAABLgAECn8kAAIGAAgJBQ4UagB7AQAGAAgJBQ4UagB7AQAAAA==.Petthemonk:BAAALgADCgcJBQAAAA==.',
Ph='Phaelissia:BAAALgAECgYJDwAAAA==.Philljr:BAAALgADCgMJAwAAAA==.',
Pi='Pinero:BAAALgADCgYJCQAAAA==.',
Pl='Plaugus:BAAALgADCgMJAwAAAA==.',
Po='Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgcJEQAAAA==.Prost:BAABLgAECn8WAAIPAAgJpBpBZQCXAQAPAAgJpBpBZQCXAQAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Pu='Puppybreath:BAAALgAECgEJAQAAAA==.Purdy:BAAALgAECgkJAgAAAA==.',
Py='Pyroblast:BAACLgAFFH8RAAIPAAQJPhjYRgA5AQAPAAQJPhjYRgA5AQAuAAQKfzIAAg8ACQljIB0hAO8CAA8ACQljIB0hAO8CAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Ravage:BAAALgADCgYJCAAAAA==.',
Re='Relaceara:BAABLgAECn8WAAIGAAkJswWbhwBAAQAGAAkJswWbhwBAAQAAAA==.Reladin:BAABLgAECn8lAAIFAAgJxwh2HQD6AAAFAAgJxwh2HQD6AAAAAA==.Relanna:BAABLgAECn8WAAIMAAYJjAdcxQDKAAAMAAYJjAdcxQDKAAAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCggJGwAAAA==.Rendstein:BAABLgAECn8bAAINAAgJ3BjKEQDBAQANAAgJ3BjKEQDBAQAAAA==.Renzr:BAACLgAFFH8GAAIMAAIJtSNSgwDOAAAMAAIJtSNSgwDOAAAuAAQKf0UAAwwACAnKJf0PAM0CAAwACAkdJf0PAM0CAA0ABwlVIt8JAEkCAAAA.Reqquuiiem:BAAALgADCgUJCAAAAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAABLgAECn8UAAIEAAkJMQ9oPAB/AQAEAAkJMQ9oPAB/AQAAAA==.Rowin:BAAALgAECggJDwAAAA==.Royal:BAAALgADCggJCAAAAA==.',
Ru='Rustedroots:BAABLgAECn8hAAIEAAgJgxSIJwDyAQAEAAgJgxSIJwDyAQAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Sailley:BAAALgAECgEJAQAAAA==.Saltdisney:BAAALgAECgQJBAABLgAFFAYJEgACAGAOAA==.Sapphyre:BAAALgAECgEJAQAAAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAABLgAECn8ZAAIeAAgJvBE3DAB5AQAeAAgJvBE3DAB5AQAAAA==.Sarnara:BAABLgAECn8hAAIFAAgJehn2CwDZAQAFAAgJehn2CwDZAQABLgAECgkJFgATALYJAA==.Savageclaw:BAAALgAECggJCAAAAA==.Savagehunt:BAAALgAECgEJAQABLgAECgYJFAAhAO0gAA==.Savagekegs:BAABLgAECn8UAAMhAAYJ7SD8OABmAQAhAAQJZSP8OABmAQAgAAUJQhhUPQAmAQAAAA==.Savagex:BAAALgAECgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAABLgAECn8ZAAIDAAgJzwMMjgDwAAADAAgJzwMMjgDwAAAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgAECgEJAQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Senarx:BAAALgAECgEJAQAAAA==.Sereniity:BAAALgAECgYJEwAAAA==.',
Sh='Shamalicous:BAAALgAECgUJEwAAAA==.Shamjam:BAABLgAECn8eAAIHAAgJ+BHcMADCAQAHAAgJ+BHcMADCAQAAAA==.Shampayne:BAAALgADCgYJBgABLgAFFAQJEAAMAGYeAA==.Shanthe:BAAALgAECgYJEQAAAA==.Sharku:BAABLgAECn8lAAIPAAgJ5R+aLABJAgAPAAgJ5R+aLABJAgAAAA==.Shãdo:BAAALgAECgIJAgAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAECgkJHgAQAAwiAA==.Siinep:BAAALgAECgcJEAAAAA==.',
Sk='Skibblé:BAAALgAECggJDwAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAAALgAECggJEwAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAITAAgJrSGCEgDrAgATAAgJrSGCEgDrAgAAAA==.Smokeyjr:BAAALgADCgcJBwAAAA==.',
Sn='Sneakyboi:BAABLgAECn8uAAIKAAkJZRqTAwBPAgAKAAkJZRqTAwBPAgAAAA==.Snippin:BAAALgAECgIJAgAAAA==.',
So='Soléne:BAAALgAECggJDwABLgAFFAMJBQAWAIoTAA==.Sorden:BAAALgAECgQJBgAAAA==.',
Sp='Spiced:BAABLgAECn8ZAAIjAAgJSCC0DQDAAgAjAAgJSCC0DQDAAgABLgAECgkJGwAZAIggAA==.Spliff:BAAALgAECgEJAQAAAA==.',
Sq='Squirt:BAABLgAECn8aAAIRAAgJvQ88GgC6AQARAAgJvQ88GgC6AQAAAA==.',
Ss='Ssks:BAAALgAECgMJBAABLgAECgMJCwABAAAAAA==.',
St='Stabsmcshank:BAACLgAFFH8JAAIOAAMJbgx2IADdAAAOAAMJbgx2IADdAAAuAAQKfykAAg4ACQmqFhgdABYCAA4ACQmqFhgdABYCAAAA.Starbux:BAABLgAECn8iAAQVAAcJlRANLABHAQAVAAYJ1Q8NLABHAQAUAAUJEA8/WgDLAAAbAAUJcAdrSwCyAAAAAA==.Steakx:BAAALgAECgQJBgAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Suriel:BAAALgAECgYJDwAAAA==.Suumcuique:BAAALgAECgIJAgABLgAECggJGwAEAIwWAA==.',
Sv='Svenya:BAAALgAECgYJEgAAAA==.',
Sy='Sygne:BAAALgAECgEJAQAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAABLgAECn8lAAIDAAgJtg6gSgCVAQADAAgJtg6gSgCVAQAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJCAABLgAECgkJGgAHAAgaAA==.',
['Sï']='Sïenna:BAAALgAECggJCwAAAA==.',
Ta='Taggy:BAABLgAECn8lAAIKAAgJnA5/CQCEAQAKAAgJnA5/CQCEAQAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Tassandie:BAAALgADCggJCQABLgAECggJGQAEAAMWAA==.Tayebeh:BAAALgADCgcJDAAAAA==.',
Te='Terran:BAAALgAECgUJBQAAAA==.Texhd:BAAALgAECgYJBgABLgAFFAgJHgAQALgaAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.Thansus:BAAALgAECgEJAQAAAA==.Theçølletør:BAAALgAECgIJAgAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.Tinygibbs:BAAALgAECgMJBAAAAA==.',
To='Toiletnuker:BAABLgAECn8XAAQfAAcJtQ33IQBtAQAfAAcJ2Qz3IQBtAQADAAYJug0lggALAQAeAAEJRApYNgAsAAABLgAECgkJNgACANMdAA==.Tokyojoe:BAABLgAECn8hAAITAAkJshT7LwDnAQATAAkJshT7LwDnAQAAAA==.Torocious:BAAALgAECgYJDQAAAA==.Torrick:BAABLgAECn8jAAQGAAgJdyEnFgChAgAGAAgJdyEnFgChAgACAAYJBRcRNwCfAQAFAAEJwxRjQwAwAAAAAA==.Torrickgreed:BAAALgADCgYJBgABLgAECggJIwAGAHchAA==.Totemtot:BAABLgAECn8lAAIlAAgJeQWJFgAUAQAlAAgJeQWJFgAUAQAAAA==.Toupee:BAAALgAECgEJAQAAAA==.',
Tr='Tradrivia:BAAALgAECgMJBAAAAA==.Tronly:BAAALgADCgUJBQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Tw='Twinkish:BAAALgAECgEJAQAAAA==.',
Ty='Tyllivan:BAAALgADCgcJCAAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCgAAAA==.',
Uf='Uffizzle:BAAALgAECgUJBwAAAA==.',
Ul='Ulf:BAABLgAECn8VAAIHAAgJcxEiNQCsAQAHAAgJcxEiNQCsAQAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Va='Valquirie:BAABLgAECn8xAAINAAcJJhrDFACaAQANAAcJJhrDFACaAQAAAA==.Valyrius:BAAALgADCggJCQABLgAECgUJBQABAAAAAA==.Varlamor:BAAALgAECgcJEAAAAA==.Vathraen:BAAALgAECgMJBgAAAA==.',
Ve='Velanistra:BAABLgAECn8oAAIGAAkJYg0xVACuAQAGAAkJYg0xVACuAQAAAA==.Velanya:BAAALgADCgkJFQAAAA==.Velnia:BAAALgAECgcJBwAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAABLgAECn8iAAIcAAgJZBGsGgBvAQAcAAgJZBGsGgBvAQAAAA==.Very:BAAALgAECgQJCAAAAA==.',
Vg='Vgerr:BAAALgAECgcJDgAAAA==.',
Vi='Viashino:BAAALgAECgEJAQABLgAECgQJBwABAAAAAA==.Vidarus:BAAALgAFFAEJAQABLgAFFAQJEAAGALIZAA==.Viridian:BAAALgAECgMJBgABLgAFFAMJBgATAMIbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAABLgAECn8cAAMDAAgJQhvgOwDFAQADAAYJyxvgOwDFAQAeAAYJlBeqFADyAAAAAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAAALgAFFAEJAwAAAA==.Vynos:BAABLgAECn8fAAIWAAcJ9wbykgAAAQAWAAcJ9wbykgAAAQAAAA==.Vysant:BAAALgADCgIJAgABLgAECgcJHwAWAPcGAA==.',
['Vä']='Väl:BAAALgAECgQJCAAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAABLgAECn8aAAMHAAkJCBqaSgBRAQAHAAYJ6hOaSgBRAQAmAAYJaxNIPgALAQAAAA==.',
We='Welker:BAAALgADCgQJCAABLgAFFAMJBwAMAKAQAA==.Welkerdk:BAACLgAFFH8HAAIMAAMJoBChdQDjAAAMAAMJoBChdQDjAAAuAAQKfzIAAgwACQlJIBgRAMUCAAwACQlJIBgRAMUCAAAA.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgATAMIbAA==.',
Wi='Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.Windeyaho:BAAALgAECgQJBAAAAA==.',
Wo='Wolfman:BAABLgAECn8WAAIhAAkJsgVHKwA/AQAhAAkJsgVHKwA/AQAAAA==.Woökie:BAAALgADCgYJBgAAAA==.',
Xa='Xalidan:BAAALgAECgUJCgAAAA==.',
Xt='Xten:BAAALgAECgYJDwAAAA==.',
Ya='Yath:BAAALgAECgMJAwAAAA==.',
Ye='Yeat:BAAALgAECgUJCwAAAA==.',
Yo='Yoatanius:BAAALgAECgEJAQAAAA==.Yoshinox:BAAALgAECgMJBAAAAA==.',
Za='Zalazam:BAABLgAECn8gAAMmAAgJyxtqFwD9AQAmAAgJyxtqFwD9AQAHAAEJjhlJoQBMAAAAAA==.Zalth:BAABLgAECn8dAAIPAAkJXwxiWQC0AQAPAAkJXwxiWQC0AQAAAA==.',
Ze='Zelliph:BAAALgAECgQJCAAAAA==.Zenagdrina:BAAALgAECgYJDwAAAA==.Zenobiå:BAAALgAECggJDwAAAA==.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.',
Zh='Zhaann:BAAALgAECgYJDwAAAA==.',
Zo='Zokor:BAAALgADCgkJKQAAAA==.Zorach:BAAALgAECgYJBgAAAA==.',
['Zá']='Zárá:BAABLgAECn8eAAIPAAcJFA+xhgBOAQAPAAcJFA+xhgBOAQAAAA==.',
['Ðz']='Ðz:BAAALgAECgQJBAAAAA==.',
['Ûn']='Ûncle:BAAALgADCgcJCwAAAA==.',
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
