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

local lookup = {'Priest-Discipline','Paladin-Holy','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Shaman-Restoration','Druid-Feral','Druid-Guardian','Shaman-Elemental','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','Unknown-Unknown','Druid-Balance','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Priest-Shadow','Warlock-Demonology','DemonHunter-Devourer','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','Mage-Fire','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Monk-Brewmaster','Warrior-Protection','Mage-Arcane','Shaman-Enhancement',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-07-19',data={Ad='Ader:BAAALgADCgkJDQAAAA==.Advîl:BAAALgAECgQJBAAAAA==.',
Ae='Aeryhnn:BAAALgAECgYJCgABLgAECgkJHwABAKkRAA==.',
Ai='Ainoskedu:BAAALgADCgIJAgAAAA==.',
Ak='Akümä:BAAALgAECgEJAgAAAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAABLgAECn8hAAICAAYJhxYdOgBiAQACAAYJhxYdOgBiAQAAAA==.Alawar:BAAALgAECgUJBQAAAA==.Albinodwarf:BAAALgAFFAEJAQAAAA==.Albinoorc:BAAALgAECgEJAgAAAA==.Alexandre:BAABLgAECn8mAAIDAAkJ/hUWMgAUAgADAAkJ/hUWMgAUAgAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAABLgAECn8aAAIEAAcJVw7eUgBEAQAEAAcJVw7eUgBEAQAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAABLgAECn8xAAQCAAkJTh1gCwDXAgACAAkJTh1gCwDXAgAFAAMJ3QOiRQBOAAAGAAEJRgcgtAEoAAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJBgAAAA==.Ansuz:BAAALgAECgEJBQAAAA==.',
Ap='Aphroditee:BAAALgAECgMJBAAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgQJBAAAAA==.',
Aq='Aquafresh:BAABLgAECn84AAIHAAkJ6R2FEgC5AgAHAAkJ6R2FEgC5AgAAAA==.',
Ar='Archspire:BAAALgADCgcJBwAAAA==.Archèrdayne:BAAALgAFFAEJAwAAAA==.Arisel:BAABLgAECn81AAMIAAkJWRo/BwBoAgAIAAkJWRo/BwBoAgAJAAUJpxAFHwCoAAAAAA==.Aristia:BAAALgAFFAEJAQABLgAFFAUJFAAKACAOAA==.Artemisiah:BAAALgAECgEJAQAAAA==.Arweni:BAABLgAECn82AAILAAgJYhnwHAAGAgALAAgJYhnwHAAGAgAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashcheeks:BAAALgAECgEJAQAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8gAAICAAgJECRDCADqAgACAAgJECRDCADqAgABLgAFFAMJCAAEADsXAA==.',
Au='Autoinvite:BAAALgADCgUJBQAAAA==.',
Av='Avlynn:BAAALgADCgMJAwABLgAFFAYJHwAHAD4MAA==.Avoidme:BAAALgADCgkJEQABLgAECgkJOAACANMdAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAABLgAECn8dAAMMAAYJWA4iEgDcAAAMAAUJtw4iEgDcAAANAAYJYgedVwCxAAABLgAECgkJOAACANMdAA==.Baridyn:BAAALgADCgMJBgAAAA==.Bariir:BAAALgAECgQJBQABLgAECgcJGQAOAAAUAA==.',
Be='Bearbacked:BAAALgAECgQJBgABLgAECgQJBwAPAAAAAA==.Bearlytankin:BAAALgADCgkJCQAAAA==.Bearscat:BAAALgADCgUJBQAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Beerus:BAAALgAECgMJAwAAAA==.Beetingu:BAAALgADCgQJBAABLgAECgkJIgAQACEgAA==.Belabites:BAAALgADCgkJCQABLgAECggJJgAGAEsLAA==.Belagrip:BAAALgAECgMJBAABLgAECggJJgAGAEsLAA==.Belashar:BAABLgAECn8mAAIGAAgJSwuBEQAjAQAGAAgJSwuBEQAjAQAAAA==.Belawar:BAAALgADCggJGgABLgAECggJJgAGAEsLAA==.Beleron:BAAALgAECgIJAgAAAA==.Belinna:BAAALgAECgkJBwAAAA==.Beytuha:BAABLgAECn8tAAIJAAkJYyXyAABdAwAJAAkJYyXyAABdAwAAAA==.',
Bi='Bigtim:BAAALgAFFAEJAQAAAA==.Bigworm:BAAALgADCgYJBgAAAA==.Billd:BAAALgAECgYJCQAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAABLgAECn8tAAMRAAkJ+B/JAQA9AgAOAAgJNB/BLwBAAgARAAkJpxvJAQA9AgAAAA==.Blackknife:BAABLgAECn8uAAMSAAgJih6PEgARAgASAAgJih6PEgARAgATAAEJGAmcKQAvAAAAAA==.Bladestorm:BAAALgAECgUJCQABLgAECgcJGQAOAAAUAA==.Blakylightz:BAACLgAFFH8KAAIFAAMJIx6PCADvAAAFAAMJIx6PCADvAAAuAAQKfx8AAwUACAnHGgQJAEYCAAUACAnHGgQJAEYCAAYABglzCXm6ABEBAAEuAAUUCQk5AAkAMh8A.Blinker:BAABLgAECn87AAIUAAkJBQ4VZQC0AQAUAAkJBQ4VZQC0AQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAcJIAAUAIIZAA==.Blueberriess:BAAALgAECgEJAgAAAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJEwABLgAFFAYJGAAEAE8IAA==.Bobbidyboo:BAACLgAFFH8YAAIEAAYJTwhGIwA/AQAEAAYJTwhGIwA/AQAuAAQKfy0AAgQACQlsFao2AM0BAAQACQlsFao2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJEAAAAA==.Boomboompowa:BAAALgADCgYJBgAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJEgAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAABLgAECn8UAAINAAcJ1BT8NAAvAQANAAcJ1BT8NAAvAQAAAA==.Brixtia:BAAALgAECgYJCgABLgAECgkJKQADAH0eAA==.Brovar:BAACLgAFFH8ZAAIGAAUJIh0mHgABAQAGAAUJIh0mHgABAQAuAAQKfyoAAwYACAm1I3UaAMoCAAYACAm1I3UaAMoCAAIABQlcCu1zAKwAAAAA.Bruiseleeroy:BAAALgAECgEJBAAAAA==.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAACLgAFFH8OAAIVAAMJ/gw9RwCsAAAVAAMJ/gw9RwCsAAAuAAQKfyIABBUACAkREW8wAHYBABUACAkREW8wAHYBABYABAnxB507AI4AABcAAQnDA31DACgAAAAA.Bubblez:BAAALgAECgUJEAAAAA==.Buddydaelf:BAABLgAECn8zAAIDAAkJ2BvkGgCEAgADAAkJ2BvkGgCEAgAAAA==.Bueskytter:BAAALgADCgEJAQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
Bw='Bwonshlongdi:BAAALgAECgcJBwAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Calithe:BAAALgAECgYJBgAAAA==.Cambey:BAAALgAECgYJDAAAAA==.Candyman:BAAALgADCgYJDgAAAA==.Caprisan:BAAALgAECgQJBAABLgAECggJHAAGAD8aAA==.Castro:BAAALgADCgQJBAAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.Ceodochatos:BAAALgAECgYJBgABLgAECgkJMQAFACQdAA==.',
Ch='Challah:BAAALgAECgEJAQAAAA==.Chals:BAACLgAFFH8cAAMYAAYJFSS9AQAiAgAYAAYJFSS9AQAiAgABAAIJsA2jPgB+AAAuAAQKfxgAAxgACQn6HCgOAHkCABgACQnyHCgOAHkCAAEAAwkVGbA5ANkAAAAA.Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Charfig:BAAALgADCgYJBgAAAA==.Chia:BAAALgAECgYJCAABLgAFFAQJBgAHAKMWAA==.Chillfang:BAACLgAFFH8HAAMOAAMJfQ1S5ACCAAAOAAIJfQ1S5ACCAAARAAEJAAATaAAAAAAuAAQKfykAAg4ACQm9HmYvAEECAA4ACQm9HmYvAEECAAAA.Chouji:BAAALgADCgYJAgAAAA==.Chune:BAAALgAECgQJEgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAABLgAECn8nAAQBAAkJqRTtAQBgAgABAAkJSxTtAQBgAgAZAAUJdhiFCQD0AAAYAAIJlwsNbgA1AAAAAA==.Clairvoyant:BAAALgAECgEJAQAAAA==.',
Co='Connor:BAABLgAECn8tAAMBAAkJChpzDQCWAgABAAkJChpzDQCWAgAYAAEJgxfzawA6AAAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgcJEQAAAA==.',
Cr='Cracken:BAAALgADCgcJCAAAAA==.Cretinboy:BAAALgAECgMJAwAAAA==.Crosshair:BAAALgAECgQJDAAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgAECgYJEwAPAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCwAAAA==.',
Da='Daciansniper:BAAALgAECgUJBgAAAA==.Dacianspirit:BAAALgADCgYJBgAAAA==.Dacianwolf:BAAALgAECggJCQAAAA==.Daemoni:BAAALgAECgYJCQAAAA==.Dagaz:BAAALgAECgEJAQAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Danïca:BAAALgAECgMJAwAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJEgAAAA==.Darkerknight:BAAALgAECgQJBAABLgAECgkJNgAUABIgAA==.Darkprincess:BAAALgAECgUJBQAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgAECgEJAQABLgAECgcJGQAOAAAUAA==.Darthbane:BAAALgAECgMJAwAAAA==.Dathguy:BAAALgAECgYJCgABLgAFFAQJGwAOAG0iAA==.Davandar:BAAALgADCgkJGgAAAA==.Daveah:BAABLgAECn80AAIHAAkJlRVbJgAoAgAHAAkJlRVbJgAoAgAAAA==.Dazarros:BAACLgAFFH8PAAIaAAMJ6RRpJQDmAAAaAAMJ6RRpJQDmAAAuAAQKfyMAAhoACQmpFL4yAA0CABoACQmpFL4yAA0CAAEuAAUUBgkeABQAehYA.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8zAAIaAAkJHhRXCQBBAQAaAAkJHhRXCQBBAQAAAA==.Deathsmoke:BAAALgAECgQJBAAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dekkaa:BAAALgAECgEJAgAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgAECgUJDgAAAA==.Demoncharge:BAAALgAECgQJBAABLgAECgkJEQAPAAAAAA==.Demonclaw:BAAALgAECgEJAgABLgAECgkJEQAPAAAAAA==.Demondrake:BAAALgAECgUJCQABLgAECgkJEQAPAAAAAA==.Demonflayer:BAAALgAECgkJEQAAAA==.Demonikat:BAAALgADCgYJDAAAAA==.Demonsmoke:BAAALgADCgkJCQAAAA==.Demonstalker:BAAALgAECgEJAQABLgAECgkJEQAPAAAAAA==.Denaeaa:BAACLgAFFH8MAAIMAAMJtQvyRgCJAAAMAAMJtQvyRgCJAAAuAAQKfxsAAgwACAkvDCJNADgBAAwACAkvDCJNADgBAAEuAAUUBgkfAAcAPgwA.Denimblue:BAAALgAECgQJBAAAAA==.Destroyerman:BAAALgADCgQJBAAAAA==.Devilzkry:BAAALgAECgcJCwAAAA==.Devistaysha:BAABLgAFFH8FAAIHAAIJ9Q3QNwBeAAAHAAIJ9Q3QNwBeAAAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgUJBQABLgAECgcJGQADAGMdAA==.',
Dh='Dharmakat:BAAALgADCgUJBQAAAA==.Dhodge:BAABLgAECn8ZAAIbAAcJGR8SLAAYAgAbAAcJGR8SLAAYAgABLgAFFAMJBgAcAFohAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn84AAICAAkJ0x0hDADLAgACAAkJ0x0hDADLAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJCQAAAA==.',
Do='Dodgehoj:BAAALgAECgMJBAABLgAFFAMJBgAcAFohAA==.Doffyy:BAAALgAECgEJAQAAAA==.Dogbreathrlz:BAAALgAECgEJAQAAAA==.Dokash:BAAALgAECgUJCQABLgAFFAEJAwAPAAAAAA==.Dotexe:BAABLgAECn8hAAITAAUJYCFBAQB0AQATAAUJYCFBAQB0AQAAAA==.Dotsy:BAACLgAFFH8iAAQdAAcJnBY4AgA1AQAeAAUJbRXeAQBSAQAdAAUJVxo4AgA1AQAaAAQJBxGBWQAUAQAuAAQKfy8ABB4ACQlNIq4PANMBAB4ABglDHK4PANMBABoABwnfHsVVAMYBAB0ABwkhInIKALgBAAAA.',
Dr='Drackarys:BAAALgAECgQJBAAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgAECgYJDQAAAA==.Drakiir:BAAALgAECgYJDQABLgAECgcJGQAOAAAUAA==.Dralkish:BAACLgAFFH8FAAIGAAMJtQdGfwC3AAAGAAMJtQdGfwC3AAAuAAQKfzgAAgYACQkuEyp0AIYBAAYACQkuEyp0AIYBAAAA.Dramore:BAABLgAECn8kAAIdAAkJzgkpDgB6AQAdAAkJzgkpDgB6AQAAAA==.Drathi:BAAALgADCgcJBwABLgAECgkJOQAGAKIjAA==.Dravas:BAABLgAECn8bAAILAAYJzg4bEQCfAAALAAYJzg4bEQCfAAAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Drezzo:BAAALgADCgMJAwAAAA==.Droxx:BAABLgAECn8VAAIOAAYJCAxgvwD/AAAOAAYJCAxgvwD/AAAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drunkash:BAAALgAECgEJAQAAAA==.Dryerbro:BAAALgAECgEJAQAAAA==.Drzark:BAABLgAECn8YAAMUAAkJHQpFDgBKAQAUAAkJHQpFDgBKAQAfAAIJrgjfFQAoAAAAAA==.',
Du='Dumpling:BAAALgADCgEJAQAAAA==.Dundunduns:BAAALgAECgYJBgAAAA==.',
Dw='Dwdog:BAABLgAECn8nAAIdAAkJrxhLBwD+AQAdAAkJrxhLBwD+AQAAAA==.',
['Dà']='Dàthguy:BAACLgAFFH8bAAIOAAQJbSLAGQB4AQAOAAQJbSLAGQB4AQAuAAQKf0cAAg4ACQnyJU0DAGsDAA4ACQnyJU0DAGsDAAAA.',
['Dæ']='Dænerÿs:BAAALgAECgMJAwAAAA==.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
['Dé']='Défault:BAACLgAFFH8YAAMOAAYJUxWwHQBbAQAOAAUJUxWwHQBbAQARAAEJAABnZwAAAAAuAAQKfy0AAw4ACQlfIh8LABUDAA4ACQlfIh8LABUDACAABAmKEqAbAPEAAAAA.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJEgAAAA==.',
Ef='Eflorescence:BAAALgAECgEJAgAAAA==.',
El='Elennie:BAAALgAECgYJDgAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elephlock:BAAALgAECgQJBQAAAA==.Elephunch:BAAALgAECgUJBQAAAA==.Elerion:BAABLgAECn8jAAMBAAkJ6hPJGgD5AQABAAkJ6hPJGgD5AQAZAAcJSQnrOAAxAQAAAA==.Elista:BAAALgADCgUJBQABLgADCgQJBAAPAAAAAA==.Elm:BAAALgAECgEJAQAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgIJAgABLgAECgQJBAAPAAAAAA==.Emmi:BAABLgAECn8/AAIOAAkJkR8GFQDJAgAOAAkJkR8GFQDJAgAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIGAAcJ/B7jLwBjAgAGAAcJ/B7jLwBjAgAAAA==.Eralis:BAAALgAECgYJBQAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilspawn:BAABLgAECn8UAAIhAAcJkgwiCADyAAAhAAcJkgwiCADyAAAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.Excalipoor:BAAALgAECgEJAQAAAA==.',
Ez='Ezekìel:BAAALgAECgEJAwABLgAECgEJAwAPAAAAAA==.',
Fa='Faelivrin:BAAALgAECgcJBQAAAA==.Faith:BAAALgADCgYJBgAAAA==.Falcor:BAACLgAFFH8GAAIVAAUJ5xFEGQDPAAAVAAUJ5xFEGQDPAAAuAAQKfx4AAxUACQkMIv4HAPkCABUACQnAIf4HAPkCABcABgldIXgRAMgBAAAA.Faloran:BAAALgAECgEJAQAAAA==.Farstad:BAAALgADCgMJAwAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgkJCQAAAA==.Fekk:BAAALgADCgIJAgABLgAECggJFAAaALkIAA==.Fenderbender:BAAALgADCgYJBgAAAA==.Feralstorm:BAAALgAECgYJCQAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feykat:BAAALgADCgUJBQAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAABLgAECn9BAAIRAAkJ9x3vCACEAgARAAkJ9x3vCACEAgAAAA==.Fifthelement:BAABLgAECn85AAIHAAkJJR8XDgDkAgAHAAkJJR8XDgDkAgAAAA==.Fiorstrasza:BAABLgAECn8YAAMWAAYJZxsYAgB0AQAWAAYJZxsYAgB0AQAXAAIJnAfjHwBTAAAAAA==.Firebunny:BAAALgADCgUJBQAAAA==.',
Fj='Fjalgeirr:BAABLgAECn85AAMhAAkJWxeoFgDSAQAhAAkJWxeoFgDSAQAiAAYJcwpGBQCeAAAAAA==.',
Fl='Fleapaw:BAAALgADCgcJBwAAAA==.Flockling:BAAALgADCgkJDwAAAA==.',
Fo='Foxymomma:BAABLgAECn88AAIYAAkJYyO6AwBOAwAYAAkJYyO6AwBOAwAAAA==.',
Fr='Frey:BAACLgAFFH8gAAMOAAYJeB4mEgC9AQAOAAYJeB4mEgC9AQARAAEJAACzLgAAAAAuAAQKfzIAAg4ACQllJbMFAEwDAA4ACQllJbMFAEwDAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8bAAMdAAkJiCBZAQDjAgAdAAcJ7iRZAQDjAgAaAAYJZxpNtgDaAAAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fugazí:BAAALgADCgUJBQAAAA==.Fulgar:BAAALgAECgQJBwAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.Furryfido:BAAALgADCggJCAABLgAECgkJQQARAPcdAA==.',
Fw='Fwenwir:BAABLgAECn8aAAQjAAYJFSCWLADKAQAjAAYJfx+WLADKAQAkAAMJvxhLPwDNAAADAAEJ+xhTGQFDAAAAAA==.',
Ga='Galatea:BAAALgAFFAEJAQAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAABLgAECn8pAAILAAkJ8A2KKwCnAQALAAkJ8A2KKwCnAQAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJGgABLgAECgkJMQACAE4dAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gidgette:BAAALgAECgYJCwAAAA==.Gilalade:BAABLgAECn8+AAIDAAkJFxzdGQCKAgADAAkJFxzdGQCKAgAAAA==.Gingee:BAAALgADCgIJAgAAAA==.',
Gl='Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8oAAIOAAgJIggOnQAwAQAOAAgJIggOnQAwAQAAAA==.',
Go='Gobann:BAAALgADCggJEAABLgAECgkJKQADAH0eAA==.Gooby:BAAALgAECgQJBAABLgAFFAgJGgACAJ8TAA==.Gooney:BAAALgAECgIJAwAAAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Greencheese:BAAALgAECgIJAgABLgAECggJGwAOABoSAA==.Grimes:BAAALgAECgEJAQABLgAECgQJBwAPAAAAAA==.Grlfriend:BAAALgAFFAEJAQAAAA==.Grodin:BAAALgAECgYJDgAAAA==.Grofiest:BAABLgAECn8kAAMZAAkJjBYSFAAuAgAZAAkJjBYSFAAuAgAYAAEJjAFWfgAYAAAAAA==.',
Gu='Guggychan:BAACLgAFFH8GAAIcAAMJWiFlIADzAAAcAAMJWiFlIADzAAAuAAQKfzkAAhwACQmGJg8BAGcDABwACQmGJg8BAGcDAAAA.',
['Gô']='Gôö:BAAALgAECgQJDAAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAINAAkJTw83KwBkAQANAAkJTw83KwBkAQAAAA==.Haelwyn:BAAALgAECgEJAQABLgAECgEJAwAPAAAAAA==.Hahine:BAAALgAECgEJAQAAAA==.Haldor:BAABLgAECn8jAAIGAAgJewyjdQCPAQAGAAgJewyjdQCPAQAAAA==.Haohmaru:BAABLgAECn8/AAIlAAkJciGuBQDlAgAlAAkJciGuBQDlAgAAAA==.',
He='Healomatic:BAAALgAECgUJBQABLgAECgcJCgAPAAAAAA==.Hecæte:BAAALgADCgYJBgAAAA==.Heella:BAAALgAECgEJAgAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgQJCAAAAA==.Hercgrimx:BAAALgAECgcJDwAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIaAAUJ+RRjjQA+AQAaAAUJ+RRjjQA+AQAAAA==.',
Hi='Him:BAABLgAECn8lAAIKAAkJqBjpEwBMAgAKAAkJqBjpEwBMAgAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Holiestgoat:BAAALgADCggJDAABLgAECgkJOAACANMdAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.Holyclunge:BAAALgAECgUJBQAAAA==.Holyshocks:BAAALgAECgEJAgAAAA==.',
Hp='Hplaysgames:BAAALgAECgUJCQAAAA==.',
Hu='Huneyhunter:BAABLgAECn8lAAIIAAkJcg5PBAALAQAIAAkJcg5PBAALAQAAAA==.Hunterer:BAAALgAECgYJBgAAAA==.',
Ic='Iceburn:BAAALgAECgEJAgAAAA==.Ichigozero:BAAALgAECgEJAQAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
In='Intern:BAACLgAFFH8MAAMBAAIJ7Q2zIABvAAABAAIJ7Q2zIABvAAAYAAIJowtcFgBYAAAuAAQKfywABAEACQmVFJYGAFwBABgACAlIFZAdANgBAAEABwmDDpYGAFwBABkAAQkAAFWgAAAAAAAA.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgAECgUJEAAAAA==.',
Iz='Iza:BAAALgADCgIJAgAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakethecake:BAAALgAECgQJBAAAAA==.Jaks:BAAALgAECgEJAwAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAABLgAECn8zAAIXAAkJfxF9BwDEAQAXAAkJfxF9BwDEAQAAAA==.January:BAAALgAECgEJAQABLgAFFAQJCQAaAK0PAA==.Javeech:BAAALgAECgQJBgAAAA==.',
Jc='Jchaotic:BAAALgAECggJDwAAAA==.',
Je='Jeezus:BAAALgADCgYJCgABLgAFFAUJKgAOAFEiAA==.Jesophocles:BAAALgAECgEJAQAAAA==.',
Jo='Jocie:BAAALgAECgEJAgAAAA==.Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwAPAAAAAA==.Jolanta:BAAALgADCgEJAQABLgAFFAUJFAAKACAOAA==.Jongsoo:BAAALgAECgcJCAAAAA==.Jovero:BAAALgAECgQJBQAAAA==.',
Ju='Junghee:BAAALgAECgEJAQAAAA==.Justicar:BAAALgAECgQJBAAAAA==.Jutas:BAABLgAECn8cAAMBAAgJdgvPLQBsAQABAAgJdgvPLQBsAQAZAAcJwAMtWQCwAAAAAA==.Juudaz:BAACLgAFFH8qAAMOAAUJUSIFGwBuAQAOAAUJhyAFGwBuAQARAAQJlh8lGwAOAQAuAAQKf1UABA4ACQlmJc8DAGQDAA4ACQlmJc8DAGQDABEABwm3IbEOACACACAAAwksC6kKAGYAAAAA.',
Jv='Jvicious:BAAALgAECgcJCgAAAA==.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAABLgAECn8+AAMCAAkJzyGCBQA6AwACAAkJzyGCBQA6AwAGAAUJMxdtnAA9AQAAAA==.Kaliista:BAAALgAECgEJAQABLgAECgkJIQAEAHwXAA==.Kallan:BAAALgAECgUJDAAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kapkywa:BAACLgAFFH8IAAIEAAMJOxf4NADZAAAEAAMJOxf4NADZAAAuAAQKfxQAAgQACAnfIe0LAAEDAAQACAnfIe0LAAEDAAAA.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.Katsumyo:BAAALgAECgMJAwAAAA==.Kazenazen:BAAALgAECgUJEAAAAA==.',
Ke='Keggz:BAAALgAECgEJAQAAAA==.Kegpoker:BAAALgAECgcJEgAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgUJCAAPAAAAAA==.',
Kh='Khaalzantro:BAAALgAECgIJAgAAAA==.',
Ki='Kilra:BAAALgAECgUJDwAAAA==.Kimbaltina:BAAALgADCgkJIQABLgAECgkJNQAIAFkaAA==.Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJEwAAAA==.Kindasmall:BAAALgAECgkJAQAAAA==.Kiyara:BAABLgAECn9HAAIDAAkJvBaiLgAiAgADAAkJvBaiLgAiAgAAAA==.Kizaki:BAAALgAECgYJDgABLgAECggJFwACAP8SAA==.',
Kn='Knownn:BAAALgAECgIJAgAAAA==.Knowoone:BAABLgAECn9TAAIEAAkJHBlrFgCUAgAEAAkJHBlrFgCUAgAAAA==.Knowwn:BAAALgAECgEJAQAAAA==.',
Ko='Komonaut:BAABLgAECn8eAAMiAAYJlA23BACzAAAiAAYJWA23BACzAAAbAAMJigiW4gByAAAAAA==.Koscihardt:BAABLgAECn8VAAIUAAcJcwZM0gDuAAAUAAcJcwZM0gDuAAAAAA==.Kouelwhip:BAAALgAECgEJAQABLgAECgcJGQAOAAAUAA==.',
Kr='Krakin:BAAALgAECgYJBgAAAA==.Krelliz:BAABLgAECn8cAAIHAAcJTRDiZgAnAQAHAAcJTRDiZgAnAQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAABLgAECn8iAAIUAAgJNAz9sAAgAQAUAAgJNAz9sAAgAQAAAA==.Kronnk:BAAALgAECgEJAQAAAA==.Krystar:BAAALgAECgUJDgAAAA==.',
Ku='Kulfig:BAAALgAECgkJEQAAAA==.Kumen:BAABLgAECn8iAAQQAAkJISD7EwAzAgAQAAgJjx37EwAzAgAIAAUJfh71FwBTAQAJAAUJUxakLgDzAAAAAA==.Kungfuwho:BAACLgAFFH8RAAMNAAQJbxBzGgD1AAANAAQJbxBzGgD1AAAMAAQJ/QNBQQCeAAAuAAQKfzYAAw0ACQlZGQwfALUBAA0ACAkpGQwfALUBAAwACAk6C1NNADgBAAAA.Kutyou:BAAALgAECgQJBAAAAA==.',
Ky='Kynlailia:BAAALgADCgQJBAAAAA==.',
['Kó']='Kóólaid:BAAALgAECgIJAgAAAA==.',
['Kû']='Kûnei:BAAALgAECgQJBwAAAA==.',
La='Laladin:BAAALgAECgMJAwAAAA==.Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lemonlime:BAAALgAFFAIJAgAAAA==.Lenaea:BAACLgAFFH8fAAMHAAYJPgykMAAfAQAHAAYJPgykMAAfAQAKAAEJMwKdOAAqAAAuAAQKfyUAAgcACQnwGKEtAAACAAcACQnwGKEtAAACAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAACLgAFFH8OAAICAAQJKg5NKQDbAAACAAQJKg5NKQDbAAAuAAQKfycAAgIACAkAFZAnAM4BAAIACAkAFZAnAM4BAAAA.Liiege:BAABLgAECn8ZAAMOAAcJABRqcwB9AQAOAAcJABRqcwB9AQARAAIJwg+GPABiAAAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQABLgAECgkJOQAHACUfAA==.Limp:BAAALgAECgEJAQAAAA==.Linlithyr:BAAALgAECgIJAgABLgAFFAMJCgARAGgXAA==.Litesuprmcst:BAAALgAECgQJBQAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJCAAAAA==.',
Lo='Lobø:BAABLgAECn8sAAIDAAkJaBnaLAApAgADAAkJaBnaLAApAgAAAA==.Loganx:BAAALgAECgUJCQABLgAECgcJCwAPAAAAAA==.Lorsie:BAAALgADCggJCAABLgAECgkJKQAGABYOAA==.Lowtierscrub:BAAALgAECgEJAQAAAA==.Loxen:BAAALgAECgEJAQAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn9NAAIOAAkJfhNQBQD4AQAOAAkJfhNQBQD4AQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgUJCAAAAA==.Lutherisch:BAAALgAECgUJBQABLgAECgUJCAAPAAAAAA==.Lux:BAAALgAECgQJBAAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgAECgQJBAAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAABLgAECn8oAAIUAAgJ6wjlmQBFAQAUAAgJ6wjlmQBFAQAAAA==.Mageairena:BAAALgAECgMJBAAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgAECgIJBQAAAA==.Magnues:BAAALgADCgQJBAAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAABLgAECn8XAAIEAAgJJB8EAwAHAgAEAAgJJB8EAwAHAgAAAA==.Manatease:BAAALgAECgEJAQAAAA==.Manatee:BAAALgAECgYJDQAAAA==.Mannan:BAAALgADCgIJAgAAAA==.Marlasinger:BAAALgAECgQJBAAAAA==.Marpesia:BAAALgAECgcJCgAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Marteris:BAAALgAECgEJAwAAAA==.Maygwyn:BAABLgAECn8sAAIUAAkJTAmdDgBFAQAUAAkJTAmdDgBFAQAAAA==.',
Me='Meanshami:BAAALgAECgEJAQAAAA==.Meatlovers:BAAALgAECgUJBgAAAA==.Mediva:BAABLgAECn8XAAIHAAUJBhhQDQAcAQAHAAUJBhhQDQAcAQAAAA==.Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgYJDwAAAA==.Megaera:BAACLgAFFH8GAAIbAAMJwhvOIwCxAAAbAAMJwhvOIwCxAAAuAAQKfx4AAxsACQnuIPMOAAcDABsACQnuIPMOAAcDACEAAQkeGBZsADoAAAAA.Melar:BAACLgAFFH8KAAMmAAIJpgRtFgBaAAAmAAIJpgRtFgBaAAALAAEJCAM9NgA0AAAuAAQKfzoAAyYACQnEDwwEAD4BAAsACAmSEK8zAHwBACYABwkaDwwEAD4BAAAA.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.Messyah:BAABLgAFFH8FAAIgAAIJ+gRjEwBnAAAgAAIJ+gRjEwBnAAAAAA==.',
Mi='Migmong:BAAALgAECgIJBQAAAA==.Mihawk:BAAALgAECgQJBwAAAA==.Milwaukee:BAAALgAECgEJAQAAAA==.Minjae:BAABLgAECn8jAAMaAAkJfhWOAwAbAgAaAAkJfhWOAwAbAgAdAAEJ/hBIPgA1AAABLgAFFAQJCQAaACcRAA==.Minseo:BAAALgAECgEJAwAAAA==.Miserain:BAABLgAECn8XAAIlAAUJfwPECwBdAAAlAAUJfwPECwBdAAAAAA==.Mistbehaving:BAAALgAECgQJBAAAAA==.',
Mo='Moondemon:BAAALgAECgUJCgAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Moozart:BAAALgADCgEJAQAAAA==.Morphumbra:BAAALgAECgUJBQAAAA==.Morrìgan:BAABLgAECn8ZAAMaAAcJ3QWOswDeAAAaAAcJ3QWOswDeAAAeAAIJqwOUYgBJAAAAAA==.Morvane:BAAALgAECgQJBAABLgAECgkJMQACAE4dAA==.Mothra:BAAALgAECgQJCQABLgAFFAQJBgAHAKMWAA==.Movack:BAABLgAECn8rAAIGAAkJpg4VZQClAQAGAAkJpg4VZQClAQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.Mozwangsung:BAAALgADCgYJBwAAAA==.',
Mu='Muncha:BAAALgAECgEJAgAAAA==.Murderface:BAABLgAECn8rAAMQAAkJ7BV3GwDvAQAQAAkJ7BV3GwDvAQAEAAcJvRl3UABNAQAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAABLgAECn8gAAIeAAkJ9gwhEQAzAQAeAAkJ9gwhEQAzAQAAAA==.Mythunran:BAABLgAECn8rAAIjAAgJJhMDDwBtAQAjAAgJJhMDDwBtAQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJEgAPAAAAAA==.Natash:BAAALgAECgEJAgAAAA==.Nau:BAAALgAECgUJBQAAAA==.Nawas:BAAALgAECgEJAgAAAA==.Nax:BAAALgAECgUJEAAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAgABLgAECgUJBwAPAAAAAA==.Nerfhammer:BAACLgAFFH8RAAIGAAUJXxpsJQBzAQAGAAUJXxpsJQBzAQAuAAQKfyoAAgYACQlLIwkcAMICAAYACQlLIwkcAMICAAAA.Nessalove:BAACLgAFFH8kAAIYAAcJ6hDoBQBhAQAYAAcJ6hDoBQBhAQAuAAQKfysAAhgACQmUHTgMAI8CABgACQmUHTgMAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8eAAQVAAkJjw2ROgBBAQAVAAcJAQ6ROgBBAQAWAAYJJxEmHwD+AAAXAAEJxANIQgArAAAAAA==.Nipao:BAABLgAECn8eAAIMAAgJGR6UAQCuAgAMAAgJGR6UAQCuAgAAAA==.Niron:BAAALgAECgUJCwAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAABLgAFFH8QAAIMAAMJPRMVOwC5AAAMAAMJPRMVOwC5AAABLgAFFAkJOwAUAAslAA==.Noriel:BAABLgAECn8VAAIUAAkJcRAGXwDCAQAUAAkJcRAGXwDCAQAAAA==.Nostradamos:BAAALgADCgYJBgAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAABLgAECn8VAAIDAAcJNREzbABpAQADAAcJNREzbABpAQAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Og='Ognyal:BAAALgAECgkJBQAAAA==.',
Oh='Ohtani:BAAALgAECgkJDgAAAA==.',
Ol='Olanali:BAAALgAECgEJAwABLgAECgEJAwAPAAAAAA==.Olectria:BAAALgADCgEJAQAAAA==.',
On='Onna:BAAALgADCgYJBwAAAA==.',
Oo='Ooblitoon:BAABLgAECn9UAAIXAAkJghO7BQD/AQAXAAkJghO7BQD/AQAAAA==.',
Op='Opali:BAAALgAECgEJAQAAAA==.',
Or='Orfantal:BAABLgAECn8hAAIDAAkJExIjSwDAAQADAAkJExIjSwDAAQAAAA==.Oridan:BAAALgAECgEJAQAAAA==.Oridon:BAAALgAECgQJDAAAAA==.',
Ou='Ouahoahoah:BAAALgAFFAEJAQAAAA==.',
Ov='Oven:BAAALgAECgUJBQABLgAFFAQJGwAOAG0iAA==.Overburned:BAAALgAECgMJAwAAAA==.Overcast:BAAALgAECgYJEAAAAA==.Overshoot:BAABLgAECn8aAAMDAAkJlgzWTwCzAQADAAkJlgzWTwCzAQAkAAIJXgRKVgBUAAAAAA==.',
Ow='Owyyn:BAAALgADCggJCQAAAA==.',
Ox='Oxen:BAAALgAECggJDAAAAA==.',
Pa='Pallanoko:BAAALgAFFAEJAQAAAA==.Pallyairena:BAAALgADCgQJBAAAAA==.Pandemix:BAAALgAECgMJAwAAAA==.Panterion:BAABLgAECn8hAAIEAAkJfBeXJQAgAgAEAAkJfBeXJQAgAgAAAA==.Papimonk:BAAALgAECgIJAgABLgAECggJFQAHAP8ZAA==.Parvarti:BAABLgAECn8gAAMeAAkJDQjDGADcAAAeAAcJBQnDGADcAAAaAAIJJgWUGAFPAAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECgkJGgAOAAYdAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Peanutxo:BAAALgADCgEJAQAAAA==.Persimmoñ:BAABLgAECn9CAAMGAAkJrhGRDQBTAQAGAAkJrhGRDQBTAQAFAAMJCgwMCwB1AAAAAA==.Petthemonk:BAAALgAECgEJAgAAAA==.',
Ph='Phaelissia:BAAALgAECgYJDwAAAA==.Philljr:BAAALgADCgMJAwAAAA==.',
Pi='Pinero:BAAALgADCgYJCQAAAA==.',
Pl='Plaugus:BAAALgAECgUJEwAAAA==.',
Po='Polkadott:BAAALgADCggJCAABLgAECgkJIgAQACEgAA==.Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgcJEQAAAA==.Prost:BAABLgAECn8mAAIUAAkJrCCmBgDlAQAUAAkJrCCmBgDlAQAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Ps='Psylocke:BAAALgAFFAEJAQAAAA==.',
Pu='Puppybreath:BAAALgAECgEJAQAAAA==.Purdy:BAAALgAECgkJAgAAAA==.',
Py='Pyroblast:BAACLgAFFH8gAAMUAAcJghm5PQB2AQAUAAYJBxq5PQB2AQAnAAEJ6Bb+AwBXAAAuAAQKfzwAAxQACQleITcSAO0CABQACQmWIDcSAO0CACcAAwkGI34HADUBAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Raedon:BAAALgAECgYJCgAAAA==.Ralie:BAAALgAECgEJAQAAAA==.Ravage:BAAALgAECgUJBwAAAA==.',
Re='Relaceara:BAABLgAECn8WAAIGAAkJswVbqQApAQAGAAkJswVbqQApAQAAAA==.Reladin:BAABLgAECn8/AAIFAAkJpwqwGgBDAQAFAAkJpwqwGgBDAQAAAA==.Relanna:BAABLgAECn8WAAIOAAYJjAfh6wDFAAAOAAYJjAfh6wDFAAAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCggJIwAAAA==.Rendstein:BAABLgAECn8jAAIRAAkJhhjIEQDxAQARAAkJhhjIEQDxAQAAAA==.Renzr:BAACLgAFFH8ZAAMOAAQJ9hygHgBVAQAOAAQJ9hygHgBVAQARAAEJwRIIIABHAAAuAAQKf0wAAw4ACQl6JTUWAMICAA4ACQnjJDUWAMICABEACAklI4cHAKICAAAA.Reqquuiiem:BAAALgADCgUJCAAAAA==.Respcct:BAAALgADCgkJGgABLgAECgkJOAACANMdAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAABLgAECn8ZAAIEAAkJ1hPRBwAbAQAEAAkJ1hPRBwAbAQAAAA==.Rowin:BAABLgAECn8XAAMEAAkJuQh0ZgABAQAEAAkJuQh0ZgABAQAQAAMJzQfmbABwAAAAAA==.Royal:BAAALgAECgEJAQAAAA==.',
Ru='Rupy:BAAALgAECgEJAQAAAA==.Rustedroots:BAABLgAECn81AAMEAAkJQhgVGwBtAgAEAAkJQhgVGwBtAgAIAAUJNxUeBAAWAQAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Sailley:BAAALgAECgUJEQAAAA==.Saltgrizzny:BAAALgAECgcJDQAAAA==.Sapphyre:BAAALgAECgEJAgAAAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAABLgAECn8eAAIjAAkJfRQVCwC5AQAjAAkJfRQVCwC5AQAAAA==.Sarnara:BAABLgAECn8xAAIFAAkJJB13CQA4AgAFAAkJJB13CQA4AgAAAA==.Savageclaw:BAAALgAECggJCQAAAA==.Savageclaws:BAAALgAECgEJAQABLgAFFAEJBAAPAAAAAA==.Savagehunt:BAAALgAFFAEJAQABLgAFFAEJBAAPAAAAAA==.Savagekegs:BAABLgAECn8VAAMlAAYJ7SD8OABmAQAlAAQJZSP8OABmAQANAAUJQhhUPQAmAQABLgAFFAEJBAAPAAAAAA==.Savagelight:BAAALgAFFAEJBAAAAA==.Savagex:BAAALgAECgEJAQAAAA==.Sazayaki:BAAALgADCgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAABLgAECn8rAAIDAAkJVQSTJQCaAAADAAkJVQSTJQCaAAAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgAECgEJAQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Senarx:BAAALgAECgIJBAAAAA==.Sereniity:BAABLgAECn8WAAQlAAcJ3SFVGwDKAQAlAAYJLiJVGwDKAQAMAAUJYRifMQAxAQANAAIJeRteYACZAAABLgAECgcJGQAOAAAUAA==.',
Sh='Shadowjack:BAAALgAECgEJAgABLgAECgEJAwAPAAAAAA==.Shakastraza:BAAALgAECgEJAQAAAA==.Shamalicous:BAABLgAECn8UAAMHAAUJAgLirABvAAAHAAUJAgLirABvAAAKAAQJ+wXvggBqAAAAAA==.Shamjam:BAABLgAECn8jAAIHAAgJ+BEwPAC+AQAHAAgJ+BEwPAC+AQAAAA==.Shamous:BAAALgAECgUJCAAAAA==.Shampayne:BAAALgADCgYJBgABLgAFFAUJKgAOAFEiAA==.Shanthe:BAAALgAECgYJEQABLgAFFAUJDQASAOYXAA==.Sharku:BAACLgAFFH8eAAIUAAYJehYKIABKAQAUAAYJehYKIABKAQAuAAQKfy4AAhQACQkvIJYWANICABQACQkvIJYWANICAAAA.Shegothalf:BAAALgAECgYJCgAAAA==.Shortwide:BAAALgADCgIJAgAAAA==.Shãdo:BAAALgAECgYJCAAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAFFAUJBgAVAOcRAA==.Siinep:BAAALgAECgcJEAAAAA==.Sintan:BAAALgAECgYJBgAAAA==.Sistersledge:BAAALgADCgkJCgAAAA==.',
Sk='Skey:BAAALgAECgIJAgAAAA==.Skibblé:BAABLgAECn8aAAIeAAkJCw8ADAB/AQAeAAkJCw8ADAB/AQAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAABLgAECn8ZAAIEAAkJXxdpKAAOAgAEAAkJXxdpKAAOAgAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIbAAgJrSGCEgDrAgAbAAgJrSGCEgDrAgAAAA==.Smokeofsteel:BAAALgAECgkJDgAAAA==.Smokeyjr:BAAALgADCgcJBwAAAA==.',
Sn='Sneakyboi:BAABLgAECn8uAAITAAkJZRq/BABBAgATAAkJZRq/BABBAgAAAA==.Snippin:BAAALgAECgIJAgAAAA==.',
So='Soléne:BAABLgAECn8iAAMHAAgJOh2gHgBZAgAHAAcJsB2gHgBZAgAKAAUJxBUAWgDWAAABLgAFFAQJCQAaAK0PAA==.Sorden:BAAALgAECgQJBgABLgAFFAIJAgAPAAAAAA==.',
Sp='Spiced:BAABLgAECn8ZAAIQAAgJSCC0DQDAAgAQAAgJSCC0DQDAAgABLgAECgkJGwAdAIggAA==.Spliff:BAAALgAECgIJAgAAAA==.',
Sq='Squirt:BAABLgAECn8aAAIWAAgJvQ88GgC6AQAWAAgJvQ88GgC6AQAAAA==.',
Ss='Ssks:BAAALgAFFAEJAQABLgAECgMJDAAPAAAAAA==.',
St='Stabsmcshank:BAACLgAFFH8ZAAISAAUJkxP3GwA7AQASAAUJkxP3GwA7AQAuAAQKfzwAAhIACQlJGsQCAJ4BABIACQlJGsQCAJ4BAAAA.Starbux:BAACLgAFFH8NAAIBAAIJkwhcIgBlAAABAAIJkwhcIgBlAAAuAAQKfyoABAEACAmBEGUuAGgBAAEACAlVDmUuAGgBABkABgm8B8hQAM4AABgABQkQDz9aAMsAAAAA.Starmagic:BAAALgAECgkJBgAAAA==.Steakx:BAAALgAECgQJCAAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Sunmae:BAAALgAECgUJCwABLgAECgkJNQAIAFkaAA==.Suriel:BAABLgAECn8oAAIRAAkJLROSAgDjAQARAAkJLROSAgDjAQAAAA==.Suumcuique:BAAALgAECgIJAgABLgAECgkJKwAQAOwVAA==.',
Sv='Svenya:BAABLgAECn8iAAMQAAkJ4hJiCwDCAAAQAAgJ1BBiCwDCAAAEAAYJWgkmEAB4AAAAAA==.',
Sy='Syenna:BAAALgAECgEJAQAAAA==.Sygne:BAAALgAECgYJEwAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAABLgAECn81AAIDAAkJgRKPPADuAQADAAkJgRKPPADuAQAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJCAABLgAFFAQJBgAHAKMWAA==.',
['Sï']='Sïenna:BAABLgAECn8UAAIOAAkJvBQeQwD5AQAOAAkJvBQeQwD5AQAAAA==.',
Ta='Tacituss:BAAALgAECgYJBgAAAA==.Taggy:BAABLgAECn8rAAITAAgJaQ8tCwB/AQATAAgJaQ8tCwB/AQABLgAECgkJNQAIAFkaAA==.Taln:BAAALgAECgEJBQAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Taraah:BAAALgADCgIJAgABLgAECgkJHwABAKkRAA==.Tassandie:BAAALgAECgYJCQABLgAECgkJIQAEAHwXAA==.Tayebeh:BAAALgAECgUJCAAAAA==.',
Te='Tektoniik:BAAALgAECgEJAQABLgAECgcJGQAOAAAUAA==.Texhd:BAAALgAECgYJBgABLgAFFAkJKwAVAHgbAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.Thansus:BAAALgAECgEJAQAAAA==.Theçølletør:BAAALgAECgMJAwAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.Tinygibbs:BAAALgAECgMJBAAAAA==.Tionie:BAAALgAECgcJCAAAAA==.',
To='Toiletnuker:BAABLgAECn8lAAQkAAkJBw9FHgCqAQAkAAkJYg5FHgCqAQADAAYJug1LoAABAQAjAAEJRApEQQAoAAABLgAECgkJOAACANMdAA==.Tokyojoe:BAABLgAECn8jAAIbAAkJ5hSrOQDgAQAbAAkJ5hSrOQDgAQAAAA==.Tolsanah:BAABLgAFFH8TAAIMAAcJ9xJsEgD3AQAMAAcJ9xJsEgD3AQABLgAFFAkJPAAWAPEeAA==.Torocious:BAAALgAECgYJDQAAAA==.Torrick:BAABLgAECn85AAQGAAkJoiPSBwAuAwAGAAkJhCPSBwAuAwAFAAYJySABAgDVAQACAAYJBRcRNwCfAQAAAA==.Torrickdemon:BAAALgAECgkJEgABLgAECgkJOQAGAKIjAA==.Torrickgreed:BAAALgADCgYJBgABLgAECgkJOQAGAKIjAA==.Totemtot:BAABLgAECn86AAIoAAkJkQiRBgDHAAAoAAkJkQiRBgDHAAAAAA==.Toupee:BAAALgAECgUJBgAAAA==.',
Tr='Tradrivia:BAAALgAECgcJCQAAAA==.Tronly:BAAALgADCgUJBQAAAA==.Trukait:BAAALgAECgEJAQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Tw='Twinkish:BAAALgAECgEJAQAAAA==.',
Ty='Tyllivan:BAAALgAECgMJBQAAAA==.',
['Tá']='Tálise:BAAALgAECgUJBgAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCgAAAA==.',
Uf='Uffizzle:BAABLgAECn8UAAIaAAgJuQi6DgDnAAAaAAgJuQi6DgDnAAAAAA==.',
Ul='Ulf:BAABLgAECn8nAAIHAAgJMBnOHQBfAgAHAAgJMBnOHQBfAgAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Uu='Uurgeorn:BAEALgADCgEJAQAAAA==.',
Va='Valquirie:BAACLgAFFH8KAAIRAAMJaBeVJADKAAARAAMJaBeVJADKAAAuAAQKf0QAAhEACQk/IX0EAOsCABEACQk/IX0EAOsCAAAA.Valyrius:BAAALgADCggJCQABLgAECgYJBgAPAAAAAA==.Varlamor:BAABLgAECn8VAAMYAAgJlwvvMABJAQAYAAgJlwvvMABJAQAZAAUJYQTvYwCLAAAAAA==.Varolokiir:BAAALgAECgEJAgABLgAECgcJGQAOAAAUAA==.Vathraen:BAAALgAECgYJDAAAAA==.',
Ve='Velanistra:BAABLgAECn8pAAIGAAkJFg45bQCUAQAGAAkJFg45bQCUAQAAAA==.Velanya:BAAALgAECgIJAwAAAA==.Velnia:BAAALgAECgcJBwAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAABLgAECn8tAAIhAAkJnBH1GwCeAQAhAAkJnBH1GwCeAQAAAA==.Very:BAAALgAECgUJDgAAAA==.',
Vg='Vgerr:BAABLgAECn8WAAIGAAkJAgyWawCXAQAGAAkJAgyWawCXAQAAAA==.',
Vi='Viashino:BAAALgAECgUJBgABLgAECgYJEAAPAAAAAA==.Vidarus:BAAALgAFFAIJAwABLgAFFAUJEQAGAF8aAA==.Vintage:BAAALgAECgEJAQAAAA==.Viridian:BAAALgAECgMJBgABLgAFFAMJBgAbAMIbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAABLgAECn8pAAMDAAkJfR43LgAkAgADAAcJbh83LgAkAgAjAAYJlBfmGADpAAAAAA==.Vorron:BAAALgADCgEJAQABLgAFFAMJCAAEADsXAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAACLgAFFH8FAAMhAAIJ1BGtEQCCAAAhAAIJ1BGtEQCCAAAbAAEJpgWApQA1AAAuAAQKfxUAAxsACQliD3yrAM8AABsACAlpDnyrAM8AACEAAgnjEVFQAHYAAAAA.Vynos:BAABLgAECn8hAAIaAAgJQgfYjwAbAQAaAAgJQgfYjwAbAQAAAA==.Vysant:BAAALgADCgQJBgABLgAECggJIQAaAEIHAA==.',
['Vä']='Väl:BAAALgAECgQJCAAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAACLgAFFH8GAAMHAAQJoxYgMwAVAQAHAAQJoxYgMwAVAQAKAAEJRwN1XwAuAAAuAAQKfyYAAwcACQkLE7E1ANoBAAcACQkLE7E1ANoBAAoABwn2E7U6AEsBAAAA.',
Wc='Wchaos:BAAALgAECgUJBwAAAA==.',
We='Welker:BAAALgADCgQJCAABLgAFFAMJCAAOAKAQAA==.Welkerdk:BAACLgAFFH8IAAIOAAMJoBCIpQDPAAAOAAMJoBCIpQDPAAAuAAQKfzIAAg4ACQlJIG8YALQCAA4ACQlJIG8YALQCAAAA.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgAbAMIbAA==.',
Wh='Whiskeycakes:BAAALgAECgQJBwAAAA==.Whispyre:BAAALgAECgEJAwAAAA==.',
Wi='Wiglet:BAAALgADCgEJAQAAAA==.Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.Windeyaho:BAAALgAECggJCgAAAA==.',
Wo='Wolfman:BAABLgAECn8jAAIlAAkJlgshJQCEAQAlAAkJlgshJQCEAQAAAA==.Woökie:BAAALgADCgYJBgAAAA==.',
Xa='Xalidan:BAAALgAFFAIJAgAAAA==.',
Xt='Xten:BAABLgAECn8iAAIEAAkJUhW6BACUAQAEAAkJUhW6BACUAQAAAA==.',
Ya='Yamedvedko:BAAALgAECgcJBwAAAA==.Yamzofsteel:BAAALgAECgEJAQAAAA==.Yath:BAAALgAECgMJAwAAAA==.',
Ye='Yeat:BAAALgAECgUJCwAAAA==.',
Yo='Yoatanius:BAAALgAECgEJAQAAAA==.Yoshinox:BAAALgAECgMJBAAAAA==.',
Yr='Yrelle:BAAALgAECgMJAwABLgAECgkJHwABAKkRAA==.',
Za='Zalazam:BAABLgAECn8mAAMKAAkJOx1HEwBTAgAKAAkJOx1HEwBTAgAHAAEJjhmvwwBMAAAAAA==.Zalth:BAABLgAECn8lAAIUAAkJ0g2WaQCpAQAUAAkJ0g2WaQCpAQAAAA==.',
Ze='Zelliph:BAAALgAECgUJDgAAAA==.Zenagdrina:BAABLgAECn8eAAMkAAkJpAiZAwBFAQAkAAkJhgiZAwBFAQADAAIJBAahJgE6AAAAAA==.Zenobiå:BAACLgAFFH8HAAMKAAIJEQYgJQBlAAAKAAIJEQYgJQBlAAAHAAIJtQR8QgBHAAAuAAQKfxsAAwoACAmkEjYIABYBAAoACAmkEjYIABYBAAcAAQmqBgrxACAAAAAA.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.Zeypher:BAAALgADCggJDAAAAA==.',
Zh='Zhaann:BAABLgAECn8fAAMBAAkJqRFrCQAXAQABAAYJgQ5rCQAXAQAZAAcJjQ7hPwARAQAAAA==.Zhaida:BAAALgADCgIJAgAAAA==.',
Zi='Zinarra:BAAALgADCgQJBAAAAA==.',
Zo='Zokor:BAAALgAECgUJCwAAAA==.Zorach:BAAALgAECgYJEQAAAA==.',
['Zá']='Zárá:BAABLgAECn89AAIUAAkJUhnBCgCCAQAUAAkJUhnBCgCCAQAAAA==.',
['Ån']='Ånéyé:BAAALgAECgIJAgAAAA==.',
['Ðz']='Ðz:BAAALgAFFAEJAQABLgAFFAcJFAAQAFwSAA==.',
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
