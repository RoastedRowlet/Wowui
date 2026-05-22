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

local lookup = {'Warlock-Demonology','Shaman-Restoration','Paladin-Retribution','Druid-Balance','DemonHunter-Havoc','Evoker-Preservation','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Warrior-Fury','Paladin-Protection','DemonHunter-Devourer','Warrior-Arms','Rogue-Assassination','Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Warlock-Destruction','Hunter-Survival','Priest-Shadow','Druid-Feral','DemonHunter-Vengeance','Mage-Frost','Hunter-Marksmanship','Mage-Arcane','Priest-Discipline','Priest-Holy','DeathKnight-Frost','Paladin-Holy','Warlock-Affliction','Rogue-Outlaw','Mage-Fire','Warrior-Protection','Druid-Restoration','Monk-Brewmaster','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE/OgAjAgABAAkJuxE/OgAjAgAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAAALgAECgUJCwABLgAECgkJMgACAFARAA==.',
Ae='Aestris:BAAALgAECgMJAwAAAA==.Aethira:BAAALgAECgEJAwAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8yAAIDAAgJfiAgGgBmAgADAAgJfiAgGgBmAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.Ainz:BAAALgADCgkJCQAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexr:BAAALgADCgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.',
Am='Amarantus:BAAALgAECgQJBAABLgAFFAIJBQAEAGULAA==.Amarndeus:BAAALgADCgMJAwAAAA==.Ammerie:BAAALgAECgkJAgAAAA==.',
An='Anakim:BAAALgAECgQJBAAAAA==.Anmo:BAAALgAECggJCAAAAA==.Anmodru:BAAALgAECgYJBgAAAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aonani:BAAALgAECgYJBgAAAA==.Aotc:BAABLgAECn8WAAIFAAcJxw1rKwBsAQAFAAcJxw1rKwBsAQAAAA==.',
Aq='Aquaism:BAAALgADCgIJAgAAAA==.Aqulath:BAAALgAFFAMJBAAAAA==.Aquílés:BAAALgAECgEJAQAAAA==.',
Ar='Arazensetal:BAABLgAECn8yAAIGAAgJyhu6BQBxAgAGAAgJyhu6BQBxAgAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAUJDQAHALoQAA==.Ariandrel:BAABLgAECn8VAAMIAAgJPQ4+NAAhAQAIAAgJPQ4+NAAhAQAJAAEJWwBPjgAUAAAAAA==.Aridhol:BAAALgAECgYJBgAAAA==.Arkaedius:BAAALgAECggJCAAAAA==.Arker:BAAALgADCgIJAgAAAA==.',
As='Asellus:BAAALgAECgcJBwAAAA==.Ashraun:BAAALgAECgMJBQAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn8pAAIFAAgJAhtjCwAPAgAFAAgJAhtjCwAPAgAAAA==.',
Au='Aubrii:BAAALgADCgYJCAAAAA==.Aukatsang:BAACLgAFFH8KAAIJAAUJ0xzQCABEAQAJAAUJ0xzQCABEAQAuAAQKfyMAAgkACQnBIl0BAKMDAAkACQnBIl0BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.Auroraa:BAAALgADCgYJBgAAAA==.',
Az='Azymor:BAAALgADCggJDgAAAA==.',
Ba='Baddy:BAABLgAECn8fAAIKAAgJ9xz+FAClAgAKAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIJAAQJvRy+CABFAQAJAAQJvRy+CABFAQAuAAQKfyQAAgkACAndHpEJAN8CAAkACAndHpEJAN8CAAAA.Baladeva:BAABLgAECn8xAAILAAgJoR/VBABiAgALAAgJoR/VBABiAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECggJMgADAH4gAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgMJAwAAAA==.',
Be='Bearhold:BAAALgAECgQJBAAAAA==.Beersnob:BAABLgAECn8jAAIIAAgJ1hUGGgDOAQAIAAgJ1hUGGgDOAQAAAA==.Benjam:BAACLgAFFH8QAAIMAAYJIBWbEACbAQAMAAYJIBWbEACbAQAuAAQKfygAAgwABwnkI0wZAL0CAAwABwnkI0wZAL0CAAAA.Benyo:BAAALgADCgIJAgAAAA==.',
Bi='Bigmikeyg:BAABLgAECn8zAAIDAAgJfBL/QwCxAQADAAgJfBL/QwCxAQAAAA==.Bigsteve:BAABLgAECn8oAAMKAAgJniBBCACbAgAKAAgJlSBBCACbAgANAAgJ1hIBEQCLAQAAAA==.',
Bl='Blanket:BAACLgAFFH8LAAMOAAMJJwpxBQDpAAAHAAMJiQWXDwD0AAAOAAMJJwpxBQDpAAAuAAQKfxYAAwcABwlSHPUqAKUBAAcABwkjHPUqAKUBAA4AAwmaGgAAAAAAAAAA.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJCgAKAAYkAA==.',
Br='Brewtel:BAAALgADCgcJBwABLgAECgQJBAAPAAAAAA==.Bricked:BAAALgAECgIJAwAAAA==.',
Bu='Bubbahowl:BAAALgADCgEJAQAAAA==.Bukara:BAAALgAECgQJBAAAAA==.Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8jAAICAAkJMRqpDgCPAgACAAkJMRqpDgCPAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgEJAQAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8eAAQGAAkJHQX8IgBhAQAGAAkJHQX8IgBhAQAQAAMJGgjIMgCAAAARAAMJ0AjhWwBmAAAAAA==.Calizon:BAAALgAECggJDgAAAA==.Camc:BAAALgAECgQJCwAAAA==.Canowhoopass:BAABLgAECn8hAAISAAYJvgpoQQDVAAASAAYJvgpoQQDVAAAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cerassin:BAACLgAFFH8VAAIMAAUJvxZaIQBDAQAMAAUJvxZaIQBDAQAuAAQKfzQAAgwACQnJIPIPAP8CAAwACQnJIPIPAP8CAAAA.Cereas:BAABLgAECn8vAAIFAAgJrxerEAC3AQAFAAgJrxerEAC3AQAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgYJCAAAAA==.Chichobelo:BAABLgAFFH8FAAMTAAUJAhP1NQBIAQATAAQJAhP1NQBIAQAUAAEJAAAVNgAAAAAAAA==.Chuckrutis:BAABLgAECn8dAAMQAAYJQR9wDAAUAgAQAAYJUh5wDAAUAgARAAMJOB94OAD1AAAAAA==.',
Cl='Cliché:BAAALgAECgUJCQAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8SAAIVAAUJthoqHABCAQAVAAUJthoqHABCAQAuAAQKfyIAAhUACQkKIXYCAHEDABUACQkKIXYCAHEDAAAA.',
Co='Coldandwet:BAABLgAFFH8FAAITAAIJ0Q7dlQCVAAATAAIJ0Q7dlQCVAAAAAA==.Combination:BAABLgAECn8zAAIWAAgJkx+uAQB+AgAWAAgJkx+uAQB+AgABLgAFFAYJHAADAEgbAA==.Constrace:BAAALgAECgMJAwAAAA==.Corvenall:BAABLgAECn83AAIQAAgJlg37BwBvAQAQAAgJlg37BwBvAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAAALgAECgUJCQAAAA==.Crossbow:BAACLgAFFH8GAAIVAAMJABMnNwDoAAAVAAMJABMnNwDoAAAuAAQKfzgAAhUACQnLHxsPAMICABUACQnLHxsPAMICAAAA.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Dante:BAAALgAECgIJAwABLgAECgkJFgAXAMURAA==.Darkluster:BAAALgAECgUJBgAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.',
De='Deathbcmesyu:BAABLgAECn8WAAITAAcJ7hHsewAiAQATAAcJ7hHsewAiAQAAAA==.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demorian:BAAALgAECgEJAQABLgAECggJJwAYANsNAA==.Deondre:BAAALgAECgMJBgAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.Devoutheart:BAAALgAECgQJBAABLgAECggJGAAZAIcgAA==.',
Di='Diehappy:BAAALgAECgUJCwAAAA==.Dillie:BAAALgADCgMJAwAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgcJDQAAAA==.',
Do='Dompal:BAAALgAECgMJBgABLgAFFAUJFAAaAKcgAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAkJIwAbAEAmAA==.Drovinos:BAAALgAECgYJBgAAAA==.Drybonez:BAABLgAECn8UAAIbAAYJ0AgBxADCAAAbAAYJ0AgBxADCAAAAAA==.Drylie:BAACLgAFFH8SAAMVAAUJCCQSCQCQAQAVAAUJCCQSCQCQAQAcAAEJwBmjJQBSAAAuAAQKfyMAAxwACQm3JNIJAAYDABwACAmdItIJAAYDABUAAwlvI/FlABwBAAAA.Dràgonkíng:BAAALgAECgYJDAAAAA==.',
Dt='Dtinnel:BAABLgAECn8gAAIKAAgJfBphFgDvAQAKAAgJfBphFgDvAQABLgAECggJKAATAC4cAA==.',
Du='Dumbledussy:BAABLgAECn8nAAIYAAgJ2w1JIQBnAQAYAAgJ2w1JIQBnAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.Dustinterp:BAAALgAECgMJAwAAAA==.',
Ed='Edanor:BAAALgAECgEJAQABLgAECgkJGgAQAIQbAA==.',
Eg='Ego:BAABLgAECn83AAIKAAkJMiSzAgAUAwAKAAkJMiSzAgAUAwAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elrondo:BAAALgAECgEJAQAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQAbAHciAA==.Emmone:BAAALgAECgUJDQAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evistan:BAAALgADCgUJBwAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAAALgAECgQJBQAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Farglight:BAAALgAECgQJBAAAAA==.Faunna:BAACLgAFFH8FAAIEAAIJZQvMKACHAAAEAAIJZQvMKACHAAAuAAQKfzQAAgQACQmlHcwIAH8CAAQACQmlHcwIAH8CAAAA.',
Fe='Feebeeboofae:BAAALgAECgEJAQAAAA==.Felaz:BAABLgAECn8pAAIdAAgJQR+HAQBHAgAdAAgJQR+HAQBHAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.',
Fi='Fingerguns:BAACLgAFFH8GAAIeAAMJMQTEIQC+AAAeAAMJMQTEIQC+AAAuAAQKfxwABB4ACAlqF0QPACQCAB4ACAlqF0QPACQCAB8AAwl3CO5mAJEAABgAAwkJCJhSAF4AAAAA.Fionaa:BAABLgAECn8dAAMBAAkJOAVOXQBIAQABAAkJDQVOXQBIAQAWAAEJsAfxeAAqAAAAAA==.Fiyona:BAAALgAECgIJBAAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgADCgMJAwAAAA==.Floortank:BAABLgAECn8dAAMgAAcJ1AaLEADqAAAgAAcJ1AaLEADqAAATAAcJLgQyoADfAAAAAA==.',
Fo='Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAACLgAFFH8LAAIhAAMJUBvJGgAAAQAhAAMJUBvJGgAAAQAuAAQKfxsAAiEABwnKI4sRAIcCACEABwnKI4sRAIcCAAAA.Frikilatar:BAAALgAECgEJBQAAAA==.Frostyhatesu:BAEALgADCgMJAwABLgAECgIJAwAPAAAAAA==.Frrank:BAACLgAFFH8UAAINAAUJhiW8AwCiAQANAAUJhiW8AwCiAQAuAAQKfysAAg0ACQm5JGEAALQDAA0ACQm5JGEAALQDAAAA.',
Fu='Fullerene:BAAALgADCgcJFwAAAA==.',
Ga='Galcain:BAABLgAECn8mAAQVAAgJ3CL2BwARAwAVAAgJliL2BwARAwAXAAUJyROcJwANAQAcAAMJVBrQYAC9AAAAAA==.Gardonea:BAAALgADCgYJBgAAAA==.',
Gh='Ghostmain:BAAALgAECgMJBAABLgAECgYJEQAPAAAAAA==.',
Gi='Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAABLgAECn8mAAIbAAgJhxPaUQCkAQAbAAgJhxPaUQCkAQAAAA==.Glaivizzon:BAAALgAECgIJAwAAAA==.',
Go='Gorizarev:BAAALgAECgQJCQAAAA==.',
Gr='Grogtar:BAAALgADCgMJAwAAAA==.Grumandel:BAABLgAECn8yAAIZAAgJpxG1CwCeAQAZAAgJpxG1CwCeAQAAAA==.',
Gu='Guce:BAAALgAECgEJAQAAAA==.Gudetama:BAABLgAECn8WAAMVAAgJjR7BFwB7AgAVAAYJESPBFwB7AgAXAAYJxxoxEgDSAQAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgYJCgAAAA==.Haidie:BAAALgADCgEJAQAAAA==.Hakur:BAABLgAECn8yAAIDAAgJ6h0tKQAUAgADAAgJ6h0tKQAUAgAAAA==.Hamahara:BAAALgAECgUJBgAAAA==.Hanma:BAACLgAFFH8PAAITAAYJZBf7EQCuAQATAAYJZBf7EQCuAQAuAAQKfygAAhMACQkFHxEsAIgCABMACQkFHxEsAIgCAAAA.Harribel:BAABLgAECn8tAAIbAAgJjQ4YZgBxAQAbAAgJjQ4YZgBxAQAAAA==.',
He='Heimdall:BAAALgADCgQJAQAAAA==.Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgADCgYJBgAAAA==.Hiroki:BAABLgAECn8ZAAITAAgJTwpCYgBaAQATAAgJTwpCYgBaAQAAAA==.Hitachitotem:BAACLgAFFH8PAAISAAMJRg2jEQDbAAASAAMJRg2jEQDbAAAuAAQKfxkAAhIACAmoGl0aAEACABIACAmoGl0aAEACAAAA.Hizzon:BAAALgADCgcJDAAAAA==.',
Ho='Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAAALgAECggJEwAAAA==.Holymaet:BAAALgADCgEJAQABLgAECggJMgAKAHIkAA==.Holyphatso:BAAALgADCgMJAwABLgAECgkJKAAfACsgAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAABLgAECn8aAAIbAAgJ4xQRRQDKAQAbAAgJ4xQRRQDKAQAAAA==.',
In='Inflikted:BAABLgAECn8lAAITAAkJVAg7VAB/AQATAAkJVAg7VAB/AQAAAA==.Interwebz:BAAALgAECggJEQAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgAECgQJBAAPAAAAAA==.Jazzarin:BAAALgADCgEJAQAAAA==.',
Je='Jehannum:BAABLgAECn8cAAISAAgJlQ0BMAAlAQASAAgJlQ0BMAAlAQAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgUJEAAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAAALgAFFAEJAQABLgAFFAQJEwACAMsfAA==.Josen:BAAALgAECgEJAQAAAA==.',
Ju='Juliana:BAAALgADCgMJAwAAAA==.Jurkzarbirt:BAAALgAECgMJAwAAAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIYAAgJ0ReQFwC4AQAYAAgJ0ReQFwC4AQAAAA==.',
Ka='Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAAALgAECgIJAgAAAA==.Katarena:BAABLgAECn8uAAIhAAgJVRDvJACTAQAhAAgJVRDvJACTAQAAAA==.Kathyra:BAABLgAECn8iAAMBAAgJPQsBWABWAQABAAgJPQsBWABWAQAiAAEJ7wEjNwAnAAAAAA==.Kavax:BAABLgAECn8aAAIhAAgJ9xLHHQDIAQAhAAgJ9xLHHQDIAQAAAA==.',
Ke='Keel:BAAALgAECgEJAQAAAA==.Keeller:BAACLgAFFH8RAAIDAAUJaA8CJwA1AQADAAUJaA8CJwA1AQAuAAQKfzUAAgMACAmqH1UoAIQCAAMACAmqH1UoAIQCAAAA.Keggor:BAAALgAECgEJAgAAAA==.Kentyr:BAABLgAECn8nAAMHAAgJgg0KHgBIAQAHAAgJgg0KHgBIAQAjAAIJZwGDDgA0AAAAAA==.',
Kh='Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgADCgIJAgABLgAECggJMgAKAHIkAA==.Kinký:BAABLgAECn8gAAMKAAgJSBGlNQDSAQAKAAgJtRClNQDSAQANAAEJ2xRNSgA8AAABLgAECgUJCwAPAAAAAA==.Kiraelis:BAABLgAECn8iAAIcAAgJBBATCwBpAQAcAAgJBBATCwBpAQAAAA==.Kiss:BAAALgADCgEJAQABLgAECgcJCgAPAAAAAA==.Kivea:BAABLgAECn8YAAMbAAgJ6Q/QXwCAAQAbAAgJ6Q/QXwCAAQAkAAEJBAchDgArAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECgcJBwAAAA==.Konagda:BAAALgADCggJEQAAAA==.Korvoh:BAABLgAECn8zAAMeAAgJ6xwZCQCQAgAeAAgJ4hwZCQCQAgAfAAMJUxeOXQC8AAAAAA==.',
Kr='Kringe:BAABLgAECn8hAAISAAgJOiCQDgA1AgASAAgJOiCQDgA1AgAAAA==.',
Ku='Kumonk:BAABLgAECn8VAAIJAAYJBgbxPAC+AAAJAAYJBgbxPAC+AAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBQAAAA==.',
['Kä']='Kämik:BAABLgAECn8zAAIVAAgJmCDWDwCKAgAVAAgJmCDWDwCKAgAAAA==.',
['Kì']='Kìn:BAAALgAECgYJEQAAAA==.',
La='Lampion:BAABLgAECn8eAAIFAAkJtAvOFACDAQAFAAkJtAvOFACDAQAAAA==.Lasstchance:BAAALgAECgUJCwAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8YAAIBAAcJChzQPgCiAQABAAcJChzQPgCiAQAAAA==.',
Le='Leijona:BAAALgAECgEJAQAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgADCgMJAwAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Likeatrain:BAABLgAECn8gAAIlAAgJCwxeGAAqAQAlAAgJCwxeGAAqAQAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMhAAgJJRN/KADqAQAhAAgJJRN/KADqAQADAAUJDghNwAC3AAAAAA==.Lilwagyu:BAAALgAFFAMJBAAAAA==.Linds:BAABLgAECn8tAAMhAAgJmyBpEgA0AgAhAAgJmyBpEgA0AgADAAYJ4gu/owDlAAAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgcJEgAAAA==.Littlefoot:BAAALgAECgYJBwABLgAECggJMgAKAHIkAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8WAAMHAAYJOhdcHwA7AQAHAAYJOhdcHwA7AQAOAAEJhxD2HwAzAAAAAA==.Lorralen:BAAALgAECgcJCAAAAA==.',
Lt='Ltdanslegs:BAABLgAECn8pAAIJAAgJPhyNDgARAgAJAAgJPhyNDgARAgAAAA==.',
Lu='Luber:BAABLgAECn8UAAICAAkJuAgVOgBmAQACAAkJuAgVOgBmAQAAAA==.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAABLgAECn83AAIUAAkJNyUKAQBBAwAUAAkJNyUKAQBBAwAAAA==.Luxzy:BAAALgAECgMJAwAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgADCgQJBQAAAA==.Manbearcat:BAABLgAECn8aAAImAAgJ5iFaCwDKAgAmAAgJ5iFaCwDKAgAAAA==.Marbleous:BAACLgAFFH8KAAIKAAMJBiQrFQAqAQAKAAMJBiQrFQAqAQAuAAQKfxgAAgoABgm6I8kZANEBAAoABgm6I8kZANEBAAAA.Marina:BAAALgADCgcJDQAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECggJGwAiAOQfAA==.Melhina:BAAALgAECgUJBQABLgAECggJKQAiAPYaAA==.Memisstotem:BAABLgAECn8eAAICAAcJghoVIQDxAQACAAcJghoVIQDxAQAAAA==.Merle:BAABLgAECn8yAAMKAAgJciTrCwBkAgAKAAgJbiPrCwBkAgANAAUJPSIaDADRAQAAAA==.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAAALgAFFAEJAQAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAAALgAECgYJEgAAAA==.Mistborn:BAABLgAECn8sAAQfAAgJkCMhCQC5AgAfAAgJkCMhCQC5AgAeAAQJ1RyJKQBMAQAYAAIJsBXIUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn8jAAIZAAgJGBPfCgCvAQAZAAgJGBPfCgCvAQAAAA==.Monkjamin:BAABLgAFFH8FAAInAAMJThegIwDoAAAnAAMJThegIwDoAAAAAA==.Moolimbo:BAABLgAECn8nAAISAAgJQBk6EgALAgASAAgJQBk6EgALAgAAAA==.Mooseboy:BAABLgAECn8sAAIZAAgJYh59BABlAgAZAAgJYh59BABlAgAAAA==.Mooserton:BAABLgAECn8lAAMhAAYJSA+hNAAuAQAhAAYJSA+hNAAuAQADAAYJrA/dlgD7AAAAAA==.Mootalstrike:BAABLgAECn8nAAIKAAgJCRS2IQCVAQAKAAgJCRS2IQCVAQAAAA==.Moshworm:BAABLgAECn8kAAIEAAgJhguCLQARAQAEAAgJhguCLQARAQAAAA==.',
Mu='Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgEJAgAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAUJEgAVALYaAA==.',
Na='Nalaxx:BAAALgAECgEJAQAAAA==.Natsumi:BAAALgAECgcJCwAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIRAAYJVQPRQwDRAAARAAYJVQPRQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn8vAAIbAAgJ8BnEQADYAQAbAAgJ8BnEQADYAQAAAA==.Neuroticaine:BAABLgAECn8zAAMYAAgJMBXkGgCaAQAYAAgJMBXkGgCaAQAeAAQJGwZFRwBoAAAAAA==.Nev:BAACLgAFFH8MAAMVAAQJZiF/DgBwAQAVAAQJZiF/DgBwAQAcAAMJ6AVCGQDAAAAuAAQKfyEAAxUACAncIsYjAC8CABUABwkjIsYjAC8CABwABwmhHLEkAAICAAAA.Nexassin:BAABLgAFFH8HAAIHAAMJfgFEHgCtAAAHAAMJfgFEHgCtAAAAAA==.',
Ni='Nico:BAABLgAECn8WAAIXAAkJxREjEQCxAQAXAAkJxREjEQCxAQAAAA==.Nimz:BAABLgAECn8bAAQiAAgJ5B/fAgAyAgAiAAgJ3R/fAgAyAgAWAAcJIRpYBgCpAQABAAIJrRPO7ACBAAAAAA==.',
No='Noctrine:BAAALgADCgMJAwAAAA==.Nooblets:BAACLgAFFH8HAAIHAAMJ/xqPFwD/AAAHAAMJ/xqPFwD/AAAuAAQKfxsAAgcABwnKIJIQANYBAAcABwnKIJIQANYBAAAA.Noradia:BAAALgAECgMJBAAAAA==.Noxxidari:BAABLgAECn8gAAMMAAgJBhJ1UABEAQAMAAgJBhJ1UABEAQAaAAIJwhRNIwA8AAAAAA==.Noxxus:BAABLgAECn8fAAILAAkJvRrrCgDDAQALAAkJvRrrCgDDAQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymphis:BAAALgADCgYJDgAAAA==.Nymz:BAAALgAECgMJAwABLgAECggJGwAiAOQfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôpmage:BAAALgAECgYJBQAAAA==.Nôwôrries:BAEALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBgAAAA==.',
Of='Offended:BAAALgAECgMJAwAAAA==.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgQJBQABLgAECggJJwASAEAZAA==.',
Om='Omnivus:BAAALgADCgEJAQAAAA==.',
On='Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCwAhAFAbAA==.Oratherah:BAABLgAFFH8JAAIUAAMJliONFwDHAAAUAAMJliONFwDHAAAAAA==.Orbs:BAAALgAECgEJAQAAAA==.Orchist:BAABLgAECn8aAAIKAAgJux+cDABaAgAKAAgJux+cDABaAgAAAA==.',
Ow='Owlyheals:BAAALgADCgQJBAAAAA==.',
Oz='Ozôls:BAAALgAECgMJBAAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Palei:BAAALgAECgYJBgAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn8zAAIgAAgJNAfjDQAXAQAgAAgJNAfjDQAXAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECggJJwASAEAZAA==.',
Ph='Phenothal:BAAALgADCgIJAgAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECggJEQAPAAAAAA==.Pitchblende:BAABLgAECn8vAAIhAAgJqxOOGgDkAQAhAAgJqxOOGgDkAQAAAA==.',
Po='Poeppsul:BAAALgADCgMJAwAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAUJDAATAJckAA==.Porthub:BAABLgAECn8oAAIbAAgJ8Al2awBlAQAbAAgJ8Al2awBlAQAAAA==.',
Pr='Protagoras:BAAALgAECgcJBwAAAA==.',
Pu='Purejoy:BAAALgAECgYJCwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qq='Qqcumber:BAAALgADCgIJAgAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAAALgAECgUJBwAAAA==.Rajak:BAAALgAECgEJAQAAAA==.Raph:BAAALgAECgEJAQAAAA==.Rathibrew:BAACLgAFFH8UAAInAAUJRyPRCACPAQAnAAUJRyPRCACPAQAuAAQKfzAAAicACQkyI7wBAIwDACcACQkyI7wBAIwDAAAA.',
Re='Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgYJCQAAAA==.Rellt:BAAALgADCgIJAgAAAA==.Remnants:BAABLgAECn8UAAInAAYJihvDJwDIAQAnAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAAALgAECgYJCgAAAA==.',
Rh='Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBgAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgADCgYJBwAAAA==.',
Ro='Rockyx:BAAALgAECgQJBQAAAA==.Roll:BAAALgADCgcJBwABLgAFFAMJCgAUAF8mAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAABLgAECn8oAAITAAgJLhxzSgCbAQATAAgJLhxzSgCbAQAAAA==.',
['Rê']='Rêzìcå:BAAALgADCgkJCQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAAALgAECgYJDAAAAA==.Salezar:BAABLgAECn8aAAIQAAkJhBvKAQCMAgAQAAkJhBvKAQCMAgAAAA==.Sandoud:BAABLgAECn8XAAIEAAkJwBFEFQDRAQAEAAkJwBFEFQDRAQAAAA==.Sapientia:BAABLgAECn8gAAIDAAgJQAVIlQD+AAADAAgJQAVIlQD+AAAAAA==.Saragon:BAAALgAECgYJBgABLgAECggJLwAFAK8XAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgADCgEJAQAAAA==.',
Sc='Scottkill:BAABLgAECn8hAAMhAAgJWhjHGQBFAgAhAAgJWhjHGQBFAgADAAEJ8g8nMgE/AAABLgAFFAcJGQAbAHIYAA==.',
Se='Sebaux:BAAALgAECgQJCQAAAA==.Segur:BAAALgAECgYJEAAAAA==.Selenesul:BAABLgAECn8iAAMDAAgJZxtOKgAQAgADAAgJZxtOKgAQAgALAAMJTAynNAB0AAAAAA==.Selyda:BAAALgADCgUJBgAAAA==.Senzie:BAACLgAFFH8JAAIJAAMJmxfqEQDvAAAJAAMJmxfqEQDvAAAuAAQKfyQAAgkACQkhHmkHAI4CAAkACQkhHmkHAI4CAAEuAAUUBQkOAAkAThMA.',
Sh='Shadowdrake:BAABLgAECn8UAAIRAAcJswqJRgC7AAARAAcJswqJRgC7AAAAAA==.Shadowheàrt:BAAALgAECgUJEwAAAA==.Shadowshifty:BAAALgAECgQJEQAAAA==.Shadowtotem:BAAALgADCgkJDQAAAA==.Shaeen:BAAALgAECgUJBQAAAA==.Shagi:BAAALgAECgcJEwAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharroz:BAABLgAECn8dAAMgAAcJiB1oAwBWAgAgAAcJiB1oAwBWAgAUAAQJVQ7QLgCVAAAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8eAAMeAAcJ6xreFQDRAQAeAAcJ6xreFQDRAQAYAAEJJQKaaQAlAAABLgAECggJKAATAC4cAA==.Shockybalboa:BAAALgAECgYJBwAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skooda:BAABLgAECn8tAAISAAkJaA7RHwCPAQASAAkJaA7RHwCPAQAAAA==.Skyded:BAABLgAECn8vAAITAAgJ0xqdLAAGAgATAAgJ0xqdLAAGAgAAAA==.Skyknight:BAABLgAECn8hAAIKAAkJmxPeGQDQAQAKAAkJmxPeGQDQAQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8LAAMXAAQJZBb6CABZAQAXAAQJZBb6CABZAQAcAAIJBwvoFwCEAAAuAAQKfzgAAxcACQnHImsCAPMCABcACQmOIWsCAPMCABwACAnXHvgFAPcBAAAA.',
Sn='Snapahead:BAAALgADCgIJAgAAAA==.Sneakytony:BAAALgADCgcJBwAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8dAAIMAAgJixyPIQAGAgAMAAgJixyPIQAGAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAAALgAECgUJCQAAAA==.Soralas:BAAALgAECgYJCgAAAA==.',
Sp='Spaazz:BAABLgAECn8cAAIDAAgJmB+THgBMAgADAAgJmB+THgBMAgAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.',
St='Starweaver:BAABLgAECn8gAAMfAAgJJRPsIwBcAQAfAAgJJRPsIwBcAQAeAAYJhwYAAAAAAAAAAA==.Stellmarine:BAABLgAECn8dAAIEAAkJzRrhEAAFAgAEAAkJzRrhEAAFAgAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgQJBgAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8vAAMoAAgJFRuPBwAZAgAoAAgJyxqPBwAZAgAEAAYJBBrnKgCqAQAAAA==.',
Su='Subzro:BAAALgAECgEJAQAAAA==.Sunamé:BAAALgAECgMJAwAAAA==.',
Sw='Swaazil:BAABLgAECn8hAAIbAAkJfw5rXACIAQAbAAkJfw5rXACIAQAAAA==.Swan:BAAALgAFFAIJBAAAAA==.Swiftsama:BAAALgAECgEJAQABLgAECgcJEAAPAAAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8VAAIMAAYJDgpOgADLAAAMAAYJDgpOgADLAAAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taloriesh:BAABLgAECn8iAAMfAAgJLxtLDgA4AgAfAAgJLxtLDgA4AgAYAAEJPhXqYAA2AAAAAA==.Tanazir:BAEALgAECgcJDwAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAAALgAECgcJDgAAAA==.',
Te='Techytechy:BAABLgAECn8WAAIWAAcJPB5PBADvAQAWAAcJPB5PBADvAQAAAA==.Tennmage:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIDAAkJLBlZRQATAgADAAkJLBlZRQATAgAAAA==.',
Ti='Tigermaster:BAAALgAECgYJDgAAAA==.Tilamano:BAABLgAECn8yAAQWAAgJOCXcAADKAgAWAAgJ0STcAADKAgABAAcJ1SPLLADnAQAiAAcJqCK4BADiAQAAAA==.',
Tm='Tmntmikey:BAABLgAFFH8KAAMIAAUJXAhKFAArAQAIAAUJXAhKFAArAQAnAAMJbgGPMQCdAAAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMVAAcJOiMZHwBLAgAVAAcJdiIZHwBLAgAcAAYJMSMUIgAVAgABLgAECggJEwAPAAAAAA==.Tonberry:BAAALgAECgkJBgAAAA==.Tonycheeks:BAAALgAECgQJBQAAAA==.Tonyhunter:BAAALgADCgYJBgAAAA==.Toogie:BAAALgAECgIJAwABLgAECggJGgAnANAgAA==.Tookie:BAAALgADCgYJBgABLgAECggJGgAnANAgAA==.Toophie:BAAALgADCgIJAgABLgAECggJGgAnANAgAA==.Toopie:BAABLgAECn8aAAMnAAgJ0CBlCwDXAgAnAAgJySBlCwDXAgAJAAUJbxkkOAA9AQAAAA==.',
Tr='Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8ZAAImAAcJ1BvLIwDmAQAmAAcJ1BvLIwDmAQAAAA==.Tryath:BAABLgAECn8VAAMmAAgJ4gqfWgDiAAAmAAcJcAifWgDiAAAEAAEJYAMddgAhAAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.Turtlegrnade:BAAALgADCgEJAQAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8LAAIWAAQJxxNQBgDcAAAWAAQJxxNQBgDcAAAuAAQKfyQAAhYACQl8G2oCAOUCABYACQl8G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIXAAkJCh8hAwABAwAXAAkJCh8hAwABAwAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJDwAAAA==.',
Um='Umbrute:BAABLgAECn8nAAIMAAkJnB9fEwDlAgAMAAkJnB9fEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgYJFQAbAIYTAA==.',
Va='Valcristo:BAABLgAECn8zAAILAAgJMyTMAgCuAgALAAgJMyTMAgCuAgAAAA==.Valros:BAAALgADCgEJAQAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgQJBgABLgAECgcJFgATAO4RAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8jAAMHAAgJHxWHHABVAQAHAAcJQROHHABVAQAOAAUJ8xGAEwDJAAAAAA==.Verdraxa:BAAALgAECgEJAQAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn8sAAIVAAgJpRujHAArAgAVAAgJpRujHAArAgAAAA==.',
Vi='Vicariana:BAACLgAFFH8UAAIeAAUJPyVdBwANAgAeAAUJPyVdBwANAgAuAAQKfyQAAh4ACQnfJhEAAPkDAB4ACQnfJhEAAPkDAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAECgYJCwAAAA==.Vidette:BAAALgADCgYJCwAAAA==.Viduus:BAAALgAECgQJBgABLgAECggJGwAiAOQfAA==.Viv:BAABLgAECn8jAAMLAAgJ8SIHBQBcAgALAAcJPCQHBQBcAgADAAYJEiNWOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8aAAIDAAcJIAb/mgDzAAADAAcJIAb/mgDzAAAAAA==.Voldermort:BAAALgAECgYJBwAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAAALgAECgYJEwABLgAFFAMJAwAPAAAAAA==.Warrendemon:BAACLgAFFH8SAAIMAAUJpiQrEQCYAQAMAAUJpiQrEQCYAQAuAAQKfy0AAwwACQkDJrsBAMADAAwACQkDJrsBAMADAAUAAwn9InlDAOkAAAAA.Waygun:BAAALgADCgYJBgAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAIbAAkJWBOvUgA/AgAbAAkJWBOvUgA/AgAAAA==.Wildheart:BAABLgAECn8YAAMZAAgJhyDQBABUAgAZAAgJMSDQBABUAgAoAAMJ+xSGIwCwAAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.Wissa:BAAALgAECgEJAQAAAA==.',
Wo='Wowbelly:BAABLgAECn8ZAAIIAAcJxRtBFgARAgAIAAcJxRtBFgARAgAAAA==.Wowbellyjr:BAAALgAECgYJDAABLgAECgcJGQAIAMUbAA==.',
Xa='Xaanii:BAAALgADCgcJCAAAAA==.Xandon:BAAALgAECgUJCQAAAA==.',
Xo='Xonk:BAACLgAFFH8QAAIiAAUJ5RATAgA2AQAiAAUJ5RATAgA2AQAuAAQKfxsAAiIACAnPICwBAPECACIACAnPICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAECgcJFgATAO4RAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgQJDQAAAA==.',
Yu='Yuuna:BAAALgAECgMJBQAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAAALgAECgYJDgAAAA==.Zaps:BAABLgAECn8mAAIpAAgJlCMnAgDDAgApAAgJlCMnAgDDAgAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCggJCQAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8VAAIbAAYJNhK6hAAyAQAbAAYJNhK6hAAyAQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn8pAAMCAAgJugdMTwANAQACAAgJugdMTwANAQASAAYJywhWRADJAAAAAA==.Zenreto:BAABLgAECn8zAAIOAAgJKx7qAgBRAgAOAAgJKx7qAgBRAgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8NAAIbAAQJjCEAJAByAQAbAAQJjCEAJAByAQAuAAQKfysAAhsACAnAJG0SADkDABsACAnAJG0SADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8TAAIpAAUJHx1+AgBmAQApAAUJHx1+AgBmAQAuAAQKfyAAAikACQm1IcMAAI8DACkACQm1IcMAAI8DAAAA.',
['Îl']='Îllîdan:BAAALgAFFAEJAgAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8xAAMBAAkJeh1JDwCdAgABAAkJeh1JDwCdAgAWAAQJGwjCQQCuAAAAAA==.',
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
