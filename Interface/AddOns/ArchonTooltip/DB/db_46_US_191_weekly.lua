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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Retribution','Priest-Shadow','Priest-Holy','Shaman-Restoration','Hunter-BeastMastery','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Hunter-Marksmanship','Warrior-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Warrior-Fury','Unknown-Unknown','DemonHunter-Devourer','DeathKnight-Frost','Paladin-Protection','Paladin-Holy','Mage-Frost','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Guardian','DeathKnight-Blood','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Warrior-Arms','Monk-Brewmaster','Priest-Discipline',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abyssara:BAAALgAECgYJDQAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAACLgAFFH8GAAIBAAMJqR+QVQC1AAABAAMJqR+QVQC1AAAuAAQKfxoAAgEACQlPIZoLAD4DAAEACQlPIZoLAD4DAAAA.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAACLgAFFH8GAAICAAMJwBVJBgAMAQACAAMJwBVJBgAMAQAuAAQKfx8ABAIACQmvIe0AAHwDAAIACQmvIe0AAHwDAAMAAQlGBwirADMAAAQAAQkuAiKOAB8AAAAA.Aelusius:BAABLgAECn8tAAIFAAkJTSK4AgCkAgAFAAkJTSK4AgCkAgAAAA==.Aeón:BAAALgAECgcJDAAAAA==.',
Ag='Aggen:BAABLgAECn8YAAIGAAgJsBR8SgCgAQAGAAgJsBR8SgCgAQAAAA==.',
Ak='Akashá:BAAALgADCgUJBQAAAA==.',
Al='Al:BAACLgAFFH8JAAMHAAMJfQs8GADhAAAHAAMJfQs8GADhAAAIAAIJbQQUIABpAAAuAAQKfykAAwcACAnJGEATAOgBAAcACAnJGEATAOgBAAgABwlpEUErAJsBAAAA.Alandarus:BAAALgAECgEJAQAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAABLgAECn8ZAAIGAAYJfBYycgBAAQAGAAYJfBYycgBAAQAAAA==.Allenwalker:BAAALgAECgUJBQAAAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAAALgAECggJEAABLgAECggJIgAJALoYAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQABLgAFFAMJBwAJACseAA==.Ambersoul:BAAALgADCgMJAwAAAA==.Amira:BAAALgAECgcJCAABLgAECgkJGgAKAMkcAA==.',
An='Anixa:BAAALgADCgMJAwAAAA==.Anyi:BAABLgAECn8YAAMLAAYJmAuCQADaAAALAAYJmAuCQADaAAAJAAQJEgKjfwBmAAAAAA==.',
Ao='Aoi:BAABLgAECn8bAAMMAAYJkwqhPQDfAAAMAAYJkwqhPQDfAAANAAEJAABKfQAzAAAAAA==.',
Ar='Arrisia:BAABLgAECn8aAAMKAAYJHRPVYQAoAQAKAAYJHRPVYQAoAQAOAAIJJwS8LwAgAAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8LAAIPAAMJXx+cDgD2AAAPAAMJXx+cDgD2AAAuAAQKfzIAAg8ACQnQI30BAHIDAA8ACQnQI30BAHIDAAAA.Arthedaine:BAACLgAFFH8PAAIQAAMJ/xxZAgARAQAQAAMJ/xxZAgARAQAuAAQKfzAAAhAACQlzI+ACAOMCABAACQlzI+ACAOMCAAEuAAUUAwkLAA8AXx8A.',
As='Asiea:BAAALgADCgQJBAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECgYJBgABLgAECgcJGAAEAFgSAA==.Autumni:BAABLgAECn8cAAIKAAcJCRcBRAB/AQAKAAcJCRcBRAB/AQAAAA==.Auvry:BAABLgAECn8aAAMRAAcJVhkdEAA5AgARAAcJVhkdEAA5AgASAAIJqAktcQAsAAAAAA==.',
Ay='Aymus:BAAALgAECgYJEAAAAA==.',
Az='Azliain:BAAALgAECgcJBgAAAA==.',
Ba='Bahamutfang:BAABLgAECn8ZAAIGAAcJQwe5lwD7AAAGAAcJQwe5lwD7AAAAAA==.Bakala:BAABLgAECn8cAAMTAAYJWRRBNAAqAQATAAYJWRRBNAAqAQAPAAQJUQYcQABRAAAAAA==.Bangbang:BAABLgAECn8qAAIKAAkJqBWgLwDOAQAKAAkJqBWgLwDOAQAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAAALgAECggJEwAAAA==.Belenos:BAAALgADCggJEQABLgADCggJEQAUAAAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAACLgAFFH8GAAIOAAMJHwshEgDKAAAOAAMJHwshEgDKAAAuAAQKfx4AAg4ACQnSE3kqANgBAA4ACQnSE3kqANgBAAAA.Benmaverick:BAABLgAECn8WAAIVAAYJkgqJfADVAAAVAAYJkgqJfADVAAAAAA==.',
Bh='Bhe:BAABLgAECn8ZAAIFAAcJUgu0EQAiAQAFAAcJUgu0EQAiAQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAABLgAECn8aAAIIAAgJFRV/EgABAgAIAAgJFRV/EgABAgAAAA==.',
Bl='Blackbird:BAAALgADCgYJCgAAAA==.',
Bo='Bobe:BAABLgAECn8nAAIPAAgJIhkMDQDNAQAPAAgJIhkMDQDNAQAAAA==.Bordok:BAABLgAECn8UAAIWAAcJowVQEgDVAAAWAAcJowVQEgDVAAAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Bruisewayne:BAAALgADCggJCAAAAA==.Brunco:BAABLgAECn8eAAMKAAgJDh+rGQBAAgAKAAgJDh+rGQBAAgAOAAYJyRNREQDYAAAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAABLgAECn8WAAIIAAYJDhlMGwClAQAIAAYJDhlMGwClAQAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Captplanet:BAABLgAECn8UAAQCAAkJNxIQDQCHAQACAAYJPxUQDQCHAQADAAYJpQaNegDpAAAEAAYJSgxFNwDfAAAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAABLgAECn8eAAIFAAcJESENBgAiAgAFAAcJESENBgAiAgAAAA==.Celiñ:BAACLgAFFH8HAAMXAAMJZxSyCACaAAAXAAMJ7QqyCACaAAAGAAIJ9xNLXwCVAAAuAAQKfyEABAYACQmAHuYbAF0CAAYACAlBIOYbAF0CABcABAnRE6EnAIoAABgAAwnvBGJeAGEAAAAA.Celîn:BAAALgAECgQJBAABLgAFFAMJBwAXAGcUAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAAALgAECgQJBwAAAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIHAAcJdQdKOgAfAQAHAAcJdQdKOgAfAQAAAA==.Cor:BAAALgAECgQJBQAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAAALgAECgYJEAABLgAECgkJLQAFAE0iAA==.Crunky:BAABLgAECn8bAAIMAAYJKRA1NAARAQAMAAYJKRA1NAARAQAAAA==.',
Cu='Cuddleybunni:BAAALgADCgMJAwAAAA==.Cuddlymethod:BAAALgAECgMJBQAAAA==.',
['Có']='Cól:BAABLgAECn8uAAIZAAkJNh5sMgCpAgAZAAkJNh5sMgCpAgAAAA==.',
Da='Dadmike:BAAALgAECgEJAQAAAA==.Dahealzrhere:BAAALgAECgQJBAAAAA==.Dalel:BAABLgAECn8aAAIVAAcJkx9EKADjAQAVAAcJkx9EKADjAQAAAA==.Dameond:BAAALgAECgIJAwAAAA==.David:BAAALgADCgQJBAABLgAECgcJAQAUAAAAAA==.',
De='Deadisdead:BAAALgAECgYJDgAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAAUAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demiurgos:BAABLgAECn8XAAMJAAcJ4x+wFABTAgAJAAcJ4x+wFABTAgAFAAMJeBBdGwCiAAAAAA==.Demonicteli:BAABLgAECn8WAAIaAAkJlxmZEABdAgAaAAkJlxmZEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Dermot:BAABLgAECn8tAAQbAAgJLiN0AwC6AgAbAAcJZCJ0AwC6AgAcAAUJ+iAlWQBVAQAdAAIJCyYHIQBuAAAAAA==.',
Dh='Dhiying:BAAALgAECgYJCgAAAA==.',
Di='Dippindots:BAABLgAECn8dAAMEAAcJlRDVKQAqAQAEAAcJlRDVKQAqAQADAAEJZQGJ7AAVAAAAAA==.Dixmen:BAAALgAFFAEJAQAAAA==.',
Dk='Dkäri:BAAALgAECgYJDQAAAA==.',
Do='Dolemen:BAABLgAECn8hAAIGAAYJVAdOrgDWAAAGAAYJVAdOrgDWAAAAAA==.Domaon:BAABLgAECn8fAAIaAAgJSCF2BgCCAgAaAAgJSCF2BgCCAgAAAA==.Domshammy:BAAALgAECgIJAgABLgAECggJHwAaAEghAA==.Doombunny:BAAALgAECgUJCQABLgAECggJKwAKAG8ZAA==.Doubt:BAAALgAECgYJDAAAAA==.',
Dr='Dranthrax:BAAALgAECgUJDAAAAA==.',
Du='Dullgrim:BAAALgADCgEJAQAAAA==.Dunigan:BAABLgAECn8sAAMGAAgJ0RDnWgB1AQAGAAgJXg/nWgB1AQAXAAYJDg9QGwDoAAAAAA==.Dunstan:BAAALgAECgYJDwAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn8oAAIQAAkJzxDdDwDxAQAQAAkJzxDdDwDxAQAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgcJDAAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ey='Eyeet:BAAALgADCgkJEAAAAA==.',
Fa='Facade:BAAALgAECgQJBQAAAA==.Facepalm:BAAALgAECggJDwAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAAUAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8ZAAIDAAcJJhP3VQBRAQADAAcJJhP3VQBRAQAAAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAABLgAECn8aAAIWAAgJrguECwBDAQAWAAgJrguECwBDAQAAAA==.',
Fi='Fierytotes:BAAALgADCgYJEgAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAABLgAECn8bAAIJAAcJbhV4KADGAQAJAAcJbhV4KADGAQAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn8vAAIJAAkJ3BP1HAAPAgAJAAkJ3BP1HAAPAgAAAA==.Foxmccloud:BAABLgAECn8bAAIJAAYJIR86HQAMAgAJAAYJIR86HQAMAgAAAA==.',
Fr='Fruitloop:BAAALgAECggJEwAAAA==.',
Fu='Fuil:BAAALgADCgUJBQAAAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgEJAQAAAA==.Gellywoo:BAABLgAECn8jAAITAAcJaxiLHgCtAQATAAcJaxiLHgCtAQAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAABLgAECn8YAAIRAAcJMRcdCwDfAQARAAcJMRcdCwDfAQAAAA==.Gooftoo:BAABLgAECn8UAAIDAAcJJx8QLwDwAQADAAcJJx8QLwDwAQAAAA==.',
Gr='Greycie:BAAALgADCgkJEwAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAABLgAECn8bAAIeAAYJkRlWEQBlAQAeAAYJkRlWEQBlAQAAAA==.',
Gy='Gyre:BAAALgAECgQJCgAAAA==.',
Ha='Happyendings:BAAALgAECgcJDQAAAA==.',
He='Helbafx:BAAALgAECgQJCAAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAABLgAECn8XAAIPAAYJyxaqGQAeAQAPAAYJyxaqGQAeAQAAAA==.',
Hu='Hunnee:BAAALgADCgYJCwAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.',
If='Ifearnobeer:BAABLgAECn8kAAILAAgJZQnDNAAPAQALAAgJZQnDNAAPAQAAAA==.',
Ii='Iifelike:BAAALgAECgUJBQABLgAECggJEwAUAAAAAA==.',
In='Inters:BAAALgAECgUJCgAAAA==.',
Ir='Ironspark:BAAALgAECgYJDQAAAA==.',
Is='Isabel:BAACLgAFFH8QAAIDAAQJTwu1IgD5AAADAAQJTwu1IgD5AAAuAAQKfxQAAgMACAnyFy0kACoCAAMACAnyFy0kACoCAAAA.Isaetr:BAAALgAECgEJAQAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jaiantobea:BAABLgAECn8aAAIJAAcJlhMkLACwAQAJAAcJlhMkLACwAQAAAA==.Jake:BAAALgAECgIJAgAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8ZAAINAAkJ7wzYHAB4AQANAAkJ7wzYHAB4AQAAAA==.',
Je='Jessuss:BAAALgAECgcJEwAAAA==.',
Ju='Jude:BAAALgAECgMJBwAAAA==.Juggernàut:BAAALgAECgYJEAAAAA==.Julïeth:BAAALgAECgEJAQAAAA==.Junipermoon:BAAALgADCggJEQAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAACLgAFFH8FAAIDAAMJqQP8MwCjAAADAAMJqQP8MwCjAAAuAAQKfyoAAgMACQnTENgoAMcBAAMACQnTENgoAMcBAAAA.Kalebeesd:BAAALgAECgYJEwAAAA==.Karthdh:BAAALgADCgMJAwABLgADCggJCAAUAAAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8fAAIDAAgJPRTpKgC5AQADAAgJPRTpKgC5AQAAAA==.Kawk:BAABLgAECn8sAAIXAAkJNR+LBAC7AgAXAAkJNR+LBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAABLgAECn8lAAILAAgJ+SP+DgC3AgALAAgJ+SP+DgC3AgABLgAFFAMJBAAUAAAAAA==.',
Ke='Kebob:BAAALgAECggJEwAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8gAAIPAAgJeRyHCAAqAgAPAAgJeRyHCAAqAgAAAA==.',
Ki='Kilo:BAAALgADCgEJAwAAAA==.Kippo:BAECLgAFFH8HAAIZAAQJigURMwDRAAAZAAQJigURMwDRAAAuAAQKfyMAAhkACAmWF0BKAFgCABkACAmWF0BKAFgCAAAA.',
Kl='Klazarth:BAACLgAFFH8HAAIHAAMJMRd5FAAFAQAHAAMJMRd5FAAFAQAuAAQKfx4AAgcACQmpHowNAKoCAAcACQmpHowNAKoCAAAA.',
Ko='Kombat:BAAALgAECgUJDQAAAA==.Korllan:BAAALgAECgEJAQAAAA==.Kossnen:BAAALgAECgYJDQAAAA==.',
Kr='Krelivus:BAAALgAECgUJBgAAAA==.',
Ku='Kuda:BAABLgAECn8bAAIZAAcJQRGhcgBXAQAZAAcJQRGhcgBXAQAAAA==.',
Kw='Kwanu:BAAALgAECgUJBwAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECgcJDAAUAAAAAA==.',
La='Lantern:BAAALgADCgUJBQAAAA==.Larke:BAAALgAECgUJBwAAAA==.Lasa:BAAALgAECgYJBwAAAA==.Lasloo:BAAALgAECgUJEgAAAA==.Laylani:BAAALgAECgMJBAAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8cAAIVAAkJ8Rc7LgBEAgAVAAkJ8Rc7LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgMJBgAAAA==.Lir:BAAALgADCgIJAwAAAA==.Lisan:BAAALgAECggJEwAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lothan:BAAALgADCgkJCQABLgAECgcJGAAEAFgSAA==.',
Lu='Lucien:BAAALgAECgYJDwAAAA==.Luciä:BAABLgAECn8aAAIfAAcJmRG9FwA1AQAfAAcJmRG9FwA1AQAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBwAAAA==.',
Ma='Machoman:BAAALgADCgcJBwAAAA==.Magdeth:BAAALgADCgYJEAAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAAALgAECggJDAAAAA==.Massack:BAAALgAECggJEwAAAA==.Mastik:BAAALgAECgEJAQAAAA==.',
Mc='Mcknight:BAAALgAECgYJBgAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAYAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgAECgEJAQAAAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJBAAAAA==.',
Mu='Muldoinit:BAAALgAECggJEwAAAA==.',
My='Myroslava:BAAALgADCgkJEwAAAA==.',
['Më']='Mërikh:BAAALgADCggJCwABLgAECgUJBQAUAAAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAABLgAECn8UAAIYAAcJtR8EEQBGAgAYAAcJtR8EEQBGAgAAAA==.Nehemia:BAAALgAECgYJEQAAAA==.Nerilestis:BAAALgAECgEJAQAAAA==.Netherrogue:BAABLgAECn8XAAQgAAcJ7xzGBgCrAQAgAAUJgBzGBgCrAQAhAAYJMgz8JAAPAQAiAAIJgxYnEgB+AAAAAA==.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAMJDAAZAAkdAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAFFAMJBwAcAG8TAA==.Nytemayer:BAACLgAFFH8HAAIcAAMJbxOFSwDpAAAcAAMJbxOFSwDpAAAuAAQKfysABBwACQmGIOQOAKMCABwACQl8H+QOAKMCABsAAwmYH4szAOkAAB0AAQkAAC4pAE0AAAAA.',
Ob='Obmakare:BAABLgAECn8bAAICAAYJZw49FgAAAQACAAYJZw49FgAAAQAAAA==.Oboñ:BAAALgAECgYJEgAAAA==.Obsfuyung:BAABLgAECn8hAAINAAcJYhHzJwAnAQANAAcJYhHzJwAnAQAAAA==.',
On='Onkelos:BAAALgAECgEJAwAAAA==.',
Or='Orcc:BAAALgADCggJCQAAAA==.',
Pa='Paley:BAAALgAECgYJBgAAAA==.Palpatine:BAAALgAECgIJAgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.Performance:BAAALgAECgcJCwAAAA==.',
Pi='Pinji:BAAALgAECgIJAgAAAA==.Pinkypoo:BAABLgAECn8dAAMBAAcJ+xhVaABNAQABAAcJXxJVaABNAQAfAAYJvBixIwAjAQAAAA==.',
Pl='Plato:BAABLgAECn8YAAQYAAgJxhjdEwAnAgAYAAgJxhjdEwAnAgAGAAEJ2wHTWgEVAAAXAAEJAAAzSAAAAAAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAABLgAECn8ZAAMbAAcJBxBnDAArAQAbAAcJBxBnDAArAQAcAAEJNgH4HAENAAAAAA==.',
Ps='Psyche:BAAALgADCgkJDgAAAA==.',
Py='Pyrokos:BAACLgAFFH8FAAIZAAMJUBkrUgABAQAZAAMJUBkrUgABAQAuAAQKfyEAAhkACAnsIAtPAK4BABkACAnsIAtPAK4BAAAA.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn8xAAMjAAkJkiHwBgA8AgAjAAkJkiHwBgA8AgATAAIJTQowlQBrAAAAAA==.Quellia:BAACLgAFFH8OAAIYAAQJMh/7EABYAQAYAAQJMh/7EABYAQAuAAQKfxwAAhgACAmTINMMALMCABgACAmTINMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8YAAITAAgJ7BCpLQBNAQATAAgJ7BCpLQBNAQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgAECgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8MAAIZAAMJCR3jTQAPAQAZAAMJCR3jTQAPAQAuAAQKfyUAAhkACAkkJGkSALYCABkACAkkJGkSALYCAAAA.',
Ru='Runningbearr:BAAALgADCgYJBgAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8MAAIGAAQJ5Q9sJwA0AQAGAAQJ5Q9sJwA0AQAuAAQKfyoAAgYACAkEIaIVAOgCAAYACAkEIaIVAOgCAAAA.',
['Rõ']='Rõbb:BAACLgAFFH8HAAIGAAMJVR5nMAAYAQAGAAMJVR5nMAAYAQAuAAQKfywAAgYACQkGIg8JAO0CAAYACQkGIg8JAO0CAAAA.',
Sa='Sabaak:BAABLgAECn8VAAIGAAYJviDIQAC9AQAGAAYJviDIQAC9AQAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAAALgAECgYJEQAAAA==.Saintsnyder:BAAALgAECgkJEQAAAA==.Saithis:BAAALgAECgYJEgAAAA==.Saltycrank:BAAALgADCgYJBgAAAA==.Sandew:BAAALgAECgYJBgABLgAECgYJBwAUAAAAAA==.Sanorasong:BAEBLgAECn8UAAMYAAcJBBrXGQDsAQAYAAcJBBrXGQDsAQAGAAQJbwxZ1gCXAAAAAA==.Saphaa:BAAALgADCgEJAQAAAA==.Sardine:BAAALgAECgMJAwAAAA==.Sarylin:BAAALgAECggJDwAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAABLgAECn8bAAIbAAYJ8ROfDQAYAQAbAAYJ8ROfDQAYAQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgAECgYJBgAAAA==.Sections:BAAALgADCgkJHAAAAA==.Severussnape:BAAALgAECggJEwAAAA==.',
Sh='Shambs:BAACLgAFFH8HAAIJAAMJKx4HIwABAQAJAAMJKx4HIwABAQAuAAQKfxsAAgkACQnPHikGAA8DAAkACQnPHikGAA8DAAAA.Shamrorag:BAAALgAECgcJEwAAAA==.Shinron:BAAALgADCgYJDwAAAA==.Shökan:BAAALgAECgMJAwAAAA==.',
Si='Sighah:BAAALgAECgkJCgAAAA==.Sinensis:BAAALgAECggJEwAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4R5nIADAAgABAAkJ4R5nIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.Sinstab:BAAALgAECggJCAAAAA==.',
Sk='Skadoosh:BAAALgADCgYJCQABLgAECgcJGgAVAJMfAA==.Skarletflame:BAAALgAECgcJEgAAAA==.',
Sl='Slather:BAABLgAECn8aAAIRAAgJcBAKGADVAQARAAgJcBAKGADVAQAAAA==.Slaycie:BAABLgAECn8bAAIZAAYJEBBijQAkAQAZAAYJEBBijQAkAQAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgcJFAAYAAQaAA==.Sorne:BAAALgAFFAMJAwAAAA==.',
Sp='Spaghett:BAABLgAECn8dAAMkAAgJ/xELLQAZAQAkAAgJAg8LLQAZAQANAAYJJhM4LwD+AAAAAA==.Springtotem:BAABLgAECn8YAAIEAAcJWBLoKAAwAQAEAAcJWBLoKAAwAQAAAA==.',
St='Stachel:BAAALgAECgMJBAAAAA==.Stanger:BAAALgAECgcJCQAAAA==.Storaxota:BAAALgAFFAUJAgAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Sugondese:BAABLgAECn8ZAAIeAAcJ0BhXDgCSAQAeAAcJ0BhXDgCSAQABLgAFFAQJEAAhAKUYAA==.Superneo:BAAALgAECgYJBgABLgAFFAMJCgAEAOciAA==.Suvion:BAAALgAECgcJEwABLgAECgkJIgALABMZAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAABLgAECn8WAAIDAAkJ6AveMQCRAQADAAkJ6AveMQCRAQAAAA==.',
Sz='Szadèk:BAAALgAECgYJBwAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8SAAIaAAgJrhRKFQB+AQAaAAgJrhRKFQB+AQAAAA==.',
Ta='Tael:BAABLgAECn8lAAITAAgJoB6BEAAsAgATAAgJoB6BEAAsAgAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAACLgAFFH8KAAIlAAMJRw6XHgDbAAAlAAMJRw6XHgDbAAAuAAQKfyoAAyUACAnuGWgVAPwBACUACAnuGWgVAPwBAAgAAQkFFq57ADoAAAAA.Tattoospyder:BAABLgAECn8aAAIDAAcJTwj1XwDSAAADAAcJTwj1XwDSAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Tessla:BAABLgAECn8iAAMLAAkJExnPFQDoAQALAAkJExnPFQDoAQAJAAIJvggOjwBHAAAAAA==.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAAALgAECggJEwAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgMJAwAAAA==.Thors:BAAALgAECgcJEQAAAA==.Thundertoes:BAAALgAECggJEwAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgADCgcJFAAAAA==.Timmy:BAAALgAECgIJBAABLgAECgYJDgAUAAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAAALgAECgcJEwAAAA==.Torgoth:BAABLgAECn8ZAAIFAAcJUxHQDgBTAQAFAAcJUxHQDgBTAQAAAA==.Toshido:BAAALgAECgYJEAAAAA==.',
Tr='Traetor:BAAALgAECggJEwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAAALgAECgYJDwAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ub='Ubully:BAAALgADCgQJBAAAAA==.',
Ul='Ultane:BAAALgAECgUJDAAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgADCgkJFQAAAA==.Valastae:BAAALgAECgYJDQAAAA==.Valiantaine:BAABLgAECn8vAAMGAAkJXiGlIwAxAgAGAAkJXiGlIwAxAgAYAAkJgg2xPQCCAQABLgAFFAMJCgAVAPgSAA==.Valiantaint:BAACLgAFFH8KAAIVAAMJ+BI6OgDyAAAVAAMJ+BI6OgDyAAAuAAQKfyIAAhUACAn7HmstAEgCABUACAn7HmstAEgCAAAA.Valiantrain:BAAALgAECgEJAgABLgAFFAMJCgAVAPgSAA==.Valyulon:BAAALgADCgMJAwABLgAFFAMJCgAVAPgSAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Vecna:BAAALgAECgUJBQABLgAECgYJEAAUAAAAAA==.Velherun:BAAALgAECggJDQAAAA==.Vendeldh:BAABLgAECn8sAAIVAAkJuCPUEgDpAgAVAAkJuCPUEgDpAgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAABLgAECn8XAAIKAAcJmg2jVwBEAQAKAAcJmg2jVwBEAQAAAA==.',
Vi='Virajr:BAAALgAECgYJEAAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAABLgAECn8bAAITAAkJ8wchLABVAQATAAkJ8wchLABVAQAAAA==.Vissiction:BAAALgAECggJDwAAAA==.Vistine:BAABLgAECn8mAAIXAAkJOQkvGwDpAAAXAAkJOQkvGwDpAAAAAA==.Vitez:BAABLgAECn8UAAMbAAgJFAeFFADHAAAbAAgJFAeFFADHAAAcAAEJggFiMgEcAAAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAABLgAECn8UAAIZAAYJhgvwnwADAQAZAAYJhgvwnwADAQAAAA==.Wendy:BAABLgAECn8iAAIJAAgJuhg5JADfAQAJAAgJuhg5JADfAQAAAA==.',
Wi='Win:BAAALgAECgYJBwABLgAECgkJNAAcANAYAA==.Winkster:BAACLgAFFH8MAAIGAAUJdBxOHQBOAQAGAAUJdBxOHQBOAQAuAAQKfysAAgYACQlZJGMGAA4DAAYACQlZJGMGAA4DAAAA.',
Xa='Xanadu:BAABLgAECn8mAAIlAAkJ4RpcCgB5AgAlAAkJ4RpcCgB5AgAAAA==.Xarinia:BAABLgAECn8cAAMSAAgJMg56OgDvAAASAAgJMg56OgDvAAARAAUJ4weUMQDjAAAAAA==.',
Xd='Xdynasty:BAACLgAFFH8QAAIhAAQJpRjxDQBRAQAhAAQJpRjxDQBRAQAuAAQKfycAAyEACQkBJCwMANUCACEACQn+IywMANUCACAABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn80AAQcAAkJ0BhFNwC+AQAcAAkJJRVFNwC+AQAbAAUJGRR5JQAxAQAdAAEJAABDMAA9AAAAAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.',
Za='Zabazz:BAABLgAECn8fAAMJAAkJ0w+SLQCoAQAJAAkJ0w+SLQCoAQALAAEJggGYjAASAAAAAA==.Zabenir:BAABLgAECn8UAAIHAAcJXBimHgB8AQAHAAcJXBimHgB8AQAAAA==.Zané:BAAALgAECgEJAgAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgkJCgAAAA==.',
Zi='Ziria:BAAALgADCgQJBAAAAA==.',
['Ðe']='Ðexter:BAAALgAECgYJBwAAAA==.',
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
