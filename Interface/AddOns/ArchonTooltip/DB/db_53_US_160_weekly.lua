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

local lookup = {'Shaman-Restoration','Druid-Restoration','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Druid-Balance','Warrior-Arms','Shaman-Enhancement','Unknown-Unknown','Shaman-Elemental','Warlock-Demonology','DemonHunter-Devourer','Paladin-Protection','Priest-Shadow','Priest-Holy','Priest-Discipline','Warlock-Destruction','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Evoker-Augmentation','Monk-Brewmaster','Druid-Feral','Mage-Arcane','Mage-Frost','Monk-Mistweaver','Warrior-Protection','Hunter-Survival','DemonHunter-Havoc','Warrior-Fury','Monk-Windwalker','DemonHunter-Vengeance','Mage-Fire',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adjust:BAABNQAECn8WAAIBAAcKlx1aQABcAgABAAcKlx1aQABcAgABNQAFFAcIGAACAGkZAA==.Admirlakbar:BAAANQADCgIIAgAAAA==.',
Ae='Aedrenis:BAAANQADCgUIDgAAAA==.Aegrisomnia:BAAANQABCgMIAwABNQAECgkJKgABAIYgAA==.Aejra:BAAANQAECgQIBAABNQAECgkJKgABAIYgAA==.Aenstus:BAAANQADCgMJAwAAAA==.Aeropunk:BAAANQADCgIJAgAAAA==.Aerys:BAAANQAECgcIEwAAAA==.Aerøs:BAAANQAECgcIEQAAAA==.',
Ag='Aggiz:BAAANQAECgUICQABNQAECgkJKgADABMeAA==.',
Aj='Ajaxprime:BAABNQAECn8lAAMEAAgKMSZTFwAAAwAEAAgKMSZTFwAAAwAFAAEK6wjTrQAvAAAAAA==.',
Ak='Akiojonës:BAAANQADCgYIBgAAAA==.',
Al='Alfabika:BAAANQAECgYICAAAAA==.Alzim:BAAANQAECgcIEgAAAA==.',
Am='Amoriara:BAAANQADCgUIEQAAAA==.',
An='Angry:BAAANQAECgYIDQAAAA==.Ankelbiter:BAABNQAECn8ZAAMGAAkKDhs1GgCnAgAGAAgKthw1GgCnAgAHAAIKIBF3RACNAAAAAA==.Anûbis:BAABNQAECn8XAAIIAAcK+AqfawBCAQAIAAcK+AqfawBCAQAAAA==.',
Ar='Aragos:BAAANQAECgYIDAAAAA==.Arcelon:BAAANQAECgEIAgAAAA==.Arwenatak:BAABNQAECn8rAAMJAAkKXx3wLwAHAwAJAAkKXx3wLwAHAwAKAAQK/w2JygDiAAAAAA==.',
As='Asgardian:BAAANQAECgMIBgAAAA==.Asmoon:BAABNQAFFH8RAAILAAUKix69CgDCAQALAAUKix69CgDCAQAAAA==.',
At='Athren:BAAANQAECgYIEQAAAA==.Athrogate:BAABNQAECn8kAAIMAAgKLxhaYgBkAgAMAAgKLxhaYgBkAgAAAA==.',
Au='Auraloxious:BAAANQAECgMIAwAAAA==.',
Az='Azmun:BAAANQAECgQIBAABNQAFFAUIEQALAIseAA==.Azmunn:BAAANQAECgMIAwABNQAFFAUIEQALAIseAA==.',
Ba='Baelzadru:BAAANQAECgUIDQAAAA==.Baelzheron:BAAANQAECgUICwAAAA==.Baksylyk:BAAANQAECgMIBAABNQAECggIGwAJAF8iAA==.Balgart:BAAANQAECgIIAgAAAA==.Ballador:BAAANQAECgYICgAAAA==.Barakas:BAAANQADCgUICAAAAA==.Barakoshamma:BAABNQAECn8vAAINAAkKWiQlAQC2AwANAAkKWiQlAQC2AwAAAA==.Barazudar:BAABNQAECn8mAAIKAAgKihNaYQDxAQAKAAgKihNaYQDxAQAAAA==.Baroke:BAAANQADCgYIBgAAAA==.Barragadin:BAAANQADCgUIBQABNQAECgYIDwAOAAAAAA==.Barrageobama:BAAANQADCgUIBQAAAA==.Barreta:BAABNQAECn8ZAAIDAAkKVg8TagA9AgADAAkKVg8TagA9AgAAAA==.',
Be='Beck:BAABNQAECn8nAAMBAAgKMQQcoQAvAQABAAgKMQQcoQAvAQAPAAcKAgN91ADmAAAAAA==.Beefykin:BAAANQAECgYIDwAAAA==.Bellamuerté:BAAANQAECgQIBAABNQAECgkJIAAQAKYVAA==.Bellámuerté:BAABNQAECn8gAAIQAAkKphVpTQBoAgAQAAkKphVpTQBoAgAAAA==.Bemmy:BAAANQAECgQIDAABNQAECgkJKgABAIYgAA==.',
Bi='Bigdrandyy:BAABNQAECn8WAAMBAAYKsiFATAAvAgABAAYKsiFATAAvAgAPAAUKfQkMxQAEAQAAAA==.Biggspal:BAAANQADCgYIBgAAAA==.',
Bl='Blackbird:BAABNQAECn8mAAIRAAkKxyHaBgBjAwARAAkKxyHaBgBjAwAAAA==.Blackmage:BAAANQADCgYIBgAAAA==.Bloodlordzz:BAABNQAECn8aAAIJAAcKEQ2rzAB8AQAJAAcKEQ2rzAB8AQAAAA==.Bloodreina:BAAANQAECgYIEAABNQAECggIEgAOAAAAAA==.Blutkind:BAAANQAECggICAAAAA==.',
Bo='Bob:BAAANQAECgYIEgAAAA==.Bobtheknob:BAAANQAECgQIBAAAAA==.Bockandcalls:BAAANQAECgYICgAAAA==.Bolbi:BAAANQAECgIIAwAAAA==.Bootyhunting:BAAANQAFFAQIBAAAAA==.',
Br='Brahm:BAAANQAECgQICAABNQAECgkJKgAPAHcbAA==.Brdua:BAAANQADCgYIBgAAAA==.Breadnbudda:BAAANQADCgcIHAAAAA==.Brideofloco:BAAANQABCgEIAQAAAA==.Brogar:BAAANQADCgcIHwAAAA==.',
Bu='Bubblekush:BAABNQAECn8UAAISAAcKUhTmIQDQAQASAAcKUhTmIQDQAQABNQAFFAYIEQATAIsWAA==.Buffknight:BAAANQAECgQIBwABNQAECgkJKgAPAHcbAA==.Bulkam:BAAANQAECgYIEAAAAA==.Bulkazarr:BAABNQAECn8cAAIBAAgKThu5PQBmAgABAAgKThu5PQBmAgAAAA==.Burbuja:BAAANQADCggICAABNQAECgkJKgAUAMIjAA==.',
['Bí']='Bíssell:BAAANQAECggIDwAAAA==.',
['Bù']='Bùllrùsh:BAAANQABCgEIAQAAAA==.',
Ca='Callabash:BAABNQAECn8tAAMBAAkKHRyZJgDIAgABAAkKHRyZJgDIAgAPAAYKAQhptwAfAQAAAA==.Catnapped:BAAANQAECgIIAwABNQAFFAIIBgAKAMEQAA==.',
Ce='Celarena:BAAANQAECgYIEQAAAA==.Cermit:BAAANQAECgEIAQAAAA==.',
Ch='Cheefkdavi:BAAANQAECgEIAwABNQAECgkJHQAIAKgiAA==.Chewie:BAAANQADCgUIBQAAAA==.Chilla:BAAANQADCgQIBAAAAA==.Chomrogg:BAAANQAECgYJBwAAAA==.Chopzzpala:BAAANQADCgYICAAAAA==.Choubelle:BAAANQADCgQIBAAAAA==.Chyp:BAABNQAECn8eAAMJAAgKgRmNcwBDAgAJAAgKgRmNcwBDAgASAAQKsRefNwApAQAAAA==.Chzpriest:BAABNQAECn8aAAQTAAgKix+VFgCkAgATAAcKeR+VFgCkAgAUAAgKrhSsVgAbAgAVAAEK8grdKgAuAAAAAA==.',
Ci='Cichorì:BAACNQAFFH8RAAMQAAQKERmqGQAtAQAQAAMKrCOqGQAtAQAWAAIKMhH/DgCaAAA1AAQKfyoAAxYACQp+JEwHAJACABAABwoOJuIvAMUCABYACQr1G0wHAJACAAAA.Cipa:BAAANQADCgcIBwAAAA==.Circee:BAAANQAECgMIBQAAAA==.',
Co='Colmer:BAAANQADCgMIAwAAAA==.',
Cp='Cptvoker:BAAANQADCgIIAgAAAA==.',
Cr='Creckko:BAAANQADCgMIBAAAAA==.Crockito:BAACNQAFFH8lAAIPAAgKqyM2AABlAwAPAAgKqyM2AABlAwA1AAQKfyMAAw8ACQr8JugAAPoDAA8ACQr8JugAAPoDAAEAAQpXDkghASgAAAAA.',
Cy='Cyrusdavirus:BAAANQADCgUIBQAAAA==.',
Da='Dabu:BAAANQAECgQIBAAAAA==.Dama:BAAANQADCgIIAgABNQADCgIIAgAOAAAAAA==.Danto:BAABNQAECn8ZAAIGAAkKvxv3EQDqAgAGAAkKvxv3EQDqAgABNQAECgkJKgAPAHcbAA==.Dantos:BAAANQAECgUICAABNQAECgkJKgAPAHcbAA==.Darc:BAAANQAECgUIBQABNQAECgYIBgAOAAAAAA==.Darktroll:BAABNQAECn8uAAIDAAkKxhVpTwB+AgADAAkKxhVpTwB+AgAAAA==.',
De='Deemo:BAAANQADCgQIBAABNQADCgcIFAAOAAAAAA==.Deladore:BAAANQADCgYIBgAAAA==.Depoprovera:BAABNQAECn8qAAISAAkKKhSvHgDvAQASAAkKKhSvHgDvAQAAAA==.Deqz:BAABNQAECn8mAAMXAAkKmBlPHgBcAgAXAAgKtBhPHgBcAgADAAEK7h5/PwFYAAAAAA==.',
Dh='Dhanto:BAAANQAECgQIBQABNQAECgkJKgAPAHcbAA==.',
Di='Diezel:BAAANQAECgIIAgABNQAECggIDwAOAAAAAA==.Dilox:BAAANQAECgMIAwAAAA==.Dinosaur:BAABNQAECn8qAAMYAAgKZBqWGQAmAgAYAAgKZBqWGQAmAgAZAAcK0hifEwATAgABNQAFFAQICAAKAAgOAA==.Dirtydee:BAABNQAECn8rAAIIAAkKWwpAVwCTAQAIAAkKWwpAVwCTAQAAAA==.Disaaya:BAABNQAECn8eAAIDAAgKtQ2fggADAgADAAgKtQ2fggADAgAAAA==.Divinecheeks:BAAANQAECgIIBgAAAA==.',
Dj='Djangó:BAAANQAECgQIBwAAAA==.',
Do='Donto:BAAANQAECgUICQABNQAECgkJKgAPAHcbAA==.Dontos:BAAANQAECgQICgABNQAECgkJKgAPAHcbAA==.Doodlebug:BAACNQAFFH8SAAIIAAUKkxrqCwCSAQAIAAUKkxrqCwCSAQA1AAQKfy4AAggACQotHg4YAOoCAAgACQotHg4YAOoCAAAA.Dooshrocket:BAAANQAECgUICgAAAA==.Dotsntaxes:BAACNQAFFH8PAAQWAAUKEQ/WEwBqAAAQAAMK5RMcJgDUAAAWAAIK3gLWEwBqAAAaAAEKAAAAFAAoAAA1AAQKfyUABBYACQrPGjQmAEIBABAACAotF0BrABgCABYABQrHEjQmAEIBABoAAQqNFS8oAEkAAAAA.',
Dr='Dracom:BAAANQAECgIIAwAAAA==.Dracuujin:BAAANQADCggICAABNQAFFAYIGwAUAEggAA==.Dralioli:BAABNQAECn8cAAIKAAcKIxOXdgCxAQAKAAcKIxOXdgCxAQAAAA==.Dreadloccs:BAAANQAECgMIBAAAAA==.Dreanil:BAABNQAECn8eAAIBAAkKrg7/agDHAQABAAkKrg7/agDHAQAAAA==.Droho:BAABNQAECn8lAAMZAAgKJyXvBABGAwAZAAgKJyXvBABGAwAbAAEK5ADhKAATAAABNQAFFAcIGAAPAJgZAA==.Drroog:BAAANQADCgQIBQABNQAECgEIAQAOAAAAAA==.',
Du='Dumper:BAAANQAECgIIAgAAAA==.',
Dw='Dwarfsize:BAAANQADCggICAABNQAFFAcIGAACAGkZAA==.',
Dz='Dzievana:BAAANQAECgEIAQAAAA==.',
['Dâ']='Dârn:BAABNQAECn8lAAMQAAkKfB2HKQDcAgAQAAkKfB2HKQDcAgAWAAEKASCPagBKAAAAAA==.',
El='Eleweaver:BAAANQADCgcIDAAAAA==.Elissra:BAAANQADCgEIAQABNQAECgcIEQAOAAAAAA==.Elvispræstly:BAAANQADCgYIBgAAAA==.',
En='Endfist:BAAANQAECggICAAAAA==.Enoughtalk:BAAANQAECgYIDAAAAA==.',
Eo='Eostre:BAABNQAECn8qAAQUAAkKwiNCBwCJAwAUAAkKciNCBwCJAwAVAAMKfR6qEQAKAQATAAEKSRcJcABEAAAAAA==.',
Es='Essa:BAAANQAECgIIAgAAAA==.',
Et='Ethernal:BAAANQAECgYIBgAAAA==.',
Eu='Eupherine:BAABNQAECn8nAAIUAAgKWSOZGAASAwAUAAgKWSOZGAASAwAAAA==.',
Ev='Evillarry:BAAANQADCgYIDAAAAA==.Evilpaladin:BAABNQAECn8xAAISAAkKTBzpDADLAgASAAkKTBzpDADLAgAAAA==.Evilrico:BAAANQAECgEIAQAAAA==.',
Ez='Ezluz:BAABNQAECn8bAAMIAAgKrRrzNAA2AgAIAAgKrRrzNAA2AgAEAAIKeBLkuAB3AAAAAA==.',
Fa='Facsimile:BAABNQAECn8qAAITAAgKORXvHQBOAgATAAgKORXvHQBOAgAAAA==.',
Fe='Festers:BAABNQAECn8cAAMGAAkKaxcbKwA4AgAGAAgKSxgbKwA4AgAHAAQK2RDbNAANAQAAAA==.',
Fi='Fingerwalk:BAABNQAECn8pAAIcAAgKrQ+kDwDxAQAcAAgKrQ+kDwDxAQAAAA==.',
Fl='Flappi:BAABNQAECn8lAAITAAkKiB3VDQAOAwATAAkKiB3VDQAOAwAAAA==.Flappii:BAAANQADCgEIAQAAAA==.Flaster:BAAANQADCgYIBgAAAA==.Fluffykat:BAABNQAECn8lAAILAAgKDBq2LQBsAgALAAgKDBq2LQBsAgAAAA==.',
Fo='Fosho:BAACNQAFFH8YAAIPAAcKmBkmAgCcAgAPAAcKmBkmAgCcAgA1AAQKfyMAAg8ACQpJJkkEAMkDAA8ACQpJJkkEAMkDAAAA.',
Fr='Franch:BAAANQAECgYIEQAAAA==.Frank:BAAANQAECgEIAQABNQAECggIDwAOAAAAAA==.Fraud:BAAANQAECgcIDgABNQAECggIEgAOAAAAAA==.Freelvlsvnty:BAAANQADCgYIBwAAAA==.Froddy:BAABNQAECn8VAAMPAAcKkxvUWwALAgAPAAcKvhnUWwALAgANAAEKZx1iMQBWAAAAAA==.Frostybox:BAAANQAECgQIBAAAAA==.Frylockk:BAABNQAECn8pAAQaAAkKQiK3AACMAwAaAAkKQiK3AACMAwAQAAYKVRqxmACjAQAWAAEKQB3RagBKAAAAAA==.',
Fu='Furrykane:BAEBNQAECn8fAAQLAAgKuRiaNwAsAgALAAgKfReaNwAsAgACAAIKaAiqZABsAAAdAAEKyReTOgBJAAAAAA==.Future:BAABNQAECn8uAAINAAgKzxXJEgA6AgANAAgKzxXJEgA6AgAAAA==.',
Ga='Gaara:BAABNQAECn8WAAIeAAcKtQpnBAGCAQAeAAcKtQpnBAGCAQAAAA==.Gamepunisher:BAABNQAECn8oAAMfAAkKQhvIDADnAQAeAAkKQRkhegCJAgAfAAcK6B7IDADnAQAAAA==.Gares:BAAANQAECggIDgAAAA==.',
Gi='Giorbs:BAAANQADCgYIBgAAAA==.',
Go='Goatgeek:BAAANQABCgUIBgABNQAECgMIAwAOAAAAAA==.Goham:BAABNQAECn8qAAIBAAkKhiAUGAARAwABAAkKhiAUGAARAwAAAA==.Goobe:BAAANQAECgQIBAABNQAECgkJKgADABMeAA==.Goontotem:BAAANQAECgEIAQABNQAECgUIBgAOAAAAAA==.Gorro:BAAANQADCgYIBgAAAA==.',
Gr='Grimkai:BAAANQABCgMIAwAAAA==.Grogon:BAAANQAECgUIEAAAAA==.Gromlo:BAABNQAECn8hAAMCAAgK2iGCDgDnAgACAAgK2iGCDgDnAgALAAIKSRbilgB3AAAAAA==.Grulog:BAAANQAECgQICwAAAA==.',
Gu='Guldav:BAAANQADCgMIAwAAAA==.Gunny:BAABNQAECn8nAAMDAAgKniKvIAATAwADAAgKniKvIAATAwAXAAIK5hfhcABtAAAAAA==.',
['Gã']='Gã:BAAANQADCgUIBQAAAA==.',
['Gö']='Göld:BAAANQAECgUIBQAAAA==.',
Ha='Haeliman:BAAANQADCggICwAAAA==.Haileigh:BAAANQAECgMICQAAAA==.Harleigh:BAAANQAECgQIBAAAAA==.Havöc:BAABNQAECn8hAAIMAAgKGhxxcQA8AgAMAAgKGhxxcQA8AgAAAA==.',
He='Herpenderper:BAAANQAECgQIBwAAAA==.',
Hi='Hikawa:BAABNQAECn8yAAIeAAgKqSXbHgBdAwAeAAgKqSXbHgBdAwAAAA==.Hippocratic:BAABNQAECn8bAAMPAAkKehqKVAAkAgAPAAgKFRqKVAAkAgABAAgKsRNBWQABAgAAAA==.',
Ho='Homunculous:BAAANQAECgIIAgAAAA==.Honortheox:BAAANQADCgEIAQABNQAECgMIAwAOAAAAAA==.',
Hu='Huntemall:BAABNQAECn8aAAIDAAcK7xFKjgDpAQADAAcK7xFKjgDpAQAAAA==.',
Hy='Hysteriix:BAEBNQAECn84AAIgAAkKViVfAQC8AwAgAAkKViVfAQC8AwAAAA==.',
Ic='Iceborn:BAAANQAECggIAQAAAA==.Iceshards:BAABNQAECn8oAAIfAAgKVQ7YDADlAQAfAAgKVQ7YDADlAQAAAA==.Icraptotems:BAAANQAECgEIAQAAAA==.',
Id='Idtrapthat:BAAANQAECgQIBgAAAA==.',
Il='Illidankior:BAACNQAFFH8KAAIhAAQKoRvoAgBKAQAhAAQKoRvoAgBKAQA1AAQKfyAAAiEACQruHkQIAM0CACEACQruHkQIAM0CAAAA.Illirothas:BAAANQAECgUIBQABNQAECgkJKwADAMoYAA==.',
Im='Imen:BAAANQAECgcIEQAAAA==.Imsassy:BAAANQAECgUICQAAAA==.',
In='Infect:BAAANQADCgIIAgABNQAECgYICAAOAAAAAA==.Infectedbøb:BAAANQAECgQICgAAAA==.Inmortuae:BAAANQAECgQIBAABNQAECgkJKwADAMoYAA==.Instågram:BAAANQAECgMIBQAAAA==.',
Io='Iornbane:BAAANQAECgYIEgAAAA==.',
Ir='Irissela:BAAANQAECgYICwAAAA==.',
Is='Ispitmagic:BAAANQAECgYIBwAAAA==.',
Iv='Ivalice:BAABNQAECn8bAAQDAAkKyRabeAAaAgADAAcKeBmbeAAaAgAXAAUK2AhIUQDgAAAiAAIKAABkDwCRAAAAAA==.',
Iz='Izüal:BAAANQADCgYICQABNQAECggIGwAJAF8iAA==.',
Ja='Jafbe:BAABNQAECn8YAAMKAAgKnB3HKQC+AgAKAAgKnB3HKQC+AgAJAAEKmhBrjQFBAAAAAA==.Jaghatai:BAAANQAECgUICAAAAA==.Jammer:BAAANQADCgYIBgAAAA==.',
Ji='Jigsaw:BAAANQADCggIDgAAAA==.Jimcarrey:BAAANQAECgIIAwABNQAECgkJJAADAMQLAA==.Jimmyc:BAAANQAECgYIDwABNQAECgkJJAADAMQLAA==.Jimmyque:BAABNQAECn8kAAIDAAkKxAttdQAiAgADAAkKxAttdQAiAgAAAA==.',
Jo='Joemauma:BAABNQAECn8iAAIfAAgKNBVYCABZAgAfAAgKNBVYCABZAgAAAA==.',
Jp='Jpam:BAACNQAFFH8KAAMfAAQKOxqpBwCcAAAeAAIKaSQFPQDDAAAfAAIKIxWpBwCcAAA1AAQKfyIAAh4ACQoaHF16AIkCAB4ACQoaHF16AIkCAAAA.',
Ju='Judges:BAAANQAECggIEAAAAA==.Jumbosize:BAACNQAFFH8YAAICAAcKaRnXAQBYAgACAAcKaRnXAQBYAgA1AAQKfy0AAgIACQoqJnMBAL8DAAIACQoqJnMBAL8DAAAA.Jupîter:BAAANQAECgEIAQABNQAECgEIAgAOAAAAAA==.Justamuslim:BAAANQADCggICAABNQAECgYICgAOAAAAAA==.',
Ka='Kaerlif:BAAANQAECgcIDAABNQAFFAUIDAAjAOIVAA==.Kaiyley:BAAANQAECgcIDAAAAA==.Kalastrian:BAABNQAECn8fAAIRAAcKmSTIEADnAgARAAcKmSTIEADnAgAAAA==.Karatepally:BAAANQAECgEIAQAAAA==.Karateshock:BAABNQAECn8nAAMBAAkKZxNNUgAZAgABAAkKZxNNUgAZAgAPAAEKmgV0OAEvAAAAAA==.Kargo:BAAANQAECgYICwAAAA==.Karlmarks:BAAANQABCggIDgAAAA==.Kazuren:BAABNQAECn8mAAIZAAgKDwviGAC4AQAZAAgKDwviGAC4AQAAAA==.',
Ke='Keano:BAABNQAECn8gAAMKAAcKZxD6mgBOAQAKAAYKhA36mgBOAQAJAAQKSxnYCgEGAQAAAA==.Keeldemall:BAAANQAECgYIDAAAAA==.Kelia:BAAANQAECgMIAwABNQAECgkJKwADAMoYAA==.Kelinna:BAABNQAECn8XAAIJAAgK4Q6drQC/AQAJAAgK4Q6drQC/AQAAAA==.',
Kh='Khmelnitsky:BAAANQADCggICAAAAA==.',
Ki='Kilron:BAAANQABCgMIAgAAAA==.Kirin:BAABNQAECn8bAAIPAAcK3Rv1SgBHAgAPAAcK3Rv1SgBHAgAAAA==.Kitri:BAAANQADCgUIBwAAAA==.',
Kl='Klaye:BAAANQAECgcIEAABNQAECgkJKgAPAHcbAA==.',
Kn='Knatknom:BAAANQAECgIIAgAAAA==.',
Ko='Kodabonk:BAABNQAECn8nAAIcAAgKox1/CAChAgAcAAgKox1/CAChAgAAAA==.Kodanorth:BAAANQAECgEJAQABNQAECggIJwAcAKMdAA==.Korthos:BAAANQAECgYIEQAAAA==.Kotara:BAAANQADCggIDwAAAA==.',
Kr='Kraur:BAABNQAECn8rAAIDAAkKyhiJOwC1AgADAAkKyhiJOwC1AgAAAA==.',
['Kì']='Kìngpin:BAABNQAECn8mAAIDAAkK5RmFQgChAgADAAkK5RmFQgChAgAAAA==.',
La='Laarry:BAAANQADCgUIBQABNQAFFAIIBgAKAMEQAA==.Lam:BAAANQADCgEIAQAAAA==.Lammp:BAABNQAECn8kAAMBAAkKkhxIMACeAgABAAgKAR1IMACeAgAPAAgK0hS/WwALAgAAAA==.Lamppally:BAAANQADCgQIBAABNQAECgkJJAABAJIcAA==.Lampshade:BAAANQADCggICAABNQAECgkJJAABAJIcAA==.Laws:BAABNQAECn8vAAIFAAkK6RQkLwAmAgAFAAkK6RQkLwAmAgAAAA==.Lazydragon:BAABNQAECn8dAAMbAAgKCgwRDwBNAQAZAAcKQwYjIABRAQAbAAcKJQ0RDwBNAQAAAA==.',
Li='Liaeda:BAABNQAECn8sAAMiAAgK7Q0jBwAMAgAiAAgK7Q0jBwAMAgADAAQK2glIDgHiAAAAAA==.Lianshi:BAAANQADCgUIBQAAAA==.Linainverse:BAAANQAECgQICQAAAA==.Lingbane:BAAANQAECgEIAQABNQAECgkJKQAaAEIiAA==.Litchslapped:BAAANQADCgcIBwAAAA==.Lixie:BAAANQADCggICAAAAA==.',
Lo='Lolo:BAAANQADCggICAABNQAFFAcIGAAPAJgZAA==.Loosie:BAAANQADCgEIAQAAAA==.Lost:BAAANQADCgUIBQABNQAECgkJLwAFAOkUAA==.Lovely:BAAANQAECgUIDAAAAA==.',
Lu='Luduhcris:BAAANQADCgYIEAAAAA==.Lugnuts:BAAANQAECgUIDAAAAA==.Lumiltiand:BAABNQAECn8gAAIEAAkKHiOWHADfAgAEAAkKHiOWHADfAgABNQAFFAIIAwAOAAAAAA==.',
Lw='Lwaxana:BAAANQAECgIIAwAAAA==.',
Ma='Maceon:BAAANQADCgcIBwAAAA==.Makloy:BAAANQAECgEIAQAAAA==.Makuahwe:BAAANQADCggICAAAAA==.Malgoros:BAAANQAECgQIBAABNQAECggIKgATADkVAA==.Malgrendin:BAABNQAECn8nAAIDAAkKtSN/BwChAwADAAkKtSN/BwChAwAAAA==.Malty:BAABNQAECn8aAAIMAAgKSxtWcQA8AgAMAAgKSxtWcQA8AgAAAA==.Malédictias:BAAANQAECgQIBgAAAA==.Manataurus:BAAANQADCgYIBgAAAA==.Manatreat:BAAANQAECgEIAQABNQAECgkJKwADAMoYAA==.Manuall:BAAANQAECgQICQAAAA==.Marbas:BAABNQAECn8eAAIEAAgKKRwPOABDAgAEAAgKKRwPOABDAgAAAA==.Maxidk:BAABNQAECn8vAAIIAAgK7SPzDwAsAwAIAAgK7SPzDwAsAwAAAA==.Maximage:BAAANQAECgQICAABNQAECggILwAIAO0jAA==.Maximonk:BAAANQADCgQIBgABNQAECggILwAIAO0jAA==.Mazëkeen:BAAANQADCggICAAAAA==.',
Me='Meditare:BAAANQABCgIIAgAAAA==.Medîvh:BAABNQAECn8ZAAIeAAkKrwsLxQD4AQAeAAkKrwsLxQD4AQAAAA==.',
Mi='Midgemaisel:BAAANQAECgUIDQAAAA==.Mik:BAAANQABCgMIAgABNQADCgYJBgAOAAAAAA==.Mikhael:BAAANQADCgEIAQABNQADCgYJBgAOAAAAAA==.Mirado:BAABNQAECn8hAAIkAAgKah7nBQC2AgAkAAgKah7nBQC2AgAAAA==.Mirix:BAAANQADCgUIBQAAAA==.Mithridates:BAABNQAECn8lAAIWAAgKDwgGGwCTAQAWAAgKDwgGGwCTAQAAAA==.',
Mo='Molonlabe:BAAANQADCgUIBQAAAA==.Monix:BAABNQAECn8iAAMIAAgK8BV9OgAZAgAIAAgK8BV9OgAZAgAEAAUKGBA5hQAHAQAAAA==.Monkragga:BAAANQAECgYIDwAAAA==.Mooseleroy:BAABNQAECn8dAAQlAAcKkRLDLQCmAQAlAAcKkRLDLQCmAQAgAAIK8QTbRgBKAAAcAAEKfQUTNQAiAAAAAA==.Moriko:BAAANQADCgcIBwABNQAECgYIDwAOAAAAAA==.Mortarien:BAABNQAECn8dAAMEAAgKaxnmUgDDAQAEAAYKbB3mUgDDAQAFAAYKuxUtUQBlAQAAAA==.Mozai:BAAANQADCgIIAgABNQAECggIGAAJAFceAA==.',
Mu='Mugged:BAABNQAECn8fAAMeAAgKAA/xzgDlAQAeAAgKAA/xzgDlAQAfAAIKoQMnNgBhAAAAAA==.',
My='Myrtle:BAABNQAECn8mAAImAAgKmRXjCwAJAgAmAAgKmRXjCwAJAgAAAA==.',
['Má']='Másóchist:BAABNQAECn8gAAMQAAkKbB6bQwCEAgAQAAgKBh2bQwCEAgAWAAIKxSCMQwC1AAAAAA==.',
Ne='Necrophobic:BAAANQADCgQIBAAAAA==.Nevernude:BAAANQAECgQIBAABNQAECgkJKgABAIYgAA==.',
Ni='Nice:BAAANQADCgYIDAAAAA==.Nikna:BAAANQADCgIIAgAAAA==.Niwatori:BAABNQAECn8kAAILAAgKWiAGHgDXAgALAAgKWiAGHgDXAgAAAA==.',
No='Noah:BAACNQAFFH8cAAMiAAcKfh4yAABaAgAiAAYKgCEyAABaAgAXAAQK+A6GEgASAQA1AAQKfyMAAyIACQocJmgBAFoDACIACQocJmgBAFoDABcAAgrJFDNtAHYAAAAA.Nol:BAAANQAECggICgABNQAFFAcIHwAGAPojAA==.Nolarz:BAACNQAFFH8fAAIGAAcK+iMqAQC2AgAGAAcK+iMqAQC2AgA1AAQKfysAAgYACQpRJlcEAI8DAAYACQpRJlcEAI8DAAAA.',
Nu='Nukthom:BAAANQADCgcICQAAAA==.',
Ny='Nyneaves:BAABNQAECn8qAAITAAkK+R1CDQAWAwATAAkK+R1CDQAWAwAAAA==.Nyst:BAABNQAECn8dAAIeAAgK0RIvwgD+AQAeAAgK0RIvwgD+AQAAAA==.',
Ob='Objekt:BAAANQAECgYICAAAAA==.',
Oh='Ohmenwah:BAAANQADCgUICQAAAA==.',
Oj='Ojplosion:BAACNQAFFH8GAAIQAAIKlx4mKQC5AAAQAAIKlx4mKQC5AAA1AAQKfxoAAxAACQopImIwAMMCABAACAqLImIwAMMCABYAAwqeHlw0APEAAAE1AAQKBggHAA4AAAAA.Ojpyroblast:BAAANQAECgYIBwAAAA==.',
Ol='Olga:BAAANQAECgYIDAAAAA==.Olma:BAABNQAECn8XAAIMAAYKUBCjywBYAQAMAAYKUBCjywBYAQABNQAFFAYIGwAUAEggAA==.',
Om='Omghunter:BAAANQADCggICAAAAA==.',
On='Onisprite:BAAANQAECgQICAAAAA==.',
Or='Orchaos:BAAANQADCgUIBgAAAA==.Ordhah:BAABNQAECn8bAAMJAAgKXyKgQQDNAgAJAAgKXyKgQQDNAgASAAEK1RbGagA6AAAAAA==.',
Os='Osanna:BAAANQADCggJFQAAAA==.',
Pa='Paladout:BAABNQAECn8nAAMJAAgKfiBOYQByAgAJAAgKPx9OYQByAgASAAQKxB/xKgCCAQAAAA==.Palagouge:BAAANQAECgEIAQAAAA==.Palletjack:BAABNQAECn8vAAIIAAkKeSY2AQDlAwAIAAkKeSY2AQDlAwAAAA==.Palli:BAAANQADCgcIFAAAAA==.Paona:BAABNQAECn8jAAILAAkKvglrSQC+AQALAAkKvglrSQC+AQAAAA==.Papafloppa:BAAANQADCgIIAgAAAA==.Paperpuppy:BAAANQADCgEIAQABNQAECggIFgAeAPMNAA==.Paulioo:BAAANQABCgIIAgAAAA==.',
Pe='Peraroll:BAAANQADCggICAAAAA==.Pewpewkuchoo:BAAANQADCgEIAQAAAA==.',
Ph='Phenphen:BAABNQAECn8lAAMGAAkKqSPYCgAxAwAGAAgKqSPYCgAxAwAHAAUKQBHsMAAxAQAAAA==.Physicyan:BAABNQAECn8VAAQUAAgKKgsDfgCaAQAUAAgKKgsDfgCaAQAVAAEKVwUTLAArAAATAAEKZgLAfgAqAAAAAA==.',
Pi='Pipez:BAAANQAECgYIDgAAAA==.',
Pl='Planetdru:BAABNQAECn8iAAILAAgKCB8nJQClAgALAAgKCB8nJQClAgAAAA==.',
Po='Pogster:BAAANQADCgcIBwAAAA==.Pollyy:BAABNQAECn8gAAIEAAcKoQmfbwBTAQAEAAcKoQmfbwBTAQAAAA==.Popshampain:BAABNQAECn8dAAIPAAcKTxNieAC1AQAPAAcKTxNieAC1AQAAAA==.',
Ps='Psychonight:BAABNQAECn8kAAIVAAkKpBpIAwDCAgAVAAkKpBpIAwDCAgAAAA==.',
Pu='Punchydabear:BAAANQAECgUIAQAAAA==.',
['Pì']='Pìp:BAAANQADCgYJBgAAAA==.',
Ra='Raenlling:BAAANQAFFAIIAwAAAA==.Ratscum:BAEANQADCggIGAAAAA==.Rayssa:BAABNQAECn8vAAMVAAgKpSNyAQA5AwAVAAgKpSNyAQA5AwAUAAcKMhhFYQD5AQAAAA==.',
Re='Redeker:BAABNQAECn8iAAIGAAgKxRPoLgAjAgAGAAgKxRPoLgAjAgAAAA==.Redlossa:BAAANQADCgIIAgAAAA==.Renneth:BAAANQADCgUICgAAAA==.Rentahunter:BAAANQAECgEIAQAAAA==.Revax:BAAANQAECgQIBAABNQAECgkJKwADAMoYAA==.Reyna:BAAANQADCgQIBAABNQADCggICAAOAAAAAA==.',
Rh='Rholand:BAAANQAECgUIBgAAAA==.',
Ri='Ricopsu:BAABNQAECn8fAAMdAAgKyx0mCQC1AgAdAAgKyx0mCQC1AgALAAEKygYXtwAnAAAAAA==.',
Rn='Rngnar:BAAANQAECggIEQAAAA==.',
Ro='Roakar:BAAANQAECgIIAwAAAA==.Rocklii:BAAANQADCggIEQAAAA==.Roguewolf:BAABNQAECn8vAAMLAAkKnxE/RADeAQALAAgKkBE/RADeAQACAAEKcQUTdwAtAAAAAA==.Rokdomaa:BAAANQAFFAEIAQAAAA==.Roki:BAABNQAECn8bAAIYAAgKXQ4CIQDGAQAYAAgKXQ4CIQDGAQAAAA==.Rolow:BAABNQAECn8tAAIeAAgKJB4TdwCPAgAeAAgKJB4TdwCPAgAAAA==.Roony:BAACNQAFFH8aAAICAAcKTx9IAQB6AgACAAcKTx9IAQB6AgA1AAQKfycAAgIACQryIgQLABUDAAIACQryIgQLABUDAAAA.Roper:BAAANQAECggIBAAAAA==.Roritai:BAAANQABCgQIBAABNQAECgQICwAOAAAAAA==.Rot:BAABNQAECn8kAAMFAAkKyCVrDwASAwAFAAgKJSVrDwASAwAEAAkKZCT1FQAJAwAAAA==.Royle:BAABNQAECn8ZAAQkAAkK3RszBwCGAgAkAAcKPx4zBwCGAgAMAAkK+RPraQBQAgAhAAEKAAClQgAzAAAAAA==.',
Ru='Runes:BAABNQAECn8rAAIEAAkKFhshKACXAgAEAAkKFhshKACXAgAAAA==.Runnerjay:BAABNQAECn8VAAIDAAkKzwaalwDVAQADAAkKzwaalwDVAQABNQAECgkJKgASACoUAA==.Rush:BAAANQADCgIIAgABNQAECggIJgABAGsZAA==.Ruuf:BAABNQAECn8aAAMSAAgK7yIZDADWAgASAAgK7yIZDADWAgAJAAYK9waGIgHfAAAAAA==.',
Ry='Rygik:BAAANQAECgYIDAABNQAECggIHAAXALsfAA==.Rysxn:BAABNQAECn8cAAIXAAgKux//EwC+AgAXAAgKux//EwC+AgAAAA==.Ryuujins:BAACNQAFFH8bAAIUAAYKSCB4BABaAgAUAAYKSCB4BABaAgA1AAQKfyYAAxQACQrzJBoaAAoDABQACQqoJBoaAAoDABUABQq/JD4JAMQBAAAA.',
['Rá']='Ráhu:BAAANQAECgQIBQABNQAECgkJLQARAFsbAA==.',
Sa='Sago:BAABNQAECn8dAAMMAAgKNyGXVACKAgAMAAgKcyCXVACKAgAhAAUK6hruHQBhAQAAAA==.Sandman:BAABNQAECn8XAAIJAAcKoxG8tQCtAQAJAAcKoxG8tQCtAQAAAA==.',
Sc='Scumball:BAEANQADCgcIEgABNQADCggIGAAOAAAAAA==.Scyon:BAACNQAFFH8HAAIeAAQKFQ1CKgAzAQAeAAQKFQ1CKgAzAQA1AAQKf0IAAh4ACQr4IKIaAGsDAB4ACQr4IKIaAGsDAAAA.',
Se='Selinie:BAAANQABCggIEAAAAA==.Senari:BAABNQAECn8oAAMSAAgKahtXHgDzAQAJAAgKRBdDhAAaAgASAAcK5RtXHgDzAQAAAA==.Senbane:BAAANQADCggICQAAAA==.Sencia:BAAANQAECgcIEAAAAA==.Senseiwacks:BAAANQAECgIIAgAAAA==.',
Sh='Shadowblazer:BAABNQAECn8fAAIQAAgKLB7URQB+AgAQAAgKLB7URQB+AgAAAA==.Shalizar:BAAANQAECgYIBgAAAA==.Shanda:BAACNQAFFH8LAAIBAAUKexeFCgChAQABAAUKexeFCgChAQA1AAQKfyQAAwEACQpqIEgeAPACAAEACQpqIEgeAPACAA8AAwoZIOnVAOMAAAAA.Shanto:BAABNQAECn8qAAIPAAkKdxv+IgD5AgAPAAkKdxv+IgD5AgAAAA==.Shatrauzg:BAAANQAECgEIAQAAAA==.Sheesh:BAAANQADCgcIDgAAAA==.Shesheshenn:BAABNQAECn8tAAMBAAkK0Rx1IgDcAgABAAgKViB1IgDcAgANAAgKmgGWKADUAAAAAA==.Shiftinmojo:BAAANQAECggIDAAAAA==.Shoumei:BAABNQAECn8lAAMlAAgKMxj+HwAqAgAlAAgKMxj+HwAqAgAgAAYKAAouLAAGAQAAAA==.Shugz:BAAANQAECgEIAQABNQAECgkJHgAHAI4dAA==.Shuken:BAAANQAECggIAQAAAA==.',
Si='Silfra:BAAANQAECgQIDAAAAA==.Sinfull:BAAANQADCggICAAAAA==.Sintharia:BAAANQAECgYIBgAAAA==.Siousxie:BAAANQADCgUIBQAAAA==.',
Sk='Skolaid:BAACNQAFFH8LAAMKAAQKnQz5EgArAQAKAAQKnQz5EgArAQAJAAMKgxwuFAAOAQA1AAQKfycAAwoACQqfIL8UACwDAAoACQqfIL8UACwDAAkABgq4I0FnAGICAAAA.',
Sl='Slapparazzi:BAAANQADCgYIBQAAAA==.',
Sm='Smilingdev:BAAANQADCggIEAABNQAECgMIAwAOAAAAAA==.Smoopoodoop:BAAANQAECgcIDAAAAA==.',
Sn='Snagglepuss:BAAANQADCggICAAAAA==.Sneakysin:BAAANQADCgQIBAAAAA==.',
So='Soulmend:BAAANQAECgYIEQAAAA==.Soulsproxy:BAAANQABCgQIBQAAAA==.',
Sp='Spaceman:BAAANQAECgUIDAAAAA==.',
Sq='Sqûïsh:BAAANQADCggICAAAAA==.',
St='Stabbz:BAAANQADCgUIBQAAAA==.Stevetson:BAAANQAECgYIDQAAAA==.Stonatroll:BAAANQAECgMIBAABNQAECgkJKwADAMoYAA==.Stoops:BAAANQADCggIFgAAAA==.Stormdemon:BAABNQAECn8eAAMMAAgKbBgsbABKAgAMAAgKFhgsbABKAgAkAAEKrxr0KwBSAAAAAA==.Stormspellz:BAABNQAECn8dAAIBAAgKLxjhSgA0AgABAAgKLxjhSgA0AgAAAA==.',
Su='Supay:BAAANQAECgUIDQAAAA==.',
Sw='Swinginsista:BAABNQAECn8eAAIKAAcKUxrZTgAtAgAKAAcKUxrZTgAtAgAAAA==.',
Ta='Taldath:BAAANQADCggJDwAAAA==.Talicso:BAACNQAFFH8GAAMeAAMKTgoFSQCTAAAeAAIKlg0FSQCTAAAfAAEKvAPXFABBAAA1AAQKfyAAAh4ACQpbGQOIAG4CAB4ACQpbGQOIAG4CAAAA.Talos:BAAANQAECggIEgAAAA==.Talzinn:BAAANQADCgYIBgABNQAECggIEgAOAAAAAA==.Tardalian:BAAANQADCgYICAAAAA==.Tarkinal:BAABNQAECn8YAAIBAAgKvB4mKwC0AgABAAgKvB4mKwC0AgAAAA==.Taurito:BAAANQAECgUIDgAAAA==.',
Te='Teezee:BAABNQAECn8tAAMJAAkKgR43MgAAAwAJAAkKgR43MgAAAwAKAAMKKBOY2gDEAAAAAA==.Teitterdrud:BAABNQAECn8dAAMLAAgK1A3xUQCQAQALAAgKGwrxUQCQAQAdAAMK1RKTKgC3AAAAAA==.Telina:BAAANQAECggIDQAAAA==.Telira:BAAANQAECgcIEQAAAA==.Tenderhoof:BAACNQAFFH8GAAILAAMKhBC/FwDpAAALAAMKhBC/FwDpAAA1AAQKfy4AAwsACQpXHtYSAC8DAAsACQpXHtYSAC8DAAIABwpxEQ0uAKYBAAAA.',
Th='Thanatus:BAAANQADCgQJBAAAAA==.Thath:BAAANQADCggIJwAAAA==.Thavus:BAAANQADCgYIBgAAAA==.Thearatwo:BAABNQAECn8dAAIIAAkKqCLzCQBlAwAIAAkKqCLzCQBlAwAAAA==.Thruumm:BAAANQAECgYICwAAAA==.Thunderclapz:BAAANQAECgcJCAAAAA==.Thunsibution:BAAANQADCggICQABNQAFFAQICgAhAKEbAA==.',
Ti='Tickz:BAABNQAECn8rAAQQAAgKJCExHAASAwAQAAgK+yAxHAASAwAaAAYKmB4zCQDwAQAWAAIKwBWZUwCCAAAAAA==.Tinilia:BAAANQADCgQIBQAAAA==.Tirah:BAABNQAECn8tAAILAAgKjAi6VgB3AQALAAgKjAi6VgB3AQAAAA==.',
To='Toat:BAAANQADCgYIBgAAAA==.Toeran:BAABNQAECn8rAAMSAAkKfx6VBwAnAwASAAkKfx6VBwAnAwAJAAUK+A6aAgEUAQAAAA==.Tokémon:BAAANQAECgcICgAAAA==.Toxren:BAACNQAFFH8GAAIKAAIKwRCHHwCOAAAKAAIKwRCHHwCOAAA1AAQKfyQAAwoACQpEHL0gAOkCAAoACQpEHL0gAOkCAAkAAgoSBfqJAUQAAAAA.',
Tr='Traelin:BAACNQAFFH8KAAIKAAQKKh72DQB+AQAKAAQKKh72DQB+AQA1AAQKfyQAAgoACQqQJDoGAJkDAAoACQqQJDoGAJkDAAAA.Tread:BAAANQAECgMIAwAAAA==.Trickee:BAAANQAECgYICwABNQAECgYIEQAOAAAAAA==.',
Ts='Tskaha:BAAANQAFFAEIAQAAAA==.',
Ty='Tyria:BAABNQAECn8aAAIXAAkK/QswKgD3AQAXAAkK/QswKgD3AQAAAA==.Tyruunas:BAAANQADCgMIAwAAAA==.',
Ug='Uggthok:BAAANQAECgcIEAAAAA==.',
Ur='Urizarah:BAAANQADCgYIDAAAAA==.',
Ut='Uthrid:BAAANQADCgYIBgAAAA==.',
Va='Vanadis:BAAANQADCgcICwAAAA==.Vardamir:BAACNQAFFH8IAAIKAAQKCA5QEwAmAQAKAAQKCA5QEwAmAQA1AAQKfyIAAgoACQreHeAdAPgCAAoACQreHeAdAPgCAAAA.Vargath:BAAANQADCgMIAwAAAA==.Vashstampede:BAAANQAECgYICAAAAA==.',
Ve='Vei:BAAANQAECggICAABNQADCgIIAgAOAAAAAA==.Velrik:BAAANQAECgQICgAAAA==.Venema:BAAANQADCgIIAgAAAA==.Venüs:BAAANQAECgEIAQAAAA==.Vercy:BAAANQADCgYIBwABNQAECgEIAQAOAAAAAA==.Vezkin:BAACNQAFFH8KAAILAAQK4Rx+EwAtAQALAAQK4Rx+EwAtAQA1AAQKfyMAAgsACQqTJWoJAIEDAAsACQqTJWoJAIEDAAAA.',
Vh='Vhexx:BAAANQAECgQIBAAAAA==.',
Vi='Vintagejeans:BAABNQAECn8ZAAIJAAcK+QOqFwHxAAAJAAcK+QOqFwHxAAAAAA==.Virtus:BAABNQAECn8qAAIDAAkKxBe6PACyAgADAAkKxBe6PACyAgAAAA==.Vitrixz:BAAANQADCgUICwAAAA==.Vizaimor:BAABNQAECn8dAAIDAAkKYRGKZwBCAgADAAkKYRGKZwBCAgAAAA==.',
Vo='Voi:BAAANQABCgIIAwABNQAECgEIAQAOAAAAAA==.Vostok:BAACNQAFFH8GAAIMAAQKZw4HHAAsAQAMAAQKZw4HHAAsAQA1AAQKfyAAAwwACQogGBphAGcCAAwACQogGBphAGcCACEAAQoxE8tBADUAAAAA.',
Vu='Vulcãnus:BAAANQAECgEIAgAAAA==.',
Wa='Wallyoak:BAAANQADCgEIAQAAAA==.Warcry:BAAANQAECgEJAQAAAA==.',
We='Wealthyscaly:BAAANQAECgMIBwAAAA==.Weedzzar:BAAANQADCgQIBgAAAA==.Werse:BAABNQAECn8nAAIUAAgKtR+kMgCbAgAUAAgKtR+kMgCbAgAAAA==.Wetloginyou:BAABNQAECn8cAAIBAAcKIiIVLwCjAgABAAcKIiIVLwCjAgAAAA==.',
Wh='Whodi:BAABNQAECn8WAAQeAAgK8w0MFQFlAQAeAAYKLwwMFQFlAQAnAAIKRgtJCQBzAAAfAAIKahAEMwBsAAAAAA==.',
Wi='Witt:BAABNQAECn8ZAAMWAAgKFAgLLQAYAQAQAAYK5AY11AAcAQAWAAUK4AgLLQAYAQAAAA==.',
Wo='Woementality:BAAANQADCgMIAwAAAA==.Wolful:BAABNQAECn8mAAMBAAgKaxlVTwAkAgABAAgKaxlVTwAkAgANAAMKbQWfLACUAAAAAA==.',
Wr='Wrathoftitan:BAAANQADCgIIAgAAAA==.',
Wu='Wubble:BAAANQAECgQIBAAAAA==.Wushoolay:BAAANQAECgQJCgAAAA==.',
Xn='Xnatem:BAABNQAECn8pAAIhAAgKJSLzBgDvAgAhAAgKJSLzBgDvAgAAAA==.',
Xo='Xoliver:BAAANQADCgYICQAAAA==.',
Ya='Yashiro:BAABNQAECn8pAAMKAAgKLBBeZgDiAQAKAAgKLBBeZgDiAQAJAAEKAAAbzgEbAAAAAA==.',
Ye='Yeraleth:BAABNQAECn8iAAICAAkKgRyUEQDCAgACAAkKgRyUEQDCAgAAAA==.',
Yi='Yisiwang:BAAANQADCgcIBwABNQAECgEIAQAOAAAAAA==.',
Yo='Yorick:BAAANQADCggIFQAAAA==.Yorkj:BAABNQAECn8VAAIFAAcKSQhJWABCAQAFAAcKSQhJWABCAQAAAA==.',
Za='Zalthorax:BAAANQAECgUICwABNQAECgkJKwADAMoYAA==.Zatilion:BAABNQAECn8bAAIJAAgKBQ4xtACwAQAJAAgKBQ4xtACwAQAAAA==.Zavage:BAAANQADCgYICgABNQAECgcIIgAQAJESAA==.Zayn:BAAANQAECgUIDAAAAA==.',
Ze='Zedon:BAABNQAECn8eAAMZAAcKIg7CHwBWAQAZAAYKIg7CHwBWAQAYAAQK+BDKMgD9AAAAAA==.Zenki:BAAANQAECgUIBQAAAA==.Zenkî:BAAANQADCgEIAQAAAA==.Zenrune:BAAANQAECgcICgABNQAECggICwAOAAAAAA==.Zephiday:BAAANQAECgMIAwAAAA==.',
Zi='Ziggamoo:BAAANQADCgUICgABNQAECgkJKgADABMeAA==.Ziggashot:BAABNQAECn8qAAIDAAkKEx6XFABKAwADAAkKEx6XFABKAwAAAA==.Zinsus:BAAANQAECgcIBwABNQAECgkJKwADAMoYAA==.',
Zo='Zongchi:BAAANQAECgEIAQAAAA==.Zoomzoom:BAAANQABCgMIAQAAAA==.',
Zu='Zurahahsha:BAABNQAECn8nAAINAAgKsgXAGwCjAQANAAgKsgXAGwCjAQAAAA==.',
['Ðr']='Ðrow:BAABNQAECn8ZAAIXAAgKfQwHMgC5AQAXAAgKfQwHMgC5AQAAAA==.',
['Óx']='Óxy:BAABNQAECn8bAAIWAAcKCAuyHACHAQAWAAcKCAuyHACHAQAAAA==.',
['Ör']='Örc:BAAANQAECgMIAwABNQAECggIGwAJAF8iAA==.',
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
