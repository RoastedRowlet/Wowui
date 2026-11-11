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

local lookup = {'Unknown-Unknown','Rogue-Assassination','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Affliction','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Paladin-Protection','Priest-Discipline','Monk-Mistweaver','DemonHunter-Vengeance','Druid-Balance','Warrior-Protection','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','DemonHunter-Devourer','Mage-Frost','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Hunter-Marksmanship','Evoker-Augmentation','Monk-Brewmaster','Druid-Guardian','Hunter-Survival',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abbii:BAAANQADCgIIAgAAAA==.',
Ai='Aidalen:BAAANQAECgEIAQAAAA==.',
Ak='Akaidia:BAAANQAECggIBgABNQAECggIEAABAAAAAA==.',
Al='Alaplateada:BAAANQAECgQIBAAAAA==.Alckmin:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Alderan:BAAANQADCgQIBAAAAA==.Alektophobia:BAABNQAECn8XAAICAAkKixVpFwBjAQACAAkKixVpFwBjAQAAAA==.Allysaun:BAAANQAECgMIBQAAAA==.Altacia:BAAANQADCgQIBAAAAA==.',
Am='Amaurra:BAAANQABCgQIBAAAAA==.Amorina:BAABNQAECn8fAAIDAAoKPxF5uQCqAQADAAoKPxF5uQCqAQAAAA==.',
An='Anda:BAAANQAECgEIAQAAAA==.Andill:BAAANQAECgQICAAAAA==.Andracca:BAAANQAECgUIBQAAAA==.Andromeda:BAAANQAECgUICQAAAA==.Aner:BAAANQADCgEIAQAAAA==.Angellete:BAACNQAFFH8OAAMEAAYK9BeIDQBKAQAEAAUK9BeIDQBKAQAFAAEKAAB0BQAAAAA1AAQKfyoAAgQACgpEH75OAJ0CAAQACgpEH75OAJ0CAAAA.Angrygnome:BAABNQAECn9FAAMGAAoK2R9cAwAQAwAGAAoKLRtcAwAQAwAHAAoKQx5KGACvAgAAAA==.Angélique:BAAANQAECggIDgABNQAFFAYIDgAEAPQXAA==.Anieros:BAAANQAECgEIAgABNQAFFAUIDAACAN0OAA==.',
Ar='Arai:BAAANQADCgQIBQAAAA==.Arax:BAAANQAECggIDQAAAA==.Arcamoon:BAAANQADCgEIAQAAAA==.Arianpali:BAABNQAECn8fAAIDAAgKCgtP1gAYAQADAAgKCgtP1gAYAQAAAA==.Armâgeddon:BAABNQAECn8qAAIEAAkKcyB+LAAKAwAEAAkKcyB+LAAKAwAAAA==.Arthritas:BAAANQADCgQIBAABNQAECgoKLgAIALgQAA==.Artistic:BAAANQADCgcIGQAAAA==.',
As='Astyl:BAAANQAECgYIBgAAAA==.',
At='Athurnz:BAAANQABCgIIAgAAAA==.Atropós:BAABNQAECn8cAAIJAAoKpgr/cwC0AQAJAAoKpgr/cwC0AQAAAA==.Attachedplag:BAABNQAECn8mAAMEAAkKhBEgWADjAQAEAAkKhBEgWADjAQAFAAEKPQb8NgArAAAAAA==.Atulwa:BAAANQADCgMIAwAAAA==.',
Au='Autodrive:BAAANQAECgYIBgAAAA==.',
Az='Azmodious:BAAANQABCgIIAgAAAA==.',
Ba='Baconhuntard:BAAANQAECgMIAwAAAA==.Bambislayer:BAAANQADCgYIBwAAAA==.Banannana:BAAANQAECgUIBgAAAA==.Banzen:BAAANQADCggIGwAAAA==.Battle:BAEANQADCgIIAgABNQAECgoKOAAKACAfAA==.',
Be='Beardedyeti:BAAANQABCgQIBAAAAA==.Beginagain:BAAANQADCgcIFAAAAA==.Belgran:BAABNQAECn8xAAILAAoKKxnQKwDuAQALAAoKKxnQKwDuAQAAAA==.Bernese:BAAANQAECgcICQAAAA==.Berunma:BAABNQAECn8bAAIMAAgKlw23rgCnAQAMAAgKlw23rgCnAQAAAA==.',
Bh='Bhain:BAABNQAECn8cAAQHAAoKyxtFIACGAgAHAAoKsRpFIACGAgAGAAMKxBvmCwDuAAANAAQKshZcGgCTAAAAAA==.',
Bi='Bileshots:BAAANQAECgcIDAAAAA==.Biowolf:BAACNQAFFH8KAAIJAAQK2QUEKwC3AAAJAAQK2QUEKwC3AAA1AAQKfxoAAgkACQqwEeWyAB0CAAkACQqwEeWyAB0CAAAA.Birdhunter:BAAANQAECgYIBgAAAA==.Bishopixixix:BAAANQABCgMIAwABNQAECgQIBAABAAAAAA==.Bishopxix:BAAANQAECgQIBAAAAA==.Bits:BAAANQAECgQIDQAAAA==.',
Bj='Bjoren:BAABNQAECn8vAAMOAAoKqSCIFwAaAwAOAAoKqSCIFwAaAwAPAAEKAAADlwAKAAAAAA==.',
Bl='Blackki:BAAANQADCgQIBQAAAA==.Bloodbaron:BAAANQAECggIDAABNQAECggIIQAHAGYVAA==.',
Bo='Bootiebang:BAABNQAECn8kAAIQAAYK4AZ8MAA7AQAQAAYK4AZ8MAA7AQAAAA==.Bootieknight:BAAANQADCgcIBwAAAA==.Bootycaall:BAAANQADCgcIDgAAAA==.Boxxie:BAAANQADCgcIFQAAAA==.',
Br='Branches:BAAANQADCgMIAwAAAA==.Brockshot:BAAANQAECgQIBQAAAA==.',
Bu='Bucknekkid:BAAANQAECgUICQAAAA==.Buckwhild:BAABNQAECn8rAAMOAAoKHh2xMwCZAgAOAAoKHh2xMwCZAgAPAAEKAADLigAfAAAAAA==.',
By='Byleth:BAAANQADCgIIAgAAAA==.',
Ca='Caladbolg:BAABNQAECn9JAAMRAAoKPCMaBgDsAgARAAoKPCMaBgDsAgADAAUKnhQZDwG9AAAAAA==.Canadaisheal:BAABNQAECn8XAAMSAAgKuw8EBwBUAQASAAYKHBIEBwBUAQAPAAIKvAeyYgAsAAAAAA==.Catslol:BAAANQADCgIIAwAAAA==.',
Ce='Cerñuñños:BAAANQAECgIIAgAAAA==.Cesàrè:BAABNQAECn8YAAITAAYKhQm9JwC1AAATAAYKhQm9JwC1AAAAAA==.',
Ch='Chahra:BAAANQAECgUICQAAAA==.Chamuki:BAABNQAECn8cAAMIAAoKshWYOgA+AQAIAAkKeRaYOgA+AQAUAAEKOxBgMAA8AAABNQAFFAcIHAAVAPAZAA==.Chaosbolt:BAAANQAECgUIBQAAAA==.Chuubak:BAAANQAECggIEAAAAA==.',
Cl='Clangeddin:BAAANQADCgIIAgAAAA==.Clangedin:BAABNQAECn8XAAMFAAgKkg8BFgADAQAFAAgKkg8BFgADAQAEAAUKgwZq7QCEAAAAAA==.',
Co='Cocomami:BAAANQADCgUIBQAAAA==.Colonidus:BAAANQAECgQIBAAAAA==.Coondic:BAAANQADCgIIAgAAAA==.Corsten:BAABNQAECn8lAAIWAAoK1RPXDgCyAQAWAAoK1RPXDgCyAQAAAA==.',
Cr='Crosis:BAAANQADCgQIBQAAAA==.',
Cu='Cute:BAABNQAECn8pAAMEAAoKqBwtOgBJAgAEAAoKqBwtOgBJAgAFAAQKWxiFHgDMAAAAAA==.',
Da='Dagby:BAAANQADCgcIGwAAAA==.Dandi:BAAANQAECgIIAgAAAA==.Daneaus:BAAANQADCgMIAwABNQAECggIJwAXANUkAA==.Dangerzone:BAAANQADCgUIBQAAAA==.Darkchronos:BAAANQADCggICwAAAA==.Darkscorp:BAAANQADCgIIAgAAAA==.Darkwolf:BAAANQAECgQICAAAAA==.Darnuus:BAABNQAECn88AAMYAAoKbh3jKADAAgAYAAoKbh3jKADAAgAZAAUKCQ2FqgCeAAAAAA==.Datnv:BAAANQADCggICAAAAA==.Datromandude:BAAANQAECgMIBQAAAA==.',
De='Deadmetalhed:BAAANQADCgIIAgAAAA==.Deathbydruid:BAABNQAECn8wAAMaAAkKPw8SLgBiAQAaAAkKPw8SLgBiAQAVAAcKwAaWcQADAQAAAA==.Deathnelf:BAAANQADCgMIAwAAAA==.Deazraelle:BAABNQAECn8pAAIHAAoKThitLgBFAgAHAAoKThitLgBFAgAAAA==.Delai:BAAANQADCgMIAwAAAA==.Dellin:BAABNQAECn8mAAIVAAgKWRhnLgB6AQAVAAgKWRhnLgB6AQAAAA==.Demeco:BAEANQAFFAQIBAABNQAFFAkJGQAXAFMZAA==.Demondots:BAAANQAECgUIDAAAAA==.Denzalle:BAAANQADCgYJCQAAAA==.Devildognutz:BAAANQAECgEIAQAAAA==.',
Dh='Dhalseem:BAAANQAECgUIBQAAAA==.',
Di='Diminuendo:BAAANQAECgIIAgAAAA==.',
Do='Dogz:BAABNQAECn8VAAMbAAkKWRrGDQBsAgAbAAkKWRrGDQBsAgAUAAIKuwvUJgBNAAABNQAFFAcIHQAMAHIhAA==.Doozydruid:BAABNQAECn8UAAIVAAcKeg/rVQCAAQAVAAcKeg/rVQCAAQAAAA==.Dorozh:BAABNQAECn8XAAIGAAkKvxC8BwBCAQAGAAkKvxC8BwBCAQAAAA==.',
Dr='Draeke:BAAANQAECgEIAQAAAA==.Dragonstorm:BAAANQAECggICQAAAA==.Dragonzdemon:BAAANQADCgcICQAAAA==.Drala:BAABNQAECn8iAAIOAAcKKRd4ZACaAQAOAAcKKRd4ZACaAQAAAA==.Dreadar:BAAANQADCgMIAwABNQADCgYICgABAAAAAA==.Dreadmage:BAAANQADCgMIAwABNQADCgYICgABAAAAAA==.Dreadpally:BAAANQADCgYJCgABNQADCgYICgABAAAAAA==.Dreco:BAAANQAECgcIEQAAAA==.Driver:BAEANQAECggICAAAAA==.Drtydhn:BAAANQABCgMIAwAAAA==.Druuzak:BAABNQAECn83AAIcAAoKaQ7OCwDEAQAcAAoKaQ7OCwDEAQAAAA==.Dryconias:BAACNQAFFH8GAAIDAAIKdQ5UIgCHAAADAAIKdQ5UIgCHAAA1AAQKf00AAgMACgq6HrNDAMkCAAMACgq6HrNDAMkCAAAA.Drèadpriest:BAAANQADCgUJBAAAAA==.',
Du='Duncanmcleod:BAABNQAECn8lAAIEAAoKGxknRAAlAgAEAAoKGxknRAAlAgABNQAECgoKNgAOAEEeAA==.Dunkelzhan:BAABNQAECn8tAAIJAAoKMBMeagDNAQAJAAoKMBMeagDNAQAAAA==.',
Dv='Dvldogma:BAAANQAECgUIDQAAAA==.',
Dy='Dyana:BAABNQAECn8XAAIMAAkKAw6NqQCyAQAMAAkKAw6NqQCyAQAAAA==.',
Dz='Dz:BAABNQAECn9DAAMXAAoKpyXFBACqAwAXAAoKpyXFBACqAwADAAYKDA7I9AAzAQAAAA==.',
['Dø']='Dømimømmÿ:BAAANQAECgMIAwAAAA==.',
Ec='Ecobessie:BAAANQADCggIDgAAAA==.Ecowolf:BAAANQADCgYICgABNQADCggIDgABAAAAAA==.',
Ed='Edlund:BAABNQAECn8bAAIdAAgKTwleEAAhAQAdAAgKTwleEAAhAQAAAA==.',
El='Electricfun:BAAANQAECgMIAgAAAA==.Eligarf:BAAANQADCggICAAAAA==.Ellenaim:BAAANQAECgUICAAAAA==.Elvy:BAABNQAECn8/AAIVAAoKRRlcHAAOAgAVAAoKRRlcHAAOAgAAAA==.',
En='Enngin:BAAANQAECgMIAwAAAA==.Enroks:BAABNQAECn87AAQZAAoKBhUEOwDSAQAZAAoKBhUEOwDSAQAYAAYKZhkdggCGAQAeAAEKAAARNwAzAAAAAA==.',
Er='Erythrina:BAAANQADCgYICAAAAA==.',
Es='Esaelle:BAAANQADCggICAAAAA==.',
Ev='Evangelene:BAABNQAECn8wAAMaAAgKAxUWLAC7AQAaAAgKAxUWLAC7AQAVAAUKWgechQC8AAAAAA==.Evangelina:BAAANQADCgEIAQAAAA==.',
Ex='Exsalsior:BAACNQAFFH8MAAMCAAUK3Q4GBgDZAAAQAAQK0QbbEwDbAAACAAMKTBEGBgDZAAA1AAQKfxgAAgIACQr4E6g1AAICAAIACQr4E6g1AAICAAAA.',
Ey='Eyedoc:BAAANQABCgIIBAAAAA==.',
Fa='Fabulousness:BAAANQAECgcIEgAAAA==.Fathur:BAAANQADCggICwAAAA==.',
Fe='Fellstar:BAAANQADCgYIBgAAAA==.',
Fo='Fornix:BAAANQADCgEIAQAAAA==.',
Fu='Furryriver:BAAANQAECgUIDwAAAA==.Furussy:BAAANQADCgcIBwAAAA==.',
Ga='Galadhras:BAAANQADCgYIDAAAAA==.Galdryn:BAAANQABCgQIBQAAAA==.Gamboslice:BAABNQAECn8wAAILAAoKZxZqLQA1AgALAAoKZxZqLQA1AgAAAA==.Garkevon:BAABNQAECn8tAAMfAAkKvQi0MABUAQAfAAkKvQi0MABUAQAgAAMKPgTzlgA6AAAAAA==.',
Ge='Gevul:BAABNQAECn9jAAQHAAoKmBy2QwCHAgAHAAkKIx22QwCHAgAGAAMK+hFKOQDbAAANAAEKAADLMQAxAAAAAA==.',
Gh='Ghuun:BAABNQAECn8hAAIHAAgKZhXKaACJAQAHAAgKZhXKaACJAQAAAA==.',
Gi='Gitmerge:BAAANQADCgYIBgAAAA==.',
Gl='Glep:BAAANQADCggICwAAAA==.Glimmervoid:BAAANQAECgQICQAAAA==.',
Go='Golland:BAAANQABCgIIAgABNQAECgoKPAAZAKAaAA==.Goob:BAAANQADCgYIBgAAAA==.Gorecurse:BAAANQAECgEIAQAAAA==.',
Gr='Grandmatank:BAAANQADCgYIBgAAAA==.Greeze:BAABNQAECn8ZAAIDAAgKFxdkiAAWAgADAAgKFxdkiAAWAgAAAA==.Grimero:BAAANQAECggIAgAAAA==.Groinsapper:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Grozny:BAAANQAECgEIAQABNQAECgoKGwAVAGwOAA==.',
Gs='Gsstuff:BAAANQADCgIIAgAAAA==.',
Gu='Gumboslice:BAACNQAFFH8LAAIaAAUKyhcdCABDAQAaAAUKyhcdCABDAQA1AAQKfz8AAxoACgrmH1IRAMkCABoACgrmH1IRAMkCABUAAQoAAAefAAAAAAAA.Gumiho:BAABNQAECn8ZAAIYAAgKNRyBJwB5AgAYAAgKNRyBJwB5AgAAAA==.Gusgus:BAABNQAECn8qAAIcAAgKBA35EgBEAQAcAAgKBA35EgBEAQAAAA==.Guud:BAAANQAECgUIBAAAAA==.',
Gy='Gyroflux:BAAANQAECgMIAwAAAA==.',
Ha='Haackh:BAACNQAFFH8JAAIMAAQKkxGSEQBHAQAMAAQKkxGSEQBHAQA1AAQKfyUAAgwACgrAIZsTAFADAAwACgrAIZsTAFADAAAA.Habanero:BAABNQAECn8jAAIZAAkKvR/OJwAxAgAZAAkKvR/OJwAxAgAAAA==.Hadd:BAAANQADCgEJAQAAAA==.Hadrìan:BAAANQADCgYIBgAAAA==.Hadéz:BAAANQAECggIAgABNQAECgkKPAAhAHcNAA==.Hammerfist:BAABNQAECn8WAAIRAAgKOxFNHAB4AQARAAgKOxFNHAB4AQAAAA==.Hark:BAAANQADCggIGQAAAA==.Haveabubble:BAAANQADCgQIAgABNQAECggIJwAWAO4YAA==.',
He='Healvisprsly:BAAANQAECgQIBAAAAA==.Helena:BAABNQAECn8/AAMRAAoKHSOXBAATAwARAAoKHSOXBAATAwADAAgKNhpecwBIAgAAAA==.Heliarc:BAAANQADCggIHwAAAA==.',
Hi='Hidän:BAABNQAECn8bAAMHAAcKuwukvQBRAQAHAAcKuwukvQBRAQAGAAEKwgWSfgAuAAAAAA==.Himself:BAAANQADCgUIBQAAAA==.',
Ho='Holeyman:BAAANQADCgMIBAAAAA==.Hoomalu:BAAANQADCgIIAgAAAA==.',
Hu='Huund:BAAANQADCgUIBQAAAA==.Huutou:BAAANQAECgQIBQAAAA==.',
Id='Idori:BAAANQAECgUIBQAAAA==.',
Il='Illatix:BAAANQAECgQICAAAAA==.Illustriä:BAABNQAECn8YAAIMAAYKzwyF3gBEAQAMAAYKzwyF3gBEAQAAAA==.',
In='Insidious:BAABNQAECn8cAAIgAAcKlxxiMABQAgAgAAcKlxxiMABQAgAAAA==.',
Ir='Irs:BAABNQAECn8cAAIDAAkK3RgJQQBYAgADAAkK3RgJQQBYAgAAAA==.',
It='Itchydh:BAAANQADCgEJAQABNQAECgkJKQAcADIfAA==.Itchymage:BAABNQAECn8pAAMcAAkKMh+jFQBTAQAJAAkKxh2ghwBvAgAcAAQKEh2jFQBTAQAAAA==.',
Iv='Ivyrayne:BAAANQAECgEIAQAAAA==.',
Ja='Jaganash:BAAANQAECgUIBAABNQAECgoKHgAQAMQXAA==.Jakeofny:BAAANQAECgYICAAAAA==.',
Je='Jeffsgoytoy:BAAANQAECgcIDQAAAA==.',
Ji='Jighlipuff:BAABNQAECn8lAAIDAAgKZwZ/7QDxAAADAAgKZwZ/7QDxAAAAAA==.Jigs:BAABNQAECn80AAIMAAoKOQw4cwC9AQAMAAoKOQw4cwC9AQAAAA==.Jinxy:BAAANQADCggINwABNQAECgUIFAAOACUIAA==.',
Ju='Judgements:BAAANQAECgUICwAAAA==.Jug:BAAANQAECgIIAgAAAA==.Jujutanketh:BAAANQAECgUICgAAAA==.Junebugg:BAABNQAECn8dAAIJAAYKXQQSEgGGAAAJAAYKXQQSEgGGAAAAAA==.',
Ka='Kabøchi:BAABNQAECn8mAAIKAAgKQBJGIQB7AQAKAAgKQBJGIQB7AQAAAA==.Kafia:BAAANQAECgcIDwAAAA==.Kalamak:BAAANQABCgYICQAAAA==.Kaldrick:BAAANQAECgYIDAAAAA==.Kanaloa:BAAANQAECgUIDAAAAA==.Kaorin:BAAANQAECgEIAQABNQAECgoKNAAYAKMjAA==.Karindis:BAABNQAECn8vAAIUAAoKOyHlAwAYAwAUAAoKOyHlAwAYAwAAAA==.Kathulhu:BAAANQAECgQIBQAAAA==.Kayler:BAAANQAECggIEAAAAA==.',
Ke='Kegerator:BAAANQADCgQIBQAAAA==.Keldica:BAABNQAECn8aAAIHAAoKERhsMgA2AgAHAAoKERhsMgA2AgABNQAECgoKJQAZACseAA==.Kenshan:BAAANQAECgEIAQAAAA==.',
Kh='Khalinor:BAABNQAECn8bAAIXAAkKPx68IQCiAgAXAAkKPx68IQCiAgAAAA==.Khotuhn:BAAANQAECgQIBAAAAA==.',
Ki='Kickazdin:BAABNQAECn8vAAMXAAoKyx7hKADFAgAXAAkKOx/hKADFAgADAAEKAABNngE4AAAAAA==.Killadragon:BAAANQAECgUIBQAAAA==.Kiryie:BAAANQAECgUIBgAAAA==.Kitinna:BAABNQAECn8WAAMJAAcKZAOK7wC+AAAJAAcK8QKK7wC+AAAcAAEKXAQLUQAlAAAAAA==.',
Kl='Klaw:BAAANQADCgYIEAAAAA==.',
Ko='Korraa:BAABNQAECn8nAAMYAAoKBBxfTwAnAgAYAAoKBBxfTwAnAgAZAAYKKBGqsQAvAQAAAA==.',
Kp='Kprist:BAAANQAECgUIDAAAAA==.',
Kr='Kraigen:BAABNQAECn8UAAIIAAcKRg0LPAA2AQAIAAcKRg0LPAA2AQAAAA==.',
Ku='Kunzhut:BAABNQAECn8fAAMfAAgKIhWnVQC7AQAfAAgKIhWnVQC7AQALAAQKsQhUhQCJAAAAAA==.Kuroi:BAAANQADCgMIAwAAAA==.',
Ky='Kynasmira:BAAANQADCgcIEwAAAA==.',
La='Ladrona:BAAANQAECgEIAQAAAA==.Laeli:BAABNQAECn8UAAIOAAUKJQhxqwDKAAAOAAUKJQhxqwDKAAAAAA==.Lailyre:BAAANQAECggIBgABNQAECggIEAABAAAAAA==.Laydin:BAABNQAECn8oAAIMAAgKIwVdAAEEAQAMAAgKIwVdAAEEAQABNQAECgkJMAAaAD8PAA==.',
Lb='Lb:BAABNQAECn8kAAMMAAoKNhrBUAAWAgAMAAoKNhrBUAAWAgAhAAUKcAsxSwAJAQAAAA==.',
Le='Legzanot:BAACNQAFFH8HAAIZAAMKlwWLHgB4AAAZAAMKlwWLHgB4AAA1AAQKf1IAAhkACgpbGE0nADQCABkACgpbGE0nADQCAAAA.Lestrade:BAABNQAECn8zAAIgAAoKxhE5JQDCAQAgAAoKxhE5JQDCAQABNQAECgoKPAAYAG4dAA==.',
Li='Lightdude:BAAANQADCgcJBwAAAA==.Lightningfox:BAABNQAECn8xAAMDAAgKhxXUpABuAQADAAgKhxXUpABuAQAXAAYKwA2diAALAQAAAA==.Lightsfallen:BAABNQAECn82AAMOAAoKQR5yFwAJAwAOAAoKQR5yFwAJAwASAAEKuwa4LQApAAAAAA==.Lilnasdormu:BAAANQADCgUIBQABNQAECgcIGQALAPARAA==.Lithia:BAAANQAECgUICAAAAA==.Littlemo:BAAANQAECgUIDwAAAA==.',
Lo='Lohnar:BAAANQAECgUIDwAAAA==.Lorzana:BAAANQADCgcIDQAAAA==.',
Lu='Lucidslock:BAAANQADCgcIEgAAAA==.Lucielbaal:BAABNQAECn8kAAIHAAgKsRr+WAC2AQAHAAgKsRr+WAC2AQAAAA==.Luckystop:BAAANQAECgEIAQAAAA==.Lumenir:BAAANQAECgEIAQAAAA==.Lunareth:BAABNQAECn8bAAIVAAoKbA7jKgCTAQAVAAoKbA7jKgCTAQAAAA==.',
Ly='Lyrska:BAAANQAECgUIEQAAAA==.Lytearrow:BAABNQAECn8bAAIMAAoKwQn+kQDlAQAMAAoKwQn+kQDlAQAAAA==.',
['Lì']='Lìvíd:BAABNQAECn8aAAMFAAcKFgwAFwD0AAAFAAcKaAsAFwD0AAAEAAQKEQfqIAGYAAAAAA==.',
Ma='Mahrylee:BAAANQAECgEIAQAAAA==.Majin:BAAANQAECgUICQAAAA==.Makbeard:BAAANQADCgYIBgABNQAECggIFgAiADERAA==.Makmobius:BAABNQAECn8WAAIiAAgKMRELCgBZAQAiAAgKMRELCgBZAQAAAA==.Manbearpally:BAAANQAECgEIAQAAAA==.Mannypack:BAAANQAECgUIBwAAAA==.Mathagni:BAAANQADCgQIBAABNQADCgcIFwABAAAAAA==.Mathau:BAAANQADCgcIFwAAAA==.Maztrix:BAAANQAECgIIAwAAAA==.',
Mc='Mcleary:BAABNQAECn8aAAIDAAUKTBB97ADzAAADAAUKTBB97ADzAAAAAA==.',
Me='Meistro:BAAANQABCgQIBAAAAA==.Meldrus:BAABNQAECn8XAAIHAAgK/gnsmQCmAQAHAAgK/gnsmQCmAQAAAA==.Mending:BAAANQAECggICgAAAA==.',
Mi='Miala:BAAANQAECgIIAgAAAA==.Midnytestorm:BAAANQADCgcJBgAAAA==.Mierna:BAABNQAECn8nAAIYAAgK+CCtMwCRAgAYAAgK+CCtMwCRAgAAAA==.Miler:BAAANQAECgcIEwAAAA==.Mirota:BAAANQADCgEJAQAAAA==.',
Mo='Moemo:BAABNQAECn8fAAMaAAcKoCMfGgBpAgAaAAcKoCMfGgBpAgAVAAEKAABBnQAAAAAAAA==.Mogryn:BAABNQAECn8tAAIMAAoKuRjoMgBqAgAMAAoKuRjoMgBqAgAAAA==.Mommybree:BAAANQAECgIIAgAAAA==.Monkeydluffy:BAAANQAECgMIAgAAAA==.Monotonous:BAAANQADCgUIEAAAAA==.Moondog:BAAANQAECgEIAQAAAA==.Moonwarriorx:BAABNQAECn8XAAIFAAkKcxNNCQDxAQAFAAkKcxNNCQDxAQAAAA==.Morganalefey:BAAANQADCgMIBAAAAA==.Morsecode:BAAANQAECgQIBAABNQAECggIKwAKAIIUAA==.Morthok:BAABNQAECn8XAAIHAAcK/BEKcgBvAQAHAAcK/BEKcgBvAQAAAA==.Mosh:BAABNQAECn8jAAIjAAcK8xyEDQAjAgAjAAcK8xyEDQAjAgAAAA==.',
Mu='Muskelunge:BAAANQAECgQIBwAAAA==.Mustachekick:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãf:BAAANQADCggICQAAAA==.',
Na='Naelyn:BAABNQAECn8oAAIMAAkKiRejcwApAgAMAAkKiRejcwApAgAAAA==.Nafir:BAAANQAECgYIBgAAAA==.Nakky:BAAANQADCggICwAAAA==.Nazgor:BAABNQAECn8uAAIfAAoKVhwTFABCAgAfAAoKVhwTFABCAgAAAA==.',
Ne='Necrodragon:BAAANQADCgMIBgAAAA==.Necrosius:BAAANQADCgEIAQAAAA==.Newwt:BAAANQADCgcIBwAAAA==.',
Ny='Nyxstalia:BAAANQADCgUIAwAAAA==.Nyyx:BAAANQAECgUIDAAAAA==.',
Oa='Oath:BAABNQAECn8eAAMQAAoKxBejLAA5AgAQAAoK7ROjLAA5AgACAAUK4RZfWwBKAQAAAA==.',
Ob='Obscyra:BAABNQAECn8lAAIcAAYKyw2RGAAzAQAcAAYKyw2RGAAzAQABNQAECgoKGwAVAGwOAA==.',
Oc='Ochiie:BAAANQAECgQIAgAAAA==.Ocho:BAAANQADCgUIBQAAAA==.',
Od='Oddsham:BAAANQADCgYIBwAAAA==.Oddyeppyep:BAAANQADCgYIEQAAAA==.',
Of='Offhand:BAAANQADCggJBwAAAA==.',
Ol='Olmek:BAACNQAFFH8MAAMEAAYKwQUKGwA8AQAEAAYKwQUKGwA8AQAFAAEK7AnzBgA9AAA1AAQKf1sAAwQACgrzI4AOABwDAAQACgp6I4AOABwDAAUABQpcI7YMAKIBAAAA.',
Oo='Oochie:BAABNQAECn8pAAIOAAkKfQ1LXgCwAQAOAAkKfQ1LXgCwAQAAAA==.Oochiee:BAAANQAECgQIBQAAAA==.Oochiië:BAAANQAECgQIBQAAAA==.',
Op='Oprahwndfury:BAAANQAECgYIBQABNQAECgQIBAABAAAAAA==.',
Pa='Palanoris:BAAANQABCggIGwAAAA==.Palasades:BAABNQAECn8eAAIDAAkKWAgyugBHAQADAAkKWAgyugBHAQAAAA==.Palelore:BAAANQAECgUICQAAAA==.Pallydussy:BAAANQAECgMIAwAAAA==.Pallymarc:BAAANQADCgQIBAAAAA==.Pandalorian:BAABNQAECn82AAIOAAoKSBYYSgBHAgAOAAoKSBYYSgBHAgAAAA==.Papapumpies:BAABNQAECn9IAAIEAAoK6yLTFwDlAgAEAAoK6yLTFwDlAgAAAA==.Parlow:BAAANQADCggIGQAAAA==.Pazzo:BAAANQAECgUIBQAAAA==.',
Ph='Pharaa:BAABNQAECn8qAAIPAAgKwgf0KQAdAQAPAAgKwgf0KQAdAQAAAA==.Philandre:BAAANQAECgQIBwAAAA==.',
Pi='Picoso:BAABNQAECn8VAAIJAAcK7AX00gDzAAAJAAcK7AX00gDzAAAAAA==.Piianna:BAABNQAECn8vAAIOAAoKJBhCLwCrAgAOAAoKJBhCLwCrAgAAAA==.Pikshunoob:BAAANQADCgIIAgAAAA==.Pizzaroll:BAABNQAECn84AAIkAAoKIyEcBgDoAgAkAAoKIyEcBgDoAgAAAA==.',
Pl='Ploppy:BAAANQADCgIIAgAAAA==.',
Po='Pomégranate:BAAANQADCggICgAAAA==.Popeweaseliv:BAAANQABCgYIBgABNQAECgoKJQAMAMQjAA==.',
Pu='Puckster:BAABNQAECn8UAAIVAAUKzQJgaQBzAAAVAAUKzQJgaQBzAAAAAA==.',
['Pø']='Pøwe:BAAANQADCgUICAABNQAECgQIBAABAAAAAA==.',
Qa='Qatbarph:BAAANQAECgYIEgAAAA==.',
Qi='Qikkaw:BAABNQAECn8rAAMYAAgKUxG+mgBEAQAYAAgKUxG+mgBEAQAZAAYKGAyDkwDNAAAAAA==.',
Qu='Quantos:BAABNQAECn8sAAIkAAgKUxHCJQBBAQAkAAgKUxHCJQBBAQAAAA==.',
Ra='Raatha:BAABNQAECn8oAAIDAAgK9hkvmADzAQADAAgK9hkvmADzAQAAAA==.Raganar:BAABNQAECn80AAIRAAgKBAwCKwAHAQARAAgKBAwCKwAHAQAAAA==.Rago:BAAANQAECgcICwAAAA==.Rasz:BAABNQAECn89AAMMAAkKDBttTwAaAgAMAAkKDBttTwAaAgAhAAYKgg3sSQARAQAAAA==.Rayjean:BAAANQADCgMIBQABNQAECgYIBgABAAAAAA==.',
Re='Regelia:BAAANQADCgcIBwAAAA==.Reider:BAAANQAECgMIAwAAAA==.Relmax:BAABNQAECn8YAAIWAAoKMwa9HwDnAAAWAAoKMwa9HwDnAAAAAA==.Rennia:BAAANQAECgIIAgABNQAECggIEAABAAAAAA==.Renri:BAAANQAECgMIAwAAAA==.Renzu:BAAANQADCgYIAQAAAA==.',
Rh='Rhonwynn:BAABNQAECn8rAAIYAAgKgxiMOQAcAgAYAAgKgxiMOQAcAgAAAA==.',
Ri='Rikershipdwn:BAAANQAECggIDQAAAA==.Rimrave:BAABNQAECn8nAAMWAAgK7hiNEgB5AQAWAAcKdBeNEgB5AQAEAAgKNBD4kwBDAQAAAA==.Ritobeans:BAAANQADCggICwAAAA==.',
Rk='Rk:BAABNQAECn8mAAIdAAcKJA3AEAAZAQAdAAcKJA3AEAAZAQABNQAECgoKJQAaACsNAA==.',
Ro='Robertkenway:BAABNQAECn8tAAIlAAkK2wviBwDnAQAlAAkK2wviBwDnAQABNQAECgoKJQAaACsNAA==.Roberto:BAAANQADCggICgAAAA==.Rod:BAABNQAECn8nAAITAAoKCRM1GwDPAQATAAoKCRM1GwDPAQAAAA==.Rokte:BAABNQAECn8gAAINAAoK4xKmBgDyAQANAAoK4xKmBgDyAQABNQAECgoKIAANAOMSAA==.Rollhots:BAAANQAECgYIDQAAAA==.Rook:BAABNQAECn83AAMNAAoKtyNrAQBIAwANAAoKACJrAQBIAwAHAAQKxR7PfQBRAQAAAA==.Rooke:BAABNQAECn8fAAIEAAkKoRrEegAoAgAEAAkKoRrEegAoAgABNQAECgoKNwANALcjAA==.Rorsh:BAAANQAECgQIBAAAAA==.Rosekenway:BAABNQAECn8lAAMaAAoKKw0YIwDAAQAaAAoKKw0YIwDAAQAVAAEKwwGOwgAfAAAAAA==.',
Rr='Rratt:BAAANQADCgcIDwAAAA==.',
Ru='Rubyknight:BAAANQADCgYICQAAAA==.Running:BAAANQAECgQICAAAAA==.',
['Rî']='Rîkku:BAAANQADCgEIAQAAAA==.',
Sa='Safewaybag:BAAANQADCgQIBAAAAA==.Samartyr:BAAANQAECgUIDwAAAA==.Sangwynaris:BAAANQADCggIDgAAAA==.Sanilien:BAAANQAECgQICQAAAA==.Saphiiraa:BAAANQADCgYIBgAAAA==.Sathara:BAAANQADCgEIAQAAAA==.',
Sc='Scorpmage:BAABNQAECn8uAAMcAAkKiRe2CwDGAQAcAAkKiRe2CwDGAQAJAAEKHA6UVAE0AAAAAA==.',
Se='Sedrick:BAABNQAECn8yAAQXAAoK5xowMgBFAgAXAAkKwxkwMgBFAgADAAkK1hJ/wgCXAQARAAUK4xM3MADnAAAAAA==.Sekaholic:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekendipity:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekhmett:BAAANQADCgIIAgAAAA==.Sekndestroy:BAAANQAECgIIAgAAAA==.Seksational:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Sekthyr:BAAANQADCgcIDgABNQAECgIIAgABAAAAAA==.Sekzen:BAAANQADCgUJDgABNQAECgIIAgABAAAAAA==.Sepulveda:BAAANQAECgQIBAABNQAECgcIHwAaAKAjAA==.',
Sh='Shamtune:BAACNQAFFH8NAAIYAAUK/BEAEQAvAQAYAAUK/BEAEQAvAQA1AAQKfyYAAxgACgoXFtBIAD8CABgACgoXFtBIAD8CABkAAQqdDkEuAToAAAAA.Sharayman:BAAANQAECgYIBgAAAA==.Shattered:BAAANQAECgIIAgAAAA==.Shaydra:BAABNQAECn8oAAILAAgKIBU3QwC3AQALAAgKIBU3QwC3AQAAAA==.Shazool:BAABNQAECn80AAMYAAoKoyODCQB1AwAYAAoKoyODCQB1AwAeAAQK/gqTJwDqAAAAAA==.Shevee:BAAANQADCgEIAQAAAA==.Shifterz:BAAANQAECgUICQAAAA==.Shrieke:BAAANQADCgYIBgAAAA==.Shrubbery:BAABNQAECn8XAAIkAAkKhAxjKwA8AQAkAAkKhAxjKwA8AQAAAA==.Shtialdryn:BAAANQADCgYIBgAAAA==.',
Si='Siarra:BAAANQADCgMIAwAAAA==.Sind:BAAANQADCgIIAgABNQAECgcIFAAHACcKAA==.Sindella:BAABNQAECn8UAAMHAAcKJwrIkQAiAQAHAAcKJwrIkQAiAQAGAAEKFgPNhQAjAAAAAA==.Sindrè:BAAANQABCgUIBQABNQAECgcIFAAHACcKAA==.Sinna:BAAANQADCgYICgAAAA==.Sinpriest:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.',
Sk='Skedaddle:BAAANQAECgQICgABNQAECgkJNgAcAB0hAA==.',
Sl='Slashgquit:BAABNQAECn8ZAAIgAAcKVCJCMABQAgAgAAcKVCJCMABQAgAAAA==.Slumbermist:BAABNQAECn8rAAIKAAgKghTsLACyAQAKAAgKghTsLACyAQAAAA==.',
Sn='Snazzi:BAABNQAECn8kAAIZAAgKTw2RfACuAQAZAAgKTw2RfACuAQAAAA==.Snowtitan:BAAANQADCgUIBQAAAA==.',
So='Solam:BAAANQAECgMIAwAAAA==.',
Sp='Sploob:BAAANQADCgUIBQAAAA==.',
St='Stabbs:BAAANQADCggIDgAAAA==.Steph:BAAANQAECgIIAgAAAA==.Strawberyy:BAAANQAECgMIAgABNQAFFAYIDgAEAPQXAA==.Strongboy:BAAANQADCgUIBwAAAA==.Stx:BAAANQADCggICAABNQAECggIFAAlAN8PAA==.',
Su='Survival:BAAANQAECgIIAgAAAA==.',
Sy='Syndar:BAABNQAECn8lAAMZAAoKKx41KQDcAgAZAAkKsh81KQDcAgAYAAIK1g+gxwB1AAAAAA==.Synthetic:BAABNQAECn8hAAIGAAcKog0bDADrAAAGAAcKog0bDADrAAAAAA==.',
Sz='Szasstaam:BAAANQAECggIBQAAAA==.',
Ta='Talionsauron:BAAANQADCggIAgAAAA==.Tandá:BAAANQADCgMIAwABNQADCggICgABAAAAAA==.Tarnaris:BAAANQADCgIIAgAAAA==.Tattersaile:BAAANQADCgUIBwAAAA==.',
Te='Tecsaran:BAAANQAECgYICgABNQAECgoKJQAZACseAA==.Tekis:BAAANQAECgQICAAAAA==.Tensanio:BAAANQAECgUIBAAAAA==.',
Th='Thalira:BAAANQAECggIDwAAAA==.Thalrix:BAABNQAECn8mAAIDAAoKwhI8awDnAQADAAoKwhI8awDnAQAAAA==.Thebiznitch:BAAANQADCgUIBAAAAA==.Theholyboi:BAAANQAECgUJBwAAAA==.Thetowelie:BAAANQADCgMIAwAAAA==.Thickneck:BAAANQADCgUIBQAAAA==.',
Ti='Tieson:BAAANQAECgUIDAAAAA==.Tinkera:BAAANQADCgcIEQAAAA==.Titanosaurus:BAAANQAECgIIAgAAAA==.',
To='Tomcruise:BAAANQABCgUICAABNQAECgIIAgABAAAAAA==.Torridwells:BAAANQAECgUICQAAAA==.',
Tr='Triebryn:BAAANQABCgQIBgAAAA==.Troag:BAABNQAECn8iAAIYAAcKNBaYUwCtAQAYAAcKNBaYUwCtAQAAAA==.Troagstar:BAABNQAECn8iAAIZAAcKIA9MegAIAQAZAAcKIA9MegAIAQAAAA==.',
Tu='Tubbytoe:BAAANQAECgEIAQAAAA==.',
Ty='Tyraana:BAACNQAFFH8FAAIIAAQKWg+bDQDRAAAIAAQKWg+bDQDRAAA1AAQKfzwAAwgACgpVH8ARAIoCAAgACgpVH8ARAIoCABsABQpOEr4xAPYAAAAA.Tyrmog:BAAANQADCggIFAAAAA==.Tytus:BAAANQABCgcIDwAAAA==.',
Un='Undetha:BAABNQAECn8XAAIgAAgK4BZXLACVAQAgAAgK4BZXLACVAQAAAA==.',
Us='Ushas:BAABNQAECn8xAAMOAAoKxBndVAAkAgAOAAoKxBndVAAkAgAPAAEKAAAZhAAlAAAAAA==.',
Va='Vaeiane:BAAANQAECggICAABNQAECggIEAABAAAAAA==.Vali:BAAANQADCgcIDQABNQAECgoKHgAQAMQXAA==.Valindrea:BAAANQAECgUIDwAAAA==.Vasrael:BAAANQAECgcIEQAAAA==.Vasrannah:BAAANQAECgUIBQAAAA==.',
Ve='Vel:BAABNQAECn83AAMbAAoKyguGHACvAQAbAAoKyguGHACvAQAUAAcKmQIXIQC7AAAAAA==.Velnie:BAAANQAECgMIBQAAAA==.Venvanse:BAAANQAECgEIAQABNQAECgoKJwAJANIRAA==.Verq:BAAANQAECgEIAQAAAA==.Vexen:BAABNQAECn8cAAIbAAcKUBe9LQDUAQAbAAcKUBe9LQDUAQAAAA==.',
Vn='Vnia:BAAANQAECgEIAQAAAA==.',
Vo='Voidmuffinz:BAACNQAFFH8GAAIbAAMK+wsZDQB6AAAbAAMK+wsZDQB6AAA1AAQKfzsAAxsACgpKHGcXAKMCABsACgpKHGcXAKMCAAgACAoIEZRJAH8BAAAA.',
Vy='Vynis:BAAANQAFFAEIAQABNQAFFAUIDQAYAPwRAA==.Vyrahildard:BAABNQAECn8nAAIDAAgKChl2ggAjAgADAAgKChl2ggAjAgAAAA==.',
Wa='Wasteland:BAABNQAECn9AAAIgAAoK6A2iLwCCAQAgAAoK6A2iLwCCAQAAAA==.Watermelon:BAACNQAFFH8JAAIYAAMKmRAfGADRAAAYAAMKmRAfGADRAAA1AAQKfzkAAxgACgreEYZZAAQCABgACgreEYZZAAQCABkABgoCFIJ8AAMBAAE1AAUUBQgVABoAKhMA.',
We='Weaselhunter:BAABNQAECn8lAAIMAAoKxCPdFQBEAwAMAAoKxCPdFQBEAwAAAA==.Weasellock:BAABNQAECn8hAAIHAAkKRBZcQgD9AQAHAAkKRBZcQgD9AQABNQAECgoKJQAMAMQjAA==.Weaselmage:BAABNQAECn8dAAMJAAgKTQ+AmgBdAQAJAAgKfwyAmgBdAQAcAAMKFxJ7KgB5AAABNQAECgoKJQAMAMQjAA==.Weaselshammy:BAABNQAECn8fAAIZAAoKIRwhPADOAQAZAAoKIRwhPADOAQABNQAECgoKJQAMAMQjAA==.',
Wh='Whatthef:BAAANQADCgcIDwAAAA==.',
Wi='Wildweasel:BAAANQAECgUIDQABNQAECgoKJQAMAMQjAA==.Windchill:BAAANQADCgEIAQAAAA==.Winterhide:BAABNQAECn8ZAAMLAAcK8BHPTQBHAQAfAAYKfxMRcQBRAQALAAcKNQvPTQBHAQAAAA==.Wishbone:BAABNQAECn8dAAIJAAgKaRCEjwB0AQAJAAgKaRCEjwB0AQAAAA==.',
Wo='Womamatoo:BAAANQADCgcICgAAAA==.',
Xa='Xallie:BAEANQAECgYIDgAAAA==.Xanvyr:BAAANQAECggICAABNQAECgUICQABAAAAAA==.Xaquillis:BAABNQAECn8qAAIgAAoKJxBHNgBfAQAgAAoKJxBHNgBfAQAAAA==.Xaras:BAAANQADCgMIAwAAAA==.',
Xe='Xentrie:BAAANQAECgQICgAAAA==.Xeyvara:BAABNQAECn8nAAIUAAgKNSKmBgAcAgAUAAgKNSKmBgAcAgAAAA==.',
Ya='Yah:BAAANQADCggIDQAAAA==.',
Za='Zaravalatha:BAAANQADCgUICQAAAA==.Zarihanna:BAABNQAECn83AAIJAAgKkBDPwAADAgAJAAgKkBDPwAADAgAAAA==.Zariia:BAAANQAECgIIAQAAAA==.Zarsiia:BAAANQAECgQIDQAAAA==.Zatima:BAAANQAECgUIBAAAAA==.',
Ze='Zernakk:BAAANQAECgUICgAAAA==.Zestdh:BAAANQAECgUIBwAAAA==.Zestyknight:BAABNQAECn8WAAIgAAkK4R29EgByAgAgAAkK4R29EgByAgAAAA==.',
Zi='Zindeshal:BAAANQADCggIDQAAAA==.',
Zo='Zorcunter:BAABNQAECn89AAIMAAoK+yTrDQAYAwAMAAoK+yTrDQAYAwAAAA==.',
Zu='Zulizzajabi:BAAANQAECgIJBAAAAA==.',
['Åt']='Åthenå:BAAANQADCgYICgAAAA==.',
['Ða']='Ðarthrevan:BAAANQAECgEIAQAAAA==.',
['Ðo']='Ðonjon:BAAANQAECgEIAQAAAA==.',
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
