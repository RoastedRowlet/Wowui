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

local lookup = {'Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Monk-Mistweaver','Shaman-Elemental','Hunter-BeastMastery','Druid-Balance','Unknown-Unknown','Paladin-Holy','Evoker-Devastation','Mage-Arcane','DeathKnight-Blood','DeathKnight-Frost','Evoker-Preservation','Druid-Feral','Hunter-Marksmanship','Paladin-Retribution','Warrior-Arms','Monk-Windwalker','Priest-Shadow','Paladin-Protection','Warrior-Protection','DemonHunter-Devourer','Shaman-Enhancement','Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Guardian','Evoker-Augmentation','Warrior-Fury','Rogue-Assassination','Druid-Restoration','Rogue-Subtlety','Mage-Frost','Priest-Discipline','Hunter-Survival','DemonHunter-Vengeance','Monk-Brewmaster','Mage-Fire','Rogue-Outlaw',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aartoo:BAAANQABCggIDQAAAA==.',
Ac='Acherona:BAAANQABCgQIBAAAAA==.Ackreshanot:BAAANQADCgMIAwABNQAFFAMICgABANIjAA==.Acuminada:BAAANQAECgEIAQAAAA==.Acuna:BAABNQAECn8UAAICAAYKugfPaACxAAACAAYKugfPaACxAAAAAA==.',
Ad='Adison:BAAANQAECgUIBwAAAA==.',
Af='Affliction:BAABNQAECn8cAAQDAAkKPB6GEAD4AQADAAYKPhmGEAD4AQAEAAUKih41DwBbAQACAAIKYBenoQBNAAAAAA==.',
Ai='Airz:BAABNQAECn8dAAIFAAcKzxuRBADBAQAFAAcKzxuRBADBAQAAAA==.',
Ak='Akâkiôs:BAABNQAECn8eAAIGAAcKXhlIXAANAgAGAAcKXhlIXAANAgAAAA==.',
Al='Aladorman:BAABNQAECn8bAAIHAAcKnQkuWQD8AAAHAAcKnQkuWQD8AAAAAA==.Alamo:BAAANQAECgUIEQAAAA==.Albertlin:BAABNQAECn8WAAIIAAgKQxMJQAD7AQAIAAgKQxMJQAD7AQAAAA==.Alexinar:BAAANQAECgEIAQABNQAECgcIDQAJAAAAAA==.Alinbirt:BAAANQAECgQIBAABNQAECgoKQQAEAL8bAA==.',
Am='Amakuagsak:BAABNQAECn8ZAAIHAAcKtQPuhwCcAAAHAAcKtQPuhwCcAAAAAA==.Amicus:BAAANQAECgUIEAAAAA==.Ampmage:BAAANQAECgQIDAAAAA==.Ampsdk:BAAANQADCgYIBgAAAA==.',
An='Anthren:BAAANQADCgUIBQAAAA==.Antihose:BAAANQABCgQIBAAAAA==.',
Ap='Apollo:BAABNQAECn8sAAIKAAkKBhvINQCNAgAKAAkKBhvINQCNAgAAAA==.Apolynnæ:BAABNQAECn8ZAAILAAcKFRbOFgDeAQALAAcKFRbOFgDeAQABNQAECgoKIAAMAJQWAA==.',
Ar='Araniss:BAABNQAECn8aAAMNAAgKHh9eLgBbAgANAAcKHh9eLgBbAgAOAAQKPQ7ugQClAAAAAA==.Arasthel:BAAANQADCggIFAAAAA==.Aratrath:BAABNQAECn8lAAIPAAgKOhttEwB2AgAPAAgKOhttEwB2AgAAAA==.Araxxi:BAAANQAECgEIAQAAAA==.Arimal:BAAANQAECgEIAQAAAA==.Arthour:BAAANQAECgEIAgAAAA==.Aryasilly:BAABNQAECn8bAAIHAAgKRBsBWQBoAgAHAAgKRBsBWQBoAgAAAA==.',
As='Asdi:BAABNQAECn8WAAIQAAYKHR5qBwA3AQAQAAYKHR5qBwA3AQAAAA==.Ashe:BAACNQAFFH8YAAIRAAUKnhjtAgArAQARAAUKnhjtAgArAQA1AAQKfzAAAhEACgq+Iv4EAIIDABEACgq+Iv4EAIIDAAAA.',
At='Athenix:BAAANQAECggIBgAAAA==.Atiaran:BAAANQAECgYIBgABNQAECggIDwAJAAAAAA==.Attabubble:BAAANQAECgEIAQABNQAFFAQIDQAHAA0aAA==.Attaraxia:BAACNQAFFH8NAAIHAAQKDRqGBgD6AAAHAAQKDRqGBgD6AAA1AAQKfz8AAwcACgo/H5cJAC4CAAcACgo/H5cJAC4CABEAAwriDwdhAKMAAAAA.',
Au='Aurelith:BAAANQAECgEIAgAAAA==.Aurellya:BAABNQAECn8UAAISAAYKiwySgwDHAAASAAYKiwySgwDHAAAAAA==.',
Av='Avalora:BAAANQADCgQIBAAAAA==.Avodakadavra:BAAANQADCggICAAAAA==.',
Ay='Ayroon:BAAANQAECgYIEAAAAA==.',
['Aé']='Aéquítas:BAAANQAECgQICgAAAA==.',
Ba='Baidas:BAAANQAECgIIAgABNQAFFAoKOwAMALkkAA==.Bamfbutcher:BAABNQAECn8UAAITAAgKax74HwCEAQATAAgKax74HwCEAQAAAA==.Barent:BAAANQADCgYIDAAAAA==.Barrimen:BAABNQAECn8uAAISAAgKfQ4jOQBXAQASAAgKfQ4jOQBXAQAAAA==.Bartolomew:BAAANQAECgcIJQAAAQ==.Bartonella:BAAANQADCgYICAABNQAECgYIDQAJAAAAAA==.',
Be='Bealzabung:BAAANQADCgUIBQABNQAECgcIBwAJAAAAAA==.Bedemere:BAABNQAECn8pAAIHAAcKGBxrcgAsAgAHAAcKGBxrcgAsAgAAAA==.Beepers:BAABNQAECn8fAAIHAAkKhg6ehwD7AQAHAAkKhg6ehwD7AQAAAA==.Behodahlia:BAABNQAECn8VAAIFAAcKagRSMADnAAAFAAcKagRSMADnAAAAAA==.Belfie:BAAANQAECgUJBwAAAA==.Berrylla:BAAANQADCgIIAgAAAA==.',
Bi='Bigdemon:BAAANQAECgIIAQAAAA==.Bigmakk:BAABNQAECn8tAAIUAAgKww8FCwBiAQAUAAgKww8FCwBiAQAAAA==.Bimzelx:BAAANQAECgQICAAAAA==.Bipolar:BAAANQAECggIDQAAAA==.Bitterblood:BAABNQAECn84AAIHAAcK6BqUYABWAgAHAAcK6BqUYABWAgAAAA==.',
Bl='Blastgamer:BAAANQAECgMIBQAAAA==.Blondebeard:BAABNQAECn8dAAIHAAkK5w9YTwATAQAHAAkK5w9YTwATAQAAAA==.',
Bo='Booshi:BAAANQAECgIIAgAAAA==.Bowiiesenpai:BAABNQAECn8iAAIVAAkKaiBPEQDnAgAVAAkKaiBPEQDnAgAAAA==.',
Br='Bragontix:BAACNQAFFH8LAAILAAQKQh1IBQBpAQALAAQKQh1IBQBpAQA1AAQKfyAAAgsACQp+HSYMAKICAAsACQp+HSYMAKICAAAA.Bravehearth:BAAANQADCgYIDwABNQAECgcIBwAJAAAAAA==.Brewvoke:BAAANQAECgUJCgAAAA==.Brightxan:BAABNQAECn9EAAIWAAoKjhJaCQBkAQAWAAoKjhJaCQBkAQAAAA==.',
Bu='Bubbadruid:BAAANQADCgQIBAABNQAECgoKMAAHAEsjAA==.Bubbahunter:BAABNQAECn8wAAIHAAoKSyPyCACVAwAHAAoKSyPyCACVAwAAAA==.Bubbashaman:BAAANQADCgIIAgABNQAECgoKMAAHAEsjAA==.Buddahspanks:BAAANQADCgcIBQAAAA==.Buddahthai:BAABNQAECn83AAIMAAoKehxTQgAAAwAMAAoKehxTQgAAAwAAAA==.Buddhabum:BAABNQAECn8mAAICAAoK5hcqFQChAQACAAoK5hcqFQChAQAAAA==.Budweaver:BAAANQADCgYICQAAAA==.Bus:BAABNQAECn8zAAIXAAoKzCYJAACYAwAXAAoKzCYJAACYAwABNQAFFAgIFwANABQiAA==.Bussdefense:BAAANQADCggIJwAAAA==.Butterrs:BAAANQAFFAYICQAAAQ==.Butterz:BAAANQAECggIEQABNQAFFAYICQAJAAAAAA==.',
Ca='Caleian:BAABNQAECn8VAAIKAAcKDgvSkwBjAQAKAAcKDgvSkwBjAQAAAA==.Caloren:BAABNQAECn8sAAIYAAkKmxrOAwDuAQAYAAkKmxrOAwDuAQAAAA==.Caorou:BAABNQAECn8aAAIGAAgK/AZajgCAAQAGAAgK/AZajgCAAQAAAA==.Carahpri:BAAANQAECgMIAwABNQAFFAcIFgABAL0gAA==.Cashaboo:BAAANQADCgYICwAAAA==.',
Cb='Cbrn:BAAANQAECgUIBQABNQAECgoKFQALANASAA==.',
Ch='Charlyte:BAABNQAECn8aAAIKAAgKKBQOXwD7AQAKAAgKKBQOXwD7AQAAAA==.Charuzu:BAAANQADCgYIBgAAAA==.',
Co='Corneater:BAAANQAECgcIBAAAAA==.',
Cr='Crysinia:BAAANQADCgYIEQAAAA==.',
Cu='Cuigy:BAABNQAECn8ZAAMBAAcK1B+FPQBpAgABAAcK1B+FPQBpAgAGAAYKYhQZjgCBAQAAAA==.',
Cy='Cyriene:BAAANQAECgYIEQAAAA==.Cyril:BAAANQAECgMIAwABNQAECggIHQAZAOASAA==.',
Da='Dagadin:BAAANQAECgcIDwAAAA==.Dalio:BAAANQAECgYIEQAAAA==.Danté:BAAANQAECgQICwABNQAFFAIIAgAJAAAAAA==.Daraen:BAAANQADCgYIBwAAAA==.Daylen:BAABNQAECn8kAAIaAAgK0wn0IwBxAQAaAAgK0wn0IwBxAQAAAA==.',
Dd='Ddeathchura:BAABNQAECn8kAAINAAgK9xKhEABdAQANAAgK9xKhEABdAQAAAA==.',
De='Deactrim:BAABNQAECn8eAAINAAgKQRIDVgCcAQANAAgKQRIDVgCcAQAAAA==.Deafknights:BAAANQAECgMIBAABNQAECggIDAAJAAAAAA==.Deathscoobs:BAAANQAECgUICAABNQAECgUIEgAJAAAAAA==.Dema:BAAANQADCgUICAAAAA==.Demonicflats:BAEANQAECgEIAQABNQAECgoKMAACAOUSAA==.Demonodie:BAAANQAECgEIAQAAAA==.Dendrada:BAABNQAECn8kAAMOAAgKtiBFBAAsAgAOAAgKtiBFBAAsAgAbAAYK1hs8VQC9AQAAAA==.Deuce:BAABNQAECn8gAAILAAcKMxBICADtAAALAAcKMxBICADtAAAAAA==.',
Di='Diogenes:BAAANQADCgQIBAAAAA==.Dizimo:BAAANQAECgUICwAAAA==.',
Dk='Dkflat:BAEANQADCggIDAABNQAECgoKMAACAOUSAA==.',
Do='Dogmeat:BAACNQAFFH8JAAIHAAQK/BdMDwBjAQAHAAQK/BdMDwBjAQA1AAQKfyYAAgcACQqCI7cQAGADAAcACQqCI7cQAGADAAE1AAUUBwgYAAgAwhgA.Doncowleone:BAAANQADCgMIAwABNQAECgcIBwAJAAAAAA==.Dotisa:BAAANQAECgQIBQAAAA==.',
Dr='Dragonlex:BAAANQADCgcIDQAAAA==.Drakeshadows:BAAANQADCgIIAgAAAA==.Drchivago:BAAANQADCgYICgAAAA==.Drdreadful:BAAANQABCgIIAgAAAA==.Drfumanchu:BAAANQADCgUICQABNQAECgcIBwAJAAAAAA==.Drotgar:BAAANQAECgIIAgABNQAECggIEgAJAAAAAA==.Druidtime:BAAANQAECggICAAAAA==.',
Du='Duna:BAAANQAECgYIEgAAAA==.Dungoofed:BAAANQAECgEJAQAAAA==.Duvidressra:BAABNQAECn9BAAMEAAoKvxuPAAAqAgAEAAkKNh+PAAAqAgACAAUKpgoHigBxAAAAAA==.',
Dx='Dxmvn:BAAANQADCgQIBQAAAA==.',
Ed='Edisonn:BAACNQAFFH8MAAMCAAUKjgzZIwDfAAACAAQKbRDZIwDfAAADAAEKzwQgCwBJAAA1AAQKfzAAAwIACgpUH+4yAL0CAAIACAotIO4yAL0CAAMABgpIEwInAD4BAAAA.',
Eg='Eggies:BAAANQAECgEIAgABNQAFFAIIBQACAD4eAA==.',
Ek='Ektrim:BAAANQAECgEIAQABNQAECggIHgANAEESAA==.',
El='Eladio:BAAANQADCgIIAgAAAA==.Eldarya:BAAANQAECgUIDAAAAA==.Elentisa:BAAANQAECgUIEgAAAA==.Elghinn:BAABNQAECn8nAAIcAAgK4g9xOwDbAQAcAAgK4g9xOwDbAQAAAA==.Elissaria:BAAANQADCgQIBAAAAA==.Eliteslayer:BAAANQADCgYIBAAAAA==.Ellastrasza:BAABNQAECn8tAAIdAAgKzRIwHADBAQAdAAgKzRIwHADBAQAAAA==.Ellesmere:BAAANQAECgEIAQAAAA==.Ellie:BAABNQAECn8iAAIHAAgKnRPLRgAnAQAHAAgKnRPLRgAnAQAAAA==.Elroy:BAABNQAECn80AAISAAoKtBB7GwC0AQASAAoKtBB7GwC0AQAAAA==.',
Em='Embold:BAAANQADCggICAABNQAFFAQIEwAVAKYkAA==.Emernantus:BAABNQAECn8fAAIWAAcKZRNHJQC2AQAWAAcKZRNHJQC2AQAAAA==.',
Er='Erazar:BAABNQAECn8xAAQLAAkKkyE5AwB3AwALAAkKkyE5AwB3AwAPAAIK/QONSQBXAAAeAAEKjhrbIwA2AAAAAA==.',
Es='Espy:BAAANQAECgMIBQAAAA==.',
Eu='Eunbyeol:BAABNQAECn8bAAIfAAkKpRpWBgCnAgAfAAkKpRpWBgCnAgAAAA==.',
Ev='Evee:BAAANQABCgQIBAAAAA==.Eventual:BAAANQADCggICAAAAA==.',
Fa='Faeria:BAABNQAECn8iAAIaAAcKKxgJKABeAQAaAAcKKxgJKABeAQAAAA==.Fatcritties:BAAANQAECgIIBAAAAA==.Fatnchunkydk:BAABNQAECn8gAAINAAcKCw7pIwDnAAANAAcKCw7pIwDnAAAAAA==.',
Fe='Feeblemind:BAAANQAECgUIEwAAAA==.Feli:BAABNQAECn8XAAMfAAcK6A2jFQBCAQATAAcKUwiOygBhAQAfAAYKvQ2jFQBCAQAAAA==.Felmommy:BAAANQADCggICAAAAA==.Femboi:BAAANQAECgEIAQAAAA==.Fender:BAABNQAECn8aAAIQAAcK0A5UCQAQAQAQAAcK0A5UCQAQAQAAAA==.',
Ff='Ffugntotems:BAAANQADCgcICwAAAA==.Ffviitifa:BAAANQADCgcICwAAAA==.',
Fi='Finfangfoom:BAAANQADCgQICQABNQAECgcIBwAJAAAAAA==.Fingertoes:BAABNQAECn8fAAIMAAgKDxryhQByAgAMAAgKDxryhQByAgAAAA==.Fistbeard:BAAANQADCgUJBQABNQADCgcJCgAJAAAAAA==.Fizban:BAAANQADCgcIBwAAAA==.Fizzlerazz:BAAANQADCgUIBQAAAA==.',
Fl='Flattulata:BAEANQADCggICQABNQAECgoKMAACAOUSAA==.Flatulatta:BAEBNQAECn8wAAICAAoK5RJSXgA9AgACAAoK5RJSXgA9AgAAAA==.Flatunter:BAEANQADCggIEAABNQAECgoKMAACAOUSAA==.Flory:BAAANQAECggIEQAAAA==.Flyciful:BAAANQAECgQICAAAAA==.Flyingweasle:BAAANQADCgQIBwAAAA==.',
Fo='Forceed:BAEANQAECgEIBQABNQAECgYIFQACAIQWAA==.Forsythe:BAAANQABCgcICQAAAA==.Foxehh:BAAANQABCgUIBwAAAA==.Foxxycontin:BAAANQADCgEIAQAAAA==.',
Fr='Fraternaldk:BAACNQAFFH8NAAIbAAUK9xL9CACHAQAbAAUK9xL9CACHAQA1AAQKfzEAAhsACQpsIckJAG8DABsACQpsIckJAG8DAAAA.Fraturnal:BAAANQADCgIIAgAAAA==.Freestyle:BAAANQADCggIEwAAAA==.Frodowagons:BAAANQAFFAQIBAAAAA==.Frostpie:BAABNQAECn8qAAIMAAkKGBfkfACEAgAMAAkKGBfkfACEAgAAAA==.',
Fu='Fuglybaby:BAAANQAECggICAAAAA==.Fuhenhenka:BAAANQAECgMIAwAAAA==.Furyofheaven:BAAANQAECgIIAwAAAA==.',
Fw='Fwakos:BAABNQAECn8UAAIDAAUKUAOMCwBwAAADAAUKUAOMCwBwAAAAAA==.Fwakow:BAAANQADCgYIEAAAAA==.',
Ga='Gacke:BAAANQADCgEIAQABNQAECggIJwAWAOgfAA==.Gakmonk:BAAANQADCggJDgABNQAECggIJwAWAOgfAA==.Gakpaladin:BAABNQAECn8nAAIWAAgK6B+IDADRAgAWAAgK6B+IDADRAgAAAA==.Galathil:BAAANQAECgYIBgAAAA==.Galaway:BAAANQAECgcIDAAAAA==.Galthul:BAAANQADCgUIBQABNQAECggIIQAGAPwcAA==.Garfyaz:BAAANQAECgEIAQAAAA==.Gargoyled:BAAANQAECgEIAQAAAA==.',
Gd='Gdlez:BAAANQAECgUICwAAAA==.',
Ge='Gerasstrois:BAAANQADCgEIAQABNQAECgoKQQAEAL8bAA==.Gethael:BAAANQADCgIIAgAAAA==.',
Go='Goatroth:BAAANQAECgUIEgAAAA==.Golorious:BAABNQAECn8hAAMWAAkKYR0hFABjAgAWAAkKYR0hFABjAgASAAMKAgfuvgByAAAAAA==.Goododie:BAAANQAECgYIEgAAAA==.',
Gr='Grayback:BAAANQAECggICgABNQAECgoKIwAYADoZAA==.Grenas:BAAANQABCgQICQAAAA==.Grippyweasle:BAABNQAECn8qAAINAAgKUBdKOwAYAgANAAgKUBdKOwAYAgAAAA==.Grovelly:BAAANQAECgEIAQAAAA==.Growlius:BAAANQAECgEIAQABNQAECgUJBwAJAAAAAA==.',
Gu='Gudit:BAAANQAECgEIAQABNQAECgcIDQAJAAAAAA==.Gulaken:BAABNQAECn8eAAIHAAcKWxH0ngDJAQAHAAcKWxH0ngDJAQAAAA==.Guseva:BAAANQAECgEIAgAAAA==.Guttershark:BAABNQAECn8aAAIgAAgKxxx2IwBsAgAgAAgKxxx2IwBsAgAAAA==.',
Ha='Hafnia:BAAANQAECgYIDQAAAA==.Halliday:BAAANQAECgEIBQAAAA==.Haoasakura:BAABNQAECn8kAAISAAkKLSLHKwAYAwASAAkKLSLHKwAYAwAAAA==.Haybuse:BAAANQAECgEIAQABNQAECgEIAgAJAAAAAA==.Haylo:BAAANQAECgIICAAAAA==.',
He='Headshop:BAAANQAECgEIAgAAAA==.Healzforfood:BAAANQAECgYIEQAAAA==.Heap:BAAANQAECgMIAwABNQAECgkJHQAHAOcPAA==.Heartlight:BAAANQADCgMIAwAAAA==.Heavyreign:BAAANQADCgQIBwAAAA==.Helicobacter:BAAANQADCgYIBgAAAA==.Hewnoshaqa:BAABNQAECn8XAAIHAAYKUQ6XxgB0AQAHAAYKUQ6XxgB0AQAAAA==.Hexorcist:BAACNQAFFH8IAAMGAAMK6QwLGwDpAAAGAAMK6QwLGwDpAAABAAEKDxVeLwA6AAA1AAQKfyQAAwEACQozH+0nAMQCAAEACQozH+0nAMQCAAYABgqfFwNwANABAAAA.',
Hi='Hickerbilly:BAAANQADCgEIAQAAAA==.Hitormist:BAABNQAECn8cAAIFAAkKTBOvFgASAgAFAAkKTBOvFgASAgABNQAECgoKFQALANASAA==.',
Ho='Holyanne:BAAANQADCgQIAgAAAA==.Holyshoot:BAAANQAECgEIAwAAAA==.Holyspanks:BAAANQADCgYIBgABNQAECgkJHAAZAMIbAA==.Horous:BAAANQAECgMIAwAAAA==.Hottowel:BAAANQAECgEIAQAAAA==.',
Hr='Hruuli:BAAANQADCgYIBgAAAA==.',
Hu='Huntreess:BAAANQABCgIIAQAAAA==.Huntrlicious:BAABNQAECn8iAAIHAAgKHQujoQDDAQAHAAgKHQujoQDDAQAAAA==.Husqvarnna:BAAANQAECgEIAQAAAA==.Huugor:BAAANQAECggIEAAAAA==.',
Ic='Icnips:BAAANQADCgUIBQAAAA==.Icoulddowork:BAAANQAECggIEgABNQAECgoKHQAIADYcAA==.',
Id='Ididwork:BAAANQAECgMIAwABNQAECgoKHQAIADYcAA==.Idoshiftwork:BAABNQAECn8dAAQIAAoKNhxAHgDYAgAIAAgK6CFAHgDYAgAhAAUKrBpPNAB4AQAQAAMKmQ0LMgCDAAAAAA==.Idunno:BAAANQADCgYICQAAAA==.',
Ih='Ihriel:BAAANQADCgEJAQAAAA==.',
Ik='Ikazuchi:BAABNQAECn8kAAIOAAcKdw0bHQAzAQAOAAcKdw0bHQAzAQAAAA==.',
Il='Illcutabish:BAABNQAECn8jAAMgAAkKBiTtCwAoAwAgAAkKBiTtCwAoAwAiAAgKKhbIHQDkAQAAAA==.Illtank:BAAANQAECggIDQAAAA==.',
Im='Imatankin:BAAANQAECgEIAgAAAA==.Imk:BAABNQAECn8kAAIYAAgKNgqmEQAlAQAYAAgKNgqmEQAlAQAAAA==.',
In='Incubuse:BAAANQAECgEIAgAAAA==.',
Io='Iock:BAEANQAECgUIBQAAAA==.',
Ir='Ironarms:BAAANQAECgYJEwAAAA==.',
Is='Ishido:BAAANQADCgYIBgAAAA==.',
Je='Jennypoo:BAABNQAECn8rAAIhAAgK5BQ0CQCkAQAhAAgK5BQ0CQCkAQAAAA==.Jessd:BAAANQADCgcIBwAAAA==.',
Ji='Jinuoo:BAAANQADCgQIBAAAAA==.',
Jo='Johnwarrior:BAABNQAECn8tAAIfAAkKAh/gBADiAgAfAAkKAh/gBADiAgAAAA==.Jorrix:BAABNQAECn8mAAISAAgK4wrgUgAfAQASAAgK4wrgUgAfAQAAAA==.',
Ju='Juduspriestt:BAABNQAECn8mAAISAAgKRQ8ATwAmAQASAAgKRQ8ATwAmAQAAAA==.',
Jy='Jynaxa:BAAANQADCgEIAQAAAA==.',
['Jä']='Jägermeister:BAAANQADCgYJDAAAAA==.',
Ka='Kaaeko:BAABNQAECn8VAAIMAAkK5ByxKgBwAQAMAAkK5ByxKgBwAQAAAA==.Kalerito:BAABNQAECn8fAAIhAAgK0SBKEADVAgAhAAgK0SBKEADVAgAAAA==.Kallythea:BAAANQADCggICAAAAA==.Kardie:BAAANQADCgQIBAABNQAECgkJMQALAJMhAA==.Karl:BAAANQAECgMICQABNQAECgUIEQAJAAAAAA==.Karne:BAAANQAECgIIAgAAAA==.Kaserr:BAACNQAFFH8YAAMiAAcK4BlxAwADAgAiAAYKfxhxAwADAgAgAAUK3RtfBgC5AQA1AAQKfzAAAyIACgrlJPgGAA4DACIACArZJfgGAA4DACAABgr+I8wIAJEBAAAA.Kayserdh:BAAANQAECgUICwAAAA==.Kazaf:BAABNQAECn8mAAINAAoKQxcyGgAcAQANAAoKQxcyGgAcAQAAAA==.Kazrik:BAAANQAECgUICQAAAA==.',
Ke='Kebru:BAABNQAECn8ZAAMKAAgKRhIvZwDiAQAKAAgKRhIvZwDiAQAWAAEKxgRLcgAsAAAAAA==.Keitrek:BAABNQAECn8nAAIKAAgKzAuUfQChAQAKAAgKzAuUfQChAQAAAA==.Kelthias:BAAANQADCgYJDQAAAA==.Kenje:BAAANQADCgIIAgAAAA==.Kerwîck:BAABNQAECn8pAAIKAAoKAxdzCAA9AgAKAAoKAxdzCAA9AgAAAA==.Keyen:BAABNQAECn8gAAIKAAgKsxDjGACSAQAKAAgKsxDjGACSAQAAAA==.',
Kh='Kheiko:BAAANQAECgUIBgAAAA==.',
Ki='Kibalion:BAABNQAECn8WAAIaAAcKCBzFHACWAQAaAAcKCBzFHACWAQAAAA==.Killbent:BAAANQAECgUIDwAAAA==.Kinnky:BAABNQAECn8XAAIjAAcKFBOaDwCvAQAjAAcKFBOaDwCvAQAAAA==.Kino:BAABNQAECn8dAAMZAAgK4BJLCgBRAQAZAAgK4BJLCgBRAQAGAAEKhAqDNQE0AAAAAA==.Kitn:BAAANQABCgQIBAAAAA==.Kityana:BAAANQADCgIIAgAAAA==.',
Ko='Kolton:BAAANQAECgEIAwAAAA==.',
Kp='Kpop:BAAANQADCgIIAwAAAA==.',
Kr='Krasdan:BAAANQAECgIIAgAAAA==.Kreettip:BAABNQAECn8nAAIaAAgK2RhaRwBQAgAaAAgK2RhaRwBQAgAAAA==.Krispy:BAAANQADCgcJBwABNQAECggIJQAPADobAA==.',
Ks='Kshira:BAAANQADCgQIBAAAAA==.Ksp:BAAANQAECgEIAQAAAA==.',
Ku='Kugamoo:BAABNQAECn8iAAMIAAoKnhW6LwBjAgAIAAoKnhW6LwBjAgAhAAcKmgfEPAA8AQAAAA==.Kulgan:BAABNQAECn8kAAMaAAkKVRpEQgBjAgAaAAkKVRpEQgBjAgAkAAEKJxGDKAA0AAAAAA==.Kurgen:BAAANQAECgYIEgAAAA==.Kuroda:BAAANQAECgYIDgAAAA==.Kurolucifer:BAAANQADCgcIGAAAAA==.',
Ky='Kylex:BAAANQAECggIEgAAAA==.',
['Kä']='Käßoom:BAAANQAECgYICQAAAA==.',
La='Lamiah:BAAANQAECgUICgAAAA==.Laredemos:BAAANQAECgYICgAAAA==.Lauadia:BAAANQAECgYICgAAAA==.',
Lc='Lckdown:BAAANQAECggIEwAAAA==.',
Le='Legomyegolas:BAAANQADCgYJBgAAAA==.Lelaeh:BAAANQAECggIDwAAAA==.',
Li='Lightsocket:BAAANQADCgYJCAABNQAECgIIAgAJAAAAAA==.Lishy:BAAANQADCgEIAQAAAA==.Livingkntpib:BAAANQADCggICAAAAA==.',
Lo='Lobotany:BAAANQADCgIIAgAAAA==.Lockedout:BAAANQAECgMIBQABNQAECgoKMQAMAMsgAA==.Lockith:BAAANQAECgEIAQABNQAECgkJJQAWANMbAA==.Loden:BAAANQAECgcIDAAAAA==.Lodev:BAAANQAECgQIBwAAAA==.Lodez:BAAANQAFFAEIAgAAAA==.Loktarhogar:BAAANQAECgUICAAAAA==.Lostadin:BAAANQADCgIIAgAAAA==.Lovi:BAABNQAECn8wAAIBAAoKshA2FACyAQABAAoKshA2FACyAQAAAA==.',
Lu='Luck:BAAANQAECgQIBAABNQAECgQIBQAJAAAAAA==.Luckyboi:BAABNQAECn8jAAQIAAoKjgoiXgBYAQAIAAgKngYiXgBYAQAhAAkKJAfzOQBPAQAdAAQKKASdSACMAAAAAA==.Lumeria:BAAANQAECgUIEgAAAA==.Lumina:BAABNQAECn8ZAAISAAcK8gmb4gBWAQASAAcK8gmb4gBWAQAAAA==.Lusciifi:BAACNQAFFH8TAAMSAAcKuR6dCADAAQASAAYKuR6dCADAAQAWAAQKlAvoBgAWAQA1AAQKfzkAAxIACgpHJvYOAJADABIACgpDJvYOAJADABYACAqTItYLANwCAAAA.',
Ly='Lykie:BAABNQAECn8lAAIWAAkK0xvfFQBQAgAWAAkK0xvfFQBQAgAAAA==.Lynxic:BAAANQAECgUICAAAAA==.Lyone:BAABNQAECn8bAAIXAAcKShqZGACnAQAXAAcKShqZGACnAQAAAA==.',
['Lä']='Lävey:BAAANQADCgEIAQAAAA==.',
['Lé']='Léxa:BAAANQAECgUICAAAAA==.',
['Lú']='Lúvaa:BAABNQAECn8XAAINAAoKFR1MKQB4AgANAAoKFR1MKQB4AgAAAA==.',
Ma='Macavity:BAAANQADCgMIAwAAAA==.Madmanmike:BAAANQADCgIIAgAAAA==.Magalis:BAAANQAECgQIEgAAAA==.Magicwoman:BAABNQAECn8UAAIMAAUKpgFCxABdAAAMAAUKpgFCxABdAAAAAA==.Magikkisback:BAAANQAECgQIBAAAAA==.Magsh:BAAANQAECgIIAwAAAA==.Mandorius:BAABNQAECn8VAAIHAAgKPxLMIQCRAQAHAAgKPxLMIQCRAQAAAA==.Maphra:BAAANQADCggJCAABNQAECgoKFQALANASAA==.Marcos:BAAANQADCgIIAgAAAA==.Marl:BAAANQAECgUICgAAAA==.Marvolo:BAAANQAECggIEQABNQAECgoKIwAYADoZAA==.Maverickdog:BAABNQAECn8dAAQRAAgKpx0kMADMAQARAAcKMxskMADMAQAlAAQKOBKlDAAIAQAHAAMKPiOBCAH2AAAAAA==.',
Mc='Mchammerwork:BAAANQAECgYIDgABNQAECgoKHQAIADYcAA==.',
Me='Mechunter:BAAANQADCgYIBgABNQAECgUICQAJAAAAAA==.Meekzz:BAABNQAECn8nAAIaAAkKexmjDgAHAgAaAAkKexmjDgAHAgAAAA==.Meeshie:BAABNQAECn9XAAQaAAoKwxvHDQAQAgAaAAoKwxvHDQAQAgAVAAgKgg3HOABfAQAkAAIKZwjQIgBRAAAAAA==.Melodrop:BAAANQAECggIDQAAAA==.Merc:BAAANQAECgEIAQAAAA==.',
Mi='Mihawk:BAAANQADCgEIAQABNQAECggIHwAMAA8aAA==.Mikexfire:BAABNQAECn8cAAIcAAgKNQ1TQAC7AQAcAAgKNQ1TQAC7AQAAAA==.Mikuzume:BAAANQADCgYIBgAAAA==.Mildchaos:BAAANQAECggIAQAAAA==.Mimic:BAAANQADCgIIAgAAAA==.Mishima:BAAANQAECggIEAAAAA==.Misspell:BAAANQAECgEIAQAAAA==.Mistypaksz:BAAANQAECgEIAQAAAA==.Miznewbooty:BAABNQAECn8iAAIVAAoKABNtHwBAAgAVAAoKABNtHwBAAgAAAA==.',
Mo='Moochella:BAAANQAECgcIEQAAAA==.Moojestic:BAAANQAECgMIAwAAAA==.Moonflungpoo:BAAANQAECgIIAgAAAA==.Moonq:BAABNQAECn8kAAIhAAgKIwNkGAAAAQAhAAgKIwNkGAAAAQAAAA==.Moosie:BAABNQAECn8lAAImAAgKOxVrDgDTAQAmAAgKOxVrDgDTAQAAAA==.Moosifer:BAAANQADCgQIBAABNQAFFAMICAAGAOkMAA==.Mooska:BAAANQAECgEIAQABNQAECggIJQAmADsVAA==.Mostunknown:BAAANQAECgEIAQAAAA==.Moxflip:BAAANQAECggICwAAAA==.Moxtsm:BAAANQAECgMICAAAAA==.Mozzers:BAAANQAECgIIAgAAAA==.',
Ms='Msrosie:BAAANQAECgQIBAAAAA==.',
Mu='Muertenegra:BAAANQADCgUIBQABNQAECgcIHgAGAF4ZAA==.Muffy:BAABNQAECn8YAAIPAAcK4w4qKwBTAQAPAAcK4w4qKwBTAQAAAA==.Muln:BAAANQADCggIBwAAAA==.Murlouh:BAAANQADCgQIBAAAAA==.',
My='Mydevil:BAAANQAECgQIBgAAAA==.Myllakura:BAAANQAECgQICgABNQAECggIEAAJAAAAAA==.Mystk:BAAANQADCgIIAgAAAA==.Mythnarra:BAACNQAFFH8OAAMcAAQKZBkABAABAQAcAAQKZBkABAABAQAYAAIKggQsEwBjAAA1AAQKfygAAxgACgrNIUgNABADABgACQpAIkgNABADABwABQpKIHcMAI0BAAAA.',
['Mä']='Mäomäo:BAAANQADCgMIAwAAAA==.',
['Mí']='Mísanthrope:BAAANQADCgQIBAABNQAECgUIEgAJAAAAAA==.',
['Mò']='Mòrpheus:BAAANQAFFAIIAgAAAA==.',
Na='Nadíne:BAABNQAECn8kAAIMAAkKmRG2ZQDyAAAMAAkKmRG2ZQDyAAAAAA==.Nanukimon:BAAANQAECgYIEgAAAA==.Narawe:BAAANQAECgQICwABNQAECgoKMAABAP4cAA==.Nardionger:BAAANQAECgQIBAAAAA==.Nastymccasty:BAAANQAECggIAwABNQAECgkJIwAgAAYkAA==.Naughtgelic:BAAANQADCgYICgAAAA==.',
Ne='Nedgamingttv:BAEBNQAECn8VAAICAAYKhBZZnQCdAQACAAYKhBZZnQCdAQAAAA==.Nekrimah:BAAANQAECggIDgABNQAECggIDwAJAAAAAA==.Nerph:BAAANQADCgYIEQAAAA==.Neutrons:BAAANQADCgIIAgAAAA==.Nevaera:BAAANQAECgQIBwAAAA==.Newarthas:BAAANQAECgQIBAAAAA==.',
Ni='Ni:BAAANQAECgQIBQAAAA==.Niallx:BAAANQAECggICAAAAA==.Nick:BAACNQAFFH8TAAMNAAQKtxMkFgD/AAAbAAQKLRMrDwAZAQANAAQKMREkFgD/AAA1AAQKfy4AAxsACQoEJtURACkDABsACQoEJtURACkDAA0AAwqnGlqGAOQAAAAA.Nikor:BAEBNQAECn8ZAAMWAAgK7w5YLAB6AQAWAAYKRxVYLAB6AQASAAIKPwIg4wEMAAAAAA==.',
Nm='Nmue:BAAANQADCgIIAgAAAA==.',
No='Nokorii:BAAANQAECgYIEgAAAA==.Nomecoma:BAABNQAECn8oAAINAAoKLxHlCACrAQANAAoKLxHlCACrAQAAAA==.Nonok:BAAANQADCgIIAgAAAA==.Nookah:BAAANQAECgYIBwABNQAFFAQIDQAHAA0aAA==.Noshom:BAABNQAECn8fAAMBAAgKuCIKHAD+AgABAAgKuCIKHAD+AgAGAAMKbQ7H7QC7AAAAAA==.Notches:BAAANQADCgEIAQAAAA==.',
Ns='Nsyncrogue:BAAANQADCgYJBgAAAA==.',
Ny='Nymful:BAABNQAECn8ZAAIRAAcKcgdFQABSAQARAAcKcgdFQABSAQAAAA==.',
['Nè']='Nèlo:BAABNQAECn8VAAITAAcK6w7LuACPAQATAAcK6w7LuACPAQAAAA==.',
Ob='Obianstrider:BAAANQADCggIHQAAAA==.',
Oc='Oceanspell:BAABNQAECn8zAAIjAAgKKCBGAQAbAgAjAAgKKCBGAQAbAgAAAA==.',
Og='Oggleboggle:BAAANQADCgEIAQAAAA==.',
Ol='Oldbuse:BAABNQAECn8lAAMZAAkK6iAiDACtAgAZAAkK6iAiDACtAgAGAAEK1BggJwFEAAAAAA==.',
On='Onlytoez:BAAANQAECgYIEAABNQAECgoKVwAaAMMbAA==.',
Or='Orave:BAABNQAECn8XAAIaAAYKAhx6FADOAQAaAAYKAhx6FADOAQAAAA==.Orionah:BAAANQAECgcIDQAAAA==.Oromë:BAAANQAECgEIAgAAAA==.Orzik:BAAANQADCggIDgAAAA==.',
Os='Osox:BAAANQAECggICAAAAA==.Ostena:BAABNQAECn8WAAICAAcKtAtvWADRAAACAAcKtAtvWADRAAAAAA==.Osteole:BAABNQAECn8ZAAMVAAYKLgdhSwDpAAAVAAUKkwdhSwDpAAAaAAQKVwQN1ACrAAABNQAECgcIFgACALQLAA==.',
Ou='Oulawdpriest:BAACNQAFFH8MAAIVAAQKcgk9DAAiAQAVAAQKcgk9DAAiAQA1AAQKfykAAxUACgr/FVAdAFcCABUACgr/FVAdAFcCABoAAQpjE5X9ADAAAAAA.',
Ov='Overture:BAAANQAECgMIAwAAAA==.',
Ow='Owthatburns:BAAANQADCgYIBgAAAA==.',
Pa='Pakszdude:BAAANQADCgUIBQAAAA==.Pandamonious:BAAANQADCggICAABNQAECgEIAwAJAAAAAA==.Papawoof:BAAANQADCgQJBQABNQAFFAMICAAGAOkMAA==.Parkour:BAAANQAECgMICwAAAA==.Paullyfists:BAABNQAECn8cAAIUAAkK0CAtEgDLAgAUAAkK0CAtEgDLAgAAAA==.',
Pe='Peni:BAAANQAECgIIAgAAAA==.',
Pi='Pintobeans:BAAANQAECgEIAwAAAA==.',
Po='Popkorn:BAACNQAFFH8eAAMYAAcK8iUbAQCcAgAYAAYK8iUbAQCcAgAmAAMKQB5ZAgAhAQA1AAQKfzIAAxgACQrSJgABAOYDABgACQrSJgABAOYDACYAAgomHnEfAM4AAAAA.Poplocks:BAAANQADCgYICgAAAA==.Porrana:BAABNQAECn8ZAAITAAcKfRovPQArAQATAAcKfRovPQArAQAAAA==.Powaqa:BAABNQAECn8VAAIDAAYKgQKQPADPAAADAAYKgQKQPADPAAAAAA==.',
Pr='Praetorian:BAABNQAECn8fAAISAAkKHw6umQDwAQASAAkKHw6umQDwAQAAAA==.Praxxus:BAAANQADCgYIBgAAAA==.',
Ps='Psy:BAAANQAECggIAgAAAA==.',
Pw='Pwincess:BAAANQADCgIIAgAAAA==.',
Py='Pyrahna:BAAANQADCgYIBgABNQAECgQIDgAJAAAAAA==.',
Qm='Qmen:BAAANQADCgIIAgAAAA==.',
Qu='Quasient:BAABNQAECn8sAAIMAAoKfhuuSgDsAgAMAAoKfhuuSgDsAgAAAA==.Quethelos:BAAANQAECgEIAQAAAA==.Quickbrew:BAAANQAECgUIBQAAAA==.Quickspell:BAABNQAECn8nAAIjAAoKORx/AACZAgAjAAoKORx/AACZAgAAAA==.',
Ra='Raalcar:BAAANQAECgMIBAABNQAECggIFwAYAHwYAA==.Raedyyn:BAAANQAECgcIDgAAAA==.Ragarninn:BAAANQAECgcIDwABNQAFFAMICgABANIjAA==.Ragarth:BAAANQAECgEIAQAAAA==.Ragendecay:BAAANQAECgYIDwAAAA==.Ragequits:BAACNQAFFH8fAAITAAkKtiJ7AQD/AgATAAkKtiJ7AQD/AgA1AAQKfygAAhMACgqLJbkRAHYDABMACgqLJbkRAHYDAAAA.Ragewar:BAAANQABCgcIDAAAAA==.Rakshassa:BAAANQAECgcICwAAAA==.Ralcar:BAABNQAECn8XAAIYAAgKfBgSIwAxAgAYAAgKfBgSIwAxAgAAAA==.Rawkphyst:BAAANQADCgQIAgAAAA==.Razrscale:BAAANQAECgEIAQAAAA==.',
Re='Redhuntsman:BAAANQAECgQICAAAAA==.Regrow:BAAANQADCgcIBwABNQAECgUICQAJAAAAAA==.Reska:BAAANQAECgQIDgAAAA==.',
Rh='Rholdentodor:BAAANQAECgQIBgABNQAECgkJMgAMADYWAA==.',
Ri='Rindorin:BAABNQAECn8UAAISAAcKyweR6gBHAQASAAcKyweR6gBHAQAAAA==.Ritarepulsa:BAAANQADCgYIDAAAAA==.Riverkitty:BAAANQAECgEIAQAAAA==.',
Ro='Rohra:BAABNQAECn8fAAIhAAcKDg1aPAA/AQAhAAcKDg1aPAA/AQAAAA==.Roral:BAAANQAECgEIAQABNQAECgUIEgAJAAAAAA==.Rosenwyn:BAAANQADCgUIBQAAAA==.Rosiee:BAAANQAECgQIDAABNQAECggILQAUAMMPAA==.Rozynwen:BAAANQAECgIIAwAAAA==.',
Ru='Ruah:BAAANQABCgMIAwAAAA==.Rubmytoes:BAAANQAECgEJAQAAAA==.Rukuna:BAAANQAECgEIAQAAAA==.Runecast:BAABNQAECn8uAAIOAAoKlxgJHgCaAgAOAAoKlxgJHgCaAgAAAA==.',
Sa='Saelyrinth:BAAANQAECgEIAwABNQAECgUIEgAJAAAAAA==.Salamence:BAAANQADCggIDwABNQAECgcIJQAJAAAAAQ==.Sambor:BAABNQAECn8XAAIhAAgKoAPLUQDCAAAhAAgKoAPLUQDCAAAAAA==.Sarapheena:BAABNQAECn8jAAIBAAoKahlZKgC6AgABAAoKahlZKgC6AgAAAA==.Sarouk:BAABNQAECn8qAAITAAkKPheXVgCHAgATAAkKPheXVgCHAgAAAA==.Satanbomb:BAAANQAECgIIBAAAAA==.Satansbride:BAAANQAECgYIBwABNQAECgcIBwAJAAAAAA==.Saterli:BAACNQAFFH8NAAIaAAUKcRKOEgB5AQAaAAUKcRKOEgB5AQA1AAQKfyQAAxoACgr/FxRDAF8CABoACgr/FxRDAF8CABUAAQplAgeGACMAAAAA.Saturno:BAAANQAECgEIAQAAAA==.Saucypirate:BAABNQAECn8iAAMjAAgKKxFIFQBYAQAMAAgKSAzw1QDbAQAjAAYKlRJIFQBYAQAAAA==.Sayygurl:BAAANQAECgQIDAAAAA==.',
Sc='Scalvert:BAABNQAECn8yAAIMAAkKNhYZtwAVAgAMAAkKNhYZtwAVAgAAAA==.Scalypanda:BAABNQAECn8dAAMeAAkK7Q5yCwCoAQAeAAkK2w1yCwCoAQALAAYKxQk6JAAgAQAAAA==.Scamander:BAABNQAECn8jAAIYAAoKOhnUFQC1AgAYAAoKOhnUFQC1AgAAAA==.Scoobs:BAAANQADCgQIBAABNQAECgUIEgAJAAAAAA==.Screamsalot:BAAANQAECgEIAgABNQAECgUIEgAJAAAAAA==.Sculi:BAABNQAECn8iAAIHAAcKDBJHmADXAQAHAAcKDBJHmADXAQAAAA==.',
Se='Seiishiro:BAAANQAECgUIDgAAAA==.Seldon:BAABNQAECn8hAAISAAgKtxLuNABiAQASAAgKtxLuNABiAQAAAA==.Senyor:BAABNQAECn8wAAIWAAoK+hQvDAA8AQAWAAoK+hQvDAA8AQAAAA==.Seradormi:BAAANQADCgMIAwAAAA==.Seraphiel:BAABNQAECn8VAAIkAAYKNyVOAACRAgAkAAYKNyVOAACRAgABNQAECgcIHQAFAGsaAA==.Serelyth:BAAANQADCgMIAwABNQAECgoKMQAMAMsgAA==.Serfort:BAAANQADCggIFQAAAA==.',
Sh='Shadowpaksz:BAABNQAECn8mAAQaAAgKvxvLcwDBAQAaAAcKcBvLcwDBAQAVAAcK7hegCgBOAQAkAAMKThIxGACwAAAAAA==.Shadowsneak:BAABNQAECn8bAAMiAAYK9AxfFgApAQAiAAYK9AxfFgApAQAgAAEKkgaRpAAzAAAAAA==.Shadowstride:BAAANQABCgQIBAAAAA==.Shadowvixen:BAAANQAECgMIBAAAAA==.Shaelistra:BAABNQAECn8hAAIQAAgKrA9+BwA1AQAQAAgKrA9+BwA1AQAAAA==.Shalilama:BAACNQAFFH8KAAIBAAMK0iPmBgAzAQABAAMK0iPmBgAzAQA1AAQKfzkAAgEACgqIJXwBANEDAAEACgqIJXwBANEDAAAA.Shamanana:BAABNQAECn8bAAIZAAkKiQsfFQAWAgAZAAkKiQsfFQAWAgAAAA==.Shamanic:BAAANQAECgQIBAAAAA==.Shamboli:BAAANQADCggIEgAAAA==.Shamirah:BAAANQADCgcJCQAAAA==.Shaï:BAAANQAECgcICwAAAA==.Shenderp:BAABNQAECn8bAAIaAAcK3BDPOAAfAQAaAAcK3BDPOAAfAQAAAA==.Shgrmclt:BAAANQADCgQIBAAAAA==.Shinerbock:BAABNQAECn8bAAInAAcKOQvJGQBHAQAnAAcKOQvJGQBHAQAAAA==.Shockitti:BAAANQAECgIIAwAAAA==.Shtark:BAAANQAECgUICgAAAA==.',
Si='Sianvar:BAAANQAECggIEgAAAA==.Silshara:BAABNQAECn8hAAIPAAkKqw1IHgDsAQAPAAkKqw1IHgDsAQAAAA==.Silverjustis:BAABNQAECn8kAAISAAgKIAWueQDVAAASAAgKIAWueQDVAAAAAA==.Siwe:BAABNQAECn8hAAQGAAgK/By5YgD5AQAGAAcKjBq5YgD5AQAZAAYKqhmAGADgAQABAAIKCxRF+AB6AAAAAA==.Six:BAAANQAECgIIAgABNQAECgMIBAAJAAAAAA==.',
Sk='Skip:BAAANQADCgMIAwAAAA==.Skittulz:BAAANQADCgQIBQAAAA==.Skribblez:BAABNQAECn8nAAMSAAgKvRpqcABPAgASAAgKvRpqcABPAgAKAAQKJBTqwQD4AAAAAA==.Skyanna:BAAANQAECgIIBAAAAA==.Skydaisey:BAAANQABCgIIAQAAAA==.',
Sl='Slackback:BAAANQAECggIDgABNQAFFAMICQAGAHIXAA==.Sloop:BAAANQADCgYIEAAAAA==.Sloot:BAAANQAECgcIEQAAAA==.',
Sn='Sneasel:BAAANQAECgMIBgABNQAECgQIBQAJAAAAAA==.Snoogins:BAAANQAECgEIAgABNQAECgcIBwAJAAAAAA==.',
So='Sockszz:BAABNQAECn8uAAIQAAkKnCWjAgCHAwAQAAkKnCWjAgCHAwAAAA==.Songblade:BAAANQABCggIEwAAAA==.Soulsy:BAABNQAECn8fAAISAAgKwiB6TQCsAgASAAgKwiB6TQCsAgAAAA==.Soulvalk:BAAANQADCgQIBAAAAA==.Sourmagic:BAABNQAECn8fAAMjAAkKIhJkCwDRAAAMAAgK0A7XygDwAQAjAAMKjhVkCwDRAAAAAA==.',
Sp='Splendorae:BAABNQAECn8fAAIKAAkKjxWKSgA+AgAKAAkKjxWKSgA+AgAAAA==.Sprints:BAABNQAECn8uAAIBAAgK0xPWHAB5AQABAAgK0xPWHAB5AQAAAA==.Spritz:BAABNQAECn8yAAMGAAoKoCBbLgDDAgAGAAgKwB9bLgDDAgABAAkKvB0PFgClAQAAAA==.Sprucewillis:BAAANQADCgQIDAABNQAECgcIBwAJAAAAAA==.Spwany:BAAANQAECgIIAQAAAA==.Spyderelite:BAABNQAECn8dAAIDAAkKsw4ECgBXAgADAAkKsw4ECgBXAgAAAA==.',
Sq='Squirrel:BAABNQAECn8ZAAIHAAgKLxRIgQAKAgAHAAgKLxRIgQAKAgAAAA==.',
Ss='Ssuperss:BAAANQADCgQICgAAAA==.',
St='Stabbot:BAAANQAECgMJBAABNQAECgoKFQALANASAA==.Stankstarstu:BAAANQAECgcIBwAAAA==.Starblood:BAAANQAECgEIAwAAAA==.Starspeaker:BAAANQAECgQICwAAAA==.Stellf:BAAANQADCgYIBgAAAA==.Steviewonder:BAAANQADCgUIBQAAAA==.Stilleta:BAAANQADCgUIBQAAAA==.Stompmyballs:BAAANQAECgYIEwABNQAFFAkJHwATALYiAA==.Stoogotz:BAAANQADCgIIBAAAAA==.Studlebane:BAAANQAECgUIEAAAAA==.Studlepalm:BAAANQAECgUIDgABNQAECgUIEAAJAAAAAA==.',
Su='Sundaresh:BAAANQADCgEIAQAAAA==.Sunwing:BAABNQAECn8eAAIaAAkKvyDWKgC9AgAaAAkKvyDWKgC9AgAAAA==.Supersasian:BAAANQAECggICgAAAA==.Supersheep:BAAANQAECgYIDAAAAA==.Suvien:BAAANQAECgMIBgAAAA==.',
Sx='Sxtitan:BAAANQAECgEIAQAAAA==.',
Sy='Sylvarian:BAABNQAECn8fAAIoAAgKWg7cAgD4AQAoAAgKWg7cAgD4AQAAAA==.Sylvinna:BAAANQAECgEIAQAAAA==.Sylvren:BAAANQAECgEIAQAAAA==.',
Ta='Tagda:BAAANQADCggICAAAAA==.Takeurland:BAAANQAECgYICwAAAA==.Tater:BAAANQABCgYICwABNQAECgEIAQAJAAAAAA==.Taterdotz:BAAANQAECgIIBAAAAA==.Tatersack:BAAANQAECgEIAQAAAA==.Tatortwats:BAAANQAFFAEIAwAAAA==.Taxdeeznutz:BAAANQADCgUIBQAAAA==.',
Te='Tengrit:BAAANQADCgcIDgAAAA==.Tephine:BAABNQAECn8cAAIZAAkKwhsgDwB4AgAZAAkKwhsgDwB4AgAAAA==.Tepicoyotl:BAABNQAECn8wAAMBAAoK/hzqEAA+AwABAAoK/hzqEAA+AwAGAAEKAADFYAEYAAAAAA==.',
Th='Thaymor:BAAANQADCgcJCgAAAA==.Thebigkitti:BAAANQADCgEIAQAAAA==.Thelonecone:BAACNQAFFH8MAAMOAAUKIBjaBQDaAAAOAAQKIBjaBQDaAAANAAEKAAAVGQAAAAA1AAQKfzgAAg4ACgoEJI4GAHoDAA4ACgoEJI4GAHoDAAAA.Theodor:BAAANQAECgMIBgAAAA==.Theoganth:BAAANQAECgMIBAABNQAFFAIIAgAJAAAAAA==.Therym:BAAANQADCgEIAQABNQAECggIDQAJAAAAAA==.Thomwizard:BAAANQADCggIFAAAAA==.Thormorn:BAAANQAECgUICQAAAA==.Thunnha:BAAANQAECgEIAQAAAA==.',
Ti='Tierali:BAAANQAECgMIBQAAAA==.Tio:BAAANQAECgEIAgAAAA==.',
To='Toastedsushi:BAAANQADCgYIBgAAAA==.Toofwess:BAABNQAECn8VAAILAAoK0BIwAQAeAgALAAoK0BIwAQAeAgAAAA==.Torrinchaos:BAAANQADCgQIBAAAAA==.Tosala:BAAANQAECgMIBgAAAA==.Totemkiller:BAABNQAECn8WAAIGAAcKQw9aIgAyAQAGAAcKQw9aIgAyAQAAAA==.',
Tr='Traael:BAABNQAECn8lAAIHAAgKJROFHQCiAQAHAAgKJROFHQCiAQAAAA==.Treesap:BAABNQAECn8gAAIpAAkKIyBfBADKAgApAAkKIyBfBADKAgAAAA==.Trinityeve:BAABNQAECn8XAAIDAAYKhAfnBwCgAAADAAYKhAfnBwCgAAAAAA==.Trmz:BAAANQAECggIDAAAAA==.Trnzlock:BAAANQAECgYIEAABNQAECggIDAAJAAAAAA==.Tryzk:BAAANQAECggICAAAAA==.Trîggêr:BAAANQAECgEIAQAAAA==.',
Tu='Tulanii:BAAANQAECgEIAgAAAA==.Tularana:BAABNQAECn8gAAIMAAoKlBapLQBoAQAMAAoKlBapLQBoAQAAAA==.Tumble:BAAANQAECgQIDAAAAA==.',
Tw='Twignberryz:BAAANQAECgQICAABNQAECgcIBwAJAAAAAA==.Twinkie:BAAANQAECgcIEAAAAA==.Twodogz:BAABNQAECn8iAAIHAAcKTiFKGgCwAQAHAAcKTiFKGgCwAQAAAA==.',
Ty='Tyious:BAABNQAECn8nAAQOAAoKyRO0MgAVAgAOAAkKWRa0MgAVAgAbAAUKkA8OnwC/AAANAAUKOQb3MACyAAAAAA==.Tyndara:BAABNQAECn8gAAIKAAcK7BOkEwC2AQAKAAcK7BOkEwC2AQAAAA==.Tyìous:BAAANQAECgcIBgABNQAECgoKJwAOAMkTAA==.',
['Tü']='Tüesdaÿ:BAAANQAECgQIBQAAAA==.',
Ub='Ubavoke:BAAANQAECggICQAAAA==.',
Uk='Ukita:BAACNQAFFH8GAAISAAMKcRFGCgDFAAASAAMKcRFGCgDFAAA1AAQKfy4AAhIACQoHI20qAB0DABIACQoHI20qAB0DAAAA.',
Ur='Ursane:BAABNQAECn81AAMTAAoKBRklIwB4AQATAAoKBRklIwB4AQAfAAQKSgjzIgCeAAAAAA==.Ursully:BAABNQAECn8hAAIdAAgKEBbVCQBeAQAdAAgKEBbVCQBeAQAAAA==.',
Uz='Uzi:BAABNQAECn8cAAIDAAcK7RE3DwAIAgADAAcK7RE3DwAIAgAAAA==.',
Va='Vaardux:BAAANQAECgQIBQAAAA==.Valentíne:BAAANQADCgYIDAAAAA==.Valhalla:BAAANQAECgMICQAAAA==.Vanish:BAAANQAFFAIIAgAAAA==.Vanncint:BAABNQAECn8XAAIMAAcKLAq5WgAIAQAMAAcKLAq5WgAIAQAAAA==.Vashie:BAAANQADCgYICgAAAA==.',
Ve='Velorius:BAAANQAECgUIBAAAAA==.Vexus:BAACNQAFFH8JAAIGAAMKchdcBQD8AAAGAAMKchdcBQD8AAA1AAQKfyMAAgYACgo7HUwqANcCAAYACgo7HUwqANcCAAAA.',
Vi='Vinecone:BAAANQAECgQIBAAAAA==.Vivifyght:BAAANQAECgIIBAAAAA==.Vixly:BAAANQADCggIGgAAAA==.',
Vl='Vladios:BAABNQAECn8aAAISAAcK2gRHAwEaAQASAAcK2gRHAwEaAQAAAA==.',
Vo='Voidmommy:BAAANQAECgEIAgABNQAECgUIEgAJAAAAAA==.Vordarian:BAAANQAECgEIAQAAAA==.',
Wa='Walolas:BAAANQAECgEIAQAAAA==.Wardrak:BAAANQAECgIIBQAAAA==.Warlokholmes:BAAANQADCgIIAgAAAA==.Warrax:BAAANQADCgcIEAAAAA==.Watchmeburst:BAAANQAECgEIAgAAAA==.',
We='Wezleydoomz:BAAANQADCgYIBgABNQAECgkJLgAHAOoiAA==.',
Wh='Whaler:BAABNQAECn8rAAITAAoK7hrhBgBYAgATAAoK7hrhBgBYAgAAAA==.Whitebison:BAAANQAECgEIAQAAAA==.',
Wi='Windeagle:BAAANQADCgQIBAABNQAECgUJBwAJAAAAAA==.Windowskey:BAAANQAECgYIBQABNQAECgkJFAARAFgcAA==.',
Wu='Wuzntmyfault:BAAANQAECgUICQAAAA==.',
Wy='Wyldfyire:BAABNQAECn8aAAILAAcKzAbSIABMAQALAAcKzAbSIABMAQAAAA==.',
Xa='Xaven:BAABNQAECn8fAAIgAAgK/BMVCACbAQAgAAgK/BMVCACbAQAAAA==.Xavenuke:BAAANQADCgcJDQABNQAECggIHwAgAPwTAA==.',
Xi='Xiaotao:BAAANQAECgMIBAAAAA==.',
Xt='Xtraxtra:BAAANQADCggICQABNQAECggIJQAPADobAA==.',
Ye='Yeetcannon:BAAANQAECggIAQAAAA==.Yellenheller:BAAANQAECgIIAgABNQAECgkJKgAMABgXAA==.',
Yo='Yoan:BAAANQAECggIFAAAAQ==.Yoga:BAABNQAECn8YAAIFAAcKeyUcAgBdAgAFAAcKeyUcAgBdAgAAAA==.',
Za='Zabra:BAAANQAECgEIAQAAAA==.Zahshia:BAAANQAECgYIEQAAAA==.Zakilron:BAAANQAECgUIBwAAAA==.Zalarian:BAAANQADCgEIAQAAAA==.Zaldina:BAAANQADCgIIAgAAAA==.Zathaeus:BAACNQAFFH8RAAIYAAUKMRqZCABwAQAYAAUKMRqZCABwAQA1AAQKfykAAhgACgqEH/MGAGIDABgACgqEH/MGAGIDAAAA.Zaylian:BAABNQAECn8oAAIcAAoKTRmfIgCGAgAcAAoKTRmfIgCGAgAAAA==.Zayragossa:BAACNQAFFH8FAAICAAIKPh7mDQCnAAACAAIKPh7mDQCnAAA1AAQKfy0AAwIACgoyI1wJAIEDAAIACgoyI1wJAIEDAAMAAgpNIZBDALcAAAAA.Zayrah:BAAANQAECgYIEwABNQAFFAIIBQACAD4eAA==.',
Ze='Zeerkk:BAABNQAECn8lAAMDAAgKSBi8GwCPAQADAAUKrRq8GwCPAQACAAQKfhNk6gD0AAAAAA==.Zergmark:BAAANQADCgUIBgAAAA==.Zervise:BAAANQAECgEIAQAAAA==.',
Zi='Zirdford:BAAANQAECgIIAgABNQAECggIEgAJAAAAAA==.Zirilian:BAAANQADCgQICAABNQAECggIJgASAEUPAA==.',
Zo='Zoomzoom:BAAANQAECgUICAABNQAFFAQIDAAVAHIJAA==.Zouris:BAAANQAECgUICAAAAA==.',
Zu='Zulkraa:BAABNQAECn8WAAICAAYKywuVVQDYAAACAAYKywuVVQDYAAAAAA==.',
Zy='Zynreth:BAAANQADCgIIAgAAAA==.',
['Ài']='Àirén:BAABNQAECn8aAAQVAAgK3SAzFADDAgAVAAgK3SAzFADDAgAaAAEKhxvz+QA4AAAkAAEKRhD+KAAyAAAAAA==.',
['Åb']='Åbon:BAAANQADCgcIEAAAAA==.',
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
