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

local lookup = {'Priest-Shadow','Paladin-Holy','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Shaman-Restoration','Druid-Feral','Druid-Guardian','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Mage-Frost','Monk-Windwalker','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Priest-Discipline','Unknown-Unknown','Warlock-Demonology','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Monk-Brewmaster','Shaman-Elemental','Druid-Balance','Warrior-Protection','Mage-Arcane','Shaman-Enhancement',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-06-27',data={Ad='Ader:BAAALgADCgkJDQAAAA==.Advîl:BAAALgAECgQJBAAAAA==.',
Ae='Aeryhnn:BAAALgAECgQJBAABLgAECgkJGAABAJELAA==.',
Ai='Ainoskedu:BAAALgADCgIJAgAAAA==.',
Ak='Akümä:BAAALgAECgEJAQAAAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAABLgAECn8hAAICAAYJhxYdOgBiAQACAAYJhxYdOgBiAQAAAA==.Albinodwarf:BAAALgAFFAEJAQAAAA==.Albinoorc:BAAALgAECgEJAgAAAA==.Alexandre:BAABLgAECn8mAAIDAAkJ/hUWMgAUAgADAAkJ/hUWMgAUAgAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAABLgAECn8aAAIEAAcJVw7eUgBEAQAEAAcJVw7eUgBEAQAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAABLgAECn8xAAQCAAkJTh1gCwDXAgACAAkJTh1gCwDXAgAFAAMJ3QOiRQBOAAAGAAEJRgcgtAEoAAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJBgAAAA==.Ansuz:BAAALgAECgEJAgAAAA==.',
Ap='Aphroditee:BAAALgAECgMJBAAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgQJAwAAAA==.',
Aq='Aquafresh:BAABLgAECn84AAIHAAkJ6R2FEgC5AgAHAAkJ6R2FEgC5AgAAAA==.',
Ar='Archèrdayne:BAAALgAFFAEJAwAAAA==.Arisel:BAABLgAECn81AAMIAAkJWxo/BwBoAgAIAAkJWxo/BwBoAgAJAAUJpxAFHwCoAAAAAA==.Aristia:BAAALgAECgUJDQAAAA==.Artemisiah:BAAALgAECgEJAQAAAA==.Arweni:BAABLgAECn82AAIKAAgJYhnwHAAGAgAKAAgJYhnwHAAGAgAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashcheeks:BAAALgAECgEJAQAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8gAAICAAgJECRDCADqAgACAAgJECRDCADqAgABLgAFFAMJBgAEADsXAA==.',
Av='Avlynn:BAAALgADCgMJAwABLgAFFAUJHAAHAD4MAA==.Avoidme:BAAALgADCgkJEQABLgAECgkJOAACANMdAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAAALgAECgYJEgABLgAECgkJOAACANMdAA==.Baridyn:BAAALgADCgMJBgAAAA==.Bariir:BAAALgAECgQJBQABLgAECgcJGQALAAAUAA==.',
Be='Bearbacked:BAAALgAECgQJBgAAAA==.Bearlytankin:BAAALgADCgkJCQAAAA==.Bearscat:BAAALgADCgUJBQAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Beerus:BAAALgAECgMJAwAAAA==.Belagrip:BAAALgAECgMJBAABLgAECgcJGgAGAF4HAA==.Belashar:BAABLgAECn8aAAIGAAcJXgd+zgD1AAAGAAcJXgd+zgD1AAAAAA==.Belawar:BAAALgADCggJGgABLgAECgcJGgAGAF4HAA==.Beleron:BAAALgAECgIJAgAAAA==.Belinna:BAAALgAECgkJBwAAAA==.Beytuha:BAABLgAECn8tAAIJAAkJYyXyAABdAwAJAAkJYyXyAABdAwAAAA==.',
Bi='Bigtim:BAAALgAFFAEJAQAAAA==.Bigworm:BAAALgADCgYJBgAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAABLgAECn8mAAMLAAkJbx/BLwBAAgALAAgJNB/BLwBAAgAMAAUJjBeFBQCKAAAAAA==.Blackknife:BAABLgAECn8uAAMNAAgJih6PEgARAgANAAgJih6PEgARAgAOAAEJGAmcKQAvAAAAAA==.Bladestorm:BAAALgAECgUJCQABLgAECgcJGQALAAAUAA==.Blakylightz:BAACLgAFFH8IAAIFAAMJZRuPCADvAAAFAAMJZRuPCADvAAAuAAQKfx8AAwUACAnHGgQJAEYCAAUACAnHGgQJAEYCAAYABglzCXm6ABEBAAEuAAUUCAkxAAkAFyEA.Blinker:BAABLgAECn87AAIPAAkJBQ4ACwAAAQAPAAkJBQ4ACwAAAQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAcJFgAPAAwZAA==.Blueberriess:BAAALgAECgEJAgAAAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJEwABLgAFFAYJGAAEAE8IAA==.Bobbidyboo:BAACLgAFFH8YAAIEAAYJTwhGIwA/AQAEAAYJTwhGIwA/AQAuAAQKfy0AAgQACQlsFao2AM0BAAQACQlsFao2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJDgAAAA==.Boomboompowa:BAAALgADCgYJBgAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJEgAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAABLgAECn8UAAIQAAcJ2hT8NAAvAQAQAAcJ2hT8NAAvAQAAAA==.Brixtia:BAAALgAECgUJCQABLgAECgkJIgADAGAcAA==.Brovar:BAACLgAFFH8UAAIGAAUJIh1QPwAsAQAGAAUJIh1QPwAsAQAuAAQKfyoAAwYACAm1I3UaAMoCAAYACAm1I3UaAMoCAAIABQlcCu1zAKwAAAAA.Bruiseleeroy:BAAALgAECgEJAgAAAA==.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAACLgAFFH8OAAIRAAMJ/gw9RwCsAAARAAMJ/gw9RwCsAAAuAAQKfyIABBEACAkREW8wAHYBABEACAkREW8wAHYBABIABAnxB507AI4AABMAAQnDA31DACgAAAAA.Bubblez:BAAALgAECgUJEAAAAA==.Buddydaelf:BAABLgAECn8xAAIDAAkJwBvkGgCEAgADAAkJwBvkGgCEAgAAAA==.Bueskytter:BAAALgADCgEJAQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
Bw='Bwonshlongdi:BAAALgAECgQJAgAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Calithe:BAAALgAECgYJBgAAAA==.Cambey:BAAALgAECgMJBgAAAA==.Candyman:BAAALgADCgYJDgAAAA==.Caprisan:BAAALgAECgQJBAABLgAECggJHAAGAD8aAA==.Castro:BAAALgADCgQJBAAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.Ceodochatos:BAAALgAECgYJBgABLgAECgkJLAAFAIgaAA==.',
Ch='Chals:BAACLgAFFH8aAAMUAAUJIiQuAQDRAQAUAAUJIiQuAQDRAQAVAAIJsA2jPgB+AAAuAAQKfxgAAxQACQn6HCgOAHkCABQACQnyHCgOAHkCABUAAwkVGbA5ANkAAAEuAAUUBQkaABQAIiQA.Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Charfig:BAAALgADCgYJBgAAAA==.Chia:BAAALgAECgYJBwABLgAFFAQJBgAHAKMWAA==.Chillfang:BAACLgAFFH8HAAMLAAMJfQ1S5ACCAAALAAIJfQ1S5ACCAAAMAAEJAAATaAAAAAAuAAQKfykAAgsACQm9HmYvAEECAAsACQm9HmYvAEECAAAA.Chouji:BAAALgADCgYJAgAAAA==.Chune:BAAALgAECgQJEgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAABLgAECn8hAAQVAAkJrxP1AAA+AgAVAAkJVhP1AAA+AgABAAUJkw1RUQDMAAAUAAIJlwsNbgA1AAAAAA==.Clairvoyant:BAAALgAECgEJAQAAAA==.',
Co='Connor:BAABLgAECn8tAAMVAAkJChpzDQCWAgAVAAkJChpzDQCWAgAUAAEJgxfzawA6AAAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgcJEQAAAA==.',
Cr='Cracken:BAAALgADCgcJCAAAAA==.Cretinboy:BAAALgAECgMJAwAAAA==.Crosshair:BAAALgAECgQJDAAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgAECgYJCwAWAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCQAAAA==.',
Da='Daciansniper:BAAALgAECgUJBgAAAA==.Dacianspirit:BAAALgADCgYJBgAAAA==.Dacianwolf:BAAALgAECggJCAAAAA==.Daemoni:BAAALgAECgYJCQAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJEgAAAA==.Darkerknight:BAAALgAECgQJBAABLgAECgkJNgAPABIgAA==.Darkprincess:BAAALgAECgUJBQAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgAECgEJAQABLgAECgcJGQALAAAUAA==.Darthbane:BAAALgAECgMJAwAAAA==.Dathguy:BAAALgAECgYJCgABLgAFFAQJFAALAD8iAA==.Davandar:BAAALgADCgkJGgAAAA==.Daveah:BAABLgAECn80AAIHAAkJlBVbJgAoAgAHAAkJlBVbJgAoAgAAAA==.Dazarros:BAACLgAFFH8IAAIXAAMJxA/aFgDVAAAXAAMJxA/aFgDVAAAuAAQKfyMAAhcACQmpFL4yAA0CABcACQmpFL4yAA0CAAAA.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8yAAIXAAkJnxO+BAA9AQAXAAkJnxO+BAA9AQAAAA==.Deathsmoke:BAAALgADCgcJBwAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dekkaa:BAAALgAECgEJAgAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgAECgUJDgAAAA==.Demoncharge:BAAALgAECgQJBAABLgAECgkJEQAWAAAAAA==.Demonclaw:BAAALgAECgEJAgABLgAECgkJEQAWAAAAAA==.Demondrake:BAAALgAECgUJCQABLgAECgkJEQAWAAAAAA==.Demonflayer:BAAALgAECgkJEQAAAA==.Demonikat:BAAALgADCgYJDAAAAA==.Demonsmoke:BAAALgADCgkJCQAAAA==.Demonstalker:BAAALgAECgEJAQABLgAECgkJEQAWAAAAAA==.Denaeaa:BAACLgAFFH8MAAIYAAMJtQvyRgCJAAAYAAMJtQvyRgCJAAAuAAQKfxsAAhgACAkvDCJNADgBABgACAkvDCJNADgBAAEuAAUUBQkcAAcAPgwA.Destroyerman:BAAALgADCgQJBAAAAA==.Devilzkry:BAAALgAECgcJCwAAAA==.Devistaysha:BAABLgAFFH8FAAIHAAIJ9Q1qHgBnAAAHAAIJ9Q1qHgBnAAAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgUJBQABLgAECgcJGQADAGMdAA==.',
Dh='Dharmakat:BAAALgADCgUJBQAAAA==.Dhodge:BAABLgAECn8ZAAIZAAcJGR8SLAAYAgAZAAcJGR8SLAAYAgABLgAFFAMJBgAaAFohAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn84AAICAAkJ0x0hDADLAgACAAkJ0x0hDADLAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJCQAAAA==.',
Do='Dodgehoj:BAAALgAECgMJBAABLgAFFAMJBgAaAFohAA==.Doffyy:BAAALgAECgEJAQAAAA==.Dogbreathrlz:BAAALgAECgEJAQAAAA==.Dokash:BAAALgAECgUJCQABLgAFFAEJAwAWAAAAAA==.Dotexe:BAABLgAECn8fAAIOAAUJLiGPAABwAQAOAAUJLiGPAABwAQAAAA==.Dotsy:BAACLgAFFH8YAAQbAAcJ3xWVBABBAQAbAAUJvxmVBABBAQAXAAQJ5wyBWQAUAQAcAAIJLxUnBwBXAAAuAAQKfy8ABBwACQlNIq4PANMBABwABglDHK4PANMBABcABwnfHsVVAMYBABsABwkhInIKALgBAAAA.',
Dr='Drackarys:BAAALgADCggJFAAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgAECgYJDQAAAA==.Drakiir:BAAALgAECgYJDQABLgAECgcJGQALAAAUAA==.Dralkish:BAACLgAFFH8FAAIGAAMJtQdGfwC3AAAGAAMJtQdGfwC3AAAuAAQKfzgAAgYACQkuEyp0AIYBAAYACQkuEyp0AIYBAAAA.Dramore:BAABLgAECn8kAAIbAAkJzgkpDgB6AQAbAAkJzgkpDgB6AQAAAA==.Drathi:BAAALgADCgcJBwABLgAECgkJMgAGAIQjAA==.Dravas:BAABLgAECn8XAAIKAAYJrQ4HCQCcAAAKAAYJrQ4HCQCcAAAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Drezzo:BAAALgADCgMJAwAAAA==.Droxx:BAABLgAECn8VAAILAAYJCAxgvwD/AAALAAYJCAxgvwD/AAAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drunkash:BAAALgAECgEJAQAAAA==.Dryerbro:BAAALgAECgEJAQAAAA==.Drzark:BAAALgAECgkJEAAAAA==.',
Du='Dumpling:BAAALgADCgEJAQAAAA==.Dundunduns:BAAALgAECgYJBgAAAA==.',
Dw='Dwdog:BAABLgAECn8nAAIbAAkJrxhLBwD+AQAbAAkJrxhLBwD+AQAAAA==.',
['Dà']='Dàthguy:BAACLgAFFH8UAAILAAQJPyLmOACKAQALAAQJPyLmOACKAQAuAAQKf0EAAgsACQnyJU0DAGsDAAsACQnyJU0DAGsDAAAA.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
['Dé']='Défault:BAACLgAFFH8UAAMLAAUJLxSUHgDsAAALAAQJLxSUHgDsAAAMAAEJAABnZwAAAAAuAAQKfycAAwsACQk4IR8LABUDAAsACQk4IR8LABUDAB0ABAmKEqAbAPEAAAAA.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJEgAAAA==.',
El='Elennie:BAAALgAECgYJDQAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elephlock:BAAALgAECgQJBQAAAA==.Elephunch:BAAALgAECgUJBQAAAA==.Elerion:BAABLgAECn8jAAMVAAkJ6hPJGgD5AQAVAAkJ6hPJGgD5AQABAAcJSQnrOAAxAQAAAA==.Elista:BAAALgADCgUJBQABLgADCgQJBAAWAAAAAA==.Elm:BAAALgAECgEJAQAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgIJAgABLgAECgQJBAAWAAAAAA==.Emmi:BAABLgAECn8+AAILAAkJih8GFQDJAgALAAkJih8GFQDJAgAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIGAAcJ/B7jLwBjAgAGAAcJ/B7jLwBjAgAAAA==.Eralis:BAAALgAECgYJBQAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilspawn:BAAALgAECgUJBQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.',
Fa='Faelivrin:BAAALgAECgcJBQAAAA==.Faith:BAAALgADCgYJBgAAAA==.Falcor:BAABLgAECn8eAAMRAAkJDCL+BwD5AgARAAkJwCH+BwD5AgATAAYJXSF4EQDIAQAAAA==.Faloran:BAAALgAECgEJAQAAAA==.Farstad:BAAALgADCgMJAwAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgkJCQAAAA==.Fekk:BAAALgADCgIJAgABLgAECgUJCwAWAAAAAA==.Fenderbender:BAAALgADCgYJBgAAAA==.Feralstorm:BAAALgAECgYJCQAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feykat:BAAALgADCgUJBQAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAABLgAECn85AAIMAAkJ9x3vCACEAgAMAAkJ9x3vCACEAgAAAA==.Fifthelement:BAABLgAECn80AAIHAAkJ0x4XDgDkAgAHAAkJ0x4XDgDkAgAAAA==.Firebunny:BAAALgADCgUJBQAAAA==.',
Fj='Fjalgeirr:BAABLgAECn80AAMeAAkJZxWoFgDSAQAeAAkJZxWoFgDSAQAfAAYJcwqTAgCgAAAAAA==.',
Fl='Fleapaw:BAAALgADCgcJBwAAAA==.Flockling:BAAALgADCgYJBgAAAA==.',
Fo='Foxymomma:BAABLgAECn87AAIUAAkJYyO6AwBOAwAUAAkJYyO6AwBOAwAAAA==.',
Fr='Frey:BAACLgAFFH8WAAILAAYJZB5OSwBcAQALAAYJZB5OSwBcAQAuAAQKfzIAAgsACQllJbMFAEwDAAsACQllJbMFAEwDAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8bAAMbAAkJiCBZAQDjAgAbAAcJ7iRZAQDjAgAXAAYJZxpNtgDaAAAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fulgar:BAAALgAECgQJBgAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.Furryfido:BAAALgADCggJCAABLgAECgkJOQAMAPcdAA==.',
Fw='Fwenwir:BAABLgAECn8aAAQgAAYJFSCWLADKAQAgAAYJfx+WLADKAQAhAAMJvxhLPwDNAAADAAEJ+xhTGQFDAAAAAA==.',
Ga='Galatea:BAAALgAFFAEJAQAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAABLgAECn8pAAIKAAkJ8A2KKwCnAQAKAAkJ8A2KKwCnAQAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJGgABLgAECgkJMQACAE4dAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gidgette:BAAALgAECgYJCwAAAA==.Gilalade:BAABLgAECn89AAIDAAkJFxzdGQCKAgADAAkJFxzdGQCKAgAAAA==.Gingee:BAAALgADCgIJAgAAAA==.',
Gl='Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8oAAILAAgJIggOnQAwAQALAAgJIggOnQAwAQAAAA==.',
Go='Gobann:BAAALgADCggJEAABLgAECgkJIgADAGAcAA==.Gooby:BAAALgAECgQJBAABLgAFFAcJGQACABgVAA==.Gooney:BAAALgAECgIJAwAAAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Greencheese:BAAALgAECgIJAgABLgAECggJGwALABoSAA==.Grimes:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.Grlfriend:BAAALgAECgYJDwAAAA==.Grodin:BAAALgAECgQJCQAAAA==.Grofiest:BAABLgAECn8kAAMBAAkJjBYSFAAuAgABAAkJjBYSFAAuAgAUAAEJjAFWfgAYAAAAAA==.',
Gu='Guggychan:BAACLgAFFH8GAAIaAAMJWiFlIADzAAAaAAMJWiFlIADzAAAuAAQKfzkAAhoACQmGJg8BAGcDABoACQmGJg8BAGcDAAAA.',
['Gô']='Gôö:BAAALgAECgQJDAAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAIQAAkJTw83KwBkAQAQAAkJTw83KwBkAQAAAA==.Haelwyn:BAAALgAECgEJAQABLgAECgEJAwAWAAAAAA==.Hahine:BAAALgAECgEJAQAAAA==.Haldor:BAABLgAECn8jAAIGAAgJewyjdQCPAQAGAAgJewyjdQCPAQAAAA==.Haohmaru:BAABLgAECn8+AAIiAAkJciGuBQDlAgAiAAkJciGuBQDlAgAAAA==.',
He='Healomatic:BAAALgAECgUJBQABLgAECgcJCgAWAAAAAA==.Hecæte:BAAALgADCgYJBgAAAA==.Heella:BAAALgAECgEJAQAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgQJCAAAAA==.Hercgrimx:BAAALgAECgcJDwAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIXAAUJ+RRjjQA+AQAXAAUJ+RRjjQA+AQAAAA==.',
Hi='Him:BAABLgAECn8lAAIjAAkJqBjpEwBMAgAjAAkJqBjpEwBMAgAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.Holyclunge:BAAALgAECgMJAwAAAA==.Holyshocks:BAAALgAECgEJAgAAAA==.',
Hp='Hplaysgames:BAAALgAECgUJCAAAAA==.',
Hu='Huneyhunter:BAABLgAECn8dAAIIAAcJZwsPHwAQAQAIAAcJZwsPHwAQAQAAAA==.',
Ic='Ichigozero:BAAALgADCgkJEQAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
In='Intern:BAACLgAFFH8GAAIUAAIJowuUDABcAAAUAAIJowuUDABcAAAuAAQKfyYABBQACQn+E5AdANgBABQACAlIFZAdANgBABUABQnUCa5fAH8AAAEAAQkAAFWgAAAAAAAA.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgAECgUJBQAAAA==.',
Iz='Iza:BAAALgADCgIJAgAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakethecake:BAAALgAECgQJBAAAAA==.Jaks:BAAALgAECgEJAwAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAABLgAECn8yAAITAAkJnhB9BwDEAQATAAkJnhB9BwDEAQAAAA==.Javeech:BAAALgAECgQJBgAAAA==.',
Jc='Jchaotic:BAAALgAECggJDwAAAA==.',
Je='Jeezus:BAAALgADCgYJCgABLgAFFAUJHwALAFEiAA==.',
Jo='Jocie:BAAALgAECgEJAQAAAA==.Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwAWAAAAAA==.Jongsoo:BAAALgAECgcJCAAAAA==.Jovero:BAAALgAECgQJBQAAAA==.',
Ju='Junghee:BAAALgADCgIJAgAAAA==.Jutas:BAABLgAECn8cAAMVAAgJdgvPLQBsAQAVAAgJdgvPLQBsAQABAAcJwAMtWQCwAAAAAA==.Juudaz:BAACLgAFFH8fAAMLAAUJUSJXDwBXAQALAAQJhyBXDwBXAQAMAAQJlh8lGwAOAQAuAAQKf1UABAsACQlmJc8DAGQDAAsACQlmJc8DAGQDAAwABwm3IbEOACACAB0AAwksC7IEAGgAAAAA.',
Jv='Jvicious:BAAALgAECgcJCgAAAA==.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAABLgAECn8+AAMCAAkJ0CGCBQA6AwACAAkJ0CGCBQA6AwAGAAUJMxdtnAA9AQAAAA==.Kaliista:BAAALgAECgEJAQABLgAECgkJIQAEAHwXAA==.Kallan:BAAALgAECgUJDAAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kapkywa:BAACLgAFFH8GAAIEAAMJOxf4NADZAAAEAAMJOxf4NADZAAAuAAQKfxQAAgQACAnfIe0LAAEDAAQACAnfIe0LAAEDAAAA.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.Katsumyo:BAAALgAECgMJAwAAAA==.',
Ke='Keggz:BAAALgAECgEJAQAAAA==.Kegpoker:BAAALgAECgcJEgAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgUJCAAWAAAAAA==.',
Kh='Khaalzantro:BAAALgAECgIJAgAAAA==.',
Ki='Kilra:BAAALgAECgUJCwAAAA==.Kimbaltina:BAAALgADCgkJGQABLgAECgkJNQAIAFsaAA==.Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJEwAAAA==.Kindasmall:BAAALgAECgkJAQAAAA==.Kiyara:BAABLgAECn9HAAIDAAkJvBaiLgAiAgADAAkJvBaiLgAiAgAAAA==.Kizaki:BAAALgADCgkJDgABLgAECggJFwACAP8SAA==.',
Kn='Knownn:BAAALgAECgIJAgAAAA==.Knowoone:BAABLgAECn9TAAIEAAkJHBlrFgCUAgAEAAkJHBlrFgCUAgAAAA==.Knowwn:BAAALgADCgEJAQAAAA==.',
Ko='Komonaut:BAABLgAECn8ZAAMfAAYJDgvTAgCMAAAfAAYJWQrTAgCMAAAZAAMJigiW4gByAAAAAA==.Koscihardt:BAABLgAECn8VAAIPAAcJcwZM0gDuAAAPAAcJcwZM0gDuAAAAAA==.Kouelwhip:BAAALgAECgEJAQABLgAECgcJGQALAAAUAA==.',
Kr='Krakin:BAAALgAECgYJBgAAAA==.Krelliz:BAABLgAECn8cAAIHAAcJTRDiZgAnAQAHAAcJTRDiZgAnAQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAABLgAECn8hAAIPAAgJGQv9sAAgAQAPAAgJGQv9sAAgAQAAAA==.Kronnk:BAAALgAECgEJAQAAAA==.Krystar:BAAALgAECgUJDgAAAA==.',
Ku='Kulfig:BAAALgAECgkJEQAAAA==.Kumen:BAABLgAECn8iAAQkAAkJISD7EwAzAgAkAAgJjx37EwAzAgAIAAUJfh71FwBTAQAJAAUJUxakLgDzAAAAAA==.Kungfuwho:BAACLgAFFH8RAAMQAAQJbxBzGgD1AAAQAAQJbxBzGgD1AAAYAAQJ/QNBQQCeAAAuAAQKfzYAAxAACQlZGQwfALUBABAACAkpGQwfALUBABgACAk6C1NNADgBAAAA.Kutyou:BAAALgADCgkJJQAAAA==.',
Ky='Kynlailia:BAAALgADCgQJBAAAAA==.',
['Kó']='Kóólaid:BAAALgAECgIJAgAAAA==.',
['Kû']='Kûnei:BAAALgAECgQJBwAAAA==.',
La='Laladin:BAAALgAECgMJAwAAAA==.Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lemonlime:BAAALgAFFAIJAgAAAA==.Lenaea:BAACLgAFFH8cAAIHAAUJPgykMAAfAQAHAAUJPgykMAAfAQAuAAQKfyUAAgcACQnwGKEtAAACAAcACQnwGKEtAAACAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAACLgAFFH8OAAICAAQJKg5NKQDbAAACAAQJKg5NKQDbAAAuAAQKfycAAgIACAkAFZAnAM4BAAIACAkAFZAnAM4BAAAA.Liiege:BAABLgAECn8ZAAMLAAcJABRqcwB9AQALAAcJABRqcwB9AQAMAAIJwg+GPABiAAAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Linlithyr:BAAALgAECgIJAgABLgAFFAMJCgAMAGgXAA==.Litesuprmcst:BAAALgAECgQJBQAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJCAAAAA==.',
Lo='Lobø:BAABLgAECn8nAAIDAAkJRxjaLAApAgADAAkJRxjaLAApAgAAAA==.Loganx:BAAALgAECgUJCAABLgAECgcJCwAWAAAAAA==.Lorsie:BAAALgADCggJCAABLgAECgkJKAAGAGINAA==.Loxen:BAAALgAECgEJAQAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn8/AAILAAkJUQsaZACfAQALAAkJUQsaZACfAQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgUJCAAAAA==.Lutherisch:BAAALgAECgUJBQABLgAECgUJCAAWAAAAAA==.Lux:BAAALgAECgQJBAAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgAECgQJBAAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAABLgAECn8oAAIPAAgJ6wjlmQBFAQAPAAgJ6wjlmQBFAQAAAA==.Mageairena:BAAALgAECgEJAQAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgAECgIJBQAAAA==.Magnues:BAAALgADCgQJBAAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAABLgAECn8XAAIEAAgJEx9kAQALAgAEAAgJEx9kAQALAgAAAA==.Manatease:BAAALgAECgEJAQAAAA==.Manatee:BAAALgAECgYJDQAAAA==.Mannan:BAAALgADCgIJAgAAAA==.Marlasinger:BAAALgAECgQJBAAAAA==.Marpesia:BAAALgAECgcJCgAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Marteris:BAAALgAECgEJAgAAAA==.Maygwyn:BAABLgAECn8sAAIPAAkJUQlKBgBcAQAPAAkJUQlKBgBcAQAAAA==.',
Me='Meatlovers:BAAALgAECgEJAQAAAA==.Mediva:BAAALgAECgUJEQAAAA==.Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgYJDwAAAA==.Megaera:BAACLgAFFH8GAAIZAAMJwhvOIwCxAAAZAAMJwhvOIwCxAAAuAAQKfx4AAxkACQnuIPMOAAcDABkACQnuIPMOAAcDAB4AAQkeGBZsADoAAAAA.Melar:BAACLgAFFH8FAAIlAAIJkQJlDQBYAAAlAAIJkQJlDQBYAAAuAAQKfywAAwoACQnwDq8zAHwBAAoACAkUEK8zAHwBACUAAwktCjAFAH4AAAAA.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.Messyah:BAAALgAFFAIJAwAAAA==.',
Mi='Migmong:BAAALgAECgIJBQAAAA==.Mihawk:BAAALgAECgQJBwAAAA==.Milwaukee:BAAALgAECgEJAQAAAA==.Minjae:BAABLgAECn8aAAMXAAgJZBQIcQBYAQAXAAgJ7RMIcQBYAQAbAAEJ/hBIPgA1AAABLgAFFAQJCQAXACcRAA==.Minseo:BAAALgAECgEJAwAAAA==.Miserain:BAAALgAECgUJEQAAAA==.Mistbehaving:BAAALgAECgQJBAAAAA==.',
Mo='Moondemon:BAAALgAECgUJBQAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Moozart:BAAALgADCgEJAQAAAA==.Morphumbra:BAAALgAECgUJBQAAAA==.Morrìgan:BAABLgAECn8ZAAMXAAcJ3QWOswDeAAAXAAcJ3QWOswDeAAAcAAIJqwOUYgBJAAAAAA==.Morvane:BAAALgAECgQJBAABLgAECgkJMQACAE4dAA==.Mothra:BAAALgAECgQJCQABLgAFFAQJBgAHAKMWAA==.Movack:BAABLgAECn8rAAIGAAkJpg4VZQClAQAGAAkJpg4VZQClAQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.Mozwangsung:BAAALgADCgYJBwAAAA==.',
Mu='Muncha:BAAALgAECgEJAgAAAA==.Murderface:BAABLgAECn8qAAMkAAkJ7BV3GwDvAQAkAAkJ7BV3GwDvAQAEAAcJpBZ3UABNAQAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAABLgAECn8bAAIcAAkJgQohEQAzAQAcAAkJgQohEQAzAQAAAA==.Mythunran:BAABLgAECn8rAAIgAAgJJhMDDwBtAQAgAAgJJhMDDwBtAQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJEgAWAAAAAA==.Natash:BAAALgAECgEJAgAAAA==.Nau:BAAALgAECgUJBQAAAA==.Nawas:BAAALgAECgEJAgAAAA==.Nax:BAAALgAECgQJBQAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAgABLgAECgUJBwAWAAAAAA==.Nerfhammer:BAACLgAFFH8RAAIGAAUJXxpsJQBzAQAGAAUJXxpsJQBzAQAuAAQKfyoAAgYACQlLIwkcAMICAAYACQlLIwkcAMICAAAA.Nessalove:BAACLgAFFH8aAAIUAAcJ7g+4DQBwAQAUAAcJ7g+4DQBwAQAuAAQKfysAAhQACQmUHTgMAI8CABQACQmUHTgMAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8eAAQRAAkJjw2ROgBBAQARAAcJAQ6ROgBBAQASAAYJJxEmHwD+AAATAAEJxANIQgArAAAAAA==.Nipao:BAABLgAECn8eAAIYAAgJGR66AACrAgAYAAgJGR66AACrAgAAAA==.Niron:BAAALgAECgUJBwAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAABLgAFFH8OAAIYAAMJPRMVOwC5AAAYAAMJPRMVOwC5AAABLgAFFAkJMwAPAOwiAA==.Noriel:BAABLgAECn8UAAIPAAkJlw8GXwDCAQAPAAkJlw8GXwDCAQAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAABLgAECn8UAAIDAAcJNREzbABpAQADAAcJNREzbABpAQAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Og='Ognyal:BAAALgAECgkJBQAAAA==.',
Oh='Ohtani:BAAALgAECgkJDgAAAA==.',
Ol='Olanali:BAAALgAECgEJAwABLgAECgEJAwAWAAAAAA==.Olectria:BAAALgADCgEJAQAAAA==.',
On='Onna:BAAALgADCgIJAgAAAA==.',
Oo='Ooblitoon:BAABLgAECn9QAAITAAkJghO7BQD/AQATAAkJghO7BQD/AQAAAA==.',
Op='Opali:BAAALgAECgEJAQAAAA==.',
Or='Orfantal:BAABLgAECn8hAAIDAAkJExIjSwDAAQADAAkJExIjSwDAAQAAAA==.Oridan:BAAALgAECgEJAQAAAA==.Oridon:BAAALgAECgQJDAAAAA==.',
Ou='Ouahoahoah:BAAALgAFFAEJAQAAAA==.',
Ov='Oven:BAAALgAECgUJBQABLgAFFAQJFAALAD8iAA==.Overcast:BAAALgAECgYJEAAAAA==.Overshoot:BAABLgAECn8aAAMDAAkJlgzWTwCzAQADAAkJlgzWTwCzAQAhAAIJXgRKVgBUAAAAAA==.',
Ow='Owyyn:BAAALgADCggJCAAAAA==.',
Ox='Oxen:BAAALgAECgYJCgAAAA==.',
Pa='Pallyairena:BAAALgADCgQJBAAAAA==.Panterion:BAABLgAECn8hAAIEAAkJfBeXJQAgAgAEAAkJfBeXJQAgAgAAAA==.Parvarti:BAABLgAECn8gAAMcAAkJDQjDGADcAAAcAAcJBQnDGADcAAAXAAIJJgWUGAFPAAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECgkJGQALAAYdAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Persimmoñ:BAABLgAECn83AAIGAAkJqRAGCQAYAQAGAAkJqRAGCQAYAQAAAA==.Petthemonk:BAAALgAECgEJAQAAAA==.',
Ph='Phaelissia:BAAALgAECgYJDwAAAA==.Philljr:BAAALgADCgMJAwAAAA==.',
Pi='Pinero:BAAALgADCgYJCQAAAA==.',
Pl='Plaugus:BAAALgAECgUJEQAAAA==.',
Po='Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgcJEQAAAA==.Prost:BAABLgAECn8gAAIPAAkJlxxfRQALAgAPAAkJlxxfRQALAgAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Pu='Puppybreath:BAAALgAECgEJAQAAAA==.Purdy:BAAALgAECgkJAgAAAA==.',
Py='Pyroblast:BAACLgAFFH8WAAMPAAcJDBm5PQB2AQAPAAYJtxi5PQB2AQAmAAEJthqpAQBeAAAuAAQKfzwAAw8ACQleITcSAO0CAA8ACQmWIDcSAO0CACYAAwkGI34HADUBAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Raedon:BAAALgAECgUJBQAAAA==.Ralie:BAAALgAECgEJAQAAAA==.Ravage:BAAALgAECgUJBwAAAA==.',
Re='Relaceara:BAABLgAECn8WAAIGAAkJswVbqQApAQAGAAkJswVbqQApAQAAAA==.Reladin:BAABLgAECn8+AAIFAAkJuQqwGgBDAQAFAAkJuQqwGgBDAQAAAA==.Relanna:BAABLgAECn8WAAILAAYJjAfh6wDFAAALAAYJjAfh6wDFAAAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCggJIwAAAA==.Rendstein:BAABLgAECn8jAAIMAAkJhhjIEQDxAQAMAAkJhhjIEQDxAQAAAA==.Renzr:BAACLgAFFH8RAAMLAAQJ9hyVFgAbAQALAAQJ9hyVFgAbAQAMAAEJzRB8EwBGAAAuAAQKf0wAAwsACQl6JTUWAMICAAsACQnjJDUWAMICAAwACAklI4cHAKICAAAA.Reqquuiiem:BAAALgADCgUJCAAAAA==.Respcct:BAAALgADCgkJGgABLgAECgkJOAACANMdAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAABLgAECn8UAAIEAAkJMQ/IRQB5AQAEAAkJMQ/IRQB5AQAAAA==.Rowin:BAABLgAECn8XAAMEAAkJuQh0ZgABAQAEAAkJuQh0ZgABAQAkAAMJzQfmbABwAAAAAA==.Royal:BAAALgAECgEJAQAAAA==.',
Ru='Rupy:BAAALgAECgEJAQAAAA==.Rustedroots:BAABLgAECn81AAMEAAkJPhgVGwBtAgAEAAkJPhgVGwBtAgAIAAUJNxXFAQAlAQAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Sailley:BAAALgAECgUJDgAAAA==.Saltgrizzny:BAAALgAECgcJDQAAAA==.Sapphyre:BAAALgAECgEJAgAAAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAABLgAECn8eAAIgAAkJfRQVCwC5AQAgAAkJfRQVCwC5AQAAAA==.Sarnara:BAABLgAECn8sAAIFAAkJiBp3CQA4AgAFAAkJiBp3CQA4AgAAAA==.Savageclaw:BAAALgAECggJCQAAAA==.Savagehunt:BAAALgAFFAEJAQAAAA==.Savagekegs:BAABLgAECn8VAAMiAAYJ7SD8OABmAQAiAAQJZSP8OABmAQAQAAUJQhhUPQAmAQABLgAFFAEJAQAWAAAAAA==.Savagelight:BAAALgAFFAEJAQABLgAFFAEJAQAWAAAAAA==.Savagex:BAAALgAECgEJAQAAAA==.Sazayaki:BAAALgADCgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAABLgAECn8oAAIDAAkJ9wOLEgCoAAADAAkJ9wOLEgCoAAAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgAECgEJAQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Senarx:BAAALgAECgIJBAAAAA==.Sereniity:BAABLgAECn8WAAQiAAcJ3SFVGwDKAQAiAAYJLiJVGwDKAQAYAAUJYRifMQAxAQAQAAIJeRteYACZAAABLgAECgcJGQALAAAUAA==.',
Sh='Shakastraza:BAAALgAECgEJAQAAAA==.Shamalicous:BAABLgAECn8UAAMHAAUJAgLirABvAAAHAAUJAgLirABvAAAjAAQJ+wXvggBqAAAAAA==.Shamjam:BAABLgAECn8jAAIHAAgJ+BEwPAC+AQAHAAgJ+BEwPAC+AQAAAA==.Shamous:BAAALgAECgUJCAAAAA==.Shampayne:BAAALgADCgYJBgABLgAFFAUJHwALAFEiAA==.Shanthe:BAAALgAECgYJEQABLgAFFAMJCAANAPgaAA==.Sharku:BAACLgAFFH8WAAIPAAUJwxffGwDyAAAPAAUJwxffGwDyAAAuAAQKfy4AAg8ACQkvIJYWANICAA8ACQkvIJYWANICAAAA.Shegothalf:BAAALgAECgUJBgAAAA==.Shortwide:BAAALgADCgIJAgAAAA==.Shãdo:BAAALgAECgYJCAAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAECgkJHgARAAwiAA==.Siinep:BAAALgAECgcJEAAAAA==.Sintan:BAAALgAECgYJBgAAAA==.Sistersledge:BAAALgADCgkJCgAAAA==.',
Sk='Skey:BAAALgAECgIJAgAAAA==.Skibblé:BAABLgAECn8aAAIcAAkJCw8ADAB/AQAcAAkJCw8ADAB/AQAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAABLgAECn8ZAAIEAAkJXxdpKAAOAgAEAAkJXxdpKAAOAgAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIZAAgJrSGCEgDrAgAZAAgJrSGCEgDrAgAAAA==.Smokeofsteel:BAAALgAECgIJAgAAAA==.Smokeyjr:BAAALgADCgcJBwAAAA==.',
Sn='Sneakyboi:BAABLgAECn8uAAIOAAkJZRq/BABBAgAOAAkJZRq/BABBAgAAAA==.Snippin:BAAALgAECgIJAgAAAA==.',
So='Soléne:BAABLgAECn8gAAMHAAgJOh2gHgBZAgAHAAcJsB2gHgBZAgAjAAUJyRAAWgDWAAABLgAFFAQJCQAXAK0PAA==.Sorden:BAAALgAECgQJBgABLgAFFAIJAgAWAAAAAA==.',
Sp='Spiced:BAABLgAECn8ZAAIkAAgJSCC0DQDAAgAkAAgJSCC0DQDAAgABLgAECgkJGwAbAIggAA==.Spliff:BAAALgAECgIJAgAAAA==.',
Sq='Squirt:BAABLgAECn8aAAISAAgJvQ88GgC6AQASAAgJvQ88GgC6AQAAAA==.',
Ss='Ssks:BAAALgAFFAEJAQABLgAECgMJCwAWAAAAAA==.',
St='Stabsmcshank:BAACLgAFFH8TAAINAAQJXxH3GwA7AQANAAQJXxH3GwA7AQAuAAQKfzQAAg0ACQkwGdgBAGABAA0ACQkwGdgBAGABAAAA.Starbux:BAACLgAFFH8HAAIVAAIJ/Aa4FABmAAAVAAIJ/Aa4FABmAAAuAAQKfykABBUACAmCEGUuAGgBABUACAlWDmUuAGgBAAEABgm8B8hQAM4AABQABQkQDz9aAMsAAAAA.Starmagic:BAAALgAECgkJBgAAAA==.Steakx:BAAALgAECgQJBwAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Suriel:BAABLgAECn8cAAIMAAkJpA8zIQBJAQAMAAkJpA8zIQBJAQAAAA==.Suumcuique:BAAALgAECgIJAgABLgAECgkJKgAkAOwVAA==.',
Sv='Svenya:BAABLgAECn8dAAMkAAkJ7Q1OOwAkAQAkAAgJbAtOOwAkAQAEAAYJ2gbphACuAAAAAA==.',
Sy='Syenna:BAAALgAECgEJAQAAAA==.Sygne:BAAALgAECgYJCwAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAABLgAECn81AAIDAAkJgRKPPADuAQADAAkJgRKPPADuAQAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJCAABLgAFFAQJBgAHAKMWAA==.',
['Sï']='Sïenna:BAABLgAECn8UAAILAAkJvBQeQwD5AQALAAkJvBQeQwD5AQAAAA==.',
Ta='Taggy:BAABLgAECn8rAAIOAAgJaQ8tCwB/AQAOAAgJaQ8tCwB/AQABLgAECgkJNQAIAFsaAA==.Taln:BAAALgAECgEJAgAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Tassandie:BAAALgAECgQJBAABLgAECgkJIQAEAHwXAA==.Tayebeh:BAAALgAECgQJBAAAAA==.',
Te='Terran:BAAALgAECgUJDwAAAA==.Texhd:BAAALgAECgYJBgABLgAFFAEJAQAWAAAAAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.Thansus:BAAALgAECgEJAQAAAA==.Theçølletør:BAAALgAECgMJAwAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.Tinygibbs:BAAALgAECgMJBAAAAA==.Tionie:BAAALgADCgIJAgAAAA==.',
To='Toiletnuker:BAABLgAECn8lAAQhAAkJCA9FHgCqAQAhAAkJYw5FHgCqAQADAAYJug1LoAABAQAgAAEJRApEQQAoAAABLgAECgkJOAACANMdAA==.Tokyojoe:BAABLgAECn8iAAIZAAkJtBSrOQDgAQAZAAkJtBSrOQDgAQAAAA==.Tolsanah:BAABLgAFFH8PAAIYAAcJ9xJsEgD3AQAYAAcJ9xJsEgD3AQABLgAFFAkJOgASAPEeAA==.Torocious:BAAALgAECgYJDQAAAA==.Torrick:BAABLgAECn8yAAQGAAkJhCPSBwAuAwAGAAkJhCPSBwAuAwACAAYJBRcRNwCfAQAFAAEJwxRjQwAwAAAAAA==.Torrickgreed:BAAALgADCgYJBgABLgAECgkJMgAGAIQjAA==.Totemtot:BAABLgAECn85AAInAAkJlQjFAgDgAAAnAAkJlQjFAgDgAAAAAA==.Toupee:BAAALgAECgUJBgAAAA==.',
Tr='Tradrivia:BAAALgAECgcJCQAAAA==.Tronly:BAAALgADCgUJBQAAAA==.Trukait:BAAALgAECgEJAQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Tw='Twinkish:BAAALgAECgEJAQAAAA==.',
Ty='Tyllivan:BAAALgADCgcJDgAAAA==.',
['Tá']='Tálise:BAAALgAECgEJAQAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCgAAAA==.',
Uf='Uffizzle:BAAALgAECgUJCwAAAA==.',
Ul='Ulf:BAABLgAECn8nAAIHAAgJMBnOHQBfAgAHAAgJMBnOHQBfAgAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Uu='Uurgeorn:BAEALgADCgEJAQAAAA==.',
Va='Valquirie:BAACLgAFFH8KAAIMAAMJaBeVJADKAAAMAAMJaBeVJADKAAAuAAQKf0QAAgwACQk/IX0EAOsCAAwACQk/IX0EAOsCAAAA.Valyrius:BAAALgADCggJCQABLgAECgYJBgAWAAAAAA==.Varlamor:BAABLgAECn8VAAMUAAgJlwvvMABJAQAUAAgJlwvvMABJAQABAAUJYQTvYwCLAAAAAA==.Varolokiir:BAAALgAECgEJAgABLgAECgcJGQALAAAUAA==.Vathraen:BAAALgAECgMJBgAAAA==.',
Ve='Velanistra:BAABLgAECn8oAAIGAAkJYg05bQCUAQAGAAkJYg05bQCUAQAAAA==.Velanya:BAAALgAECgIJAgAAAA==.Velnia:BAAALgAECgcJBwAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAABLgAECn8oAAIeAAkJFBH1GwCeAQAeAAkJFBH1GwCeAQAAAA==.Very:BAAALgAECgUJDgAAAA==.',
Vg='Vgerr:BAABLgAECn8WAAIGAAkJAgyWawCXAQAGAAkJAgyWawCXAQAAAA==.',
Vi='Viashino:BAAALgAECgUJBgABLgAECgYJEAAWAAAAAA==.Vidarus:BAAALgAFFAIJAwABLgAFFAUJEQAGAF8aAA==.Viridian:BAAALgAECgMJBgABLgAFFAMJBgAZAMIbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAABLgAECn8iAAMDAAkJYBw3LgAkAgADAAcJ/Rw3LgAkAgAgAAYJlBfmGADpAAAAAA==.Vorron:BAAALgADCgEJAQABLgAFFAMJBgAEADsXAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAABLgAECn8VAAMZAAkJYg98qwDPAAAZAAgJaQ58qwDPAAAeAAIJ4xFRUAB2AAAAAA==.Vynos:BAABLgAECn8hAAIXAAgJQgfYjwAbAQAXAAgJQgfYjwAbAQAAAA==.Vysant:BAAALgADCgQJBgABLgAECggJIQAXAEIHAA==.',
['Vä']='Väl:BAAALgAECgQJCAAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAACLgAFFH8GAAMHAAQJoxYgMwAVAQAHAAQJoxYgMwAVAQAjAAEJRwN1XwAuAAAuAAQKfyQAAwcACQm7EbE1ANoBAAcACQm7EbE1ANoBACMABwn2E7U6AEsBAAAA.',
Wc='Wchaos:BAAALgAECgUJBwAAAA==.',
We='Welker:BAAALgADCgQJCAABLgAFFAMJCAALAKAQAA==.Welkerdk:BAACLgAFFH8IAAILAAMJoBCIpQDPAAALAAMJoBCIpQDPAAAuAAQKfzIAAgsACQlJIG8YALQCAAsACQlJIG8YALQCAAAA.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgAZAMIbAA==.',
Wh='Whiskeycakes:BAAALgAECgQJBgABLgAECgQJBgAWAAAAAA==.',
Wi='Wiglet:BAAALgADCgEJAQAAAA==.Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.Windeyaho:BAAALgAECggJCgAAAA==.',
Wo='Wolfman:BAABLgAECn8jAAIiAAkJlgshJQCEAQAiAAkJlgshJQCEAQAAAA==.Woökie:BAAALgADCgYJBgAAAA==.',
Xa='Xalidan:BAAALgAFFAIJAgAAAA==.',
Xt='Xten:BAABLgAECn8cAAIEAAkJshSCOAC0AQAEAAkJshSCOAC0AQAAAA==.',
Ya='Yamedvedko:BAAALgAECgcJBwAAAA==.Yamzofsteel:BAAALgAECgEJAQAAAA==.Yath:BAAALgAECgMJAwAAAA==.',
Ye='Yeat:BAAALgAECgUJCwAAAA==.',
Yo='Yoatanius:BAAALgAECgEJAQAAAA==.Yoshinox:BAAALgAECgMJBAAAAA==.',
Yr='Yrelle:BAAALgADCgkJEQABLgAECgkJGAABAJELAA==.',
Za='Zalazam:BAABLgAECn8iAAMjAAkJPBxHEwBTAgAjAAkJPBxHEwBTAgAHAAEJjhmvwwBMAAAAAA==.Zalth:BAABLgAECn8kAAIPAAkJ0g2WaQCpAQAPAAkJ0g2WaQCpAQAAAA==.',
Ze='Zelliph:BAAALgAECgUJDgAAAA==.Zenagdrina:BAABLgAECn8YAAMhAAgJ7AXAMwASAQAhAAgJIQXAMwASAQADAAIJBAahJgE6AAAAAA==.Zenobiå:BAABLgAECn8WAAMjAAgJmA4KNwBdAQAjAAgJmA4KNwBdAQAHAAEJqgYK8QAgAAAAAA==.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.',
Zh='Zhaann:BAABLgAECn8YAAMBAAkJkQvhPwARAQABAAcJCg7hPwARAQAVAAMJtQh+bQBQAAAAAA==.Zhaida:BAAALgADCgIJAgAAAA==.',
Zo='Zokor:BAAALgADCgkJQwAAAA==.Zorach:BAAALgAECgYJDwAAAA==.',
['Zá']='Zárá:BAABLgAECn88AAIPAAkJUhltBQB9AQAPAAkJUhltBQB9AQAAAA==.',
['Ðz']='Ðz:BAAALgAFFAEJAQABLgAFFAMJCwAkAIQPAA==.',
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
