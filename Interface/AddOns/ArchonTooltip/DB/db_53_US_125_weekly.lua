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

local lookup = {'Priest-Holy','Priest-Discipline','Priest-Shadow','Unknown-Unknown','DeathKnight-Unholy','Evoker-Devastation','Warrior-Protection','DemonHunter-Devourer','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Hunter-Marksmanship','Monk-Windwalker','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Druid-Balance','Warlock-Affliction','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Monk-Mistweaver','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Druid-Restoration','Mage-Arcane','Evoker-Preservation','Warrior-Arms','DemonHunter-Havoc','Mage-Frost','Paladin-Protection',}
local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Activion:BAAANQAECgIJAQAAAA==.',
Ad='Addelana:BAAANQADCgQIBAAAAA==.Adelanaa:BAABNQAECoEcAAQBAAgKJhH+OwD6AQABAAgK1hD+OwD6AQACAAUKFQgyDgDpAAADAAEKJgELZAAXAAABNQADCgQIBAAEAAAAAA==.Adrasta:BAAANQADCggIEQAAAA==.Adriell:BAAANQAECgUICwAAAA==.Adura:BAAANQADCgUIBgAAAA==.',
Ae='Aelathe:BAAANQAECgIIAgAAAA==.Aeneas:BAAANQAECggICQAAAA==.Aenimma:BAABNQAECoEVAAIFAAgKmwJoZwDVAAAFAAgKmwJoZwDVAAAAAA==.Aerys:BAAANQADCggIDQAAAA==.',
Ak='Akey:BAAANQAECgUJCgAAAA==.',
Al='Alamwah:BAAANQADCgEIAQABNQAECgEIAQAEAAAAAA==.Alaroo:BAAANQADCggJEQAAAA==.Alatao:BAAANQABCgYIBgAAAA==.Aleinaas:BAAANQADCgYICgAAAA==.Aleine:BAAANQAECgUIBgAAAA==.Alektra:BAAANQAECgcJEgAAAA==.Alexella:BAAANQADCgcICQAAAA==.Allerfala:BAAANQADCgQIBAABNQAECgkJJQAGACogAA==.Alliete:BAAANQADCgIIAgAAAA==.Allya:BAAANQAECgQJCAAAAA==.Aloine:BAABNQAECoEZAAIBAAgKLgOaYgBNAQABAAgKLgOaYgBNAQAAAA==.Alteredbeast:BAAANQAECgQIBAABNQAECgcJEgAEAAAAAA==.',
Am='Amogus:BAAANQAECgQJBAAAAA==.Amoresh:BAAANQAECgQJCQAAAA==.Ampuzzible:BAAANQAECgYIBgAAAA==.',
An='Anbebi:BAAANQAECgUIBgAAAA==.Anchor:BAAANQABCgEIAgAAAA==.Anqu:BAAANQADCgMIAwAAAA==.',
Ar='Arbitera:BAAANQAECgYJEQAAAA==.Arkona:BAAANQADCgcJEQAAAA==.Arthelais:BAAANQAECgEIAQAAAA==.Arzir:BAABNQAECoEfAAIHAAkK8hHFCQAgAgAHAAkK8hHFCQAgAgAAAA==.',
As='Ashbringer:BAAANQAECgYIBwAAAA==.Asmonjoel:BAAANQADCgcICAAAAA==.Assumi:BAAANQADCggIEgAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.',
Au='Audree:BAAANQADCgYIBAAAAA==.Aurellia:BAAANQAECggJCQAAAA==.',
Av='Avoide:BAAANQADCgYJCgAAAA==.',
Ax='Axedup:BAAANQAECgEIAgABNQAFFAYIDAAIAEUaAA==.',
Ay='Aydy:BAAANQAECgQIBAAAAA==.',
Az='Azamat:BAAANQAECgIIAwAAAA==.Azuredemonx:BAABNQAECoEhAAIIAAcKaxblGgAuAgAIAAcKaxblGgAuAgAAAA==.',
Ba='Backup:BAAANQAECgQIEAAAAA==.Balayn:BAAANQADCgYIBgAAAA==.Banan:BAAANQAECgIJAgAAAA==.Banoni:BAAANQABCgQIBAABNQAECgIJAgAEAAAAAA==.',
Bb='Bbajer:BAAANQAECgEIAQAAAA==.Bbqporkbuns:BAABNQAECoEiAAIJAAkKuSDEAgBXAwAJAAkKuSDEAgBXAwAAAA==.',
Be='Bearzy:BAAANQAECgEIAgAAAA==.Bearzz:BAAANQAECgcJEAAAAA==.Belledormi:BAAANQAECgUJCwAAAA==.Bellest:BAAANQAECgcJEAAAAA==.Benji:BAABNQAECoEbAAMKAAkKeiN4CACAAwAKAAkKeiN4CACAAwALAAYKvAqUfAAQAQAAAA==.',
Bf='Bfev:BAAANQAECgYJDAAAAA==.',
Bg='Bggestthighs:BAAANQAECgQIBQABNQAECgcJLAAMACQVAA==.',
Bi='Bid:BAAANQAECgYIDQAAAA==.Bigado:BAAANQADCggICgAAAA==.Bigalo:BAAANQAECgYICgAAAA==.Bigarms:BAAANQAECgIJBQABNQAECgQIBQAEAAAAAA==.Bigfel:BAAANQABCgQIBAAAAA==.Biggesthighz:BAABNQAECoEsAAIMAAcKJBUNIgDLAQAMAAcKJBUNIgDLAQAAAA==.',
Bl='Blindanddeaf:BAAANQAECgUICAAAAA==.Bluee:BAAANQAECgIIAgABNQAECgUICAAEAAAAAA==.',
Bo='Boohbooh:BAAANQADCggIEQAAAA==.Boomakus:BAAANQAECggIEwAAAA==.',
Br='Brannie:BAAANQAECgUJBwAAAA==.Brenine:BAAANQAECgQICgAAAA==.Brewskie:BAAANQADCgEIAgAAAA==.Brodess:BAABNQAECoEiAAMKAAkKCCUJAgDYAwAKAAkKCCUJAgDYAwALAAEKTwsw4QAjAAAAAA==.Brody:BAAANQAFFAIIAgAAAA==.Bromorc:BAAANQADCgYJFwAAAA==.Broner:BAABNQAECoEYAAINAAcKdAzRIQB8AQANAAcKdAzRIQB8AQAAAA==.Bronlite:BAAANQADCgQIDQAAAA==.Brotherlee:BAABNQAECoEcAAIOAAkK1xMSSQAvAgAOAAkK1xMSSQAvAgAAAA==.',
Bu='Bubski:BAAANQAECgIIAgAAAA==.Bulimio:BAAANQADCgIIAgAAAA==.Bunz:BAAANQAECgEIAQAAAA==.Buratt:BAAANQADCgYJFwAAAA==.',
['Bé']='Béllâ:BAAANQADCggIAgAAAA==.',
['Bõ']='Bõggie:BAAANQAECgcJCgABNQAFFAYIDwAFAEcVAA==.',
Ca='Calabor:BAAANQADCggJDQAAAA==.Capacitør:BAAANQAECgUIDAAAAA==.Cardib:BAABNQAECoEgAAMPAAkKaB5sKwBzAgAPAAcKPh5sKwBzAgAQAAMKtRjcLwDjAAAAAA==.Carlîn:BAAANQADCgYIBgAAAA==.Cattamend:BAABNQAECoEXAAMCAAgKNBqaAwBVAgACAAcKRRuaAwBVAgABAAQKshenbAAkAQAAAA==.Cattawrath:BAAANQAECgYICgAAAA==.Cattazap:BAAANQAECgUIDQAAAA==.Cauliflawer:BAAANQAECgYJDwAAAA==.Cavoda:BAAANQADCgMIAwAAAA==.',
Ch='Chakrakhan:BAAANQAECgUJCAAAAA==.Char:BAAANQAECgEJAQAAAA==.Chase:BAAANQAECgMIBQAAAA==.Chinadh:BAACNQAFFIEMAAIIAAYKRRpTAQBCAgAIAAYKRRpTAQBCAgA1AAQKgR4AAggACQo3ImIHAD8DAAgACQo3ImIHAD8DAAAA.Chinahunter:BAAANQABCgYJCQABNQAFFAYIDAAIAEUaAA==.Chinamage:BAAANQAECgYIDAABNQAFFAYIDAAIAEUaAA==.Chopzuey:BAAANQADCgQICAAAAA==.Chugtiki:BAABNQAECoEbAAMKAAgKHBgRLgBVAgAKAAgKHBgRLgBVAgALAAEKSgu50wAzAAAAAA==.Chuunky:BAAANQABCgIIAgAAAA==.',
Ci='Cinderaz:BAAANQADCgYJFwAAAA==.',
Cl='Clikboomboom:BAAANQADCgUIBwAAAA==.',
Co='Cones:BAAANQADCgYICgABNQAECgQIBQAEAAAAAA==.Conesworth:BAAANQAECgcJEgAAAA==.Conesy:BAAANQAECgMIAwABNQAECgcJEgAEAAAAAA==.Coquina:BAAANQAECgIJAgAAAA==.Cordeilia:BAABNQAECoEnAAIBAAkKrRQIKQBcAgABAAkKrRQIKQBcAgAAAA==.Cordi:BAAANQABCgEIAQAAAA==.Corruptax:BAAANQADCgcIDgAAAA==.Costiigan:BAAANQADCgYIBgAAAA==.',
Cr='Critsaquino:BAAANQAECgcIDwAAAA==.Critsngigs:BAAANQAECgYICAAAAA==.Crotchsniffa:BAAANQAECgEIAQAAAA==.Crowlêy:BAAANQAECgEIAQABNQAECggIGgARAN4ZAA==.',
Cy='Cyberlust:BAAANQADCggICAAAAA==.Cyklar:BAAANQADCgYJFQAAAA==.',
Da='Daddydevito:BAABNQAECoEcAAISAAcKJAtgPwB7AQASAAcKJAtgPwB7AQAAAA==.Daddythyme:BAAANQAECgYJDwAAAA==.Dames:BAAANQADCgYIBgAAAA==.Damocies:BAAANQADCggJCAAAAA==.Danky:BAAANQAECgMJAwAAAA==.Daqueta:BAAANQAECgUIBQAAAA==.Daquetarg:BAAANQADCgQIBAAAAA==.Daquetawar:BAAANQAECgQIBAAAAA==.Darkniggura:BAAANQAECgMIAwAAAA==.Darknstormy:BAAANQADCgcIDQABNQADCgcJEQAEAAAAAA==.Darkpal:BAAANQAECggJEAAAAA==.Dazzi:BAAANQADCgYIEgAAAA==.',
De='Deathdaddy:BAAANQADCgYIGQAAAA==.Decapitation:BAAANQAECgYIDgAAAA==.Deepkingz:BAAANQADCggIDwAAAA==.Defacedd:BAAANQADCgYICgAAAA==.Deify:BAAANQAECgQIBwAAAA==.Deifyh:BAAANQADCgQIBQAAAA==.Deliaz:BAAANQADCgYJFwAAAA==.Destruction:BAAANQAECggJCAAAAA==.',
Di='Digitalhungr:BAAANQADCgYIBgABNQAECgcJEgAEAAAAAA==.Dismarryx:BAAANQAECgEIAgAAAA==.',
Dj='Djapana:BAAANQADCgYIDgABNQADCgcJEQAEAAAAAA==.',
Dk='Dkunt:BAAANQADCgQIBAAAAA==.',
Dn='Dnomm:BAAANQADCgYJFwAAAA==.',
Do='Dogmuffin:BAAANQADCgMIAwAAAA==.Doristhedull:BAAANQADCgIJAgAAAA==.',
Dr='Drakyon:BAAANQAECgIIAwAAAA==.Dreaddlord:BAAANQAECgEIAQABNQAECgQIDQAEAAAAAA==.Dreadiedude:BAAANQAECgUJCwAAAA==.Drowlie:BAAANQADCgYIBgABNQAECgUJBgAEAAAAAA==.',
Du='Durrin:BAAANQAECgQIBgAAAA==.Dutchman:BAAANQAECgQJBQAAAA==.',
Ef='Effectus:BAABNQAECoEWAAQPAAcKeg/iXwCpAQAPAAcKeg/iXwCpAQAQAAIKtQTwWABOAAATAAEKNwcpIwA0AAAAAA==.',
Ei='Eith:BAAANQAECgQIBQAAAA==.',
El='Elele:BAAANQABCgUJBQAAAA==.Eljay:BAAANQAECgYJDwAAAA==.Ellell:BAABNQAECoEnAAIKAAYK9QnceQAoAQAKAAYK9QnceQAoAQAAAA==.Elliemental:BAAANQABCgcJDAAAAA==.',
Em='Emberly:BAAANQADCgEIAQAAAA==.Emsulquiorra:BAAANQAECgIIAQAAAA==.',
En='Endersfault:BAABNQAECoEeAAIHAAgK8x2GBQCoAgAHAAgK8x2GBQCoAgAAAA==.',
Ep='Epicdemoness:BAABNQAECoEYAAIIAAgKOBcgFQB0AgAIAAgKOBcgFQB0AgAAAA==.',
Er='Eroni:BAAANQAECgUJCQAAAA==.',
Eu='Euphea:BAAANQADCgYJDQAAAA==.',
Ev='Evaelfie:BAABNQAECoEdAAMUAAkKcQvNIgDgAQAUAAkKcQvNIgDgAQAFAAMKagTYdwCHAAAAAA==.',
Fa='Fanks:BAAANQADCgEIAQABNQABCgQIBAAEAAAAAA==.Farrand:BAAANQADCgQIBAAAAA==.',
Fe='Fearology:BAAANQADCgMIAwAAAA==.Felcollins:BAAANQADCgYJDQAAAA==.Felicia:BAAANQAECgcJEgAAAA==.Fellordkiki:BAABNQAECoEaAAQQAAgKtg00MADhAAAPAAYKeAvakQATAQAQAAQK+Ao0MADhAAATAAMKBQZaFgBuAAAAAA==.',
Fi='Filthydh:BAAANQADCgYIBgABNQAECgkJHgAOAPMjAA==.Filthypally:BAABNQAECoEeAAIOAAkK8yORCQCLAwAOAAkK8yORCQCLAwAAAA==.Fivëam:BAAANQABCgIJAgAAAA==.',
Fl='Flashheart:BAAANQAECgMIBQAAAA==.Fleabag:BAAANQADCgYJEwAAAA==.',
Fo='Fossgate:BAAANQAECggJCQABNQAECggJFQAFAJsCAA==.Foxe:BAEANQADCgMIAwABNQAECgQICgAEAAAAAA==.',
Fr='Freezefauker:BAAANQAECgUJCwAAAA==.Fridge:BAAANQAECgYIDQAAAA==.Frostxfury:BAAANQAECgIIAgAAAA==.Frøstynips:BAACNQAFFIEYAAMUAAYKZBesAQCuAQAUAAUKahWsAQCuAQAVAAEKSSFhFgBfAAA1AAQKgTsAAxQACQq6JZACAKQDABQACQpNJZACAKQDAAUACQpQJPALACoDAAAA.',
Fu='Furysdeath:BAAANQAECgcIBwAAAA==.Furysgrip:BAABNQAECoEaAAIVAAgKwg0pPgCVAQAVAAgKwg0pPgCVAQAAAA==.',
['Fì']='Fìsty:BAAANQADCgYIBgAAAA==.',
Ga='Gabagool:BAAANQAECgUICgABNQABCgEJAQAEAAAAAA==.Gaidal:BAAANQAECgQICwAAAA==.Galafrey:BAAANQAECgQIBQABNQAECggIGAARAO4bAA==.Garaktou:BAAANQADCgQICAAAAA==.Gashweaver:BAAANQADCgMJAwAAAA==.',
Ge='Gekyum:BAABNQAECoEkAAIMAAkKByMYBAB4AwAMAAkKByMYBAB4AwAAAA==.Getinmyspit:BAAANQAECgQIBQAAAA==.',
Gh='Ghazgkhull:BAAANQADCgYIBgAAAA==.',
Gi='Gidyana:BAAANQAECgMIAwAAAA==.Girlsdayoni:BAAANQAECgQICAAAAA==.Girlsnight:BAAANQADCgQIBwAAAA==.',
Gl='Glancelot:BAAANQAECgUIDQAAAA==.Glipglorp:BAAANQADCgQIBAAAAA==.',
Gn='Gnuh:BAAANQADCggICAABNQAECgUIDQAEAAAAAA==.Gnurse:BAAANQAECgIJAgAAAA==.',
Go='Gommo:BAAANQAECgYIDwAAAA==.Goodgirl:BAAANQAECgMIAwAAAA==.Gorbad:BAAANQAECgEJAQAAAA==.',
Gr='Greggoryy:BAAANQABCgQICQAAAA==.Groundizzle:BAAANQAECgcIDwAAAA==.',
Gt='Gtoromu:BAAANQADCggJFAAAAA==.',
Gu='Guanyu:BAAANQAECgUIBgAAAA==.Guccisosa:BAAANQADCgYIBgAAAA==.Guccisweet:BAAANQADCgcIBwAAAA==.Guineamon:BAAANQADCggJCQAAAA==.',
Ha='Haruk:BAABNQAECoEbAAIWAAgK8R+wEgD2AgAWAAgK8R+wEgD2AgAAAA==.',
He='Heatfist:BAAANQAECgUICQAAAA==.Helldridge:BAAANQAECgEIAgAAAA==.Heåls:BAAANQAECgUJCwAAAA==.',
Ho='Hoelishock:BAAANQAECgYJBwAAAA==.Hollynova:BAAANQAECgEIAQAAAA==.Holychad:BAABNQAECoEeAAMOAAgKxRZVSgAqAgAOAAgKxRZVSgAqAgAWAAgKzRGNPAAFAgAAAA==.Honeydew:BAACNQAFFIEPAAMNAAUK9BVrBAA8AQANAAQKuxJrBAA8AQAXAAEK8RVbBgBbAAA1AAQKgS4AAg0ACQoLIecGACcDAA0ACQoLIecGACcDAAAA.Honganteresa:BAAANQAECgYICgAAAA==.Hoofmax:BAAANQADCgYICAAAAA==.Hotteemie:BAAANQADCgYIDAAAAA==.',
['Hø']='Høtdøts:BAAANQAECgEIAQAAAA==.',
If='Ifrit:BAAANQAECgIIAwABNQAECgkJIQAWADQjAA==.',
Il='Illidank:BAAANQAECgUIEAAAAA==.',
Im='Imanoob:BAAANQADCgUJBQAAAA==.Imperiex:BAAANQADCgEIAQAAAA==.',
In='Infectedlock:BAAANQAECgYJBgABNQAFFAYIDAAIAEUaAA==.Inurdreams:BAAANQABCgcICAAAAA==.',
Io='Ionsw:BAABNQAECoEbAAMPAAgKXxbFSgD0AQAPAAcKvRbFSgD0AQAQAAUKBQy8JwATAQAAAA==.',
Ip='Ipsifu:BAAANQAECgYICAAAAA==.',
Ir='Ironski:BAAANQAECgIIAgAAAA==.',
Ja='Jackillz:BAAANQADCgUIBQABNQAECgcJEAAEAAAAAA==.Jatzsy:BAAANQAECgMIBQAAAA==.Jayar:BAAANQAECgQIBwAAAA==.Jazzy:BAAANQADCgUIBQAAAA==.',
Je='Jee:BAAANQAECgQJCQAAAA==.Jenkem:BAAANQABCgQJBAAAAA==.Jescon:BAAANQAECgIIAgAAAA==.Jeé:BAAANQADCgUJBQAAAA==.',
Ji='Jiamil:BAAANQAECgUJEQAAAA==.Jigolow:BAAANQADCgUIBQAAAA==.',
Jo='Johlissa:BAAANQAECgIIAgAAAA==.',
Ju='Jubber:BAAANQAECgYIDQAAAA==.',
Ka='Kadashy:BAAANQAECgYICQAAAA==.Kadashyy:BAAANQAECgIIAwABNQAECgYICQAEAAAAAA==.Kaherd:BAAANQAECgEIAgAAAA==.Kakapooeybum:BAAANQADCgQIBAAAAA==.Kakashimaya:BAAANQADCgIIBAAAAA==.Kamikasi:BAAANQADCggICwAAAA==.Kaneshiro:BAAANQAECgYIDwAAAA==.Karytheca:BAAANQADCgYIBAAAAA==.Katae:BAAANQAECgYJEAAAAA==.Kayrali:BAAANQADCgIIAgAAAA==.',
Kb='Kboomz:BAAANQADCgYJDAABNQADCgcJEQAEAAAAAA==.',
Ke='Kegaz:BAAANQAECgMIAwAAAA==.Kegward:BAAANQADCgUIBQAAAA==.Kelynada:BAABNQAECoEWAAIPAAYKdBD1bgB2AQAPAAYKdBD1bgB2AQAAAA==.Kendd:BAACNQAFFIEQAAMYAAYK0BcmAQA7AgAYAAYK0BcmAQA7AgAZAAEKNgknDwBSAAA1AAQKgSUABBgACQqWISMDAF4DABgACQpxHyMDAF4DABoABwpCEKEJAJ0BABkAAgpeF21MAJcAAAAA.Kerrigân:BAAANQAECgIIAgAAAA==.Keyshock:BAAANQADCgYJBgAAAA==.',
Ki='Kindra:BAAANQADCgYIBgAAAA==.Kithari:BAAANQAECgUJCwAAAA==.',
Kn='Knickerbits:BAAANQABCgEIAQAAAA==.Knotting:BAAANQADCggJFgAAAA==.',
Ko='Kochez:BAAANQADCgUICQAAAA==.Kollateral:BAAANQAECgQJBAAAAA==.',
Kr='Krankiekunt:BAABNQAECoEiAAIbAAkKjSA/AwAgAwAbAAkKjSA/AwAgAwAAAA==.Krellhim:BAAANQAECgIIAQAAAA==.',
Ku='Kuanija:BAABNQAECoEZAAMJAAgKmhrcCQB8AgAJAAgKmxncCQB8AgAKAAUKUhHNcgA8AQAAAA==.Kuuga:BAAANQAECgYICgAAAA==.',
La='Landwalker:BAABNQAECoEZAAIcAAkK2B1yBwD/AgAcAAkK2B1yBwD/AgAAAA==.Langas:BAAANQAECgIIAQABNQAECggIBgAEAAAAAA==.Langasbrew:BAAANQAECggIBgAAAA==.Latorius:BAAANQAECgYJEAAAAA==.Lavaloadz:BAAANQADCggIDQAAAA==.Lazziel:BAAANQADCgcIDQAAAA==.',
Le='Lexavis:BAACNQAFFIEIAAMWAAQKMxHbCgD0AAAWAAMKkArbCgD0AAAOAAIKNRm0DgCdAAA1AAQKgSgAAw4ACQpXIpcbAAUDAA4ACQpXIpcbAAUDABYABwoVIvYbALMCAAE1AAQKCAkiAB0AeAgA.Leyiast:BAAANQAECgUICwAAAA==.Leyissa:BAAANQADCgIIAgABNQAECgUICwAEAAAAAA==.',
Lh='Lheo:BAAANQADCgYICAAAAA==.',
Li='Liggma:BAAANQAECgQICAAAAA==.Lightborn:BAAANQADCggICAAAAA==.Lilwhite:BAAANQAECgcIEQABNQAECgEIAQAEAAAAAA==.Liminal:BAAANQADCgcJBwAAAA==.',
Lo='Lockaboom:BAAANQAECgUICQAAAA==.Loldruid:BAAANQAECgQIDQAAAA==.Lom:BAAANQAECgcJEAAAAA==.Lomzz:BAAANQADCgIJAgAAAA==.',
Lu='Lukie:BAEANQAECgIIAgAAAA==.',
Ly='Lycan:BAAANQADCgEIAQAAAA==.Lym:BAAANQAECgUIBQAAAA==.Lynarium:BAAANQAECgEJAQAAAA==.Lyradaeris:BAAANQADCgUJBQAAAA==.',
['Lÿ']='Lÿrath:BAAANQADCggIEQAAAA==.',
Ma='Magepill:BAAANQADCgQIBAAAAA==.Magharitta:BAAANQAECgUIEAAAAA==.Magroth:BAAANQAECgYJCwAAAA==.Mahwae:BAAANQADCgIIAwAAAA==.Makavelli:BAAANQADCgIIAgAAAA==.Manoliso:BAAANQAECgUICAAAAA==.Marmite:BAAANQAECgcJBwAAAA==.',
Me='Medesin:BAAANQADCgYJFwAAAA==.Mekhanite:BAAANQAECgUJCQAAAA==.Mercykill:BAAANQADCgUJBQAAAA==.',
Mi='Milfdella:BAAANQAECgIIAQAAAA==.Milspec:BAAANQAECgYJEgAAAA==.Minami:BAAANQAECgUJCwAAAA==.Minhiriath:BAAANQADCgQIBAAAAA==.Mintbadger:BAAANQADCgUIBwAAAA==.Mistea:BAAANQADCgMJAwAAAA==.Misticuffs:BAAANQADCgYIBgABNQABCgEJAQAEAAAAAA==.',
Mo='Mochimask:BAAANQADCgIIAgAAAA==.Moetown:BAAANQADCggICAABNQAFFAIIBgAdAAkZAA==.Moistex:BAAANQADCgUIBQABNQAECggIGQAHAPcZAA==.Moistmaker:BAABNQAECoEnAAILAAgK5iMJDQAiAwALAAgK5iMJDQAiAwAAAA==.Mold:BAAANQAECgMIAwAAAA==.Momotaku:BAAANQAECgcJDwAAAA==.Monalisa:BAAANQAECgUJCAAAAA==.Monkmon:BAAANQADCgIIAgABNQAECgQIBwAEAAAAAA==.Moonoo:BAAANQADCgUIBQAAAA==.Mordok:BAAANQAECgEIAQAAAA==.Morena:BAAANQADCgcIEgAAAA==.Morgaina:BAAANQADCgcIDQAAAA==.',
Mu='Muffinman:BAAANQAECggJBgABNQAECggIBgAEAAAAAA==.Muscleclub:BAABNQAECoEXAAIXAAgKCBsvCQChAgAXAAgKCBsvCQChAgAAAA==.',
My='Mysticalzz:BAAANQAECgIJAgAAAA==.',
['Më']='Mëmëmë:BAAANQAECgEJAQAAAA==.',
['Mü']='Müddrätt:BAAANQAECgEIAQAAAA==.',
Na='Naeff:BAAANQAECgUIAQAAAA==.Natria:BAAANQAECgYJDQAAAA==.Naya:BAABNQAECoEaAAIdAAgK8ySuGQBRAwAdAAgK8ySuGQBRAwAAAA==.',
Ne='Nerfdehoof:BAAANQADCggICQAAAA==.Nerfdelag:BAAANQAECgYJDQAAAA==.Nerfgün:BAABNQAECoEYAAIRAAgK7hvMKgCJAgARAAgK7hvMKgCJAgAAAA==.Nescåfe:BAAANQADCgYJBgAAAA==.',
Ni='Nicodautroc:BAAANQAECgQIBwABNQAECgQJCAAEAAAAAA==.Nintone:BAAANQAECgUJCwAAAA==.',
No='Nonippies:BAAANQAECgMJBwAAAA==.Noolie:BAAANQADCgIIAgABNQAECgUJBgAEAAAAAA==.',
Ns='Nsi:BAAANQADCgUJCAAAAA==.',
Nu='Nubishe:BAAANQAECgMIAwAAAA==.Nutsdormu:BAAANQAECgQIEQAAAA==.',
Ny='Nythe:BAAANQADCgEIAQABNQADCgIIAgAEAAAAAA==.Nyxmoona:BAAANQADCgYJFwAAAA==.',
['Nà']='Nàishà:BAAANQAECgMJAwAAAA==.',
Ob='Obskurer:BAAANQAECggIEAAAAA==.',
Od='Odinwolf:BAAANQAECgMIBQABNQAECgkJIQAWADQjAA==.',
Oj='Ojisancage:BAABNQAECoEoAAIPAAgKlxrQJgCJAgAPAAgKlxrQJgCJAgAAAA==.',
Om='Omegaflaps:BAAANQAECgYJBgAAAA==.Omnitract:BAAANQADCgUIBQAAAA==.',
On='Onceagain:BAAANQAECgEIAQAAAA==.',
Or='Orinys:BAAANQAECgQICgAAAA==.Orkky:BAAANQAECgcJEgAAAA==.',
Pa='Page:BAABNQAECoEYAAMYAAkKdQ5nFAANAgAYAAgK9g5nFAANAgAZAAEKZwpZXwA5AAAAAA==.Pakurruun:BAAANQAECgQJCgAAAA==.Palahan:BAAANQADCgYJBwAAAA==.Palala:BAAANQADCgcIBwABNQAECgUICwAEAAAAAA==.Pallatress:BAAANQADCgYJFwAAAA==.Pandor:BAAANQAECgEIAQAAAA==.Panginoon:BAABNQAECoEXAAMUAAkKUx2bDwC0AgAUAAkKFhmbDwC0AgAFAAgKVR1zHACDAgAAAA==.Paparìch:BAABNQAECoEdAAISAAkKgh8CDwAaAwASAAkKgh8CDwAaAwAAAA==.Paphio:BAAANQADCggJDAAAAA==.',
Pe='Perden:BAAANQADCgYIBgAAAA==.Pesh:BAAANQADCgYIDQAAAA==.',
Pg='Pgundry:BAAANQADCggJFwAAAA==.',
Ph='Phakin:BAAANQADCgMIAwAAAA==.Phex:BAAANQAECgMJAwAAAA==.',
Pi='Piddlesworth:BAAANQADCggIFwAAAA==.Piergeiron:BAAANQAECgYIBAAAAA==.Pinkyblue:BAABNQAECoEYAAMPAAkKWx1QLgBnAgAPAAgKJx1QLgBnAgAQAAEK9x6wWABPAAAAAA==.Pipssqeek:BAAANQADCgcJFQAAAA==.',
Pj='Pjw:BAABNQAECoEgAAIWAAkKlRahIQCPAgAWAAkKlRahIQCPAgAAAA==.',
Pl='Plarrior:BAAANQADCgMIAwAAAA==.Plip:BAABNQAECoEwAAQKAAgKvBuBIwCXAgAKAAgKvBuBIwCXAgAJAAIK7AuQIACGAAALAAEKjgMf5gAbAAAAAA==.',
Po='Pokerrface:BAAANQADCggICAABNQAECgIJAgAEAAAAAA==.Polloloco:BAAANQADCgEIAQAAAA==.Poobumhead:BAAANQAECgQICgAAAA==.Porkroll:BAAANQADCgIIAgAAAA==.Poweredman:BAAANQADCgIIAgAAAA==.Powerheal:BAAANQAECgUIBQAAAA==.',
Pr='Praetoar:BAAANQADCgYJBgAAAA==.Prftlybalncd:BAABNQAECoEXAAIeAAcKIxWkFgDkAQAeAAcKIxWkFgDkAQABNQAECgkJIAAWAJUWAA==.Probabele:BAAANQAECgEIAQAAAA==.Probably:BAACNQAFFIEWAAMUAAUKEhrvAgBmAQAUAAQKcxzvAgBmAQAVAAEKkBBhHQAyAAA1AAQKgT4ABBQACQr7I18DAIsDABQACQr7I18DAIsDABUAAQr/HAGMAFEAAAUAAQrnEziJAEYAAAAA.Protato:BAAANQADCggJCAAAAA==.',
Ps='Psyche:BAAANQADCgcIDAAAAA==.',
Pt='Ptrie:BAAANQAECgcIDQAAAA==.',
Pu='Pudgeyp:BAABNQAECoEYAAIfAAkKUxfEOQB/AgAfAAkKUxfEOQB/AgAAAA==.Pudgeyr:BAAANQAECgYIAgAAAA==.Punj:BAAANQAECgIIAwAAAA==.Puntarr:BAAANQADCgYIGQAAAA==.Puppybonks:BAAANQAECgIIAgAAAA==.Purdxpriest:BAAANQABCggICAABNQADCggJDwAEAAAAAA==.Purdxwarrior:BAAANQABCgQIBQABNQADCggJDwAEAAAAAA==.',
Pw='Pwrbottom:BAAANQAECgQIAwAAAA==.',
Qi='Qibla:BAAANQAECgcJEgAAAA==.',
Qu='Quarizma:BAACNQAFFIELAAIMAAUKaiJjAgAFAgAMAAUKaiJjAgAFAgA1AAQKgSoAAgwACQq7JBwCAK0DAAwACQq7JBwCAK0DAAAA.',
Ra='Radiantbunz:BAAANQADCggIGgAAAA==.Rankone:BAAANQAECgMIAwABNQAECgQIBgAEAAAAAA==.Raxe:BAEANQAECgQICgAAAA==.',
Re='Reaperoffire:BAAANQAECgEIAQAAAA==.Repliod:BAAANQAECgUIDQAAAA==.Reploid:BAAANQADCgcIBwABNQAECgUIDQAEAAAAAA==.Restho:BAAANQAECgUIEQAAAA==.Revarix:BAAANQAECgYJDQAAAA==.',
Rh='Rhaella:BAAANQAECgUJCwAAAA==.Rhuiser:BAABNQAECoEYAAIfAAgKlSLFJADgAgAfAAgKlSLFJADgAgAAAA==.Rhuno:BAAANQAECgQJCAAAAA==.',
Ri='Rigormortits:BAAANQADCgcJBwABNQAECgUIEAAEAAAAAA==.Ritsuki:BAAANQAECgUIBwAAAA==.Ritéboys:BAAANQAECggICwAAAA==.Ritëboys:BAAANQAECgcIEwABNQAECggICwAEAAAAAA==.',
Ro='Rocketjuice:BAABNQAECoEkAAIdAAgKuxb6ZgBbAgAdAAgKuxb6ZgBbAgAAAA==.Roflpwnnt:BAAANQAECgEJAQAAAA==.Ronjames:BAAANQADCgMIAwAAAA==.Rothy:BAAANQAECgUIBQAAAA==.',
Ru='Rutee:BAABNQAECoEaAAIOAAgKKxQfUAAVAgAOAAgKKxQfUAAVAgAAAA==.',
Ry='Ryz:BAAANQAECgEJAQABNQAECgYICwAEAAAAAA==.',
Sa='Saethene:BAAANQAECgEIAQABNQAECggIGAARAO4bAA==.Safh:BAAANQADCggICQAAAA==.Safk:BAABNQAECoEYAAIVAAgKGBNuLwDpAQAVAAgKGBNuLwDpAQAAAA==.Saleina:BAAANQADCgIIAwAAAA==.Sandiwang:BAAANQADCgIIAgAAAA==.Sanosanz:BAAANQAECgIJAwAAAA==.Saptko:BAAANQADCgUIBQAAAA==.Sartoc:BAAANQAECgMIBAABNQAECggIGAARAO4bAA==.',
Sc='Scabbo:BAAANQAECgQIBQAAAA==.Scalesoul:BAAANQAECgcIGAAAAQ==.',
Sd='Sdfgoose:BAAANQAECgMJBAAAAA==.',
Se='Seiferoth:BAABNQAECoEhAAIWAAkKNCOdBACLAwAWAAkKNCOdBACLAwAAAA==.Selitha:BAAANQABCgIIAgAAAA==.Senddori:BAAANQADCgUIBQAAAA==.Sergantcolen:BAAANQAECgUIBgAAAA==.Señornanna:BAAANQADCgQIBAAAAA==.',
Sh='Shaddai:BAAANQAECgQICAAAAA==.Shadowofevil:BAAANQAECgUJCgAAAA==.Shadypally:BAAANQADCgUJBQAAAA==.Shakywing:BAAANQADCgIIAgAAAA==.Shalavoo:BAAANQAECgIIAgAAAA==.Shamankiller:BAAANQAECgMICAAAAA==.Shamazzle:BAAANQAECgUICQAAAA==.Shamlen:BAABNQAECoEdAAIKAAcKxQNHeQApAQAKAAcKxQNHeQApAQAAAA==.Sharkyob:BAAANQAECgQJBAAAAA==.Shichokeme:BAAANQADCgMIAwAAAA==.Shiicho:BAAANQADCgYICQAAAA==.Shinieedruid:BAAANQAECgcJEgAAAA==.Shions:BAAANQADCgYIBgAAAA==.Shockostoob:BAAANQAECgUICwAAAA==.',
Si='Sidatas:BAAANQADCggICwAAAA==.Silverspulse:BAABNQAECoEjAAIBAAcKjyCnHACkAgABAAcKjyCnHACkAgAAAA==.Sinequanon:BAABNQAECoEfAAMBAAgKxBWKOQAGAgABAAgKxBWKOQAGAgADAAYKvhiuIAC4AQAAAA==.Sinfulbeast:BAABNQAECoEaAAIRAAgK3hlULQB+AgARAAgK3hlULQB+AgAAAA==.Sippycup:BAAANQAECgEIAQABNQAECggIEgAEAAAAAA==.',
Sk='Skrogan:BAAANQABCgQICAAAAA==.Skulv:BAACNQAFFIEGAAIIAAQKgxE4BQBSAQAIAAQKgxE4BQBSAQA1AAQKgSUAAwgACQoFIjQEAH8DAAgACQoCIjQEAH8DACAAAgpyFTZRAI4AAAAA.',
Sl='Slakzor:BAAANQADCgQIAwAAAA==.Slammed:BAAANQAECgQIBwAAAA==.Sleepyshark:BAAANQAECgcJEAAAAA==.Slopain:BAAANQAECgYIDQAAAA==.Slåppery:BAABNQAECoEeAAIMAAkKGB8tBgBLAwAMAAkKGB8tBgBLAwAAAA==.',
Sm='Smashy:BAAANQADCggIGQAAAA==.Smìtty:BAAANQADCgMIBAAAAA==.',
Sn='Snorlax:BAAANQAECgYIEQAAAA==.Snort:BAAANQAECgUIDAAAAA==.',
So='Sona:BAAANQAECgYIBgAAAA==.Sonotafurry:BAAANQAECgIIAgAAAA==.Soresu:BAAANQAECgQJBQAAAA==.Soundwit:BAABNQAECoEZAAIZAAcKmR91DwCYAgAZAAcKmR91DwCYAgAAAA==.',
Sp='Sparrowstalk:BAAANQADCgEIAQAAAA==.Spindrift:BAAANQAECgYIDAAAAA==.Spoonyy:BAACNQAFFIEGAAMdAAQKMRyxFQAUAQAdAAMK/RuxFQAUAQAhAAEKzRxSBQBcAAA1AAQKgR8AAx0ACQoBItU0AO8CAB0ACQpaIdU0AO8CACEAAgpvJdgVANoAAAAA.',
Sq='Squanchie:BAAANQAECgEIAQABNQAECgYJEAAEAAAAAA==.',
St='Starstorm:BAAANQADCgYJBgAAAA==.Steinlarger:BAAANQAECgUJBQAAAA==.Stephen:BAAANQAECgYJCgAAAA==.Storrmbender:BAAANQAECgYJDgAAAA==.Stoutbrew:BAAANQADCggICQAAAA==.Strípe:BAAANQAECgUJBwAAAA==.Stuy:BAABNQAECoEeAAIMAAgKcxJiGwAcAgAMAAgKcxJiGwAcAgAAAA==.Stãria:BAAANQAECgUJCQAAAA==.Störme:BAAANQADCgYJDgAAAA==.',
Su='Sugarburst:BAAANQAECgIJAwAAAA==.Sukmahdisc:BAAANQADCggICAAAAA==.',
Sw='Swak:BAABNQAECoErAAIRAAgK0RTROwBHAgARAAgK0RTROwBHAgAAAA==.Sweet:BAAANQAECgMIAQAAAA==.Switchmage:BAAANQADCggJEAAAAA==.Switchskin:BAABNQAECoEeAAISAAkKkB24DwATAwASAAkKkB24DwATAwAAAA==.',
Sy='Syvrogue:BAABNQAECoEWAAIYAAgK6Qn8FwDjAQAYAAgK6Qn8FwDjAQABNQAECgEIAQAEAAAAAA==.',
Ta='Tallinor:BAAANQAECgQICgAAAA==.Tanags:BAAANQAECgUJCwAAAA==.Tankakus:BAAANQAECgEIAQAAAA==.Taumast:BAAANQADCgMIAwABNQAECgcIDwAEAAAAAA==.Tauter:BAAANQADCgYJFAAAAA==.Tazzee:BAAANQADCgYIDAAAAA==.',
Te='Temperature:BAAANQAECgIIAwABNQAECgMJBgAEAAAAAA==.Testaxltesta:BAAANQAECgYIDQABNQADCggIDgAEAAAAAA==.',
Th='Thael:BAAANQADCgQIBAAAAA==.Thalia:BAAANQAECgYIEQAAAA==.Thoriatit:BAAANQAECgUICAAAAA==.Thottydot:BAAANQAECgEIAQAAAA==.Thox:BAAANQADCgIIAgAAAA==.Throber:BAAANQADCgUJBQAAAA==.Thyranux:BAAANQADCgMIBAAAAA==.',
Ti='Tienchi:BAAANQAECgYJEQAAAA==.Tierk:BAAANQADCggICAABNQAECgkJGAAYAHUOAA==.Tim:BAAANQAECgcJEgAAAA==.Timmyy:BAAANQAECgEIAQAAAA==.',
Tl='Tlo:BAAANQADCgcIBwABNQAFFAQJCQARAMIdAA==.',
To='Tollmemaybe:BAABNQAECoEyAAMiAAgKhSFOBgD6AgAiAAgKhSFOBgD6AgAOAAEK9AiKJgExAAAAAA==.Tormént:BAABNQAECoEbAAIUAAgKmyCCDgDEAgAUAAgKmyCCDgDEAgAAAA==.',
Tr='Transport:BAAANQAECgMJBgAAAA==.Traumatizer:BAAANQADCggJDQAAAA==.Trenbolone:BAAANQADCgIIAwAAAA==.Tronix:BAAANQAECgUICAAAAA==.Trucidario:BAAANQAECgIIAgAAAA==.Truwar:BAABNQAECoEXAAIfAAkKcRuOQgBdAgAfAAkKcRuOQgBdAgAAAA==.',
Tu='Tubbquake:BAAANQAECgcIDwAAAA==.Tufflock:BAAANQADCgEJAQAAAA==.',
Tw='Twatasaurus:BAAANQAECgIJAgAAAA==.',
['Tî']='Tîmmeh:BAAANQAECgYIDAABNQAECgEIAQAEAAAAAA==.',
Ub='Ubica:BAABNQAECoEZAAMZAAgKbAo7HwDmAQAZAAgKTgo7HwDmAQAYAAQK1ASvMQDDAAAAAA==.',
Un='Unholykníght:BAAANQADCgEIAQAAAA==.Unvoid:BAAANQAECgIICAAAAA==.',
Ur='Urzog:BAAANQADCgUIBQAAAA==.',
Us='Useacooldown:BAAANQAECgQIBQAAAA==.',
Va='Valaya:BAAANQAECgIJAwAAAA==.Valentine:BAAANQAECgcIDgAAAA==.Valithor:BAAANQAECgIIAwAAAA==.Valkyrion:BAACNQAFFIEFAAIeAAMKpw37CADwAAAeAAMKpw37CADwAAA1AAQKgSEAAh4ACQp2IaoDAFgDAB4ACQp2IaoDAFgDAAAA.Valysan:BAAANQADCgEIAQAAAA==.Vann:BAAANQADCggICQAAAA==.',
Ve='Velathri:BAAANQAECgQJBQAAAA==.Velenlerolan:BAABNQAECoElAAIFAAkKbCVJAgDJAwAFAAkKbCVJAgDJAwAAAA==.Velrayne:BAAANQAECgcJEgAAAA==.Veng:BAAANQABCgQIBAAAAA==.Verailde:BAAANQADCgUICQAAAA==.Verathriel:BAAANQABCgQIBgAAAA==.Verilence:BAABNQAECoEWAAQPAAcKZCCcNgBDAgAPAAYKqiCcNgBDAgATAAUKJByMCAB8AQAQAAEK1h1dVwBTAAAAAA==.Veventhius:BAAANQADCgIIAgAAAA==.Vext:BAAANQADCgMIAwAAAA==.',
Vi='Vindicor:BAAANQADCgQJCAAAAA==.',
Vo='Voidberg:BAAANQAECgQIBAABNQAECgkJHwAcAGsdAA==.Vorndryad:BAAANQAECgEJAgAAAA==.',
Vy='Vynburn:BAABNQAECoEaAAIdAAgKORc0awBQAgAdAAgKORc0awBQAgAAAA==.',
Wa='Warmon:BAAANQADCggIEQAAAA==.Watson:BAAANQAECgYJCwAAAA==.Waveryy:BAAANQADCgMIBgAAAA==.',
We='Wemblitz:BAAANQADCgYJEQAAAA==.Wesh:BAABNQAECoEfAAMFAAgKERvfHgBtAgAFAAgKARvfHgBtAgAVAAYKExAvTQBKAQAAAA==.',
Wh='Whio:BAAANQAECgYIDQAAAA==.Whitetabby:BAAANQAECgUJBwAAAA==.Whtclass:BAAANQAECgMIAwAAAA==.',
Wi='Wintersfence:BAAANQADCgYJCAAAAA==.',
Wk='Wkwk:BAAANQAECgQICAAAAA==.',
Wo='Wozxx:BAAANQAECgEJAQAAAA==.',
Wp='Wpd:BAABNQAECoEiAAISAAkKKCDECQBYAwASAAkKKCDECQBYAwAAAA==.',
['Wî']='Wîngman:BAAANQAECgcJEwAAAA==.',
Xe='Xenarn:BAEANQAECgQICgAAAA==.Xenoruin:BAAANQAECgUJCwAAAA==.',
Xi='Xiphios:BAAANQADCgYIBgAAAA==.',
Ya='Yarpidk:BAAANQADCgcJCQAAAA==.',
Ye='Yejin:BAAANQADCggJCAAAAA==.',
Yo='Yorkie:BAABNQAECoElAAIdAAkKAR7JIwApAwAdAAkKAR7JIwApAwAAAA==.Yoyogi:BAAANQADCgYIBwAAAA==.',
Yu='Yui:BAAANQADCggICAAAAA==.Yurarzir:BAABNQAECoEaAAIdAAgKzRCEegAmAgAdAAgKzRCEegAmAgAAAA==.',
Za='Zanisha:BAAANQAECgEIAgAAAA==.Zaz:BAAANQADCgYIBwAAAA==.',
Ze='Zelendorm:BAAANQAECgYIEQAAAA==.',
Zu='Zula:BAAANQADCgcIBwABNQAECgQIBgAEAAAAAA==.',
['Ås']='Åshz:BAAANQADCgIIAgABNQAECgUJCwAEAAAAAA==.',
['ßa']='ßaccycønes:BAAANQADCggIGwAAAA==.',
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
