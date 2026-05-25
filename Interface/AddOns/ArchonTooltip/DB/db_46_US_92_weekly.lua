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

local lookup = {'Warlock-Demonology','Shaman-Elemental','Paladin-Retribution','Druid-Balance','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Warrior-Fury','Paladin-Protection','DemonHunter-Devourer','Warrior-Arms','Rogue-Assassination','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Hunter-BeastMastery','Warlock-Destruction','Hunter-Survival','Druid-Feral','Priest-Shadow','Mage-Frost','Hunter-Marksmanship','Mage-Arcane','Priest-Discipline','Priest-Holy','Paladin-Holy','Warlock-Affliction','Rogue-Outlaw','Mage-Fire','Warrior-Protection','Druid-Restoration','Monk-Brewmaster','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE/OgAjAgABAAkJuxE/OgAjAgAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAAALgAECgUJEgABLgAFFAUJCAACAPgKAA==.',
Ae='Aethira:BAAALgAECgEJAwAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn85AAIDAAkJpiCUDwDQAgADAAkJpiCUDwDQAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.Ainz:BAAALgADCgkJCQAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexr:BAAALgADCgMJAwAAAA==.Alfee:BAAALgAECgIJAgAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.',
Am='Amarantus:BAAALgAECgQJBAABLgAFFAMJCAAEABgNAA==.Amarndeus:BAAALgADCgMJAwAAAA==.Ammerie:BAAALgAECgkJAgAAAA==.',
An='Anakim:BAAALgAECgQJBQAAAA==.Anmo:BAAALgAECggJEAAAAA==.Anmodru:BAAALgAECgYJBgAAAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aonani:BAAALgAECggJBgAAAA==.Aotc:BAABLgAECn8WAAIFAAcJxw1rKwBsAQAFAAcJxw1rKwBsAQAAAA==.',
Aq='Aquaism:BAAALgADCgIJAgAAAA==.Aqulath:BAACLgAFFH8JAAIGAAQJbBnrAgAoAQAGAAQJbBnrAgAoAQAuAAQKfxQAAgYACQnaGvUDAGQCAAYACQnaGvUDAGQCAAAA.Aquílés:BAAALgAECgEJAQAAAA==.',
Ar='Arazensetal:BAABLgAECn80AAIHAAgJyhsMBwBrAgAHAAgJyhsMBwBrAgAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAUJEgAIAKUSAA==.Ariandrel:BAACLgAFFH8FAAIJAAMJvwYfLQCZAAAJAAMJvwYfLQCZAAAuAAQKfx4AAwkACQkdEZchAMoBAAkACQkdEZchAMoBAAoAAQlbAE+OABQAAAAA.Aridhol:BAAALgAECgcJDQAAAA==.Arkaedius:BAAALgAECggJCgAAAA==.Arker:BAAALgADCgIJAgAAAA==.',
As='Asashin:BAAALgADCgYJBgABLgAECgQJBAALAAAAAA==.Asellus:BAAALgAECgcJDAAAAA==.Ashraun:BAAALgAECgMJBgAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn8qAAIFAAgJAhv5DgABAgAFAAgJAhv5DgABAgAAAA==.Atulno:BAAALgAECgYJBgAAAA==.',
Au='Aubrii:BAAALgADCgYJCAAAAA==.Aukatsang:BAACLgAFFH8NAAIKAAUJth9RCQBXAQAKAAUJth9RCQBXAQAuAAQKfyoAAgoACQmTI10BAKMDAAoACQmTI10BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.Auroraa:BAAALgADCgYJBgAAAA==.',
Az='Azymor:BAAALgADCggJDgAAAA==.',
Ba='Baddy:BAABLgAECn8fAAIMAAgJ9xz+FAClAgAMAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIKAAQJvRwkDAA6AQAKAAQJvRwkDAA6AQAuAAQKfyQAAgoACAndHpEJAN8CAAoACAndHpEJAN8CAAAA.Baladeva:BAABLgAECn8zAAINAAgJoR9WBgBYAgANAAgJoR9WBgBYAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECgkJOQADAKYgAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgMJAwAAAA==.',
Be='Bearhold:BAAALgAECgQJBAAAAA==.Beersnob:BAABLgAECn8kAAIJAAkJLxabFwAeAgAJAAkJLxabFwAeAgAAAA==.Benjam:BAACLgAFFH8RAAIOAAYJZBbIFACoAQAOAAYJZBbIFACoAQAuAAQKfygAAg4ABwnlI0wZAL0CAA4ABwnlI0wZAL0CAAAA.Benyo:BAAALgADCgIJAgAAAA==.',
Bi='Bigmikeyg:BAABLgAECn81AAIDAAgJfBIlUwCxAQADAAgJfBIlUwCxAQAAAA==.Bigsteve:BAABLgAECn8oAAMMAAgJnyC0CwCKAgAMAAgJlSC0CwCKAgAPAAgJ1hKBFACRAQAAAA==.',
Bl='Blanket:BAACLgAFFH8LAAMQAAMJJwpYBgDoAAAIAAMJiQWXDwD0AAAQAAMJJwpYBgDoAAAuAAQKfxYAAwgABwlSHPUqAKUBAAgABwkjHPUqAKUBABAAAwmaGgAAAAAAAAAA.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJCgAMAAYkAA==.',
Br='Brewtel:BAAALgADCgcJBwABLgAECgQJBAALAAAAAA==.Bricked:BAAALgAECgIJBAAAAA==.Bronzesun:BAAALgADCgYJBgAAAA==.',
Bu='Bubbahowl:BAAALgADCgEJAQAAAA==.Bukara:BAAALgAECgQJBgAAAA==.Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8jAAIRAAkJMRobEwCIAgARAAkJMRobEwCIAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgQJBQAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8eAAQHAAkJHQX8IgBhAQAHAAkJHQX8IgBhAQASAAMJGgjIMgCAAAATAAMJ0Ai9aQBlAAAAAA==.Calizon:BAAALgAECggJDwAAAA==.Camc:BAAALgAECgQJDAAAAA==.Canowhoopass:BAABLgAECn8mAAICAAgJvApvNwAqAQACAAgJvApvNwAqAQAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cerassin:BAACLgAFFH8bAAIOAAYJtxnzFACnAQAOAAYJtxnzFACnAQAuAAQKfzYAAg4ACQkJIbUHAP4CAA4ACQkJIbUHAP4CAAAA.Cereas:BAABLgAECn87AAIFAAgJPBoTDgAPAgAFAAgJPBoTDgAPAgAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgYJCAAAAA==.Chichobelo:BAABLgAFFH8LAAQUAAYJFhxCFADGAQAUAAUJWhtCFADGAQAVAAEJuR6rFQBbAAAWAAEJAABePwAAAAAAAA==.Chuckrutis:BAABLgAECn8fAAMSAAYJQR9wDAAUAgASAAYJUh5wDAAUAgATAAMJOB8JRADyAAAAAA==.',
Cl='Cliché:BAAALgAECgYJDwAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8XAAIXAAUJfhvAIABFAQAXAAUJfhvAIABFAQAuAAQKfyoAAhcACQk6IXYCAHEDABcACQk6IXYCAHEDAAAA.',
Co='Coldandwet:BAABLgAFFH8IAAIUAAMJ/hAxdgDiAAAUAAMJ/hAxdgDiAAAAAA==.Combination:BAABLgAECn81AAIYAAgJ3R9AAgB6AgAYAAgJ3R9AAgB6AgABLgAFFAcJHgADAEkZAA==.Constrace:BAAALgAECgUJBQAAAA==.Corvenall:BAABLgAECn83AAISAAgJlw2YCQBoAQASAAgJlw2YCQBoAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAAALgAECgYJCgAAAA==.Crossbow:BAACLgAFFH8GAAIXAAMJABN2RgDcAAAXAAMJABN2RgDcAAAuAAQKfzkAAhcACQnLHxsPAMICABcACQnLHxsPAMICAAAA.Crystoph:BAAALgAECgEJAQABLgAFFAQJCQAGAGwZAA==.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Cy='Cylan:BAAALgADCgYJBgABLgAECggJOwAFADwaAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Dante:BAAALgAECgIJAwABLgAECgkJGQAZAMQRAA==.Darkluster:BAAALgAECgUJCgAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.',
De='Deathbcmesyu:BAABLgAECn8WAAIUAAcJ1RH7jQAjAQAUAAcJ1RH7jQAjAQAAAA==.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demonheart:BAAALgADCgQJBAABLgAECggJGwAaAIggAA==.Demorian:BAAALgAECgEJAQABLgAECggJJwAbANoNAA==.Deondre:BAAALgAECgQJCAAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.Devoutheart:BAAALgAECgQJBAABLgAECggJGwAaAIggAA==.',
Di='Diehappy:BAAALgAECgUJEgAAAA==.Dillie:BAAALgADCgMJAwAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgcJDQAAAA==.',
Do='Dompal:BAAALgAECgMJBgABLgAFFAUJGQAGAFAjAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dragonshark:BAAALgADCgEJAQAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAkJLAAcAGAmAA==.Drovinos:BAAALgAECgYJBgAAAA==.Druken:BAAALgAECgMJAwAAAA==.Drybonez:BAABLgAECn8UAAIcAAYJ0Aha+AAKAQAcAAYJ0Aha+AAKAQAAAA==.Drylie:BAACLgAFFH8TAAMXAAUJCCQJFABxAQAXAAUJCCQJFABxAQAdAAEJwBmjJQBSAAAuAAQKfyMAAx0ACQm3JNIJAAYDAB0ACAmdItIJAAYDABcAAwlvI/9/ABABAAAA.Dràgonkíng:BAAALgAECggJEgAAAA==.',
Dt='Dtinnel:BAABLgAECn8nAAIMAAkJWRx5DgBoAgAMAAkJWRx5DgBoAgABLgAFFAUJCQAUAKEPAA==.',
Du='Dumbledussy:BAABLgAECn8nAAIbAAgJ2g2dJgBvAQAbAAgJ2g2dJgBvAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.Dustinterp:BAAALgAECgMJAwAAAA==.',
Ed='Edanor:BAAALgAECgQJBQABLgAECgkJJAASAGcdAA==.',
Eg='Ego:BAABLgAECn83AAIMAAkJMiTOBAD7AgAMAAkJMiTOBAD7AgAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elrondo:BAAALgAECgEJAQAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQAcAHciAA==.Emmone:BAAALgAECgUJDwAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.',
En='Endo:BAAALgAECgEJAQAAAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evistan:BAAALgADCgYJDQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAAALgAECgUJCQAAAA==.Excaleon:BAAALgAECgQJBAAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Farglight:BAAALgAECgQJBAAAAA==.Faunna:BAACLgAFFH8IAAIEAAMJGA0fJgDJAAAEAAMJGA0fJgDJAAAuAAQKfzsAAgQACQkbH4gHAL0CAAQACQkbH4gHAL0CAAAA.',
Fe='Feath:BAAALgAECgkJAQAAAA==.Feebeeboofae:BAAALgAECgEJAQAAAA==.Felaz:BAABLgAECn82AAIeAAkJJCCoAADhAgAeAAkJJCCoAADhAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.Ferreii:BAAALgADCgEJAQAAAA==.',
Fi='Fingerguns:BAACLgAFFH8GAAIfAAMJMQQxKAC8AAAfAAMJMQQxKAC8AAAuAAQKfxwABB8ACAlqFzMTABsCAB8ACAlqFzMTABsCACAAAwl3CO5mAJEAABsAAwkJCNteAF4AAAAA.Fionaa:BAABLgAECn8dAAMBAAkJOAXAawBNAQABAAkJDQXAawBNAQAYAAEJsAfxeAAqAAAAAA==.Fiyona:BAAALgAECgMJBgAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgADCgMJAwAAAA==.Floortank:BAABLgAECn8qAAMVAAcJowdwFQDlAAAUAAcJtQV9pQD7AAAVAAcJSwdwFQDlAAAAAA==.',
Fo='Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAACLgAFFH8LAAIhAAMJUBtYIADwAAAhAAMJUBtYIADwAAAuAAQKfxsAAiEABwnKI4sRAIcCACEABwnKI4sRAIcCAAAA.Frikilatar:BAAALgAECgEJBQAAAA==.Frostyhatesu:BAEALgADCgMJAwABLgAECgIJAwALAAAAAA==.Frrank:BAACLgAFFH8ZAAIPAAUJhiVvBQChAQAPAAUJhiVvBQChAQAuAAQKfzMAAg8ACQkeJWEAALQDAA8ACQkeJWEAALQDAAAA.',
Fu='Fullerene:BAAALgAECgEJAQAAAA==.',
Ga='Galcain:BAABLgAECn8sAAQXAAgJ+yL2BwARAwAXAAgJtiL2BwARAwAZAAcJQxUgHACeAQAdAAMJVBrQYAC9AAAAAA==.Galkhan:BAAALgAECgQJBAABLgAECggJLAAXAPsiAA==.Gardonea:BAAALgADCggJDgAAAA==.',
Gh='Ghostmain:BAAALgAECgQJBgABLgAECgcJAQALAAAAAA==.',
Gi='Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAABLgAECn8mAAIcAAgJhxPpXwCjAQAcAAgJhxPpXwCjAQAAAA==.Glaivizzon:BAAALgAECgIJAwAAAA==.',
Go='Gorizarev:BAAALgAECgQJCgAAAA==.',
Gr='Grogtar:BAAALgADCgMJAwAAAA==.Grumandel:BAABLgAECn80AAIaAAgJGBIVDgCfAQAaAAgJGBIVDgCfAQAAAA==.',
Gu='Guce:BAAALgAECgUJBwAAAA==.Gudetama:BAABLgAECn8ZAAMXAAgJTiHBFwB7AgAXAAYJESPBFwB7AgAZAAYJ/h2pEwDvAQAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgYJCgAAAA==.Haidie:BAAALgADCgEJAQAAAA==.Hakur:BAABLgAECn87AAIDAAkJQhz/IwBUAgADAAkJQhz/IwBUAgAAAA==.Hamahara:BAAALgAECgUJBgAAAA==.Hanma:BAACLgAFFH8VAAIUAAcJgBnnCwAIAgAUAAcJgBnnCwAIAgAuAAQKfygAAhQACQkFHxEsAIgCABQACQkFHxEsAIgCAAAA.Harribel:BAABLgAECn8vAAIcAAgJjA6tdABzAQAcAAgJjA6tdABzAQAAAA==.',
He='Heimdall:BAAALgADCgQJAQAAAA==.Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgADCgYJBgAAAA==.Hiroki:BAABLgAECn8gAAIUAAgJegstawBqAQAUAAgJegstawBqAQAAAA==.Hitachitotem:BAACLgAFFH8SAAICAAMJsg+jEQDbAAACAAMJsg+jEQDbAAAuAAQKfxkAAgIACAmtGl0aAEACAAIACAmtGl0aAEACAAAA.Hiyoda:BAAALgAECgUJBQAAAA==.Hiyodaw:BAAALgAECgMJAwAAAA==.Hizzon:BAAALgADCgcJDAAAAA==.',
Ho='Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAAALgAECggJEwAAAA==.Holymaet:BAAALgADCgEJAQABLgAFFAMJBwAMAAMdAA==.Holyphatso:BAAALgADCgMJAwABLgAECgkJKQAgACsgAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAABLgAECn8dAAIcAAgJ4xQsVQDAAQAcAAgJ4xQsVQDAAQAAAA==.',
In='Inflikted:BAABLgAECn8lAAIUAAkJVQioYwB9AQAUAAkJVQioYwB9AQAAAA==.Interwebz:BAABLgAECn8UAAMUAAkJ5Ru6IwBUAgAUAAkJ8hq6IwBUAgAWAAIJ9h1SMwCeAAAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgAECgQJBAALAAAAAA==.Jazzarin:BAAALgADCgEJAQAAAA==.',
Je='Jehannum:BAABLgAECn8cAAICAAgJlQ2ZOQAgAQACAAgJlQ2ZOQAgAQAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgUJEAAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAABLgAFFH8FAAIhAAMJZBtaIQDnAAAhAAMJZBtaIQDnAAABLgAFFAQJFwARABYjAA==.Josen:BAAALgAECgEJAQAAAA==.',
Ju='Juliana:BAAALgADCgMJAwAAAA==.Jurkzarbirt:BAAALgAECgMJAwAAAA==.',
Jz='Jz:BAAALgAECgQJBAAAAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIbAAgJ0hcxHQC1AQAbAAgJ0hcxHQC1AQAAAA==.',
Ka='Kaelibrimbor:BAAALgAECgcJBwAAAA==.Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAAALgAECgMJBAAAAA==.Katarena:BAABLgAECn8zAAIhAAgJVRCHKwCOAQAhAAgJVRCHKwCOAQAAAA==.Kathyra:BAABLgAECn8jAAMBAAkJvwoMTwCXAQABAAkJvwoMTwCXAQAiAAEJ7wEjNwAnAAAAAA==.Kavax:BAABLgAECn8dAAIhAAkJRxG+HQDuAQAhAAkJRxG+HQDuAQAAAA==.',
Ke='Keel:BAAALgAECgUJCgAAAA==.Keeller:BAACLgAFFH8TAAIDAAYJlw+6FACBAQADAAYJlw+6FACBAQAuAAQKfzYAAgMACQkKHvUoADwCAAMACQkKHvUoADwCAAAA.Keggor:BAAALgAECgEJAgAAAA==.Kentyr:BAABLgAECn8pAAMIAAgJVA4hIQBfAQAIAAgJVA4hIQBfAQAjAAIJZwGDDgA0AAAAAA==.',
Kh='Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgADCgIJAgABLgAFFAMJBwAMAAMdAA==.Kinký:BAABLgAECn8vAAMMAAkJNBYaEgBBAgAMAAkJNBYaEgBBAgAPAAEJ2xS3WQA8AAABLgAECgUJCwALAAAAAA==.Kiraelis:BAABLgAECn8lAAIdAAkJqg8tCgClAQAdAAkJqg8tCgClAQAAAA==.Kiss:BAAALgADCgEJAQABLgAECgcJDwALAAAAAA==.Kivea:BAABLgAECn8YAAMcAAgJ6Q/mbQCCAQAcAAgJ6Q/mbQCCAQAkAAEJBAcpEAArAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECggJDwAAAA==.Konagda:BAAALgADCggJEQAAAA==.Korvoh:BAABLgAECn81AAMfAAgJ6hy7CwCHAgAfAAgJ4Ry7CwCHAgAgAAMJUxeOXQC8AAAAAA==.',
Kr='Kringe:BAABLgAECn8jAAICAAgJOiDXEQA3AgACAAgJOiDXEQA3AgAAAA==.Krynn:BAAALgAECgYJBgAAAA==.',
Ku='Kumonk:BAABLgAECn8cAAIKAAcJWAY4PQDeAAAKAAcJWAY4PQDeAAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBQAAAA==.',
['Kä']='Kämik:BAABLgAECn81AAIXAAgJmCCdFwBwAgAXAAgJmCCdFwBwAgAAAA==.',
['Kì']='Kìn:BAABLgAECn8XAAMfAAYJsAZ4OgDyAAAfAAYJsAZ4OgDyAAAbAAIJfQL9agA5AAAAAA==.',
La='Lampion:BAABLgAECn8hAAIFAAkJdAzzGACCAQAFAAkJdAzzGACCAQAAAA==.Langris:BAAALgAECgEJAQAAAA==.Lasstchance:BAAALgAECgUJEgAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8dAAIBAAgJKBonLAARAgABAAgJKBonLAARAgAAAA==.',
Le='Leijona:BAAALgAECgEJAwAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgADCgMJAwAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Likeatrain:BAABLgAECn8mAAIlAAkJ0A1GFACEAQAlAAkJ0A1GFACEAQAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMhAAgJJRN/KADqAQAhAAgJJRN/KADqAQADAAUJDgjR4gCzAAAAAA==.Lilwagyu:BAAALgAFFAMJBAAAAA==.Linds:BAABLgAECn80AAMhAAkJOh6jEQBjAgAhAAkJOh6jEQBjAgADAAYJTQydwADkAAAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgcJEgAAAA==.Littlefoot:BAAALgAECgYJEAABLgAFFAMJBwAMAAMdAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8ZAAMIAAgJQha7FwC1AQAIAAgJQha7FwC1AQAQAAEJhxD2HwAzAAAAAA==.Lorralen:BAAALgAECgcJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn8rAAIKAAgJlRykEQARAgAKAAgJlRykEQARAgAAAA==.',
Lu='Luber:BAABLgAECn8kAAIRAAkJVQpnPwB+AQARAAkJVQpnPwB+AQAAAA==.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAABLgAECn9BAAIWAAkJoSXGAABVAwAWAAkJoSXGAABVAwAAAA==.Luxzy:BAAALgAECgcJCwAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgADCgQJBQAAAA==.Manbearcat:BAABLgAECn8dAAImAAkJPSAYCAAbAwAmAAkJPSAYCAAbAwAAAA==.Marbleous:BAACLgAFFH8KAAIMAAMJBiTdHAAZAQAMAAMJBiTdHAAZAQAuAAQKfxgAAgwABgm6I94gAMQBAAwABgm6I94gAMQBAAAA.Marina:BAAALgADCgcJDQAAAA==.',
Mc='Mcpink:BAAALgAECgQJCAABLgAECgkJHQAmAD0gAA==.Mcspicy:BAAALgADCgYJBwAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECgkJHQAiAFkfAA==.Melhina:BAAALgAECgUJCQABLgAECggJMAAiADAcAA==.Memisstotem:BAABLgAECn8eAAIRAAcJgRrPKADsAQARAAcJgRrPKADsAQAAAA==.Merle:BAACLgAFFH8HAAIMAAMJAx06IQD+AAAMAAMJAx06IQD+AAAuAAQKf0IAAwwACAmCJW8GAN0CAAwACAkiJG8GAN0CAA8ABQkCI4AOANcBAAAA.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAABLgAECn8UAAIOAAgJ8BUTMADmAQAOAAgJ8BUTMADmAQAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAABLgAECn8XAAIgAAcJTgtwLwAtAQAgAAcJTgtwLwAtAQAAAA==.Mistborn:BAABLgAECn8zAAQgAAkJPiEhCQC5AgAgAAkJPiEhCQC5AgAfAAQJ1RyJKQBMAQAbAAIJsBXIUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn8jAAIaAAgJGRMsDQCvAQAaAAgJGRMsDQCvAQAAAA==.Monkjamin:BAABLgAFFH8GAAInAAMJThf1KQDiAAAnAAMJThf1KQDiAAAAAA==.Moolimbo:BAABLgAECn8qAAICAAkJghhQEQA9AgACAAkJghhQEQA9AgAAAA==.Moonfawn:BAAALgAECgIJAgABLgAECgkJJAASAGcdAA==.Mooseboy:BAABLgAECn8tAAIaAAkJah5gAwC6AgAaAAkJah5gAwC6AgAAAA==.Mooserton:BAABLgAECn8lAAMhAAYJSA/hPAArAQAhAAYJSA/hPAArAQADAAYJrA9itQD1AAAAAA==.Mootalstrike:BAABLgAECn8uAAIMAAkJhhNNGwDuAQAMAAkJhhNNGwDuAQAAAA==.Moshworm:BAABLgAECn8nAAIEAAgJBQwAMwAdAQAEAAgJBQwAMwAdAQAAAA==.',
Mu='Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgEJAgAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAUJFwAXAH4bAA==.',
Na='Nalaxx:BAAALgAECgEJAQAAAA==.Natsumi:BAABLgAECn8WAAIRAAcJxgv8VAAqAQARAAcJxgv8VAAqAQAAAA==.',
Ne='Neeners:BAABLgAECn8UAAITAAYJVQPRQwDRAAATAAYJVQPRQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn81AAIcAAkJUR10HwCHAgAcAAkJUR10HwCHAgAAAA==.Neuroticaine:BAABLgAECn81AAMbAAgJLhVHIACcAQAbAAgJLhVHIACcAQAfAAQJCA6FPQDfAAAAAA==.Nev:BAACLgAFFH8QAAMXAAQJZiGmFQBpAQAXAAQJZiGmFQBpAQAdAAMJ6AVCGQDAAAAuAAQKfyEAAxcACAncIsYjAC8CABcABwkjIsYjAC8CAB0ABwmhHLEkAAICAAAA.Nexassin:BAABLgAFFH8IAAIIAAMJ2AJ6IwCuAAAIAAMJ2AJ6IwCuAAAAAA==.',
Ni='Nico:BAABLgAECn8ZAAIZAAkJxBEjEQCxAQAZAAkJxBEjEQCxAQAAAA==.Nimz:BAABLgAECn8dAAQiAAkJWR/PAgBrAgAiAAkJUx/PAgBrAgAYAAcJIBrgBwClAQABAAIJrRPO7ACBAAAAAA==.',
No='Noctrine:BAAALgADCgMJAwAAAA==.Nooblets:BAACLgAFFH8HAAIIAAMJ/xpdHQD2AAAIAAMJ/xpdHQD2AAAuAAQKfxsAAggABwnMIOkVAMgBAAgABwnMIOkVAMgBAAAA.Noradia:BAAALgAECgMJBAAAAA==.Noxxic:BAAALgAECgMJAwAAAA==.Noxxidari:BAABLgAECn8hAAMOAAgJBxIzXQBNAQAOAAgJBxIzXQBNAQAGAAIJwhQMKQA7AAAAAA==.Noxxus:BAABLgAECn8fAAINAAkJvRqdDAD9AQANAAkJvRqdDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymphis:BAAALgADCgYJFAAAAA==.Nymz:BAAALgAECgMJAwABLgAECgkJHQAiAFkfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôpmage:BAAALgAECgYJBQAAAA==.Nôwôrries:BAEALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBgAAAA==.',
Of='Offended:BAAALgAECgYJCQAAAA==.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgUJBgABLgAECgkJKgACAIIYAA==.',
Om='Omnivus:BAAALgAECgMJAwAAAA==.',
On='One:BAAALgADCgMJAwAAAA==.Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCwAhAFAbAA==.Oratherah:BAABLgAFFH8LAAIWAAMJziRkGwDOAAAWAAMJziRkGwDOAAAAAA==.Orbs:BAAALgAECgEJAQAAAA==.Orchist:BAABLgAECn8dAAIMAAkJOCCXCAC4AgAMAAkJOCCXCAC4AgAAAA==.',
Ow='Owlyheals:BAAALgADCgQJBAAAAA==.',
Oz='Ozôls:BAAALgAECggJDAAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Palei:BAAALgAECgYJBgAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn81AAIVAAgJMwffEgAGAQAVAAgJMwffEgAGAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgkJKgACAIIYAA==.',
Ph='Phenothal:BAAALgADCgIJAgAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgkJFAAUAOUbAA==.Pinkymcpink:BAAALgAECgEJAQABLgAECgkJHQAmAD0gAA==.Pitchblende:BAABLgAECn8xAAIhAAkJMBLiGQAPAgAhAAkJMBLiGQAPAgAAAA==.',
Po='Poeppsul:BAAALgADCgMJAwAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAUJEAAUAOEkAA==.Porthub:BAABLgAECn8pAAIcAAkJLAnrYgCcAQAcAAkJLAnrYgCcAQAAAA==.',
Pr='Protagoras:BAAALgAECgcJBwAAAA==.',
Pu='Purejoy:BAAALgAECgcJDwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qq='Qqcumber:BAAALgADCgIJAgAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAAALgAECgUJDgAAAA==.Rajak:BAAALgAECgEJAQAAAA==.Range:BAAALgAECgEJAQAAAA==.Raph:BAAALgAECgEJAQAAAA==.Rathibrew:BAACLgAFFH8ZAAInAAUJwSNCCgCeAQAnAAUJwSNCCgCeAQAuAAQKfzgAAicACQmcJLEBADwDACcACQmcJLEBADwDAAAA.',
Re='Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgYJCQAAAA==.Rellt:BAAALgADCgIJAgAAAA==.Remnants:BAABLgAECn8UAAInAAYJihvDJwDIAQAnAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAAALgAECgYJDwAAAA==.',
Rh='Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBwAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgADCgYJBwAAAA==.',
Ro='Rockyx:BAAALgAECgQJBwAAAA==.Roll:BAAALgADCgcJBwABLgAFFAMJDQAWAF8mAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAACLgAFFH8JAAMUAAUJoQ9gTwAtAQAUAAUJoQ9gTwAtAQAVAAEJUQ17GABHAAAuAAQKfy8AAhQACQnGHzMhAGECABQACQnGHzMhAGECAAAA.',
['Rê']='Rêzìcå:BAAALgADCgkJCQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAAALgAECgcJDQAAAA==.Salezar:BAABLgAECn8kAAISAAkJZx2nAQCyAgASAAkJZx2nAQCyAgAAAA==.Sandoud:BAABLgAECn8ZAAIEAAkJ6xOKFAAGAgAEAAkJ6xOKFAAGAgAAAA==.Sapientia:BAABLgAECn8sAAIDAAkJuAdAdQBjAQADAAkJuAdAdQBjAQAAAA==.Saragon:BAAALgAECgcJDQABLgAECggJOwAFADwaAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgADCgEJAQAAAA==.',
Sc='Scottkill:BAACLgAFFH8GAAIhAAQJcw/bHQABAQAhAAQJcw/bHQABAQAuAAQKfyEAAyEACAlaGMcZAEUCACEACAlaGMcZAEUCAAMAAQnyDycyAT8AAAEuAAUUCAkdABwAGhoA.',
Se='Sebaux:BAAALgAECgQJCgAAAA==.Segur:BAAALgAFFAEJAQAAAA==.Selenesul:BAABLgAECn8pAAMDAAkJ9RwPFgChAgADAAkJ9RwPFgChAgANAAMJTAynNAB0AAAAAA==.Selyda:BAAALgADCgUJBgAAAA==.Senzie:BAACLgAFFH8MAAIKAAQJdRnICwA+AQAKAAQJdRnICwA+AQAuAAQKfyUAAgoACQkiHvoJAIACAAoACQkiHvoJAIACAAEuAAUUBQkPAAoA9hQA.Sevro:BAAALgADCgQJBAABLgAECgkJHQAhAEcRAA==.',
Sh='Shadowdrake:BAABLgAECn8XAAITAAkJqAonJwCHAQATAAkJqAonJwCHAQAAAA==.Shadowheàrt:BAABLgAECn8YAAMhAAYJcxjZNABUAQAhAAUJThjZNABUAQADAAQJkAJtKAFXAAAAAA==.Shadowshifty:BAABLgAECn8XAAIoAAYJcQ/GJQDfAAAoAAYJcQ/GJQDfAAAAAA==.Shadowtotem:BAAALgADCgkJDQAAAA==.Shaeen:BAAALgAECgUJBQAAAA==.Shagi:BAABLgAECn8ZAAInAAgJGBUZGgC2AQAnAAgJGBUZGgC2AQAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharroz:BAABLgAECn8dAAMVAAcJiB1oAwBWAgAVAAcJiB1oAwBWAgAWAAQJVQ5qNgCOAAAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8eAAMfAAcJ6xr7GgDKAQAfAAcJ6xr7GgDKAQAbAAEJJQKaaQAlAAABLgAFFAUJCQAUAKEPAA==.Shockybalboa:BAABLgAECn8UAAICAAcJNBOVKwBrAQACAAcJNBOVKwBrAQAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Silvver:BAAALgAECgMJBAAAAA==.Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skooda:BAABLgAECn8tAAICAAkJaA5tJgCKAQACAAkJaA5tJgCKAQAAAA==.Skyded:BAABLgAECn8yAAIUAAkJLBkEJgBIAgAUAAkJLBkEJgBIAgAAAA==.Skyknight:BAABLgAECn8hAAIMAAkJnBNZIADIAQAMAAkJnBNZIADIAQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8LAAMZAAQJZBZMDQBEAQAZAAQJZBZMDQBEAQAdAAIJBwsgHACCAAAuAAQKfzsAAxkACQlyI9cCAP8CABkACQlQItcCAP8CAB0ACAnWHuoSAJ8CAAAA.',
Sn='Snapahead:BAAALgADCgIJAgAAAA==.Sneakytony:BAAALgADCgcJBwAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8dAAIOAAgJjBwMKgACAgAOAAgJjBwMKgACAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAAALgAECgYJCwAAAA==.Soralas:BAAALgAECgYJCgAAAA==.',
Sp='Spaazz:BAABLgAECn8gAAIDAAgJmB89KABAAgADAAgJmB89KABAAgAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.',
St='Starweaver:BAABLgAECn8jAAMgAAkJdBESJACAAQAgAAgJJhMSJACAAQAfAAgJawbYKQBVAQAAAA==.Stellmarine:BAABLgAECn8dAAIEAAkJzRrYFQD4AQAEAAkJzRrYFQD4AQAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgQJBgAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8yAAMoAAkJIhtIBgBpAgAoAAkJ4RpIBgBpAgAEAAYJBBrnKgCqAQAAAA==.',
Su='Subzro:BAAALgAECgUJBwAAAA==.Sunamé:BAAALgAECgQJBwAAAA==.',
Sw='Swaazil:BAABLgAECn8iAAIcAAkJgg7PaACOAQAcAAkJgg7PaACOAQAAAA==.Swan:BAAALgAFFAIJBAAAAA==.Swiftsama:BAAALgAECgEJAQABLgAECgcJEAALAAAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8cAAIOAAcJuwqAeAAJAQAOAAcJuwqAeAAJAQAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taloriesh:BAACLgAFFH8HAAIgAAMJ3x6BEQAPAQAgAAMJ3x6BEQAPAQAuAAQKfyQAAyAACAkvGwcSACkCACAACAkvGwcSACkCABsAAQk+FepgADYAAAAA.Tanazir:BAEALgAECggJEgAAAA==.Taric:BAAALgAECgEJAQAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAABLgAECn8VAAIKAAgJwA8RIgB2AQAKAAgJwA8RIgB2AQAAAA==.',
Te='Techytechy:BAABLgAECn8eAAIYAAgJnBxzAwA1AgAYAAgJnBxzAwA1AgAAAA==.Tenebris:BAEALgAECgMJAwABLgAECggJEgALAAAAAA==.Tennmage:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrakk:BAAALgAECgQJBAAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIDAAkJLBlZRQATAgADAAkJLBlZRQATAgAAAA==.',
Ti='Tigermaster:BAABLgAECn8VAAIXAAcJ1AWsewAZAQAXAAcJ1AWsewAZAQAAAA==.Tilamano:BAABLgAECn85AAQYAAkJpSU7AQC/AgAYAAgJ0iQ7AQC/AgAiAAgJOiTJAQCnAgABAAgJMiTMHgBSAgAAAA==.',
Tm='Tmntmikey:BAABLgAFFH8PAAMJAAUJ5Q8vFwBFAQAJAAUJ5Q8vFwBFAQAnAAMJbgEXOACbAAAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMXAAcJRCMZHwBLAgAXAAcJgCIZHwBLAgAdAAYJMSMUIgAVAgABLgAECggJEwALAAAAAA==.Tonberry:BAAALgAECgkJBgAAAA==.Tonycheeks:BAAALgAECgQJBQAAAA==.Tonyhunter:BAAALgADCgYJBgAAAA==.Toogie:BAAALgAECgIJAwABLgAECggJGgAnANAgAA==.Tookie:BAAALgADCgYJBgABLgAECggJGgAnANAgAA==.Toophie:BAAALgADCgIJAgABLgAECggJGgAnANAgAA==.Toopie:BAABLgAECn8aAAMnAAgJ0CBlCwDXAgAnAAgJySBlCwDXAgAKAAUJbxkkOAA9AQAAAA==.',
Tr='Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8eAAImAAgJJBlrIgASAgAmAAgJJBlrIgASAgAAAA==.Tryath:BAABLgAECn8ZAAMmAAgJ4wrQZQDiAAAmAAcJcAjQZQDiAAAEAAQJzAmVVwCAAAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.Turtlegrnade:BAAALgADCgEJAQAAAA==.Tuzzyfits:BAAALgAECgEJAQAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8NAAIYAAQJ7RYqBwDpAAAYAAQJ7RYqBwDpAAAuAAQKfyQAAhgACQl8G2oCAOUCABgACQl8G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIZAAkJCh8hAwABAwAZAAkJCh8hAwABAwAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJDwAAAA==.',
Um='Umbrute:BAABLgAECn8rAAIOAAkJQiBfEwDlAgAOAAkJQiBfEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgcJGQAcALwVAA==.',
Va='Vader:BAAALgAECgMJAwAAAA==.Valcristo:BAABLgAECn86AAINAAkJiSNlAQAdAwANAAkJiSNlAQAdAwAAAA==.Valros:BAAALgADCgEJAQAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgQJBgABLgAECggJFgAUANURAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8qAAMIAAkJnxbQDwANAgAIAAkJshXQDwANAgAQAAUJ8xGAEwDJAAAAAA==.Verdraxa:BAAALgAECgEJAQAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn8uAAIXAAgJpRuEJwAXAgAXAAgJpRuEJwAXAgAAAA==.',
Vi='Vicariana:BAACLgAFFH8ZAAIfAAUJrCW2CgAKAgAfAAUJrCW2CgAKAgAuAAQKfywAAx8ACQnfJhEAAPkDAB8ACQnfJhEAAPkDABsAAQnWIZxdAGIAAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAECgYJCwAAAA==.Vidette:BAAALgADCgYJEQAAAA==.Viduus:BAAALgAECgQJBgABLgAECgkJHQAiAFkfAA==.Viv:BAABLgAECn8jAAMNAAgJ8SK8BQCWAgANAAcJPCS8BQCWAgADAAYJEiNWOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8bAAIDAAgJsQWhmgAfAQADAAgJsQWhmgAfAQAAAA==.Voideddn:BAAALgADCgYJBgAAAA==.Voldermort:BAAALgAECgcJCgAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAAALgAECgYJEwABLgAFFAMJAwALAAAAAA==.Warrendemon:BAACLgAFFH8XAAIOAAUJFCYGFACtAQAOAAUJFCYGFACtAQAuAAQKfzUAAw4ACQkDJrsBAMADAA4ACQkDJrsBAMADAAUAAwn9InlDAOkAAAAA.Waygun:BAAALgADCgYJBgAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAIcAAkJWBOvUgA/AgAcAAkJWBOvUgA/AgAAAA==.Wildheart:BAABLgAECn8bAAMaAAgJiCB5BgBKAgAaAAgJMiB5BgBKAgAoAAMJ+xQHLgCuAAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.Wissa:BAAALgAECgEJAQAAAA==.',
Wo='Wowbelly:BAACLgAFFH8IAAIJAAQJggxZIgDhAAAJAAQJggxZIgDhAAAuAAQKfxsAAgkABwnFG0EWABECAAkABwnFG0EWABECAAAA.Wowbellyjr:BAAALgAFFAEJAQABLgAFFAQJCAAJAIIMAA==.',
Xa='Xaanii:BAAALgADCgcJCAAAAA==.Xandon:BAAALgAECgUJCQAAAA==.',
Xo='Xonk:BAACLgAFFH8VAAIiAAUJPRPXAgA/AQAiAAUJPRPXAgA/AQAuAAQKfyQAAiIACQkQICwBAPECACIACQkQICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAECggJFgAUANURAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgUJDwAAAA==.',
Yu='Yuuna:BAAALgAECgMJBQAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAABLgAECn8TAAMFAAcJQQi9KQD0AAAFAAcJQQi9KQD0AAAOAAYJ+QKRvgB6AAAAAA==.Zaps:BAABLgAECn8pAAIpAAkJKCNJAQASAwApAAkJKCNJAQASAwAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCgkJDAAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8cAAIcAAcJlhNBbwB/AQAcAAcJlhNBbwB/AQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zebco:BAAALgADCgQJBAAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn8wAAMRAAkJsguOQAB5AQARAAkJsguOQAB5AQACAAYJywjAUADEAAAAAA==.Zenreto:BAABLgAECn8zAAIQAAgJKB7cAwA/AgAQAAgJKB7cAwA/AgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8RAAIcAAUJjCF5KgB5AQAcAAUJjCF5KgB5AQAuAAQKfysAAhwACAnAJG0SADkDABwACAnAJG0SADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8YAAIpAAUJBx/sAgByAQApAAUJBx/sAgByAQAuAAQKfyAAAikACQm1IcMAAI8DACkACQm1IcMAAI8DAAAA.',
['Îl']='Îllîdan:BAABLgAFFH8FAAIOAAIJYg7hYgCOAAAOAAIJYg7hYgCOAAAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8zAAMBAAkJuR1hFACUAgABAAkJuR1hFACUAgAYAAQJGwjCQQCuAAAAAA==.',
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
