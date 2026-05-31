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

local lookup = {'Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Shaman-Restoration','Druid-Feral','Druid-Guardian','Warrior-Fury','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Warlock-Demonology','Monk-Mistweaver','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Monk-Windwalker','DeathKnight-Frost','Druid-Balance','Warrior-Protection','Shaman-Elemental','Shaman-Enhancement',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Ader:BAAALgADCgkJDQAAAA==.Advîl:BAAALgAECgQJBAAAAA==.',
Ae='Aeryhnn:BAAALgADCggJHwABLgAECgcJEAABAAAAAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAABLgAECn8hAAICAAYJhxZRNQBlAQACAAYJhxZRNQBlAQAAAA==.Alexandre:BAABLgAECn8gAAIDAAgJRBVAPgDQAQADAAgJRBVAPgDQAQAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAABLgAECn8XAAIEAAYJuA/rVgAiAQAEAAYJuA/rVgAiAQAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAABLgAECn8qAAQCAAgJOxs/EwBhAgACAAgJOxs/EwBhAgAFAAMJ3QPNPgBOAAAGAAEJRgcUhgErAAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJBgAAAA==.',
Ap='Aphroditee:BAAALgAECgIJAwAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgQJAwAAAA==.',
Aq='Aquafresh:BAABLgAECn82AAIHAAkJqh3sDwC6AgAHAAkJqh3sDwC6AgAAAA==.',
Ar='Archèrdayne:BAAALgAFFAEJAQAAAA==.Arisel:BAABLgAECn8tAAMIAAgJLhbxCwDYAQAIAAgJ+hXxCwDYAQAJAAUJpxAFHwCoAAAAAA==.Aristia:BAAALgAECgUJCAAAAA==.Artemisiah:BAAALgAECgEJAQAAAA==.Arweni:BAABLgAECn8zAAIKAAgJYhk9HAD4AQAKAAgJYhk9HAD4AQAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashcheeks:BAAALgAECgEJAQAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8gAAICAAgJECRDCADqAgACAAgJECRDCADqAgAAAA==.',
Av='Avlynn:BAAALgADCgMJAwABLgAFFAUJFgAHAEEMAA==.Avoidme:BAAALgADCgkJEQABLgAECgkJNwACANMdAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAAALgAECgYJDQABLgAECgkJNwACANMdAA==.Baridyn:BAAALgADCgMJBgAAAA==.Bariir:BAAALgAECgQJBAABLgAECgYJFAALAC4iAA==.',
Be='Bearbacked:BAAALgAECgQJBgAAAA==.Bearlytankin:BAAALgADCgkJCQAAAA==.Bearscat:BAAALgADCgUJBQAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Beerus:BAAALgAECgMJAwAAAA==.Belagrip:BAAALgAECgMJBAABLgAECgcJEAABAAAAAA==.Belashar:BAAALgAECgcJEAAAAA==.Belawar:BAAALgADCggJEAABLgAECgcJEAABAAAAAA==.Beleron:BAAALgADCgMJAwAAAA==.Beytuha:BAABLgAECn8dAAIJAAkJtSLnAQAcAwAJAAkJtSLnAQAcAwAAAA==.',
Bi='Bigtim:BAAALgAECgYJDQAAAA==.Bigworm:BAAALgADCgYJBgAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAABLgAECn8fAAMMAAcJaR4zRwDaAQAMAAcJaR4zRwDaAQANAAQJLBVJKwDlAAAAAA==.Blackknife:BAABLgAECn8uAAMOAAgJih4CEAAXAgAOAAgJih4CEAAXAgAPAAEJGAmnJQAvAAAAAA==.Bladestorm:BAAALgAECgEJAQABLgAECgYJFAALAC4iAA==.Blakylightz:BAACLgAFFH8FAAIFAAEJvxtOEgBNAAAFAAEJvxtOEgBNAAAuAAQKfx8AAwUACAnHGgQJAEYCAAUACAnHGgQJAEYCAAYABglzCXm6ABEBAAEuAAUUCAklAAkAzB4A.Blinker:BAABLgAECn8sAAIQAAgJxw1/gABcAQAQAAgJxw1/gABcAQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAUJEwAQAD4YAA==.Blueberriess:BAAALgAECgEJAQAAAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJEwABLgAFFAUJFgAEADEIAA==.Bobbidyboo:BAACLgAFFH8WAAIEAAUJMQiPIwAjAQAEAAUJMQiPIwAjAQAuAAQKfy0AAgQACQlsFao2AM0BAAQACQlsFao2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJCgAAAA==.Boomboompowa:BAAALgADCgYJBgAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJEgAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAAALgAECgYJEQAAAA==.Brixtia:BAAALgAECgEJAQABLgAECggJHAADAEIbAA==.Brovar:BAACLgAFFH8UAAIGAAUJIh0NLAA+AQAGAAUJIh0NLAA+AQAuAAQKfyoAAwYACAm1I3UaAMoCAAYACAm1I3UaAMoCAAIABQlcCu1zAKwAAAAA.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAACLgAFFH8JAAIRAAMJ3gcmPgCtAAARAAMJ3gcmPgCtAAAuAAQKfyIABBEACAkREVIsAG8BABEACAkREVIsAG8BABIABAnxB507AI4AABMAAQnDA31DACgAAAAA.Bubblez:BAAALgAECgUJDwAAAA==.Buddydaelf:BAABLgAECn8pAAIDAAgJbxs3MgD9AQADAAgJbxs3MgD9AQAAAA==.Bueskytter:BAAALgADCgEJAQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
Bw='Bwonshlongdi:BAAALgADCgcJBwAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Calithe:BAAALgAECgYJBgAAAA==.Candyman:BAAALgADCgYJDgAAAA==.Caprisan:BAAALgAECgQJBAABLgAECggJHAAGAD8aAA==.Castro:BAAALgADCgQJBAAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.Ceodochatos:BAAALgAECgEJAQABLgAECgkJGgAUALYJAA==.',
Ch='Chals:BAACLgAFFH8RAAMVAAQJhCFsCgB6AQAVAAQJhCFsCgB6AQAWAAIJsA3dMgCFAAAuAAQKfxgAAxUACQn6HCgOAHkCABUACQnyHCgOAHkCABYAAwkVGbA5ANkAAAEuAAUUBAkRABUAhCEA.Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Charfig:BAAALgADCgYJBgAAAA==.Chillfang:BAACLgAFFH8HAAMMAAMJfQ3hxACFAAAMAAIJfQ3hxACFAAANAAEJAACVVQAAAAAuAAQKfykAAgwACQm9HiMoAE0CAAwACQm9HiMoAE0CAAAA.Chune:BAAALgAECgQJEgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAAALgAECggJCAAAAA==.Clairvoyant:BAAALgAECgEJAQAAAA==.',
Co='Connor:BAABLgAECn8tAAMWAAkJChp0CwCaAgAWAAkJChp0CwCaAgAVAAEJgxecYgA8AAAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgcJEQAAAA==.',
Cr='Cracken:BAAALgADCgcJCAAAAA==.Cretinboy:BAAALgAECgMJAwAAAA==.Crosshair:BAAALgAECgQJDAAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgAECgQJBQABAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCQAAAA==.',
Da='Daciansniper:BAAALgADCggJCAAAAA==.Dacianwolf:BAAALgAECgUJAgAAAA==.Daemoni:BAAALgAECgYJCQAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJEgAAAA==.Darkerknight:BAAALgAECgQJBAABLgAECgkJNgAQABIgAA==.Darkprincess:BAAALgAECgUJBQAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgADCgcJDQABLgAECgYJFAALAC4iAA==.Davandar:BAAALgADCgkJEQAAAA==.Daveah:BAABLgAECn8sAAIHAAgJXRWlKQD7AQAHAAgJXRWlKQD7AQAAAA==.Dazarros:BAABLgAECn8dAAIXAAYJCxZybgBTAQAXAAYJCxZybgBTAQAAAA==.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8oAAIXAAgJxRG0UgCYAQAXAAgJxRG0UgCYAQAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dekkaa:BAAALgAECgEJAQAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgAECgUJCwAAAA==.Demoncharge:BAAALgAECgQJBAABLgAECggJDwABAAAAAA==.Demonclaw:BAAALgADCgMJAwABLgAECggJDwABAAAAAA==.Demondrake:BAAALgAECgUJCAABLgAECggJDwABAAAAAA==.Demonflayer:BAAALgAECggJDwAAAA==.Demonicow:BAAALgAECgcJDgAAAA==.Demonikat:BAAALgADCgYJDAAAAA==.Demonstalker:BAAALgAECgEJAQABLgAECggJDwABAAAAAA==.Denaeaa:BAACLgAFFH8HAAIYAAMJowZkOgB2AAAYAAMJowZkOgB2AAAuAAQKfxsAAhgACAkvDHBAADcBABgACAkvDHBAADcBAAEuAAUUBQkWAAcAQQwA.Destroyerman:BAAALgADCgQJBAAAAA==.Devilzkry:BAAALgAECgcJCwAAAA==.Devistaysha:BAAALgAECgcJDQAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgUJBQABLgAECgcJGQADAGMdAA==.',
Dh='Dhodge:BAABLgAECn8ZAAIUAAcJGR8XJwAaAgAUAAcJGR8XJwAaAgABLgAFFAMJBgAZAFohAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn83AAICAAkJ0x1KCgDSAgACAAkJ0x1KCgDSAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJCQAAAA==.',
Do='Dodgehoj:BAAALgAECgMJBAABLgAFFAMJBgAZAFohAA==.Doffyy:BAAALgAECgEJAQAAAA==.Dogbreathrlz:BAAALgAECgEJAQAAAA==.Dokash:BAAALgAECgUJCQABLgAFFAEJAQABAAAAAA==.Dotexe:BAABLgAECn8ZAAIPAAUJvB9EDwAeAQAPAAUJvB9EDwAeAQAAAA==.Dotsy:BAACLgAFFH8VAAQaAAUJJRvYAgBVAQAaAAUJvxnYAgBVAQAXAAMJFQ36bgDNAAAbAAEJFCA/HQBSAAAuAAQKfy8ABBsACQlNIq4PANMBABsABglDHK4PANMBABcABwnfHsVVAMYBABoABwkhIpMIAL4BAAAA.',
Dr='Drackarys:BAAALgADCggJFAAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgAECgUJCQAAAA==.Drakiir:BAAALgAECgQJCQABLgAECgYJFAALAC4iAA==.Dralkish:BAABLgAECn84AAIGAAkJLhMbaQCDAQAGAAkJLhMbaQCDAQAAAA==.Dramore:BAABLgAECn8fAAIaAAcJ1AruEQAlAQAaAAcJ1AruEQAlAQAAAA==.Drathi:BAAALgADCgcJBwABLgAECggJIwAGAHchAA==.Dravas:BAAALgAECgUJEgAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Drezzo:BAAALgADCgMJAwAAAA==.Droxx:BAAALgAECgYJDwAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drunkash:BAAALgAECgEJAQAAAA==.Dryerbro:BAAALgAECgEJAQAAAA==.Drzark:BAAALgAECgUJCAAAAA==.',
Du='Dundunduns:BAAALgAECgYJBgAAAA==.',
Dw='Dwdog:BAABLgAECn8nAAIaAAkJrxjDBQAIAgAaAAkJrxjDBQAIAgAAAA==.',
['Dà']='Dàthguy:BAACLgAFFH8NAAIMAAMJxiD/ZAAVAQAMAAMJxiD/ZAAVAQAuAAQKfzoAAgwACQnyJSwCAHQDAAwACQnyJSwCAHQDAAAA.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJDwAAAA==.',
El='Elennie:BAAALgAECgQJCAAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elephlock:BAAALgAECgQJBQAAAA==.Elephunch:BAAALgAECgUJBQAAAA==.Elerion:BAABLgAECn8jAAMWAAkJ6hMeFwD7AQAWAAkJ6hMeFwD7AQAcAAcJSQmvMwAoAQAAAA==.Elista:BAAALgADCgUJBQABLgADCgQJBAABAAAAAA==.Elm:BAAALgADCgUJBQAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgIJAgAAAA==.Emmi:BAABLgAECn8qAAIMAAgJIhz5MAAnAgAMAAgJIhz5MAAnAgAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIGAAcJ/B7jLwBjAgAGAAcJ/B7jLwBjAgAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.',
Fa='Faelivrin:BAAALgAECgYJBQAAAA==.Faith:BAAALgADCgYJBgAAAA==.Falcor:BAABLgAECn8eAAMRAAkJDCL+BwD5AgARAAkJwCH+BwD5AgATAAYJXSF4EQDIAQAAAA==.Faloran:BAAALgAECgEJAQAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgkJCQAAAA==.Fekk:BAAALgADCgIJAgABLgAECgUJBwABAAAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAABLgAECn8tAAINAAgJ7xsWDQAfAgANAAgJ7xsWDQAfAgAAAA==.Fifthelement:BAABLgAECn8lAAIHAAgJZx3ZFACKAgAHAAgJZx3ZFACKAgAAAA==.',
Fj='Fjalgeirr:BAABLgAECn8pAAMdAAgJQxWVGQCTAQAdAAgJQxWVGQCTAQAeAAUJIQbZJABcAAAAAA==.',
Fl='Flockling:BAAALgADCgYJBgAAAA==.',
Fo='Foxymomma:BAABLgAECn8nAAIVAAgJxR9uCQC8AgAVAAgJxR9uCQC8AgAAAA==.',
Fr='Frey:BAACLgAFFH8VAAIMAAUJ4iKfNABrAQAMAAUJ4iKfNABrAQAuAAQKfzIAAgwACQllJScEAFUDAAwACQllJScEAFUDAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8bAAMaAAkJiCBZAQDjAgAaAAcJ7iRZAQDjAgAXAAYJZxqnrADfAAAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fulgar:BAAALgAECgQJBQAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.',
Fw='Fwenwir:BAABLgAECn8aAAQfAAYJFSCWLADKAQAfAAYJfx+WLADKAQAgAAMJvxiMOQDYAAADAAEJ+xht9wBGAAAAAA==.',
Ga='Galatea:BAAALgAECgYJBgAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAABLgAECn8jAAIKAAgJBg4tMQBzAQAKAAgJBg4tMQBzAQAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJGgABLgAECggJKgACADsbAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gidgette:BAAALgAECgYJCwAAAA==.Gilalade:BAABLgAECn8pAAIDAAgJMxUhQQDHAQADAAgJMxUhQQDHAQAAAA==.Gingee:BAAALgADCgIJAgAAAA==.',
Gl='Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8iAAIMAAgJZgfMkgAtAQAMAAgJZgfMkgAtAQAAAA==.',
Go='Gobann:BAAALgADCggJEAABLgAECggJHAADAEIbAA==.Gooby:BAAALgAECgQJBAABLgAFFAYJFgACAJ4TAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Greencheese:BAAALgAECgIJAgAAAA==.Grimes:BAAALgAECgEJAQABLgAECgQJBgABAAAAAA==.Grlfriend:BAAALgAECgQJBAAAAA==.Grodin:BAAALgAECgQJBQAAAA==.Grofiest:BAABLgAECn8iAAMcAAgJxBYnGADqAQAcAAgJxBYnGADqAQAVAAEJjAHocgAbAAAAAA==.',
Gu='Guggychan:BAACLgAFFH8GAAIZAAMJWiFwFwD+AAAZAAMJWiFwFwD+AAAuAAQKfzkAAhkACQmGJrMAAHADABkACQmGJrMAAHADAAAA.',
['Gô']='Gôö:BAAALgAECgQJDAAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAIhAAkJTw/hJQBuAQAhAAkJTw/hJQBuAQAAAA==.Haelwyn:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.Haldor:BAABLgAECn8jAAIGAAgJewyjdQCPAQAGAAgJewyjdQCPAQAAAA==.Haohmaru:BAABLgAECn8qAAILAAgJ2x8NCwByAgALAAgJ2x8NCwByAgAAAA==.',
He='Healomatic:BAAALgAECgUJBQABLgAECgcJCgABAAAAAA==.Hecæte:BAAALgADCgYJBgAAAA==.Heella:BAAALgAECgEJAQAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgQJCAAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIXAAUJ+RRjjQA+AQAXAAUJ+RRjjQA+AQAAAA==.',
Hi='Him:BAAALgAECgkJEwAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.Holyshocks:BAAALgAECgEJAgAAAA==.',
Hp='Hplaysgames:BAAALgAECgMJAwAAAA==.',
Hu='Huneyhunter:BAABLgAECn8WAAIIAAYJ3QeLIgDNAAAIAAYJ3QeLIgDNAAAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
Im='Imsocold:BAACLgAFFH8MAAIMAAQJ9g2KYQAbAQAMAAQJ9g2KYQAbAQAuAAQKfyEAAgwACAmsIK4WAKwCAAwACAmsIK4WAKwCAAAA.',
In='Intern:BAABLgAECn8hAAQVAAcJ7hZ2HwCxAQAVAAcJ7hZ2HwCxAQAWAAMJ4QluWgBgAAAcAAEJAAA/jQAAAAAAAA==.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgADCgkJIAAAAA==.',
Iz='Iza:BAAALgADCgIJAgAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakethecake:BAAALgAECgMJAwAAAA==.Jaks:BAAALgAECgEJAQAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAABLgAECn8jAAITAAgJBA9OCQCAAQATAAgJBA9OCQCAAQAAAA==.Javeech:BAAALgAECgQJBgAAAA==.',
Jc='Jchaotic:BAAALgAECgUJCAAAAA==.',
Je='Jeezus:BAAALgADCgYJBgABLgAFFAQJEwAMAOgfAA==.',
Jo='Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwABAAAAAA==.Jongsoo:BAAALgAECgcJBwAAAA==.Jovero:BAAALgAECgQJBAAAAA==.',
Ju='Jutas:BAAALgAECggJEwAAAA==.Juudaz:BAACLgAFFH8TAAIMAAQJ6B/hMAB1AQAMAAQJ6B/hMAB1AQAuAAQKf0gABAwACQlmJZgCAG0DAAwACQlmJZgCAG0DAA0ABQkqIPIgADwBACIAAgn8CBcwADQAAAAA.',
Jv='Jvicious:BAAALgAECgcJCgAAAA==.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAABLgAECn8qAAMCAAgJpB+ADACzAgACAAgJpB+ADACzAgAGAAQJLxJmxgDiAAAAAA==.Kallan:BAAALgAECgUJDAAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kapkywa:BAABLgAECn8UAAIEAAgJ3yFoCgAEAwAEAAgJ3yFoCgAEAwABLgAECggJIAACABAkAA==.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.Katsumyo:BAAALgAECgMJAwAAAA==.',
Ke='Keggz:BAAALgAECgEJAQAAAA==.Kegpoker:BAAALgAECgcJEgAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgUJCAABAAAAAA==.',
Kh='Khaalzantro:BAAALgAECgIJAgAAAA==.',
Ki='Kilra:BAAALgAECgUJBQAAAA==.Kimbaltina:BAAALgADCgkJCQABLgAECggJLQAIAC4WAA==.Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJEgAAAA==.Kindasmall:BAAALgAECgkJAQAAAA==.Kiyara:BAABLgAECn81AAIDAAkJ5RP0MwD2AQADAAkJ5RP0MwD2AQAAAA==.Kizaki:BAAALgADCgkJDgABLgAECggJFwACAP8SAA==.',
Kn='Knowoone:BAABLgAECn9BAAIEAAkJZBj0GABrAgAEAAkJZBj0GABrAgAAAA==.',
Ko='Komonaut:BAAALgAECgYJCQAAAA==.Koscihardt:BAABLgAECn8VAAIQAAcJcwbvxADjAAAQAAcJcwbvxADjAAAAAA==.Kouelwhip:BAAALgADCgEJAQABLgAECgYJFAALAC4iAA==.',
Kr='Krelliz:BAABLgAECn8cAAIHAAcJTRBmXAApAQAHAAcJTRBmXAApAQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAABLgAECn8eAAIQAAcJhgrGpAAYAQAQAAcJhgrGpAAYAQAAAA==.Krystar:BAAALgAECgUJDQAAAA==.',
Ku='Kulfig:BAAALgAECgcJDgAAAA==.Kumen:BAABLgAECn8hAAQjAAkJISC+EQA2AgAjAAgJjx2+EQA2AgAIAAQJ+RwaFABZAQAJAAUJUxZiJwD0AAAAAA==.Kungfuwho:BAACLgAFFH8NAAMhAAQJbxD4EwAOAQAhAAQJbxD4EwAOAQAYAAIJLAKcRQBNAAAuAAQKfzQAAyEACAkpGXYbALwBACEACAkpGXYbALwBABgABglwCiZWAOAAAAAA.Kutyou:BAAALgADCggJEwAAAA==.',
Ky='Kynlailia:BAAALgADCgQJBAAAAA==.',
['Kû']='Kûnei:BAAALgAECgQJBwAAAA==.',
La='Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lenaea:BAACLgAFFH8WAAIHAAUJQQw8JAAyAQAHAAUJQQw8JAAyAQAuAAQKfyUAAgcACQnwGCsoAAMCAAcACQnwGCsoAAMCAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAACLgAFFH8LAAICAAQJKg4FIgD4AAACAAQJKg4FIgD4AAAuAAQKfycAAgIACAkAFcwjANIBAAIACAkAFcwjANIBAAAA.Liiege:BAABLgAECn8UAAMMAAUJww9u3wC6AAAMAAUJww9u3wC6AAANAAIJwg+GPABiAAABLgAECgYJFAALAC4iAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Litesuprmcst:BAAALgAECgEJAQAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJCAAAAA==.',
Lo='Lobø:BAABLgAECn8hAAIDAAgJuReaOQDhAQADAAgJuReaOQDhAQAAAA==.Loganx:BAAALgAECgMJAwABLgAECgcJCwABAAAAAA==.Loxen:BAAALgADCgEJAQAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn8sAAIMAAkJqAgSaACCAQAMAAkJqAgSaACCAQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgUJCAAAAA==.Lutherisch:BAAALgAECgQJBAABLgAECgUJCAABAAAAAA==.Lux:BAAALgAECgQJBAAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgAECgEJAQAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAABLgAECn8kAAIQAAcJ2AmxpQAXAQAQAAcJ2AmxpQAXAQAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgAECgIJBAAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAAALgAECgYJDwAAAA==.Manatee:BAAALgAECgYJDAAAAA==.Mannan:BAAALgADCgIJAgAAAA==.Marlasinger:BAAALgADCgcJCwAAAA==.Marpesia:BAAALgAECgcJCgAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Maygwyn:BAABLgAECn8aAAIQAAcJtgWPwADqAAAQAAcJtgWPwADqAAAAAA==.',
Me='Mediva:BAAALgAECgIJAgAAAA==.Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgYJDwAAAA==.Megaera:BAACLgAFFH8GAAIUAAMJwhvOIwCxAAAUAAMJwhvOIwCxAAAuAAQKfx4AAxQACQnuIPMOAAcDABQACQnuIPMOAAcDAB0AAQkeGBZsADoAAAAA.Melar:BAABLgAECn8nAAMKAAcJpg/oOQBJAQAKAAcJpg/oOQBJAQAkAAEJWAC+UQARAAAAAA==.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.',
Mi='Migmong:BAAALgAECgEJAgAAAA==.Mihawk:BAAALgAECgQJBwAAAA==.Milwaukee:BAAALgAECgEJAQAAAA==.Minjae:BAAALgAECgYJDwABLgAECgkJOgAXAPkWAA==.Minseo:BAAALgAECgEJAgAAAA==.Miserain:BAAALgAECgIJAgAAAA==.Mistbehaving:BAAALgAECgQJBAAAAA==.',
Mo='Moondemon:BAAALgADCgEJAQAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Moozart:BAAALgADCgEJAQAAAA==.Morphumbra:BAAALgAECgEJAQAAAA==.Morrìgan:BAABLgAECn8ZAAMXAAcJ3QXspADrAAAXAAcJ3QXspADrAAAbAAIJqwOUYgBJAAAAAA==.Mothra:BAAALgAECgQJBAABLgAECgkJGgAHAAgaAA==.Movack:BAABLgAECn8qAAIGAAkJpg6kVwCsAQAGAAkJpg6kVwCsAQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.',
Mu='Muncha:BAAALgAECgEJAgAAAA==.Murderface:BAABLgAECn8gAAMEAAgJ7xcFTwBAAQAEAAcJ8BUFTwBAAQAjAAYJrRZlOQARAQAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAABLgAECn8YAAIbAAgJswrpEQAPAQAbAAgJswrpEQAPAQAAAA==.Mythunran:BAABLgAECn8rAAIfAAgJJhMhDQB4AQAfAAgJJhMhDQB4AQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJDwABAAAAAA==.Natash:BAAALgAECgEJAgAAAA==.Nax:BAAALgAECgQJBQAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAgAAAA==.Nerfhammer:BAACLgAFFH8QAAIGAAQJshkPNQApAQAGAAQJshkPNQApAQAuAAQKfyoAAgYACQlLIwkcAMICAAYACQlLIwkcAMICAAAA.Nessalove:BAACLgAFFH8XAAIVAAUJixFoDwA0AQAVAAUJixFoDwA0AQAuAAQKfysAAhUACQmUHTgMAI8CABUACQmUHTgMAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8eAAQRAAkJjw0HNQA8AQARAAcJAQ4HNQA8AQASAAYJJxELHQAAAQATAAEJxANIQgArAAAAAA==.Nipao:BAAALgAECggJDwAAAA==.Niron:BAAALgAECgUJBwAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAABLgAFFH8LAAIYAAMJPROYKwDGAAAYAAMJPROYKwDGAAABLgAFFAgJLAAQAFIkAA==.Noriel:BAAALgAECgYJDwAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAAALgAECgYJDQAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Og='Ognyal:BAAALgAECgkJBQAAAA==.',
Oh='Ohtani:BAAALgAECgcJDAAAAA==.',
Ol='Olanali:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.Olectria:BAAALgADCgEJAQAAAA==.',
Oo='Ooblitoon:BAABLgAECn9EAAITAAkJWRP9BAAHAgATAAkJWRP9BAAHAgAAAA==.',
Or='Orfantal:BAABLgAECn8hAAIDAAkJExKEPwDMAQADAAkJExKEPwDMAQAAAA==.Oridon:BAAALgAECgQJBQAAAA==.',
Ou='Ouahoahoah:BAAALgAFFAEJAQAAAA==.',
Ov='Oven:BAAALgAECgQJBAABLgAFFAMJDQAMAMYgAA==.Overcast:BAAALgAECgQJBwAAAA==.Overshoot:BAABLgAECn8UAAMDAAgJ/QqRYABtAQADAAgJ/QqRYABtAQAgAAIJXgTOTgBYAAAAAA==.',
Ox='Oxen:BAAALgAECgYJBwAAAA==.',
Pa='Panterion:BAABLgAECn8eAAIEAAgJ/hYjLgDaAQAEAAgJ/hYjLgDaAQAAAA==.Parvarti:BAABLgAECn8dAAMbAAgJPAhbFQDjAAAbAAcJBQlbFQDjAAAXAAEJhwMSRgEhAAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECggJFwAMAGgbAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Persimmoñ:BAABLgAECn8sAAIGAAgJcg9YdQBpAQAGAAgJcg9YdQBpAQAAAA==.Petthemonk:BAAALgADCgcJBQAAAA==.',
Ph='Phaelissia:BAAALgAECgYJDwAAAA==.Philljr:BAAALgADCgMJAwAAAA==.',
Pi='Pinero:BAAALgADCgYJCQAAAA==.',
Pl='Plaugus:BAAALgAECgIJAgAAAA==.',
Po='Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgcJEQAAAA==.Prost:BAABLgAECn8ZAAIQAAgJOBu2ZQCZAQAQAAgJOBu2ZQCZAQAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Pu='Puppybreath:BAAALgAECgEJAQAAAA==.Purdy:BAAALgAECgkJAgAAAA==.',
Py='Pyroblast:BAACLgAFFH8TAAIQAAUJPhiuUQAuAQAQAAUJPhiuUQAuAQAuAAQKfzIAAhAACQljIB0hAO8CABAACQljIB0hAO8CAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Ravage:BAAALgAECgMJAwAAAA==.',
Re='Relaceara:BAABLgAECn8WAAIGAAkJswUfmgAlAQAGAAkJswUfmgAlAQAAAA==.Reladin:BAABLgAECn8qAAIFAAgJCwroHQAMAQAFAAgJCwroHQAMAQAAAA==.Relanna:BAABLgAECn8WAAIMAAYJjAcP1ADKAAAMAAYJjAcP1ADKAAAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCggJIwAAAA==.Rendstein:BAABLgAECn8eAAINAAgJ3Bi2EwC7AQANAAgJ3Bi2EwC7AQAAAA==.Renzr:BAACLgAFFH8IAAIMAAIJtSOckgDHAAAMAAIJtSOckgDHAAAuAAQKf0cAAwwACAnKJU8SAMkCAAwACAkdJU8SAMkCAA0ACAmeIjIGAK0CAAAA.Reqquuiiem:BAAALgADCgUJCAAAAA==.Respcct:BAAALgADCgkJCQABLgAECgkJNwACANMdAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAABLgAECn8UAAIEAAkJMQ9pQAB9AQAEAAkJMQ9pQAB9AQAAAA==.Rowin:BAAALgAECggJDwAAAA==.Royal:BAAALgAECgEJAQAAAA==.',
Ru='Rustedroots:BAABLgAECn8pAAIEAAgJ9RXoJAASAgAEAAgJ9RXoJAASAgAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Sailley:BAAALgAECgQJBQAAAA==.Saltgrizzny:BAAALgAECgYJDAAAAA==.Sapphyre:BAAALgAECgEJAgAAAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAABLgAECn8dAAIfAAkJVBNzCQDIAQAfAAkJVBNzCQDIAQAAAA==.Sarnara:BAABLgAECn8mAAIFAAgJbRr7CwDuAQAFAAgJbRr7CwDuAQABLgAECgkJGgAUALYJAA==.Savageclaw:BAAALgAECggJCAAAAA==.Savagehunt:BAAALgAECgEJAgABLgAECgYJFQALAO0gAA==.Savagekegs:BAABLgAECn8VAAMLAAYJ7SD8OABmAQALAAQJZSP8OABmAQAhAAUJQhhUPQAmAQAAAA==.Savagex:BAAALgAECgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAABLgAECn8hAAIDAAgJ8QPplAD6AAADAAgJ8QPplAD6AAAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgAECgEJAQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Senarx:BAAALgAECgIJBAAAAA==.Sereniity:BAABLgAECn8UAAQLAAYJLiLwGADOAQALAAYJLiLwGADOAQAYAAUJFBefMQAxAQAhAAEJrBbRgwA7AAAAAA==.',
Sh='Shamalicous:BAABLgAECn8UAAMHAAUJAgKvmgBwAAAHAAUJAgKvmgBwAAAlAAQJ+wXedABrAAAAAA==.Shamjam:BAABLgAECn8jAAIHAAgJ+BF1NQDAAQAHAAgJ+BF1NQDAAQAAAA==.Shamous:BAAALgAECgEJAQAAAA==.Shampayne:BAAALgADCgYJBgABLgAFFAQJEwAMAOgfAA==.Shanthe:BAAALgAECgYJEQAAAA==.Sharku:BAACLgAFFH8IAAIQAAMJChI/bQDnAAAQAAMJChI/bQDnAAAuAAQKfyYAAhAACAnlH3UxADsCABAACAnlH3UxADsCAAAA.Shãdo:BAAALgAECgYJCAAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAECgkJHgARAAwiAA==.Siinep:BAAALgAECgcJEAAAAA==.',
Sk='Skey:BAAALgADCgIJAgAAAA==.Skibblé:BAABLgAECn8XAAIbAAgJ1Q1dDQBLAQAbAAgJ1Q1dDQBLAQAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAABLgAECn8VAAIEAAgJKxbzNQCuAQAEAAgJKxbzNQCuAQAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIUAAgJrSGCEgDrAgAUAAgJrSGCEgDrAgAAAA==.Smokeyjr:BAAALgADCgcJBwAAAA==.',
Sn='Sneakyboi:BAABLgAECn8uAAIPAAkJZRohBABIAgAPAAkJZRohBABIAgAAAA==.Snippin:BAAALgAECgIJAgAAAA==.',
So='Soléne:BAAALgAECggJEQABLgAFFAQJBgAXABEPAA==.Sorden:BAAALgAECgQJBgAAAA==.',
Sp='Spiced:BAABLgAECn8ZAAIjAAgJSCC0DQDAAgAjAAgJSCC0DQDAAgABLgAECgkJGwAaAIggAA==.Spliff:BAAALgAECgIJAgAAAA==.',
Sq='Squirt:BAABLgAECn8aAAISAAgJvQ88GgC6AQASAAgJvQ88GgC6AQAAAA==.',
Ss='Ssks:BAAALgAFFAEJAQABLgAECgMJCwABAAAAAA==.',
St='Stabsmcshank:BAACLgAFFH8KAAIOAAQJ/A20GgAmAQAOAAQJ/A20GgAmAQAuAAQKfykAAg4ACQmqFhgdABYCAA4ACQmqFhgdABYCAAAA.Starbux:BAABLgAECn8kAAQWAAcJpxHrJwBuAQAWAAcJKw/rJwBuAQAVAAUJEA8/WgDLAAAcAAUJ3geaUwCZAAAAAA==.Steakx:BAAALgAECgQJBgAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Suriel:BAAALgAECgcJEAAAAA==.Suumcuique:BAAALgAECgIJAgABLgAECggJIAAEAO8XAA==.',
Sv='Svenya:BAABLgAECn8XAAMjAAgJyQ3aQQDpAAAjAAcJ2AraQQDpAAAEAAYJOAXAfACxAAAAAA==.',
Sy='Syenna:BAAALgAECgEJAQAAAA==.Sygne:BAAALgAECgQJBQAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAABLgAECn8tAAIDAAgJtg44UgCTAQADAAgJtg44UgCTAQAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJCAABLgAECgkJGgAHAAgaAA==.',
['Sï']='Sïenna:BAAALgAECgkJDwAAAA==.',
Ta='Taggy:BAABLgAECn8rAAIPAAgJaQ8ACgCGAQAPAAgJaQ8ACgCGAQABLgAECggJLQAIAC4WAA==.Tankachi:BAAALgADCgIJAgAAAA==.Tassandie:BAAALgAECgQJBAABLgAECggJHgAEAP4WAA==.Tayebeh:BAAALgADCgcJDAAAAA==.',
Te='Terran:BAAALgAECgUJCAAAAA==.Texhd:BAAALgAECgYJBgABLgAFFAEJAQABAAAAAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.Thansus:BAAALgAECgEJAQAAAA==.Theçølletør:BAAALgAECgIJAgAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.Tinygibbs:BAAALgAECgMJBAAAAA==.',
To='Toiletnuker:BAABLgAECn8eAAQgAAgJ3A2JHACqAQAgAAgJHw2JHACqAQADAAYJug07jQALAQAfAAEJRAohOQAsAAABLgAECgkJNwACANMdAA==.Tokyojoe:BAABLgAECn8hAAIUAAkJshRiNADeAQAUAAkJshRiNADeAQAAAA==.Torocious:BAAALgAECgYJDQAAAA==.Torrick:BAABLgAECn8jAAQGAAgJdyGdGQCSAgAGAAgJdyGdGQCSAgACAAYJBRcRNwCfAQAFAAEJwxRjQwAwAAAAAA==.Torrickgreed:BAAALgADCgYJBgABLgAECggJIwAGAHchAA==.Totemtot:BAABLgAECn8mAAImAAgJeQVAGQAUAQAmAAgJeQVAGQAUAQAAAA==.Toupee:BAAALgAECgQJBQAAAA==.',
Tr='Tradrivia:BAAALgAECgMJBAAAAA==.Tronly:BAAALgADCgUJBQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Tw='Twinkish:BAAALgAECgEJAQAAAA==.',
Ty='Tyllivan:BAAALgADCgcJDgAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCgAAAA==.',
Uf='Uffizzle:BAAALgAECgUJBwAAAA==.',
Ul='Ulf:BAABLgAECn8bAAIHAAgJbRLWNQC+AQAHAAgJbRLWNQC+AQAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Va='Valquirie:BAABLgAECn85AAINAAkJsCD2AwDpAgANAAkJsCD2AwDpAgAAAA==.Valyrius:BAAALgADCggJCQABLgAECgUJBQABAAAAAA==.Varlamor:BAABLgAECn8VAAMVAAgJlws0LABSAQAVAAgJlws0LABSAQAcAAUJYQSuWgB9AAAAAA==.Vathraen:BAAALgAECgMJBgAAAA==.',
Ve='Velanistra:BAABLgAECn8oAAIGAAkJYg3uXgCaAQAGAAkJYg3uXgCaAQAAAA==.Velanya:BAAALgADCgkJFQAAAA==.Velnia:BAAALgAECgcJBwAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAABLgAECn8lAAIdAAgJZBG9HQBpAQAdAAgJZBG9HQBpAQAAAA==.Very:BAAALgAECgUJDQAAAA==.',
Vg='Vgerr:BAAALgAECgcJDgAAAA==.',
Vi='Viashino:BAAALgAECgEJAQABLgAECgQJBwABAAAAAA==.Vidarus:BAAALgAFFAIJAwABLgAFFAQJEAAGALIZAA==.Viridian:BAAALgAECgMJBgABLgAFFAMJBgAUAMIbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAABLgAECn8cAAMDAAgJQhsyRAC9AQADAAYJyxsyRAC9AQAfAAYJlBctFgDwAAAAAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAAALgAFFAEJAwAAAA==.Vynos:BAABLgAECn8hAAIXAAgJQgc1ggAqAQAXAAgJQgc1ggAqAQAAAA==.Vysant:BAAALgADCgIJAgABLgAECggJIQAXAEIHAA==.',
['Vä']='Väl:BAAALgAECgQJCAAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAABLgAECn8aAAMHAAkJCBpkUQBOAQAHAAYJ6hNkUQBOAQAlAAYJaxNtQwAKAQAAAA==.',
Wc='Wchaos:BAAALgAECgQJBAAAAA==.',
We='Welker:BAAALgADCgQJCAABLgAFFAMJCAAMAKAQAA==.Welkerdk:BAACLgAFFH8IAAIMAAMJoBCHhgDYAAAMAAMJoBCHhgDYAAAuAAQKfzIAAgwACQlJIPgTAL0CAAwACQlJIPgTAL0CAAAA.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgAUAMIbAA==.',
Wh='Whiskeycakes:BAAALgAECgEJAQABLgAECgQJBgABAAAAAA==.',
Wi='Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.Windeyaho:BAAALgAECggJCgAAAA==.',
Wo='Wolfman:BAABLgAECn8WAAILAAkJsgUuLgA7AQALAAkJsgUuLgA7AQAAAA==.Woökie:BAAALgADCgYJBgAAAA==.',
Xa='Xalidan:BAAALgAECgUJCgAAAA==.',
Xt='Xten:BAAALgAECgcJEAAAAA==.',
Ya='Yamzofsteel:BAAALgADCgMJAwAAAA==.Yath:BAAALgAECgMJAwAAAA==.',
Ye='Yeat:BAAALgAECgUJCwAAAA==.',
Yo='Yoatanius:BAAALgAECgEJAQAAAA==.Yoshinox:BAAALgAECgMJBAAAAA==.',
Yr='Yrelle:BAAALgADCggJCAABLgAECgcJEAABAAAAAA==.',
Za='Zalazam:BAABLgAECn8hAAMlAAkJPBzIEABWAgAlAAkJPBzIEABWAgAHAAEJjhnjrgBMAAAAAA==.Zalth:BAABLgAECn8jAAIQAAkJ4Aw6XQCvAQAQAAkJ4Aw6XQCvAQAAAA==.',
Ze='Zelliph:BAAALgAECgUJDQAAAA==.Zenagdrina:BAABLgAECn8WAAMgAAgJiQUIMAAYAQAgAAgJvQQIMAAYAQADAAIJBAa9/gA+AAAAAA==.Zenobiå:BAAALgAECggJEAAAAA==.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.',
Zh='Zhaann:BAAALgAECgcJEAAAAA==.',
Zo='Zokor:BAAALgADCgkJMgAAAA==.Zorach:BAAALgAECgYJBgAAAA==.',
['Zá']='Zárá:BAABLgAECn8jAAIQAAcJ0BDKhgBOAQAQAAcJ0BDKhgBOAQAAAA==.',
['Ðz']='Ðz:BAAALgAFFAEJAQAAAA==.',
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
