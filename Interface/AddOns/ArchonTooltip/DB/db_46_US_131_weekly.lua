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
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-06-06',data={Ad='Ader:BAAALgADCgkJDQAAAA==.Advîl:BAAALgAECgQJBAAAAA==.',
Ae='Aeryhnn:BAAALgADCgkJKAABLgAECgcJFgABAJ8MAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAABLgAECn8hAAICAAYJhxa1NwBjAQACAAYJhxa1NwBjAQAAAA==.Albinodwarf:BAAALgAECgIJAwAAAA==.Alexandre:BAABLgAECn8hAAIDAAkJyhRlLwATAgADAAkJyhRlLwATAgAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAABLgAECn8XAAIEAAYJuA8xWgAfAQAEAAYJuA8xWgAfAQAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAABLgAECn8sAAQCAAkJ/BlkDgCjAgACAAkJ/BlkDgCjAgAFAAMJ3QMNQgBOAAAGAAEJRgcgngEoAAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJBgAAAA==.Ansuz:BAAALgAECgEJAQAAAA==.',
Ap='Aphroditee:BAAALgAECgIJAwAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgQJAwAAAA==.',
Aq='Aquafresh:BAABLgAECn82AAIHAAkJqh1yEQC3AgAHAAkJqh1yEQC3AgAAAA==.',
Ar='Archèrdayne:BAAALgAFFAEJAgAAAA==.Arisel:BAABLgAECn8xAAMIAAgJihkhCgAPAgAIAAgJihkhCgAPAgAJAAUJpxAFHwCoAAAAAA==.Aristia:BAAALgAECgUJDQABLgAFFAMJCQAKAN0NAA==.Artemisiah:BAAALgAECgEJAQAAAA==.Arweni:BAABLgAECn8zAAILAAgJYhlbHgD1AQALAAgJYhlbHgD1AQAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashcheeks:BAAALgAECgEJAQAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8gAAICAAgJECRDCADqAgACAAgJECRDCADqAgAAAA==.',
Av='Avlynn:BAAALgADCgMJAwABLgAFFAUJGgAHAD4MAA==.Avoidme:BAAALgADCgkJEQABLgAECgkJNwACANMdAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAAALgAECgYJDQABLgAECgkJNwACANMdAA==.Baridyn:BAAALgADCgMJBgAAAA==.Bariir:BAAALgAECgQJBQABLgAECgcJGQAMAAAUAA==.',
Be='Bearbacked:BAAALgAECgQJBgAAAA==.Bearlytankin:BAAALgADCgkJCQAAAA==.Bearscat:BAAALgADCgUJBQAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Beerus:BAAALgAECgMJAwAAAA==.Belagrip:BAAALgAECgMJBAABLgAECgcJFgAGAKQGAA==.Belashar:BAABLgAECn8WAAIGAAcJpAaXyQDvAAAGAAcJpAaXyQDvAAAAAA==.Belawar:BAAALgADCggJFgABLgAECgcJFgAGAKQGAA==.Beleron:BAAALgADCgMJAwAAAA==.Belinna:BAAALgAECgkJBwAAAA==.Beytuha:BAABLgAECn8mAAIJAAkJNSXjAABaAwAJAAkJNSXjAABaAwAAAA==.',
Bi='Bigtim:BAAALgAECgYJDQAAAA==.Bigworm:BAAALgADCgYJBgAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAABLgAECn8hAAMMAAgJLR8kLQBCAgAMAAgJLR8kLQBCAgANAAQJLBXgLQDjAAAAAA==.Blackknife:BAABLgAECn8uAAMOAAgJih5GEQATAgAOAAgJih5GEQATAgAPAAEJGAmFJwAvAAAAAA==.Bladestorm:BAAALgAECgMJBAABLgAECgcJGQAMAAAUAA==.Blakylightz:BAACLgAFFH8HAAIFAAMJyhmHCADgAAAFAAMJyhmHCADgAAAuAAQKfx8AAwUACAnHGgQJAEYCAAUACAnHGgQJAEYCAAYABglzCXm6ABEBAAEuAAUUCAkpAAkA0CAA.Blinker:BAABLgAECn8sAAIQAAgJxw0/gQBvAQAQAAgJxw0/gQBvAQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAYJFQAQALcYAA==.Blueberriess:BAAALgAECgEJAQAAAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJEwABLgAFFAYJGAAEAE8IAA==.Bobbidyboo:BAACLgAFFH8YAAIEAAYJTwi6HQBcAQAEAAYJTwi6HQBcAQAuAAQKfy0AAgQACQlsFao2AM0BAAQACQlsFao2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJDgAAAA==.Boomboompowa:BAAALgADCgYJBgAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJEgAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAAALgAECgYJEgAAAA==.Brixtia:BAAALgAECgEJAQABLgAECggJHQADAOUbAA==.Brovar:BAACLgAFFH8UAAIGAAUJIh0wNgAwAQAGAAUJIh0wNgAwAQAuAAQKfyoAAwYACAm1I3UaAMoCAAYACAm1I3UaAMoCAAIABQlcCu1zAKwAAAAA.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAACLgAFFH8MAAIRAAMJ/gzVPwC4AAARAAMJ/gzVPwC4AAAuAAQKfyIABBEACAkREZIuAHUBABEACAkREZIuAHUBABIABAnxB507AI4AABMAAQnDA31DACgAAAAA.Bubblez:BAAALgAECgUJDwAAAA==.Buddydaelf:BAABLgAECn8qAAIDAAgJfxw+MQAMAgADAAgJfxw+MQAMAgAAAA==.Bueskytter:BAAALgADCgEJAQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
Bw='Bwonshlongdi:BAAALgADCgcJBwAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Calithe:BAAALgAECgYJBgAAAA==.Cambey:BAAALgAECgIJAgAAAA==.Candyman:BAAALgADCgYJDgAAAA==.Caprisan:BAAALgAECgQJBAABLgAECggJHAAGAD8aAA==.Castro:BAAALgADCgQJBAAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.Ceodochatos:BAAALgAECgIJAgABLgAECgkJJwAFAFMaAA==.',
Ch='Chals:BAACLgAFFH8RAAMUAAQJhCH+CwBxAQAUAAQJhCH+CwBxAQAVAAIJsA1IOACAAAAuAAQKfxgAAxQACQn6HCgOAHkCABQACQnyHCgOAHkCABUAAwkVGbA5ANkAAAEuAAUUBAkRABQAhCEA.Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Charfig:BAAALgADCgYJBgAAAA==.Chillfang:BAACLgAFFH8HAAMMAAMJfQ0I1QCFAAAMAAIJfQ0I1QCFAAANAAEJAADsXQAAAAAuAAQKfykAAgwACQm9HiMrAEwCAAwACQm9HiMrAEwCAAAA.Chune:BAAALgAECgQJEgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAAALgAECggJCQAAAA==.Clairvoyant:BAAALgAECgEJAQAAAA==.',
Co='Connor:BAABLgAECn8tAAMVAAkJChp6DACaAgAVAAkJChp6DACaAgAUAAEJgxeSZgA7AAAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgcJEQAAAA==.',
Cr='Cracken:BAAALgADCgcJCAAAAA==.Cretinboy:BAAALgAECgMJAwAAAA==.Crosshair:BAAALgAECgQJDAAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgAECgQJBQAWAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCQAAAA==.',
Da='Daciansniper:BAAALgAECgUJBQAAAA==.Dacianwolf:BAAALgAECgcJBAAAAA==.Daemoni:BAAALgAECgYJCQAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJEgAAAA==.Darkerknight:BAAALgAECgQJBAABLgAECgkJNgAQABIgAA==.Darkprincess:BAAALgAECgUJBQAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgADCgcJDQABLgAECgcJGQAMAAAUAA==.Dathguy:BAAALgAECgYJBgABLgAFFAQJEQAMAD8iAA==.Davandar:BAAALgADCgkJGgAAAA==.Daveah:BAABLgAECn8wAAIHAAgJ9xVTKgAEAgAHAAgJ9xVTKgAEAgAAAA==.Dazarros:BAABLgAECn8jAAIXAAkJqRTELwAUAgAXAAkJqRTELwAUAgAAAA==.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8oAAIXAAgJxRHgVwCQAQAXAAgJxRHgVwCQAQAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dekkaa:BAAALgAECgEJAQAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgAECgUJCwAAAA==.Demoncharge:BAAALgAECgQJBAABLgAECggJEAAWAAAAAA==.Demonclaw:BAAALgADCgMJAwABLgAECggJEAAWAAAAAA==.Demondrake:BAAALgAECgUJCQABLgAECggJEAAWAAAAAA==.Demonflayer:BAAALgAECggJEAAAAA==.Demonicow:BAAALgAECgcJDwAAAA==.Demonikat:BAAALgADCgYJDAAAAA==.Demonstalker:BAAALgAECgEJAQABLgAECggJEAAWAAAAAA==.Denaeaa:BAACLgAFFH8KAAIYAAMJ9QfQPwCDAAAYAAMJ9QfQPwCDAAAuAAQKfxsAAhgACAkvDKdGADcBABgACAkvDKdGADcBAAEuAAUUBQkaAAcAPgwA.Destroyerman:BAAALgADCgQJBAAAAA==.Devilzkry:BAAALgAECgcJCwAAAA==.Devistaysha:BAAALgAECgcJDgAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgUJBQABLgAECgcJGQADAGMdAA==.',
Dh='Dharmakat:BAAALgADCgUJBQAAAA==.Dhodge:BAABLgAECn8ZAAIZAAcJGR+CKQAYAgAZAAcJGR+CKQAYAgABLgAFFAMJBgAaAFohAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn83AAICAAkJ0x0sCwDPAgACAAkJ0x0sCwDPAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJCQAAAA==.',
Do='Dodgehoj:BAAALgAECgMJBAABLgAFFAMJBgAaAFohAA==.Doffyy:BAAALgAECgEJAQAAAA==.Dogbreathrlz:BAAALgAECgEJAQAAAA==.Dokash:BAAALgAECgUJCQABLgAFFAEJAgAWAAAAAA==.Dotexe:BAABLgAECn8aAAIPAAUJJCBCDwAmAQAPAAUJJCBCDwAmAQAAAA==.Dotsy:BAACLgAFFH8XAAQbAAYJLxipAwBPAQAbAAUJvxmpAwBPAQAXAAQJ5ww0UQAXAQAcAAEJFCAnIQBOAAAuAAQKfy8ABBwACQlNIq4PANMBABwABglDHK4PANMBABcABwnfHsVVAMYBABsABwkhIosJALkBAAAA.',
Dr='Drackarys:BAAALgADCggJFAAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgAECgUJCgAAAA==.Drakiir:BAAALgAECgQJCQABLgAECgcJGQAMAAAUAA==.Dralkish:BAACLgAFFH8FAAIGAAMJtQeDcQC6AAAGAAMJtQeDcQC6AAAuAAQKfzgAAgYACQkuExttAIkBAAYACQkuExttAIkBAAAA.Dramore:BAABLgAECn8iAAIbAAgJ5wnCEABEAQAbAAgJ5wnCEABEAQAAAA==.Drathi:BAAALgADCgcJBwABLgAECgkJKgAGACQjAA==.Dravas:BAAALgAECgUJEgAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Drezzo:BAAALgADCgMJAwAAAA==.Droxx:BAABLgAECn8VAAIMAAYJCAyitAAEAQAMAAYJCAyitAAEAQAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drunkash:BAAALgAECgEJAQAAAA==.Dryerbro:BAAALgAECgEJAQAAAA==.Drzark:BAAALgAECgcJDgAAAA==.',
Du='Dumpling:BAAALgADCgEJAQAAAA==.Dundunduns:BAAALgAECgYJBgAAAA==.',
Dw='Dwdog:BAABLgAECn8nAAIbAAkJrxiUBgABAgAbAAkJrxiUBgABAgAAAA==.',
['Dà']='Dàthguy:BAACLgAFFH8RAAIMAAQJPyKDLACWAQAMAAQJPyKDLACWAQAuAAQKfz0AAgwACQnyJbYCAHEDAAwACQnyJbYCAHEDAAAA.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJDwAAAA==.',
El='Elennie:BAAALgAECgQJCgAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elephlock:BAAALgAECgQJBQAAAA==.Elephunch:BAAALgAECgUJBQAAAA==.Elerion:BAABLgAECn8jAAMVAAkJ6hNKGAADAgAVAAkJ6hNKGAADAgABAAcJSQkwNAA/AQAAAA==.Elista:BAAALgADCgUJBQABLgADCgQJBAAWAAAAAA==.Elm:BAAALgADCgUJBQAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgIJAgAAAA==.Emmi:BAABLgAECn8vAAIMAAkJeh0xGgChAgAMAAkJeh0xGgChAgAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIGAAcJ/B7jLwBjAgAGAAcJ/B7jLwBjAgAAAA==.Eralis:BAAALgAECgUJBQAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.',
Fa='Faelivrin:BAAALgAECgYJBQAAAA==.Faith:BAAALgADCgYJBgAAAA==.Falcor:BAABLgAECn8eAAMRAAkJDCL+BwD5AgARAAkJwCH+BwD5AgATAAYJXSF4EQDIAQAAAA==.Faloran:BAAALgAECgEJAQAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgkJCQAAAA==.Fekk:BAAALgADCgIJAgABLgAECgUJBwAWAAAAAA==.Fenderbender:BAAALgADCgYJBgAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feykat:BAAALgADCgUJBQAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAABLgAECn8xAAINAAgJZR4rCwBSAgANAAgJZR4rCwBSAgAAAA==.Fifthelement:BAABLgAECn8nAAIHAAkJ+xqhEQC1AgAHAAkJ+xqhEQC1AgAAAA==.',
Fj='Fjalgeirr:BAABLgAECn8rAAMdAAkJXBTQFQDLAQAdAAkJXBTQFQDLAQAeAAYJeAa4IACIAAAAAA==.',
Fl='Fleapaw:BAAALgADCgcJBwAAAA==.Flockling:BAAALgADCgYJBgAAAA==.',
Fo='Foxymomma:BAABLgAECn8sAAIUAAkJtx6bBgD+AgAUAAkJtx6bBgD+AgAAAA==.',
Fr='Frey:BAACLgAFFH8VAAIMAAUJ4iISPwBlAQAMAAUJ4iISPwBlAQAuAAQKfzIAAgwACQllJd4EAFIDAAwACQllJd4EAFIDAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8bAAMbAAkJiCBZAQDjAgAbAAcJ7iRZAQDjAgAXAAYJZxqLsADeAAAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fulgar:BAAALgAECgQJBQAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.',
Fw='Fwenwir:BAABLgAECn8aAAQfAAYJFSCWLADKAQAfAAYJfx+WLADKAQAgAAMJvxjxOwDXAAADAAEJ+xiuBgFEAAAAAA==.',
Ga='Galatea:BAAALgAECgYJBgAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAABLgAECn8lAAILAAkJRg03KQCtAQALAAkJRg03KQCtAQAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJGgABLgAECgkJLAACAPwZAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gidgette:BAAALgAECgYJCwAAAA==.Gilalade:BAABLgAECn8uAAIDAAkJKxYAKwAmAgADAAkJKxYAKwAmAgAAAA==.Gingee:BAAALgADCgIJAgAAAA==.',
Gl='Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8iAAIMAAgJZgf/mQAsAQAMAAgJZgf/mQAsAQAAAA==.',
Go='Gobann:BAAALgADCggJEAABLgAECggJHQADAOUbAA==.Gooby:BAAALgAECgQJBAABLgAFFAYJFwACAO0UAA==.Gooney:BAAALgAECgIJAgAAAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Greencheese:BAAALgAECgIJAgABLgAECggJGwAMABoSAA==.Grimes:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.Grlfriend:BAAALgAECgYJCQAAAA==.Grodin:BAAALgAECgQJBQAAAA==.Grofiest:BAABLgAECn8jAAMBAAkJjBZKEgA6AgABAAkJjBZKEgA6AgAUAAEJjAFteAAYAAAAAA==.',
Gu='Guggychan:BAACLgAFFH8GAAIaAAMJWiG8GwD4AAAaAAMJWiG8GwD4AAAuAAQKfzkAAhoACQmGJtcAAGwDABoACQmGJtcAAGwDAAAA.',
['Gô']='Gôö:BAAALgAECgQJDAAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAIhAAkJTw/LKABmAQAhAAkJTw/LKABmAQAAAA==.Haelwyn:BAAALgAECgEJAQABLgAECgEJAwAWAAAAAA==.Haldor:BAABLgAECn8jAAIGAAgJewyUkwBAAQAGAAgJewyUkwBAAQAAAA==.Haohmaru:BAABLgAECn8vAAIiAAkJVh/gBgDCAgAiAAkJVh/gBgDCAgAAAA==.',
He='Healomatic:BAAALgAECgUJBQABLgAECgcJCgAWAAAAAA==.Hecæte:BAAALgADCgYJBgAAAA==.Heella:BAAALgAECgEJAQAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgQJCAAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIXAAUJ+RRjjQA+AQAXAAUJ+RRjjQA+AQAAAA==.',
Hi='Him:BAABLgAECn8cAAIKAAkJ/Bf9EwA+AgAKAAkJ/Bf9EwA+AgAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.Holyshocks:BAAALgAECgEJAgAAAA==.',
Hp='Hplaysgames:BAAALgAECgMJBQAAAA==.',
Hu='Huneyhunter:BAABLgAECn8XAAIIAAYJOgg7JADUAAAIAAYJOgg7JADUAAAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
Im='Imsocold:BAACLgAFFH8PAAIMAAQJeRAUZwAhAQAMAAQJeRAUZwAhAQAuAAQKfyIAAwwACAmsIOoYAKkCAAwACAmsIOoYAKkCACMAAQnMEwAAAAAAAAAA.',
In='Intern:BAABLgAECn8kAAQUAAgJYRW7GwDbAQAUAAgJSBW7GwDbAQAVAAQJDQpVWACHAAABAAEJAADOlQAAAAAAAA==.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgADCgkJIAAAAA==.',
Iz='Iza:BAAALgADCgIJAgAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakethecake:BAAALgAECgMJAwAAAA==.Jaks:BAAALgAECgEJAwAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAABLgAECn8oAAITAAkJAQ+ABwC2AQATAAkJAQ+ABwC2AQAAAA==.Javeech:BAAALgAECgQJBgAAAA==.',
Jc='Jchaotic:BAAALgAECggJDwAAAA==.',
Je='Jeezus:BAAALgADCgYJBgABLgAFFAUJGAAMALEhAA==.',
Jo='Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwAWAAAAAA==.Jongsoo:BAAALgAECgcJBwAAAA==.Jovero:BAAALgAECgQJBQAAAA==.',
Ju='Jutas:BAABLgAECn8ZAAMVAAgJFAuSKwBsAQAVAAgJFAuSKwBsAQABAAcJaQIGWwCcAAAAAA==.Juudaz:BAACLgAFFH8YAAMMAAUJsSHjOwBtAQAMAAQJ6B/jOwBtAQANAAQJlh9qFwAYAQAuAAQKf00ABAwACQlmJSUDAGoDAAwACQlmJSUDAGoDAA0ABwm3IZgNACYCACMAAgn8CFsyAEAAAAAA.',
Jv='Jvicious:BAAALgAECgcJCgAAAA==.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAABLgAECn8vAAMCAAkJtR8XBwASAwACAAkJtR8XBwASAwAGAAUJTRX8kwA/AQAAAA==.Kaliista:BAAALgAECgEJAQABLgAECgkJIAAEAOEWAA==.Kallan:BAAALgAECgUJDAAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kapkywa:BAABLgAECn8UAAIEAAgJ3yEdCwADAwAEAAgJ3yEdCwADAwABLgAECggJIAACABAkAA==.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.Katsumyo:BAAALgAECgMJAwAAAA==.',
Ke='Keggz:BAAALgAECgEJAQAAAA==.Kegpoker:BAAALgAECgcJEgAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgUJCAAWAAAAAA==.',
Kh='Khaalzantro:BAAALgAECgIJAgAAAA==.',
Ki='Kilra:BAAALgAECgUJBgAAAA==.Kimbaltina:BAAALgADCgkJEgABLgAECggJMQAIAIoZAA==.Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJEgAAAA==.Kindasmall:BAAALgAECgkJAQAAAA==.Kiyara:BAABLgAECn8+AAIDAAkJrRXcLAAeAgADAAkJrRXcLAAeAgAAAA==.Kizaki:BAAALgADCgkJDgABLgAECggJFwACAP8SAA==.',
Kn='Knowoone:BAABLgAECn9KAAIEAAkJkRjtGAB1AgAEAAkJkRjtGAB1AgAAAA==.',
Ko='Komonaut:BAAALgAECgYJDgAAAA==.Koscihardt:BAABLgAECn8VAAIQAAcJcwYYyQD2AAAQAAcJcwYYyQD2AAAAAA==.Kouelwhip:BAAALgADCgEJAQABLgAECgcJGQAMAAAUAA==.',
Kr='Krelliz:BAABLgAECn8cAAIHAAcJTRAgYQApAQAHAAcJTRAgYQApAQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAABLgAECn8eAAIQAAcJhgrGpwApAQAQAAcJhgrGpwApAQAAAA==.Krystar:BAAALgAECgUJDgAAAA==.',
Ku='Kulfig:BAAALgAECgcJDwAAAA==.Kumen:BAABLgAECn8hAAQkAAkJISDKEgA1AgAkAAgJjx3KEgA1AgAIAAQJ+RzoFQBWAQAJAAUJUxYAKwDzAAAAAA==.Kungfuwho:BAACLgAFFH8RAAMhAAQJbxCxFgAHAQAhAAQJbxCxFgAHAQAYAAQJ/QOsNwClAAAuAAQKfzQAAyEACAkpGUkdALYBACEACAkpGUkdALYBABgABglwChxeAOAAAAAA.Kutyou:BAAALgADCgkJHAAAAA==.',
Ky='Kynlailia:BAAALgADCgQJBAAAAA==.',
['Kû']='Kûnei:BAAALgAECgQJBwAAAA==.',
La='Laladin:BAAALgAECgMJAwAAAA==.Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lenaea:BAACLgAFFH8aAAIHAAUJPgyNKgAhAQAHAAUJPgyNKgAhAQAuAAQKfyUAAgcACQnwGNQqAAICAAcACQnwGNQqAAICAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAACLgAFFH8OAAICAAQJKg4UJQDtAAACAAQJKg4UJQDtAAAuAAQKfycAAgIACAkAFaYlANABAAIACAkAFaYlANABAAAA.Liiege:BAABLgAECn8ZAAMMAAcJABTTbQCAAQAMAAcJABTTbQCAAQANAAIJwg+GPABiAAAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Litesuprmcst:BAAALgAECgEJAQAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJCAAAAA==.',
Lo='Lobø:BAABLgAECn8iAAIDAAgJuRcsPwDaAQADAAgJuRcsPwDaAQAAAA==.Loganx:BAAALgAECgMJBAABLgAECgcJCwAWAAAAAA==.Loxen:BAAALgADCgEJAQAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn81AAIMAAkJnQoJXwCjAQAMAAkJnQoJXwCjAQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgUJCAAAAA==.Lutherisch:BAAALgAECgUJBQABLgAECgUJCAAWAAAAAA==.Lux:BAAALgAECgQJBAAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgAECgQJBAAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAABLgAECn8oAAIQAAgJ6whckQBPAQAQAAgJ6whckQBPAQAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgAECgIJBQAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAAALgAECgYJDwAAAA==.Manatee:BAAALgAECgYJDAAAAA==.Mannan:BAAALgADCgIJAgAAAA==.Marlasinger:BAAALgADCgcJCwAAAA==.Marpesia:BAAALgAECgcJCgAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Marteris:BAAALgADCgEJAQAAAA==.Maygwyn:BAABLgAECn8bAAIQAAcJtgXgwgAAAQAQAAcJtgXgwgAAAQAAAA==.',
Me='Mediva:BAAALgAECgQJBQAAAA==.Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgYJDwAAAA==.Megaera:BAACLgAFFH8GAAIZAAMJwhvOIwCxAAAZAAMJwhvOIwCxAAAuAAQKfx4AAxkACQnuIPMOAAcDABkACQnuIPMOAAcDAB0AAQkeGBZsADoAAAAA.Melar:BAABLgAECn8qAAMLAAgJFBATMACHAQALAAgJFBATMACHAQAlAAEJWAC+UQARAAAAAA==.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.Messyah:BAAALgAFFAEJAQAAAA==.',
Mi='Migmong:BAAALgAECgIJBAAAAA==.Mihawk:BAAALgAECgQJBwAAAA==.Milwaukee:BAAALgAECgEJAQAAAA==.Minjae:BAABLgAECn8UAAMXAAYJ9Bb2bQBaAQAXAAYJTRb2bQBaAQAbAAEJ/hA/OQA2AAABLgAFFAMJBQAXAI8UAA==.Minseo:BAAALgAECgEJAwAAAA==.Miserain:BAAALgAECgQJBQAAAA==.Mistbehaving:BAAALgAECgQJBAAAAA==.',
Mo='Moondemon:BAAALgADCgEJAQAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Moozart:BAAALgADCgEJAQAAAA==.Morphumbra:BAAALgAECgEJAQAAAA==.Morrìgan:BAABLgAECn8ZAAMXAAcJ3QUvqwDnAAAXAAcJ3QUvqwDnAAAcAAIJqwOUYgBJAAAAAA==.Mothra:BAAALgAECgQJBQABLgAFFAQJBQAHAOoRAA==.Movack:BAABLgAECn8rAAIGAAkJpg7xXQCrAQAGAAkJpg7xXQCrAQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.',
Mu='Muncha:BAAALgAECgEJAgAAAA==.Murderface:BAABLgAECn8lAAMkAAkJZxYoIQCxAQAkAAgJhRYoIQCxAQAEAAcJpBbNTQBNAQAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAABLgAECn8ZAAIcAAgJswomEwANAQAcAAgJswomEwANAQAAAA==.Mythunran:BAABLgAECn8rAAIfAAgJJhMpDgBuAQAfAAgJJhMpDgBuAQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJDwAWAAAAAA==.Natash:BAAALgAECgEJAgAAAA==.Nawas:BAAALgAECgEJAQAAAA==.Nax:BAAALgAECgQJBQAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAgAAAA==.Nerfhammer:BAACLgAFFH8RAAIGAAUJXxqoHQB6AQAGAAUJXxqoHQB6AQAuAAQKfyoAAgYACQlLIwkcAMICAAYACQlLIwkcAMICAAAA.Nessalove:BAACLgAFFH8ZAAIUAAYJxg9QCwB7AQAUAAYJxg9QCwB7AQAuAAQKfysAAhQACQmUHTgMAI8CABQACQmUHTgMAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8eAAQRAAkJjw1aNwBFAQARAAcJAQ5aNwBFAQASAAYJJxEDHgAAAQATAAEJxANIQgArAAAAAA==.Nipao:BAABLgAECn8WAAIYAAgJKRa+IAACAgAYAAgJKRa+IAACAgAAAA==.Niron:BAAALgAECgUJBwAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAABLgAFFH8NAAIYAAMJPRMyMgDCAAAYAAMJPRMyMgDCAAABLgAFFAgJLAAQAFIkAA==.Noriel:BAAALgAECgYJDwAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAABLgAECn8UAAIDAAcJNRGoYwBxAQADAAcJNRGoYwBxAQAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Og='Ognyal:BAAALgAECgkJBQAAAA==.',
Oh='Ohtani:BAAALgAECgcJDAAAAA==.',
Ol='Olanali:BAAALgAECgEJAgABLgAECgEJAwAWAAAAAA==.Olectria:BAAALgADCgEJAQAAAA==.',
Oo='Ooblitoon:BAABLgAECn9KAAITAAkJWRNSBQAAAgATAAkJWRNSBQAAAgAAAA==.',
Op='Opali:BAAALgAECgEJAQAAAA==.',
Or='Orfantal:BAABLgAECn8hAAIDAAkJExKjRADIAQADAAkJExKjRADIAQAAAA==.Oridan:BAAALgAECgEJAQAAAA==.Oridon:BAAALgAECgQJBQAAAA==.',
Ou='Ouahoahoah:BAAALgAFFAEJAQAAAA==.',
Ov='Oven:BAAALgAECgQJBAABLgAFFAQJEQAMAD8iAA==.Overcast:BAAALgAECgQJBwAAAA==.Overshoot:BAABLgAECn8WAAMDAAgJVwtuZQBsAQADAAgJVwtuZQBsAQAgAAIJXgQWUgBXAAAAAA==.',
Ox='Oxen:BAAALgAECgYJBwAAAA==.',
Pa='Panterion:BAABLgAECn8gAAIEAAkJ4RYqJAAgAgAEAAkJ4RYqJAAgAgAAAA==.Parvarti:BAABLgAECn8fAAMcAAkJDQjSFgDhAAAcAAcJBQnSFgDhAAAXAAIJJgWVCgFTAAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECgkJGQAMAAYdAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Persimmoñ:BAABLgAECn8vAAIGAAgJ7A9rdwB0AQAGAAgJ7A9rdwB0AQAAAA==.Petthemonk:BAAALgADCgcJBQAAAA==.',
Ph='Phaelissia:BAAALgAECgYJDwAAAA==.Philljr:BAAALgADCgMJAwAAAA==.',
Pi='Pinero:BAAALgADCgYJCQAAAA==.',
Pl='Plaugus:BAAALgAECgQJBQAAAA==.',
Po='Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgcJEQAAAA==.Prost:BAABLgAECn8bAAIQAAkJlxxQQgAOAgAQAAkJlxxQQgAOAgAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Pu='Puppybreath:BAAALgAECgEJAQAAAA==.Purdy:BAAALgAECgkJAgAAAA==.',
Py='Pyroblast:BAACLgAFFH8VAAIQAAYJtxiTMwCIAQAQAAYJtxiTMwCIAQAuAAQKfzYAAxAACQkjIfUSAOMCABAACQmWIPUSAOMCACYAAQkLIqIPAGQAAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Ravage:BAAALgAECgMJAwAAAA==.',
Re='Relaceara:BAABLgAECn8WAAIGAAkJswVrnwAtAQAGAAkJswVrnwAtAQAAAA==.Reladin:BAABLgAECn8vAAIFAAkJMwraGQA+AQAFAAkJMwraGQA+AQAAAA==.Relanna:BAABLgAECn8WAAIMAAYJjAfB3gDKAAAMAAYJjAfB3gDKAAAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCggJIwAAAA==.Rendstein:BAABLgAECn8fAAINAAkJzBd6EAD3AQANAAkJzBd6EAD3AQAAAA==.Renzr:BAACLgAFFH8JAAIMAAIJtSNIoADHAAAMAAIJtSNIoADHAAAuAAQKf0cAAwwACAnKJSgUAMcCAAwACAkdJSgUAMcCAA0ACAmeItMGAKkCAAAA.Reqquuiiem:BAAALgADCgUJCAAAAA==.Respcct:BAAALgADCgkJEgABLgAECgkJNwACANMdAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAABLgAECn8UAAIEAAkJMQ/MQgB8AQAEAAkJMQ/MQgB8AQAAAA==.Rowin:BAAALgAECggJDwAAAA==.Royal:BAAALgAECgEJAQAAAA==.',
Ru='Rustedroots:BAABLgAECn8sAAIEAAgJZxgPIQA2AgAEAAgJZxgPIQA2AgAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Sailley:BAAALgAECgQJBQAAAA==.Saltgrizzny:BAAALgAECgcJDQAAAA==.Sapphyre:BAAALgAECgEJAgAAAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAABLgAECn8dAAIfAAkJVBNPCgC+AQAfAAkJVBNPCgC+AQAAAA==.Sarnara:BAABLgAECn8nAAIFAAkJUxr5CAA3AgAFAAkJUxr5CAA3AgAAAA==.Savageclaw:BAAALgAECggJCAAAAA==.Savagehunt:BAAALgAECgEJAgABLgAECgYJFQAiAO0gAA==.Savagekegs:BAABLgAECn8VAAMiAAYJ7SD8OABmAQAiAAQJZSP8OABmAQAhAAUJQhhUPQAmAQAAAA==.Savagelight:BAAALgAECgEJAQABLgAECgYJFQAiAO0gAA==.Savagex:BAAALgAECgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAABLgAECn8jAAIDAAgJFARKnAD5AAADAAgJFARKnAD5AAAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgAECgEJAQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Senarx:BAAALgAECgIJBAAAAA==.Sereniity:BAABLgAECn8UAAQiAAYJLiIpGgDMAQAiAAYJLiIpGgDMAQAYAAUJFBefMQAxAQAhAAEJrBaSiwA7AAABLgAECgcJGQAMAAAUAA==.',
Sh='Shamalicous:BAABLgAECn8UAAMHAAUJAgLCogBwAAAHAAUJAgLCogBwAAAKAAQJ+wXjegBrAAAAAA==.Shamjam:BAABLgAECn8jAAIHAAgJ+BHhOAC+AQAHAAgJ+BHhOAC+AQAAAA==.Shamous:BAAALgAECgUJCAAAAA==.Shampayne:BAAALgADCgYJBgABLgAFFAUJGAAMALEhAA==.Shanthe:BAAALgAECgYJEQABLgAFFAMJBQAOAPgaAA==.Sharku:BAACLgAFFH8KAAIQAAMJsBSucADxAAAQAAMJsBSucADxAAAuAAQKfycAAhAACQkMIOsdAKMCABAACQkMIOsdAKMCAAAA.Shegothalf:BAAALgAECgQJBQAAAA==.Shãdo:BAAALgAECgYJCAAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAECgkJHgARAAwiAA==.Siinep:BAAALgAECgcJEAAAAA==.',
Sk='Skey:BAAALgAECgIJAgAAAA==.Skibblé:BAABLgAECn8XAAIcAAgJ1Q1gDgBJAQAcAAgJ1Q1gDgBJAQAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAABLgAECn8XAAIEAAgJHhf2MwDDAQAEAAgJHhf2MwDDAQAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIZAAgJrSGCEgDrAgAZAAgJrSGCEgDrAgAAAA==.Smokeyjr:BAAALgADCgcJBwAAAA==.',
Sn='Sneakyboi:BAABLgAECn8uAAIPAAkJZRp0BABDAgAPAAkJZRp0BABDAgAAAA==.Snippin:BAAALgAECgIJAgAAAA==.',
So='Soléne:BAABLgAECn8WAAMHAAgJgh03KQALAgAHAAYJdR43KQALAgAKAAUJyRBkVADXAAABLgAFFAQJCQAXAK0PAA==.Sorden:BAAALgAECgQJBgABLgAECgkJMAAZAKofAA==.',
Sp='Spiced:BAABLgAECn8ZAAIkAAgJSCC0DQDAAgAkAAgJSCC0DQDAAgABLgAECgkJGwAbAIggAA==.Spliff:BAAALgAECgIJAgAAAA==.',
Sq='Squirt:BAABLgAECn8aAAISAAgJvQ88GgC6AQASAAgJvQ88GgC6AQAAAA==.',
Ss='Ssks:BAAALgAFFAEJAQABLgAECgMJCwAWAAAAAA==.',
St='Stabsmcshank:BAACLgAFFH8OAAIOAAQJ/A7/GgA0AQAOAAQJ/A7/GgA0AQAuAAQKfykAAg4ACQmqFhgdABYCAA4ACQmqFhgdABYCAAAA.Starbux:BAABLgAECn8kAAQVAAcJpxEMKwBvAQAVAAcJKw8MKwBvAQAUAAUJEA8/WgDLAAABAAUJ3ge+VQCwAAAAAA==.Steakx:BAAALgAECgQJBgAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Suriel:BAABLgAECn8WAAINAAcJ1BIpHwBQAQANAAcJ1BIpHwBQAQAAAA==.Suumcuique:BAAALgAECgIJAgABLgAECgkJJQAkAGcWAA==.',
Sv='Svenya:BAABLgAECn8YAAMkAAgJyQ1lRQDoAAAkAAcJ2AplRQDoAAAEAAYJOAUcgQCuAAAAAA==.',
Sy='Syenna:BAAALgAECgEJAQAAAA==.Sygne:BAAALgAECgQJBQAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAABLgAECn8xAAIDAAgJBBLHTQCsAQADAAgJBBLHTQCsAQAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJCAABLgAFFAQJBQAHAOoRAA==.',
['Sï']='Sïenna:BAAALgAECgkJEAAAAA==.',
Ta='Taggy:BAABLgAECn8rAAIPAAgJaQ+yCgCBAQAPAAgJaQ+yCgCBAQABLgAECggJMQAIAIoZAA==.Taln:BAAALgAECgEJAQAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Tassandie:BAAALgAECgQJBAABLgAECgkJIAAEAOEWAA==.Tayebeh:BAAALgADCgcJDAAAAA==.',
Te='Terran:BAAALgAECgUJCwAAAA==.Texhd:BAAALgAECgYJBgABLgAFFAgJIgARADkbAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.Thansus:BAAALgAECgEJAQAAAA==.Theçølletør:BAAALgAECgIJAgAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.Tinygibbs:BAAALgAECgMJBAAAAA==.',
To='Toiletnuker:BAABLgAECn8iAAQgAAgJ8A7KHACyAQAgAAgJMw7KHACyAQADAAYJug31lQAGAQAfAAEJRAoEPgAoAAABLgAECgkJNwACANMdAA==.Tokyojoe:BAABLgAECn8hAAIZAAkJshQONwDeAQAZAAkJshQONwDeAQAAAA==.Tolsanah:BAABLgAFFH8JAAIYAAUJXA8ZIgAtAQAYAAUJXA8ZIgAtAQABLgAFFAkJOAASAJIeAA==.Torocious:BAAALgAECgYJDQAAAA==.Torrick:BAABLgAECn8qAAQGAAkJJCNPCAAgAwAGAAkJJCNPCAAgAwACAAYJBRcRNwCfAQAFAAEJwxRjQwAwAAAAAA==.Torrickgreed:BAAALgADCgYJBgABLgAECgkJKgAGACQjAA==.Totemtot:BAABLgAECn8rAAInAAkJyAUMFwBDAQAnAAkJyAUMFwBDAQAAAA==.Toupee:BAAALgAECgQJBQAAAA==.',
Tr='Tradrivia:BAAALgAECgQJBgAAAA==.Tronly:BAAALgADCgUJBQAAAA==.Trukait:BAAALgAECgEJAQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Tw='Twinkish:BAAALgAECgEJAQAAAA==.',
Ty='Tyllivan:BAAALgADCgcJDgAAAA==.',
['Tá']='Tálise:BAAALgADCgcJBwAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCgAAAA==.',
Uf='Uffizzle:BAAALgAECgUJBwAAAA==.',
Ul='Ulf:BAABLgAECn8gAAIHAAgJbRIzOQC8AQAHAAgJbRIzOQC8AQAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Va='Valquirie:BAACLgAFFH8FAAINAAMJ4xZ3IADVAAANAAMJ4xZ3IADVAAAuAAQKfzwAAg0ACQmwIIYEAOQCAA0ACQmwIIYEAOQCAAAA.Valyrius:BAAALgADCggJCQABLgAECgYJBgAWAAAAAA==.Varlamor:BAABLgAECn8VAAMUAAgJlwtMLgBMAQAUAAgJlwtMLgBMAQABAAUJYQRUXQCTAAAAAA==.Vathraen:BAAALgAECgMJBgAAAA==.',
Ve='Velanistra:BAABLgAECn8oAAIGAAkJYg3MZQCZAQAGAAkJYg3MZQCZAQAAAA==.Velanya:BAAALgADCgkJFQAAAA==.Velnia:BAAALgAECgcJBwAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAABLgAECn8nAAIdAAkJFBGXGQCjAQAdAAkJFBGXGQCjAQAAAA==.Very:BAAALgAECgUJDgAAAA==.',
Vg='Vgerr:BAABLgAECn8WAAIGAAkJAgw0ZQCaAQAGAAkJAgw0ZQCaAQAAAA==.',
Vi='Viashino:BAAALgAECgEJAQABLgAECgQJBwAWAAAAAA==.Vidarus:BAAALgAFFAIJAwABLgAFFAUJEQAGAF8aAA==.Viridian:BAAALgAECgMJBgABLgAFFAMJBgAZAMIbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAABLgAECn8dAAMDAAgJ5Ru6QwDKAQADAAYJiBy6QwDKAQAfAAYJlBemFwDqAAAAAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAABLgAECn8VAAMZAAkJYg9TggAkAQAZAAgJaQ5TggAkAQAdAAIJ4xGTSgB2AAAAAA==.Vynos:BAABLgAECn8hAAIXAAgJQgcoiAAlAQAXAAgJQgcoiAAlAQAAAA==.Vysant:BAAALgADCgQJBgABLgAECggJIQAXAEIHAA==.',
['Vä']='Väl:BAAALgAECgQJCAAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAACLgAFFH8FAAMHAAQJ6hF+MwD8AAAHAAQJ6hF+MwD8AAAKAAEJRwOaVQAxAAAuAAQKfyQAAwcACQm7EZUyANsBAAcACQm7EZUyANsBAAoABwn2E183AEsBAAAA.',
Wc='Wchaos:BAAALgAECgUJBwAAAA==.',
We='Welker:BAAALgADCgQJCAABLgAFFAMJCAAMAKAQAA==.Welkerdk:BAACLgAFFH8IAAIMAAMJoBBYlADXAAAMAAMJoBBYlADXAAAuAAQKfzIAAgwACQlJIAEWALsCAAwACQlJIAEWALsCAAAA.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgAZAMIbAA==.',
Wh='Whiskeycakes:BAAALgAECgIJAwABLgAECgQJBgAWAAAAAA==.',
Wi='Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.Windeyaho:BAAALgAECggJCgAAAA==.',
Wo='Wolfman:BAABLgAECn8fAAIiAAkJXApCJwBtAQAiAAkJXApCJwBtAQAAAA==.Woökie:BAAALgADCgYJBgAAAA==.',
Xa='Xalidan:BAAALgAECgUJCgAAAA==.',
Xt='Xten:BAABLgAECn8WAAIEAAcJhxXJNwCuAQAEAAcJhxXJNwCuAQAAAA==.',
Ya='Yamzofsteel:BAAALgADCgMJAwAAAA==.Yath:BAAALgAECgMJAwAAAA==.',
Ye='Yeat:BAAALgAECgUJCwAAAA==.',
Yo='Yoatanius:BAAALgAECgEJAQAAAA==.Yoshinox:BAAALgAECgMJBAAAAA==.',
Yr='Yrelle:BAAALgADCggJCAABLgAECgcJFgABAJ8MAA==.',
Za='Zalazam:BAABLgAECn8iAAMKAAkJPBzTEQBWAgAKAAkJPBzTEQBWAgAHAAEJjhlWuABMAAAAAA==.Zalth:BAABLgAECn8jAAIQAAkJ4AzdYgCyAQAQAAkJ4AzdYgCyAQAAAA==.',
Ze='Zelliph:BAAALgAECgUJDgAAAA==.Zenagdrina:BAABLgAECn8WAAMgAAgJiQX/MQAXAQAgAAgJvQT/MQAXAQADAAIJBAZ8EQE9AAAAAA==.Zenobiå:BAAALgAECggJEgAAAA==.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.',
Zh='Zhaann:BAABLgAECn8WAAMBAAcJnwwyPQAUAQABAAYJwA4yPQAUAQAVAAIJqAm7ZABVAAAAAA==.Zhaida:BAAALgADCgIJAgAAAA==.',
Zo='Zokor:BAAALgADCgkJOwAAAA==.Zorach:BAAALgAECgYJDQAAAA==.',
['Zá']='Zárá:BAABLgAECn8tAAIQAAcJQhKbggBsAQAQAAcJQhKbggBsAQAAAA==.',
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
