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

local lookup = {'Priest-Shadow','Paladin-Holy','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Shaman-Restoration','Druid-Feral','Druid-Guardian','Shaman-Elemental','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Priest-Discipline','Unknown-Unknown','Warlock-Demonology','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','Druid-Balance','Warrior-Protection','Mage-Arcane','Shaman-Enhancement',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Ader:BAAALgADCgkJDQAAAA==.Advîl:BAAALgAECgQJBAAAAA==.',
Ae='Aeryhnn:BAAALgAECgQJBAABLgAECgcJFgABAJ8MAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAABLgAECn8hAAICAAYJhxZ6OQBiAQACAAYJhxZ6OQBiAQAAAA==.Albinodwarf:BAAALgAECgIJAwAAAA==.Alexandre:BAABLgAECn8lAAIDAAkJ/hXwMAAUAgADAAkJ/hXwMAAUAgAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAABLgAECn8aAAIEAAcJVw76UQBFAQAEAAcJVw76UQBFAQAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAABLgAECn8wAAQCAAkJ3xwtCwDYAgACAAkJ3xwtCwDYAgAFAAMJ3QOnRABOAAAGAAEJRgckrQEoAAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJBgAAAA==.Ansuz:BAAALgAECgEJAQAAAA==.',
Ap='Aphroditee:BAAALgAECgIJAwAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgQJAwAAAA==.',
Aq='Aquafresh:BAABLgAECn84AAIHAAkJ6R0qEgC5AgAHAAkJ6R0qEgC5AgAAAA==.',
Ar='Archèrdayne:BAAALgAFFAEJAwAAAA==.Arisel:BAABLgAECn8zAAMIAAkJEBohBwBnAgAIAAkJEBohBwBnAgAJAAUJpxAFHwCoAAAAAA==.Aristia:BAAALgAECgUJDQABLgAFFAQJCwAKAJMLAA==.Artemisiah:BAAALgAECgEJAQAAAA==.Arweni:BAABLgAECn82AAILAAgJYhltHAAJAgALAAgJYhltHAAJAgAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashcheeks:BAAALgAECgEJAQAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8gAAICAAgJECRDCADqAgACAAgJECRDCADqAgAAAA==.',
Av='Avlynn:BAAALgADCgMJAwABLgAFFAUJGwAHAD4MAA==.Avoidme:BAAALgADCgkJEQABLgAECgkJOAACANMdAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAAALgAECgYJDQABLgAECgkJOAACANMdAA==.Baridyn:BAAALgADCgMJBgAAAA==.Bariir:BAAALgAECgQJBQABLgAECgcJGQAMAAAUAA==.',
Be='Bearbacked:BAAALgAECgQJBgAAAA==.Bearlytankin:BAAALgADCgkJCQAAAA==.Bearscat:BAAALgADCgUJBQAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Beerus:BAAALgAECgMJAwAAAA==.Belagrip:BAAALgAECgMJBAABLgAECgcJGgAGAF4HAA==.Belashar:BAABLgAECn8aAAIGAAcJXge2ygD3AAAGAAcJXge2ygD3AAAAAA==.Belawar:BAAALgADCggJFgABLgAECgcJGgAGAF4HAA==.Beleron:BAAALgAECgIJAgAAAA==.Belinna:BAAALgAECgkJBwAAAA==.Beytuha:BAABLgAECn8sAAIJAAkJNSUCAQBZAwAJAAkJNSUCAQBZAwAAAA==.',
Bi='Bigtim:BAAALgAECgYJDgAAAA==.Bigworm:BAAALgADCgYJBgAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAABLgAECn8jAAMMAAgJMR/+LgBBAgAMAAgJMR/+LgBBAgANAAQJLBV/LwDhAAAAAA==.Blackknife:BAABLgAECn8uAAMOAAgJih4zEgASAgAOAAgJih4zEgASAgAPAAEJGAn1KAAvAAAAAA==.Bladestorm:BAAALgAECgUJCQABLgAECgcJGQAMAAAUAA==.Blakylightz:BAACLgAFFH8HAAIFAAMJyhleCQDcAAAFAAMJyhleCQDcAAAuAAQKfx8AAwUACAnHGgQJAEYCAAUACAnHGgQJAEYCAAYABglzCXm6ABEBAAEuAAUUCAktAAkAFyEA.Blinker:BAABLgAECn81AAIQAAkJ+QxxYwC0AQAQAAkJ+QxxYwC0AQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAYJFQAQALcYAA==.Blueberriess:BAAALgAECgEJAgAAAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJEwABLgAFFAYJGAAEAE8IAA==.Bobbidyboo:BAACLgAFFH8YAAIEAAYJTwgAIgBBAQAEAAYJTwgAIgBBAQAuAAQKfy0AAgQACQlsFao2AM0BAAQACQlsFao2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJDgAAAA==.Boomboompowa:BAAALgADCgYJBgAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJEgAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAAALgAECgYJEgAAAA==.Brixtia:BAAALgAECgEJAQABLgAECgkJIQADAGAcAA==.Brovar:BAACLgAFFH8UAAIGAAUJIh2WPAAsAQAGAAUJIh2WPAAsAQAuAAQKfyoAAwYACAm1I3UaAMoCAAYACAm1I3UaAMoCAAIABQlcCu1zAKwAAAAA.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAACLgAFFH8OAAIRAAMJ/gzcRACwAAARAAMJ/gzcRACwAAAuAAQKfyIABBEACAkREf8vAHUBABEACAkREf8vAHUBABIABAnxB507AI4AABMAAQnDA31DACgAAAAA.Bubblez:BAAALgAECgUJDwAAAA==.Buddydaelf:BAABLgAECn8uAAIDAAgJohwWKAA7AgADAAgJohwWKAA7AgAAAA==.Bueskytter:BAAALgADCgEJAQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
Bw='Bwonshlongdi:BAAALgADCgcJBwAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Calithe:BAAALgAECgYJBgAAAA==.Cambey:BAAALgAECgMJBQAAAA==.Candyman:BAAALgADCgYJDgAAAA==.Caprisan:BAAALgAECgQJBAABLgAECggJHAAGAD8aAA==.Castro:BAAALgADCgQJBAAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.Ceodochatos:BAAALgAECgMJAwABLgAECgkJKgAFAIgaAA==.',
Ch='Chals:BAACLgAFFH8SAAMUAAUJkSGPBwDRAQAUAAUJkSGPBwDRAQAVAAIJsA2sPAB/AAAuAAQKfxgAAxQACQn6HCgOAHkCABQACQnyHCgOAHkCABUAAwkVGbA5ANkAAAEuAAUUBQkSABQAkSEA.Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Charfig:BAAALgADCgYJBgAAAA==.Chia:BAAALgAECgYJBgABLgAFFAQJBgAHAKMWAA==.Chillfang:BAACLgAFFH8HAAMMAAMJfQ393QCFAAAMAAIJfQ393QCFAAANAAEJAAC4ZAAAAAAuAAQKfykAAgwACQm9HgcuAEUCAAwACQm9HgcuAEUCAAAA.Chouji:BAAALgADCgYJAgAAAA==.Chune:BAAALgAECgQJEgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAAALgAECgkJEgAAAA==.Clairvoyant:BAAALgAECgEJAQAAAA==.',
Co='Connor:BAABLgAECn8tAAMVAAkJChovDQCYAgAVAAkJChovDQCYAgAUAAEJgxc0agA7AAAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgcJEQAAAA==.',
Cr='Cracken:BAAALgADCgcJCAAAAA==.Cretinboy:BAAALgAECgMJAwAAAA==.Crosshair:BAAALgAECgQJDAAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgAECgYJCwAWAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCQAAAA==.',
Da='Daciansniper:BAAALgAECgUJBgAAAA==.Dacianwolf:BAAALgAECggJCAAAAA==.Daemoni:BAAALgAECgYJCQAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJEgAAAA==.Darkerknight:BAAALgAECgQJBAABLgAECgkJNgAQABIgAA==.Darkprincess:BAAALgAECgUJBQAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgADCgcJDQABLgAECgcJGQAMAAAUAA==.Darthbane:BAAALgAECgMJAwAAAA==.Dathguy:BAAALgAECgYJCgABLgAFFAQJEQAMAD8iAA==.Davandar:BAAALgADCgkJGgAAAA==.Daveah:BAABLgAECn8yAAIHAAkJGhSeJQApAgAHAAkJGhSeJQApAgAAAA==.Dazarros:BAACLgAFFH8FAAIXAAIJJgoNpwB/AAAXAAIJJgoNpwB/AAAuAAQKfyMAAhcACQmpFGAxABECABcACQmpFGAxABECAAAA.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8oAAIXAAgJxRHWWwCKAQAXAAgJxRHWWwCKAQAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dekkaa:BAAALgAECgEJAQAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgAECgUJCwAAAA==.Demoncharge:BAAALgAECgQJBAABLgAECggJEAAWAAAAAA==.Demonclaw:BAAALgAECgEJAQABLgAECggJEAAWAAAAAA==.Demondrake:BAAALgAECgUJCQABLgAECggJEAAWAAAAAA==.Demonflayer:BAAALgAECggJEAAAAA==.Demonikat:BAAALgADCgYJDAAAAA==.Demonstalker:BAAALgAECgEJAQABLgAECggJEAAWAAAAAA==.Denaeaa:BAACLgAFFH8MAAIYAAMJtQvtQwCJAAAYAAMJtQvtQwCJAAAuAAQKfxsAAhgACAkvDD1LADgBABgACAkvDD1LADgBAAEuAAUUBQkbAAcAPgwA.Destroyerman:BAAALgADCgQJBAAAAA==.Devilzkry:BAAALgAECgcJCwAAAA==.Devistaysha:BAAALgAFFAEJAQAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgUJBQABLgAECgcJGQADAGMdAA==.',
Dh='Dharmakat:BAAALgADCgUJBQAAAA==.Dhodge:BAABLgAECn8ZAAIZAAcJGR9UKwAYAgAZAAcJGR9UKwAYAgABLgAFFAMJBgAaAFohAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn84AAICAAkJ0x3qCwDNAgACAAkJ0x3qCwDNAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJCQAAAA==.',
Do='Dodgehoj:BAAALgAECgMJBAABLgAFFAMJBgAaAFohAA==.Doffyy:BAAALgAECgEJAQAAAA==.Dogbreathrlz:BAAALgAECgEJAQAAAA==.Dokash:BAAALgAECgUJCQABLgAFFAEJAwAWAAAAAA==.Dotexe:BAABLgAECn8bAAIPAAUJLiBKDgA9AQAPAAUJLiBKDgA9AQAAAA==.Dotsy:BAACLgAFFH8XAAQbAAYJLxhZBABCAQAbAAUJvxlZBABCAQAXAAQJ5wwpVwAUAQAcAAEJFCBhIwBNAAAuAAQKfy8ABBwACQlNIq4PANMBABwABglDHK4PANMBABcABwnfHsVVAMYBABsABwkhIjAKALgBAAAA.',
Dr='Drackarys:BAAALgADCggJFAAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgAECgUJCgAAAA==.Drakiir:BAAALgAECgYJDQABLgAECgcJGQAMAAAUAA==.Dralkish:BAACLgAFFH8FAAIGAAMJtQczewC4AAAGAAMJtQczewC4AAAuAAQKfzgAAgYACQkuE6lxAIgBAAYACQkuE6lxAIgBAAAA.Dramore:BAABLgAECn8kAAIbAAkJzgmzDQB8AQAbAAkJzgmzDQB8AQAAAA==.Drathi:BAAALgADCgcJBwABLgAECgkJMgAGAIQjAA==.Dravas:BAAALgAECgUJEwAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Drezzo:BAAALgADCgMJAwAAAA==.Droxx:BAABLgAECn8VAAIMAAYJCAzPuwABAQAMAAYJCAzPuwABAQAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drunkash:BAAALgAECgEJAQAAAA==.Dryerbro:BAAALgAECgEJAQAAAA==.Drzark:BAAALgAECgcJDgAAAA==.',
Du='Dumpling:BAAALgADCgEJAQAAAA==.Dundunduns:BAAALgAECgYJBgAAAA==.',
Dw='Dwdog:BAABLgAECn8nAAIbAAkJrxgcBwD/AQAbAAkJrxgcBwD/AQAAAA==.',
['Dà']='Dàthguy:BAACLgAFFH8RAAIMAAQJPyLqNACOAQAMAAQJPyLqNACOAQAuAAQKf0EAAgwACQnyJRsDAGwDAAwACQnyJRsDAGwDAAAA.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJEgAAAA==.',
El='Elennie:BAAALgAECgYJDAAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elephlock:BAAALgAECgQJBQAAAA==.Elephunch:BAAALgAECgUJBQAAAA==.Elerion:BAABLgAECn8jAAMVAAkJ6hOpGQAAAgAVAAkJ6hOpGQAAAgABAAcJSQmLNwA1AQAAAA==.Elista:BAAALgADCgUJBQABLgADCgQJBAAWAAAAAA==.Elm:BAAALgADCgUJBgAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgIJAgAAAA==.Emmi:BAABLgAECn80AAIMAAkJqh0mGwCiAgAMAAkJqh0mGwCiAgAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIGAAcJ/B7jLwBjAgAGAAcJ/B7jLwBjAgAAAA==.Eralis:BAAALgAECgYJBQAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.',
Fa='Faelivrin:BAAALgAECgcJBQAAAA==.Faith:BAAALgADCgYJBgAAAA==.Falcor:BAABLgAECn8eAAMRAAkJDCL+BwD5AgARAAkJwCH+BwD5AgATAAYJXSF4EQDIAQAAAA==.Faloran:BAAALgAECgEJAQAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgkJCQAAAA==.Fekk:BAAALgADCgIJAgABLgAECgUJCwAWAAAAAA==.Fenderbender:BAAALgADCgYJBgAAAA==.Feralstorm:BAAALgAECgYJCQAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feykat:BAAALgADCgUJBQAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAABLgAECn8yAAINAAkJLhy0CACIAgANAAkJLhy0CACIAgAAAA==.Fifthelement:BAABLgAECn8vAAIHAAkJsx21DQDlAgAHAAkJsx21DQDlAgAAAA==.',
Fj='Fjalgeirr:BAABLgAECn8vAAMdAAkJZxUmFgDUAQAdAAkJZxUmFgDUAQAeAAYJeAY4IgCIAAAAAA==.',
Fl='Fleapaw:BAAALgADCgcJBwAAAA==.Flockling:BAAALgADCgYJBgAAAA==.',
Fo='Foxymomma:BAABLgAECn8xAAIUAAkJtx4jBwD7AgAUAAkJtx4jBwD7AgAAAA==.',
Fr='Frey:BAACLgAFFH8VAAIMAAUJ4iK/RwBeAQAMAAUJ4iK/RwBeAQAuAAQKfzIAAgwACQllJXEFAE4DAAwACQllJXEFAE4DAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8bAAMbAAkJiCBZAQDjAgAbAAcJ7iRZAQDjAgAXAAYJZxo7tgDaAAAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fulgar:BAAALgAECgQJBgAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.Furryfido:BAAALgADCggJCAABLgAECgkJMgANAC4cAA==.',
Fw='Fwenwir:BAABLgAECn8aAAQfAAYJFSCWLADKAQAfAAYJfx+WLADKAQAgAAMJvxgtPgDRAAADAAEJ+xggEwFDAAAAAA==.',
Ga='Galatea:BAAALgAFFAEJAQAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAABLgAECn8pAAILAAkJ8A0oKgCtAQALAAkJ8A0oKgCtAQAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJGgABLgAECgkJMAACAN8cAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gidgette:BAAALgAECgYJCwAAAA==.Gilalade:BAABLgAECn8zAAIDAAkJDhtwGwB8AgADAAkJDhtwGwB8AgAAAA==.Gingee:BAAALgADCgIJAgAAAA==.',
Gl='Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8oAAIMAAgJIgiXmQAzAQAMAAgJIgiXmQAzAQAAAA==.',
Go='Gobann:BAAALgADCggJEAABLgAECgkJIQADAGAcAA==.Gooby:BAAALgAECgQJBAABLgAFFAYJGAACAO0UAA==.Gooney:BAAALgAECgIJAwAAAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Greencheese:BAAALgAECgIJAgABLgAECggJGwAMABoSAA==.Grimes:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.Grlfriend:BAAALgAECgYJDAAAAA==.Grodin:BAAALgAECgQJBQAAAA==.Grofiest:BAABLgAECn8jAAMBAAkJjBaAEwA0AgABAAkJjBaAEwA0AgAUAAEJjAFmfAAYAAAAAA==.',
Gu='Guggychan:BAACLgAFFH8GAAIaAAMJWiEXHwD1AAAaAAMJWiEXHwD1AAAuAAQKfzkAAhoACQmGJgEBAGgDABoACQmGJgEBAGgDAAAA.',
['Gô']='Gôö:BAAALgAECgQJDAAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAIhAAkJTw9YKgBmAQAhAAkJTw9YKgBmAQAAAA==.Haelwyn:BAAALgAECgEJAQABLgAECgEJAwAWAAAAAA==.Haldor:BAABLgAECn8jAAIGAAgJewyjdQCPAQAGAAgJewyjdQCPAQAAAA==.Haohmaru:BAABLgAECn80AAIiAAkJfR8NBwDFAgAiAAkJfR8NBwDFAgAAAA==.',
He='Healomatic:BAAALgAECgUJBQABLgAECgcJCgAWAAAAAA==.Hecæte:BAAALgADCgYJBgAAAA==.Heella:BAAALgAECgEJAQAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgQJCAAAAA==.Hercgrimx:BAAALgAECgcJDwAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIXAAUJ+RRjjQA+AQAXAAUJ+RRjjQA+AQAAAA==.',
Hi='Him:BAABLgAECn8lAAIKAAkJqBiREwBNAgAKAAkJqBiREwBNAgAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.Holyshocks:BAAALgAECgEJAgAAAA==.',
Hp='Hplaysgames:BAAALgAECgUJBwAAAA==.',
Hu='Huneyhunter:BAABLgAECn8YAAIIAAcJ5Qh+IQD2AAAIAAcJ5Qh+IQD2AAAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
Im='Imsocold:BAACLgAFFH8QAAMMAAUJeRC6cAAcAQAMAAQJeRC6cAAcAQANAAEJAAALZAAAAAAuAAQKfyUAAwwACAmsIKwaAKUCAAwACAmsIKwaAKUCACMABAmKEgcbAPMAAAAA.',
In='Intern:BAABLgAECn8lAAQUAAgJYRX/HADZAQAUAAgJSBX/HADZAQAVAAQJDQrjXACFAAABAAEJAAAZnQAAAAAAAA==.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgADCgkJIAAAAA==.',
Iz='Iza:BAAALgADCgIJAgAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakethecake:BAAALgAECgMJAwAAAA==.Jaks:BAAALgAECgEJAwAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAABLgAECn8oAAITAAkJAQ/xBwC0AQATAAkJAQ/xBwC0AQAAAA==.Javeech:BAAALgAECgQJBgAAAA==.',
Jc='Jchaotic:BAAALgAECggJDwAAAA==.',
Je='Jeezus:BAAALgADCgYJBgABLgAFFAUJGAAMALEhAA==.',
Jo='Jocie:BAAALgAECgEJAQAAAA==.Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwAWAAAAAA==.Jongsoo:BAAALgAECgcJCAAAAA==.Jovero:BAAALgAECgQJBQAAAA==.',
Ju='Jutas:BAABLgAECn8cAAMVAAgJdgtRLABzAQAVAAgJdgtRLABzAQABAAcJwAMxVwCzAAAAAA==.Juudaz:BAACLgAFFH8YAAMMAAUJsSEgRQBkAQAMAAQJ6B8gRQBkAQANAAQJlh8gGgAQAQAuAAQKf00ABAwACQlmJY4DAGYDAAwACQlmJY4DAGYDAA0ABwm3IWsOACICACMAAgn8CFk2AD0AAAAA.',
Jv='Jvicious:BAAALgAECgcJCgAAAA==.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAABLgAECn80AAMCAAkJtR+mBwAQAwACAAkJtR+mBwAQAwAGAAUJTRV9mgA9AQAAAA==.Kaliista:BAAALgAECgEJAQABLgAECgkJIAAEAOEWAA==.Kallan:BAAALgAECgUJDAAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kapkywa:BAABLgAECn8UAAIEAAgJ3yGzCwACAwAEAAgJ3yGzCwACAwABLgAECggJIAACABAkAA==.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.Katsumyo:BAAALgAECgMJAwAAAA==.',
Ke='Keggz:BAAALgAECgEJAQAAAA==.Kegpoker:BAAALgAECgcJEgAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgUJCAAWAAAAAA==.',
Kh='Khaalzantro:BAAALgAECgIJAgAAAA==.',
Ki='Kilra:BAAALgAECgUJBgAAAA==.Kimbaltina:BAAALgADCgkJGQABLgAECgkJMwAIABAaAA==.Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJEwAAAA==.Kindasmall:BAAALgAECgkJAQAAAA==.Kiyara:BAABLgAECn9HAAIDAAkJvBaJLQAjAgADAAkJvBaJLQAjAgAAAA==.Kizaki:BAAALgADCgkJDgABLgAECggJFwACAP8SAA==.',
Kn='Knowoone:BAABLgAECn9TAAIEAAkJHBkZFgCUAgAEAAkJHBkZFgCUAgAAAA==.',
Ko='Komonaut:BAABLgAECn8UAAMeAAYJ2wqIGwC7AAAeAAYJJgqIGwC7AAAZAAMJigjt3gByAAAAAA==.Koscihardt:BAABLgAECn8VAAIQAAcJcwZizwDvAAAQAAcJcwZizwDvAAAAAA==.Kouelwhip:BAAALgAECgEJAQABLgAECgcJGQAMAAAUAA==.',
Kr='Krelliz:BAABLgAECn8cAAIHAAcJTRBBZQAmAQAHAAcJTRBBZQAmAQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAABLgAECn8fAAIQAAcJhgpgrgAgAQAQAAcJhgpgrgAgAQAAAA==.Kronnk:BAAALgAECgEJAQAAAA==.Krystar:BAAALgAECgUJDgAAAA==.',
Ku='Kulfig:BAAALgAECgkJEQAAAA==.Kumen:BAABLgAECn8hAAQkAAkJISDFEwAzAgAkAAgJjx3FEwAzAgAIAAQJ+RxlFwBTAQAJAAUJUxaDLQDzAAAAAA==.Kungfuwho:BAACLgAFFH8RAAMhAAQJbxCkGQD1AAAhAAQJbxCkGQD1AAAYAAQJ/QM+PgCfAAAuAAQKfzYAAyEACQlZGYUeALUBACEACAkpGYUeALUBABgACAk6C2pLADcBAAAA.Kutyou:BAAALgADCgkJHAAAAA==.',
Ky='Kynlailia:BAAALgADCgQJBAAAAA==.',
['Kû']='Kûnei:BAAALgAECgQJBwAAAA==.',
La='Laladin:BAAALgAECgMJAwAAAA==.Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lenaea:BAACLgAFFH8bAAIHAAUJPgzILgAfAQAHAAUJPgzILgAfAQAuAAQKfyUAAgcACQnwGM0sAAACAAcACQnwGM0sAAACAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAACLgAFFH8OAAICAAQJKg5jKADbAAACAAQJKg5jKADbAAAuAAQKfycAAgIACAkAFQknAM8BAAIACAkAFQknAM8BAAAA.Liiege:BAABLgAECn8ZAAMMAAcJABR1cQB+AQAMAAcJABR1cQB+AQANAAIJwg+GPABiAAAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Litesuprmcst:BAAALgAECgEJAQAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJCAAAAA==.',
Lo='Lobø:BAABLgAECn8mAAIDAAkJRxi6KwAqAgADAAkJRxi6KwAqAgAAAA==.Loganx:BAAALgAECgUJBwABLgAECgcJCwAWAAAAAA==.Lorsie:BAAALgADCgUJBQABLgAECgkJKAAGAGINAA==.Loxen:BAAALgAECgEJAQAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn8+AAIMAAkJUQvdYQCiAQAMAAkJUQvdYQCiAQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgUJCAAAAA==.Lutherisch:BAAALgAECgUJBQABLgAECgUJCAAWAAAAAA==.Lux:BAAALgAECgQJBAAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgAECgQJBAAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAABLgAECn8oAAIQAAgJ6wi+lwBGAQAQAAgJ6wi+lwBGAQAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgAECgIJBQAAAA==.Magnues:BAAALgADCgQJBAAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAAALgAECgYJEAAAAA==.Manatease:BAAALgAECgEJAQAAAA==.Manatee:BAAALgAECgYJDQAAAA==.Mannan:BAAALgADCgIJAgAAAA==.Marlasinger:BAAALgADCgcJCwAAAA==.Marpesia:BAAALgAECgcJCgAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Marteris:BAAALgAECgEJAQAAAA==.Maygwyn:BAABLgAECn8bAAIQAAcJtgUhyQD4AAAQAAcJtgUhyQD4AAAAAA==.',
Me='Mediva:BAAALgAECgUJCQAAAA==.Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgYJDwAAAA==.Megaera:BAACLgAFFH8GAAIZAAMJwhvOIwCxAAAZAAMJwhvOIwCxAAAuAAQKfx4AAxkACQnuIPMOAAcDABkACQnuIPMOAAcDAB0AAQkeGBZsADoAAAAA.Melar:BAABLgAECn8qAAMLAAgJFBBiMgCBAQALAAgJFBBiMgCBAQAlAAEJWAC+UQARAAAAAA==.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.Messyah:BAAALgAFFAEJAQAAAA==.',
Mi='Migmong:BAAALgAECgIJBQAAAA==.Mihawk:BAAALgAECgQJBwAAAA==.Milwaukee:BAAALgAECgEJAQAAAA==.Minjae:BAABLgAECn8YAAMXAAYJ9BYicABZAQAXAAYJTRYicABZAQAbAAEJ/hCsPAA2AAABLgAFFAMJCAAXAI8UAA==.Minseo:BAAALgAECgEJAwAAAA==.Miserain:BAAALgAECgUJCQAAAA==.Mistbehaving:BAAALgAECgQJBAAAAA==.',
Mo='Moondemon:BAAALgADCgEJAQAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Moozart:BAAALgADCgEJAQAAAA==.Morphumbra:BAAALgAECgEJAQAAAA==.Morrìgan:BAABLgAECn8ZAAMXAAcJ3QUWsQDiAAAXAAcJ3QUWsQDiAAAcAAIJqwOUYgBJAAAAAA==.Mothra:BAAALgAECgQJBQABLgAFFAQJBgAHAKMWAA==.Movack:BAABLgAECn8rAAIGAAkJpg6MYgCpAQAGAAkJpg6MYgCpAQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.Mozwangsung:BAAALgADCgIJAwAAAA==.',
Mu='Muncha:BAAALgAECgEJAgAAAA==.Murderface:BAABLgAECn8lAAMkAAkJZxbKIgCwAQAkAAgJhRbKIgCwAQAEAAcJpBbLTwBNAQAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAABLgAECn8aAAIcAAkJgQq5EAA0AQAcAAkJgQq5EAA0AQAAAA==.Mythunran:BAABLgAECn8rAAIfAAgJJhPADgBtAQAfAAgJJhPADgBtAQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJEgAWAAAAAA==.Natash:BAAALgAECgEJAgAAAA==.Nawas:BAAALgAECgEJAgAAAA==.Nax:BAAALgAECgQJBQAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAgAAAA==.Nerfhammer:BAACLgAFFH8RAAIGAAUJXxpOIwBzAQAGAAUJXxpOIwBzAQAuAAQKfyoAAgYACQlLIwkcAMICAAYACQlLIwkcAMICAAAA.Nessalove:BAACLgAFFH8ZAAIUAAYJxg8mDQByAQAUAAYJxg8mDQByAQAuAAQKfysAAhQACQmUHTgMAI8CABQACQmUHTgMAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8eAAQRAAkJjw11OQBEAQARAAcJAQ51OQBEAQASAAYJJxHJHgD9AAATAAEJxANIQgArAAAAAA==.Nipao:BAABLgAECn8WAAIYAAgJKRaXIgAEAgAYAAgJKRaXIgAEAgAAAA==.Niron:BAAALgAECgUJBwAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAABLgAFFH8NAAIYAAMJPRM8OAC7AAAYAAMJPRM8OAC7AAABLgAFFAgJMAAQAFIkAA==.Noriel:BAAALgAECgYJDwAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAABLgAECn8UAAIDAAcJNRETagBpAQADAAcJNRETagBpAQAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Og='Ognyal:BAAALgAECgkJBQAAAA==.',
Oh='Ohtani:BAAALgAECgkJDgAAAA==.',
Ol='Olanali:BAAALgAECgEJAwABLgAECgEJAwAWAAAAAA==.Olectria:BAAALgADCgEJAQAAAA==.',
Oo='Ooblitoon:BAABLgAECn9QAAITAAkJghOiBQD/AQATAAkJghOiBQD/AQAAAA==.',
Op='Opali:BAAALgAECgEJAQAAAA==.',
Or='Orfantal:BAABLgAECn8hAAIDAAkJExKdSQDAAQADAAkJExKdSQDAAQAAAA==.Oridan:BAAALgAECgEJAQAAAA==.Oridon:BAAALgAECgQJCQAAAA==.',
Ou='Ouahoahoah:BAAALgAFFAEJAQAAAA==.',
Ov='Oven:BAAALgAECgUJBQABLgAFFAQJEQAMAD8iAA==.Overcast:BAAALgAECgYJEAAAAA==.Overshoot:BAABLgAECn8aAAMDAAkJlgwnTgCzAQADAAkJlgwnTgCzAQAgAAIJXgSgVABXAAAAAA==.',
Ow='Owyyn:BAAALgADCggJCAAAAA==.',
Ox='Oxen:BAAALgAECgYJBwAAAA==.',
Pa='Panterion:BAABLgAECn8gAAIEAAkJ4RY0JQAgAgAEAAkJ4RY0JQAgAgAAAA==.Parvarti:BAABLgAECn8fAAMcAAkJDQg9GADdAAAcAAcJBQk9GADdAAAXAAIJJgWyFQFPAAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECgkJGQAMAAYdAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Persimmoñ:BAABLgAECn8xAAIGAAkJkQ+cXQC0AQAGAAkJkQ+cXQC0AQAAAA==.Petthemonk:BAAALgADCgcJCwAAAA==.',
Ph='Phaelissia:BAAALgAECgYJDwAAAA==.Philljr:BAAALgADCgMJAwAAAA==.',
Pi='Pinero:BAAALgADCgYJCQAAAA==.',
Pl='Plaugus:BAAALgAECgUJCQAAAA==.',
Po='Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgcJEQAAAA==.Prost:BAABLgAECn8fAAIQAAkJlxxHRAAMAgAQAAkJlxxHRAAMAgAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Pu='Puppybreath:BAAALgAECgEJAQAAAA==.Purdy:BAAALgAECgkJAgAAAA==.',
Py='Pyroblast:BAACLgAFFH8VAAIQAAYJtxiTOQCHAQAQAAYJtxiTOQCHAQAuAAQKfzwAAxAACQleIcERAO0CABAACQmWIMERAO0CACYAAwkGI1wHADUBAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Ravage:BAAALgAECgMJAwAAAA==.',
Re='Relaceara:BAABLgAECn8WAAIGAAkJswX3pQArAQAGAAkJswX3pQArAQAAAA==.Reladin:BAABLgAECn80AAIFAAkJPgrsGgA9AQAFAAkJPgrsGgA9AQAAAA==.Relanna:BAABLgAECn8WAAIMAAYJjAd05wDHAAAMAAYJjAd05wDHAAAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCggJIwAAAA==.Rendstein:BAABLgAECn8jAAINAAkJhhg6EQD1AQANAAkJhhg6EQD1AQAAAA==.Renzr:BAACLgAFFH8JAAIMAAIJtSPBrADDAAAMAAIJtSPBrADDAAAuAAQKf0cAAwwACAnKJakVAMMCAAwACAkdJakVAMMCAA0ACAmeIlMHAKQCAAAA.Reqquuiiem:BAAALgADCgUJCAAAAA==.Respcct:BAAALgADCgkJGgABLgAECgkJOAACANMdAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAABLgAECn8UAAIEAAkJMQ/SRAB6AQAEAAkJMQ/SRAB6AQAAAA==.Rowin:BAABLgAECn8VAAMEAAkJ4gY3ZQACAQAEAAkJ4gY3ZQACAQAkAAMJzQcuawBwAAAAAA==.Royal:BAAALgAECgEJAQAAAA==.',
Ru='Rustedroots:BAABLgAECn8uAAIEAAkJPRfCGgBtAgAEAAkJPRfCGgBtAgAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Sailley:BAAALgAECgQJBQAAAA==.Saltgrizzny:BAAALgAECgcJDQAAAA==.Sapphyre:BAAALgAECgEJAgAAAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAABLgAECn8dAAIfAAkJVBPZCgC5AQAfAAkJVBPZCgC5AQAAAA==.Sarnara:BAABLgAECn8qAAIFAAkJiBpHCQA5AgAFAAkJiBpHCQA5AgAAAA==.Savageclaw:BAAALgAECggJCQAAAA==.Savagehunt:BAAALgAECgEJAgABLgAECgYJFQAiAO0gAA==.Savagekegs:BAABLgAECn8VAAMiAAYJ7SD8OABmAQAiAAQJZSP8OABmAQAhAAUJQhhUPQAmAQAAAA==.Savagelight:BAAALgAECgEJAgABLgAECgYJFQAiAO0gAA==.Savagex:BAAALgAECgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAABLgAECn8kAAIDAAkJ3wPsnQAAAQADAAkJ3wPsnQAAAQAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgAECgEJAQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Senarx:BAAALgAECgIJBAAAAA==.Sereniity:BAABLgAECn8WAAQiAAcJ3SEOGwDKAQAiAAYJLiIOGwDKAQAYAAUJYRifMQAxAQAhAAIJeRvyXgCZAAABLgAECgcJGQAMAAAUAA==.',
Sh='Shamalicous:BAABLgAECn8UAAMHAAUJAgLNqQBvAAAHAAUJAgLNqQBvAAAKAAQJ+wVbgABrAAAAAA==.Shamjam:BAABLgAECn8jAAIHAAgJ+BElOwC+AQAHAAgJ+BElOwC+AQAAAA==.Shamous:BAAALgAECgUJCAAAAA==.Shampayne:BAAALgADCgYJBgABLgAFFAUJGAAMALEhAA==.Shanthe:BAAALgAECgYJEQABLgAFFAMJCAAOAPgaAA==.Sharku:BAACLgAFFH8RAAIQAAUJ9RRMUQBDAQAQAAUJ9RRMUQBDAQAuAAQKfy0AAhAACQkvIA0WANMCABAACQkvIA0WANMCAAAA.Shegothalf:BAAALgAECgQJBQAAAA==.Shãdo:BAAALgAECgYJCAAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAECgkJHgARAAwiAA==.Siinep:BAAALgAECgcJEAAAAA==.Sintan:BAAALgAECgYJBgAAAA==.',
Sk='Skey:BAAALgAECgIJAgAAAA==.Skibblé:BAABLgAECn8YAAIcAAkJCQ6vCwCAAQAcAAkJCQ6vCwCAAQAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAABLgAECn8YAAIEAAgJHhdsNQDCAQAEAAgJHhdsNQDCAQAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIZAAgJrSGCEgDrAgAZAAgJrSGCEgDrAgAAAA==.Smokeyjr:BAAALgADCgcJBwAAAA==.',
Sn='Sneakyboi:BAABLgAECn8uAAIPAAkJZRq2BABAAgAPAAkJZRq2BABAAgAAAA==.Snippin:BAAALgAECgIJAgAAAA==.',
So='Soléne:BAABLgAECn8cAAMHAAgJOh0AHgBZAgAHAAcJsB0AHgBZAgAKAAUJyRBjWADXAAABLgAFFAQJCQAXAK0PAA==.Sorden:BAAALgAECgQJBgABLgAECgkJMQAZAOQhAA==.',
Sp='Spiced:BAABLgAECn8ZAAIkAAgJSCC0DQDAAgAkAAgJSCC0DQDAAgABLgAECgkJGwAbAIggAA==.Spliff:BAAALgAECgIJAgAAAA==.',
Sq='Squirt:BAABLgAECn8aAAISAAgJvQ88GgC6AQASAAgJvQ88GgC6AQAAAA==.',
Ss='Ssks:BAAALgAFFAEJAQABLgAECgMJCwAWAAAAAA==.',
St='Stabsmcshank:BAACLgAFFH8PAAIOAAQJ/A5NHQAvAQAOAAQJ/A5NHQAvAQAuAAQKfykAAg4ACQmqFhgdABYCAA4ACQmqFhgdABYCAAAA.Starbux:BAABLgAECn8oAAQVAAcJpxFULQBsAQAVAAcJKw9ULQBsAQABAAYJvAdSTwDQAAAUAAUJEA8/WgDLAAAAAA==.Starmagic:BAAALgAECgkJBgAAAA==.Steakx:BAAALgAECgQJBwAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Suriel:BAABLgAECn8aAAINAAcJ1BKlIABLAQANAAcJ1BKlIABLAQAAAA==.Suumcuique:BAAALgAECgIJAgABLgAECgkJJQAkAGcWAA==.',
Sv='Svenya:BAABLgAECn8cAAMkAAkJ7Q2lOQAoAQAkAAgJbAulOQAoAQAEAAYJOAXRgwCuAAAAAA==.',
Sy='Syenna:BAAALgAECgEJAQAAAA==.Sygne:BAAALgAECgYJCwAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAABLgAECn8zAAIDAAkJ7RFCOwDuAQADAAkJ7RFCOwDuAQAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJCAABLgAFFAQJBgAHAKMWAA==.',
['Sï']='Sïenna:BAAALgAECgkJEwAAAA==.',
Ta='Taggy:BAABLgAECn8rAAIPAAgJaQ8ICwB/AQAPAAgJaQ8ICwB/AQABLgAECgkJMwAIABAaAA==.Taln:BAAALgAECgEJAQAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Tassandie:BAAALgAECgQJBAABLgAECgkJIAAEAOEWAA==.Tayebeh:BAAALgADCgcJDAAAAA==.',
Te='Terran:BAAALgAECgUJCwAAAA==.Texhd:BAAALgAECgYJBgABLgAFFAgJIgARADkbAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.Thansus:BAAALgAECgEJAQAAAA==.Theçølletør:BAAALgAECgMJAwAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.Tinygibbs:BAAALgAECgMJBAAAAA==.',
To='Toiletnuker:BAABLgAECn8jAAQgAAgJPg+9HQCvAQAgAAgJgQ69HQCvAQADAAYJug1AnQABAQAfAAEJRApEQAAoAAABLgAECgkJOAACANMdAA==.Tokyojoe:BAABLgAECn8hAAIZAAkJshT9OADfAQAZAAkJshT9OADfAQAAAA==.Tolsanah:BAABLgAFFH8PAAIYAAcJ9xIGEQD4AQAYAAcJ9xIGEQD4AQABLgAFFAkJOgASAPEeAA==.Torocious:BAAALgAECgYJDQAAAA==.Torrick:BAABLgAECn8yAAQGAAkJhCNzBwAwAwAGAAkJhCNzBwAwAwACAAYJBRcRNwCfAQAFAAEJwxRjQwAwAAAAAA==.Torrickgreed:BAAALgADCgYJBgABLgAECgkJMgAGAIQjAA==.Totemtot:BAABLgAECn8vAAInAAkJwgaOFwBJAQAnAAkJwgaOFwBJAQAAAA==.Toupee:BAAALgAECgUJBgAAAA==.',
Tr='Tradrivia:BAAALgAECgQJBgAAAA==.Tronly:BAAALgADCgUJBQAAAA==.Trukait:BAAALgAECgEJAQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Tw='Twinkish:BAAALgAECgEJAQAAAA==.',
Ty='Tyllivan:BAAALgADCgcJDgAAAA==.',
['Tá']='Tálise:BAAALgADCgcJBwAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCgAAAA==.',
Uf='Uffizzle:BAAALgAECgUJCwAAAA==.',
Ul='Ulf:BAABLgAECn8gAAIHAAgJbRKjOwC8AQAHAAgJbRKjOwC8AQAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Va='Valquirie:BAACLgAFFH8JAAINAAMJaBd4IwDPAAANAAMJaBd4IwDPAAAuAAQKf0IAAg0ACQk/IWAEAO4CAA0ACQk/IWAEAO4CAAAA.Valyrius:BAAALgADCggJCQABLgAECgYJBgAWAAAAAA==.Varlamor:BAABLgAECn8VAAMUAAgJlwsaMABKAQAUAAgJlwsaMABKAQABAAUJYQSIYQCPAAAAAA==.Vathraen:BAAALgAECgMJBgAAAA==.',
Ve='Velanistra:BAABLgAECn8oAAIGAAkJYg1tagCXAQAGAAkJYg1tagCXAQAAAA==.Velanya:BAAALgAECgEJAQAAAA==.Velnia:BAAALgAECgcJBwAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAABLgAECn8nAAIdAAkJFBEOGwCiAQAdAAkJFBEOGwCiAQAAAA==.Very:BAAALgAECgUJDgAAAA==.',
Vg='Vgerr:BAABLgAECn8WAAIGAAkJAgwGagCYAQAGAAkJAgwGagCYAQAAAA==.',
Vi='Viashino:BAAALgAECgUJBgABLgAECgYJEAAWAAAAAA==.Vidarus:BAAALgAFFAIJAwABLgAFFAUJEQAGAF8aAA==.Viridian:BAAALgAECgMJBgABLgAFFAMJBgAZAMIbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAABLgAECn8hAAMDAAkJYBz4LAAlAgADAAcJ/Rz4LAAlAgAfAAYJlBeAGADpAAAAAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAABLgAECn8VAAMZAAkJYg8ZqQDPAAAZAAgJaQ4ZqQDPAAAdAAIJ4xHBTgB2AAAAAA==.Vynos:BAABLgAECn8hAAIXAAgJQge2jQAfAQAXAAgJQge2jQAfAQAAAA==.Vysant:BAAALgADCgQJBgABLgAECggJIQAXAEIHAA==.',
['Vä']='Väl:BAAALgAECgQJCAAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAACLgAFFH8GAAMHAAQJoxYFMQAWAQAHAAQJoxYFMQAWAQAKAAEJRwP5WwAuAAAuAAQKfyQAAwcACQm7Eck0ANoBAAcACQm7Eck0ANoBAAoABwn2E9o5AEsBAAAA.',
Wc='Wchaos:BAAALgAECgUJBwAAAA==.',
We='Welker:BAAALgADCgQJCAABLgAFFAMJCAAMAKAQAA==.Welkerdk:BAACLgAFFH8IAAIMAAMJoBA1oADSAAAMAAMJoBA1oADSAAAuAAQKfzIAAgwACQlJIMoXALYCAAwACQlJIMoXALYCAAAA.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgAZAMIbAA==.',
Wh='Whiskeycakes:BAAALgAECgQJBQABLgAECgQJBgAWAAAAAA==.',
Wi='Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.Windeyaho:BAAALgAECggJCgAAAA==.',
Wo='Wolfman:BAABLgAECn8fAAIiAAkJXAqgKABrAQAiAAkJXAqgKABrAQAAAA==.Woökie:BAAALgADCgYJBgAAAA==.',
Xa='Xalidan:BAAALgAECgUJCgAAAA==.',
Xt='Xten:BAABLgAECn8aAAIEAAcJ0RUmOAC0AQAEAAcJ0RUmOAC0AQAAAA==.',
Ya='Yamzofsteel:BAAALgADCgMJAwAAAA==.Yath:BAAALgAECgMJAwAAAA==.',
Ye='Yeat:BAAALgAECgUJCwAAAA==.',
Yo='Yoatanius:BAAALgAECgEJAQAAAA==.Yoshinox:BAAALgAECgMJBAAAAA==.',
Yr='Yrelle:BAAALgADCggJCAABLgAECgcJFgABAJ8MAA==.',
Za='Zalazam:BAABLgAECn8iAAMKAAkJPBzxEgBUAgAKAAkJPBzxEgBUAgAHAAEJjhklwABMAAAAAA==.Zalth:BAABLgAECn8jAAIQAAkJ4Az8ZwCpAQAQAAkJ4Az8ZwCpAQAAAA==.',
Ze='Zelliph:BAAALgAECgUJDgAAAA==.Zenagdrina:BAABLgAECn8XAAMgAAgJ7AX8MgAWAQAgAAgJIQX8MgAWAQADAAIJBAY8IAE6AAAAAA==.Zenobiå:BAABLgAECn8WAAMKAAgJmA48NgBdAQAKAAgJmA48NgBdAQAHAAEJqgZq7AAgAAAAAA==.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.',
Zh='Zhaann:BAABLgAECn8WAAMBAAcJnwziPgATAQABAAYJwA7iPgATAQAVAAIJqAlbagBTAAAAAA==.Zhaida:BAAALgADCgIJAgAAAA==.',
Zo='Zokor:BAAALgADCgkJQwAAAA==.Zorach:BAAALgAECgYJDwAAAA==.',
['Zá']='Zárá:BAABLgAECn8vAAIQAAcJrxXQcgCRAQAQAAcJrxXQcgCRAQAAAA==.',
['Ðz']='Ðz:BAAALgAFFAEJAQABLgAFFAIJBQAhAEcMAA==.',
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
