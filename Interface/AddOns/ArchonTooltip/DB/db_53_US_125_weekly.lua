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

local lookup = {'Priest-Holy','Priest-Discipline','Priest-Shadow','Unknown-Unknown','DeathKnight-Unholy','Warlock-Destruction','Evoker-Devastation','Shaman-Elemental','Warrior-Protection','DemonHunter-Devourer','Shaman-Enhancement','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Preservation','Shaman-Restoration','Hunter-Marksmanship','Druid-Feral','Druid-Balance','Monk-Windwalker','Paladin-Retribution','Warlock-Demonology','Warlock-Affliction','DeathKnight-Frost','DemonHunter-Havoc','DeathKnight-Blood','Druid-Guardian','Paladin-Holy','Monk-Mistweaver','Rogue-Subtlety','Mage-Arcane','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Druid-Restoration','Warrior-Arms','Hunter-Survival','Mage-Frost','Paladin-Protection',}
local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Activion:BAAANQAECgIIAgAAAA==.',
Ad='Addelana:BAAANQADCgQIBAAAAA==.Adelanaa:BAABNQAECoEcAAQBAAgKJhEjTQDpAQABAAgK1hAjTQDpAQACAAUKFQjIEADkAAADAAEKJgF4dAAXAAABNQADCgQIBAAEAAAAAA==.Adrasta:BAAANQAECgMIAwAAAA==.Adriell:BAAANQAECgUICwAAAA==.Adura:BAAANQADCgcICAAAAA==.',
Ae='Aelathe:BAAANQAECgIIAgAAAA==.Aeneas:BAAANQAECggICQAAAA==.Aenimma:BAABNQAECoEjAAIFAAgKvQNAcADmAAAFAAgKvQNAcADmAAAAAA==.Aerys:BAAANQADCggIDQAAAA==.',
Ak='Akey:BAAANQAECgYIDwAAAA==.',
Al='Alamwah:BAAANQADCgEIAQABNQAECggICgAEAAAAAA==.Alaroo:BAAANQAECgEIAQAAAA==.Alatao:BAAANQABCgYIBwAAAA==.Aleinaas:BAAANQADCgYICgAAAA==.Aleine:BAAANQAECgUIBgAAAA==.Alektra:BAABNQAECoEeAAIGAAgKQBNjDAAeAgAGAAgKQBNjDAAeAgAAAA==.Alexella:BAAANQADCgcICQAAAA==.Allerfala:BAAANQADCgQIBAABNQAECgkJLAAHALYgAA==.Alliete:BAAANQADCgIIAgAAAA==.Allya:BAAANQAECgQICAABNQAECgUICgAEAAAAAA==.Aloine:BAABNQAECoEgAAIBAAgKdgP6dQBLAQABAAgKdgP6dQBLAQAAAA==.Alteredbeast:BAAANQAECgQIBAABNQAECgkJHgAIAPoWAA==.',
Am='Amogus:BAAANQAECgUICQAAAA==.Amoresh:BAAANQAECgQJCQAAAA==.Ampuzzible:BAAANQAECgcIDAAAAA==.',
An='Anbebi:BAAANQAECgUICAAAAA==.Anchor:BAAANQABCgEIAgAAAA==.Anqu:BAAANQADCgMIAwAAAA==.',
Ar='Arbitera:BAAANQAECgcIEwAAAA==.Arkona:BAAANQADCggIFQAAAA==.Arthelais:BAAANQAECgYIBwAAAA==.Arzir:BAABNQAECoEnAAIJAAkKNxJ0DAAaAgAJAAkKNxJ0DAAaAgAAAA==.',
As='Ashbringer:BAAANQAECgYICwAAAA==.Asmonjoel:BAAANQADCgcICAAAAA==.Assumi:BAAANQADCggIHgAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.',
Au='Audree:BAAANQADCgYIBAAAAA==.Aurellia:BAAANQAECggICQAAAA==.',
Av='Avoide:BAAANQADCgYJCgAAAA==.',
Ax='Axedup:BAAANQAECgcICQABNQAFFAYIEQAKAAwcAA==.',
Ay='Aydy:BAAANQAECgYICQAAAA==.',
Az='Azamat:BAAANQAECgMIBAAAAA==.Azuredemonx:BAABNQAECoE3AAIKAAgKwBuGEgCtAgAKAAgKwBuGEgCtAgAAAA==.',
Ba='Backup:BAAANQAECgQIEAAAAA==.Balayn:BAAANQADCgYICQAAAA==.Banan:BAAANQAECgIIAgAAAA==.Banhbolock:BAAANQAECgMIAwAAAA==.Banoni:BAAANQABCgQIBgABNQAECgIIAgAEAAAAAA==.',
Bb='Bbajer:BAAANQAECgEIAQAAAA==.Bbqporkbuns:BAABNQAECoEmAAILAAkKHiFPAwBUAwALAAkKHiFPAwBUAwAAAA==.',
Be='Bearzy:BAAANQAECgEIAgAAAA==.Bearzz:BAABNQAECoEhAAIMAAgKexyMLQClAgAMAAgKexyMLQClAgAAAA==.Beefcakes:BAAANQADCgEIAQAAAA==.Bekinsale:BAAANQADCgYIBgABNQADCggIFwAEAAAAAA==.Belledormi:BAABNQAECoEaAAQHAAcKRwmxIQD8AAAHAAYK8waxIQD8AAANAAIKCgx4FwBpAAAOAAIKbgv9OwBkAAAAAA==.Bellest:BAAANQAECgcIEwAAAA==.Benji:BAABNQAECoEcAAMIAAkKeiMZDQBlAwAIAAkKeiMZDQBlAwAPAAYKvAqzkgABAQAAAA==.',
Bf='Bfev:BAAANQAECgYJDAAAAA==.',
Bg='Bggestthighs:BAAANQAECgQIBQABNQAECgcJLAAQACQVAA==.',
Bi='Bid:BAAANQAECgYIEwAAAA==.Bigado:BAAANQADCggICgAAAA==.Bigalo:BAAANQAECgYIEAAAAA==.Bigarms:BAAANQAECgIIBQABNQAECgYIBwAEAAAAAA==.Bigfel:BAAANQABCgQIBAAAAA==.Biggesthighz:BAABNQAECoEsAAIQAAcKJBUvKQCzAQAQAAcKJBUvKQCzAQAAAA==.Bird:BAAANQAECgIIAgAAAA==.',
Bl='Blindanddeaf:BAAANQAECgUIDgAAAA==.Bluee:BAAANQAECgIIAgABNQAECgYIDgAEAAAAAA==.',
Bo='Boohbooh:BAAANQADCggIFQAAAA==.Boomakus:BAAANQAECggIEwAAAA==.',
Br='Brannie:BAAANQAECgUJBwAAAA==.Brenine:BAABNQAECoEUAAMRAAUK6wzlHwCqAAASAAQKYQyMZwDZAAARAAMKhgvlHwCqAAAAAA==.Brewskie:BAAANQADCgEIAgAAAA==.Brodess:BAACNQAFFIEGAAIIAAMK4R7wEwC/AAAIAAMK4R7wEwC/AAA1AAQKgSsAAwgACQrhJVwBAOsDAAgACQrhJVwBAOsDAA8AAQpPC5z5ACMAAAAA.Brody:BAAANQAFFAIIAgAAAA==.Bromorc:BAAANQADCgcIGAAAAA==.Broner:BAABNQAECoEYAAITAAcKdAxfKgBhAQATAAcKdAxfKgBhAQAAAA==.Bronlite:BAAANQADCgUIEgAAAA==.Brorn:BAAANQADCgQIBAAAAA==.Brotherlee:BAABNQAECoEkAAIUAAkK+BhuRQB5AgAUAAkK+BhuRQB5AgAAAA==.',
Bu='Bubski:BAAANQAECgIIAwAAAA==.Bulimio:BAAANQADCgIIAgAAAA==.Bunz:BAAANQAECgUIBQAAAA==.Buratt:BAAANQADCgcIGAAAAA==.Butternut:BAAANQAECgYIBgAAAA==.',
['Bé']='Béllâ:BAAANQADCggIAgAAAA==.',
['Bõ']='Bõggie:BAAANQAECgcICgABNQAFFAYIEAAFAJ8XAA==.',
Ca='Calabor:BAAANQADCggJDQAAAA==.Caleano:BAAANQADCgQIBAAAAA==.Capacitør:BAAANQAECgUIEQAAAA==.Cardib:BAABNQAECoEpAAMVAAkKhSADLwCSAgAVAAcK9iADLwCSAgAGAAMKtRjlMQDoAAAAAA==.Carlîn:BAAANQADCgYIBgAAAA==.Cattamend:BAABNQAECoEfAAMCAAkKJxxpAwCKAgACAAgKjxlpAwCKAgABAAcK8B6sKQCFAgAAAA==.Cattawrath:BAAANQAECggIEAAAAA==.Cattazap:BAABNQAECoEXAAMPAAgKKiAzFwDpAgAPAAgKKiAzFwDpAgAIAAEK+xbG7QBDAAAAAA==.Cauliflawer:BAAANQAECgYIEAAAAA==.Cavoda:BAAANQADCgMIAwAAAA==.',
Ch='Chakrakhan:BAAANQAECgYIDgAAAA==.Char:BAAANQAECgQIBQAAAA==.Chase:BAAANQAECgMIBQAAAA==.Chinadh:BAACNQAFFIERAAIKAAYKDBzSAQBFAgAKAAYKDBzSAQBFAgA1AAQKgSEAAgoACQrzIgcIAD4DAAoACQrzIgcIAD4DAAAA.Chinahunter:BAAANQAECgEIAQABNQAFFAYIEQAKAAwcAA==.Chinamage:BAAANQAECgcIEAABNQAFFAYIEQAKAAwcAA==.Chopzuey:BAAANQADCgQICAAAAA==.Chugtiki:BAABNQAECoEiAAMIAAkKQBjpKAChAgAIAAkKQBjpKAChAgAPAAEKSgtx9AAnAAAAAA==.Chuunky:BAAANQABCgIIAgAAAA==.',
Ci='Cinderaz:BAAANQADCgcIGAAAAA==.',
Cl='Clikboomboom:BAAANQADCgUIBwAAAA==.',
Co='Cones:BAAANQADCgYICgABNQAECgYIBwAEAAAAAA==.Conesworth:BAABNQAECoEeAAIIAAkK+ha2KgCXAgAIAAkK+ha2KgCXAgAAAA==.Conesy:BAAANQAECgUICAABNQAECgkJHgAIAPoWAA==.Coquina:BAAANQAECgIIAgAAAA==.Cordeilia:BAACNQAFFIEGAAIBAAQKGALWHwCMAAABAAQKGALWHwCMAAA1AAQKgTAAAgEACQqxFE81AE8CAAEACQqxFE81AE8CAAAA.Cordi:BAAANQABCgEIAQAAAA==.Corruptax:BAAANQADCgcIDgAAAA==.Costiigan:BAAANQADCgYIBgAAAA==.',
Cr='Critsaquino:BAAANQAECgcIEAAAAA==.Critsngigs:BAAANQAECgYIDAAAAA==.Crotchsniffa:BAAANQAECgEIAQAAAA==.Crowlêy:BAAANQAECgEIAQABNQAECgkJJAAMADMbAA==.',
Cy='Cyberlust:BAAANQADCggICAAAAA==.Cyklar:BAAANQADCgcIFgAAAA==.',
Da='Daddydevito:BAABNQAECoEhAAISAAgKTAoqQQCjAQASAAgKTAoqQQCjAQAAAA==.Daddythyme:BAAANQAECgcIEAAAAA==.Dames:BAAANQADCgYIBgAAAA==.Damocies:BAAANQADCggICwAAAA==.Danky:BAAANQAECgMJAwAAAA==.Daqueta:BAAANQAECgUIBQAAAA==.Daquetarg:BAAANQADCgQIBAAAAA==.Daquetawar:BAAANQAECgQIBAAAAA==.Dardrolor:BAAANQAECgEIAQAAAA==.Darknstormy:BAAANQADCgcIDwABNQADCggIFQAEAAAAAA==.Darkpal:BAAANQAECggJEAAAAA==.Dazrawr:BAAANQAECgYIBwAAAA==.Dazzi:BAAANQADCgYIEgAAAA==.',
De='Deathdaddy:BAAANQADCgcIGwAAAA==.Decapitation:BAAANQAECgYIDgAAAA==.Deepkingz:BAAANQAECggICQAAAA==.Defacedd:BAAANQADCgYICgAAAA==.Deify:BAAANQAECgQIBwAAAA==.Deifyh:BAAANQADCgQIBQAAAA==.Deliaz:BAAANQADCgcIGAAAAA==.Destruction:BAAANQAECggICAAAAA==.',
Di='Digitalhungr:BAAANQAECgQIBAABNQAECgkJHgAIAPoWAA==.Dismarryx:BAAANQAECgEIAgAAAA==.',
Dj='Djapana:BAAANQADCgYIFAABNQADCggIFQAEAAAAAA==.Djshadowz:BAAANQAECgEIAQAAAA==.',
Dk='Dkunt:BAAANQADCgQIBAAAAA==.',
Dn='Dnomm:BAAANQADCgcIGAAAAA==.',
Do='Dogmuffin:BAAANQADCgMIAwAAAA==.Doristhedull:BAAANQAECgUIBAAAAA==.',
Dp='Dps:BAAANQAECgEIAQAAAA==.',
Dr='Drakyon:BAAANQAECgMIBgAAAA==.Dreaddlord:BAAANQAECgEIAQABNQAECgYIEgAEAAAAAA==.Dreadiedude:BAAANQAECgYIEQAAAA==.Drowlie:BAAANQADCgYIBgABNQAECgUICQAEAAAAAA==.',
Du='Durrin:BAAANQAECgQIBgAAAA==.Dutchman:BAAANQAECgQICAAAAA==.',
Ef='Effectus:BAABNQAECoEZAAQVAAcKeg+LeQCaAQAVAAcKeg+LeQCaAQAGAAIKtQTMYABKAAAWAAEKNwevKAAyAAAAAA==.',
Ei='Eith:BAAANQAECgYICwAAAA==.',
El='Elele:BAAANQABCgUIBQAAAA==.Eljay:BAAANQAECgYJDwAAAA==.Ellell:BAABNQAECoEnAAIIAAYK9QmXkgAeAQAIAAYK9QmXkgAeAQAAAA==.Ellieb:BAAANQAECgIIAgAAAA==.Elliemental:BAAANQABCggIDQAAAA==.',
Em='Emberly:BAAANQADCgEIAQAAAA==.Emsulquiorra:BAAANQAECgMIBAAAAA==.',
En='Endersfault:BAABNQAECoEkAAIJAAkKiB2qBAD4AgAJAAkKiB2qBAD4AgAAAA==.Enterni:BAAANQAECgUIBQAAAA==.Enve:BAAANQADCgEIAQABNQADCgQIBAAEAAAAAA==.',
Ep='Epicdemoness:BAABNQAECoEgAAIKAAgK6hryFQCEAgAKAAgK6hryFQCEAgAAAA==.',
Er='Eroni:BAAANQAECgYIDwAAAA==.',
Eu='Euphea:BAAANQADCgcIDgAAAA==.',
Ev='Evaelfie:BAABNQAECoEgAAMXAAkKuxAuJgAGAgAXAAkKuxAuJgAGAgAFAAMKagQykwByAAAAAA==.',
Fa='Fanks:BAAANQADCgUIBQABNQADCgQIBAAEAAAAAA==.Farrand:BAAANQADCgQIBAAAAA==.',
Fe='Fearology:BAAANQAECgQIBAAAAA==.Felcollins:BAAANQAECgMIAwAAAA==.Felicia:BAABNQAECoEdAAIYAAgKbSDnDwDuAgAYAAgKbSDnDwDuAgAAAA==.Fellordkiki:BAABNQAECoEhAAQWAAgKpg/lDwADAQAVAAYKeAsrsAALAQAWAAUK2ArlDwADAQAGAAQK+AqrNADbAAAAAA==.',
Fi='Filthydh:BAAANQADCgYIBgABNQAECgkJIgAUAPMjAA==.Filthypally:BAABNQAECoEiAAIUAAkK8yNpEABqAwAUAAkK8yNpEABqAwAAAA==.Fivëam:BAAANQABCgIJAgAAAA==.',
Fl='Flashheart:BAAANQAECgQIBQAAAA==.Fleabag:BAAANQADCgYJEwAAAA==.',
Fo='Fossgate:BAAANQAECggIEQABNQAECggIIwAFAL0DAA==.Foxe:BAEANQADCgMIAwABNQAECgUIFAAJAFckAA==.',
Fr='Freezefauker:BAAANQAECgYIEQAAAA==.Fridge:BAAANQAECgYIEwAAAA==.Frostxfury:BAAANQAECgIIAgAAAA==.Frøstynips:BAACNQAFFIEdAAQXAAYKuBnuAgCfAQAXAAUKaxfuAgCfAQAZAAIKVRh9FQCXAAAFAAEKkRmAEgBgAAA1AAQKgT4AAxcACQriJT8EAIMDABcACQqCJT8EAIMDAAUACQpQJBsWANICAAAA.',
Fu='Furysdeath:BAAANQAECgcIBwAAAA==.Furysgrip:BAABNQAECoEdAAIZAAkKZA7NPADNAQAZAAkKZA7NPADNAQAAAA==.',
['Fì']='Fìsty:BAAANQADCgYIBgAAAA==.',
Ga='Gabagool:BAABNQAECoEYAAIMAAYK1QaPqgBFAQAMAAYK1QaPqgBFAQABNQAECgEIAQAEAAAAAA==.Gaidal:BAABNQAECoEZAAMRAAYK2hmwEACIAQARAAUKmxmwEACIAQAaAAIKCRo9LgCZAAAAAA==.Galafrey:BAAANQAECgQIBQABNQAECggIGgAMAO4bAA==.Garaktou:BAAANQADCgQICAAAAA==.Gashweaver:BAAANQADCgMJAwAAAA==.',
Ge='Gekyum:BAACNQAFFIEJAAIQAAUKLCA1BADlAQAQAAUKLCA1BADlAQA1AAQKgSgAAhAACQpyI7YEAHQDABAACQpyI7YEAHQDAAAA.Getinmyspit:BAAANQAECgQIBQAAAA==.',
Gh='Ghazgkhull:BAAANQADCgYIDQABNQAECgIIAgAEAAAAAA==.',
Gi='Gidyana:BAAANQAECgMIAwAAAA==.Girlsdayoni:BAAANQAECgQICAAAAA==.Girlsnight:BAAANQADCgQIBwAAAA==.',
Gl='Glancelot:BAABNQAECoEYAAIUAAkK3x7eHwAVAwAUAAkK3x7eHwAVAwAAAA==.Glipglorp:BAAANQADCgQIBAAAAA==.',
Gn='Gnuh:BAAANQADCggIEAABNQAECgYIEQAEAAAAAA==.Gnurse:BAAANQAECgQICAAAAA==.',
Go='Gommo:BAAANQAECgcIEAAAAA==.Goodgirl:BAAANQAECgMIAwAAAA==.Gorbad:BAAANQAECgEIAQAAAA==.',
Gr='Greggoryy:BAAANQAECgIIAgAAAA==.Groundizzle:BAAANQAECgcIDwAAAA==.',
Gt='Gtoromu:BAAANQADCggJFAAAAA==.',
Gu='Guanyu:BAAANQAECgUIBgAAAA==.Guccisosa:BAAANQADCgYIBgAAAA==.Guccisweet:BAAANQADCggICgAAAA==.Guineamon:BAAANQAECgEIAQAAAA==.',
Ha='Hammel:BAAANQAECggIAQAAAA==.Haruk:BAABNQAECoEkAAIbAAkK1yBbCwBOAwAbAAkK1yBbCwBOAwAAAA==.',
He='Heatfist:BAAANQAECgUIDgAAAA==.Helldridge:BAAANQAECgIIBAAAAA==.Heåls:BAAANQAECgUIEAAAAA==.',
Hi='Hirukek:BAAANQAECgYIBwAAAA==.',
Ho='Hoelishock:BAAANQAECgYJBwAAAA==.Hollynova:BAAANQAECgEIAQAAAA==.Holychad:BAABNQAECoEnAAMbAAkKDhUHLwBwAgAbAAkKDhUHLwBwAgAUAAgKxRZFZAAVAgAAAA==.Honeydew:BAACNQAFFIEWAAMTAAUK7BSKBACNAQATAAUK7BSKBACNAQAcAAEK8RWsCABOAAA1AAQKgTIAAhMACQptIe8JAAkDABMACQptIe8JAAkDAAAA.Honganteresa:BAAANQAECgYIDgAAAA==.Hoofmax:BAAANQADCgYICAAAAA==.Hotteemie:BAAANQADCgcIDgAAAA==.',
['Hø']='Høtdøts:BAAANQAECgEIAQAAAA==.',
If='Ifrit:BAAANQAECgIIAwABNQAECgkJJAAbAEEjAA==.',
Il='Illidank:BAABNQAECoEaAAMYAAgKpRhkHQBoAgAYAAgKpRhkHQBoAgAKAAIK3wSsUgBSAAAAAA==.',
Im='Imanoob:BAAANQAECgIIAgAAAA==.Imperiex:BAAANQADCgEIAQAAAA==.',
In='Infectedlock:BAAANQAECgYIBgABNQAFFAYIEQAKAAwcAA==.Inurdreams:BAAANQABCgcICAAAAA==.',
Io='Ionsw:BAABNQAECoEeAAMVAAkKchWyTwAeAgAVAAgKphWyTwAeAgAGAAUKBQyCKwANAQAAAA==.',
Ip='Ipsifu:BAAANQAECgcICQABNQAFFAUIDQAdAHEZAA==.',
Ir='Ironski:BAAANQAECgIIAwAAAA==.',
Ja='Jackillz:BAAANQADCgUIBQABNQAECgcIEAAEAAAAAA==.Jatzsy:BAAANQAECgMIBQAAAA==.Jayar:BAAANQAECgUICwAAAA==.Jazzy:BAAANQADCgUIBQAAAA==.',
Je='Jee:BAAANQAECgYIDwAAAA==.Jenkem:BAAANQABCgQIBgAAAA==.Jescon:BAAANQAECgIIAgAAAA==.Jeé:BAAANQADCgUJBQAAAA==.',
Ji='Jiamil:BAABNQAECoEfAAIbAAgK8xy8IAC7AgAbAAgK8xy8IAC7AgAAAA==.Jigolow:BAAANQADCgUIBQAAAA==.',
Jo='Johlissa:BAAANQAECgIIAgAAAA==.Jolteon:BAAANQAECgYIBgAAAA==.',
Ju='Jubber:BAAANQAECgYIEwAAAA==.',
Ka='Kadashyy:BAAANQAECgIIAwAAAA==.Kaherd:BAAANQAECgUIDAAAAA==.Kakapooeybum:BAAANQAECgUIBQAAAA==.Kakashimaya:BAAANQADCgQIBgAAAA==.Kamikasi:BAAANQADCggICwAAAA==.Kaneshiro:BAABNQAECoEWAAIeAAcKLxJWyACkAQAeAAcKLxJWyACkAQAAAA==.Karytheca:BAAANQADCgYIBAAAAA==.Katae:BAAANQAECgYJEAAAAA==.Kayrali:BAAANQADCgIIAgAAAA==.',
Kb='Kboomz:BAAANQADCgYJDAABNQADCggIFQAEAAAAAA==.',
Ke='Kegaz:BAAANQAECgUICAAAAA==.Kegward:BAAANQADCgUIBQAAAA==.Kelynada:BAABNQAECoEWAAIVAAYKdBBdiQBrAQAVAAYKdBBdiQBrAQAAAA==.Kendd:BAACNQAFFIEXAAMdAAcKjRibAQAvAgAdAAYKyxmbAQAvAgAfAAMKow2jBwD8AAA1AAQKgSkABB0ACQqtIlUEAEADAB0ACQpxH1UEAEADAB8ABQp9IHQpANsBACAABwpCEBELAIsBAAAA.Kerrigân:BAAANQAECgIIAgAAAA==.Keyshock:BAAANQADCgYJBgAAAA==.',
Ki='Kindra:BAAANQADCgYIBgAAAA==.Kithari:BAAANQAECgYIEQAAAA==.',
Kn='Knickerbits:BAAANQABCgEIAQAAAA==.Knotting:BAAANQADCggJFgAAAA==.',
Ko='Kochez:BAAANQADCgUICQAAAA==.Kollateral:BAAANQAECgUICQAAAA==.',
Kr='Krankiekunt:BAACNQAFFIEHAAIhAAQKzxcTAwA3AQAhAAQKzxcTAwA3AQA1AAQKgSUAAiEACQr6IHgDACwDACEACQr6IHgDACwDAAAA.Krellhim:BAAANQAECgIIAQAAAA==.',
Ku='Kuanija:BAABNQAECoEbAAMLAAkKmhplCQCuAgALAAkKmhplCQCuAgAIAAUKUhHhigAxAQAAAA==.Kuuga:BAAANQAECggIEgAAAA==.',
La='Landwalker:BAACNQAFFIEGAAIiAAMK2hJlBwD8AAAiAAMK2hJlBwD8AAA1AAQKgR0AAiIACQovH80HABsDACIACQovH80HABsDAAAA.Langas:BAAANQAECgIIAQABNQAECggIBgAEAAAAAA==.Langasbrew:BAAANQAECggIBgAAAA==.Latorius:BAAANQAECgcIEQAAAA==.Lavaloadz:BAAANQADCggIDQAAAA==.Lazziel:BAAANQAECgUIBQAAAA==.',
Le='Lexavis:BAACNQAFFIEIAAMbAAQKMxFPDwDsAAAbAAMKkApPDwDsAAAUAAIKNRlyFQCZAAA1AAQKgTMAAxsACQoNHd8PACoDABsACQoNHd8PACoDABQACQp+IjokAAADAAE1AAQKCAgwAB4AQA4A.Leyiast:BAABNQAECoEaAAIeAAcKChDvugC/AQAeAAcKChDvugC/AQAAAA==.Leyissa:BAAANQADCgIIAgABNQAECgcIGgAeAAoQAA==.',
Lh='Lheo:BAAANQADCgYICAAAAA==.',
Li='Liggma:BAAANQAECgQICAAAAA==.Lightborn:BAAANQADCggICAAAAA==.Lilbai:BAAANQAECggICgABNQAECggICgAEAAAAAA==.Lilthicc:BAAANQAECgEIAQAAAA==.Lilwhite:BAAANQAECgcIEQABNQAECggICgAEAAAAAA==.Liminal:BAAANQADCgcJBwAAAA==.',
Lo='Lockaboom:BAAANQAECgcIDwAAAA==.Loldruid:BAAANQAECgYIEgAAAA==.Lom:BAABNQAECoEbAAIPAAkKkhGtPQAfAgAPAAkKkhGtPQAfAgAAAA==.Lomzz:BAAANQADCgIJAgAAAA==.',
Lu='Lukie:BAEANQAECgIIAgAAAA==.',
Ly='Lycan:BAAANQADCgEIAQAAAA==.Lym:BAAANQAECgUIBQAAAA==.Lynarium:BAAANQAECgEIAQAAAA==.Lyradaeris:BAAANQADCgcIBwAAAA==.',
['Lÿ']='Lÿrath:BAAANQADCggIEQAAAA==.',
Ma='Magepill:BAAANQADCgQIBAAAAA==.Magharitta:BAABNQAECoEbAAMFAAgK/R/7GgCpAgAFAAcKQCL7GgCpAgAXAAIK0BJjawB6AAAAAA==.Magroth:BAAANQAECgcIEAAAAA==.Mahwae:BAAANQADCgIIAwAAAA==.Makavelli:BAAANQADCgIIAgAAAA==.Manoliso:BAAANQAECgUICQAAAA==.Marmite:BAAANQAECgcIDgAAAA==.Maybeforever:BAAANQAECgQIBwAAAA==.',
Me='Medesin:BAAANQADCgYJFwAAAA==.Mekhanite:BAAANQAECgYIDwAAAA==.Mercykill:BAAANQADCgUJBQAAAA==.',
Mi='Milfdella:BAAANQAECgMIAwAAAA==.Milspec:BAAANQAECgYJEgAAAA==.Minami:BAAANQAECgYIEQAAAA==.Minhiriath:BAAANQADCgQIBAAAAA==.Mintbadger:BAAANQADCgUIBwAAAA==.Mistea:BAAANQADCgMJAwAAAA==.Misticuffs:BAAANQAECgMIBAABNQAECgEIAQAEAAAAAA==.',
Mo='Mochimask:BAAANQAECgYIBgAAAA==.Moetown:BAAANQADCggICAABNQAFFAUIEAAeAJURAA==.Moistex:BAAANQAECgEIAQABNQAECggIHwAJAE8bAA==.Moistmaker:BAABNQAECoE3AAIPAAgKJSQkEAAbAwAPAAgKJSQkEAAbAwAAAA==.Mold:BAAANQAECgUIBQABNQAECgYICwAEAAAAAA==.Momotaku:BAABNQAECoEZAAMIAAgK0hAUTAD3AQAIAAgK0hAUTAD3AQAPAAYKag8CegBGAQAAAA==.Monalisa:BAAANQAECgcIDQAAAA==.Monkmon:BAAANQADCgIIAgABNQAECgYIDQAEAAAAAA==.Monthax:BAAANQAECgUIBQAAAA==.Moonoo:BAAANQADCgUIBQAAAA==.Mordok:BAAANQAECgEIAQAAAA==.Morena:BAAANQADCggIGAAAAA==.Morgaina:BAAANQAECgUIBQAAAA==.',
Mu='Muffinman:BAAANQAECggIBgABNQAECggIBgAEAAAAAA==.Muscleclub:BAABNQAECoEfAAIcAAgKzhy3CgCmAgAcAAgKzhy3CgCmAgAAAA==.',
My='Mysticalzz:BAAANQAECgMIBAAAAA==.',
['Më']='Mëmëmë:BAAANQAECgMIBAAAAA==.',
['Mù']='Mùji:BAAANQAECgEIAQAAAA==.',
['Mü']='Müddrätt:BAAANQAECgEIAQAAAA==.',
Na='Naeff:BAAANQAECgYIAQAAAA==.Natria:BAABNQAECoEYAAIHAAgKoQl9FwCRAQAHAAgKoQl9FwCRAQAAAA==.Naya:BAABNQAECoEhAAIeAAgKMyW8HABRAwAeAAgKMyW8HABRAwAAAA==.',
Ne='Nerfdehoof:BAAANQAECgQIBAAAAA==.Nerfdelag:BAAANQAECgcIEwAAAA==.Nerfgün:BAABNQAECoEaAAIMAAgK7hsGPQBsAgAMAAgK7hsGPQBsAgAAAA==.Nescåfe:BAAANQADCgYJBgAAAA==.',
Ni='Nicodautroc:BAAANQAECgUICgAAAA==.Ninish:BAAANQADCgMIBQAAAA==.Nintone:BAAANQAECgYICwAAAA==.',
No='Nonippies:BAAANQAECgQICgAAAA==.Noolie:BAAANQADCgIIAgABNQAECgUICQAEAAAAAA==.',
Ns='Nsi:BAAANQADCgUJCAAAAA==.',
Nu='Nubishe:BAAANQAECgMIAwAAAA==.Nutsdormu:BAABNQAECoEaAAIOAAUK3hOOJgA3AQAOAAUK3hOOJgA3AQAAAA==.',
Ny='Nythe:BAAANQADCgEIAQABNQADCgIIAgAEAAAAAA==.Nyxmoona:BAAANQADCgcIGAAAAA==.',
['Nà']='Nàishà:BAAANQAECgUICAAAAA==.',
Ob='Obskurer:BAABNQAECoEZAAMPAAkKeBnMIgCjAgAPAAkKeBnMIgCjAgAIAAEKsAw4AQEwAAAAAA==.',
Od='Odinwolf:BAAANQAECgQICQABNQAECgkJJAAbAEEjAA==.',
Oj='Ojisancage:BAABNQAECoE4AAIVAAgKOSB+GAD3AgAVAAgKOSB+GAD3AgAAAA==.',
Om='Omegaflaps:BAAANQAECgYJBgAAAA==.Omnitract:BAAANQADCgUIBQAAAA==.',
Or='Orinys:BAABNQAECoEUAAIOAAUKng3hKQAQAQAOAAUKng3hKQAQAQAAAA==.Orkky:BAABNQAECoEeAAIZAAgKbiH8DwAIAwAZAAgKbiH8DwAIAwAAAA==.',
Pa='Page:BAABNQAECoEgAAMfAAkKHRZ5HwAqAgAfAAgK6BN5HwAqAgAdAAgK9g77FwD6AQAAAA==.Pakurruun:BAAANQAECgUIDwAAAA==.Palahan:BAAANQADCgYIBwAAAA==.Palala:BAAANQADCgcIBwAAAA==.Pallatress:BAAANQADCgcIGAAAAA==.Pandor:BAAANQAECgEIAQAAAA==.Panginoon:BAABNQAECoEeAAMXAAkKSB95DwDdAgAXAAkKgxt5DwDdAgAFAAgKJh/qIwBlAgAAAA==.Paparìch:BAABNQAECoEgAAISAAkKgh+qEwAFAwASAAkKgh+qEwAFAwAAAA==.Paphio:BAAANQADCggIDAAAAA==.',
Pe='Perden:BAAANQADCgYIBgAAAA==.Pesh:BAAANQADCgYIDQAAAA==.',
Pg='Pgundry:BAAANQADCggIFwAAAA==.',
Ph='Phakin:BAAANQADCgMIAwAAAA==.Phex:BAAANQAECgMJAwAAAA==.',
Pi='Picks:BAAANQABCgEIAQAAAA==.Piddlesworth:BAAANQADCggIFwAAAA==.Piergeiron:BAAANQAECgYIBAAAAA==.Pinkyblue:BAABNQAECoEbAAMVAAkKWx2DQQBOAgAVAAgKJx2DQQBOAgAGAAEK9x5zYABLAAAAAA==.Pipssqeek:BAAANQADCgcIHAAAAA==.',
Pj='Pjw:BAABNQAECoEnAAIbAAkKFRf5KQCJAgAbAAkKFRf5KQCJAgAAAA==.',
Pl='Plarrior:BAAANQADCgMIAwAAAA==.Plip:BAABNQAECoE+AAQIAAgKohyHKQCeAgAIAAgKohyHKQCeAgALAAIK7As7JQB/AAAPAAEKjgPRAQEbAAAAAA==.',
Po='Pokerrface:BAAANQADCggICAABNQAECgIIAgAEAAAAAA==.Polloloco:BAAANQADCgEIAQAAAA==.Poobumhead:BAABNQAECoEUAAIVAAUKRRBomABEAQAVAAUKRRBomABEAQAAAA==.Porkroll:BAAANQADCgIIAgAAAA==.Poweredman:BAAANQADCgIIAgAAAA==.Powerheal:BAAANQAECgUIBQAAAA==.',
Pr='Praetoar:BAAANQADCgYJBgAAAA==.Prftlybalncd:BAABNQAECoEXAAIOAAcKIxV9GgDcAQAOAAcKIxV9GgDcAQABNQAECgkJJwAbABUXAA==.Probabele:BAAANQAECgEIAQAAAA==.Probably:BAACNQAFFIEbAAMXAAUK4SI+AQALAgAXAAUK4SI+AQALAgAZAAEKkBA9JQAyAAA1AAQKgUAABBcACQrrJL4EAHgDABcACQrrJL4EAHgDABkAAQr/HCOgAE4AAAUAAQrnEzipADwAAAAA.Protato:BAAANQADCggJCAAAAA==.',
Ps='Psyche:BAAANQAECgcIBwAAAA==.',
Pt='Ptrie:BAAANQAECgcIDwAAAA==.',
Pu='Pudgeyp:BAABNQAECoEbAAIjAAkKxhimRQB9AgAjAAkKxhimRQB9AgAAAA==.Pudgeyr:BAAANQAECgYIAwAAAA==.Punj:BAAANQAECgMIBAAAAA==.Puntarr:BAAANQADCgcIGwAAAA==.Puppybonks:BAAANQAECgIIAgAAAA==.Purdxpriest:BAAANQABCggICAABNQADCggJDwAEAAAAAA==.Purdxwarrior:BAAANQABCgQIBQABNQADCggJDwAEAAAAAA==.',
Pw='Pwrbottom:BAAANQAECgQIAwAAAA==.',
Py='Pyroskolv:BAAANQAECgIIAQABNQAFFAUICwAKAPwYAA==.',
Qi='Qibla:BAABNQAECoEdAAIUAAgKuAtSigCpAQAUAAgKuAtSigCpAQAAAA==.',
Qu='Quarizma:BAACNQAFFIEPAAIQAAYK8SDdAQBhAgAQAAYK8SDdAQBhAgA1AAQKgS0AAhAACQpDJWUCAKwDABAACQpDJWUCAKwDAAAA.',
Ra='Radiantbunz:BAAANQADCggIGgAAAA==.Rankone:BAAANQAECgMIAwABNQAECgQICQAEAAAAAA==.Raxe:BAEBNQAECoEUAAIJAAUKVyTeDAARAgAJAAUKVyTeDAARAgAAAA==.',
Re='Reaperoffire:BAAANQAECgEIAQAAAA==.Repliod:BAABNQAECoEcAAIaAAYKdiRvCQBuAgAaAAYKdiRvCQBuAgAAAA==.Reploid:BAAANQADCgcIBwABNQAECgYIHAAaAHYkAA==.Restho:BAABNQAECoEfAAMPAAgK0h6QLwBhAgAPAAcKJiKQLwBhAgAIAAcKSBTIVgDPAQAAAA==.Revarix:BAAANQAECgcIEQAAAA==.',
Rh='Rhaella:BAAANQAECgYIEQAAAA==.Rhuiser:BAABNQAECoEaAAIjAAgK0yLsMQDHAgAjAAgK0yLsMQDHAgAAAA==.Rhuno:BAAANQAECgQICAAAAA==.',
Ri='Rigormortits:BAAANQAECgIIAgABNQAECggIGgAYAKUYAA==.Ritsuki:BAAANQAECgUICwAAAA==.Ritéboys:BAAANQAECggIEwABNQAECggIGQAKADghAA==.Ritëboys:BAABNQAECoEZAAMKAAgKOCEmEgCzAgAKAAgKOCEmEgCzAgAYAAEKig/ebwA9AAAAAA==.',
Ro='Rocketjuice:BAABNQAECoEqAAIeAAgKRheifQBJAgAeAAgKRheifQBJAgAAAA==.Roflpwnnt:BAAANQAECgEJAQAAAA==.Ronjames:BAAANQADCgUICAAAAA==.Rothy:BAAANQAECggIDQAAAA==.',
Ru='Rutee:BAABNQAECoEiAAIUAAkK4xSRTwBWAgAUAAkK4xSRTwBWAgAAAA==.',
Ry='Ryz:BAAANQAECgEJAQABNQAECgMIAwAEAAAAAA==.',
Sa='Saethene:BAAANQAECgEIAQABNQAECggIGgAMAO4bAA==.Safh:BAAANQADCggICgAAAA==.Safk:BAABNQAECoEfAAIZAAgKdRcGKwAyAgAZAAgKdRcGKwAyAgAAAA==.Saleina:BAAANQADCgIIAwAAAA==.Sandiwang:BAAANQADCgUICAAAAA==.Sanosan:BAAANQAECgMIAwAAAA==.Sanosanz:BAAANQAECgIJAwAAAA==.Saptko:BAAANQADCgUIBQAAAA==.Sartoc:BAAANQAECgMIBAABNQAECggIGgAMAO4bAA==.',
Sc='Scabbo:BAAANQAECgYICgAAAA==.Scalesoul:BAAANQAECgcIHwAAAQ==.',
Sd='Sdfgoose:BAAANQAECgYICAAAAA==.',
Se='Seiferoth:BAABNQAECoEkAAIbAAkKQSPrBQCHAwAbAAkKQSPrBQCHAwAAAA==.Selitha:BAAANQADCgQIBAAAAA==.Senddori:BAAANQADCgUIBQAAAA==.Sergantcolen:BAAANQAECgUIBgAAAA==.Señornanna:BAAANQADCgQIBAAAAA==.',
Sh='Shaddai:BAAANQAECgUIDQAAAA==.Shadowofevil:BAAANQAECgYIEAAAAA==.Shadypally:BAAANQADCgUJBQAAAA==.Shakywing:BAAANQADCgIIAgAAAA==.Shalavoo:BAAANQAECgIIAgAAAA==.Shamankiller:BAAANQAECgMICAAAAA==.Shamazzle:BAAANQAECgUICQAAAA==.Shamlen:BAABNQAECoErAAIIAAgK9wT/eABhAQAIAAgK9wT/eABhAQAAAA==.Sharkyob:BAAANQAECgQIBwAAAA==.Shichokeme:BAAANQADCgMIAwAAAA==.Shiicho:BAAANQADCgYICwAAAA==.Shinieedruid:BAAANQAFFAEIAQAAAA==.Shions:BAAANQADCgYIBgAAAA==.Shockostoob:BAAANQAECgYIEQAAAA==.',
Si='Sidatas:BAAANQADCggICwAAAA==.Silverspulse:BAABNQAECoE7AAIBAAgKGB84GADnAgABAAgKGB84GADnAgAAAA==.Sinequanon:BAABNQAECoEhAAMDAAgKfRXsHgD5AQADAAcKQhjsHgD5AQABAAgKxBVJSgD1AQAAAA==.Sinfulbeast:BAABNQAECoEkAAQMAAkKMxthLwCeAgAMAAgKOBxhLwCeAgAkAAMKaxJ4DgBHAAAQAAEKrQi8bAA1AAAAAA==.Sippycup:BAAANQAECgEIAQABNQAECgkJHQAeAEMYAA==.',
Sk='Skrogan:BAAANQAECgEIAQAAAA==.Skulv:BAACNQAFFIELAAIKAAUK/Bj5AwDLAQAKAAUK/Bj5AwDLAQA1AAQKgSgAAwoACQrlI3wDAJMDAAoACQrlI3wDAJMDABgAAgpyFSthAIYAAAAA.',
Sl='Slakzor:BAAANQADCgQIAwAAAA==.Slammed:BAAANQAECgYIDQAAAA==.Sleepyshark:BAABNQAECoEYAAMVAAgKlRhdOgBnAgAVAAgKlRhdOgBnAgAGAAEKzALsdwAlAAAAAA==.Slopain:BAAANQAECgYIEwAAAA==.Slopflop:BAAANQAECggIBQAAAA==.Slowlearner:BAAANQAECgQIBAAAAA==.Slåppery:BAABNQAECoEnAAIQAAkKjSIrBAB/AwAQAAkKjSIrBAB/AwAAAA==.',
Sm='Smashy:BAAANQADCggIGQAAAA==.Smìtty:BAAANQADCgMIBAAAAA==.',
Sn='Snorlax:BAAANQAECgcIEwAAAA==.Snort:BAAANQAECgUIDAAAAA==.',
So='Sona:BAAANQAECgcIDQAAAA==.Sonotafurry:BAAANQAECgIIAgAAAA==.Soresu:BAAANQAECgQICQAAAA==.Soundwit:BAABNQAECoEkAAIfAAcK3SBVEgCkAgAfAAcK3SBVEgCkAgAAAA==.',
Sp='Sparrowstalk:BAAANQADCgEIAQAAAA==.Spindrift:BAAANQAECgYIEQAAAA==.Spoonyy:BAACNQAFFIEKAAMeAAUKRB3QDQC8AQAeAAUKchvQDQC8AQAlAAEKzRxCCQBXAAA1AAQKgSMAAx4ACQodIjo4APoCAB4ACQqiITo4APoCACUAAgpvJU4bANIAAAAA.Spudder:BAAANQABCgIIAgABNQABCgQIAwAEAAAAAA==.',
Sq='Squanchie:BAAANQAECgEIAQABNQAECgcIGAAMAMYVAA==.',
St='Starstorm:BAAANQADCgYJBgAAAA==.Steinlarger:BAAANQAECgUJBQAAAA==.Stephen:BAAANQAECgYIDAABNQAECggIHwAPANIeAA==.Storrmbender:BAAANQAECgYJDgAAAA==.Stoutbrew:BAAANQADCggICQAAAA==.Strípe:BAAANQAECgYICAAAAA==.Stuy:BAABNQAECoEnAAIQAAkKIBfjEgChAgAQAAkKIBfjEgChAgAAAA==.Stãria:BAAANQAECgYICQAAAA==.Stårlå:BAAANQABCgcIDAAAAA==.Störme:BAAANQADCgcIDwAAAA==.',
Su='Sugarburst:BAAANQAECgIIBQAAAA==.Sukmahdisc:BAAANQAECgQIBAAAAA==.',
Sw='Swak:BAABNQAECoEzAAIMAAgKeRYcRwBMAgAMAAgKeRYcRwBMAgAAAA==.Sweet:BAAANQAECgMIAQAAAA==.Switchmage:BAAANQADCggJEAAAAA==.Switchskin:BAABNQAECoEhAAISAAkKbh/TEAAgAwASAAkKbh/TEAAgAwAAAA==.',
Sy='Syvrogue:BAABNQAECoEYAAIdAAkK7QlGGwDWAQAdAAkK7QlGGwDWAQABNQAECgEIAQAEAAAAAA==.',
Ta='Tallinor:BAABNQAECoEUAAIlAAUKqw5RFAAjAQAlAAUKqw5RFAAjAQAAAA==.Tamukå:BAAANQAECgEIAQAAAA==.Tanags:BAABNQAECoEaAAIPAAcK3iI5HwC5AgAPAAcK3iI5HwC5AgAAAA==.Tankakus:BAAANQAECgEIAgAAAA==.Taumast:BAAANQADCgMIAwABNQAECgcIDwAEAAAAAA==.Tauter:BAAANQADCgcIFQAAAA==.Tazzee:BAAANQAECgQIBAAAAA==.',
Te='Temperature:BAAANQAECgIIBQABNQAECgMJBgAEAAAAAA==.Testaxltesta:BAABNQAECoEdAAMBAAgKwCN1DwAiAwABAAgKRiN1DwAiAwACAAUK6yQ9BQAgAgABNQADCggIDgAEAAAAAA==.',
Th='Thael:BAAANQADCgQIBAAAAA==.Thalia:BAABNQAECoEcAAImAAgKTBQyFgD4AQAmAAgKTBQyFgD4AQAAAA==.Thoriatit:BAAANQAECgYIDgAAAA==.Thottydot:BAAANQAECgEIAQAAAA==.Thox:BAAANQADCgIIAgAAAA==.Throber:BAAANQADCgUJBQAAAA==.Thunderzz:BAAANQADCgUIBQABNQADCggIFQAEAAAAAA==.Thyranux:BAAANQADCgMIBAAAAA==.',
Ti='Tienchi:BAAANQAECgcIEwAAAA==.Tiendira:BAAANQAECgQIBAAAAA==.Tierk:BAAANQADCggICAABNQAECgkJIAAfAB0WAA==.Tim:BAAANQAECgcIEgAAAA==.Timmyy:BAAANQAECgEIAQAAAA==.',
Tl='Tlo:BAAANQADCgcIBwABNQAFFAUIDQAMAIcaAA==.',
To='Tollmemaybe:BAABNQAECoFGAAMmAAgKmiPBBQAlAwAmAAgKmiPBBQAlAwAUAAUKLRCBwgAkAQAAAA==.Tormént:BAABNQAECoEkAAIXAAkKDyIoDQD4AgAXAAkKDyIoDQD4AgAAAA==.',
Tr='Transport:BAAANQAECgMJBgAAAA==.Traumatizer:BAAANQADCggJDQAAAA==.Trenbolone:BAAANQADCgIIAwAAAA==.Tronix:BAAANQAECgUICAAAAA==.Trucidario:BAAANQAECgIIAgAAAA==.Truwar:BAABNQAECoEnAAIjAAkKQSCGLwDQAgAjAAkKQSCGLwDQAgAAAA==.',
Tu='Tubbquake:BAAANQAECgcIDwAAAA==.Tuffhunts:BAAANQAECgMIAwAAAA==.Tufflock:BAAANQADCgEJAQAAAA==.',
Tw='Twatasaurus:BAAANQAECgQIBgAAAA==.',
['Tî']='Tîmmeh:BAAANQAECgYIDAABNQAECgEIAQAEAAAAAA==.',
['Tï']='Tïmmeh:BAAANQAECgQIBAABNQAECgEIAQAEAAAAAA==.',
Ub='Ubica:BAABNQAECoEiAAMfAAkKaw4THgA2AgAfAAkKaw4THgA2AgAdAAQK1ATkNgC/AAAAAA==.',
Ul='Ultratunee:BAAANQAECgYIBgABNQAECgcIDwAEAAAAAA==.',
Un='Unholykníght:BAAANQADCgEIAQAAAA==.Unvoid:BAAANQAECgIICAAAAA==.',
Ur='Urzog:BAAANQADCgUIBQAAAA==.',
Us='Useacooldown:BAAANQAECgYIBwAAAA==.',
Va='Valaya:BAAANQAECgIIAwAAAA==.Valentine:BAAANQAECgcIDgAAAA==.Valithor:BAAANQAECgMIBAAAAA==.Valkyrion:BAACNQAFFIEFAAIOAAMKpw31CwDrAAAOAAMKpw31CwDrAAA1AAQKgSQAAg4ACQq6ITsEAFsDAA4ACQq6ITsEAFsDAAAA.Valysan:BAAANQADCgEIAQAAAA==.Vann:BAAANQADCggIEAAAAA==.',
Ve='Velathri:BAAANQAECgUIBQAAAA==.Velenlerolan:BAACNQAFFIEHAAIFAAUKixtjAwCnAQAFAAUKixtjAwCnAQA1AAQKgSgAAgUACQoAJi4EAJsDAAUACQoAJi4EAJsDAAAA.Velrayne:BAABNQAECoEcAAMMAAgKexcxTAA8AgAMAAcKvxkxTAA8AgAQAAYKrQYOOgAZAQAAAA==.Veng:BAAANQABCgQIBAAAAA==.Verailde:BAAANQADCgUICQAAAA==.Verathriel:BAAANQABCgQIBgAAAA==.Verilence:BAABNQAECoEdAAQVAAcKZCAIMgCGAgAVAAcKHiAIMgCGAgAWAAUKJBwNCwBtAQAGAAEK1h0UXwBPAAAAAA==.Veventhius:BAAANQADCgIIAgAAAA==.Vext:BAAANQADCgMIAwAAAA==.',
Vi='Vindicor:BAAANQAECgYIBgAAAA==.',
Vo='Voidberg:BAAANQAECgQIBQABNQAECgkJIwAiAD8eAA==.Vorndryad:BAAANQAECgEJAgAAAA==.',
Vr='Vras:BAAANQADCgUIAwAAAA==.',
Vy='Vynburn:BAABNQAECoEjAAIeAAkKKheXXACaAgAeAAkKKheXXACaAgAAAA==.',
Wa='Warmon:BAAANQADCggIFgAAAA==.Watson:BAAANQAECgYIEQAAAA==.Waveryy:BAAANQADCgMIBgAAAA==.',
We='Wemblitz:BAAANQADCgcIEgAAAA==.Wesh:BAABNQAECoEqAAQFAAkKAxrBLgAcAgAFAAgKARvBLgAcAgAZAAcKDBNyRQCiAQAXAAEKPRGyggA1AAAAAA==.',
Wh='Whio:BAAANQAECgYIEwAAAA==.Whitetabby:BAAANQAECgYIDQAAAA==.Whtclass:BAAANQAECgMIAwAAAA==.',
Wi='Wintersfence:BAAANQADCgYJCAAAAA==.',
Wk='Wkwk:BAAANQAECgQICwAAAA==.',
Wo='Wozxx:BAAANQAECgEIAQAAAA==.',
Wp='Wpd:BAABNQAECoEqAAISAAkK6SHBCAB0AwASAAkK6SHBCAB0AwAAAA==.',
['Wî']='Wîngman:BAABNQAECoEfAAIUAAgKkRexWAA5AgAUAAgKkRexWAA5AgAAAA==.',
Xe='Xenarn:BAEBNQAECoEUAAIhAAUKVA7xGAABAQAhAAUKVA7xGAABAQAAAA==.Xenoruin:BAAANQAECgYIEQAAAA==.',
Xi='Xiphios:BAAANQADCgYIBgAAAA==.',
Ya='Yarpidk:BAAANQADCgcJCQAAAA==.',
Ye='Yejin:BAAANQADCggJCAAAAA==.',
Yo='Yorkie:BAABNQAECoEsAAIeAAkKRSCPGwBVAwAeAAkKRSCPGwBVAwAAAA==.Yoyogi:BAAANQADCgYIBwAAAA==.',
Yu='Yui:BAAANQADCggICAAAAA==.Yurarzir:BAABNQAECoEjAAIeAAkKFxNdbwBrAgAeAAkKFxNdbwBrAgAAAA==.',
Za='Zanisha:BAAANQAECgUIDAAAAA==.Zaz:BAAANQADCgYIBwAAAA==.',
Ze='Zelendorm:BAAANQAECgcIEwAAAA==.',
Zu='Zula:BAAANQADCggIBwABNQAECgQIBgAEAAAAAA==.',
['Ås']='Åshz:BAAANQADCgIIAgABNQAECgUIEAAEAAAAAA==.',
['ßa']='ßaccycønes:BAAANQADCggIIwAAAA==.',
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
