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

local lookup = {'Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Shaman-Restoration','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','Unknown-Unknown','Druid-Feral','Priest-Holy','Priest-Shadow','Warrior-Arms','Mage-Arcane','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Priest-Discipline','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Warrior-Protection','Shaman-Elemental','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Evoker-Preservation','Shaman-Enhancement','Warlock-Demonology','Druid-Guardian','Monk-Brewmaster','Warlock-Affliction','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Warrior-Fury','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aakai:BAABNQAECn9VAAQBAAoKrBzHIQCDAgABAAoKnRvHIQCDAgACAAgKoBldBgBsAgADAAIKEQrJRQB2AAAAAA==.Aarmorr:BAABNQAECn9OAAIEAAoKKQlHagB1AQAEAAoKKQlHagB1AQAAAA==.',
Ac='Acinianis:BAAANQADCggIDwAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.Adiro:BAAANQADCgcICwAAAA==.Adsdad:BAAANQAECgQIBQAAAA==.',
Ae='Aedelas:BAAANQADCggIFQAAAA==.',
Ai='Aimeeiove:BAAANQAECgQIAwAAAA==.Airoldeel:BAAANQADCgcICAAAAA==.',
Ak='Akarag:BAAANQADCgcICgAAAA==.',
Al='Alcarza:BAAANQADCgcIBwAAAA==.Alchon:BAABNQAECn8kAAIFAAgK0xp7UwB2AgAFAAgK0xp7UwB2AgAAAA==.Alicalsastre:BAAANQAECgcIEQAAAA==.Alista:BAAANQABCgIIAgAAAA==.Allykat:BAABNQAECn87AAMGAAgK0RM8JQDKAQAGAAgK0RM8JQDKAQAHAAUKzgS0hAC/AAAAAA==.Alunathsong:BAAANQAECgYIBwAAAA==.Alvagíngras:BAAANQAECgYIBwAAAA==.',
Am='Amaith:BAAANQAECgQJCgAAAA==.Amantillado:BAAANQAECgIIAwABNQAECgYIDwAIAAAAAA==.Amata:BAAANQAECgQIBgAAAA==.Amblance:BAAANQAECggIDQAAAA==.Amelianne:BAAANQAECgQIBAAAAA==.Amerria:BAAANQABCgMIAwAAAA==.Ammastary:BAAANQAECgQIBgAAAA==.Ammonfrey:BAAANQADCgUIBQAAAA==.',
An='Andrea:BAABNQAECn88AAIJAAoKuhOHDgDiAQAJAAoKuhOHDgDiAQAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.Anysra:BAAANQADCgYJBgAAAA==.',
Ap='Apöllo:BAABNQAECn8iAAMKAAkKMRGZewBnAQAKAAkKMRGZewBnAQALAAQKUQdEVgCzAAAAAA==.',
Aq='Aqules:BAAANQADCggICwAAAA==.',
Ar='Arcapeligo:BAAANQADCggIFQAAAA==.Archonsfury:BAAANQAECggIEwAAAA==.Ardagg:BAAANQABCgYICQAAAA==.Arilyn:BAAANQADCgQIBAAAAA==.Arin:BAABNQAECn8eAAIMAAoK7Be7bwBEAgAMAAoK7Be7bwBEAgAAAA==.',
As='Ashentris:BAABNQAECn8YAAINAAYK/AQB4ADtAAANAAYK/AQB4ADtAAAAAA==.Asnew:BAABNQAECn8zAAIOAAoKQBKqOgBXAQAOAAoKQBKqOgBXAQAAAA==.Asura:BAABNQAECn8iAAMPAAoKMBEEUQDPAQAPAAgKNhMEUQDPAQAQAAUKOgnyeQDAAAAAAA==.',
At='Athelstan:BAABNQAECn8XAAILAAgKlgpdQAAsAQALAAgKlgpdQAAsAQAAAA==.Atonement:BAAANQADCgIIAgABNQAECgoKPQARALoeAA==.',
Au='Aumaril:BAAANQAECggIEQAAAA==.Auralynn:BAABNQAECn8WAAISAAkKiAb37AAIAQASAAkKiAb37AAIAQAAAA==.Auroriana:BAAANQADCgQIBQAAAA==.',
Av='Averus:BAABNQAECn9PAAIHAAoKMguVLgCQAQAHAAoKMguVLgCQAQAAAA==.',
Az='Azariel:BAABNQAECn8mAAMSAAoKqRB2mgDuAQASAAoKqRB2mgDuAQARAAEKAAB7dQAnAAAAAA==.Azatre:BAAANQADCgIIAgAAAA==.Azuriah:BAABNQAECn9OAAIRAAoKPxueDgBAAgARAAoKPxueDgBAAgAAAA==.',
Ba='Baane:BAAANQAECgQIBgABNQAECgYIHwATALcPAA==.Babnik:BAEBNQAECn8lAAIFAAoKXgxacADgAQAFAAoKXgxacADgAQAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Balderdashe:BAAANQAECgIIAgAAAA==.',
Be='Bealzibub:BAAANQABCgIIAgAAAA==.Bedhead:BAABNQAECn9IAAMTAAoKrhuSBQCyAQAKAAoKnhq7NABsAgATAAgKYxKSBQCyAQAAAA==.Belaim:BAAANQABCgIIAgAAAA==.Belovis:BAACNQAFFH8XAAISAAYK2xaTCgCfAQASAAYK2xaTCgCfAQA1AAQKfzkAAhIACgrlJCcQACoDABIACgrlJCcQACoDAAAA.Betsea:BAAANQADCgcIBwABNQAECgkJJwAUAOkUAA==.',
Bi='Bidock:BAAANQAECgUIBAAAAA==.Bidoof:BAABNQAECn82AAIVAAoK3Q5XKwC2AQAVAAoK3Q5XKwC2AQAAAA==.Bigblunt:BAAANQADCgUIBgAAAA==.Bigocritties:BAAANQABCgMIAgAAAA==.Bitemarks:BAAANQADCggJFQAAAA==.Bix:BAABNQAECn9JAAIWAAoK2x7NAwC+AgAWAAoK2x7NAwC+AgAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBQAAAA==.Blokmor:BAABNQAECn8cAAMUAAoK5Q6acwBaAQAUAAgKngyacwBaAQARAAYK8AduTwCpAAAAAA==.',
Bo='Boggrog:BAABNQAECn8fAAMMAAYK5A47xgDoAAAMAAYKGAw7xgDoAAAXAAMKhRN3NABuAAAAAA==.Bolz:BAAANQADCgYIBgAAAA==.Bonepicklucy:BAAANQADCgUIDgAAAA==.Boneybob:BAAANQABCgQJCAAAAA==.Boras:BAAANQAECgUIBwAAAA==.Bordeaux:BAAANQAECgMIBQABNQAECgYIGgALAP0UAA==.Bosshog:BAABNQAECn88AAMYAAkKywxCVwCCAQAYAAkKywxCVwCCAQAEAAEKdgFtEwEXAAAAAA==.',
Br='Brabanzio:BAABNQAECn8iAAIKAAoKSxNXQgAwAgAKAAoKSxNXQgAwAgABNQAECgoKQgAEAJQfAA==.Breadfriend:BAAANQADCggICAAAAA==.Brightnshiny:BAAANQABCgIIAgAAAA==.Broseidon:BAAANQAECgMIAwAAAA==.Brotato:BAAANQABCgcICwABNQAECgcICwAIAAAAAA==.Brotatochip:BAAANQAECgcICwAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.Brycke:BAAANQADCggIFwAAAA==.',
Bu='Buffsalot:BAABNQAECn8pAAIUAAoK8x4uEAA9AwAUAAoK8x4uEAA9AwAAAA==.Burningblunt:BAAANQAECgYICgAAAA==.Buttons:BAAANQADCgcJBwAAAA==.',
Ca='Calav:BAABNQAECn8UAAIFAAcKSAdI2wD8AAAFAAcKSAdI2wD8AAABNQAECggIGQAZAMoFAA==.Castle:BAABNQAECn8gAAMSAAYK0AuwCQHaAAASAAYK0AuwCQHaAAAUAAQKYgrT5AC3AAAAAA==.Catsinhats:BAAANQADCggIDQABNQAECgoKQAAPAHYcAA==.Catzinhatz:BAAANQADCgUIBQABNQAECgoKQAAPAHYcAA==.',
Ce='Cecelya:BAABNQAECn8mAAMKAAoKZRlJPwBuAgAKAAoKZRlJPwBuAgALAAEKyAUQZQAzAAAAAA==.Celerian:BAAANQADCgUIBQAAAA==.',
Ch='Chablis:BAAANQAECgIIAQAAAA==.Cherlia:BAAANQADCgcIDgABNQAECggIIwAVADEdAA==.Chillpills:BAAANQABCgIIAgAAAA==.Chivactdl:BAAANQAECgIIAgABNQAECgoKTAAEAPwTAA==.Chosenn:BAAANQAECgUICgAAAA==.Chotek:BAABNQAECn8eAAMHAAgKFBKINABqAQAHAAgKFBKINABqAQAJAAEKGwwZSgA0AAAAAA==.Chunknoriss:BAABNQAECn8bAAMaAAYKjxjtGQBlAQAaAAYKjxjtGQBlAQAbAAEKAACUdwAgAAABNQAECgoKTAAEAPwTAA==.',
Ci='Cilarnen:BAABNQAECn8lAAMUAAcKvBG9hwAgAQAUAAcKvBG9hwAgAQASAAcKzgajBwHdAAAAAA==.',
Cl='Claudiuss:BAABNQAECn8ZAAIGAAoKWA4bJADVAQAGAAoKWA4bJADVAQABNQAECgoKQgAEAJQfAA==.Clure:BAABNQAECn8wAAIUAAoK4CIxFQArAwAUAAoK4CIxFQArAwABNQAECgoKSAAcAHEfAA==.Clurelock:BAAANQAECggIDQABNQAECgoKSAAcAHEfAA==.Clurethyr:BAABNQAECn9IAAIcAAoKcR8CBABbAwAcAAoKcR8CBABbAwAAAA==.',
Co='Conchobhar:BAAANQAECgYICAAAAA==.Coppertan:BAAANQADCgcIFwAAAA==.Cornaddict:BAACNQAFFH8OAAMKAAUKQg57EwBvAQAKAAUKQg57EwBvAQALAAEKAAByGABEAAA1AAQKfzcAAwoACgrkFvc/ADoCAAoACQrOGPc/ADoCAAsACAq2HYshACoCAAAA.Corrosion:BAABNQAECn8qAAIdAAoKFx/+BgASAwAdAAoKFx/+BgASAwAAAA==.',
Cr='Crommash:BAAANQAECggICQAAAA==.Cromshade:BAAANQABCgYIBgAAAA==.Cromsteel:BAAANQADCgQIBAAAAA==.Cromsyth:BAAANQADCgYIBgAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAABNQAECn8UAAISAAUKIxPB8QA5AQASAAUKIxPB8QA5AQABNQAFFAUICQASAK8UAA==.Crylessplz:BAAANQAECgUIDgABNQAECgoKPQARALoeAA==.',
Ct='Cthuwu:BAABNQAECn8cAAIeAAoKQxS9PQAeAgAeAAoKQxS9PQAeAgABNQAFFAUIDQAFAH8eAA==.',
Cv='Cvhamster:BAAANQADCgcIBwAAAA==.',
Cy='Cy:BAAANQADCggJCAAAAA==.Cybeast:BAABNQAECn8rAAMJAAoKPBu+CwBvAgAJAAoKFRu+CwBvAgAfAAkK+BNOGADIAQAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAABNQAECn8iAAIFAAkK4RUCggC1AQAFAAkK4RUCggC1AQAAAA==.Dados:BAAANQAECgUIBQAAAA==.Daeghun:BAAANQADCgYIBgAAAA==.Dahleigh:BAAANQADCgYIBAAAAA==.Dakanar:BAAANQADCggIDAAAAA==.Darkessence:BAAANQADCgEIAQAAAA==.Darkfox:BAAANQADCgYIBgAAAA==.Darkhazel:BAAANQAECgYICAAAAA==.Darkkromdor:BAABNQAECn8tAAISAAoKXBu0YgByAgASAAoKXBu0YgByAgAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAABNQAECn8qAAIVAAoKChfkJwBfAgAVAAoKChfkJwBfAgAAAA==.Deathcat:BAABNQAECn9AAAMPAAoKdhweLgB5AgAPAAoKdhweLgB5AgAQAAYKPgthYQAfAQAAAA==.Deathkiss:BAAANQAECgMJBAAAAA==.Deathrixx:BAAANQADCggICAAAAA==.Deathshadowx:BAAANQAECgQIBgAAAA==.Decayy:BAABNQAECn8mAAIOAAoKhhi2LQBeAgAOAAoKhhi2LQBeAgAAAA==.Dedbull:BAAANQADCggIIQAAAA==.Demodius:BAAANQADCggICAAAAA==.Demourdenite:BAAANQADCgYIFQAAAA==.Des:BAAANQABCgIIAgAAAA==.',
Di='Discharged:BAAANQADCgYICAABNQAECgYIDwAIAAAAAA==.',
Dk='Dkpheonix:BAABNQAECn9EAAILAAoK7BQ0FAAaAgALAAoK7BQ0FAAaAgAAAA==.',
Do='Dolemite:BAABNQAECn80AAMaAAkKBhFaFQCsAQAaAAkKBhFaFQCsAQAbAAcKPRLRKwA6AQAAAA==.Donalbain:BAABNQAECn9CAAIEAAoKlB+6DABcAwAEAAoKlB+6DABcAwAAAA==.Donninban:BAABNQAECn8YAAMYAAYKUhPShgCTAQAYAAYKUhPShgCTAQAEAAQKRxnavQCdAAAAAA==.Doodoobutter:BAAANQAECgIIAgABNQAFFAMIBgAgABoKAA==.',
Dr='Draganpriest:BAAANQAECgEIAQAAAA==.Dremar:BAABNQAECn8bAAIhAAcKihbODABxAQAhAAcKihbODABxAQAAAA==.Drizzeh:BAAANQABCggIEAAAAA==.Drugoja:BAAANQADCgcICAAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.Dunshotya:BAAANQAECgIIAgAAAA==.',
Ea='Eas:BAAANQADCgUIBQAAAA==.',
Eb='Ebolla:BAAANQADCgcIBwAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQAECgUIDwAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elienda:BAAANQABCgIIAgAAAA==.Elifar:BAAANQADCggIFwAAAA==.Eloweñ:BAAANQABCgQIBAAAAA==.Eluneatic:BAAANQADCgQIBAAAAA==.Elyssaris:BAABNQAECn8+AAIOAAoKBxZrJQDQAQAOAAoKBxZrJQDQAQAAAA==.Elzulkin:BAAANQADCgQIBAAAAA==.',
Em='Emmdeath:BAAANQADCgYIBgAAAA==.Emmils:BAABNQAECn8hAAIHAAoK/gfbVgB7AQAHAAoK/gfbVgB7AQAAAA==.Emìly:BAABNQAECn9LAAMbAAoK7xbkEgA1AgAbAAoK7xbkEgA1AgAaAAgKFxYFHADEAQAAAA==.',
En='Entaria:BAAANQAECgUIBwAAAA==.',
Ep='Ephria:BAABNQAECn8vAAMEAAoKiSQZEABDAwAEAAoKiSQZEABDAwAYAAEKAACXTQEnAAAAAA==.Episkey:BAAANQAECgQIDAAAAA==.',
Er='Eroversion:BAABNQAECn8tAAMGAAkKUROFLQCEAQAGAAgKtBSFLQCEAQAfAAYKlwx+RwCgAAABNQAECgoKbwAXAHEcAA==.Eroward:BAABNQAECn9vAAMXAAoKcRynCABWAgAXAAoKcRynCABWAgAMAAUK0wc53QC5AAAAAA==.',
Es='Esmay:BAABNQAECn9AAAIYAAoKow93UwCNAQAYAAoKow93UwCNAQAAAA==.',
Et='Ethren:BAABNQAECn9PAAIDAAoKJBi9CQBCAgADAAoKJBi9CQBCAgAAAA==.',
Eu='Eudoxos:BAAANQAECgEIAQAAAA==.Euroecka:BAAANQAECgEIAQAAAA==.',
Ev='Evelynstar:BAAANQADCgMIAwAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.Fangsofblood:BAAANQAECgQIBAABNQAECgoKPgASAJ0QAA==.',
Fe='Felbolter:BAABNQAECn8qAAIZAAgKlR2rCAByAgAZAAgKlR2rCAByAgAAAA==.Feliri:BAAANQAECgIIAQAAAA==.Fetide:BAAANQADCgIIAgAAAA==.',
Fi='Fiddlefaddle:BAAANQABCgMIAwAAAA==.Filgulfin:BAABNQAECn9RAAIFAAoKGx1yKgCXAgAFAAoKGx1yKgCXAgAAAA==.Finkate:BAAANQAECggIDAAAAA==.Firebringer:BAABNQAECn83AAIiAAoKzAjQIwB/AQAiAAoKzAjQIwB/AQAAAA==.Fistmegently:BAAANQADCgYICwAAAA==.',
Fl='Flamehunter:BAABNQAECn8UAAIVAAgKjxUvNQB4AQAVAAgKjxUvNQB4AQAAAA==.Flo:BAABNQAECn9QAAQLAAoKMhQtIwAZAgALAAoKMhQtIwAZAgAKAAkKfAr6ZwCnAQATAAgKZw0iBwBnAQAAAA==.Floki:BAABNQAECn8YAAMXAAkKRRBkHQBsAQAXAAkKRRBkHQBsAQAMAAUKlAeG9wDuAAAAAA==.Flokin:BAAANQAECgIIAwAAAA==.Flowing:BAABNQAECn86AAQjAAoKgxIgCAAbAgAjAAoKgxIgCAAbAgAcAAYKIwcqMgAIAQAkAAQKfATALwCcAAAAAA==.',
Fo='Foods:BAABNQAECn9XAAQMAAoKwhCtXgDjAQAMAAoKhQ+tXgDjAQAXAAYKaw6ELQDJAAAlAAIKUAtdLwBDAAAAAA==.',
Fr='Fripouille:BAAANQADCgQICAAAAA==.',
['Fæ']='Fæ:BAAANQADCgcIBwAAAA==.',
Ga='Gabmoo:BAAANQADCgMIAwAAAA==.Gaboo:BAABNQAECn8bAAISAAkKiBD3ygCGAQASAAkKiBD3ygCGAQAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBAAAAA==.',
Gi='Gilorion:BAABNQAECn80AAIFAAkKZBvfRgBEAgAFAAkKZBvfRgBEAgAAAA==.',
Gl='Glasgoww:BAAANQADCgUIBQABNQAECgoKQgAEAJQfAA==.Gler:BAAANQADCgQIBQAAAA==.',
Gn='Gnibat:BAAANQAECgQIBQAAAA==.',
Go='Goburina:BAABNQAECn8yAAIEAAoKVRIrXwDxAQAEAAoKVRIrXwDxAQAAAA==.Goldhawk:BAAANQABCgIIAgAAAA==.',
Gr='Gracee:BAAANQAECgEIAQAAAA==.Graedyn:BAAANQADCgEIAQAAAA==.Grommel:BAAANQADCgIIAgAAAA==.Gryffen:BAAANQABCgcICQAAAA==.',
Gu='Gulpron:BAAANQABCgMJBAAAAA==.',
['Gí']='Gímlí:BAABNQAECn8oAAIFAAoKORuZTwCAAgAFAAoKORuZTwCAAgAAAA==.',
Ha='Haidyn:BAAANQADCgMJAwAAAA==.Halcyndraag:BAABNQAECn8zAAQjAAkK1A9kCgBjAQAjAAkKEw9kCgBjAQAkAAYKow3hHwBYAQAcAAUKzgRgOwC+AAAAAA==.Hallowed:BAAANQADCgUIBQAAAA==.Handofcope:BAAANQAECgYIEAAAAA==.Hartu:BAABNQAECn9VAAIXAAoKGBvlCQA1AgAXAAoKGBvlCQA1AgAAAA==.Harukasan:BAAANQADCgIIAgAAAA==.',
He='Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQAECgQIBgAAAA==.',
Hi='Hircine:BAAANQADCggIDAAAAA==.',
Ho='Holysea:BAAANQAECgIIAgABNQAECgkJJwAUAOkUAA==.Honk:BAAANQAECgQIBAAAAA==.',
Ic='Ichiko:BAAANQADCgUIBQAAAA==.',
Im='Imwithfloki:BAABNQAECn8eAAQfAAgKsBXaHgCoAQAfAAgKsBXaHgCoAQAJAAEKAAC1OwBLAAAGAAEKhhBHeQAuAAAAAA==.',
Ir='Ironmark:BAAANQAECgIIAgAAAA==.Irys:BAAANQADCgcIDQAAAA==.',
Is='Isam:BAAANQAECgUIBQAAAA==.Isamidor:BAABNQAECn8mAAIFAAkK6SW2CACXAwAFAAkK6SW2CACXAwAAAA==.Ismokeu:BAABNQAECn8sAAMKAAoKKRnCSABMAgAKAAoKKRnCSABMAgALAAEKAACfeAAAAAAAAA==.Ismyn:BAAANQAECgMIAgAAAA==.Istran:BAAANQAECggIEQAAAA==.',
Iv='Ivrys:BAAANQAECgcIDwAAAA==.',
Iw='Iwillbethere:BAAANQAECgIIAwAAAA==.',
Ja='Jackoneal:BAABNQAECn8zAAMSAAoK/gQW2gAnAQASAAoK/gQW2gAnAQARAAEKAABnfwAdAAAAAA==.Jalidelo:BAABNQAECn8nAAIKAAoKchI6WgATAgAKAAoKchI6WgATAgAAAA==.Jalidemon:BAAANQADCggIEAAAAA==.Jalyyn:BAAANQAECgIIAgAAAA==.',
Ji='Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAABNQAECn87AAIeAAoKlxx4JgB2AgAeAAoKlxx4JgB2AgAAAA==.Jokersfists:BAABNQAECn8sAAIiAAoKWxddEQBFAgAiAAoKWxddEQBFAgAAAA==.Jokersmage:BAABNQAECn8rAAINAAoKOA8HYgDyAQANAAoKOA8HYgDyAQABNQAECgoKLAAiAFsXAA==.Joraflheim:BAAANQABCgMIBAAAAA==.Joranbragi:BAABNQAECn8uAAISAAcKKgSvTwGhAAASAAcKKgSvTwGhAAAAAA==.Jordanjr:BAABNQAECn9JAAMmAAoKthhsEgAbAgAFAAoKOBL3TACHAgAmAAoK8RRsEgAbAgAAAA==.Josunlee:BAAANQAECggIDgAAAA==.Jotoonice:BAABNQAECn8oAAMWAAoKuBGtFgBIAQAWAAYKlxStFgBIAQANAAgKOgeoRwEWAQAAAA==.',
Jt='Jtoothaordan:BAACNQAFFH8NAAMmAAYK+w0jEwAOAQAmAAQKtw4jEwAOAQAFAAMKfwsjHgCpAAA1AAQKfzkAAyYACgrWH3ccAG8CACYACgrhF3ccAG8CAAUABArvIY3LABsBAAAA.',
Ju='Juicyfruit:BAAANQABCgYICQAAAA==.Jules:BAAANQADCgcIBwAAAA==.',
Ka='Kaana:BAABNQAECn9PAAIFAAoKZxRVSgA7AgAFAAoKZxRVSgA7AgAAAA==.Kaedina:BAABNQAECn8nAAMKAAoKrwuxbADYAQAKAAoKrwuxbADYAQALAAkKjw/2HQCgAQABNQAECgoKSQAmALYYAA==.Kallista:BAAANQADCgYIDwAAAA==.Karugan:BAAANQADCgIIAgABNQADCgcICgAIAAAAAA==.Karvel:BAABNQAECn8jAAIOAAoKeBmXLwBUAgAOAAoKeBmXLwBUAgAAAA==.Kaychow:BAAANQAECgQICAABNQAECgoKOwAUAKcfAA==.Kaydullz:BAABNQAECn8jAAIKAAoKEBgmNQBqAgAKAAoKEBgmNQBqAgAAAA==.',
Kc='Kchowchow:BAAANQAECgYIBgABNQAECgoKOwAUAKcfAA==.',
Ke='Kelonaar:BAACNQAFFH8WAAMYAAQKaxe9EADmAAAYAAQKaxe9EADmAAAEAAMK5gPWJgBuAAA1AAQKfysAAxgACgpfIGojAPkCABgACgpfIGojAPkCAAQAAwq7GPLiAKQAAAAA.Keloni:BAAANQAECgUIBgABNQAFFAQIFgAYAGsXAA==.Kenack:BAAANQAECgQIDAAAAA==.',
Kh='Kharys:BAAANQADCggIHAAAAA==.Khell:BAAANQAECggIDAAAAA==.',
Ki='Killallnius:BAAANQADCgIIAgAAAA==.Killermoomoo:BAAANQAECgQIBgAAAA==.',
Kl='Kloverr:BAAANQAECgYIEAAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.Koranthia:BAAANQADCgUICQAAAA==.',
Kr='Kretaios:BAAANQADCgEIAQAAAA==.Kromir:BAAANQADCggICAAAAA==.Kronixrage:BAAANQAECgMIBQAAAA==.Krooler:BAAANQAECgMJBAAAAA==.Krum:BAAANQAECgYIEQAAAA==.',
La='Ladgarkk:BAABNQAECn8qAAMUAAoKqB0PDwBJAwAUAAoKqB0PDwBJAwASAAEKDAfTmwEzAAAAAA==.Lanval:BAABNQAECn9WAAISAAoK4hqSRgBWAgASAAoK4hqSRgBWAgAAAA==.Lardorm:BAAANQADCgQIBAAAAA==.Latinlover:BAAANQAECgIIAgAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAABNQAECn9aAAIfAAoKaB6CCAC8AgAfAAoKaB6CCAC8AgAAAA==.Leftblank:BAAANQAECgQIBQAAAA==.Letmetameyou:BAAANQADCgQICAAAAA==.',
Li='Lich:BAAANQAECgQIBAAAAA==.Lighthugger:BAABNQAECn88AAISAAoKeBy2VgAqAgASAAoKeBy2VgAqAgAAAA==.Lilyoptra:BAABNQAECn8lAAIeAAcKawORzwCyAAAeAAcKawORzwCyAAABNQAECgcIJQAUALwRAA==.Liqmycrits:BAAANQADCggIGwAAAA==.Lishalzin:BAAANQAECgEIAQABNQAECggIIwAVAKAQAA==.Liszt:BAAANQADCgMIAwAAAA==.Livana:BAAANQADCggIEAABNQAECgYIDwAIAAAAAA==.',
Lo='Lockpockets:BAABNQAECn8cAAIeAAcKLwoxrAD8AAAeAAcKLwoxrAD8AAAAAA==.Loriane:BAAANQAECgIIAgABNQAECgcIEQAIAAAAAA==.Lorianth:BAABNQAECn84AAImAAoK6g9THACbAQAmAAoK6g9THACbAQAAAA==.Lotharbacco:BAAANQADCggICAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.Loveisbeauty:BAAANQADCgcIBQAAAA==.',
Lu='Lucifér:BAAANQABCggICgAAAA==.Lundigras:BAAANQADCgUIBQAAAA==.',
Ly='Lychi:BAAANQAECgQIBgAAAA==.Lylora:BAABNQAECn9aAAIGAAoKiSaHAABQBAAGAAoKiSaHAABQBAAAAA==.',
['Lê']='Lêmonaide:BAABNQAECn8qAAMKAAoKUxX1UgAqAgAKAAoKUxX1UgAqAgALAAUKIQX7SwB6AAAAAA==.',
['Lô']='Lôki:BAAANQAECgUIBQAAAA==.',
Ma='Madclaws:BAABNQAECn9ZAAMfAAoKYh9ECQCsAgAfAAoKzh1ECQCsAgAHAAkKNB/AFgBdAgAAAA==.Madman:BAAANQAECgUIEwAAAA==.Magekaestey:BAAANQADCggIDwABNQAECgoKLAAMAJcMAA==.Malala:BAAANQADCgYIEwABNQAECgoKYwAKAL0gAA==.Malyndra:BAAANQAECgYIDgABNQAECgcIEgAIAAAAAA==.Marshy:BAAANQAFFAEIAQAAAA==.Marvolt:BAABNQAECn8kAAIeAAoKwQeYnQCcAQAeAAoKwQeYnQCcAQAAAA==.Maryjane:BAAANQAECgUIBAAAAA==.Masy:BAABNQAECn8aAAISAAoKUgfjugBcAQASAAoKUgfjugBcAQAAAA==.',
Me='Mesmash:BAABNQAECn86AAIXAAkKXyGLBwB4AgAXAAkKXyGLBwB4AgAAAA==.Metadk:BAAANQAECgYIDwAAAA==.Metamasters:BAAANQADCgYIDgABNQAECgYIDwAIAAAAAA==.Metatotem:BAAANQAECgYICAABNQAECgYIDwAIAAAAAA==.',
Mi='Mialtaa:BAAANQAECgIIAwAAAA==.Micah:BAAANQAECgIJAgAAAA==.Midgiit:BAAANQAECgcIEgABNQAECgkJMQAKANYbAA==.Miniborg:BAAANQAECgUIDAABNQAFFAUICQASAK8UAA==.Minidude:BAABNQAECn8nAAIMAAoKExbEPQBLAgAMAAoKExbEPQBLAgAAAA==.Misfire:BAAANQAECgEIAQAAAA==.Mistycrusade:BAAANQAECgUICwAAAA==.Mizzen:BAABNQAECn8+AAMPAAoKRB80CwDFAgAPAAoKRB80CwDFAgAOAAMK1g3ytABfAAABNQAFFAUIDgALANcRAA==.',
Mo='Moejojojo:BAABNQAECn8aAAIbAAkKRh7pHgA5AgAbAAkKRh7pHgA5AgAAAA==.Moofasaha:BAABNQAECn8dAAQEAAgKBR23YgDlAQAEAAgKBR23YgDlAQAYAAQKggjS+wCbAAAdAAEKSggONgA9AAAAAA==.Morog:BAABNQAECn8UAAMFAAgKHB8rOwC4AgAFAAgKHB8rOwC4AgAmAAEKAACNigA0AAAAAA==.Morragan:BAAANQADCggIGQAAAA==.',
Mu='Mulvan:BAABNQAECn8ZAAINAAkK7gfPMAE7AQANAAkK7gfPMAE7AQAAAA==.',
['Mâ']='Mârshy:BAAANQAECgUIBgABNQAFFAEIAQAIAAAAAA==.',
['Mã']='Mãrshy:BAABNQAECn8cAAIKAAgKgB6IOgB/AgAKAAgKgB6IOgB/AgABNQAFFAEIAQAIAAAAAA==.',
['Mä']='Märshy:BAAANQAECgQIBAABNQAFFAEIAQAIAAAAAA==.',
Na='Nabû:BAAANQADCgQIBAAAAA==.Naler:BAAANQAECgUICAAAAA==.Nanarus:BAABNQAECn9jAAMKAAoKvSAsCgCXAwAKAAoKvSAsCgCXAwALAAIKwAUcWABOAAAAAA==.Nashalie:BAABNQAECn87AAMeAAoKbCGjGAAlAwAeAAoKbCGjGAAlAwAZAAIKOgzdVQB9AAAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAABNQAECn8bAAIEAAkKzxmNYQCTAQAEAAkKzxmNYQCTAQAAAA==.Neverfrozen:BAAANQAECgYIDQAAAA==.Nexbasia:BAABNQAECn9HAAIJAAoK2RGXEAC9AQAJAAoK2RGXEAC9AQAAAA==.',
Ni='Nickyboy:BAAANQAECgUIBAAAAA==.Nightevel:BAAANQADCgYICQAAAA==.Nihimetal:BAAANQADCgcIEwAAAA==.',
No='Noctum:BAAANQAECgIIAgAAAA==.Nomad:BAAANQADCggIGgAAAA==.Norinisa:BAAANQABCgcIBwAAAA==.',
Ny='Nymmycup:BAAANQAECgMIBAAAAA==.',
Oc='Octt:BAAANQAECgYICgAAAA==.',
Ol='Oldcannabis:BAABNQAECn8dAAIFAAgKyQotmQDVAQAFAAgKyQotmQDVAQAAAA==.',
Om='Ominis:BAAANQADCgQIBAAAAA==.',
Oo='Oomaw:BAAANQAECgEIAQAAAA==.',
Or='Ormbar:BAAANQADCgIIAgAAAA==.Ornimus:BAABNQAECn8lAAQRAAYKfBZqNQDcAAARAAYKfBZqNQDcAAASAAQKbQGShQFSAAAUAAIKuwFuHgE4AAAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAACNQAFFH8HAAILAAQKdBpcCgBTAQALAAQKdBpcCgBTAQA1AAQKfxwAAgsACQpNIisRAOgCAAsACQpNIisRAOgCAAAA.',
Oz='Ozo:BAAANQAECgQICQAAAA==.',
Pa='Paiva:BAAANQAECgMIAwAAAA==.Pallydoof:BAAANQADCggICQAAAA==.Pallyscorned:BAABNQAECn8vAAIRAAoKmxfeFADhAQARAAoKmxfeFADhAQAAAA==.Pamgetem:BAAANQAECgQIBQABNQAECggIEgAIAAAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Pandaria:BAAANQAFFAEIAQAAAA==.Panduh:BAABNQAECn8xAAMbAAkKZiEPCwAjAwAbAAkKECEPCwAjAwAgAAcKjx+bDgAKAgAAAA==.',
Ph='Phenixy:BAAANQAECgQIBgAAAA==.Phoebell:BAABNQAECn8dAAIGAAcKXQlLRQDuAAAGAAcKXQlLRQDuAAAAAA==.Phoinix:BAAANQADCgcIDgAAAA==.',
Pi='Pinkducky:BAAANQADCggIHgAAAA==.',
Pl='Plen:BAAANQAECgIIAgABNQAECgkJMQAKANYbAA==.',
Po='Ponyo:BAABNQAECn9NAAIKAAoKCyQABgDSAwAKAAoKCyQABgDSAwAAAA==.Poppyseed:BAAANQAECggICAAAAA==.Poquads:BAAANQADCggIDAAAAA==.',
Pr='Prinnce:BAAANQAECgYIEAABNQAECgoKSwAbAO8WAA==.',
Pu='Pulmifinger:BAAANQADCggICAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAABNQAECn8cAAMmAAgKXg92OACMAQAmAAgKnQ52OACMAQAFAAMK1hF5HgHAAAAAAA==.',
Ra='Raddra:BAAANQAECgUICwAAAA==.Raddrah:BAAANQAECgMIAwAAAA==.Raddrap:BAAANQADCgUIBgAAAA==.Raddraw:BAAANQADCgEIAQAAAA==.Radmuster:BAAANQAECgIIAgABNQAECgoKHgALAG0SAA==.Radra:BAABNQAECn82AAIiAAoKNxDxIgCGAQAiAAoKNxDxIgCGAQAAAA==.Raeku:BAABNQAECn8vAAInAAoKVx9nAgCuAgAnAAoKVx9nAgCuAgAAAA==.Raharuto:BAAANQADCggICAAAAA==.Raja:BAAANQAECgMJBQAAAA==.Rav:BAAANQADCgIIAgAAAA==.Razzlor:BAAANQADCgQIBAAAAA==.',
Re='Recoill:BAABNQAECn88AAIKAAoKHh+KEABWAwAKAAoKHh+KEABWAwAAAA==.Redhaven:BAABNQAECn8eAAIKAAoKeA0EWgDWAQAKAAoKeA0EWgDWAQAAAA==.Reducto:BAAANQADCgYICwAAAA==.Retribution:BAABNQAECn8+AAISAAoKnRANfgDRAQASAAoKnRANfgDRAQAAAA==.',
Ro='Robomurph:BAAANQADCgQIBAAAAA==.Rokz:BAAANQAECgIIAgAAAA==.Rolas:BAAANQAECggICAAAAA==.Ronfax:BAACNQAFFH8RAAIEAAYKGRY4CgDJAQAEAAYKGRY4CgDJAQA1AAQKfzwAAgQACgrgIFoSADUDAAQACgrgIFoSADUDAAAA.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQAECgYIDQAAAA==.Rowdyredneck:BAAANQADCgYIBwABNQAECgYIDwAIAAAAAA==.',
Ru='Ruby:BAABNQAECn8cAAIgAAkKBiDbBQD4AgAgAAkKBiDbBQD4AgAAAA==.Rul:BAAANQADCgIIAgABNQAECgkJMQAbAGYhAA==.',
Ry='Ryllae:BAAANQADCgIIAgABNQAECggIIwAVADEdAA==.Ryuu:BAAANQAECgIIAwAAAA==.Ryuusythe:BAAANQADCggICQAAAA==.',
['Rå']='Råhl:BAAANQABCgcICQAAAA==.',
['Rì']='Rììdìì:BAABNQAECn8dAAMhAAoKXwgIGgC2AAAeAAoK/AfaqwB7AQAhAAQKuwYIGgC2AAABNQAECgoKKAAFADkbAA==.',
['Rï']='Rïchardgear:BAAANQADCggIDAABNQAECgoKKAAFADkbAA==.',
Sa='Saint:BAABNQAECn8vAAMSAAkKnREcwACcAQASAAcKWRYcwACcAQAUAAkKeBWsdABXAQAAAA==.Sallypally:BAAANQABCgQIBgAAAA==.Salopard:BAAANQADCgQIBAAAAA==.Saltsquirrel:BAAANQABCgIIAgAAAA==.Sarandria:BAAANQAECgQIBAABNQAECgkJGQAWAKQYAA==.Sarinae:BAABNQAECn8sAAQjAAoK8AaxEAAsAQAjAAoKsgaxEAAsAQAkAAYKPgVZKgDVAAAcAAEK3QEjQgASAAAAAA==.Sarmuc:BAABNQAECn9JAAIdAAoKqxiECQDdAgAdAAoKqxiECQDdAgAAAA==.Saryda:BAABNQAECn8aAAMLAAYK/RSHNQB3AQALAAYK/RSHNQB3AQAKAAEK1wIz+wArAAAAAA==.Sauda:BAAANQAECgUIDAAAAA==.',
Sc='Schuybusta:BAAANQAECgEIAQAAAA==.Scubagal:BAABNQAECn8dAAISAAcKawOtNAGeAAASAAcKawOtNAGeAAAAAA==.Scythraza:BAAANQAECgcICwAAAA==.',
Se='Secundinius:BAAANQADCgMIAwAAAA==.Sellenah:BAAANQADCgUIBAABNQAECgUIBwAIAAAAAA==.Selûne:BAAANQABCggICgAAAA==.Sensu:BAABNQAECn8fAAMTAAYKtw9PCAA4AQATAAYKtw9PCAA4AQALAAEKbANKaQAqAAAAAA==.Serrest:BAAANQAECgYICgAAAA==.Seä:BAABNQAECn8nAAIUAAkK6RQZVQAaAgAUAAkK6RQZVQAaAgAAAA==.',
Sh='Shacktown:BAAANQAECggIAQAAAA==.Shadowdoh:BAAANQAECgcIEgAAAA==.Shapzan:BAABNQAECn8aAAMHAAcKZw55WQC6AAAHAAYKrgp5WQC6AAAfAAQKShFNRgCZAAAAAA==.Sharks:BAAANQAECgQJBgAAAA==.Shivant:BAABNQAECn9MAAIEAAoK/BMBOQA0AgAEAAoK/BMBOQA0AgAAAA==.',
Si='Sidebürns:BAAANQAECgQIBAAAAA==.Silendreas:BAAANQADCgUIBQAAAA==.',
Sl='Sloth:BAABNQAECn8+AAIOAAoKaiLFCQDyAgAOAAoKaiLFCQDyAgAAAA==.',
Sm='Smalltwngirl:BAABNQAECn8aAAIGAAgKBRHELgB6AQAGAAgKBRHELgB6AQABNQAFFAYIEQAEABkWAA==.',
So='Solaire:BAAANQAECgQIBwAAAA==.Solaspirus:BAABNQAECn8XAAQVAAgKAxLYUQBOAQAVAAYK8xPYUQBOAQAiAAMKuwi3SgBoAAAoAAEKLRD4NAAoAAAAAA==.Solinius:BAAANQADCggIGgAAAA==.Songbreeze:BAABNQAECn8xAAMKAAkK1hsUKgDBAgAKAAkK1hsUKgDBAgALAAUKmQUkUADRAAAAAA==.Sonofagun:BAAANQAECgYICAAAAA==.Soraka:BAAANQAECgQIBAABNQAECggIIwAVAKAQAA==.',
Sp='Spectors:BAABNQAECn8zAAQhAAoKsAc7DgBvAQAhAAoKUQc7DgBvAQAeAAcKHwPs5wD5AAAZAAEKAAA5hQAkAAAAAA==.Spideygirl:BAAANQAECgEIAQAAAA==.',
St='Stabon:BAAANQAECgcIEgAAAA==.Strykah:BAAANQADCgQIBAAAAA==.',
Su='Sugarcube:BAAANQAECgEIAQAAAA==.Sugarmarks:BAAANQAECgMIAgAAAA==.',
Sw='Sweetstorm:BAABNQAECn85AAIVAAoKrwQHSQAIAQAVAAoKrwQHSQAIAQAAAA==.',
Sy='Sydburns:BAAANQABCgYICAABNQAECgQIBAAIAAAAAA==.Sydley:BAAANQABCgUIBQAAAA==.',
Ta='Tagg:BAAANQADCggICAAAAA==.Taotao:BAABNQAECn8kAAQYAAgKBAaxcwAvAQAYAAgKBAaxcwAvAQAEAAgK0QLolwDyAAAdAAEKAACkPQAAAAAAAA==.Tarixx:BAABNQAECn8WAAMSAAgKlB1lfADUAQASAAgKKBplfADUAQARAAYKVyB1JQC0AQAAAA==.Tazanoth:BAABNQAECn83AAQFAAoKBBwdYgBSAgAFAAoKwxodYgBSAgAnAAgK6BskBgBDAgAmAAYKPQo+RwAiAQAAAA==.',
Te='Tekeela:BAABNQAECn8wAAIFAAoK7yEnEwAAAwAFAAoK7yEnEwAAAwABNQAFFAUIDQAFAH8eAA==.Tekeelà:BAACNQAFFH8NAAIFAAUKfx5SEgD3AAAFAAUKfx5SEgD3AAA1AAQKf0QAAgUACgriItgOAGsDAAUACgriItgOAGsDAAAA.Terzo:BAAANQABCgQIBgAAAA==.',
Th='Thalarus:BAAANQADCgYICgABNQADCgcICgAIAAAAAA==.Thalion:BAAANQAECgYICwAAAA==.Theenna:BAAANQADCgEIAQAAAA==.Theroux:BAAANQADCggIEAAAAA==.Thess:BAAANQADCgYIBgAAAA==.Thianna:BAABNQAECn8cAAMUAAkKEg4deQBKAQAUAAkKEg4deQBKAQASAAEKewYquwEqAAAAAA==.Thobu:BAAANQAECgUIBgAAAA==.Thornscale:BAABNQAECn8jAAQjAAoKeAl3DgBfAQAkAAkK+weoHQB0AQAjAAgKEwl3DgBfAQAcAAEKJQIMUwAmAAAAAA==.',
Ti='Tielee:BAAANQAECgUIBQAAAA==.Tigolcrittys:BAAANQADCggIEQABNQAECgoKKAAFADkbAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgYICgAAAA==.Tonguepunch:BAABNQAECn8XAAIEAAoKCRgxNQBGAgAEAAoKCRgxNQBGAgAAAA==.Totem:BAAANQAECgUICgAAAA==.Tovê:BAABNQAECn8kAAMEAAoKChdNJwCPAgAEAAoKChdNJwCPAgAYAAUKAwuaxwADAQAAAA==.',
Tr='Traumajazz:BAAANQABCgIIAgAAAA==.Traveler:BAAANQADCgEIAQAAAA==.Trenko:BAAANQADCgMIAwAAAA==.Troloq:BAABNQAECn8dAAMZAAgKzCCABADhAgAZAAgKzCCABADhAgAhAAMKQBLkGQC3AAAAAA==.Trxcy:BAAANQAECgQICAAAAA==.',
Tu='Turger:BAAANQAECgEIAQABNQAECggIHQAEAAUdAA==.',
Va='Vaeluptuous:BAABNQAECn8lAAIeAAcKQBHSkAA5AQAeAAcKQBHSkAA5AQAAAA==.Vahlorraa:BAAANQADCgMJAwAAAA==.Vaimei:BAABNQAECn8rAAMZAAoKwSC2BADaAgAZAAgKSh62BADaAgAeAAkKbBvlYQAzAgAAAA==.Valacicra:BAAANQADCgQIBgAAAA==.Valdreu:BAAANQADCgUIBQAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Vapor:BAABNQAECn8dAAIDAAoKtQ2ZGQBYAQADAAoKtQ2ZGQBYAQAAAA==.Varaine:BAAANQAECgUIBQABNQAECggIIwAVAKAQAA==.',
Ve='Veebs:BAAANQAECgYIBQAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQAECgYIDwAAAA==.',
Vi='Virauca:BAABNQAECn9OAAIiAAoKCRdcEwAsAgAiAAoKCRdcEwAsAgAAAA==.Vizon:BAAANQADCggIGAAAAA==.',
Vo='Voices:BAAANQAECgYIEwAAAA==.Voltrix:BAAANQADCggIGwAAAA==.',
Vy='Vynesta:BAABNQAECn8jAAIVAAgKMR2PIQCPAgAVAAgKMR2PIQCPAgAAAA==.',
Wa='Wanagi:BAABNQAECn8aAAISAAYKugMyRgGHAAASAAYKugMyRgGHAAAAAA==.Wankz:BAAANQAECgUIDAAAAA==.Warkaestey:BAABNQAECn8sAAIMAAoKlwzyeQCXAQAMAAoKlwzyeQCXAQAAAA==.Warriorguyes:BAABNQAECn8lAAIMAAoKlxyvPQBLAgAMAAoKlxyvPQBLAgAAAA==.',
Wh='Whomper:BAAANQAECgQICAAAAA==.',
Wi='Wickedshadow:BAAANQADCgIIAgAAAA==.Widowx:BAABNQAECn8mAAIYAAoKlxE9OgDrAQAYAAoKlxE9OgDrAQAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.Wintervalor:BAABNQAECn9LAAIOAAkK+REoMACNAQAOAAkK+REoMACNAQAAAA==.',
Wo='Womphunt:BAABNQAECn8wAAIFAAoK0BlvPABfAgAFAAoK0BlvPABfAgAAAA==.',
Wu='Wulyn:BAAANQAECgUIEgAAAA==.',
Wy='Wylla:BAABNQAECn8hAAIbAAYKZwyRRAD2AAAbAAYKZwyRRAD2AAAAAA==.',
Xa='Xalethra:BAAANQAECgQIBQAAAA==.',
Xe='Xenophobias:BAABNQAECn8mAAIOAAoKiAxfMgCCAQAOAAoKiAxfMgCCAQAAAA==.',
Xs='Xsuns:BAABNQAECn9BAAIGAAoKixgIGQBLAgAGAAoKixgIGQBLAgAAAA==.',
Yv='Yve:BAAANQAECgMIBQAAAA==.',
Za='Zabberz:BAAANQAECgMIBAAAAA==.Zaharian:BAAANQADCgYJBgAAAA==.Zalajin:BAABNQAECn8cAAIdAAgKLAjrHgA0AQAdAAgKLAjrHgA0AQAAAA==.Zarathiel:BAABNQAECn8fAAIMAAoKew1EnwDOAQAMAAoKew1EnwDOAQAAAA==.',
Ze='Zeddicus:BAABNQAECn8+AAMhAAkKWAdFDwBbAQAhAAkKCwdFDwBbAQAeAAcKHQRrtwDkAAAAAA==.',
Zi='Zivadaavid:BAAANQADCgEIAQAAAA==.',
Zo='Zoidz:BAAANQAECgQIBAAAAA==.Zoriadon:BAAANQADCgcIDAAAAA==.',
Zz='Zzilladinzz:BAAANQAECggIDAAAAA==.',
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
