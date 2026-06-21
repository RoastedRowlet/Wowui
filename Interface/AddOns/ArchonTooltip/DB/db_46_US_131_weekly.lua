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

local lookup = {'Priest-Shadow','Paladin-Holy','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Shaman-Restoration','Druid-Feral','Druid-Guardian','Shaman-Elemental','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Priest-Discipline','Unknown-Unknown','Warlock-Demonology','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Warrior-Protection','Mage-Arcane','Shaman-Enhancement',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Ader:BAAALgADCgkJDQAAAA==.Advîl:BAAALgAECgQJBAAAAA==.',
Ae='Aeryhnn:BAAALgAECgQJBAABLgAECgcJFgABAJ8MAA==.',
Ai='Ainoskedu:BAAALgADCgIJAgAAAA==.',
Ak='Akümä:BAAALgAECgEJAQAAAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAABLgAECn8hAAICAAYJhxYeOgBiAQACAAYJhxYeOgBiAQAAAA==.Albinodwarf:BAAALgAECgQJCAAAAA==.Albinoorc:BAAALgAECgEJAgAAAA==.Alexandre:BAABLgAECn8mAAIDAAkJ/hUZMgAUAgADAAkJ/hUZMgAUAgAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAABLgAECn8aAAIEAAcJVw7iUgBEAQAEAAcJVw7iUgBEAQAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAABLgAECn8xAAQCAAkJTh1gCwDXAgACAAkJTh1gCwDXAgAFAAMJ3QOiRQBOAAAGAAEJRgcetAEoAAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJBgAAAA==.Ansuz:BAAALgAECgEJAgAAAA==.',
Ap='Aphroditee:BAAALgAECgIJAwAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgQJAwAAAA==.',
Aq='Aquafresh:BAABLgAECn84AAIHAAkJ6R2FEgC5AgAHAAkJ6R2FEgC5AgAAAA==.',
Ar='Archèrdayne:BAAALgAFFAEJAwAAAA==.Arisel:BAABLgAECn8zAAMIAAkJEBo+BwBoAgAIAAkJEBo+BwBoAgAJAAUJpxAFHwCoAAAAAA==.Aristia:BAAALgAECgUJDQABLgAFFAQJCwAKAJMLAA==.Artemisiah:BAAALgAECgEJAQAAAA==.Arweni:BAABLgAECn82AAILAAgJYhntHAAGAgALAAgJYhntHAAGAgAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashcheeks:BAAALgAECgEJAQAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8gAAICAAgJECRDCADqAgACAAgJECRDCADqAgABLgAFFAMJBgAEADsXAA==.',
Av='Avlynn:BAAALgADCgMJAwABLgAFFAUJGwAHAD4MAA==.Avoidme:BAAALgADCgkJEQABLgAECgkJOAACANMdAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAAALgAECgYJEgABLgAECgkJOAACANMdAA==.Baridyn:BAAALgADCgMJBgAAAA==.Bariir:BAAALgAECgQJBQABLgAECgcJGQAMAAAUAA==.',
Be='Bearbacked:BAAALgAECgQJBgAAAA==.Bearlytankin:BAAALgADCgkJCQAAAA==.Bearscat:BAAALgADCgUJBQAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Beerus:BAAALgAECgMJAwAAAA==.Belagrip:BAAALgAECgMJBAABLgAECgcJGgAGAF4HAA==.Belashar:BAABLgAECn8aAAIGAAcJXgd8zgD1AAAGAAcJXgd8zgD1AAAAAA==.Belawar:BAAALgADCggJGgABLgAECgcJGgAGAF4HAA==.Beleron:BAAALgAECgIJAgAAAA==.Belinna:BAAALgAECgkJBwAAAA==.Beytuha:BAABLgAECn8tAAIJAAkJYyXyAABdAwAJAAkJYyXyAABdAwAAAA==.',
Bi='Bigtim:BAAALgAFFAEJAQAAAA==.Bigworm:BAAALgADCgYJBgAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAABLgAECn8mAAMMAAkJbx/ALwBAAgAMAAgJNB/ALwBAAgANAAUJjBdiAgCIAAAAAA==.Blackknife:BAABLgAECn8uAAMOAAgJih6OEgARAgAOAAgJih6OEgARAgAPAAEJGAmbKQAvAAAAAA==.Bladestorm:BAAALgAECgUJCQABLgAECgcJGQAMAAAUAA==.Blakylightz:BAACLgAFFH8IAAIFAAMJZRuOCADvAAAFAAMJZRuOCADvAAAuAAQKfx8AAwUACAnHGgQJAEYCAAUACAnHGgQJAEYCAAYABglzCXm6ABEBAAEuAAUUCAkxAAkAFyEA.Blinker:BAABLgAECn87AAIQAAkJBQ7iAwAGAQAQAAkJBQ7iAwAGAQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAYJFQAQALcYAA==.Blueberriess:BAAALgAECgEJAgAAAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJEwABLgAFFAYJGAAEAE8IAA==.Bobbidyboo:BAACLgAFFH8YAAIEAAYJTwhNIwA/AQAEAAYJTwhNIwA/AQAuAAQKfy0AAgQACQlsFao2AM0BAAQACQlsFao2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJDgAAAA==.Boomboompowa:BAAALgADCgYJBgAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJEgAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAAALgAECgYJEwAAAA==.Brixtia:BAAALgAECgQJBQABLgAECgkJIgADAGAcAA==.Brovar:BAACLgAFFH8UAAIGAAUJIh1bPwAsAQAGAAUJIh1bPwAsAQAuAAQKfyoAAwYACAm1I3UaAMoCAAYACAm1I3UaAMoCAAIABQlcCu1zAKwAAAAA.Bruiseleeroy:BAAALgAECgEJAQAAAA==.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAACLgAFFH8OAAIRAAMJ/gw0RwCsAAARAAMJ/gw0RwCsAAAuAAQKfyIABBEACAkREW0wAHYBABEACAkREW0wAHYBABIABAnxB507AI4AABMAAQnDA31DACgAAAAA.Bubblez:BAAALgAECgUJDwAAAA==.Buddydaelf:BAABLgAECn8wAAIDAAkJXBvlGgCEAgADAAkJXBvlGgCEAgAAAA==.Bueskytter:BAAALgADCgEJAQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
Bw='Bwonshlongdi:BAAALgADCgcJBwAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Calithe:BAAALgAECgYJBgAAAA==.Cambey:BAAALgAECgMJBQAAAA==.Candyman:BAAALgADCgYJDgAAAA==.Caprisan:BAAALgAECgQJBAABLgAECggJHAAGAD8aAA==.Castro:BAAALgADCgQJBAAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.Ceodochatos:BAAALgAECgYJBgABLgAECgkJKwAFAIgaAA==.',
Ch='Chals:BAACLgAFFH8WAAMUAAUJIiSXAAB4AQAUAAUJIiSXAAB4AQAVAAIJsA2oPgB+AAAuAAQKfxgAAxQACQn6HCgOAHkCABQACQnyHCgOAHkCABUAAwkVGbA5ANkAAAEuAAUUBQkWABQAIiQA.Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Charfig:BAAALgADCgYJBgAAAA==.Chia:BAAALgAECgYJBgABLgAFFAQJBgAHAKMWAA==.Chillfang:BAACLgAFFH8HAAMMAAMJfQ1U5ACCAAAMAAIJfQ1U5ACCAAANAAEJAAAaaAAAAAAuAAQKfykAAgwACQm9HmUvAEECAAwACQm9HmUvAEECAAAA.Chouji:BAAALgADCgYJAgAAAA==.Chune:BAAALgAECgQJEgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAABLgAECn8bAAQVAAkJFRFqAAAPAgAVAAkJvBBqAAAPAgABAAUJkw1MUQDMAAAUAAEJjBAJbgA1AAAAAA==.Clairvoyant:BAAALgAECgEJAQAAAA==.',
Co='Connor:BAABLgAECn8tAAMVAAkJChpzDQCWAgAVAAkJChpzDQCWAgAUAAEJgxfuawA6AAAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgcJEQAAAA==.',
Cr='Cracken:BAAALgADCgcJCAAAAA==.Cretinboy:BAAALgAECgMJAwAAAA==.Crosshair:BAAALgAECgQJDAAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgAECgYJCwAWAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCQAAAA==.',
Da='Daciansniper:BAAALgAECgUJBgAAAA==.Dacianspirit:BAAALgADCgYJBgAAAA==.Dacianwolf:BAAALgAECggJCAAAAA==.Daemoni:BAAALgAECgYJCQAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJEgAAAA==.Darkerknight:BAAALgAECgQJBAABLgAECgkJNgAQABIgAA==.Darkprincess:BAAALgAECgUJBQAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgAECgEJAQABLgAECgcJGQAMAAAUAA==.Darthbane:BAAALgAECgMJAwAAAA==.Dathguy:BAAALgAECgYJCgABLgAFFAQJFAAMAD8iAA==.Davandar:BAAALgADCgkJGgAAAA==.Daveah:BAABLgAECn8yAAIHAAkJGhRZJgAoAgAHAAkJGhRZJgAoAgAAAA==.Dazarros:BAACLgAFFH8HAAIXAAIJqQ9fCwCUAAAXAAIJqQ9fCwCUAAAuAAQKfyMAAhcACQmpFL0yAA4CABcACQmpFL0yAA4CAAAA.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8tAAIXAAkJGBFjRgDHAQAXAAkJGBFjRgDHAQAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dekkaa:BAAALgAECgEJAQAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgAECgUJDgAAAA==.Demoncharge:BAAALgAECgQJBAABLgAECgkJEQAWAAAAAA==.Demonclaw:BAAALgAECgEJAQABLgAECgkJEQAWAAAAAA==.Demondrake:BAAALgAECgUJCQABLgAECgkJEQAWAAAAAA==.Demonflayer:BAAALgAECgkJEQAAAA==.Demonikat:BAAALgADCgYJDAAAAA==.Demonsmoke:BAAALgADCgkJCQAAAA==.Demonstalker:BAAALgAECgEJAQABLgAECgkJEQAWAAAAAA==.Denaeaa:BAACLgAFFH8MAAIYAAMJtQvtRgCJAAAYAAMJtQvtRgCJAAAuAAQKfxsAAhgACAkvDCFNADgBABgACAkvDCFNADgBAAEuAAUUBQkbAAcAPgwA.Destroyerman:BAAALgADCgQJBAAAAA==.Devilzkry:BAAALgAECgcJCwAAAA==.Devistaysha:BAAALgAFFAEJAgAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgUJBQABLgAECgcJGQADAGMdAA==.',
Dh='Dharmakat:BAAALgADCgUJBQAAAA==.Dhodge:BAABLgAECn8ZAAIZAAcJGR8ULAAYAgAZAAcJGR8ULAAYAgABLgAFFAMJBgAaAFohAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn84AAICAAkJ0x0hDADLAgACAAkJ0x0hDADLAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJCQAAAA==.',
Do='Dodgehoj:BAAALgAECgMJBAABLgAFFAMJBgAaAFohAA==.Doffyy:BAAALgAECgEJAQAAAA==.Dogbreathrlz:BAAALgAECgEJAQAAAA==.Dokash:BAAALgAECgUJCQABLgAFFAEJAwAWAAAAAA==.Dotexe:BAABLgAECn8cAAIPAAUJLiFwDgA+AQAPAAUJLiFwDgA+AQAAAA==.Dotsy:BAACLgAFFH8XAAQbAAYJLxiVBABBAQAbAAUJvxmVBABBAQAXAAQJ5wyYWQAUAQAcAAEJFCD4JABMAAAuAAQKfy8ABBwACQlNIq4PANMBABwABglDHK4PANMBABcABwnfHsVVAMYBABsABwkhInEKALgBAAAA.',
Dr='Drackarys:BAAALgADCggJFAAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgAECgUJCgAAAA==.Drakiir:BAAALgAECgYJDQABLgAECgcJGQAMAAAUAA==.Dralkish:BAACLgAFFH8FAAIGAAMJtQdOfwC3AAAGAAMJtQdOfwC3AAAuAAQKfzgAAgYACQkuEyx0AIYBAAYACQkuEyx0AIYBAAAA.Dramore:BAABLgAECn8kAAIbAAkJzgkpDgB6AQAbAAkJzgkpDgB6AQAAAA==.Drathi:BAAALgADCgcJBwABLgAECgkJMgAGAIQjAA==.Dravas:BAAALgAECgUJEwAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Drezzo:BAAALgADCgMJAwAAAA==.Droxx:BAABLgAECn8VAAIMAAYJCAxavwD/AAAMAAYJCAxavwD/AAAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drunkash:BAAALgAECgEJAQAAAA==.Dryerbro:BAAALgAECgEJAQAAAA==.Drzark:BAAALgAECgcJDgAAAA==.',
Du='Dumpling:BAAALgADCgEJAQAAAA==.Dundunduns:BAAALgAECgYJBgAAAA==.',
Dw='Dwdog:BAABLgAECn8nAAIbAAkJrxhLBwD+AQAbAAkJrxhLBwD+AQAAAA==.',
['Dà']='Dàthguy:BAACLgAFFH8UAAIMAAQJPyJhBwAEAQAMAAQJPyJhBwAEAQAuAAQKf0EAAgwACQnyJU0DAGsDAAwACQnyJU0DAGsDAAAA.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
['Dé']='Défault:BAACLgAFFH8UAAMMAAUJLxSCCADvAAAMAAQJLxSCCADvAAANAAEJAABtZwAAAAAuAAQKfycAAwwACQk4IR8LABUDAAwACQk4IR8LABUDAB0ABAmKEqAbAPEAAAAA.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJEgAAAA==.',
El='Elennie:BAAALgAECgYJDAAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elephlock:BAAALgAECgQJBQAAAA==.Elephunch:BAAALgAECgUJBQAAAA==.Elerion:BAABLgAECn8jAAMVAAkJ6hPIGgD5AQAVAAkJ6hPIGgD5AQABAAcJSQnoOAAxAQAAAA==.Elista:BAAALgADCgUJBQABLgADCgQJBAAWAAAAAA==.Elm:BAAALgADCgUJBgAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgIJAgABLgAECgQJBAAWAAAAAA==.Emmi:BAABLgAECn85AAIMAAkJKx8EFQDJAgAMAAkJKx8EFQDJAgAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIGAAcJ/B7jLwBjAgAGAAcJ/B7jLwBjAgAAAA==.Eralis:BAAALgAECgYJBQAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilspawn:BAAALgAECgUJBQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.',
Fa='Faelivrin:BAAALgAECgcJBQAAAA==.Faith:BAAALgADCgYJBgAAAA==.Falcor:BAABLgAECn8eAAMRAAkJDCL+BwD5AgARAAkJwCH+BwD5AgATAAYJXSF4EQDIAQAAAA==.Faloran:BAAALgAECgEJAQAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgkJCQAAAA==.Fekk:BAAALgADCgIJAgABLgAECgUJCwAWAAAAAA==.Fenderbender:BAAALgADCgYJBgAAAA==.Feralstorm:BAAALgAECgYJCQAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feykat:BAAALgADCgUJBQAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAABLgAECn83AAINAAkJLhzyCACEAgANAAkJLhzyCACEAgAAAA==.Fifthelement:BAABLgAECn8wAAIHAAkJ0h0XDgDkAgAHAAkJ0h0XDgDkAgAAAA==.Firebunny:BAAALgADCgUJBQAAAA==.',
Fj='Fjalgeirr:BAABLgAECn8wAAMeAAkJZxWpFgDSAQAeAAkJZxWpFgDSAQAfAAYJ6gfTIgCIAAAAAA==.',
Fl='Fleapaw:BAAALgADCgcJBwAAAA==.Flockling:BAAALgADCgYJBgAAAA==.',
Fo='Foxymomma:BAABLgAECn82AAIUAAkJoCG7AwBOAwAUAAkJoCG7AwBOAwAAAA==.',
Fr='Frey:BAACLgAFFH8VAAIMAAUJ4iJTSwBcAQAMAAUJ4iJTSwBcAQAuAAQKfzIAAgwACQllJbMFAEwDAAwACQllJbMFAEwDAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8bAAMbAAkJiCBZAQDjAgAbAAcJ7iRZAQDjAgAXAAYJZxpQtgDaAAAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fulgar:BAAALgAECgQJBgAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.Furryfido:BAAALgADCggJCAABLgAECgkJNwANAC4cAA==.',
Fw='Fwenwir:BAABLgAECn8aAAQgAAYJFSCWLADKAQAgAAYJfx+WLADKAQAhAAMJvxhKPwDNAAADAAEJ+xhQGQFDAAAAAA==.',
Ga='Galatea:BAAALgAFFAEJAQAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAABLgAECn8pAAILAAkJ8A2KKwCnAQALAAkJ8A2KKwCnAQAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJGgABLgAECgkJMQACAE4dAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gidgette:BAAALgAECgYJCwAAAA==.Gilalade:BAABLgAECn84AAIDAAkJpxvgGQCKAgADAAkJpxvgGQCKAgAAAA==.Gingee:BAAALgADCgIJAgAAAA==.',
Gl='Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8oAAIMAAgJIggMnQAwAQAMAAgJIggMnQAwAQAAAA==.',
Go='Gobann:BAAALgADCggJEAABLgAECgkJIgADAGAcAA==.Gooby:BAAALgAECgQJBAABLgAFFAYJGAACAO0UAA==.Gooney:BAAALgAECgIJAwAAAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Greencheese:BAAALgAECgIJAgABLgAECggJGwAMABoSAA==.Grimes:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.Grlfriend:BAAALgAECgYJDwAAAA==.Grodin:BAAALgAECgQJBgAAAA==.Grofiest:BAABLgAECn8jAAMBAAkJjBYUFAAuAgABAAkJjBYUFAAuAgAUAAEJjAFRfgAYAAAAAA==.',
Gu='Guggychan:BAACLgAFFH8GAAIaAAMJWiFrIADzAAAaAAMJWiFrIADzAAAuAAQKfzkAAhoACQmGJg8BAGcDABoACQmGJg8BAGcDAAAA.',
['Gô']='Gôö:BAAALgAECgQJDAAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAIiAAkJTw82KwBkAQAiAAkJTw82KwBkAQAAAA==.Haelwyn:BAAALgAECgEJAQABLgAECgEJAwAWAAAAAA==.Hahine:BAAALgAECgEJAQAAAA==.Haldor:BAABLgAECn8jAAIGAAgJewyjdQCPAQAGAAgJewyjdQCPAQAAAA==.Haohmaru:BAABLgAECn85AAIjAAkJyiCuBQDlAgAjAAkJyiCuBQDlAgAAAA==.',
He='Healomatic:BAAALgAECgUJBQABLgAECgcJCgAWAAAAAA==.Hecæte:BAAALgADCgYJBgAAAA==.Heella:BAAALgAECgEJAQAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgQJCAAAAA==.Hercgrimx:BAAALgAECgcJDwAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIXAAUJ+RRjjQA+AQAXAAUJ+RRjjQA+AQAAAA==.',
Hi='Him:BAABLgAECn8lAAIKAAkJqBjqEwBMAgAKAAkJqBjqEwBMAgAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.Holyshocks:BAAALgAECgEJAgAAAA==.',
Hp='Hplaysgames:BAAALgAECgUJBwAAAA==.',
Hu='Huneyhunter:BAABLgAECn8dAAIIAAcJZwsOHwAQAQAIAAcJZwsOHwAQAQAAAA==.',
Ic='Ichigozero:BAAALgADCgkJCQAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
In='Intern:BAABLgAECn8lAAQUAAgJYRWOHQDYAQAUAAgJSBWOHQDYAQAVAAQJDQqrXwB/AAABAAEJAABNoAAAAAAAAA==.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgAECgUJBQAAAA==.',
Iz='Iza:BAAALgADCgIJAgAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakethecake:BAAALgAECgQJBAAAAA==.Jaks:BAAALgAECgEJAwAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAABLgAECn8tAAITAAkJKRB9BwDEAQATAAkJKRB9BwDEAQAAAA==.Javeech:BAAALgAECgQJBgAAAA==.',
Jc='Jchaotic:BAAALgAECggJDwAAAA==.',
Je='Jeezus:BAAALgADCgYJBgABLgAFFAUJGgAMALEhAA==.',
Jo='Jocie:BAAALgAECgEJAQAAAA==.Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwAWAAAAAA==.Jongsoo:BAAALgAECgcJCAAAAA==.Jovero:BAAALgAECgQJBQAAAA==.',
Ju='Junghee:BAAALgADCgIJAgAAAA==.Jutas:BAABLgAECn8cAAMVAAgJdgvPLQBsAQAVAAgJdgvPLQBsAQABAAcJwAMoWQCwAAAAAA==.Juudaz:BAACLgAFFH8aAAMMAAUJsSFmRQBpAQAMAAQJ6B9mRQBpAQANAAQJlh8rGwANAQAuAAQKf00ABAwACQlmJc8DAGQDAAwACQlmJc8DAGQDAA0ABwm3IbIOACACAB0AAgn8CF04ADsAAAAA.',
Jv='Jvicious:BAAALgAECgcJCgAAAA==.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAABLgAECn85AAMCAAkJSCGDBQA6AwACAAkJSCGDBQA6AwAGAAUJTRVvnAA9AQAAAA==.Kaliista:BAAALgAECgEJAQABLgAECgkJIAAEAOEWAA==.Kallan:BAAALgAECgUJDAAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kapkywa:BAACLgAFFH8GAAIEAAMJOxf+NADZAAAEAAMJOxf+NADZAAAuAAQKfxQAAgQACAnfIe0LAAEDAAQACAnfIe0LAAEDAAAA.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.Katsumyo:BAAALgAECgMJAwAAAA==.',
Ke='Keggz:BAAALgAECgEJAQAAAA==.Kegpoker:BAAALgAECgcJEgAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgUJCAAWAAAAAA==.',
Kh='Khaalzantro:BAAALgAECgIJAgAAAA==.',
Ki='Kilra:BAAALgAECgUJCQAAAA==.Kimbaltina:BAAALgADCgkJGQABLgAECgkJMwAIABAaAA==.Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJEwAAAA==.Kindasmall:BAAALgAECgkJAQAAAA==.Kiyara:BAABLgAECn9HAAIDAAkJvBajLgAiAgADAAkJvBajLgAiAgAAAA==.Kizaki:BAAALgADCgkJDgABLgAECggJFwACAP8SAA==.',
Kn='Knowoone:BAABLgAECn9TAAIEAAkJHBlrFgCUAgAEAAkJHBlrFgCUAgAAAA==.Knowwn:BAAALgADCgEJAQAAAA==.',
Ko='Komonaut:BAABLgAECn8UAAMfAAYJ2woEHAC7AAAfAAYJJgoEHAC7AAAZAAMJigiX4gByAAAAAA==.Koscihardt:BAABLgAECn8VAAIQAAcJcwZG0gDuAAAQAAcJcwZG0gDuAAAAAA==.Kouelwhip:BAAALgAECgEJAQABLgAECgcJGQAMAAAUAA==.',
Kr='Krakin:BAAALgAECgEJAQAAAA==.Krelliz:BAABLgAECn8cAAIHAAcJTRDZZgAnAQAHAAcJTRDZZgAnAQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAABLgAECn8fAAIQAAcJhgr2sAAgAQAQAAcJhgr2sAAgAQAAAA==.Kronnk:BAAALgAECgEJAQAAAA==.Krystar:BAAALgAECgUJDgAAAA==.',
Ku='Kulfig:BAAALgAECgkJEQAAAA==.Kumen:BAABLgAECn8iAAQkAAkJISD6EwAzAgAkAAgJjx36EwAzAgAIAAUJfh7zFwBTAQAJAAUJUxajLgDzAAAAAA==.Kungfuwho:BAACLgAFFH8RAAMiAAQJbxB0GgD1AAAiAAQJbxB0GgD1AAAYAAQJ/QM9QQCeAAAuAAQKfzYAAyIACQlZGQwfALUBACIACAkpGQwfALUBABgACAk6C1FNADgBAAAA.Kutyou:BAAALgADCgkJJQAAAA==.',
Ky='Kynlailia:BAAALgADCgQJBAAAAA==.',
['Kû']='Kûnei:BAAALgAECgQJBwAAAA==.',
La='Laladin:BAAALgAECgMJAwAAAA==.Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lenaea:BAACLgAFFH8bAAIHAAUJPgy8MAAeAQAHAAUJPgy8MAAeAQAuAAQKfyUAAgcACQnwGJ4tAAACAAcACQnwGJ4tAAACAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAACLgAFFH8OAAICAAQJKg5QKQDbAAACAAQJKg5QKQDbAAAuAAQKfycAAgIACAkAFY4nAM4BAAIACAkAFY4nAM4BAAAA.Liiege:BAABLgAECn8ZAAMMAAcJABRncwB9AQAMAAcJABRncwB9AQANAAIJwg+GPABiAAAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Litesuprmcst:BAAALgAECgQJBAAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJCAAAAA==.',
Lo='Lobø:BAABLgAECn8nAAIDAAkJRxjbLAApAgADAAkJRxjbLAApAgAAAA==.Loganx:BAAALgAECgUJBwABLgAECgcJCwAWAAAAAA==.Lorsie:BAAALgADCggJCAABLgAECgkJKAAGAGINAA==.Loxen:BAAALgAECgEJAQAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn8/AAIMAAkJUQsYZACfAQAMAAkJUQsYZACfAQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgUJCAAAAA==.Lutherisch:BAAALgAECgUJBQABLgAECgUJCAAWAAAAAA==.Lux:BAAALgAECgQJBAAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgAECgQJBAAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAABLgAECn8oAAIQAAgJ6wjjmQBFAQAQAAgJ6wjjmQBFAQAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgAECgIJBQAAAA==.Magnues:BAAALgADCgQJBAAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAABLgAECn8UAAIEAAcJ8BwNLAD5AQAEAAcJ8BwNLAD5AQAAAA==.Manatease:BAAALgAECgEJAQAAAA==.Manatee:BAAALgAECgYJDQAAAA==.Mannan:BAAALgADCgIJAgAAAA==.Marlasinger:BAAALgAECgQJBAAAAA==.Marpesia:BAAALgAECgcJCgAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Marteris:BAAALgAECgEJAQAAAA==.Maygwyn:BAABLgAECn8jAAIQAAgJAwe9pQAxAQAQAAgJAwe9pQAxAQAAAA==.',
Me='Mediva:BAAALgAECgUJDQAAAA==.Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgYJDwAAAA==.Megaera:BAACLgAFFH8GAAIZAAMJwhvOIwCxAAAZAAMJwhvOIwCxAAAuAAQKfx4AAxkACQnuIPMOAAcDABkACQnuIPMOAAcDAB4AAQkeGBZsADoAAAAA.Melar:BAABLgAECn8qAAMLAAgJFBCuMwB8AQALAAgJFBCuMwB8AQAlAAEJWAC+UQARAAAAAA==.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.Messyah:BAAALgAFFAEJAQAAAA==.',
Mi='Migmong:BAAALgAECgIJBQAAAA==.Mihawk:BAAALgAECgQJBwAAAA==.Milwaukee:BAAALgAECgEJAQAAAA==.Minjae:BAABLgAECn8YAAMXAAYJ9BYHcQBYAQAXAAYJTRYHcQBYAQAbAAEJ/hBJPgA1AAABLgAFFAQJCQAXACcRAA==.Minseo:BAAALgAECgEJAwAAAA==.Miserain:BAAALgAECgUJDQAAAA==.Mistbehaving:BAAALgAECgQJBAAAAA==.',
Mo='Moondemon:BAAALgADCgEJAQAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Moozart:BAAALgADCgEJAQAAAA==.Morphumbra:BAAALgAECgEJAQAAAA==.Morrìgan:BAABLgAECn8ZAAMXAAcJ3QWPswDeAAAXAAcJ3QWPswDeAAAcAAIJqwOUYgBJAAAAAA==.Mothra:BAAALgAECgQJCQABLgAFFAQJBgAHAKMWAA==.Movack:BAABLgAECn8rAAIGAAkJpg4WZQClAQAGAAkJpg4WZQClAQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.Mozwangsung:BAAALgADCgYJBwAAAA==.',
Mu='Muncha:BAAALgAECgEJAgAAAA==.Murderface:BAABLgAECn8qAAMkAAkJ7BV2GwDvAQAkAAkJ7BV2GwDvAQAEAAcJpBZ6UABNAQAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAABLgAECn8bAAIcAAkJgQohEQAzAQAcAAkJgQohEQAzAQAAAA==.Mythunran:BAABLgAECn8rAAIgAAgJJhMCDwBtAQAgAAgJJhMCDwBtAQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJEgAWAAAAAA==.Natash:BAAALgAECgEJAgAAAA==.Nau:BAAALgAECgUJBQAAAA==.Nawas:BAAALgAECgEJAgAAAA==.Nax:BAAALgAECgQJBQAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAgABLgAECgUJBwAWAAAAAA==.Nerfhammer:BAACLgAFFH8RAAIGAAUJXxqAJQBzAQAGAAUJXxqAJQBzAQAuAAQKfyoAAgYACQlLIwkcAMICAAYACQlLIwkcAMICAAAA.Nessalove:BAACLgAFFH8ZAAIUAAYJxg+4DQBwAQAUAAYJxg+4DQBwAQAuAAQKfysAAhQACQmUHTgMAI8CABQACQmUHTgMAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8eAAQRAAkJjw2OOgBBAQARAAcJAQ6OOgBBAQASAAYJJxElHwD+AAATAAEJxANIQgArAAAAAA==.Nipao:BAABLgAECn8bAAIYAAgJBRvfAAC7AQAYAAgJBRvfAAC7AQAAAA==.Niron:BAAALgAECgUJBwAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAABLgAFFH8OAAIYAAMJPRMTOwC5AAAYAAMJPRMTOwC5AAABLgAFFAgJMgAQAFIkAA==.Noriel:BAABLgAECn8UAAIQAAkJlw8IXwDCAQAQAAkJlw8IXwDCAQAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAABLgAECn8UAAIDAAcJNRE4bABpAQADAAcJNRE4bABpAQAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Og='Ognyal:BAAALgAECgkJBQAAAA==.',
Oh='Ohtani:BAAALgAECgkJDgAAAA==.',
Ol='Olanali:BAAALgAECgEJAwABLgAECgEJAwAWAAAAAA==.Olectria:BAAALgADCgEJAQAAAA==.',
On='Onna:BAAALgADCgIJAgAAAA==.',
Oo='Ooblitoon:BAABLgAECn9QAAITAAkJghO7BQD/AQATAAkJghO7BQD/AQAAAA==.',
Op='Opali:BAAALgAECgEJAQAAAA==.',
Or='Orfantal:BAABLgAECn8hAAIDAAkJExIjSwDAAQADAAkJExIjSwDAAQAAAA==.Oridan:BAAALgAECgEJAQAAAA==.Oridon:BAAALgAECgQJCQAAAA==.',
Ou='Ouahoahoah:BAAALgAFFAEJAQAAAA==.',
Ov='Oven:BAAALgAECgUJBQABLgAFFAQJFAAMAD8iAA==.Overcast:BAAALgAECgYJEAAAAA==.Overshoot:BAABLgAECn8aAAMDAAkJlgzXTwCzAQADAAkJlgzXTwCzAQAhAAIJXgRIVgBUAAAAAA==.',
Ow='Owyyn:BAAALgADCggJCAAAAA==.',
Ox='Oxen:BAAALgAECgYJBwAAAA==.',
Pa='Pallyairena:BAAALgADCgQJBAAAAA==.Panterion:BAABLgAECn8gAAIEAAkJ4RaZJQAgAgAEAAkJ4RaZJQAgAgAAAA==.Parvarti:BAABLgAECn8gAAMcAAkJDQjAGADcAAAcAAcJBQnAGADcAAAXAAIJJgWTGAFPAAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECgkJGQAMAAYdAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Persimmoñ:BAABLgAECn81AAIGAAkJRxB7XwCyAQAGAAkJRxB7XwCyAQAAAA==.Petthemonk:BAAALgAECgEJAQAAAA==.',
Ph='Phaelissia:BAAALgAECgYJDwAAAA==.Philljr:BAAALgADCgMJAwAAAA==.',
Pi='Pinero:BAAALgADCgYJCQAAAA==.',
Pl='Plaugus:BAAALgAECgUJDQAAAA==.',
Po='Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgcJEQAAAA==.Prost:BAABLgAECn8gAAIQAAkJlxxiRQALAgAQAAkJlxxiRQALAgAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Pu='Puppybreath:BAAALgAECgEJAQAAAA==.Purdy:BAAALgAECgkJAgAAAA==.',
Py='Pyroblast:BAACLgAFFH8VAAIQAAYJtxjZPQB2AQAQAAYJtxjZPQB2AQAuAAQKfzwAAxAACQleITsSAO0CABAACQmWIDsSAO0CACYAAwkGI34HADUBAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Raedon:BAAALgAECgEJAQAAAA==.Ravage:BAAALgAECgUJBwAAAA==.',
Re='Relaceara:BAABLgAECn8WAAIGAAkJswVXqQApAQAGAAkJswVXqQApAQAAAA==.Reladin:BAABLgAECn85AAIFAAkJegqwGgBDAQAFAAkJegqwGgBDAQAAAA==.Relanna:BAABLgAECn8WAAIMAAYJjAfY6wDFAAAMAAYJjAfY6wDFAAAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCggJIwAAAA==.Rendstein:BAABLgAECn8jAAINAAkJhhjHEQDxAQANAAkJhhjHEQDxAQAAAA==.Renzr:BAACLgAFFH8MAAIMAAQJnxuVSABiAQAMAAQJnxuVSABiAQAuAAQKf0wAAwwACQl6JTQWAMICAAwACQnjJDQWAMICAA0ACAklI4oHAKICAAAA.Reqquuiiem:BAAALgADCgUJCAAAAA==.Respcct:BAAALgADCgkJGgABLgAECgkJOAACANMdAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAABLgAECn8UAAIEAAkJMQ/KRQB5AQAEAAkJMQ/KRQB5AQAAAA==.Rowin:BAABLgAECn8XAAMEAAkJuQg7AwB6AAAEAAkJuQg7AwB6AAAkAAMJzQfkbABwAAAAAA==.Royal:BAAALgAECgEJAQAAAA==.',
Ru='Rustedroots:BAABLgAECn8zAAMEAAkJPRcVGwBtAgAEAAkJPRcVGwBtAgAIAAUJNxWmAAAcAQAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Sailley:BAAALgAECgQJCgAAAA==.Saltgrizzny:BAAALgAECgcJDQAAAA==.Sapphyre:BAAALgAECgEJAgAAAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAABLgAECn8eAAIgAAkJfRQVCwC5AQAgAAkJfRQVCwC5AQAAAA==.Sarnara:BAABLgAECn8rAAIFAAkJiBp3CQA4AgAFAAkJiBp3CQA4AgAAAA==.Savageclaw:BAAALgAECggJCQAAAA==.Savagehunt:BAAALgAECgEJAgABLgAECgYJFQAjAO0gAA==.Savagekegs:BAABLgAECn8VAAMjAAYJ7SD8OABmAQAjAAQJZSP8OABmAQAiAAUJQhhUPQAmAQAAAA==.Savagex:BAAALgAECgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAABLgAECn8lAAIDAAkJ3wO3oAAAAQADAAkJ3wO3oAAAAQAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgAECgEJAQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Senarx:BAAALgAECgIJBAAAAA==.Sereniity:BAABLgAECn8WAAQjAAcJ3SFTGwDKAQAjAAYJLiJTGwDKAQAYAAUJYRifMQAxAQAiAAIJeRtfYACZAAABLgAECgcJGQAMAAAUAA==.',
Sh='Shakastraza:BAAALgAECgEJAQAAAA==.Shamalicous:BAABLgAECn8UAAMHAAUJAgLdrABvAAAHAAUJAgLdrABvAAAKAAQJ+wXxggBqAAAAAA==.Shamjam:BAABLgAECn8jAAIHAAgJ+BEuPAC+AQAHAAgJ+BEuPAC+AQAAAA==.Shamous:BAAALgAECgUJCAAAAA==.Shampayne:BAAALgADCgYJBgABLgAFFAUJGgAMALEhAA==.Shanthe:BAAALgAECgYJEQAAAA==.Sharku:BAACLgAFFH8UAAIQAAUJvhZ6CQDgAAAQAAUJvhZ6CQDgAAAuAAQKfy0AAhAACQkvIJoWANICABAACQkvIJoWANICAAAA.Shegothalf:BAAALgAECgQJBQAAAA==.Shortwide:BAAALgADCgIJAgAAAA==.Shãdo:BAAALgAECgYJCAAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAECgkJHgARAAwiAA==.Siinep:BAAALgAECgcJEAAAAA==.Sintan:BAAALgAECgYJBgAAAA==.Sistersledge:BAAALgADCgEJAQAAAA==.',
Sk='Skey:BAAALgAECgIJAgAAAA==.Skibblé:BAABLgAECn8YAAIcAAkJCQ4ADAB/AQAcAAkJCQ4ADAB/AQAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAABLgAECn8ZAAIEAAkJXxdrKAAOAgAEAAkJXxdrKAAOAgAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIZAAgJrSGCEgDrAgAZAAgJrSGCEgDrAgAAAA==.Smokeyjr:BAAALgADCgcJBwAAAA==.',
Sn='Sneakyboi:BAABLgAECn8uAAIPAAkJZRq+BABBAgAPAAkJZRq+BABBAgAAAA==.Snippin:BAAALgAECgIJAgAAAA==.',
So='Soléne:BAABLgAECn8gAAMHAAgJOh2fHgBZAgAHAAcJsB2fHgBZAgAKAAUJyRD9WQDWAAABLgAFFAQJCQAXAK0PAA==.Sorden:BAAALgAECgQJBgABLgAECgkJMQAZAOQhAA==.',
Sp='Spiced:BAABLgAECn8ZAAIkAAgJSCC0DQDAAgAkAAgJSCC0DQDAAgABLgAECgkJGwAbAIggAA==.Spliff:BAAALgAECgIJAgAAAA==.',
Sq='Squirt:BAABLgAECn8aAAISAAgJvQ88GgC6AQASAAgJvQ88GgC6AQAAAA==.',
Ss='Ssks:BAAALgAFFAEJAQABLgAECgMJCwAWAAAAAA==.',
St='Stabsmcshank:BAACLgAFFH8TAAIOAAQJXxH8GwA7AQAOAAQJXxH8GwA7AQAuAAQKfzQAAg4ACQkwGbIAAGUBAA4ACQkwGbIAAGUBAAAA.Starbux:BAACLgAFFH8FAAIVAAIJGgTzQwBsAAAVAAIJGgTzQwBsAAAuAAQKfygABBUABwmnEWQuAGgBABUABwkrD2QuAGgBAAEABgm8B8JQAM4AABQABQkQDz9aAMsAAAAA.Starmagic:BAAALgAECgkJBgAAAA==.Steakx:BAAALgAECgQJBwAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Suriel:BAABLgAECn8aAAINAAcJ1BIxIQBJAQANAAcJ1BIxIQBJAQAAAA==.Suumcuique:BAAALgAECgIJAgABLgAECgkJKgAkAOwVAA==.',
Sv='Svenya:BAABLgAECn8dAAMkAAkJ7Q1LOwAkAQAkAAgJbAtLOwAkAQAEAAYJ2gbohACuAAAAAA==.',
Sy='Syenna:BAAALgAECgEJAQAAAA==.Sygne:BAAALgAECgYJCwAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAABLgAECn8zAAIDAAkJ7RGRPADuAQADAAkJ7RGRPADuAQAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJCAABLgAFFAQJBgAHAKMWAA==.',
['Sï']='Sïenna:BAABLgAECn8UAAIMAAkJvBQaQwD5AQAMAAkJvBQaQwD5AQAAAA==.',
Ta='Taggy:BAABLgAECn8rAAIPAAgJaQ8uCwB/AQAPAAgJaQ8uCwB/AQABLgAECgkJMwAIABAaAA==.Taln:BAAALgAECgEJAgAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Tassandie:BAAALgAECgQJBAABLgAECgkJIAAEAOEWAA==.Tayebeh:BAAALgADCgcJDAAAAA==.',
Te='Terran:BAAALgAECgUJCwAAAA==.Texhd:BAAALgAECgYJBgABLgAFFAgJIgARADkbAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.Thansus:BAAALgAECgEJAQAAAA==.Theçølletør:BAAALgAECgMJAwAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.Tinygibbs:BAAALgAECgMJBAAAAA==.Tionie:BAAALgADCgIJAgAAAA==.',
To='Toiletnuker:BAABLgAECn8jAAQhAAgJPg9FHgCqAQAhAAgJgQ5FHgCqAQADAAYJug1KoAABAQAgAAEJRApHQQAoAAABLgAECgkJOAACANMdAA==.Tokyojoe:BAABLgAECn8hAAIZAAkJshSoOQDgAQAZAAkJshSoOQDgAQAAAA==.Tolsanah:BAABLgAFFH8PAAIYAAcJ9xJtEgD3AQAYAAcJ9xJtEgD3AQABLgAFFAkJOgASAPEeAA==.Torocious:BAAALgAECgYJDQAAAA==.Torrick:BAABLgAECn8yAAQGAAkJhCPRBwAuAwAGAAkJhCPRBwAuAwACAAYJBRcRNwCfAQAFAAEJwxRjQwAwAAAAAA==.Torrickgreed:BAAALgADCgYJBgABLgAECgkJMgAGAIQjAA==.Totemtot:BAABLgAECn80AAInAAkJ4QblFwBKAQAnAAkJ4QblFwBKAQAAAA==.Toupee:BAAALgAECgUJBgAAAA==.',
Tr='Tradrivia:BAAALgAECgcJCQAAAA==.Tronly:BAAALgADCgUJBQAAAA==.Trukait:BAAALgAECgEJAQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Tw='Twinkish:BAAALgAECgEJAQAAAA==.',
Ty='Tyllivan:BAAALgADCgcJDgAAAA==.',
['Tá']='Tálise:BAAALgADCggJDwAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCgAAAA==.',
Uf='Uffizzle:BAAALgAECgUJCwAAAA==.',
Ul='Ulf:BAABLgAECn8mAAIHAAgJMBnNHQBfAgAHAAgJMBnNHQBfAgAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Va='Valquirie:BAACLgAFFH8JAAINAAMJaBedJADKAAANAAMJaBedJADKAAAuAAQKf0QAAg0ACQk/IX8EAOsCAA0ACQk/IX8EAOsCAAAA.Valyrius:BAAALgADCggJCQABLgAECgYJBgAWAAAAAA==.Varlamor:BAABLgAECn8VAAMUAAgJlwvrMABJAQAUAAgJlwvrMABJAQABAAUJYQTkYwCLAAAAAA==.Varolokiir:BAAALgAECgEJAgABLgAECgcJGQAMAAAUAA==.Vathraen:BAAALgAECgMJBgAAAA==.',
Ve='Velanistra:BAABLgAECn8oAAIGAAkJYg09bQCUAQAGAAkJYg09bQCUAQAAAA==.Velanya:BAAALgAECgIJAgAAAA==.Velnia:BAAALgAECgcJBwAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAABLgAECn8oAAIeAAkJFBH2GwCeAQAeAAkJFBH2GwCeAQAAAA==.Very:BAAALgAECgUJDgAAAA==.',
Vg='Vgerr:BAABLgAECn8WAAIGAAkJAgyYawCXAQAGAAkJAgyYawCXAQAAAA==.',
Vi='Viashino:BAAALgAECgUJBgABLgAECgYJEAAWAAAAAA==.Vidarus:BAAALgAFFAIJAwABLgAFFAUJEQAGAF8aAA==.Viridian:BAAALgAECgMJBgABLgAFFAMJBgAZAMIbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAABLgAECn8iAAMDAAkJYBw5LgAkAgADAAcJ/Rw5LgAkAgAgAAYJlBfkGADpAAAAAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAABLgAECn8VAAMZAAkJYg96qwDPAAAZAAgJaQ56qwDPAAAeAAIJ4xFOUAB2AAAAAA==.Vynos:BAABLgAECn8hAAIXAAgJQgfTjwAbAQAXAAgJQgfTjwAbAQAAAA==.Vysant:BAAALgADCgQJBgABLgAECggJIQAXAEIHAA==.',
['Vä']='Väl:BAAALgAECgQJCAAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAACLgAFFH8GAAMHAAQJoxYbMwAVAQAHAAQJoxYbMwAVAQAKAAEJRwN2XwAuAAAuAAQKfyQAAwcACQm7Ea01ANoBAAcACQm7Ea01ANoBAAoABwn2E7E6AEsBAAAA.',
Wc='Wchaos:BAAALgAECgUJBwAAAA==.',
We='Welker:BAAALgADCgQJCAABLgAFFAMJCAAMAKAQAA==.Welkerdk:BAACLgAFFH8IAAIMAAMJoBCMpQDPAAAMAAMJoBCMpQDPAAAuAAQKfzIAAgwACQlJIG4YALQCAAwACQlJIG4YALQCAAAA.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgAZAMIbAA==.',
Wh='Whiskeycakes:BAAALgAECgQJBQABLgAECgQJBgAWAAAAAA==.',
Wi='Wiglet:BAAALgADCgEJAQAAAA==.Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.Windeyaho:BAAALgAECggJCgAAAA==.',
Wo='Wolfman:BAABLgAECn8jAAIjAAkJlgseJQCEAQAjAAkJlgseJQCEAQAAAA==.Woökie:BAAALgADCgYJBgAAAA==.',
Xa='Xalidan:BAAALgAECgUJCgAAAA==.',
Xt='Xten:BAABLgAECn8aAAIEAAcJ0RWFOAC0AQAEAAcJ0RWFOAC0AQAAAA==.',
Ya='Yamedvedko:BAAALgAECgcJBwAAAA==.Yamzofsteel:BAAALgADCgMJAwAAAA==.Yath:BAAALgAECgMJAwAAAA==.',
Ye='Yeat:BAAALgAECgUJCwAAAA==.',
Yo='Yoatanius:BAAALgAECgEJAQAAAA==.Yoshinox:BAAALgAECgMJBAAAAA==.',
Yr='Yrelle:BAAALgADCgkJEQABLgAECgcJFgABAJ8MAA==.',
Za='Zalazam:BAABLgAECn8iAAMKAAkJPBxIEwBTAgAKAAkJPBxIEwBTAgAHAAEJjhmpwwBMAAAAAA==.Zalth:BAABLgAECn8jAAIQAAkJ4AyUaQCpAQAQAAkJ4AyUaQCpAQAAAA==.',
Ze='Zelliph:BAAALgAECgUJDgAAAA==.Zenagdrina:BAABLgAECn8YAAMhAAgJ7AW9MwASAQAhAAgJIQW9MwASAQADAAIJBAadJgE6AAAAAA==.Zenobiå:BAABLgAECn8WAAMKAAgJmA4HNwBdAQAKAAgJmA4HNwBdAQAHAAEJqgYK8QAgAAAAAA==.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.',
Zh='Zhaann:BAABLgAECn8WAAMBAAcJnwzbPwARAQABAAYJwA7bPwARAQAVAAIJqAl8bQBQAAAAAA==.Zhaida:BAAALgADCgIJAgAAAA==.',
Zo='Zokor:BAAALgADCgkJQwAAAA==.Zorach:BAAALgAECgYJDwAAAA==.',
['Zá']='Zárá:BAABLgAECn82AAIQAAkJQheiNABGAgAQAAkJQheiNABGAgAAAA==.',
['Ðz']='Ðz:BAAALgAFFAEJAQABLgAFFAMJCQAJALQMAA==.',
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
