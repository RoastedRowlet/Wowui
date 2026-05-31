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

local lookup = {'Warlock-Demonology','Priest-Holy','Priest-Shadow','Shaman-Restoration','Paladin-Retribution','Druid-Balance','Hunter-Survival','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Warrior-Fury','Paladin-Protection','DemonHunter-Devourer','Warrior-Arms','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Hunter-BeastMastery','Warlock-Destruction','Druid-Feral','Mage-Frost','Hunter-Marksmanship','Mage-Fire','Monk-Brewmaster','Mage-Arcane','Priest-Discipline','Warlock-Affliction','Rogue-Outlaw','Warrior-Protection','Druid-Restoration','Druid-Guardian',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE/OgAjAgABAAkJuxE/OgAjAgAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAABLgAECn8XAAMCAAYJ9hz5IgCVAQACAAUJEBz5IgCVAQADAAUJdg1CRgDPAAABLgAFFAYJDgAEAMwCAA==.',
Ae='Aethira:BAAALgAECgEJAwAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8+AAIFAAkJpiBeEQDHAgAFAAkJpiBeEQDHAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.Ainz:BAAALgADCgkJCQAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexr:BAAALgADCgMJAwAAAA==.Alfee:BAAALgAECgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.',
Am='Amarantus:BAAALgAECgUJCAABLgAFFAMJCQAGABgNAA==.Amarndeus:BAAALgADCgMJAwAAAA==.Ammerie:BAAALgAECgkJAgAAAA==.',
An='Anakim:BAAALgAECgQJBgAAAA==.Anmo:BAABLgAECn8VAAIHAAgJyRDGGQDCAQAHAAgJyRDGGQDCAQABLgAFFAYJGwAIAP8eAA==.Anmodru:BAAALgAECgYJBgABLgAFFAYJGwAIAP8eAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aonani:BAAALgAECggJBgAAAA==.Aotc:BAABLgAECn8WAAIJAAcJxw1rKwBsAQAJAAcJxw1rKwBsAQAAAA==.',
Aq='Aquaism:BAAALgADCgIJAgAAAA==.Aqulath:BAACLgAFFH8NAAIKAAQJjhopAwA2AQAKAAQJjhopAwA2AQAuAAQKfxYAAgoACQnOG+UDAHgCAAoACQnOG+UDAHgCAAAA.Aquílés:BAAALgAECgEJAQAAAA==.',
Ar='Arazensetal:BAABLgAECn89AAILAAkJCRrkBQCfAgALAAkJCRrkBQCfAgAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAYJEwAMAMAPAA==.Ariandrel:BAACLgAFFH8FAAINAAMJvwZRNgCNAAANAAMJvwZRNgCNAAAuAAQKfx4AAw0ACQkdEXslAMwBAA0ACQkdEXslAMwBAA4AAQlbAE+OABQAAAAA.Aridhol:BAAALgAECgcJDQAAAA==.Arkaedius:BAAALgAFFAEJAQAAAA==.Arker:BAAALgADCgIJAgAAAA==.',
As='Asashin:BAAALgADCgcJBwABLgAECgQJBAAPAAAAAA==.Asellus:BAAALgAECgcJDAAAAA==.Ashraun:BAAALgAECgMJBgAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn8tAAIJAAkJFB6bCACIAgAJAAkJFB6bCACIAgAAAA==.Atulno:BAAALgAECgYJBgAAAA==.',
Au='Aubrii:BAAALgAECgEJAQAAAA==.Aukatsang:BAACLgAFFH8OAAIOAAYJ1x43BQCjAQAOAAYJ1x43BQCjAQAuAAQKfyoAAg4ACQmTI10BAKMDAA4ACQmTI10BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.Auroraa:BAAALgADCgYJBgAAAA==.',
Az='Azymor:BAAALgADCggJDgAAAA==.',
Ba='Baddy:BAABLgAECn8fAAIQAAgJ9xz+FAClAgAQAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIOAAQJvRy3DgAzAQAOAAQJvRy3DgAzAQAuAAQKfyQAAg4ACAndHpEJAN8CAA4ACAndHpEJAN8CAAAA.Baladeva:BAABLgAECn88AAIRAAkJIR3fBACUAgARAAkJIR3fBACUAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECgkJPgAFAKYgAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgMJAwAAAA==.',
Be='Bearhold:BAAALgAECgQJBAAAAA==.Beefy:BAAALgAECgMJAwAAAA==.Beenis:BAAALgAECgEJAQAAAA==.Beersnob:BAABLgAECn8kAAINAAkJLxYOGgAhAgANAAkJLxYOGgAhAgAAAA==.Benjam:BAACLgAFFH8TAAISAAcJrRYiDwD7AQASAAcJrRYiDwD7AQAuAAQKfygAAhIABwnlI0wZAL0CABIABwnlI0wZAL0CAAAA.Benyo:BAAALgADCgIJAgAAAA==.',
Bi='Bigmikeyg:BAABLgAECn8+AAIFAAkJzhO1NwAKAgAFAAkJzhO1NwAKAgAAAA==.Bigsteve:BAABLgAECn8xAAMQAAkJ8CJlAwAkAwAQAAkJ8CJlAwAkAwATAAgJ1hK2FwCGAQAAAA==.',
Bl='Blanket:BAACLgAFFH8MAAMUAAMJJwo3BwDWAAAMAAMJiQWXDwD0AAAUAAMJJwo3BwDWAAAuAAQKfxYAAwwABwlSHPUqAKUBAAwABwkjHPUqAKUBABQAAwmaGgAAAAAAAAAA.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJCgAQAAYkAA==.',
Br='Brewtel:BAAALgADCgcJBwABLgAECgQJBAAPAAAAAA==.Bricked:BAAALgAECgIJBAAAAA==.Bronzesun:BAAALgADCgYJBgAAAA==.',
Bu='Bubbahowl:BAAALgADCgEJAQAAAA==.Bukara:BAAALgAECgUJCAAAAA==.Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8jAAIEAAkJMRqCFQCFAgAEAAkJMRqCFQCFAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgYJDwAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8eAAQLAAkJHQX8IgBhAQALAAkJHQX8IgBhAQAVAAMJGgjIMgCAAAAWAAMJ0AhGbgBlAAAAAA==.Calizon:BAAALgAECgkJEQAAAA==.Camc:BAAALgAECgQJDwAAAA==.Canowhoopass:BAABLgAECn8mAAIXAAgJvAooPAAoAQAXAAgJvAooPAAoAQAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cerassin:BAACLgAFFH8cAAISAAYJtxngGwCZAQASAAYJtxngGwCZAQAuAAQKfzYAAhIACQkJIeAIAPUCABIACQkJIeAIAPUCAAAA.Cereas:BAABLgAECn87AAIJAAgJPBr7DwAIAgAJAAgJPBr7DwAIAgAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgYJCAAAAA==.Chichobelo:BAABLgAFFH8LAAQYAAYJFhz/HQC0AQAYAAUJWhv/HQC0AQAZAAEJuR7yGgBWAAAaAAEJAAD8RwAAAAAAAA==.Chuckrutis:BAACLgAFFH8FAAIWAAQJGw95KQAAAQAWAAQJGw95KQAAAQAuAAQKfx8AAxUABglBH3AMABQCABUABglSHnAMABQCABYAAwk4HxVHAOsAAAAA.',
Cl='Cliché:BAABLgAECn8VAAMbAAYJvRZlMQB8AQAbAAYJvRZlMQB8AQAFAAYJMgeJ1gDLAAAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8XAAIcAAUJfhtGKwBAAQAcAAUJfhtGKwBAAQAuAAQKfyoAAhwACQk6IXYCAHEDABwACQk6IXYCAHEDAAAA.',
Co='Coldandwet:BAABLgAFFH8LAAIYAAMJDRQsdQD0AAAYAAMJDRQsdQD0AAAAAA==.Combination:BAABLgAECn8+AAIdAAkJniD6AADtAgAdAAkJniD6AADtAgABLgAFFAcJIgAFABAdAA==.Constrace:BAAALgAECgUJBwAAAA==.Corvenall:BAABLgAECn83AAIVAAgJlw1qCgBkAQAVAAgJlw1qCgBkAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAAALgAECggJEQAAAA==.Crossbow:BAACLgAFFH8IAAIcAAMJABNzUgDaAAAcAAMJABNzUgDaAAAuAAQKfz0AAhwACQnLHxsPAMICABwACQnLHxsPAMICAAAA.Crystoph:BAAALgAECgEJAQABLgAFFAQJDQAKAI4aAA==.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Cy='Cylan:BAAALgADCgYJBgABLgAECggJOwAJADwaAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Dante:BAAALgAECgIJAwABLgAECgkJGwAHAAoSAA==.Darkluster:BAAALgAECgUJCgAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.',
De='Deathbcmesyu:BAABLgAECn8XAAIYAAgJfxBYfABVAQAYAAgJfxBYfABVAQAAAA==.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demonheart:BAAALgAECgQJBAABLgAECgkJHQAeANUgAA==.Demorian:BAAALgAECgEJAQABLgAECggJJwADANoNAA==.Deondre:BAAALgAECgQJCAAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.Devoutheart:BAAALgAECgQJBAABLgAECgkJHQAeANUgAA==.',
Di='Diehappy:BAABLgAECn8WAAMZAAUJ9ArsHQCqAAAZAAUJ9ArsHQCqAAAaAAUJ+gbJPACFAAAAAA==.Dillie:BAAALgADCgMJAwAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgcJDQAAAA==.',
Do='Domevoker:BAAALgAFFAMJAwABLgAFFAYJGgAKAMUjAA==.Dompal:BAAALgAECgMJBgABLgAFFAYJGgAKAMUjAA==.Donkystyle:BAAALgAECgQJBgAAAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dragonshark:BAAALgADCgEJAQAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAkJMQAfAGImAA==.Drovinos:BAAALgAECgYJBgAAAA==.Druken:BAAALgAECgUJCwAAAA==.Drybonez:BAABLgAECn8UAAIfAAYJ0Aha+AAKAQAfAAYJ0Aha+AAKAQAAAA==.Drylie:BAACLgAFFH8UAAMcAAYJMSTGHABmAQAcAAUJCCTGHABmAQAgAAIJSR+pIABuAAAuAAQKfyMAAyAACQm3JNIJAAYDACAACAmdItIJAAYDABwAAwlvI0yNAAsBAAAA.Dràgonkíng:BAABLgAECn8VAAMhAAgJFwT3CADNAAAhAAgJFwT3CADNAAAfAAEJOwC/iwEGAAAAAA==.',
Dt='Dtinnel:BAABLgAECn8nAAIQAAkJWRyrEABfAgAQAAkJWRyrEABfAgABLgAFFAUJDgAYAF4VAA==.',
Du='Dumbledussy:BAABLgAECn8nAAIDAAgJ2g1xKwBYAQADAAgJ2g1xKwBYAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.Dustinterp:BAAALgAECgQJBwAAAA==.',
Ed='Edanor:BAAALgAECgQJBQABLgAECgkJKwAVAKYfAA==.',
Eg='Ego:BAABLgAECn83AAIQAAkJMiTTBQDwAgAQAAkJMiTTBQDwAgAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elrondo:BAAALgAECgEJAQAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQAfAHciAA==.Emmone:BAAALgAECgUJDwAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.',
En='Endo:BAAALgAECgEJAQAAAA==.Entuidax:BAAALgAFFAIJAgABLgAFFAQJDAAiAO4TAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAAALgAECgYJCgAAAA==.Excaleon:BAAALgAECgUJCQAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Farglight:BAAALgAECgQJBAAAAA==.Faunna:BAACLgAFFH8JAAIGAAMJGA2hKwCuAAAGAAMJGA2hKwCuAAAuAAQKfz0AAgYACQmEIFkGAOICAAYACQmEIFkGAOICAAAA.',
Fe='Feath:BAAALgAECgkJAQAAAA==.Feebeeboofae:BAAALgAECgIJAgAAAA==.Felaz:BAABLgAECn82AAIjAAkJJCDPAADQAgAjAAkJJCDPAADQAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.Ferreii:BAAALgAECgEJAQAAAA==.',
Fi='Fingerguns:BAACLgAFFH8GAAIkAAMJMQQlLgCrAAAkAAMJMQQlLgCrAAAuAAQKfx0ABCQACQndFVwQAEwCACQACQndFVwQAEwCAAIAAwl3CO5mAJEAAAMAAwkJCMJkAFwAAAAA.Fionaa:BAABLgAECn8dAAMBAAkJOAWNcwBHAQABAAkJDQWNcwBHAQAdAAEJsAfxeAAqAAAAAA==.Fiyona:BAAALgAECgMJBgAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgADCgMJAwAAAA==.Floortank:BAABLgAECn8tAAMYAAgJqAdukgAtAQAYAAgJAQZukgAtAQAZAAcJSwdVGQDUAAAAAA==.',
Fo='Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAACLgAFFH8LAAIbAAMJUBuTJADmAAAbAAMJUBuTJADmAAAuAAQKfxsAAhsABwnKI4sRAIcCABsABwnKI4sRAIcCAAAA.Frikilatar:BAAALgAECgEJBgAAAA==.Frostyhatesu:BAEALgADCgMJAwABLgAECgIJAwAPAAAAAA==.Frrank:BAACLgAFFH8aAAITAAYJwyWpAwAJAgATAAYJwyWpAwAJAgAuAAQKfzMAAhMACQkeJWEAALQDABMACQkeJWEAALQDAAAA.',
Fu='Fullerene:BAAALgAECgEJAgAAAA==.',
Ga='Galcain:BAACLgAFFH8GAAMcAAMJbR0QRAD/AAAcAAMJbR0QRAD/AAAHAAMJtQ9QHgDEAAAuAAQKfywABBwACAn7IvYHABEDABwACAm2IvYHABEDAAcABwlDFbceAJgBACAAAwlUGtBgAL0AAAAA.Galkhan:BAAALgAECgQJBAABLgAFFAMJBgAcAG0dAA==.Gardonea:BAAALgADCggJDgAAAA==.',
Gh='Ghostmain:BAAALgAECgQJBgABLgAECgcJAgAPAAAAAA==.',
Gi='Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAABLgAECn8mAAIfAAgJhxOPZgCXAQAfAAgJhxOPZgCXAQAAAA==.Glaivizzon:BAAALgAECgIJAwAAAA==.Glamor:BAAALgAECgQJBAAAAA==.',
Go='Gorizarev:BAAALgAECgQJCgAAAA==.',
Gr='Grippysox:BAAALgADCgYJBgAAAA==.Grogtar:BAAALgADCgMJAwAAAA==.Grumandel:BAABLgAECn89AAIeAAkJXxa5CAAgAgAeAAkJXxa5CAAgAgAAAA==.',
Gu='Guce:BAAALgAECgYJCQAAAA==.Gudetama:BAABLgAECn8ZAAMcAAgJTiHBFwB7AgAcAAYJESPBFwB7AgAHAAYJ/h2zFQDpAQAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgYJCgAAAA==.Haidie:BAAALgADCgEJAQAAAA==.Hakur:BAABLgAECn87AAIFAAkJQhxCKQBEAgAFAAkJQhxCKQBEAgAAAA==.Hamahara:BAAALgAECgYJBwAAAA==.Hanma:BAACLgAFFH8VAAIYAAcJgBltEgD7AQAYAAcJgBltEgD7AQAuAAQKfygAAhgACQkFHxEsAIgCABgACQkFHxEsAIgCAAAA.Harribel:BAABLgAECn81AAIfAAgJjA7PhABSAQAfAAgJjA7PhABSAQAAAA==.',
He='Heimdall:BAAALgADCgQJAQAAAA==.Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgADCgYJBgAAAA==.Hiroki:BAABLgAECn8oAAIYAAgJ9gsOcABwAQAYAAgJ9gsOcABwAQAAAA==.Hitachitotem:BAACLgAFFH8WAAIXAAQJzhTUGwAYAQAXAAQJzhTUGwAYAQAuAAQKfxkAAhcACAmtGl0aAEACABcACAmtGl0aAEACAAAA.Hiyoda:BAAALgAECgYJCAAAAA==.Hiyodal:BAAALgAECgEJAQAAAA==.Hiyodam:BAAALgADCgEJAQAAAA==.Hiyodat:BAAALgAECgMJAwAAAA==.Hiyodaw:BAAALgAECgUJCAAAAA==.Hizzon:BAAALgADCgcJDAAAAA==.',
Ho='Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAABLgAECn8XAAISAAkJ2ho/HABXAgASAAkJ2ho/HABXAgAAAA==.Holymaet:BAAALgADCgEJAQABLgAFFAMJCgAQAPQfAA==.Holyphatso:BAAALgADCgMJAwABLgAECgkJKQACACsgAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAABLgAECn8hAAIfAAkJ9BNgRgDxAQAfAAkJ9BNgRgDxAQAAAA==.',
In='Inflikted:BAABLgAECn8lAAIYAAkJVQh7awB6AQAYAAkJVQh7awB6AQAAAA==.Interwebz:BAABLgAECn8cAAMYAAkJHh15HQCDAgAYAAkJKxx5HQCDAgAaAAIJ9h0DOACbAAAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgAECgQJBAAPAAAAAA==.Jazzarin:BAAALgAECgMJAwAAAA==.',
Je='Jehannum:BAABLgAECn8cAAIXAAgJlQ09PgAfAQAXAAgJlQ09PgAfAQAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgUJEAAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAABLgAFFH8FAAIbAAMJZBv/JADjAAAbAAMJZBv/JADjAAABLgAFFAQJGwAEAB4kAA==.Josen:BAAALgAECgEJAQAAAA==.',
Ju='Juliana:BAAALgADCgMJAwAAAA==.Jurkzarbirt:BAAALgAECgMJAwAAAA==.',
Jz='Jz:BAAALgAECgQJBwAAAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIDAAgJ0hfNIAChAQADAAgJ0hfNIAChAQAAAA==.',
Ka='Kaelibrimbor:BAAALgAECgcJBwAAAA==.Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAAALgAECgUJCAAAAA==.Katarena:BAABLgAECn83AAIbAAgJVRD0LQCQAQAbAAgJVRD0LQCQAQAAAA==.Kathyra:BAABLgAECn8mAAMBAAkJiQwXTgClAQABAAkJiQwXTgClAQAlAAEJ7wEjNwAnAAAAAA==.Kavax:BAABLgAECn8lAAIbAAkJXxTFFwA0AgAbAAkJXxTFFwA0AgAAAA==.',
Ke='Keel:BAAALgAECggJEgAAAA==.Keeller:BAACLgAFFH8TAAIFAAYJlw9xHQBsAQAFAAYJlw9xHQBsAQAuAAQKfzYAAgUACQkKHuouACwCAAUACQkKHuouACwCAAAA.Keggor:BAAALgAECgEJAgAAAA==.Kentyr:BAABLgAECn8xAAMMAAgJMxE4GgCuAQAMAAgJMxE4GgCuAQAmAAIJZwGDDgA0AAAAAA==.Keolus:BAAALgAECgQJBQAAAA==.',
Kh='Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgAECgMJAwABLgAFFAMJCgAQAPQfAA==.Kinký:BAABLgAECn8vAAMQAAkJNBbmFAA2AgAQAAkJNBbmFAA2AgATAAEJ2xSjZQA3AAABLgAECgYJEAAPAAAAAA==.Kiraelis:BAABLgAECn8lAAIgAAkJqg9ACwCeAQAgAAkJqg9ACwCeAQAAAA==.Kisara:BAAALgADCgQJBAABLgAFFAMJAwAPAAAAAA==.Kiss:BAAALgADCgEJAQABLgAFFAEJAQAPAAAAAA==.Kivea:BAABLgAECn8aAAMfAAkJZg+MXgCrAQAfAAkJZg+MXgCrAQAhAAEJBAcAEgAqAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECggJDwAAAA==.Konagda:BAAALgADCggJEQAAAA==.Korvoh:BAABLgAECn8+AAMkAAkJohtPCADVAgAkAAkJmRtPCADVAgACAAMJUxeOXQC8AAAAAA==.',
Kr='Kringe:BAABLgAECn8sAAIXAAkJRCNMBAAPAwAXAAkJRCNMBAAPAwAAAA==.Krynn:BAAALgAECgYJBgAAAA==.',
Ku='Kumonk:BAABLgAECn8cAAIOAAcJWAZ2QgDdAAAOAAcJWAZ2QgDdAAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBQAAAA==.',
['Kä']='Kämik:BAABLgAECn87AAIcAAgJLyF5FgCJAgAcAAgJLyF5FgCJAgAAAA==.',
['Kì']='Kìn:BAABLgAECn8YAAMkAAYJsAZcQgDUAAAkAAYJsAZcQgDUAAADAAIJbwOubgBBAAAAAA==.',
La='Lampion:BAABLgAECn8hAAIJAAkJdAz0GwB7AQAJAAkJdAz0GwB7AQAAAA==.Langris:BAAALgAECgEJAgAAAA==.Lasstchance:BAABLgAECn8XAAIcAAYJCQsnigARAQAcAAYJCQsnigARAQAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8mAAIBAAkJeR4ADgDQAgABAAkJeR4ADgDQAgAAAA==.',
Le='Leijona:BAAALgAECgEJAwAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgADCgMJAwAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Likeatrain:BAABLgAECn8sAAInAAkJ3g12FgB6AQAnAAkJ3g12FgB6AQAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMbAAgJJRN/KADqAQAbAAgJJRN/KADqAQAFAAUJDghD9wCiAAAAAA==.Lilwagyu:BAAALgAFFAMJBAAAAA==.Linds:BAABLgAECn85AAMbAAkJOh6AEwBfAgAbAAkJOh6AEwBfAgAFAAYJTQzW1ADOAAAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgcJEgAAAA==.Littlefoot:BAAALgAECgYJEAABLgAFFAMJCgAQAPQfAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8bAAMMAAgJlBe+FwDFAQAMAAgJlBe+FwDFAQAUAAEJhxD2HwAzAAAAAA==.Lorralen:BAAALgAECggJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn8uAAIOAAkJ+x4iCQCeAgAOAAkJ+x4iCQCeAgAAAA==.',
Lu='Luber:BAABLgAECn8kAAIEAAkJVQoJRQB9AQAEAAkJVQoJRQB9AQAAAA==.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAABLgAECn9JAAIaAAkJ9SWuAABmAwAaAAkJ9SWuAABmAwAAAA==.Luxzy:BAAALgAECggJDQAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgADCgQJBQAAAA==.Manbearcat:BAABLgAECn8hAAIoAAkJPSAaCQAYAwAoAAkJPSAaCQAYAwAAAA==.Marbleous:BAACLgAFFH8KAAIQAAMJBiRhIgARAQAQAAMJBiRhIgARAQAuAAQKfxgAAhAABgm6IxokAL8BABAABgm6IxokAL8BAAAA.Marina:BAAALgADCgcJDQAAAA==.',
Mc='Mcgrips:BAAALgAECgEJAQAAAA==.Mcpink:BAAALgAECgQJCAABLgAECgkJIQAoAD0gAA==.Mcspicy:BAAALgAECgMJAwAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECgkJHQAlAFkfAA==.Melhina:BAAALgAECgUJCQABLgAECggJNQAlAL8cAA==.Memisstotem:BAABLgAECn8eAAIEAAcJgRr8LADqAQAEAAcJgRr8LADqAQAAAA==.Merle:BAACLgAFFH8KAAIQAAMJ9B+gIQAVAQAQAAMJ9B+gIQAVAQAuAAQKf0gAAxAACQkNJXQCAD8DABAACQnYI3QCAD8DABMABgncJH8MAAkCAAAA.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAABLgAECn8ZAAISAAgJ7RmmJQAhAgASAAgJ7RmmJQAhAgAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAABLgAECn8dAAICAAcJmA1AMAA2AQACAAcJmA1AMAA2AQAAAA==.Mistborn:BAABLgAECn84AAQCAAkJiCKFBwDiAgACAAkJiCKFBwDiAgAkAAQJ1RyJKQBMAQADAAIJsBXIUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Modinn:BAAALgAECgEJAQABLgAECgkJKwAVAKYfAA==.Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn8rAAIeAAkJWhr5BQBtAgAeAAkJWhr5BQBtAgAAAA==.Monkjamin:BAABLgAFFH8GAAIiAAMJThfGLgDXAAAiAAMJThfGLgDXAAAAAA==.Moolimbo:BAABLgAECn8qAAIXAAkJghhYEwA5AgAXAAkJghhYEwA5AgAAAA==.Moonfawn:BAAALgAECgIJAgABLgAECgkJKwAVAKYfAA==.Mooseboy:BAABLgAECn8tAAIeAAkJah7zAwCvAgAeAAkJah7zAwCvAgAAAA==.Mooserton:BAABLgAECn8vAAMbAAcJNx3OFABRAgAbAAcJNx3OFABRAgAFAAYJrA8MxQDkAAAAAA==.Mootalstrike:BAABLgAECn8zAAIQAAkJbhUsGwAAAgAQAAkJbhUsGwAAAgAAAA==.Moshworm:BAABLgAECn8rAAIGAAkJygyzKgBjAQAGAAkJygyzKgBjAQAAAA==.',
Mu='Muramasa:BAAALgAECgEJAQABLgAFFAUJDgAYAF4VAA==.Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgEJAgAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAUJFwAcAH4bAA==.',
Na='Nalaxx:BAAALgAECgEJAQAAAA==.Natsumi:BAABLgAECn8WAAIEAAcJxgtTXAApAQAEAAcJxgtTXAApAQAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIWAAYJVQPRQwDRAAAWAAYJVQPRQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn84AAIfAAkJBh6KHgCQAgAfAAkJBh6KHgCQAgAAAA==.Neuroticaine:BAABLgAECn8+AAMDAAkJnBXZGADkAQADAAkJnBXZGADkAQAkAAQJCA5OQADeAAAAAA==.Nev:BAACLgAFFH8SAAMcAAQJsCHUHQBjAQAcAAQJsCHUHQBjAQAgAAMJ6AVCGQDAAAAuAAQKfyEAAxwACAncIsYjAC8CABwABwkjIsYjAC8CACAABwmhHLEkAAICAAAA.Nexassin:BAABLgAFFH8KAAIMAAMJbwmrJgC+AAAMAAMJbwmrJgC+AAAAAA==.',
Ni='Nico:BAABLgAECn8bAAIHAAkJChIjEQCxAQAHAAkJChIjEQCxAQAAAA==.Nimz:BAABLgAECn8dAAQlAAkJWR96AwBeAgAlAAkJUx96AwBeAgAdAAcJIBrnCACfAQABAAIJrRPO7ACBAAAAAA==.',
No='Noctrine:BAAALgADCgMJAwAAAA==.Nooblets:BAACLgAFFH8HAAIMAAMJ/xrCIQDsAAAMAAMJ/xrCIQDsAAAuAAQKfxsAAgwABwnMIAgYAMIBAAwABwnMIAgYAMIBAAAA.Noradia:BAAALgAECgMJBAAAAA==.Noxxic:BAAALgAECgcJCgAAAA==.Noxxidari:BAABLgAECn8iAAMSAAkJQBKVSgCOAQASAAkJQBKVSgCOAQAKAAIJwhSjLAA6AAAAAA==.Noxxus:BAABLgAECn8fAAIRAAkJvRqdDAD9AQARAAkJvRqdDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymz:BAAALgAECgMJAwABLgAECgkJHQAlAFkfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôpmage:BAAALgAECgYJBQAAAA==.Nôwôrries:BAEALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBgAAAA==.',
Of='Offended:BAAALgAECgcJDQAAAA==.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgUJBgABLgAECgkJKgAXAIIYAA==.',
Om='Omnivus:BAAALgAECgMJAwAAAA==.',
On='One:BAAALgADCgMJAwAAAA==.Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Op='Opinion:BAAALgADCgMJAwABLgAECgEJAgAPAAAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCwAbAFAbAA==.Oratherah:BAABLgAFFH8LAAIaAAMJziQmHwDHAAAaAAMJziQmHwDHAAAAAA==.Orbs:BAAALgAECgEJAQAAAA==.Orchist:BAABLgAECn8lAAIQAAkJPiJ2BQD4AgAQAAkJPiJ2BQD4AgAAAA==.',
Ow='Owlyheals:BAAALgADCgQJBAAAAA==.',
Oz='Ozôls:BAAALgAECggJDQAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Palei:BAAALgAECgYJBgAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn8+AAIZAAkJuwcKEQAzAQAZAAkJuwcKEQAzAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgkJKgAXAIIYAA==.',
Ph='Phenothal:BAAALgADCgIJAgAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgkJHAAYAB4dAA==.Pinkymcpink:BAAALgAECgEJAQABLgAECgkJIQAoAD0gAA==.Pitchblende:BAABLgAECn8xAAIbAAkJMBIoHAAMAgAbAAkJMBIoHAAMAgAAAA==.',
Po='Poeppsul:BAAALgADCgMJAwAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAUJEAAYAOEkAA==.Porthub:BAABLgAECn8pAAIfAAkJLAkfcQB+AQAfAAkJLAkfcQB+AQAAAA==.',
Pr='Protagoras:BAAALgAECgcJBwAAAA==.',
Pu='Purejoy:BAAALgAECgcJDwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qq='Qqcumber:BAAALgADCgIJAgAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAAALgAECgYJEwAAAA==.Rajak:BAAALgAECgIJAwAAAA==.Range:BAAALgAECgUJBgAAAA==.Raph:BAAALgAECgEJAQAAAA==.Rathibrew:BAACLgAFFH8aAAIiAAYJMCFVBwDhAQAiAAYJMCFVBwDhAQAuAAQKfzgAAiIACQmcJLwBAIwDACIACQmcJLwBAIwDAAAA.',
Re='Redine:BAAALgAECgIJAgAAAA==.Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgYJCQAAAA==.Rellt:BAAALgADCgIJAgAAAA==.Remnants:BAABLgAECn8UAAIiAAYJihvDJwDIAQAiAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAABLgAECn8UAAQCAAYJwAbLQQDOAAACAAYJwAbLQQDOAAADAAUJEAOwZgBWAAAkAAEJ4gFMegAMAAAAAA==.',
Rh='Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBwAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgAECgIJAgAAAA==.',
Ro='Rockyx:BAAALgAECgQJCAAAAA==.Roll:BAAALgADCgcJBwABLgAFFAQJBAAPAAAAAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAACLgAFFH8OAAMYAAUJXhWaTQA4AQAYAAUJXhWaTQA4AQAZAAEJUQ3/HQBGAAAuAAQKfzEAAhgACQnGHx0lAFwCABgACQnGHx0lAFwCAAAA.',
['Rê']='Rêzìcå:BAAALgADCgkJCQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAAALgAECgcJEQAAAA==.Salezar:BAABLgAECn8rAAIVAAkJph8fAQDwAgAVAAkJph8fAQDwAgAAAA==.Sandoud:BAABLgAECn8bAAIGAAkJ6xOiFgADAgAGAAkJ6xOiFgADAgAAAA==.Sapientia:BAABLgAECn8tAAIFAAkJqwjyfwBUAQAFAAkJqwjyfwBUAQAAAA==.Saragon:BAAALgAECgcJDQABLgAECggJOwAJADwaAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgADCgEJAQAAAA==.',
Sc='Scottkill:BAACLgAFFH8GAAIbAAQJcw9JIgD3AAAbAAQJcw9JIgD3AAAuAAQKfyEAAxsACAlaGMcZAEUCABsACAlaGMcZAEUCAAUAAQnyDycyAT8AAAEuAAUUCAkhAB8AThoA.',
Se='Sebaux:BAAALgAECgQJCwAAAA==.Segur:BAAALgAFFAIJAgAAAA==.Selenesul:BAABLgAECn8sAAMFAAkJ9RzBGQCRAgAFAAkJ9RzBGQCRAgARAAMJTAynNAB0AAAAAA==.Selyda:BAAALgADCgUJBgAAAA==.Senzie:BAACLgAFFH8PAAIOAAQJrRuECwBQAQAOAAQJrRuECwBQAQAuAAQKfyUAAg4ACQkiHnYLAHgCAA4ACQkiHnYLAHgCAAEuAAUUBQkPAA4A9hQA.Sevro:BAAALgADCgQJBAABLgAECgkJJQAbAF8UAA==.',
Sh='Shadowdrake:BAABLgAECn8ZAAIWAAkJqArmKwBxAQAWAAkJqArmKwBxAQAAAA==.Shadowheàrt:BAABLgAECn8cAAMbAAYJcxjIOABRAQAbAAUJThjIOABRAQAFAAQJNgVxHwFtAAAAAA==.Shadowshifty:BAABLgAECn8aAAIpAAYJcQ89KwDdAAApAAYJcQ89KwDdAAAAAA==.Shadowtotem:BAAALgADCgkJDQAAAA==.Shaeen:BAAALgAFFAMJAwAAAA==.Shagi:BAABLgAECn8eAAIiAAgJdhXKGwC1AQAiAAgJdhXKGwC1AQAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharroz:BAABLgAECn8dAAMZAAcJiB1oAwBWAgAZAAcJiB1oAwBWAgAaAAQJVQ62OgCOAAAAAA==.Shauna:BAAALgAFFAEJAQAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8hAAMkAAgJeBr5EwAfAgAkAAgJeBr5EwAfAgADAAEJJQKaaQAlAAABLgAFFAUJDgAYAF4VAA==.Shockybalboa:BAABLgAECn8UAAIXAAcJNBOPLwBoAQAXAAcJNBOPLwBoAQAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Silvver:BAAALgAECgMJBQAAAA==.Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skooda:BAABLgAECn8tAAIXAAkJaA70KQCIAQAXAAkJaA70KQCIAQAAAA==.Skyded:BAABLgAECn8yAAIYAAkJLBleKgBDAgAYAAkJLBleKgBDAgAAAA==.Skyknight:BAABLgAECn8hAAIQAAkJnBMUJAC/AQAQAAkJnBMUJAC/AQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8LAAMHAAQJZBYYEAA9AQAHAAQJZBYYEAA9AQAgAAIJBwtmHwB6AAAuAAQKfzsAAwcACQlyI3QDAPcCAAcACQlQInQDAPcCACAACAnWHuoSAJ8CAAAA.',
Sn='Snapahead:BAAALgAECgQJBAAAAA==.Sneakytony:BAAALgADCgcJBwAAAA==.Snowclaw:BAAALgADCgYJCwAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8mAAISAAkJwhp/HABVAgASAAkJwhp/HABVAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAAALgAECggJEAAAAA==.Soralas:BAAALgAECgcJEQAAAA==.',
Sp='Spaazz:BAABLgAECn8jAAIFAAkJsyFWEADPAgAFAAkJsyFWEADPAgAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.Spuds:BAAALgAECgEJAQAAAA==.',
St='Starweaver:BAABLgAECn8nAAMkAAkJkxKaJQB+AQAkAAkJ7weaJQB+AQACAAgJJhPEJgB5AQAAAA==.Stellmarine:BAABLgAECn8dAAIGAAkJzRoDGAD2AQAGAAkJzRoDGAD2AQAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgYJDAAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8yAAMpAAkJIhtHBwBmAgApAAkJ4RpHBwBmAgAGAAYJBBrnKgCqAQAAAA==.',
Su='Subzro:BAAALgAECgUJCQAAAA==.Sunamé:BAAALgAECgUJCwAAAA==.',
Sw='Swaazil:BAABLgAECn8mAAIfAAkJKxHyVQDDAQAfAAkJKxHyVQDDAQAAAA==.Swan:BAAALgAFFAIJBAAAAA==.Sweetlady:BAAALgAECgIJAgAAAA==.Swiftsama:BAAALgAECgEJAQABLgAECgcJEAAPAAAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8cAAISAAcJuwpphAD6AAASAAcJuwpphAD6AAAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taloriesh:BAACLgAFFH8HAAICAAMJ3x6oEwAEAQACAAMJ3x6oEwAEAQAuAAQKfycAAwIACQmJG3gLAJgCAAIACQmJG3gLAJgCAAMAAQk+FepgADYAAAAA.Tanazir:BAEBLgAECn8WAAIVAAgJxg06DAA8AQAVAAgJxg06DAA8AQAAAA==.Taric:BAAALgAECgIJAgAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAABLgAECn8VAAIOAAgJwA8xJQBzAQAOAAgJwA8xJQBzAQAAAA==.',
Te='Techytechy:BAABLgAECn8eAAIdAAgJnBwGBAAuAgAdAAgJnBwGBAAuAgAAAA==.Tenebris:BAEALgAECgMJAwABLgAECggJFgAVAMYNAA==.Tennmage:BAAALgAECgEJAQAAAA==.Terenii:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrakk:BAAALgAECgQJBAAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIFAAkJLBlZRQATAgAFAAkJLBlZRQATAgAAAA==.',
Ti='Tigermaster:BAABLgAECn8WAAIcAAcJ1AUAiAAVAQAcAAcJ1AUAiAAVAQAAAA==.Tilamano:BAABLgAECn87AAQdAAkJpSWIAQC4AgAdAAgJ0iSIAQC4AgAlAAgJOiQ3AgCcAgABAAgJMiQFIgBNAgAAAA==.Tilthulhu:BAAALgAECgMJAwABLgAECgkJOwAdAKUlAA==.',
Tm='Tmntmikey:BAABLgAFFH8PAAMNAAUJ5Q9eHQAwAQANAAUJ5Q9eHQAwAQAiAAMJbgEIPQCUAAAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMcAAcJRCMZHwBLAgAcAAcJgCIZHwBLAgAgAAYJMSMUIgAVAgABLgAECgkJFwASANoaAA==.Tonberry:BAAALgAECgkJBgAAAA==.Tonycheeks:BAAALgAECgQJBQAAAA==.Tonyhunter:BAAALgADCgYJBgAAAA==.Toogie:BAAALgAECgIJAwABLgAFFAEJBQAiAO8lAA==.Tookie:BAAALgADCgYJBgABLgAFFAEJBQAiAO8lAA==.Toophie:BAAALgADCgIJAgABLgAFFAEJBQAiAO8lAA==.Toopie:BAACLgAFFH8FAAIiAAEJ7yVzRwBqAAAiAAEJ7yVzRwBqAAAuAAQKfx4AAyIACAn7IWULANcCACIACAn7IWULANcCAA4ABQlvGSQ4AD0BAAAA.',
Tr='Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8nAAIoAAkJxBvfEQCtAgAoAAkJxBvfEQCtAgAAAA==.Tryath:BAABLgAECn8ZAAMoAAgJ4wrsagDiAAAoAAcJcAjsagDiAAAGAAQJzAnnXQCAAAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.Turtlegrnade:BAAALgADCgEJAQAAAA==.Tuzzyfits:BAAALgAECgEJAQAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8OAAIdAAUJAhXSBAA1AQAdAAUJAhXSBAA1AQAuAAQKfyQAAh0ACQl8G2oCAOUCAB0ACQl8G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIHAAkJCh8hAwABAwAHAAkJCh8hAwABAwAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJDwAAAA==.',
Um='Umbrute:BAABLgAECn8rAAISAAkJQiBfEwDlAgASAAkJQiBfEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgcJGQAfALkVAA==.',
Va='Vader:BAAALgAECgMJAwAAAA==.Valcristo:BAABLgAECn8/AAIRAAkJoiOmAQAeAwARAAkJoiOmAQAeAwAAAA==.Valros:BAAALgADCgEJAQAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgQJBgABLgAECggJFwAYAH8QAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8qAAMMAAkJnxb5EQABAgAMAAkJshX5EQABAgAUAAUJ8xGAEwDJAAAAAA==.Verdraxa:BAAALgAECgEJAQAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn83AAIcAAkJ+xrHGwBpAgAcAAkJ+xrHGwBpAgAAAA==.',
Vi='Vicariana:BAACLgAFFH8bAAIkAAYJpyUGBwBwAgAkAAYJpyUGBwBwAgAuAAQKfywAAyQACQnfJhEAAPkDACQACQnfJhEAAPkDAAMAAQnWIc1iAGEAAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAFFAIJAgAAAA==.Vidette:BAAALgADCgcJGAAAAA==.Viduus:BAAALgAECgQJBgABLgAECgkJHQAlAFkfAA==.Viv:BAABLgAECn8nAAMRAAgJ8SK8BQCWAgARAAcJPCS8BQCWAgAFAAYJEiNWOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8bAAIFAAgJsQWIrQAHAQAFAAgJsQWIrQAHAQAAAA==.Voideddn:BAAALgADCgYJBgAAAA==.Voldermort:BAAALgAECgcJDAAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAAALgAECgYJEwABLgAFFAMJAwAPAAAAAA==.Warrendemon:BAACLgAFFH8YAAISAAYJCiZ3DAAWAgASAAYJCiZ3DAAWAgAuAAQKfzUAAxIACQkDJrsBAMADABIACQkDJrsBAMADAAkAAwn9InlDAOkAAAAA.Waygun:BAAALgADCgYJBgAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAIfAAkJWBOvUgA/AgAfAAkJWBOvUgA/AgAAAA==.Wildheart:BAABLgAECn8dAAMeAAkJ1SAfBACpAgAeAAkJiiAfBACpAgApAAMJ+xTBNACtAAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.Wissa:BAAALgAECggJCAAAAA==.',
Wo='Wowbelly:BAACLgAFFH8IAAINAAQJggznKADXAAANAAQJggznKADXAAAuAAQKfx0AAg0ABwnFG0EWABECAA0ABwnFG0EWABECAAAA.Wowbellyjr:BAAALgAFFAEJAQABLgAFFAQJCAANAIIMAA==.',
Xa='Xaanii:BAAALgADCgcJCAAAAA==.Xandon:BAAALgAECgUJCQAAAA==.',
Xo='Xonk:BAACLgAFFH8WAAIlAAYJ8g+2AQCCAQAlAAYJ8g+2AQCCAQAuAAQKfyQAAiUACQkQICwBAPECACUACQkQICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAECggJFwAYAH8QAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgYJEQAAAA==.',
Yu='Yuuna:BAAALgAECgQJDAAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAABLgAECn8UAAMJAAcJQQjTLQDwAAAJAAcJQQjTLQDwAAASAAYJ+QKFzABwAAAAAA==.Zaps:BAABLgAECn8pAAIIAAkJKCObAQANAwAIAAkJKCObAQANAwAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCgkJDAAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8cAAIfAAcJlBNkdgByAQAfAAcJlBNkdgByAQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zebco:BAAALgADCgQJBAAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn81AAMEAAkJ4QuzRQB7AQAEAAkJ4QuzRQB7AQAXAAcJxwiOSgDvAAAAAA==.Zenreto:BAABLgAECn85AAIUAAgJdR7EAwBXAgAUAAgJdR7EAwBXAgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8XAAIfAAYJgR+kHQDOAQAfAAYJgR+kHQDOAQAuAAQKfysAAh8ACAnAJG0SADkDAB8ACAnAJG0SADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8bAAIIAAYJ/x6DAQDJAQAIAAYJ/x6DAQDJAQAuAAQKfyUAAggACQlKIsMAAI8DAAgACQlKIsMAAI8DAAAA.',
['Îl']='Îllîdan:BAABLgAFFH8GAAISAAIJYg7KbQCFAAASAAIJYg7KbQCFAAAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8zAAMBAAkJuR02FwCMAgABAAkJuR02FwCMAgAdAAQJGwjCQQCuAAAAAA==.',
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
