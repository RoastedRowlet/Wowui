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

local lookup = {'Priest-Shadow','Paladin-Holy','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Shaman-Restoration','Druid-Feral','Druid-Guardian','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','Unknown-Unknown','Druid-Balance','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Priest-Discipline','Warlock-Demonology','DemonHunter-Devourer','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','Mage-Fire','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Monk-Brewmaster','Shaman-Elemental','Warrior-Protection','Mage-Arcane','Shaman-Enhancement',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-07-12',data={Ad='Ader:BAAALgADCgkJDQAAAA==.Advîl:BAAALgAECgQJBAAAAA==.',
Ae='Aeryhnn:BAAALgAECgYJCgABLgAECgkJGgABAHoLAA==.',
Ai='Ainoskedu:BAAALgADCgIJAgAAAA==.',
Ak='Akümä:BAAALgAECgEJAgAAAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAABLgAECn8hAAICAAYJhxYdOgBiAQACAAYJhxYdOgBiAQAAAA==.Alawar:BAAALgAECgUJBQAAAA==.Albinodwarf:BAAALgAFFAEJAQAAAA==.Albinoorc:BAAALgAECgEJAgAAAA==.Alexandre:BAABLgAECn8mAAIDAAkJ/hUWMgAUAgADAAkJ/hUWMgAUAgAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAABLgAECn8aAAIEAAcJVw7eUgBEAQAEAAcJVw7eUgBEAQAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAABLgAECn8xAAQCAAkJTh1gCwDXAgACAAkJTh1gCwDXAgAFAAMJ3QOiRQBOAAAGAAEJRgcgtAEoAAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJBgAAAA==.Ansuz:BAAALgAECgEJBQAAAA==.',
Ap='Aphroditee:BAAALgAECgMJBAAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgQJAwAAAA==.',
Aq='Aquafresh:BAABLgAECn84AAIHAAkJ6R2FEgC5AgAHAAkJ6R2FEgC5AgAAAA==.',
Ar='Archspire:BAAALgADCgcJBwAAAA==.Archèrdayne:BAAALgAFFAEJAwAAAA==.Arisel:BAABLgAECn81AAMIAAkJWRo/BwBoAgAIAAkJWRo/BwBoAgAJAAUJpxAFHwCoAAAAAA==.Aristia:BAAALgAFFAEJAQAAAA==.Artemisiah:BAAALgAECgEJAQAAAA==.Arweni:BAABLgAECn82AAIKAAgJYhnwHAAGAgAKAAgJYhnwHAAGAgAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashcheeks:BAAALgAECgEJAQAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8gAAICAAgJECRDCADqAgACAAgJECRDCADqAgABLgAFFAMJCAAEADsXAA==.',
Au='Autoinvite:BAAALgADCgUJBQAAAA==.',
Av='Avlynn:BAAALgADCgMJAwABLgAFFAYJHwAHAD4MAA==.Avoidme:BAAALgADCgkJEQABLgAECgkJOAACANMdAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAABLgAECn8aAAMLAAYJgQssEwC6AAALAAUJTgssEwC6AAAMAAYJYgedVwCxAAABLgAECgkJOAACANMdAA==.Baridyn:BAAALgADCgMJBgAAAA==.Bariir:BAAALgAECgQJBQABLgAECgcJGQANAAAUAA==.',
Be='Bearbacked:BAAALgAECgQJBgABLgAECgQJBwAOAAAAAA==.Bearlytankin:BAAALgADCgkJCQAAAA==.Bearscat:BAAALgADCgUJBQAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Beerus:BAAALgAECgMJAwAAAA==.Beetingu:BAAALgADCgQJBAABLgAECgkJIgAPACEgAA==.Belabites:BAAALgADCgkJCQABLgAECggJIQAGAN0IAA==.Belagrip:BAAALgAECgMJBAABLgAECggJIQAGAN0IAA==.Belashar:BAABLgAECn8hAAIGAAgJ3Qi3FQDiAAAGAAgJ3Qi3FQDiAAAAAA==.Belawar:BAAALgADCggJGgABLgAECggJIQAGAN0IAA==.Beleron:BAAALgAECgIJAgAAAA==.Belinna:BAAALgAECgkJBwAAAA==.Beytuha:BAABLgAECn8tAAIJAAkJYyXyAABdAwAJAAkJYyXyAABdAwAAAA==.',
Bi='Bigtim:BAAALgAFFAEJAQAAAA==.Bigworm:BAAALgADCgYJBgAAAA==.Billd:BAAALgAECgYJCQAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAABLgAECn8qAAMNAAkJxB/BLwBAAgANAAgJNB/BLwBAAgAQAAcJaRlfAwB0AQAAAA==.Blackknife:BAABLgAECn8uAAMRAAgJih6PEgARAgARAAgJih6PEgARAgASAAEJGAmcKQAvAAAAAA==.Bladestorm:BAAALgAECgUJCQABLgAECgcJGQANAAAUAA==.Blakylightz:BAACLgAFFH8KAAIFAAMJIx6PCADvAAAFAAMJIx6PCADvAAAuAAQKfx8AAwUACAnHGgQJAEYCAAUACAnHGgQJAEYCAAYABglzCXm6ABEBAAEuAAUUCQk5AAkAMh8A.Blinker:BAABLgAECn87AAITAAkJBQ4VZQC0AQATAAkJBQ4VZQC0AQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAcJGwATAIIZAA==.Blueberriess:BAAALgAECgEJAgAAAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJEwABLgAFFAYJGAAEAE8IAA==.Bobbidyboo:BAACLgAFFH8YAAIEAAYJTwhGIwA/AQAEAAYJTwhGIwA/AQAuAAQKfy0AAgQACQlsFao2AM0BAAQACQlsFao2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJEAAAAA==.Boomboompowa:BAAALgADCgYJBgAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJEgAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAABLgAECn8UAAIMAAcJ1BT8NAAvAQAMAAcJ1BT8NAAvAQAAAA==.Brixtia:BAAALgAECgUJCQABLgAECgkJJQADAFIdAA==.Brovar:BAACLgAFFH8UAAIGAAUJIh1QPwAsAQAGAAUJIh1QPwAsAQAuAAQKfyoAAwYACAm1I3UaAMoCAAYACAm1I3UaAMoCAAIABQlcCu1zAKwAAAAA.Bruiseleeroy:BAAALgAECgEJBAAAAA==.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAACLgAFFH8OAAIUAAMJ/gw9RwCsAAAUAAMJ/gw9RwCsAAAuAAQKfyIABBQACAkREW8wAHYBABQACAkREW8wAHYBABUABAnxB507AI4AABYAAQnDA31DACgAAAAA.Bubblez:BAAALgAECgUJEAAAAA==.Buddydaelf:BAABLgAECn8zAAIDAAkJ2BvkGgCEAgADAAkJ2BvkGgCEAgAAAA==.Bueskytter:BAAALgADCgEJAQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
Bw='Bwonshlongdi:BAAALgAECgQJAgAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Calithe:BAAALgAECgYJBgAAAA==.Cambey:BAAALgAECgYJDAAAAA==.Candyman:BAAALgADCgYJDgAAAA==.Caprisan:BAAALgAECgQJBAABLgAECggJHAAGAD8aAA==.Castro:BAAALgADCgQJBAAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.Ceodochatos:BAAALgAECgYJBgABLgAECgkJLAAFAIgaAA==.',
Ch='Chals:BAACLgAFFH8bAAMXAAYJFSRRAQAqAgAXAAYJFSRRAQAqAgAYAAIJsA2jPgB+AAAuAAQKfxgAAxcACQn6HCgOAHkCABcACQnyHCgOAHkCABgAAwkVGbA5ANkAAAAA.Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Charfig:BAAALgADCgYJBgAAAA==.Chia:BAAALgAECgYJCAABLgAFFAQJBgAHAKMWAA==.Chillfang:BAACLgAFFH8HAAMNAAMJfQ1S5ACCAAANAAIJfQ1S5ACCAAAQAAEJAAATaAAAAAAuAAQKfykAAg0ACQm9HmYvAEECAA0ACQm9HmYvAEECAAAA.Chouji:BAAALgADCgYJAgAAAA==.Chune:BAAALgAECgQJEgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAABLgAECn8nAAQYAAkJqRShAQBXAgAYAAkJSxShAQBXAgABAAUJdhgMCAD2AAAXAAIJlwsNbgA1AAAAAA==.Clairvoyant:BAAALgAECgEJAQAAAA==.',
Co='Connor:BAABLgAECn8tAAMYAAkJChpzDQCWAgAYAAkJChpzDQCWAgAXAAEJgxfzawA6AAAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgcJEQAAAA==.',
Cr='Cracken:BAAALgADCgcJCAAAAA==.Cretinboy:BAAALgAECgMJAwAAAA==.Crosshair:BAAALgAECgQJDAAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgAECgYJDgAOAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCwAAAA==.',
Da='Daciansniper:BAAALgAECgUJBgAAAA==.Dacianspirit:BAAALgADCgYJBgAAAA==.Dacianwolf:BAAALgAECggJCQAAAA==.Daemoni:BAAALgAECgYJCQAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Danïca:BAAALgAECgMJAwAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJEgAAAA==.Darkerknight:BAAALgAECgQJBAABLgAECgkJNgATABIgAA==.Darkprincess:BAAALgAECgUJBQAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgAECgEJAQABLgAECgcJGQANAAAUAA==.Darthbane:BAAALgAECgMJAwAAAA==.Dathguy:BAAALgAECgYJCgABLgAFFAQJGwANAG0iAA==.Davandar:BAAALgADCgkJGgAAAA==.Daveah:BAABLgAECn80AAIHAAkJlRVbJgAoAgAHAAkJlRVbJgAoAgAAAA==.Dazarros:BAACLgAFFH8NAAIZAAMJxA8WKADKAAAZAAMJxA8WKADKAAAuAAQKfyMAAhkACQmpFL4yAA0CABkACQmpFL4yAA0CAAAA.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8zAAIZAAkJHhRKCABAAQAZAAkJHhRKCABAAQAAAA==.Deathsmoke:BAAALgADCgkJEAAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dekkaa:BAAALgAECgEJAgAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgAECgUJDgAAAA==.Demoncharge:BAAALgAECgQJBAABLgAECgkJEQAOAAAAAA==.Demonclaw:BAAALgAECgEJAgABLgAECgkJEQAOAAAAAA==.Demondrake:BAAALgAECgUJCQABLgAECgkJEQAOAAAAAA==.Demonflayer:BAAALgAECgkJEQAAAA==.Demonikat:BAAALgADCgYJDAAAAA==.Demonsmoke:BAAALgADCgkJCQAAAA==.Demonstalker:BAAALgAECgEJAQABLgAECgkJEQAOAAAAAA==.Denaeaa:BAACLgAFFH8MAAILAAMJtQvyRgCJAAALAAMJtQvyRgCJAAAuAAQKfxsAAgsACAkvDCJNADgBAAsACAkvDCJNADgBAAEuAAUUBgkfAAcAPgwA.Denimblue:BAAALgAECgIJAgAAAA==.Destroyerman:BAAALgADCgQJBAAAAA==.Devilzkry:BAAALgAECgcJCwAAAA==.Devistaysha:BAABLgAFFH8FAAIHAAIJ9Q2iMgBgAAAHAAIJ9Q2iMgBgAAAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgUJBQABLgAECgcJGQADAGMdAA==.',
Dh='Dharmakat:BAAALgADCgUJBQAAAA==.Dhodge:BAABLgAECn8ZAAIaAAcJGR8SLAAYAgAaAAcJGR8SLAAYAgABLgAFFAMJBgAbAFohAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn84AAICAAkJ0x0hDADLAgACAAkJ0x0hDADLAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJCQAAAA==.',
Do='Dodgehoj:BAAALgAECgMJBAABLgAFFAMJBgAbAFohAA==.Doffyy:BAAALgAECgEJAQAAAA==.Dogbreathrlz:BAAALgAECgEJAQAAAA==.Dokash:BAAALgAECgUJCQABLgAFFAEJAwAOAAAAAA==.Dotexe:BAABLgAECn8gAAISAAUJLiEYAQBvAQASAAUJLiEYAQBvAQAAAA==.Dotsy:BAACLgAFFH8dAAQcAAcJNxaVBABBAQAdAAUJbRWeAQBaAQAcAAUJvxmVBABBAQAZAAQJBxGBWQAUAQAuAAQKfy8ABB0ACQlNIq4PANMBAB0ABglDHK4PANMBABkABwnfHsVVAMYBABwABwkhInIKALgBAAAA.Dozius:BAAALgAECgYJBgABLgAFFAYJEQAPAO0UAA==.',
Dr='Drackarys:BAAALgADCgkJIAAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgAECgYJDQAAAA==.Drakiir:BAAALgAECgYJDQABLgAECgcJGQANAAAUAA==.Dralkish:BAACLgAFFH8FAAIGAAMJtQdGfwC3AAAGAAMJtQdGfwC3AAAuAAQKfzgAAgYACQkuEyp0AIYBAAYACQkuEyp0AIYBAAAA.Dramore:BAABLgAECn8kAAIcAAkJzgkpDgB6AQAcAAkJzgkpDgB6AQAAAA==.Drathi:BAAALgADCgcJBwABLgAECgkJOAAGAKIjAA==.Dravas:BAABLgAECn8bAAIKAAYJzg7zDgCiAAAKAAYJzg7zDgCiAAAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Drezzo:BAAALgADCgMJAwAAAA==.Droxx:BAABLgAECn8VAAINAAYJCAxgvwD/AAANAAYJCAxgvwD/AAAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drunkash:BAAALgAECgEJAQAAAA==.Dryerbro:BAAALgAECgEJAQAAAA==.Drzark:BAABLgAECn8XAAMTAAkJEwoLEQATAQATAAkJEwoLEQATAQAeAAIJrgjfFQAoAAAAAA==.',
Du='Dumpling:BAAALgADCgEJAQAAAA==.Dundunduns:BAAALgAECgYJBgAAAA==.',
Dw='Dwdog:BAABLgAECn8nAAIcAAkJrxhLBwD+AQAcAAkJrxhLBwD+AQAAAA==.',
['Dà']='Dàthguy:BAACLgAFFH8bAAINAAQJbSLmFQCAAQANAAQJbSLmFQCAAQAuAAQKf0cAAg0ACQnyJU0DAGsDAA0ACQnyJU0DAGsDAAAA.',
['Dæ']='Dænerÿs:BAAALgAECgMJAwAAAA==.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
['Dé']='Défault:BAACLgAFFH8WAAMNAAYJkREPIAA4AQANAAUJkREPIAA4AQAQAAEJAABnZwAAAAAuAAQKfygAAw0ACQl1IR8LABUDAA0ACQl1IR8LABUDAB8ABAmKEqAbAPEAAAAA.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJEgAAAA==.',
Ef='Eflorescence:BAAALgAECgEJAgAAAA==.',
El='Elennie:BAAALgAECgYJDgAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elephlock:BAAALgAECgQJBQAAAA==.Elephunch:BAAALgAECgUJBQAAAA==.Elerion:BAABLgAECn8jAAMYAAkJ6hPJGgD5AQAYAAkJ6hPJGgD5AQABAAcJSQnrOAAxAQAAAA==.Elista:BAAALgADCgUJBQABLgADCgQJBAAOAAAAAA==.Elm:BAAALgAECgEJAQAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgIJAgABLgAECgQJBAAOAAAAAA==.Emmi:BAABLgAECn8/AAINAAkJkR8GFQDJAgANAAkJkR8GFQDJAgAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIGAAcJ/B7jLwBjAgAGAAcJ/B7jLwBjAgAAAA==.Eralis:BAAALgAECgYJBQAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilspawn:BAAALgAECgcJEQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.Excalipoor:BAAALgADCggJCAAAAA==.',
Ez='Ezekìel:BAAALgAECgEJAgABLgAECgEJAgAOAAAAAA==.',
Fa='Faelivrin:BAAALgAECgcJBQAAAA==.Faith:BAAALgADCgYJBgAAAA==.Falcor:BAACLgAFFH8GAAIUAAUJ5xGYFgDWAAAUAAUJ5xGYFgDWAAAuAAQKfx4AAxQACQkMIv4HAPkCABQACQnAIf4HAPkCABYABgldIXgRAMgBAAAA.Faloran:BAAALgAECgEJAQAAAA==.Farstad:BAAALgADCgMJAwAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgkJCQAAAA==.Fekk:BAAALgADCgIJAgABLgAECgcJDQAOAAAAAA==.Fenderbender:BAAALgADCgYJBgAAAA==.Feralstorm:BAAALgAECgYJCQAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feykat:BAAALgADCgUJBQAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAABLgAECn9BAAIQAAkJ9x3vCACEAgAQAAkJ9x3vCACEAgAAAA==.Fifthelement:BAABLgAECn80AAIHAAkJ0x4XDgDkAgAHAAkJ0x4XDgDkAgAAAA==.Fiorstrasza:BAAALgAECgYJEwAAAA==.Firebunny:BAAALgADCgUJBQAAAA==.',
Fj='Fjalgeirr:BAABLgAECn80AAMgAAkJZxWoFgDSAQAgAAkJZxWoFgDSAQAhAAYJcwp5BAChAAAAAA==.',
Fl='Fleapaw:BAAALgADCgcJBwAAAA==.Flockling:BAAALgADCgkJDwAAAA==.',
Fo='Foxymomma:BAABLgAECn88AAIXAAkJYyO6AwBOAwAXAAkJYyO6AwBOAwAAAA==.',
Fr='Frey:BAACLgAFFH8bAAMNAAYJeB4hDwDGAQANAAYJeB4hDwDGAQAQAAEJAAAFKwAAAAAuAAQKfzIAAg0ACQllJbMFAEwDAA0ACQllJbMFAEwDAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8bAAMcAAkJiCBZAQDjAgAcAAcJ7iRZAQDjAgAZAAYJZxpNtgDaAAAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fugazí:BAAALgADCgUJBQAAAA==.Fulgar:BAAALgAECgQJBwAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.Furryfido:BAAALgADCggJCAABLgAECgkJQQAQAPcdAA==.',
Fw='Fwenwir:BAABLgAECn8aAAQiAAYJFSCWLADKAQAiAAYJfx+WLADKAQAjAAMJvxhLPwDNAAADAAEJ+xhTGQFDAAAAAA==.',
Ga='Galatea:BAAALgAFFAEJAQAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAABLgAECn8pAAIKAAkJ8A2KKwCnAQAKAAkJ8A2KKwCnAQAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJGgABLgAECgkJMQACAE4dAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gidgette:BAAALgAECgYJCwAAAA==.Gilalade:BAABLgAECn8+AAIDAAkJFxzdGQCKAgADAAkJFxzdGQCKAgAAAA==.Gingee:BAAALgADCgIJAgAAAA==.',
Gl='Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8oAAINAAgJIggOnQAwAQANAAgJIggOnQAwAQAAAA==.',
Go='Gobann:BAAALgADCggJEAABLgAECgkJJQADAFIdAA==.Gooby:BAAALgAECgQJBAABLgAFFAgJGgACAJ8TAA==.Gooney:BAAALgAECgIJAwAAAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Greencheese:BAAALgAECgIJAgABLgAECggJGwANABoSAA==.Grimes:BAAALgAECgEJAQABLgAECgQJBwAOAAAAAA==.Grlfriend:BAAALgAFFAEJAQAAAA==.Grodin:BAAALgAECgQJCQAAAA==.Grofiest:BAABLgAECn8kAAMBAAkJjBYSFAAuAgABAAkJjBYSFAAuAgAXAAEJjAFWfgAYAAAAAA==.',
Gu='Guggychan:BAACLgAFFH8GAAIbAAMJWiFlIADzAAAbAAMJWiFlIADzAAAuAAQKfzkAAhsACQmGJg8BAGcDABsACQmGJg8BAGcDAAAA.',
['Gô']='Gôö:BAAALgAECgQJDAAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAIMAAkJTw83KwBkAQAMAAkJTw83KwBkAQAAAA==.Haelwyn:BAAALgAECgEJAQABLgAECgEJAwAOAAAAAA==.Hahine:BAAALgAECgEJAQAAAA==.Haldor:BAABLgAECn8jAAIGAAgJewyjdQCPAQAGAAgJewyjdQCPAQAAAA==.Haohmaru:BAABLgAECn8/AAIkAAkJciGuBQDlAgAkAAkJciGuBQDlAgAAAA==.',
He='Healomatic:BAAALgAECgUJBQABLgAECgcJCgAOAAAAAA==.Hecæte:BAAALgADCgYJBgAAAA==.Heella:BAAALgAECgEJAgAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgQJCAAAAA==.Hercgrimx:BAAALgAECgcJDwAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIZAAUJ+RRjjQA+AQAZAAUJ+RRjjQA+AQAAAA==.',
Hi='Him:BAABLgAECn8lAAIlAAkJqBjpEwBMAgAlAAkJqBjpEwBMAgAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Holiestgoat:BAAALgADCggJDAABLgAECgkJOAACANMdAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.Holyclunge:BAAALgAECgMJAwAAAA==.Holyshocks:BAAALgAECgEJAgAAAA==.',
Hp='Hplaysgames:BAAALgAECgUJCQAAAA==.',
Hu='Huneyhunter:BAABLgAECn8gAAIIAAcJQQwPHwAQAQAIAAcJQQwPHwAQAQAAAA==.Hunterer:BAAALgAECgYJBgAAAA==.',
Ic='Iceburn:BAAALgAECgEJAgAAAA==.Ichigozero:BAAALgAECgEJAQAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
In='Intern:BAACLgAFFH8KAAMYAAIJ7Q0JHgBvAAAYAAIJ7Q0JHgBvAAAXAAIJowuKFABZAAAuAAQKfywABBgACQmVFIIFAF0BABcACAlIFZAdANgBABgABwmDDoIFAF0BAAEAAQkAAFWgAAAAAAAA.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgAECgUJDQAAAA==.',
Iz='Iza:BAAALgADCgIJAgAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakethecake:BAAALgAECgQJBAAAAA==.Jaks:BAAALgAECgEJAwAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAABLgAECn8zAAIWAAkJfxF9BwDEAQAWAAkJfxF9BwDEAQAAAA==.January:BAAALgAECgEJAQABLgAFFAQJCQAZAK0PAA==.Javeech:BAAALgAECgQJBgAAAA==.',
Jc='Jchaotic:BAAALgAECggJDwAAAA==.',
Je='Jeezus:BAAALgADCgYJCgABLgAFFAUJIwANAFEiAA==.Jesophocles:BAAALgAECgEJAQAAAA==.',
Jo='Jocie:BAAALgAECgEJAgAAAA==.Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwAOAAAAAA==.Jongsoo:BAAALgAECgcJCAAAAA==.Jovero:BAAALgAECgQJBQAAAA==.',
Ju='Junghee:BAAALgADCgIJAgAAAA==.Jutas:BAABLgAECn8cAAMYAAgJdgvPLQBsAQAYAAgJdgvPLQBsAQABAAcJwAMtWQCwAAAAAA==.Juudaz:BAACLgAFFH8jAAMNAAUJUSLTGQBfAQANAAQJhyDTGQBfAQAQAAQJlh8lGwAOAQAuAAQKf1UABA0ACQlmJc8DAGQDAA0ACQlmJc8DAGQDABAABwm3IbEOACACAB8AAwksCy8JAGYAAAAA.',
Jv='Jvicious:BAAALgAECgcJCgAAAA==.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAABLgAECn8+AAMCAAkJzyGCBQA6AwACAAkJzyGCBQA6AwAGAAUJMxdtnAA9AQAAAA==.Kaliista:BAAALgAECgEJAQABLgAECgkJIQAEAHwXAA==.Kallan:BAAALgAECgUJDAAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kapkywa:BAACLgAFFH8IAAIEAAMJOxf4NADZAAAEAAMJOxf4NADZAAAuAAQKfxQAAgQACAnfIe0LAAEDAAQACAnfIe0LAAEDAAAA.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.Katsumyo:BAAALgAECgMJAwAAAA==.Kazenazen:BAAALgAECgUJEAAAAA==.',
Ke='Keggz:BAAALgAECgEJAQAAAA==.Kegpoker:BAAALgAECgcJEgAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgUJCAAOAAAAAA==.',
Kh='Khaalzantro:BAAALgAECgIJAgAAAA==.',
Ki='Kilra:BAAALgAECgUJDgAAAA==.Kimbaltina:BAAALgADCgkJIQABLgAECgkJNQAIAFkaAA==.Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJEwAAAA==.Kindasmall:BAAALgAECgkJAQAAAA==.Kiyara:BAABLgAECn9HAAIDAAkJvBaiLgAiAgADAAkJvBaiLgAiAgAAAA==.Kizaki:BAAALgAECgYJDgABLgAECggJFwACAP8SAA==.',
Kn='Knownn:BAAALgAECgIJAgAAAA==.Knowoone:BAABLgAECn9TAAIEAAkJHBlrFgCUAgAEAAkJHBlrFgCUAgAAAA==.Knowwn:BAAALgAECgEJAQAAAA==.',
Ko='Komonaut:BAABLgAECn8ZAAMhAAYJDgvwBACMAAAhAAYJWQrwBACMAAAaAAMJigiW4gByAAAAAA==.Koscihardt:BAABLgAECn8VAAITAAcJcwZM0gDuAAATAAcJcwZM0gDuAAAAAA==.Kouelwhip:BAAALgAECgEJAQABLgAECgcJGQANAAAUAA==.',
Kr='Krakin:BAAALgAECgYJBgAAAA==.Krelliz:BAABLgAECn8cAAIHAAcJTRDiZgAnAQAHAAcJTRDiZgAnAQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAABLgAECn8hAAITAAgJGQv9sAAgAQATAAgJGQv9sAAgAQAAAA==.Kronnk:BAAALgAECgEJAQAAAA==.Krystar:BAAALgAECgUJDgAAAA==.',
Ku='Kulfig:BAAALgAECgkJEQAAAA==.Kumen:BAABLgAECn8iAAQPAAkJISD7EwAzAgAPAAgJjx37EwAzAgAIAAUJfh71FwBTAQAJAAUJUxakLgDzAAAAAA==.Kungfuwho:BAACLgAFFH8RAAMMAAQJbxBzGgD1AAAMAAQJbxBzGgD1AAALAAQJ/QNBQQCeAAAuAAQKfzYAAwwACQlZGQwfALUBAAwACAkpGQwfALUBAAsACAk6C1NNADgBAAAA.Kutyou:BAAALgAECgQJBAAAAA==.',
Ky='Kynlailia:BAAALgADCgQJBAAAAA==.',
['Kó']='Kóólaid:BAAALgAECgIJAgAAAA==.',
['Kû']='Kûnei:BAAALgAECgQJBwAAAA==.',
La='Laladin:BAAALgAECgMJAwAAAA==.Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lemonlime:BAAALgAFFAIJAgAAAA==.Lenaea:BAACLgAFFH8fAAMHAAYJPgykMAAfAQAHAAYJPgykMAAfAQAlAAEJMwLyMwArAAAuAAQKfyUAAgcACQnwGKEtAAACAAcACQnwGKEtAAACAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAACLgAFFH8OAAICAAQJKg5NKQDbAAACAAQJKg5NKQDbAAAuAAQKfycAAgIACAkAFZAnAM4BAAIACAkAFZAnAM4BAAAA.Liiege:BAABLgAECn8ZAAMNAAcJABRqcwB9AQANAAcJABRqcwB9AQAQAAIJwg+GPABiAAAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Linlithyr:BAAALgAECgIJAgABLgAFFAMJCgAQAGgXAA==.Litesuprmcst:BAAALgAECgQJBQAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJCAAAAA==.',
Lo='Lobø:BAABLgAECn8nAAIDAAkJRxjaLAApAgADAAkJRxjaLAApAgAAAA==.Loganx:BAAALgAECgUJCQABLgAECgcJCwAOAAAAAA==.Lorsie:BAAALgADCggJCAABLgAECgkJKAAGAGINAA==.Lowtierscrub:BAAALgAECgEJAQAAAA==.Loxen:BAAALgAECgEJAQAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn9IAAINAAkJfhNyBAD5AQANAAkJfhNyBAD5AQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgUJCAAAAA==.Lutherisch:BAAALgAECgUJBQABLgAECgUJCAAOAAAAAA==.Lux:BAAALgAECgQJBAAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgAECgQJBAAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAABLgAECn8oAAITAAgJ6wjlmQBFAQATAAgJ6wjlmQBFAQAAAA==.Mageairena:BAAALgAECgMJAwAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgAECgIJBQAAAA==.Magnues:BAAALgADCgQJBAAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAABLgAECn8XAAIEAAgJJB+pAgACAgAEAAgJJB+pAgACAgAAAA==.Manatease:BAAALgAECgEJAQAAAA==.Manatee:BAAALgAECgYJDQAAAA==.Mannan:BAAALgADCgIJAgAAAA==.Marlasinger:BAAALgAECgQJBAAAAA==.Marpesia:BAAALgAECgcJCgAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Marteris:BAAALgAECgEJAwAAAA==.Maygwyn:BAABLgAECn8sAAITAAkJTAnZDABCAQATAAkJTAnZDABCAQAAAA==.',
Me='Meanshami:BAAALgAECgEJAQAAAA==.Meatlovers:BAAALgAECgUJBgAAAA==.Mediva:BAAALgAECgUJEwAAAA==.Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgYJDwAAAA==.Megaera:BAACLgAFFH8GAAIaAAMJwhvOIwCxAAAaAAMJwhvOIwCxAAAuAAQKfx4AAxoACQnuIPMOAAcDABoACQnuIPMOAAcDACAAAQkeGBZsADoAAAAA.Melar:BAACLgAFFH8IAAMmAAIJpgSWFABbAAAmAAIJpgSWFABbAAAKAAEJCAPFMgA0AAAuAAQKfzYAAyYACQnED2oDAEABAAoACAmMEK8zAHwBACYABwkaD2oDAEABAAAA.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.Messyah:BAAALgAFFAIJAwAAAA==.',
Mi='Migmong:BAAALgAECgIJBQAAAA==.Mihawk:BAAALgAECgQJBwAAAA==.Milwaukee:BAAALgAECgEJAQAAAA==.Minjae:BAABLgAECn8hAAMZAAkJWxViBADEAQAZAAkJWxViBADEAQAcAAEJ/hBIPgA1AAABLgAFFAQJCQAZACcRAA==.Minseo:BAAALgAECgEJAwAAAA==.Miserain:BAAALgAECgUJEwAAAA==.Mistbehaving:BAAALgAECgQJBAAAAA==.',
Mo='Moondemon:BAAALgAECgUJCgAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Moozart:BAAALgADCgEJAQAAAA==.Morphumbra:BAAALgAECgUJBQAAAA==.Morrìgan:BAABLgAECn8ZAAMZAAcJ3QWOswDeAAAZAAcJ3QWOswDeAAAdAAIJqwOUYgBJAAAAAA==.Morvane:BAAALgAECgQJBAABLgAECgkJMQACAE4dAA==.Mothra:BAAALgAECgQJCQABLgAFFAQJBgAHAKMWAA==.Movack:BAABLgAECn8rAAIGAAkJpg4VZQClAQAGAAkJpg4VZQClAQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.Mozwangsung:BAAALgADCgYJBwAAAA==.',
Mu='Muncha:BAAALgAECgEJAgAAAA==.Murderface:BAABLgAECn8rAAMPAAkJ7BV3GwDvAQAPAAkJ7BV3GwDvAQAEAAcJvRl3UABNAQAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAABLgAECn8bAAIdAAkJgQohEQAzAQAdAAkJgQohEQAzAQAAAA==.Mythunran:BAABLgAECn8rAAIiAAgJJhMDDwBtAQAiAAgJJhMDDwBtAQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJEgAOAAAAAA==.Natash:BAAALgAECgEJAgAAAA==.Nau:BAAALgAECgUJBQAAAA==.Nawas:BAAALgAECgEJAgAAAA==.Nax:BAAALgAECgUJDQAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAgABLgAECgUJBwAOAAAAAA==.Nerfhammer:BAACLgAFFH8RAAIGAAUJXxpsJQBzAQAGAAUJXxpsJQBzAQAuAAQKfyoAAgYACQlLIwkcAMICAAYACQlLIwkcAMICAAAA.Nessalove:BAACLgAFFH8fAAIXAAcJ7g8yBQBfAQAXAAcJ7g8yBQBfAQAuAAQKfysAAhcACQmUHTgMAI8CABcACQmUHTgMAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8eAAQUAAkJjw2ROgBBAQAUAAcJAQ6ROgBBAQAVAAYJJxEmHwD+AAAWAAEJxANIQgArAAAAAA==.Nipao:BAABLgAECn8eAAILAAgJGR5QAQCoAgALAAgJGR5QAQCoAgAAAA==.Niron:BAAALgAECgUJCwAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAABLgAFFH8QAAILAAMJPRMVOwC5AAALAAMJPRMVOwC5AAABLgAFFAkJOQATAAslAA==.Noriel:BAABLgAECn8VAAITAAkJcRAGXwDCAQATAAkJcRAGXwDCAQAAAA==.Nostradamos:BAAALgADCgYJBgAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAABLgAECn8UAAIDAAcJNREzbABpAQADAAcJNREzbABpAQAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Og='Ognyal:BAAALgAECgkJBQAAAA==.',
Oh='Ohtani:BAAALgAECgkJDgAAAA==.',
Ol='Olanali:BAAALgAECgEJAwABLgAECgEJAwAOAAAAAA==.Olectria:BAAALgADCgEJAQAAAA==.',
On='Onna:BAAALgADCgIJAgAAAA==.',
Oo='Ooblitoon:BAABLgAECn9UAAIWAAkJghO7BQD/AQAWAAkJghO7BQD/AQAAAA==.',
Op='Opali:BAAALgAECgEJAQAAAA==.',
Or='Orfantal:BAABLgAECn8hAAIDAAkJExIjSwDAAQADAAkJExIjSwDAAQAAAA==.Oridan:BAAALgAECgEJAQAAAA==.Oridon:BAAALgAECgQJDAAAAA==.',
Ou='Ouahoahoah:BAAALgAFFAEJAQAAAA==.',
Ov='Oven:BAAALgAECgUJBQABLgAFFAQJGwANAG0iAA==.Overburned:BAAALgAECgMJAwAAAA==.Overcast:BAAALgAECgYJEAAAAA==.Overshoot:BAABLgAECn8aAAMDAAkJlgzWTwCzAQADAAkJlgzWTwCzAQAjAAIJXgRKVgBUAAAAAA==.',
Ow='Owyyn:BAAALgADCggJCQAAAA==.',
Ox='Oxen:BAAALgAECggJDAAAAA==.',
Pa='Pallyairena:BAAALgADCgQJBAAAAA==.Panterion:BAABLgAECn8hAAIEAAkJfBeXJQAgAgAEAAkJfBeXJQAgAgAAAA==.Papimonk:BAAALgAECgIJAgABLgAECggJFQAHAP8ZAA==.Parvarti:BAABLgAECn8gAAMdAAkJDQjDGADcAAAdAAcJBQnDGADcAAAZAAIJJgWUGAFPAAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECgkJGgANAAYdAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Peanutxo:BAAALgADCgEJAQAAAA==.Persimmoñ:BAABLgAECn8/AAMGAAkJrhFcCwBXAQAGAAkJrhFcCwBXAQAFAAMJ9AbICwBbAAAAAA==.Petthemonk:BAAALgAECgEJAgAAAA==.',
Ph='Phaelissia:BAAALgAECgYJDwAAAA==.Philljr:BAAALgADCgMJAwAAAA==.',
Pi='Pinero:BAAALgADCgYJCQAAAA==.',
Pl='Plaugus:BAAALgAECgUJEwAAAA==.',
Po='Polkadott:BAAALgADCggJCAABLgAECgkJIgAPACEgAA==.Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgcJEQAAAA==.Prost:BAABLgAECn8hAAITAAkJlxxfRQALAgATAAkJlxxfRQALAgAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Ps='Psylocke:BAAALgAFFAEJAQAAAA==.',
Pu='Puppybreath:BAAALgAECgEJAQAAAA==.Purdy:BAAALgAECgkJAgAAAA==.',
Py='Pyroblast:BAACLgAFFH8bAAMTAAcJghm5PQB2AQATAAYJBxq5PQB2AQAnAAEJ6BY0AwBaAAAuAAQKfzwAAxMACQleITcSAO0CABMACQmWIDcSAO0CACcAAwkGI34HADUBAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Raedon:BAAALgAECgUJBQAAAA==.Ralie:BAAALgAECgEJAQAAAA==.Ravage:BAAALgAECgUJBwAAAA==.',
Re='Relaceara:BAABLgAECn8WAAIGAAkJswVbqQApAQAGAAkJswVbqQApAQAAAA==.Reladin:BAABLgAECn8/AAIFAAkJpwqwGgBDAQAFAAkJpwqwGgBDAQAAAA==.Relanna:BAABLgAECn8WAAINAAYJjAfh6wDFAAANAAYJjAfh6wDFAAAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCggJIwAAAA==.Rendstein:BAABLgAECn8jAAIQAAkJhhjIEQDxAQAQAAkJhhjIEQDxAQAAAA==.Renzr:BAACLgAFFH8YAAMNAAQJ9hxCGgBcAQANAAQJ9hxCGgBcAQAQAAEJwRIAHQBJAAAuAAQKf0wAAw0ACQl6JTUWAMICAA0ACQnjJDUWAMICABAACAklI4cHAKICAAAA.Reqquuiiem:BAAALgADCgUJCAAAAA==.Respcct:BAAALgADCgkJGgABLgAECgkJOAACANMdAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAABLgAECn8UAAIEAAkJMQ/IRQB5AQAEAAkJMQ/IRQB5AQAAAA==.Rowin:BAABLgAECn8XAAMEAAkJuQh0ZgABAQAEAAkJuQh0ZgABAQAPAAMJzQfmbABwAAAAAA==.Royal:BAAALgAECgEJAQAAAA==.',
Ru='Rupy:BAAALgAECgEJAQAAAA==.Rustedroots:BAABLgAECn81AAMEAAkJQhgVGwBtAgAEAAkJQhgVGwBtAgAIAAUJNxV6AwAYAQAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Sailley:BAAALgAECgUJEQAAAA==.Saltgrizzny:BAAALgAECgcJDQAAAA==.Sapphyre:BAAALgAECgEJAgAAAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAABLgAECn8eAAIiAAkJfRQVCwC5AQAiAAkJfRQVCwC5AQAAAA==.Sarnara:BAABLgAECn8sAAIFAAkJiBp3CQA4AgAFAAkJiBp3CQA4AgAAAA==.Savageclaw:BAAALgAECggJCQAAAA==.Savageclaws:BAAALgAECgEJAQABLgAFFAEJBAAOAAAAAA==.Savagehunt:BAAALgAFFAEJAQABLgAFFAEJBAAOAAAAAA==.Savagekegs:BAABLgAECn8VAAMkAAYJ7SD8OABmAQAkAAQJZSP8OABmAQAMAAUJQhhUPQAmAQABLgAFFAEJBAAOAAAAAA==.Savagelight:BAAALgAFFAEJBAAAAA==.Savagex:BAAALgAECgEJAQAAAA==.Sazayaki:BAAALgADCgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAABLgAECn8rAAIDAAkJVQS5IACcAAADAAkJVQS5IACcAAAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgAECgEJAQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Senarx:BAAALgAECgIJBAAAAA==.Sereniity:BAABLgAECn8WAAQkAAcJ3SFVGwDKAQAkAAYJLiJVGwDKAQALAAUJYRifMQAxAQAMAAIJeRteYACZAAABLgAECgcJGQANAAAUAA==.',
Sh='Shadowjack:BAAALgAECgEJAgAAAA==.Shakastraza:BAAALgAECgEJAQAAAA==.Shamalicous:BAABLgAECn8UAAMHAAUJAgLirABvAAAHAAUJAgLirABvAAAlAAQJ+wXvggBqAAAAAA==.Shamjam:BAABLgAECn8jAAIHAAgJ+BEwPAC+AQAHAAgJ+BEwPAC+AQAAAA==.Shamous:BAAALgAECgUJCAAAAA==.Shampayne:BAAALgADCgYJBgABLgAFFAUJIwANAFEiAA==.Shanthe:BAAALgAECgYJEQABLgAFFAUJDQARAOYXAA==.Sharku:BAACLgAFFH8dAAITAAUJKhp7KAABAQATAAUJKhp7KAABAQAuAAQKfy4AAhMACQkvIJYWANICABMACQkvIJYWANICAAAA.Shegothalf:BAAALgAECgYJCgAAAA==.Shortwide:BAAALgADCgIJAgAAAA==.Shãdo:BAAALgAECgYJCAAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAFFAUJBgAUAOcRAA==.Siinep:BAAALgAECgcJEAAAAA==.Sintan:BAAALgAECgYJBgAAAA==.Sistersledge:BAAALgADCgkJCgAAAA==.',
Sk='Skey:BAAALgAECgIJAgAAAA==.Skibblé:BAABLgAECn8aAAIdAAkJCw8ADAB/AQAdAAkJCw8ADAB/AQAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAABLgAECn8ZAAIEAAkJXxdpKAAOAgAEAAkJXxdpKAAOAgAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIaAAgJrSGCEgDrAgAaAAgJrSGCEgDrAgAAAA==.Smokeofsteel:BAAALgAECggJDQAAAA==.Smokeyjr:BAAALgADCgcJBwAAAA==.',
Sn='Sneakyboi:BAABLgAECn8uAAISAAkJZRq/BABBAgASAAkJZRq/BABBAgAAAA==.Snippin:BAAALgAECgIJAgAAAA==.',
So='Soléne:BAABLgAECn8iAAMHAAgJOh2gHgBZAgAHAAcJsB2gHgBZAgAlAAUJxBUAWgDWAAABLgAFFAQJCQAZAK0PAA==.Sorden:BAAALgAECgQJBgABLgAFFAIJAgAOAAAAAA==.',
Sp='Spiced:BAABLgAECn8ZAAIPAAgJSCC0DQDAAgAPAAgJSCC0DQDAAgABLgAECgkJGwAcAIggAA==.Spliff:BAAALgAECgIJAgAAAA==.',
Sq='Squirt:BAABLgAECn8aAAIVAAgJvQ88GgC6AQAVAAgJvQ88GgC6AQAAAA==.',
Ss='Ssks:BAAALgAFFAEJAQABLgAECgMJDAAOAAAAAA==.',
St='Stabsmcshank:BAACLgAFFH8YAAIRAAQJkxP3GwA7AQARAAQJkxP3GwA7AQAuAAQKfzwAAhEACQlJGocCAJgBABEACQlJGocCAJgBAAAA.Starbux:BAACLgAFFH8KAAIYAAIJsgfYHwBkAAAYAAIJsgfYHwBkAAAuAAQKfyoABBgACAmBEGUuAGgBABgACAlVDmUuAGgBAAEABgm8B8hQAM4AABcABQkQDz9aAMsAAAAA.Starmagic:BAAALgAECgkJBgAAAA==.Steakx:BAAALgAECgQJCAAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Sunmae:BAAALgAECgUJCAABLgAECgkJNQAIAFkaAA==.Suriel:BAABLgAECn8nAAIQAAkJLRO1AgCtAQAQAAkJLRO1AgCtAQAAAA==.Suumcuique:BAAALgAECgIJAgABLgAECgkJKwAPAOwVAA==.',
Sv='Svenya:BAABLgAECn8dAAMPAAkJ7Q1OOwAkAQAPAAgJbAtOOwAkAQAEAAYJ2gbphACuAAAAAA==.',
Sy='Syenna:BAAALgAECgEJAQAAAA==.Sygne:BAAALgAECgYJDgAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAABLgAECn81AAIDAAkJgRKPPADuAQADAAkJgRKPPADuAQAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJCAABLgAFFAQJBgAHAKMWAA==.',
['Sï']='Sïenna:BAABLgAECn8UAAINAAkJvBQeQwD5AQANAAkJvBQeQwD5AQAAAA==.',
Ta='Tacituss:BAAALgAECgYJBgAAAA==.Taggy:BAABLgAECn8rAAISAAgJaQ8tCwB/AQASAAgJaQ8tCwB/AQABLgAECgkJNQAIAFkaAA==.Taln:BAAALgAECgEJBQAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Taraah:BAAALgADCgIJAgABLgAECgkJGgABAHoLAA==.Tassandie:BAAALgAECgQJBAABLgAECgkJIQAEAHwXAA==.Tayebeh:BAAALgAECgUJBwAAAA==.',
Te='Tektoniik:BAAALgAECgEJAQABLgAECgcJGQANAAAUAA==.Texhd:BAAALgAECgYJBgABLgAFFAkJKAAUAKEZAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.Thansus:BAAALgAECgEJAQAAAA==.Theçølletør:BAAALgAECgMJAwAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.Tinygibbs:BAAALgAECgMJBAAAAA==.Tionie:BAAALgADCgIJAgAAAA==.',
To='Toiletnuker:BAABLgAECn8lAAQjAAkJBw9FHgCqAQAjAAkJYg5FHgCqAQADAAYJug1LoAABAQAiAAEJRApEQQAoAAABLgAECgkJOAACANMdAA==.Tokyojoe:BAABLgAECn8jAAIaAAkJ5hSrOQDgAQAaAAkJ5hSrOQDgAQAAAA==.Tolsanah:BAABLgAFFH8TAAILAAcJ9xJsEgD3AQALAAcJ9xJsEgD3AQABLgAFFAkJOgAVAPEeAA==.Torocious:BAAALgAECgYJDQAAAA==.Torrick:BAABLgAECn84AAQGAAkJoiPSBwAuAwAGAAkJhCPSBwAuAwAFAAYJySCsAQDXAQACAAYJBRcRNwCfAQAAAA==.Torrickdemon:BAAALgAECgkJDgABLgAECgkJOAAGAKIjAA==.Torrickgreed:BAAALgADCgYJBgABLgAECgkJOAAGAKIjAA==.Totemtot:BAABLgAECn86AAIoAAkJkQiuBQDKAAAoAAkJkQiuBQDKAAAAAA==.Toupee:BAAALgAECgUJBgAAAA==.',
Tr='Tradrivia:BAAALgAECgcJCQAAAA==.Tronly:BAAALgADCgUJBQAAAA==.Trukait:BAAALgAECgEJAQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Tw='Twinkish:BAAALgAECgEJAQAAAA==.',
Ty='Tyllivan:BAAALgAECgMJBQAAAA==.',
['Tá']='Tálise:BAAALgAECgUJBgAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCgAAAA==.',
Uf='Uffizzle:BAAALgAECgcJDQAAAA==.',
Ul='Ulf:BAABLgAECn8nAAIHAAgJMBnOHQBfAgAHAAgJMBnOHQBfAgAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Uu='Uurgeorn:BAEALgADCgEJAQAAAA==.',
Va='Valquirie:BAACLgAFFH8KAAIQAAMJaBeVJADKAAAQAAMJaBeVJADKAAAuAAQKf0QAAhAACQk/IX0EAOsCABAACQk/IX0EAOsCAAAA.Valyrius:BAAALgADCggJCQABLgAECgYJBgAOAAAAAA==.Varlamor:BAABLgAECn8VAAMXAAgJlwvvMABJAQAXAAgJlwvvMABJAQABAAUJYQTvYwCLAAAAAA==.Varolokiir:BAAALgAECgEJAgABLgAECgcJGQANAAAUAA==.Vathraen:BAAALgAECgMJBgAAAA==.',
Ve='Velanistra:BAABLgAECn8oAAIGAAkJYg05bQCUAQAGAAkJYg05bQCUAQAAAA==.Velanya:BAAALgAECgIJAwAAAA==.Velnia:BAAALgAECgcJBwAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAABLgAECn8oAAIgAAkJFBH1GwCeAQAgAAkJFBH1GwCeAQAAAA==.Very:BAAALgAECgUJDgAAAA==.',
Vg='Vgerr:BAABLgAECn8WAAIGAAkJAgyWawCXAQAGAAkJAgyWawCXAQAAAA==.',
Vi='Viashino:BAAALgAECgUJBgABLgAECgYJEAAOAAAAAA==.Vidarus:BAAALgAFFAIJAwABLgAFFAUJEQAGAF8aAA==.Vintage:BAAALgAECgEJAQAAAA==.Viridian:BAAALgAECgMJBgABLgAFFAMJBgAaAMIbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAABLgAECn8lAAMDAAkJUh03LgAkAgADAAcJGB43LgAkAgAiAAYJlBfmGADpAAAAAA==.Vorron:BAAALgADCgEJAQABLgAFFAMJCAAEADsXAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAACLgAFFH8FAAMgAAIJ1BHADwCNAAAgAAIJ1BHADwCNAAAaAAEJpgWApQA1AAAuAAQKfxUAAxoACQliD3yrAM8AABoACAlpDnyrAM8AACAAAgnjEVFQAHYAAAAA.Vynos:BAABLgAECn8hAAIZAAgJQgfYjwAbAQAZAAgJQgfYjwAbAQAAAA==.Vysant:BAAALgADCgQJBgABLgAECggJIQAZAEIHAA==.',
['Vä']='Väl:BAAALgAECgQJCAAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAACLgAFFH8GAAMHAAQJoxYgMwAVAQAHAAQJoxYgMwAVAQAlAAEJRwN1XwAuAAAuAAQKfyYAAwcACQkLE7E1ANoBAAcACQkLE7E1ANoBACUABwn2E7U6AEsBAAAA.',
Wc='Wchaos:BAAALgAECgUJBwAAAA==.',
We='Welker:BAAALgADCgQJCAABLgAFFAMJCAANAKAQAA==.Welkerdk:BAACLgAFFH8IAAINAAMJoBCIpQDPAAANAAMJoBCIpQDPAAAuAAQKfzIAAg0ACQlJIG8YALQCAA0ACQlJIG8YALQCAAAA.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgAaAMIbAA==.',
Wh='Whiskeycakes:BAAALgAECgQJBwAAAA==.Whispyre:BAAALgAECgEJAgABLgAECgEJAgAOAAAAAA==.',
Wi='Wiglet:BAAALgADCgEJAQAAAA==.Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.Windeyaho:BAAALgAECggJCgAAAA==.',
Wo='Wolfman:BAABLgAECn8jAAIkAAkJlgshJQCEAQAkAAkJlgshJQCEAQAAAA==.Woökie:BAAALgADCgYJBgAAAA==.',
Xa='Xalidan:BAAALgAFFAIJAgAAAA==.',
Xt='Xten:BAABLgAECn8hAAIEAAkJUhX/BABmAQAEAAkJUhX/BABmAQAAAA==.',
Ya='Yamedvedko:BAAALgAECgcJBwAAAA==.Yamzofsteel:BAAALgAECgEJAQAAAA==.Yath:BAAALgAECgMJAwAAAA==.',
Ye='Yeat:BAAALgAECgUJCwAAAA==.',
Yo='Yoatanius:BAAALgAECgEJAQAAAA==.Yoshinox:BAAALgAECgMJBAAAAA==.',
Yr='Yrelle:BAAALgAECgMJAwABLgAECgkJGgABAHoLAA==.',
Za='Zalazam:BAABLgAECn8mAAMlAAkJOx1HEwBTAgAlAAkJOx1HEwBTAgAHAAEJjhmvwwBMAAAAAA==.Zalth:BAABLgAECn8lAAITAAkJ0g2WaQCpAQATAAkJ0g2WaQCpAQAAAA==.',
Ze='Zelliph:BAAALgAECgUJDgAAAA==.Zenagdrina:BAABLgAECn8dAAMjAAgJuggABAARAQAjAAgJlwgABAARAQADAAIJBAahJgE6AAAAAA==.Zenobiå:BAACLgAFFH8GAAMlAAIJEQYFIQBrAAAlAAIJEQYFIQBrAAAHAAIJtQQmPQBKAAAuAAQKfxsAAyUACAmkEgwHABcBACUACAmkEgwHABcBAAcAAQmqBgrxACAAAAAA.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.Zeypher:BAAALgADCggJDAAAAA==.',
Zh='Zhaann:BAABLgAECn8aAAMBAAkJegvhPwARAQABAAcJ7A3hPwARAQAYAAUJHwmnEQBmAAAAAA==.Zhaida:BAAALgADCgIJAgAAAA==.',
Zi='Zinarra:BAAALgADCgQJBAAAAA==.',
Zo='Zokor:BAAALgAECgUJCAAAAA==.Zorach:BAAALgAECgYJDwAAAA==.',
['Zá']='Zárá:BAABLgAECn89AAITAAkJUhkZCQCFAQATAAkJUhkZCQCFAQAAAA==.',
['Ðz']='Ðz:BAAALgAFFAEJAQABLgAFFAYJEQAPAO0UAA==.',
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
