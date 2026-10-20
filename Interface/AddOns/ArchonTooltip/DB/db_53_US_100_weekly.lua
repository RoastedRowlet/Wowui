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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Hunter-Marksmanship','Paladin-Holy','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Druid-Balance','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Warlock-Demonology','Warlock-Affliction','Mage-Arcane','Rogue-Subtlety','Warrior-Fury','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Priest-Holy','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Monk-Brewmaster','Paladin-Protection','Rogue-Outlaw','Mage-Frost','Priest-Discipline','Warlock-Destruction','Druid-Feral','Monk-Mistweaver',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aamodar:BAABNQAECn8ZAAIBAAYKhg9gugCPAQABAAYKhg9gugCPAQAAAA==.',
Ab='Abadon:BAAANQAFFAIIAgAAAA==.',
Ac='Acathisia:BAAANQAECgEIAQAAAA==.',
Ad='Adino:BAABNQAECn8dAAIBAAcK6Ao4UgAMAQABAAcK6Ao4UgAMAQAAAA==.Adorabell:BAAANQAECgYICgABNQAFFAYIGAABAK8TAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAABNQAECn8oAAICAAgK6xo4CAC5AQACAAgK6xo4CAC5AQAAAA==.Aeryn:BAACNQAFFH8MAAIDAAUKhh0vBgD7AAADAAUKhh0vBgD7AAA1AAQKfzQAAgMACgroIngSAH4DAAMACgroIngSAH4DAAAA.Aerís:BAAANQAECgQICQAAAA==.',
Ag='Aglaia:BAAANQABCggIDAAAAA==.Agrolazor:BAABNQAECn8mAAIEAAoKzhU+HQBYAgAEAAoKzhU+HQBYAgAAAA==.',
Ah='Ahote:BAAANQAECggIAwAAAA==.Ahtee:BAABNQAECn8gAAIDAAoKcQ+UoQDeAQADAAoKcQ+UoQDeAQAAAA==.',
Al='Alara:BAAANQAECgEIAQAAAA==.Albarino:BAAANQADCgYIBgAAAA==.Algodon:BAABNQAECn8WAAIDAAgKNRHdYwD+AAADAAgKNRHdYwD+AAABNQAECgoKPQABACciAA==.Alseena:BAAANQAECgQIBgAAAA==.',
Am='Amun:BAAANQADCgIJAgAAAA==.',
An='Andenarras:BAAANQAECgMIAwABNQAECgUIDwAFAAAAAA==.Anthais:BAAANQAECgMIAwAAAA==.Anvar:BAACNQAFFH8GAAIBAAMKwQ2PEQB+AAABAAMKwQ2PEQB+AAA1AAQKfzIAAwEACgomHlUpAHUBAAYACAqiDn81AKIBAAEACgomHlUpAHUBAAAA.',
Ar='Arathion:BAABNQAECn8fAAIHAAgKxxjsSABDAgAHAAgKxxjsSABDAgAAAA==.Arcanemommy:BAAANQAECggIBAAAAA==.Archistrate:BAAANQADCgQIBAAAAA==.Ariandra:BAAANQADCggICAABNQAECggIEgAFAAAAAA==.Arianrhod:BAABNQAECn8aAAIIAAkKISEnCABNAwAIAAkKISEnCABNAwAAAA==.Artamir:BAAANQABCgYIBgAAAA==.Arx:BAABNQAECn8fAAMJAAgKrSD5EQAHAgAKAAgKZheGhwAJAgAJAAcKrSD5EQAHAgAAAA==.',
As='Ashaldrin:BAAANQAECgEIBAAAAA==.Ashleyk:BAAANQAECgEIAQAAAA==.Aska:BAAANQADCgIIAgAAAA==.',
At='Atrumdeus:BAACNQAFFH8HAAIDAAMKxgmFHQC6AAADAAMKxgmFHQC6AAA1AAQKfzoAAgMACgpWGXFhAHUCAAMACgpWGXFhAHUCAAAA.',
Au='Audiamer:BAABNQAECn8kAAILAAkKfQjfIADnAAALAAkKfQjfIADnAAAAAA==.Aufsela:BAAANQAECgEIAgABNQAECggIEgAFAAAAAA==.',
Az='Azureshal:BAAANQAECggIEgAAAA==.',
Ba='Babydragon:BAABNQAECn8lAAIMAAoKyhGBGAA1AgAMAAoKyhGBGAA1AgAAAA==.Babysaja:BAAANQAECgcIDgAAAA==.Bangerz:BAAANQAECgcIDwAAAA==.Bannann:BAABNQAECn8eAAMNAAgKCR9MLQCtAgANAAgKCR9MLQCtAgAOAAEKAABeTgEnAAAAAA==.Baojai:BAAANQAFFAEIAQAAAA==.',
Be='Beaksbigdk:BAABNQAECn8nAAQPAAkK1ySZFQANAwAPAAkKACOZFQANAwAQAAQK1SSFSQCWAQARAAEKYyU3sABrAAAAAA==.Beefÿfridge:BAAANQADCggIFgAAAA==.Belfegor:BAAANQAECgcIDAAAAA==.Belldia:BAACNQAFFH8YAAIBAAYKrxPBAgBGAQABAAYKrxPBAgBGAQA1AAQKfzYAAgEACgp0IQcUAE4DAAEACgp0IQcUAE4DAAAA.Belphaegor:BAABNQAECn8nAAMSAAkKoBbQBADDAQASAAkKoBbQBADDAQALAAUKpg0ycAAJAQAAAA==.Beni:BAABNQAECn8YAAIKAAkKwhamSAAPAQAKAAkKwhamSAAPAQAAAA==.Beniaru:BAABNQAECn8fAAITAAkKUxrQFACjAQATAAkKUxrQFACjAQAAAA==.Bennyflipz:BAAANQAECgQIBwAAAA==.',
Bi='Bigmuzz:BAAANQAECgEIBQAAAA==.Bigobuffalo:BAAANQAECgUIBAAAAA==.Bigsneaki:BAAANQADCgUIBQAAAA==.',
Bl='Blightedmilk:BAAANQAECgUIEAABNQAECgoKNwAUABwfAA==.Bloopmasta:BAAANQAECggICwAAAA==.Blufox:BAABNQAECn8qAAMDAAoKExiYDQASAgADAAkK+xqYDQASAgAHAAIKQQASqwAEAAAAAA==.',
Bo='Bobfresh:BAABNQAECn9CAAIOAAoKxiSoBwCrAwAOAAoKxiSoBwCrAwAAAA==.Bootwitdafur:BAAANQADCggIEAAAAA==.Bowtugger:BAAANQAECgQIBAAAAA==.',
Br='Bracks:BAAANQAECgIIAgAAAA==.Braps:BAAANQAECgIIAgAAAA==.Brett:BAAANQAECgMIAwAAAA==.Brighamyoung:BAAANQAECggIAgAAAA==.Broherum:BAAANQAECgEIAQAAAA==.Bronzetusk:BAAANQAECgEIAgAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYIDAAAAA==.Buc:BAAANQADCgIIBAAAAA==.Buckbeak:BAAANQADCggICAABNQAECgkJJwAPANckAA==.Busting:BAABNQAECn8oAAIVAAoKhyH3DQD6AQAVAAoKhyH3DQD6AQAAAA==.',
By='Byusoaker:BAAANQABCgEIAQABNQAECggIFwAWAJEOAA==.',
['Bà']='Bàhamut:BAAANQAECgQICQAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Camellieva:BAAANQAECgUICQABNQAECggIHQACAAwfAA==.Captchaos:BAAANQAECgYICgAAAA==.Carritha:BAAANQAECgMIAwABNQAECgMICgAFAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAABNQAECn8qAAIXAAgKnhL3BABdAQAXAAgKnhL3BABdAQAAAA==.',
Ch='Charlixchix:BAAANQADCggICAABNQAECggIFwAWAJEOAA==.Chimneybones:BAABNQAECn8ZAAIKAAoKHworWQDnAAAKAAoKHworWQDnAAAAAA==.Chizz:BAABNQAECn8fAAIVAAkKKgvL0wDfAQAVAAkKKgvL0wDfAQAAAA==.Chriswong:BAAANQAECggIDQAAAA==.Chronoslicer:BAAANQABCgIIAgAAAA==.Chá:BAAANQADCggIEAABNQAECgkJLwAPANckAA==.',
Cl='Clairebenet:BAABNQAECn81AAMYAAoKzRxOAACkAgABAAkK5R2uMADaAgAYAAoKfhZOAACkAgAAAA==.Claymoor:BAAANQAECgQIBAAAAA==.Cleph:BAAANQAECgMICQAAAA==.Clumzylock:BAAANQAECgcIEwABNQAECgoKWwARAOEWAA==.Clumzyninja:BAABNQAECn9bAAIRAAoK4RbPIQCnAgARAAoK4RbPIQCnAgAAAA==.',
Co='Coolbreez:BAAANQAECgcICgAAAA==.Coolynn:BAAANQAECgMJBgAAAA==.Corl:BAAANQADCgIJAgAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.Creams:BAAANQAECgIIAgABNQAECgIIAwAFAAAAAA==.Crew:BAAANQADCggICgAAAA==.Cronoth:BAAANQAECgUIBQAAAA==.',
Cu='Cumb:BAABNQAECn8VAAMZAAgKQhi+BwDKAQAZAAcKhBe+BwDKAQAaAAIKkBp6JACbAAABNQAECgoKQgAOAMYkAA==.',
Cy='Cyrothea:BAAANQABCgIIAgAAAA==.',
['Cä']='Cäldius:BAAANQAECgYIBwAAAA==.',
Da='Daenerys:BAAANQADCgEIAQAAAA==.Daioh:BAAANQAECgQICQAAAA==.Damacraze:BAABNQAECn8sAAIBAAkKBx/dJwD4AgABAAkKBx/dJwD4AgAAAA==.Danielwu:BAABNQAECn8XAAMUAAkKQAwyGQC/AAATAAkKkwudpgCHAQAUAAMKcxAyGQC/AAAAAA==.Dawigrund:BAAANQAECgYIEgAAAA==.',
De='Deadroar:BAABNQAECn8XAAIRAAgKfxXzTgC5AQARAAgKfxXzTgC5AQABNQAFFAEIAQAFAAAAAA==.Deadtomato:BAABNQAECn8XAAMbAAkK/h8yGAC7AgAbAAgKCSAyGAC7AgAWAAUKsxpxEABTAQAAAA==.Deadwill:BAABNQAECn8ZAAIWAAcKnw43FgAqAQAWAAcKnw43FgAqAQAAAA==.Deadzug:BAAANQAECgUIBQABNQAFFAMIBgABAMENAA==.Deaminase:BAABNQAECn8fAAIVAAkKjxd3SgAnAQAVAAkKjxd3SgAnAQAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAABNQAECn8rAAIcAAoKvxnYLAC1AgAcAAoKvxnYLAC1AgAAAA==.Deggle:BAAANQADCgIIAgAAAA==.Delphoxx:BAAANQAECgYIEwAAAA==.Demidru:BAABNQAECn8YAAILAAcKjxCoTACwAQALAAcKjxCoTACwAQAAAA==.Demonshot:BAAANQADCgUIBAAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgMJBgAFAAAAAA==.Derovia:BAAANQAECggICwAAAA==.Deshojo:BAAANQAECgYIDQAAAA==.Desrook:BAAANQAECgYICgAAAA==.',
Dh='Dhqt:BAAANQAECgEIAgABNQAECgIIAwAFAAAAAA==.',
Di='Diablominion:BAAANQAECgUIBwAAAA==.Divinèhero:BAAANQAECgUIEAAAAA==.',
Do='Doomgirl:BAAANQAECgIIAgAAAA==.Double:BAAANQAECgQIBAAAAA==.Doublelift:BAABNQAECn8sAAMEAAoK9x6MEQDjAgAEAAkKfB6MEQDjAgAcAAQKyxZmqgAXAQAAAA==.',
Dr='Draghula:BAAANQAECgEIAQAAAA==.Dragondeznut:BAAANQADCggJDgAAAA==.Drakisara:BAAANQADCggIBgABNQAECgYIDQAFAAAAAA==.Drakuul:BAAANQADCgUIBwAAAA==.Droni:BAABNQAECn8cAAMdAAcKwRejJwAHAgAdAAcKwRejJwAHAgAZAAEKAADSjgA9AAAAAA==.Drpumper:BAAANQAECgIIAgABNQAECgQIBQAFAAAAAA==.Drummer:BAAANQADCgIIAgAAAA==.Dröbi:BAACNQAFFH8TAAMeAAYKeBZYBACYAQAeAAUK+BZYBACYAQAfAAQKZBZ7BgA3AQA1AAQKfycAAx8ACgqvIS4IAPgCAB8ACQprIS4IAPgCAB4ABAolHm4SAAwBAAAA.',
Du='Duberagon:BAAANQADCgQIBAAAAA==.Dumbledork:BAAANQAECgEIAQAAAA==.Dundundun:BAAANQAECggIEwAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIDAAAAA==.',
['Dâ']='Dârkdune:BAAANQAECggICgAAAA==.',
Eg='Eggdrop:BAAANQAECggIEgAAAA==.Egufro:BAABNQAECn8YAAMHAAoKoA+UIQBgAQAHAAoKoA+UIQBgAQADAAQKkASfuAB6AAABNQAECgoKOQAgAIUYAA==.',
Eh='Ehgu:BAABNQAECn85AAIgAAoKhRjjDQCOAgAgAAoKhRjjDQCOAgAAAA==.',
El='Eleaya:BAAANQADCggIDgAAAA==.Eleverclear:BAAANQADCgYIBgAAAA==.Eliizabeth:BAAANQAECgcIEgAAAA==.Elynnah:BAAANQAECgIIAQAAAA==.Elysiawaters:BAEANQADCggICAAAAA==.',
Em='Emidget:BAAANQAECgEIAgAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMICgAFAAAAAA==.Enyalio:BAAANQADCgYICwAAAA==.',
Ep='Epicaecin:BAAANQAECgEIBAAAAA==.',
Er='Erhmer:BAAANQAECggIBAAAAA==.Ericwym:BAAANQAECgEIAgAAAA==.',
Et='Ethersong:BAAANQADCgIIAgAAAA==.Etom:BAAANQAECggIDAAAAA==.',
Ev='Eviae:BAAANQAECgQICAAAAA==.',
Fa='Faaith:BAAANQADCgIIAgAAAA==.Faceroll:BAAANQAECgIIAgAAAA==.Fairyhunter:BAAANQAECgQICAAAAA==.Fairymonk:BAAANQAECgQIBwAAAA==.Fatfatfat:BAAANQAECgMIBgABNQAFFAEIAQAFAAAAAA==.Fañgrat:BAABNQAECn8XAAMHAAkKixfJPwBlAgAHAAkKixfJPwBlAgADAAQKGQevSQGqAAABNQAECgIIAwAFAAAAAA==.',
Fe='Femboyluvr:BAABNQAECn8UAAIKAAgKMhCFOQA0AQAKAAgKMhCFOQA0AQAAAA==.',
Fi='Filumena:BAAANQADCggIFQAAAA==.Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flameblue:BAAANQADCgQIBAAAAA==.Flandia:BAABNQAECn8gAAIBAAgKLxwQIgCPAQABAAgKLxwQIgCPAQAAAA==.Flex:BAAANQAECgQIBAAAAA==.Floppiterry:BAABNQAECn8bAAIBAAYKow4ZwwB8AQABAAYKow4ZwwB8AQAAAA==.Floppyterri:BAAANQADCgYIBgAAAA==.Floppyterry:BAAANQAECgIIAgAAAA==.Flow:BAABNQAECn8qAAIhAAoKoxgUCQCTAgAhAAoKoxgUCQCTAgAAAA==.',
Fo='Forduecezero:BAAANQADCgYIBgAAAA==.Fowl:BAABNQAECn8kAAIdAAkKzhchGgCIAgAdAAkKzhchGgCIAgAAAA==.Foxyshaman:BAAANQAECgQIBQAAAA==.',
Fr='Fricher:BAABNQAECn8cAAIPAAgKxxNBUQDOAQAPAAgKxxNBUQDOAQAAAA==.',
Fy='Fylerianprie:BAAANQAECgIIBQAAAA==.Fyleriansham:BAAANQADCgMIAwAAAA==.',
Ga='Gagli:BAAANQAECgEIAgAAAA==.Galathynius:BAAANQAECgQIBgAAAA==.Galelora:BAAANQADCggICAAAAA==.Ganjja:BAAANQADCggIGAAAAA==.Gawk:BAAANQADCgUICAABNQAECgIIAwAFAAAAAA==.',
Ge='Geneman:BAAANQABCgYIDAAAAA==.Getsyouwet:BAAANQAECgIIAgABNQAECgkJJwAPANckAA==.Getter:BAAANQADCgkJFQAAAA==.',
Gh='Ghettomike:BAAANQAECgQIBAAAAA==.',
Gi='Giny:BAABNQAECn8fAAMOAAgKHhj5XwACAgAOAAcKHhj5XwACAgANAAIKRgFKHAE0AAAAAA==.',
Gl='Glowfungus:BAAANQAECgEIAgAAAA==.',
Go='Gobbledeez:BAABNQAECn8cAAINAAkKmCGIDABcAwANAAkKmCGIDABcAwAAAA==.Gobblez:BAAANQAECgQIBAAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Gosulock:BAAANQAECggICAAAAA==.Govinniuur:BAAANQAECgIJBAAAAA==.',
Gr='Grasfedjones:BAAANQAECgUICgAAAA==.Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAABNQAECn8kAAIZAAkKWhuQFAD4AgAZAAkKWhuQFAD4AgAAAA==.Grue:BAEANQADCggIEAABNQAECgcIGQAOAEIFAA==.Gröthis:BAAANQAECgQIBQAAAA==.',
Gw='Gweilo:BAAANQAECggIBgAAAA==.Gwendilyn:BAAANQAECgIIAgAAAA==.',
Gy='Gyndrinolara:BAAANQAECgMICAAAAA==.',
Ha='Hafadude:BAAANQAECggIAQAAAA==.Hahgottum:BAAANQAECgYIEwAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAABNQAECn8XAAMYAAYKRw4eCwBNAQAYAAYKwAgeCwBNAQABAAUKngt4+wANAQAAAA==.Healgoßyeßye:BAAANQADCgYIBgAAAA==.',
Hi='Hikiru:BAAANQAECggIBgAAAA==.',
Ho='Hollandar:BAAANQADCgcIBwAAAA==.Holyflame:BAAANQAECgEIAQAAAA==.Holypewpewz:BAAANQAECgQICgAAAA==.Holyyshift:BAAANQAECgEJAQABNQAECgQICgAFAAAAAA==.Horhel:BAAANQAECgYIDQAAAA==.Hottstreak:BAAANQADCggICAAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.Hungmao:BAAANQADCggICAAAAA==.Huuron:BAAANQAECgIIBQAAAA==.',
Hy='Hyperiann:BAAANQAECgMIBAAAAA==.Hypnôtoâd:BAAANQAECgEIAQABNQAECgIIAwAFAAAAAA==.',
Ia='Iamfried:BAABNQAECn8oAAILAAoK1BnzHQDaAgALAAoK1BnzHQDaAgAAAA==.',
Ic='Iceyrot:BAAANQAECgEIAgAAAA==.',
Ig='Igran:BAAANQAECgIIBAABNQAECggIEgAFAAAAAA==.',
Ih='Ihatemodels:BAAANQAECgQIBAAAAA==.',
Il='Illidank:BAAANQADCgMIAwAAAA==.Illidigle:BAAANQADCggIDAABNQAECgkJHwAcAKgUAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAABNQAECn8kAAMdAAkKvRwBJQAeAgAdAAgK7RgBJQAeAgAZAAQKvR74TwBZAQAAAA==.Innarius:BAAANQAECgIIAgAAAA==.Intothedark:BAAANQAECggIAgAAAA==.Inviçtus:BAAANQADCgQIBAAAAA==.Inyadraug:BAAANQAECgcIEwAAAA==.',
Ir='Ironheãrt:BAABNQAECn87AAIiAAoKGxzbAgAKAgAiAAoKGxzbAgAKAgAAAA==.Ironjaws:BAAANQAECgUIBwAAAA==.Ironsight:BAAANQAECgMIBAAAAA==.Irontaco:BAAANQAECgMIBQAAAA==.Irsa:BAAANQAECggIEAAAAA==.',
Is='Isaacnewton:BAAANQAECgEIAwAAAA==.',
It='Itai:BAABNQAECn8vAAIPAAkK1yRmAwC+AwAPAAkK1yRmAwC+AwAAAA==.',
Iv='Iverson:BAAANQAECgIIAwAAAA==.',
Iz='Izayam:BAAANQADCgcIBwABNQAECgkJIwAVAHciAA==.',
Ja='Jackk:BAACNQAFFH8ZAAIHAAcKVhmGAwBeAgAHAAcKVhmGAwBeAgA1AAQKfyUAAwcACQpYJJYIAIMDAAcACQpYJJYIAIMDAAMAAgplCeSFAVIAAAAA.Jackks:BAAANQAECgcIEAABNQAFFAcIGQAHAFYZAA==.Jaddix:BAAANQADCgYICwAAAA==.Janzan:BAAANQAECgIIAgAAAA==.Jasmonk:BAABNQAECn8ZAAIIAAgKGQsJMwB+AQAIAAgKGQsJMwB+AQAAAA==.Jaxed:BAAANQAECgEIAgAAAA==.',
Je='Jeeyell:BAAANQADCgUIBQAAAA==.Jellysickle:BAAANQADCgcICAAAAA==.Jemzz:BAABNQAECn8ZAAMBAAoKYAdpWwD2AAABAAkKrgdpWwD2AAAGAAQKigSeKQBpAAAAAA==.',
Ji='Jimmyray:BAAANQAECgEIAQAAAA==.Jinkua:BAAANQAECgIIAwABNQAECggIDAAFAAAAAA==.Jinkz:BAAANQAECgUICgAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIBAAAAA==.Jorhel:BAAANQADCggJDgAAAA==.Joshú:BAAANQADCgEIAQABNQAECggIEgAFAAAAAA==.',
Ju='Judgementàl:BAAANQAECgUIBQABNQAECgoKJQAMAMoRAA==.Judgevis:BAAANQAECgcIEgAAAA==.Jumbles:BAAANQAECgIIAgAAAA==.',
Jy='Jynxy:BAAANQAECgIIBQAAAA==.',
['Já']='Jáydn:BAAANQAECgIIAgABNQAECgkJJQADAKcfAA==.',
['Jø']='Jøshu:BAAANQAECgEIAQABNQAECggIEgAFAAAAAA==.',
Ka='Kaeliis:BAAANQAECgcIEwAAAA==.Kagestrasz:BAAANQAECgEIAQAAAA==.Karrona:BAAANQADCggJDAAAAA==.Kazuu:BAABNQAECn8UAAILAAYKKxYZHgD5AAALAAYKKxYZHgD5AAAAAA==.',
Kb='Kbeckinsale:BAABNQAECn8oAAQWAAkKpR0kCQCgAQAbAAcKjR0CIwBvAgAWAAcKSBskCQCgAQAjAAIKLwbJGABXAAAAAA==.',
Ke='Keelone:BAAANQAECgEIAQAAAA==.Keladun:BAAANQADCgUJDwAAAA==.',
Kh='Khallessi:BAAANQAECgEIAQAAAA==.Kharga:BAAANQAECgcIDwAAAA==.Khonan:BAAANQADCgUIBgABNQAFFAcICwAVADoYAA==.',
Ki='Kiamar:BAAANQAECgYIBwAAAA==.Kidgroove:BAAANQADCggICgAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Kn='Kneecaps:BAAANQADCgcIBwAAAA==.',
Ko='Kolus:BAAANQADCgcIBwAAAA==.Konamy:BAABNQAECn8YAAIVAAgKPBPZdADTAAAVAAgKPBPZdADTAAAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAABNQAECn8WAAIcAAgKkxXSawDbAQAcAAgKkxXSawDbAQAAAA==.',
Kr='Krex:BAAANQADCgEIAQAAAA==.Kriss:BAAANQAECgEIAQAAAA==.Kristeena:BAAANQAECgQIBAAAAA==.Kroldun:BAAANQADCgIIAgAAAA==.Kryptonikk:BAAANQAECgYIEwAAAA==.Krystall:BAAANQADCgEIAQAAAA==.Kröw:BAABNQAECn8pAAIgAAgK0Q99FgAAAgAgAAgK0Q99FgAAAgAAAA==.',
Ku='Kudrix:BAABNQAECn8hAAIIAAkKQB5VDwDuAgAIAAkKQB5VDwDuAgAAAA==.Kurø:BAAANQAECgYIDwAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQAECgMIBAAAAA==.Laurijaydn:BAABNQAECn8lAAIDAAkKpx+pAwDSAgADAAkKpx+pAwDSAgAAAA==.Laurynn:BAAANQAECgEIAwAAAA==.',
Le='Legendaries:BAAANQAECgEIAgAAAA==.Legionremix:BAAANQAECgEIAQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.Levyathan:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQAECgQICAAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgkJHwAcAKgUAA==.Lillina:BAAANQADCgIIAgAAAA==.Littlestarz:BAABNQAECn8VAAINAAcKdxy3SQA8AgANAAcKdxy3SQA8AgAAAA==.Lizzieag:BAEANQADCgcICwABNQAECgcINAABAGQXAA==.',
Ll='Llazz:BAACNQAFFH8MAAIHAAUKxBjbAwCQAQAHAAUKxBjbAwCQAQA1AAQKfxgAAgcACgpvGVg2AIoCAAcACgpvGVg2AIoCAAAA.Llemons:BAAANQAECggIDwABNQAECggIGwAVANoTAA==.',
Lo='Lockinaround:BAAANQAECgEIAQAAAA==.Locknlizzie:BAEBNQAECn80AAIBAAcKZBfzPgA5AQABAAcKZBfzPgA5AQAAAA==.Lohueng:BAAANQADCggIFwAAAA==.Lolblur:BAAANQAECgQIBAAAAA==.Lolhigh:BAAANQAECgEIAwAAAA==.Lootah:BAAANQADCggIGAAAAA==.Loranoth:BAAANQADCggJIAAAAA==.Lovecox:BAAANQADCggIFAAAAA==.',
Lu='Luke:BAABNQAECn8aAAIDAAgK5xa+hQAcAgADAAgK5xa+hQAcAgAAAA==.Luminali:BAABNQAECn8WAAMHAAgK8g1rpAA6AQAHAAcKUAxrpAA6AQADAAQKCw2pPAG/AAAAAA==.Luminari:BAAANQAECggIDQABNQAECggIFgAHAPINAA==.Lunadari:BAAANQAECgIJBQAAAA==.Lunareva:BAABNQAECn8dAAICAAgKDB9NGwBeAgACAAgKDB9NGwBeAgAAAA==.',
Ly='Lyrielle:BAAANQADCgQIBQAAAA==.Lyxon:BAABNQAECn8eAAICAAkKmhRyFAAgAQACAAkKmhRyFAAgAQAAAA==.',
['Læ']='Lænna:BAAANQADCgUJBQAAAA==.',
['Lí']='Lílîth:BAAANQAECgMIAgAAAA==.',
Ma='Machiavellï:BAAANQAECgQIBAAAAA==.Mael:BAAANQADCgQIBwABNQADCggICAAFAAAAAA==.Maeltne:BAAANQADCgcIBgAAAA==.Mafoôza:BAACNQAFFH8HAAIKAAMK8hQdIgDsAAAKAAMK8hQdIgDsAAA1AAQKfxYAAgoACgpBE6uEABACAAoACgpBE6uEABACAAAA.Magicalama:BAACNQAFFH8FAAIVAAIKgQ3DGgCUAAAVAAIKgQ3DGgCUAAA1AAQKfzEAAhUACgqEGMB9AIMCABUACgqEGMB9AIMCAAAA.Magiplex:BAAANQAECgQICAAAAA==.Magnanimity:BAEANQAECgIIBQABNQAECgkJJQABAMUTAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAABNQAECn8bAAIVAAcK2hNX3gDLAQAVAAcK2hNX3gDLAQAAAA==.Makto:BAAANQAECgIIAgAAAA==.Malia:BAAANQAECgUICQAAAA==.Maliciouso:BAAANQAECggIEgAAAA==.Malédiction:BAAANQAECgUICAAAAA==.Manydoor:BAAANQADCgIIAgAAAA==.Mariemaya:BAAANQAECgEIAgAAAA==.Marley:BAABNQAECn8mAAIBAAgKfgg+nADOAQABAAgKfgg+nADOAQAAAA==.Matua:BAAANQAECgUIDgAAAA==.Maximillian:BAAANQAECgQIBAAAAA==.Maymae:BAAANQADCggIFwABNQAECgUIEAAFAAAAAA==.',
Mc='Mcßlood:BAAANQAECggICQAAAA==.',
Me='Meatsheeld:BAAANQAECgYIBgABNQAFFAMIBgABAMENAA==.Meepz:BAAANQAECgEIAQAAAA==.Megadk:BAAANQAECgQIBwABNQAECggIEAAFAAAAAA==.Megamacdin:BAAANQAECggIEAAAAA==.Mendietta:BAABNQAECn8gAAINAAkKIxSgCwAMAgANAAkKIxSgCwAMAgAAAA==.Meridian:BAAANQAECgYIEwAAAA==.',
Mi='Miistral:BAABNQAECn8bAAMHAAcKUBI7egCqAQAHAAcKUBI7egCqAQADAAEKAACrvAEqAAAAAA==.Milkhoof:BAAANQAECgMIBQAAAA==.Mimie:BAAANQAECgUJDAAAAA==.Mistyeva:BAAANQAECgEIAQABNQAECggIHQACAAwfAA==.Miyamoto:BAAANQADCgEIAQAAAA==.Miyoko:BAAANQADCgUIBwAAAA==.',
Mo='Moistooltip:BAABNQAECn8vAAIIAAoK7B82AgBFAgAIAAoK7B82AgBFAgAAAA==.Mokotrize:BAABNQAECn8fAAIiAAgKaRqHFABfAgAiAAgKaRqHFABfAgAAAA==.Mooscifer:BAAANQADCgYIBgAAAA==.Moosh:BAABNQAECn8cAAISAAYKphL0LwAcAQASAAYKphL0LwAcAQAAAA==.Mordred:BAABNQAECn8ZAAIaAAYKvQUcIADGAAAaAAYKvQUcIADGAAAAAA==.Morria:BAAANQADCgIIAgAAAA==.Mouthkisser:BAAANQAECgQIBAAAAA==.',
Mu='Mud:BAAANQAECggIDwAAAA==.Mudslinger:BAAANQAECgcICAAAAA==.Munchies:BAAANQAECggIEgAAAA==.',
My='Myrolan:BAAANQADCgYICgABNQADCgcICwAFAAAAAA==.Myrrha:BAAANQAECgcIBwAAAA==.',
['Mø']='Møønwuu:BAAANQAECgUIDgAAAA==.',
Na='Naarf:BAAANQAECgIIAgABNQAFFAMIBgABAMENAA==.Nanoko:BAAANQAECgIIAgAAAA==.Naora:BAAANQAECgEIAQABNQAECgUJDAAFAAAAAA==.Natedoggydog:BAAANQAECggICAAAAA==.',
Ne='Neckslice:BAACNQAFFH8RAAIOAAcKxxV6AwBvAgAOAAcKxxV6AwBvAgA1AAQKfyEAAg4ACgrnIjMLALoBAA4ACgrnIjMLALoBAAAA.Nemophilist:BAAANQAECgEIAQAAAA==.Neuro:BAABNQAECn8jAAMVAAkKdyL+MwAiAwAVAAkKdyL+MwAiAwAkAAEKFhicQABDAAAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQAECgQIBQAAAA==.Nictamom:BAAANQAECgEIAQAAAA==.Nightfaze:BAAANQADCggIDgABNQAECgYIDQAFAAAAAA==.Nightnite:BAAANQAECgEIAQAAAA==.Nij:BAAANQAECgEIAQAAAA==.Nirri:BAAANQAECgUIBwAAAA==.Nitefall:BAABNQAECn8YAAIBAAkKgxN/SwAcAQABAAkKgxN/SwAcAQAAAA==.Nithon:BAAANQAECgUIBwAAAA==.',
No='Nocando:BAABNQAECn8fAAIcAAkKqBSHSgBGAgAcAAkKqBSHSgBGAgAAAA==.Notadk:BAAANQAECgYIDgAAAA==.Nott:BAAANQAECgEJAQAAAA==.Noturbudpal:BAAANQADCgQIBgABNQAECgoKWwARAOEWAA==.',
Nu='Nuriel:BAAANQADCgQIBAAAAA==.',
Ny='Nylinuya:BAAANQAECgUIDQABNQAECgoKNwAUABwfAA==.Nywen:BAAANQADCgUIBQAAAA==.',
Ob='Obsydia:BAAANQADCgcIBwAAAA==.',
Oc='Occulus:BAAANQAECgEIAQAAAA==.',
Ok='Okowilly:BAAANQADCggIDQAAAA==.',
Ol='Oline:BAABNQAECn8VAAITAAkKySGAIgD6AgATAAkKySGAIgD6AgAAAA==.',
On='Onijunk:BAAANQADCgQIBAAAAA==.',
Oo='Oonaki:BAAANQAECggIEwAAAA==.',
Or='Orchideva:BAAANQAECgQIBAABNQAECggIHQACAAwfAA==.Oriphiel:BAAANQAECgUIDgAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAABNQAECn8VAAMPAAYKNwj9hQAJAQAPAAYKGQj9hQAJAQAQAAUKKwUWhgCYAAAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgUIBwAAAA==.Paradoxx:BAABNQAECn8rAAIkAAoK/SO5AgA0AwAkAAoK/SO5AgA0AwAAAA==.',
Pe='Pestelince:BAAANQADCggIDQAAAA==.',
Ph='Phelefica:BAAANQAECgQIBQAAAA==.Phreyja:BAAANQADCgcICAAAAA==.Phylgon:BAABNQAECn8gAAMcAAgKyhDRHgCKAQAcAAgKyhDRHgCKAQAEAAEKAAAJlgANAAAAAA==.',
Pl='Pleblords:BAAANQAECgEIAQAAAA==.',
Pm='Pmac:BAAANQAECgYICwABNQAECggIEAAFAAAAAA==.',
Po='Poggrin:BAAANQAECgEIAQAAAA==.Pogrin:BAAANQAECgQICwAAAA==.Pointybrows:BAAANQAECgQICQAAAA==.',
Pr='Protect:BAAANQAECgEIAgAAAA==.Pryona:BAAANQAECgEIAQABNQAECgQIBwAFAAAAAA==.',
Pu='Putrescence:BAAANQAECgIIAgAAAA==.',
Pw='Pwnhubb:BAAANQADCgQIBAAAAA==.',
Py='Pyràbànks:BAAANQAECgEIAQAAAA==.',
Qu='Quelestraza:BAABNQAECn8hAAMMAAgKwBV9AwDUAQAMAAgKwBV9AwDUAQAfAAEKAACRPgAvAAAAAA==.Quikkmex:BAAANQAECgQIBwAAAA==.',
Ra='Rabbit:BAAANQADCgQIBAAAAA==.Raewyck:BAABNQAECn8lAAIBAAoKrQ7ieQAbAgABAAoKrQ7ieQAbAgAAAA==.Raginbull:BAABNQAECn8oAAMJAAgKjxkWCAA1AQAJAAgKjxkWCAA1AQAKAAIK3QYDvwA9AAAAAA==.Ragingmaze:BAABNQAECn8hAAQRAAgKYxLUTQC/AQARAAgKYxLUTQC/AQAPAAgKsgTjfwAdAQAQAAIKQAWzngBTAAAAAA==.Rainburrow:BAABNQAECn8XAAMhAAkKHhIVEwCyAQAhAAYKuhcVEwCyAQAIAAMKpAofHwCzAAAAAA==.Raptormortis:BAAANQAECgQIBwAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Reinitia:BAAANQAECgEIAgAAAA==.Reinnii:BAAANQAECgQIBAAAAA==.Reinslight:BAAANQAECgEIAQAAAA==.Resurrection:BAAANQAECgIIAwAAAA==.Retana:BAABNQAECn8qAAIDAAkKmx5vNwBbAQADAAkKmx5vNwBbAQAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAABNQAECn8ZAAIgAAYKIga5IgAwAQAgAAYKIga5IgAwAQAAAA==.',
Ri='Rickypeepee:BAABNQAECn8eAAIDAAgK+B4PRADIAgADAAgK+B4PRADIAgAAAA==.Rider:BAAANQAECgEIAQAAAA==.Rigatoni:BAAANQAECgMIAwAAAA==.Rizzlybear:BAAANQAECgIIAQABNQAECgIIAQAFAAAAAA==.',
Ro='Roastedz:BAAANQAECgcIEwAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQAECgUICwAAAA==.Rorthu:BAAANQAECgIIAgAAAA==.',
Ru='Rukélie:BAAANQAECgIIAgAAAA==.',
Ry='Ry:BAAANQAECggIEgAAAA==.Ryanna:BAABNQAECn8bAAIVAAgKXgh6MwBYAQAVAAgKXgh6MwBYAQAAAA==.',
Sa='Saevio:BAABNQAECn8hAAMQAAcKHhIZIQAgAQAQAAcKHhIZIQAgAQARAAQKqhCyigDWAAAAAA==.Sajin:BAAANQAECgMIBAAAAA==.Salvader:BAABNQAECn8dAAIGAAgKuRTuJgAUAgAGAAgKuRTuJgAUAgAAAA==.Sanctus:BAAANQAECgEIAQAAAA==.Sashimi:BAACNQAFFH8GAAMQAAIKsQyjCQCJAAAQAAIKsQyjCQCJAAAPAAEK6wNfJAA7AAA1AAQKfyUAAxAACgomG6wXAM0CABAACQpfHKwXAM0CAA8ABQo3DhQmAM4AAAAA.Sataves:BAAANQABCgMIAwAAAA==.Satharis:BAAANQAECgUICQAAAA==.',
Sc='Scarlet:BAAANQAECgQIBgAAAA==.Scarllett:BAABNQAECn8aAAMNAAgK9gzppAAqAQANAAcKZwvppAAqAQAOAAYKnBGJtgAlAQAAAA==.Scrubiclese:BAAANQADCgQIBAAAAA==.Scrytearia:BAAANQAECgEIAQAAAA==.',
Se='Seldaren:BAAANQAECgMIBgAAAA==.Selfward:BAAANQAECgQICgAAAA==.Selrina:BAAANQAECgUIBgAAAA==.Seran:BAAANQAECgcIDwAAAA==.Serenade:BAAANQAECgYIDwAAAA==.Seviana:BAABNQAECn8ZAAIHAAoK3R47FwAfAwAHAAoK3R47FwAfAwABNQAFFAYIHQAMAIAmAA==.Sevie:BAACNQAFFH8dAAIMAAYKgCb1AQCnAgAMAAYKgCb1AQCnAgA1AAQKfzUAAgwACgqTJNEBAKsDAAwACgqTJNEBAKsDAAAA.',
Sh='Shabbyy:BAAANQADCgUICwABNQAECgQIBwAFAAAAAA==.Shadowpump:BAABNQAECn8dAAQEAAcKuRSrOABgAQAEAAYKBxGrOABgAQAcAAUKvhb9mgBEAQAlAAEKzQsDLAAsAAAAAA==.Shalada:BAAANQADCgUIBQAAAA==.Shamsel:BAABNQAECn8jAAIEAAgKShC9BwB5AQAEAAgKShC9BwB5AQAAAA==.Shellack:BAAANQAECgEIAgAAAA==.Shinnz:BAABNQAECn8+AAMDAAoKIhqYBgB/AgADAAoKIhqYBgB/AgAHAAMK8QCJHQE5AAAAAA==.Shockcaller:BAAANQAECgYIDQAAAA==.Shockingnut:BAAANQAECgUICwAAAA==.Showtooltip:BAAANQAECgMIBAABNQAECgoKLwAIAOwfAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAAANQAECgcIEQABNQAECgIIAwAFAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAABNQAECn8jAAMBAAkKAxvPGwCoAQABAAkKAxvPGwCoAQAYAAEKqBJyEgBAAAAAAA==.Simmara:BAAANQAECgMICgAAAA==.Sinh:BAAANQAECgEIAQAAAA==.Sip:BAAANQAECgEIAgAAAA==.',
Sk='Skapelijones:BAAANQAECgIIAwAAAA==.Skipper:BAAANQAECgEIAgAAAA==.Skylinelol:BAAANQAECggIDAAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIBAAFAAAAAA==.',
Sm='Smallcurse:BAAANQAECgYICwAAAA==.Smallighting:BAABNQAECn8wAAQNAAoKJREFYADuAQANAAoKJREFYADuAQAgAAQKgRtsIwAlAQAOAAQKpxM30ADzAAAAAA==.Smokiemcpot:BAAANQAECgMIAgAAAA==.',
So='Solanthis:BAAANQAECgEJAQAAAA==.Solstica:BAABNQAECn8XAAMlAAYKvh64AAAJAgAlAAYKvh64AAAJAgAEAAEKAADEjgAcAAAAAA==.',
Sp='Spiritualone:BAABNQAECn8aAAIiAAYKPxXlLAB2AQAiAAYKPxXlLAB2AQAAAA==.',
Sq='Sqwaat:BAAANQAECgIJAwAAAA==.',
St='Steelrib:BAABNQAECn8aAAIRAAYKNAVViADdAAARAAYKNAVViADdAAAAAA==.Stonystark:BAAANQAECgUICQAAAA==.Straam:BAACNQAFFH8JAAINAAQKawVKCQD1AAANAAQKawVKCQD1AAA1AAQKf0QAAw0ACgqbGLYUAK4BAA0ACgqbGLYUAK4BAA4ABgqkEKqfAFcBAAAA.Strizzle:BAEBNQAECn8ZAAIOAAcKQgUwpwBGAQAOAAcKQgUwpwBGAQAAAA==.Stupidity:BAAANQADCggICAAAAA==.Støney:BAAANQAECgQJBAAAAA==.',
Su='Subatronic:BAACNQAFFH8fAAIRAAcKvSQiAgCOAgARAAcKvSQiAgCOAgA1AAQKfywAAhEACgqOJoIBAN4DABEACgqOJoIBAN4DAAAA.Subfractal:BAAANQADCgYIBgABNQAFFAcIHwARAL0kAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Sy='Sylthara:BAABNQAECn8ZAAQNAAYKuxIjkQBdAQANAAYKuxIjkQBdAQAOAAMKowEqkQA4AAAgAAEKAABhPAASAAAAAA==.Syrothea:BAAANQADCgUJBQAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAABNQAECn8XAAIKAAcKjBNGSQANAQAKAAcKjBNGSQANAQAAAA==.Takki:BAAANQAECggIEQAAAA==.Talethia:BAAANQAECgUIEAAAAA==.Tamsîn:BAABNQAECn8uAAIUAAoKohemAwC3AgAUAAoKohemAwC3AgAAAA==.',
Tb='Tbonez:BAAANQADCgIIAgABNQAECgYIGgARADQFAA==.',
Te='Teech:BAAANQADCggIIAAAAA==.Teinuya:BAABNQAECn83AAMUAAoKHB+SAAAoAgAUAAkKmx2SAAAoAgAmAAUK/SLbDwAAAgAAAA==.Tenderfiddle:BAAANQADCgEIAQAAAA==.Tenderloinz:BAAANQAECgEIAQAAAA==.Tenochitilan:BAABNQAECn8WAAMNAAgKUw7XnQA8AQANAAcKdwvXnQA8AQAOAAIK6w0cEgFoAAAAAA==.',
Th='Thedon:BAAANQAECgEIAQAAAA==.Theocracy:BAAANQAECgQIDQAAAA==.Thoorz:BAAANQAECgIIAwAAAA==.Thorimeir:BAAANQAECgQIBAAAAA==.Thorzy:BAAANQAECggIEQABNQAECgIIAwAFAAAAAA==.Thraxacious:BAABNQAECn84AAInAAoKqhzrAABmAgAnAAoKqhzrAABmAgAAAA==.Thulsadoomm:BAAANQAECgUIDwAAAA==.Thundermay:BAAANQAECgUIEAAAAA==.',
Ti='Tiduss:BAABNQAECn8WAAIJAAUKMQupLADSAAAJAAUKMQupLADSAAAAAA==.Tigó:BAAANQAECgcIBgAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAABNQAECn8aAAIoAAYKAhvXGgDUAQAoAAYKAhvXGgDUAQAAAA==.Timorrow:BAAANQADCgUIBwAAAA==.Tinkerbel:BAABNQAECn8kAAIHAAkKIxxYNQCPAgAHAAkKIxxYNQCPAgAAAA==.Tinkerbella:BAAANQAECgQIBQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAFFAYIGAABAK8TAA==.Tireliaa:BAAANQADCgUIBgAAAA==.',
To='Tohsaka:BAAANQADCgQICQAAAA==.Torsin:BAAANQADCgIIAgAAAA==.Totamic:BAAANQAECgQIBAAAAA==.',
Tr='Trafalgor:BAAANQAECgQICAAAAA==.Trafalgour:BAAANQAECgEIAgAAAA==.Trazen:BAAANQAECgEIAQAAAA==.Tribulationz:BAAANQADCgUIBQABNQAECgUIDwAFAAAAAA==.Triplebolt:BAAANQAECgMIAwAAAA==.Try:BAAANQAECggIBQABNQAECggIEgAFAAAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAABNQAECn8dAAMKAAgKKg5pnQDTAQAKAAgKKg5pnQDTAQAJAAQK8AUlMwCeAAAAAA==.Tsurinoya:BAAANQAECgIIAgAAAA==.',
Tu='Tundal:BAAANQAECgQIBwAAAA==.',
Ty='Tydz:BAAANQAECgEIAgABNQAFFAUIDwAHAOAQAA==.Tyylerdurden:BAAANQAECgEIBQAAAA==.',
Ua='Uafraidofme:BAAANQAECgMIBAAAAA==.',
Ud='Uddermishap:BAEANQADCgYIBgABNQAECgkJJQABAMUTAA==.Uddertrouble:BAEBNQAECn8lAAIBAAkKxRM3GAC5AQABAAkKxRM3GAC5AQAAAA==.',
Ul='Ulfgrim:BAAANQADCgYIDAAAAA==.',
Un='Unholytiran:BAAANQAECgUICwAAAA==.',
Ur='Urmada:BAABNQAECn8dAAIkAAgKXBGcDADvAQAkAAgKXBGcDADvAQAAAA==.Urmami:BAABNQAECn8UAAITAAgK8hKZeAD5AQATAAgK8hKZeAD5AQAAAA==.',
Ut='Utterlyaloof:BAAANQADCgcIBwAAAA==.',
Uz='Uzui:BAAANQAECgIIAwAAAA==.',
Va='Valyne:BAAANQAECgQIBQAAAA==.Vampire:BAABNQAECn8cAAIdAAgKgB8FEQDnAgAdAAgKgB8FEQDnAgAAAA==.Vampyre:BAABNQAECn8VAAIRAAkKlhuJLQBgAgARAAkKlhuJLQBgAgAAAA==.Vanadie:BAAANQAECgIIAgAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Varekth:BAAANQADCgMIAwAAAA==.Vargmal:BAAANQAECgUIBQAAAA==.',
Vi='Virala:BAAANQAECgIIAwAAAQ==.Visenya:BAAANQAECgMIBQAAAA==.Visquake:BAAANQAECgIICAAAAA==.Vitamin:BAAANQADCgcIBwABNQAECgcIGAADAH8fAA==.Vitaminn:BAABNQAECn8YAAMDAAcKfx9fdQBDAgADAAcKfx9fdQBDAgAHAAEKIQOhKQEsAAAAAA==.',
Vl='Vlaen:BAAANQAECgQIBQAAAA==.',
Vo='Votum:BAAANQADCgkJFgAAAA==.',
Vy='Vyrisa:BAAANQAECgEIAgAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Wasabii:BAAANQAECgYICgAAAA==.',
Wh='Whisa:BAABNQAECn8ZAAIcAAoKWBgSCwAzAgAcAAoKWBgSCwAzAgAAAA==.White:BAAANQADCggICAABNQAFFAcIEQAOAMcVAA==.',
Wi='Wildwolff:BAAANQADCgUIBQAAAA==.Wilhedin:BAABNQAECn8rAAIKAAgKKCQVJgAhAwAKAAgKKCQVJgAhAwAAAA==.Willowwind:BAAANQAECgMIBAABNQAECgkJGQAoAGUeAA==.Wing:BAEANQAFFAMIBAAAAA==.',
Wo='Wolfblade:BAAANQADCgQJBQAAAA==.Worm:BAACNQAFFH8QAAIKAAcKKxnXBgBUAgAKAAcKKxnXBgBUAgA1AAQKfy8AAgoACgpJII4YAKQBAAoACgpJII4YAKQBAAAA.',
Wu='Wulfnbolt:BAAANQAECgUJCwAAAA==.',
Ww='Wwoman:BAAANQAECgIIAgAAAA==.',
Wy='Wyon:BAAANQAECgYIHwAAAQ==.',
Ya='Yasnah:BAAANQADCggJEgAAAA==.',
Yu='Yunahpabo:BAABNQAECn8vAAIKAAoKrxsFCwAPAgAKAAoKrxsFCwAPAgAAAA==.Yurna:BAAANQAECgEIAQAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQAECgUICgAAAA==.Zanikan:BAAANQAECggICQAAAA==.Zankuza:BAAANQAECggIAwAAAA==.Zathara:BAABNQAECn84AAInAAoKQhCYDgAqAgAnAAoKQhCYDgAqAgAAAA==.',
Zi='Ziki:BAAANQAECgEIAgAAAA==.',
Zo='Zodiac:BAABNQAECn8eAAIKAAgKbBVFTQAEAQAKAAgKbBVFTQAEAQAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQAECgUIBwAAAA==.Zuluk:BAABNQAECn8WAAMBAAcKGxQRkwDjAQABAAcKGxQRkwDjAQAGAAMK2wPAbgB2AAAAAA==.',
['Zö']='Zörö:BAABNQAECn8wAAMPAAgKpxXuXQCYAQAPAAcKQBXuXQCYAQARAAgKbQa+bABBAQAAAA==.',
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
